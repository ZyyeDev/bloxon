extends Node

var isClient = true
var UID = ""
var user_id = 0
var token = ""
var username = ""

var brainrotTypes = [
	"noobini pizzanini",  
	"lirilì larilà",
	"chimpanzini bananini",
	"Svinina Bombardino",
]

var RARITIES = {
	COMMON = 0,
	RARE = 1,
	EPIC = 2,
	LEGENDARY = 3,
	MYTHIC = 4
}
var RARITIES_PERCENT = {
	0 : 80,
	1 : 70,
	2 : 50,
	3 : 30,
	4 : 10
}

var avatarData = {}
var player_money = 0
var canSave = false
var currentServer = "test"
var houses = {}
var brainrots = {}

var noportIp = "92.176.163.239"
var masterIp = "http://"+noportIp+":8080"
var localPlayer = null
var currentInvSelect = -1

var ERROR_CODES = {
	SERVER_REACH = 50,
	CANT_REACH = 100,
	DISCONNECT = 101,
	TIMEOUT = 800,
	CORRUPTED_FILES = -555
}
var alrHasError = false

func _ready() -> void:
	if Engine.is_editor_hint(): isClient = true
	if isClient:
		startClient()
	else:
		startServer()
	initializeHouses()

func saveLocal():
	if !canSave: return
	var data = {
		"user_id": user_id,
		"token": token,
		"username": username,
	}
	LocalData.saveData("data.dat",data)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if isClient:
			saveLocal()

func startClient():
	set_process(true)

func _process_client(delta):
	pass 

func tryGrab(brainrotUID):
	if isClient:
		print("Client trying to grab: ", brainrotUID, " with UID: ", UID)
		if multiplayer.has_multiplayer_peer():
			rpc_id(1, "server_try_grab", brainrotUID, UID)

func startServer():
	set_process(true)
	spawnBrainrotLoop()

func _process_server(delta):
	pass

func initializeHouses():
	for i in range(1, 8):
		addHouse(i)

func addHouse(id):
	houses[id] = {"plr": "", "brainrots": {}}

func assignHouse(playerUID):
	if !isClient:
		for house_id in houses:
			if houses[house_id]["plr"] == "" or houses[house_id]["plr"] == playerUID:
				if houses[house_id]["plr"] == playerUID:
					print("Player ", playerUID, " already has house ", house_id)
					return house_id
				
				houses[house_id]["plr"] = playerUID
				var house_node = getHouse(house_id)
				if house_node:
					house_node.plrAssigned = playerUID
				print("Assigned house ", house_id, " to player ", playerUID)
				rpc("client_house_assigned", house_id, playerUID)
				return house_id
		print("No available houses for player ", playerUID)
		return null

func getHouse(id):
	if not Game.workspace or not Game.workspace.has_node("NavigationRegion3D"):
		return null
	var houses_container = Game.workspace.get_node("NavigationRegion3D").get_node("houses")
	if not houses_container:
		return null
	for i in houses_container.get_children():
		if i.id == int(id):
			return i
	return null

func whatHousePlr(PUID):
	for i in houses:
		if houses[i]["plr"] == str(PUID):
			return {"id": i, "ref": getHouse(i)}
	return null

func whatHouseIm():
	return whatHousePlr(UID)

func spawnBrainrotLoop():
	if isClient:
		return
	var timer = Timer.new()
	timer.autostart = true
	timer.wait_time = 1.5
	timer.timeout.connect(func():
		spawnBrainrot()
		)
	add_child(timer)
	print("Brainrot spawn loop started")

func getRandomBrainrot():
	var tries = 0
	while true:
		var brainrot = brainrotTypes[randi_range(0,brainrotTypes.size()-1)]
		var temp = load("res://brainrots/"+brainrot+".tscn").instantiate()
		if randi_range(0,100) <= RARITIES_PERCENT[temp.rarity]:
			return brainrot
		if tries >= 10:
			return brainrot
		tries += 1

@rpc("authority", "call_remote", "reliable")
func spawnBrainrot(brUID="", brData={}): 
	if not Game or not Game.workspace:
		print("No workspace available")
		return
		
	if not Game.workspace.has_node("brainrots"):
		print("No brainrots container found")
		return
		
	if not Game.workspace.has_node("bspawn"):
		print("No bspawn found")
		return 
	
	if !brData.is_empty():
		if not brData.has("target_position"):
			printerr("no target pos 🤪🤪")
			return
		
		if brData.has("position") and brData.has("target_position"):
			if brData["position"].y <= brData["target_position"].y-1:
				printerr("Cannot spawn on here!")
				return
	
	# HACK: Invalid operands 'Dictionary' and 'String' in operator '=='.
	# idc what the error is, this just fixes it, fuck you
	if typeof(brUID) == TYPE_DICTIONARY:
		return
	
	var is_new_spawn = false
	if brUID == "":
		brUID = str(Time.get_unix_time_from_system()) + str(randi())
		is_new_spawn = true
	
	if brUID in brainrots:
		print("Brainrot already exists: ", brUID)
		return
	
	var randomBrainrot = brData.get("bName", getRandomBrainrot())
	var loaded = load("res://brainrots/"+randomBrainrot+".tscn")
	if not loaded:
		print("[ERROR]: Uhhhhh, loaded brainrot is null?? random brainrot was: ",randomBrainrot, " and path is ","res://brainrots/"+randomBrainrot+".tscn")
		return
	var brainrot = loaded.instantiate()
	brainrot.UID = brUID
	Game.workspace.get_node("brainrots").add_child(brainrot)
	
	if brData.has("position"):
		brainrot.global_position = brData.position
	else:
		brainrot.global_position = Game.workspace.get_node("bspawn").global_position
	
	if brData.has("cost"):
		brainrot.cost = brData.cost
	if brData.has("pGet"):
		brainrot.pGet = brData.pGet
	if brData.has("target_position") and brData.has("has_target"):
		brainrot.target_position = brData.target_position
		brainrot.has_target = brData.has_target
	
	brainrots[brUID] = brainrot 
	
	if !isClient:
		if is_new_spawn:
			await get_tree().process_frame
		
		var sync_data = {
			"bName": brainrot.bName,
			"position": brainrot.global_position,
			"cost": brainrot.cost,
			"pGet": brainrot.pGet,
			"target_position": brainrot.target_position,
			"has_target": brainrot.has_target
		}
		rpc("spawnBrainrot", brUID, sync_data)
		
		if brainrot.pGet != "" and brUID in brainrots:
			brainrot.rpc("updatePlayerTarget", brainrot.pGet)

@rpc("any_peer", "call_remote", "reliable")
func server_try_grab(brUID, pUID):
	if !isClient and brUID in brainrots and brainrots[brUID]:
		var br = brainrots[brUID]
		
		if br.pGet != "":
			print("Brainrot already grabbed by: ", br.pGet)
		
		var plr = getPlayer(pUID)
		
		if plr and br.cost <= plr.moneyValue.Value:
			plr.moneyValue.Value -= br.cost
			
			br.cost = int(br.cost * 1.5)
			
			br.pGet = str(pUID)
			
			var player_house = whatHousePlr(str(pUID))
			if player_house and player_house.ref and player_house.ref.plrSpawn:
				br.set_target_position(player_house.ref.plrSpawn.global_position)
			
			br.rpc("updatePlayerTarget", str(pUID))
			br.rpc("updateCost", br.cost)
			
			rpc("updateBrainrotPosition", brUID, br.global_position, br.target_position, br.has_target, br.pGet)
			
			if get_parent().has_node("Server"):
				var server = get_parent().get_node("Server")
				server.updatePlayerMoney(pUID, plr.moneyValue.Value)
				var user_id = server.uidToUserId.get(pUID)
				if user_id:
					server.updatePlayerStatistic(user_id, "brainrots_grabbed", server.playerData[user_id].get("statistics", {}).get("brainrots_grabbed", 0) + 1)
		else:
			if !plr:
				print("Player not found for UID: ", pUID)
			elif br.cost > plr.moneyValue.Value:
				print("Player cannot afford brainrot - Cost: ", br.cost, " Money: ", plr.moneyValue.Value)

@rpc("authority", "call_remote", "reliable") 
func client_house_assigned(house_id, player_uid):
	houses[house_id] = {"plr": player_uid, "brainrots": {}}
	var house_node = getHouse(house_id)
	if house_node:
		house_node.plrAssigned = player_uid
	if player_uid == UID:
		print("Client: Assigned to house ", house_id)

func brainrotCollected(brUID, ref, pUID):
	if !isClient:
		if brUID in brainrots:
			brainrots.erase(brUID)
		var bname = ref.bName
		ref.queue_free()
		rpc("remove_brainrot", brUID)
		
		var player_house = whatHousePlr(pUID)
		if player_house:
			var house_node = getHouse(player_house.id)
			if house_node:
				house_node.collectBrainrot(bname)
				if player_house.id in houses:
					houses[player_house.id]["brainrots"] = house_node.brainrots
				
				if get_parent().has_node("Server"):
					var server = get_parent().get_node("Server")
					var user_id = server.uidToUserId.get(pUID)
					if user_id and user_id in server.playerData:
						if not server.playerData[user_id].has("brainrots_collected"):
							server.playerData[user_id]["brainrots_collected"] = {}
						
						var collected = server.playerData[user_id]["brainrots_collected"]
						if collected.has(bname):
							collected[bname] += 1
						else:
							collected[bname] = 1
						
						server.updatePlayerActivity(user_id)

@rpc("authority", "call_remote", "reliable")
func remove_brainrot(brUID):
	if brUID in brainrots and brainrots[brUID]:
		brainrots[brUID].queue_free()
		brainrots.erase(brUID)

func wait(num):
	return await get_tree().create_timer(num).timeout

func on_player_connected():
	pass

@rpc("any_peer", "call_remote", "unreliable")
func updateBrainrotPosition(SUID, pos, target_pos, has_target_flag, pget):
	if not Game or not Game.workspace: 
		return
	
	var brainrot = null
	for i in Game.workspace.get_node("brainrots").get_children():
		if i.UID == SUID:
			brainrot = i
			break
	
	if brainrot:
		brainrot.global_position = pos
		brainrot.target_position = target_pos
		brainrot.has_target = has_target_flag
		brainrot.pGet = pget

func sendBrainrotPos(BUID, global_transform, global_position):
	var brainrot = brainrots.get(BUID)
	if brainrot:
		rpc("updateBrainrotPosition", BUID, global_position, brainrot.target_position, brainrot.has_target, brainrot.pGet)

func fromStud(studs):
	return studs*0.28

func toStud(num):
	return num/0.28

var defaultLeavePressed = func(): return "NOTBINDED"

func errorMessage(
	primaryMsg,
	errorCode,
	dialogTitle: String = "Disconnected",
	leaveText: String = "Leave",
	leavePressed: Callable = defaultLeavePressed
):
	if alrHasError:
		return
	alrHasError = true
	
	var box = load("res://scenes/ErrorBox.tscn").instantiate()
	box.primaryMsg = primaryMsg
	box.errorCode = "Error Code: " + str(errorCode)
	box.btnText = leaveText
	box.dialogTitle = dialogTitle
	
	if leavePressed != defaultLeavePressed:
		box.binded = true
		box.leavePressed.connect(leavePressed)
		
	get_tree().current_scene.add_child(box)
	return box

func getAllServers():
	var json_data = {"token": Global.token}
	var json_string = JSON.stringify(json_data)
	var headers = ["Content-Type: application/json"]
	
	print("Updating servers...")
	
	var sHttp = HTTPRequest.new()
	add_child(sHttp)
	sHttp.request_completed.connect(func(result, code, headers, body):
		var response_text = body.get_string_from_utf8()
		print("Response code: ", code, " Body: ", response_text)
		
		if code != 200:
			print("Failed to get server info, code: ", code)
			return
			
		var data = JSON.parse_string(response_text)
		if data == null:
			print("Failed to parse response")
			return
		if data.has("servers"):
			Client.servers = data["servers"]
			Client.serverlist_update.emit())
	sHttp.request(
		Global.masterIp + "/ping_all_servers",
		headers,
		HTTPClient.METHOD_POST,
		json_string
	)

@rpc("authority", "call_remote", "reliable")
func sync_full_game_state(game_state):
	print("Syncing full game state: ", game_state)
	
	houses = game_state.houses.duplicate(true)
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	for house_id in houses:
		var house_node = getHouse(house_id)
		if house_node and houses[house_id].has("plr"):
			house_node.plrAssigned = houses[house_id]["plr"]
			if houses[house_id].has("brainrots"):
				house_node.updateBrainrots(houses[house_id]["brainrots"])
	
	for brUID in game_state.brainrots:
		if brUID in brainrots:
			continue
		var br_data = game_state.brainrots[brUID]
		spawnBrainrot(brUID, br_data)
		await get_tree().process_frame

@rpc("any_peer","call_remote","reliable")
func collectMoney(pUID, index):
	if isClient:
		return
		
	var phouse_data = whatHousePlr(pUID)
	if not phouse_data:
		print("Player house not found for UID: ", pUID)
		return
	
	var phouse = phouse_data.ref
	if not phouse:
		print("Player house ref not found for UID: ", pUID)
		return
	
	var money_collected = 0
	var updated_brainrots = phouse.brainrots.duplicate(true)
	
	for slot_name in updated_brainrots:
		var slot = updated_brainrots[slot_name]
		if slot["index"] == index:
			money_collected = slot["money"]
			
			if money_collected > 0:
				updated_brainrots[slot_name]["money"] = 0
				
				var plr = getPlayer(pUID)
				if plr:
					plr.moneyValue.Value += money_collected
					print("Player ", pUID, " collected $", money_collected, " - New total: $", plr.moneyValue.Value)
					
					phouse.brainrots = updated_brainrots
					houses[phouse_data.id]["brainrots"] = updated_brainrots
					phouse.rpc("syncMoney", updated_brainrots)
					
					if get_parent().has_node("Server"):
						var server = get_parent().get_node("Server")
						server.updatePlayerMoney(pUID, plr.moneyValue.Value)
						var user_id = server.uidToUserId.get(pUID)
						if user_id:
							server.updatePlayerActivity(user_id)
				else:
					print("Player not found for UID: ", pUID)
			break

func getPlayer(pUID):
	if not Game or not Game.workspace or not Game.workspace.playersContainer:
		print("Cannot get player, missing game components")
		return null
		
	for i in Game.workspace.playersContainer.get_children():
		if str(i.uid) == str(pUID):
			return i
	print("Player not found with UID: ", pUID)
	return null

func get_full_game_state():
	var game_state = {
		"houses": {},
		"brainrots": {}
	}
	
	for house_id in houses:
		var house_node = Global.getHouse(house_id)
		
		var house_brainrots = {}
		if house_node and house_node.brainrots:
			house_brainrots = house_node.brainrots.duplicate(true)
		else:
			house_brainrots = houses[house_id].get("brainrots", {}).duplicate(true)
		
		for slot_name in house_brainrots:
			if house_brainrots[slot_name].has("ref"):
				house_brainrots[slot_name].erase("ref")
			if house_brainrots[slot_name].has("brRef"):
				house_brainrots[slot_name].erase("brRef")
			if house_brainrots[slot_name].has("moneyLabel"):
				house_brainrots[slot_name].erase("moneyLabel")
		
		game_state.houses[house_id] = {
			"plr": houses[house_id]["plr"],
			"brainrots": house_brainrots
		}
		
		if house_node:
			game_state.houses[house_id]["position"] = house_node.global_position
			game_state.houses[house_id]["rotation"] = house_node.global_rotation
	
	for brUID in brainrots:
		if brainrots[brUID]:
			var br = brainrots[brUID]
			game_state.brainrots[brUID] = {
				"position": br.global_position,
				"target_position": br.target_position,
				"has_target": br.has_target,
				"pGet": br.pGet,
				"cost": br.cost,
				"bName": br.bName
			}
	
	return game_state

@rpc("any_peer","call_remote","reliable")
func sendChatMessage(message: String, senderUID: String, senderToken: String):
	var sender_peer_id = multiplayer.get_remote_sender_id()
	
	if !isClient:
		if senderToken != "SERVER":
			var expected_uid = str(sender_peer_id)
			if senderUID != expected_uid:
				print("Chat message rejected: UID mismatch")
				return
			
			if get_parent().has_node("Server"):
				var server = get_parent().get_node("Server")
				var user_id = server.uidToUserId.get(senderUID)
				if not user_id:
					print("Chat message rejected: Invalid user")
					return
		
		message = message.substr(0, 200)
		message = message.strip_edges()
		
		if message.length() == 0:
			return
		
		rpc("receiveChatMessage", message, senderUID)

@rpc("authority", "call_remote", "reliable")
func receiveChatMessage(message: String, senderUID: String):
	if isClient:
		var player = getPlayer(senderUID)
		var username = "Player"
		if player:
			username = player.name
			player.addBubbleBox(message)
		
		if CoreGui and CoreGui.has_method("addChatMessage"):
			CoreGui.addChatMessage(username, message)
		
		print("[CHAT] ", username, ": ", message)

@rpc("any_peer","call_remote","reliable")
func changeHoldingItem(itemId,myId,mytoken):
	var sender = multiplayer.get_remote_sender_id()
	if !isClient:
		for i in Server.playerData:
			if Server.playerData[i].get("inventory", {}).has(str(itemId)) or itemId == -1:
				if get_parent().has_node("Server"):
					var server = get_parent().get_node("Server")
					server.playerData[server.uidToUserId[str(sender)]]["holdingItem"] = itemId
				rpc_id(sender,"changeHoldingItem",itemId,myId,"SERVER-"+Server.uid)
	else:
		if mytoken == token:
			if localPlayer:
				localPlayer.toolHolding = itemId
		elif "SERVER" in mytoken:
			var player = getPlayer(myId)
			if player:
				player.toolHolding = itemId

@rpc("any_peer")
func rebirth():
	var sender = multiplayer.get_remote_sender_id()
	var plr = getPlayer(sender)
	
	plr.rebirthsVal.Value += 1
