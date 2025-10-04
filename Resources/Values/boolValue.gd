extends BaseValue
class_name BoolValue

@export var Value: bool:
	set(val):
		Value = val
		value = val

func _ready() -> void:
	value = Value
	changed.connect(func(newval):
		if newval != Value:
			Value = newval
	)
