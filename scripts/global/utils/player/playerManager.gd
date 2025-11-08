extends Node

@export var playerScene: PackedScene = preload("res://player/player.tscn")
var playersContainer : Node
var localplayer : player

var players = {}
var pending_avatar_data = {}
var players_being_created = {}

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
		
		if isLocal and UID in players:
			print("Local player already exists, removing old instance")
			players_being_created.erase(UID)
			if players[UID]:
				players[UID].queue_free()
			players.erase(UID)
	
	if UID in players:
		if is_instance_valid(players[UID]) and players[UID].is_inside_tree():
			print("Player ", UID, " already exists, skipping creation")
			return players[UID]
		else:
			print("Player ", UID, " exists but invalid, removing")
			players.erase(UID)
			players_being_created.erase(UID)
	
	if UID in players_being_created:
		print("Player ", UID, " is already being created, returning null immediately")
		return null
	
	players_being_created[UID] = true
	
	var playerClone = playerScene.instantiate()
	if not playerClone:
		print("Error: Failed to instantiate player")
		players_being_created.erase(UID)
		return null
		
	playerClone.localPlayer = isLocal
	playerClone.uid = UID
	playerClone.global_position = position
	playerClone.name = str(UID)
	
	if isLocal:
		if localplayer and is_instance_valid(localplayer):
			print("Removing old local player")
			localplayer.queue_free()
		localplayer = playerClone
	
	players[UID] = playerClone
	playersContainer.add_child(playerClone)
	
	await get_tree().process_frame
	
	if not is_instance_valid(playerClone):
		print("ERROR: Player became invalid after adding to tree")
		players_being_created.erase(UID)
		players.erase(UID)
		return null
	
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
	
	playerClone.init()
	
	players_being_created.erase(UID)
	print("Player ", UID, " successfully created and added to tree")
	
	return playerClone

@rpc("authority", "call_remote", "reliable")
func removePlayer(UID):
	print_rich("[color=red] Removing player: ", UID, "[/color]")
	if UID in players:
		if players[UID] and is_instance_valid(players[UID]):
			players[UID].queue_free()
		players.erase(UID)
	players_being_created.erase(UID)
	pending_avatar_data.erase(UID)
	
	if Global.isClient and str(UID) in Global.allPlayers:
		Global.allPlayers.erase(str(UID))

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
		print("PlayerManager: Peer connected: ", id)
		
		await get_tree().process_frame
		
		var user_id = int(get_user_id_for_uid(str(id)))
		var avatar_data = {}
		if user_id > 0:
			print("Pre-fetching avatar data for peer ", id)
			avatar_data = await Client.getAvatar(user_id, Global.token)
			Global.avatarData[str(id)] = avatar_data
		
		for existing_uid in players:
			var existing_player = players[existing_uid]
			if existing_player and is_instance_valid(existing_player):
				var existing_user_id = int(get_user_id_for_uid(existing_uid))
				var existing_avatar = Global.avatarData.get(existing_uid, {})
				if existing_avatar.is_empty() and existing_user_id > 0:
					existing_avatar = await Client.getAvatar(existing_user_id, Global.token)
					Global.avatarData[existing_uid] = existing_avatar
				rpc_id(id, "createPlayer", existing_uid, existing_player.global_position, false, existing_avatar)

func create_player_for_peer(peer_id: int, spawn_pos: Vector3, avatar_data: Dictionary = {}):
	if Global.isClient:
		return null
	
	print("PlayerManager: Creating player for peer ", peer_id, " at ", spawn_pos)
	
	var new_player = await createPlayer(str(peer_id), spawn_pos, false, avatar_data)
	if new_player:
		var server_user_id = Server.uidToUserId.get(str(peer_id))
		if server_user_id and server_user_id in Server.playerData:
			var saved_money = Server.playerData[server_user_id].get("money", 100)
			var saved_rebirths = Server.playerData[server_user_id].get("rebirths", 0)
			new_player.moneyValue.Value = saved_money
			if new_player.rebirthsVal:
				new_player.rebirthsVal.Value = saved_rebirths
			print("Set new player stats - Money: $", saved_money, " Rebirths: ", saved_rebirths)
		
		await get_tree().process_frame
		
		rpc_id(peer_id, "createPlayer", str(peer_id), spawn_pos, true, avatar_data)
		
		for other_peer_id in get_tree().get_multiplayer().get_peers():
			if other_peer_id != peer_id:
				rpc_id(other_peer_id, "createPlayer", str(peer_id), spawn_pos, false, avatar_data)
		
		print("PlayerManager: Player ", peer_id, " created and synced to all clients")
	else:
		print("ERROR: Failed to create player for peer ", peer_id)
	
	return new_player

func _on_peer_disconnected(id):
	if !Global.isClient:
		print("PlayerManager: Peer disconnected: ", id)
		
		removePlayer(str(id))
		rpc("removePlayer", str(id))

func createLocalPlayer():
	if Global.isClient:
		var my_id = get_tree().get_multiplayer().get_unique_id()
		Global.UID = str(my_id)
		await get_tree().process_frame
		
		var max_retries = 3
		var retry_count = 0
		var player = null
		
		while retry_count < max_retries and player == null:
			player = await createPlayer(str(my_id), Vector3.ZERO, true)
			if player == null:
				retry_count += 1
				print("Retry ", retry_count, " for local player creation")
				await get_tree().create_timer(0.5).timeout
		
		if player == null:
			print("CRITICAL: Failed to create local player after ", max_retries, " attempts")

func get_user_id_for_uid(uid: String) -> int:
	if Global.isClient:
		if uid == Global.UID:
			return Global.user_id
		return 0
	else:
		if uid in Server.uidToUserId:
			return Server.uidToUserId[uid]
		return 0
