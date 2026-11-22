class_name CityBlock
extends Node3D
## the city, rebuilt small and dense (2026-11-22): one 92 x 92 m crossroads at cat scale instead
## of the old osm map. two streets (main st east-west, cross st north-south) meet in the middle
## with traffic lights + crosswalks (traffic: city_traffic.gd). the four blocks around them:
##   nw  neko ramen corner, apartments, laundromat, the alley, a back lot with a loading dock
##   ne  deli, apartments with a fire escape, arcade, hotel tower, parking lot, backyards w/ a treehouse
##   sw  bodega, noodle bar, hotel, a construction site (unfinished floors + scaffold), a plaza + cat cafe
##   se  the park: big climbable trees, benches, a raised pond with a fountain, playground, gazebo
## everything a cat uses: sills, ac units, awnings, drain pipes, fire escapes (switchback ramps),
## parapets, cornices, fences, dumpsters, crates, pallets, car roofs, crawl spaces (loading dock,
## porch, gazebo, footbridge stairs, under parked cars), roof gaps + a sign bridge + a footbridge.
##
## looks: every static box goes into one merged mesh per 12 m cell with one shader
## (city_block.gdshader, pattern id per box: brick, concrete, planks, grating, glow, glass...).
## collision: one StaticBody3D per (surface, climbable, cell), many box / cylinder shapes each.

const SHADER := preload("res://scripts/city/city_block.gdshader")
const HALF := 46.0           # the map edge (x and z)
const ROAD := 5.0            # roadway half width: 2 lanes + parking lanes
const WALK := 9.0            # sidewalk outer edge
const CURB := 0.15
const FLOOR_H := 3.3
const CELL := 12.0
const MAX_LIGHTS := 60

enum {PLAIN, BRICK, CONC, WOOD, GRASS, METAL, GLOW, GLASS, WATER, ASPHALT, FABRIC, LEAF, TILE}

const C_ROAD := Color(0.16, 0.16, 0.18)
const C_WALK := Color(0.46, 0.45, 0.47)
const C_CURB := Color(0.6, 0.6, 0.6)
const C_METAL := Color(0.22, 0.23, 0.26)
const C_RUST := Color(0.38, 0.2, 0.14)
const C_WOOD := Color(0.45, 0.31, 0.2)
const C_BARK := Color(0.3, 0.22, 0.16)
const C_LEAF := Color(0.24, 0.48, 0.2)
const C_GRASS := Color(0.26, 0.44, 0.2)
const C_DUMP := Color(0.12, 0.3, 0.2)
const NEON := [Color(3.0, 0.6, 1.8), Color(0.5, 2.6, 3.0), Color(3.0, 1.9, 0.5), Color(1.2, 3.0, 0.9), Color(1.9, 1.1, 3.0), Color(3.0, 0.7, 0.5)]
const WARM := [Color(1.0, 0.72, 0.42), Color(1.0, 0.82, 0.55), Color(0.62, 0.8, 1.0), Color(1.0, 0.5, 0.75), Color(0.75, 1.0, 0.8)]

var rng := RandomNumberGenerator.new()
var n_boxes := 0
var n_lights := 0
var n_shapes := 0

# what the other systems read
var start := Vector3(-38.0, CURB, 7.0)
var start_yaw := -PI * 0.5
var vent_at := Vector3(-27.0, CURB, 7.4)
var exit_at := Vector3(-44.6, CURB, 7.0)
var perches: Array[Vector3] = []      # bird perches: parapet corners, wires, lamp heads, branches
var pigeon_spots: Array[Vector3] = [] # pigeon flocks on the pavement
var sparrow_spots: Array[Vector3] = []
var rat_dens: Array = []              # [home, [hides]]
var trunks: Array = []                # [base, radius, height]
var labels: Array = []                # map labels [text, Vector3]
var spots: Array = []                 # [name, pos, yaw] (t key, tour)
var parked: Array = []                # [pos, yaw] parked car spots along the curbs
var blockers: Array = []              # [Vector2 centre, radius] prey steer round these

var _buckets := {}                    # cell -> [verts, normals, colors, uvs]
var _bodies := {}
var _mat: ShaderMaterial
static var _unit_v := PackedVector3Array()
static var _unit_n := PackedVector3Array()


func build() -> void:
	rng.seed = 4242
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_unit_cube()
	_ground()
	_road_marks()
	_streets()
	_nw()
	_ne()
	_sw()
	_park()
	_bridges()
	_edges()
	_backdrop()
	_flush()
	spots = [
		["s main st", start, start_yaw],
		["the alley", Vector3(-34.5, CURB, -14.0), PI],
		["neko ramen roof", Vector3(-15.0, 10.17, -15.0), -PI * 0.5],
		["the back lot", Vector3(-27.0, CURB, -30.0), 0.0],
		["backyards", Vector3(34.0, CURB, -28.0), 0.0],
		["the park", Vector3(14.0, 0.2, 14.0), -PI * 0.75],
		["playground", Vector3(18.0, 0.2, 30.0), PI],
		["construction site", Vector3(-28.0, CURB, 27.0), PI * 0.5],
		["footbridge", Vector3(27.1, 5.32, 0.0), 0.0],
	]


# ================================================================ mesh + collision kit

func _unit_cube() -> void:
	if not _unit_v.is_empty():
		return
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * 0.5
		var a := c - u * 0.5 - v * 0.5
		var b := c + u * 0.5 - v * 0.5
		var cc := c + u * 0.5 + v * 0.5
		var d := c - u * 0.5 + v * 0.5
		for p in [a, cc, b, a, d, cc]:
			_unit_v.append(p)
			_unit_n.append(n)


func _bucket(p: Vector3) -> Array:
	var cell := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if not _buckets.has(cell):
		_buckets[cell] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array()]
	return _buckets[cell]


func _emit(xf: Transform3D, verts: PackedVector3Array, norms: PackedVector3Array, col: Color, pat: int, glow: float) -> void:
	var b := _bucket(xf.origin)
	var vv: PackedVector3Array = b[0]
	var nn: PackedVector3Array = b[1]
	var cc: PackedColorArray = b[2]
	var uu: PackedVector2Array = b[3]
	b[0] = PackedVector3Array()   # drop the bucket's ref so the appends don't copy the array
	b[1] = PackedVector3Array()
	b[2] = PackedColorArray()
	b[3] = PackedVector2Array()
	var nb := xf.basis.inverse().transposed()
	var uv := Vector2(pat, glow)
	for i in verts.size():
		vv.append(xf * verts[i])
		var n := (nb * norms[i]).normalized()
		nn.append(n)
		# a touch of fake ambient occlusion: undersides darker
		var k := 0.62 if n.y < -0.5 else 1.0
		cc.append(Color(col.r * k, col.g * k, col.b * k))
		uu.append(uv)
	b[0] = vv
	b[1] = nn
	b[2] = cc
	b[3] = uu


func _body(at: Vector3, surf: String, climb: bool) -> StaticBody3D:
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	var key := "%s|%s|%d,%d" % [surf, climb, cell.x, cell.y]
	if _bodies.has(key):
		return _bodies[key]
	var sb := StaticBody3D.new()
	sb.name = "City_%s%s_%d_%d" % [surf, "_climb" if climb else "", cell.x, cell.y]
	sb.set_meta("surface", surf)
	if climb:
		sb.add_to_group("climbable")
	if surf == "bark" or surf == "wood":
		sb.add_to_group("scratchable")
	add_child(sb)
	_bodies[key] = sb
	return sb


func _shape(xf: Transform3D, shape: Shape3D, surf: String, climb: bool) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	_body(xf.origin, surf, climb).add_child(cs)
	n_shapes += 1


## a box centred at c. basis = orientation (no scale). solid = collides
func box(c: Vector3, size: Vector3, col: Color, pat := PLAIN, surf := "stone", solid := true, climb := false, basis := Basis(), glow := 0.0) -> void:
	_emit(Transform3D(basis * Basis.from_scale(size), c), _unit_v, _unit_n, col, pat, glow)
	n_boxes += 1
	if solid:
		var bs := BoxShape3D.new()
		bs.size = size
		_shape(Transform3D(basis, c), bs, surf, climb)


## box from min corner + size (axis aligned)
func bx(minc: Vector3, size: Vector3, col: Color, pat := PLAIN, surf := "stone", solid := true, climb := false) -> void:
	box(minc + size * 0.5, size, col, pat, surf, solid, climb)


## glowing box (neon, lit windows, lenses), no collision
func glow(c: Vector3, size: Vector3, col: Color, energy := 2.0, basis := Basis()) -> void:
	box(c, size, col, GLOW, "", false, false, basis, energy)


## upright prism (poles, trunks, pipes, tanks): base centre, height, radius
func cyl(base: Vector3, h: float, r: float, col: Color, pat := PLAIN, surf := "metal", solid := true, climb := false, segs := 8, basis := Basis()) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0) * 0.5, 0, sin(a0) * 0.5)
		var p1 := Vector3(cos(a1) * 0.5, 0, sin(a1) * 0.5)
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var up := Vector3.UP
		for p in [p0, p1 + up, p1, p0, p0 + up, p1 + up]:
			verts.append(p)
			norms.append(n)
		for p in [Vector3(0, 1, 0), p0 + up, p1 + up]:
			verts.append(p)
			norms.append(Vector3.UP)
		for p in [Vector3.ZERO, p1, p0]:
			verts.append(p)
			norms.append(Vector3.DOWN)
	# winding: the side quads above are clockwise seen from outside -> flip
	var fv := PackedVector3Array()
	var fn := PackedVector3Array()
	for i in range(0, verts.size(), 3):
		fv.append(verts[i])
		fv.append(verts[i + 2])
		fv.append(verts[i + 1])
		fn.append(norms[i])
		fn.append(norms[i + 2])
		fn.append(norms[i + 1])
	_emit(Transform3D(basis * Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), base), fv, fn, col, pat, 0.0)
	n_boxes += 1
	if solid:
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = h
		_shape(Transform3D(basis, base + basis * Vector3(0, h * 0.5, 0)), cy, surf, climb)


## a blob of leaves (no collision): a squashed faceted sphere
func leaves(c: Vector3, size: Vector3, col := C_LEAF) -> void:
	var m: ArrayMesh = LowPoly.sphere(7, 5)
	var arr := m.surface_get_arrays(0)
	var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx = arr[Mesh.ARRAY_INDEX]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	if idx is PackedInt32Array and idx.size() > 0:
		for i in idx:
			v.append(sv[i])
			n.append(sn[i])
	else:
		v = sv
		n = sn
	_emit(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(size), c), v, n, col.lerp(Color(0.25, 0.4, 0.12), rng.randf() * 0.4), LEAF, 0.0)


func light(at: Vector3, col: Color, energy := 1.2, rng_ := 6.0) -> void:
	if n_lights >= MAX_LIGHTS:
		return
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	add_child(l)
	n_lights += 1


func sign_text(text: String, at: Vector3, normal: Vector3, col: Color, px := 0.012, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 10
	l.outline_modulate = Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.9)
	l.shaded = false
	l.double_sided = false
	l.position = at
	add_child(l)
	if absf(normal.y) < 0.9:
		l.look_at(at - normal, Vector3.UP)
	l.visibility_range_end = 70.0
	return l


# ---------------------------------------------------------------- facade frames

## a building face: start point (y 0), along unit, out normal, length
func _face(r: Rect2, f: String) -> Dictionary:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	var d := {}
	match f:
		"n": d = {"s": Vector3(x0, 0, z0), "a": Vector3(1, 0, 0), "o": Vector3(0, 0, -1), "L": r.size.x}
		"s": d = {"s": Vector3(x0, 0, z1), "a": Vector3(1, 0, 0), "o": Vector3(0, 0, 1), "L": r.size.x}
		"w": d = {"s": Vector3(x0, 0, z0), "a": Vector3(0, 0, 1), "o": Vector3(-1, 0, 0), "L": r.size.y}
		_: d = {"s": Vector3(x1, 0, z0), "a": Vector3(0, 0, 1), "o": Vector3(1, 0, 0), "L": r.size.y}
	var a: Vector3 = d.a
	d["B"] = Basis(a, Vector3.UP, a.cross(Vector3.UP))
	return d


func fp(F: Dictionary, u: float, y: float, out: float) -> Vector3:
	return F.s + F.a * u + F.o * out + Vector3.UP * y


## box on a face: (u, y, out) centre, (sa along, sh high, so out) size. tilt = rises along u
func fbox(F: Dictionary, u: float, y: float, out: float, sa: float, sh: float, so: float, col: Color, pat := PLAIN, surf := "stone", solid := true, climb := false, tilt := 0.0, gl := 0.0) -> void:
	var b: Basis = F.B
	if tilt != 0.0:
		b = b * Basis(Vector3(0, 0, 1), tilt)
	box(fp(F, u, y, out), Vector3(sa, sh, so), col, pat, surf, solid, climb, b, gl)


func fglow(F: Dictionary, u: float, y: float, out: float, sa: float, sh: float, so: float, col: Color, energy := 2.0) -> void:
	fbox(F, u, y, out, sa, sh, so, col, GLOW, "", false, false, 0.0, energy)


# ================================================================ ground + streets

func _ground() -> void:
	# the road: one slab under everything (runs on into the tunnels)
	box(Vector3(0, -0.25, 0), Vector3(2 * HALF + 24, 0.5, 2 * HALF + 24), C_ROAD, ASPHALT, "stone")
	# four raised blocks (sidewalk height): buildings, yards and the park sit on these
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cx: float = sx * (ROAD + HALF) * 0.5
			var cz: float = sz * (ROAD + HALF) * 0.5
			box(Vector3(cx, CURB * 0.5, cz), Vector3(HALF - ROAD, CURB, HALF - ROAD), C_WALK, CONC, "stone")
			# curb stones along both road edges
			box(Vector3(cx, CURB * 0.5 + 0.001, sz * (ROAD + 0.12)), Vector3(HALF - ROAD, CURB + 0.004, 0.24), C_CURB, CONC, "", false)
			box(Vector3(sx * (ROAD + 0.12), CURB * 0.5 + 0.001, cz), Vector3(0.24, CURB + 0.004, HALF - ROAD), C_CURB, CONC, "", false)
	# manholes, drains + steam
	for p in [Vector3(-20, 0, 1.2), Vector3(14, 0, -1.6), Vector3(1.4, 0, 24), Vector3(-1.2, 0, -30), Vector3(33, 0, 1.6)]:
		cyl(p + Vector3(0, -0.005, 0), 0.02, 0.36, Color(0.1, 0.1, 0.11), METAL, "", false, false, 12)


func _road_marks() -> void:
	var white := Color(0.85, 0.85, 0.82)
	var yellow := Color(0.9, 0.7, 0.15)
	for s in [-1.0, 1.0]:
		var a0 := WALK + 0.5
		var mid: float = s * (a0 + HALF + 6) * 0.5
		var ln := HALF + 6 - a0
		# centre double yellow + parking lane lines, main st (x) and cross st (z)
		for off in [-0.08, 0.08]:
			box(Vector3(mid, 0.003, off), Vector3(ln, 0.006, 0.07), yellow, PLAIN, "", false)
			box(Vector3(off, 0.003, mid), Vector3(0.07, 0.006, ln), yellow, PLAIN, "", false)
		for side in [-1.0, 1.0]:
			box(Vector3(mid, 0.003, side * 3.45), Vector3(ln, 0.006, 0.08), white, PLAIN, "", false)
			box(Vector3(side * 3.45, 0.003, mid), Vector3(0.08, 0.006, ln), white, PLAIN, "", false)
		# zebra crosswalks on all four arms of the crossing + stop lines
		for k in 9:
			var w := -4.4 + k * 1.1
			box(Vector3(s * 7.0, 0.004, w), Vector3(3.0, 0.008, 0.55), white, PLAIN, "", false)
			box(Vector3(w, 0.004, s * 7.0), Vector3(0.55, 0.008, 3.0), white, PLAIN, "", false)
		box(Vector3(s * 9.2, 0.004, -s * 1.75), Vector3(0.35, 0.008, 3.3), white, PLAIN, "", false)
		box(Vector3(s * 1.75, 0.004, -s * 9.2), Vector3(3.3, 0.008, 0.35), white, PLAIN, "", false)
	# bus stop box on the north kerb of main st (east of the crossing, by the deli)
	box(Vector3(-18.5, 0.003, 4.2), Vector3(9.0, 0.006, 0.08), yellow, PLAIN, "", false)
	sign_text("BUS", Vector3(-18.5, 0.01, 4.4), Vector3.UP, Color(0.9, 0.7, 0.15), 0.02).rotation = Vector3(-PI * 0.5, 0, 0)


## sidewalk furniture along the curbs: lamps, street trees, hydrants, meters, bins, boxes,
## benches, a bus shelter, utility poles with sagging wires (pigeon perches)
func _streets() -> void:
	var curb := ROAD + 0.55
	# [axis, side]: axis "x" = along main st (z fixed), "z" = along cross st (x fixed)
	for axis in ["x", "z"]:
		for side in [-1.0, 1.0]:
			for seg in [-1.0, 1.0]:
				var u := 12.5
				var i := 0
				while u < HALF - 2.0:
					var a: float = seg * u
					var p := Vector3(a, CURB, side * curb) if axis == "x" else Vector3(side * curb, CURB, a)
					var skip: bool = (axis == "x" and side > 0 and seg > 0) or (axis == "z" and side > 0 and seg > 0)
					var park_edge: bool = skip    # the park side gets its own iron fence + trees
					if axis == "x" and side > 0 and a > -21.0 and a < -16.0:
						u += 5.5
						i += 1
						continue    # the bus shelter
					match i % 4:
						0: _lamp(p, axis, side)
						1:
							if not park_edge:
								_street_tree(p)
						2: _clutter(p, axis, side, i)
						3:
							if not park_edge:
								_street_tree(p)
					u += 5.5
					i += 1
	# a few hydrants + meters + bins right by the corners
	for c in [Vector3(-10.3, CURB, 5.8), Vector3(10.3, CURB, -5.8), Vector3(-5.8, CURB, -10.3), Vector3(5.8, CURB, 10.3)]:
		_hydrant(c)
	_bus_shelter(Vector3(-18.5, CURB, 5.9))
	# parked cars: along both parking lanes, away from the crossing, the bus stop and the footbridge
	for side in [-1.0, 1.0]:
		for x in [-40.0, -33.5, -27.0, 15.5, 22.0, 35.5, 42.0]:
			if side > 0 and x < -14.0 and x > -24.0:
				continue
			parked.append([Vector3(x, 0, side * 4.25), -PI * 0.5 if side > 0 else PI * 0.5])
		for z in [-40.0, -33.0, -15.5, 15.5, 24.0, 33.0, 40.0]:
			if side < 0 and z > -24.0 and z < -14.0:
				continue
			parked.append([Vector3(side * 4.25, 0, z), PI if side > 0 else 0.0])
	# utility wires strung across main st and cross st (perches)
	for w in [[Vector3(-30, 7.2, -8.6), Vector3(-30, 7.2, 8.6)], [Vector3(39.5, 7.0, -8.6), Vector3(39.5, 7.0, 8.6)],
			[Vector3(-8.6, 7.4, -30), Vector3(8.6, 7.4, -30)], [Vector3(-8.6, 7.1, 32), Vector3(8.6, 7.1, 32)]]:
		_wire(w[0], w[1], 0.9)
		_pole(w[0])
		_pole(w[1])


func _lamp(p: Vector3, axis: String, side: float) -> void:
	cyl(p, 4.6, 0.07, C_METAL, METAL, "metal")
	cyl(p, 0.5, 0.13, C_METAL, METAL, "metal")
	var arm := Vector3(0, 0, -side) if axis == "x" else Vector3(-side, 0, 0)
	var head := p + Vector3(0, 4.55, 0) + arm * 0.7
	box(p + Vector3(0, 4.55, 0) + arm * 0.35, Vector3(0.06, 0.06, 0.7) if axis == "x" else Vector3(0.7, 0.06, 0.06), C_METAL, METAL, "metal")
	box(head, Vector3(0.36, 0.12, 0.5), C_METAL, METAL, "metal")
	glow(head - Vector3(0, 0.07, 0), Vector3(0.3, 0.02, 0.42), Color(1.0, 0.8, 0.55), 4.0)
	light(head - Vector3(0, 0.4, 0), Color(1.0, 0.78, 0.5), 1.6, 9.0)
	perches.append(head + Vector3(0, 0.07, 0))


func _street_tree(p: Vector3) -> void:
	bx(p + Vector3(-0.6, -0.002, -0.6), Vector3(1.2, 0.006, 1.2), Color(0.13, 0.12, 0.11), METAL, "", false)
	var h := 2.6 + rng.randf() * 0.8
	cyl(p, h, 0.09, C_BARK, PLAIN, "bark", true, true, 7)
	trunks.append([p, 0.09, h])
	leaves(p + Vector3(0, h + 0.3, 0), Vector3(2.0, 1.5, 2.0))
	leaves(p + Vector3(0.4, h - 0.2, 0.2), Vector3(1.4, 1.0, 1.4))
	perches.append(p + Vector3(0.3, h + 0.6, 0))
	blockers.append([Vector2(p.x, p.z), 0.2])


func _clutter(p: Vector3, axis: String, side: float, i: int) -> void:
	var along := Vector3(1, 0, 0) if axis == "x" else Vector3(0, 0, 1)
	match (i / 4 + int(absf(p.x + p.z))) % 5:
		0:   # newspaper boxes (a step up onto awnings)
			for k in 2:
				var q := p + along * (k * 0.55 - 0.27)
				box(q + Vector3(0, 0.5, 0), Vector3(0.45, 1.0, 0.45), [Color(0.7, 0.12, 0.1), Color(0.1, 0.3, 0.6)][k], METAL, "metal")
				glow(q + Vector3(0, 0.75, 0) - Vector3(0, 0, side * 0.23) if axis == "x" else q + Vector3(0, 0.75, 0) - Vector3(side * 0.23, 0, 0), Vector3(0.3, 0.2, 0.02) if axis == "x" else Vector3(0.02, 0.2, 0.3), Color(0.9, 0.9, 0.8), 0.6)
		1:   # trash can
			cyl(p, 0.95, 0.27, Color(0.2, 0.24, 0.22), METAL, "metal", true, false, 10)
			cyl(p + Vector3(0, 0.95, 0), 0.06, 0.3, Color(0.15, 0.17, 0.16), METAL, "metal", true, false, 10)
		2:   # parking meter pair
			for k in 2:
				var q := p + along * (k * 1.2 - 0.6)
				cyl(q, 1.1, 0.03, C_METAL, METAL, "metal")
				box(q + Vector3(0, 1.22, 0), Vector3(0.16, 0.26, 0.12), Color(0.5, 0.52, 0.55), METAL, "metal")
				glow(q + Vector3(0, 1.26, 0), Vector3(0.08, 0.05, 0.13), Color(0.2, 1.0, 0.4), 1.5)
		3:   # bench
			_bench(p, along)
		_:   # vending machine against the curb side (1.8 m: up to the awnings)
			var n := Vector3(0, 0, -side) if axis == "x" else Vector3(-side, 0, 0)
			var sz := Vector3(0.9, 1.8, 0.75) if axis == "x" else Vector3(0.75, 1.8, 0.9)
			box(p + Vector3(0, 0.9, 0), sz, Color(0.75, 0.1, 0.2), METAL, "metal")
			glow(p + Vector3(0, 1.15, 0) + n * 0.38, Vector3(0.7, 1.0, 0.02) if axis == "x" else Vector3(0.02, 1.0, 0.7), Color(0.6, 0.9, 1.0), 2.0)
			light(p + Vector3(0, 1.2, 0) + n * 0.8, Color(0.6, 0.85, 1.0), 0.6, 3.0)
	blockers.append([Vector2(p.x, p.z), 0.4])


func _bench(p: Vector3, along: Vector3, col := C_WOOD) -> void:
	var side := Vector3(along.z, 0, along.x)
	var w := Vector3(1.6, 0.05, 0.42) if along.x != 0 else Vector3(0.42, 0.05, 1.6)
	box(p + Vector3(0, 0.45, 0), w, col, WOOD, "wood")
	var back := Vector3(1.6, 0.4, 0.05) if along.x != 0 else Vector3(0.05, 0.4, 1.6)
	box(p + Vector3(0, 0.75, 0) + side * 0.2, back, col, WOOD, "wood")
	for k in [-0.7, 0.7]:
		box(p + along * k + Vector3(0, 0.22, 0), Vector3(0.06, 0.45, 0.4) if along.x != 0 else Vector3(0.4, 0.45, 0.06), C_METAL, METAL, "metal")


func _hydrant(p: Vector3) -> void:
	cyl(p, 0.55, 0.11, Color(0.75, 0.15, 0.1), METAL, "metal", true, false, 8)
	cyl(p + Vector3(0, 0.55, 0), 0.1, 0.08, Color(0.75, 0.15, 0.1), METAL, "metal", true, false, 8)
	box(p + Vector3(0, 0.38, 0), Vector3(0.36, 0.08, 0.08), Color(0.75, 0.15, 0.1), METAL, "", false)


func _bus_shelter(p: Vector3) -> void:
	# glass box with a flat roof (2.45 m): bench 0.45 -> bin 0.95 -> roof
	for k in [-1.6, 1.6]:
		box(p + Vector3(k, 1.2, 0.6), Vector3(0.08, 2.4, 0.08), C_METAL, METAL, "metal")
		box(p + Vector3(k, 1.2, -0.6), Vector3(0.08, 2.4, 0.08), C_METAL, METAL, "metal")
	box(p + Vector3(0, 1.25, 0.66), Vector3(3.2, 2.0, 0.03), Color(0.5, 0.6, 0.7), GLASS, "glass")
	box(p + Vector3(0, 2.45, 0.05), Vector3(3.6, 0.1, 1.6), C_METAL, METAL, "metal")
	glow(p + Vector3(1.0, 1.3, 0.69), Vector3(1.0, 1.6, 0.02), Color(1.0, 0.45, 0.8), 2.2)
	sign_text("NINE LIVES\nINSURANCE", p + Vector3(1.0, 1.4, 0.71), Vector3(0, 0, 1), Color(1, 1, 1), 0.006)
	_bench(p + Vector3(-0.6, 0, 0.3), Vector3(1, 0, 0), C_METAL)
	cyl(p + Vector3(-2.2, 0, 0.2), 0.95, 0.27, Color(0.2, 0.24, 0.22), METAL, "metal", true, false, 10)
	light(p + Vector3(0, 2.2, 0), Color(0.8, 0.9, 1.0), 0.8, 4.0)
	perches.append(p + Vector3(1.4, 2.52, 0.6))
	labels.append(["bus stop", p])


func _pole(p: Vector3) -> void:
	cyl(Vector3(p.x, CURB, p.z), p.y + 0.5 - CURB, 0.12, C_BARK.darkened(0.2), WOOD, "wood", true, true, 6)
	box(Vector3(p.x, p.y + 0.2, p.z), Vector3(1.2, 0.1, 0.1) if absf(p.z) > absf(p.x) else Vector3(0.1, 0.1, 1.2), C_WOOD, WOOD, "wood")
	perches.append(Vector3(p.x, p.y + 0.55, p.z))


## a sagging cable a to b (pigeons sit on it). visual + perch points
func _wire(a: Vector3, b: Vector3, sag: float, col := Color(0.05, 0.05, 0.06), bulbs := false) -> void:
	var n := 10
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var p0 := a.lerp(b, t0) - Vector3(0, sag * 4.0 * t0 * (1.0 - t0), 0)
		var p1 := a.lerp(b, t1) - Vector3(0, sag * 4.0 * t1 * (1.0 - t1), 0)
		var mid := (p0 + p1) * 0.5
		var d := p1 - p0
		var xf := LowPoly.seg_xform(p0, p1)
		box(mid, Vector3(0.025, d.length(), 0.025), col, PLAIN, "", false, false, xf.basis.orthonormalized())
		if bulbs and i % 2 == 0:
			glow(mid - Vector3(0, 0.08, 0), Vector3(0.07, 0.1, 0.07), WARM[i % WARM.size()], 4.0)
		if i % 3 == 1:
			perches.append(mid + Vector3(0, 0.03, 0))


# ================================================================ buildings

## a building on lot r with its roof at h. faces: {"n"/"s"/"e"/"w": kind} kinds: shop, door,
## alley, blank. opts: col, pat, trim, names {face: text}, fire (face), water (tower), bill (text)
func building(r: Rect2, h: float, faces: Dictionary, opts := {}) -> void:
	var col: Color = opts.get("col", Color(0.5, 0.3, 0.25))
	var pat: int = opts.get("pat", BRICK)
	var trim: Color = opts.get("trim", col.lightened(0.3))
	var y0 := CURB
	var c := Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
	box(Vector3(c.x, (y0 + h) * 0.5, c.z), Vector3(r.size.x, h - y0, r.size.y), col, pat, "stone")
	var floors := maxi(1, roundi((h - y0 - 0.8) / FLOOR_H))
	# tar roof, parapet (cats walk along the top), cornice ledge
	box(Vector3(c.x, h + 0.01, c.z), Vector3(r.size.x - 0.3, 0.02, r.size.y - 0.3), Color(0.17, 0.17, 0.19), CONC, "", false)
	for f in ["n", "s", "e", "w"]:
		var F := _face(r, f)
		var L: float = F.L
		fbox(F, L * 0.5, h + 0.275, -0.11, L, 0.55, 0.22, trim, CONC, "stone")
		fbox(F, L * 0.5, h + 0.56, -0.11, L + 0.06, 0.04, 0.28, trim.lightened(0.1), CONC, "stone")
		fbox(F, L * 0.5, h - 0.75, 0.14, L + 0.56, 0.24, 0.28, trim, CONC, "stone")
		fbox(F, L * 0.5, h - 0.9, 0.07, L + 0.3, 0.1, 0.14, trim.darkened(0.2), CONC, "", false)
		# string courses between floors
		for k in range(1, floors):
			fbox(F, L * 0.5, y0 + k * FLOOR_H - 0.12, 0.03, L, 0.1, 0.06, trim.darkened(0.1), CONC, "", false)
		perches.append(fp(F, 0.4, h + 0.6, -0.11))
		perches.append(fp(F, L - 0.4, h + 0.6, -0.11))
		if faces.has(f):
			_facade(F, h, floors, str(faces[f]), opts, f)
	_roof(r, h, opts)
	if opts.has("name"):
		labels.append([str(opts.name), Vector3(c.x, h, c.z)])


func _facade(F: Dictionary, h: float, floors: int, kind: String, opts: Dictionary, f: String) -> void:
	var L: float = F.L
	var names: Dictionary = opts.get("names", {})
	var fire := str(opts.get("fire", "")) == f
	var fe0 := L * 0.5 - 3.0
	var fe1 := L * 0.5 + 3.0
	if kind == "blank":
		_blank(F, h)
		return
	# upper floors: windows, sills, ac units, flower boxes, balconies
	var bays := maxi(1, int(L / 2.6))
	var margin := (L - bays * 2.6) * 0.5
	for fl in range(1, floors):
		var yf := CURB + fl * FLOOR_H
		for i in bays:
			var u := margin + 1.3 + i * 2.6
			if fire and u > fe0 - 0.6 and u < fe1 + 0.6 and i % 2 == 1:
				continue
			_window(F, u, yf, kind == "door" and opts.get("balcony", false) and fl % 2 == 1 and i % 3 == 1)
	# ground floor
	match kind:
		"shop":
			_shopfront(F, str(names.get(f, "")), opts)
		"door":
			_stoops(F, opts)
		"alley":
			_backside(F, opts, fire, f)
	# drain pipes on the corners (climbable, all the way to the roof)
	if kind != "shop" or L > 10.0:
		_pipe(F, 0.35, h)
	if kind == "alley" and L > 9.0:
		_pipe(F, L - 0.35, h)
	if fire and floors >= 2:
		_fire_escape(F, fe0, fe1, floors, h)


func _window(F: Dictionary, u: float, yf: float, balcony: bool) -> void:
	var lit := rng.randf() < 0.42
	var wc: Color = WARM[rng.randi() % WARM.size()]
	# frame, glass (dark or lit), mullions, lintel
	fbox(F, u, yf + 1.55, 0.03, 1.3, 1.72, 0.06, Color(0.82, 0.8, 0.74), CONC, "", false)
	if lit:
		fglow(F, u, yf + 1.55, 0.065, 1.1, 1.5, 0.02, wc, 1.2 + rng.randf() * 1.6)
		if rng.randf() < 0.3:   # blinds half down
			fbox(F, u, yf + 1.95, 0.08, 1.1, 0.7, 0.01, Color(0.85, 0.82, 0.7), PLAIN, "", false)
	else:
		fbox(F, u, yf + 1.55, 0.065, 1.1, 1.5, 0.02, Color(0.3, 0.38, 0.5), GLASS, "", false)
	fbox(F, u, yf + 1.55, 0.08, 0.05, 1.5, 0.02, Color(0.82, 0.8, 0.74), PLAIN, "", false)
	fbox(F, u, yf + 1.75, 0.08, 1.1, 0.05, 0.02, Color(0.82, 0.8, 0.74), PLAIN, "", false)
	fbox(F, u, yf + 2.47, 0.07, 1.45, 0.14, 0.14, Color(0.7, 0.68, 0.62), CONC, "", false)
	if balcony:
		fbox(F, u, yf + 0.06, 0.55, 2.0, 0.12, 1.1, Color(0.6, 0.6, 0.6), CONC, "stone")
		fbox(F, u, yf + 1.0, 1.08, 2.0, 0.05, 0.05, C_METAL, METAL, "metal")
		for k in [-0.98, 0.98]:
			fbox(F, u + k, yf + 0.55, 0.55, 0.05, 0.95, 1.1, C_METAL, METAL, "metal", false)
			fbox(F, u + k, yf + 1.0, 0.55, 0.05, 0.05, 1.1, C_METAL, METAL, "metal")
		for k in 7:
			fbox(F, u - 0.9 + k * 0.3, yf + 0.55, 1.08, 0.025, 0.9, 0.025, C_METAL, METAL, "", false)
		if rng.randf() < 0.6:
			fbox(F, u + 0.5, yf + 0.32, 0.4, 0.4, 0.4, 0.4, Color(0.55, 0.3, 0.2), PLAIN, "stone")
			leaves(fp(F, u + 0.5, yf + 0.7, 0.4), Vector3(0.5, 0.5, 0.5))
		perches.append(fp(F, u, yf + 1.04, 1.08))
		return
	# sill: 26 cm deep, a cat can sit on it
	fbox(F, u, yf + 0.77, 0.13, 1.4, 0.06, 0.26, Color(0.72, 0.7, 0.64), CONC, "stone")
	var roll := rng.randf()
	if roll < 0.24:
		# window ac unit sat on the sill, sticking out: a step on the facade
		fbox(F, u + 0.15, yf + 1.01, 0.3, 0.64, 0.42, 0.52, Color(0.78, 0.78, 0.74), METAL, "metal")
		fbox(F, u + 0.15, yf + 1.01, 0.565, 0.56, 0.32, 0.01, Color(0.3, 0.3, 0.3), METAL, "", false)
		fbox(F, u + 0.15, yf + 0.5, 0.3, 0.03, 0.5, 0.03, Color(0.3, 0.25, 0.2), PLAIN, "", false)
	elif roll < 0.38:
		# flower box on the sill
		fbox(F, u, yf + 0.89, 0.2, 1.0, 0.18, 0.22, Color(0.45, 0.25, 0.15), WOOD, "wood")
		for k in 3:
			leaves(fp(F, u - 0.35 + k * 0.35, yf + 1.05, 0.2), Vector3(0.35, 0.25, 0.25), [Color(0.7, 0.2, 0.3), C_LEAF, Color(0.85, 0.7, 0.2)][k])
	elif roll < 0.48:
		# shutters
		for k in [-0.72, 0.72]:
			fbox(F, u + k, yf + 1.55, 0.06, 0.36, 1.6, 0.04, Color(0.2, 0.32, 0.28), WOOD, "", false)
	if rng.randf() < 0.12:
		perches.append(fp(F, u - 0.4, yf + 0.82, 0.13))


func _shopfront(F: Dictionary, name: String, opts: Dictionary) -> void:
	var L: float = F.L
	var col: Color = opts.get("shop_col", NEON[rng.randi() % NEON.size()])
	var awn: Color = opts.get("awning", [Color(0.6, 0.12, 0.12), Color(0.12, 0.35, 0.3), Color(0.15, 0.2, 0.45), Color(0.55, 0.45, 0.1)][rng.randi() % 4])
	var y0 := CURB
	# pillars + bulkhead + lit display windows + a door
	var n := maxi(2, int(L / 3.2))
	var w := L / n
	var door_i := n / 2
	for i in n + 1:
		fbox(F, clampf(i * w, 0.2, L - 0.2), y0 + 1.5, 0.08, 0.4, 3.0, 0.16, Color(0.25, 0.22, 0.22), CONC, "stone")
	for i in n:
		var u := (i + 0.5) * w
		if i == door_i:
			fbox(F, u, y0 + 1.15, 0.04, 1.1, 2.3, 0.04, Color(0.2, 0.25, 0.3), GLASS, "", false)
			fglow(F, u, y0 + 2.45, 0.06, 1.1, 0.12, 0.02, col * 0.6, 2.0)
			fbox(F, u + 0.4, y0 + 1.1, 0.09, 0.04, 0.4, 0.04, Color(0.8, 0.75, 0.5), METAL, "", false)
			fbox(F, u, y0 + 0.04, 0.35, 1.3, 0.08, 0.6, Color(0.3, 0.28, 0.27), CONC, "stone")
			continue
		fbox(F, u, y0 + 0.3, 0.06, w - 0.4, 0.6, 0.12, Color(0.18, 0.12, 0.1), WOOD, "wood")
		fglow(F, u, y0 + 1.55, 0.04, w - 0.4, 1.8, 0.02, WARM[(i + int(L)) % 2], 1.6)
		# stuff in the window: shelves, a sleepy shop cat shape, posters
		fbox(F, u, y0 + 1.0, -0.15, w - 0.6, 0.04, 0.3, Color(0.3, 0.22, 0.15), PLAIN, "", false)
		if (i + int(L)) % 3 == 0:
			fbox(F, u - 0.3, y0 + 1.1, -0.1, 0.35, 0.16, 0.2, Color(0.1, 0.1, 0.1), PLAIN, "", false)
			fbox(F, u - 0.12, y0 + 1.23, -0.1, 0.12, 0.12, 0.12, Color(0.1, 0.1, 0.1), PLAIN, "", false)
	# sign band + neon name
	fbox(F, L * 0.5, y0 + 3.1, 0.12, L - 0.2, 0.5, 0.2, Color(0.08, 0.08, 0.1), METAL, "metal")
	if name != "":
		var l := sign_text(name, fp(F, L * 0.5, y0 + 3.1, 0.24), F.o, col, 0.009)
		l.font_size = 72
	light(fp(F, L * 0.5, y0 + 2.2, 1.6), Color(col.r, col.g, col.b).clamp() * 0.9 + Color(0.1, 0.1, 0.1), 1.0, 6.0)
	# awning: 1.4 m out, sloping down, fabric (cats can climb + walk it), with a valance.
	# split in two with a small gap so you have to hop it
	var gap_u := L * 0.5 + (0.6 if n % 2 == 0 else 0.0)
	for half in 2:
		var u0 := 0.3 if half == 0 else gap_u + 0.35
		var u1 := gap_u - 0.35 if half == 0 else L - 0.3
		if u1 - u0 < 0.8:
			continue
		var um := (u0 + u1) * 0.5
		var slope := 0.25
		var o: Vector3 = F.o
		var cen := fp(F, um, y0 + 2.62, 0.75)
		# tilt about the along axis so the outer edge is lower
		var tb: Basis = Basis(F.a, slope if o.dot(F.B.z) > 0.0 else -slope) * F.B
		box(cen, Vector3(u1 - u0, 0.06, 1.5), awn, FABRIC, "fabric", true, true, tb)
		fbox(F, um, y0 + 2.33, 1.48, u1 - u0, 0.25, 0.03, awn.darkened(0.2), FABRIC, "", false)
		perches.append(fp(F, um, y0 + 2.75, 0.75))
	# a step up to the awning near one end: crates / bins / a planter
	var s_u := 0.9 if (int(L) % 2 == 0) else L - 0.9
	fbox(F, s_u, y0 + 0.3, 0.7, 0.6, 0.6, 0.5, Color(0.55, 0.42, 0.25), WOOD, "wood")
	fbox(F, s_u, y0 + 0.85, 0.7, 0.5, 0.5, 0.45, Color(0.6, 0.47, 0.3), WOOD, "wood")
	fbox(F, s_u, y0 + 1.3, 0.75, 0.45, 0.4, 0.4, Color(0.5, 0.38, 0.22), WOOD, "wood")
	if opts.get("blade", false):
		var bu := L - 0.6
		fbox(F, bu, y0 + 7.0, 0.9, 0.12, 6.0, 1.2, Color(0.08, 0.08, 0.1), METAL, "metal")
		var bc: Color = NEON[(int(L) + 2) % NEON.size()]
		fglow(F, bu, y0 + 7.0, 0.9, 0.16, 5.7, 0.06, bc, 1.0)
		var t := str(opts.get("blade_text", "HOTEL"))
		for k in t.length():
			var lab := sign_text(t[k], fp(F, bu + 0.09, y0 + 9.4 - k * 1.0, 0.9), F.a, bc, 0.02)
			lab.font_size = 64
			var lab2 := sign_text(t[k], fp(F, bu - 0.09, y0 + 9.4 - k * 1.0, 0.9), -F.a, bc, 0.02)
			lab2.font_size = 64


func _stoops(F: Dictionary, opts: Dictionary) -> void:
	var L: float = F.L
	var y0 := CURB
	for u in [L * 0.28, L * 0.72]:
		for k in 3:
			fbox(F, u, y0 + 0.1 + k * 0.2, 1.0 - k * 0.3, 1.6, 0.2, 0.9 - k * 0.3 + 0.3, Color(0.55, 0.5, 0.46), CONC, "stone")
		fbox(F, u, y0 + 1.75, 0.04, 1.1, 2.3, 0.05, Color(0.25, 0.14, 0.1), WOOD, "", false)
		fglow(F, u, y0 + 3.0, 0.1, 0.3, 0.2, 0.1, Color(1, 0.8, 0.5), 3.0)
		light(fp(F, u, y0 + 2.9, 0.6), Color(1.0, 0.8, 0.55), 0.7, 4.0)
		# a little concrete canopy over the door: 2.75 up, reachable from the railing
		fbox(F, u, y0 + 2.75, 0.5, 1.6, 0.12, 1.0, Color(0.6, 0.58, 0.55), CONC, "stone")
		for s in [-0.85, 0.85]:
			fbox(F, u + s, y0 + 0.9, 0.9, 0.05, 0.05, 1.0, C_METAL, METAL, "metal")
			fbox(F, u + s, y0 + 0.5, 1.35, 0.05, 0.85, 0.05, C_METAL, METAL, "metal", false)
	# ground floor windows with bars
	for u in [L * 0.5, 0.9, L - 0.9]:
		fbox(F, u, y0 + 1.8, 0.05, 1.0, 1.2, 0.03, Color(0.3, 0.35, 0.45), GLASS, "", false)
		for k in 5:
			fbox(F, u - 0.4 + k * 0.2, y0 + 1.8, 0.1, 0.025, 1.25, 0.025, C_METAL, METAL, "", false)
		fbox(F, u, y0 + 1.15, 0.12, 1.2, 0.06, 0.24, Color(0.7, 0.68, 0.62), CONC, "stone")


func _backside(F: Dictionary, opts: Dictionary, fire: bool, f: String) -> void:
	var L: float = F.L
	var y0 := CURB
	var du := L * 0.25
	# back door + metal hood + lamp
	fbox(F, du, y0 + 1.1, 0.04, 1.0, 2.2, 0.05, Color(0.3, 0.32, 0.3), METAL, "", false)
	fbox(F, du, y0 + 2.45, 0.35, 1.4, 0.06, 0.7, C_METAL, METAL, "metal")
	fglow(F, du, y0 + 2.3, 0.08, 0.25, 0.12, 0.08, Color(1.0, 0.65, 0.35), 3.0)
	light(fp(F, du, y0 + 2.2, 0.8), Color(1.0, 0.65, 0.35), 0.9, 5.0)
	fbox(F, du, y0 + 0.1, 0.5, 1.2, 0.2, 0.8, Color(0.4, 0.4, 0.4), CONC, "stone")
	# electrical boxes, gas meters, a vent fan, graffiti
	fbox(F, du + 1.3, y0 + 1.4, 0.12, 0.5, 0.7, 0.24, Color(0.5, 0.5, 0.48), METAL, "metal")
	fbox(F, du + 1.9, y0 + 1.6, 0.1, 0.35, 0.5, 0.2, Color(0.55, 0.52, 0.4), METAL, "metal")
	fbox(F, du + 2.6, y0 + 2.6, 0.08, 0.6, 0.6, 0.16, Color(0.35, 0.35, 0.35), METAL, "metal")
	fbox(F, du + 2.6, y0 + 2.6, 0.17, 0.5, 0.5, 0.02, Color(0.1, 0.1, 0.1), METAL, "", false)
	if L > 6.0:
		var g: Color = NEON[(int(L * 7.0)) % NEON.size()] * 0.09
		fbox(F, L * 0.62, y0 + 1.2, 0.012, 2.4, 1.3, 0.01, Color(g.r, g.g, g.b).clamp(), PLAIN, "", false)
	# a horizontal pipe run at 2.9 m: walk along it
	cyl(fp(F, 0.2, y0 + 2.9, 0.22), L - 0.4, 0.08, Color(0.32, 0.3, 0.28), METAL, "metal", true, false, 8, F.B * Basis(Vector3(0, 0, 1), -PI * 0.5))
	for k in range(1, int(L / 2.5)):
		fbox(F, k * 2.5, y0 + 2.85, 0.12, 0.05, 0.2, 0.24, C_METAL, METAL, "", false)
	# dumpster + bags + crates (dumpster top 1.25: hop onto it, then up)
	var nd = opts.get("no_dumpster", false)
	if not ((nd is bool and nd) or (nd is Array and f in nd)):
		var dpu := L * 0.6 if not fire else L * 0.5 - 2.4
		_dumpster(fp(F, dpu, CURB, 0.75), F.a)
		fbox(F, dpu + 1.4, y0 + 0.22, 0.5, 0.5, 0.44, 0.44, Color(0.05, 0.05, 0.06), PLAIN, "stone")
		fbox(F, dpu + 1.75, y0 + 0.18, 0.75, 0.42, 0.36, 0.4, Color(0.06, 0.06, 0.07), PLAIN, "stone")
		# a rat hole in the wall base by the dumpster
		var hole := fp(F, dpu - 1.3, y0 + 0.06, 0.005)
		fbox(F, dpu - 1.3, y0 + 0.07, 0.006, 0.16, 0.12, 0.01, Color(0.01, 0.01, 0.01), PLAIN, "", false)
		rat_dens.append([fp(F, dpu + 0.5, CURB, 1.6), [hole + F.o * 0.08, fp(F, dpu, CURB, 0.75)]])


func _dumpster(p: Vector3, along: Vector3) -> void:
	var b := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var c := Color(0.16, 0.42, 0.28) if int(absf(p.x * 3.0 + p.z)) % 2 == 0 else Color(0.3, 0.33, 0.4)
	box(p + Vector3(0, 0.62, 0), Vector3(1.9, 1.05, 1.1), c, METAL, "metal", true, false, b)
	box(p + Vector3(0, 0.13, 0), Vector3(1.75, 0.1, 0.95), C_METAL, METAL, "", false, false, b)   # raised: a gap under it for rats
	box(p + Vector3(0, 1.2, 0) + b * Vector3(0, 0, -0.1), Vector3(1.95, 0.06, 1.15), c.darkened(0.3), PLAIN, "metal", true, false, b * Basis(Vector3(1, 0, 0), 0.08))
	blockers.append([Vector2(p.x, p.z), 1.0])


func _pipe(F: Dictionary, u: float, h: float) -> void:
	cyl(fp(F, u, CURB, 0.13), h + 0.25 - CURB, 0.065, Color(0.3, 0.3, 0.32), METAL, "metal", true, true, 7)
	for k in range(1, int(h / 1.8)):
		fbox(F, u, CURB + k * 1.8, 0.07, 0.18, 0.06, 0.14, C_METAL, METAL, "", false)
	fbox(F, u, h + 0.3, 0.13, 0.2, 0.18, 0.2, Color(0.3, 0.3, 0.32), METAL, "metal")


func _blank(F: Dictionary, h: float) -> void:
	var L: float = F.L
	if L < 4.0:
		return
	var roll := rng.randf()
	if roll < 0.5:
		# ivy patch: climbable, from the ground most of the way up
		var w := minf(L * 0.4, 4.0)
		var u := rng.randf_range(w * 0.5 + 0.3, L - w * 0.5 - 0.3)
		var top := h * rng.randf_range(0.5, 0.9)
		fbox(F, u, (CURB + top) * 0.5, 0.06, w, top - CURB, 0.12, Color(0.16, 0.3, 0.13), LEAF, "fabric", true, true)
		for k in 4:
			leaves(fp(F, u + rng.randf_range(-w * 0.4, w * 0.4), rng.randf_range(1.0, top), 0.15), Vector3(0.8, 0.6, 0.3), Color(0.18, 0.34, 0.14))
	else:
		# a painted mural: big cat face blocks
		var u := L * 0.5
		var base := Color(0.15, 0.25, 0.5).lerp(Color(0.5, 0.2, 0.35), rng.randf())
		fbox(F, u, 3.2, 0.012, minf(L - 1.0, 6.0), 4.5, 0.01, base, PLAIN, "", false)
		fbox(F, u, 3.0, 0.02, 2.2, 1.8, 0.01, Color(0.95, 0.65, 0.2), PLAIN, "", false)
		for s in [-0.75, 0.75]:
			fbox(F, u + s, 4.15, 0.02, 0.6, 0.7, 0.01, Color(0.95, 0.65, 0.2), PLAIN, "", false, false, s * 0.6)
			fbox(F, u + s * 0.6, 3.25, 0.028, 0.3, 0.32, 0.01, Color(0.2, 0.8, 0.4), PLAIN, "", false)


## switchback fire escape: a walkway along the wall + two ramp lanes, platforms every floor,
## a drop ladder at the bottom (climb it off a dumpster) and a wall ladder up to the roof
func _fire_escape(F: Dictionary, u0: float, u1: float, floors: int, h: float) -> void:
	var col := C_RUST.lerp(C_METAL, 0.4)
	var lanes := [0.82, 1.4]        # out offsets of ramp lanes A, B (walkway at 0.3)
	var land := 0.85
	var top_lv := floors - 1
	for k in range(1, top_lv + 1):
		var y := CURB + k * FLOOR_H - 0.05
		# walkway along the wall, full length
		fbox(F, (u0 + u1) * 0.5, y, 0.3, u1 - u0, 0.06, 0.56, col, METAL, "metal")
		var at_left := k % 2 == 1                 # level k's landing end
		var lu := u0 + land * 0.5 if at_left else u1 - land * 0.5
		# landing in the arrival lane (ramp k-1) and the departure lane (ramp k)
		fbox(F, lu, y, lanes[0], land, 0.06, 0.58, col, METAL, "metal")
		fbox(F, lu, y, lanes[1], land, 0.06, 0.58, col, METAL, "metal")
		# railings: outer edge + ends (thin tops: cats perch on them)
		fbox(F, (u0 + u1) * 0.5, y + 0.9, 1.72, u1 - u0, 0.04, 0.04, col, METAL, "metal")
		for e in [u0, u1]:
			fbox(F, e, y + 0.9, 1.0, 0.04, 0.04, 1.44, col, METAL, "metal")
		var uu := u0
		while uu <= u1 + 0.01:
			fbox(F, uu, y + 0.45, 1.72, 0.03, 0.9, 0.03, col, METAL, "", false)
			uu += 0.6
		# brackets into the wall
		fbox(F, u0 + 0.3, y - 0.4, 0.8, 0.06, 0.06, 1.6, col, METAL, "", false, false, 0.0)
		fbox(F, u1 - 0.3, y - 0.4, 0.8, 0.06, 0.06, 1.6, col, METAL, "", false, false, 0.0)
		# ramp k up to level k+1 (not from the top level)
		if k < top_lv:
			var lane: float = lanes[k % 2]
			var ua := u0 + land if at_left else u1 - land
			var ub := u1 - land if at_left else u0 + land
			var run := absf(ub - ua)
			var ang := atan2(FLOOR_H, run)
			var tilt := ang if ub > ua else -ang
			fbox(F, (ua + ub) * 0.5, y + FLOOR_H * 0.5, lane, sqrt(run * run + FLOOR_H * FLOOR_H), 0.05, 0.56, col, METAL, "metal", true, false, tilt)
			# ramp handrail
			fbox(F, (ua + ub) * 0.5, y + FLOOR_H * 0.5 + 0.85, lane + 0.3, sqrt(run * run + FLOOR_H * FLOOR_H), 0.04, 0.04, col, METAL, "", false, false, tilt)
		perches.append(fp(F, (u0 + u1) * 0.5, y + 0.93, 1.72))
	# drop ladder under level 1: hangs from 1.35 m (climb it from the dumpster next to it)
	var y1 := CURB + FLOOR_H - 0.05
	var lu1 := u0 + land * 0.5
	fbox(F, lu1, (1.35 + y1) * 0.5, 1.75, 0.55, y1 - 1.35, 0.05, col, METAL, "metal", true, true)
	for k in int((y1 - 1.35) / 0.3):
		fbox(F, lu1, 1.45 + k * 0.3, 1.79, 0.55, 0.03, 0.03, col.lightened(0.1), METAL, "", false)
	# wall ladder from the top platform to the roof (thick enough to clear the cornice)
	var yt := CURB + top_lv * FLOOR_H - 0.05
	var tu := u1 - 0.4 if top_lv % 2 == 1 else u0 + 0.4
	fbox(F, tu, (yt + h + 0.55) * 0.5, 0.2, 0.5, h + 0.55 - yt, 0.4, col, METAL, "metal", true, true)
	for k in int((h + 0.55 - yt) / 0.3):
		fbox(F, tu, yt + 0.15 + k * 0.3, 0.42, 0.5, 0.03, 0.03, col.lightened(0.1), METAL, "", false)


func _roof(r: Rect2, h: float, opts: Dictionary) -> void:
	var x0 := r.position.x + 1.0
	var z0 := r.position.y + 1.0
	var x1 := r.end.x - 1.0
	var z1 := r.end.y - 1.0
	var area := (x1 - x0) * (z1 - z0)
	# ac condensers (step stools on the roof), vent stacks, a hatch hut, skylights
	for k in clampi(int(area / 25.0), 1, 5):
		var p := Vector3(rng.randf_range(x0 + 0.6, x1 - 0.6), h, rng.randf_range(z0 + 0.6, z1 - 0.6))
		box(p + Vector3(0, 0.45, 0), Vector3(1.1, 0.9, 0.9), Color(0.7, 0.7, 0.68), METAL, "metal")
		cyl(p + Vector3(0, 0.9, 0), 0.03, 0.38, Color(0.2, 0.2, 0.2), METAL, "", false, false, 10)
		cyl(p + Vector3(0.8, 0, 0.5), 0.8, 0.07, Color(0.4, 0.4, 0.4), METAL, "metal")
	var hut := Vector3(x0 + 1.2, h, z1 - 1.2)
	box(hut + Vector3(0, 1.1, 0), Vector3(2.0, 2.2, 2.0), Color(0.45, 0.43, 0.42), CONC, "stone")
	box(hut + Vector3(0, 2.25, 0), Vector3(2.2, 0.1, 2.2), Color(0.3, 0.3, 0.3), CONC, "stone")
	glow(hut + Vector3(1.01, 1.8, 0), Vector3(0.02, 0.15, 0.4), Color(1, 0.75, 0.4), 2.0)
	perches.append(hut + Vector3(0.9, 2.32, 0.9))
	if area > 60.0:
		var sk := Vector3((x0 + x1) * 0.5, h, (z0 + z1) * 0.5 - 1.0)
		box(sk + Vector3(0, 0.2, 0), Vector3(1.6, 0.4, 1.2), Color(0.5, 0.5, 0.5), CONC, "stone")
		box(sk + Vector3(0, 0.42, 0), Vector3(1.5, 0.04, 1.1), Color(0.5, 0.6, 0.7), GLASS, "glass")
	if rng.randf() < 0.5:   # satellite dish + antenna
		var a := Vector3(x1 - 0.5, h, z0 + 0.5)
		cyl(a, 3.0, 0.03, C_METAL, METAL, "", false)
		box(a + Vector3(-0.3, 0.6, 0.3), Vector3(0.6, 0.6, 0.05), Color(0.8, 0.8, 0.8), METAL, "", false, false, Basis(Vector3.UP, 0.7) * Basis(Vector3(1, 0, 0), -0.5))
		glow(a + Vector3(0, 3.0, 0), Vector3(0.08, 0.08, 0.08), Color(1, 0.1, 0.1), 5.0)
	if opts.get("garden", false):
		for k in 4:
			var g := Vector3(x0 + 1.0 + k * 1.6, h, z0 + 1.0)
			box(g + Vector3(0, 0.25, 0), Vector3(1.3, 0.5, 0.6), C_WOOD, WOOD, "wood")
			leaves(g + Vector3(0, 0.65, 0), Vector3(1.1, 0.5, 0.5))
		_wire(Vector3(x0, h + 1.8, z0 + 2.5), Vector3(x1, h + 1.8, z0 + 2.5), 0.3, Color(0.8, 0.8, 0.8))
		for k in 5:
			box(Vector3(lerpf(x0, x1, 0.15 + k * 0.17), h + 1.35, z0 + 2.5), Vector3(0.5, 0.7, 0.02), WARM[k % WARM.size()] * 0.6, FABRIC, "", false)
	if opts.get("water", false):
		var t := Vector3(x1 - 2.0, h, z1 - 2.2)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				cyl(t + Vector3(sx * 0.9, 0, sz * 0.9), 2.2, 0.07, C_METAL, METAL, "metal")
		box(t + Vector3(0, 2.25, 0), Vector3(2.6, 0.1, 2.6), C_WOOD, WOOD, "wood")
		cyl(t + Vector3(0, 2.3, 0), 2.6, 1.25, Color(0.42, 0.3, 0.2), WOOD, "wood", true, true, 12)
		cyl(t + Vector3(0, 4.9, 0), 0.7, 1.32, Color(0.25, 0.25, 0.27), METAL, "metal", true, false, 12, Basis.IDENTITY)
		# a climbable ladder up the legs
		box(t + Vector3(1.32, 1.6, 0), Vector3(0.05, 3.2, 0.45), C_METAL, METAL, "metal", true, true)
		perches.append(t + Vector3(0, 5.65, 0))
		labels.append(["water tower", t])
	if opts.has("bill"):
		_billboard(r, h, str(opts.bill), str(opts.get("bill_face", "s")))


func _billboard(r: Rect2, h: float, text: String, f: String) -> void:
	var F := _face(r, f)
	var L: float = F.L
	var w := minf(L - 2.0, 8.0)
	var u := L * 0.5
	var col: Color = NEON[text.length() % NEON.size()]
	# lattice frame on legs (climbable), a catwalk in front, the glowing panel
	for k in [-w * 0.4, 0.0, w * 0.4]:
		fbox(F, u + k, h + 1.6, -1.2, 0.12, 3.2, 0.12, C_METAL, METAL, "metal", true, true)
	fbox(F, u, h + 1.2, -0.7, w, 0.06, 0.7, C_METAL, METAL, "metal")
	fbox(F, u, h + 1.8, -0.36, w, 0.04, 0.04, C_METAL, METAL, "metal")
	fbox(F, u, h + 3.2, -1.1, w + 0.3, 2.9, 0.15, Color(0.06, 0.06, 0.08), METAL, "metal")
	fglow(F, u, h + 3.2, -1.02, w, 2.6, 0.02, col * 0.35, 1.0)
	var l := sign_text(text, fp(F, u, h + 3.2, -0.98), F.o, col, 0.02)
	l.font_size = 96
	light(fp(F, u, h + 2.2, 1.0), Color(col.r, col.g, col.b).clamp(), 1.4, 9.0)
	perches.append(fp(F, u - w * 0.4, h + 4.7, -1.1))
	perches.append(fp(F, u + w * 0.4, h + 4.7, -1.1))


# ================================================================ the four blocks

func _nw() -> void:
	var ramen := Color(0.52, 0.2, 0.17)
	building(Rect2(-21, -21, 12, 12), 10.15, {"s": "shop", "e": "shop", "n": "alley", "w": "blank"},
		{"col": ramen, "names": {"s": "NEKO RAMEN", "e": "SUSHI 24H"}, "name": "neko ramen", "bill": "PURRNET 6G", "bill_face": "e", "shop_col": NEON[0]})
	building(Rect2(-33, -21, 12, 12), 13.45, {"s": "door", "n": "alley", "w": "alley", "e": "blank"},
		{"col": Color(0.4, 0.3, 0.26), "balcony": true, "fire": "n", "name": "apartments", "garden": true})
	building(Rect2(-46, -21, 10, 12), 7.15, {"s": "shop", "e": "alley", "n": "alley"},
		{"col": Color(0.55, 0.5, 0.42), "pat": CONC, "names": {"s": "WASH N FOLD"}, "name": "laundromat", "shop_col": NEON[1], "no_dumpster": true})
	building(Rect2(-46, -46, 10, 21), 10.15, {"e": "alley", "s": "alley"},
		{"col": Color(0.33, 0.28, 0.3), "fire": "e", "name": "warehouse"})
	building(Rect2(-21, -34, 12, 11), 10.15, {"e": "shop", "w": "alley", "s": "alley"},
		{"col": Color(0.45, 0.36, 0.25), "names": {"e": "PAWN"}, "name": "pawn shop", "shop_col": NEON[2], "no_dumpster": ["s"]})
	building(Rect2(-21, -46, 12, 12), 16.75, {"e": "shop", "w": "alley"},
		{"col": Color(0.3, 0.32, 0.36), "pat": CONC, "names": {"e": "CLINIC"}, "fire": "w", "water": true, "name": "the tower"})
	# b's east wall above neko ramen's roof: a pipe up to the apartments roof
	cyl(Vector3(-20.87, 10.15, -11.0), 3.6, 0.065, Color(0.3, 0.3, 0.32), METAL, "metal", true, true, 7)
	# the alley (x -36..-33): dumpsters, crates, a wooden fence with a gap, steam, puddles
	labels.append(["the alley", Vector3(-34.5, 0, -24)])
	_crate_stack(Vector3(-35.3, CURB, -12.5), 3)
	_dumpster(Vector3(-34.0, CURB, -17.0), Vector3(0, 0, 1))
	_fence(Vector3(-36, CURB, -30.0), Vector3(-33, CURB, -30.0), 2.0, true)
	_pallets(Vector3(-35.4, CURB, -36.0))
	_steam(Vector3(-34.2, CURB, -27.0))
	rat_dens.append([Vector3(-34.5, CURB, -24.0), [Vector3(-35.95, CURB, -22.5), Vector3(-34.0, CURB, -17.0), Vector3(-33.05, CURB, -27.5)]])
	# the cut between the laundromat and the warehouse (z -25..-21): a chain-link fence across
	_chainlink(Vector3(-46, CURB, -23.0), Vector3(-36.2, CURB, -23.0), 1.9)
	# back lot (x -33..-21, z -46..-23): loading dock with a crawl space, shed, pallets, fence
	labels.append(["back lot", Vector3(-27, 0, -33)])
	var dock_y := 1.1
	bx(Vector3(-31.0, dock_y - 0.2, -23.0), Vector3(7.0, 0.2, 2.0), Color(0.5, 0.48, 0.45), CONC, "stone")
	for x in [-30.8, -27.5, -24.2]:
		bx(Vector3(x, CURB, -21.6), Vector3(0.25, dock_y - 0.2 - CURB, 0.25), Color(0.4, 0.4, 0.4), CONC, "stone")
	# skirt boards with a gap at the bottom (cats in, people not)
	bx(Vector3(-31.0, 0.45, -23.05), Vector3(7.0, dock_y - 0.65, 0.04), C_WOOD, WOOD, "wood")
	for k in 3:
		bx(Vector3(-31.6 + k * 0.32, CURB, -21.9), Vector3(0.3, 0.06, 0.06), Color(0.3, 0.3, 0.28), CONC, "", false)
	for k in 4:
		bx(Vector3(-33.0 + k * 0.25, CURB, -23.0), Vector3(2.0 - k * 0.25, (k + 1) * 0.24, 1.6), Color(0.45, 0.45, 0.43), CONC, "stone")
	box(Vector3(-27.5, CURB + 1.6, -21.04), Vector3(3.0, 2.6, 0.06), Color(0.42, 0.42, 0.4), METAL, "", false)   # roll-up door
	rat_dens.append([Vector3(-27.5, CURB, -22.4), [Vector3(-29.0, CURB, -22.2), Vector3(-25.0, CURB, -21.8)]])
	_shed(Vector3(-31.0, CURB, -44.0), 0.0)
	_dumpster(Vector3(-24.6, CURB, -26.5), Vector3(1, 0, 0))
	_crate_stack(Vector3(-22.6, CURB, -29.4), 4)
	_pallets(Vector3(-28.0, CURB, -36.5))
	_fence(Vector3(-33, CURB, -38.5), Vector3(-25, CURB, -38.5), 1.8, true)
	_car_wreck(Vector3(-26.5, CURB, -42.5))
	pigeon_spots.append(Vector3(-27.0, CURB, -31.0))


func _ne() -> void:
	building(Rect2(9, -21, 12, 12), 10.15, {"s": "shop", "w": "shop", "n": "alley", "e": "alley"},
		{"col": Color(0.25, 0.32, 0.3), "pat": CONC, "names": {"s": "DELI", "w": "KIBBLE+"}, "name": "the deli", "shop_col": NEON[3]})
	building(Rect2(23, -21, 12, 12), 13.45, {"s": "door", "n": "alley", "w": "alley", "e": "alley"},
		{"col": Color(0.6, 0.38, 0.28), "balcony": true, "fire": "n", "name": "apartments", "no_dumpster": ["w", "e"]})
	building(Rect2(37, -21, 9, 12), 7.15, {"s": "shop", "w": "alley", "n": "alley"},
		{"col": Color(0.2, 0.18, 0.28), "pat": CONC, "names": {"s": "ARCADE"}, "name": "arcade", "shop_col": NEON[4], "bill": "MEOWTEK", "bill_face": "s", "no_dumpster": ["w"]})
	building(Rect2(9, -46, 12, 15), 16.75, {"w": "shop", "s": "alley", "e": "alley"},
		{"col": Color(0.35, 0.25, 0.32), "names": {"w": "HOTEL"}, "fire": "e", "no_dumpster": ["s"], "name": "hotel neko", "water": true, "bill": "SYNTH TUNA", "bill_face": "w", "blade": true, "blade_text": "NEKO"})
	# gangways between the buildings: a wooden gate with a cat sized gap
	_fence(Vector3(21.1, CURB, -9.3), Vector3(22.9, CURB, -9.3), 2.0, true)
	_fence(Vector3(35.1, CURB, -9.3), Vector3(36.9, CURB, -9.3), 2.0, true)
	rat_dens.append([Vector3(22.0, CURB, -15.0), [Vector3(22.0, CURB, -9.4), Vector3(22.0, CURB, -20.5)]])
	# parking lot (x 9..21, z -31..-21) off cross st: carport roof (2.4 m) on posts
	labels.append(["parking lot", Vector3(15, 0, -26)])
	for x in [13.0, 17.0, 21.0]:
		bx(Vector3(x - 0.08, 0.002 + CURB, -30.5), Vector3(0.08, 0.004, 5.0), Color(0.85, 0.85, 0.8), PLAIN, "", false)
	for x in [13.2, 20.8]:
		for z in [-30.4, -25.6]:
			cyl(Vector3(x, CURB, z), 2.3, 0.07, C_METAL, METAL, "metal")
	box(Vector3(17.0, CURB + 2.36, -28.0), Vector3(8.2, 0.08, 5.4), Color(0.45, 0.47, 0.5), METAL, "metal")
	parked.append([Vector3(15.0, CURB, -28.4), PI])
	parked.append([Vector3(19.0, CURB, -28.0), 0.0])
	_dumpster(Vector3(10.5, CURB, -30.0), Vector3(0, 0, 1))
	box(Vector3(10.2, CURB + 1.1, -22.5), Vector3(1.2, 2.2, 1.2), Color(0.8, 0.75, 0.3), METAL, "metal")   # pay booth
	glow(Vector3(10.81, CURB + 1.5, -22.5), Vector3(0.02, 0.6, 0.9), Color(1, 0.9, 0.6), 1.5)
	# backyards (x 23..46, z -46..-23): three yards split by wooden fences
	labels.append(["backyards", Vector3(34, 0, -34)])
	for x in [30.5, 38.0]:
		_fence(Vector3(x, CURB, -45.9), Vector3(x, CURB, -23.1), 1.8, true)
	_fence(Vector3(23.1, CURB, -23.0), Vector3(45.9, CURB, -23.0), 1.6, true)
	for yard in [[23.0, 30.5], [30.5, 38.0], [38.0, 46.0]]:
		var cx: float = (yard[0] + yard[1]) * 0.5
		bx(Vector3(yard[0] + 0.3, CURB, -45.7), Vector3(yard[1] - yard[0] - 0.6, 0.02, 14.0), C_GRASS, GRASS, "grass", true)
	# yard 1: raised porch deck with a crawl space, bbq, kiddie pool
	bx(Vector3(23.6, 0.7, -29.0), Vector3(6.4, 0.1, 5.4), C_WOOD, WOOD, "wood")
	for x in [23.8, 26.8, 29.8]:
		for z in [-28.8, -24.0]:
			bx(Vector3(x, CURB, z), Vector3(0.14, 0.55, 0.14), C_WOOD, WOOD, "wood")
	for k in 4:
		bx(Vector3(27.0, CURB, -29.0 - 0.3 * (4 - k)), Vector3(1.4, (k + 1) * 0.14, 0.3 * (4 - k)), C_WOOD, WOOD, "wood")
	cyl(Vector3(26.0, CURB, -38.0), 0.3, 1.0, Color(0.2, 0.5, 0.8), PLAIN, "plastic", true, false, 14)
	cyl(Vector3(26.0, CURB + 0.02, -38.0), 0.26, 0.92, Color(0.3, 0.55, 0.7), WATER, "", false, false, 14)
	box(Vector3(28.5, CURB + 0.5, -35.5), Vector3(0.6, 1.0, 0.5), Color(0.15, 0.15, 0.15), METAL, "metal")
	_wire(Vector3(23.4, 2.2, -32.0), Vector3(30.2, 2.2, -36.0), 0.25, Color(0.85, 0.85, 0.85))
	for k in 5:
		box(Vector3(lerpf(24.5, 29.0, k / 4.0), 1.75, lerpf(-32.6, -35.4, k / 4.0)), Vector3(0.5, 0.6, 0.02), WARM[k % WARM.size()] * 0.7, FABRIC, "", false, false, Basis(Vector3.UP, -0.53))
	rat_dens.append([Vector3(26.5, CURB, -26.5), [Vector3(25.0, CURB, -23.6), Vector3(28.6, CURB, -23.6)]])
	# yard 2: the treehouse tree (bark trunk, branches, a plank platform at 3 m, rope ladder)
	_tree(Vector3(34.2, CURB, -37.0), 0.32, 5.0, 1.3)
	bx(Vector3(32.7, 3.0, -38.6), Vector3(3.0, 0.1, 3.0), C_WOOD, WOOD, "wood")
	for k in 4:
		bx(Vector3(32.7 + (0.0 if k < 2 else 2.92), 3.1, -38.6 + (0.0 if k % 2 == 0 else 2.92)), Vector3(0.08, 0.9, 0.08), C_WOOD, WOOD, "wood")
	box(Vector3(34.2, 3.55, -38.62), Vector3(3.0, 0.9, 0.05), C_WOOD.darkened(0.1), WOOD, "wood")
	box(Vector3(33.0, 4.6, -37.1), Vector3(0.1, 1.2, 3.1), Color(0.6, 0.2, 0.2), WOOD, "wood", true, false, Basis(Vector3(0, 0, 1), 0.6))
	box(Vector3(35.4, 4.6, -37.1), Vector3(0.1, 1.2, 3.1), Color(0.6, 0.2, 0.2), WOOD, "wood", true, false, Basis(Vector3(0, 0, 1), -0.6))
	box(Vector3(34.3, 1.55, -35.55), Vector3(0.5, 2.9, 0.04), Color(0.65, 0.55, 0.35), PLAIN, "rope", true, true)
	labels.append(["treehouse", Vector3(34.2, 3, -37)])
	_shed(Vector3(36.0, CURB, -44.0), PI * 0.5)
	# yard 3: garden beds, a trampoline frame, wheelbarrow, a cat flap door on the arcade
	for k in 3:
		bx(Vector3(39.5 + k * 2.0, CURB, -40.0), Vector3(1.4, 0.35, 3.0), C_WOOD, WOOD, "wood")
		for j in 3:
			leaves(Vector3(40.2 + k * 2.0, CURB + 0.5, -39.4 + j * 1.0), Vector3(0.5, 0.4, 0.5), [Color(0.3, 0.5, 0.2), Color(0.7, 0.3, 0.2), C_LEAF][j])
	cyl(Vector3(42.0, CURB + 0.6, -30.0), 0.06, 1.6, Color(0.1, 0.1, 0.12), PLAIN, "fabric", true, false, 16)
	for a in 6:
		cyl(Vector3(42.0 + cos(a * TAU / 6) * 1.5, CURB, -30.0 + sin(a * TAU / 6) * 1.5), 0.62, 0.04, C_METAL, METAL, "", false)
	sparrow_spots.append(Vector3(41.0, CURB, -36.0))
	sparrow_spots.append(Vector3(27.0, CURB, -41.0))


func _sw() -> void:
	building(Rect2(-21, 9, 12, 12), 7.15, {"n": "shop", "e": "shop", "s": "alley", "w": "alley"},
		{"col": Color(0.6, 0.55, 0.45), "pat": CONC, "names": {"n": "BODEGA", "e": "LOTTO"}, "name": "bodega", "shop_col": NEON[5], "garden": true})
	building(Rect2(-35, 9, 12, 12), 10.15, {"n": "shop", "s": "alley", "e": "alley", "w": "alley"},
		{"col": Color(0.42, 0.22, 0.2), "names": {"n": "NOODLE BAR"}, "fire": "s", "name": "noodle bar", "shop_col": NEON[2], "no_dumpster": ["e"]})
	building(Rect2(-46, 9, 9, 12), 13.45, {"n": "shop", "e": "alley", "s": "alley"},
		{"col": Color(0.25, 0.22, 0.3), "names": {"n": "LOBBY"}, "name": "hotel", "blade": true, "blade_text": "HOTEL", "shop_col": NEON[4], "water": true, "no_dumpster": ["e"]})
	_fence(Vector3(-22.9, CURB, 9.3), Vector3(-21.1, CURB, 9.3), 2.0, true)
	_fence(Vector3(-36.9, CURB, 9.3), Vector3(-35.1, CURB, 9.3), 2.0, true)
	rat_dens.append([Vector3(-36.0, CURB, 15.0), [Vector3(-36.0, CURB, 9.4), Vector3(-36.0, CURB, 20.6)]])
	# construction site (x -46..-24, z 23..46): unfinished concrete frame + scaffold + piles
	labels.append(["construction site", Vector3(-35, 0, 34)])
	_chainlink(Vector3(-46, CURB, 23.0), Vector3(-30.0, CURB, 23.0), 2.0)
	_chainlink(Vector3(-28.4, CURB, 23.0), Vector3(-24.0, CURB, 23.0), 2.0)   # gap at -30..-28.4
	_chainlink(Vector3(-24.0, CURB, 23.0), Vector3(-24.0, CURB, 46.0), 2.0)
	var fx0 := -44.0
	var fx1 := -32.0
	var fz0 := 30.0
	var fz1 := 44.0
	for lv in [1, 2]:
		var y: float = CURB + lv * FLOOR_H
		bx(Vector3(fx0, y - 0.25, fz0), Vector3(fx1 - fx0, 0.25, fz1 - fz0), Color(0.55, 0.54, 0.52), CONC, "stone")
		# rebar sticking up at the open edge on the top floor
		if lv == 2:
			for k in 10:
				cyl(Vector3(fx0 + 0.3 + k * 1.3, y, fz0 + 0.2), 0.7, 0.012, C_RUST, METAL, "", false, false, 4)
	for x in [fx0 + 0.2, (fx0 + fx1) * 0.5, fx1 - 0.6]:
		for z in [fz0 + 0.2, (fz0 + fz1) * 0.5, fz1 - 0.6]:
			bx(Vector3(x, CURB, z), Vector3(0.4, 2.0 * FLOOR_H - 0.25, 0.4), Color(0.5, 0.5, 0.48), CONC, "stone")
	# concrete ramps (stairs) up through the floors
	var r1 := atan2(FLOOR_H, 6.0)
	box(Vector3(-41.0, CURB + FLOOR_H * 0.5, 41.0), Vector3(6.9, 0.2, 1.4), Color(0.5, 0.5, 0.48), CONC, "stone", true, false, Basis(Vector3(0, 0, 1), -r1))
	box(Vector3(-41.0, CURB + FLOOR_H * 1.5, 38.6), Vector3(6.9, 0.2, 1.4), Color(0.5, 0.5, 0.48), CONC, "stone", true, false, Basis(Vector3(0, 0, 1), r1))
	# scaffold tower against the frame: planks every 1.7 m, ladders (climbable)
	for lv in 4:
		var y := CURB + 1.7 * (lv + 1)
		bx(Vector3(-31.6, y, 30.5), Vector3(1.6, 0.06, 8.0), Color(0.6, 0.48, 0.3), WOOD, "wood")
	for x in [-31.6, -30.0]:
		for z in [30.5, 34.5, 38.5]:
			cyl(Vector3(x, CURB, z), 7.0, 0.035, Color(0.7, 0.7, 0.7), METAL, "metal", true, true)
	for k in 4:
		box(Vector3(-29.95, CURB + 0.85 + k * 1.7, 31.2 + (k % 2) * 6.0), Vector3(0.06, 1.7, 0.45), Color(0.7, 0.7, 0.7), METAL, "metal", true, true)
	for k in 8:
		box(Vector3(-30.8, CURB + 1.0 + k * 0.85, 34.5), Vector3(1.6, 0.03, 8.0), Color(0.7, 0.7, 0.7), METAL, "", false, false, Basis(Vector3(1, 0, 0), 0.0))
	# piles: pipes, brick pallets, a sand heap, a porta potty, cones, a cement mixer
	for k in 5:
		cyl(Vector3(-38.0, CURB + 0.15 + (k % 3) * 0.28 + (0.0 if k < 3 else 0.14), 26.0 + (k % 3) * 0.32 + (0.16 if k >= 3 else 0.0)), 4.0, 0.15, Color(0.45, 0.45, 0.48), METAL, "metal", true, false, 8, Basis(Vector3(0, 0, 1), PI * 0.5))
	for k in 3:
		bx(Vector3(-44.5 + k * 1.3, CURB, 25.0), Vector3(1.1, 0.12, 1.1), C_WOOD, WOOD, "wood")
		bx(Vector3(-44.4 + k * 1.3, CURB + 0.12, 25.1), Vector3(0.9, 0.5 + k * 0.25, 0.9), Color(0.55, 0.25, 0.18), BRICK, "stone")
	box(Vector3(-27.0, CURB + 0.4, 42.0), Vector3(3.2, 0.9, 3.2), Color(0.75, 0.65, 0.45), CONC, "dirt", true, false, Basis(Vector3.UP, 0.4) * Basis(Vector3(1, 0, 0), 0.25))
	box(Vector3(-26.0, CURB + 1.15, 27.0), Vector3(1.2, 2.3, 1.2), Color(0.2, 0.45, 0.75), PLAIN, "plastic")
	box(Vector3(-26.0, CURB + 2.35, 27.0), Vector3(1.3, 0.1, 1.3), Color(0.9, 0.9, 0.9), PLAIN, "plastic")
	for k in 6:
		_cone(Vector3(-28.0 + k * 0.7, CURB, 24.0))
	cyl(Vector3(-36.0, CURB + 0.7, 27.5), 1.0, 0.55, Color(0.85, 0.45, 0.1), METAL, "metal", true, false, 10, Basis(Vector3(1, 0, 0), 0.6))
	box(Vector3(-36.0, CURB + 0.35, 27.5), Vector3(1.2, 0.7, 0.8), C_METAL, METAL, "metal")
	sign_text("KEEP OUT", Vector3(-35.0, 1.5, 22.94), Vector3(0, 0, -1), Color(1.0, 0.85, 0.2), 0.01)
	light(Vector3(-38.0, 4.2, 37.0), Color(1.0, 0.85, 0.6), 1.2, 9.0)
	glow(Vector3(-38.0, CURB + FLOOR_H - 0.32, 37.0), Vector3(0.3, 0.08, 0.3), Color(1, 0.9, 0.7), 4.0)
	rat_dens.append([Vector3(-37.0, CURB, 33.0), [Vector3(-38.0, CURB, 26.2), Vector3(-44.0, CURB, 25.5), Vector3(-30.8, CURB, 41.0)]])
	pigeon_spots.append(Vector3(-40.0, CURB + 2.0 * FLOOR_H, 36.0))
	# the plaza (x -21..-9, z 21..34) + cat cafe
	labels.append(["the plaza", Vector3(-15, 0, 28)])
	bx(Vector3(-21.0, CURB, 21.0), Vector3(12.0, 0.01, 15.0), Color(0.5, 0.45, 0.42), TILE, "tile")
	building(Rect2(-22, 36, 13, 10), 7.15, {"n": "shop", "e": "shop", "w": "alley"},
		{"col": Color(0.85, 0.75, 0.6), "pat": CONC, "names": {"n": "CAT CAFE", "e": "CAFE"}, "name": "cat cafe", "shop_col": NEON[0], "garden": true, "awning": Color(0.8, 0.45, 0.55)})
	_food_truck(Vector3(-13.0, CURB, 26.0))
	for p in [Vector3(-18.0, CURB, 30.0), Vector3(-18.0, CURB, 25.5)]:
		_picnic(p)
	# string lights across the plaza (perches) on two poles
	_pole(Vector3(-20.5, 4.0, 22.0))
	_pole(Vector3(-20.5, 4.0, 34.0))
	_wire(Vector3(-20.5, 4.3, 22.0), Vector3(-9.6, 3.6, 34.0), 0.5, Color(0.05, 0.05, 0.05), true)
	_wire(Vector3(-20.5, 4.3, 34.0), Vector3(-9.6, 3.6, 22.0), 0.5, Color(0.05, 0.05, 0.05), true)
	light(Vector3(-15, 3.2, 28), Color(1.0, 0.75, 0.45), 1.2, 9.0)
	pigeon_spots.append(Vector3(-15.0, CURB, 31.0))
	pigeon_spots.append(Vector3(-28.0, CURB, 6.8))


# ---------------------------------------------------------------- the park (se)

func _park() -> void:
	var x0 := WALK + 0.5
	var z0 := WALK + 0.5
	labels.append(["the park", Vector3(28, 0, 26)])
	# grass on top of the block slab (2 cm up), gravel paths
	bx(Vector3(x0, CURB, z0), Vector3(HALF - x0, 0.02, HALF - z0), C_GRASS, GRASS, "grass")
	var gravel := Color(0.6, 0.55, 0.47)
	bx(Vector3(x0, CURB + 0.02, 12.0), Vector3(HALF - x0, 0.012, 2.2), gravel, CONC, "dirt")
	bx(Vector3(12.0, CURB + 0.02, z0), Vector3(2.2, 0.012, HALF - z0), gravel, CONC, "dirt")
	bx(Vector3(12.0, CURB + 0.02, 24.5), Vector3(32.0, 0.012, 2.0), gravel, CONC, "dirt")
	bx(Vector3(26.0, CURB + 0.02, z0), Vector3(2.0, 0.012, 34.0), gravel, CONC, "dirt")
	# iron fence along both street sides with brick piers, gates at the corner + mid paths
	_iron_fence(Vector3(x0 - 0.3, CURB, 14.6), Vector3(x0 - 0.3, CURB, 45.8))
	_iron_fence(Vector3(14.6, CURB, z0 - 0.3), Vector3(25.6, CURB, z0 - 0.3))
	_iron_fence(Vector3(28.4, CURB, z0 - 0.3), Vector3(45.8, CURB, z0 - 0.3))
	for p in [Vector3(x0 - 0.3, CURB, 14.6), Vector3(14.6, CURB, z0 - 0.3)]:
		box(p + Vector3(0, 0.7, 0), Vector3(0.5, 1.4, 0.5), Color(0.5, 0.25, 0.2), BRICK, "stone")
		glow(p + Vector3(0, 1.5, 0), Vector3(0.25, 0.2, 0.25), Color(1, 0.85, 0.6), 3.0)
	# back wall + hedge on the map edges
	bx(Vector3(x0, CURB, HALF - 0.5), Vector3(HALF - x0, 2.6, 0.5), Color(0.45, 0.25, 0.2), BRICK, "stone")
	bx(Vector3(HALF - 0.5, CURB, z0), Vector3(0.5, 2.6, HALF - z0), Color(0.45, 0.25, 0.2), BRICK, "stone")
	for k in 12:
		leaves(Vector3(x0 + 2.0 + k * 3.0, CURB + 1.0, HALF - 1.3), Vector3(2.8, 1.8, 1.4))
		box(Vector3(x0 + 2.0 + k * 3.0, CURB + 0.7, HALF - 1.3), Vector3(2.6, 1.4, 1.1), C_LEAF, LEAF, "fabric", true, false)
	# big trees: bark trunks (climb), a couple of thick limbs to sit on, canopies
	for t in [[Vector3(17.0, CURB, 17.0), 0.34, 5.2], [Vector3(34.0, CURB, 15.5), 0.3, 4.6], [Vector3(41.0, CURB, 26.0), 0.36, 5.6],
			[Vector3(20.0, CURB, 40.0), 0.3, 4.8], [Vector3(38.0, CURB, 41.0), 0.32, 5.0], [Vector3(15.5, CURB, 29.0), 0.26, 4.2], [Vector3(31.5, CURB, 21.0), 0.24, 4.0]]:
		_tree(t[0], t[1], t[2], 1.0 + t[1])
	# benches along the paths
	for b in [[Vector3(20.0, CURB, 14.2), Vector3(1, 0, 0)], [Vector3(30.0, CURB, 14.2), Vector3(1, 0, 0)], [Vector3(14.6, CURB, 20.0), Vector3(0, 0, 1)],
			[Vector3(28.6, CURB, 31.0), Vector3(0, 0, 1)], [Vector3(36.0, CURB, 23.0), Vector3(1, 0, 0)], [Vector3(14.6, CURB, 36.0), Vector3(0, 0, 1)]]:
		_bench(b[0], b[1])
	# park lamps
	for p in [Vector3(13.6, CURB, 13.6), Vector3(25.0, CURB, 13.6), Vector3(13.6, CURB, 26.0), Vector3(27.6, CURB, 26.0), Vector3(39.0, CURB, 13.6), Vector3(27.6, CURB, 38.0)]:
		cyl(p, 3.2, 0.06, Color(0.12, 0.14, 0.12), METAL, "metal")
		box(p + Vector3(0, 3.3, 0), Vector3(0.32, 0.32, 0.32), Color(0.12, 0.14, 0.12), METAL, "metal")
		glow(p + Vector3(0, 3.28, 0), Vector3(0.26, 0.24, 0.26), Color(1.0, 0.85, 0.6), 3.0)
		light(p + Vector3(0, 3.0, 0), Color(1.0, 0.82, 0.55), 1.3, 8.0)
		perches.append(p + Vector3(0, 3.5, 0))
	# raised pond with a stone rim + fountain (a cat statue on a plinth), stepping stones
	labels.append(["the pond", Vector3(33, 0, 33)])
	var pc := Vector3(34.0, CURB + 0.02, 33.0)
	var pr := 4.8
	var segs := 20
	for i in segs:
		var a := TAU * i / segs
		var p := pc + Vector3(cos(a) * pr, 0, sin(a) * pr)
		box(p + Vector3(0, 0.2, 0), Vector3(0.5, 0.42, pr * TAU / segs + 0.12), Color(0.55, 0.53, 0.5), CONC, "stone", true, false, Basis(Vector3.UP, -a))
	cyl(pc, 0.12, pr - 0.1, Color(0.1, 0.25, 0.3), WATER, "", false, false, segs)
	cyl(pc, 0.9, 0.7, Color(0.5, 0.48, 0.46), CONC, "stone", true, false, 10)
	box(pc + Vector3(0, 1.05, 0), Vector3(0.35, 0.3, 0.6), Color(0.35, 0.45, 0.4), PLAIN, "stone")
	box(pc + Vector3(0, 1.3, -0.25), Vector3(0.24, 0.3, 0.2), Color(0.35, 0.45, 0.4), PLAIN, "stone")
	box(pc + Vector3(-0.07, 1.5, -0.25), Vector3(0.06, 0.1, 0.06), Color(0.35, 0.45, 0.4), PLAIN, "stone", false)
	box(pc + Vector3(0.07, 1.5, -0.25), Vector3(0.06, 0.1, 0.06), Color(0.35, 0.45, 0.4), PLAIN, "stone", false)
	box(pc + Vector3(0, 1.1, 0.4), Vector3(0.06, 0.06, 0.4), Color(0.35, 0.45, 0.4), PLAIN, "stone", false, false, Basis(Vector3(1, 0, 0), -0.8))
	_fountain(pc + Vector3(0, 1.4, -0.4))
	for k in 5:
		cyl(pc + Vector3(-pr + 0.9 + k * 0.85, 0, 1.8 + sin(k * 1.3) * 0.4), 0.33, 0.28, Color(0.5, 0.5, 0.48), CONC, "stone", true, false, 7)
	for k in 6:
		cyl(pc + Vector3(cos(k * 1.1) * 2.6, 0.31, sin(k * 1.1) * 2.6), 0.01, 0.25, Color(0.2, 0.5, 0.2), LEAF, "", false, false, 7)
	sparrow_spots.append(Vector3(30.0, CURB, 28.0))
	sparrow_spots.append(Vector3(20.0, CURB, 22.0))
	pigeon_spots.append(Vector3(26.5, CURB, 18.0))
	perches.append(pc + Vector3(0, 1.48, 0))
	# playground (x 12..24, z 30..44): sand, slide, swings, climbing frame, seesaw, spring rider
	labels.append(["playground", Vector3(18, 0, 37)])
	bx(Vector3(14.6, CURB + 0.02, 31.0), Vector3(9.4, 0.02, 7.5), Color(0.78, 0.68, 0.48), CONC, "dirt")
	_playground(Vector3(14.6, CURB + 0.04, 31.0))
	# gazebo (bandstand): floor raised on posts with a crawl gap under, eight posts, a roof
	labels.append(["gazebo", Vector3(40, 0, 18)])
	_gazebo(Vector3(40.0, CURB, 17.5))
	# restroom kiosk + drinking fountain + bins + picnic tables
	building(Rect2(41.0, 34.0, 4.6, 5.0), 3.0, {"w": "alley"}, {"col": Color(0.7, 0.68, 0.6), "pat": BRICK, "no_dumpster": true})
	cyl(Vector3(29.0, CURB, 24.2), 0.9, 0.15, Color(0.4, 0.4, 0.42), METAL, "metal", true, false, 8)
	_picnic(Vector3(22.0, CURB, 19.0))
	_picnic(Vector3(20.0, CURB, 27.6))
	for p in [Vector3(25.0, CURB, 15.0), Vector3(13.2, CURB, 23.0), Vector3(29.5, CURB, 37.0)]:
		cyl(p, 0.95, 0.27, Color(0.15, 0.3, 0.18), METAL, "metal", true, false, 10)
	# flower beds
	for p in [Vector3(20.0, CURB, 25.5), Vector3(32.0, CURB, 25.5)]:
		box(p + Vector3(0, 0.2, 0.0), Vector3(3.0, 0.4, 1.0), Color(0.5, 0.45, 0.4), BRICK, "stone")
		for k in 5:
			leaves(p + Vector3(-1.2 + k * 0.6, 0.55, 0), Vector3(0.45, 0.35, 0.45), [Color(0.8, 0.2, 0.3), Color(0.9, 0.75, 0.2), Color(0.55, 0.3, 0.8)][k % 3])
	rat_dens.append([Vector3(40.5, CURB, 31.5), [Vector3(41.0, CURB, 36.5), Vector3(40.0, CURB, 17.5)]])


func _tree(p: Vector3, r: float, h: float, spread: float) -> void:
	cyl(p, h, r, C_BARK, PLAIN, "bark", true, true, 8)
	trunks.append([p, r, h])
	blockers.append([Vector2(p.x, p.z), r + 0.1])
	# roots
	for k in 4:
		var a := k * PI * 0.5 + 0.4
		box(p + Vector3(cos(a) * r, 0.08, sin(a) * r), Vector3(r * 1.6, 0.16, 0.18), C_BARK, PLAIN, "", false, false, Basis(Vector3.UP, -a))
	# two or three thick limbs (standable, bark) at 2.4-3.6 m
	for k in 3:
		var a := rng.randf() * TAU
		var y := h * (0.5 + 0.13 * k)
		var len := spread * (1.6 - k * 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		var c := p + Vector3(0, y, 0) + d * (len * 0.5 + r * 0.6)
		var b := Basis(Vector3.UP, -a) * Basis(Vector3(0, 0, 1), 0.18)
		box(c, Vector3(len, 0.16, 0.18), C_BARK, PLAIN, "bark", true, true, b)
		perches.append(p + Vector3(0, y + 0.25 + len * 0.18, 0) + d * (len + r * 0.6 - 0.1))
		leaves(p + Vector3(0, y + 0.7, 0) + d * len, Vector3(1.8, 1.2, 1.8))
	leaves(p + Vector3(0, h + 0.4, 0), Vector3(spread * 3.6, 2.4, spread * 3.6))
	leaves(p + Vector3(0.8, h - 0.6, -0.5), Vector3(spread * 2.6, 1.8, spread * 2.6))
	leaves(p + Vector3(-0.9, h - 0.4, 0.7), Vector3(spread * 2.4, 1.6, spread * 2.4))


func _fountain(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = 40
	p.lifetime = 0.9
	p.direction = Vector3(0, 0.6, 1)
	p.spread = 6.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 1.9
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var qm := SphereMesh.new()
	qm.radius = 0.02
	qm.height = 0.04
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.85, 1.0, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.3, 0.45, 0.6)
	qm.material = m
	p.mesh = qm
	add_child(p)


func _playground(o: Vector3) -> void:
	var red := Color(0.8, 0.2, 0.15)
	var blue := Color(0.15, 0.35, 0.75)
	var yel := Color(0.9, 0.75, 0.15)
	# slide: ladder (climb) up to a 1.6 m deck, a slide back down
	var s := o + Vector3(1.5, 0, 1.5)
	for x in [0.0, 1.0]:
		for z in [0.0, 1.0]:
			cyl(s + Vector3(x, 0, z), 2.6, 0.05, blue, METAL, "metal")
	bx(s + Vector3(-0.05, 1.55, -0.05), Vector3(1.1, 0.08, 1.1), yel, PLAIN, "plastic")
	box(s + Vector3(0.5, 2.62, 0.5), Vector3(1.3, 0.08, 1.3), red, PLAIN, "plastic", true, false, Basis())
	box(s + Vector3(0.5, 0.8, -0.1), Vector3(0.55, 1.6, 0.05), blue, METAL, "metal", true, true)
	var ang := atan2(1.55, 2.6)
	box(s + Vector3(0.5, 0.82, 2.4), Vector3(0.6, 0.05, sqrt(1.55 * 1.55 + 2.6 * 2.6)), Color(0.75, 0.75, 0.8), METAL, "metal", true, false, Basis(Vector3(1, 0, 0), ang))
	for side in [0.2, 0.8]:
		box(s + Vector3(side, 0.95, 2.4), Vector3(0.04, 0.18, sqrt(1.55 * 1.55 + 2.6 * 2.6)), yel, PLAIN, "", false, false, Basis(Vector3(1, 0, 0), ang))
	# swings: an a-frame (posts climbable) with a 2.2 m top bar to walk + seats on chains
	var w := o + Vector3(5.0, 0, 1.0)
	for x in [0.0, 3.2]:
		for zz in [-0.5, 0.5]:
			box(w + Vector3(x, 1.1, zz * 0.6), Vector3(0.08, 2.3, 0.08), red, METAL, "metal", true, true, Basis(Vector3(1, 0, 0), zz * 0.45))
	box(w + Vector3(1.6, 2.2, 0), Vector3(3.3, 0.1, 0.1), red, METAL, "metal")
	for k in 2:
		var sx := 0.9 + k * 1.4
		box(w + Vector3(sx, 0.45, 0), Vector3(0.45, 0.05, 0.2), Color(0.1, 0.1, 0.1), PLAIN, "plastic")
		for c in [-0.2, 0.2]:
			box(w + Vector3(sx + c, 1.33, 0), Vector3(0.015, 1.75, 0.015), Color(0.6, 0.6, 0.6), PLAIN, "", false)
	# climbing frame: a grid of bars, posts climbable, bars standable
	var g := o + Vector3(1.0, 0, 5.0)
	for x in 4:
		for z in 3:
			cyl(g + Vector3(x * 0.7, 0, z * 0.7), 2.1, 0.03, yel, METAL, "metal", true, true)
	for lv in 3:
		var y := 0.6 + lv * 0.7
		for z in 3:
			box(g + Vector3(1.05, y, z * 0.7), Vector3(2.15, 0.04, 0.04), blue, METAL, "metal")
		for x in 4:
			box(g + Vector3(x * 0.7, y, 0.7), Vector3(0.04, 0.04, 1.45), blue, METAL, "metal")
	# seesaw + spring rider + a little playhouse with a roof
	box(o + Vector3(6.5, 0.5, 5.5), Vector3(3.0, 0.08, 0.3), red, WOOD, "wood", true, false, Basis(Vector3(0, 0, 1), 0.22))
	box(o + Vector3(6.5, 0.22, 5.5), Vector3(0.2, 0.44, 0.3), C_METAL, METAL, "metal")
	cyl(o + Vector3(8.4, 0, 3.5), 0.4, 0.06, Color(0.5, 0.5, 0.5), METAL, "metal")
	box(o + Vector3(8.4, 0.62, 3.5), Vector3(0.25, 0.4, 0.6), yel, PLAIN, "plastic")
	bx(o + Vector3(4.0, 0, 5.0), Vector3(1.6, 1.4, 1.6), Color(0.8, 0.6, 0.4), WOOD, "wood")
	box(o + Vector3(4.8, 1.6, 5.8), Vector3(1.9, 0.08, 1.9), red, WOOD, "wood", true, false, Basis(Vector3(1, 0, 0), 0.12))
	perches.append(o + Vector3(6.6, 2.3, 1.0))


func _gazebo(c: Vector3) -> void:
	var r := 3.0
	var fy := 0.55
	var col := Color(0.88, 0.86, 0.8)
	# octagon floor on short posts: a 35 cm crawl gap under (skirt with an opening)
	for i in 8:
		var a := TAU * i / 8.0
		var p := c + Vector3(cos(a) * r * 0.5, 0, sin(a) * r * 0.5)
		box(p + Vector3(0, fy, 0), Vector3(r * 1.0, 0.1, r * 0.83), col.darkened(0.2), WOOD, "wood", true, false, Basis(Vector3.UP, -a))
		var q := c + Vector3(cos(a) * r, 0, sin(a) * r)
		bx(q + Vector3(-0.07, CURB, -0.07), Vector3(0.14, fy - CURB, 0.14), col, WOOD, "wood")
		if i != 2:
			box(c + Vector3(cos(a + PI / 8) * r * 0.93, 0.32, sin(a + PI / 8) * r * 0.93), Vector3(0.03, 0.28, r * 0.76), col, WOOD, "wood", true, false, Basis(Vector3.UP, -a - PI / 8))
		# posts up to the roof (climbable) + a rail between
		cyl(q + Vector3(0, fy, 0), 2.6, 0.07, col, WOOD, "wood", true, true, 6)
		if i != 6:
			box(c + Vector3(cos(a + PI / 8) * r * 0.93, fy + 0.9, sin(a + PI / 8) * r * 0.93), Vector3(0.06, 0.06, r * 0.76), col, WOOD, "wood", true, false, Basis(Vector3.UP, -a - PI / 8))
		# roof: eight sloped panels
		box(c + Vector3(cos(a + PI / 8) * r * 0.55, fy + 3.05, sin(a + PI / 8) * r * 0.55), Vector3(r * 1.0, 0.08, r * 0.95), Color(0.3, 0.42, 0.35), WOOD, "wood", true, false, Basis(Vector3.UP, -a - PI / 8) * Basis(Vector3(0, 0, 1), 0.38))
	# steps up on the open side
	for k in 2:
		box(c + Vector3(0.0, CURB + 0.1 + k * 0.17, -r - 0.55 + k * 0.3), Vector3(1.3, 0.2, 0.4), col.darkened(0.25), WOOD, "wood")
	light(c + Vector3(0, fy + 2.4, 0), Color(1.0, 0.8, 0.5), 1.0, 6.0)
	glow(c + Vector3(0, fy + 2.5, 0), Vector3(0.18, 0.18, 0.18), Color(1, 0.85, 0.6), 4.0)
	perches.append(c + Vector3(0, fy + 3.7, 0))
	rat_dens.append([c + Vector3(r + 1.0, CURB, 0), [c + Vector3(0, CURB, 0)]])


# ---------------------------------------------------------------- props

func _crate_stack(p: Vector3, n: int) -> void:
	var y := p.y
	for k in n:
		var s := 0.6 - k * 0.04
		var off := Vector3(((k * 37) % 5 - 2) * 0.05, 0, ((k * 53) % 5 - 2) * 0.05)
		box(Vector3(p.x, y + s * 0.5, p.z) + off, Vector3(s, s, s), Color(0.58, 0.44, 0.27).darkened(k * 0.05), WOOD, "wood", true, false, Basis(Vector3.UP, k * 0.3))
		y += s
	perches.append(Vector3(p.x, y + 0.05, p.z))


func _pallets(p: Vector3) -> void:
	for k in 5:
		box(p + Vector3(0, 0.07 + k * 0.15, 0), Vector3(1.2, 0.13, 1.0), Color(0.6, 0.5, 0.35).darkened(k * 0.03), WOOD, "wood", true, false, Basis(Vector3.UP, k * 0.05))


func _steam(p: Vector3) -> void:
	box(p + Vector3(0, 0.006, 0), Vector3(0.6, 0.012, 0.6), Color(0.12, 0.12, 0.13), METAL, "", false)
	var s := CPUParticles3D.new()
	s.position = p + Vector3(0, 0.05, 0)
	s.amount = 16
	s.lifetime = 2.8
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	s.emission_box_extents = Vector3(0.25, 0.01, 0.25)
	s.direction = Vector3.UP
	s.spread = 15.0
	s.initial_velocity_min = 0.4
	s.initial_velocity_max = 0.7
	s.gravity = Vector3(0.05, 0.1, 0)
	s.scale_amount_min = 1.0
	s.scale_amount_max = 2.6
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.8, 0.9, 0.12)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	s.mesh = q
	add_child(s)


## wooden fence a->b, height h, posts + boards. climbable (wood), top rail standable.
## gap = a cat sized hole at the bottom in the middle
func _fence(a: Vector3, b: Vector3, h: float, gap := false) -> void:
	var d := b - a
	var len := d.length()
	var dir := d / len
	var ry := atan2(-dir.z, dir.x)
	var basis := Basis(Vector3.UP, ry)
	var mid := (a + b) * 0.5
	if gap:
		var g := 0.36
		var l1 := len * 0.5 - g * 0.5
		box(a + dir * l1 * 0.5 + Vector3(0, h * 0.5, 0), Vector3(l1, h, 0.05), C_WOOD, WOOD, "wood", true, true, basis)
		box(b - dir * l1 * 0.5 + Vector3(0, h * 0.5, 0), Vector3(l1, h, 0.05), C_WOOD, WOOD, "wood", true, true, basis)
		box(mid + Vector3(0, (h + 0.3) * 0.5, 0), Vector3(g, h - 0.3, 0.05), C_WOOD, WOOD, "wood", true, true, basis)
	else:
		box(mid + Vector3(0, h * 0.5, 0), Vector3(len, h, 0.05), C_WOOD, WOOD, "wood", true, true, basis)
	box(mid + Vector3(0, h + 0.03, 0), Vector3(len, 0.06, 0.12), C_WOOD.darkened(0.15), WOOD, "wood", true, false, basis)
	var n := int(len / 2.0)
	for k in n + 1:
		var p := a + dir * (len * k / maxf(n, 1))
		box(p + Vector3(0, h * 0.5 + 0.05, 0), Vector3(0.1, h + 0.1, 0.1), C_WOOD.darkened(0.2), WOOD, "wood", true, true, basis)
	perches.append(mid + Vector3(0, h + 0.08, 0))


func _chainlink(a: Vector3, b: Vector3, h: float) -> void:
	var d := b - a
	var len := d.length()
	var dir := d / len
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	box((a + b) * 0.5 + Vector3(0, h * 0.5, 0), Vector3(len, h, 0.03), Color(0.55, 0.57, 0.6), METAL, "metal", true, true, basis)
	box((a + b) * 0.5 + Vector3(0, h, 0), Vector3(len, 0.05, 0.05), Color(0.6, 0.6, 0.62), METAL, "metal", true, false, basis)
	for k in int(len / 2.5) + 1:
		cyl(a + dir * minf(k * 2.5, len), h + 0.05, 0.03, Color(0.6, 0.6, 0.62), METAL, "metal")


func _iron_fence(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	var dir := d / len
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	var col := Color(0.08, 0.09, 0.08)
	box((a + b) * 0.5 + Vector3(0, 0.9, 0), Vector3(len, 0.05, 0.05), col, METAL, "metal", true, false, basis)
	box((a + b) * 0.5 + Vector3(0, 0.2, 0), Vector3(len, 0.04, 0.04), col, METAL, "", false, false, basis)
	# pickets: visual; one collider panel (cats hop it, 0.92 m)
	var n := int(len / 0.14)
	for k in n:
		var p := a + dir * (k * 0.14 + 0.07)
		box(p + Vector3(0, 0.47, 0), Vector3(0.02, 0.92, 0.02), col, PLAIN, "", false)
	var sb := BoxShape3D.new()
	sb.size = Vector3(len, 0.9, 0.04)
	_shape(Transform3D(basis, (a + b) * 0.5 + Vector3(0, 0.45, 0)), sb, "metal", false)


func _shed(p: Vector3, ry: float) -> void:
	var b := Basis(Vector3.UP, ry)
	box(p + Vector3(0, 1.1, 0), Vector3(3.0, 2.2, 2.4), Color(0.4, 0.45, 0.35), WOOD, "wood", true, false, b)
	box(p + Vector3(0, 2.3, 0), Vector3(3.3, 0.08, 2.8), Color(0.25, 0.25, 0.27), METAL, "metal", true, false, b * Basis(Vector3(1, 0, 0), 0.1))
	box(p + b * Vector3(0, 1.0, 1.22), Vector3(1.0, 1.9, 0.04), Color(0.3, 0.33, 0.25), WOOD, "", false, false, b)
	# a barrel to climb on (0.9) next to it
	cyl(p + b * Vector3(1.9, 0, 0.8), 0.9, 0.3, Color(0.25, 0.35, 0.5), METAL, "metal", true, false, 10)
	perches.append(p + Vector3(0, 2.4, 0))


func _car_wreck(p: Vector3) -> void:
	# an old car on blocks, no wheels: crawl under, sit on the roof
	for x in [-1.3, 1.3]:
		for z in [-0.6, 0.6]:
			box(p + Vector3(x, 0.15, z), Vector3(0.3, 0.3, 0.3), Color(0.5, 0.5, 0.48), CONC, "stone")
	box(p + Vector3(0, 0.6, 0), Vector3(3.8, 0.55, 1.7), Color(0.45, 0.2, 0.15), METAL, "metal")
	box(p + Vector3(0.2, 1.12, 0), Vector3(2.0, 0.5, 1.5), Color(0.42, 0.18, 0.14), METAL, "metal")
	box(p + Vector3(0.2, 1.12, 0), Vector3(1.9, 0.38, 1.52), Color(0.25, 0.3, 0.35), GLASS, "", false)


func _cone(p: Vector3) -> void:
	cyl(p, 0.03, 0.18, Color(0.1, 0.1, 0.1), PLAIN, "", false, false, 6)
	box(p + Vector3(0, 0.25, 0), Vector3(0.18, 0.45, 0.18), Color(0.95, 0.45, 0.1), PLAIN, "plastic", true, false, Basis(Vector3.UP, 0.78))


func _picnic(p: Vector3) -> void:
	box(p + Vector3(0, 0.74, 0), Vector3(1.8, 0.05, 0.8), C_WOOD, WOOD, "wood")
	for s in [-0.65, 0.65]:
		box(p + Vector3(0, 0.44, s), Vector3(1.8, 0.04, 0.28), C_WOOD, WOOD, "wood")
	for x in [-0.7, 0.7]:
		box(p + Vector3(x, 0.37, 0), Vector3(0.06, 0.74, 1.4), C_WOOD.darkened(0.2), WOOD, "", false)
	blockers.append([Vector2(p.x, p.z), 0.9])


func _food_truck(p: Vector3) -> void:
	box(p + Vector3(0, 1.5, 0), Vector3(2.3, 2.4, 5.6), Color(0.95, 0.85, 0.3), METAL, "metal")
	box(p + Vector3(0, 0.3, 0), Vector3(2.2, 0.35, 5.2), Color(0.15, 0.15, 0.15), METAL, "metal")
	for z in [-1.8, 1.8]:
		for x in [-1.1, 1.1]:
			cyl(p + Vector3(x, 0.38, z), 0.25, 0.38, Color(0.05, 0.05, 0.05), PLAIN, "", false, false, 10, Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.IDENTITY)
	glow(p + Vector3(-1.16, 1.7, 0.3), Vector3(0.02, 0.9, 2.6), Color(1.0, 0.75, 0.45), 1.8)
	box(p + Vector3(-1.75, 2.45, 0.3), Vector3(1.2, 0.05, 3.0), Color(0.8, 0.2, 0.2), FABRIC, "fabric", true, true, Basis(Vector3(0, 0, 1), -0.2))
	box(p + Vector3(-1.4, 1.05, 0.3), Vector3(0.5, 0.05, 2.6), Color(0.6, 0.6, 0.6), METAL, "metal")
	var l := sign_text("TACO CAT", p + Vector3(-1.18, 2.4, 0.3), Vector3(-1, 0, 0), Color(3.0, 1.2, 0.4), 0.01)
	l.font_size = 64
	light(p + Vector3(-2.0, 2.0, 0.3), Color(1.0, 0.75, 0.45), 1.0, 5.0)
	perches.append(p + Vector3(0, 2.75, 1.5))


# ================================================================ bridges + edges

func _bridges() -> void:
	# the sign bridge: roof to roof over cross st (neko ramen <-> the deli), parapet top height
	var y := 10.15 + 0.58
	var z := -15.0
	box(Vector3(0, y - 0.05, z), Vector3(18.6, 0.1, 1.1), C_METAL, METAL, "metal")
	for s in [-0.55, 0.55]:
		box(Vector3(0, y + 0.45, z + s), Vector3(18.6, 0.04, 0.04), C_METAL, METAL, "metal")
		for k in 10:
			box(Vector3(-8.4 + k * 1.87, y + 0.22, z + s), Vector3(0.04, 0.45, 0.04), C_METAL, METAL, "", false)
	# truss under it + the hanging sign
	for k in 9:
		box(Vector3(-8.0 + k * 2.0, y - 0.6, z), Vector3(0.05, 1.2, 1.0), C_METAL, METAL, "", false, false, Basis(Vector3(0, 0, 1), 0.6 if k % 2 == 0 else -0.6))
	box(Vector3(0, y - 2.2, z), Vector3(8.0, 2.0, 0.2), Color(0.06, 0.06, 0.08), METAL, "metal")
	glow(Vector3(0, y - 2.2, z), Vector3(7.7, 1.7, 0.24), Color(0.4, 0.1, 0.35), 0.8)
	for s in [1.0, -1.0]:
		var l := sign_text("WHISKR", Vector3(0, y - 2.2, z + s * 0.14), Vector3(0, 0, s), NEON[0], 0.03)
		l.font_size = 72
	light(Vector3(0, y - 3.6, z), Color(1.0, 0.3, 0.7), 1.6, 9.0)
	labels.append(["sign bridge", Vector3(0, y, z)])
	perches.append(Vector3(-4.0, y + 0.5, z + 0.55))
	perches.append(Vector3(4.0, y + 0.5, z - 0.55))
	# the footbridge over main st (x 26..28.2): stairs down both sidewalks (ramps), railings,
	# crawl space under the stairs
	var dy := 5.15
	var x0 := 26.0
	var x1 := 28.2
	var col := Color(0.35, 0.38, 0.42)
	box(Vector3((x0 + x1) * 0.5, dy - 0.08, 0), Vector3(x1 - x0, 0.16, 17.6), col, METAL, "metal")
	for s in [x0 + 0.05, x1 - 0.05]:
		box(Vector3(s, dy + 0.55, 0), Vector3(0.05, 1.1, 17.6), Color(0.5, 0.6, 0.7), GLASS, "glass")
		box(Vector3(s, dy + 1.12, 0), Vector3(0.1, 0.05, 17.6), C_METAL, METAL, "metal")
	for zs in [-1.0, 1.0]:
		cyl(Vector3((x0 + x1) * 0.5, CURB, zs * 7.0), dy - 0.16 - CURB, 0.22, col, METAL, "metal")
		var run := 8.0
		var ang := atan2(dy - CURB, run)
		box(Vector3(x1 + run * 0.5, (dy + CURB) * 0.5, zs * 7.7), Vector3(sqrt(run * run + (dy - CURB) * (dy - CURB)), 0.12, 1.6), col, METAL, "metal", true, false, Basis(Vector3(0, 0, 1), -ang))
		box(Vector3(x1 + run * 0.5, (dy + CURB) * 0.5 + 0.9, zs * 7.7 + zs * 0.8), Vector3(sqrt(run * run + (dy - CURB) * (dy - CURB)), 0.05, 0.05), C_METAL, METAL, "metal", true, false, Basis(Vector3(0, 0, 1), -ang))
		cyl(Vector3(x1 + 3.5, CURB, zs * 7.7), (dy - CURB) * 0.55, 0.1, col, METAL, "metal")
	labels.append(["footbridge", Vector3(27, dy, 0)])
	light(Vector3(27.1, dy + 2.2, 0), Color(0.6, 0.8, 1.0), 1.0, 7.0)
	box(Vector3(27.1, dy + 2.3, 0), Vector3(2.4, 0.08, 17.6), C_METAL, METAL, "metal")   # a canopy on top
	glow(Vector3(27.1, dy + 2.24, 0), Vector3(0.1, 0.03, 16.0), Color(0.6, 0.8, 1.0), 2.0)
	for zz in [-8.0, 0.0, 8.0]:
		for s in [x0, x1]:
			box(Vector3(s, dy + 1.7, zz), Vector3(0.08, 1.2, 0.08), C_METAL, METAL, "metal")
	perches.append(Vector3(27.1, dy + 2.38, 3.0))
	# a plank across the gangway from the warehouse roof to the apartments' fire escape side
	box(Vector3(-36.0, 10.75, -24.0), Vector3(3.6, 0.06, 0.32), Color(0.6, 0.48, 0.3), WOOD, "wood")
	# a plank from the bodega roof (7.15) to the noodle bar's fire escape (level 2 = 6.75)
	box(Vector3(-22.0, 7.75, 18.0), Vector3(2.6, 0.06, 0.32), Color(0.6, 0.48, 0.3), WOOD, "wood")


func _edges() -> void:
	# invisible walls on the map edge, all the way up
	for s in [-1.0, 1.0]:
		var ws := BoxShape3D.new()
		ws.size = Vector3(0.5, 60, 2 * HALF + 2)
		_shape(Transform3D(Basis(), Vector3(s * (HALF + 0.25), 30, 0)), ws, "stone", false)
		var ws2 := BoxShape3D.new()
		ws2.size = Vector3(2 * HALF + 2, 60, 0.5)
		_shape(Transform3D(Basis(), Vector3(0, 30, s * (HALF + 0.25))), ws2, "stone", false)
	# tunnel portals where the streets leave the map: concrete, dark mouth, orange lamps
	var conc := Color(0.38, 0.38, 0.4)
	for s in [-1.0, 1.0]:
		for axis in ["x", "z"]:
			var at: float = s * (HALF + 0.6)
			var c := Vector3(at, 0, 0) if axis == "x" else Vector3(0, 0, at)
			var big := Vector3(1.2, 9.0, 18.0) if axis == "x" else Vector3(18.0, 9.0, 1.2)
			box(c + Vector3(0, 10.0, 0), big, conc, CONC, "stone")
			for side in [-1.0, 1.0]:
				var post := Vector3(1.2, 5.5, 4.0) if axis == "x" else Vector3(4.0, 5.5, 1.2)
				var off := Vector3(0, 2.75, side * 7.0) if axis == "x" else Vector3(side * 7.0, 2.75, 0)
				box(c + off, post, conc, CONC, "stone")
			# the tunnel itself: a dark box running on (cars vanish in there)
			var tc := Vector3(s * (HALF + 7.0), 2.9, 0) if axis == "x" else Vector3(0, 2.9, s * (HALF + 7.0))
			var tsz := Vector3(12.0, 0.2, 10.4) if axis == "x" else Vector3(10.4, 0.2, 12.0)
			box(tc + Vector3(0, 2.6, 0), tsz, Color(0.05, 0.05, 0.06), CONC, "", false)
			for side in [-1.0, 1.0]:
				var wsz := Vector3(12.0, 5.6, 0.2) if axis == "x" else Vector3(0.2, 5.6, 12.0)
				var wo := Vector3(0, 0, side * 5.2) if axis == "x" else Vector3(side * 5.2, 0, 0)
				box(tc + wo, wsz, Color(0.08, 0.08, 0.09), CONC, "", false)
			for k in 3:
				var lp := tc + (Vector3(s * (k * 3.5 - 4.0), 2.3, 0) if axis == "x" else Vector3(0, 2.3, s * (k * 3.5 - 4.0)))
				glow(lp, Vector3(0.4, 0.06, 0.4), Color(1.0, 0.55, 0.2), 4.0)
			var lab := "MAIN ST" if axis == "x" else "CROSS ST"
			sign_text(lab, c + Vector3(-s * 0.62, 6.3, 0) if axis == "x" else c + Vector3(0, 6.3, -s * 0.62), Vector3(-s, 0, 0) if axis == "x" else Vector3(0, 0, -s), Color(0.9, 0.95, 1.0), 0.016)


## the city goes on past the edges: tall dark blocks with lit windows (no collision, far away)
func _backdrop() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for side in 4:
		var u := -HALF - 22.0
		while u < HALF + 22.0:
			var w := r.randf_range(7.0, 14.0)
			var mid := u + w * 0.5
			u += w + r.randf_range(0.5, 3.0)
			if absf(mid) < 9.0:
				continue    # the street runs on here
			var depth := r.randf_range(8.0, 16.0)
			var h := r.randf_range(14.0, 42.0)
			var off := HALF + 4.0 + r.randf_range(0.0, 10.0) + depth * 0.5
			var c := Vector3(mid, h * 0.5, off)
			var size := Vector3(w, h, depth)
			var n := Vector3(0, 0, -1)
			match side:
				1:
					c = Vector3(mid, h * 0.5, -off); n = Vector3(0, 0, 1)
				2:
					c = Vector3(off, h * 0.5, mid); size = Vector3(depth, h, w); n = Vector3(-1, 0, 0)
				3:
					c = Vector3(-off, h * 0.5, mid); size = Vector3(depth, h, w); n = Vector3(1, 0, 0)
			var col := Color(0.12, 0.11, 0.15).lerp(Color(0.25, 0.18, 0.22), r.randf())
			box(c, size, col, CONC, "", false)
			# rows of lit windows on the face toward the city
			var face := c + n * (size.dot(n.abs()) * 0.5 + 0.02)
			var along := Vector3(n.z, 0, n.x).abs()
			for fl in int(h / 3.3):
				var y := 2.0 + fl * 3.3
				for k in int(w / 2.2):
					if r.randf() < 0.35:
						var a := -w * 0.5 + 1.1 + k * 2.2
						glow(Vector3(face.x, y, face.z) + along * a, along * 1.1 + Vector3(0, 1.3, 0) + n.abs() * 0.02, WARM[r.randi() % WARM.size()], r.randf_range(0.8, 2.2))
			if r.randf() < 0.3:
				glow(Vector3(face.x, h - 2.0, face.z), along * (w * 0.7) + Vector3(0, 1.5, 0) + n.abs() * 0.05, NEON[r.randi() % NEON.size()], 1.2)
			if r.randf() < 0.5:
				glow(Vector3(c.x, h + 0.3, c.z), Vector3(0.15, 0.15, 0.15), Color(1, 0.1, 0.1), 5.0)


# ================================================================ finish

func _flush() -> void:
	for cell in _buckets:
		var b: Array = _buckets[cell]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b[0]
		arr[Mesh.ARRAY_NORMAL] = b[1]
		arr[Mesh.ARRAY_COLOR] = b[2]
		arr[Mesh.ARRAY_TEX_UV] = b[3]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = _mat
		mi.name = "Cell_%d_%d" % [cell.x, cell.y]
		add_child(mi)
	_buckets.clear()


## the sidewalk height under x, z (0 on the road, CURB on the blocks)
static func ground_y(x: float, z: float) -> float:
	if absf(x) < ROAD or absf(z) < ROAD:
		return 0.0
	return CURB


static func on_road(p: Vector3) -> bool:
	return (absf(p.x) < ROAD or absf(p.z) < ROAD) and absf(p.x) < HALF and absf(p.z) < HALF


## the closest point on a sidewalk (for putting a bonked cat back on the curb)
static func nearest_curb(p: Vector3, from_side := Vector3.ZERO) -> Vector3:
	var x := p.x
	var z := p.z
	var side := from_side if from_side != Vector3.ZERO else p
	if absf(p.z) < ROAD and absf(p.x) >= ROAD:
		z = signf(side.z if side.z != 0.0 else 1.0) * (ROAD + 0.9)
	elif absf(p.x) < ROAD and absf(p.z) >= ROAD:
		x = signf(side.x if side.x != 0.0 else 1.0) * (ROAD + 0.9)
	else:
		# in the crossing: nearest corner
		x = signf(side.x if side.x != 0.0 else 1.0) * (ROAD + 0.9)
		z = signf(side.z if side.z != 0.0 else 1.0) * (ROAD + 0.9)
	return Vector3(x, CURB + 0.05, z)
