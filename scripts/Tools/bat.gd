@icon("res://assets/EditorIcons/Tool.png")
extends ToolBase

@export var knockback = 5.0
@export var ragdollTime = 1.0
@export var hitWaitTime = .75
@export var sound:AudioStream

var debounce = false
var plrsInHitbox = []

func _ready() -> void:
	super._ready()
	Activated.connect(_activated)

func _activated():
	if debounce: return
	debounce = true
	var debounceTimer = Timer.new()
	debounceTimer.wait_time = hitWaitTime
	debounceTimer.timeout.connect(func():
		debounce = false
		debounceTimer.queue_free()
		)
	add_child(debounceTimer)
	debounceTimer.start()
	
	if holder:
		var area = Area3D.new()
		var coll_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(5,15,10)
		coll_shape.shape = box
		area.add_child(coll_shape)
		holder.player_mesh.add_child(area)
		
		var forward = -holder.player_mesh.transform.basis.z.normalized()
		var area_pos = holder.global_transform.origin + forward * 2.0
		var forward_direction = forward
		
		var getBodies = func():
			var bodies = area.get_overlapping_bodies()
			bodies.erase(holder)
			for i in bodies:
				if i.is_in_group("plr"):
					if i.is_ragdolled:
						bodies.erase(i)
					if i.uid == holderUID:
						bodies.erase(i)
				else:
					bodies.erase(i)
			return bodies
		
		var index = 0
		var bodies = getBodies.call()
		while bodies.size() == 0:
			index += 1
			bodies = getBodies.call()
			if index == 10:
				break
			await Global.wait(.1)
		if bodies.size() != 0:
			var hitSnd = Sound.new()
			hitSnd.stream = sound
			Game.workspace.add_child(hitSnd)
			hitSnd.position = holder.position
			hitSnd.play()
		
		if !Global.isClient:
			holder.rpc("syncToolAnim","BatHit")
			await get_tree().process_frame
			for body in bodies:
				if body and body.is_in_group("plr"):
					print("hit:", body)
					
					body.server_start_ragdoll.rpc(ragdollTime, forward_direction * knockback)
					body.server_start_ragdoll(ragdollTime, forward_direction * knockback)
					body.server_apply_knockback.rpc(forward_direction, knockback)
					body.server_apply_knockback(forward_direction, knockback)
					
					var timer = Timer.new()
					timer.wait_time = ragdollTime
					timer.one_shot = true
					timer.timeout.connect(func():
						if is_instance_valid(body):
							body.server_end_ragdoll.rpc()
							body.server_end_ragdoll()
						timer.queue_free()
					)
					add_child(timer)
					timer.start()
					if body.whoImStealing.Value != -1 and body.stealingSlot.Value != -1:
						var phouse:house = Global.whatHousePlr(body.whoImStealing.Value).ref
						if phouse:
							phouse.updateBrainrotStealing(false, body.stealingSlot.Value)
						body.stealingSlot.Value = -1
						body.whoImStealing.Value = -1
						body.changeBrainrotHolding.rpc("")
			area.queue_free()
	else:
		holder = Global.getPlayer(holderUID)
		push_warning("holder of tool is null!!!")
		return

func _on_area_3d_body_entered(body: Node3D) -> void:
	if not plrsInHitbox.has(body) and body.is_in_group("plr"):
		plrsInHitbox.append(body)

func _on_area_3d_body_exited(body: Node3D) -> void:
	if plrsInHitbox.has(body) and body.is_in_group("plr"):
		plrsInHitbox.erase(body)
