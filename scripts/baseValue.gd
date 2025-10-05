@icon("res://assets/EditorIcons/ObjectValue.png")
extends Node
class_name BaseValue

var value = null:
	set(val):
		if value != val:
			value = val
			changed.emit(value)
			if !Global.isClient and !_is_receiving:
				rpc("sendData", value)

signal changed(newValue)
var _is_receiving = false

func _ready():
	if !Global.isClient:
		get_tree().get_multiplayer().peer_connected.connect(_on_new_peer_connected)

func _on_new_peer_connected(id):
	if !Global.isClient and value != null:
		rpc_id(id, "sendData", value)

@rpc("any_peer", "call_remote", "reliable")
func sendData(newVal):
	if Global.isClient:
		_is_receiving = true
		value = newVal
		_is_receiving = false
