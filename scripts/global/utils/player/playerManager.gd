extends Node

@export var playerScene: PackedScene = preload("res://player/player.tscn")
var playersContainer : Node
var localplayer : player

var players = {}
var pending_avatar_data = {}

func _ready():
	if !Global.isClient:
		get_tree().get_multiplayer().peer_connected.connect(_on_peer_connected)
		get_tree().get_multiplayer().peer_disconnected.connect(_on_peer_disconnected)

func setPlayers(playersContainerRef : Node):
	playersContainer = playersContainerRef

@rpc("authority", "call_remote", "reliable")
func createPlayer(UID, position: Vector3, isLocal = false, avatar_data = {}):
	print_rich("[color=green] Adding player: ", UID, "[/color]")
	 
	if not playersContainer:
		print("Error: playersContainer is null")
		return null
		
	if not playerScene:
		print("Error: Player scene not loaded")
		return null
	
	if Global.isClient:
		if UID == Global.UID and not isLocal:
			return
	
	if UID in players:
		print("Player ", UID, " already exists, skipping creation")
		return players[UID] 
	
	var playerClone = playerScene.instantiate()
	if not playerClone:
		print("Error: Failed to instantiate player")
		return null
		
	playerClone.localPlayer = isLocal
	playerClone.uid = UID
	playerClone.global_position = position
	playerClone.name = str(UID)
	
	if isLocal:
		localplayer = playerClone
	
	players[UID] = playerClone
	playersContainer.add_child(playerClone)
	
	if not avatar_data.is_empty():
		playerClone.changeColors(avatar_data)
	else:
		var user_id = int(get_user_id_for_uid(UID))
		if user_id > 0:
			pending_avatar_data[UID] = true
			var avatarData = await Client.getAvatar(user_id, Global.token)
			if UID in players and is_instance_valid(players[UID]):
				players[UID].changeColors(avatarData)
				if !Global.isClient:
					players[UID].rpc("changeColors", avatarData)
			pending_avatar_data.erase(UID)
	 
	await get_tree().process_frame
	playerClone.init()
	
	return playerClone

@rpc("authority", "call_remote", "reliable")
func removePlayer(UID):
	print_rich("[color=red] Removing player: ", UID, "[/color]")
	if UID in players:
		if players[UID]:
			players[UID].queue_free()
		players.erase(UID)
	pending_avatar_data.erase(UID)

@rpc("any_peer", "call_remote", "unreliable")
func updatePlayerPosition(UID, position: Vector3, rotation: Vector3, velocity: Vector3, is_grounded: bool, anim_name: String, anim_speed: float):
	if UID in players:
		var player = players[UID] 
		if player and not player.localPlayer: 
			player.update_network_transform(position, rotation.y, velocity, is_grounded, anim_name, anim_speed)
	else:
		if Global.isClient and UID != Global.UID:
			createPlayer(UID, position, false)

func _on_peer_connected(id):
	if !Global.isClient:
		print("Peer connected: ", id)
		
		await get_tree().process_frame
		
		var assigned_house_id = Global.assignHouse(str(id))
		var spawn_pos = Vector3.ZERO
		if assigned_house_id:
			var house_node = Global.getHouse(assigned_house_id)
			if house_node and house_node.plrSpawn:
				spawn_pos = house_node.plrSpawn.global_position
		
		await get_tree().process_frame
		
		var user_id = int(get_user_id_for_uid(str(id)))
		var avatar_data = {}
		if user_id > 0:
			avatar_data = await Client.getAvatar(user_id, Global.token)
		
		for existing_uid in players:
			var existing_player = players[existing_uid]
			if existing_player:
				var existing_user_id = int(get_user_id_for_uid(existing_uid))
				var existing_avatar = {}
				if existing_user_id > 0:
					existing_avatar = await Client.getAvatar(existing_user_id, Global.token)
				rpc_id(id, "createPlayer", existing_uid, existing_player.global_position, false, existing_avatar)
		 
		var new_player = await createPlayer(str(id), spawn_pos, false, avatar_data)
		if new_player: 
			var server_user_id = Server.uidToUserId.get(str(id))
			if server_user_id and server_user_id in Server.playerData:
				var saved_money = Server.playerData[server_user_id].get("money", 100)
				new_player.moneyValue.Value = saved_money
				print("Set new player money to saved value: $", saved_money)
			
			rpc_id(id, "createPlayer", str(id), spawn_pos, true, avatar_data)
			 
			for peer_id in get_tree().get_multiplayer().get_peers():
				if peer_id != id:
					rpc_id(peer_id, "createPlayer", str(id), spawn_pos, false, avatar_data)

func _on_peer_disconnected(id):
	if !Global.isClient:
		print("Peer disconnected: ", id)
		 
		for house_id in Global.houses:
			if Global.houses[house_id]["plr"] == str(id):
				Global.houses[house_id]["plr"] = ""
				var house_node = Global.getHouse(house_id)
				if house_node:
					house_node.plrAssigned = ""
				Global.rpc("client_house_assigned", house_id, "")
				break
		 
		removePlayer(str(id))
		rpc("removePlayer", str(id))

func createLocalPlayer():
	if Global.isClient:
		var my_id = get_tree().get_multiplayer().get_unique_id()
		Global.UID = str(my_id)
		await get_tree().process_frame
		await createPlayer(str(my_id), Vector3.ZERO, true)

func get_user_id_for_uid(uid: String) -> int:
	if Global.isClient:
		if uid == Global.UID:
			return Global.user_id
		return 0
	else:
		if uid in Server.uidToUserId:
			return Server.uidToUserId[uid]
		return 0
