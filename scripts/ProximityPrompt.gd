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

var wasNotEnabled = false

var collision_shape: CollisionShape3D
var sphere_shape: SphereShape3D
var prompt_ui: Control
var progress_bar: ProgressBar
var label: Label
var touch_button: Button

func _init():
	setup_3d_components()

func _ready():
	setup_ui_components()

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
	prompt_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt_ui.visible = false
	
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(200, 80)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt_ui.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)
	
	label = Label.new()
	label.text = prompt_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = hold_duration
	progress_bar.value = 0
	progress_bar.custom_minimum_size = Vector2(180, 20)
	vbox.add_child(progress_bar)
	
	if OS.has_feature("mobile"):
		touch_button = Button.new()
		touch_button.text = "Hold to Interact"
		touch_button.custom_minimum_size = Vector2(180, 40)
		touch_button.button_down.connect(_on_touch_start)
		touch_button.button_up.connect(_on_touch_end)
		vbox.add_child(touch_button)
	
	get_viewport().add_child(prompt_ui)

func get_3d_node():
	return self

func _on_body_entered(body):
	if body.is_in_group("plr") or body.name == "Player":
		player_in_range = true
		show_prompt()

func _on_body_exited(body):
	if body.is_in_group("plr") or body.name == "Player":
		player_in_range = false
		hide_prompt()
		reset_progress()

func show_prompt():
	showing.emit()
	prompt_ui.visible = true
	update_prompt_position()

func hide_prompt():
	hiding.emit()
	prompt_ui.visible = false

func update_prompt_position():
	if not player_in_range:
		return
	
	var camera = get_viewport().get_camera_3d()
	if camera:
		var world_pos = global_position + prompt_offset
		var screen_pos = camera.unproject_position(world_pos)
		prompt_ui.global_position = screen_pos - prompt_ui.size / 2

func _process(delta):
	if !enabled:
		wasNotEnabled = true
		hide_prompt()
	elif wasNotEnabled:
		wasNotEnabled = false
		if player_in_range:
			show_prompt()
	if player_in_range:
		update_prompt_position()
		handle_input(delta)

func handle_input(delta):
	var should_hold = false
	
	if Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_E):
		should_hold = true
	
	if should_hold and not is_holding:
		start_hold()
	elif not should_hold and is_holding:
		stop_hold()
	
	if is_holding:
		hold_progress += delta
		progress_bar.value = hold_progress
		
		if hold_progress >= hold_duration:
			complete_prompt()

func _on_touch_start():
	if player_in_range:
		start_hold()

func _on_touch_end():
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
