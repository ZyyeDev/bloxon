extends Node

var http: HTTPRequest
var peer: ENetMultiplayerPeer
var uid: String = ""
var port: int = 5001 
var maxPlayers: int = 8
var heartbeat_timer: Timer
var server_running: bool = false

var DATASTORE_password = "@MEOW"

var playerData = {}
var uidToUserId = {}
var connectedPlayers = {}

func _ready():
	if !Global.isClient:
		print("Starting dedicated server...")
		await get_tree().process_frame
		get_tree().change_scene_to_file("res://scenes/mainGame.tscn")
		await get_tree().process_frame
		await get_tree().process_frame
		
		parseArgs()
		
		http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(_on_request_completed)
		
		peer = ENetMultiplayerPeer.new()
		var ok = peer.create_server(port, maxPlayers)
		if ok != OK:
			print("Failed to create server on port ", port, " Error: ", ok)
			get_tree().quit()
			return
		
		get_tree().get_multiplayer().multiplayer_peer = peer
		get_tree().get_multiplayer().peer_connected.connect(_on_peer_connected)
		get_tree().get_multiplayer().peer_disconnected.connect(_on_peer_disconnected)
		
		server_running = true
		print("Server created successfully on port ", port)
		
		await get_tree().process_frame
		print("Registering server...")
		registerServer()
		print("Starting heartbeat...")
		startHeartbeat()
		
		var saveTimer = Timer.new()
		add_child(saveTimer)
		saveTimer.wait_time = 30
		saveTimer.autostart = true
		saveTimer.timeout.connect(func():
			print("Auto-saving all player data...")
			await saveAllPlayerData()
		)
		saveTimer.start()

func parseArgs():
	var args = OS.get_cmdline_args()
	if args.find("--server") != -1:
		args.remove_at(args.find("--server"))
	var i = 0
	while i < args.size():
		var a = args[i]
		if a == "--uid" and i + 1 < args.size():
			uid = args[i + 1]
			i += 1
		elif a == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
			i += 1
		elif a == "--master" and i + 1 < args.size():
			Global.masterIp = args[i + 1]
			i += 1
		i += 1

func get_external_ip():
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10.") or (addr.begins_with("172.") and addr.split(".")[1].to_int() >= 16 and addr.split(".")[1].to_int() <= 31):
			return addr
		elif not addr.begins_with("127.") and not addr.begins_with("169.254") and ":" not in addr:
			return addr
	return Global.noportIp

func registerServer():
	if !server_running:
		print("Server not running, skipping registration")
		return
		
	var url = Global.masterIp + "/register_server"
	var headers = ["Content-Type: application/json"]
	var server_ip = Global.noportIp
	print("Registering server with IP: ", server_ip)
	
	if uid == "": 
		uid = str(randi_range(1111,99999999999))
		print("Generated server UID: ", uid)
	
	var body = {"uid": uid, "ip": server_ip, "port": port, "max_players": maxPlayers}
	print("Registration payload: ", JSON.stringify(body))
	
	var register_http = HTTPRequest.new()
	add_child(register_http)
	register_http.request_completed.connect(_on_register_completed)
	var err = register_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		print("Failed to send registration request: ", err)
		register_http.queue_free()

func _on_register_completed(result, code, headers, body):
	var sender = get_children().back()
	if sender is HTTPRequest:
		sender.queue_free()
	
	if code == 200:
		print("Server registration successful")
	else:
		print("Server registration failed, code: ", code, " body: ", body.get_string_from_utf8())

func startHeartbeat():
	if !server_running:
		return
		
	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = 5.0
	heartbeat_timer.autostart = true
	add_child(heartbeat_timer)
	heartbeat_timer.timeout.connect(_on_heartbeat_timer)

func _on_heartbeat_timer():
	if !server_running:
		print("Server not running, skipping heartbeat")
		return
		
	var url = Global.masterIp + "/heartbeat_server"
	var headers = ["Content-Type: application/json"]
	var body = {"uid": uid}
	
	var http_hb = HTTPRequest.new()
	add_child(http_hb)
	http_hb.request_completed.connect(_on_heartbeat_completed)
	var err = http_hb.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		print("Failed to send heartbeat: ", err)
		http_hb.queue_free()

func _on_heartbeat_completed(result, code, headers, body):
	var sender = get_children().back()
	if sender is HTTPRequest:
		sender.queue_free()
	
	if code != 200:
		pass

func _on_request_completed(result, code, headers, body):
	if code == 200:
		print("Server operation successful")
	else:
		print("Server operation failed, code: ", code)

@rpc("any_peer","call_remote","reliable")
func register_client_account(user_id, token):
	print("Registering client - user_id: ", user_id, " peer_id: ", get_tree().get_multiplayer().get_remote_sender_id())
	var sender_id = get_tree().get_multiplayer().get_remote_sender_id()
	
	uidToUserId[str(sender_id)] = user_id
	connectedPlayers[user_id] = {
		"peer_id": sender_id,
		"connected_at": Time.get_unix_time_from_system(),
		"last_activity": Time.get_unix_time_from_system()
	}
	
	await loadPlayerData(user_id, sender_id)

func _on_peer_connected(id):
	print("Peer connected: ", id)
	await get_tree().process_frame
	await get_tree().process_frame
	
	var game_state = Global.get_full_game_state()
	print("Sending game state to peer ", id)
	Global.sync_full_game_state.rpc_id(id, game_state)

func _on_peer_disconnected(id):
	print("Peer disconnected: ", id)
	
	var user_id = uidToUserId.get(str(id))
	if user_id:
		var plr = Global.getPlayer(str(id))
		if plr and plr.moneyValue:
			playerData[user_id]["money"] = plr.moneyValue.Value
			print("Captured money before save: $", plr.moneyValue.Value)
		
		print("Saving data for user_id: ", user_id)
		await savePlayerData(user_id)
		uidToUserId.erase(str(id))
		connectedPlayers.erase(user_id)
	
	for house_id in Global.houses:
		if Global.houses[house_id]["plr"] == str(id):
			Global.houses[house_id]["plr"] = ""
			var house_node = Global.getHouse(house_id)
			if house_node:
				house_node.plrAssigned = ""
			Global.rpc("client_house_assigned", house_id, "")
			break
	
	if str(id) in PlayerManager.players:
		PlayerManager.removePlayer(str(id))

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		await cleanup_server()

func cleanup_server():
	server_running = false
	print("Server shutting down, saving all player data...")
	
	for peer_id in uidToUserId:
		var user_id = uidToUserId[peer_id]
		var plr = Global.getPlayer(peer_id)
		if plr and plr.moneyValue and user_id in playerData:
			playerData[user_id]["money"] = plr.moneyValue.Value
	
	await saveAllPlayerData()
	if heartbeat_timer:
		heartbeat_timer.queue_free()
	if peer:
		peer.close()

func serializeBrainrots(brainrots_dict: Dictionary) -> Dictionary:
	var serialized = {}
	for slot_name in brainrots_dict:
		var slot = brainrots_dict[slot_name]
		serialized[slot_name] = {
			"brainrot": slot.get("brainrot", {"id": "", "UID": "", "generate": 0, "modifiers": {}}).duplicate(true),
			"money": slot.get("money", 0),
			"index": slot.get("index", 0)
		}
	return serialized

func savePlayerData(user_id: int):
	if not user_id in playerData:
		print("No data to save for user_id: ", user_id)
		return false
	
	var peer_id = getUserPeerId(user_id)
	var current_data = playerData[user_id].duplicate(true)
	
	print("Saving player ", user_id, " (peer_id: ", peer_id, ")")
	
	var money_to_save = current_data.get("money", 100)
	
	if peer_id != -1:
		var plr = Global.getPlayer(str(peer_id))
		if plr and plr.moneyValue:
			money_to_save = plr.moneyValue.Value
			print("  Money from player object: $", money_to_save)
		else:
			print("  Money from stored data: $", money_to_save)
	else:
		print("  Money from stored data (player disconnected): $", money_to_save)
	
	if money_to_save < 0:
		money_to_save = 0
		print("  WARNING: Negative money detected, clamping to 0")
	
	current_data["money"] = money_to_save
	
	var house_id = current_data.get("house_id")
	if house_id and house_id in Global.houses:
		var house_node = Global.getHouse(house_id)
		if house_node:
			var serialized_brainrots = serializeBrainrots(house_node.brainrots)
			
			current_data["house_data"] = {
				"brainrots": serialized_brainrots
			}
			
			print("  Saved brainrots with ", serialized_brainrots.size(), " slots")
			for slot_name in serialized_brainrots:
				var slot = serialized_brainrots[slot_name]
				if slot["brainrot"]["id"] != "":
					print("    Slot ", slot_name, ": ", slot["brainrot"]["id"], " ($", slot["money"], ", gen: ", slot["brainrot"]["generate"], ")")
		else:
			print("  ERROR: House node not found for house_id: ", house_id)
	else:
		print("  No house assigned or house_id not in houses")
	
	current_data["last_save"] = Time.get_unix_time_from_system()
	
	if user_id in connectedPlayers:
		var session_time = Time.get_unix_time_from_system() - connectedPlayers[user_id]["connected_at"]
		current_data["total_playtime"] = current_data.get("total_playtime", 0) + session_time
		current_data["last_session_duration"] = session_time
		connectedPlayers[user_id]["connected_at"] = Time.get_unix_time_from_system()
	
	current_data["brainrots_collected"] = current_data.get("brainrots_collected", {})
	current_data["statistics"] = current_data.get("statistics", {
		"sessions_played": 0,
		"total_money_earned": 0,
		"brainrots_grabbed": 0
	})
	
	var key = "player_" + str(user_id)
	var success = await SetAsync(key, current_data)
	if success:
		print("Successfully saved data for user_id: ", user_id, " with money: $", current_data["money"])
		playerData[user_id] = current_data
		return true
	else:
		print("Failed to save player data for user_id: ", user_id)
		return false

func loadPlayerData(user_id: int, peer_id: int):
	var key = "player_" + str(user_id)
	var data = await GetAsync(key)
	
	if data != null:
		var loaded_money = data.get("money", 100)
		var loaded_rebirths = data.get("rebirths", 0)
		
		if loaded_money < 0:
			loaded_money = 100
		
		data["money"] = loaded_money
		playerData[user_id] = data.duplicate(true)
		
		print("Loaded data for user_id: ", user_id)
		print("  Money: $", loaded_money)
		
		var plr = Global.getPlayer(str(peer_id))
		if plr and plr.moneyValue:
			plr.moneyValue.Value = loaded_money
			print("  Set player money to: $", loaded_money)
		
		if plr and plr.rebirthsVal:
			plr.rebirthsVal.Value = loaded_rebirths
			print("  Set player rebirths to: ", loaded_rebirths)
		
		await get_tree().process_frame
		
		var house_id = Global.assignHouse(str(peer_id))
		if house_id:
			playerData[user_id]["house_id"] = house_id
			print("  Assigned house ", house_id)
			
			for i in range(10):
				await get_tree().process_frame
			
			if data.has("house_data") and data["house_data"].has("brainrots"):
				var saved_brainrots = data["house_data"]["brainrots"].duplicate(true)
				var house_node = Global.getHouse(house_id)
				
				if house_node:
					print("  Loading brainrots into house ", house_id)
					
					for slot_name in saved_brainrots:
						if house_node.brainrots.has(slot_name):
							var slot_data = saved_brainrots[slot_name]
							house_node.brainrots[slot_name]["brainrot"] = slot_data.get("brainrot", {"id": "", "UID": "", "generate": 0, "modifiers": {}}).duplicate(true)
							house_node.brainrots[slot_name]["money"] = slot_data.get("money", 0)
							
							var brainrot_id = slot_data["brainrot"]["id"]
							if brainrot_id != "":
								print("    Slot ", slot_name, ": ", brainrot_id, " ($", slot_data["money"], ", gen: ", slot_data["brainrot"]["generate"], ")")
						else:
							printerr("house node has no brainrots key ",slot_name)
					
					Global.houses[house_id]["brainrots"] = house_node.brainrots.duplicate(true)
					
					await get_tree().process_frame
					
					house_node.updateBrainrots(house_node.brainrots)
					house_node.rpc("updateBrainrots", house_node.brainrots)
					
					print("  Brainrots loaded and synced to client")
				else:
					print("  ERROR: House node not found for house_id: ", house_id)
	else:
		print("No saved data for user_id: ", user_id, ", creating new")
		playerData[user_id] = {
			"money": 100,
			"rebirths": 0,
			"total_playtime": 0,
			"last_session_duration": 0,
			"house_id": null,
			"house_data": {"brainrots": {}},
			"brainrots_collected": {},
			"inventory": {},
			"statistics": {
				"sessions_played": 0,
				"total_money_earned": 0,
				"brainrots_grabbed": 0
			},
			"last_save": Time.get_unix_time_from_system()
		}
		
		var plr = Global.getPlayer(str(peer_id))
		if plr and plr.moneyValue:
			plr.moneyValue.Value = 100
		
		var house_id = Global.assignHouse(str(peer_id))
		if house_id:
			playerData[user_id]["house_id"] = house_id

func saveAllPlayerData():
	print("Saving all player data - ", playerData.size(), " players")
	
	for peer_id in uidToUserId:
		var user_id = uidToUserId[peer_id]
		var plr = Global.getPlayer(peer_id)
		if plr and plr.moneyValue and user_id in playerData:
			playerData[user_id]["money"] = plr.moneyValue.Value
	
	for user_id in playerData:
		await savePlayerData(user_id)
	print("All player data saved")

func updatePlayerMoney(peer_uid: String, amount: int):
	var user_id = uidToUserId.get(peer_uid)
	
	if user_id and user_id in playerData:
		var old_money = playerData[user_id].get("money", 0)
		playerData[user_id]["money"] = amount
		updatePlayerActivity(user_id)
		
		if amount > old_money:
			if not playerData[user_id].has("statistics"):
				playerData[user_id]["statistics"] = {}
			playerData[user_id]["statistics"]["total_money_earned"] = playerData[user_id]["statistics"].get("total_money_earned", 0) + (amount - old_money)
		
		var actual_peer_id = getUserPeerId(user_id)
		
		if actual_peer_id != -1:
			var plr = Global.getPlayer(str(actual_peer_id))
			if plr and plr.moneyValue:
				plr.moneyValue.Value = amount

func getPlayerMoney(peer_uid: String) -> int:
	var user_id = uidToUserId.get(peer_uid)
	if user_id and user_id in playerData:
		return playerData[user_id].get("money", 100)
	
	var plr = Global.getPlayer(peer_uid)
	if plr and plr.moneyValue:
		return plr.moneyValue.Value
	
	return 100

func updatePlayerActivity(user_id: int):
	if user_id in connectedPlayers:
		connectedPlayers[user_id]["last_activity"] = Time.get_unix_time_from_system()

func getPlayerByUserId(user_id: int):
	var peer_id = getUserPeerId(user_id)
	if peer_id != -1:
		return Global.getPlayer(str(peer_id))
	return null

func getUserPeerId(user_id: int) -> int:
	for peer_uid in uidToUserId:
		if uidToUserId[peer_uid] == user_id:
			return int(peer_uid)
	return -1

func updatePlayerStatistic(user_id: int, stat_name: String, value):
	if user_id in playerData:
		if not playerData[user_id].has("statistics"):
			playerData[user_id]["statistics"] = {}
		playerData[user_id]["statistics"][stat_name] = value

func addToPlayerInventory(user_id: int, item_id: String, quantity: int = 1):
	if user_id in playerData:
		if not playerData[user_id].has("inventory"):
			playerData[user_id]["inventory"] = {}
		
		if playerData[user_id]["inventory"].has(item_id):
			playerData[user_id]["inventory"][item_id] += quantity
		else:
			playerData[user_id]["inventory"][item_id] = quantity

func grantAchievement(user_id: int, achievement_id: String):
	if user_id in playerData:
		if not playerData[user_id].has("achievements"):
			playerData[user_id]["achievements"] = []
		
		if achievement_id not in playerData[user_id]["achievements"]:
			playerData[user_id]["achievements"].append(achievement_id)

func GetAsync(key: String) -> Variant:
	var data = {
		"key": key,
		"access_key": DATASTORE_password
	}
	
	var get_http = HTTPRequest.new()
	add_child(get_http)
	
	var result = await _make_request(get_http, Global.masterIp + "/datastore/get", data)
	
	if result.code == 200:
		var response = JSON.parse_string(result.body)
		if response and response.has("value"):
			return response.value
	
	return null

func SetAsync(key: String, value: Variant) -> bool:
	var data = {
		"key": key,
		"value": value,
		"access_key": DATASTORE_password
	}
	
	var set_http = HTTPRequest.new()
	add_child(set_http)
	
	var result = await _make_request(set_http, Global.masterIp + "/datastore/set", data)
	
	return result.code == 200

func RemoveAsync(key: String) -> bool:
	var data = {
		"key": key,
		"access_key": DATASTORE_password
	}
	
	var remove_http = HTTPRequest.new()
	add_child(remove_http)
	
	var result = await _make_request(remove_http, Global.masterIp + "/datastore/remove", data)
	
	return result.code == 200

func UpdateAsync(key: String, transformFunction: Callable) -> Variant:
	var current_value = await GetAsync(key)
	var new_value = transformFunction.call(current_value)
	
	if new_value != null:
		var success = await SetAsync(key, new_value)
		if success:
			return new_value
	
	return null

func IncrementAsync(key: String, delta: int) -> int:
	var current_value = await GetAsync(key)
	var current_int = 0
	
	if current_value is int or current_value is float:
		current_int = int(current_value)
	
	var new_value = current_int + delta
	var success = await SetAsync(key, new_value)
	
	if success:
		return new_value
	else:
		return current_int

func ListKeysAsync() -> Array:
	var data = {}
	
	var list_http = HTTPRequest.new()
	add_child(list_http)
	
	var result = await _make_request(list_http, Global.masterIp + "/datastore/list_keys", data)
	
	if result.code == 200:
		var response = JSON.parse_string(result.body)
		if response and response.has("keys"):
			return response.keys
	
	return []

func _make_request(http_request: HTTPRequest, url: String, data: Dictionary) -> Dictionary:
	var promise = {}
	promise.completed = false
	promise.code = 0
	promise.body = ""
	
	http_request.request_completed.connect(func(result, code, headers, body):
		promise.completed = true
		promise.code = code
		promise.body = body.get_string_from_utf8()
		http_request.queue_free()
	)
	
	var err = http_request.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(data)
	)
	
	if err != OK:
		http_request.queue_free()
		promise.code = 0
		promise.completed = true
		return promise
	
	while not promise.completed:
		await get_tree().process_frame
	
	return promise
