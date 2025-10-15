import signal
import asyncio
import time
import uuid
import subprocess
import os
import json
import hashlib
import secrets
import threading
from collections import defaultdict, deque
from datetime import datetime, timedelta
from aiohttp import web
import aiohttp

import auth_utils
from api_extensions import addNewRoutes
from player_data import createPlayerData, getPlayerFullProfile, resetAllPlayerServers
from config import SERVER_PUBLIC_IP, BASE_PORT, GODOT_SERVER_BIN, DATASTORE_PASSWORD, DASHBOARD_PASSWORD
from database_manager import init_database, execute_query
from global_messages import (add_global_message, get_global_messages, set_maintenance_mode,
                             get_maintenance_status, is_maintenance_mode, clear_old_messages)
from payment_verification import verify_google_play_purchase, verify_ad_reward, get_currency_packages
from server_monitoring import get_system_stats, get_process_stats
import atexit

shutdown_lock = threading.Lock()

serverList = {}
playerList = {}
processList = {}
rateLimitDict = defaultdict(deque)
blockedIps = {}
datastoreDict = {}

MAX_SERVERS = 200
maxRequestsPer15Sec = 100
authMaxRequests = 100

last_cleanup = 0
dashboard_sessions = {}

def emergencyShutdown():
    with shutdown_lock:
        try:
            resetAllPlayerServers()
        except:
            pass

atexit.register(emergencyShutdown)

def checkRateLimit(clientIp):
    return auth_utils.checkRateLimit(clientIp)

def blockIp(clientIp, duration_minutes):
    blockedIps[clientIp] = time.time() + (duration_minutes * 60)

def validateToken(token):
    return auth_utils.validateToken(token)

def hashPassword(password):
    salt = secrets.token_hex(16)
    password_hash = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000)
    import base64
    return salt + ":" + base64.b64encode(password_hash).decode()

def verifyPassword(password, stored_hash):
    try:
        import base64
        salt, hash_part = stored_hash.split(":")
        password_hash = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 100000)
        return base64.b64encode(password_hash).decode() == hash_part
    except:
        return False

def generateToken():
    return secrets.token_urlsafe(32)

async def registerUser(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
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

    existing = execute_query("SELECT user_id FROM accounts WHERE username = ?",
                            (username,), fetch_one=True)
    if existing:
        return web.json_response({"error": "username_taken"}, status=409)

    hashedPassword = hashPassword(password)
    token = generateToken()

    user_id = execute_query(
        "INSERT INTO accounts (username, password, gender, created) VALUES (?, ?, ?, ?)",
        (username, hashedPassword, gender, time.time())
    )

    execute_query(
        "INSERT INTO tokens (token, username, created) VALUES (?, ?, ?)",
        (token, username, time.time())
    )

    createPlayerData(user_id, username)

    return web.json_response({
        "status": "registered",
        "token": token,
        "username": username,
        "user_id": user_id
    })

async def loginUser(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "auth_rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    username = requestData.get("username", "").strip()
    password = requestData.get("password", "")

    if not username or not password:
        return web.json_response({"error": "missing_credentials"}, status=400)

    user_data = execute_query("SELECT user_id, password FROM accounts WHERE username = ?",
                             (username,), fetch_one=True)
    if not user_data:
        return web.json_response({"error": "user_not_found"}, status=404)

    if not verifyPassword(password, user_data[1]):
        return web.json_response({"error": "invalid_password"}, status=401)

    token = generateToken()
    execute_query("INSERT INTO tokens (token, username, created) VALUES (?, ?, ?)",
                 (token, username, time.time()))

    return web.json_response({
        "status": "logged_in",
        "token": token,
        "username": username,
        "user_id": user_data[0]
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
    if is_maintenance_mode():
        return web.json_response({"error": "maintenance_mode"}, status=503)

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

    username = auth_utils.getUsernameFromToken(token)
    user_data = execute_query("SELECT user_id FROM accounts WHERE username = ?",
                              (username,), fetch_one=True)
    userId = user_data[0] if user_data else None

    for serverUid, serverInfo in serverList.items():
        if len(serverInfo["players"]) < serverInfo["max"] and not serverInfo.get("starting", False):
            serverInfo["players"].add(username)
            playerList[username] = {"server": serverUid, "last": time.time()}

            if userId:
                from player_data import setPlayerServer
                setPlayerServer(userId, serverUid)

            return web.json_response({"uid": serverUid, "ip": serverInfo["ip"], "port": serverInfo["port"]})

    serverUid = str(uuid.uuid4())
    serverPort = BASE_PORT + len(serverList) % MAX_SERVERS
    serverList[serverUid] = {
        "ip": SERVER_PUBLIC_IP,
        "port": serverPort,
        "players": {username},
        "max": 6,
        "last": time.time(),
        "starting": True
    }
    playerList[username] = {"server": serverUid, "last": time.time()}

    if userId:
        from player_data import setPlayerServer
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

    username = auth_utils.getUsernameFromToken(token)
    if username in playerList:
        playerList[username]["last"] = time.time()
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

    if isinstance(value, (dict, list)):
        value_str = json.dumps(value)
    else:
        value_str = str(value) if value is not None else ""

    execute_query(
        "INSERT OR REPLACE INTO datastores (key, value, timestamp) VALUES (?, ?, ?)",
        (datastoreKey, value_str, time.time())
    )

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

    result = execute_query(
        "SELECT value, timestamp FROM datastores WHERE key = ?",
        (datastoreKey,), fetch_one=True
    )

    if result:
        value = result[0]
        try:
            value = json.loads(value)
        except:
            pass

        return web.json_response({
            "key": key,
            "value": value,
            "timestamp": result[1]
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

    execute_query("DELETE FROM datastores WHERE key = ?", (datastoreKey,))

    return web.json_response({"status": "removed", "key": key})

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

    results = execute_query(
        "SELECT key, timestamp FROM datastores WHERE key LIKE 'server:%'",
        fetch_all=True
    )

    serverKeys = []
    for row in results:
        key = row[0][7:]
        serverKeys.append({
            "key": key,
            "timestamp": row[1]
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

    user_data = execute_query(
        "SELECT username, user_id, gender, created FROM accounts WHERE user_id = ?",
        (user_id,), fetch_one=True
    )

    if user_data:
        return web.json_response({
            "username": user_data[0],
            "user_id": user_data[1],
            "gender": user_data[2],
            "created": user_data[3]
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

    results = execute_query(
        "SELECT username, user_id, gender, created FROM accounts WHERE LOWER(username) LIKE ? LIMIT ?",
        (f"%{search_query}%", limit), fetch_all=True
    )

    matching_users = []
    for row in results:
        matching_users.append({
            "username": row[0],
            "user_id": row[1],
            "gender": row[2],
            "created": row[3]
        })

    return web.json_response({"users": matching_users})

async def getMaintenanceStatus(httpRequest):
    status = get_maintenance_status()
    return web.json_response(status)

async def getGlobalMessages(httpRequest):
    clientIp = httpRequest.remote
    if not checkRateLimit(clientIp):
        return web.json_response({"error": "rate_limit_exceeded"}, status=429)

    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    since_id = requestData.get("since_id", 0)
    from global_messages import get_global_messages, get_latest_message_id
    messages = get_global_messages(since_id)

    return web.json_response({
        "success": True,
        "data": {
            "messages": messages,
            "latest_id": get_latest_message_id()
        }
    })

    return web.json_response({
        "success": True,
        "data": {"messages": messages}
    })

async def processPurchase(httpRequest):
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

    username = auth_utils.getUsernameFromToken(token)
    user_data = execute_query("SELECT user_id FROM accounts WHERE username = ?",
                              (username,), fetch_one=True)
    if not user_data:
        return web.json_response({"error": "user_not_found"}, status=404)

    user_id = user_data[0]
    product_id = requestData.get("product_id")
    purchase_token = requestData.get("purchase_token")

    if not product_id or not purchase_token:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = verify_google_play_purchase(user_id, product_id, purchase_token)
    return web.json_response(result)

async def processAdReward(httpRequest):
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

    username = auth_utils.getUsernameFromToken(token)
    user_data = execute_query("SELECT user_id FROM accounts WHERE username = ?",
                              (username,), fetch_one=True)
    if not user_data:
        return web.json_response({"error": "user_not_found"}, status=404)

    user_id = user_data[0]
    ad_network = requestData.get("ad_network", "admob")
    ad_unit_id = requestData.get("ad_unit_id")
    reward_amount = requestData.get("reward_amount", 10)
    verification_data = requestData.get("verification_data")

    if not ad_unit_id:
        return web.json_response({"error": "missing_ad_unit_id"}, status=400)

    result = verify_ad_reward(user_id, ad_network, ad_unit_id, reward_amount, verification_data)
    return web.json_response(result)

async def getCurrencyPackagesEndpoint(httpRequest):
    result = get_currency_packages()
    return web.json_response(result)

def verify_dashboard_session(session_token):
    if not session_token or session_token not in dashboard_sessions:
        return False

    session_data = dashboard_sessions[session_token]
    if time.time() - session_data["created"] > 3600:
        del dashboard_sessions[session_token]
        return False

    return True

async def dashboardLogin(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    password = requestData.get("password")

    if password == DASHBOARD_PASSWORD:
        session_token = secrets.token_urlsafe(32)
        dashboard_sessions[session_token] = {
            "created": time.time(),
            "ip": httpRequest.remote
        }
        return web.json_response({"success": True, "session_token": session_token})

    return web.json_response({"error": "invalid_password"}, status=401)

async def sendGlobalMessage(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    session_token = requestData.get("session_token")
    if not verify_dashboard_session(session_token):
        return web.json_response({"error": "unauthorized"}, status=401)

    message_type = requestData.get("type")
    properties = requestData.get("properties", {})

    if not message_type:
        return web.json_response({"error": "missing_type"}, status=400)

    result = add_global_message(message_type, properties)
    return web.json_response(result)

async def setMaintenanceMode(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    session_token = requestData.get("session_token")
    if not verify_dashboard_session(session_token):
        return web.json_response({"error": "unauthorized"}, status=401)

    enabled = requestData.get("enabled", False)
    message = requestData.get("message", "")

    result = set_maintenance_mode(enabled, message)
    return web.json_response(result)

async def getWeatherTypes(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    session_token = requestData.get("session_token")
    if not verify_dashboard_session(session_token):
        return web.json_response({"error": "unauthorized"}, status=401)

    from database_manager import get_weather_types
    weathers = get_weather_types()
    return web.json_response({"success": True, "data": weathers})

async def addWeatherType(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    session_token = requestData.get("session_token")
    if not verify_dashboard_session(session_token):
        return web.json_response({"error": "unauthorized"}, status=401)

    weather_name = requestData.get("weather_name")
    if not weather_name:
        return web.json_response({"error": "missing_weather_name"}, status=400)

    from database_manager import add_weather_type
    success = add_weather_type(weather_name)

    if success:
        return web.json_response({"success": True})
    else:
        return web.json_response({"error": "weather_exists"}, status=400)

async def removeWeatherType(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    session_token = requestData.get("session_token")
    if not verify_dashboard_session(session_token):
        return web.json_response({"error": "unauthorized"}, status=401)

    weather_name = requestData.get("weather_name")
    if not weather_name:
        return web.json_response({"error": "missing_weather_name"}, status=400)

    from database_manager import remove_weather_type
    success = remove_weather_type(weather_name)

    return web.json_response({"success": success})

async def getDashboardData(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        data = await httpRequest.text()
        if data:
            return web.json_response({"error": "invalid_json"}, status=400)
        requestData = {}

    session_token = requestData.get("session_token")
    if not verify_dashboard_session(session_token):
        return web.json_response({"error": "unauthorized"}, status=401)

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
        utilization = (playerCount / maxPlayers) * 100 if maxPlayers > 0 else 0

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

    system_stats = get_system_stats()
    process_stats = get_process_stats(processList)

    from database_manager import get_weather_types
    weather_types = get_weather_types()

    user_count = execute_query("SELECT COUNT(*) FROM accounts", fetch_one=True)[0]

    return web.json_response({
        "stats": {
            "total_servers": totalServers,
            "total_players": totalPlayers,
            "active_servers": activeServers,
            "total_capacity": totalCapacity,
            "total_users": user_count
        },
        "servers": servers_data,
        "rate_limits": rate_limit_data,
        "system": system_stats,
        "processes": process_stats,
        "maintenance": is_maintenance_mode(),
        "weather_types": weather_types
    })

async def dashboardView(httpRequest):
    with open("dashboard.html", "r", encoding="utf-8") as f:
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

            execute_query("DELETE FROM datastores WHERE timestamp < ?", (currentTime - 86400,))
            execute_query("DELETE FROM tokens WHERE created < ?", (currentTime - 2592000,))

            clear_old_messages(300)

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

    username = auth_utils.getUsernameFromToken(token)
    user_data = execute_query(
        "SELECT user_id, created FROM accounts WHERE username = ?",
        (username,), fetch_one=True
    )

    token_data = execute_query(
        "SELECT created FROM tokens WHERE token = ?",
        (token,), fetch_one=True
    )

    return web.json_response({
        "status": "valid",
        "username": username,
        "user_id": user_data[0],
        "expires_in": int(2592000 - (time.time() - token_data[0]))
    })

async def connectToServerID(httpRequest):
    if is_maintenance_mode():
        return web.json_response({"error": "maintenance_mode"}, status=503)

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

    username = auth_utils.getUsernameFromToken(token)
    serverInfo = serverList[serverId]

    if len(serverInfo["players"]) >= serverInfo["max"]:
        return web.json_response({"error": "server_full"}, status=400)

    serverInfo["players"].add(username)
    playerList[username] = {"server": serverId, "last": time.time()}

    return web.json_response({
        "uid": serverId,
        "ip": serverInfo["ip"],
        "port": serverInfo["port"]
    })

async def listAllAccessories(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    session_token = requestData.get("session_token")
    if not verify_dashboard_session(session_token):
        return web.json_response({"error": "unauthorized"}, status=401)

    from avatar_service import listMarketItems
    result = listMarketItems(pagination={"page": 1, "limit": 1000})
    return web.json_response(result)

async def deleteAccessoryEndpoint(httpRequest):
    try:
        requestData = await httpRequest.json()
    except:
        return web.json_response({"error": "invalid_json"}, status=400)

    session_token = requestData.get("session_token")
    if not verify_dashboard_session(session_token):
        return web.json_response({"error": "unauthorized"}, status=401)

    accessory_id = requestData.get("accessory_id")
    if not accessory_id:
        return web.json_response({"error": "missing_accessory_id"}, status=400)

    from avatar_service import deleteAccessory
    result = deleteAccessory(accessory_id)
    return web.json_response(result)

async def addAccessoryEndpoint(httpRequest):
    try:
        session_token = None
        fields = {}
        files = {}
        filenames = {}

        reader = await httpRequest.multipart()
        async for field in reader:
            if field.name == "session_token":
                session_token = await field.text()
            elif field.name in ["name", "type", "price", "equip_slot"]:
                fields[field.name] = await field.text()
            elif field.name in ["model", "texture", "mtl", "icon"]:
                files[field.name] = await field.read()
                filenames[field.name] = field.filename

        if not session_token or not verify_dashboard_session(session_token):
            return web.json_response({"error": "unauthorized"}, status=401)

        if not all(k in fields for k in ["name", "type", "price", "equip_slot"]):
            return web.json_response({"error": "missing_required_fields"}, status=400)

        if "model" not in files:
            return web.json_response({"error": "model_file_required"}, status=400)

        try:
            price = int(fields["price"])
        except:
            return web.json_response({"error": "invalid_price"}, status=400)

        from avatar_service import addAccessoryFromDashboard

        result = addAccessoryFromDashboard(
            name=fields["name"],
            accessory_type=fields["type"],
            price=price,
            equip_slot=fields["equip_slot"],
            model_data=files["model"],
            texture_data=files.get("texture"),
            mtl_data=files.get("mtl"),
            icon_data=files.get("icon"),
            model_filename=filenames.get("model")
        )

        return web.json_response(result)

    except Exception as e:
        import traceback
        print(f"Error in addAccessoryEndpoint: {e}")
        print(traceback.format_exc())
        return web.json_response({"error": str(e)}, status=400)

async def startApp():
    init_database()

    from player_data import loadPlayerData
    loadPlayerData()

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
        web.get("/maintenance_status", getMaintenanceStatus),
        web.post("/global_messages", getGlobalMessages),
        web.post("/payments/purchase", processPurchase),
        web.post("/payments/ad_reward", processAdReward),
        web.get("/payments/packages", getCurrencyPackagesEndpoint),
        web.post("/dashboard/login", dashboardLogin),
        web.post("/dashboard/send_message", sendGlobalMessage),
        web.post("/dashboard/set_maintenance", setMaintenanceMode),
        web.post("/dashboard/weather/list", getWeatherTypes),
        web.post("/dashboard/weather/add", addWeatherType),
        web.post("/dashboard/weather/remove", removeWeatherType),
        web.post("/api/dashboard", getDashboardData),
        web.get("/dashboard", dashboardView),
        web.post("/dashboard/accessories/list", listAllAccessories),
        web.post("/dashboard/accessories/add", addAccessoryEndpoint),
        web.post("/dashboard/accessories/delete", deleteAccessoryEndpoint),
    ])

    addNewRoutes(webApp)
    asyncio.create_task(cleanupTask())
    return webApp

def shutdownHandler(signalNum, frameObj):
    with shutdown_lock:
        resetAllPlayerServers()
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
    os.makedirs("icons", exist_ok=True)
    web.run_app(startApp(), host='0.0.0.0', port=8080)
