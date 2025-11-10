extends Node

var CLIENT_VERSION = "1.0.0"

var isClient = true
var UID = ""
var user_id = 0
var token = ""
var username = ""

var currentProximityPrompt = null

var volume = 9
var graphics = 9

var currentInventory = {}

var allPlayers = {}

var brainrotTypes = [
	"noobini pizzanini",  
	"lirilì larilà",
	"Svinina Bombardino",
	"chimpanzini bananini",
	"Trippi Troppi",
	"Gangster Footera",
	"Boneca Ambalabu",
	"Chef Crabracadabra",
	"Brr Brr Patapim"
]

var rebirths = {
	1: {
		"need": [
			{
				"what": 1000000,
				"type": "money"
			},
			{
				"what": "Trippi Troppi",
				"type": "brainrot"
			},
			{
				"what": "Gangster Footera",
				"type": "brainrot"
			},
		],
		"get": [
			{
				"what": 5000,
				"type": "money"
			},
			{
				"what": 10,
				"type": "lockBase"
			},
			{
				"what": 2,
				"type": "tool",
			},
			{
				"what": 3,
				"type": "tool",
			},
		]
	},
	2: {
		"need": [
			{
				"what": 3000000,
				"type": "money"
			},
			{
				"what": "Brr Brr Patapim",
				"type": "brainrot"
			},
			{
				"what": "Boneca Ambalabu",
				"type": "brainrot"
			},
		],
		"get": [
			{
				"what": 10000,
				"type": "money"
			},
			{
				"what": 10,
				"type": "lockBase"
			},
			{
				"what": 1,
				"type": "slot"
			},
			{
				"what": "Gold Slap",
				"type": "tool"
			},
			{
				"what": "Coil Combo",
				"type": "tool"
			},
			{
				"what": "Rage Table",
				"type": "tool"
			},
		]
	},
	3: {
		"need": [
			{
				"what": 12500000,
				"type": "money"
			},
			{
				"what": "Trulimero Trulicina",
				"type": "brainrot"
			},
			{
				"what": "Chimpanzini Bananini",
				"type": "brainrot"
			},
		],
		"get": [
			{
				"what": 25000,
				"type": "money"
			},
			{
				"what": 10,
				"type": "lockBase"
			},
			{
				"what": 1,
				"type": "slot"
			},
			{
				"what": "Diamond Slap",
				"type": "tool"
			},
		]
	},
}

var RARITIES = {
	COMMON = 0,
	RARE = 1,
	EPIC = 2,
	LEGENDARY = 3,
	MYTHIC = 4
}
var RARITIES_PERCENT = {
	0 : 100,
	1 : 40,
	2 : 20,
	3 : 8,
	4 : 3
}

var RARITIES_STRING = {
	0 : "COMMON",
	1 : "RARE",
	2 : "EPIC",
	3 : "LEGENDARY",
	4 : "MYTHIC",
}

var avatarData = {}
var player_money = 0
var canSave = false
var currentServer = "test"
var houses = {}
var brainrots = {}

var noportIp = "46.224.26.214"
var port = ":8080"
var masterIp = "http://"+noportIp+port
var localPlayer:player = null
var currentInvSelect = -1

var myPlrData = {}

signal myPlrDataUpdate
signal allPlayersUpdate

var ERROR_CODES = {
	MAINTENANCE = 49,
	SERVER_REACH = 50,
	CANT_REACH = 100,
	DISCONNECT = 101,
	TIMEOUT = 800,
	CORRUPTED_FILES = -555,
}
var alrHasError = false

func _ready() -> void:
	if ".onrender.com" in masterIp:
		masterIp = masterIp.replace("http://","https://")
	var args = OS.get_cmdline_args()
	if "--pfp-render" in args:
		print("Pfp rendering")
		get_tree().change_scene_to_file("res://scenes/avatar_rendering.tscn")
		return
	if "--server" in args or OS.has_feature("dedicated_server"):
		isClient = false
		print("Running as SERVER")
	else:
		isClient = true
		print("Running as CLIENT")
		await checkVersionBeforeStart()
	if isClient:
		for i in 9:
			currentInventory[i] = -1
		startClient()
	else:
		startServer()
	initializeHouses()

func checkVersionBeforeStart():
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"version": CLIENT_VERSION
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(masterIp + "/check_version", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 426:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		if jsonResponse:
			errorMessage(
				"Update Required",
				ERROR_CODES.CORRUPTED_FILES,
				"Version Mismatch",
				"Exit",
				func(): get_tree().quit()
			)
			await get_tree().create_timer(999999).timeout

func saveLocal():
	if !canSave: return
	var data = {
		"user_id": user_id,
		"token": token,
		"username": username,
		"volume" : volume,
		"graphics": graphics,
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
					print("WARNING: Player ", playerUID, " trying to get house ", house_id, " but already assigned!")
					
					var is_actually_connected = false
					if get_parent().has_node("Server"):
						var server = get_parent().get_node("Server")
						if str(playerUID) in server.uidToUserId:
							is_actually_connected = true
					
					if not is_actually_connected:
						print("Player not actually connected, reassigning house ", house_id)
						houses[house_id]["plr"] = ""
						var house_node = getHouse(house_id)
						if house_node:
							house_node.plrAssigned = ""
							house_node.locked = false
					else:
						return house_id
				
				if houses[house_id]["plr"] == "":
					houses[house_id]["plr"] = playerUID
					var house_node = getHouse(house_id)
					if house_node:
						house_node.plrAssigned = playerUID
						house_node.locked = false
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
		if Server.inMaintenance:
			return
		spawnBrainrot()
		)
	add_child(timer)
	print("Brainrot spawn loop started")

func getRandomBrainrot():
	var weighted_list = []
	
	for brainrot in brainrotTypes:
		var temp = load("res://brainrots/" + brainrot + ".tscn").instantiate()
		var percent = RARITIES_PERCENT[temp.rarity]
		
		if temp.chanceOverride != -1:
			percent = temp.chanceOverride
		
		for i in range(percent):
			weighted_list.append(brainrot)
		
		temp.queue_free()
	
	if weighted_list.is_empty():
		return "noobini pizzanini"
	
	return weighted_list[randi() % weighted_list.size()]

@rpc("authority", "call_remote", "reliable")
func spawnBrainrot(brUID="", brData={}): 
	if Server.inMaintenance:
		return
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
			printerr("no target pos")
			return
		
		if brData.has("position") and brData.has("target_position"):
			if brData["position"].y <= brData["target_position"].y-1:
				printerr("Cannot spawn on here!")
				return
	
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
	
	Game.workspace.get_node("brainrots").call_deferred("add_child", brainrot)
	
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
		
		var plr = getPlayer(pUID)
		
		if not whatHousePlr(pUID).ref.getAvailableSpace():
			return
		
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
				var user_id = int(server.uidToUserId.get(pUID))
				if user_id:
					server.updatePlayerStatistic(user_id, "brainrots_grabbed", server.playerData[user_id].get("statistics", {}).get("brainrots_grabbed", 0) + 1)
			
			plr.rpc("syncMoney", plr.moneyValue.Value)
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
					var user_id = int(server.uidToUserId.get(pUID))
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
		box.leavePressed.connect(func():
			var snd = AudioStreamPlayer.new()
			snd.stream = load("uid://vwx7j0muuk3a")
			snd.volume_db = -12.5
			add_child(snd)
			snd.play()
			)
	
	CoreGui.add_child(box)
	return box

func getAllServers():
	var json_data = {"token": Global.token}
	var json_string = JSON.stringify(json_data)
	var headers = ["Content-Type: application/json"]
	
	var sHttp = HTTPRequest.new()
	add_child(sHttp)
	sHttp.request_completed.connect(func(result, code, headers, body):
		var response_text = body.get_string_from_utf8()
		
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
					
					phouse.brainrots = updated_brainrots
					houses[phouse_data.id]["brainrots"] = updated_brainrots
					phouse.rpc("syncMoney", updated_brainrots)
					
					if get_parent().has_node("Server"):
						var server = get_parent().get_node("Server")
						server.updatePlayerMoney(pUID, plr.moneyValue.Value)
						var user_id = int(server.uidToUserId.get(pUID))
						if user_id:
							server.updatePlayerActivity(user_id)
					
					plr.rpc("syncMoney", plr.moneyValue.Value)
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
			
			var plr = getPlayer(senderUID)
			if not plr:
				print("Chat message rejected: Player not found")
				return
			
			if get_parent().has_node("Server"):
				var server = get_parent().get_node("Server")
				var moderated = await server.moderation(message)
				var data = moderated
				print("moderated ",moderated)
				print(data)
				
				if not data.is_empty():
					var flagged = false
					for v in data:
						var howMuch = data[v]
						if float(howMuch) > .6:
							flagged = true
					if flagged:
						var msgLength =  message.length()
						message = ""
						for i in range(msgLength):
							message = message+"#"
				
				var user_id = int(server.uidToUserId.get(senderUID))
				
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
		var plr = getPlayer(senderUID)
		var username = allPlayers[senderUID].get("username", "Unknown")
		if plr:
			plr.addBubbleBox(message)
		
		CoreGui.addChatMessage(username, message)
		
		print("[CHAT] ", username, ": ", message)

@rpc("any_peer", "call_remote", "reliable")
func changeHoldingItem(invId, itemId, myId, mytoken):
	var sender = multiplayer.get_remote_sender_id()
	if !isClient:
		if get_parent().has_node("Server"):
			var server = get_parent().get_node("Server")
			var user_id = int(server.uidToUserId.get(str(sender)))
			
			if user_id:
				if invId == -1:
					rpc("syncHoldingItem", str(sender), -1, -1)
					syncHoldingItem(str(sender), -1, -1)
					
					var plr = getPlayer(str(sender))
					if plr:
						plr.toolHolding = -1
						plr.currentSlot = -1
					return
				
				if invId >= 0 and invId < 9:
					var tools_for_rebirth = getToolsForRebirth(server.playerData[user_id].get("rebirths", 0))
					
					if invId < tools_for_rebirth.size():
						var expected_item_id = tools_for_rebirth[invId]
						
						if expected_item_id == itemId or itemId == -1:
							rpc("syncHoldingItem", str(sender), invId, itemId)
							syncHoldingItem(str(sender), invId, itemId)
							
							var plr = getPlayer(str(sender))
							if plr:
								plr.toolHolding = itemId
								plr.currentSlot = invId
						else:
							print("Player tried to equip item ", itemId, " from slot ", invId, " but expected ", expected_item_id)
					else:
						print("Player tried to equip from invalid slot ", invId, " with rebirth level ", server.playerData[user_id].get("rebirths", 0))
		else:
			printerr("server dont have server script???")
	else:
		printerr("cant call from client!")

@rpc("any_peer", "call_remote", "reliable")
func giveItemToPlayer(pUID: String, itemId: int, pToken: String):
	pass

func giveRebirthTools(pUID: String, rebirthLevel: int):
	if isClient: return
	
	if get_parent().has_node("Server"):
		var server = get_parent().get_node("Server")
		var user_id = int(server.uidToUserId.get(pUID))
		
		if user_id and server.playerData.has(user_id):
			var player = getPlayer(pUID)
			if player:
				var inventory_data = {}
				var tools = getToolsForRebirth(rebirthLevel)
				
				for i in 9:
					if i < tools.size():
						inventory_data[i] = tools[i]
					else:
						inventory_data[i] = -1
				
				player.rpc("syncInventory", inventory_data)
				print("Gave rebirth tools to player ", pUID, ": ", inventory_data)

@rpc("authority", "call_remote", "reliable")
func syncHoldingItem(pUID: String, invId, itemId: int):
	var plr = getPlayer(pUID)
	if plr:
		print("synced Holding Item ", pUID, itemId)
		plr.toolHolding = itemId
		plr.currentSlot = invId
	else:
		printerr("PLAYER IS NULL FROM SYNC HOLDING ITEM")

@rpc("any_peer")
func rebirth(token): 
	var sender = multiplayer.get_remote_sender_id() 
	var plr:player = getPlayer(sender) 
	var phouse:house = whatHousePlr(sender).ref 
	var brainrots = phouse.brainrots 
	
	if plr.rebirthsVal.Value+1 not in rebirths:
		return
	
	var rebirthData = rebirths[plr.rebirthsVal.Value+1]
	
	if rebirthData == null:
		return
	
	if not "need" in rebirthData:
		return
	
	var brainrotsNeeded = {} 
	var hasMoney = false 
	
	for i in rebirthData.need:
		if i.type == "money": 
			if plr.moneyValue.Value >= i.what: 
				hasMoney = true
		elif i.type == "brainrot":
			brainrotsNeeded[i.what] = false
			for v in phouse.brainrots: 
				var brainrot = phouse.brainrots[v]["brainrot"]
				if brainrot.id == i.what:
					brainrotsNeeded[i.what] = true
	
	var brainrotHas = 0 
	
	for i in brainrotsNeeded: 
		if brainrotsNeeded[i] == true: brainrotHas += 1 
	
	if hasMoney and brainrotHas == brainrotsNeeded.size(): 
		var moneyGet = 0 
		for i in rebirthData.get: 
			if i.type == "money": 
				moneyGet += i.what
				break 
		plr.moneyValue.Value = moneyGet
		
		for i in phouse.brainrots:
			phouse.removeBrainrot(i) 
		
		plr.rebirthsVal.Value += 1
		
		if get_parent().has_node("Server"):
			var server = get_parent().get_node("Server")
			var user_id = int(server.uidToUserId.get(str(sender)))
			if user_id and server.playerData.has(user_id):
				server.playerData[user_id]["rebirths"] = plr.rebirthsVal.Value
				server.playerData[user_id]["money"] = plr.moneyValue.Value
				server.updatePlayerMoney(str(sender), plr.moneyValue.Value)
		
		giveRebirthTools(str(sender), plr.rebirthsVal.Value)
		plr.rpc("syncMoney", plr.moneyValue.Value)

func getToolsForRebirth(rebirthLevel: int) -> Array:
	if rebirthLevel <= 0:
		return [1]
	elif rebirthLevel == 1:
		return [1, 2, 3]
	elif rebirthLevel == 2:
		return [1, 2, 3, 4]
	else:
		return [1, 2, 3, 4]

@rpc("any_peer")
func trySteal(slot_name, plruid):
	var peer_id = multiplayer.get_remote_sender_id()
	
	if !isClient:
		var phouse:house = whatHousePlr(plruid).ref
		var houseOwner:player = getPlayer(plruid)
		var actionPlayer:player = getPlayer(peer_id)
		var actionPlrHouse = whatHousePlr(peer_id)
		
		print("trySteal called - Slot: ", slot_name, " | House Owner: ", plruid, " | Action Player: ", peer_id)
		print("phouse exists: ", phouse != null)
		print("brainrots dict: ", phouse.brainrots if phouse else "null")
		
		if !phouse:
			print("ERROR: phouse is null")
			return
			
		if !phouse.brainrots.has(slot_name):
			print("ERROR: Invalid slot name: ", slot_name)
			return
		
		print("Slot data: ", phouse.brainrots[slot_name])
		
		if phouse.brainrots[slot_name]["brainrot"]["id"] == "":
			print("ERROR: No brainrot in slot: ", slot_name)
			return
		
		var buid = phouse.brainrots[slot_name]["brainrot"]["UID"]
		var brainrot_id = phouse.brainrots[slot_name]["brainrot"]["id"]
		var slot_index = phouse.brainrots[slot_name]["index"]
		
		print("Loading brainrot scene: ", brainrot_id)
		var temp = load("res://brainrots/%s.tscn" % brainrot_id).instantiate()
		var bcost = temp.cost
		var bgenerate = temp.generate
		var brarity = temp.rarity
		temp.queue_free()
		temp = null
		
		print("Brainrot loaded - cost: ", bcost, " | generate: ", bgenerate)
		print("Comparing peer_id (", peer_id, " type:", typeof(peer_id), ") with plruid (", plruid, " type:", typeof(plruid), ")")
		print("Are they equal? ", str(peer_id) == str(plruid))
		
		if str(peer_id) == str(plruid):
			print("Player selling brainrot for: $", int(round(bcost * 0.10)))
			print("houseOwner exists: ", houseOwner != null)
			if houseOwner:
				print("Adding money to player, current value: ", houseOwner.moneyValue.Value)
				houseOwner.moneyValue.Value += int(round(bcost * 0.10))
				print("New money value: ", houseOwner.moneyValue.Value)
				
				if get_parent().has_node("Server"):
					var server = get_parent().get_node("Server")
					server.updatePlayerMoney(str(peer_id), houseOwner.moneyValue.Value)
			
			print("Calling removeBrainrot on slot: ", slot_name)
			phouse.removeBrainrot(slot_name)
			print("removeBrainrot completed")
		else:
			print("Player ", peer_id, " attempting to steal from house owned by ", plruid)
			print("actionPlayer exists: ", actionPlayer != null)
			if actionPlayer:
				phouse.rpc("updateBrainrotStealing", true, slot_name)
				actionPlayer.rpc("changeBrainrotHolding", brainrot_id)
				actionPlayer.stealingSlot.Value = slot_index
				actionPlayer.whoImStealing.Value = int(plruid)
				print("Steal initiated - Brainrot: ", brainrot_id, " | Slot name: ", slot_name, " | Slot index: ", slot_index)

func server_give_item(pUID: String, itemId: int, quantity: int = 1):
	pass

@rpc("authority","call_remote","reliable")
func updateMyPlrData(npdata):
	myPlrDataUpdate.emit()
	myPlrData = npdata

@rpc("authority", "call_remote", "reliable")
func updateAllPlayers(players_data):
	allPlayers = players_data
	allPlayersUpdate.emit()

@rpc("authority", "call_remote", "reliable")
func register_sound(path_to_node: NodePath, stream_sound_path: String, volume: float, playing: bool, position: Vector3):
	print(path_to_node)
	
	var sound = Sound.new()
	sound.volume_db = volume
	
	var stream = load(stream_sound_path)
	if stream:
		sound.stream = stream
	else:
		push_error("Failed to load AudioStream: " + stream_sound_path)
		
	var parent_node = get_node_or_null(path_to_node)
	if parent_node:
		parent_node.add_child(sound)
	else:
		add_child(sound)
	
	sound.position = position
	
	if playing:
		sound.play()
