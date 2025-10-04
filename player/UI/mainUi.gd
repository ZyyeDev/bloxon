extends Control

@export var money = 0

@export var moneyLabel: Label
@export var TopMsgsContainer: VBoxContainer
@export var bottomMsgsContainer: VBoxContainer

@export var rebirthPanel: Panel

func _process(delta: float) -> void:
	if moneyLabel:
		moneyLabel.text = "$" + str(money)

@rpc("authority", "call_local", "reliable")
func addBottomMsg(msg: String, time: float):
	var label = RichTextLabel.new()
	
	label.bbcode_enabled = true
	
	label.text = msg
	
	label.fit_content = true
	
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = bottomMsgsContainer.size
	
	label.scroll_active = false
	label.modulate.a = 0
	
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_contents = false
	
	bottomMsgsContainer.add_child(label)
	bottomMsgsContainer.move_child(label, 0)
	
	await get_tree().process_frame
	
	var font_size = 32
	label.add_theme_font_size_override("normal_font_size", font_size)
	while label.get_content_height() > bottomMsgsContainer.size.y and font_size > 8:
		font_size -= 2
		label.add_theme_font_size_override("normal_font_size", font_size)
		await get_tree().process_frame
	
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	
	await get_tree().create_timer(time - 0.5).timeout
	
	if label and is_instance_valid(label):
		var fade_out = create_tween()
		fade_out.tween_property(label, "modulate:a", 0.0, 0.5)
		await fade_out.finished
		label.queue_free()

func _on_rebirth_button_pressed() -> void:
	rebirthPanel.visible = !rebirthPanel.visible

func _on_rebirth_confirm_pressed() -> void:
	pass # Replace with function body.
