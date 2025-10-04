import time

rateLimitDict = {}
blockedIps = {}
userTokens = {}
maxRequestsPer15Sec = 100

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

def validateToken(token):
    if token not in userTokens:
        return False

    token_data = userTokens[token]
    if time.time() - token_data["created"] > 2592000:
        del userTokens[token]
        return False

    return True
