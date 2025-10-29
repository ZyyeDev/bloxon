extends Node

const SAVE_DIR = "user://saves/"

func _ready():
	ensure_save_directory()

func ensure_save_directory():
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)

func saveData(filename: String, data: Dictionary) -> bool:
	var path = SAVE_DIR + filename
	var file = FileAccess.open(path, FileAccess.WRITE)
	
	if not file:
		print("Failed to open file for writing: ", path)
		return false
	
	var json_string = JSON.stringify(data)
	file.store_string(json_string)
	file.close()
	return true

func loadData(filename: String) -> Dictionary:
	var path = SAVE_DIR + filename
	
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("Failed to open file for reading: ", path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Failed to parse JSON from: ", path)
		return {}
	
	return json.data if json.data is Dictionary else {}

func deleteData(filename: String) -> bool:
	var path = SAVE_DIR + filename
	
	if FileAccess.file_exists(path):
		var dir = DirAccess.open(SAVE_DIR)
		if dir:
			dir.remove(filename)
			return true
	
	return false

func fileExists(filename: String) -> bool:
	var path = SAVE_DIR + filename
	return FileAccess.file_exists(path)
