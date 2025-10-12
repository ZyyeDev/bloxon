import signal
import asyncio
import time
import uuid
import subprocess
import os
import json
import hashlib
import secrets
import hmac
import sqlite3
import threading
from collections import defaultdict, deque
from player_data import setPlayerServer
from datetime import datetime, timedelta
from aiohttp import web
import aiohttp
from cryptography.fernet import Fernet
import base64

import auth_utils
from api_extensions import addNewRoutes
from player_data import createPlayerData, getPlayerFullProfile
from friends import (
    sendFriendRequest, getFriendRequests, acceptFriendRequest,
    rejectFriendRequest, cancelFriendRequest, removeFriend, getFriends, loadFriendsData, saveFriendsData
)
from avatar_service import loadAccessoriesData, saveAccessoriesData
from pfp_service import ensurePfpDirectory
from config import SERVER_PUBLIC_IP, BASE_PORT, GODOT_SERVER_BIN, DATASTORE_PASSWORD
import atexit

shutdown_lock = threading.Lock()
db_lock = threading.RLock()

serverList = {}
playerList = {}
processList = {}
rateLimitDict = defaultdict(deque)
blockedIps = {}
datastoreDict = {}
userAccounts = {}
userTokens = {}
authRateLimitDict = defaultdict(deque)

MAX_SERVERS = 200
maxRequestsPer15Sec = 100
authMaxRequests = 100

DATA_DIR = "server_data"
DB_FILE = os.path.join(DATA_DIR, "server.db")
KEY_FILE = os.path.join(DATA_DIR, "master.key")

nextUserId = 1
last_cleanup = 0

def init_database():
    os.makedirs(DATA_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_FILE, check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA cache_size=10000")

    conn.executescript("""
        CREATE TABLE IF NOT EXISTS accounts (
            username TEXT PRIMARY KEY,
            password TEXT NOT NULL,
            gender TEXT NOT NULL,
            created REAL NOT NULL,
            user_id INTEGER UNIQUE NOT NULL
        );

        CREATE TABLE IF NOT EXISTS tokens (
            token TEXT PRIMARY KEY,
            username TEXT NOT NULL,
            created REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS datastores (
            key TEXT PRIMARY KEY,
            value TEXT,
            timestamp REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS servers (
            uid TEXT PRIMARY KEY,
            ip TEXT NOT NULL,
            port INTEGER NOT NULL,
            max_players INTEGER NOT NULL,
            last_seen REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_tokens_created ON tokens(created);
        CREATE INDEX IF NOT EXISTS idx_datastores_timestamp ON datastores(timestamp);
    """)
    conn.commit()
    return conn

db_conn = init_database()

def emergencyShutdown():
    with shutdown_lock:
        try:
            from player_data import resetAllPlayerServers
            resetAllPlayerServers()
            saveAllData()
        except:
            pass

atexit.register(emergencyShutdown)

def generateMasterKey():
    if not os.path.exists(KEY_FILE):
        key = Fernet.generate_key()
        with open(KEY_FILE, "wb") as f:
            f.write(key)
        os.chmod(KEY_FILE, 0o600)
        return key
    else:
        with open(KEY_FILE, "rb") as f:
            return f.read()

def getEncryptionKey():
    return generateMasterKey()

def encryptData(data):
    fernet = Fernet(getEncryptionKey())
    json_data = json.dumps(data).encode()
    return fernet.encrypt(json_data)

def decryptData(encrypted_data):
    try:
        fernet = Fernet(getEncryptionKey())
        decrypted_data = fernet.decrypt(encrypted_data)
        return json.loads(decrypted_data.decode())
    except:
        return {}

def saveAllData():
    with db_lock:
        try:
            db_conn.execute("BEGIN IMMEDIATE")

            db_conn.execute("DELETE FROM accounts")
            for username, data in userAccounts.items():
                db_conn.execute(
                    "INSERT INTO accounts (username, password, gender, created, user_id) VALUES (?, ?, ?, ?, ?)",
                    (username, data["password"], data["gender"], data["created"], data["user_id"])
                )

            db_conn.execute("DELETE FROM tokens")
            for token, data in auth_utils.userTokens.items():
                db_conn.execute(
                    "INSERT INTO tokens (token, username, created) VALUES (?, ?, ?)",
                    (token, data["username"], data["created"])
                )

            db_conn.execute("DELETE FROM datastores")
            for key, data in datastoreDict.items():
                value = data["value"]
                if isinstance(value, (dict, list)):
                    value = json.dumps(value)
                elif not isinstance(value, str):
                    value = str(value)

                db_conn.execute(
                    "INSERT INTO datastores (key, value, timestamp) VALUES (?, ?, ?)",
                    (key, value, data["timestamp"])
                )

            db_conn.execute("DELETE FROM servers")
            for uid, info in serverList.items():
                db_conn.execute(
                    "INSERT INTO servers (uid, ip, port, max_players, last_seen) VALUES (?, ?, ?, ?, ?)",
                    (uid, info["ip"], info["port"], info["max"], info["last"])
                )

            db_conn.commit()

        except Exception as e:
            db_conn.rollback()
            print(f"Error saving data: {e}")

def loadAllData():
    global userAccounts, datastoreDict, serverList, nextUserId

    with db_lock:
        cursor = db_conn.cursor()

        cursor.execute("SELECT username, password, gender, created, user_id FROM accounts")
        userAccounts = {}
        for row in cursor.fetchall():
            userAccounts[row[0]] = {
                "password": row[1],
                "gender": row[2],
                "created": row[3],
                "user_id": row[4]
            }

        cursor.execute("SELECT token, username, created FROM tokens")
        auth_utils.userTokens = {}
        for row in cursor.fetchall():
            auth_utils.userTokens[row[0]] = {
                "username": row[1],
                "created": row[2]
            }

        cursor.execute("SELECT key, value, timestamp FROM datastores")
        datastoreDict = {}
        for row in cursor.fetchall():
            value = row[1]
            try:
                value = json.loads(value)
            except (json.JSONDecodeError, TypeError):
                pass

            datastoreDict[row[0]] = {
                "value": value,
                "timestamp": row[2]
            }

        cursor.execute("SELECT uid, ip, port, max_players, last_seen FROM servers")
        serverList = {}
        for row in cursor.fetchall():
            serverList[row[0]] = {
                "ip": row[1],
                "port": row[2],
                "players": set(),
                "max": row[3],
                "last": row[4]
            }

    nextUserId = max([acc.get("user_id", 0) for acc in userAccounts.values()], default=0) + 1

    loadFriendsData()
    loadAccessoriesData()
    ensurePfpDirectory()

    from player_data import playerDataDict, savePlayerDataDict
    for userId in playerDataDict:
        if "serverId" in playerDataDict[userId]:
            playerDataDict[userId]["serverId"] = None
    savePlayerDataDict()

def hashPassword(password):
    salt = secrets.token_hex(16)
    password_hash = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000)
    return salt + ":" + base64.b64encode(password_hash).decode()

def verifyPassword(password, stored_hash):
    try:
        salt, hash_part = stored_hash.split(":")
        password_hash = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000)
        return base64.b64encode(password_hash).decode() == hash_part
    except:
        return False

def generateToken():
    return secrets.token_urlsafe(32)

def checkAuthRateLimit(clientIp):
    currentTime = time.time()
    window = authRateLimitDict[clientIp]

    while window and currentTime - window[0] > 60:
        window.popleft()

    if len(window) >= authMaxRequests:
        return False

    window.append(currentTime)
    return True

def validateToken(token):
    return auth_utils.validateToken(token)

def checkRateLimit(clientIp):
    currentTime = time.time()

    if clientIp in blockedIps:
        if currentTime < blockedIps[clientIp]:
            return False
        else:
            del blockedIps[clientIp]

    window = rateLimitDict[clientIp]

    while window and currentTime - window[0] > 15:
        window.popleft()

    if len(window) >= maxRequestsPer15Sec:
        return False

    window.append(currentTime)
    return True

def blockIp(clientIp, duration_minutes):
    blockedIps[clientIp] = time.time() + (duration_minutes * 60)

async def registerUser(httpRequest):
    clientIp = httpRequest.remote
    if not checkAuthRateLimit(clientIp):
        return web.json_response({"error": "auth_rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    username = requestData.get("username", "").strip()
    password = requestData.get("password", "")
    gender = requestData.get("gender", "").lower()

    if not username or not password or gender not in ["male", "female", "none"]:
        return web.json_response({"error": "invalid_data"}, status=400)

    if len(username) < 3 or len(username) > 20:
        return web.json_response({"error": "username_length_invalid"}, status=400)

    if len(password) < 6:
        return web.json_response({"error": "password_too_short"}, status=400)

    if username in userAccounts:
        return web.json_response({"error": "username_taken"}, status=409)

    hashedPassword = hashPassword(password)
    token = generateToken()

    global nextUserId
    userAccounts[username] = {
        "password": hashedPassword,
        "gender": gender,
        "created": time.time(),
        "user_id": nextUserId
    }

    user_id = nextUserId
    nextUserId += 1

    auth_utils.userTokens[token] = {
        "username": username,
        "created": time.time()
    }

    createPlayerData(user_id, username)

    return web.json_response({
        "status": "registered",
        "token": token,
        "username": username,
        "user_id": user_id
    })

async def loginUser(httpRequest):
    clientIp = httpRequest.remote
    if not checkAuthRateLimit(clientIp):
        return web.json_response({"error": "auth_rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    username = requestData.get("username", "").strip()
    password = requestData.get("password", "")

    if not username or not password:
        return web.json_response({"error": "missing_credentials"}, status=400)

    if username not in userAccounts:
        return web.json_response({"error": "user_not_found"}, status=404)

    if not verifyPassword(password, userAccounts[username]["password"]):
        return web.json_response({"error": "invalid_password"}, status=401)

    token = generateToken()
    auth_utils.userTokens[token] = {
        "username": username,
        "created": time.time()
    }

    return web.json_response({
        "status": "logged_in",
        "token": token,
        "username": username,
        "user_id": userAccounts[username]["user_id"]
    })

async def pingServer(ip, port):
    try:
        startTime = time.time()
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(ip, port),
            timeout=1.0
        )
        endTime = time.time()
        writer.close()
        await writer.wait_closed()
        return int((endTime - startTime) * 1000)
    except:
        return -1

async def spawnServer(serverUid, serverPort):
    serverProc = await asyncio.create_subprocess_exec(
        GODOT_SERVER_BIN,
        "--headless",
        f"--uid", f"{serverUid}",
        f"--port", f"{serverPort}",
        f"--master", f"http://{SERVER_PUBLIC_IP}:{BASE_PORT}",
        "--server",
    )
    processList[serverUid] = serverProc
    await asyncio.sleep(2)

async def registerServer(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    serverUid = requestData.get("uid")
    serverPort = requestData["port"]
    maxPlayerCount = requestData.get("max_players", 8)

    if serverUid in serverList:
        serverList[serverUid].update({"ip": SERVER_PUBLIC_IP, "port": serverPort, "max": maxPlayerCount, "last": time.time()})
    else:
        serverList[serverUid] = {"ip": SERVER_PUBLIC_IP, "port": serverPort, "players": set(), "max": maxPlayerCount, "last": time.time()}

    return web.json_response({"uid": serverUid, "ip": SERVER_PUBLIC_IP, "port": serverPort})

async def requestServer(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    token = requestData.get("token")
    if not token or not validateToken(token):
        return web.json_response({"error": "invalid_token"}, status=401)

    playerId = auth_utils.userTokens[token]["username"]
    username = auth_utils.userTokens[token]["username"]
    userId = None
    for uname, userData in userAccounts.items():
        if uname == username:
            userId = userData["user_id"]
            break

    for serverUid, serverInfo in serverList.items():
        if len(serverInfo["players"]) < serverInfo["max"] and not serverInfo.get("starting", False):
            serverInfo["players"].add(playerId)
            playerList[playerId] = {"server": serverUid, "last": time.time()}

            if userId:
                setPlayerServer(userId, serverUid)

            return web.json_response({"uid": serverUid, "ip": serverInfo["ip"], "port": serverInfo["port"]})

    serverUid = str(uuid.uuid4())
    serverPort = BASE_PORT + len(serverList) % MAX_SERVERS
    serverList[serverUid] = {
        "ip": SERVER_PUBLIC_IP,
        "port": serverPort,
        "players": {playerId},
        "max": 6,
        "last": time.time(),
        "starting": True
    }
    playerList[playerId] = {"server": serverUid, "last": time.time()}

    if userId:
        setPlayerServer(userId, serverUid)

    await spawnServer(serverUid, serverPort)

    await asyncio.sleep(3)
    if serverUid in serverList:
        serverList[serverUid]["starting"] = False

    return web.json_response({"uid": serverUid, "ip": SERVER_PUBLIC_IP, "port": serverList[serverUid]["port"]})

async def heartbeatServer(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    token = requestData.get("token")
    if not token or not validateToken(token):
        return web.json_response({"error": "invalid_token"}, status=401)

    serverUid = requestData.get("uid")
    if serverUid in serverList:
        serverList[serverUid]["last"] = time.time()
        return web.json_response({"status": "alive"})
    return web.json_response({"status": "not_found"})

async def heartbeatClient(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    token = requestData.get("token")
    if not token or not validateToken(token):
        return web.json_response({"error": "invalid_token"}, status=401)

    playerId = auth_utils.userTokens[token]["username"]
    if playerId in playerList:
        playerList[playerId]["last"] = time.time()
        return web.json_response({"status": "alive"})
    return web.json_response({"status": "not_found", "error": "player_not_found"})

async def getServerPing(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    token = requestData.get("token")
    if not token or not validateToken(token):
        return web.json_response({"error": "invalid_token"}, status=401)

    serverUid = requestData.get("uid")

    if serverUid not in serverList:
        return web.json_response({"error": "server_not_found"}, status=404)

    serverInfo = serverList[serverUid]
    ping = await pingServer(serverInfo["ip"], serverInfo["port"])

    return web.json_response({
        "uid": serverUid,
        "ip": serverInfo["ip"],
        "port": serverInfo["port"],
        "ping": ping
    })

async def getAllServersPing(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    token = requestData.get("token")
    if not token or not validateToken(token):
        return web.json_response({"error": "invalid_token"}, status=401)

    serversPingData = []

    for serverUid, serverInfo in serverList.items():
        ping = await pingServer(serverInfo["ip"], serverInfo["port"])
        serversPingData.append({
            "uid": serverUid,
            "ip": serverInfo["ip"],
            "port": serverInfo["port"],
            "ping": ping,
            "players": len(serverInfo["players"]),
            "max_players": serverInfo["max"]
        })

    return web.json_response({"servers": serversPingData})

async def setDatastore(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    allowed_ips = ["127.0.0.1", "::1", SERVER_PUBLIC_IP]
    if clientIp not in allowed_ips:
        return web.json_response({"error": "unauthorized_ip"}, status=403)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    key = requestData.get("key")
    value = requestData.get("value")
    accessKey = requestData.get("access_key")

    if not key or not accessKey:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    if accessKey != DATASTORE_PASSWORD:
        return web.json_response({"error": "invalid_access_key"}, status=403)

    datastoreKey = f"server:{key}"
    datastoreDict[datastoreKey] = {
        "value": value,
        "timestamp": time.time()
    }

    return web.json_response({"status": "success", "key": key})

async def getDatastore(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    key = requestData.get("key")
    accessKey = requestData.get("access_key")

    if not key or not accessKey:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    if accessKey != DATASTORE_PASSWORD:
        return web.json_response({"error": "invalid_access_key"}, status=403)

    datastoreKey = f"server:{key}"

    if datastoreKey in datastoreDict:
        return web.json_response({
            "key": key,
            "value": datastoreDict[datastoreKey]["value"],
            "timestamp": datastoreDict[datastoreKey]["timestamp"]
        })

    return web.json_response({"error": "key_not_found"}, status=404)

async def removeDatastore(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    allowed_ips = ["127.0.0.1", "::1", SERVER_PUBLIC_IP]
    if clientIp not in allowed_ips:
        return web.json_response({"error": "unauthorized_ip"}, status=403)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    key = requestData.get("key")
    accessKey = requestData.get("access_key")

    if not key or not accessKey:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    if accessKey != DATASTORE_PASSWORD:
        return web.json_response({"error": "invalid_access_key"}, status=403)

    datastoreKey = f"server:{key}"

    if datastoreKey in datastoreDict:
        del datastoreDict[datastoreKey]
        return web.json_response({"status": "removed", "key": key})

    return web.json_response({"error": "key_not_found"}, status=404)

async def listDatastoreKeys(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    accessKey = requestData.get("access_key")

    if not accessKey:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    if accessKey != DATASTORE_PASSWORD:
        return web.json_response({"error": "invalid_access_key"}, status=403)

    serverKeys = []
    prefix = "server:"

    for datastoreKey in datastoreDict.keys():
        if datastoreKey.startswith(prefix):
            key = datastoreKey[len(prefix):]
            serverKeys.append({
                "key": key,
                "timestamp": datastoreDict[datastoreKey]["timestamp"]
            })

    return web.json_response({"keys": serverKeys})

async def getUserById(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    user_id = requestData.get("user_id")

    if not user_id:
        return web.json_response({"error": "missing_user_id"}, status=400)

    for username, userData in userAccounts.items():
        if userData.get("user_id") == user_id:
            return web.json_response({
                "username": username,
                "user_id": userData["user_id"],
                "gender": userData["gender"],
                "created": userData["created"]
            })

    return web.json_response({"error": "user_not_found"}, status=404)

async def searchUsers(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    search_query = requestData.get("query", "").strip().lower()
    limit = requestData.get("limit", 20)

    if not search_query:
        return web.json_response({"error": "missing_query"}, status=400)

    if limit > 50:
        limit = 50

    matching_users = []
    for username, userData in userAccounts.items():
        if search_query in username.lower():
            matching_users.append({
                "username": username,
                "user_id": userData["user_id"],
                "gender": userData["gender"],
                "created": userData["created"]
            })

    matching_users.sort(key=lambda x: x["username"].lower().find(search_query.lower()))
    return web.json_response({"users": matching_users[:limit]})

async def getDashboardData(httpRequest):
    currentTime = time.time()
    totalServers = len(serverList)
    totalPlayers = len(playerList)
    activeServers = sum(1 for s in serverList.values() if len(s["players"]) > 0)
    totalCapacity = sum(s["max"] for s in serverList.values())

    servers_data = []
    for serverUid, serverInfo in sorted(serverList.items(), key=lambda x: x[1]["last"], reverse=True):
        lastSeen = int(currentTime - serverInfo["last"])
        playerCount = len(serverInfo["players"])
        maxPlayers = serverInfo["max"]

        status = "starting" if serverInfo.get("starting", False) else "healthy" if lastSeen <= 5 else "stale"
        utilization = (playerCount / maxPlayers) * 100

        servers_data.append({
            "uid": serverUid,
            "short_uid": serverUid[:8],
            "ip": serverInfo["ip"],
            "port": serverInfo["port"],
            "player_count": playerCount,
            "max_players": maxPlayers,
            "utilization": utilization,
            "status": status,
            "last_seen": lastSeen
        })

    rate_limit_data = []
    for ip, timestamps in rateLimitDict.items():
        recent_requests = len(timestamps)
        if recent_requests > 0:
            rate_limit_data.append({
                "ip": ip,
                "requests": recent_requests,
                "blocked": ip in blockedIps,
                "block_expires": int(blockedIps[ip] - currentTime) if ip in blockedIps else 0
            })

    rate_limit_data.sort(key=lambda x: x["requests"], reverse=True)

    return web.json_response({
        "stats": {
            "total_servers": totalServers,
            "total_players": totalPlayers,
            "active_servers": activeServers,
            "total_capacity": totalCapacity,
            "total_users": len(userAccounts)
        },
        "servers": servers_data,
        "rate_limits": rate_limit_data
    })

async def dashboardView(httpRequest):
    with open("dashboard.html", "r") as f:
        html = f.read()
    return web.Response(text=html, content_type="text/html")

async def cleanupTask():
    global last_cleanup

    while True:
        currentTime = time.time()

        if currentTime - last_cleanup > 30:
            deadPlayerList = [playerId for playerId, playerInfo in playerList.items() if currentTime - playerInfo["last"] > 15]
            for playerId in deadPlayerList:
                serverUid = playerList[playerId]["server"]
                if serverUid in serverList and playerId in serverList[serverUid]["players"]:
                    serverList[serverUid]["players"].remove(playerId)
                del playerList[playerId]

            emptyServerList = []
            for serverUid, serverInfo in serverList.items():
                if len(serverInfo["players"]) == 0 and not serverInfo.get("starting", False):
                    if currentTime - serverInfo["last"] > 10:
                        emptyServerList.append(serverUid)

            for serverUid in emptyServerList:
                if serverUid in processList:
                    try:
                        processList[serverUid].terminate()
                        try:
                            await asyncio.wait_for(processList[serverUid].wait(), timeout=5.0)
                        except asyncio.TimeoutError:
                            processList[serverUid].kill()
                            await processList[serverUid].wait()
                    except Exception as e:
                        pass
                    del processList[serverUid]
                del serverList[serverUid]

            oldDatastoreKeys = []
            for key, data in datastoreDict.items():
                if currentTime - data["timestamp"] > 86400:
                    oldDatastoreKeys.append(key)

            for key in oldDatastoreKeys:
                del datastoreDict[key]

            expiredTokens = []
            for token, tokenData in auth_utils.userTokens.items():
                if currentTime - tokenData["created"] > 2592000:
                    expiredTokens.append(token)
            for token in expiredTokens:
                del auth_utils.userTokens[token]

            saveAllData()
            last_cleanup = currentTime

        await asyncio.sleep(5)

async def validateTokenEndpoint(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    token = requestData.get("token")
    if not token:
        return web.json_response({"error": "missing_token"}, status=400)

    if not validateToken(token):
        return web.json_response({"error": "invalid_token"}, status=401)

    token_data = auth_utils.userTokens[token]
    username = token_data["username"]
    user_data = userAccounts[username]

    return web.json_response({
        "status": "valid",
        "username": username,
        "user_id": user_data["user_id"],
        "expires_in": int(2592000 - (time.time() - token_data["created"]))
    })

async def connectToServerID(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    token = requestData.get("token")
    serverId = requestData.get("server_id")

    if not token or not validateToken(token):
        return web.json_response({"error": "invalid_token"}, status=401)

    if not serverId:
        return web.json_response({"error": "missing_server_id"}, status=400)

    if serverId not in serverList:
        return web.json_response({"error": "server_not_found"}, status=404)

    playerId = auth_utils.userTokens[token]["username"]
    serverInfo = serverList[serverId]

    if len(serverInfo["players"]) >= serverInfo["max"]:
        return web.json_response({"error": "server_full"}, status=400)

    serverInfo["players"].add(playerId)
    playerList[playerId] = {"server": serverId, "last": time.time()}

    return web.json_response({
        "uid": serverId,
        "ip": serverInfo["ip"],
        "port": serverInfo["port"]
    })

async def startApp():
    loadAllData()

    webApp = web.Application()
    webApp.add_routes([
        web.post("/auth/register", registerUser),
        web.post("/auth/login", loginUser),
        web.post("/auth/validate", validateTokenEndpoint),
        web.post("/register_server", registerServer),
        web.post("/request_server", requestServer),
        web.post("/heartbeat_server", heartbeatServer),
        web.post("/heartbeat_client", heartbeatClient),
        web.post("/ping_server", getServerPing),
        web.post("/ping_all_servers", getAllServersPing),
        web.post("/connect_to_server", connectToServerID),
        web.post("/datastore/set", setDatastore),
        web.post("/datastore/get", getDatastore),
        web.post("/datastore/remove", removeDatastore),
        web.post("/datastore/list_keys", listDatastoreKeys),
        web.post("/users/get_by_id", getUserById),
        web.post("/users/search", searchUsers),
        web.get("/api/dashboard", getDashboardData),
        web.get("/dashboard", dashboardView),
    ])

    addNewRoutes(webApp)
    asyncio.create_task(cleanupTask())
    return webApp

def shutdownHandler(signalNum, frameObj):
    with shutdown_lock:
        from player_data import resetAllPlayerServers
        resetAllPlayerServers()
        saveAllData()
        for serverUid, serverProc in processList.items():
            try:
                serverProc.kill()
            except:
                pass
    os._exit(0)

signal.signal(signal.SIGINT, shutdownHandler)
signal.signal(signal.SIGTERM, shutdownHandler)

if __name__ == "__main__":
    os.makedirs("pfps", exist_ok=True)
    os.makedirs("models", exist_ok=True)
    os.makedirs("accessories", exist_ok=True)
    web.run_app(startApp(), host='0.0.0.0', port=8080)
