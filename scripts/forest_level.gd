class_name ForestLevel
extends RefCounted
## procedural low poly forest at real cat scale (meters), ~76 x 76 m bowl of hills:
##   stream with stepping stones + a log bridge, a pond, a sunny meadow, a rock outcrop with ledges,
##   pines / oaks / birches (trunks climbable, limbs are perches), fallen + hollow logs, stumps,
##   a deer stand, bushes to hide in. wildlife lives in wildlife.gd and reads the lists built here.

const HALF := 40.0
const WATER_Y := -0.32
const MEADOW := Vector2(0.0, -14.0)
const MEADOW_R := 9.0
const POND := Vector2(19.0, 7.0)
const POND_R := 5.0
const SPAWN := Vector3(0.0, 0.0, 33.0)

const C_GRASS := Color(0.3, 0.47, 0.2)
const C_GRASS2 := Color(0.38, 0.54, 0.22)
const C_DIRT := Color(0.5, 0.4, 0.28)
const C_MUD := Color(0.36, 0.3, 0.22)
const C_BARK := Color(0.38, 0.28, 0.2)
const C_BARK_D := Color(0.28, 0.21, 0.16)
const C_PINE := Color(0.18, 0.36, 0.22)
const C_LEAF := Color(0.32, 0.52, 0.22)
const C_BIRCH := Color(0.88, 0.86, 0.8)
const C_ROCK := Color(0.52, 0.52, 0.5)
const C_MOSS := Color(0.34, 0.48, 0.22)

static var _noise: FastNoiseLite
static var lv: Node3D
## wildlife hooks
static var perches: Array[Vector3] = []     # tops of limbs / rocks birds can land on
static var trunks: Array = []               # [Vector3 base, radius, climb_top_y]
static var obstacles: Array = []            # [Vector2 center, radius] for ground animals
static var flowers: Array[Vector3] = []     # butterfly spots


# ------------------------------------------------------------------ terrain
static func height(x: float, z: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 4242
		_noise.frequency = 0.045
		_noise.fractal_octaves = 3
	var h := 0.45 + _noise.get_noise_2d(x, z) * 1.3
	# hills all round so the bowl reads as a valley in the woods
	var edge := maxf(absf(x), absf(z))
	h += smoothstep(27.0, 40.0, edge) * 5.0
	# meadow + spawn are gentle
	var dm := Vector2(x, z).distance_to(MEADOW)
	h = lerpf(h, 0.35 + _noise.get_noise_2d(x * 0.5, z * 0.5) * 0.25, 1.0 - smoothstep(MEADOW_R - 2.0, MEADOW_R + 3.0, dm))
	var ds := Vector2(x, z).distance_to(Vector2(SPAWN.x, SPAWN.z))
	h = lerpf(h, 0.3, 1.0 - smoothstep(3.0, 7.0, ds))
	# stream valley + pond
	var d := stream_dist(x, z)
	h = lerpf(h, -0.58, 1.0 - smoothstep(1.1, 3.4, d))
	var dp := Vector2(x, z).distance_to(POND)
	h = lerpf(h, -0.8, 1.0 - smoothstep(POND_R - 1.5, POND_R + 1.5, dp))
	return h


static func stream_z(x: float) -> float:
	return 5.0 + 5.0 * sin(x / 8.5) + 2.0 * sin(x / 3.7 + 1.0)


static func stream_dist(x: float, z: float) -> float:
	return absf(z - stream_z(x)) * 0.92


static func path_dist(x: float, z: float) -> float:
	# dirt path: spawn gate -> stream (stepping stones) -> meadow
	var pts := [Vector2(0, 38), Vector2(1.5, 28), Vector2(-1.0, 18), Vector2(0.5, 10.0), Vector2(0.0, stream_z(0.0)), Vector2(-1.0, 0.0), Vector2(0.5, -6.0)]
	var best := 1e9
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var p := Vector2(x, z)
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return best


static func ground_color(x: float, z: float, h: float, rng: RandomNumberGenerator) -> Color:
	var c := C_GRASS.lerp(C_GRASS2, clampf(0.5 + _noise.get_noise_2d(x * 2.0 + 100.0, z * 2.0) * 1.5, 0.0, 1.0))
	if Vector2(x, z).distance_to(MEADOW) < MEADOW_R:
		c = c.lerp(Color(0.55, 0.66, 0.3), 0.5)
	var pd := path_dist(x, z)
	if pd < 0.9:
		c = c.lerp(C_DIRT, (1.0 - smoothstep(0.3, 0.9, pd)) * 0.75)
	if h < 0.0:
		c = c.lerp(C_MUD, clampf(-h * 2.5, 0.0, 1.0))
	if h > 2.5:
		c = c.lerp(Color(0.32, 0.42, 0.22), 0.5)
	var j := rng.randf_range(-0.035, 0.035)
	return Color(c.r + j, c.g + j * 1.2, c.b + j * 0.6)


static func _terrain() -> void:
	var n := int(HALF * 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			hs[iz * (n + 1) + ix] = height(ix - HALF, iz - HALF)
	# visual terrain in 20 x 20 m tiles: each tile stays well under the 32k vertex limit
	# the web (webgl) build silently drops vertices past, and tiles cull better too
	var tile := 20
	for tz in range(0, n, tile):
		for tx in range(0, n, tile):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for iz in range(tz, mini(tz + tile, n)):
				for ix in range(tx, mini(tx + tile, n)):
					var x0 := ix - HALF
					var z0 := iz - HALF
					var p00 := Vector3(x0, hs[iz * (n + 1) + ix], z0)
					var p10 := Vector3(x0 + 1, hs[iz * (n + 1) + ix + 1], z0)
					var p01 := Vector3(x0, hs[(iz + 1) * (n + 1) + ix], z0 + 1)
					var p11 := Vector3(x0 + 1, hs[(iz + 1) * (n + 1) + ix + 1], z0 + 1)
					for tri in [[p00, p10, p11], [p00, p11, p01]]:
						var a: Vector3 = tri[0]
						var b: Vector3 = tri[1]
						var c: Vector3 = tri[2]
						var nrm := (c - a).cross(b - a).normalized()
						var cen := (a + b + c) / 3.0
						var col := ground_color(cen.x, cen.z, cen.y, rng)
						for v in [a, b, c]:
							st.set_normal(nrm)
							st.set_color(col)
							st.add_vertex(v)
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = LowPoly.mat(Color.WHITE, 0.95)
			mi.name = "Terrain_%d_%d" % [tx, tz]
			lv.add_child(mi)
	# collision: heightmap (godot centers it, 1 m spacing)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = n + 1
	hm.map_depth = n + 1
	hm.map_data = hs
	cs.shape = hm
	sb.add_child(cs)
	sb.set_meta("surface", "grass")
	lv.add_child(sb)
	# invisible walls at the edge (the hills already climb, this just stops wandering off)
	for s in [-1, 1]:
		_wall(Vector3(s * (HALF - 1.0), 8, 0), Vector3(0.5, 20, HALF * 2))
		_wall(Vector3(0, 8, s * (HALF - 1.0)), Vector3(HALF * 2, 20, 0.5))
	# water: one big sheet, the terrain hides it everywhere it isn't low
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2, HALF * 2)
	pm.subdivide_width = 40
	pm.subdivide_depth = 40
	w.mesh = pm
	var wm := StandardMaterial3D.new()
	# opaque on purpose: a huge alpha plane draws over the terrain in the web build
	wm.albedo_color = Color(0.22, 0.36, 0.4)
	wm.roughness = 0.08
	wm.metallic_specular = 0.8
	w.material_override = wm
	w.position.y = WATER_Y
	w.name = "Water"
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lv.add_child(w)
	# far hills + treeline beyond the edge so there's no void
	# ground ring outside the bowl (not over it!)
	for sx in [-1, 1]:
		LowPoly.part(lv, LowPoly.box(0.0), Color(0.3, 0.42, 0.22), Vector3(sx * (HALF + 100.0 - 0.5), 4.9, 0), Vector3(200, 0.2, 400))
		LowPoly.part(lv, LowPoly.box(0.0), Color(0.3, 0.42, 0.22), Vector3(0, 4.9, sx * (HALF + 100.0 - 0.5)), Vector3(400, 0.2, 200))
	var r2 := RandomNumberGenerator.new()
	r2.seed = 9
	for k in 90:
		var a := k * TAU / 90.0 + r2.randf_range(-0.03, 0.03)
		var rad := r2.randf_range(41.0, 58.0)
		var p := Vector3(cos(a) * rad, 4.9, sin(a) * rad)
		var th := r2.randf_range(6.0, 11.0)
		LowPoly.part(lv, LowPoly.cyl(0.0, 0.5, 6), C_PINE.darkened(r2.randf() * 0.25), p + Vector3(0, th * 0.5, 0), Vector3(3.2, th, 3.2))


static func _wall(c: Vector3, s: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	sb.add_child(cs)
	sb.position = c
	lv.add_child(sb)


## a place to put the player: nudged off the 1 m terrain grid. with the camera exactly on a grid
## line, webgl (at least swiftshader) drops the ground triangles right in front of it
static func spot(x: float, z: float) -> Vector3:
	return ground(x + 0.137, z + 0.173) + Vector3(0, 0.05, 0)


static func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)


# ------------------------------------------------------------------ helpers
static func _climb(n: Node, scratch := true) -> void:
	if not n.has_meta("surface"):
		n.set_meta("surface", "wood")
	n.add_to_group("climbable")
	if scratch:
		n.add_to_group("scratchable")


static func _cyl_body(center: Vector3, basis: Basis, r: float, h: float, col: Color, segs := 7, collide := true, taper := 1.0) -> Node3D:
	var node: Node3D
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = h
		cs.shape = sh
		sb.add_child(cs)
		node = sb
	else:
		node = Node3D.new()
	node.transform = Transform3D(basis, center)
	lv.add_child(node)
	LowPoly.part(node, LowPoly.cyl(0.5 * taper, 0.5, segs), col, Vector3.ZERO, Vector3(r * 2.0, h, r * 2.0))
	return node


## a lumpy low poly rock with a matching convex collider
static func rock(pos: Vector3, size: Vector3, rot_y: float, col := C_ROCK, moss := true) -> Node3D:
	var src := SphereMesh.new()
	src.radius = 0.5
	src.height = 1.0
	src.radial_segments = 7
	src.rings = 4
	var arr := src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 131 + pos.z * 17)
	var pts := PackedVector3Array()
	# squash the bottom flat and wobble the rest
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + _hash3(v) * 0.22
		v *= k
		v.y = maxf(v.y, -0.25)
		verts[i] = v * size
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var surf := SurfaceTool.new()
	surf.create_from(am, 0)
	var flat := _flatten(surf.commit(), col, moss)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	for v in verts:
		pts.append(v)
	sh.points = pts
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = rot_y
	lv.add_child(sb)
	var mi := MeshInstance3D.new()
	mi.mesh = flat
	mi.material_override = LowPoly.mat(Color.WHITE, 0.9)
	sb.add_child(mi)
	sb.add_to_group("scratchable")
	perches.append(pos + Vector3(0, size.y * 0.5 * 1.1, 0))
	obstacles.append([Vector2(pos.x, pos.z), maxf(size.x, size.z) * 0.55])
	return sb


static func _hash3(v: Vector3) -> float:
	var s := sin(v.x * 12.9898 + v.y * 78.233 + v.z * 37.719) * 43758.5453
	return (s - floorf(s)) * 2.0 - 1.0


## per-face flat shading + color (moss on the up-facing faces)
static func _flatten(m: ArrayMesh, col: Color, moss: bool) -> ArrayMesh:
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := idx.size() if idx.size() > 0 else verts.size()
	for t in range(0, count - 2, 3):
		var a := verts[idx[t]] if idx.size() > 0 else verts[t]
		var b := verts[idx[t + 1]] if idx.size() > 0 else verts[t + 1]
		var c := verts[idx[t + 2]] if idx.size() > 0 else verts[t + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if n.dot((a + b + c) / 3.0) < 0.0:
			n = -n
			var tmp := b
			b = c
			c = tmp
		var cc := col.lightened(_hash3(a + c) * 0.06 + 0.03)
		if moss and n.y > 0.55:
			cc = C_MOSS.lightened(_hash3(b) * 0.05)
		for v in [a, c, b]:
			st.set_normal(n)
			st.set_color(cc)
			st.add_vertex(v)
	return st.commit()


# ------------------------------------------------------------------ trees
static func pine(base: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	var r := 0.16 + h * 0.012
	var trunk := _cyl_body(base + Vector3(0, h * 0.5, 0), Basis(), r, h, C_BARK, 7, true, 0.55)
	_climb(trunk)
	trunks.append([base, r, h * 0.55])
	obstacles.append([Vector2(base.x, base.z), r + 0.15])
	# branch stubs = perches. first one ~1.4-2.0 m up
	var y := rng.randf_range(1.4, 2.0)
	var a := rng.randf() * TAU
	while y < h * 0.62:
		var len := rng.randf_range(0.6, 1.1)
		var d := Vector3(cos(a), 0, sin(a))
		var limb := Level.rbox(lv, base + Vector3(0, y, 0) + d * (len * 0.5 + r * 0.6), Vector3(len, 0.08, 0.1), Vector3(0, -a, 0), C_BARK_D)
		_climb(limb)
		perches.append(base + Vector3(0, y + 0.05, 0) + d * (len * 0.7 + r))
		y += rng.randf_range(0.55, 0.9)
		a += rng.randf_range(1.6, 2.8)
	# foliage: stacked cones (visual), starts at a third of the height so the cat can see the limbs
	var tiers := 4
	for k in tiers:
		var t := float(k) / tiers
		var cy := lerpf(h * 0.38, h * 0.92, t)
		var w := lerpf(h * 0.42, h * 0.14, t)
		LowPoly.part(lv, LowPoly.cyl(0.0, 0.5, 7), C_PINE.lightened(rng.randf() * 0.08 + t * 0.05), base + Vector3(0, cy, 0), Vector3(w, h * 0.32, w), Vector3(0, rng.randf() * TAU, 0))


static func oak(base: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	var r := 0.26 + h * 0.02
	var trunk := _cyl_body(base + Vector3(0, h * 0.5, 0), Basis(), r, h, C_BARK, 8, true, 0.75)
	_climb(trunk)
	trunks.append([base, r, h * 0.6])
	obstacles.append([Vector2(base.x, base.z), r + 0.2])
	for k in 4:
		var aa := k * PI * 0.5 + rng.randf()
		LowPoly.part(lv, LowPoly.box(), C_BARK_D, base + Vector3(cos(aa) * r, 0.1, sin(aa) * r), Vector3(0.24, 0.2, 0.24), Vector3(0, aa, 0.4))
	# thick flat-topped limbs to walk out on
	var n := rng.randi_range(4, 6)
	for k in n:
		var y := lerpf(1.5, h * 0.82, float(k) / (n - 1)) + rng.randf_range(-0.2, 0.2)
		var a := k * 2.4 + rng.randf_range(-0.4, 0.4)
		var len := rng.randf_range(1.4, 2.4) * (1.0 - float(k) / n * 0.4)
		var d := Vector3(cos(a), 0, sin(a))
		var tilt := rng.randf_range(0.05, 0.22)
		var limb := Level.rbox(lv, base + Vector3(0, y + len * 0.5 * sin(tilt), 0) + d * (len * 0.5 + r * 0.6), Vector3(len, 0.15, 0.17), Vector3(0, -a, tilt), C_BARK)
		_climb(limb)
		var tip := base + Vector3(0, y + len * sin(tilt) + 0.08, 0) + d * (len + r * 0.6)
		perches.append(tip - d * 0.2)
		for j in 2:
			var lc := tip + Vector3(rng.randf_range(-0.4, 0.4), 0.5 + rng.randf() * 0.4, rng.randf_range(-0.4, 0.4))
			LowPoly.part(lv, LowPoly.sphere(7, 4), C_LEAF.lightened(rng.randf() * 0.1), lc, Vector3.ONE * rng.randf_range(1.0, 1.5))
	for j in 7:
		var lc := base + Vector3(rng.randf_range(-1.8, 1.8), h + rng.randf_range(-0.6, 0.6), rng.randf_range(-1.8, 1.8))
		LowPoly.part(lv, LowPoly.sphere(7, 4), C_LEAF.lightened(rng.randf() * 0.12), lc, Vector3(1.0, 0.8, 1.0) * rng.randf_range(1.6, 2.4))


static func birch(base: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	var r := 0.1 + h * 0.008
	var trunk := _cyl_body(base + Vector3(0, h * 0.5, 0), Basis(), r, h, C_BIRCH, 6, true, 0.7)
	_climb(trunk)
	trunks.append([base, r, h * 0.6])
	obstacles.append([Vector2(base.x, base.z), r + 0.12])
	for k in int(h * 2.5):
		var y := rng.randf_range(0.3, h * 0.9)
		LowPoly.part(trunk, LowPoly.box(0.0), Color(0.12, 0.12, 0.12), Vector3(0, y - h * 0.5, 0), Vector3(r * 2.05, 0.03, r * rng.randf_range(0.6, 1.4)), Vector3(0, rng.randf() * TAU, 0))
	for k in 2:
		var y := rng.randf_range(h * 0.45, h * 0.7)
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var limb := Level.rbox(lv, base + Vector3(0, y, 0) + d * 0.45, Vector3(0.8, 0.06, 0.07), Vector3(0, -a, 0.3), C_BIRCH.darkened(0.1))
		_climb(limb)
		perches.append(base + Vector3(0, y + 0.18, 0) + d * 0.75)
	for j in 5:
		var lc := base + Vector3(rng.randf_range(-1.0, 1.0), h * rng.randf_range(0.7, 1.0), rng.randf_range(-1.0, 1.0))
		LowPoly.part(lv, LowPoly.sphere(6, 4), Color(0.5, 0.65, 0.25).lightened(rng.randf() * 0.1), lc, Vector3(1.0, 0.8, 1.0) * rng.randf_range(0.9, 1.4))


# ------------------------------------------------------------------ props
static func fallen_log(a: Vector3, b: Vector3, r: float, climb := true) -> Node3D:
	var d := b - a
	var len := d.length()
	var y := d / len
	var x := y.cross(Vector3.UP).normalized() if absf(y.y) < 0.95 else Vector3.RIGHT
	var z := x.cross(y).normalized()
	var node := _cyl_body((a + b) * 0.5, Basis(x, y, z), r, len, C_BARK, 7)
	if climb:
		_climb(node)
	# cut ends
	for e in [a, b]:
		LowPoly.part(lv, LowPoly.cyl(0.5, 0.5, 7), Color(0.72, 0.58, 0.4), e, Vector3(r * 1.9, 0.02, r * 1.9)).transform.basis = Basis(x, y, z) * Basis.from_scale(Vector3(r * 1.9, 0.02, r * 1.9))
	obstacles.append([Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5), len * 0.3])
	perches.append((a + b) * 0.5 + Vector3(0, r + 0.02, 0))
	return node


## hollow log the cat can crawl through (inside clearance ~0.3 m)
static func hollow_log(center: Vector3, yaw: float, len: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var r_in := 0.17
	var segs := 8
	for k in segs:
		var a := (k + 0.5) * TAU / segs
		var off := Vector3(cos(a) * (r_in + 0.05), sin(a) * (r_in + 0.05) + r_in + 0.03, 0)
		var w := 2.0 * (r_in + 0.1) * tan(PI / segs) + 0.02
		var sb := Level.rbox(lv, center + b * off, Vector3(w, 0.1, len), Vector3(0, yaw, 0) + Vector3(0, 0, 0), C_BARK)
		sb.transform.basis = b * Basis(Vector3.BACK, a + PI / 2)
		_climb(sb)
	for e in [-1, 1]:
		var ring := MeshInstance3D.new()
		ring.mesh = LowPoly.cyl(0.5, 0.5, segs)
		ring.material_override = LowPoly.mat(Color(0.7, 0.56, 0.38))
		ring.transform = Transform3D(b * Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(r_in * 2 + 0.22, 0.015, r_in * 2 + 0.22)), center + b * Vector3(0, r_in + 0.03, e * len * 0.5))
		lv.add_child(ring)
		# dark hole so the ring reads as hollow
		LowPoly.part(lv, LowPoly.cyl(0.5, 0.5, segs), Color(0.08, 0.06, 0.05), center + b * Vector3(0, r_in + 0.03, e * (len * 0.5 + 0.01)), Vector3(r_in * 2, 0.016, r_in * 2), Vector3(PI / 2, yaw, 0)).transform.basis = b * Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(r_in * 2, 0.016, r_in * 2))
	obstacles.append([Vector2(center.x, center.z), len * 0.5])


static func stump(pos: Vector3, r: float, h: float) -> void:
	var s := _cyl_body(pos + Vector3(0, h * 0.5, 0), Basis(), r, h, C_BARK, 8)
	_climb(s)
	LowPoly.part(lv, LowPoly.cyl(0.5, 0.5, 8), Color(0.74, 0.6, 0.42), pos + Vector3(0, h + 0.005, 0), Vector3(r * 1.9, 0.01, r * 1.9))
	perches.append(pos + Vector3(0, h + 0.02, 0))
	obstacles.append([Vector2(pos.x, pos.z), r + 0.1])


static func bush(pos: Vector3, s: float, rng: RandomNumberGenerator, berries := false) -> void:
	# no collider: the cat can push in and hide under it
	for k in 4:
		var o := Vector3(rng.randf_range(-0.4, 0.4) * s, 0.35 * s + rng.randf() * 0.2 * s, rng.randf_range(-0.4, 0.4) * s)
		LowPoly.part(lv, LowPoly.sphere(6, 4), C_LEAF.darkened(0.15 + rng.randf() * 0.1), pos + o, Vector3(0.9, 0.7, 0.9) * s * rng.randf_range(0.8, 1.1))
	if berries:
		for k in 8:
			var a := rng.randf() * TAU
			LowPoly.part(lv, LowPoly.box(0.0), Color(0.75, 0.1, 0.15), pos + Vector3(cos(a) * 0.45 * s, 0.4 * s + rng.randf() * 0.35 * s, sin(a) * 0.45 * s), Vector3.ONE * 0.04)


static func deer_stand(base: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := 3.0
	for p in [Vector3(-0.7, 0, -0.7), Vector3(0.7, 0, -0.7), Vector3(-0.7, 0, 0.7), Vector3(0.7, 0, 0.7)]:
		var post := Level.box(lv, base + b * p + Vector3(0, h * 0.5, 0), Vector3(0.1, h, 0.1), Color(0.5, 0.4, 0.3))
		_climb(post)
	var plat := Level.rbox(lv, base + Vector3(0, h, 0), Vector3(1.6, 0.06, 1.6), Vector3(0, yaw, 0), Color(0.6, 0.5, 0.36))
	perches.append(base + Vector3(0.5, h + 0.04, 0.5))
	# low rail (cat walks under) + seat
	for s in [-1, 1]:
		Level.rbox(lv, base + b * Vector3(s * 0.78, 0, 0) + Vector3(0, h + 0.5, 0), Vector3(0.05, 0.05, 1.6), Vector3(0, yaw, 0), Color(0.5, 0.4, 0.3))
	Level.rbox(lv, base + b * Vector3(0, 0, -0.78) + Vector3(0, h + 0.5, 0), Vector3(1.6, 0.05, 0.05), Vector3(0, yaw, 0), Color(0.5, 0.4, 0.3))
	Level.rbox(lv, base + b * Vector3(0, 0, -0.5) + Vector3(0, h + 0.4, 0), Vector3(1.0, 0.05, 0.3), Vector3(0, yaw, 0), Color(0.6, 0.5, 0.36))
	# ladder: one climbable collider + rungs
	var lad := Level.rbox(lv, base + b * Vector3(0, 0, 1.15) + Vector3(0, h * 0.5, 0), Vector3(0.5, h, 0.05), Vector3(0, yaw, 0), Color(0.5, 0.4, 0.3), true)
	lad.get_child(1).visible = false
	_climb(lad, false)
	for s in [-1, 1]:
		Level.rbox(lv, base + b * Vector3(s * 0.25, 0, 1.15) + Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.05), Vector3(0, yaw, 0), Color(0.5, 0.4, 0.3), false)
	for k in 10:
		Level.rbox(lv, base + b * Vector3(0, 0, 1.15) + Vector3(0, 0.3 + k * 0.3, 0), Vector3(0.5, 0.04, 0.04), Vector3(0, yaw, 0), Color(0.55, 0.45, 0.33), false)
	obstacles.append([Vector2(base.x, base.z), 1.1])


static func gate(pos: Vector3) -> void:
	# wooden fence across the south end with an open gate (walk through -> back to the yard)
	for s in [-1, 1]:
		for k in 5:
			var x: float = s * (1.0 + k * 2.0)
			var g := ground(pos.x + x, pos.z)
			Level.box(lv, g + Vector3(0, 0.7, 0), Vector3(0.12, 1.4, 0.12), Color(0.55, 0.45, 0.32))
			if k < 4:
				var g2 := ground(pos.x + x + s * 2.0, pos.z)
				var mid := (g + g2) * 0.5
				for y in [0.45, 1.05]:
					var rail := Level.box(lv, mid + Vector3(0, y, 0), Vector3(2.0, 0.08, 0.06), Color(0.6, 0.5, 0.36))
					_climb(rail)
	# swung-open gate leaf
	var gp := ground(pos.x - 1.0, pos.z)
	Level.rbox(lv, gp + Vector3(0, 0.75, 0.5), Vector3(0.06, 1.1, 1.0), Vector3.ZERO, Color(0.62, 0.52, 0.38), false)
	# sign
	Level.box(lv, ground(pos.x + 1.6, pos.z - 0.6) + Vector3(0, 0.6, 0), Vector3(0.08, 1.2, 0.08), Color(0.5, 0.4, 0.3))
	Level.box(lv, ground(pos.x + 1.6, pos.z - 0.6) + Vector3(0, 1.15, 0), Vector3(0.7, 0.3, 0.04), Color(0.7, 0.6, 0.42))


static func _scatter() -> void:
	# grass tufts, ferns, flowers, mushrooms as multimeshes (cheap, no collision)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var sets := {
		"grass": {"mesh": LowPoly.cyl(0.0, 0.5, 3), "n": 5000},
		"fern": {"mesh": LowPoly.cyl(0.0, 0.5, 5), "n": 700},
		"flower": {"mesh": LowPoly.box(0.0), "n": 900},
		"shroom": {"mesh": LowPoly.sphere(5, 3), "n": 120},
	}
	for key in sets:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = sets[key].mesh
		var want: int = sets[key].n
		var xfs: Array[Transform3D] = []
		var cols: Array[Color] = []
		var tries := 0
		while xfs.size() < want and tries < want * 6:
			tries += 1
			var x := rng.randf_range(-HALF + 2, HALF - 2)
			var z := rng.randf_range(-HALF + 2, HALF - 2)
			var h := height(x, z)
			if h < WATER_Y + 0.05 or path_dist(x, z) < 0.6:
				continue
			var dm := Vector2(x, z).distance_to(MEADOW)
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			match key:
				"grass":
					var s := rng.randf_range(0.12, 0.3)
					xfs.append(Transform3D(b.scaled(Vector3(0.05, s, 0.05) * rng.randf_range(0.8, 1.4)), Vector3(x, h + s * 0.5, z)))
					cols.append(C_GRASS2.lerp(Color(0.6, 0.7, 0.3), rng.randf() * 0.5))
				"fern":
					if dm < MEADOW_R:
						continue
					var s := rng.randf_range(0.3, 0.6)
					xfs.append(Transform3D(b.scaled(Vector3(s, s * 0.35, s)), Vector3(x, h + s * 0.15, z)))
					cols.append(Color(0.25, 0.45, 0.2).lightened(rng.randf() * 0.1))
				"flower":
					if dm > MEADOW_R + 2.0 and rng.randf() < 0.85:
						continue
					var y := rng.randf_range(0.12, 0.3)
					xfs.append(Transform3D(b.scaled(Vector3(0.045, 0.03, 0.045)), Vector3(x, h + y, z)))
					cols.append([Color(0.95, 0.9, 0.3), Color(0.95, 0.95, 0.95), Color(0.75, 0.4, 0.9), Color(0.95, 0.4, 0.3)][rng.randi() % 4])
					if rng.randf() < 0.06:
						flowers.append(Vector3(x, h + y, z))
				"shroom":
					if dm < MEADOW_R:
						continue
					var s := rng.randf_range(0.04, 0.09)
					xfs.append(Transform3D(b.scaled(Vector3(s, s * 0.6, s)), Vector3(x, h + s * 0.5, z)))
					cols.append(Color(0.85, 0.2, 0.15) if rng.randf() < 0.4 else Color(0.85, 0.78, 0.65))
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Scatter_" + key
		mmi.material_override = LowPoly.mat(Color.WHITE, 0.9)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lv.add_child(mmi)


# ------------------------------------------------------------------ build
static func build(root: Node3D) -> Dictionary:
	perches.clear()
	trunks.clear()
	obstacles.clear()
	flowers.clear()
	lv = Node3D.new()
	lv.name = "Forest"
	root.add_child(lv)
	_noise = null
	_terrain()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024

	# --- landmark features first so trees keep clear of them ---
	# stepping stones across the stream on the path
	var sz0 := stream_z(0.0)
	for k in 6:
		var x := -0.4 + sin(k * 1.3) * 0.35
		var z := sz0 - 2.5 + k * 1.0
		rock(Vector3(x, WATER_Y - 0.1, z), Vector3(0.7, 0.5, 0.6), rng.randf() * TAU, Color(0.5, 0.5, 0.52), false)
	# log bridge over the stream further east (balance beam)
	var bx := 9.0
	var bz := stream_z(bx)
	fallen_log(ground(bx - 0.4, bz - 3.6) + Vector3(0, 0.15, 0), ground(bx + 0.4, bz + 3.6) + Vector3(0, 0.15, 0), 0.22)
	# rock outcrop with ledges NW of the meadow: 0.5 / 1.0 / 1.6 / 2.3 m shelves
	var oc := Vector3(-14.0, 0, -8.0)
	oc.y = height(oc.x, oc.z)
	rock(oc + Vector3(0, 0.3, 0), Vector3(3.6, 1.4, 3.0), 0.3)
	rock(oc + Vector3(1.2, 0.7, -1.4), Vector3(2.6, 2.0, 2.4), 1.1)
	rock(oc + Vector3(-0.4, 1.3, -2.6), Vector3(2.4, 3.0, 2.2), 2.0)
	rock(oc + Vector3(-1.9, 1.0, -0.6), Vector3(1.4, 1.0, 1.6), 0.7)
	rock(oc + Vector3(2.4, 0.1, 0.8), Vector3(1.0, 0.7, 0.9), 2.4)
	obstacles.append([Vector2(oc.x, oc.z - 1.0), 3.0])
	# boulders around
	for k in 26:
		var x := rng.randf_range(-34, 34)
		var z := rng.randf_range(-34, 34)
		if Vector2(x, z).distance_to(MEADOW) < MEADOW_R or path_dist(x, z) < 1.5:
			continue
		var s := rng.randf_range(0.4, 1.4)
		rock(ground(x, z) + Vector3(0, s * 0.15, 0), Vector3(s * rng.randf_range(0.9, 1.5), s, s * rng.randf_range(0.9, 1.4)), rng.randf() * TAU)
	# hollow log + fallen logs
	hollow_log(ground(-4.0, 22.0) + Vector3(0, -0.02, 0), 0.4, 2.6)
	for spec in [[Vector2(6, 26), Vector2(10, 23)], [Vector2(-9, 14), Vector2(-14, 16)], [Vector2(12, -6), Vector2(14, -1)], [Vector2(-20, 24), Vector2(-17, 28)], [Vector2(20, -18), Vector2(24, -15)], [Vector2(-6, -24), Vector2(-2, -27)]]:
		var a: Vector2 = spec[0]
		var b: Vector2 = spec[1]
		var r := rng.randf_range(0.18, 0.3)
		fallen_log(ground(a.x, a.y) + Vector3(0, r * 0.8, 0), ground(b.x, b.y) + Vector3(0, r * 0.8, 0), r)
	# leaning tree: fallen against another, a ramp up to 2.4 m
	fallen_log(ground(-22.0, -2.0) + Vector3(0, 0.15, 0), ground(-22.0, 2.6) + Vector3(0, 2.4, 0), 0.17)
	for p in [Vector2(-2.5, 19), Vector2(4, 16), Vector2(-7, -3), Vector2(8, -12), Vector2(-16, 4), Vector2(15, 16), Vector2(-10, -22), Vector2(3, -22)]:
		stump(ground(p.x, p.y), rng.randf_range(0.2, 0.32), rng.randf_range(0.3, 0.75))
	deer_stand(ground(12.0, -14.0), -0.6)
	gate(Vector3(0, 0, 37.0))

	# --- trees: poisson-ish scatter, kept out of the meadow, stream, path ---
	var placed: Array[Vector2] = [Vector2(-22.0, 2.6)]
	var tries := 0
	while placed.size() < 95 and tries < 4000:
		tries += 1
		var x := rng.randf_range(-36, 36)
		var z := rng.randf_range(-36, 36)
		var p := Vector2(x, z)
		if p.distance_to(MEADOW) < MEADOW_R + 1.0 or stream_dist(x, z) < 3.3 or p.distance_to(POND) < POND_R + 2.0:
			continue
		if path_dist(x, z) < 1.8 or p.distance_to(Vector2(SPAWN.x, SPAWN.z)) < 4.0 or p.distance_to(Vector2(oc.x, oc.z - 1.0)) < 4.5:
			continue
		if p.distance_to(Vector2(12, -14)) < 2.5:
			continue
		var ok := true
		for q in placed:
			if p.distance_to(q) < 3.4:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var roll := rng.randf()
		var g := ground(x, z) - Vector3(0, 0.1, 0)
		if roll < 0.45:
			pine(g, rng.randf_range(7.0, 12.0), rng)
		elif roll < 0.78:
			oak(g, rng.randf_range(5.0, 7.5), rng)
		else:
			birch(g, rng.randf_range(5.0, 8.0), rng)
		if rng.randf() < 0.35:
			var a := rng.randf() * TAU
			bush(ground(x + cos(a) * 1.6, z + sin(a) * 1.6), rng.randf_range(0.8, 1.3), rng, rng.randf() < 0.3)
	# the big climbing oak by the meadow edge (the "home tree")
	oak(ground(6.0, -4.0) - Vector3(0, 0.1, 0), 8.5, rng)
	# bushes along the stream + meadow edge (hiding spots)
	for k in 18:
		var a := rng.randf() * TAU
		var p := MEADOW + Vector2(cos(a), sin(a)) * (MEADOW_R + rng.randf_range(0.5, 2.0))
		if path_dist(p.x, p.y) > 1.5:
			bush(ground(p.x, p.y), rng.randf_range(0.7, 1.2), rng, rng.randf() < 0.4)
	_scatter()
	batch(lv)
	return {
		"spawn": spot(SPAWN.x, SPAWN.z),
		"spawn_yaw": 0.0,
		"points": [
			["gate", spot(SPAWN.x, SPAWN.z), 0.0],
			["stream crossing", spot(0.3, stream_z(0.0) + 4.0), 0.0],
			["meadow", spot(MEADOW.x, MEADOW.y + 6.0), 0.0],
			["rock outcrop", spot(-11.0, -6.0), 0.9],
			["big oak", spot(6.0, -2.4), 0.0],
			["pond", spot(14.0, 11.0), -0.9],
			["deer stand", spot(12.6, -12.4), 0.6],
			["log bridge", spot(9.0, stream_z(9.0) + 4.6), 0.0],
		],
	}


# ------------------------------------------------------------------ batching
## merges every static vertex-colored mesh under `root` into one ArrayMesh per CELL x CELL m chunk.
## thousands of separate MeshInstances break the web (compatibility) renderer and cost a draw call each,
## so the colliders stay as they are and only the visuals get merged. big meshes (terrain) are left alone.
const CELL := 16.0

static func batch(root: Node3D) -> void:
	var chunks := {}
	var victims: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or not mat.vertex_color_use_as_albedo:
			continue
		var xf := mi.global_transform
		var aabb := xf * mi.get_aabb()
		if aabb.size.length() > 30.0:
			continue
		var key := Vector2i(floori(aabb.get_center().x / CELL), floori(aabb.get_center().z / CELL))
		if not chunks.has(key):
			chunks[key] = [[PackedVector3Array(), PackedVector3Array(), PackedColorArray()]]
		var list: Array = chunks[key]
		# webgl drops vertices past ~32k per draw, so start a fresh mesh well before that
		if (list[list.size() - 1][0] as PackedVector3Array).size() > 24000:
			list.append([PackedVector3Array(), PackedVector3Array(), PackedColorArray()])
		var ch: Array = list[list.size() - 1]
		var nb := xf.basis.inverse().transposed()
		var tint := mat.albedo_color
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := idx.size() if idx.size() > 0 else verts.size()
			var pv: PackedVector3Array = ch[0]
			var pn: PackedVector3Array = ch[1]
			var pc: PackedColorArray = ch[2]
			for k in count:
				var i := idx[k] if idx.size() > 0 else k
				pv.append(xf * verts[i])
				pn.append((nb * norms[i]).normalized() if norms.size() > 0 else Vector3.UP)
				var c := cols[i] if cols.size() > 0 else Color.WHITE
				pc.append(Color(c.r * tint.r, c.g * tint.g, c.b * tint.b))
			ch[0] = pv
			ch[1] = pn
			ch[2] = pc
		victims.append(mi)
	for key in chunks:
		for part_i in (chunks[key] as Array).size():
			var ch: Array = chunks[key][part_i]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = ch[0]
			arr[Mesh.ARRAY_NORMAL] = ch[1]
			arr[Mesh.ARRAY_COLOR] = ch[2]
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var out := MeshInstance3D.new()
			out.mesh = m
			out.material_override = LowPoly.mat(Color.WHITE, 0.9)
			out.name = "Chunk_%d_%d_%d" % [key.x, key.y, part_i]
			root.add_child(out)
	for mi in victims:
		mi.get_parent().remove_child(mi)
		mi.free()
