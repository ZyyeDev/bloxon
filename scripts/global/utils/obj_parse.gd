extends Object
class_name ObjParse

const PRINT_DEBUG: bool = false
const PRINT_COMMENTS: bool = false
const TEXTURE_KEYS: Array[String] = [
	"map_kd", "map_disp", "disp", 
	"map_bump", "map_normal", "bump",
	"map_ao", "map_ks"
]

static func from_path(obj_path: String, mtl_path: String = "") -> Mesh:
	var obj_str: String = _read_file_str(obj_path)
	if (obj_str.is_empty()): return null
	if (mtl_path.is_empty()):
		var mtl_filename: String = _get_mtl_filename(obj_str)
		if (mtl_filename.is_empty()): return _create_obj(obj_str, {})
		mtl_path = obj_path.get_base_dir() + "/" + mtl_filename
	var materials: Dictionary[String, StandardMaterial3D] = _create_mtl(_read_file_str(mtl_path), _get_mtl_tex(mtl_path))
	return _create_obj(obj_str, materials)

static func from_obj_string(
	obj_data: String,
	materials: Dictionary[String, StandardMaterial3D] = {}
) -> Mesh:
	return _create_obj(obj_data, materials)

static func from_mtl_string(
	mtl_data: String,
	textures: Dictionary[String, ImageTexture] = {}
) -> Dictionary[String, StandardMaterial3D]:
	return _create_mtl(mtl_data, textures)

static func _prefix_print(args: Array) -> void:
	args.insert(0, "[ObjParse]")
	prints(args)

static func _debug_msg(args: Array) -> void:
	if (!PRINT_DEBUG): return
	_prefix_print(args)

static func _read_file_str(path: String) -> String:
	if (path.is_empty()): return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if (file == null): return ""
	return file.get_as_text()

static func _get_mtl_tex(mtl_path: String) -> Dictionary[String, ImageTexture]:
	var file_paths: Array[String] = _get_mtl_tex_paths(mtl_path)
	var textures: Dictionary[String, ImageTexture] = {}
	for k: String in file_paths:
		var img: Image = _get_image(mtl_path, k)
		if (img == null || img.is_empty()): continue
		textures[k] = ImageTexture.create_from_image(img)
	return textures

static func _get_mtl_tex_paths(mtl_path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(mtl_path, FileAccess.READ)
	if (file == null): return []
	var paths: Array[String] = []
	var lines: PackedStringArray = file.get_as_text().split("\n", false)
	for line: String in lines:
		var parts: PackedStringArray = line.split(" ", false, 1)
		if (parts.size() < 2): continue
		if (!TEXTURE_KEYS.has(parts[0].to_lower())): continue
		if (paths.has(parts[1])): continue
		paths.append(parts[1])
	return paths

static func _get_mtl_filename(obj: String) -> String:
	var lines: PackedStringArray = obj.split("\n")
	for line: String in lines:
		var split: PackedStringArray = line.split(" ", false)
		if (split.size() < 2): continue
		if (split[0] != "mtllib"): continue
		return split[1].strip_edges()
	return ""

static func _create_mtl(
	obj: String,
	textures: Dictionary[String, ImageTexture]
) -> Dictionary[String, StandardMaterial3D]:
	if (obj.is_empty()): return {}
	var materials: Dictionary[String, StandardMaterial3D] = {}
	var current_material: StandardMaterial3D = null
	var lines: PackedStringArray = obj.split("\n", false)
	for line: String in lines:
		var parts: PackedStringArray = line.split(" ", false)
		if (parts.size() == 0): continue
		match parts[0].to_lower():
			"#":
				if (!PRINT_COMMENTS): continue
				_prefix_print([line])
			"newmtl":
				if (parts.size() < 2):
					_debug_msg(["New material is missing a name"])
					continue
				var mat_name: String = parts[1].strip_edges()
				_debug_msg(["Adding new material", mat_name])
				current_material = StandardMaterial3D.new()
				materials[mat_name] = current_material
			"kd":
				if (current_material == null || parts.size() < 4):
					_debug_msg(["Invalid albedo/diffuse color"])
					continue
				current_material.albedo_color = Color(
					parts[1].to_float(), 
					parts[2].to_float(),
					parts[3].to_float()
				)
			"map_kd":
				if (current_material == null): continue
				var path: String = line.split(" ", false, 1)[1]
				if (!textures.has(path)): continue
				current_material.albedo_texture = textures[path]
			"map_disp", "disp":
				if (current_material == null): continue
				var path: String = line.split(" ", false, 1)[1]
				if (!textures.has(path)): continue
				current_material.heightmap_enabled = true
				current_material.heightmap_texture = textures[path]
			"map_bump", "map_normal", "bump":
				if (current_material == null): continue
				var path: String = line.split(" ", false, 1)[1]
				if (!textures.has(path)): continue
				current_material.normal_enabled = true
				current_material.normal_texture = textures[path]
			"map_ao":
				if (current_material == null): continue
				var path: String = line.split(" ", false, 1)[1]
				if (!textures.has(path)): continue
				current_material.ao_texture = textures[path]
			"map_ks":
				if (current_material == null): continue
				var path: String = line.split(" ", false, 1)[1]
				if (!textures.has(path)): continue
				current_material.roughness_texture = textures[path]
			_:
				pass
	return materials

static func _parse_mtl_file(path: String) -> Dictionary[String, StandardMaterial3D]:
	return _create_mtl(_read_file_str(path), _get_mtl_tex(path))

static func _get_image(mtl_filepath: String, tex_filename: String) -> Image:
	_debug_msg(["Mapping texture file", tex_filename])
	var tex_filepath: String = tex_filename
	if tex_filename.is_relative_path():
		tex_filepath = mtl_filepath.get_base_dir() + "/" + tex_filename
		tex_filepath = tex_filepath.strip_edges()
	var file_type: String = tex_filepath.get_extension()
	_debug_msg(["Texture file path:", tex_filepath, "of type", file_type])
	
	var img: Image = Image.new()
	var err = img.load(tex_filepath)
	if err != OK:
		_debug_msg(["Failed to load image:", tex_filepath, "Error:", err])
		return null
	return img

static func _get_texture(mtl_filepath, tex_filename) -> ImageTexture:
	var img = _get_image(mtl_filepath, tex_filename)
	if img == null: return null
	var tex = ImageTexture.create_from_image(img)
	_debug_msg(["Texture is", str(tex)])
	return tex

static func _create_obj(
	obj: String,
	materials: Dictionary[String, StandardMaterial3D]
) -> Mesh:
	var mat_name: String = "_default"
	if (!materials.has("_default")): materials["_default"] = StandardMaterial3D.new()
	var mesh: ArrayMesh = ArrayMesh.new()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var faces: Dictionary = {}
	for mat_key: String in materials.keys(): faces[mat_key] = []
	
	var lines: PackedStringArray = obj.split("\n", false)
	for line: String in lines:
		if (line.is_empty()): continue
		var feature: String = line.substr(0, line.find(" "))
		match feature:
			"#":
				if (!PRINT_COMMENTS): continue
				_prefix_print([line])
			"v":
				var line_remaining: String = line.substr(feature.length() + 1)
				var parts: PackedFloat64Array = line_remaining.split_floats(" ")
				if parts.size() < 3: continue
				var n_v: Vector3 = Vector3(parts[0], parts[1], parts[2])
				vertices.append(n_v)
			"vn":
				var line_remaining: String = line.substr(feature.length() + 1)
				var parts: PackedFloat64Array = line_remaining.split_floats(" ")
				if parts.size() < 3: continue
				var n_vn: Vector3 = Vector3(parts[0], parts[1], parts[2])
				normals.append(n_vn)
			"vt":
				var line_remaining: String = line.substr(feature.length() + 1)
				var parts: PackedFloat64Array = line_remaining.split_floats(" ")
				if parts.size() < 2: continue
				var n_uv: Vector2 = Vector2(parts[0], 1 - parts[1])
				uvs.append(n_uv)
			"usemtl":
				mat_name = line.substr(feature.length() + 1).strip_edges()
				if not faces.has(mat_name):
					faces[mat_name] = []
					if not materials.has(mat_name):
						materials[mat_name] = StandardMaterial3D.new()
			"f":
				var line_remaining: String = line.substr(feature.length() + 1)
				var def_count: int = line_remaining.count(" ") + 1
				var components_per: int = \
					line_remaining.substr(0, line_remaining.find(" ") - 1).count("/") + 1
				var sectioned: bool = (components_per > 1)
				if (line_remaining.find("/")):
					line_remaining = line_remaining.replace("//", " 0 ").replace("/", " ")
				var parts: PackedFloat64Array = line_remaining.split_floats(" ", false)
				if (sectioned):
					if (parts.size() % components_per != 0):
						_debug_msg(["Face needs 3+ parts to be valid"])
						continue
				elif (parts.size() < 3):
					_debug_msg(["Face needs 3+ parts to be valid"])
					continue
				var face: ObjParseFace = ObjParseFace.new()
				for cursor: int in def_count:
					var idx = cursor
					if (sectioned): idx *= components_per
					var v_idx = int(parts[idx]) - 1
					var vt_idx = (int(parts[idx + 1]) - 1) if sectioned else -1
					var vn_idx = (int(parts[idx + 2]) - 1) if sectioned else -1
					
					if v_idx < 0: v_idx = vertices.size() + v_idx + 1
					if vt_idx < -1 && vt_idx != -1: vt_idx = uvs.size() + vt_idx + 1
					if vn_idx < -1 && vn_idx != -1: vn_idx = normals.size() + vn_idx + 1
					
					face.v.append(v_idx)
					face.vt.append(vt_idx)
					face.vn.append(vn_idx)
				if (def_count == 3):
					faces[mat_name].append(face)
					continue
				for i: int in range(1, def_count - 1):
					var tri_face: ObjParseFace = ObjParseFace.new()
					tri_face.v.append(face.v[0])
					tri_face.v.append(face.v[i])
					tri_face.v.append(face.v[i + 1])
					tri_face.vt.append(face.vt[0])
					tri_face.vt.append(face.vt[i])
					tri_face.vt.append(face.vt[i + 1])
					tri_face.vn.append(face.vn[0])
					tri_face.vn.append(face.vn[i])
					tri_face.vn.append(face.vn[i + 1])
					faces[mat_name].append(tri_face)
			_:
				pass
	
	if (faces.size() == 1 && faces["_default"].is_empty()):
		return mesh
	
	for mat_group: String in faces.keys():
		if faces[mat_group].is_empty(): continue
		
		_debug_msg([
			"Creating surface for material", mat_group,
			"with", str(faces[mat_group].size()), "faces"
		])
		
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		
		if (!materials.has(mat_group)):
			materials[mat_group] = StandardMaterial3D.new()
		st.set_material(materials[mat_group])
		
		for face: ObjParseFace in faces[mat_group]:
			var fan_v: PackedVector3Array = PackedVector3Array()
			var fan_vn: PackedVector3Array = PackedVector3Array()
			var fan_vt: PackedVector2Array = PackedVector2Array()
			
			for k: int in [0, 2, 1]:
				if face.v[k] < 0 || face.v[k] >= vertices.size(): continue
				fan_v.append(vertices[face.v[k]])
				
				if face.vn[k] >= 0 && face.vn[k] < normals.size():
					fan_vn.append(normals[face.vn[k]])
				else:
					fan_vn.append(Vector3.UP)
				
				if face.vt[k] >= 0 && face.vt[k] < uvs.size():
					fan_vt.append(uvs[face.vt[k]])
				else:
					fan_vt.append(Vector2.ZERO)
			
			if fan_v.size() == 3:
				st.add_triangle_fan(fan_v, fan_vt, PackedColorArray(), PackedVector2Array(), fan_vn, [])
		
		mesh = st.commit(mesh)
	
	for k: int in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(k)
		mat_name = ""
		for m: String in materials:
			if (materials[m] != mat): continue
			mat_name = m
		mesh.surface_set_name(k, mat_name)
	
	return mesh

class ObjParseFace extends RefCounted:
	var v: PackedInt32Array = PackedInt32Array()
	var vt: PackedInt32Array = PackedInt32Array()
	var vn: PackedInt32Array = PackedInt32Array()
