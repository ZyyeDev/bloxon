extends Panel

@export var Name = ""
@export var Amount = ""
@export var unlocked = false

@export var iconSprite:Sprite2D
@export var NameLabel:Label
@export var amountLabel:Label

func _ready() -> void:
	while Name == "": await Global.wait(1)
	NameLabel.text = Name
	amountLabel.text = Amount
	print("bName ",Name)
	iconSprite.texture = await createTextureFrom3D(Name)

func _process(delta: float) -> void:
	if unlocked:
		iconSprite.modulate = Color.from_hsv(0,0,1)
	else:
		iconSprite.modulate = Color.from_hsv(0,0,0)

func createTextureFrom3D(loadedItem) -> Texture:
	if loadedItem == "":
		return
	var item = load("res://brainrots/models/"+loadedItem+".tscn")
	if not item:
		printerr("wtf???")
		return
	item = item.instantiate()
	
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.world_3d = World3D.new()
	
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(6.308,6.6,-5.596)
	camera.rotation = Vector3(deg_to_rad(-22.4),deg_to_rad(133.9),deg_to_rad(0.0))
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
	
	item.position = Vector3.ZERO
	viewport.add_child(item)
	
	get_tree().root.add_child(viewport)
	
	await RenderingServer.frame_post_draw
	
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	
	var texture := ImageTexture.create_from_image(image)
	
	viewport.queue_free()
	
	return texture
