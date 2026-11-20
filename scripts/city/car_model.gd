extends Node3D
## A car's looks: the Shitbox Rally body (assets/vehicles/<id>/body.glb, converted from its
## body.blend by tools/vehicles/convert_sr_cars.py) and its wheels (tyre.glb: one root per tire
## look, "tyre__road", "tyre__performance"...). Every material goes through the PSX shader; the
## paint surfaces (material names with "Paint") take the car's color; head / tail light lenses
## glow, brake lights brighten when braking.
## Model space: Blender -Y front ends up at +Z, so the body turns 180 degrees (def "model_yaw").

const Psx := preload("res://scripts/city/psx_mat.gd")
const SHADER := preload("res://scripts/city/psx_world.gdshader")
const HEAD := ["headlens", "bulb", "projectorlens", "headlightglass", "foglens"]
const TAIL := ["taillens", "tail"]
const Merge := preload("res://scripts/city/mesh_merge.gd")

var body: MeshInstance3D
var hubs: Array[Node3D] = []      # one per wheel (car.wheels order)
var spins: Array[Node3D] = []
var _tail_mats: Array[ShaderMaterial] = []
static var _meshes := {}     # merged glbs (one per model / tire look)
static var _shared := {}     # converted materials (per source material + paint)


func build(def: Dictionary, rest_y: float, wheels: Array, paint: Color) -> void:
	# the body: every part merged into one mesh (shared by every car of this model), the PSX
	# materials shared by every car with the same paint (tail lights stay per car: brake lights)
	var merged := _merged(str(def["model"]), "")
	var bmi := MeshInstance3D.new()
	bmi.mesh = merged["mesh"]
	bmi.visibility_range_end = 230.0
	var mats: Array = merged["mats"]
	for i in mats.size():
		bmi.set_surface_override_material(i, _material(mats[i], paint))
	body = bmi
	add_child(body)
	body.rotation.y = deg_to_rad(float(def.get("model_yaw", 180.0)))
	body.position.y = rest_y
	var look := "tyre__" + str(def.get("tire_look", "road"))
	var tm := _merged(str(def["tyre_model"]), look)
	for w in wheels:
		var hub := Node3D.new()
		add_child(hub)
		var spin := Node3D.new()
		hub.add_child(spin)
		var t := MeshInstance3D.new()
		t.mesh = tm["mesh"]
		t.visibility_range_end = 110.0
		var tmats: Array = tm["mats"]
		for i in tmats.size():
			t.set_surface_override_material(i, _material(tmats[i], paint))
		spin.add_child(t)
		var r := (t.mesh as ArrayMesh).get_aabb().size.y * 0.5
		if r > 0.05:
			t.scale = Vector3.ONE * (float(w.radius) / r)
		hubs.append(hub)
		spins.append(spin)


## a glb merged to one mesh, cached (`only` = keep just that child root, for tire looks)
static func _merged(path: String, only: String) -> Dictionary:
	var key := path + "|" + only
	if _meshes.has(key):
		return _meshes[key]
	var ps: PackedScene = load(path)
	var root: Node3D = ps.instantiate()
	var src: Node3D = root
	if only != "":
		var keep: Node = root.find_child(only, false, false)
		if keep == null:
			keep = root.find_child("tyre__road", false, false)
		src = keep as Node3D
	var r := Merge.merge(src)
	root.free()
	_meshes[key] = r
	return r


func _material(src: Material, paint: Color) -> Material:
	var name_l := (src.resource_name if src != null else "").to_lower()
	for t in TAIL:
		if t in name_l and not "reflector" in name_l:
			return _convert(src, paint)   # its own: brake lights
	var key := "%s|%s" % [src.resource_name if src != null else "", paint.to_html()]
	if not _shared.has(key):
		_shared[key] = _convert(src, paint)
	return _shared[key]


func _convert(src: Material, paint: Color) -> Material:
	var name_l := (src.resource_name if src != null else "").to_lower()
	var std := src as BaseMaterial3D
	if std != null and std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		var g := std.duplicate() as BaseMaterial3D   # glass: keep it see-through, just pixelated
		g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		return g
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var col := std.albedo_color if std != null else Color(0.6, 0.6, 0.6)
	var tex: Texture2D = std.albedo_texture if std != null else null
	if "paint" in name_l:
		col = paint if tex == null else Color.WHITE.lerp(paint, 0.85)
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("albedo_tex", tex if tex != null else Psx.tex("plain"))
	m.set_shader_parameter("uv_scale", 1.0)
	m.set_shader_parameter("world_uv", false)
	var glow := 0.0
	for h in HEAD:
		if h in name_l:
			glow = 2.0
	for t in TAIL:
		if t in name_l and not "reflector" in name_l:
			glow = 0.6
			_tail_mats.append(m)
	m.set_shader_parameter("emission", glow)
	return m


## per frame: wheel hubs follow the physics wheels; brake lights
func sync(wheels: Array, braking: bool) -> void:
	for i in wheels.size():
		var w = wheels[i]
		var hub := hubs[i]
		var r: float = w.eff_radius()
		hub.position = Vector3(w.pos.x, w.pos.y - (w.travel - w.compression) if w.contact else w.pos.y - w.travel, w.pos.z)
		hub.position.y += 0.0 if w.contact else 0.0
		hub.rotation.y = w.steer + (PI if w.left else 0.0)
		spins[i].rotation.x = (-1.0 if not w.left else 1.0) * w.spin_angle
		spins[i].scale = Vector3(1, r / w.radius, r / w.radius)
	for m in _tail_mats:
		m.set_shader_parameter("emission", 2.2 if braking else 0.6)
