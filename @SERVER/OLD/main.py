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
from datetime import datetime, timedelta
from aiohttp import web
import aiohttp
from cryptography.fernet import Fernet
import base64

serverList = {}
playerList = {}
processList = {}
rateLimitDict = {}
blockedIps = {}
datastoreDict = {}
userAccounts = {}
userTokens = {}
authRateLimitDict = {}

DATASTORE_PASSWORD = "@MEOW"
GODOT_SERVER_BIN = "server.exe"
BASE_PORT = 5000
MAX_SERVERS = 200
maxRequestsPer15Sec = 100
authMaxRequests = 100
SERVER_PUBLIC_IP = "92.176.163.239"

DATA_DIR = "server_data"
ACCOUNTS_FILE = os.path.join(DATA_DIR, "accounts.dat")
DATASTORES_FILE = os.path.join(DATA_DIR, "datastores.dat")
TOKENS_FILE = os.path.join(DATA_DIR, "tokens.dat")
SERVERS_FILE = os.path.join(DATA_DIR, "servers.dat")
KEY_FILE = os.path.join(DATA_DIR, "master.key")

nextUserId = 1

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

def generateDataHash(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()

def saveSecureData(filename, data):
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        os.chmod(DATA_DIR, 0o700)

        data_hash = generateDataHash(data)
        secure_data = {
            "data": data,
            "hash": data_hash,
            "timestamp": time.time()
        }

        encrypted_data = encryptData(secure_data)
        temp_file = filename + ".tmp"

        with open(temp_file, "wb") as f:
            f.write(encrypted_data)
        os.chmod(temp_file, 0o600)

        if os.path.exists(filename):
            os.remove(filename)
        os.rename(temp_file, filename)

        return True
    except Exception as e:
        print(f"Error saving data to {filename}: {e}")
        return False

def loadSecureData(filename):
    try:
        if not os.path.exists(filename):
            return {}

        with open(filename, "rb") as f:
            encrypted_data = f.read()

        secure_data = decryptData(encrypted_data)
        if not secure_data:
            return {}

        data = secure_data.get("data", {})
        stored_hash = secure_data.get("hash", "")
        calculated_hash = generateDataHash(data)

        if stored_hash != calculated_hash:
            print(f"Data integrity check failed for {filename}")
            return {}

        return data
    except Exception as e:
        print(f"Error loading data from {filename}: {e}")
        return {}

def saveAllData():
    saveSecureData(ACCOUNTS_FILE, userAccounts)
    saveSecureData(DATASTORES_FILE, datastoreDict)
    saveSecureData(TOKENS_FILE, userTokens)
    saveSecureData("user_id_counter.dat", {"next_id": nextUserId})

    server_data = {}
    for uid, info in serverList.items():
        server_data[uid] = {
            "ip": info["ip"],
            "port": info["port"],
            "max": info["max"],
            "last": info["last"]
        }
    saveSecureData(SERVERS_FILE, server_data)

def loadAllData():
    global userAccounts, datastoreDict, userTokens, serverList

    userAccounts = loadSecureData(ACCOUNTS_FILE)
    datastoreDict = loadSecureData(DATASTORES_FILE)
    userTokens = loadSecureData(TOKENS_FILE)

    id_data = loadSecureData("user_id_counter.dat")
    global nextUserId
    if id_data and "next_id" in id_data:
        nextUserId = id_data["next_id"]
    else:
        nextUserId = max([acc.get("user_id", 0) for acc in userAccounts.values()], default=0) + 1

    server_data = loadSecureData(SERVERS_FILE)
    for uid, info in server_data.items():
        serverList[uid] = {
            "ip": info["ip"],
            "port": info["port"],
            "players": set(),
            "max": info["max"],
            "last": info["last"]
        }

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

    if clientIp not in authRateLimitDict:
        authRateLimitDict[clientIp] = []

    authRateLimitDict[clientIp] = [timestamp for timestamp in authRateLimitDict[clientIp] if currentTime - timestamp < 60]

    if len(authRateLimitDict[clientIp]) >= authMaxRequests:
        return False

    authRateLimitDict[clientIp].append(currentTime)
    return True

def validateToken(token):
    if token not in userTokens:
        return False

    token_data = userTokens[token]
    if time.time() - token_data["created"] > 2592000:
        del userTokens[token]
        return False

    return True

def checkRateLimit(clientIp):
    currentTime = time.time()

    if clientIp in blockedIps:
        if currentTime < blockedIps[clientIp]:
            return False
        else:
            del blockedIps[clientIp]

    if clientIp not in rateLimitDict:
        rateLimitDict[clientIp] = []

    rateLimitDict[clientIp] = [timestamp for timestamp in rateLimitDict[clientIp] if currentTime - timestamp < 15]

    if len(rateLimitDict[clientIp]) >= maxRequestsPer15Sec:
        return False

    rateLimitDict[clientIp].append(currentTime)
    return True

def blockIp(clientIp, duration_minutes):
    blockedIps[clientIp] = time.time() + (duration_minutes * 60)
    print(f"Blocked IP {clientIp} for {duration_minutes} minutes")

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

    print(username,password,gender)

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

    nextUserId += 1

    userTokens[token] = {
        "username": username,
        "created": time.time()
    }

    saveAllData()

    return web.json_response({
        "status": "registered",
        "token": token,
        "username": username,
        "user_id": userAccounts[username]["user_id"]
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
    userTokens[token] = {
        "username": username,
        "created": time.time()
    }

    saveAllData()

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
    print(f"Spawning new server {serverUid} on port {serverPort}")
    serverProc = await asyncio.create_subprocess_exec(
        GODOT_SERVER_BIN,
        "--headless",
        f"--uid", f"{serverUid}",
        f"--port", f"{serverPort}",
        f"--master", f"http://{SERVER_PUBLIC_IP}:8080",
        "--server",
        #stdout=subprocess.PIPE,
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

    #token = requestData.get("token")
    #if not token or not validateToken(token):
    #    return web.json_response({"error": "invalid_token"}, status=401)

    serverUid = requestData.get("uid")
    serverIp = requestData.get("ip", SERVER_PUBLIC_IP)
    serverPort = requestData["port"]
    maxPlayerCount = requestData.get("max_players", 8)

    if serverUid in serverList:
        serverList[serverUid].update({"ip": SERVER_PUBLIC_IP, "port": serverPort, "max": maxPlayerCount, "last": time.time()})
    else:
        serverList[serverUid] = {"ip": SERVER_PUBLIC_IP, "port": serverPort, "players": set(), "max": maxPlayerCount, "last": time.time()}

    saveAllData()
    print(f"Server registered: {serverUid} at {SERVER_PUBLIC_IP}:{serverPort}")
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

    playerId = userTokens[token]["username"]

    for serverUid, serverInfo in serverList.items():
        if len(serverInfo["players"]) < serverInfo["max"] and not serverInfo.get("starting", False):
            serverInfo["players"].add(playerId)
            playerList[playerId] = {"server": serverUid, "last": time.time()}
            print(f"Player {playerId} joined existing server {serverUid}")
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
    print(f"Created new server {serverUid} for player {playerId}")
    await spawnServer(serverUid, serverPort)

    await asyncio.sleep(3)
    if serverUid in serverList:
        serverList[serverUid]["starting"] = False

    saveAllData()
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

    playerId = userTokens[token]["username"]
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

    saveAllData()
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
        saveAllData()
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

async def adminBlockIp(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    if 1==1: return 

    clientIp = requestData.get("ip")
    duration = requestData.get("duration", 60)

    if clientIp:
        blockIp(clientIp, duration)
        return web.json_response({"status": "blocked", "ip": clientIp, "duration": duration})
    return web.json_response({"error": "invalid_ip"}, status=400)

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

async def adminRestartServers(httpRequest):
    print("Restarting all servers...")
    if 1==1: return 

    for serverUid, serverProc in list(processList.items()):
        try:
            serverProc.terminate()
            try:
                await asyncio.wait_for(serverProc.wait(), timeout=5.0)
            except asyncio.TimeoutError:
                serverProc.kill()
                await serverProc.wait()
        except Exception as e:
            print(f"Error stopping server {serverUid}: {e}")

    processList.clear()
    playerList.clear()

    servers_to_restart = list(serverList.keys())
    for serverUid in servers_to_restart:
        serverInfo = serverList[serverUid]
        serverList[serverUid] = {
            "ip": SERVER_PUBLIC_IP,
            "port": serverInfo["port"],
            "players": set(),
            "max": serverInfo["max"],
            "last": time.time(),
            "starting": True
        }
        await spawnServer(serverUid, serverInfo["port"])
        serverList[serverUid]["starting"] = False

    return web.json_response({"status": "restarted", "servers": len(servers_to_restart)})

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
        recent_requests = len([t for t in timestamps if currentTime - t < 15])
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
    while True:
        currentTime = time.time()

        deadPlayerList = [playerId for playerId, playerInfo in playerList.items() if currentTime - playerInfo["last"] > 15]
        for playerId in deadPlayerList:
            serverUid = playerList[playerId]["server"]
            if serverUid in serverList and playerId in serverList[serverUid]["players"]:
                serverList[serverUid]["players"].remove(playerId)
                print(f"Removed dead player {playerId} from server {serverUid}")
            del playerList[playerId]

        emptyServerList = []
        for serverUid, serverInfo in serverList.items():
            if len(serverInfo["players"]) == 0 and not serverInfo.get("starting", False):
                if time.time() - serverInfo["last"] > 10:
                    emptyServerList.append(serverUid)

        for serverUid in emptyServerList:
            print(f"Shutting down empty server {serverUid}")
            if serverUid in processList:
                try:
                    processList[serverUid].terminate()
                    try:
                        await asyncio.wait_for(processList[serverUid].wait(), timeout=5.0)
                    except asyncio.TimeoutError:
                        processList[serverUid].kill()
                        await processList[serverUid].wait()
                except Exception as errorMsg:
                    print(f"Error killing process {serverUid}: {errorMsg}")
                del processList[serverUid]
            del serverList[serverUid]

        oldDatastoreKeys = []
        for key, data in datastoreDict.items():
            if currentTime - data["timestamp"] > 86400:
                oldDatastoreKeys.append(key)

        for key in oldDatastoreKeys:
            del datastoreDict[key]

        expiredTokens = []
        for token, tokenData in userTokens.items():
            if currentTime - tokenData["created"] > 2592000:
                expiredTokens.append(token)

        for token in expiredTokens:
            del userTokens[token]

        saveAllData()
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

    token_data = userTokens[token]
    username = token_data["username"]
    user_data = userAccounts[username]

    return web.json_response({
        "status": "valid",
        "username": username,
        "user_id": user_data["user_id"],
        "expires_in": int(2592000 - (time.time() - token_data["created"]))
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
        web.post("/datastore/set", setDatastore),
        web.post("/datastore/get", getDatastore),
        web.post("/datastore/remove", removeDatastore),
        web.post("/datastore/list_keys", listDatastoreKeys),
        web.post("/users/get_by_id", getUserById),
        web.post("/users/search", searchUsers), 
        web.post("/admin/block_ip", adminBlockIp), #disabled for now to prevent exploiting, not really using this so just keep like that
        web.post("/admin/restart_servers", adminRestartServers), #disabled for now to prevent exploiting, not really using this so just keep like that
        web.get("/api/dashboard", getDashboardData),
        web.get("/dashboard", dashboardView),
    ])
    asyncio.create_task(cleanupTask())
    return webApp

def shutdownHandler(signalNum, frameObj):
    print("Shutting down all servers...")
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
    web.run_app(startApp(), host='0.0.0.0', port=8080)
