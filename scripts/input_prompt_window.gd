extends Panel
class_name InputPromptWindow

@export var promptText = ""
@export var placeholderText = ""
@export var text = ""

signal confirm_pressed(inputText:String)
signal cancel_pressed

func _ready() -> void:
	$AudioStreamPlayer.play()

func _process(delta: float) -> void:
	$BG/VBoxContainer/RichTextLabel.text = promptText
	$BG/VBoxContainer/LineEdit.placeholder_text = placeholderText
	text = $BG/VBoxContainer/LineEdit.text

func _on_confirm_pressed() -> void:
	var pressedSnd:AudioStreamPlayer = $pressed.duplicate()
	if pressedSnd:
		pressedSnd.reparent(get_tree().current_scene)
		pressedSnd.play()
	Debris.addItem(pressedSnd,pressedSnd.stream.get_length())
	confirm_pressed.emit($BG/VBoxContainer/LineEdit.text)

func _on_cancel_pressed() -> void:
	var pressedSnd:AudioStreamPlayer = $pressed.duplicate()
	pressedSnd.reparent(get_tree().current_scene)
	pressedSnd.play()
	Debris.addItem(pressedSnd,pressedSnd.stream.get_length())
	cancel_pressed.emit()
	queue_free()
