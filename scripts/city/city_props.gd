extends Node3D
## Street furniture from the city JSON's props (PLACEHOLDER models): Pioneer Square's double-globe
## lamp posts with hanging flower baskets (every third one has a real light), street trees, benches,
## bus shelters, hydrants, the iron pergola, cafe tables. Drawn in batches (one MultiMesh per kind),
## colliders on one body, so a few hundred trees stay cheap.
## Poles, trunks, shelters and hydrants collide (layer 1), so cars can wrap around them.

const Psx := preload("res://scripts/city/psx_mat.gd")

var terrain = null              # terrain.gd (heights); null = flat
var parked: Array[Transform3D] = []
var lamps: Array[Vector3] = []
var _meshes := {}
var _n_lamp := 0
var _batch := {}                 # kind -> [Transform3D]
var _body: StaticBody3D


func build(props: Array) -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	for p in props:
		var at := Vector3(float(p["x"]), 0.15, float(p["z"]))
		if terrain != null:
			at.y += terrain.at(at.x, at.z)
		var rot := deg_to_rad(float(p.get("rot", 0.0)))
		match str(p["kind"]):
			"lamp":
				_lamp(at)
			"tree":
				_put("trunk", at + Vector3(0, 1.8, 0), rot)
				_put("canopy", at + Vector3(0, 5.4, 0), rot)
				_post(at, 0.22, 3.6)
			"bench":
				_put("bench", at + Vector3(0, 0.25, 0), rot)
			"bus_stop":
				_put("shelter_roof", at + Vector3(0, 2.5, 0), rot)
				_put("shelter_back", at + Vector3(0, 1.3, 0) + Basis(Vector3.UP, rot) * Vector3(0, 0, 0.7), rot)
				_box_body(at + Vector3(0, 1.3, 0) + Basis(Vector3.UP, rot) * Vector3(0, 0, 0.7), Vector3(3.2, 2.4, 0.1), rot)
			"hydrant":
				_put("hydrant", at + Vector3(0, 0.4, 0), rot)
				_post(at, 0.15, 0.8)
			"pergola":
				_pergola(at, rot)
			"parked_car":
				parked.append(Transform3D(Basis(Vector3.UP, rot), Vector3(at.x, at.y - 0.1, at.z)))
			"cafe_table":
				_put("table", at + Vector3(0, 0.37, 0), rot)
				for c in [Vector3(0.75, 0, 0), Vector3(-0.75, 0, 0)]:
					_put("chair", at + Basis(Vector3.UP, rot) * c + Vector3(0, 0.25, 0), rot)
	for kind in _batch:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh(kind)
		var xs: Array = _batch[kind]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"pole":
			m = _cyl(0.09, 5.2, Color(0.18, 0.2, 0.22), "metal")
		"lamp_head":   # two white globes on a cross arm
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var g := SphereMesh.new()
			g.radius = 0.24
			g.height = 0.48
			g.radial_segments = 6
			g.rings = 3
			for x in [-0.45, 0.45]:
				st.append_from(g, 0, Transform3D(Basis(), Vector3(x, 0.15, 0)))
			st.append_from(BoxMesh.new(), 0, Transform3D(Basis().scaled(Vector3(1.0, 0.06, 0.06)), Vector3.ZERO))
			m = st.commit()
			m.surface_set_material(0, Psx.mat(Color(1, 0.92, 0.75), "plain", 1.0, 2.2, false))
		"basket":
			var b := SphereMesh.new()
			b.radius = 0.3
			b.height = 0.45
			b.radial_segments = 6
			b.rings = 3
			b.material = Psx.mat(Color(0.75, 0.25, 0.45), "grass", 2.0, 0.0, false)
			m = b
		"table":
			m = _cyl(0.38, 0.05, Color(0.55, 0.75, 0.2), "metal")
		"chair":
			m = _box(Vector3(0.42, 0.5, 0.42), Color(0.55, 0.75, 0.2), "metal")
		"trunk":
			m = _cyl(0.2, 3.6, Color(0.42, 0.38, 0.3), "plain")
		"canopy":
			var s := SphereMesh.new()
			s.radius = 3.0
			s.height = 4.4
			s.radial_segments = 7
			s.rings = 3
			s.material = Psx.mat(Color(0.16, 0.3, 0.16), "grass", 1.5, 0.0, false)
			m = s
		"bench":
			m = _box(Vector3(1.8, 0.12, 0.5), Color(0.35, 0.25, 0.16), "crate")
		"shelter_roof":
			m = _box(Vector3(3.4, 0.12, 1.6), Color(0.25, 0.28, 0.3), "metal")
		"shelter_back":
			m = _box(Vector3(3.2, 2.4, 0.06), Color(0.4, 0.55, 0.6), "plain", 0.3)
		"hydrant":
			m = _cyl(0.15, 0.8, Color(0.8, 0.65, 0.15), "plain")
		"pergola_post":
			m = _cyl(0.1, 4.0, Color(0.12, 0.14, 0.13), "metal")
		"pergola_roof":
			m = _box(Vector3(12.0, 0.3, 4.0), Color(0.14, 0.16, 0.15), "metal", 0.0)
	_meshes[kind] = m
	return m


func _cyl(r: float, h: float, col: Color, tex: String) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	c.material = Psx.mat(col, tex, 2.0, 0.0, false)
	return c


func _box(s: Vector3, col: Color, tex: String, glow := 0.0) -> Mesh:
	var b := BoxMesh.new()
	b.size = s
	b.material = Psx.mat(col, tex, 1.0, glow, false)
	return b


func _put(kind: String, at: Vector3, rot: float) -> void:
	if not _batch.has(kind):
		_batch[kind] = []
	_batch[kind].append(Transform3D(Basis(Vector3.UP, rot), at))


func _lamp(at: Vector3) -> void:
	_put("pole", at + Vector3(0, 2.6, 0), 0.0)
	_put("lamp_head", at + Vector3(0, 5.25, 0), 0.0)
	_put("basket", at + Vector3(0.32, 3.7, 0), 0.0)
	_post(at, 0.12, 5.2)
	lamps.append(at)
	_n_lamp += 1
	if _n_lamp % 3 != 1:
		return
	var l := OmniLight3D.new()
	l.position = at + Vector3(0, 4.9, 0)
	l.light_color = Color(1.0, 0.72, 0.42)
	l.light_energy = 1.8
	l.omni_range = 15.0
	l.omni_attenuation = 1.2
	add_child(l)


func _pergola(at: Vector3, rot: float) -> void:
	var b := Basis(Vector3.UP, rot)
	for sx in [-5.5, -1.8, 1.8, 5.5]:
		for sz in [-1.7, 1.7]:
			var p: Vector3 = at + b * Vector3(sx, 0, sz)
			_put("pergola_post", p + Vector3(0, 2.0, 0), rot)
			_post(p, 0.12, 4.0)
	_put("pergola_roof", at + Vector3(0, 4.1, 0), rot)


## a collision cylinder (poles, trunks, hydrants)
func _post(at: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	_body.add_child(cs)
	cs.position = at + Vector3(0, h * 0.5, 0)


func _box_body(at: Vector3, size: Vector3, rot: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.position = at
	body.rotation.y = rot
