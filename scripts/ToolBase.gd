extends Node3D
class_name ToolBase

@export_subgroup("Editor")
@export var itemId = 0

@export var toolName = ""
@export var toolTip = ""

@export var canDrop = false
@export var ManualActivationOnly = false

@export var holderUID = 0

var uid = ""
var register = true

signal Activated
signal Equipped
signal Unequipped

func _ready() -> void:
	uid = uuid.v4()
	
	if register:
		pass # TODO: this should register the tool in the server, only server, then send to clients

func _process(delta: float) -> void:
	if not Global.UID == holderUID: return
	if Input.is_action_just_pressed("ActivateTool"):
		Activated.emit()
		rpc_id(1,"activateServer")

# dont use this to fire Activated from the ToolBase or anything like that, this is only for activating the
# tool manually in case is needed in any point (another reason i added this is to make this look more like
# roblox's api but yh)
func Activate():
	if not Global.UID == holderUID: return
	if ManualActivationOnly: return
	Activated.emit()
	rpc_id(1,"activateServer")

@rpc("any_peer","call_remote","reliable")
func activateServer():
	var sender = multiplayer.get_remote_sender_id()
	if Global.isClient: return
	if sender == holderUID:
		Activated.emit()
