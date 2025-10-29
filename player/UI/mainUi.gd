extends Control

@export var money = 0

@export var moneyLabel: Label
@export var TopMsgsContainer: VBoxContainer
@export var bottomMsgsContainer: VBoxContainer

@export var unlockHBox:HBoxContainer
@export var requirementsHBox:HBoxContainer
@export var progressBar:ProgressBar
@export var progressBarText:Label

@export var mainRebirthControl:Control
@export var rebirthMaxLevel:Label

@export var indexPanel:Panel

@export var rebirthPanel: Panel

var updatingRebirth = false

func _ready() -> void:
	updateRebirth()
	createIndexBrainrots()
	Global.myPlrDataUpdate.connect(createIndexBrainrots)
	if Global.localPlayer:
		Global.localPlayer.rebirthsVal.changed.connect(updateRebirth)
	else:
		if !is_instance_valid(Global.localPlayer): Global.localPlayer = null
		await Global.localPlayer != null
		updateRebirth()

func _process(delta: float) -> void:
	visible = get_parent().localPlayer
	if !Global.localPlayer: return
	if Global.localPlayer.rebirthsVal.Value == Global.rebirths.size():
		mainRebirthControl.visible = false
		rebirthMaxLevel.visible = true
	else:
		mainRebirthControl.visible = true
		rebirthMaxLevel.visible = false
	
	##
	var needMoney = 0
	if !getMyRebirthData().is_empty():
		for i in getMyRebirthData().get("need",[{}]):
			if i.type == "money":
				needMoney = i.what
				break
	
	progressBar.max_value = needMoney
	progressBar.value = money
	progressBarText.text = "$"+str(money)+" / $"+str(needMoney)
	##
	
	if moneyLabel:
		moneyLabel.text = "$" + str(Client.format_number(money))

func createIndexBrainrots(): 
	if true: return
	for i in indexPanel.get_node("GridContainer").get_children():
		i.queue_free()
	if Global.myPlrData == null: Global.myPlrData = {}
	while !Global.myPlrData and Global.myPlrData.size() <= 0:
		await Global.wait(1)
	print("creating index things")
	for i in Global.myPlrData["indexBrainrots"]:
		print("index: ",i)
		var ins = load("res://scenes/indexThing.tscn").instantiate()
		ins.Name = i
		var temp = load("res://brainrots/%s.tscn" % i).instantiate()
		ins.Amount = Global.RARITIES_STRING[temp.rarity]
		ins.unlocked = Global.myPlrData["indexBrainrots"][i]
		temp.queue_free()
		temp = null
		print("create ",i, " ",ins, " ", ins.Name, " ",ins.Amount)
		indexPanel.get_node("GridContainer").add_child(ins)

func getMyRebirthData():
	var myRebirth = Global.localPlayer.rebirthsVal.Value+1
	if Global.rebirths.has(myRebirth):
		return Global.rebirths[myRebirth]
	return {}

func updateRebirth():
	if updatingRebirth: return
	updatingRebirth = true
	for i in unlockHBox.get_children():
		i.queue_free()
	for i in requirementsHBox.get_children():
		i.queue_free()
	
	while not Global.localPlayer: await Global.wait(1)
	while not Global.localPlayer.rebirthsVal: await Global.wait(1)
	
	if !getMyRebirthData().is_empty():
		var rebirthData = getMyRebirthData()
		
		var needs = rebirthData["need"]
		var gets = rebirthData["get"]
		
		var createThing = func(data,where,whichIm):
			var thing = load("res://scenes/rebirthThing.tscn").instantiate()
			if data["type"] == "money" and whichIm == 1: return
			if data["type"] == "tool":
				var itemId = data["what"]
				var toolGot = ToolController.getToolById(itemId)
				if !toolGot:
					push_error("GetToolById is returning null! ItemId: ",itemId, " toolGot: ",toolGot)
				print("toolGot ",toolGot)
				var tool_data = ToolController.toolData[toolGot]
				var toolName = ToolController.getToolById(itemId)
				thing.iconSprite.texture = await ToolController.createTextureFrom3D(toolName)
				thing.Name = str(tool_data["Name"])
			elif data["type"] == "money":
				thing.iconSprite.texture = load("res://assets/images/money.png")
				thing.Name = data["type"]
				thing.Amount = "$" + str(data["what"])
			elif data["type"] == "lockBase":
				thing.iconSprite.texture = load("res://assets/images/money.png")
				thing.Name = "Lock Base"
				thing.Amount = "+" + str(data["what"]) + " sec"
			else:
				thing.Name = data["type"]
				thing.Amount = str(data["what"])
			where.add_child(thing)
		
		for i in needs:
			createThing.call(i,requirementsHBox,1)
		
		for i in gets:
			createThing.call(i,unlockHBox,2)
		
	updatingRebirth = false

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

func hideAll():
	rebirthPanel.visible = false
	indexPanel.visible = false

func _on_rebirth_button_pressed() -> void:
	if rebirthPanel.visible == false:
		hideAll()
	rebirthPanel.visible = !rebirthPanel.visible

func _on_rebirth_confirm_pressed() -> void:
	Global.rpc_id(1,"rebirth",Global.token)

func _on_index_button_pressed() -> void:
	if indexPanel.visible == false:
		hideAll()
		createIndexBrainrots()
	indexPanel.visible = !indexPanel.visible
