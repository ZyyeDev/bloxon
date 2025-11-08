@icon("res://scripts/ProximityPrompt.gd")
extends Area3D
class_name ProximityPrompt

signal prompt_activated
signal start_holding
signal stop_holding
signal showing
signal hiding

@export var prompt_text: String = "Hold E"
@export var hold_duration: float = 2.0
@export var detection_radius: float = 5.0
@export var prompt_offset: Vector3 = Vector3(0, 2, 0)
@export var enabled = true

var player_in_range: bool = false
var is_holding: bool = false
var hold_progress: float = 0.0
var was_not_enabled = false
var camera: Camera3D

var collision_shape: CollisionShape3D
var sphere_shape: SphereShape3D
var prompt_ui: Control
var progress_bar: ProgressBar
var label: Label
var touch_button: Button
var panel: PanelContainer

var ui_scale: float = 1.0

func _init():
	ui_scale = 1.0 # 1.5 if is_mobile else 1.0
	setup_3d_components()

func _ready():
	setup_ui_components()
	camera = get_viewport().get_camera_3d()

func setup_3d_components():
	collision_shape = CollisionShape3D.new()
	sphere_shape = SphereShape3D.new()
	sphere_shape.radius = detection_radius
	collision_shape.shape = sphere_shape
	add_child(collision_shape)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func setup_ui_components():
	prompt_ui = Control.new()
	prompt_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_ui.z_index = 100
	
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 80) * ui_scale
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_color = Color(0.3, 0.6, 1.0, 0.8)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	
	prompt_ui.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	label = Label.new()
	label.text = prompt_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(16 * ui_scale))
	label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(label)
	
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = hold_duration
	progress_bar.value = 0
	progress_bar.custom_minimum_size = Vector2(180, 20) * ui_scale
	progress_bar.show_percentage = false
	
	var progress_style = StyleBoxFlat.new()
	progress_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	progress_style.corner_radius_top_left = 4
	progress_style.corner_radius_top_right = 4
	progress_style.corner_radius_bottom_left = 4
	progress_style.corner_radius_bottom_right = 4
	progress_bar.add_theme_stylebox_override("background", progress_style)
	
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.3, 0.7, 1.0, 1.0)
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	
	vbox.add_child(progress_bar)
	
	prompt_ui.visible = false
	get_viewport().add_child(prompt_ui)

func get_3d_node():
	return self

func _on_body_entered(body):
	if body.is_in_group("plr") or body.name == "Player":
		player_in_range = true
		if enabled:
			show_prompt()

func _on_body_exited(body):
	if body.is_in_group("plr") or body.name == "Player":
		player_in_range = false
		hide_prompt()
		reset_progress()

func show_prompt():
	if not enabled:
		return
	Global.currentProximityPrompt = self
	sphere_shape.radius = detection_radius
	showing.emit()
	prompt_ui.visible = true

func hide_prompt():
	if Global.currentProximityPrompt == self:
		_on_touch_end()
		Global.currentProximityPrompt = null
	sphere_shape.radius = detection_radius
	hiding.emit()
	prompt_ui.visible = false

func update_prompt_position():
	if not camera:
		camera = get_viewport().get_camera_3d()
		if not camera:
			return
	
	var world_pos = global_position + prompt_offset
	var screen_pos = camera.unproject_position(world_pos)
	
	await get_tree().process_frame
	if !is_instance_valid(panel): return
	var panel_size = panel.size
	prompt_ui.position = screen_pos - panel_size / 2

func _process(delta):
	if not enabled:
		if not was_not_enabled:
			was_not_enabled = true
			hide_prompt()
	elif was_not_enabled:
		was_not_enabled = false
		if player_in_range:
			show_prompt()
	
	if player_in_range and prompt_ui.visible:
		update_prompt_position()
		handle_input(delta)
	
	if is_holding:
		hold_progress += delta
		progress_bar.value = hold_progress
		
		if hold_progress >= hold_duration:
			complete_prompt()

func handle_input(delta):
	var should_hold = Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_E)
	
	if should_hold and not is_holding:
		start_hold()
	elif not should_hold and is_holding:
		stop_hold()

func _on_touch_start():
	if player_in_range and enabled:
		start_hold()

func _on_touch_end():
	if is_holding:
		stop_hold()

func start_hold():
	start_holding.emit()
	is_holding = true

func stop_hold():
	stop_holding.emit()
	is_holding = false
	reset_progress()

func reset_progress():
	hold_progress = 0.0
	progress_bar.value = 0

func complete_prompt():
	prompt_activated.emit()
	hide_prompt()
	reset_progress()
	is_holding = false

func _exit_tree():
	if prompt_ui and is_instance_valid(prompt_ui):
		prompt_ui.queue_free()
