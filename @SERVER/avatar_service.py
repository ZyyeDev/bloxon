import os
import json
import time
import shutil
from typing import Dict, List, Any, Optional
from config import SERVER_PUBLIC_IP
from database_manager import execute_query, save_accessory_purchase

ACCESSORIES_DIR = "accessories"
MODELS_DIR = "models"
ICONS_DIR = "icons"

def loadAccessoriesData():
    pass

def saveAccessoriesData():
    pass

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
    result = execute_query(
        "SELECT accessory_id, name, type, price, model_file, texture_file, mtl_file, equip_slot, icon_file, created_at FROM accessories WHERE accessory_id = ?",
        (accessoryId,), fetch_one=True
    )

    if not result:
        return None

    port = os.environ.get('PORT', 8080)
    accessory = {
        "id": result[0],
        "name": result[1],
        "type": result[2],
        "price": result[3],
        "modelFile": result[4],
        "textureFile": result[5],
        "mtlFile": result[6],
        "equipSlot": result[7],
        "iconFile": result[8],
        "createdAt": result[9]
    }

    if accessory["modelFile"]:
        modelFileUrl = accessory["modelFile"].replace("\\", "/")
        accessory["downloadUrl"] = f"http://{SERVER_PUBLIC_IP}:{port}/{modelFileUrl}"

    if accessory["textureFile"]:
        textureFileUrl = accessory["textureFile"].replace("\\", "/")
        accessory["textureUrl"] = f"http://{SERVER_PUBLIC_IP}:{port}/{textureFileUrl}"

    if accessory["mtlFile"]:
        mtlFileUrl = accessory["mtlFile"].replace("\\", "/")
        accessory["mtlUrl"] = f"http://{SERVER_PUBLIC_IP}:{port}/{mtlFileUrl}"

    if accessory["iconFile"]:
        iconFileUrl = accessory["iconFile"].replace("\\", "/")
        accessory["iconUrl"] = f"http://{SERVER_PUBLIC_IP}:{port}/{iconFileUrl}"

    return accessory

def checkItemOwnership(userId: int, itemId: int) -> bool:
    result = execute_query(
        "SELECT owned_accessories FROM player_data WHERE user_id = ?",
        (userId,), fetch_one=True
    )

    if not result or not result[0]:
        return False

    owned_accessories = json.loads(result[0])
    return itemId in owned_accessories

def buyItem(userId: int, itemId: int) -> Dict[str, Any]:
    from currency_system import debitCurrency
    from player_data import getPlayerData, savePlayerData

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    if "ownedAccessories" not in playerData:
        playerData["ownedAccessories"] = []

    if itemId in playerData["ownedAccessories"]:
        return {"success": False, "error": {"code": "ALREADY_OWNED", "message": "Item already owned"}}

    accessory = getAccessory(itemId)
    if not accessory:
        return {"success": False, "error": {"code": "ITEM_NOT_FOUND", "message": "Item not found"}}

    price = accessory.get("price", 0)
    debitResult = debitCurrency(userId, price)
    if not debitResult["success"]:
        return debitResult

    playerData["ownedAccessories"].append(itemId)
    savePlayerData(userId, playerData)

    result = execute_query(
        "UPDATE player_data SET owned_accessories = ? WHERE user_id = ?",
        (json.dumps(playerData["ownedAccessories"]), userId)
    )

    save_accessory_purchase(userId, itemId, price)

    return {"success": True, "data": {"itemId": itemId, "price": price, "newBalance": debitResult["data"]["newBalance"]}}

def equipAccessory(userId: int, accessoryId: int) -> Dict[str, Any]:
    from player_data import getPlayerData, savePlayerData

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
        "textureFile": accessory.get("textureFile"),
        "mtlFile": accessory.get("mtlFile"),
        "downloadUrl": accessory.get("downloadUrl"),
        "textureUrl": accessory.get("textureUrl"),
        "mtlUrl": accessory.get("mtlUrl")
    })

    playerData["avatar"]["accessories"] = newAccessories
    savePlayerData(userId, playerData)

    return {"success": True, "data": {"equippedAccessory": accessoryId, "slot": equipSlot}}

def unequipAccessory(userId: int, accessoryId: int) -> Dict[str, Any]:
    from player_data import getPlayerData, savePlayerData

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    currentAccessories = playerData.get("avatar", {}).get("accessories", [])

    newAccessories = [acc for acc in currentAccessories if acc.get("id") != accessoryId]

    if len(newAccessories) == len(currentAccessories):
        return {"success": False, "error": {"code": "NOT_EQUIPPED", "message": "Accessory not currently equipped"}}

    playerData["avatar"]["accessories"] = newAccessories
    savePlayerData(userId, playerData)

    return {"success": True, "data": {"unequippedAccessory": accessoryId}}

def listMarketItems(filter: Optional[Dict] = None, pagination: Optional[Dict] = None) -> Dict[str, Any]:
    query = "SELECT accessory_id, name, type, price, model_file, texture_file, mtl_file, equip_slot, icon_file, created_at FROM accessories"
    params = []

    if filter:
        conditions = []
        if filter.get("type"):
            conditions.append("type = ?")
            params.append(filter["type"])
        if filter.get("maxPrice"):
            conditions.append("price <= ?")
            params.append(filter["maxPrice"])

        if conditions:
            query += " WHERE " + " AND ".join(conditions)

    query += " ORDER BY name, accessory_id"

    results = execute_query(query, tuple(params), fetch_all=True)

    items = []
    port = os.environ.get('PORT', 8080)

    for row in results:
        item = {
            "id": row[0],
            "name": row[1],
            "type": row[2],
            "price": row[3],
            "modelFile": row[4],
            "textureFile": row[5],
            "mtlFile": row[6],
            "equipSlot": row[7],
            "iconFile": row[8],
            "createdAt": row[9]
        }

        if item["modelFile"]:
            modelFileUrl = item["modelFile"].replace("\\", "/")
            item["downloadUrl"] = f"http://{SERVER_PUBLIC_IP}:{port}/{modelFileUrl}"

        if item["textureFile"]:
            textureFileUrl = item["textureFile"].replace("\\", "/")
            item["textureUrl"] = f"http://{SERVER_PUBLIC_IP}:{port}/{textureFileUrl}"

        if item["mtlFile"]:
            mtlFileUrl = item["mtlFile"].replace("\\", "/")
            item["mtlUrl"] = f"http://{SERVER_PUBLIC_IP}:{port}/{mtlFileUrl}"

        if item["iconFile"]:
            iconFileUrl = item["iconFile"].replace("\\", "/")
            item["iconUrl"] = f"http://{SERVER_PUBLIC_IP}:{port}/{iconFileUrl}"

        items.append(item)

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
    result = execute_query(
        "SELECT owned_accessories FROM player_data WHERE user_id = ?",
        (userId,), fetch_one=True
    )

    if not result or not result[0]:
        return []

    return json.loads(result[0])

def deleteAccessory(accessoryId: int) -> Dict[str, Any]:
    result = execute_query(
        "SELECT model_file, texture_file, mtl_file, icon_file FROM accessories WHERE accessory_id = ?",
        (accessoryId,), fetch_one=True
    )

    if not result:
        return {"success": False, "error": "Accessory not found"}

    files_to_delete = [result[0], result[1], result[2], result[3]]

    for file_path in files_to_delete:
        if file_path:
            full_path = file_path
            if os.path.exists(full_path):
                try:
                    os.remove(full_path)
                except:
                    pass

    execute_query("DELETE FROM accessories WHERE accessory_id = ?", (accessoryId,))
    execute_query("DELETE FROM accessory_purchases WHERE accessory_id = ?", (accessoryId,))

    return {"success": True, "data": {"deletedId": accessoryId}}

def addAccessoryFromDashboard(name: str, accessory_type: str, price: int, equip_slot: str,
                              model_data: bytes, texture_data: Optional[bytes] = None,
                              mtl_data: Optional[bytes] = None, icon_data: Optional[bytes] = None,
                              model_filename: str = None) -> Dict[str, Any]:
    os.makedirs(MODELS_DIR, exist_ok=True)
    os.makedirs(ICONS_DIR, exist_ok=True)

    try:
        accessory_id = execute_query(
            """INSERT INTO accessories (name, type, price, model_file, texture_file, mtl_file, equip_slot, icon_file, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (name, accessory_type, price, "", "", "", equip_slot, "", time.time())
        )

        if not model_filename:
            model_filename = f"{accessory_id}_model.glb"
        else:
            name_part, ext = os.path.splitext(model_filename)
            model_filename = f"{accessory_id}_model{ext}"

        model_path = os.path.join(MODELS_DIR, model_filename)

        with open(model_path, 'wb') as f:
            f.write(model_data)

        model_path_url = model_path.replace("\\", "/")

        texture_path_url = None
        if texture_data:
            texture_filename = f"{accessory_id}_texture.png"
            texture_path = os.path.join(MODELS_DIR, texture_filename)
            with open(texture_path, 'wb') as f:
                f.write(texture_data)
            texture_path_url = texture_path.replace("\\", "/")

        mtl_path_url = None
        if mtl_data:
            mtl_filename = f"{accessory_id}_material.mtl"
            mtl_path = os.path.join(MODELS_DIR, mtl_filename)
            with open(mtl_path, 'wb') as f:
                f.write(mtl_data)
            mtl_path_url = mtl_path.replace("\\", "/")

        icon_path_url = None
        if icon_data:
            icon_filename = f"{accessory_id}_icon.png"
            icon_path = os.path.join(ICONS_DIR, icon_filename)
            with open(icon_path, 'wb') as f:
                f.write(icon_data)
            icon_path_url = icon_path.replace("\\", "/")

        execute_query(
            "UPDATE accessories SET model_file = ?, texture_file = ?, mtl_file = ?, icon_file = ? WHERE accessory_id = ?",
            (model_path_url, texture_path_url, mtl_path_url, icon_path_url, accessory_id)
        )

        return {"success": True, "data": {"accessoryId": accessory_id, "name": name}}

    except Exception as e:
        return {"success": False, "error": str(e)}

def autoLoadAccessories():
    if not os.path.exists(ACCESSORIES_DIR):
        print(f"Accessories directory '{ACCESSORIES_DIR}' not found. Skipping auto-load.")
        return

    existing_count = execute_query("SELECT COUNT(*) FROM accessories", fetch_one=True)[0]

    if existing_count == 0:
        print(f"Auto-loading accessories from '{ACCESSORIES_DIR}'...")
        successfulIds = []
        errors = []

        for folderName in os.listdir(ACCESSORIES_DIR):
            folderPath = os.path.join(ACCESSORIES_DIR, folderName)
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

                mtlFile = None
                if modelFile.endswith(".obj"):
                    mtlFiles = [f for f in os.listdir(folderPath) if f.endswith(".mtl")]
                    mtlFile = mtlFiles[0] if mtlFiles else None

                textureFiles = [f for f in os.listdir(folderPath) if f.endswith((".png", ".jpg", ".jpeg"))]
                textureFile = textureFiles[0] if textureFiles else None

                os.makedirs(MODELS_DIR, exist_ok=True)

                folder_created_time = os.path.getctime(folderPath)

                accessory_id = execute_query(
                    """INSERT INTO accessories (name, type, price, model_file, texture_file, equip_slot, icon_file, created_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (metadata["name"], metadata["type"], metadata["price"], "", "",
                     metadata.get("equipSlot", metadata["type"]), "", folder_created_time)
                )

                print(f"Created accessory {accessory_id} for {folderName}")

                srcModelPath = os.path.join(folderPath, modelFile)
                destModelFile = f"{accessory_id}_{modelFile}"
                destModelPath = os.path.join(MODELS_DIR, destModelFile)

                shutil.copy2(srcModelPath, destModelPath)
                print(f"  Copied model: {srcModelPath} -> {destModelPath}")

                if not os.path.exists(destModelPath):
                    raise Exception(f"Model file was not copied successfully: {destModelPath}")

                destModelPathUrl = destModelPath.replace("\\", "/")

                if mtlFile:
                    srcMtlPath = os.path.join(folderPath, mtlFile)
                    destMtlFile = f"{accessory_id}_{mtlFile}"
                    destMtlPath = os.path.join(MODELS_DIR, destMtlFile)

                    try:
                        with open(srcMtlPath, 'r', encoding='utf-8', errors='ignore') as f:
                            mtlContent = f.read()

                        if textureFile:
                            newTextureName = f"{accessory_id}_{textureFile}"
                            for mapType in ['map_Kd', 'map_Ka', 'map_Ks', 'map_Bump', 'map_d', 'bump']:
                                mtlContent = mtlContent.replace(f"{mapType} {textureFile}", f"{mapType} {newTextureName}")
                            mtlContent = mtlContent.replace(textureFile, newTextureName)

                        with open(destMtlPath, 'w', encoding='utf-8') as f:
                            f.write(mtlContent)

                        print(f"  Copied MTL: {srcMtlPath} -> {destMtlPath}")

                        try:
                            with open(destModelPath, 'r', encoding='utf-8', errors='ignore') as f:
                                objContent = f.read()

                            objContent = objContent.replace(f"mtllib {mtlFile}", f"mtllib {destMtlFile}")

                            with open(destModelPath, 'w', encoding='utf-8') as f:
                                f.write(objContent)

                            print(f"  Updated OBJ mtllib reference")
                        except Exception as e:
                            print(f"  Warning: Could not update OBJ mtllib reference: {e}")

                    except Exception as e:
                        print(f"  Warning: Error processing MTL file: {e}")

                destTexturePath = None
                if textureFile:
                    srcTexturePath = os.path.join(folderPath, textureFile)
                    destTextureFile = f"{accessory_id}_{textureFile}"
                    destTexturePath = os.path.join(MODELS_DIR, destTextureFile)

                    shutil.copy2(srcTexturePath, destTexturePath)
                    print(f"  Copied texture: {srcTexturePath} -> {destTexturePath}")

                    if not os.path.exists(destTexturePath):
                        print(f"  Warning: Texture file was not copied successfully")

                    destTexturePath = destTexturePath.replace("\\", "/")

                execute_query(
                    "UPDATE accessories SET model_file = ?, texture_file = ? WHERE accessory_id = ?",
                    (destModelPathUrl, destTexturePath, accessory_id)
                )

                print(f"  Successfully added accessory {accessory_id}: {metadata['name']}")
                successfulIds.append(accessory_id)

            except Exception as e:
                import traceback
                error_msg = f"{str(e)}\n{traceback.format_exc()}"
                print(f"  Error processing {folderName}: {error_msg}")
                errors.append({"folder": folderName, "error": str(e)})

        addedCount = len(successfulIds)
        errorCount = len(errors)
        print(f"Loaded {addedCount} accessories")

        if errorCount > 0:
            print(f"Warning: {errorCount} folders had errors:")
            for error in errors:
                print(f"  - {error['folder']}: {error['error']}")
    else:
        print(f"Found {existing_count} existing accessories in database")

autoLoadAccessories()
