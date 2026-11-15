class_name Foliage
extends Node3D
## ground cover for the forest: real grass blades (wind sway, bend away from the cat, shrink out with
## distance), wildflowers with stems, reeds + cattails on the banks, lily pads on the pond.
## everything is multimeshes in CHUNK x CHUNK m tiles so only the tiles near the camera draw.
##   var f := Foliage.new(); add_child(f)    after ForestLevel.build()

const CHUNK := 10.0
const GRASS_FAR := 34.0

const SWAY_CODE := """
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled;
uniform vec3 cat_pos = vec3(0.0, -100.0, 0.0);
uniform vec3 cat_vel = vec3(0.0);
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform float wind = 1.0;
uniform float far = 34.0;
uniform float bend = 1.0;
uniform float sheen = 1.0;
varying float tip;
varying float gust_v;
void vertex() {
	float h = UV.y;
	tip = h;
	float len = length(MODEL_MATRIX[1].xyz);
	vec3 root = MODEL_MATRIX[3].xyz;
	// shrink into the ground toward the draw distance so tiles never pop
	float dist = distance(root.xz, CAMERA_POSITION_WORLD.xz);
	float keep = 1.0 - smoothstep(far - 9.0, far, dist);
	VERTEX = mix(root, VERTEX, keep);
	// wind: rolling gust fronts plus a little flutter per blade
	float ph = dot(root.xz, wind_dir) * 0.42 - TIME * 1.5;
	float gust = sin(ph) * 0.55 + sin(ph * 2.7 + root.z * 0.9) * 0.25 + 0.3;
	float flut = sin(TIME * 5.3 + root.x * 9.1 + root.z * 7.3) * 0.12;
	gust_v = gust;
	float k = h * h * len * wind * bend;
	vec2 off = wind_dir * (gust * 0.28 + flut * 0.2) * k;
	// the cat pushes blades flat and away from itself
	vec2 d = root.xz - cat_pos.xz;
	float dl = length(d) + 0.0001;
	float push = (1.0 - smoothstep(0.1, 0.42, dl)) * (1.0 - smoothstep(0.1, 0.5, abs(root.y - cat_pos.y)));
	off += (d / dl) * push * len * h * 0.75 * bend;
	VERTEX.xz += off;
	VERTEX.y -= (length(off) * 0.45 + push * len * 0.4 * h) * keep;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.8));
	// uv.x = 1: tinted by the instance (blades, petals), 0: keeps its own vertex colour (stems, seed heads)
	COLOR.rgb *= mix(vec3(1.0), INSTANCE_CUSTOM.rgb, UV.x) * mix(0.66, 1.1, h);
}
void fragment() {
	// lighter band rolls across the field with each gust
	ALBEDO = COLOR.rgb * (1.0 + gust_v * 0.1 * tip * sheen);
	ROUGHNESS = 0.9;
	BACKLIGHT = COLOR.rgb * 0.35 * tip;
}
"""

static var grass_mat: ShaderMaterial
static var plant_mat: ShaderMaterial
var _cat: Node3D


static func _mat(bend: float, sheen: float, far: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SWAY_CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("bend", bend)
	m.set_shader_parameter("sheen", sheen)
	m.set_shader_parameter("far", far)
	return m


## one blade: a tapered strip with a bend, uv.y = 0 at the root, 1 at the tip
static func _blade(st: SurfaceTool, base: Vector3, yaw: float, w: float, h: float, lean: float, segs := 2) -> void:
	var side := Vector3(cos(yaw), 0, sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, cos(yaw))
	var pts: Array = []
	for s in segs + 1:
		var t := float(s) / segs
		var c := base + Vector3(0, h * t, 0) + fwd * lean * t * t
		var ww := w * (1.0 - t * 0.85)
		pts.append([c - side * ww * 0.5, c + side * ww * 0.5, t])
	var n := fwd * -1.0 + Vector3(0, 0.3, 0)
	n = n.normalized()
	for s in segs:
		var a: Array = pts[s]
		var b: Array = pts[s + 1]
		for tri in [[a[0], a[1], b[1], a[2], a[2], b[2]], [a[0], b[1], b[0], a[2], b[2], b[2]]]:
			for i in 3:
				st.set_normal(n)
				st.set_uv(Vector2(1.0, tri[3 + i]))
				st.set_color(Color.WHITE)
				st.add_vertex(tri[i])


static func _clump_mesh(blades: int, spread: float, w: float, seed_: int, wide := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in blades:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * spread
		var hh := rng.randf_range(0.55, 1.0)
		_blade(st, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf() * TAU, w * rng.randf_range(0.7, 1.3) * (2.2 if wide else 1.0), hh, rng.randf_range(0.05, 0.4) * hh)
	return st.commit()


## flower: thin stem + a little faceted head. head colour comes from the instance colour, stem is tinted green
static func _flower_mesh(petals: int, seed_: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.3, 0.52, 0.2)
	# stem: two crossed strips
	for yaw in [0.0, PI * 0.5]:
		var side := Vector3(cos(yaw), 0, sin(yaw)) * 0.035
		var quad := [Vector3.ZERO - side, Vector3.ZERO + side, Vector3(0, 0.86, 0) + side * 0.6, Vector3(0, 0.86, 0) - side * 0.6]
		var uv := [0.0, 0.0, 0.86, 0.86]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for i in tri:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0.0, uv[i]))
				st.set_color(green)
				st.add_vertex(quad[i])
	# a leaf
	for tri in [[Vector3(0, 0.3, 0), Vector3(0.22, 0.42, 0.05), Vector3(0.1, 0.34, -0.08)]]:
		for v in tri:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.0, v.y))
			st.set_color(green)
			st.add_vertex(v)
	# head: petals fanned round a centre, tilted up
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var top := Vector3(0, 0.9, 0)
	for p in petals:
		var a0 := float(p) / petals * TAU
		var a1 := a0 + TAU / petals * 0.8
		var r := 0.3
		var v1 := top + Vector3(cos(a0) * r, 0.1, sin(a0) * r)
		var v2 := top + Vector3(cos(a1) * r, 0.1, sin(a1) * r)
		for v in [top, v1, v2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1.0, 1.0))
			st.set_color(Color(0.92, 0.92, 0.92) if p % 2 == 0 else Color.WHITE)
			st.add_vertex(v)
	# centre dot
	var c := top + Vector3(0, 0.12, 0)
	for p in 4:
		var a0 := float(p) / 4.0 * TAU
		var a1 := a0 + TAU / 4.0
		for v in [c, top + Vector3(cos(a0) * 0.1, 0.11, sin(a0) * 0.1), top + Vector3(cos(a1) * 0.1, 0.11, sin(a1) * 0.1)]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.0, 1.0))
			st.set_color(Color(1.0, 0.8, 0.2))
			st.add_vertex(v)
	return st.commit()


## cattail: tall stalk with the brown sausage on top + a couple of long leaves
static func _cattail_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blade(st, Vector3.ZERO, 0.0, 0.03, 1.0, 0.04, 3)
	_blade(st, Vector3.ZERO, PI * 0.5, 0.03, 1.0, 0.04, 3)
	_blade(st, Vector3(0.03, 0, 0), 0.8, 0.09, 0.8, 0.3, 3)
	_blade(st, Vector3(-0.03, 0, 0.02), 3.6, 0.09, 0.7, 0.34, 3)
	# seed head: brown box near the top (vertex colour overrides the green instance tint)
	var brown := Color(0.42, 0.24, 0.13)
	var bx := BoxMesh.new()
	bx.size = Vector3(0.05, 0.2, 0.05)
	var arr := bx.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		var v := verts[i] + Vector3(0.0, 0.86, 0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, v.y))
		st.set_color(brown)
		st.add_vertex(v)
	return st.commit()


func _ready() -> void:
	name = "Foliage"
	var web := OS.has_feature("web")
	var density := 0.45 if web else 1.0
	if grass_mat == null or not is_instance_valid(grass_mat):
		grass_mat = _mat(1.0, 1.0, GRASS_FAR)
		plant_mat = _mat(0.55, 0.0, 46.0)
	var parent := get_parent()
	# the old cone tufts + floating box flowers are replaced by this
	for old in ["Scatter_grass", "Scatter_flower"]:
		var n := ForestLevel.lv.get_node_or_null(old) if ForestLevel.lv else null
		if n:
			n.queue_free()
	_index_obstacles()
	_build_grass(density)
	_build_flowers(density)
	_build_water_plants()
	if parent:
		_cat = get_tree().get_first_node_in_group("player") as Node3D


static var _ogrid := {}

static func _index_obstacles() -> void:
	_ogrid.clear()
	for o in ForestLevel.obstacles:
		var c: Vector2 = o[0]
		var r: float = o[1]
		if r >= 2.5:
			continue
		for gx in range(floori((c.x - r) / 2.0), floori((c.x + r) / 2.0) + 1):
			for gz in range(floori((c.y - r) / 2.0), floori((c.y + r) / 2.0) + 1):
				var key := Vector2i(gx, gz)
				if not _ogrid.has(key):
					_ogrid[key] = []
				_ogrid[key].append(o)


static func _clear(x: float, z: float, margin := 0.0) -> bool:
	var list: Variant = _ogrid.get(Vector2i(floori(x / 2.0), floori(z / 2.0)))
	if list == null:
		return true
	for o in list:
		var c: Vector2 = o[0]
		var r: float = o[1]
		if Vector2(x, z).distance_to(c) < r * 0.8 + margin:
			return false
	return true


func _mm(mesh: Mesh, xfs: Array, cols: Array, mat: Material, far: float, center: Vector3) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var t: Transform3D = xfs[i]
		t.origin -= center
		mm.set_instance_transform(i, t)
		mm.set_instance_custom_data(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.position = center
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = far + CHUNK
	mmi.extra_cull_margin = 0.6
	add_child(mmi)


func _build_grass(density: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var noise := FastNoiseLite.new()
	noise.seed = 99
	noise.frequency = 0.11
	var short_mesh := _clump_mesh(5, 0.5, 0.11, 1)
	var tall_mesh := _clump_mesh(7, 0.45, 0.07, 2)
	var broad_mesh := _clump_mesh(4, 0.4, 0.1, 3, true)
	var half := ForestLevel.HALF
	var n := int(half * 2.0 / CHUNK)
	for cz in n:
		for cx in n:
			var x0 := -half + cx * CHUNK
			var z0 := -half + cz * CHUNK
			var center := Vector3(x0 + CHUNK * 0.5, 0, z0 + CHUNK * 0.5)
			center.y = ForestLevel.height(center.x, center.z)
			var sets := [[[], []], [[], []], [[], []]]
			var want := int(CHUNK * CHUNK * 11.0 * density)
			for k in want:
				var x := x0 + rng.randf() * CHUNK
				var z := z0 + rng.randf() * CHUNK
				if absf(x) > half - 1.5 or absf(z) > half - 1.5:
					continue
				var h := ForestLevel.height(x, z)
				if h < ForestLevel.WATER_Y + 0.04:
					continue
				var pd := ForestLevel.path_dist(x, z)
				if pd < 0.55 or (pd < 1.0 and rng.randf() < 0.6):
					continue
				if not _clear(x, z):
					continue
				var dm := Vector2(x, z).distance_to(ForestLevel.MEADOW)
				var meadow := 1.0 - smoothstep(ForestLevel.MEADOW_R - 1.0, ForestLevel.MEADOW_R + 3.0, dm)
				var patch := noise.get_noise_2d(x, z) * 0.5 + 0.5
				# under the trees the ground cover thins out
				if meadow < 0.5 and rng.randf() > 0.45 + patch * 0.5:
					continue
				var col := ForestLevel.ground_color(x, z, h, rng)
				col = col.lerp(Color(0.5, 0.66, 0.24), 0.25 + rng.randf() * 0.25)
				col = col.lerp(Color(0.3, 0.52, 0.16), 0.3)
				var kind := 0
				var s := rng.randf_range(0.07, 0.15)
				var roll := rng.randf()
				if roll < 0.1 + patch * 0.22:
					# tussocks of long grass: tall enough to stalk through (the cat's eyes are at 0.25 m)
					kind = 1
					s = rng.randf_range(0.2, 0.38) * (0.8 + meadow * 0.3)
					col = col.lerp(Color(0.66, 0.7, 0.34), 0.35)
				elif roll > 0.93:
					kind = 2
					s = rng.randf_range(0.06, 0.12)
					col = col.darkened(0.1)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(1.0, 1.5), s, s * rng.randf_range(1.0, 1.5)))
				sets[kind][0].append(Transform3D(b, Vector3(x, h - 0.01, z)))
				sets[kind][1].append(col)
			_mm(short_mesh, sets[0][0], sets[0][1], grass_mat, GRASS_FAR, center)
			_mm(tall_mesh, sets[1][0], sets[1][1], grass_mat, GRASS_FAR, center)
			_mm(broad_mesh, sets[2][0], sets[2][1], grass_mat, GRASS_FAR, center)


func _build_flowers(density: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	var meshes := [_flower_mesh(5, 1), _flower_mesh(8, 2), _flower_mesh(6, 3)]
	var palette := [Color(0.98, 0.86, 0.2), Color(0.97, 0.97, 0.95), Color(0.72, 0.42, 0.95), Color(0.98, 0.42, 0.34), Color(0.4, 0.6, 1.0), Color(1.0, 0.62, 0.8)]
	var sets := [[[], []], [[], []], [[], []]]
	ForestLevel.flowers.clear()
	var want := int(1500 * density)
	var tries := 0
	var placed := 0
	while placed < want and tries < want * 8:
		tries += 1
		var x := rng.randf_range(-36.0, 36.0)
		var z := rng.randf_range(-36.0, 36.0)
		var h := ForestLevel.height(x, z)
		if h < ForestLevel.WATER_Y + 0.08 or ForestLevel.path_dist(x, z) < 0.7 or not _clear(x, z):
			continue
		var dm := Vector2(x, z).distance_to(ForestLevel.MEADOW)
		if dm > ForestLevel.MEADOW_R + 2.0 and rng.randf() < 0.82:
			continue
		# flowers come in drifts of one colour
		var drift := int(floorf(x / 5.0) * 7.0 + floorf(z / 5.0) * 13.0)
		var ci := posmod(drift + (rng.randi() % 2), palette.size())
		var mi := posmod(drift, 3)
		var s := rng.randf_range(0.1, 0.22)
		var tilt := Basis(Vector3(1, 0, 0), rng.randf_range(-0.2, 0.2)) * Basis(Vector3.UP, rng.randf() * TAU)
		sets[mi][0].append(Transform3D(tilt.scaled(Vector3(s * 0.55, s, s * 0.55)), Vector3(x, h - 0.005, z)))
		sets[mi][1].append(palette[ci])
		placed += 1
		if rng.randf() < 0.05:
			ForestLevel.flowers.append(Vector3(x, h + s, z))
	for i in 3:
		_mm(meshes[i], sets[i][0], sets[i][1], plant_mat, 46.0, Vector3.ZERO)


func _build_water_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var reed := _clump_mesh(6, 0.35, 0.05, 9)
	var cat := _cattail_mesh()
	var rx: Array = []
	var rc: Array = []
	var cx: Array = []
	var cc: Array = []
	var tries := 0
	while rx.size() < 520 and tries < 30000:
		tries += 1
		var x := rng.randf_range(-36.0, 36.0)
		var z := rng.randf_range(-36.0, 36.0)
		var h := ForestLevel.height(x, z)
		# a band right at the waterline, feet just wet
		if h > ForestLevel.WATER_Y + 0.1 or h < ForestLevel.WATER_Y - 0.14:
			continue
		if ForestLevel.path_dist(x, z) < 1.6:
			continue
		# clumps: only where a slow noise says so, so banks stay open in places
		if sin(x * 0.9) * cos(z * 0.7) + sin(x * 0.23 + z * 0.31) < 0.25:
			continue
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		if rng.randf() < 0.22:
			var s := rng.randf_range(0.55, 0.9)
			cx.append(Transform3D(b.scaled(Vector3(s, s, s)), Vector3(x, h - 0.02, z)))
			cc.append(Color(0.42, 0.58, 0.26).lightened(rng.randf() * 0.1))
		else:
			var s := rng.randf_range(0.35, 0.7)
			rx.append(Transform3D(b.scaled(Vector3(s * 0.7, s, s * 0.7)), Vector3(x, h - 0.02, z)))
			rc.append(Color(0.46, 0.62, 0.28).lerp(Color(0.7, 0.68, 0.36), rng.randf() * 0.4))
	_mm(reed, rx, rc, plant_mat, 46.0, Vector3.ZERO)
	_mm(cat, cx, cc, plant_mat, 46.0, Vector3.ZERO)
	# lily pads: flat notched discs floating on the pond, a few with a flower
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pad_n := 0
	var flower_at: Array[Vector3] = []
	for k in 60:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (ForestLevel.POND_R - 0.4)
		var p := Vector3(ForestLevel.POND.x + cos(a) * r, ForestLevel.WATER_Y + 0.006, ForestLevel.POND.y + sin(a) * r)
		if ForestLevel.height(p.x, p.z) > ForestLevel.WATER_Y - 0.12:
			continue
		var pr := rng.randf_range(0.09, 0.2)
		var yaw := rng.randf() * TAU
		var col := Color(0.24, 0.5, 0.22).lightened(rng.randf() * 0.12)
		for s in 7:   # 8 slices, one missing = the notch
			var a0 := yaw + s * TAU / 8.0
			var a1 := a0 + TAU / 8.0
			for v in [p, p + Vector3(cos(a1) * pr, 0, sin(a1) * pr), p + Vector3(cos(a0) * pr, 0, sin(a0) * pr)]:
				st.set_normal(Vector3.UP)
				st.set_color(col if s % 2 == 0 else col.darkened(0.06))
				st.add_vertex(v)
		pad_n += 1
		if rng.randf() < 0.22:
			flower_at.append(p)
	if pad_n > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = LowPoly.mat(Color.WHITE, 0.6)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "LilyPads"
		add_child(mi)
	for p in flower_at:
		for k in 5:
			var a := k * TAU / 5.0
			LowPoly.part(self, LowPoly.cone(4), Color(0.98, 0.9, 0.95), p + Vector3(cos(a) * 0.022, 0.03, sin(a) * 0.022), Vector3(0.03, 0.06, 0.03), Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		LowPoly.part(self, LowPoly.box(0.0), Color(0.98, 0.8, 0.2), p + Vector3(0, 0.03, 0), Vector3.ONE * 0.018)


func _process(_dt: float) -> void:
	if _cat == null or not is_instance_valid(_cat):
		_cat = get_tree().get_first_node_in_group("player") as Node3D
		if _cat == null:
			return
	var p := _cat.global_position
	grass_mat.set_shader_parameter("cat_pos", p)
	plant_mat.set_shader_parameter("cat_pos", p)
