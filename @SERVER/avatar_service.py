import os
import json
import time
import shutil
from typing import Dict, List, Any, Optional, Tuple
from config import SERVER_PUBLIC_IP

ACCESSORIES_FILE = os.path.join("server_data", "accessories.dat")
ACCESSORIES_DIR = "accessories"
MODELS_DIR = "models"

accessoriesDict = {}
nextAccessoryId = 1

def loadAccessoriesData():
    global accessoriesDict, nextAccessoryId
    try:
        if os.path.exists(ACCESSORIES_FILE):
            with open(ACCESSORIES_FILE, "r") as f:
                data = json.load(f)
                accessoriesDict = data.get("accessories", {})
                nextAccessoryId = data.get("nextId", 1)
        else:
            accessoriesDict = {}
            nextAccessoryId = 1
    except:
        accessoriesDict = {}
        nextAccessoryId = 1

def saveAccessoriesData():
    try:
        os.makedirs("server_data", exist_ok=True)
        data = {
            "accessories": accessoriesDict,
            "nextId": nextAccessoryId
        }
        with open(ACCESSORIES_FILE, "w") as f:
            json.dump(data, f)
    except Exception as e:
        print(f"Error saving accessories data: {e}")

def getFullAvatar(userId: int) -> Dict[str, Any]:
    from player_data import getPlayerData

    playerData = getPlayerData(userId)
    if not playerData:
        return {
            "bodyColors": {
                "head": "#FFCC99",
                "torso": "#0066CC",
                "left_leg": "#00AA00",
                "right_leg": "#00AA00",
                "left_arm": "#FFCC99",
                "right_arm": "#FFCC99"
            },
            "accessories": []
        }

    avatar = playerData.get("avatar", {})
    return {
        "bodyColors": avatar.get("bodyColors", {
            "head": "#FFCC99",
            "torso": "#0066CC",
            "left_leg": "#00AA00",
            "right_leg": "#00AA00",
            "left_arm": "#FFCC99",
            "right_arm": "#FFCC99"
        }),
        "accessories": avatar.get("accessories", [])
    }

def getAccessory(accessoryId: int) -> Optional[Dict[str, Any]]:
    accessoryKey = str(accessoryId)
    if accessoryKey not in accessoriesDict:
        return None

    accessory = accessoriesDict[accessoryKey].copy()
    modelFile = accessory.get("modelFile", "")
    if modelFile:
        modelFileUrl = modelFile.replace("\\", "/")
        accessory["downloadUrl"] = f"http://{SERVER_PUBLIC_IP}:{os.environ.get('PORT', 8080)}/{modelFileUrl}"

    return accessory

def checkItemOwnership(userId: int, itemId: int) -> bool:
    from player_data import getPlayerData

    playerData = getPlayerData(userId)
    if not playerData:
        return False

    ownedAccessories = playerData.get("ownedAccessories", [])
    return itemId in ownedAccessories

def buyItem(userId: int, itemId: int) -> Dict[str, Any]:
    from currency_system import debitCurrency
    from player_data import getPlayerData, savePlayerData

    if checkItemOwnership(userId, itemId):
        return {"success": False, "error": {"code": "ALREADY_OWNED", "message": "Item already owned"}}

    accessory = getAccessory(itemId)
    if not accessory:
        return {"success": False, "error": {"code": "ITEM_NOT_FOUND", "message": "Item not found"}}

    price = accessory.get("price", 0)
    debitResult = debitCurrency(userId, price)
    if not debitResult["success"]:
        return debitResult

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    if "ownedAccessories" not in playerData:
        playerData["ownedAccessories"] = []

    playerData["ownedAccessories"].append(itemId)
    savePlayerData(userId, playerData)

    return {"success": True, "data": {"itemId": itemId, "price": price}}

def equipAccessory(userId: int, accessoryId: int) -> Dict[str, Any]:
    from player_data import getPlayerData, savePlayerData
    from pfp_service import updateUserPfp

    if not checkItemOwnership(userId, accessoryId):
        return {"success": False, "error": {"code": "NOT_OWNED", "message": "Accessory not owned"}}

    accessory = getAccessory(accessoryId)
    if not accessory:
        return {"success": False, "error": {"code": "ITEM_NOT_FOUND", "message": "Accessory not found"}}

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    if "avatar" not in playerData:
        playerData["avatar"] = {"bodyColors": {}, "accessories": []}

    currentAccessories = playerData["avatar"].get("accessories", [])

    equipSlot = accessory.get("equipSlot", accessory.get("type"))

    newAccessories = [acc for acc in currentAccessories if acc.get("equipSlot", acc.get("type")) != equipSlot]

    newAccessories.append({
        "id": accessoryId,
        "type": accessory.get("type"),
        "equipSlot": equipSlot,
        "modelFile": accessory.get("modelFile"),
        "downloadUrl": accessory.get("downloadUrl")
    })

    playerData["avatar"]["accessories"] = newAccessories
    savePlayerData(userId, playerData)

    try:
        updateUserPfp(userId)
    except:
        pass

    return {"success": True, "data": {"equippedAccessory": accessoryId, "slot": equipSlot}}

def unequipAccessory(userId: int, accessoryId: int) -> Dict[str, Any]:
    from player_data import getPlayerData, savePlayerData
    from pfp_service import updateUserPfp

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    currentAccessories = playerData.get("avatar", {}).get("accessories", [])

    newAccessories = [acc for acc in currentAccessories if acc.get("id") != accessoryId]

    if len(newAccessories) == len(currentAccessories):
        return {"success": False, "error": {"code": "NOT_EQUIPPED", "message": "Accessory not currently equipped"}}

    playerData["avatar"]["accessories"] = newAccessories
    savePlayerData(userId, playerData)

    try:
        updateUserPfp(userId)
    except:
        pass

    return {"success": True, "data": {"unequippedAccessory": accessoryId}}

def listMarketItems(filter: Optional[Dict] = None, pagination: Optional[Dict] = None) -> Dict[str, Any]:
    items = []
    for accessoryId, accessory in accessoriesDict.items():
        item = accessory.copy()
        item["id"] = int(accessoryId)

        if filter:
            itemType = filter.get("type")
            if itemType and item.get("type") != itemType:
                continue

            maxPrice = filter.get("maxPrice")
            if maxPrice and item.get("price", 0) > maxPrice:
                continue

        items.append(item)

    items.sort(key=lambda x: (x.get("name", ""), x.get("id", 0)))

    totalItems = len(items)

    if pagination:
        page = pagination.get("page", 1)
        limit = pagination.get("limit", 20)
        start = (page - 1) * limit
        end = start + limit
        items = items[start:end]

    return {
        "success": True,
        "data": {
            "items": items,
            "total": totalItems,
            "page": pagination.get("page", 1) if pagination else 1,
            "limit": pagination.get("limit", 20) if pagination else len(items)
        }
    }

def getUserAccessories(userId: int) -> List[int]:
    from player_data import getPlayerData

    playerData = getPlayerData(userId)
    if not playerData:
        return []

    return playerData.get("ownedAccessories", [])

def addAccessoryFromFolder(path: str) -> Dict[str, Any]:
    global nextAccessoryId

    if not os.path.exists(path):
        return {"success": False, "error": {"code": "PATH_NOT_FOUND", "message": "Folder path not found"}}

    successfulIds = []
    errors = []

    for folderName in os.listdir(path):
        folderPath = os.path.join(path, folderName)
        if not os.path.isdir(folderPath):
            continue

        metadataPath = os.path.join(folderPath, "metadata.json")
        if not os.path.exists(metadataPath):
            errors.append({"folder": folderName, "error": "metadata.json not found"})
            continue

        try:
            with open(metadataPath, "r") as f:
                metadata = json.load(f)

            requiredFields = ["name", "type", "price"]
            if not all(field in metadata for field in requiredFields):
                errors.append({"folder": folderName, "error": "Missing required metadata fields"})
                continue

            modelFiles = [f for f in os.listdir(folderPath) if f.endswith((".glb", ".gltf", ".obj", ".fbx"))]
            if not modelFiles:
                errors.append({"folder": folderName, "error": "No model files found"})
                continue

            modelFile = modelFiles[0]
            accessoryId = nextAccessoryId
            nextAccessoryId += 1

            os.makedirs(MODELS_DIR, exist_ok=True)
            destModelPath = os.path.join(MODELS_DIR, f"{accessoryId}_{modelFile}")
            shutil.copy2(os.path.join(folderPath, modelFile), destModelPath)

            destModelPathUrl = destModelPath.replace("\\", "/")

            accessory = {
                "id": accessoryId,
                "name": metadata["name"],
                "type": metadata["type"],
                "price": metadata["price"],
                "modelFile": destModelPathUrl,
                "downloadUrl": f"http://{SERVER_PUBLIC_IP}:{os.environ.get('PORT', 8080)}/{destModelPathUrl}",
                "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            }

            if "equipSlot" in metadata:
                accessory["equipSlot"] = metadata["equipSlot"]

            accessoriesDict[str(accessoryId)] = accessory
            successfulIds.append(accessoryId)

        except Exception as e:
            errors.append({"folder": folderName, "error": str(e)})

    saveAccessoriesData()
    return {"success": True, "data": {"addedIds": successfulIds, "errors": errors}}

def autoLoadAccessories(): 
    if not os.path.exists(ACCESSORIES_DIR):
        print(f"Accessories directory '{ACCESSORIES_DIR}' not found. Skipping auto-load.")
        return

    if len(accessoriesDict) == 0:
        print(f"Auto-loading accessories from '{ACCESSORIES_DIR}'...")
        result = addAccessoryFromFolder(ACCESSORIES_DIR)

        if result["success"]:
            addedCount = len(result["data"]["addedIds"])
            errorCount = len(result["data"]["errors"])
            print(f"✓ Loaded {addedCount} accessories")

            if errorCount > 0:
                print(f"⚠ {errorCount} folders had errors:")
                for error in result["data"]["errors"]:
                    print(f"  - {error['folder']}: {error['error']}")
        else:
            print(f"✗ Failed to load accessories: {result.get('error', {}).get('message', 'Unknown error')}")
    else:
        print(f"Found {len(accessoriesDict)} existing accessories in database")

loadAccessoriesData()
autoLoadAccessories()
