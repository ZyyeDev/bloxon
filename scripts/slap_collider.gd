extends Area3D

@export var alrSlapped = false
@export var creatorUID : String
@export var slappedUID : String
@export var power = 10

# New exported variables
@export var force_position : Vector3 = Vector3(0, 0, 0)
@export var force_strength : float = 0.0
@export var force_rotation : Vector3 = Vector3(0, 0, 0)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("CanBeSlapped"):
		if body.uid != Global.UID:
			slappedUID = body.uid
			alrSlapped = true
			
			PlayerManager.slapController(slappedUID, creatorUID, power,"", force_position, force_strength, force_rotation)
			
			var direction = -body.transform.basis.z + (Vector3.UP * 5)
			direction = direction.normalized()
			var force = direction * power
			
			if body is CharacterBody3D:
				body.velocity -= force
