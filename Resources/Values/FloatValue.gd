extends BaseValue
class_name FloatValue

@export var Value: float:
	set(val):
		Value = val
		value = val

func _ready() -> void:
	value = Value
	changed.connect(func(newval):
		if newval != Value:
			Value = newval
	)
