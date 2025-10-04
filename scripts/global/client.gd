extends Node

var http: HTTPRequest
var peer: ENetMultiplayerPeer
var playerId: String = "" 
var heartbeat_timer: Timer
var is_connected: bool = false
var last_heartbeat_success: float = 0.0

var heartbeatCompleted = {}
var lastTimerheartbeatCompleted = null

var serverUID = ""

var servers = []

var inventory = {}

signal server_connected
signal server_disconnected
signal kicked_from_server
signal serverlist_update

func _ready():
	if Global.isClient:
		for i in 10:
			inventory[i] = ""
		playerId = str(randi())
		http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(_on_request_completed)

func requestServer():
	CoreGui.showConnect("Searching servers...")
	var url = Global.masterIp + "/request_server"
	var headers = ["Content-Type: application/json"]
	var body = {"player_id": playerId,"token": Global.token}
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_request_completed(result, code, headers, body):
	var response_text = body.get_string_from_utf8()
	print("Response code: ", code, " Body: ", response_text)
	
	if code != 200:
		print("Failed to get server info, code: ", code)
		return
		
	var data = JSON.parse_string(response_text)
	if data == null:
		print("Failed to parse response")
		return
		
	if data.has("error"):
		if data["error"] == "player_not_found":
			emit_signal("kicked_from_server")
		return
		
	if data.has("ip") and data["ip"] != null and data.has("uid") and data["uid"] != null:
		print("Connecting to server: ", data["ip"], ":", data["port"])
		connectToServer(data["ip"], int(data["port"]))
		startHeartbeat()

func connectToServerID(serverId: String):
	CoreGui.showConnect("Connecting to server...")
	var url = Global.masterIp + "/connect_to_server"
	var headers = ["Content-Type: application/json"]
	var body = {"player_id": playerId, "token": Global.token, "server_id": serverId}
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func connectToServer(ip: String, port: int):
	CoreGui.showConnect("Connecting to server...")
	print("connecting to server...")
	peer = ENetMultiplayerPeer.new()
	var ok = peer.create_client(ip, port)
	if ok != OK:
		print("Failed to create client connection. | ", ok)
		return
	
	get_tree().get_multiplayer().multiplayer_peer = peer
	get_tree().get_multiplayer().connected_to_server.connect(_on_connected_to_server)
	get_tree().get_multiplayer().connection_failed.connect(_on_connection_failed)
	get_tree().get_multiplayer().server_disconnected.connect(_on_server_disconnected)

func _on_connected_to_server():
	server_connected.emit()
	for i in inventory:
		inventory[i] = ""
	CoreGui.hideConnect()
	PlayerManager.setPlayers(Game.workspace.playersContainer)
	print("Creating local player...")
	PlayerManager.createLocalPlayer()
	print("Connected to server successfully! UID: ", Global.UID)
	is_connected = true
	Global.on_player_connected()
	Server.rpc_id(1, "register_client_account",Global.user_id,Global.token)

func _on_connection_failed():
	print("Failed to connect to server")
	serverUID = ""
	is_connected = false

func _on_server_disconnected():
	Global.errorMessage("Disconnected from the server",Global.ERROR_CODES.DISCONNECT)
	serverUID = ""
	print("Disconnected from server")
	is_connected = false
	emit_signal("server_disconnected")
	if heartbeat_timer:
		heartbeat_timer.queue_free()

func startHeartbeat():
	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = 10.0
	heartbeat_timer.autostart = true
	add_child(heartbeat_timer)
	heartbeat_timer.timeout.connect(_on_heartbeat_timer)
	last_heartbeat_success = Time.get_unix_time_from_system()

func _on_heartbeat_timer():
	if !is_connected:
		return
		
	var url = Global.masterIp + "/heartbeat_client"
	var headers = ["Content-Type: application/json"]
	var body = {"player_id": playerId,"token": Global.token}
	
	var timeout = Timer.new()
	timeout.autostart = true
	timeout.wait_time = 5
	heartbeatCompleted[timeout] = false
	lastTimerheartbeatCompleted = timeout
	timeout.timeout.connect(func():
		if !heartbeatCompleted[timeout]:
			Global.errorMessage("Timeout",Global.ERROR_CODES.TIMEOUT)
		else:
			heartbeatCompleted.erase(timeout)
		timeout.queue_free()
		)
	
	add_child(timeout)
	
	var http_hb = HTTPRequest.new()
	add_child(http_hb)
	http_hb.request_completed.connect(_on_heartbeat_completed)
	http_hb.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_heartbeat_completed(result, code, headers, body):
	var sender = get_children().back()
	if sender is HTTPRequest:
		sender.queue_free()
	
	if lastTimerheartbeatCompleted and lastTimerheartbeatCompleted in heartbeatCompleted:
		heartbeatCompleted[lastTimerheartbeatCompleted] = true
	
	if not is_connected:
		print("cant hb, not connected yet!")
		return
	
	if code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data and data.has("status") and data["status"] == "alive":
			last_heartbeat_success = Time.get_unix_time_from_system()
		else:
			Global.errorMessage("Couldn't reach server",Global.ERROR_CODES.CANT_REACH)
			print("Server says we don't exist")
			emit_signal("kicked_from_server")
	else:
		print("Heartbeat failed with code: ", code)
		if Time.get_unix_time_from_system() - last_heartbeat_success > 30.0:
			print("Haven't received successful heartbeat in 30 seconds")
			Global.errorMessage("Couldn't reach server",Global.ERROR_CODES.CANT_REACH)
			emit_signal("server_disconnected")

func _process(delta):
	if is_connected and get_tree().get_multiplayer().multiplayer_peer:
		var state = get_tree().get_multiplayer().multiplayer_peer.get_connection_status()
		if state == MultiplayerPeer.CONNECTION_DISCONNECTED:
			print("Multiplayer peer disconnected")
			is_connected = false
			emit_signal("server_disconnected")

func disconnect_from_server():
	is_connected = false
	serverUID = ""
	if heartbeat_timer:
		heartbeat_timer.queue_free()
		heartbeat_timer = null
	if peer:
		peer.close()
		peer = null
	if get_tree().get_multiplayer().multiplayer_peer:
		get_tree().get_multiplayer().multiplayer_peer = null
	emit_signal("server_disconnected")
	get_tree().change_scene_to_file("res://scenes/INIT.tscn")

func init():
	pass

func getUserById(userId: int):
	var http = HTTPRequest.new()
	add_child(http)
	
	var data = {"user_id": userId}
	var json = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	
	http.request_completed.connect(_onGetUserByIdResponse)
	http.request(Global.masterIp + "/users/get_by_id", headers, HTTPClient.METHOD_POST, json)

func _onGetUserByIdResponse(result: int, responseCode: int, headers: PackedStringArray, body: PackedByteArray):
	var response = JSON.parse_string(body.get_string_from_utf8())
	if responseCode == 200:
		var username = response.username
		var userId = response.user_id
		var gender = response.gender
		var created = response.created

func searchUsers(query: String, limit: int = 20):
	var http = HTTPRequest.new()
	add_child(http)
	
	var data = {"query": query, "limit": limit}
	var json = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	
	http.request(Global.masterIp + "/users/search", headers, HTTPClient.METHOD_POST, json)
	
	var response = await http.request_completed
	http.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.new()
		var parseResult = jsonResponse.parse(response[3].get_string_from_utf8())
		if parseResult == OK:
			return jsonResponse.data
	
	return {}

func getPlayerDataById(userId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp+"/player/get_profile", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.new()
		var parseResult = jsonResponse.parse(response[3].get_string_from_utf8())
		if parseResult == OK:
			return jsonResponse.data
	
	return {}

func getPlayerPfpById(userId: int, token: String) -> String:
	var playerData = await getPlayerDataById(userId, token)
	
	if playerData.has("success") and playerData.success:
		var data = playerData.get("data", {})
		return data.get("pfp", "")
	
	return ""

func getCurrency(userId: int, token: String) -> String:
	var playerData = await getPlayerDataById(userId, token)
	
	if playerData.has("success") and playerData.success:
		var data = playerData.get("data", {})
		return data.get("currency", "")
	
	return ""

func getAvatar(userId: int, token: String) -> Dictionary:
	var playerData = await getPlayerDataById(userId, token)
	
	if playerData.has("success") and playerData.success:
		var data = playerData.get("data", {}) 
		return data.get("avatar", {})
	
	return {}

func getFriends(userId: int, token: String) -> Dictionary:
	var playerData = await getPlayerDataById(userId, token)
	
	if playerData.has("success") and playerData.success:
		var data = playerData.get("data", {})
		return data.get("friends", {})
	
	return {}

func loadTextureFromUrl(url: String) -> ImageTexture:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	httpRequest.request(url)
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var imageData = response[3]
		var image = Image.new()
		
		if url.ends_with(".png"):
			image.load_png_from_buffer(imageData)
		elif url.ends_with(".jpg") or url.ends_with(".jpeg"):
			image.load_jpg_from_buffer(imageData)
		elif url.ends_with(".webp"):
			image.load_webp_from_buffer(imageData)
		
		if image.get_width() > 0:
			var texture = ImageTexture.new()
			texture.set_image(image)
			return texture
	
	return null

func getPlayerPfpTexture(userId: int, token: String) -> ImageTexture:
	var pfpUrl = await getPlayerPfpById(userId, token)
	if pfpUrl != "":
		return await loadTextureFromUrl(pfpUrl)
	return null

func sendFriendRequest(fromUserId: int, toUserId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"fromUserId": fromUserId,
		"toUserId": toUserId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/friends/send_request", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	var status_code = response[1]
	var response_body = response[3].get_string_from_utf8()
	
	var jsonResponse = JSON.parse_string(response_body)
	if jsonResponse == null:
		return {
			"success": false,
			"error": {
				"code": "PARSE_ERROR",
				"message": "Failed to parse server response"
			},
			"raw_response": response_body
		}
	return response_body

func getFriendRequests(userId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/friends/get_requests", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	print(response[3].get_string_from_utf8())
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func acceptFriendRequest(userId: int, requesterId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId,
		"requesterId": requesterId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/friends/accept_request", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func rejectFriendRequest(userId: int, requesterId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId,
		"requesterId": requesterId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/friends/reject_request", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func cancelFriendRequest(userId: int, targetUserId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId,
		"targetUserId": targetUserId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/friends/cancel_request", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func removeFriend(userId: int, friendId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId,
		"friendId": friendId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/friends/remove", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func getFriendsList(userId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/friends/get", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func listMarketAccessories(token: String, filterData: Dictionary = {}, pagination: Dictionary = {}) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"filter": filterData,
		"pagination": pagination
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/avatar/list_market", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func getAccessoryData(accessoryId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"accessoryId": accessoryId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/avatar/get_accessory", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func getUserAccessories(userId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/avatar/get_user_accessories", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func buyAccessory(userId: int, itemId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId,
		"itemId": itemId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/avatar/buy_item", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {
		"success": false,
		"error": {
			"code": "HTTP_ERROR",
			"message": "Request failed with code: " + str(response[1])
		}
	}

func downloadAccessoryModel(downloadUrl: String, accessoryId: int) -> String:
	var cacheDir = "user://cache/accessories/"
	var fileName = str(accessoryId) + "_" + downloadUrl.get_file()
	var cachePath = cacheDir + fileName
	
	if not DirAccess.dir_exists_absolute(cacheDir):
		DirAccess.open("user://").make_dir_recursive("cache/accessories")
	
	if FileAccess.file_exists(cachePath):
		print("Accessory model already cached: ", cachePath)
		return cachePath
	
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	httpRequest.request(downloadUrl)
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var file = FileAccess.open(cachePath, FileAccess.WRITE)
		if file:
			file.store_buffer(response[3])
			file.close()
			print("Downloaded accessory model: ", cachePath)
			return cachePath
		else:
			print("Failed to save accessory model to cache")
			return ""
	else:
		print("Failed to download accessory model, code: ", response[1])
		return ""

# TODO
func loadAccessoryModelNode(accessoryId: int, token: String) -> Node3D:
	var accessoryData = await getAccessoryData(accessoryId, token)
	
	if not accessoryData.has("success") or not accessoryData.success:
		print("Failed to get accessory data")
		return null
	
	var data = accessoryData.get("data", {})
	var downloadUrl = data.get("downloadUrl", "")
	
	if downloadUrl == "":
		print("No download URL for accessory")
		return null
	
	var modelPath = await downloadAccessoryModel(downloadUrl, accessoryId)
	if modelPath == "":
		print("Failed to download model")
		return null
	
	var modelNode: Node3D = null
	
	if modelPath.ends_with(".glb") or modelPath.ends_with(".gltf"):
		var gltf = GLTFDocument.new()
		var state = GLTFState.new()
		var error = gltf.append_from_file(modelPath, state)
		if error == OK:
			modelNode = gltf.generate_scene(state)
	elif modelPath.ends_with(".obj"):pass
		#var objLoader = load("res://addons/obj_loader/OBJLoader.gd")
		#if objLoader:
		#	modelNode = objLoader.load_obj(modelPath)
	elif modelPath.ends_with(".fbx"):
		return null
	
	if modelNode:
		modelNode.name = "Accessory_" + str(accessoryId)
		#var accessoryScript = preload("res://scripts/AccessoryNode.gd")
		#if accessoryScript:
		#	modelNode.set_script(accessoryScript)
		#	modelNode.accessoryId = accessoryId
		#	modelNode.accessoryData = data
	
	return modelNode

func clearAccessoryCache():
	var cacheDir = "user://cache/accessories/"
	var dir = DirAccess.open(cacheDir)
	if dir:
		dir.list_dir_begin()
		var fileName = dir.get_next()
		while fileName != "":
			if not dir.current_is_dir():
				dir.remove(fileName)
				print("Removed cached file: ", fileName)
			fileName = dir.get_next()

func getCacheSize() -> int:
	var cacheDir = "user://cache/accessories/"
	var totalSize = 0
	var dir = DirAccess.open(cacheDir)
	if dir:
		dir.list_dir_begin()
		var fileName = dir.get_next()
		while fileName != "":
			if not dir.current_is_dir():
				var file = FileAccess.open(cacheDir + fileName, FileAccess.READ)
				if file:
					totalSize += file.get_length()
					file.close()
			fileName = dir.get_next()
	return totalSize

func preloadAccessoryModel(accessoryId: int, token: String):
	var accessoryData = await getAccessoryData(accessoryId, token)
	
	if accessoryData.has("success") and accessoryData.success:
		var data = accessoryData.get("data", {})
		var downloadUrl = data.get("downloadUrl", "")
		if downloadUrl != "":
			await downloadAccessoryModel(downloadUrl, accessoryId)

func isAccessoryModelCached(accessoryId: int, downloadUrl: String) -> bool:
	var cacheDir = "user://cache/accessories/"
	var fileName = str(accessoryId) + "_" + downloadUrl.get_file()
	var cachePath = cacheDir + fileName
	return FileAccess.file_exists(cachePath)
