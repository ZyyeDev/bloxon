from aiohttp import web
import time
import os
import auth_utils
from friends import addFriendDirect, removeFriend, getFriends, sendFriendRequest, getFriendRequests, acceptFriendRequest, rejectFriendRequest, cancelFriendRequest
from avatar_service import getFullAvatar, getAccessory, buyItem, listMarketItems, getUserAccessories, addAccessoryFromFolder
from currency_system import creditCurrency, debitCurrency, getCurrency, transferCurrency
from player_data import getPlayerData, savePlayerData, createPlayerData, updatePlayerAvatar, setPlayerServer, getPlayerFullProfile
from pfp_service import getPfp, updateUserPfp

def checkRateLimit(clientIp):
    return auth_utils.checkRateLimit(clientIp)

def validateToken(token):
    return auth_utils.validateToken(token)

async def addFriendEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    friendId = requestData.get("friendId")

    if not userId or not friendId:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = addFriendDirect(userId, friendId)
    if result["success"]:
        return web.json_response(result)
    else:
        return web.json_response(result, status=400)

async def removeFriendEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    friendId = requestData.get("friendId")

    if not userId or not friendId:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = removeFriend(userId, friendId)
    return web.json_response(result)

async def getFriendsEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    if not userId:
        return web.json_response({"error": "missing_user_id"}, status=400)

    friends = getFriends(userId)
    return web.json_response({"success": True, "data": friends})

async def getFullAvatarEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    if not userId:
        return web.json_response({"error": "missing_user_id"}, status=400)

    avatar = getFullAvatar(userId)
    return web.json_response({"success": True, "data": avatar})

async def getAccessoryEndpoint(httpRequest):
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

    accessoryId = requestData.get("accessoryId")
    if not accessoryId:
        return web.json_response({"error": "missing_accessory_id"}, status=400)

    accessory = getAccessory(accessoryId)
    if accessory:
        return web.json_response({"success": True, "data": accessory})
    else:
        return web.json_response({"success": False, "error": {"code": "NOT_FOUND", "message": "Accessory not found"}}, status=404)

async def buyItemEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    itemId = requestData.get("itemId")

    if not userId or not itemId:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = buyItem(userId, itemId)
    if result["success"]:
        return web.json_response(result)
    else:
        return web.json_response(result, status=400)

async def listMarketItemsEndpoint(httpRequest):
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

    filterData = requestData.get("filter")
    pagination = requestData.get("pagination")

    result = listMarketItems(filterData, pagination)
    return web.json_response(result)

async def getUserAccessoriesEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    if not userId:
        return web.json_response({"error": "missing_user_id"}, status=400)

    accessories = getUserAccessories(userId)
    return web.json_response({"success": True, "data": accessories})

async def addAccessoryFromFolderEndpoint(httpRequest):
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

    path = requestData.get("path")
    if not path:
        return web.json_response({"error": "missing_path"}, status=400)

    result = addAccessoryFromFolder(path)
    return web.json_response(result)

async def creditCurrencyEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    amount = requestData.get("amount")

    if not userId or not amount:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = creditCurrency(userId, amount)
    if result["success"]:
        return web.json_response(result)
    else:
        return web.json_response(result, status=400)

async def debitCurrencyEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    amount = requestData.get("amount")

    if not userId or not amount:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = debitCurrency(userId, amount)
    if result["success"]:
        return web.json_response(result)
    else:
        return web.json_response(result, status=400)

async def getCurrencyEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    if not userId:
        return web.json_response({"error": "missing_user_id"}, status=400)

    result = getCurrency(userId)
    return web.json_response(result)

async def getPfpEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    if not userId:
        return web.json_response({"error": "missing_user_id"}, status=400)

    pfpUrl = getPfp(userId)
    return web.json_response({"success": True, "data": {"pfp": pfpUrl}})

async def updateAvatarEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    avatarData = requestData.get("avatar")

    if not userId or not avatarData:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = updatePlayerAvatar(userId, avatarData)
    return web.json_response(result)

async def getPlayerProfileEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    if not userId:
        return web.json_response({"error": "missing_user_id"}, status=400)

    result = getPlayerFullProfile(userId)
    return web.json_response(result)

async def setPlayerServerEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    serverId = requestData.get("serverId")

    if not userId:
        return web.json_response({"error": "missing_user_id"}, status=400)

    result = setPlayerServer(userId, serverId)
    return web.json_response(result)

async def sendFriendRequestEndpoint(httpRequest):
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

    fromUserId = requestData.get("fromUserId")
    toUserId = requestData.get("toUserId")

    if not fromUserId or not toUserId:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = sendFriendRequest(fromUserId, toUserId)
    if result["success"]:
        return web.json_response(result)
    else:
        return web.json_response(result, status=400)

async def getFriendRequestsEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    if not userId:
        return web.json_response({"error": "missing_user_id"}, status=400)

    result = getFriendRequests(userId)
    return web.json_response(result)

async def acceptFriendRequestEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    requesterId = requestData.get("requesterId")

    if not userId or not requesterId:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = acceptFriendRequest(userId, requesterId)
    if result["success"]:
        return web.json_response(result)
    else:
        return web.json_response(result, status=400)

async def rejectFriendRequestEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    requesterId = requestData.get("requesterId")

    if not userId or not requesterId:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = rejectFriendRequest(userId, requesterId)
    if result["success"]:
        return web.json_response(result)
    else:
        return web.json_response(result, status=400)

async def cancelFriendRequestEndpoint(httpRequest):
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

    userId = requestData.get("userId")
    targetUserId = requestData.get("targetUserId")

    if not userId or not targetUserId:
        return web.json_response({"error": "missing_required_fields"}, status=400)

    result = cancelFriendRequest(userId, targetUserId)
    if result["success"]:
        return web.json_response(result)
    else:
        return web.json_response(result, status=400)

def addNewRoutes(webApp):
    webApp.add_routes([
        web.post("/friends/add", addFriendEndpoint),
        web.post("/friends/remove", removeFriendEndpoint),
        web.post("/friends/get", getFriendsEndpoint),

        web.post("/friends/send_request", sendFriendRequestEndpoint),
        web.post("/friends/get_requests", getFriendRequestsEndpoint),
        web.post("/friends/accept_request", acceptFriendRequestEndpoint),
        web.post("/friends/reject_request", rejectFriendRequestEndpoint),
        web.post("/friends/cancel_request", cancelFriendRequestEndpoint),

        web.post("/avatar/get_full", getFullAvatarEndpoint),
        web.post("/avatar/get_accessory", getAccessoryEndpoint),
        web.post("/avatar/buy_item", buyItemEndpoint),
        web.post("/avatar/list_market", listMarketItemsEndpoint),
        web.post("/avatar/get_user_accessories", getUserAccessoriesEndpoint),
        web.post("/avatar/add_from_folder", addAccessoryFromFolderEndpoint),

        web.post("/currency/credit", creditCurrencyEndpoint),
        web.post("/currency/debit", debitCurrencyEndpoint),
        web.post("/currency/get", getCurrencyEndpoint),

        web.post("/player/get_pfp", getPfpEndpoint),
        web.post("/player/update_avatar", updateAvatarEndpoint),
        web.post("/player/get_profile", getPlayerProfileEndpoint),
        web.post("/player/set_server", setPlayerServerEndpoint),
    ])

    webApp.router.add_static("/pfps/", "pfps")
    webApp.router.add_static("/models/", "models")
    webApp.router.add_static("/accessories/", "accessories")