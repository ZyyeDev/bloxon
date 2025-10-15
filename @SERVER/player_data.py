import os
import json
import time
from typing import Dict, Any, Optional
from config import SERVER_PUBLIC_IP
from database_manager import execute_query

PLAYER_DATA_FILE = os.path.join("server_data", "player_data.dat")

playerDataDict = {}

DEFAULT_PLAYER_SCHEMA = {
    "schemaVersion": 1,
    "currency": 100,
    "friends": [],
    "ownedAccessories": [],
    "avatar": {
        "bodyColors": {
            "head": "#FFCCAA",
            "torso": "#00FF00",
            "left_leg": "#0000FF",
            "right_leg": "#0000FF",
            "left_arm": "#0000FF",
            "right_arm": "#0000FF"
        },
        "accessories": []
    },
    "pfp": f"http://{SERVER_PUBLIC_IP}:{os.environ.get('PORT', 8080)}/pfps/default.png",
    "serverId": None
}

def loadPlayerData():
    global playerDataDict
    try:
        if os.path.exists(PLAYER_DATA_FILE):
            with open(PLAYER_DATA_FILE, "r") as f:
                playerDataDict = json.load(f)
        else:
            playerDataDict = {}
    except:
        playerDataDict = {}

def savePlayerDataDict():
    try:
        os.makedirs("server_data", exist_ok=True)
        with open(PLAYER_DATA_FILE, "w") as f:
            json.dump(playerDataDict, f)
    except Exception as e:
        print(f"Error saving player data: {e}")

def ensurePlayerDataDefaults(playerData: Dict[str, Any]) -> Dict[str, Any]:
    result = playerData.copy()

    def applyDefaults(data: Dict[str, Any], defaults: Dict[str, Any]) -> Dict[str, Any]:
        for key, defaultValue in defaults.items():
            if key not in data:
                if isinstance(defaultValue, dict):
                    data[key] = {}
                    applyDefaults(data[key], defaultValue)
                else:
                    data[key] = defaultValue
            elif isinstance(defaultValue, dict) and isinstance(data[key], dict):
                applyDefaults(data[key], defaultValue)
        return data

    result = applyDefaults(result, DEFAULT_PLAYER_SCHEMA)

    if result.get("schemaVersion", 0) < DEFAULT_PLAYER_SCHEMA["schemaVersion"]:
        result["schemaVersion"] = DEFAULT_PLAYER_SCHEMA["schemaVersion"]

    return result

def getPlayerData(userId: int) -> Optional[Dict[str, Any]]:
    userKey = str(userId)
    if userKey in playerDataDict:
        data = ensurePlayerDataDefaults(playerDataDict[userKey])

        db_result = execute_query(
            "SELECT owned_accessories FROM player_data WHERE user_id = ?",
            (userId,), fetch_one=True
        )

        if db_result and db_result[0]:
            try:
                data["ownedAccessories"] = json.loads(db_result[0])
            except:
                data["ownedAccessories"] = []

        return data

    db_result = execute_query(
        "SELECT username, currency, avatar_data, owned_accessories, pfp, server_id FROM player_data WHERE user_id = ?",
        (userId,), fetch_one=True
    )

    if db_result:
        data = DEFAULT_PLAYER_SCHEMA.copy()
        data["username"] = db_result[0]
        data["userId"] = userId
        data["currency"] = db_result[1]

        if db_result[2]:
            try:
                data["avatar"] = json.loads(db_result[2])
            except:
                pass

        if db_result[3]:
            try:
                data["ownedAccessories"] = json.loads(db_result[3])
            except:
                data["ownedAccessories"] = []

        if db_result[4]:
            data["pfp"] = db_result[4]

        if db_result[5]:
            data["serverId"] = db_result[5]

        playerDataDict[userKey] = data
        return ensurePlayerDataDefaults(data)

    return None

def savePlayerData(userId: int, data: Dict[str, Any]):
    userKey = str(userId)
    data = ensurePlayerDataDefaults(data)
    playerDataDict[userKey] = data

    avatar_json = json.dumps(data.get("avatar", {}))
    owned_accessories_json = json.dumps(data.get("ownedAccessories", []))

    execute_query(
        """INSERT OR REPLACE INTO player_data
           (user_id, username, currency, avatar_data, owned_accessories, pfp, server_id, schema_version)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (userId, data.get("username", ""), data.get("currency", 100),
         avatar_json, owned_accessories_json, data.get("pfp", ""),
         data.get("serverId"), data.get("schemaVersion", 1))
    )

    savePlayerDataDict()

def createPlayerData(userId: int, username: str) -> Dict[str, Any]:
    from friends import getFriends

    playerData = DEFAULT_PLAYER_SCHEMA.copy()
    playerData["username"] = username
    playerData["userId"] = userId
    playerData["friends"] = getFriends(userId)

    savePlayerData(userId, playerData)
    return playerData

def updatePlayerAvatar(userId: int, avatarData: Dict[str, Any]) -> Dict[str, Any]:
    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    playerData["avatar"] = avatarData
    savePlayerData(userId, playerData)

    return {"success": True, "data": playerData}

def setPlayerServer(userId: int, serverId: Optional[str]) -> Dict[str, Any]:
    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    playerData["serverId"] = serverId
    savePlayerData(userId, playerData)

    return {"success": True, "data": {"userId": userId, "serverId": serverId}}

def getPlayerFullProfile(userId: int) -> Dict[str, Any]:
    from friends import getFriends
    from avatar_service import getUserAccessories
    from currency_system import getCurrency
    from pfp_service import getPfp

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    profile = playerData.copy()
    profile["friends"] = getFriends(userId)
    profile["ownedAccessories"] = getUserAccessories(userId)

    currencyResult = getCurrency(userId)
    if currencyResult["success"]:
        profile["currency"] = currencyResult["data"]["balance"]

    profile["pfp"] = getPfp(userId)

    return {"success": True, "data": profile}

def resetAllPlayerServers():
    global playerDataDict
    modified = False

    for userId in playerDataDict:
        if playerDataDict[userId].get("serverId") is not None:
            playerDataDict[userId]["serverId"] = None
            modified = True

    if modified:
        savePlayerDataDict()
        print("Reset all player server assignments")

loadPlayerData()
