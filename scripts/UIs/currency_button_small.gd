extends Button

@export var blips : int
@export var cost : float
@export var currency = "$"

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE

func _process(delta: float) -> void:
	$Blips.text = "𝔹 " + str(blips)
	$Cost.text = currency + str(cost)
