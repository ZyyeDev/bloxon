extends Button

@export var invId = 0
@export var itemId = -1

@export_subgroup("ref")
@export var imgRef:Sprite2D

var oldItemId 

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE

func _process(delta: float) -> void:
	if itemId != oldItemId:
		oldItemId = invId
		if itemId == -1:
			imgRef.texture = null
		else:
			imgRef.texture = await ToolController.createTextureFrom3D(await ToolController.getToolById(itemId))

func _on_pressed() -> void:
	Global.rpc_id(1,"changeHoldingItem",itemId,Global.user_id,Global.token)
