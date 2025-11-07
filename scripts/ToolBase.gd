@icon("res://assets/EditorIcons/Tool.png")
extends Node3D
class_name ToolBase

@export_subgroup("Editor")
@export var itemId = -1

@export var toolName = ""
@export var toolTip = ""

@export var canDrop = false
@export var ManualActivationOnly = false

@export var holderUID = ""

var holder:player = null

var uid = ""
var register = true

signal Activated
signal Equipped
signal Unequipped

func _ready() -> void:
	uid = uuid.v4()
	
	if register:
		await get_tree().process_frame
		var wait_time = 0.0
		while holderUID == "" or holderUID == "-1":
			if wait_time > 5.0:
				push_error("ToolBase timeout waiting for holderUID")
				queue_free()
				return
			await get_tree().create_timer(0.1).timeout
			wait_time += 0.1
		
		holder = Global.getPlayer(str(holderUID))
		if holder:
			Equipped.emit()
		else:
			push_error("ToolBase: Could not find holder with UID: ", holderUID)
			queue_free()
			return
	
	tree_exiting.connect(func():Unequipped.emit())

func _process(delta: float) -> void:
	if not holder or not is_instance_valid(holder):
		return
	if str(Global.UID) != str(holderUID):
		return
	if Input.is_action_just_pressed("ActivateTool"):
		rpc_id(1, "activateServer")

func Activate():
	if str(Global.UID) != str(holderUID):
		return
	if ManualActivationOnly:
		return
	Activated.emit()
	rpc_id(1, "activateServer")

@rpc("any_peer", "call_remote", "reliable")
func activateServer():
	var sender = multiplayer.get_remote_sender_id()
	if Global.isClient:
		return
	if str(sender) == str(holderUID):
		Activated.emit()
		rpc("activateClient")

@rpc("authority", "call_remote", "reliable")
func activateClient():
	if str(Global.UID) == str(holderUID):
		Activated.emit()
