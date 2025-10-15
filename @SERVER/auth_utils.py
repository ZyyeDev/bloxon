import time
from config import SERVER_PUBLIC_IP
from database_manager import execute_query

rateLimitDict = {}
blockedIps = {}
maxRequestsPer15Sec = 100

def isServerIp(clientIp):
    server_ips = ["127.0.0.1", "::1", SERVER_PUBLIC_IP, "localhost"]

    if clientIp in server_ips:
        return True

    if clientIp.startswith("127.") or clientIp.startswith("192.168.") or clientIp.startswith("10.") or clientIp.startswith("172."):
        return True

    return False

def checkRateLimit(clientIp):
    if isServerIp(clientIp):
        return True

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

def validateToken(token):
    result = execute_query(
        "SELECT username, created FROM tokens WHERE token = ?",
        (token,), fetch_one=True
    )

    if not result:
        return False

    if time.time() - result[1] > 2592000:
        execute_query("DELETE FROM tokens WHERE token = ?", (token,))
        return False

    return True

def getUsernameFromToken(token):
    result = execute_query(
        "SELECT username FROM tokens WHERE token = ?",
        (token,), fetch_one=True
    )
    return result[0] if result else None
