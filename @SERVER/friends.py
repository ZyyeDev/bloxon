import os
import json
import time
from typing import List, Dict, Any, Optional

FRIENDS_FILE = os.path.join("server_data", "friends.dat")
FRIEND_REQUESTS_FILE = os.path.join("server_data", "friend_requests.dat")

friendsDict = {}
friendRequestsDict = {}

def loadFriendsData():
    global friendsDict, friendRequestsDict
    try:
        if os.path.exists(FRIENDS_FILE):
            with open(FRIENDS_FILE, "r") as f:
                friendsDict = json.load(f)
        else:
            friendsDict = {}
    except:
        friendsDict = {}

    try:
        if os.path.exists(FRIEND_REQUESTS_FILE):
            with open(FRIEND_REQUESTS_FILE, "r") as f:
                friendRequestsDict = json.load(f)
        else:
            friendRequestsDict = {}
    except:
        friendRequestsDict = {}

def saveFriendsData():
    try:
        os.makedirs("server_data", exist_ok=True)
        with open(FRIENDS_FILE, "w") as f:
            json.dump(friendsDict, f)
        with open(FRIEND_REQUESTS_FILE, "w") as f:
            json.dump(friendRequestsDict, f)
    except Exception as e:
        print(f"Error saving friends data: {e}")

def sendFriendRequest(fromUserId: int, toUserId: int) -> Dict[str, Any]:
    if fromUserId == toUserId:
        return {"success": False, "error": {"code": "SELF_REQUEST", "message": "Cannot send friend request to yourself"}}

    fromUserKey = str(fromUserId)
    toUserKey = str(toUserId)

    if toUserKey in friendsDict and fromUserId in friendsDict[toUserKey]:
        return {"success": False, "error": {"code": "ALREADY_FRIENDS", "message": "Already friends with this user"}}

    if toUserKey not in friendRequestsDict:
        friendRequestsDict[toUserKey] = {"incoming": [], "outgoing": []}
    if fromUserKey not in friendRequestsDict:
        friendRequestsDict[fromUserKey] = {"incoming": [], "outgoing": []}

    if fromUserId in friendRequestsDict[toUserKey]["incoming"]:
        return {"success": False, "error": {"code": "REQUEST_EXISTS", "message": "Friend request already sent"}}

    if toUserId in friendRequestsDict[fromUserKey]["incoming"]:
        return acceptFriendRequest(fromUserId, toUserId)

    friendRequestsDict[toUserKey]["incoming"].append(fromUserId)
    friendRequestsDict[fromUserKey]["outgoing"].append(toUserId)

    saveFriendsData()
    return {"success": True, "data": {"fromUserId": fromUserId, "toUserId": toUserId, "timestamp": time.time()}}

def getFriendRequests(userId: int) -> Dict[str, Any]:
    userKey = str(userId)

    if userKey not in friendRequestsDict:
        return {"success": True, "data": {"incoming": [], "outgoing": []}}

    incoming = friendRequestsDict[userKey].get("incoming", [])
    outgoing = friendRequestsDict[userKey].get("outgoing", [])

    return {"success": True, "data": {"incoming": incoming, "outgoing": outgoing}}

def acceptFriendRequest(userId: int, requesterId: int) -> Dict[str, Any]:
    userKey = str(userId)
    requesterKey = str(requesterId)

    if userKey not in friendRequestsDict or requesterId not in friendRequestsDict[userKey]["incoming"]:
        return {"success": False, "error": {"code": "REQUEST_NOT_FOUND", "message": "Friend request not found"}}

    friendRequestsDict[userKey]["incoming"].remove(requesterId)
    if requesterKey in friendRequestsDict and userId in friendRequestsDict[requesterKey]["outgoing"]:
        friendRequestsDict[requesterKey]["outgoing"].remove(userId)

    if userKey not in friendsDict:
        friendsDict[userKey] = []
    if requesterKey not in friendsDict:
        friendsDict[requesterKey] = []

    if requesterId not in friendsDict[userKey]:
        friendsDict[userKey].append(requesterId)
    if userId not in friendsDict[requesterKey]:
        friendsDict[requesterKey].append(userId)

    saveFriendsData()
    return {"success": True, "data": {"userId": userId, "friendId": requesterId, "timestamp": time.time()}}

def rejectFriendRequest(userId: int, requesterId: int) -> Dict[str, Any]:
    userKey = str(userId)
    requesterKey = str(requesterId)

    if userKey not in friendRequestsDict or requesterId not in friendRequestsDict[userKey]["incoming"]:
        return {"success": False, "error": {"code": "REQUEST_NOT_FOUND", "message": "Friend request not found"}}

    friendRequestsDict[userKey]["incoming"].remove(requesterId)
    if requesterKey in friendRequestsDict and userId in friendRequestsDict[requesterKey]["outgoing"]:
        friendRequestsDict[requesterKey]["outgoing"].remove(userId)

    saveFriendsData()
    return {"success": True, "data": {"userId": userId, "requesterId": requesterId}}

def cancelFriendRequest(userId: int, targetUserId: int) -> Dict[str, Any]:
    userKey = str(userId)
    targetKey = str(targetUserId)

    if userKey not in friendRequestsDict or targetUserId not in friendRequestsDict[userKey]["outgoing"]:
        return {"success": False, "error": {"code": "REQUEST_NOT_FOUND", "message": "Outgoing friend request not found"}}

    friendRequestsDict[userKey]["outgoing"].remove(targetUserId)
    if targetKey in friendRequestsDict and userId in friendRequestsDict[targetKey]["incoming"]:
        friendRequestsDict[targetKey]["incoming"].remove(userId)

    saveFriendsData()
    return {"success": True, "data": {"userId": userId, "targetUserId": targetUserId}}

def addFriendDirect(userId: int, friendId: int) -> Dict[str, Any]: 
    if userId == friendId:
        return {"success": False, "error": {"code": "SELF_FRIEND", "message": "Cannot add yourself as friend"}}

    userKey = str(userId)
    friendKey = str(friendId)

    if userKey not in friendsDict:
        friendsDict[userKey] = []
    if friendKey not in friendsDict:
        friendsDict[friendKey] = []

    if friendId not in friendsDict[userKey]:
        friendsDict[userKey].append(friendId)
    if userId not in friendsDict[friendKey]:
        friendsDict[friendKey].append(userId)

    saveFriendsData()
    return {"success": True, "data": {"userId": userId, "friendId": friendId}}

def removeFriend(userId: int, friendId: int) -> Dict[str, Any]:
    userKey = str(userId)
    friendKey = str(friendId)

    if userKey in friendsDict and friendId in friendsDict[userKey]:
        friendsDict[userKey].remove(friendId)
    if friendKey in friendsDict and userId in friendsDict[friendKey]:
        friendsDict[friendKey].remove(userId)

    saveFriendsData()
    return {"success": True, "data": {"userId": userId, "friendId": friendId}}

def getFriends(userId: int) -> List[int]:
    userKey = str(userId)
    return friendsDict.get(userKey, [])

loadFriendsData()
