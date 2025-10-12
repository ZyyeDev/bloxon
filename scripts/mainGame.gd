@icon("res://assets/EditorIcons/Workspace.png")
extends Node3D 
class_name mainGame

@export var audio_player : AudioStreamPlayer
@export var normalMusic: Array[AudioStream] = []
@export var halloweenMusic: Array[AudioStream] = []
@export var playersContainer : Node

var musicArray = []

func _ready():
	Game.workspace = self
	Game.GameContainer = self 
	if not playersContainer:
		playersContainer = $players
	PlayerManager.setPlayers(Game.workspace.playersContainer)
	
	musicArray = normalMusic
	
	if Global.isClient:
		while not Client.is_connected:
			await Global.wait(1)
		audio_player.stream = musicArray[randi_range(0,musicArray.size()-1)]
		audio_player.play()

func _process(delta: float) -> void:
	$WorldEnvironment.environment.ssao_enabled = Global.graphics >= 6
	$WorldEnvironment.environment.ssil_enabled = Global.graphics >= 7

func _on_audio_stream_player_finished() -> void:
	audio_player.stream = musicArray[randi_range(0,musicArray.size()-1)]
	audio_player.play()
