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

var paused = false
var chatOpen = false
var chatTexting = false

const MAX_MESSAGE_LENGTH = 200

func _ready() -> void: 
	updateInv()
	chatLineEdit.max_length = MAX_MESSAGE_LENGTH
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
		queue_free()

func _process(delta: float) -> void:
	if !Global.isClient: return
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
	gameGui.visible = false
	connectGui.visible = true
	connectingLabel.text = text

func hideConnect():
	if not connectGui: return
	gameGui.visible = true
	connectGui.visible = false

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/INIT.tscn")

func showEscape():
	$Game/AnimationPlayer.play("open")
	paused = false

func hideEscape():
	$Game/AnimationPlayer.play("close")
	paused = true

func _on_resume_pressed() -> void:
	hideEscape()

func _on_leave_pressed() -> void:
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

@rpc("any_peer","call_remote","reliable")
func sendMessage(text,playerName):
	addChatMessage(playerName, text)

func _on_jump_pressed() -> void:
	print("jump mobile")
	Input.action_press("jump")
	await get_tree().process_frame
	Input.action_release("jump")

func _on_line_edit_focus_entered() -> void:
	chatTexting = true

func _on_line_edit_focus_exited() -> void:
	chatTexting = false

func updateInv():
	var id = 0
	
	for v in inventoryBox.get_children():
		v.queue_free()
		
		var slot = load("res://scenes/inventorySlot.tscn").instantiate()
		slot.invId = id
		slot.name = "slot"+str(id)
		inventoryBox.add_child(slot)
		
		id += 1
