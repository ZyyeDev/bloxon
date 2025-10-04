@icon("res://assets/EditorIcons/Sound.png")
extends AudioStreamPlayer3D
class_name Sound

var _last_playing = false
var _last_volume = 0.0
var _last_position = 0.0

func _process(delta):
	if multiplayer.is_server():
		if playing != _last_playing:
			_last_playing = playing
			rpc("sync_playing", playing, get_playback_position())
		
		if volume_db != _last_volume:
			_last_volume = volume_db
			rpc("sync_volume", volume_db)
		
		var current_pos = get_playback_position()
		if abs(current_pos - _last_position) > 0.1: 
			_last_position = current_pos
			rpc("sync_position", current_pos)

@rpc("authority", "call_remote", "reliable")
func sync_playing(is_playing: bool, position: float):
	if is_playing:
		play(position)
	else:
		stop()

@rpc("authority", "call_remote", "reliable")
func sync_volume(vol: float):
	volume_db = vol

@rpc("authority", "call_remote", "unreliable")
func sync_position(position: float):
	if playing and abs(get_playback_position() - position) > 0.2:
		seek(position)
