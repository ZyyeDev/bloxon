extends Node

signal request_received(from_peer, method_name, args)

func send_to_server(method_name: String, args: Array = []):
	if Global.isClient and multiplayer.has_multiplayer_peer():
		rpc_id(1, "_handle_client_request", method_name, args, multiplayer.get_unique_id())

func send_to_client(peer_id: int, method_name: String, args: Array = []):
	if not Global.isClient and multiplayer.has_multiplayer_peer():
		rpc_id(peer_id, "_handle_server_response", method_name, args)

func send_to_all_clients(method_name: String, args: Array = []):
	if not Global.isClient and multiplayer.has_multiplayer_peer():
		rpc("_handle_server_response", method_name, args)

func send_to_all_except(excluded_peer: int, method_name: String, args: Array = []):
	if not Global.isClient and multiplayer.has_multiplayer_peer():
		for peer in multiplayer.get_peers():
			if peer != excluded_peer:
				rpc_id(peer, "_handle_server_response", method_name, args)

@rpc("any_peer", "call_remote", "reliable")
func _handle_client_request(method_name: String, args: Array, from_peer: int):
	if not Global.isClient:
		emit_signal("request_received", from_peer, method_name, args)
		
		match method_name:
			"assign_house":
				_handle_assign_house(from_peer)
			"try_grab":
				if args.size() >= 1:
					_handle_try_grab(args[0], from_peer)
			"player_spawned":
				_handle_player_spawned(from_peer)
			"purchase_brainrot":
				if args.size() >= 1:
					_handle_purchase_brainrot(from_peer, args[0])

@rpc("any_peer", "call_remote", "reliable")
func _handle_server_response(method_name: String, args: Array):
	if Global.isClient:
		emit_signal("request_received", 1, method_name, args)
		
		match method_name:
			"house_assigned":
				if args.size() >= 1:
					_handle_house_assigned(args[0])
			"spawn_brainrot":
				if args.size() >= 2:
					_handle_spawn_brainrot(args[0], args[1])
			"remove_brainrot":
				if args.size() >= 1:
					_handle_remove_brainrot(args[0])
			"update_slaps":
				if args.size() >= 1:
					_handle_update_slaps(args[0])
			"house_updated":
				if args.size() >= 2:
					_handle_house_updated(args[0], args[1])
			"update_house_brainrots":
				if args.size() >= 2:
					_handle_update_house_brainrots(args[0], args[1])
			"money_update":
				if args.size() >= 1:
					_handle_money_update(args[0])
			"purchase_result":
				if args.size() >= 2:
					_handle_purchase_result(args[0], args[1])

func _handle_update_house_brainrots(house_id, house_brainrots):
	var house_node = Global.getHouse(house_id)
	if house_node:
		house_node.updateBrainrots(house_brainrots)

func _handle_house_updated(house_id, player_uid):
	Global.houses[house_id] = {"plr": player_uid}
	var house_node = Global.getHouse(house_id)
	if house_node:
		house_node.plrAssigned = player_uid

func _handle_assign_house(peer_id: int):
	for house_id in Global.houses:
		if Global.houses[house_id]["plr"] == "":
			Global.houses[house_id]["plr"] = str(peer_id)
			var house_node = Global.getHouse(house_id)
			if house_node:
				house_node.plrAssigned = str(peer_id)
			send_to_client(peer_id, "house_assigned", [house_id])
			send_to_all_except(peer_id, "house_updated", [house_id, str(peer_id)])
			print("Assigned house ", house_id, " to player ", peer_id)
			return
	print("No available houses for player ", peer_id)

func _handle_try_grab(brainrot_uid: String, peer_id: int):
	if brainrot_uid in Global.brainrots and Global.brainrots[brainrot_uid]:
		var br = Global.brainrots[brainrot_uid]
		if br.pGet == "":
			br.pGet = str(peer_id)
			var player_house = Global.whatHousePlr(peer_id)
			if player_house and player_house.ref:
				br.target = player_house.ref.plrSpawn
				br.target = player_house.ref.plrSpawn
				br.rpc("updatePlayerTarget", str(peer_id))

func _handle_purchase_brainrot(peer_id: int, house_id: int):
	print("Handle purchase from peer ", peer_id, " for house ", house_id)

func _handle_player_spawned(peer_id: int):
	_handle_assign_house(peer_id)

func _handle_house_assigned(house_id):
	Global.houses[house_id] = {"plr": Global.UID}
	var house_node = Global.getHouse(house_id)
	if house_node:
		house_node.plrAssigned = Global.UID
	print("Client: Assigned to house ", house_id)

func _handle_spawn_brainrot(br_uid: String, position: Vector3):
	print("spawn brainrot with: ",br_uid)
	var br = load("res://brainrots/noobini pizzanini.tscn").instantiate()
	br.UID = br_uid
	Game.workspace.get_node("brainrots").add_child(br)
	br.global_position = position
	Global.brainrots[br_uid] = br

func _handle_remove_brainrot(br_uid: String):
	if br_uid in Global.brainrots:
		if not Global.brainrots[br_uid]: return
		Global.brainrots[br_uid].queue_free()
		Global.brainrots.erase(br_uid)

func _handle_update_slaps(value: int):
	Global.slaps = value

func _handle_money_update(amount: int):
	Global.player_money = amount
	print("Money updated to: ", amount)

func _handle_purchase_result(success: bool, message: String):
	if success:
		print("Purchase successful!")
	else:
		print("Purchase failed: ", message)

func request_house_assignment():
	send_to_server("assign_house")

func try_grab_brainrot(brainrot_uid: String):
	send_to_server("try_grab", [brainrot_uid])

func request_purchase_brainrot(house_id: int):
	send_to_server("purchase_brainrot", [house_id])
