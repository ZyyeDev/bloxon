extends CharacterBody3D
class_name player

@export_group("Online")
@export var uid : String
@export var localPlayer : bool

@export_group("Player")
@export var snap_vector : Vector3 = Vector3.DOWN 
@export var shiftlock : bool
@export var Havetool : bool
@export var tool : String
@export var isSlapping : bool = false
@export var cameraMiddle : Node3D
@export var cursorSpr : Sprite2D
@export var playerCollider : CollisionShape3D
@export var player_mesh : Node3D 
@export var head:MeshInstance3D
@export var Torso:MeshInstance3D
@export var RightArm:MeshInstance3D
@export var LeftArm:MeshInstance3D
@export var LeftLeg:MeshInstance3D
@export var RightLeg:MeshInstance3D
@export var toolHolding = -1
@export var brainrotHolding = ""

@export_group("Movement vars")
@export var walkspeed : float = 16
@export var jump_strength : float = 50
@export var gravity : float = 196.2
@export var step_height : float = 0.6
@export var step_check_distance : float = 1.0

@export var spring_arm_pivot : Node3D
@export var spawn_position : Vector3

@export_group("Mobile Controls")
@export var mobile_sensitivity : float = 1
@export var touch_deadzone : float = 10

@export_group("Others")
@export var moneyValue: IntValue
@export var rebirthsVal: IntValue
@export var BubbleBox: Sprite3D

var network_position: Vector3
var network_rotation: float
var network_velocity: Vector3
var movement_sync_timer: float = 0.0
var last_position: Vector3
var last_rotation: Vector3

var oldtoolHolding = -1
var toolHoldingInst = null

var _collider_margin : float
var grounded : bool
var was_grounded : bool
var force_stair_step : bool = false
var temp_step_height : float = 0
var desired_velocity : Vector3 = Vector3.ZERO

const ANIMATION_BLEND : float = 7.0
const LERP_VALUE : float = 0.15
const NETWORK_LERP_SPEED : float = 10.0
const SYNC_INTERVAL : float = 0.1
const _horizontal : Vector3 = Vector3(1,0,1)

var is_mobile : bool = false
var touch_start_pos : Vector2
var is_dragging : bool = false
var last_touch_pos : Vector2
var joystick_area : Rect2  
var camera_touch_index : int = -1 

var oldBrainrotHolding = ""
var oldBrainrotInst = null

func _ready():
	_collider_margin = playerCollider.shape.margin
	
	if localPlayer:
		Global.localPlayer = self
	
	is_mobile = true#OS.get_name() == "Android" or OS.get_name() == "iOS"
	
	var screen_size = get_viewport().get_visible_rect().size
	joystick_area = Rect2(0, 0, screen_size.x * 0.3, screen_size.y) 
	
	if localPlayer:
		set_process_input(true)
		movement_sync_timer = 0.0
		$bassSound.play()
		while not await Global.whatHouseIm():
			await Global.wait(.1)
		if await Global.whatHouseIm():
			var myhouse = await Global.whatHouseIm()
			spawn_position = myhouse.ref.plrSpawn.global_position
			global_position = spawn_position
	else:
		set_physics_process(false)
		network_position = global_position
		network_rotation = player_mesh.rotation.y
 
func get_or_create_override_material(mesh_instance: MeshInstance3D, surface_index: int = 0) -> Material:
	var override_material = mesh_instance.get_surface_override_material(surface_index)
	
	if override_material == null: 
		var original_material = mesh_instance.get_active_material(surface_index)
		if original_material:
			override_material = original_material.duplicate()
		else: 
			override_material = StandardMaterial3D.new()
		
		mesh_instance.set_surface_override_material(surface_index, override_material)
	
	return override_material

func changeColors(data):
	var bodyColors = data.bodyColors
	
	print(uid, " | ",bodyColors)
	
	if head:
		get_or_create_override_material(head).albedo_color = Color(bodyColors.head)
	if Torso:
		get_or_create_override_material(Torso).albedo_color = Color(bodyColors.torso)
	if RightArm:
		get_or_create_override_material(RightArm).albedo_color = Color(bodyColors.right_arm)
	if LeftArm:
		get_or_create_override_material(LeftArm).albedo_color = Color(bodyColors.left_arm)
	if LeftLeg:
		get_or_create_override_material(LeftLeg).albedo_color = Color(bodyColors.left_leg)
	if RightLeg:
		get_or_create_override_material(RightLeg).albedo_color = Color(bodyColors.right_leg)

func init():
	if await Global.whatHouseIm():
		var myhouse = await Global.whatHouseIm()
		spawn_position = myhouse.ref.plrSpawn.global_position
		global_position = spawn_position
	
	if localPlayer: 
		spring_arm_pivot = cameraMiddle
		last_position = global_position
		last_rotation = player_mesh.rotation
	else:
		if cameraMiddle:
			cameraMiddle.queue_free() 
		network_position = global_position
		network_rotation = player_mesh.rotation.y

func _physics_process(delta):
	was_grounded = grounded
	grounded = is_on_floor()
	desired_velocity = Vector3.ZERO
	
	if localPlayer:
		handle_local_physics(delta)
		handle_network_sync(delta)
	else:
		handle_remote_physics(delta)

func move_and_stair_step():
	stair_step_up()
	move_and_slide()
	stair_step_down()

func stair_step_down() -> void:
	if was_grounded == false || velocity.y >= 0: return
	
	var result = PhysicsTestMotionResult3D.new()
	var parameters = PhysicsTestMotionParameters3D.new()
	
	parameters.from = global_transform
	parameters.motion = Vector3.DOWN * step_height
	parameters.margin = _collider_margin
	
	if PhysicsServer3D.body_test_motion(get_rid(), parameters, result) == false:
		return
		
	global_transform = global_transform.translated(result.get_travel())
	apply_floor_snap()

func stair_step_up() -> void:
	if (grounded == false && force_stair_step == false): return
	
	var horizontal_velocity = velocity * _horizontal
	var testing_velocity = horizontal_velocity if horizontal_velocity != Vector3.ZERO else desired_velocity
	
	if testing_velocity == Vector3.ZERO: return
	
	var result = PhysicsTestMotionResult3D.new()
	var parameters = PhysicsTestMotionParameters3D.new()
	parameters.margin = _collider_margin
	
	var motion_transform = global_transform
	var distance = testing_velocity * get_physics_process_delta_time()
	parameters.from = motion_transform
	parameters.motion = distance
	
	if PhysicsServer3D.body_test_motion(get_rid(), parameters, result) == false:
		return
		
	var remainder = result.get_remainder()
	motion_transform = motion_transform.translated(result.get_travel())

	var step_up = step_height * Vector3.UP
	parameters.from = motion_transform
	parameters.motion = step_up
	PhysicsServer3D.body_test_motion(get_rid(), parameters, result)
	motion_transform = motion_transform.translated(result.get_travel())
	var step_up_distance = result.get_travel().length()

	parameters.from = motion_transform
	parameters.motion = remainder
	PhysicsServer3D.body_test_motion(get_rid(), parameters, result)
	motion_transform = motion_transform.translated(result.get_travel())
	
	parameters.from = motion_transform
	parameters.motion = Vector3.DOWN * step_up_distance
	
	if PhysicsServer3D.body_test_motion(get_rid(), parameters, result) == false:
		return
	
	motion_transform = motion_transform.translated(result.get_travel())
	
	var surfaceNormal = result.get_collision_normal(0)
	if (surfaceNormal.angle_to(Vector3.UP) > floor_max_angle): return

	global_position.y = motion_transform.origin.y

func handle_local_physics(delta):
	if Global.alrHasError: return
	var move_direction : Vector3 = Vector3.ZERO
	
	if !CoreGui.chatTexting:
		move_direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		move_direction.z = Input.get_action_strength("move_backwards") - Input.get_action_strength("move_forward")
	
	if move_direction.x != 0 or move_direction.z != 0:
		$animations.speed_scale = walkspeed/16
		$animations.play("walk")
	else:
		$animations.play("idle")
	
	move_direction = move_direction.rotated(Vector3.UP, spring_arm_pivot.rotation.y)
	
	if move_direction.length() > 0:
		move_direction = move_direction.normalized()
	
	velocity.y -= ((Global.fromStud(gravity)+(playerCollider.shape.size.y-1.4))*3) * delta
	
	if is_on_floor():
		velocity.x = move_direction.x * ((Global.fromStud(walkspeed)+(playerCollider.shape.size.x+Global.fromStud(2))*8))
		velocity.z = move_direction.z * ((Global.fromStud(walkspeed)+(playerCollider.shape.size.z+Global.fromStud(2))*12))
		
		if Input.is_action_just_pressed("jump") and !CoreGui.chatTexting:
			velocity.y = (Global.fromStud(jump_strength)+(playerCollider.shape.size.y-1.4)*6)
	else:
		velocity.x = move_direction.x * ((Global.fromStud(walkspeed)+(playerCollider.shape.size.x+Global.fromStud(2))*8))
		velocity.z = move_direction.z * ((Global.fromStud(walkspeed)+(playerCollider.shape.size.z+Global.fromStud(2))*12))

	if move_direction.length() > 0:
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, atan2(velocity.x, velocity.z), LERP_VALUE)

	move_and_stair_step()
	
	if global_position.y <= -50:
		die()

func handle_remote_physics(delta):
	velocity.y -= (Global.fromStud(gravity) * delta)*1
	
	move_and_slide()

func update_network_transform(pos: Vector3, rot_y: float):
	if !localPlayer:
		global_position = global_position.lerp(pos, NETWORK_LERP_SPEED * get_physics_process_delta_time())
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, rot_y, NETWORK_LERP_SPEED * get_physics_process_delta_time())

func handle_network_sync(delta):
	var pos_changed = global_position.distance_to(last_position) > 0.01
	var rot_changed = abs(player_mesh.rotation.y - last_rotation.y) > 0.01
	
	if pos_changed or rot_changed: 
		PlayerManager.updatePlayerPosition.rpc(uid, global_position, Vector3(0, player_mesh.rotation.y, 0))
		last_position = global_position
		last_rotation = player_mesh.rotation
	
	movement_sync_timer = 0.0

@rpc("any_peer", "call_remote", "unreliable")
func updatePlayerTransform(pos: Vector3, rot: float, vel: Vector3):
	if !localPlayer:
		network_position = pos
		network_rotation = rot
		network_velocity = vel

func setisSlappingFalse(cooldown):
	await get_tree().create_timer(cooldown-0.3).timeout
	isSlapping = false

func _input(event):
	if !localPlayer: return
	
	if is_mobile:
		handle_mobile_input(event)
	else:
		pass#handle_desktop_input(event)

func handle_mobile_input(event):
	if event is InputEventScreenTouch:
		if event.pressed: 
			if joystick_area.has_point(event.position): 
				return
			 
			camera_touch_index = event.index
			touch_start_pos = event.position
			last_touch_pos = event.position
			is_dragging = false
		else: 
			if event.index == camera_touch_index:
				is_dragging = false
				camera_touch_index = -1
	
	elif event is InputEventScreenDrag:  
		if event.index != camera_touch_index:
			return
			 
		if joystick_area.has_point(touch_start_pos):
			return
			
		var touch_delta = event.position - last_touch_pos
		
		if not is_dragging:
			var distance = event.position.distance_to(touch_start_pos)
			if distance > touch_deadzone:
				is_dragging = true
		
		if is_dragging and cameraMiddle: 
			spring_arm_pivot.rotation.y -= touch_delta.x * mobile_sensitivity * 0.01
			 
			if spring_arm_pivot.has_method("rotate_x"):
				spring_arm_pivot.rotation.x -= touch_delta.y * mobile_sensitivity * 0.01
				spring_arm_pivot.rotation.x = clamp(spring_arm_pivot.rotation.x, -PI/3, PI/3)
		
		last_touch_pos = event.position

@rpc("any_peer", "call_remote", "reliable")
func performSlap():
	$animations.play("slap")
	isSlapping = true
	if localPlayer:
		var slapCollider = load("res://player/colliders/slap_collider.tscn").instantiate()
		Game.GameContainer.add_child(slapCollider)
		var forward_direction = -transform.basis.z.normalized()
		var new_position = global_transform.origin + forward_direction * 3.0
		slapCollider.global_transform.origin = global_transform.origin + forward_direction * 3.0
		slapCollider.creatorUID = uid
		Debris.addItem(slapCollider, 0.5)
	setisSlappingFalse(1)

func _process(_delta):
	if oldBrainrotHolding != brainrotHolding:
		oldBrainrotHolding = brainrotHolding
		if oldBrainrotInst:
			oldBrainrotInst.queue_free()
			oldBrainrotInst = null
		if oldBrainrotInst == "":
			$animations/AnimationPlayer.stop()
		else:
			$animations/AnimationPlayer.play("holdBrainrot")
			var inst = load("res://brainrots/models/%s.tscn" % brainrotHolding).instantiate()
			oldBrainrotInst = inst
			inst.position = $StealBrainrotPosition.position
			inst.rotation = $StealBrainrotPosition.rotation
			add_child(inst)
	
	if !localPlayer: return
	if oldtoolHolding != toolHolding:
		oldtoolHolding = toolHolding
		if toolHoldingInst:
			toolHoldingInst.queue_free()
			toolHoldingInst = null
		if toolHolding != -1:
			if ToolController.getToolById(toolHolding):
				var inst = load("res://assets/Tools/"+ToolController.getToolById(toolHolding).Name).instantiate()
				$"Node3D/Right Arm/ToolPos".add_child(inst)
				toolHoldingInst = inst
	if Global.localPlayer and Global.localPlayer != self:
		queue_free()
	$MainUi.money = moneyValue.Value
	shiftlock = cameraMiddle.shiftlock if cameraMiddle else false
	if shiftlock:
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var camera_rotation = spring_arm_pivot.rotation.y
		player_mesh.rotation.y = camera_rotation + PI
		cursorSpr.visible = true
	else:
		cursorSpr.visible = false

func die():
	global_position = spawn_position
	$dieSound.play()
	if localPlayer:
		rpc("syncDie")

@rpc("any_peer", "call_remote", "reliable")
func syncDie():
	global_position = spawn_position

#@rpc("authority","call_remote","reliable")
func addBottomMsg(msg,time):
	$MainUi.addBottomMsg(msg,time)

func addBubbleBox(msg):
	var msgins = load("res://Resources/chatMessage.tscn").instantiate()
	msgins.text = msg
	
	BubbleBox.get_node("SubViewport").get_node("VBoxContainer").add_child(msgins)
	BubbleBox.move_child(msgins, 0)
	Debris.addItem(msgins,5)
	await Global.wait(4)
	if is_instance_valid(msgins):
		if msgins:
			msgins.Hide()
