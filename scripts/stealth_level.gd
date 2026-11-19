class_name StealthLevel
extends RefCounted
## "pier 9 pump house": an original night time dockside industrial level, psx style.
## built at real scale (meters) as a cat parkour playground:
##   hall: crate stairs, pallet rack, pipe runs, wall kick shaft into a crawl duct,
##         catwalk + raised control office, storage cage (chain link = climbable),
##         crawl gaps (roll up door, inspection deck), overhead i-beams
##   dock: shipping container stacks, guard hut, bollards, climbable crane leg, rain, sea

const HALL_X := 12.0
const HALL_N := -10.0
const HALL_S := 6.0
const HALL_H := 7.0
const CATWALK_Y := 2.6
const BEAM_Y := 4.6
const DUCT_Y := 4.0

# palette (tints over the tiny textures)
const T_CONC := Color(0.78, 0.78, 0.8)
const T_WALL := Color(0.55, 0.62, 0.62)
const T_STEEL := Color(0.62, 0.66, 0.7)
const T_YEL := Color(0.95, 0.78, 0.25)
const T_PIPE := Color(0.45, 0.55, 0.5)
const T_PIPE_R := Color(0.7, 0.32, 0.25)
const T_OLIVE := Color(0.5, 0.55, 0.38)

static var lv: Node3D
static var lights: Array[Light3D] = []
static var beacons: Array[Node3D] = []
static var blinkers: Array[Node3D] = []
static var sweepers: Array[Node3D] = []


# ------------------------------------------------------------------ helpers
## the dark puddles on the pier (xz rects): splashy underfoot
const PUDDLES := [Rect2(-3.8, 8.45, 1.6, 1.1), Rect2(3.7, 11.95, 1.6, 1.1), Rect2(-12.8, 15.45, 1.6, 1.1), Rect2(13.2, 8.95, 1.6, 1.1)]


static func box(center: Vector3, size: Vector3, kind: String, tint := Color.WHITE, collide := true, density := 1.0, rot_y := 0.0, groups: Array = [], emission := 0.0, parent: Node = null) -> Node3D:
	var node: Node3D
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		sb.set_meta("surface", kind)     # what the cat walks on: steps + how loud it is (puzzle_dog.gd)
		node = sb
	else:
		node = Node3D.new()
	node.position = center
	node.rotation.y = rot_y
	(parent if parent else lv).add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = PSX.box_mesh(size, density, 1.2, center.y if rot_y == 0.0 else -100.0, hash(center))
	var m := PSX.mat(kind, tint, emission, {"cutout": true} if kind in ["grate", "chainlink"] else {})
	mi.material_override = m
	if kind in ["grate", "chainlink"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	for g in groups:
		node.add_to_group(g)
	return node


## box from min corner + size
static func bx(minc: Vector3, size: Vector3, kind: String, tint := Color.WHITE, collide := true, density := 1.0, groups: Array = []) -> Node3D:
	return box(minc + size * 0.5, size, kind, tint, collide, density, 0.0, groups)


## cylinder. axis: "y" upright, "x" or "z" lying along that axis
static func cyl(center: Vector3, radius: float, length: float, kind: String, tint := Color.WHITE, axis := "y", collide := true, segs := 8, groups: Array = []) -> Node3D:
	var node: Node3D
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = length
		cs.shape = sh
		sb.add_child(cs)
		node = sb
	else:
		node = Node3D.new()
	node.position = center
	if axis == "x":
		node.rotation.z = PI / 2
	elif axis == "z":
		node.rotation.x = PI / 2
	lv.add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = PSX.cyl_mesh(radius, length, segs, 2.0)
	mi.material_override = PSX.mat(kind, tint)
	node.add_child(mi)
	for g in groups:
		node.add_to_group(g)
	return node


static func omni(pos: Vector3, col: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadow
	l.light_specular = 0.0
	lv.add_child(l)
	lights.append(l)
	return l


## hanging industrial lamp: cable, conical shade, glowing bulb + light
static func hang_lamp(pos: Vector3, col: Color, energy := 2.2, rng := 9.0, cable := 1.0, shadow := false) -> void:
	box(pos + Vector3(0, cable * 0.5 + 0.12, 0), Vector3(0.015, cable, 0.015), "rubber", Color.WHITE, false)
	var shade := MeshInstance3D.new()
	shade.mesh = PSX.cyl_mesh(0.28, 0.2, 8, 3.0, false)
	shade.material_override = PSX.mat("metal", Color(0.3, 0.38, 0.32))
	shade.position = pos + Vector3(0, 0.08, 0)
	shade.scale = Vector3(1, 1, 1)
	lv.add_child(shade)
	box(pos + Vector3(0, 0.17, 0), Vector3(0.2, 0.04, 0.2), "metal", Color(0.3, 0.38, 0.32), false)
	box(pos + Vector3(0, -0.02, 0), Vector3(0.14, 0.1, 0.14), "light", col, false, 1.0, 0.0, [], 3.0)
	omni(pos + Vector3(0, -0.25, 0), col, energy, rng, shadow)


static func crate(pos: Vector3, s: float, rot := 0.0, tint := Color.WHITE) -> Node3D:
	return box(pos + Vector3(0, s * 0.5, 0), Vector3(s, s, s), "crate", tint, true, 1.6 / s * 0.5 + 0.8, rot)


static func cardboard(pos: Vector3, size: Vector3, rot := 0.0) -> Node3D:
	return box(pos + Vector3(0, size.y * 0.5, 0), size, "cardboard", Color.WHITE, true, 1.0 / maxf(size.x, size.z), rot)


static func drum(pos: Vector3, tint: Color) -> void:
	cyl(pos + Vector3(0, 0.44, 0), 0.29, 0.88, "rust", tint, "y", true, 10)
	# rolling hoops
	for y in [0.3, 0.6]:
		cyl(pos + Vector3(0, y, 0), 0.3, 0.03, "metal", tint.darkened(0.3), "y", false, 10)


static func pallet(pos: Vector3, rot := 0.0) -> void:
	box(pos + Vector3(0, 0.07, 0), Vector3(1.2, 0.14, 1.0), "wood", Color(0.85, 0.75, 0.6), true, 2.0, rot)


static func rail(a: Vector3, b: Vector3, h := 1.0) -> void:
	# catwalk railing: posts + top + mid rail. the gap under the mid rail is cat sized
	var d := b - a
	var len := d.length()
	var n := maxi(1, ceili(len / 1.5))
	for i in n + 1:
		var p := a + d * float(i) / n
		box(p + Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.05), "metal", T_YEL)
	var mid := (a + b) * 0.5
	var sz := Vector3(len if absf(d.x) > absf(d.z) else 0.05, 0.05, len if absf(d.z) >= absf(d.x) else 0.05)
	box(mid + Vector3(0, h, 0), sz, "metal", T_YEL)
	box(mid + Vector3(0, h * 0.5, 0), Vector3(sz.x, 0.03, sz.z), "metal", T_YEL)


static func ibeam(z: float, y_top: float, x0: float, x1: float) -> void:
	var len := x1 - x0
	var cx := (x0 + x1) * 0.5
	box(Vector3(cx, y_top - 0.02, z), Vector3(len, 0.04, 0.2), "rust", Color(0.8, 0.75, 0.7), true, 1.5)
	box(Vector3(cx, y_top - 0.22, z), Vector3(len, 0.36, 0.03), "rust", Color(0.8, 0.75, 0.7), true, 1.5)
	box(Vector3(cx, y_top - 0.42, z), Vector3(len, 0.04, 0.2), "rust", Color(0.8, 0.75, 0.7), true, 1.5)


static func chainlink(center: Vector3, size: Vector3) -> void:
	# visual mesh fence + invisible climbable collider
	var mi := MeshInstance3D.new()
	var horiz := size.x > size.z
	mi.mesh = PSX.quad_mesh(Vector2(size.x if horiz else size.z, size.y), 2.0)
	mi.material_override = PSX.mat("chainlink", Color.WHITE, 0.0, {"cutout": true})
	mi.position = center
	if not horiz:
		mi.rotation.y = PI / 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lv.add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(size.x, 0.04), size.y, maxf(size.z, 0.04))
	cs.shape = bs
	sb.add_child(cs)
	sb.position = center
	sb.add_to_group("climbable")
	sb.add_to_group("scratchable")
	lv.add_child(sb)
	# frame posts + top pipe
	var a := center - Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.5)
	var len := size.x if horiz else size.z
	var n := maxi(1, ceili(len / 2.5))
	for i in n + 1:
		var p := a + (Vector3(len * i / n, 0, 0) if horiz else Vector3(0, 0, len * i / n))
		cyl(p + Vector3(0, size.y * 0.5, 0), 0.03, size.y, "metal", T_STEEL, "y", true, 6)
	cyl(center + Vector3(0, size.y * 0.5, 0), 0.025, len, "metal", T_STEEL, "x" if horiz else "z", true, 6)


static func wall_sign(pos: Vector3, rot_y: float, kind := "sign", size := Vector2(0.4, 0.4), emission := 0.3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = PSX.quad_mesh(size, 1.0 / size.x)
	mi.material_override = PSX.mat(kind, Color.WHITE, emission)
	mi.position = pos
	mi.rotation.y = rot_y
	lv.add_child(mi)


static func container(center_bottom: Vector3, tint: Color, rot := 0.0) -> Node3D:
	# 20 ft box: 6.06 x 2.59 x 2.44
	var size := Vector3(6.06, 2.59, 2.44)
	var c := box(center_bottom + Vector3(0, size.y * 0.5, 0), size, "container", tint, true, 0.5, rot)
	# corner castings + door bars (visual only, they ride along with the container node)
	for sx in [-1, 1]:
		for sy in [0, 1]:
			for sz in [-1, 1]:
				box(Vector3(sx * 2.98, -1.2 + sy * 2.4, sz * 1.17), Vector3(0.12, 0.14, 0.12), "metal", Color(0.3, 0.3, 0.3), false, 1.0, 0.0, [], 0.0, c)
	for k in 4:
		box(Vector3(3.04, 0, -0.9 + k * 0.6), Vector3(0.03, 2.3, 0.04), "metal", tint.darkened(0.3), false, 1.0, 0.0, [], 0.0, c)
	return c


# ------------------------------------------------------------------ build
static func build(root: Node3D) -> Dictionary:
	lights.clear()
	beacons.clear()
	blinkers.clear()
	sweepers.clear()
	lv = Node3D.new()
	lv.name = "StealthLevel"
	root.add_child(lv)
	_hall()
	_crate_stairs()
	_rack()
	_pipes()
	_shaft_and_duct()
	_catwalk_and_office()
	_cage()
	_hall_props()
	_dock()
	_backdrop()
	return {
		"spawn": Vector3(-8.5, 0.02, 3.5),
		"spawn_yaw": -0.5,
		# quick teleports for testing (keys 1-7)
		"points": [
			["hall", Vector3(-8.5, 0.02, 3.5), -0.5],
			["crate stairs", Vector3(-7.0, 0.02, -3.6), 0.0],
			["pallet rack", Vector3(-1.0, 0.02, -2.6), 0.0],
			["wall kick shaft", Vector3(11.6, 0.02, 3.0), 0.0],
			["control office", Vector3(8.0, CATWALK_Y + 0.02, -8.0), -PI / 2],
			["dock containers", Vector3(-6.0, 0.02, 9.0), 1.2],
			["crane", Vector3(10.0, 0.02, 18.0), 0.0],
		],
	}


static func _hall() -> void:
	var w := HALL_X * 2.0
	var d := HALL_S - HALL_N
	var cz := (HALL_S + HALL_N) * 0.5
	# floor: concrete slabs, extends out under the dock
	box(Vector3(0, -0.1, cz), Vector3(w + 0.4, 0.2, d + 0.4), "concrete_slab", T_CONC, true, 0.25)
	# hazard strip down the middle aisle
	box(Vector3(0, 0.003, cz), Vector3(0.15, 0.006, d - 1.0), "hazard", Color.WHITE, false, 2.0)
	box(Vector3(-1.9, 0.003, cz), Vector3(0.1, 0.006, d - 1.0), "paint", T_YEL, false)
	box(Vector3(1.9, 0.003, cz), Vector3(0.1, 0.006, d - 1.0), "paint", T_YEL, false)
	# walls (corrugated), lower 1.2 m is concrete block
	for side in [-1, 1]:
		var x: float = side * (HALL_X + 0.1)
		box(Vector3(x, HALL_H * 0.5 + 0.6, cz), Vector3(0.2, HALL_H - 1.2, d + 0.4), "corrugated", T_WALL, true, 0.6)
		box(Vector3(x, 0.6, cz), Vector3(0.24, 1.2, d + 0.4), "brick", Color(0.75, 0.75, 0.78), true, 1.0)
	box(Vector3(0, HALL_H * 0.5 + 0.6, HALL_N - 0.1), Vector3(w + 0.4, HALL_H - 1.2, 0.2), "corrugated", T_WALL, true, 0.6)
	box(Vector3(0, 0.6, HALL_N - 0.1), Vector3(w + 0.4, 1.2, 0.24), "brick", Color(0.75, 0.75, 0.78), true, 1.0)
	# south wall with a roll up door (x -2..2, stuck 0.22 m open = cat crawl gap)
	# and a personnel door (x 6..7)
	var s := HALL_S + 0.1
	box(Vector3(-7.0, HALL_H * 0.5, s), Vector3(10.4, HALL_H, 0.2), "corrugated", T_WALL, true, 0.6)
	box(Vector3(4.0, HALL_H * 0.5, s), Vector3(4.0, HALL_H, 0.2), "corrugated", T_WALL, true, 0.6)
	box(Vector3(9.6, HALL_H * 0.5, s), Vector3(5.2, HALL_H, 0.2), "corrugated", T_WALL, true, 0.6)
	box(Vector3(6.5, (2.1 + HALL_H) * 0.5, s), Vector3(1.0, HALL_H - 2.1, 0.2), "corrugated", T_WALL, true, 0.6)
	box(Vector3(0, (4.2 + HALL_H) * 0.5, s), Vector3(4.0, HALL_H - 4.2, 0.2), "corrugated", T_WALL, true, 0.6)
	# roll up door: slats from 0.22 up to 4.2
	box(Vector3(0, (0.22 + 4.2) * 0.5, s), Vector3(4.0, 4.2 - 0.22, 0.12), "corrugated", Color(0.6, 0.5, 0.35), true, 0.8)
	box(Vector3(0, 0.25, s), Vector3(4.0, 0.06, 0.16), "hazard", Color.WHITE, false, 2.0)
	box(Vector3(0, 4.35, s - 0.25), Vector3(4.4, 0.4, 0.4), "metal", T_STEEL) # roller housing
	# door frames
	for x in [6.0, 7.0]:
		box(Vector3(x, 1.05, s), Vector3(0.08, 2.1, 0.26), "metal", T_YEL, false)
	box(Vector3(6.5, 2.1, s), Vector3(1.08, 0.08, 0.26), "metal", T_YEL, false)
	# roof + skylights
	box(Vector3(0, HALL_H + 0.1, cz), Vector3(w + 0.4, 0.2, d + 0.4), "corrugated", Color(0.35, 0.38, 0.4), true, 0.5)
	for z in [-6.0, -1.0, 4.0]:
		box(Vector3(0, HALL_H - 0.01, z), Vector3(10.0, 0.02, 1.4), "grate", Color(0.4, 0.55, 0.7), false, 3.0, 0.0, [], 0.5)
	# roof trusses (visual) + columns
	for z in [-8.0, -3.5, 1.0, 5.0]:
		box(Vector3(0, HALL_H - 0.35, z), Vector3(w, 0.15, 0.15), "rust", T_STEEL, false, 1.0)
	for x in [-HALL_X + 0.15, HALL_X - 0.15]:
		for z in [-4.5, 1.5]:
			box(Vector3(x, HALL_H * 0.5, z), Vector3(0.3, HALL_H, 0.3), "metal", T_YEL)
	# overhead i-beams (cat highway, 0.2 m wide top flange)
	for z in [-6.5, -2.5, 1.5]:
		ibeam(z, BEAM_Y, -HALL_X, HALL_X)
		hang_lamp(Vector3(-6.0, BEAM_Y - 1.6, z), Color(1.0, 0.86, 0.6), 2.4, 10.0, 1.1, z == -2.5)
		hang_lamp(Vector3(6.0, BEAM_Y - 1.6, z), Color(0.75, 1.0, 0.8), 1.8, 9.0, 1.1)
	# stencil numbers / hazard bands on columns
	for x in [-HALL_X + 0.32, HALL_X - 0.32]:
		for z in [-4.5, 1.5]:
			box(Vector3(x, 0.6, z), Vector3(0.04, 1.2, 0.32), "hazard", Color.WHITE, false, 3.0)


## crates rising to the north catwalk: 0.6 -> 1.2 -> 1.8 -> catwalk 2.6
static func _crate_stairs() -> void:
	crate(Vector3(-7.0, 0, -4.6), 0.6, 0.1)
	crate(Vector3(-7.1, 0, -5.6), 1.2, -0.05)
	crate(Vector3(-7.0, 0, -6.9), 1.2, 0.0)
	crate(Vector3(-7.0, 1.2, -7.0), 0.6, 0.15)
	crate(Vector3(-5.8, 0, -7.2), 1.2, 0.0, Color(0.8, 0.85, 0.9))
	cardboard(Vector3(-6.2, 0, -4.4), Vector3(0.4, 0.3, 0.3), 0.4)
	cardboard(Vector3(-6.3, 0.3, -4.45), Vector3(0.3, 0.25, 0.3), 0.1)
	pallet(Vector3(-4.6, 0, -7.6))
	cardboard(Vector3(-4.8, 0.14, -7.6), Vector3(0.5, 0.45, 0.5), 0.05)
	cardboard(Vector3(-4.3, 0.14, -7.5), Vector3(0.45, 0.6, 0.45), -0.1)
	cardboard(Vector3(-4.75, 0.59, -7.55), Vector3(0.4, 0.4, 0.4), 0.3)


## pallet rack: levels at 1.3 / 2.6 / 3.9, reach the i-beam at 4.6 from the top
static func _rack() -> void:
	var x0 := -3.0
	var x1 := 3.0
	var z0 := -5.5
	var z1 := -4.5
	for x in [x0, 0.0, x1]:
		for z in [z0, z1]:
			box(Vector3(x, 2.0, z), Vector3(0.08, 4.0, 0.08), "metal", Color(0.3, 0.45, 0.75))
		# x bracing on the ends
		box(Vector3(x, 1.0, (z0 + z1) * 0.5), Vector3(0.03, 0.03, 1.0), "metal", Color(0.3, 0.45, 0.75), false)
		box(Vector3(x, 3.0, (z0 + z1) * 0.5), Vector3(0.03, 0.03, 1.0), "metal", Color(0.3, 0.45, 0.75), false)
	for y in [1.3, 2.6, 3.9]:
		box(Vector3(0, y - 0.06, z0), Vector3(6.1, 0.12, 0.06), "metal", Color(0.95, 0.5, 0.15))
		box(Vector3(0, y - 0.06, z1), Vector3(6.1, 0.12, 0.06), "metal", Color(0.95, 0.5, 0.15))
		box(Vector3(0, y - 0.025, (z0 + z1) * 0.5), Vector3(6.0, 0.05, 0.94), "grate", Color(0.8, 0.8, 0.8), true, 3.0)
	# stock on the shelves (gaps left so the cat can get up)
	pallet(Vector3(-2.2, 0, -5.0))
	cardboard(Vector3(-2.4, 0.14, -5.0), Vector3(0.6, 0.6, 0.6))
	cardboard(Vector3(-1.8, 0.14, -5.1), Vector3(0.4, 0.4, 0.5), 0.2)
	drum(Vector3(1.0, 0, -4.0), Color(0.3, 0.45, 0.65))
	drum(Vector3(1.65, 0, -3.85), Color(0.75, 0.3, 0.2))
	cardboard(Vector3(2.2, 1.3, -5.0), Vector3(0.6, 0.55, 0.7))
	crate(Vector3(-1.2, 1.3, -5.0), 0.7)
	pallet(Vector3(-2.3, 2.6, -5.0))
	cardboard(Vector3(-2.5, 2.74, -5.0), Vector3(0.5, 0.7, 0.6), 0.1)
	crate(Vector3(1.5, 2.6, -5.0), 0.6, 0.2)
	cardboard(Vector3(-0.6, 3.9, -5.1), Vector3(0.5, 0.35, 0.5), -0.2)
	wall_sign(Vector3(0, 0.9, -4.42), 0.0, "sign", Vector2(0.35, 0.35))


## pipe runs along the west wall: 0.45 / 1.05 / 1.65 m, then the catwalk at 2.6
static func _pipes() -> void:
	var x := -HALL_X + 0.35
	for i in 3:
		var y := 0.45 + i * 0.6
		cyl(Vector3(x - i * 0.06, y, -2.5), 0.12, 11.0, "metal", [T_PIPE, T_PIPE_R, Color(0.75, 0.75, 0.7)][i], "z", true, 8)
		# flanges every 2 m
		for k in 6:
			cyl(Vector3(x - i * 0.06, y, -7.5 + k * 2.0), 0.15, 0.06, "metal", Color(0.4, 0.4, 0.4), "z", false, 8)
	# brackets
	for k in 4:
		box(Vector3(-HALL_X + 0.2, 1.0, -7.0 + k * 3.0), Vector3(0.3, 2.0, 0.06), "rust", T_STEEL, false)
	# valve wheels
	for z in [-5.0, 0.5]:
		cyl(Vector3(x + 0.18, 1.05, z), 0.03, 0.2, "metal", Color(0.5, 0.5, 0.5), "x", false, 6)
		var wheel := cyl(Vector3(x + 0.3, 1.05, z), 0.13, 0.03, "metal", Color(0.85, 0.15, 0.12), "x", false, 8)
	# vertical lagged (insulated) pipe: fabric wrapped = claws go in, climb it
	cyl(Vector3(-HALL_X + 0.35, 3.0, 3.4), 0.13, 6.0, "fabric", Color(0.85, 0.82, 0.72), "y", true, 8, ["climbable", "scratchable"])
	for k in 10:
		cyl(Vector3(-HALL_X + 0.35, 0.3 + k * 0.6, 3.4), 0.14, 0.03, "metal", Color(0.6, 0.6, 0.6), "y", false, 8)
	# gauge panel
	box(Vector3(-HALL_X + 0.05, 1.7, 0.5), Vector3(0.06, 0.6, 0.8), "metal", T_OLIVE, false)
	box(Vector3(-HALL_X + 0.1, 1.75, 0.3), Vector3(0.02, 0.18, 0.18), "paint", Color.WHITE, false, 1.0, 0.0, [], 0.3)
	box(Vector3(-HALL_X + 0.1, 1.75, 0.7), Vector3(0.02, 0.18, 0.18), "paint", Color.WHITE, false, 1.0, 0.0, [], 0.3)


## wall kick shaft on the east wall (0.6 m wide, 4 m tall) into an overhead crawl duct
## that runs north and drops into the control office
static func _shaft_and_duct() -> void:
	var inner := HALL_X - 0.6  # free wall face
	box(Vector3(inner - 0.1, DUCT_Y * 0.5, 1.2), Vector3(0.2, DUCT_Y, 1.6), "concrete", Color(0.7, 0.7, 0.72), true, 1.0)
	box(Vector3(inner - 0.1, 0.6, 1.2), Vector3(0.21, 1.2, 1.61), "hazard", Color.WHITE, false, 2.0)
	wall_sign(Vector3(inner - 0.21, 1.8, 1.2), -PI / 2, "sign", Vector2(0.3, 0.3))
	# duct: floor, roof, inner wall, from the top of the shaft north to the office
	var z0 := 0.4
	var z1 := -6.35
	var dz := (z0 + z1) * 0.5
	var dl := z0 - z1
	var x0 := inner - 0.2
	var x1 := HALL_X
	var dw := x1 - x0
	box(Vector3((x0 + x1) * 0.5, DUCT_Y - 0.03, dz), Vector3(dw, 0.06, dl), "metal", T_STEEL, true, 2.0)
	box(Vector3((x0 + x1) * 0.5, DUCT_Y + 0.47, dz), Vector3(dw, 0.06, dl + 0.0), "metal", T_STEEL, true, 2.0)
	box(Vector3(x0 + 0.03, DUCT_Y + 0.22, dz), Vector3(0.06, 0.44, dl), "metal", T_STEEL, true, 2.0)
	# the duct starts right over the shaft: lip at the shaft top
	box(Vector3((x0 + x1) * 0.5, DUCT_Y + 0.22, 1.98), Vector3(dw, 0.5, 0.04), "grate", Color.WHITE, false, 4.0)
	# hangers + vent slats
	for k in 4:
		var z := z0 - 1.0 - k * 1.6
		box(Vector3(x0 + 0.15, (DUCT_Y + 0.5 + HALL_H) * 0.5, z), Vector3(0.03, HALL_H - DUCT_Y - 0.5, 0.03), "metal", T_STEEL, false)
		box(Vector3(x0 - 0.005, DUCT_Y + 0.22, z), Vector3(0.02, 0.3, 0.4), "grate", Color(0.2, 0.2, 0.2), false, 6.0)
	omni(Vector3(HALL_X - 0.3, DUCT_Y + 0.25, -2.5), Color(0.5, 0.7, 1.0), 0.4, 2.5)


## north catwalk (2.6 m) from the crate stairs to the raised control office in the NE corner
static func _catwalk_and_office() -> void:
	var y := CATWALK_Y
	var cz0 := HALL_N
	var cz1 := HALL_N + 1.2
	var cx0 := -HALL_X
	var cx1 := 6.0
	box(Vector3((cx0 + cx1) * 0.5, y - 0.03, (cz0 + cz1) * 0.5), Vector3(cx1 - cx0, 0.06, cz1 - cz0), "grate", Color.WHITE, true, 4.0)
	box(Vector3((cx0 + cx1) * 0.5, y - 0.1, cz1), Vector3(cx1 - cx0, 0.14, 0.06), "metal", T_YEL)
	rail(Vector3(cx0 + 0.6, y, cz1 - 0.03), Vector3(-7.9, y, cz1 - 0.03))
	rail(Vector3(-6.1, y, cz1 - 0.03), Vector3(4.2, y, cz1 - 0.03))
	for x in [-9.0, -3.0, 3.0]:
		box(Vector3(x, y * 0.5, cz1 - 0.1), Vector3(0.12, y, 0.12), "metal", T_YEL)
	# stairs down to the floor (x 4.4..5.6), 0.2 m risers
	var steps := 13
	for i in steps:
		var top := (i + 1) * (y / steps)
		var z := cz1 + (steps - i) * 0.3 - 0.15
		box(Vector3(5.0, top * 0.5, z), Vector3(1.2, top, 0.3), "tread", Color(0.8, 0.8, 0.8), true, 3.0)
	box(Vector3(5.0, y - 0.03, cz0 + 0.6), Vector3(1.2, 0.06, 1.2), "tread", Color.WHITE, true, 3.0)
	rail(Vector3(4.37, 0, cz1 + steps * 0.3), Vector3(4.37, 0, cz1 + 0.3), 1.0)
	# office: floor slab x 6..12, z -10..-6 on columns
	var ox0 := 6.0
	var ox1 := HALL_X
	var oz0 := HALL_N
	var oz1 := -6.0
	var ocx := (ox0 + ox1) * 0.5
	var ocz := (oz0 + oz1) * 0.5
	var top := 5.0
	box(Vector3(ocx, y - 0.1, ocz), Vector3(ox1 - ox0, 0.2, oz1 - oz0), "tread", Color(0.6, 0.62, 0.6), true, 2.0)
	for p in [Vector3(6.2, 0, -6.2), Vector3(9.0, 0, -6.2), Vector3(11.8, 0, -6.2)]:
		box(p + Vector3(0, (y - 0.2) * 0.5, 0), Vector3(0.25, y - 0.2, 0.25), "metal", T_YEL)
	box(Vector3(ocx, top + 0.05, ocz), Vector3(ox1 - ox0, 0.1, oz1 - oz0), "metal", T_STEEL, true, 1.0)
	# west wall with door from the catwalk (door at z -9.9..-9.0)
	var wh := top - y
	box(Vector3(ox0, y + wh * 0.5, (-9.0 + oz1) * 0.5), Vector3(0.12, wh, oz1 + 9.0), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	box(Vector3(ox0, y + (2.0 + wh) * 0.5, (oz0 - 9.0) * 0.5 - 0.0), Vector3(0.12, wh - 2.0, 1.0), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	# south wall: window strip x 6.6..10.4 (y +0.95..+1.75), duct hole at x 11.2..12 (y 4.0..4.5)
	var sy0 := y + 0.95
	var sy1 := y + 1.75
	box(Vector3(ocx, (y + sy0) * 0.5, oz1), Vector3(ox1 - ox0, sy0 - y, 0.12), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	box(Vector3(6.3, (sy0 + sy1) * 0.5, oz1), Vector3(0.6, sy1 - sy0, 0.12), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	box(Vector3(10.75, (sy0 + DUCT_Y) * 0.5, oz1), Vector3(0.7, DUCT_Y - sy0, 0.12), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	box(Vector3(11.55, (sy0 + DUCT_Y - 0.06) * 0.5, oz1), Vector3(0.9, DUCT_Y - 0.06 - sy0, 0.12), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	box(Vector3(8.5, (sy1 + top) * 0.5, oz1), Vector3(5.0, top - sy1, 0.12), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	box(Vector3(10.75, (DUCT_Y + top) * 0.5, oz1), Vector3(0.7, top - DUCT_Y, 0.12), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	box(Vector3(11.55, (DUCT_Y + 0.5 + top) * 0.5, oz1), Vector3(0.9, top - DUCT_Y - 0.5, 0.12), "paint", Color(0.55, 0.6, 0.52), true, 1.0)
	# window frame bars (the window itself is open: hop through it to the hall)
	for x in [7.9, 9.2]:
		box(Vector3(x, (sy0 + sy1) * 0.5, oz1), Vector3(0.05, sy1 - sy0, 0.06), "metal", T_STEEL, false)
	# inside: desk, monitors, lockers, filing cabinet, chair, mugs
	var fy := y
	box(Vector3(8.5, fy + 0.73, -6.6), Vector3(2.4, 0.04, 0.7), "wood", Color(0.7, 0.62, 0.5), true, 2.0)
	box(Vector3(7.4, fy + 0.355, -6.6), Vector3(0.05, 0.71, 0.65), "metal", T_STEEL, true)
	box(Vector3(9.6, fy + 0.355, -6.6), Vector3(0.45, 0.71, 0.65), "metal", T_STEEL, true)
	for i in 3:
		var mx := 7.8 + i * 0.6
		box(Vector3(mx, fy + 0.94, -6.45), Vector3(0.42, 0.38, 0.36), "paint", Color(0.85, 0.82, 0.72), true)
		box(Vector3(mx, fy + 0.95, -6.63), Vector3(0.34, 0.26, 0.01), "screen", Color.WHITE, false, 1.0, 0.0, [], 2.0)
	omni(Vector3(8.4, fy + 1.0, -6.95), Color(0.3, 1.0, 0.5), 0.6, 2.5)
	for i in 4:
		box(Vector3(11.7, fy + 0.9, -9.6 + i * 0.42), Vector3(0.5, 1.8, 0.4), "metal", Color(0.4, 0.5, 0.45), true, 2.0)
	box(Vector3(6.5, fy + 0.65, -7.4), Vector3(0.5, 1.3, 0.6), "metal", Color(0.55, 0.55, 0.5), true, 2.0)
	box(Vector3(8.4, fy + 0.45, -7.25), Vector3(0.45, 0.06, 0.45), "rubber", Color.WHITE)
	box(Vector3(8.4, fy + 0.22, -7.25), Vector3(0.06, 0.44, 0.06), "metal", T_STEEL)
	box(Vector3(8.4, fy + 0.72, -7.45), Vector3(0.45, 0.5, 0.06), "rubber", Color.WHITE)
	Level.mug(lv, Vector3(9.3, fy + 0.75, -6.75), Color(0.85, 0.85, 0.82))
	Level.mug(lv, Vector3(7.2, fy + 0.75, -6.8), Color(0.25, 0.35, 0.6))
	omni(Vector3(9.0, top - 0.3, -8.0), Color(0.95, 1.0, 0.85), 1.4, 6.0, true)
	box(Vector3(9.0, top - 0.04, -8.0), Vector3(1.2, 0.04, 0.3), "light", Color(0.95, 1.0, 0.85), false, 1.0, 0.0, [], 2.5)


## chain link storage cage in the SE: climb the fence, drop in on the crates
static func _cage() -> void:
	var x0 := 6.5
	var x1 := 10.5
	var z0 := 2.2
	var z1 := 5.8
	var h := 2.4
	chainlink(Vector3((x0 + x1) * 0.5, h * 0.5, z0), Vector3(x1 - x0, h, 0.0))
	chainlink(Vector3(x0, h * 0.5, (z0 + z1) * 0.5 - 0.6), Vector3(0.0, h, z1 - z0 - 1.2))
	chainlink(Vector3(x1, h * 0.5, (z0 + z1) * 0.5), Vector3(0.0, h, z1 - z0))
	crate(Vector3(9.4, 0, 4.6), 1.0)
	crate(Vector3(9.4, 1.0, 4.6), 0.6, 0.3)
	crate(Vector3(8.2, 0, 4.9), 0.8, -0.2)
	cardboard(Vector3(7.3, 0, 3.0), Vector3(0.5, 0.4, 0.4), 0.3)
	wall_sign(Vector3((x0 + x1) * 0.5, 1.5, z0 - 0.02), PI, "sign", Vector2(0.45, 0.45))


static func _hall_props() -> void:
	# oil drums
	for p in [Vector3(2.5, 0, 2.0), Vector3(3.1, 0, 2.2), Vector3(2.75, 0, 2.7), Vector3(3.6, 0, 1.6)]:
		drum(p, Color(0.25, 0.4, 0.6) if int(p.x * 10) % 2 == 0 else Color(0.7, 0.55, 0.15))
	pallet(Vector3(3.4, 0, 3.3))
	drum(Vector3(3.15, 0.14, 3.3), Color(0.25, 0.45, 0.3))
	drum(Vector3(3.75, 0.14, 3.35), Color(0.25, 0.45, 0.3))
	# inspection deck on short legs: 0.2 m crawl gap underneath
	box(Vector3(-4.0, 0.26, 3.5), Vector3(4.0, 0.12, 3.0), "tread", Color(0.7, 0.72, 0.7), true, 2.0)
	for x in [-5.9, -4.0, -2.1]:
		for z in [2.1, 3.5, 4.9]:
			box(Vector3(x, 0.1, z), Vector3(0.08, 0.2, 0.08), "metal", T_YEL)
	box(Vector3(-4.0, 0.62, 4.6), Vector3(1.4, 0.6, 0.6), "metal", T_OLIVE, true, 1.5) # pump housing
	cyl(Vector3(-4.0, 1.1, 4.6), 0.18, 0.4, "metal", T_OLIVE, "y", true, 8)
	cyl(Vector3(-2.9, 0.62, 4.6), 0.1, 0.8, "metal", T_PIPE_R, "x", true, 8)
	# forklift (generic, blocky)
	var fx := 7.0
	var fz := -1.5
	box(Vector3(fx, 0.55, fz), Vector3(1.1, 0.8, 1.9), "paint", T_YEL, true, 1.0)
	box(Vector3(fx, 1.0, fz + 0.6), Vector3(1.0, 0.3, 0.6), "metal", Color(0.25, 0.25, 0.25), true)
	for sx in [-0.5, 0.5]:
		box(Vector3(fx + sx, 1.25, fz - 0.4), Vector3(0.05, 1.2, 0.05), "metal", Color(0.2, 0.2, 0.2), false)
		box(Vector3(fx + sx, 1.25, fz + 0.4), Vector3(0.05, 1.2, 0.05), "metal", Color(0.2, 0.2, 0.2), false)
	box(Vector3(fx, 1.85, fz), Vector3(1.1, 0.05, 0.9), "grate", Color(0.3, 0.3, 0.3), true, 4.0)
	box(Vector3(fx, 1.3, fz - 1.05), Vector3(0.9, 2.4, 0.12), "metal", Color(0.2, 0.2, 0.2), true)
	for sx in [-0.3, 0.3]:
		box(Vector3(fx + sx, 0.05, fz - 1.7), Vector3(0.12, 0.05, 1.1), "metal", Color(0.25, 0.25, 0.25), true)
	for p in [Vector3(-0.55, 0.25, -0.6), Vector3(0.55, 0.25, -0.6), Vector3(-0.55, 0.22, 0.65), Vector3(0.55, 0.22, 0.65)]:
		cyl(Vector3(fx, 0, fz) + p, 0.25 if p.z < 0 else 0.22, 0.2, "rubber", Color.WHITE, "x", false, 8)
	# loose cardboard boxes (the classic hiding spot, cat sized ones included)
	cardboard(Vector3(-1.0, 0, 0.5), Vector3(0.6, 0.45, 0.45), 0.3)
	cardboard(Vector3(0.6, 0, -0.8), Vector3(0.45, 0.35, 0.35), -0.6)
	cardboard(Vector3(-9.6, 0, -1.0), Vector3(0.8, 0.6, 0.6), 0.1)
	cardboard(Vector3(-9.5, 0.6, -1.05), Vector3(0.5, 0.4, 0.45), 0.4)
	# tool bench along the west wall
	box(Vector3(-11.2, 0.88, -1.4), Vector3(0.7, 0.05, 1.8), "wood", Color(0.75, 0.65, 0.5), true, 2.0)
	for z in [-2.2, -0.6]:
		box(Vector3(-11.2, 0.43, z), Vector3(0.6, 0.86, 0.06), "metal", T_STEEL)
	box(Vector3(-11.2, 0.95, -1.8), Vector3(0.3, 0.1, 0.18), "paint", Color(0.8, 0.15, 0.12), true)
	Level.mug(lv, Vector3(-11.1, 0.9, -0.9), Color(0.9, 0.5, 0.2))
	# a wind up toy mouse loose in the hall
	var tm := ToyMouse.new()
	tm.position = Vector3(-2.0, 0.05, 1.5)
	lv.add_child(tm)
	# red rotating beacons over the doors
	for p in [Vector3(-2.4, 4.6, HALL_S - 0.15), Vector3(7.25, 2.4, HALL_S - 0.15)]:
		_beacon(p)
	# emergency exit sign
	box(Vector3(6.5, 2.35, HALL_S - 0.05), Vector3(0.5, 0.18, 0.04), "paint", Color(0.2, 1.0, 0.35), false, 1.0, 0.0, [], 2.0)


static func _beacon(p: Vector3) -> void:
	box(p + Vector3(0, -0.06, 0), Vector3(0.14, 0.04, 0.14), "metal", Color(0.2, 0.2, 0.2), false)
	box(p + Vector3(0, 0.04, 0), Vector3(0.1, 0.14, 0.1), "light", Color(1, 0.15, 0.1), false, 1.0, 0.0, [], 3.0)
	var piv := Node3D.new()
	piv.position = p + Vector3(0, 0.05, 0)
	lv.add_child(piv)
	var sl := SpotLight3D.new()
	sl.light_color = Color(1.0, 0.12, 0.08)
	sl.light_energy = 6.0
	sl.spot_range = 9.0
	sl.spot_angle = 22.0
	sl.light_specular = 0.0
	sl.rotation.x = -0.35
	piv.add_child(sl)
	beacons.append(piv)


static func _dock() -> void:
	# pier slab (z 6..24) with the sea below
	box(Vector3(0, -0.1, 15.2), Vector3(44.0, 0.2, 18.4), "concrete", Color(0.55, 0.57, 0.6), true, 0.5)
	box(Vector3(0, -1.0, 24.3), Vector3(44.0, 1.8, 0.6), "concrete", Color(0.4, 0.42, 0.45), true, 0.5)
	box(Vector3(0, 0.08, 24.15), Vector3(44.0, 0.16, 0.3), "hazard", Color.WHITE, true, 1.5) # curb
	for side in [-1, 1]:
		box(Vector3(side * 22.2, -1.0, 15.2), Vector3(0.4, 1.8, 18.4), "concrete", Color(0.4, 0.42, 0.45), true, 0.5)
	# painted lane lines
	for k in 8:
		box(Vector3(-18.0 + k * 5.0, 0.003, 7.5), Vector3(2.5, 0.006, 0.15), "paint", T_YEL, false)
	# puddles (dark glossy patches)
	for r in PUDDLES:
		var rc: Vector2 = (r as Rect2).get_center()
		var p := Vector3(rc.x, 0, rc.y)
		box(p + Vector3(0, 0.004, 0), Vector3(1.6, 0.008, 1.1), "water", Color(0.4, 0.5, 0.6), false, 1.0, 0.3, [], 0.2)
	# sea
	var sea := MeshInstance3D.new()
	sea.mesh = _grid_mesh(200.0, 120.0, 48)
	sea.material_override = PSX.mat("water", Color(0.35, 0.45, 0.55), 0.15, {"wave": 0.12, "scroll": Vector2(0.03, 0.05)})
	sea.position = Vector3(0, -1.3, 84.0)
	lv.add_child(sea)

	# ---- container yard (west): 2 high, crate steps up ----
	container(Vector3(-12.0, 0, 11.0), Color(0.7, 0.25, 0.18))
	container(Vector3(-12.0, 2.59, 11.0), Color(0.2, 0.45, 0.55))
	container(Vector3(-12.0, 0, 13.6), Color(0.3, 0.42, 0.3))
	container(Vector3(-18.5, 0, 12.3), Color(0.75, 0.7, 0.55), PI / 2)
	container(Vector3(-5.5, 0, 17.5), Color(0.25, 0.3, 0.55), 0.08)
	container(Vector3(-12.0, 0, 19.5), Color(0.6, 0.4, 0.15))
	container(Vector3(-12.0, 2.59, 19.5), Color(0.7, 0.25, 0.18), -0.05)
	container(Vector3(-12.0, 5.18, 19.5), Color(0.75, 0.75, 0.72), 0.03)
	# the way up: 0.6 crate, 1.2 stack, pallet+crates to 1.8, onto the 2.59 roof
	crate(Vector3(-8.3, 0, 9.5), 0.6, 0.2)
	crate(Vector3(-8.4, 0, 10.4), 1.2, -0.1)
	crate(Vector3(-8.5, 1.2, 10.5), 0.6, 0.35)
	# on the first stack's roof: crates up to the second level (5.18)
	crate(Vector3(-11.0, 2.59, 13.6), 0.9, 0.1)
	crate(Vector3(-12.2, 2.59, 13.7), 1.2, 0.0)
	crate(Vector3(-12.3, 3.79, 13.7), 0.6, 0.0)
	# plank bridge between the stacks (narrow balance beam at 5.18)
	box(Vector3(-12.0, 5.2, 16.25), Vector3(0.25, 0.05, 5.6), "wood", Color(0.75, 0.65, 0.5), true, 2.0)
	# drums + pallets around the yard
	for p in [Vector3(-15.0, 0, 9.0), Vector3(-15.6, 0, 9.3), Vector3(-15.2, 0, 9.85)]:
		drum(p, Color(0.2, 0.4, 0.25))
	pallet(Vector3(-7.0, 0, 14.5), 0.3)
	pallet(Vector3(-7.0, 0.14, 14.5), 0.25)
	cardboard(Vector3(-7.1, 0.28, 14.4), Vector3(0.6, 0.5, 0.5), 0.3)

	# ---- guard hut (east) ----
	var hx := 8.0
	var hz := 10.5
	box(Vector3(hx, 1.3, hz - 1.1), Vector3(2.6, 2.6, 0.12), "paint", Color(0.85, 0.82, 0.7), true, 1.0)
	box(Vector3(hx - 1.3, 1.3, hz), Vector3(0.12, 2.6, 2.2), "paint", Color(0.85, 0.82, 0.7), true, 1.0)
	box(Vector3(hx + 1.3, 1.3, hz), Vector3(0.12, 2.6, 2.2), "paint", Color(0.85, 0.82, 0.7), true, 1.0)
	# front: window + door gap
	box(Vector3(hx - 0.2, 0.5, hz + 1.1), Vector3(2.2, 1.0, 0.12), "paint", Color(0.85, 0.82, 0.7), true, 1.0)
	box(Vector3(hx - 0.2, 2.3, hz + 1.1), Vector3(2.2, 0.6, 0.12), "paint", Color(0.85, 0.82, 0.7), true, 1.0)
	box(Vector3(hx + 1.2, 2.35, hz + 1.1), Vector3(0.3, 0.5, 0.12), "paint", Color(0.85, 0.82, 0.7), true, 1.0)
	box(Vector3(hx, 2.65, hz), Vector3(2.9, 0.1, 2.5), "corrugated", Color(0.5, 0.25, 0.2), true, 1.0)
	box(Vector3(hx - 0.3, 0.78, hz + 0.75), Vector3(1.8, 0.04, 0.5), "wood", Color(0.7, 0.62, 0.5), true, 2.0)
	box(Vector3(hx - 0.8, 0.95, hz + 0.7), Vector3(0.35, 0.3, 0.3), "paint", Color(0.85, 0.82, 0.72), true)
	box(Vector3(hx - 0.8, 0.96, hz + 0.86), Vector3(0.27, 0.2, 0.01), "screen", Color.WHITE, false, 1.0, 0.0, [], 2.0)
	box(Vector3(hx - 0.3, 0.38, hz + 0.75), Vector3(0.06, 0.76, 0.06), "metal", T_STEEL)
	Level.mug(lv, Vector3(hx - 0.1, 0.8, hz + 0.75), Color(0.9, 0.9, 0.85))
	omni(Vector3(hx, 2.3, hz), Color(1.0, 0.9, 0.65), 1.2, 4.5, true)
	# ac unit + drum = steps onto the hut roof
	box(Vector3(hx + 1.75, 0.45, hz - 0.3), Vector3(0.6, 0.9, 0.8), "metal", Color(0.75, 0.75, 0.72), true, 2.0)
	drum(Vector3(hx + 1.8, 0, hz + 0.75), Color(0.6, 0.2, 0.15))
	box(Vector3(hx + 1.8, 1.65, hz - 0.3), Vector3(0.12, 1.5, 0.12), "metal", Color(0.4, 0.4, 0.4), false)

	# ---- bollards, rope, lamp posts ----
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		cyl(Vector3(x, 0.25, 23.4), 0.18, 0.5, "metal", Color(0.25, 0.25, 0.28), "y", true, 8)
		cyl(Vector3(x, 0.52, 23.4), 0.24, 0.06, "metal", Color(0.25, 0.25, 0.28), "y", true, 8)
	for i in 6:
		cyl(Vector3(3.0, 0.03 + i * 0.05, 22.6), 0.35 - i * 0.03, 0.05, "fabric", Color(0.75, 0.65, 0.45), "y", i == 5, 10)
	for p in [Vector3(-16.0, 0, 7.5), Vector3(-2.0, 0, 21.5), Vector3(12.0, 0, 21.5), Vector3(18.0, 0, 7.5)]:
		cyl(p + Vector3(0, 3.0, 0), 0.08, 6.0, "metal", Color(0.35, 0.35, 0.38), "y", true, 6)
		box(p + Vector3(0, 6.0, -0.4), Vector3(0.12, 0.12, 0.9), "metal", Color(0.35, 0.35, 0.38), false)
		box(p + Vector3(0, 5.94, -0.8), Vector3(0.35, 0.1, 0.25), "light", Color(1.0, 0.6, 0.25), false, 1.0, 0.0, [], 3.0)
		omni(p + Vector3(0, 5.6, -0.8), Color(1.0, 0.58, 0.25), 3.5, 13.0, p.x == -2.0)

	# ---- chain link fence on the east edge of the dock ----
	chainlink(Vector3(21.0, 1.0, 13.0), Vector3(0.0, 2.0, 12.0))
	for k in 10:
		box(Vector3(21.0, 2.1, 7.5 + k * 1.2), Vector3(0.05, 0.05, 0.6), "metal", Color(0.4, 0.4, 0.42), false, 1.0, 0.7) # barbed wire

	# ---- dock crane leg + gantry (lattice legs = climbable) ----
	var gx := 10.0
	var gz := 19.5
	for sx in [-3.0, 3.0]:
		for sz in [-1.2, 1.2]:
			box(Vector3(gx + sx, 4.5, gz + sz), Vector3(0.35, 9.0, 0.35), "grate", T_YEL, true, 3.0, 0.0, ["climbable"])
			box(Vector3(gx + sx, 0.25, gz + sz), Vector3(0.7, 0.5, 0.7), "metal", Color(0.3, 0.3, 0.3), true)
	for y in [3.0, 6.0]:
		for sx in [-3.0, 3.0]:
			box(Vector3(gx + sx, y, gz), Vector3(0.12, 0.12, 2.4), "metal", T_YEL, true)
	box(Vector3(gx, 9.1, gz), Vector3(7.0, 0.3, 3.0), "tread", Color(0.85, 0.75, 0.3), true, 2.0)
	box(Vector3(gx, 9.8, gz + 1.3), Vector3(2.4, 1.4, 1.5), "metal", Color(0.8, 0.7, 0.25), true, 1.5) # cab
	box(Vector3(gx, 9.9, gz + 0.54), Vector3(1.8, 0.6, 0.02), "water", Color(0.6, 0.8, 1.0), false, 1.0, 0.0, [], 0.6)
	box(Vector3(gx, 9.3, gz + 6.0), Vector3(1.2, 0.5, 9.0), "grate", T_YEL, true, 3.0) # boom out over the water
	_blink(Vector3(gx, 10.6, gz + 1.3))
	_blink(Vector3(gx, 9.6, gz + 10.4))

	# rain over the dock
	var rain := GPUParticles3D.new()
	rain.amount = 6000
	rain.lifetime = 1.1
	rain.visibility_aabb = AABB(Vector3(-24, -14, -12), Vector3(48, 30, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(23.0, 0.5, 11.0)
	pm.direction = Vector3(0.1, -1, 0.05)
	pm.spread = 2.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 17.0
	pm.gravity = Vector3(0, -6, 0)
	rain.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.012, 0.4)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.7, 0.8, 0.95, 0.35)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.disable_receive_shadows = true
	drop.material = dm
	rain.draw_pass_1 = drop
	rain.position = Vector3(0, 12.0, 15.5)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lv.add_child(rain)

	# sweeping searchlight from the crane cab
	var piv := Node3D.new()
	piv.position = Vector3(gx, 10.4, gz + 0.5)
	lv.add_child(piv)
	var sl := SpotLight3D.new()
	sl.light_color = Color(0.85, 0.92, 1.0)
	sl.light_energy = 14.0
	sl.spot_range = 30.0
	sl.spot_angle = 9.0
	sl.light_specular = 0.0
	sl.shadow_enabled = true
	sl.rotation = Vector3(-0.55, PI, 0)
	piv.add_child(sl)
	sweepers.append(piv)


## dark industrial skyline across the water with blinking red lights
static func _backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 22:
		var x := -90.0 + i * 8.5 + rng.randf_range(-2, 2)
		var h := rng.randf_range(6, 30)
		var z := rng.randf_range(95, 120)
		if rng.randf() < 0.35:
			cyl(Vector3(x, h * 0.5 - 2, z), rng.randf_range(1.5, 4), h, "metal", Color(0.12, 0.13, 0.16), "y", false, 8)
		else:
			box(Vector3(x, h * 0.5 - 2, z), Vector3(rng.randf_range(4, 9), h, 5), "metal", Color(0.1, 0.11, 0.14), false, 0.2)
		if rng.randf() < 0.6:
			_blink(Vector3(x, h - 1.8, z - 2.6))
		if rng.randf() < 0.5:
			# lit windows
			for k in rng.randi_range(2, 6):
				box(Vector3(x + rng.randf_range(-1.5, 1.5), rng.randf_range(1, h - 3), z - 2.55), Vector3(0.6, 0.3, 0.05), "light", Color(1.0, 0.75, 0.4), false, 1.0, 0.0, [], 1.5)
	# a long chimney stack with smoke-ish glow
	cyl(Vector3(30, 18, 110), 2.0, 40, "brick", Color(0.35, 0.3, 0.3), "y", false, 8)
	_blink(Vector3(30, 38.5, 108))


static func _blink(p: Vector3) -> void:
	var b := box(p, Vector3(0.25, 0.25, 0.25), "light", Color(1, 0.1, 0.05), false, 1.0, 0.0, [], 4.0)
	blinkers.append(b)


static func _grid_mesh(w: float, d: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for j in n:
			var x0 := -w * 0.5 + w * i / n
			var x1 := -w * 0.5 + w * (i + 1) / n
			var z0 := -d * 0.5 + d * j / n
			var z1 := -d * 0.5 + d * (j + 1) / n
			var q := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_color(Color.WHITE)
				st.set_uv(Vector2(q[idx].x, q[idx].z) * 0.25)
				st.add_vertex(q[idx])
	return st.commit()


## call every frame: beacons spin, searchlight sweeps, warning lights blink
static func animate(t: float) -> void:
	for b in beacons:
		if is_instance_valid(b):
			b.rotation.y = t * 4.0
	for s in sweepers:
		if is_instance_valid(s):
			s.rotation.y = sin(t * 0.35) * 1.1
	for i in blinkers.size():
		var b := blinkers[i]
		if is_instance_valid(b):
			b.visible = fmod(t + i * 0.37, 1.6) < 0.8
