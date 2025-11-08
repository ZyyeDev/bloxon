extends Control

var timeoutConnection = false

@export var infoLabel:Label
var assetsPreload = [
	"res://Resources/house.tscn",
	"res://Resources/brainrot_walk.tscn",
	"res://scenes/mainGame.tscn"
]

# this is so all menus stay in here (music persistancy and some other things ill need too)
var oldScene = null
var maintenance = false

func _ready():
	if !Global.isClient: return
	var args = OS.get_cmdline_args()
	if "--pfp-render" in args: return
	
	var maintenanceRq = await Client.checkMaintenance()
	maintenance = maintenanceRq.get("maintenance",false)
	print("maintenance ",maintenance)
	if maintenance:
		$Error.play()
		var box = Global.errorMessage(
			"Servers are currently on maintenance. Please come back later!",
			Global.ERROR_CODES.MAINTENANCE,
			"Servers Maintenance",
			"Retry",
			func():
				get_tree().reload_current_scene()
				#heckAuth()
		)
		return
	oldScene = $scene
	infoLabel.text = "Preloading assets..."
	## preload thing, disabled because it wasnt that useful
	if false:
		for path in assetsPreload:
			infoLabel.text = "Loading: %s..." % path
			await get_tree().process_frame 
			var res = load(path)
			if res:
				print("Preloaded: ", path)
			else:
				push_warning("Failed to load: " + path)
	infoLabel.text = "Connecting to server..."
	if LocalData.fileExists("data.dat"):
		var data = LocalData.loadData("data.dat")
		Global.user_id = data.get("user_id", -1)
		Global.token = data.get("token", "")
		Global.volume = data.get("volume", 9)
		Global.graphics = data.get("graphics", 9)
		CoreGui.updateVolume()
		CoreGui.updateGraphics()
		print(data)
	checkAuth()

func checkAuth():
	var json_data = {
		"token": Global.token
	}
	var json_string = JSON.stringify(json_data)
	var headers = ["Content-Type: application/json"]
	var http = HTTPRequest.new()
	add_child(http)
	http.timeout = 10
	http.request(
		Global.masterIp + "/auth/validate",
		headers,
		HTTPClient.METHOD_POST,
		json_string
		)
	http.request_completed.connect(_on_validate_completed)
	http.request_completed.connect(func():
		http.queue_free()
	)

func _on_validate_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	Client.http.request_completed.disconnect(_on_validate_completed)
	
	print(result,response_code)
	
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		if parse_result == OK:
			var response = json.data
			print("response: ",response)
			if response.has("status") and response["status"] == "valid":
				Global.user_id = response["user_id"]
				Global.avatarData = await Client.getAvatar(Global.user_id,Global.token)
				print(Global.avatarData)
				Global.username = response["username"]
				Global.canSave = true
				#$Done.play()
				changeTo("res://scenes/menus/mainMenu.tscn")
				print("Token valid, user_id: ", Global.user_id)
			else:
				if !timeoutConnection:
					Global.canSave = true
					changeTo("res://scenes/menus/LoginRegister.tscn")
				print("Token validation failed")
				Global.token = ""
				Global.user_id = 0
		else:
			if !timeoutConnection:
				Global.canSave = true
				changeTo("res://scenes/menus/LoginRegister.tscn")
			print("Failed to parse validation response")
	else:
		print("Token validation failed with code: ", response_code)
		if response_code == 0:
			connectionError()
		Global.token = ""
		Global.user_id = 0
		if !timeoutConnection:
			Global.canSave = true
			changeTo("res://scenes/menus/LoginRegister.tscn")

func connectionError():
	$Error.play()
	var box = Global.errorMessage("There was a problem reaching the servers. Please try again later!",Global.ERROR_CODES.SERVER_REACH,"Connection Error","Retry",
	func():
		#get_tree().reload_current_scene()
		checkAuth()
	)
	self.add_child(box)

func _on_timer_timeout() -> void:
	if maintenance: return
	timeoutConnection = true
	connectionError()

func changeTo(path):
	var thing = load(path).instantiate()
	oldScene.queue_free()
	oldScene = thing
	add_child(thing)

func _on_music_finished() -> void:
	$Music.play()
