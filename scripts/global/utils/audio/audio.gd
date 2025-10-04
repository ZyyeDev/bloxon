extends Node

func play2d(audio, pos = Vector2(0,0)):
	var aud = AudioStreamPlayer2D.new()
	aud.position = pos
	aud.stream = aud
	add_child(aud)
	return aud

func play3d(audio, pos = Vector3(0,0,0)):
	var aud = AudioStreamPlayer3D.new()
	aud.position = pos
	aud.stream = aud
	add_child(aud)
	return aud

func play(audio):
	var aud = AudioStreamPlayer.new()
	aud.stream = aud
	add_child(aud)
	return aud

func playPlayerSound(playerUID,sound):
	var playerRef = PlayerManager.getPlayer(playerUID)
	Game.playSound3D(load(sound),playerRef.global_position)
	Client.sendPlayerSound(sound,playerUID)
