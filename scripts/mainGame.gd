@icon("res://assets/EditorIcons/Workspace.png")
extends Node3D 
class_name mainGame

@export var audio_player : AudioStreamPlayer
@export var playersContainer : Node

func _ready():
	Game.workspace = self
	Game.GameContainer = self 
	if not playersContainer:
		playersContainer = $players
	PlayerManager.setPlayers(Game.workspace.playersContainer)
	
	if Global.isClient:
		while not Client.is_connected:
			await Global.wait(1)
		$AudioStreamPlayer.play()
