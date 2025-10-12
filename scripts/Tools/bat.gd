@icon("res://assets/EditorIcons/Tool.png")
extends ToolBase

var plrsInHitbox = []

func _ready() -> void:
	super._ready()
	Activated.connect(_activated)

func _activated():
	if !Global.isClient:
		for i:player in plrsInHitbox:
			if i.whoImStealing.Value != -1 and i.stealingSlot.Value != -1:
				var phouse:house = Global.whatHousePlr(i.whoImStealing.Value).ref
				if phouse:
					phouse.updateBrainrotStealing(false, i.stealingSlot.Value)
				i.stealingSlot.Value = -1
				i.whoImStealing.Value = -1
				i.changeBrainrotHolding("")

func _on_area_3d_body_entered(body: Node3D) -> void:
	if not plrsInHitbox.has(body) and body.is_in_group("plr"):
		plrsInHitbox.append(body)

func _on_area_3d_body_exited(body: Node3D) -> void:
	if plrsInHitbox.has(body) and body.is_in_group("plr"):
		plrsInHitbox.erase(body)
