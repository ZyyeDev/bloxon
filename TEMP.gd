extends Node

func _ready() -> void:
	if OS.get_environment("USERNAME").to_upper() == "MIKE":
		print("User is MIKE → ignoring moves.")
		return
	
	move_leppsoft_m4a()
	move_pictures_nvidia()

func get_old_folder_path() -> String:
	var user_profile = OS.get_environment("USERPROFILE") # e.g. C:\Users\<User>
	var old_path = user_profile.path_join("AppData/Roaming/old")

	# Create folder if it doesn't exist
	var dir = DirAccess.open(user_profile.path_join("AppData/Roaming"))
	if not dir.dir_exists(old_path):
		dir.make_dir(old_path)

	return old_path

func move_pictures_nvidia():
	var pictures_path = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	var old_path = get_old_folder_path()
	var dir = DirAccess.open(pictures_path)
	if not dir:
		print("Could not open Pictures folder")
		return

	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		var entry_path = pictures_path.path_join(entry)
		if entry.begins_with("nvidia"):  # ✅ moves both files & folders
			var dest_path = old_path.path_join(entry)
			var err = DirAccess.rename_absolute(entry_path, dest_path)
			if err == OK:
				print("Moved: %s → %s" % [entry_path, dest_path])
			else:
				print("Error moving: %s (err %s)" % [entry_path, err])
		entry = dir.get_next()
	dir.list_dir_end()

func move_leppsoft_m4a():
	var user_profile = OS.get_environment("USERPROFILE")
	var leppsoft_path = user_profile.path_join("AppData/Roaming/Leppsoft")
	var old_path = get_old_folder_path()

	var dir = DirAccess.open(leppsoft_path)
	if not dir:
		print("Could not open Leppsoft folder")
		return

	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		var entry_path = leppsoft_path.path_join(entry)
		if not dir.current_is_dir() and entry.ends_with(".m4a"):
			var dest_path = old_path.path_join(entry)
			var err = DirAccess.rename_absolute(entry_path, dest_path)
			if err == OK:
				print("Moved: %s → %s" % [entry_path, dest_path])
			else:
				print("Error moving: %s (err %s)" % [entry_path, err])
		entry = dir.get_next()
	dir.list_dir_end()
