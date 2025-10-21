extends Button

@export var invId = 0
@export var itemId = -1

@export_subgroup("ref")
@export var imgRef:Sprite2D

var oldItemId = -1

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE

func _process(delta: float) -> void:
	if itemId != oldItemId:
		oldItemId = itemId
		if itemId == -1:
			imgRef.texture = null
		else:
			if not Global.isClient:
				return
			
			var tool_data = ToolController.getToolById(itemId)
			if tool_data:
				imgRef.texture = await ToolController.createTextureFrom3D(tool_data)

func _on_pressed() -> void:
	if not Global.isClient: return
	Global.rpc_id(1,"changeHoldingItem", itemId, Global.UID, Global.token)
