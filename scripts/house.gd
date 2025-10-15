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

var brainrotTemplate = {
	"brainrot" = {
		"id" = "",
		"UID" = "",
		"generate" = 0,
		"modifiers" = {}
	},
	"brRef" = null,
	"money" = 0,
	"ref" = null,
	"proximity_prompt" = null,
	"moneyLabel" = null,
	"beingSteal" = false,
	"stealing" = false,
	"index" = 0
}

func _ready() -> void:
	while id == -1: 
		await Global.wait(1)
	
	var index = 0
	
	for i in brainrotPositionContainter.get_children():
		var dictionary = brainrotTemplate.duplicate(true)
		dictionary.ref = i
		dictionary.moneyLabel = i.get_node("Label3D")
		dictionary.index = index
		
		brainrots[i.name] = dictionary
		
		for n in i.get_children():
			if n.name == "Area3D":
				var current_index = index
				n.body_entered.connect(func (body: Node3D):
					if Global.isClient and body == Global.localPlayer:
						if not str(Global.UID) == str(plrAssigned): return
						Global.rpc_id(1, "collectMoney", Global.UID, current_index)
						if brainrots[i.name]["money"] > 0:
							var snd = AudioStreamPlayer.new() 
							snd.volume_db = -15
							snd.stream = load("res://assets/sounds/cash register.ogg")
							CoreGui.add_child(snd)
							snd.play()
							Debris.addItem(snd,snd.stream.get_length())
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
		if slot.has("moneyLabel") and slot["moneyLabel"]:
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
			if brainrots.has(slot_name) and updated_brainrots_data.has(slot_name):
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
				if str(Global.UID) == str(plrAssigned):
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

@rpc("any_peer", "call_remote", "reliable")
func unblockBase(senderUID):
	if plrAssigned == senderUID:
		if Global.isClient:
			pass
		if locked:
			locked = false

@rpc("any_peer", "call_remote", "reliable")  
func updateBrainrots(brainrotsList): 
	for slot_name in brainrots:
		if brainrots[slot_name].has("proximity_prompt") and brainrots[slot_name]["proximity_prompt"]:
			if is_instance_valid(brainrots[slot_name]["proximity_prompt"]):
				brainrots[slot_name]["proximity_prompt"].queue_free()
			brainrots[slot_name]["proximity_prompt"] = null
		
		if brainrots[slot_name].has("brRef") and brainrots[slot_name]["brRef"]:
			if is_instance_valid(brainrots[slot_name]["brRef"]):
				brainrots[slot_name]["brRef"].queue_free()
			brainrots[slot_name]["brRef"] = null
	
	for slot_name in brainrotsList:
		if brainrots.has(slot_name):
			brainrots[slot_name]["brainrot"] = brainrotsList[slot_name]["brainrot"].duplicate(true)
			brainrots[slot_name]["money"] = brainrotsList[slot_name]["money"]
			
			var brainrot_id = brainrots[slot_name]["brainrot"]["id"]
			print("  Slot ", slot_name, ": id='", brainrot_id, "' money=", brainrots[slot_name]["money"])
			
			var bcost = 0
			var bgenerate = brainrotsList[slot_name]["brainrot"]["generate"]
			var brarity = 1
			
			if brainrot_id != "":
				var temp = load("res://brainrots/%s.tscn" % brainrot_id).instantiate()
				bcost = temp.cost
				bgenerate = temp.generate
				brarity = temp.rarity
				temp.queue_free()
				temp = null
			
			if brainrot_id != "":
				var model_path = "res://brainrots/models/" + brainrot_id + ".tscn"
				print("    Loading model from: ", model_path)
				if ResourceLoader.exists(model_path):
					var brainrotN = load(model_path).instantiate()
					brainrots[slot_name]["brRef"] = brainrotN
					brainrotPositionContainter.add_child(brainrotN)
					brainrotN.global_position = brainrots[slot_name]["ref"].global_position
					brainrotN.global_rotation = brainrots[slot_name]["ref"].global_rotation
					
					brainrots[slot_name]["brainrot"]["generate"] = bgenerate
					
					var tryGrab = func():
						if str(Global.UID) != str(plrAssigned):
							if getAvailableSpace() == null:
								Global.localPlayer.get_node("MainUi").addBottomMsg(
									"[outline_size=8][outline_color=#000000][color=#ff0000]You don't have space in your base![/color][/outline_color][/outline_size]",
									5)
								var snd = AudioStreamPlayer.new()
								snd.volume_db = -20
								snd.stream = load("res://assets/sounds/error.ogg")
								Global.localPlayer.add_child(snd)
								snd.play()
								Debris.addItem(snd,snd.stream.get_length())
						Global.rpc_id(1, "trySteal", slot_name, plrAssigned)
					
					var proximity_prompt = ProximityPrompt.new()
					if Global.UID == plrAssigned:
						proximity_prompt.prompt_text = "Sell for $" + str(int(round(bcost*0.10)))
					else:
						proximity_prompt.prompt_text = "Steal"
					proximity_prompt.hold_duration = .5
					proximity_prompt.detection_radius = 6
					proximity_prompt.prompt_activated.connect(tryGrab)
					proximity_prompt.name = "ProximityPrompt"
					brainrotN.add_child(proximity_prompt)
					brainrots[slot_name]["proximity_prompt"] = proximity_prompt
					
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

func removeBrainrot(remove_at_slot):
	if remove_at_slot != null:
		var newList = {}
		for slot_name in brainrots:
			newList[slot_name] = brainrots[slot_name].duplicate(true)
		
		var dictionary = brainrotTemplate.duplicate(true)
		dictionary.ref = newList[remove_at_slot]["ref"]
		dictionary.moneyLabel = newList[remove_at_slot]["moneyLabel"]
		dictionary.index = newList[remove_at_slot]["index"]
		
		if brainrots[remove_at_slot].has("proximity_prompt") and brainrots[remove_at_slot]["proximity_prompt"]:
			if is_instance_valid(brainrots[remove_at_slot]["proximity_prompt"]):
				brainrots[remove_at_slot]["proximity_prompt"].queue_free()
		
		newList[remove_at_slot] = dictionary
		
		brainrots = newList
		if !Global.isClient and id in Global.houses:
			Global.houses[id]["brainrots"] = newList
		
		updateBrainrots(newList)
		if !Global.isClient:
			print("Broadcasting brainrot update to clients")
			rpc("updateBrainrots", newList)

@rpc("any_peer","call_remote","reliable")
func updateBrainrotStealing(state:bool, slot):
	if brainrots.has(slot):
		brainrots[slot]["stealing"] = state

func getAvailableSpace():
	for i in brainrots:
		var brainrotData = brainrots[i]["brainrot"]
		if brainrotData["id"] == "":
			return i
	return null

func _on_steal_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("plr"):
		var plr:player = body
		
		if str(plr.uid) == str(plrAssigned):
			for i in brainrots:
				if brainrots[i].has("proximity_prompt") and brainrots[i]["proximity_prompt"]:
					if is_instance_valid(brainrots[i]["proximity_prompt"]):
						brainrots[i]["proximity_prompt"].enabled = true
		
		if !Global.isClient:
			if plr.stealingSlot.Value >= 0 and plr.whoImStealing.Value >= 0 and str(plr.uid) == str(plrAssigned):
				if Global.getPlayer(str(plr.whoImStealing.Value)) and Global.whatHousePlr(str(plr.whoImStealing.Value)):
					var source_house_data = Global.whatHousePlr(str(plr.whoImStealing.Value))
					var source_house = source_house_data.ref
					var source_slot_index = plr.stealingSlot.Value
					
					var source_slot = null
					for slot_name in source_house.brainrots:
						if int(source_house.brainrots[slot_name]["index"]) == int(source_slot_index):
							source_slot = slot_name
							break
					
					if source_slot and source_house.brainrots.has(source_slot):
						var stolen_brainrot_id = source_house.brainrots[source_slot]["brainrot"]["id"]
						var stolen_money = source_house.brainrots[source_slot]["money"]
						var stolen_generate = source_house.brainrots[source_slot]["brainrot"]["generate"]
						
						if stolen_brainrot_id != "":
							var space = getAvailableSpace()
							if space != null:
								source_house.removeBrainrot(source_slot)
								
								var newList = {}
								for slot_name in brainrots:
									newList[slot_name] = brainrots[slot_name].duplicate(true)
								
								newList[space]["brainrot"]["id"] = stolen_brainrot_id
								newList[space]["brainrot"]["generate"] = stolen_generate
								newList[space]["brainrot"]["UID"] = str(Time.get_unix_time_from_system()) + str(randi())
								newList[space]["money"] = stolen_money
								
								brainrots = newList
								if id in Global.houses:
									Global.houses[id]["brainrots"] = newList
								
								updateBrainrots(newList)
								rpc("updateBrainrots", newList)
								
								plr.stealingSlot.Value = -1
								plr.whoImStealing.Value = -1
								plr.rpc("changeBrainrotHolding", "")
							else:
								plr.stealingSlot.Value = -1
								plr.whoImStealing.Value = -1
								plr.rpc("changeBrainrotHolding", "")

func _on_steal_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("plr"):
		var plr:player = body
		if str(plr.uid) == str(plrAssigned):
			for i in brainrots:
				if brainrots[i].has("proximity_prompt") and brainrots[i]["proximity_prompt"]:
					if is_instance_valid(brainrots[i]["proximity_prompt"]):
						brainrots[i]["proximity_prompt"].enabled = false
