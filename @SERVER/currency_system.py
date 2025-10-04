from typing import Dict, Any

CURRENCY_NAME = "coins"

def creditCurrency(userId: int, amount: int) -> Dict[str, Any]:
    from player_data import getPlayerData, savePlayerData

    if amount <= 0:
        return {"success": False, "error": {"code": "INVALID_AMOUNT", "message": "Amount must be positive"}}

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    currentCurrency = playerData.get("currency", 0)
    newCurrency = currentCurrency + amount

    playerData["currency"] = newCurrency
    savePlayerData(userId, playerData)

    return {"success": True, "data": {"previousBalance": currentCurrency, "newBalance": newCurrency, "amount": amount}}

def debitCurrency(userId: int, amount: int) -> Dict[str, Any]:
    from player_data import getPlayerData, savePlayerData

    if amount <= 0:
        return {"success": False, "error": {"code": "INVALID_AMOUNT", "message": "Amount must be positive"}}

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    currentCurrency = playerData.get("currency", 0)
    if currentCurrency < amount:
        return {"success": False, "error": {"code": "INSUFFICIENT_FUNDS", "message": "Not enough currency"}}

    newCurrency = currentCurrency - amount
    playerData["currency"] = newCurrency
    savePlayerData(userId, playerData)

    return {"success": True, "data": {"previousBalance": currentCurrency, "newBalance": newCurrency, "amount": amount}}

def getCurrency(userId: int) -> Dict[str, Any]:
    from player_data import getPlayerData

    playerData = getPlayerData(userId)
    if not playerData:
        return {"success": False, "error": {"code": "USER_NOT_FOUND", "message": "User not found"}}

    return {"success": True, "data": {"balance": playerData.get("currency", 0), "currencyName": CURRENCY_NAME}}

def transferCurrency(fromUserId: int, toUserId: int, amount: int) -> Dict[str, Any]:
    if fromUserId == toUserId:
        return {"success": False, "error": {"code": "SAME_USER", "message": "Cannot transfer to yourself"}}

    debitResult = debitCurrency(fromUserId, amount)
    if not debitResult["success"]:
        return debitResult

    creditResult = creditCurrency(toUserId, amount)
    if not creditResult["success"]:
        creditCurrency(fromUserId, amount)
        return creditResult

    return {"success": True, "data": {"from": fromUserId, "to": toUserId, "amount": amount}}
