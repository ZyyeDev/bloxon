extends Node

var GameContainer : Node3D

var workspace : Node3D
var players = PlayerManager

func playSound3D(sound,position: Vector3):
	if sound == null:
		return
	var soundPlayer = AudioStreamPlayer3D.new()
	var node3D = Node3D.new()
	soundPlayer.stream = sound
	node3D.add_child(soundPlayer)
	get_tree().root.add_child(node3D)
	soundPlayer.play()
	Debris.addItem(node3D,soundPlayer.stream.get_length())
