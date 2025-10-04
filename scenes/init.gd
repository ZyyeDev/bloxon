extends Control

var timeoutConnection = false

func _ready():
	if !Global.isClient: return
	if LocalData.file_exists("data.dat"):
		var data = LocalData.loadData("data.dat")
		Global.user_id = data["user_id"]
		Global.token = data["token"]
		print(data)
	var json_data = {
		"token": Global.token
	}
	var json_string = JSON.stringify(json_data)
	var headers = ["Content-Type: application/json"]
	Client.http.request(
		Global.masterIp + "/auth/validate",
		headers,
		HTTPClient.METHOD_POST,
		json_string
		)
	Client.http.request_completed.connect(_on_validate_completed)

func _on_validate_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	Client.http.request_completed.disconnect(_on_validate_completed)
	
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		if parse_result == OK:
			var response = json.data
			if response.has("status") and response["status"] == "valid":
				Global.user_id = response["user_id"]
				Global.avatarData = await Client.getAvatar(Global.user_id,Global.token)
				print(Global.avatarData)
				Global.username = response["username"]
				Global.canSave = true
				get_tree().change_scene_to_file("res://scenes/menus/mainMenu.tscn")
				print("Token valid, user_id: ", Global.user_id)
			else:
				if !timeoutConnection:
					Global.canSave = true
					get_tree().change_scene_to_file("res://scenes/menus/LoginRegister.tscn")
				print("Token validation failed")
				Global.token = ""
				Global.user_id = 0
		else:
			if !timeoutConnection:
				Global.canSave = true
				get_tree().change_scene_to_file("res://scenes/menus/LoginRegister.tscn")
			print("Failed to parse validation response")
	else:
		print("Token validation failed with code: ", response_code)
		if response_code == 0:
			connectionError()
		Global.token = ""
		Global.user_id = 0
		if !timeoutConnection:
			Global.canSave = true
			get_tree().change_scene_to_file("res://scenes/menus/LoginRegister.tscn")

func connectionError():
	var box = Global.errorMessage("There was a problem reaching the servers. Please try again later!",Global.ERROR_CODES.SERVER_REACH,"Connection Error","Retry",func():get_tree().reload_current_scene())
	self.add_child(box)

func _on_timer_timeout() -> void:
	timeoutConnection = true
	connectionError()
