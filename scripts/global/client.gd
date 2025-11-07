extends Node

var http: HTTPRequest
var peer: ENetMultiplayerPeer
var playerId: String = "" 
var heartbeat_timer: Timer
var is_connected: bool = false
var last_heartbeat_success: float = 0.0

var heartbeatCompleted = {}
var lastTimerheartbeatCompleted = null

var paymentConnected = false

var payment
var recent_product_id
var recent_purchase_type
var purchased_products_ids = []
var queried_product_details = {}

var ws: WebSocketPeer
var message_callbacks = []

var serverUID = ""

var servers = []

var inventory = {}

signal server_connected
signal server_disconnected
signal kicked_from_server
signal serverlist_update
signal bought_product(product_id: String)
signal purchase_completed(success: bool, product_id: String, message: String)
signal purchase_failed(error_message: String)

func _ready():
	var args = OS.get_cmdline_args()
	if Global.isClient and not "--pfp-render" in args:
		for i in 9:
			inventory[i] = -1
		playerId = str(randi())
		http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(_on_request_completed)
		Client.subscribeToGlobalMessages(_on_global_message)
		
		if OS.get_name() == "Android":
			_setup_payment_system()

func _setup_payment_system():
	if Engine.has_singleton("GodotGooglePlayBilling"):
		payment = Engine.get_singleton("GodotGooglePlayBilling")
		
		payment.connected.connect(_on_payment_connected)
		payment.disconnected.connect(_on_payment_disconnected)
		payment.connect_error.connect(_on_payment_connect_error)
		payment.purchases_updated.connect(_on_purchases_updated)
		payment.query_purchases_response.connect(_on_query_purchases_response)
		payment.purchase_error.connect(_on_purchase_error)
		payment.product_details_query_completed.connect(_on_product_details_query_completed)
		payment.product_details_query_error.connect(_on_product_details_query_error)
		
		payment.startConnection()
	else:
		print("Google Play Billing plugin not available")
		paymentConnected = false

func _on_payment_connected():
	print("Billing connected!")
	paymentConnected = true
	payment.queryPurchasesAsync("inapp")

func _on_payment_disconnected():
	print("Billing disconnected")
	paymentConnected = false

func _on_payment_connect_error(error_code: int, error_message: String):
	printerr("BILLING CONNECTION ERROR: ", error_message, " (", error_code, ")")
	paymentConnected = false
	purchase_failed.emit("Failed to connect to payment system: " + error_message)

func _on_product_details_query_completed(products: Array):
	print("Product details query completed: ", products)
	for product in products:
		var product_id = product.get("productId", "")
		if product_id != "":
			queried_product_details[product_id] = product

func _on_product_details_query_error(error_code: int, error_message: String, product_ids: Array):
	printerr("Product details query error: ", error_message, " (", error_code, ")")
	purchase_failed.emit("Failed to query product details: " + error_message)

func _on_purchases_updated(purchases: Array):
	print("Purchases updated: ", purchases)
	for purchase in purchases:
		if purchase.purchase_state == 1:
			var product_id = purchase.products[0]
			if product_id not in purchased_products_ids:
				_verify_and_consume_purchase(purchase)

func _on_query_purchases_response(query_result: Dictionary):
	print("Query purchases response: ", query_result)
	var status = query_result.get("status", -1)
	var response_code = query_result.get("response_code", -1)
	
	if status == OK and response_code == 0:
		var purchases = query_result.get("purchases", [])
		for purchase in purchases:
			if purchase.purchase_state == 1:
				var product_id = purchase.products[0]
				if product_id not in purchased_products_ids:
					_verify_and_consume_purchase(purchase)

func _on_purchase_error(error_code: int, error_message: String):
	printerr("Purchase error: ", error_message, " (", error_code, ")")
	purchase_failed.emit(error_message)

func _verify_and_consume_purchase(purchase: Dictionary):
	var product_id = purchase.products[0]
	var purchase_token = purchase.purchase_token
	
	print("Verifying purchase: ", product_id)
	
	var result = await processPurchase(Global.token, product_id, purchase_token)
	
	if result.get("success", false):
		purchased_products_ids.append(product_id)
		
		if payment and paymentConnected:
			payment.consumePurchase(purchase_token)
		
		var currency_granted = result.get("data", {}).get("currency_granted", 0)
		print("Purchase verified and consumed! Currency granted: ", currency_granted)
		bought_product.emit(product_id)
		purchase_completed.emit(true, product_id, "Purchase successful! Granted " + str(currency_granted) + " currency")
	else:
		var error_msg = result.get("error", {}).get("message", "Unknown error")
		printerr("Failed to verify purchase: ", error_msg)
		purchase_failed.emit(error_msg)

func _on_global_message(message: Dictionary):
	var msg_type = message.get("type")
	var properties = message.get("properties", {})
	
	print(message)
	
	match msg_type:
		"Maintenance":
			if properties.get("enabled", false):
				Global.errorMessage(
					properties.get("message", "Server maintenance"),
					Global.ERROR_CODES.MAINTENANCE,
					"Disconnected",
					"Leave",
					func():
						CoreGui.hideConnect()
						get_tree().change_scene_to_file("res://scenes/INIT.tscn")
				)
		"Message":
			CoreGui.addAnnouncement(properties.get("message", ""),4)
		"ServerShutdown":
			CoreGui.addAnnouncement("Server restarting soon!",2)

func requestServer():
	CoreGui.showConnect("Searching for servers...")
	var thread = Thread.new()
	thread.start(func():
		await Global.wait(randi_range(1,4))
		CoreGui.showConnect("Reserving server")
	)
	var otherTextThread
	var url = Global.masterIp + "/request_server"
	var headers = ["Content-Type: application/json"]
	var body = {"player_id": playerId,"token": Global.token}
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_request_completed(result, code, headers, body):
	var response_text = body.get_string_from_utf8()
	print("Response code: ", code, " Body: ", response_text)
	
	if code != 200:
		if code == 503:
			var data = JSON.parse_string(response_text)
			if data and data.has("error"):
				if data["error"] == "vm_timeout":
					CoreGui.showConnect("Server is starting, please wait...")
					await get_tree().create_timer(10.0).timeout
					requestServer()
					return
				elif data["error"] == "vm_full":
					CoreGui.showConnect("All servers full, creating new one...")
					await get_tree().create_timer(5.0).timeout
					requestServer()
					return
		
		Global.errorMessage(
			"Failed to find server",
			Global.ERROR_CODES.SERVER_REACH,
			"Disconnected",
			"Leave",
			func():
				CoreGui.hideConnect()
				get_tree().change_scene_to_file("res://scenes/INIT.tscn")
		)
		print("Failed to get server info, code: ", code)
		return
		
	var data = JSON.parse_string(response_text)
	if data == null:
		print("Failed to parse response")
		Global.errorMessage(
			"Server error",
			Global.ERROR_CODES.CORRUPTED_FILES,
			"Disconnected",
			"Leave",
			func():
				CoreGui.hideConnect()
				get_tree().change_scene_to_file("res://scenes/INIT.tscn")
		)
		return
		
	if data.has("error"):
		if data["error"] == "player_not_found":
			emit_signal("kicked_from_server")
		return
		
	if data.has("ip") and data["ip"] != null and data.has("uid"):
		data["port"] = int(data["port"])
		print("Connecting to server: ", data["ip"], ":", data["port"])
		CoreGui.showConnect("Connecting to server...")
		await get_tree().create_timer(2.0).timeout
		connectToServer(data["ip"], int(data["port"]))
		startHeartbeat()
	else:
		Global.errorMessage(
			"Server error",
			Global.ERROR_CODES.CORRUPTED_FILES,
			"Disconnected",
			"Leave",
			func():
				CoreGui.hideConnect()
				get_tree().change_scene_to_file("res://scenes/INIT.tscn")
		)

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
	print(ok)
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
	Server.rpc_id(1, "register_client_account",Global.user_id,Global.token)
	Global.on_player_connected()

func _on_connection_failed():
	Global.errorMessage(
		"Error",
		Global.ERROR_CODES.TIMEOUT,
		"Failed to connect to server.",
		"Leave",
		func():
			CoreGui.hideConnect()
			get_tree().change_scene_to_file("res://scenes/INIT.tscn")
	)
	print("Failed to connect to server")
	serverUID = ""
	is_connected = false

func _on_server_disconnected():
	Global.localPlayer = null
	Global.errorMessage(
		"Disconnected from the server",
		Global.ERROR_CODES.DISCONNECT,
		"Disconnected",
		"Leave",
		func():
			CoreGui.hideConnect()
			get_tree().change_scene_to_file("res://scenes/INIT.tscn")
	)
	serverUID = ""
	print("Disconnected from server")
	is_connected = false
	emit_signal("server_disconnected")
	if heartbeat_timer:
		heartbeat_timer.queue_free()

func startHeartbeat():
	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = 5.0
	heartbeat_timer.autostart = true
	add_child(heartbeat_timer)
	heartbeat_timer.timeout.connect(_on_heartbeat_timer)
	last_heartbeat_success = Time.get_unix_time_from_system()

func _on_heartbeat_timer():
	if !is_connected:
		return
	
	last_heartbeat_success = Time.get_unix_time_from_system()
	
	if multiplayer.has_multiplayer_peer():
		Server.rpc_id(1, "client_heartbeat", Global.UID)

func _on_heartbeat_completed(result, code, headers, body):
	var sender = get_children().back()
	if sender is HTTPRequest:
		sender.queue_free()
	if not is_connected:
		return
	if code == 200:
		last_heartbeat_success = Time.get_unix_time_from_system()
	else:
		if Time.get_unix_time_from_system() - last_heartbeat_success > 15.0:
			Global.errorMessage(
				"Couldn't reach server",
				Global.ERROR_CODES.CANT_REACH,
				"Disconnected",
				"Leave",
				func():
					CoreGui.hideConnect()
					get_tree().change_scene_to_file("res://scenes/INIT.tscn")
			)
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

func getCurrency(userId: int, token: String) -> int:
	var playerData = await getPlayerDataById(userId, token)
	if playerData.has("success") and playerData.success:
		var data = playerData.get("data", {})
		return data.get("currency", 0)
	
	return 0

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
	call_deferred("add_child",httpRequest)
	
	while !httpRequest.is_inside_tree():
		await get_tree().process_frame
	
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
	return load("res://assets/images/fallbackPfp.png")

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
	print(response_body)
	return jsonResponse

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
		var marketData:Array = requestData.get("data",{}).get("items",[])
		
		if !marketData.is_empty():
			for myData in marketData:
				var id = int(myData["id"])
				var downloadUrl = myData["downloadUrl"]
				downloadAccessoryModel(downloadUrl,id)
				
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func getAccessoryData(accessoryId: int) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
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

# TODO: it should auto connect if backend respondes with a correct code
func joinFriend(friendId:int) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": Global.token,
		"friendId":friendId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/friend/joinFriendServer", headers, HTTPClient.METHOD_POST, jsonString)
	
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
		"user_id":userId
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

func getUserAccessoriesFull(token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/avatar/get_full", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func checkMaintenance() -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/maintenance_status", headers, HTTPClient.METHOD_GET, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func buyAccessory(itemId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
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

func alrCached(downloadUrl: String):
	var cacheDir = "user://cache/accessories/"
	var fileName = downloadUrl.get_file()
	var cachePath = cacheDir + fileName
	if not DirAccess.dir_exists_absolute(cacheDir):
		return false
	
	if FileAccess.file_exists(cachePath):
		return true
	else:
		return false

func downloadAccessoryModel(downloadUrl: String, accessoryId: int) -> Dictionary:
	var cacheDir = "user://cache/accessories/"
	var fileName = downloadUrl.get_file()
	var cachePath = cacheDir + fileName
	
	if not DirAccess.dir_exists_absolute(cacheDir):
		DirAccess.open("user://").make_dir_recursive("cache/accessories")
	
	var returnData = {
		"model" = "",
		"texture" = "",
		"mtl" = "",
	}
	
	if FileAccess.file_exists(cachePath):
		print("Accessory model already cached: ", cachePath)
		returnData["model"] = cachePath
		if FileAccess.file_exists(cachePath.replace("_model.obj","_texture.png")):
			returnData["texture"] = cachePath.replace("_model.obj","_texture.png")
		if FileAccess.file_exists(cachePath.replace("_model.obj","_material.mtl")):
			returnData["mtl"] = cachePath.replace("_model.obj","_material.mtl")
		return returnData
	
	returnData["model"] = await downloadFile(downloadUrl,cachePath)
	
	if ".obj" in downloadUrl:
		var textureDownload = downloadUrl.replace("_model.obj","_texture.png")
		returnData["texture"] = await downloadFile(textureDownload,cachePath.replace("_model.obj","_texture.png"))
		var mtlDownload = downloadUrl.replace("_model.obj","_material.mtl")
		returnData["mtl"] = await downloadFile(mtlDownload,cachePath.replace("_model.obj","_material.mtl"))
	
	return returnData

func downloadFile(downloadUrl:String,DownloadPath:String):
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	httpRequest.request(downloadUrl)
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var file = FileAccess.open(DownloadPath, FileAccess.WRITE)
		if file:
			file.store_buffer(response[3])
			file.close()
			print("Downloaded file: ", DownloadPath)
			return DownloadPath
		else:
			print("Failed to save file")
			return ""
	else:
		print("Failed to download file, code: ", response[1], " | ",downloadUrl)
		return ""

func loadAccessoryModelNode(accessoryId: int, token: String) -> Node3D:
	var accessoryData = await getAccessoryData(accessoryId)
	
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
	elif modelPath.ends_with(".obj"):
		pass
	elif modelPath.ends_with(".fbx"):
		return null
	
	if modelNode:
		modelNode.name = "Accessory_" + str(accessoryId)
	
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
	var accessoryData = await getAccessoryData(accessoryId)
	
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

func equipAccessory(accessoryId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"accessoryId": accessoryId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/avatar/equip", headers, HTTPClient.METHOD_POST, jsonString)
	
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

func unequipAccessory(accessoryId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"accessoryId": accessoryId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/avatar/unequip", headers, HTTPClient.METHOD_POST, jsonString)
	
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

func updateAvatar(userId: int, avatarData: Dictionary, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId,
		"avatar": avatarData
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/player/update_avatar", headers, HTTPClient.METHOD_POST, jsonString)
	
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

func getFullAvatar(userId: int, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"userId": userId
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/avatar/get_full", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func format_number(num: float) -> String:
	var suffixes = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
	
	if num < 1000:
		return str(int(num))
	
	var exp = 0
	while num >= 1000.0 and exp < suffixes.size() - 1:
		num /= 1000.0
		exp += 1
	
	var formatted = "%.2f" % num
	
	while formatted.ends_with("0") and not formatted.ends_with(".0"):
		formatted = formatted.substr(0, formatted.length() - 1)
	
	if formatted.ends_with(".0"):
		formatted = formatted.substr(0, formatted.length() - 2)
	elif formatted.ends_with("."):
		formatted = formatted.substr(0, formatted.length() - 1)
	
	return formatted + suffixes[exp]

func getGlobalMessages(since_id: int = 0) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"since_id": since_id
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/global_messages", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func addAccessoryToPlayer(accessoryId:int,charRef:Node3D):
	var acReq = await Client.getAccessoryData(int(accessoryId))
	
	var myData = acReq.get("data",{})
	if myData.is_empty():
		push_error("acessory data is empty!!")
		return null
	var id = int(myData["id"])
	var Name = myData["name"]
	var type = myData["type"]
	var price = myData["price"]
	var downloadUrl = myData["downloadUrl"]
	var textureUrl = ""
	if myData.has("textureUrl"):
		textureUrl = myData["textureUrl"]
	var iconUrl = myData["iconUrl"]
	var createdAt = myData["createdAt"]
	var equipSlot = myData["equipSlot"]
	
	var cachePath = await Client.downloadAccessoryModel(downloadUrl,id)
	var mesh = null
	if !cachePath.is_empty():
		var mtlPath = ""
		if cachePath.has("mtl"):
			mtlPath = cachePath["mtl"]
		mesh = ObjParse.from_path(cachePath["model"],mtlPath)
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var possibleLimbs = {}
	for v in charRef.get_children():
		possibleLimbs[v.name.to_lower()] = v
	print(equipSlot.to_lower())
	print(mesh_instance)
	possibleLimbs[equipSlot.to_lower()].add_child(mesh_instance)
	mesh_instance.scale = Vector3(.5,.5,.5)
	mesh_instance.position = Vector3(0,-.6,0)
	return mesh_instance

func generateCaptcha() -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var headers = ["Content-Type: application/json"]
	
	httpRequest.request(Global.masterIp + "/captcha/generate", headers, HTTPClient.METHOD_POST, "")
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {
		"success": false,
		"error": "Failed to generate CAPTCHA"
	}

func verifyCaptcha(captcha_id: String, answer: int) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"captcha_id": captcha_id,
		"answer": answer
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/captcha/verify", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {
		"success": false,
		"message": "Request failed"
	}

func registerWithCaptcha(username: String, password: String, gender: String, captcha_id: String, captcha_answer: int) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"username": username,
		"password": password,
		"gender": gender,
		"captcha_id": captcha_id,
		"captcha_answer": captcha_answer
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/auth/register_with_captcha", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {
		"status": "failed",
		"error": "Request failed with code: " + str(response[1])
	}

func subscribeToGlobalMessages(callback: Callable):
	message_callbacks.append(callback)
	
	print("connect to ws")
	
	if not ws or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		connectToMessageStream()
	else:
		printerr("has ws")

func connectToMessageStream():
	ws = WebSocketPeer.new()
	var ws_url = Global.masterIp.replace("http://", "ws://").replace("https://", "wss://")
	var err = ws.connect_to_url(ws_url + "/ws/messages")
	if err != OK:
		print("Failed to connect to message stream: ", err)
		return
	
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	timer.timeout.connect(func():
		_poll_messages()
		)
	add_child(timer)
	timer.start()

func _poll_messages():
	if not ws:
		return
	
	ws.poll()
	
	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count():
			var packet = ws.get_packet()
			var message_text = packet.get_string_from_utf8()
			var message = JSON.parse_string(message_text)
			if message:
				for callback in message_callbacks:
					callback.call(message)
	
	elif state == WebSocketPeer.STATE_CLOSED:
		await get_tree().create_timer(5.0).timeout
		connectToMessageStream()
		return

func changeUsername(new_username: String, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"new_username": new_username
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/account/change_username", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {
		"success": false,
		"error": "Request failed with code: " + str(response[1])
	}

func checkFreeUsername(token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/account/check_free_username", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {
		"success": false,
		"error": "Request failed with code: " + str(response[1])
	}

func changePassword(old_password: String, new_password: String, token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"old_password": old_password,
		"new_password": new_password
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/account/change_password", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {
		"success": false,
		"error": "Request failed with code: " + str(response[1])
	}

func processPurchase(token: String, product_id: String, purchase_token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"product_id": product_id,
		"purchase_token": purchase_token
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/payments/purchase", headers, HTTPClient.METHOD_POST, jsonString)
	
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

func processAdReward(token: String, ad_network: String, ad_unit_id: String, reward_amount: int, verification_data: Dictionary) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token,
		"ad_network": ad_network,
		"ad_unit_id": ad_unit_id,
		"reward_amount": reward_amount,
		"verification_data": verification_data
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/payments/ad_reward", headers, HTTPClient.METHOD_POST, jsonString)
	
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

func getCurrencyPackages(justReturn:bool=false) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var headers = ["Content-Type: application/json"]
	
	httpRequest.request(Global.masterIp + "/payments/packages", headers, HTTPClient.METHOD_GET, "")
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		if justReturn:
			return jsonResponse if jsonResponse != null else {}
		if jsonResponse.get("success",false):
			var packData = jsonResponse.get("data",{}).get("packages",[])
			var products = []
			if !packData.is_empty():
				for i in packData:
					var product_id = i["product_id"]
					products.append(product_id)
				
				if OS.get_name() == "Android" and payment and paymentConnected:
					payment.queryProductDetails(products, "inapp")
					await get_tree().create_timer(1.0).timeout
					payment.queryPurchasesAsync("inapp")
		return jsonResponse if jsonResponse != null else {}
	
	return {"error":"no_data"}

func getPaymentHistory(token: String) -> Dictionary:
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": token
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/payments/history", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		return jsonResponse if jsonResponse != null else {}
	
	return {}

func buy(product_id, purchase_type = ""):
	if !paymentConnected or !payment:
		purchase_failed.emit("Payment system not initialized")
		return false
	
	if !queried_product_details.has(product_id):
		print("Product details not loaded, attempting to reload...")
		await getCurrencyPackages()
		await get_tree().create_timer(2.0).timeout
		
		if !queried_product_details.has(product_id):
			purchase_failed.emit("Product details not loaded. Please try again.")
			return false
	
	recent_product_id = product_id
	recent_purchase_type = purchase_type
	
	var product_details = queried_product_details[product_id]
	var result = payment.purchase(product_details)
	
	if result.status != OK:
		purchase_failed.emit("Failed to initiate purchase: " + str(result))
		return false
	
	return true
