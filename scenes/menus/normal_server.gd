extends Panel

@export var plrsLabel :Label
@export var pingLabel :Label

@export var UID = ""

@export var plrs = 0
@export var maxPlrs = 0
@export var ping = 0

@export var ip = ""
@export var port:int

func _process(delta: float) -> void:
	if ping < 0: ping = 0
	plrsLabel.text = str(int(plrs))+"/"+str(int(maxPlrs))
	pingLabel.text = str(int(ping))+" ms"

func _on__button_95_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/mainGame.tscn")
	Client.connectToServer(ip, int(port))
