class_name World
extends RefCounted
## the big demo map around the living room: a two storey bedroom wing with an attic
## office, the back yard (fence, big climbable tree, garden), and a barn with a hay
## loft, beams, stalls and a rope. real scale, meters. everything static goes through
## Level.box so it gets merged into a few big meshes.

const C_SIDING := Color(0.82, 0.78, 0.68)
const C_TRIM := Color(0.95, 0.95, 0.92)
const C_ROOF := Color(0.36, 0.3, 0.3)
const C_GRASS := Color(0.42, 0.58, 0.3)
const C_DIRT := Color(0.55, 0.45, 0.32)
const C_FENCE := Color(0.7, 0.6, 0.45)
const C_BARN := Color(0.58, 0.17, 0.13)
const C_BARN_IN := Color(0.5, 0.36, 0.24)
const C_HAY := Color(0.86, 0.74, 0.4)
const C_BARK := Color(0.4, 0.3, 0.22)
const C_LEAF := Color(0.3, 0.5, 0.24)
const C_CARPET := Color(0.5, 0.55, 0.62)
const C_WOOD := Color(0.48, 0.32, 0.2)
const C_WOOD_L := Color(0.72, 0.56, 0.38)

const WING_X0 := 5.2
const WING_X1 := 11.2
const FLOOR2 := 2.7     # attic floor top
const WING_H := 5.0


static func build(lv: Node3D) -> void:
	_ground(lv)
	_wing(lv)
	_roofs(lv)
	_yard(lv)
	_barn(lv, Vector3(12.0, 0, 22.0))
	Hub.build_farm(lv)


static func B(lv: Node3D, c: Vector3, s: Vector3, col: Color, collide := true) -> Node3D:
	return Level.box(lv, c, s, col, collide)


static func X(lv: Node3D, minc: Vector3, s: Vector3, col: Color, collide := true) -> Node3D:
	return Level.bx(lv, minc, s, col, collide)


static func _climb(n: Node, scratch := true) -> void:
	n.add_to_group("climbable")
	if scratch:
		n.add_to_group("scratchable")


# ---------------------------------------------------------------- ground

static func _ground(lv: Node3D) -> void:
	# one collider for the whole lot, grass visual in tiles with a bit of tone variation
	Level.box(lv, Vector3(5, -0.25, 11), Vector3(50, 0.5, 46), C_GRASS, true, 0.0, false).set_meta("surface", "grass")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for ix in range(-20, 30, 2):
		for iz in range(-12, 34, 2):
			var t := rng.randf_range(-0.04, 0.04)
			B(lv, Vector3(ix + 1, -0.025, iz + 1), Vector3(2, 0.03, 2), Color(C_GRASS.r + t, C_GRASS.g + t * 1.2, C_GRASS.b + t * 0.6), false)
	# farmland beyond the fence + a ring of distant trees so the horizon isn't a void
	B(lv, Vector3(5, -0.08, 11), Vector3(500, 0.1, 500), Color(0.5, 0.6, 0.34), false)
	for k in 46:
		var ang := k * TAU / 46.0 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(34.0, 60.0)
		var tp := Vector3(5 + cos(ang) * r * 1.1, 0, 11 + sin(ang) * r)
		var th := rng.randf_range(3.0, 6.0)
		B(lv, tp + Vector3(0, th * 0.4, 0), Vector3(0.5, th * 0.8, 0.5), C_BARK, false)
		B(lv, tp + Vector3(0, th, 0), Vector3.ONE * rng.randf_range(2.5, 4.0), C_LEAF.darkened(rng.randf() * 0.2), false)
	# stepping stone path patio door -> barn door
	var p := Vector3(2.3, 0, 4.6)
	var q := Vector3(12.0, 0, 15.6)
	var n := 16
	for k in n:
		var t := float(k) / float(n - 1)
		var c := p.lerp(q, t) + Vector3(sin(k * 1.7) * 0.15, 0, 0)
		B(lv, c + Vector3(0, -0.005, 0), Vector3(0.45, 0.02, 0.38), Color(0.62, 0.6, 0.56).lightened(rng.randf() * 0.08), false)
	# patio slab outside the door
	B(lv, Vector3(2.3, -0.01, 5.0), Vector3(3.0, 0.03, 1.6), Color(0.7, 0.68, 0.64), false)


# ---------------------------------------------------------------- bedroom wing + attic

static func _wing(lv: Node3D) -> void:
	var x0 := WING_X0
	var x1 := WING_X1
	# walls (two storeys). west wall is the living room's east wall below 2.6, above it a gable wall
	X(lv, Vector3(x1, 0, -4.2), Vector3(0.2, WING_H, 8.4), Color(0.8, 0.76, 0.84))
	X(lv, Vector3(x0, 0, -4.2), Vector3(x1 - x0, WING_H, 0.2), Color(0.8, 0.76, 0.84))
	# south wall: window in the bedroom (x 8.2..9.4, y 0.8..1.9)
	X(lv, Vector3(x0, 0, 4.0), Vector3(3.0, WING_H, 0.2), Color(0.8, 0.76, 0.84))
	X(lv, Vector3(9.4, 0, 4.0), Vector3(x1 - 9.4, WING_H, 0.2), Color(0.8, 0.76, 0.84))
	X(lv, Vector3(8.2, 0, 4.0), Vector3(1.2, 0.8, 0.2), Color(0.8, 0.76, 0.84))
	X(lv, Vector3(8.2, 1.9, 4.0), Vector3(1.2, WING_H - 1.9, 0.2), Color(0.8, 0.76, 0.84))
	X(lv, Vector3(8.15, 0.78, 3.85), Vector3(1.3, 0.04, 0.4), C_TRIM)          # sill, top 0.82
	X(lv, Vector3(5.0, 2.6, -4.2), Vector3(0.2, WING_H - 2.6, 8.4), Color(0.8, 0.76, 0.84))
	# carpet (thin collider on top of the yard ground so it grips like carpet)
	B(lv, Vector3((x0 + x1) * 0.5, 0.004, 0), Vector3(x1 - x0, 0.008, 8.0), C_CARPET, false)
	Level.box(lv, Vector3((x0 + x1) * 0.5, -0.001, 0), Vector3(x1 - x0, 0.01, 8.0), C_CARPET, true, 0.0, false).set_meta("surface", "carpet")

	# attic floor with the stairwell hole along the north wall (x 6.2..10.0, z -4.0..-3.1)
	for fl in [X(lv, Vector3(x0, FLOOR2 - 0.12, -3.1), Vector3(x1 - x0, 0.12, 7.1), C_WOOD_L),
			X(lv, Vector3(10.0, FLOOR2 - 0.12, -4.0), Vector3(x1 - 10.0, 0.12, 0.9), C_WOOD_L),
			X(lv, Vector3(x0, FLOOR2 - 0.12, -4.0), Vector3(6.2 - x0, 0.12, 0.9), C_WOOD_L)]:
		fl.set_meta("surface", "wood")
	X(lv, Vector3(x0, WING_H, -4.2), Vector3(x1 - x0 + 0.2, 0.1, 8.4), Color(0.95, 0.94, 0.9))   # ceiling
	X(lv, Vector3(x0, FLOOR2 - 0.13, -3.1), Vector3(x1 - x0, 0.01, 7.1), Color(0.95, 0.94, 0.9), false)   # bedroom ceiling paint

	# stairs: 14 steps of 19 cm. visual blocks + one smooth ramp collider so walking up just works
	var steps := 14
	var rise := FLOOR2 / steps
	var run := 3.8 / steps
	for k in steps:
		var sx := 6.2 + k * run
		X(lv, Vector3(sx, 0, -4.0), Vector3(run + 0.002, rise * (k + 1), 0.9), C_WOOD if k % 2 == 0 else C_WOOD.lightened(0.05), k == steps - 1)
	# ramp runs through the middle of each tread: from (6.2 - run/2, 0) to (10 - run/2, 2.7)
	var ang := atan2(FLOOR2, 3.8)
	var ramp_len := Vector2(3.8, FLOOR2).length() + 0.1
	var rc := Vector3(6.2 + 1.9 - run * 0.5, FLOOR2 * 0.5, -3.55) + Vector3(sin(ang), -cos(ang), 0) * 0.05
	var ramp := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(ramp_len, 0.1, 0.9)
	cs.shape = bs
	ramp.add_child(cs)
	ramp.transform = Transform3D(Basis(Vector3.BACK, ang), rc)
	lv.add_child(ramp)
	# railing along the stairwell (top rail is a nice cat walk)
	Level.box(lv, Vector3(8.1, FLOOR2 + 0.45, -3.11), Vector3(3.8, 0.9, 0.02), Color.WHITE, true, 0.0, false)
	for k in 8:
		X(lv, Vector3(6.2 + k * 0.53, FLOOR2, -3.12), Vector3(0.04, 0.9, 0.04), C_WOOD, false)
	X(lv, Vector3(6.15, FLOOR2 + 0.9, -3.16), Vector3(3.9, 0.04, 0.1), C_WOOD)

	# ---- bedroom (ground floor) ----
	# bed: mattress top 0.55, headboard against the south wall
	X(lv, Vector3(8.6, 0, 1.8), Vector3(2.0, 0.3, 2.1), C_WOOD)
	var mat := X(lv, Vector3(8.65, 0.3, 1.85), Vector3(1.9, 0.25, 2.0), Color(0.93, 0.93, 0.95))
	mat.add_to_group("scratchable")
	X(lv, Vector3(8.65, 0.55, 3.2), Vector3(1.9, 0.1, 0.6), Color(0.9, 0.9, 0.95))          # pillows
	X(lv, Vector3(8.65, 0.55, 1.85), Vector3(1.9, 0.05, 1.3), Color(0.45, 0.55, 0.75))       # duvet
	X(lv, Vector3(8.6, 0, 3.85), Vector3(2.0, 1.05, 0.12), C_WOOD)                            # headboard
	# nightstands + lamps
	for sx in [8.0, 10.65]:
		X(lv, Vector3(sx, 0, 3.4), Vector3(0.5, 0.55, 0.45), C_WOOD_L)
	Level.mug(lv, Vector3(10.85, 0.55, 3.6), Color(0.95, 0.6, 0.2))
	_book(lv, Vector3(8.2, 0.55, 3.55), Color(0.3, 0.4, 0.7))
	_book(lv, Vector3(8.25, 0.58, 3.55), Color(0.7, 0.25, 0.3))
	# dresser by the west wall + mirror
	X(lv, Vector3(5.25, 0, 1.5), Vector3(0.5, 0.95, 1.6), C_WOOD)
	for k in 3:
		X(lv, Vector3(5.73, 0.1 + k * 0.28, 1.55), Vector3(0.02, 0.24, 1.5), C_WOOD_L, false)
	B(lv, Vector3(5.22, 1.5, 2.3), Vector3(0.03, 0.8, 0.6), Color(0.75, 0.85, 0.9), false)
	_book(lv, Vector3(5.45, 0.95, 1.8), Color(0.2, 0.6, 0.5))
	Level.mug(lv, Vector3(5.5, 0.95, 2.6), Color(0.9, 0.9, 0.95))
	_ball(lv, Vector3(5.5, 0.98, 1.2), Color(0.9, 0.2, 0.3), 0.04)
	# wardrobe (2.1 m) on the east wall, the dresser -> wardrobe leap is the challenge here
	X(lv, Vector3(10.6, 0, -2.4), Vector3(0.6, 2.1, 1.6), C_WOOD)
	X(lv, Vector3(10.58, 0.05, -1.62), Vector3(0.02, 2.0, 0.02), C_WOOD_L, false)
	X(lv, Vector3(10.65, 2.1, -2.3), Vector3(0.45, 0.25, 0.45), Color(0.74, 0.57, 0.36))     # box on top
	# laundry basket (soft, scratchable) + chair
	var lb := X(lv, Vector3(9.6, 0, -0.6), Vector3(0.5, 0.45, 0.4), Color(0.85, 0.82, 0.7))
	lb.add_to_group("scratchable")
	Level.table(lv, Vector2(7.2, -1.8), Vector3(0.45, 0.46, 0.45), C_WOOD_L, C_WOOD)
	B(lv, Vector3(7.2, 0.72, -1.58), Vector3(0.45, 0.5, 0.03), C_WOOD)
	# rug
	B(lv, Vector3(8.0, 0.012, 0.5), Vector3(2.4, 0.008, 1.6), Color(0.75, 0.45, 0.35), false)
	_light(lv, Vector3(8.2, 2.3, 0.0), 0.8, 6.0)

	# ---- attic office (upstairs) ----
	var f := FLOOR2
	X(lv, Vector3(6.3, f + 0.71, 2.95), Vector3(1.4, 0.04, 0.7), C_WOOD_L)       # desk top 0.75
	for dx in [6.35, 7.6]:
		for dz in [3.0, 3.55]:
			X(lv, Vector3(dx, f, dz), Vector3(0.05, 0.71, 0.05), C_WOOD)
	X(lv, Vector3(6.6, f, 2.3), Vector3(0.45, 0.46, 0.45), C_WOOD)                # stool
	B(lv, Vector3(6.8, f + 0.9, 3.55), Vector3(0.5, 0.3, 0.04), Color(0.1, 0.1, 0.12))       # monitor
	_book(lv, Vector3(7.4, f + 0.75, 3.2), Color(0.8, 0.7, 0.2))
	Level.mug(lv, Vector3(7.5, f + 0.75, 3.45), Color(0.2, 0.2, 0.25))
	for k in 4:
		_pencil(lv, Vector3(6.4 + k * 0.05, f + 0.76, 3.1))
	# tall bookshelf with open shelves to climb
	for side in [0.0, 1.2]:
		X(lv, Vector3(10.6, f, -0.5 + side), Vector3(0.4, 2.0, 0.04), C_WOOD)
	for y in [0.0, 0.5, 1.0, 1.5, 1.96]:
		X(lv, Vector3(10.6, f + y, -0.46), Vector3(0.4, 0.04, 1.2), C_WOOD_L)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for y in [0.04, 0.54, 1.04]:
		var z := -0.44
		while z < 0.6:
			var t := rng.randf_range(0.025, 0.05)
			var h := rng.randf_range(0.2, 0.36)
			if rng.randf() < 0.75:
				B(lv, Vector3(10.85, f + y + h * 0.5, z + t * 0.5), Vector3(0.24, h, t), Color.from_hsv(rng.randf(), 0.45, 0.65), false)
			z += t + 0.004
			if rng.randf() < 0.1:
				z += 0.25
	# cardboard box fort + storage
	for b in [[Vector3(5.5, f, -2.6), Vector3(0.6, 0.5, 0.6)], [Vector3(5.5, f + 0.5, -2.5), Vector3(0.45, 0.4, 0.45)], [Vector3(6.2, f, -2.7), Vector3(0.5, 0.35, 0.5)], [Vector3(5.4, f, 1.2), Vector3(0.7, 0.6, 0.5)]]:
		X(lv, b[0], b[1], Color(0.74, 0.57, 0.36).lightened(rng.randf() * 0.08))
	# high shelf across the gable wall with a treat, reach it from the bookshelf top
	X(lv, Vector3(10.4, f + 1.95, 1.0), Vector3(0.8, 0.04, 2.8), C_WOOD_L)
	_treat(lv, Vector3(10.8, f + 2.03, 3.4))
	# beanbag (soft landing)
	B(lv, Vector3(8.7, f + 0.2, 2.6), Vector3(0.9, 0.4, 0.9), Color(0.55, 0.3, 0.5))
	B(lv, Vector3(8.7, f + 0.004, 0.8), Vector3(2.4, 0.008, 1.8), Color(0.35, 0.5, 0.55), false)
	var mouse := ToyMouse.new()
	mouse.position = Vector3(8.2, f + 0.02, 0.2)
	lv.add_child(mouse)
	_light(lv, Vector3(8.2, f + 2.0, 0.5), 0.9, 6.0)
	# exterior siding on the outside faces of the house
	var sd := C_SIDING
	X(lv, Vector3(-5.24, 0, 4.2), Vector3(7.04, 2.62, 0.02), sd, false)
	X(lv, Vector3(2.8, 0, 4.2), Vector3(2.4, 2.62, 0.02), sd, false)
	X(lv, Vector3(1.8, 2.1, 4.2), Vector3(1.0, 0.52, 0.02), sd, false)
	X(lv, Vector3(5.2, 0, 4.2), Vector3(3.0, WING_H, 0.02), sd, false)
	X(lv, Vector3(9.4, 0, 4.2), Vector3(2.0, WING_H, 0.02), sd, false)
	X(lv, Vector3(8.2, 0, 4.2), Vector3(1.2, 0.8, 0.02), sd, false)
	X(lv, Vector3(8.2, 1.9, 4.2), Vector3(1.2, WING_H - 1.9, 0.02), sd, false)
	X(lv, Vector3(11.4, 0, -4.22), Vector3(0.02, WING_H, 8.44), sd, false)
	X(lv, Vector3(-5.22, 0, -4.22), Vector3(10.22, 2.62, 0.02), sd, false)
	X(lv, Vector3(5.0, 0, -4.22), Vector3(6.42, WING_H, 0.02), sd, false)
	# siding lap lines
	for y in range(1, 17):
		var yy := y * 0.3
		if yy < 2.62:
			B(lv, Vector3(-1.5, yy, 4.215), Vector3(7.4, 0.015, 0.012), sd.darkened(0.12), false)
		B(lv, Vector3(8.3, yy, 4.215), Vector3(6.2, 0.015, 0.012), sd.darkened(0.12), false)
	# patio door frame + window frames
	X(lv, Vector3(1.74, 0, 4.18), Vector3(0.06, 2.16, 0.06), C_TRIM, false)
	X(lv, Vector3(2.8, 0, 4.18), Vector3(0.06, 2.16, 0.06), C_TRIM, false)
	X(lv, Vector3(1.74, 2.1, 4.18), Vector3(1.12, 0.06, 0.06), C_TRIM, false)
	X(lv, Vector3(8.14, 0.78, 4.18), Vector3(1.32, 0.06, 0.08), C_TRIM, false)
	X(lv, Vector3(8.14, 1.9, 4.18), Vector3(1.32, 0.06, 0.08), C_TRIM, false)


# ---------------------------------------------------------------- roofs

static func _roofs(lv: Node3D) -> void:
	# living room: gable along x, eaves 2.65 at z +-4.5, ridge 3.9 at z 0. low enough to walk on
	var half := 4.5
	var rise := 1.25
	var a := atan2(rise, half)
	var l := Vector2(half, rise).length()
	for sz in [-1.0, 1.0]:
		Level.rbox(lv, Vector3(-0.1, 2.65 + rise * 0.5 + 0.06, sz * half * 0.5), Vector3(10.6, 0.12, l + 0.1), Vector3(sz * a, 0, 0), C_ROOF)
	# gable end (west) as stepped blocks: very on brand
	for k in 6:
		var h := rise * (1.0 - k / 6.0)
		var w := half * 2.0 * (1.0 - (k + 0.5) / 6.0)
		X(lv, Vector3(-5.22, 2.6 + k * rise / 6.0, -w * 0.5), Vector3(0.24, rise / 6.0 + 0.01, w), C_SIDING, false)
	# ridge cap
	B(lv, Vector3(-0.1, 3.95, 0), Vector3(10.6, 0.08, 0.2), C_ROOF.darkened(0.2))
	# bedroom wing: steeper gable along x, eaves 5.0, ridge 6.6
	var rise2 := 1.6
	var a2 := atan2(rise2, half)
	var l2 := Vector2(half, rise2).length()
	for sz in [-1.0, 1.0]:
		Level.rbox(lv, Vector3(8.3, WING_H + rise2 * 0.5 + 0.06, sz * half * 0.5), Vector3(6.6, 0.12, l2 + 0.1), Vector3(sz * a2, 0, 0), C_ROOF)
	for k in 8:
		var w := half * 2.0 * (1.0 - (k + 0.5) / 8.0)
		X(lv, Vector3(11.2, WING_H + k * rise2 / 8.0, -w * 0.5), Vector3(0.24, rise2 / 8.0 + 0.01, w), C_SIDING, false)
		X(lv, Vector3(4.98, WING_H + k * rise2 / 8.0, -w * 0.5), Vector3(0.24, rise2 / 8.0 + 0.01, w), C_SIDING, false)
	# chimney
	X(lv, Vector3(-3.5, 2.6, -2.2), Vector3(0.6, 2.0, 0.6), Color(0.6, 0.35, 0.28))
	# gutter along the south eave (a ledge the cat can grab from the tree side)
	X(lv, Vector3(-5.4, 2.58, 4.45), Vector3(10.8, 0.08, 0.1), Color(0.75, 0.75, 0.78))


# ---------------------------------------------------------------- yard

static func _yard(lv: Node3D) -> void:
	# fence around the lot: one climbable collider per panel, pickets as visuals
	var x0 := -16.0
	var x1 := 26.0
	var z0 := -9.0
	var z1 := 31.0
	var runs := [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x1, z0), Vector2(x1, z1)], [Vector2(x1, z1), Vector2(x0, z1)], [Vector2(x0, z1), Vector2(x0, z0)]]
	for r in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var panels := int(ceil(len / 2.5))
		for i in panels:
			var pa := a + dir * (len * i / panels)
			var pb := a + dir * (len * (i + 1) / panels)
			var pm := (pa + pb) * 0.5
			var pl := pa.distance_to(pb)
			var horiz := absf(dir.x) > 0.5
			# hub gates to the other levels (hub.gd): forest west, pier 9 east, trail north
			var gate := Hub.gate_on_fence(horiz, pm, pl)
			if gate != "":
				Hub.fence_gate(lv, gate, Vector3(pm.x, 0, pm.y), pl)
				continue
			var sz := Vector3(pl, 1.25, 0.05) if horiz else Vector3(0.05, 1.25, pl)
			var panel := Level.box(lv, Vector3(pm.x, 0.625, pm.y), sz, C_FENCE, true, 0.0, false)
			_climb(panel)
			# post
			B(lv, Vector3(pa.x, 0.7, pa.y), Vector3(0.1, 1.4, 0.1), C_FENCE.darkened(0.15))
			# pickets
			var n := int(pl / 0.14)
			for k in n:
				var p := pa + dir * (k + 0.5) * pl / n
				B(lv, Vector3(p.x, 0.6, p.y), Vector3(0.1 if horiz else 0.025, 1.2, 0.025 if horiz else 0.1), C_FENCE.lightened(0.04 * ((k * 7) % 3)), false)
			# top rail you can walk along
			B(lv, Vector3(pm.x, 1.27, pm.y), Vector3(pl, 0.04, 0.1) if horiz else Vector3(0.1, 0.04, pl), C_FENCE.darkened(0.08))

	# big tree west of the patio: climbable trunk, branches as walkways, one reaches the roof
	_tree(lv, Vector3(-2.5, 0, 8.0), 5.2, 7)
	_tree(lv, Vector3(20.0, 0, 6.0), 4.2, 13)

	# garden bench + table with pots to knock over
	X(lv, Vector3(4.2, 0, 7.6), Vector3(1.6, 0.42, 0.45), C_WOOD_L)
	X(lv, Vector3(4.2, 0.42, 8.0), Vector3(1.6, 0.45, 0.06), C_WOOD_L)
	Level.table(lv, Vector2(5.0, 9.4), Vector3(1.0, 0.7, 0.7), C_WOOD_L, C_WOOD)
	for k in 3:
		_pot(lv, Vector3(4.7 + k * 0.3, 0.7, 9.4 + (k % 2) * 0.12))
	Level.mug(lv, Vector3(5.3, 0.7, 9.2), Color(0.95, 0.95, 0.95))
	# raised veggie beds (scratchable soil edges)
	for k in 3:
		var c := Vector3(-10.0 + k * 2.4, 0, 18.0)
		X(lv, c, Vector3(1.8, 0.35, 1.0), C_WOOD)
		X(lv, c + Vector3(0.05, 0.35, 0.05), Vector3(1.7, 0.01, 0.9), C_DIRT, false)
		for j in 4:
			B(lv, c + Vector3(0.3 + j * 0.4, 0.5, 0.5), Vector3(0.18, 0.3, 0.18), C_LEAF.lightened(0.1 * (j % 2)), false)
	# woodpile against the fence: stepped, scratchable
	for row in 4:
		var wp := X(lv, Vector3(-15.5, row * 0.3, 4.0 + row * 0.25), Vector3(1.0, 0.3, 3.0 - row * 0.5), C_BARK.lightened(0.1))
		_climb(wp)
	# garden trellis (climbable) + shed
	var tr := X(lv, Vector3(-15.8, 0, -3.0), Vector3(0.06, 2.0, 1.4), C_WOOD_L)
	_climb(tr)
	for k in 7:
		B(lv, Vector3(-15.74, 0.15 + k * 0.28, -2.3), Vector3(0.02, 0.02, 1.4), C_WOOD, false)
	_shed(lv, Vector3(-11.0, 0, 25.0))
	# kids' stuff: a ball and a bucket on the lawn
	_ball(lv, Vector3(6.0, 0.15, 13.0), Color(0.2, 0.5, 0.9), 0.11)
	_ball(lv, Vector3(-4.0, 0.05, 14.0), Color(0.95, 0.85, 0.2), 0.035)
	_bucket(lv, Vector3(1.5, 0.0, 12.0), Color(0.85, 0.3, 0.25))
	# wheelbarrow (static)
	X(lv, Vector3(15.0, 0.3, 12.0), Vector3(0.6, 0.35, 0.9), Color(0.3, 0.5, 0.35))
	X(lv, Vector3(15.25, 0, 12.85), Vector3(0.1, 0.3, 0.3), Color(0.15, 0.15, 0.15))
	X(lv, Vector3(15.0, 0, 12.05), Vector3(0.05, 0.3, 0.05), C_WOOD)
	X(lv, Vector3(15.55, 0, 12.05), Vector3(0.05, 0.3, 0.05), C_WOOD)
	var tm := ToyMouse.new()
	tm.position = Vector3(3.0, 0.02, 10.5)
	lv.add_child(tm)


static func _tree(lv: Node3D, base: Vector3, h: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var trunk := B(lv, base + Vector3(0, h * 0.5, 0), Vector3(0.38, h, 0.38), C_BARK)
	_climb(trunk)
	# root flare
	for k in 4:
		var a := k * PI * 0.5 + 0.3
		B(lv, base + Vector3(cos(a) * 0.25, 0.08, sin(a) * 0.25), Vector3(0.22, 0.16, 0.22), C_BARK.darkened(0.1), false)
	# branches: flat-topped limbs you can walk out on
	var limbs := [[1.7, 0.0, 2.0], [2.5, 2.1, 1.8], [3.2, 4.0, 2.2], [3.9, 1.0, 1.6], [4.5, 3.0, 1.4]]
	for lb in limbs:
		var y: float = lb[0]
		var a: float = lb[1] + rng.randf_range(-0.3, 0.3)
		var len: float = lb[2]
		var d := Vector3(cos(a), 0, sin(a))
		var c := base + Vector3(0, y, 0) + d * (len * 0.5 + 0.15)
		var limb := Level.rbox(lv, c, Vector3(len, 0.14, 0.16), Vector3(0, -a, 0), C_BARK)
		_climb(limb)
		# leaf clumps (visual)
		for j in 3:
			var lc := base + Vector3(0, y + 0.45 + rng.randf() * 0.3, 0) + d * (len * (0.55 + j * 0.25)) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
			B(lv, lc, Vector3.ONE * rng.randf_range(0.7, 1.1), C_LEAF.lightened(rng.randf() * 0.12), false)
	# crown
	for j in 9:
		var lc := base + Vector3(rng.randf_range(-1.4, 1.4), h + rng.randf_range(-0.4, 0.6), rng.randf_range(-1.4, 1.4))
		B(lv, lc, Vector3.ONE * rng.randf_range(1.0, 1.6), C_LEAF.lightened(rng.randf() * 0.12), false)


static func _shed(lv: Node3D, c: Vector3) -> void:
	# little garden shed: open front, shelves inside, flat roof you can sit on (2.1 m)
	var w := 2.4
	var d := 2.0
	X(lv, c + Vector3(-w * 0.5, 0, d * 0.5 - 0.06), Vector3(w, 2.0, 0.06), Color(0.45, 0.55, 0.45))
	X(lv, c + Vector3(-w * 0.5, 0, -d * 0.5), Vector3(0.06, 2.0, d), Color(0.45, 0.55, 0.45))
	X(lv, c + Vector3(w * 0.5 - 0.06, 0, -d * 0.5), Vector3(0.06, 2.0, d), Color(0.45, 0.55, 0.45))
	X(lv, c + Vector3(-w * 0.5 - 0.1, 2.0, -d * 0.5 - 0.15), Vector3(w + 0.2, 0.08, d + 0.25), C_ROOF)
	for y in [0.5, 1.0, 1.5]:
		X(lv, c + Vector3(-w * 0.5 + 0.06, y, d * 0.5 - 0.4), Vector3(w - 0.12, 0.03, 0.34), C_WOOD_L)
	_pot(lv, c + Vector3(-0.6, 0.53, 0.75))
	_pot(lv, c + Vector3(-0.2, 0.53, 0.78))
	_bucket(lv, c + Vector3(0.5, 1.03, 0.75), Color(0.6, 0.6, 0.65))
	_bucket(lv, c + Vector3(0.6, 0.0, 0.0), Color(0.3, 0.5, 0.75))
	var tm := ToyMouse.new()
	tm.position = c + Vector3(0, 0.02, 0)
	lv.add_child(tm)


# ---------------------------------------------------------------- barn

static func _barn(lv: Node3D, c: Vector3) -> void:
	var hw := 6.0      # half width (x)
	var hd := 6.0      # half depth (z)
	var wh := 4.0      # wall height
	var ridge := 6.4
	var t := 0.2
	var cx := c.x
	var cz := c.z
	# floor: packed dirt + straw patches
	B(lv, c + Vector3(0, 0.004, 0), Vector3(hw * 2, 0.008, hd * 2), C_DIRT, false)
	Level.box(lv, c + Vector3(0, -0.001, 0), Vector3(hw * 2, 0.01, hd * 2), C_DIRT, true, 0.0, false).set_meta("surface", "dirt")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for k in 30:
		B(lv, c + Vector3(rng.randf_range(-hw + 0.5, hw - 0.5), 0.01, rng.randf_range(-hd + 0.5, hd - 0.5)), Vector3(rng.randf_range(0.4, 1.2), 0.01, rng.randf_range(0.4, 1.2)), C_HAY.darkened(0.15), false)
	# walls: north has the big door (x -1.6..1.6, h 3.2), south has the loft hatch
	var zN := cz - hd
	var zS := cz + hd
	X(lv, Vector3(cx - hw, 0, zN - t), Vector3(hw - 1.6, wh, t), C_BARN)
	X(lv, Vector3(cx + 1.6, 0, zN - t), Vector3(hw - 1.6, wh, t), C_BARN)
	X(lv, Vector3(cx - 1.6, 3.2, zN - t), Vector3(3.2, wh - 3.2, t), C_BARN)
	X(lv, Vector3(cx - hw, 0, zS), Vector3(hw - 1.0, wh, t), C_BARN)
	X(lv, Vector3(cx + 1.0, 0, zS), Vector3(hw - 1.0, wh, t), C_BARN)
	X(lv, Vector3(cx - 1.0, 0, zS), Vector3(2.0, 2.55, t), C_BARN)
	X(lv, Vector3(cx - hw - t, 0, zN - t), Vector3(t, wh, hd * 2 + t * 2), C_BARN)
	X(lv, Vector3(cx + hw, 0, zN - t), Vector3(t, wh, hd * 2 + t * 2), C_BARN)
	# board lines + white trim outside
	for k in int(hw * 2 / 0.3):
		var x := cx - hw + k * 0.3
		if absf(x - cx) > 1.62:
			B(lv, Vector3(x, 2.0, zN - t - 0.006), Vector3(0.02, 4.0, 0.01), C_BARN.darkened(0.25), false)
		B(lv, Vector3(x, 2.0, zS + t + 0.006), Vector3(0.02, 4.0, 0.01), C_BARN.darkened(0.25), false)
	for sx in [-1.0, 1.0]:
		for k in int(hd * 2 / 0.3):
			B(lv, Vector3(cx + sx * (hw + t + 0.006), 2.0, cz - hd + k * 0.3), Vector3(0.01, 4.0, 0.02), C_BARN.darkened(0.25), false)
	# door trim: the classic white X
	X(lv, Vector3(cx - 1.75, 0, zN - t - 0.05), Vector3(0.15, 3.35, 0.05), C_TRIM, false)
	X(lv, Vector3(cx + 1.6, 0, zN - t - 0.05), Vector3(0.15, 3.35, 0.05), C_TRIM, false)
	X(lv, Vector3(cx - 1.75, 3.2, zN - t - 0.05), Vector3(3.5, 0.15, 0.05), C_TRIM, false)
	# open doors swung out to the sides, each with the X brace
	for sx in [-1.0, 1.0]:
		var dc := Vector3(cx + sx * 2.45, 1.55, zN - t - 0.9)
		B(lv, dc, Vector3(0.08, 3.1, 1.6), C_BARN)
		Level.rbox(lv, dc + Vector3(-sx * 0.05, 0, 0), Vector3(0.03, 3.3, 0.12), Vector3(0.48, 0, 0), C_TRIM, false)
		Level.rbox(lv, dc + Vector3(-sx * 0.05, 0, 0), Vector3(0.03, 3.3, 0.12), Vector3(-0.48, 0, 0), C_TRIM, false)
	# roof: gable along z, ridge at cx. stepped gable ends filled in
	var rise := ridge - wh
	var a := atan2(rise, hw + 0.3)
	var l := Vector2(hw + 0.3, rise).length()
	for sx in [-1.0, 1.0]:
		Level.rbox(lv, Vector3(cx + sx * (hw + 0.3) * 0.5, wh + rise * 0.5 + 0.08, cz), Vector3(l + 0.1, 0.14, hd * 2 + 0.8), Vector3(0, 0, -sx * a), Color(0.3, 0.3, 0.32))
	for zz in [zN - t, zS]:
		for k in 8:
			var w := hw * 2.0 * (1.0 - (k + 0.5) / 8.0)
			X(lv, Vector3(cx - w * 0.5, wh + k * rise / 8.0, zz), Vector3(w, rise / 8.0 + 0.01, t), C_BARN)
	# hay loft over the back half (z > cz), top 2.55. its edge is a beam you can grab
	var loft_y := 2.55
	X(lv, Vector3(cx - hw, loft_y - 0.12, cz), Vector3(hw * 2, 0.12, hd), C_WOOD)
	for k in int(hw * 2 / 0.25):
		B(lv, Vector3(cx - hw + 0.125 + k * 0.25, loft_y + 0.002, cz + hd * 0.5), Vector3(0.23, 0.004, hd), C_WOOD.lightened(0.04 * (k % 3)), false)
	X(lv, Vector3(cx - hw, loft_y - 0.32, cz - 0.1), Vector3(hw * 2, 0.2, 0.2), C_WOOD.darkened(0.15), false)
	# posts holding the loft (climbable, rough wood)
	for px in [-3.0, 0.0, 3.0]:
		_climb(B(lv, Vector3(cx + px, (loft_y - 0.3) * 0.5, cz - 0.05), Vector3(0.2, loft_y - 0.3, 0.2), C_WOOD.darkened(0.1)))
	# centre posts up to the ridge + tie beams across (walk the beams from the loft)
	for pz in [-hd + 1.5, hd - 1.5]:
		_climb(B(lv, Vector3(cx, ridge * 0.5, cz + pz), Vector3(0.22, ridge, 0.22), C_WOOD.darkened(0.1)))
	for bz in [-4.0, -1.5, 1.5, 4.0]:
		_climb(B(lv, Vector3(cx, 3.3, cz + bz), Vector3(hw * 2, 0.16, 0.16), C_WOOD.darkened(0.05)), false)
	B(lv, Vector3(cx, 3.3, cz), Vector3(0.16, 0.16, hd * 2), C_WOOD.darkened(0.05))   # spine beam
	# ladder up to the loft (climb it)
	var lx := cx - 1.6
	var lad := Level.box(lv, Vector3(lx, loft_y * 0.5, cz - 0.15), Vector3(0.5, loft_y, 0.08), C_WOOD, true, 0.0, false)
	_climb(lad, false)
	for sx in [-0.22, 0.22]:
		B(lv, Vector3(lx + sx, (loft_y + 0.5) * 0.5, cz - 0.15), Vector3(0.05, loft_y + 0.5, 0.06), C_WOOD.darkened(0.1), false)
	for k in int(loft_y / 0.28):
		B(lv, Vector3(lx, 0.28 * (k + 1), cz - 0.15), Vector3(0.44, 0.035, 0.035), C_WOOD.lightened(0.05), false)
	# hay bales: stepped stack in the front right corner up to the loft, all scratchable/climbable
	var stack := [
		[0, Vector3(3.2, 0, -4.8)], [0, Vector3(4.2, 0, -4.8)], [0, Vector3(3.2, 0, -4.3)], [0, Vector3(4.2, 0, -4.3)],
		[0, Vector3(4.2, 0, -3.3)], [0, Vector3(4.2, 0, -2.3)], [0, Vector3(4.2, 0, -1.3)],
		[1, Vector3(4.2, 0.35, -4.8)], [1, Vector3(4.2, 0.35, -3.3)], [1, Vector3(4.2, 0.35, -2.3)], [1, Vector3(4.2, 0.35, -1.3)],
		[2, Vector3(4.2, 0.7, -2.3)], [2, Vector3(4.2, 0.7, -1.3)], [2, Vector3(4.2, 0.7, -0.8)],
		[3, Vector3(4.2, 1.05, -1.3)], [3, Vector3(4.2, 1.05, -0.8)],
		[4, Vector3(4.2, 1.4, -0.8)],
		[0, Vector3(4.2, 0, -0.35)], [1, Vector3(4.2, 0.35, -0.35)], [2, Vector3(4.2, 0.7, -0.35)], [3, Vector3(4.2, 1.05, -0.35)], [4, Vector3(4.2, 1.4, -0.35)],
		[5, Vector3(4.2, 1.75, -0.55)],
	]
	for s in stack:
		_bale(lv, c + s[1], rng)
	# bales up on the loft too + loose straw
	for k in 6:
		_bale(lv, c + Vector3(-5.0 + k * 0.95, loft_y, 4.6), rng)
	for k in 3:
		_bale(lv, c + Vector3(-5.0 + k * 0.95, loft_y + 0.35, 4.6), rng)
	_bale(lv, c + Vector3(-5.0, loft_y + 0.7, 4.6), rng)
	# stalls along the west wall: partitions you can walk along the top of
	for k in 4:
		var pz := cz - hd + 0.6 + k * 1.6
		X(lv, Vector3(cx - hw, 0, pz), Vector3(2.2, 1.3, 0.06), C_WOOD)
		X(lv, Vector3(cx - hw, 1.3, pz - 0.02), Vector3(2.2, 0.04, 0.1), C_WOOD.darkened(0.1))
	X(lv, Vector3(cx - hw + 0.2, 0, cz - hd + 0.8), Vector3(0.5, 0.45, 1.2), Color(0.5, 0.52, 0.55))   # trough
	B(lv, Vector3(cx - hw + 0.45, 0.43, cz - hd + 1.4), Vector3(0.4, 0.01, 1.1), Color(0.4, 0.55, 0.7), false)
	# barrels (heavy, swats barely rock them), buckets + crates
	for p in [Vector3(-2.6, 0, -5.2), Vector3(-2.0, 0, -5.3), Vector3(-2.3, 0, -4.7)]:
		_barrel(lv, c + p)
	for p in [Vector3(1.8, 0, -1.0), Vector3(2.3, 0, -0.6)]:
		_bucket(lv, c + p, Color(0.55, 0.57, 0.6))
	X(lv, c + Vector3(1.4, 0, 3.4), Vector3(0.7, 0.6, 0.7), Color(0.6, 0.45, 0.3))
	X(lv, c + Vector3(1.5, 0.6, 3.5), Vector3(0.5, 0.5, 0.5), Color(0.65, 0.5, 0.33))
	# workbench + tools
	X(lv, c + Vector3(3.0, 0, 5.2), Vector3(2.4, 0.9, 0.6), C_WOOD)
	Level.mug(lv, c + Vector3(3.4, 0.9, 5.4), Color(0.25, 0.3, 0.25))
	_can(lv, c + Vector3(4.2, 0.9, 5.45))
	_can(lv, c + Vector3(4.5, 0.9, 5.4))
	_book(lv, c + Vector3(3.8, 0.9, 5.4), Color(0.7, 0.2, 0.2))
	# a rope hanging from a beam (climbable)
	var rope := B(lv, c + Vector3(-1.5, 1.95, -1.5), Vector3(0.05, 2.7, 0.05), Color(0.8, 0.7, 0.5))
	_climb(rope)
	# feed sacks (soft, scratchable)
	for k in 3:
		var sk := X(lv, c + Vector3(-1.0 + k * 0.55, 0, 5.3), Vector3(0.5, 0.6, 0.35), Color(0.85, 0.8, 0.65))
		sk.add_to_group("scratchable")
	# light: open hatch + bulbs
	_light(lv, c + Vector3(0, 3.0, -2.5), 1.1, 9.0, Color(1.0, 0.85, 0.6))
	_light(lv, c + Vector3(0, 3.0, 3.0), 0.8, 7.0, Color(1.0, 0.85, 0.6))
	for p in [Vector3(1.0, 1.0, 4.0), Vector3(-2.0, loft_y + 0.02, 3.0)]:
		var tm := ToyMouse.new()
		tm.position = c + p + Vector3(0, 0.02, 0)
		lv.add_child(tm)


static func _bale(lv: Node3D, minc: Vector3, rng: RandomNumberGenerator) -> void:
	var col := C_HAY.lightened(rng.randf() * 0.06).darkened(rng.randf() * 0.08)
	var b := X(lv, minc, Vector3(0.9, 0.35, 0.45), col)
	_climb(b)
	b.set_meta("surface", "hay")
	# twine bands
	for k in 2:
		B(lv, minc + Vector3(0.25 + k * 0.4, 0.175, 0.225), Vector3(0.015, 0.36, 0.46), C_HAY.darkened(0.3), false)


static func _light(lv: Node3D, p: Vector3, e: float, r: float, col := Color(1.0, 0.85, 0.65)) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = col
	l.light_energy = e
	l.omni_range = r
	l.light_volumetric_fog_energy = 0.0
	lv.add_child(l)
	LowPoly.part(lv, LowPoly.sphere(6, 4), Color(1.0, 0.95, 0.8), p + Vector3(0, 0.15, 0), Vector3.ONE * 0.12, Vector3.ZERO, 1.5)


static func _treat(lv: Node3D, p: Vector3) -> void:
	var fish := Node3D.new()
	fish.position = p
	lv.add_child(fish)
	LowPoly.part(fish, LowPoly.sphere(6, 4), Color(1.0, 0.65, 0.25), Vector3.ZERO, Vector3(0.05, 0.04, 0.11), Vector3.ZERO, 0.8)
	LowPoly.part(fish, LowPoly.cone(3), Color(1.0, 0.65, 0.25), Vector3(0, 0, 0.07), Vector3(0.05, 0.04, 0.03), Vector3(PI / 2, 0, 0), 0.8)


# ---------------------------------------------------------------- loose props (swat / grab)

static func _rb(lv: Node3D, pos: Vector3, mass: float, shape: Shape3D) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = mass
	var cs := CollisionShape3D.new()
	cs.shape = shape
	rb.add_child(cs)
	rb.position = pos
	rb.can_sleep = true
	lv.add_child(rb)
	return rb


static func _book(lv: Node3D, pos: Vector3, col: Color) -> void:
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.15, 0.03, 0.21)
	var rb := _rb(lv, pos + Vector3(0, 0.016, 0), 0.35, bs)
	LowPoly.part(rb, LowPoly.box(), col, Vector3.ZERO, bs.size)
	LowPoly.part(rb, LowPoly.box(0.0), Color(0.95, 0.93, 0.88), Vector3(0.006, 0, 0), bs.size - Vector3(0.006, 0.006, 0.01))


static func _pencil(lv: Node3D, pos: Vector3) -> void:
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.008, 0.008, 0.17)
	var rb := _rb(lv, pos, 0.006, bs)
	LowPoly.part(rb, LowPoly.box(), Color(0.95, 0.8, 0.2), Vector3.ZERO, bs.size)
	LowPoly.part(rb, LowPoly.cone(4), Color(0.9, 0.75, 0.6), Vector3(0, 0, -0.09), Vector3(0.008, 0.016, 0.008), Vector3(-PI / 2, 0, 0))


static func _ball(lv: Node3D, pos: Vector3, col: Color, r: float) -> void:
	var sh := SphereShape3D.new()
	sh.radius = r
	var rb := _rb(lv, pos + Vector3(0, r, 0), 0.06 if r < 0.06 else 0.3, sh)
	rb.physics_material_override = PhysicsMaterial.new()
	rb.physics_material_override.bounce = 0.55
	rb.angular_damp = 0.4
	LowPoly.part(rb, LowPoly.sphere(8, 6), col, Vector3.ZERO, Vector3.ONE * r * 2.0)


static func _pot(lv: Node3D, pos: Vector3) -> void:
	var cy := CylinderShape3D.new()
	cy.radius = 0.07
	cy.height = 0.13
	var rb := _rb(lv, pos + Vector3(0, 0.066, 0), 0.8, cy)
	LowPoly.part(rb, LowPoly.cyl(0.075, 0.055, 8), Color(0.75, 0.42, 0.3), Vector3.ZERO, Vector3(1, 0.13, 1))
	for k in 3:
		var a := k * TAU / 3.0
		LowPoly.part(rb, LowPoly.cone(4), C_LEAF.lightened(0.1 * k), Vector3(cos(a) * 0.02, 0.12, sin(a) * 0.02), Vector3(0.04, 0.14, 0.02), Vector3(sin(a) * 0.4, -a, -cos(a) * 0.4))


static func _bucket(lv: Node3D, pos: Vector3, col: Color) -> void:
	var cy := CylinderShape3D.new()
	cy.radius = 0.13
	cy.height = 0.26
	var rb := _rb(lv, pos + Vector3(0, 0.131, 0), 1.0, cy)
	LowPoly.part(rb, LowPoly.cyl(0.14, 0.11, 10), col, Vector3.ZERO, Vector3(1, 0.26, 1))
	LowPoly.part(rb, LowPoly.cyl(0.125, 0.125, 10), col.darkened(0.4), Vector3(0, 0.125, 0), Vector3(1, 0.01, 1))


static func _barrel(lv: Node3D, pos: Vector3) -> void:
	var cy := CylinderShape3D.new()
	cy.radius = 0.28
	cy.height = 0.85
	var rb := _rb(lv, pos + Vector3(0, 0.426, 0), 25.0, cy)
	LowPoly.part(rb, LowPoly.cyl(0.27, 0.27, 10), Color(0.5, 0.34, 0.2), Vector3.ZERO, Vector3(1, 0.85, 1))
	for y in [-0.3, 0.3]:
		LowPoly.part(rb, LowPoly.cyl(0.285, 0.285, 10), Color(0.3, 0.3, 0.32), Vector3(0, y, 0), Vector3(1, 0.04, 1))


static func _can(lv: Node3D, pos: Vector3) -> void:
	var cy := CylinderShape3D.new()
	cy.radius = 0.035
	cy.height = 0.12
	var rb := _rb(lv, pos + Vector3(0, 0.061, 0), 0.25, cy)
	LowPoly.part(rb, LowPoly.cyl(0.035, 0.035, 8), Color(0.7, 0.2, 0.15), Vector3.ZERO, Vector3(1, 0.12, 1))
