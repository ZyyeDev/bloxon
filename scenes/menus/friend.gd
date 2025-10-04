extends Control

@export var uName = "PLAYER_NAME"
@export var uId = 0

@export var pfp = ""

@export var isOnline = true
@export var serverId = ""

@export var uLabel :Label
@export var infoPanel:Panel

var texture = null

signal pressed

func _ready() -> void:
	infoPanel.visible = false
	while uId == 0:
		await Global.wait(.1)
	if pfp == "":
		texture = await Client.getPlayerPfpTexture(uId,Global.token)
	else:
		texture = await Client.loadTextureFromUrl(pfp)
	if texture == null:
		texture = load("res://assets/images/fallbackPfp.png") as Texture

func _process(delta: float) -> void:
	uLabel.text = uName
	$Online.visible = isOnline
	if texture != null:
		$Sprite2D.texture = texture

func _on__button_40_pressed() -> void:
	pressed.emit()

func _on_join_pressed() -> void: 
	pass
