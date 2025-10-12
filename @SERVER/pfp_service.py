import os
import json
import time
import subprocess
import asyncio
import platform
from typing import Optional, Dict, Any
from config import SERVER_PUBLIC_IP, GODOT_SERVER_BIN

PFPS_DIR = "pfps"
GODOT_BIN = GODOT_SERVER_BIN
IS_WINDOWS = platform.system() == "Windows"
USE_XVFB = not IS_WINDOWS and os.environ.get("USE_XVFB", "true").lower() == "true"

def ensurePfpDirectory():
    os.makedirs(PFPS_DIR, exist_ok=True)

async def generatePfp(userId: int, avatarData: Dict[str, Any]) -> str:
    ensurePfpDirectory()

    timestamp = int(time.time())
    filename = f"{userId}_{timestamp}.png"
    filepath = f"{PFPS_DIR}/{filename}"

    if IS_WINDOWS:
        config_path = f"avatar_config_{userId}_{timestamp}.json"
    else:
        config_path = f"/tmp/avatar_config_{userId}_{timestamp}.json"

    try:
        with open(config_path, 'w') as f:
            json.dump(avatarData, f)
    except Exception as e:
        print(f"Error writing avatar config: {e}")
        return generateFallbackPfp(userId)

    try:
        if USE_XVFB and os.path.exists("/usr/bin/xvfb-run"):
            cmd = [
                "xvfb-run",
                "-a",
                "-s", "-screen 0 512x512x24",
                GODOT_BIN,
                "--rendering-driver", "opengl3",
                "--pfp-render",
                "--avatar-config", config_path,
                "--output", filepath
            ]
        elif IS_WINDOWS:
            cmd = [
                GODOT_BIN,
                "--rendering-driver", "opengl3",
                "--pfp-render",
                "--avatar-config", config_path,
                "--output", filepath
            ]
        else:
            cmd = [
                GODOT_BIN,
                "--rendering-driver", "opengl3",
                "--display-driver", "x11",
                "--pfp-render",
                "--avatar-config", config_path,
                "--output", filepath
            ]

        if IS_WINDOWS:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = subprocess.SW_HIDE

            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                startupinfo=startupinfo,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
        else:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={**os.environ, "DISPLAY": ":99"} if not USE_XVFB else None
            )

        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=15.0
            )

            if process.returncode == 0 and os.path.exists(filepath):
                try:
                    os.remove(config_path)
                except:
                    pass
                return filepath
            else:
                error_msg = stderr.decode() if stderr else "Unknown error"
                print(f"Godot render failed (code {process.returncode}): {error_msg}")

        except asyncio.TimeoutError:
            process.kill()
            await process.wait()
            print(f"Godot render timeout for user {userId}")

    except Exception as e:
        print(f"Error rendering PFP for user {userId}: {e}")

    try:
        if os.path.exists(config_path):
            os.remove(config_path)
    except:
        pass

    return generateFallbackPfp(userId)

def generateFallbackPfp(userId: int) -> str:
    timestamp = int(time.time())
    filename = f"{userId}_{timestamp}_fallback.png"
    filepath = f"{PFPS_DIR}/{filename}"

    try:
        from PIL import Image, ImageDraw, ImageFont

        colors = [
            "#FF6B6B", "#4ECDC4", "#45B7D1", "#FFA07A",
            "#98D8C8", "#F7DC6F", "#BB8FCE", "#85C1E2"
        ]
        color = colors[userId % len(colors)]

        img = Image.new('RGB', (512, 512), color=color)
        draw = ImageDraw.Draw(img)

        try:
            if IS_WINDOWS:
                font = ImageFont.truetype("arial.ttf", 80)
            else:
                font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 80)
        except:
            font = ImageFont.load_default()

        text = f"#{userId}"
        bbox = draw.textbbox((0, 0), text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
        x = (512 - text_width) // 2
        y = (512 - text_height) // 2

        draw.text((x, y), text, fill='white', font=font)
        img.save(filepath)

    except ImportError:
        with open(filepath, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x01\x00\x00\x00\x01\x00\x08\x06\x00\x00\x00\x5c\x8a?\xa8\x00\x00\x00\x04sBIT\x08\x08\x08\x08|\x08d\x88\x00\x00\x00\x19tEXtSoftware\x00www.inkscape.org\x9b\xee<\x1a\x00\x00\x00\x0bIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xdb\x00\x00\x00\x00IEND\xaeB`\x82')

    return filepath

async def updateUserPfp(userId: int) -> str:
    from avatar_service import getFullAvatar
    from player_data import getPlayerData, savePlayerData

    avatarData = getFullAvatar(userId)
    
    cleanupOldPfps(userId, keepRecent=0)

    newPfpPath = await generatePfp(userId, avatarData)

    playerData = getPlayerData(userId)
    if playerData:
        port = os.environ.get('PORT', 8080)
        playerData["pfp"] = f"http://{SERVER_PUBLIC_IP}:{port}/{newPfpPath}"
        savePlayerData(userId, playerData)

    return newPfpPath

def getPfp(userId: int) -> str:
    from player_data import getPlayerData

    playerData = getPlayerData(userId)
    if playerData and "pfp" in playerData:
        return playerData["pfp"]

    defaultPfpPath = f"{PFPS_DIR}/default.png"
    if not os.path.exists(defaultPfpPath):
        ensurePfpDirectory()
        try:
            from PIL import Image, ImageDraw

            img = Image.new('RGB', (512, 512), color='#2C3E50')
            draw = ImageDraw.Draw(img)

            draw.ellipse([156, 100, 356, 300], fill='#34495E')
            draw.ellipse([106, 280, 406, 480], fill='#34495E')

            img.save(defaultPfpPath)

        except ImportError:
            with open(defaultPfpPath, 'wb') as f:
                f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x01\x00\x00\x00\x01\x00\x08\x06\x00\x00\x00\x5c\x8a?\xa8\x00\x00\x00\x04sBIT\x08\x08\x08\x08|\x08d\x88\x00\x00\x00\x19tEXtSoftware\x00www.inkscape.org\x9b\xee<\x1a\x00\x00\x00\x0bIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xdb\x00\x00\x00\x00IEND\xaeB`\x82')

    port = os.environ.get('PORT', 8080)
    return f"http://{SERVER_PUBLIC_IP}:{port}/{defaultPfpPath}"

def cleanupOldPfps(userId: int, keepRecent: int = 5):
    ensurePfpDirectory()

    userPfps = []
    prefix = f"{userId}_"

    for filename in os.listdir(PFPS_DIR):
        if filename.startswith(prefix) and filename.endswith('.png'):
            filepath = os.path.join(PFPS_DIR, filename)
            try:
                timestamp = os.path.getctime(filepath)
                userPfps.append((timestamp, filepath))
            except:
                pass

    userPfps.sort(key=lambda x: x[0], reverse=True)

    for _, filepath in userPfps[keepRecent:]:
        try:
            os.remove(filepath)
        except Exception as e:
            print(f"Failed to remove old PFP {filepath}: {e}")
