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

# HACK: overrideSaveDir is just temp, should be changed in the future to have another function to just load data
# but im lazy now to do this for some reason, it just works, why would i make the effort?
func loadData(filename: String, overrideSaveDir:String=SAVE_DIR) -> Dictionary:
	var path = overrideSaveDir + filename
	
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

# same here as above
func fileExists(filename: String, overrideSaveDir:String=SAVE_DIR) -> bool:
	var path = overrideSaveDir + filename
	return FileAccess.file_exists(path)

func deleteData(filename: String) -> bool:
	var path = SAVE_DIR + filename
	
	if FileAccess.file_exists(path):
		var dir = DirAccess.open(SAVE_DIR)
		if dir:
			dir.remove(filename)
			return true
	
	return false
