@icon("res://assets/EditorIcons/Tool.png")
extends ToolBase

@export var jumpModifier = 2.5

func _ready() -> void:
	super._ready()
	$Sound.play()
	while holder == null:
		#print(holder)
		await Global.wait(.1)
	holder.jump_strength*=jumpModifier
	Unequipped.connect(func():holder.jump_strength = holder.original_jump_strength)
