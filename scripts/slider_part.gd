extends Panel

@export var id = 0
@export var toggled = true

signal pressed

func _process(delta: float) -> void:
	if toggled:
		modulate = Color(1,1,1)
	else:
		modulate = Color(0,0,0)

func _on_button_pressed() -> void:
	pressed.emit()
