extends BaseValue
class_name IntValue

@export var Value: int:
	set(val):
		Value = val
		value = val

func _ready() -> void:
	super._ready()
	value = Value
	changed.connect(func(newval):
		if newval != Value:
			Value = newval
	)
