extends Node

var first_icon = false
var toolData = {}

func _ready() -> void:
	var dir = DirAccess.open("res://assets/Tools/")
	if dir == null:
		print("Could not open folder (tools)")
		var errMsg = "Tools folder don't exist. Please report this error: "+str(Global.ERROR_CODES.CORRUPTED_FILES)
		OS.alert(errMsg)
		OS.crash(errMsg)
		return
	dir.list_dir_begin()
	while true:
		var fname = dir.get_next()
		if fname == "": break
		if fname == "ToolBase.tscn": continue
		
		var path = "res://assets/Tools/"+fname
		var loaded = load(path.trim_suffix(".remap"))
		if not loaded: continue
		var tempTool = loaded.instantiate()
		tempTool.register = false
		var itemId = tempTool.itemId
		var toolName = tempTool.toolName
		var toolTip = tempTool.toolTip
		var CanDrop = tempTool.canDrop
		tempTool.queue_free()
		
		var data = {
			id = itemId,
			Name = toolName,
			tip = toolTip,
			canDrop = CanDrop
		}
		toolData[fname.replace(".tscn","").replace(".remaps","")] = data

func createTextureFrom3D(loadedItem) -> Texture:
	var path:String = "res://assets/Tools/"+loadedItem+".tscn"
	var item = load(path.trim_suffix(".remap")).instantiate()
	
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.world_3d = World3D.new()
	
	var camPos:Node3D = item.get_node("cameraPos") if item.has_node("cameraPos") else null
	if camPos:
		print("Using cameraPos from item.")
	else:
		print("No cameraPos found, using default position.")
	
	var camera := Camera3D.new()
	camera.current = true
	camera.global_position = Vector3(0, 1, 3)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	viewport.add_child(camera)
	
	var light := DirectionalLight3D.new()
	light.light_energy = 1.0
	light.rotation_degrees = Vector3(-45, 45, 0)
	viewport.add_child(light)
	
	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.4)
	ambient.environment = env
	viewport.add_child(ambient)
	
	viewport.add_child(item)
	
	get_tree().root.add_child(viewport)
	
	await RenderingServer.frame_post_draw
	
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	
	var texture := ImageTexture.create_from_image(image)
	
	viewport.queue_free()
	
	return texture

func getToolByName(_name):
	for packed_scene in toolData:
		var data = toolData[packed_scene]
		if data.Name == _name:
			return packed_scene
	return null

func getToolById(id):
	for packed_scene in toolData:
		var data = toolData[packed_scene]
		print(data)
		if int(data.id) == int(id):
			return packed_scene
	return null
