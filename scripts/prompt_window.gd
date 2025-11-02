extends Panel
class_name promptWindow

@export var text = ""

signal confirm_pressed
signal cancel_pressed

func _ready() -> void:
	$AudioStreamPlayer.play()

func _process(delta: float) -> void:
	$BG/RichTextLabel.text = text

func _on_confirm_pressed() -> void:
	var pressedSnd:AudioStreamPlayer = $pressed.duplicate()
	pressedSnd.reparent(get_tree().current_scene)
	pressedSnd.play()
	Debris.addItem(pressedSnd,pressedSnd.stream.get_length())
	confirm_pressed.emit()

func _on_cancel_pressed() -> void:
	var pressedSnd:AudioStreamPlayer = $pressed.duplicate()
	pressedSnd.reparent(get_tree().current_scene)
	pressedSnd.play()
	Debris.addItem(pressedSnd,pressedSnd.stream.get_length())
	cancel_pressed.emit()
