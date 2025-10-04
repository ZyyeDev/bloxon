extends Node

var _debris_queue: Array = []

func _process(delta: float) -> void:
	for i in range(_debris_queue.size() - 1, -1, -1):
		var debris_entry = _debris_queue[i]
		debris_entry.time_left -= delta
		
		if debris_entry.time_left <= 0:
			if is_instance_valid(debris_entry.object):
				debris_entry.object.queue_free()
			_debris_queue.remove_at(i)

func addItem(object: Object, lifetime: float) -> void:
	if object == null:
		return
	
	var debrisData = {
		"object": object,
		"time_left": lifetime
	}
	
	_debris_queue.append(debrisData)
