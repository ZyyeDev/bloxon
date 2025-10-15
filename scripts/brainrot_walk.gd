extends Node3D

@export var speed: float = 20
@export var bName = ""
@export var UID = ""
@export var pGet = ""
@export var cost = 0
@export var generate = 0
@export var rarity = 0

var target_position: Vector3 = Vector3.ZERO
var has_target: bool = false
var oldcost = 0
var proximity_prompt = null

func _ready() -> void:  
	if Global.isClient:
		proximity_prompt = ProximityPrompt.new()
		proximity_prompt.prompt_text = "Collect"
		proximity_prompt.hold_duration = .25
		proximity_prompt.detection_radius = 8
		proximity_prompt.prompt_activated.connect(tryGrab)
		proximity_prompt.name = "ProximityPrompt"
		add_child(proximity_prompt)
		#print("ProximityPrompt added to brainrot: ", UID)
	
	$Cost.text = "$"+str(cost)
	$Generate.text = str(generate) + " $/s"
	$Name.text = bName
	
	if !Global.isClient:
		await get_tree().process_frame
		set_initial_target()
		$SendData.start()

func set_initial_target():
	if pGet != "":
		var player_house = Global.whatHousePlr(pGet)
		if player_house and player_house.ref and player_house.ref.plrSpawn:
			target_position = player_house.ref.plrSpawn.global_position
			has_target = true
			print("Set target to player house for: ", UID)
			return
	
	if Game and Game.workspace and Game.workspace.has_node("bbye"):
		target_position = Game.workspace.get_node("bbye").global_position
		has_target = true
		#print("Set target to bbye for: ", UID)
	else:
		has_target = false
		print("No target found for brainrot: ", UID)

func tryGrab():
	if Global.whatHouseIm().ref.getAvailableSpace() == null:
		Global.localPlayer.get_node("MainUi").addBottomMsg(
			"[outline_size=8][outline_color=#000000][color=#ff0000]You don't have space in your base![/color][/outline_color][/outline_size]",
			5)
		var snd = AudioStreamPlayer.new()
		snd.volume_db = -20
		snd.stream = load("res://assets/sounds/error.ogg")
		Global.localPlayer.add_child(snd)
		snd.play()
		Debris.addItem(snd,snd.stream.get_length())
		return
	
	if Global.localPlayer.get_node("moneyVal").Value >= cost:
		Global.localPlayer.get_node("MainUi").addBottomMsg("[outline_size=8][outline_color=#000000][color=#99FF66]Successfully purchased %s [/color][/outline_color][/outline_size]" % [bName], 5.0)
	
	if Global.isClient:
		Global.tryGrab(UID)

func _process(delta: float) -> void:
	if oldcost != cost and !Global.isClient:
		oldcost = cost
		rpc("updateCost", cost)
	
	#if pGet != "":
	#	speed = fastSpeed
	
	if !has_target:
		if !Global.isClient:
			set_initial_target()
		return
	
	var current_pos = global_transform.origin
	var adjusted_target = target_position
	adjusted_target.y = current_pos.y
	
	var direction = (adjusted_target - current_pos).normalized()
	global_position += direction * speed * delta
	
	# i fixed it, you are welcome 👍
	#if target_position != Vector3.ZERO && Global.isClient:
		# HACK: Fucking shit, idk there a fucking error where it creates brainrots out of nowhere??? 
		# im just fucking lazy to debug this shit, this fixes it god fucking damn
	#	if ((global_position.y <= target_position.y-1) and (global_position.y == 6 or target_position.y == 6 or target_position == Game.workspace.get_node("bbye").position)) or global_position.y == 0:
	#		queue_free()
		
	if Global.isClient: 
		return
	
	if Server.inMaintenance:
		global_position = target_position
	
	if global_position.distance_to(target_position) <= 7:
		if pGet == "":
			if UID in Global.brainrots:
				Global.brainrots.erase(UID)
			queue_free()
			Global.rpc("remove_brainrot", UID)
		else:
			Global.brainrotCollected(UID, self, pGet)

func set_target_position(new_target_pos: Vector3):
	target_position = new_target_pos
	has_target = true

func _on_send_data_timeout() -> void:
	if !Global.isClient:
		Global.sendBrainrotPos(UID, global_transform, global_position)

@rpc("authority","call_remote","reliable")
func updatePlayerTarget(player_uid: String):
	pGet = player_uid
	
	$Cost.text = "$" + str(cost)
	
	if Global.isClient and player_uid == Global.UID:
		if proximity_prompt:
			proximity_prompt.queue_free()
			proximity_prompt = null
	
	var player_house = Global.whatHousePlr(player_uid)
	if player_house and player_house.ref and player_house.ref.plrSpawn:
		set_target_position(player_house.ref.plrSpawn.global_position)
	else:
		print("Could not find player house for: ", player_uid)

@rpc("authority","call_remote","reliable") 
func updateCost(ncost):
	cost = ncost
	$Cost.text = "$"+str(ncost)

@rpc("authority", "call_remote", "unreliable")
func syncPosition(pos: Vector3, target_pos: Vector3, has_target_flag: bool):
	if Global.isClient:
		global_position = pos
		target_position = target_pos
		has_target = has_target_flag
