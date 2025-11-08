extends Button

@export var blips : int

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE

func _process(delta: float) -> void:
	$VBoxContainer/Blips.text = "𝔹 " + str(blips)

func _on_pressed() -> void:
	$AudioStreamPlayer.play()
