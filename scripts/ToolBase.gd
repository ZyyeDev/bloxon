@icon("res://assets/EditorIcons/Tool.png")
extends Node3D
class_name ToolBase

@export_subgroup("Editor")
@export var itemId = -1

@export var toolName = ""
@export var toolTip = ""

@export var canDrop = false
@export var ManualActivationOnly = false

@export var holderUID = -1

var holder:player = null

var uid = ""
var register = true

signal Activated
signal Equipped
signal Unequipped

func _ready() -> void:
	uid = uuid.v4()
	
	if register:
		pass
	
	while holderUID == -1:
		print(holderUID)
		await Global.wait(.1)
	
	holder = Global.getPlayer(holderUID)
	Equipped.emit()
	tree_exiting.connect(func():Unequipped.emit())

func _process(delta: float) -> void:
	if not int(Global.UID) == holderUID: return
	if Input.is_action_just_pressed("ActivateTool"):
		#Activated.emit()
		rpc_id(1, "activateServer")

func Activate():
	if not int(Global.UID) == holderUID: return
	if ManualActivationOnly: return
	Activated.emit()
	rpc_id(1, "activateServer")

@rpc("any_peer", "call_remote", "reliable")
func activateServer():
	var sender = multiplayer.get_remote_sender_id()
	if Global.isClient: return
	if sender == holderUID:
		Activated.emit()
		rpc("activateClient")

@rpc("authority", "call_remote", "reliable")
func activateClient():
	if int(Global.UID) == holderUID:
		Activated.emit()
