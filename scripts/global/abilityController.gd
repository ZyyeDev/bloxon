extends Node

func handle(glove):
	if glove == 1:
		audio.playPlayerSound(Global.UID,"res://assets/sounds/sounds/gloves/funny_fart.ogg")
		var oldWalkSpeed = PlayerManager.getPlayer(Global.UID).walkspeed
		PlayerManager.getPlayer(Global.UID).walkspeed = 40
		while PlayerManager.getPlayer(Global.UID).walkspeed >= oldWalkSpeed:
			PlayerManager.getPlayer(Global.UID).walkspeed -= .5
			await get_tree().create_timer(.01).timeout
		PlayerManager.getPlayer(Global.UID).walkspeed = oldWalkSpeed
