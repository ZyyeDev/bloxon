import os
import time
from typing import Optional, Dict, Any

PFPS_DIR = "pfps"
SERVER_PUBLIC_IP = "92.176.163.239"

def ensurePfpDirectory():
    os.makedirs(PFPS_DIR, exist_ok=True)

def generatePfp(userId: int, avatarData: Dict[str, Any]) -> str:
    ensurePfpDirectory()

    timestamp = int(time.time())
    filename = f"{userId}_{timestamp}.png"
    filepath = os.path.join(PFPS_DIR, filename)

    try:
        from PIL import Image, ImageDraw

        img = Image.new('RGB', (256, 256), color='white')
        draw = ImageDraw.Draw(img)

        bodyColors = avatarData.get("bodyColors", {})
        headColor = bodyColors.get("head", "#FFCCAA")

        draw.ellipse([64, 32, 192, 160], fill=headColor)

        accessories = avatarData.get("accessories", [])
        for accessory in accessories:
            if accessory.get("type") == "hat":
                draw.rectangle([64, 20, 192, 50], fill="#8B4513")

        img.save(filepath)

    except ImportError:
        with open(filepath, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x01\x00\x00\x00\x01\x00\x08\x06\x00\x00\x00\x5c\x8a?\xa8\x00\x00\x00\x04sBIT\x08\x08\x08\x08|\x08d\x88\x00\x00\x00\x19tEXtSoftware\x00www.inkscape.org\x9b\xee<\x1a\x00\x00\x00\x0bIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xdb\x00\x00\x00\x00IEND\xaeB`\x82')

    return filepath

def updateUserPfp(userId: int) -> str:
    from avatar_service import getFullAvatar
    from player_data import getPlayerData, savePlayerData

    avatarData = getFullAvatar(userId)
    newPfpPath = generatePfp(userId, avatarData)

    playerData = getPlayerData(userId)
    if playerData:
        playerData["pfp"] = f"http://{SERVER_PUBLIC_IP}:8080/{newPfpPath}"
        savePlayerData(userId, playerData)

    return newPfpPath

def getPfp(userId: int) -> str:
    from player_data import getPlayerData

    playerData = getPlayerData(userId)
    if playerData and "pfp" in playerData:
        return playerData["pfp"]

    defaultPfpPath = os.path.join(PFPS_DIR, "default.png")
    if not os.path.exists(defaultPfpPath):
        ensurePfpDirectory()
        try:
            from PIL import Image, ImageDraw

            img = Image.new('RGB', (256, 256), color='#CCCCCC')
            draw = ImageDraw.Draw(img)
            draw.ellipse([64, 32, 192, 160], fill='#FFCCAA')
            img.save(defaultPfpPath)

        except ImportError:
            with open(defaultPfpPath, 'wb') as f:
                f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x01\x00\x00\x00\x01\x00\x08\x06\x00\x00\x00\x5c\x8a?\xa8\x00\x00\x00\x04sBIT\x08\x08\x08\x08|\x08d\x88\x00\x00\x00\x19tEXtSoftware\x00www.inkscape.org\x9b\xee<\x1a\x00\x00\x00\x0bIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xdb\x00\x00\x00\x00IEND\xaeB`\x82')

    return f"http://{SERVER_PUBLIC_IP}:8080/{defaultPfpPath}"

def cleanupOldPfps(userId: int, keepRecent: int = 5):
    ensurePfpDirectory()

    userPfps = []
    prefix = f"{userId}_"

    for filename in os.listdir(PFPS_DIR):
        if filename.startswith(prefix) and filename.endswith('.png'):
            filepath = os.path.join(PFPS_DIR, filename)
            timestamp = os.path.getctime(filepath)
            userPfps.append((timestamp, filepath))

    userPfps.sort(key=lambda x: x[0], reverse=True)

    for _, filepath in userPfps[keepRecent:]:
        try:
            os.remove(filepath)
        except:
            pass
