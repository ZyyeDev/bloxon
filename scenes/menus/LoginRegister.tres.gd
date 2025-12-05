extends Control

@export var status_label: RichTextLabel
@export var title_label: Label

@export var username_input: LineEdit
@export var password_input: LineEdit
@export var confirm_password_input: LineEdit

@export var gender_container: HBoxContainer

@export var male_button: Button
@export var female_button: Button
@export var none_button: Button

@export var register_button: Button
@export var login_button: Button
@export var switch_mode_button: Button  

var username: String = ""
var http_request: HTTPRequest
var is_register: bool = true
var selected_gender: String = "none"

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)
	
	male_button.pressed.connect(func(): update_gender_selection("male"))
	female_button.pressed.connect(func(): update_gender_selection("female"))
	none_button.pressed.connect(func(): update_gender_selection("none"))

func _on_switch_mode_pressed():
	is_register = !is_register
	update_auth_mode()

func _on_register_pressed():
	if not is_register:
		return
		
	var user = username_input.text.strip_edges()
	var password = password_input.text
	var confirm_password = confirm_password_input.text
	
	if user.length() < 3 or user.length() > 20:
		update_status("Username must be 3-20 characters", "red")
		return
	
	if password.length() < 6:
		update_status("password must be at least 6 characters", "red")
		return
		
	if password != confirm_password:
		update_status("passwords do not match", "red")
		return
	
	var data = {
		"username": user,
		"password": password,
		"gender": selected_gender
	}
	
	make_request("POST", "/auth/register", data, "register")
	update_status("Creating account...", "yellow")

func _on_login_pressed():
	if is_register:
		return
		
	var user = username_input.text.strip_edges()
	var password = password_input.text
	
	if user.is_empty() or password.is_empty():
		update_status("Please enter username and password", "red")
		return
	
	var data = {
		"username": user,
		"password": password
	}
	
	make_request("POST", "/auth/login", data, "login")
	update_status("Logging in...", "yellow")

# it looks a bit ugly to me tbh
func update_gender_selection(gender: String):
	selected_gender = gender
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.3, 0.35, 0.45)
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	
	var selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(0.2, 0.6, 0.8)
	selected_style.corner_radius_top_left = 6
	selected_style.corner_radius_top_right = 6
	selected_style.corner_radius_bottom_left = 6
	selected_style.corner_radius_bottom_right = 6
	
	male_button.add_theme_stylebox_override("normal", normal_style)
	female_button.add_theme_stylebox_override("normal", normal_style)
	none_button.add_theme_stylebox_override("normal", normal_style)
	
	match gender:
		"male":
			male_button.add_theme_stylebox_override("normal", selected_style)
		"female":
			female_button.add_theme_stylebox_override("normal", selected_style)
		"none":
			none_button.add_theme_stylebox_override("normal", selected_style)

func update_auth_mode():
	if is_register:
		title_label.text = "SIGN UP AND START HAVING FUN!"
		confirm_password_input.visible = true
		confirm_password_input.get_parent().get_child(confirm_password_input.get_index() - 1).visible = true
		gender_container.visible = true
		gender_container.get_parent().get_child(gender_container.get_index() - 1).visible = true
		register_button.visible = true
		login_button.visible = false
		switch_mode_button.text = "Already have an account? Log in"
	else:
		title_label.text = "LOG IN TO YOUR ACCOUNT"
		confirm_password_input.visible = false
		confirm_password_input.get_parent().get_child(confirm_password_input.get_index() - 1).visible = false
		gender_container.visible = false
		gender_container.get_parent().get_child(gender_container.get_index() - 1).visible = false
		register_button.visible = false
		login_button.visible = true
		switch_mode_button.text = "Don't have an account? Sign up"

func make_request(method: String, endpoint: String, data: Dictionary, request_type: String):
	var url = Global.masterIp + endpoint
	print(url)
	var headers = ["Content-Type: application/json"]
	var json_data = JSON.stringify(data)
	
	http_request.set_meta("request_type", request_type)
	
	if method == "POST":
		http_request.request(url, headers, HTTPClient.METHOD_POST, json_data)
	else:
		http_request.request(url, headers, HTTPClient.METHOD_GET)

func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var request_type = http_request.get_meta("request_type", "")
	var response_text = body.get_string_from_utf8()
	
	print(response_code, " | ", response_text, " | ",request_type)
	
	if response_code != 200:
		var error_msg = "Request failed"
		if response_code == 429:
			error_msg = "Rate Limited"
		elif response_code == 400:
			error_msg = "Missing Username Or Password"
		elif response_code == 304:
			error_msg = "user not found"
		elif response_code == 401:
			error_msg = "Invalid Password"
		if not response_text.is_empty():
			var json = JSON.new()
			if json.parse(response_text) == OK:
				var data = json.get_data()
				if data.has("error"):
					error_msg = str(data.error).replace("_", " ").capitalize()
		
		update_status(error_msg, "red")
		return
	
	var json = JSON.new()
	if json.parse(response_text) != OK:
		update_status("Invalid server response", "red")
		return
	
	var data = json.get_data()
	handle_response(request_type, data)

func handle_response(request_type: String, data: Dictionary):
	match request_type:
		"register":
			if data.has("token"):
				Global.username = data.username
				Global.token = data.token
				Global.user_id = data.user_id
				Global.saveLocal()
				get_parent().changeTo("res://scenes/menus/mainMenu.tscn")
			else:
				update_status("Registration failed", "red")
		
		"login":
			if data.has("token"):
				Global.username = data.username
				Global.token = data.token
				Global.user_id = data.user_id
				Global.saveLocal()
				get_parent().changeTo("res://scenes/menus/mainMenu.tscn")
			else:
				update_status("Login failed", "red")

func update_status(message: String, color: String = "white"):
	var color_code = ""
	match color:
		"red":
			color_code = "#ff6b6b"
		"green":
			color_code = "#51cf66"
		"yellow":
			color_code = "#ffd43b"
		"blue":
			color_code = "#74c0fc"
		_:
			color_code = "#ffffff"
	
	status_label.text = "[center][color=" + color_code + "]" + message + "[/color][/center]"
