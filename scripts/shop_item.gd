extends Panel

@export var spriteTexture:Texture
@export var itemName = ""
@export var Cost = 0

@export var itemNameLabel:Label
@export var CostLabel:Label
@export var sprite2d:Sprite2D

signal pressed

func _ready() -> void:
	itemNameLabel.text = itemName
	CostLabel.text = "𝔹 " + str(int(Cost))
	var panel = get_theme_stylebox("panel").duplicate()
	panel.bg_color = Color.from_string("2f2f2f",Color(47,47,47))
	add_theme_stylebox_override("panel",panel)

func light():
	var panel = get_theme_stylebox("panel").duplicate()
	panel.bg_color = Color.from_string("393939",Color(57,57,57))
	add_theme_stylebox_override("panel",panel)

func normal():
	var panel = get_theme_stylebox("panel").duplicate()
	panel.bg_color = Color.from_string("2f2f2f",Color(47,47,47))
	add_theme_stylebox_override("panel",panel)

func _on_button_pressed() -> void:
	pressed.emit()

func _process(delta: float) -> void:
	if sprite2d.texture != spriteTexture:
		sprite2d.texture = spriteTexture
