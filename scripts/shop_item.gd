extends Panel

@export var itemName = ""
@export var Cost = 0

@export var itemNameLabel:Label
@export var CostLabel:Label

signal pressed

func _ready() -> void:
	itemNameLabel.text = itemName
	CostLabel.text = "𝔹 " + str(int(Cost))

func _on_button_pressed() -> void:
	pressed.emit()
