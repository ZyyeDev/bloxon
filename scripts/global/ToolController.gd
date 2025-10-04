extends Node

var first_icon = false

var toolData = {}

func _ready() -> void:
	var dir = DirAccess.open("res://assets/Tools/")
	if dir == null:
		print("Could not open folder (tools)")
		var errMsg = "Tools folder don't exist. Please report this error: "+str(Global.ERROR_CODES.CORRUPTED_FILES)
		OS.alert(errMsg)
		# idk what msg in that does cuz i dont see anything idk
		OS.crash(errMsg)
		return
	dir.list_dir_begin()
	while true:
		var fname = dir.get_next()
		if fname == "": break
		if fname == "ToolBase.tscn": continue # we dont want the base tool ofc
		
		var loaded = load("res://assets/Tools/"+fname)
		var tempTool = loaded.instantiate()
		tempTool.register = false
		var itemId = tempTool.itemId
		var toolName = tempTool.toolName
		var toolTip = tempTool.toolTip
		var CanDrop = tempTool.canDrop
		
		var data = {
			id = itemId,
			Name = toolName,
			tip = toolTip,
			canDrop = CanDrop
		}
		toolData[loaded] = data

func createTextureFrom3D(loadedItem) -> Texture:
	var item = loadedItem.instantiate()
	
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(0, 0, 3)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	viewport.add_child(camera)
	
	var temp_parent := Node3D.new()
	temp_parent.add_child(item)
	viewport.add_child(temp_parent)
	
	if not first_icon:
		for light in get_tree().get_nodes_in_group("icon_lights"):
			if light is DirectionalLight3D or light is OmniLight3D or light is SpotLight3D:
				light.visible = false
	else:
		first_icon = false
	
	item.global_position = Vector3.ZERO
	get_tree().root.add_child(viewport)
	
	await RenderingServer.frame_post_draw
	
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	
	var texture := ImageTexture.create_from_image(image)
	
	viewport.queue_free()
	
	return texture

func getToolByName(_name):
	for v in toolData:
		if v.Name == _name:
			return v
	return null

func getToolById(id):
	for v in toolData:
		if v.id == id:
			return v
	return null
