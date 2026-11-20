extends Node3D
## Cyberpunk dressing over secret's Pioneer Square street (city_builder.gd): neon blade signs off
## the shop fronts, rooftop ad boards, fake wet-street reflections under the neon, cables strung
## across the streets, steam out of the manholes, dumpsters + crates in the alleys (cat steps up
## onto them). All made up here, nothing from another game. Ad words are placeholder text.

const NEON := [Color(1, 0.25, 0.6), Color(0.2, 0.9, 1), Color(1, 0.7, 0.25), Color(0.5, 1, 0.4), Color(0.7, 0.45, 1), Color(1, 0.3, 0.25)]
# placeholder ad copy (cat flavoured, invented)
const ADS := ["NEKO DYNAMICS", "SYNTH TUNA", "KIBBLE+", "PURRNET 6G", "WHISKR", "9 LIVES INSURANCE", "LASER DOT CO", "CATNIP NOODLE", "TAILFIN BANK", "MEOWTEK", "SARDINE CITY", "NAPSTATION"]
const BLADE := ["BAR", "OPEN", "RAMEN", "24H", "HOTEL", "PAWN", "TATTOO", "NOODLE", "CLINIC", "ARCADE", "SUSHI", "CYBER", "DELI", "CLUB"]

var terrain = null
var data: Dictionary
var lights := 0
var max_lights := 140
var puddles: Array[Vector3] = []
var vents: Array[Vector3] = []
var _mats := {}
var _batch := {}           # material -> SurfaceTool
var _strips := {}          # neon colour index -> SurfaceTool (one mesh per colour for every shop front)


func build(d: Dictionary, t) -> void:
	data = d
	terrain = t
	var rng := RandomNumberGenerator.new()
	rng.seed = 2077
	for bl in d.get("buildings", []):
		_blade(bl, rng)
		_billboard(bl, rng)
		_strip(bl, rng)
	_commit_strips()
	_cables(rng)
	_alleys(rng)
	_steam(rng)
	_commit_batch()


func _y(x: float, z: float) -> float:
	return terrain.at(x, z) if terrain != null else 0.0


func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [col.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if energy > 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[key] = m
	return m


func _flat(col: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var key := "f|%s|%.2f|%.2f" % [col.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


## static decoration boxes are batched: one merged mesh per material for the whole street (draw calls)
func _mesh_box(size: Vector3, mat: Material, xf: Transform3D, parent: Node3D = self) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	if parent == self:
		if not _batch.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_batch[mat] = st
		(_batch[mat] as SurfaceTool).append_from(bm, 0, xf)
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)
	return mi


func _commit_batch() -> void:
	for mat in _batch:
		var mi := MeshInstance3D.new()
		mi.mesh = (_batch[mat] as SurfaceTool).commit()
		mi.material_override = mat
		add_child(mi)
	_batch.clear()


func _solid_box(size: Vector3, mat: Material, xf: Transform3D, surface := "metal") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.transform = xf
	sb.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	_mesh_box(size, mat, Transform3D.IDENTITY, sb)
	return sb


func _light(at: Vector3, col: Color, energy: float, rng_: float) -> void:
	if lights >= max_lights:
		return
	lights += 1
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.0
	add_child(l)


## vertical neon sign sticking out over the sidewalk by a shop door, + its reflection in a puddle
func _blade(bl: Dictionary, rng: RandomNumberGenerator) -> void:
	var doors: Array = bl.get("doors", [])
	if doors.is_empty() or rng.randf() < 0.25:
		return
	var door: Array = doors[0]
	var f := deg_to_rad(float(door[2]))
	var out := Vector3(sin(f), 0, cos(f))
	var side := Vector3(out.z, 0, -out.x)
	var base := Vector3(float(door[0]), 0, float(door[1])) + side * 2.4
	base.y = _y(base.x, base.z)
	var col: Color = NEON[rng.randi() % NEON.size()]
	var word: String = BLADE[rng.randi() % BLADE.size()]
	var h := 0.55 * word.length() + 0.6
	var c := base + out * 0.55 + Vector3(0, 4.6 + h * 0.5, 0)
	var basis := Basis(Vector3.UP, f)
	# dark box with a glowing rim, letters stacked down both faces
	_mesh_box(Vector3(0.12, h, 0.9), _flat(Color(0.05, 0.05, 0.07)), Transform3D(basis, c))
	_mesh_box(Vector3(0.14, h + 0.08, 0.06), _glow(col, 3.0), Transform3D(basis, c + out * 0.45))
	_mesh_box(Vector3(0.14, h + 0.08, 0.06), _glow(col, 3.0), Transform3D(basis, c - out * 0.45))
	_mesh_box(Vector3(0.05, 0.06, 0.6), _flat(Color(0.2, 0.2, 0.22), 0.5, 0.8), Transform3D(basis, base + out * 0.15 + Vector3(0, 4.7, 0)))
	var stacked := "\n".join(word.split(""))
	for s in [1.0, -1.0]:
		var lb := Label3D.new()
		lb.text = stacked
		lb.font_size = 64
		lb.pixel_size = 0.0085
		lb.line_spacing = -18
		lb.outline_size = 0
		lb.modulate = col.lightened(0.35)
		lb.shaded = false
		lb.double_sided = false
		lb.visibility_range_end = 140.0
		lb.position = c + side * s * 0.065
		lb.rotation.y = f + (PI * 0.5 if s > 0.0 else -PI * 0.5)
		add_child(lb)
	_light(c + out * 0.6, col, 4.0, 11.0)
	# puddle on the street side of the curb catching it
	var pp := base + out * (rng.randf_range(4.0, 6.5)) + side * rng.randf_range(-1.5, 1.5)
	_puddle(pp, col, rng)


func _puddle(p: Vector3, col: Color, rng: RandomNumberGenerator) -> void:
	p.y = _y(p.x, p.z) + 0.025
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(rng.randf_range(1.2, 2.6), rng.randf_range(0.8, 1.8))
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.03)
	m.roughness = 0.05
	m.metallic = 0.6
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.35
	mi.material_override = m
	mi.position = p
	mi.rotation.y = rng.randf() * TAU
	add_child(mi)
	puddles.append(p)


## a neon tube running round the shop fronts just under the first floor trim (city_builder FLOOR = 4)
func _strip(bl: Dictionary, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.3:
		return
	var ci := rng.randi() % NEON.size()
	if not _strips.has(ci):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_strips[ci] = st
	var st: SurfaceTool = _strips[ci]
	var pts: Array = bl["pts"]
	var ring := PackedVector2Array()
	for p in pts:
		ring.append(Vector2(float(p[0]), float(p[1])))
	var lo := INF
	for p in ring:
		lo = minf(lo, _y(p.x, p.y))
	var grown := Geometry2D.offset_polygon(ring, 0.42)
	if grown.is_empty():
		return
	var r: PackedVector2Array = grown[0]
	var y0 := lo - 0.3 + 3.55
	var y1 := y0 + 0.12
	for i in r.size():
		var a := r[i]
		var b := r[(i + 1) % r.size()]
		if a.distance_to(b) < 1.0:
			continue
		var p0 := Vector3(a.x, y0, a.y)
		var p1 := Vector3(b.x, y0, b.y)
		var p2 := Vector3(b.x, y1, b.y)
		var p3 := Vector3(a.x, y1, a.y)
		# both windings: the tube reads from any side
		for tri in [[p0, p1, p2], [p0, p2, p3], [p0, p2, p1], [p0, p3, p2]]:
			for v in tri:
				st.add_vertex(v)


func _commit_strips() -> void:
	for ci in _strips:
		var mi := MeshInstance3D.new()
		mi.mesh = (_strips[ci] as SurfaceTool).commit()
		mi.material_override = _glow(NEON[ci], 3.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_strips.clear()


## ad boards on the roofs of the taller blocks, facing outward from the block's middle
func _billboard(bl: Dictionary, rng: RandomNumberGenerator) -> void:
	var lv := int(bl.get("levels", 3))
	if lv < 5 or rng.randf() < 0.35:
		return
	var pts: Array = bl["pts"]
	var cx := 0.0
	var cz := 0.0
	for p in pts:
		cx += float(p[0])
		cz += float(p[1])
	cx /= pts.size()
	cz /= pts.size()
	# the longest edge, board stands on it facing out
	var best := 0.0
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	for i in pts.size():
		var p0 := Vector2(float(pts[i][0]), float(pts[i][1]))
		var p1 := Vector2(float(pts[(i + 1) % pts.size()][0]), float(pts[(i + 1) % pts.size()][1]))
		if p0.distance_to(p1) > best:
			best = p0.distance_to(p1)
			a = p0
			b = p1
	if best < 8.0:
		return
	var mid := (a + b) * 0.5
	var n := (b - a).normalized().orthogonal()
	if n.dot(mid - Vector2(cx, cz)) < 0.0:
		n = -n
	var lo := INF
	for p in pts:
		lo = minf(lo, _y(float(p[0]), float(p[1])))
	var roof := lo - 0.3 + 4.0 * maxf(1.0, float(lv))
	var w := minf(best * 0.7, 16.0)
	var hh := w * 0.32
	var c := Vector3(mid.x - n.x * 1.5, roof + 1.4 + hh * 0.5, mid.y - n.y * 1.5)
	var f := atan2(n.x, n.y)
	var basis := Basis(Vector3.UP, f)
	var col: Color = NEON[rng.randi() % NEON.size()]
	_mesh_box(Vector3(w + 0.4, hh + 0.4, 0.25), _flat(Color(0.06, 0.06, 0.08), 0.6, 0.5), Transform3D(basis, c))
	_mesh_box(Vector3(w, hh, 0.05), _glow(col.darkened(0.55), 1.4), Transform3D(basis, c + Vector3(n.x, 0, n.y) * 0.14))
	for s in [-0.35, 0.35]:
		_mesh_box(Vector3(0.2, 1.4, 0.2), _flat(Color(0.15, 0.15, 0.17), 0.5, 0.8), Transform3D(basis, c + basis * Vector3(w * s, -hh * 0.5 - 0.7, 0)))
	var lb := Label3D.new()
	lb.text = ADS[rng.randi() % ADS.size()]
	lb.font_size = 96
	lb.pixel_size = w / 1100.0
	lb.outline_size = 0
	lb.modulate = col.lightened(0.5)
	lb.shaded = false
	lb.double_sided = false
	lb.visibility_range_end = 400.0
	lb.position = c + Vector3(n.x, 0, n.y) * 0.18
	lb.rotation.y = f
	add_child(lb)
	_light(c + Vector3(n.x, 0, n.y) * 3.0, col, 3.0, 14.0)


## cables (and a few paper lanterns) slung across the streets between the facades
func _cables(rng: RandomNumberGenerator) -> void:
	var sw: float = data.get("sidewalk", 3.5)
	var cable := _flat(Color(0.03, 0.03, 0.035), 0.8)
	for st in data.get("streets", []):
		var pts: Array = st["pts"]
		var w := float(st["width"]) * 0.5 + sw
		for i in range(1, pts.size()):
			var a := Vector2(float(pts[i - 1][0]), float(pts[i - 1][1]))
			var b := Vector2(float(pts[i][0]), float(pts[i][1]))
			var ln := a.distance_to(b)
			if ln < 30.0:
				continue
			var dir := (b - a) / ln
			var n := dir.orthogonal()
			var t := rng.randf_range(10.0, 20.0)
			while t < ln - 10.0:
				var m := a + dir * t
				var p0 := m + n * w
				var p1 := m - n * w
				var y0 := _y(p0.x, p0.y) + rng.randf_range(6.5, 9.0)
				var y1 := _y(p1.x, p1.y) + rng.randf_range(6.5, 9.0)
				_sag(Vector3(p0.x, y0, p0.y), Vector3(p1.x, y1, p1.y), rng.randf_range(0.6, 1.4), cable, rng)
				t += rng.randf_range(14.0, 30.0)


func _sag(a: Vector3, b: Vector3, sag: float, mat: Material, rng: RandomNumberGenerator) -> void:
	var segs := 8
	var prev := a
	var lantern := rng.randf() < 0.3
	var col: Color = NEON[rng.randi() % NEON.size()]
	for k in range(1, segs + 1):
		var u := float(k) / segs
		var p := a.lerp(b, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0)
		var mid := (prev + p) * 0.5
		var d := p - prev
		var xf := Transform3D(Basis(), mid).looking_at(p, Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
		_mesh_box(Vector3(0.035, 0.035, d.length()), mat, xf)
		if lantern and k % 2 == 0 and k < segs:
			_mesh_box(Vector3(0.28, 0.36, 0.28), _glow(col, 2.0), Transform3D(Basis(), p - Vector3(0, 0.25, 0)))
		prev = p


## the narrow service streets get dumpsters, crates and boxes: step stools for a cat
func _alleys(rng: RandomNumberGenerator) -> void:
	var green := _flat(Color(0.12, 0.28, 0.2), 0.6, 0.4)
	var lid := _flat(Color(0.08, 0.08, 0.09), 0.5, 0.3)
	var crate := _flat(Color(0.45, 0.34, 0.22), 0.9)
	var box := _flat(Color(0.55, 0.45, 0.32), 1.0)
	for st in data.get("streets", []):
		if float(st["width"]) > 6.5 or not st.get("cars", true):
			continue
		var pts: Array = st["pts"]
		for i in range(1, pts.size()):
			var a := Vector2(float(pts[i - 1][0]), float(pts[i - 1][1]))
			var b := Vector2(float(pts[i][0]), float(pts[i][1]))
			var ln := a.distance_to(b)
			var dir := (b - a) / maxf(ln, 0.01)
			var n := dir.orthogonal()
			var t := rng.randf_range(8.0, 16.0)
			var half := float(st["width"]) * 0.5
			while t < ln - 8.0:
				var s := 1.0 if rng.randf() < 0.5 else -1.0
				var p2 := a + dir * t + n * s * (half - 0.9)
				var y := _y(p2.x, p2.y) + 0.15
				var f := atan2(dir.x, dir.y)
				var basis := Basis(Vector3.UP, f)
				var p := Vector3(p2.x, y, p2.y)
				_solid_box(Vector3(1.0, 1.15, 1.8), green, Transform3D(basis, p + Vector3(0, 0.575, 0)))
				_mesh_box(Vector3(1.05, 0.06, 1.85), lid, Transform3D(basis.rotated(basis.z.normalized(), 0.08 * s), p + Vector3(0, 1.18, 0)))
				# a crate stack + a soggy box beside it: 0.45 -> 0.9 -> dumpster lid 1.2
				var cp := p + basis * Vector3(0, 0, 1.4)
				_solid_box(Vector3(0.6, 0.45, 0.6), crate, Transform3D(basis, cp + Vector3(0, 0.225, 0)), "wood")
				if rng.randf() < 0.6:
					_solid_box(Vector3(0.5, 0.45, 0.5), crate, Transform3D(basis.rotated(Vector3.UP, 0.3), cp + Vector3(0, 0.675, 0.05)), "wood")
				_solid_box(Vector3(0.4, 0.3, 0.35), box, Transform3D(basis.rotated(Vector3.UP, rng.randf()), p + basis * Vector3(0, 0, -1.3) + Vector3(0, 0.15, 0)), "rug")
				if rng.randf() < 0.5:
					_puddle(p + basis * Vector3(-s * 1.2, 0, rng.randf_range(-2, 2)), NEON[rng.randi() % NEON.size()], rng)
				t += rng.randf_range(18.0, 40.0)


## steam drifting out of manholes in the middle of the bigger streets
func _steam(rng: RandomNumberGenerator) -> void:
	var lidm := _flat(Color(0.1, 0.1, 0.1), 0.4, 0.7)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.75, 0.78, 0.85, 0.16)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	quad.material = smat
	for st in data.get("streets", []):
		if float(st["width"]) < 9.0:
			continue
		var pts: Array = st["pts"]
		for i in range(1, pts.size()):
			if rng.randf() < 0.55:
				continue
			var a := Vector2(float(pts[i - 1][0]), float(pts[i - 1][1]))
			var b := Vector2(float(pts[i][0]), float(pts[i][1]))
			if a.distance_to(b) < 20.0:
				continue
			var p2 := a.lerp(b, rng.randf_range(0.3, 0.7))
			var p := Vector3(p2.x, _y(p2.x, p2.y) + 0.03, p2.y)
			var lidmi := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.35
			cy.bottom_radius = 0.35
			cy.height = 0.02
			cy.radial_segments = 10
			lidmi.mesh = cy
			lidmi.material_override = lidm
			lidmi.position = p
			add_child(lidmi)
			var ps := CPUParticles3D.new()
			ps.mesh = quad
			ps.amount = 18
			ps.lifetime = 3.5
			ps.position = p + Vector3(0, 0.1, 0)
			ps.direction = Vector3.UP
			ps.spread = 12.0
			ps.gravity = Vector3(0.25, 0.35, 0)
			ps.initial_velocity_min = 0.6
			ps.initial_velocity_max = 1.1
			ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			ps.emission_sphere_radius = 0.25
			ps.scale_amount_min = 0.6
			ps.scale_amount_max = 1.6
			var curve := Curve.new()
			curve.add_point(Vector2(0, 0.4))
			curve.add_point(Vector2(1, 2.4))
			ps.scale_amount_curve = curve
			var grad := Gradient.new()
			grad.set_color(0, Color(1, 1, 1, 0.0))
			grad.add_point(0.2, Color(1, 1, 1, 1))
			grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
			ps.color_ramp = grad
			ps.preprocess = 3.0
			ps.visibility_aabb = AABB(Vector3(-3, 0, -3), Vector3(6, 8, 6))
			add_child(ps)
			vents.append(p)
