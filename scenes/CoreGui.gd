@icon("res://assets/EditorIcons/SurfaceGui.png")
extends Control
class_name core_gui

@export var connectGui:Control
@export var gameGui:Control
@export var connectingLabel:Label

@export_subgroup("Inventory")
@export var inventoryBox:Control
@export_subgroup("Chat")
@export var chatContainer:Control
@export var chatScrollContainer:ScrollContainer
@export var chatVBContainer:VBoxContainer
@export var chatLineEdit:LineEdit
@export_subgroup("Mobile")
@export var joystick:Control
@export var JumpButton:TouchScreenButton

var paused = false
var chatOpen = false
var chatTexting = false

const MAX_MESSAGE_LENGTH = 200

func _ready() -> void: 
	await get_tree().process_frame
	updateInv()
	chatLineEdit.max_length = MAX_MESSAGE_LENGTH
	$Game/escape/SettingsMenu/AudioBar.value = Global.volume
	$Game/escape/SettingsMenu/GraphicsBar.value = Global.graphics
	if Global.isClient:
		$WhiteOverlayAsset.modulate = Color8(0,0,0,0)
		chatOpen = false
		hideEscape()
		hideConnect()
		Client.server_connected.connect(func():
			updateInv()
		)
		Client.server_disconnected.connect(func():
			for i in chatVBContainer.get_children():
				i.queue_free()
		)
	else:
		print("DESTROYING COREGUI CUZ SERVER!")
		queue_free()

func _process(delta: float) -> void:
	if !Global.isClient: return
	if Global.localPlayer and Client.is_connected:
		if Global.localPlayer.whoImStealing.Value == -1:
			inventoryBox.visible = true
		else:
			inventoryBox.visible = false
	$Game.visible = Client.is_connected
	if Input.is_action_just_pressed("pause"):
		toggleMenuEsc()
	if !Client.is_connected:
		hideEscape()
		chatOpen = false
		$Game/escape.visible = false
	else:
		$Game/escape.visible = !($Game/escape.position.y == -677.0)
	if chatOpen:
		$Game/chat/Chat.modulate = Color(56/255,133/255,255/255,255)
	else:
		$Game/chat/Chat.modulate = Color(255/255,255/255,255/255,255/255)
	chatContainer.visible = chatOpen

func showConnect(text:String):
	if not connectGui or not connectingLabel: return
	$connectGui/ColorRect.visible = false
	gameGui.visible = false
	connectGui.visible = true
	connectingLabel.text = text
	await Global.wait(1.5)
	if Client.is_connected:
		coolColorRectEffect()

func hideConnect():
	if not connectGui: return
	updateGraphics()
	updateVolume()
	gameGui.visible = true
	connectGui.visible = false

func _on_back_pressed() -> void:
	hideConnect()
	Client.http.cancel_request()
	await Client.disconnect_from_server()
	if Client.peer:
		Client.peer.close()
		Client.peer = null
	get_tree().change_scene_to_file("res://scenes/INIT.tscn")
	
	var snd = AudioStreamPlayer.new()
	snd.stream = load("res://assets/sounds/UI/")
	add_child(snd)
	snd.play()
	Debris.addItem(snd,snd.stream.get_length())

func showEscape():
	$Game/AnimationPlayer.play("open")
	JumpButton.visible = false
	joystick.visible = false
	paused = false

func hideEscape():
	$Game/AnimationPlayer.play("close")
	JumpButton.visible = true
	joystick.visible = true
	paused = true

func _on_resume_pressed() -> void:
	hideEscape()

func _on_leave_pressed() -> void:
	Global.saveLocal()
	hideEscape()
	Client.disconnect_from_server()

func _on_menu_pressed() -> void:
	toggleMenuEsc()

func toggleMenuEsc():
	if paused:
		showEscape()
	else:
		hideEscape() 

func _on_chat_pressed() -> void:
	chatOpen = !chatOpen

func dmgScreen():
	$WhiteOverlayAsset.modulate = Color8(255,0,0,100)
	var tw = create_tween()
	tw.tween_property($WhiteOverlayAsset,"modulate",Color8(255,0,0,0),.2)

func addSystemMessage(text: String):
	var textLabel = RichTextLabel.new()
	textLabel.bbcode_enabled = true
	textLabel.custom_minimum_size = Vector2(0,25)
	textLabel.fit_content = true
	textLabel.scroll_active = false
	textLabel.text = "[color=yellow][SYSTEM]:[/color] " + text
	chatVBContainer.add_child(textLabel)
	
	chatScrollContainer.scroll_vertical = chatScrollContainer.get_v_scroll_bar().max_value

func addChatMessage(playerName: String, text: String):
	var textLabel = RichTextLabel.new()
	textLabel.bbcode_enabled = true
	textLabel.custom_minimum_size = Vector2(0,25)
	textLabel.fit_content = true
	textLabel.scroll_active = false
	textLabel.text = "[color=red]["+playerName+"]:[/color] "+text
	chatVBContainer.add_child(textLabel)
	
	chatScrollContainer.scroll_vertical = chatScrollContainer.get_v_scroll_bar().max_value

func _on_line_edit_text_submitted(new_text: String) -> void:
	chatTexting = false
	chatLineEdit.text = ""
	
	if new_text.length() == 0:
		return
	
	Global.rpc_id(1,"sendChatMessage",new_text, Global.UID, Global.token)

func _on_jump_pressed() -> void:
	print("jump mobile")
	Input.action_press("jump")
	await get_tree().process_frame
	Input.action_release("jump")
	JumpButton.icon = load("res://assets/images/UI/Mobile/jumpPressed.png")

func _on_jump_button_button_up() -> void:
	JumpButton.icon = load("res://assets/images/UI/Mobile/jump.png")

func updateInv():
	var id = 0
	
	for v in inventoryBox.get_children():
		v.queue_free()
	
	await get_tree().process_frame
	
	for i in range(9):
		var slot = load("res://scenes/inventorySlot.tscn").instantiate()
		slot.invId = i
		slot.name = "slot"+str(i)
		slot.itemId = -1
		inventoryBox.add_child(slot)
	
	await get_tree().process_frame
	
	if Global.currentInventory.size() > 0:
		print("Populating inventory with: ", Global.currentInventory)
		
		for slot_index in Global.currentInventory:
			if slot_index < 0 or slot_index >= 9:
				continue
			
			var item_id = Global.currentInventory[slot_index]
			
			if item_id != -1:
				var slot_node = inventoryBox.get_node("slot" + str(slot_index))
				if slot_node:
					slot_node.itemId = item_id
					print("Set slot ", slot_index, " to item ID ", item_id)

func _on_line_edit_editing_toggled(toggled_on: bool) -> void:
	chatTexting = toggled_on

func coolColorRectEffect():pass
	#var tw = get_tree().create_tween()
	#tw.tween_property($connectGui/ColorRect, "Color", Color(1, 1, 1, 1), 2)
	#tw.play()

func _on_players_pressed() -> void:
	$Game/escape/PlayerList.visible = true
	$Game/escape/SettingsMenu.visible = false

func _on_settings_pressed() -> void:
	$Game/escape/PlayerList.visible = false
	$Game/escape/SettingsMenu.visible = true

func set_master_volume(percent: float):
	percent = clamp(percent, 0.0, 100.0)
	
	if percent == 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -80)
		return
	 
	var min_db = -10.0
	var max_db = 10.0
	var db = min_db + (max_db - min_db) * pow(percent / 100.0, 2)
	
	var bus = AudioServer.get_bus_index("Master")
	print("Percent: ", percent, " | dB: ", db)
	AudioServer.set_bus_volume_db(bus, db)

func _on_audio_bar_changed(new_value) -> void: 
	Global.volume = new_value
	updateVolume()
	var snd = AudioStreamPlayer.new()
	snd.stream = load("res://assets/sounds/UI/volume_slider.ogg")
	snd.volume_db = -10
	add_child(snd)
	snd.play()
	Debris.addItem(snd,snd.stream.get_length())

func _on_graphics_bar_changed(new_value: Variant) -> void:
	new_value += 1
	Global.graphics = new_value
	updateGraphics()

func updateGraphics():
	var viewport = get_viewport()
	Global.saveLocal()
	if Global.graphics >= 5:
		viewport.msaa_3d = Viewport.MSAA_2X
		RenderingServer.viewport_set_screen_space_aa(viewport,RenderingServer.VIEWPORT_SCREEN_SPACE_AA_FXAA)
	else:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		RenderingServer.viewport_set_screen_space_aa(viewport,RenderingServer.VIEWPORT_SCREEN_SPACE_AA_DISABLED)

func updateVolume():
	print("updateVolume ",Global.volume)
	Global.saveLocal()
	set_master_volume(float((Global.volume+1)*10))

func addAnnouncement(text:String,duration:float):
	var textL = load("res://scenes/announcement.tscn").instantiate()
	textL.text = text
	var snd = AudioStreamPlayer.new()
	add_child(snd)
	snd.stream = load("res://assets/sounds/UI/PopUp.wav")
	snd.play()
	Debris.addItem(snd,snd.stream.get_length())
	$Announcements.add_child(textL)
	Debris.addItem(textL,duration)
