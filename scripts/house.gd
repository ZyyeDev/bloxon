extends Node3D
class_name house

@export var id = -1
@export var plrAssigned = ""
@export var locked = true
@export var plrSpawn :Node3D
@export var below : MeshInstance3D
@export var up : MeshInstance3D
@export var belowCol : CollisionShape3D
@export var upCol : CollisionShape3D
@export var brainrotPositionContainter:Node3D
@export var brainrots = {}

@export var lockSound:AudioStreamPlayer3D

var oldBrainrots = {}
var brainrotsRef = {}

func _ready() -> void:
	while id == -1: 
		await Global.wait(1)
	
	var index = 0
	
	for i in brainrotPositionContainter.get_children():
		brainrots[i.name] = {
			"brainrot" = {
				"id" = "",
				"UID" = "",
				"generate" = 0,
				"modifiers" = {}
			},
			"brRef" = null,
			"money" = 0,
			"ref" = i,
			"moneyLabel" = i.get_node("Label3D"),
			"index" = index
		}
		
		for n in i.get_children():
			if n.name == "Area3D":
				var current_index = index
				n.body_entered.connect(func (body: Node3D):
					if Global.isClient and body == Global.localPlayer: 
						print("Collecting money from slot index: ", current_index)
						Global.rpc_id(1, "collectMoney", Global.UID, current_index)
				)
			elif n.name != "Label3D":
				n.queue_free()
		
		index += 1
	
	if !Global.isClient:
		if id in Global.houses:
			Global.houses[id]["brainrots"] = brainrots
		print("House ", id, " starting money timer")
		$MoneyTimer.wait_time = 1.0
		$MoneyTimer.timeout.connect(_on_money_timer_timeout)
		$MoneyTimer.start()
	
	$Timer.start()

func _process(delta: float) -> void:
	if plrAssigned == "": 
		locked = false
	
	below.visible = locked
	up.visible = locked
	
	if Global.UID != plrAssigned: 
		belowCol.disabled = !locked
		upCol.disabled = !locked
	else: 
		belowCol.disabled = true
		upCol.disabled = true
	
	if $Timer.time_left > 0:
		$Label3D.text = str(int(floor($Timer.time_left)))
	else:
		$Label3D.text = ""
 
	for slot_name in brainrots:
		var slot = brainrots[slot_name]
		if slot.has("moneyLabel"):
			if slot["brainrot"]["id"] != "":
				slot["moneyLabel"].text = "$" + str(int(slot["money"]))
			else:
				slot["moneyLabel"].text = ""

func _on_money_timer_timeout() -> void:
	if Global.isClient:
		return
	
	var money_updated = false
	var updated_brainrots = brainrots.duplicate(true)
	
	for slot_name in updated_brainrots:
		var slot = updated_brainrots[slot_name]
		if slot["brainrot"]["id"] != "":
			var generate_amount = slot["brainrot"]["generate"] 
			if generate_amount > 0:
				slot["money"] += generate_amount
				money_updated = true 
	
	if money_updated:
		brainrots = updated_brainrots
		if id in Global.houses:
			Global.houses[id]["brainrots"] = updated_brainrots
		rpc("syncMoney", updated_brainrots) 

@rpc("authority", "call_remote", "reliable")
func syncMoney(updated_brainrots_data):
	if Global.isClient:
		for slot_name in updated_brainrots_data:
			if brainrots.has(slot_name):
				brainrots[slot_name]["money"] = updated_brainrots_data[slot_name]["money"]

func _on_timer_timeout() -> void:
	unblockBase(plrAssigned)
	if !Global.isClient:
		rpc("unblockBase", plrAssigned)
	$Timer.stop()

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("plr"):
		if body.uid == plrAssigned:
			blockBase(body.uid)
			if !Global.isClient:
				rpc("blockBase", body.uid)

@rpc("any_peer", "call_remote", "reliable")
func blockBase(senderUID):
	if plrAssigned == senderUID:
		if not locked:
			if Global.isClient:
				Global.localPlayer.get_node("MainUi").addBottomMsg("[outline_size=8][outline_color=#000000][color=#99FF66]You locked your base for 60 Seconds![/color][/outline_color][/outline_size]", 5.0)
				var snd = AudioStreamPlayer.new()
				snd.volume_db = -20
				snd.stream = load("res://assets/sounds/correctSound.wav")
				Global.localPlayer.add_child(snd)
				snd.play()
				Debris.addItem(snd,snd.stream.get_length())
			$Timer.wait_time = 60
			$Timer.start()
			locked = true
		else: pass
			#Global.localPlayer.get_node("MainUi").addBottomMsg("[outline_size=8][outline_color=#000000][color=#99FF66][/color][/outline_color][/outline_size]", 5.0)
			#var snd = AudioStreamPlayer.new()
			#snd.volume_db = -20
			#snd.stream = load("res://assets/sounds/error.ogg")
			#Global.localPlayer.add_child(snd)
			#snd.play()
			#Debris.addItem(snd,snd.stream.get_length())

@rpc("any_peer", "call_remote", "reliable")
func unblockBase(senderUID):
	if plrAssigned == senderUID:
		if Global.isClient:
			pass
		if locked:
			locked = false

@rpc("any_peer", "call_remote", "reliable")  
func updateBrainrots(brainrotsList):
	print("House ", id, " updating brainrots")
	
	for slot_name in brainrots:
		if brainrots[slot_name].get("brRef") and is_instance_valid(brainrots[slot_name]["brRef"]):
			brainrots[slot_name]["brRef"].queue_free()
			brainrots[slot_name]["brRef"] = null
	
	for slot_name in brainrotsList:
		if brainrots.has(slot_name):
			brainrots[slot_name]["brainrot"] = brainrotsList[slot_name]["brainrot"].duplicate(true)
			brainrots[slot_name]["money"] = brainrotsList[slot_name]["money"]
			
			var brainrot_id = brainrots[slot_name]["brainrot"]["id"]
			print("  Slot ", slot_name, ": id='", brainrot_id, "' money=", brainrots[slot_name]["money"])
			
			if brainrot_id != "":
				var model_path = "res://brainrots/models/" + brainrot_id + ".tscn"
				print("    Loading model from: ", model_path)
				if ResourceLoader.exists(model_path):
					var brainrotN = load(model_path).instantiate()
					brainrots[slot_name]["brRef"] = brainrotN
					brainrotPositionContainter.add_child(brainrotN)
					brainrotN.global_position = brainrots[slot_name]["ref"].global_position
					brainrotN.global_rotation = brainrots[slot_name]["ref"].global_rotation
					
					var tryGrab = func():
						Global.trySteal(brainrots[slot_name]["brainrot"]["uid"],plrAssigned)
					
					var proximity_prompt = ProximityPrompt.new()
					if Global.UID == plrAssigned:
						proximity_prompt.prompt_text = "Sell"
					else:
						proximity_prompt.prompt_text = "Steal"
					proximity_prompt.hold_duration = .5
					proximity_prompt.detection_radius = 10
					proximity_prompt.prompt_activated.connect(tryGrab)
					proximity_prompt.name = "ProximityPrompt"
					brainrotN.add_child(proximity_prompt)
					
					print("    Spawned brainrot visual '", brainrot_id, "' at slot ", slot_name)
				else:
					print("    ERROR: Model not found at ", model_path)
	
	if !Global.isClient and id in Global.houses:
		Global.houses[id]["brainrots"] = brainrots.duplicate(true)

@rpc("authority", "call_remote", "reliable")
func syncHouseState(assigned_player: String, is_locked: bool, timer_time: float):
	plrAssigned = assigned_player
	locked = is_locked
	if timer_time > 0:
		$Timer.wait_time = timer_time
		$Timer.start()

func collectBrainrot(brId):
	var where = getAvailableSpace()
	if where != null:
		var newList = {}
		for slot_name in brainrots:
			newList[slot_name] = brainrots[slot_name].duplicate(true)
		
		newList[where]["brainrot"]["id"] = brId
		print("Collecting brainrot: ", brId, " into slot: ", where)
		var temp = load("res://brainrots/"+brId+".tscn").instantiate()
		newList[where]["brainrot"]["generate"] = temp.generate
		
		temp.queue_free()
		newList[where]["brainrot"]["UID"] = str(Time.get_unix_time_from_system()) + str(randi())
		newList[where]["money"] = 0
		
		brainrots = newList
		if !Global.isClient and id in Global.houses:
			Global.houses[id]["brainrots"] = newList
		
		updateBrainrots(newList)
		if !Global.isClient:
			print("Broadcasting brainrot update to clients")
			rpc("updateBrainrots", newList)

func getAvailableSpace():
	for i in brainrots:
		var brainrotData = brainrots[i]["brainrot"]
		if brainrotData["id"] == "":
			return i
	return null
