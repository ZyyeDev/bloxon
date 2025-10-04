import sqlite3
import json
import os

DB_FILE = os.path.join("server_data", "server.db")
c = sqlite3.connect(DB_FILE)

print("=== ACCOUNTS ===")
for r in c.execute("SELECT * FROM accounts"):
    print(json.dumps({"username": r[0], "password": r[1], "gender": r[2], "created": r[3], "user_id": r[4]}, indent=2))

print("\n=== TOKENS ===")
for r in c.execute("SELECT * FROM tokens"):
    print(json.dumps({"token": r[0], "username": r[1], "created": r[2]}, indent=2))

print("\n=== DATASTORES ===")
for r in c.execute("SELECT * FROM datastores"):
    v = r[1]
    try: v = json.loads(v)
    except: pass
    print(json.dumps({"key": r[0], "value": v, "timestamp": r[2]}, indent=2))

print("\n=== SERVERS ===")
for r in c.execute("SELECT * FROM servers"):
    print(json.dumps({"uid": r[0], "ip": r[1], "port": r[2], "max_players": r[3], "last_seen": r[4]}, indent=2))

c.close()