extends ToolBase

func _ready() -> void:
	Activated.connect(toolActivated)

func toolActivated():
	pass
