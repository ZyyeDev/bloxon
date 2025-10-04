extends Node

func saveData(fName,data):
	var f = FileAccess.open_encrypted_with_pass("user://"+fName, FileAccess.WRITE, "@MEOW")
	f.store_string(JSON.stringify(data))
	f.close()

func loadData(fName):
	if not file_exists(fName):
		return null
	var f = FileAccess.open_encrypted_with_pass("user://"+fName, FileAccess.READ, "@MEOW")
	var res = JSON.parse_string(f.get_as_text())
	f.close()
	return res

func file_exists(fName: String) -> bool:
	return FileAccess.file_exists("user://"+fName)
