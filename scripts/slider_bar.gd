extends HBoxContainer

@export var value = 0
@export var canBeZero = false

signal changed(new_value)

var things = {}

func _ready() -> void:
	for i in get_children():
		things[i.id] = i
		i.pressed.connect(func():
			if i.id == 0 and value == 0 and canBeZero:
				value = -1
			value = i.id
			print("val ",value, " i ",i.id)
			changed.emit(value)
			)

func _process(delta: float) -> void:
	for i in things:
		var thing = things[i]
		if thing.id > value:
			thing.toggled = false
		else:
			thing.toggled = true
