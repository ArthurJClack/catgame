class_name DesertLevel
extends RefCounted
## the desert (res://desert.tscn), late afternoon, at cat scale (80 x 80 m):
##   south   where you arrive: old fence posts, the farm gate back, creosote + quail
##   middle  a dry wash (arroyo) snaking east-west, gravel floor a metre below the flats
##   west    the ranch ruin: an adobe shack (door shut, a broken window over the rain barrel), a dead
##           tree the vultures sit in
##   east    the windmill + its dry trough, a rusted-out pickup half sunk in the sand
##   north   a dune field (east) and a red sandstone mesa you can climb (west), a balanced rock
## the cat is 25 cm tall: a barrel is a step, the mesa is a mountain.

const HALF := 40.0
const SPAWN := Vector3(0.0, 0.0, 33.0)
const SHACK := Vector2(-12.0, 20.0)
const MILL := Vector2(6.0, 20.0)
const TRUCK := Vector2(17.0, 27.0)
const MESA := Vector2(-22.0, -18.0)
const TREE := Vector2(-7.0, 15.0)
const ROCK_ARCH := Vector2(-3.0, -4.0)

const C_SAND := Color(0.88, 0.68, 0.44)
const C_SAND_L := Color(0.95, 0.8, 0.58)
const C_PAN := Color(0.8, 0.6, 0.42)
const C_GRAVEL := Color(0.62, 0.52, 0.42)
const C_RED := Color(0.82, 0.46, 0.3)
const C_RED_D := Color(0.66, 0.34, 0.24)
const C_CACTUS := Color(0.42, 0.55, 0.32)
const C_SAGE := Color(0.52, 0.56, 0.4)

static var _lo: FastNoiseLite
static var _hi: FastNoiseLite
static var pads := []         # [Vector2 centre, radius, height] flattened ground for buildings
static var mill_info := {}    # windmill parts the puzzle drives (wheel node, platform top, trough)
static var shack_info := {}


static func _noises() -> void:
	_lo = FastNoiseLite.new()
	_lo.seed = 5150
	_lo.frequency = 0.03
	_hi = FastNoiseLite.new()
	_hi.seed = 5151
	_hi.frequency = 0.22


static func wash_z(x: float) -> float:
	return 8.0 + 4.0 * sin(x * 0.08) + 1.2 * sin(x * 0.21 + 1.0)


static func wash_dist(x: float, z: float) -> float:
	return absf(z - wash_z(x)) * cos(atan(0.32 * cos(x * 0.08)))


static func dune_w(x: float, z: float) -> float:
	return smoothstep(2.0, 9.0, x) * smoothstep(6.0, -2.0, z)


static func _raw(x: float, z: float) -> float:
	if _lo == null:
		_noises()
	var h := 1.3 + _lo.get_noise_2d(x, z) * 0.5 + _hi.get_noise_2d(x, z) * 0.04
	# dunes: asymmetric ridges (long gentle windward side, steep slip face), crests ~2.4 m
	var dw := dune_w(x, z)
	if dw > 0.0:
		var u := (x * 0.94 + z * 0.34) * 0.62 + _lo.get_noise_2d(x * 2.0, z * 2.0) * 1.6
		var f := fposmod(u, TAU) / TAU
		var ridge := (f / 0.78) if f < 0.78 else (1.0 - (f - 0.78) / 0.22)
		ridge = ridge * ridge * (3.0 - 2.0 * ridge)
		h += ridge * 2.4 * dw
	# the wash: a flat gravel floor ~1.1 m down with sloped banks
	var wd := wash_dist(x, z)
	h -= 1.1 * (1.0 - smoothstep(1.3, 3.4, wd))
	return h


static func height(x: float, z: float) -> float:
	var h := _raw(x, z)
	for p in pads:
		var c: Vector2 = p[0]
		var w := 1.0 - smoothstep(float(p[1]) - 1.5, float(p[1]), Vector2(x, z).distance_to(c))
		h = lerpf(h, float(p[2]), w)
	return h


static func surface(x: float, z: float) -> String:
	if wash_dist(x, z) < 2.2:
		return "gravel"
	return "sand"


static func color(x: float, z: float, h: float, slope: float) -> Color:
	var hsh := fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)
	var wd := wash_dist(x, z)
	var dw := dune_w(x, z)
	var c := C_PAN.lerp(C_SAND, clampf(dw * 1.4, 0.0, 1.0))
	c = c.lerp(C_SAND_L, clampf((h - 2.4) * 0.5, 0.0, 0.5) * dw)
	if wd < 3.2:
		c = c.lerp(C_GRAVEL, 1.0 - smoothstep(1.4, 3.2, wd))
	# slip faces + banks a touch darker, a few pebbly speckles
	c = c.darkened(clampf(slope * 0.9, 0.0, 0.25))
	return c.darkened(hsh * 0.06)


static func build(root: Node3D) -> Dictionary:
	_noises()
	pads = []
	for p in [[SHACK, 4.2], [MILL, 3.4], [TRUCK, 3.0], [Vector2(SPAWN.x, SPAWN.z), 3.0]]:
		var c: Vector2 = p[0]
		pads.append([c, p[1], _raw(c.x, c.y)])
	var lv := BiomeKit.begin(root, "Desert", HALF, height)
	BiomeKit.terrain(color, surface)
	BiomeKit.apron(C_PAN.darkened(0.05), 1.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	_backdrop(rng)
	_mesa()
	_shack()
	_dead_tree()
	_windmill()
	_truck()
	_rocks(rng)
	_plants(rng)
	_fence()
	var sp := BiomeKit.at(SPAWN.x, SPAWN.z)
	return {
		"spawn": sp,
		"spawn_yaw": 0.0,
		"exit": {"pos": BiomeKit.at(SPAWN.x, SPAWN.z + 3.2), "normal": Vector3(0, 0, -1)},
		"spots": [
			["the gate", sp, 0.0],
			["the ranch", BiomeKit.at(SHACK.x + 3.0, SHACK.y + 3.0), PI * 0.25],
			["the windmill", BiomeKit.at(MILL.x - 1.5, MILL.y + 3.0), -PI * 0.15],
			["the wash", BiomeKit.at(0.0, wash_z(0.0)), PI * 0.5],
			["the dunes", BiomeKit.at(14.0, -10.0), PI * 0.2],
			["the mesa", BiomeKit.at(MESA.x + 2.0, MESA.y + 7.0), 0.0],
			["the pickup", BiomeKit.at(TRUCK.x - 2.5, TRUCK.y), -PI * 0.5],
		],
		"tour": _tour(),
	}


static func _tour() -> Array:
	var a := func(x: float, z: float, up: float) -> Vector3: return BiomeKit.at(x, z, up)
	return [
		[a.call(0.0, 36.5, 0.5), a.call(0.0, 30.0, 0.4), 3.0],
		[a.call(1.5, 30.0, 0.8), a.call(4.0, 22.0, 1.4), 3.5],
		[a.call(3.5, 23.5, 1.6), a.call(6.0, 20.0, 3.4), 3.5],
		[a.call(8.5, 17.5, 4.2), a.call(6.0, 20.0, 3.6), 3.0],
		[a.call(13.0, 22.0, 1.2), a.call(17.0, 27.0, 0.7), 3.0],
		[a.call(10.0, 12.0, 0.4), a.call(0.0, wash_z(0.0), 0.2), 3.0],
		[a.call(-4.0, wash_z(-4.0), 0.3), a.call(-12.0, wash_z(-12.0), 0.3), 3.5],
		[a.call(-8.0, 17.0, 1.0), a.call(-12.0, 20.0, 1.0), 3.0],
		[a.call(-9.6, 20.4, 1.25), a.call(-12.5, 19.6, 0.4), 3.0],
		[a.call(-8.0, 10.0, 2.5), a.call(-3.0, -4.0, 2.0), 3.5],
		[a.call(6.0, -4.0, 1.5), a.call(14.0, -12.0, 2.5), 3.5],
		[a.call(10.0, -16.0, 4.5), a.call(-22.0, -18.0, 5.0), 4.0],
		[a.call(-14.0, -10.0, 3.0), a.call(-22.0, -18.0, 6.0), 3.5],
		[a.call(-20.0, -17.0, 9.5), a.call(0.0, 10.0, 0.0), 4.0],
		[a.call(-20.0, -17.0, 12.0), a.call(10.0, 30.0, 0.0), 1.0],
	]


# ------------------------------------------------------------------ pieces

static func _backdrop(rng: RandomNumberGenerator) -> void:
	# far mesas + buttes on every side, sinking into the haze
	for k in 18:
		var a := k * TAU / 18.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(80.0, 150.0)
		var w := rng.randf_range(14.0, 40.0)
		var h := rng.randf_range(10.0, 26.0)
		var c := Vector3(cos(a) * r, 1.0 + h * 0.5, sin(a) * r)
		var col := C_RED_D.lerp(Color(0.7, 0.45, 0.4), rng.randf() * 0.5)
		# a mesa = cap rock on a wider talus skirt, so it doesn't read as a plain box
		BiomeKit.far(c, Vector3(w, h, w * rng.randf_range(0.5, 1.0)), a, col)
		BiomeKit.far(Vector3(c.x, 1.0 + h * 0.18, c.z), Vector3(w * 1.5, h * 0.36, w * 1.2), a, col.lightened(0.12))
		if rng.randf() < 0.5:
			BiomeKit.far(c + Vector3(rng.randf_range(-4, 4), h * 0.5 + 2.5, 0), Vector3(w * 0.5, 5.0, w * 0.4), a, col.lightened(0.05))


static func _mesa() -> void:
	# red sandstone mesa in tiers, with broken ledges up its south side so a cat can work up it
	var m := BiomeKit.at(MESA.x, MESA.y)
	var g := m.y - 0.3
	BiomeKit.slab(Vector3(m.x, g, m.z), Vector3(10.0, 3.0, 8.0), 0.15, C_RED)
	BiomeKit.slab(Vector3(m.x - 0.6, g + 3.0, m.z - 0.8), Vector3(7.0, 2.6, 5.6), 0.15, C_RED_D)
	BiomeKit.slab(Vector3(m.x - 1.0, g + 5.6, m.z - 1.2), Vector3(4.0, 2.2, 3.2), 0.2, C_RED)
	# the way up: ledges stepping across the south face (each step <= 0.9 m)
	var steps := [
		[Vector3(3.6, 0, 4.4), Vector3(1.6, 0.8, 1.2)],
		[Vector3(2.0, 0, 4.6), Vector3(1.2, 1.6, 1.0)],
		[Vector3(0.6, 0, 4.5), Vector3(1.2, 2.4, 1.0)],
		[Vector3(-1.4, 3.0, 2.6), Vector3(1.4, 0.8, 1.0)],
		[Vector3(-2.8, 3.0, 2.3), Vector3(1.2, 1.6, 1.0)],
		[Vector3(-0.2, 5.6, 0.7), Vector3(1.2, 0.8, 1.0)],
		[Vector3(1.0, 5.6, 0.6), Vector3(1.0, 1.5, 0.9)],
	]
	var b := Basis(Vector3.UP, 0.15)
	for s in steps:
		var off: Vector3 = b * Vector3(s[0].x, 0, s[0].z)
		BiomeKit.slab(Vector3(m.x + off.x, g + s[0].y, m.z + off.z), s[1], 0.15, C_RED.lerp(C_RED_D, 0.4))
	# talus at the foot
	for k in 10:
		var a := k * 0.6 + 0.3
		var p := Vector3(m.x + cos(a) * 6.2, 0, m.z + sin(a) * 5.0)
		BiomeKit.rock(BiomeKit.at(p.x, p.z), Vector3(0.6, 0.45, 0.55) * (0.6 + 0.12 * (k % 4)), a, C_RED, k)
	# balanced rock: a pillar with a boulder sat on top
	var br := BiomeKit.at(ROCK_ARCH.x, ROCK_ARCH.y)
	BiomeKit.rock(br + Vector3(0, -0.1, 0), Vector3(2.2, 1.4, 2.0), 0.2, C_RED_D, 6, true, 0.1)
	BiomeKit.slab(br + Vector3(0, 0.6, 0), Vector3(1.3, 2.2, 1.2), 0.4, C_RED_D)
	BiomeKit.rock(br + Vector3(0.1, 2.75, 0), Vector3(2.6, 1.5, 2.1), 0.9, C_RED, 4, true, 0.05)
	BiomeKit.slab(br + Vector3(1.2, -0.2, 0.6), Vector3(0.8, 1.2, 0.8), 0.2, C_RED)


static func _shack() -> void:
	# adobe walls 2.2 m, tin roof, door shut. the broken window in the east wall is the way in: barrel
	# (0.8 m) -> sill (1.0 m) -> inside
	var c := BiomeKit.at(SHACK.x, SHACK.y)
	var fy := c.y
	var W := 3.2
	var D := 2.6
	var H := 2.2
	var T := 0.14
	var adobe := Color(0.86, 0.66, 0.5)
	var K := BiomeKit
	# floor boards
	K.pbox(Vector3(c.x, fy + 0.02, c.z), Vector3(W - T, 0.04, D - T), 0.0, "wood", Color(0.75, 0.62, 0.48), true, "wood")
	# north + west walls
	K.pbox(Vector3(c.x, fy + H * 0.5, c.z - D * 0.5), Vector3(W, H, T), 0.0, "adobe", adobe, true, "stone")
	K.pbox(Vector3(c.x - W * 0.5, fy + H * 0.5, c.z), Vector3(T, H, D), 0.0, "adobe", adobe, true, "stone")
	# south wall with the door (shut, planks)
	K.pbox(Vector3(c.x - 0.95, fy + H * 0.5, c.z + D * 0.5), Vector3(1.3, H, T), 0.0, "adobe", adobe, true, "stone")
	K.pbox(Vector3(c.x + 0.95, fy + H * 0.5, c.z + D * 0.5), Vector3(1.3, H, T), 0.0, "adobe", adobe, true, "stone")
	K.pbox(Vector3(c.x, fy + 1.95, c.z + D * 0.5), Vector3(0.6, 0.5, T), 0.0, "adobe", adobe, true, "stone")
	K.pbox(Vector3(c.x, fy + 0.85, c.z + D * 0.5 + 0.02), Vector3(0.62, 1.7, 0.06), 0.0, "wood", Color(0.6, 0.45, 0.32), true, "wood")
	# east wall around the window hole (sill 1.0, hole 0.55 wide x 0.42 tall)
	var ex := c.x + W * 0.5
	var sill := 1.0
	var hw := 0.55
	var hh := 0.42
	K.pbox(Vector3(ex, fy + sill * 0.5, c.z), Vector3(T, sill, D), 0.0, "adobe", adobe, true, "stone")
	K.pbox(Vector3(ex, fy + (sill + hh + H) * 0.5, c.z), Vector3(T, H - sill - hh, D), 0.0, "adobe", adobe, true, "stone")
	var side := (D - hw) * 0.5
	K.pbox(Vector3(ex, fy + sill + hh * 0.5, c.z - hw * 0.5 - side * 0.5), Vector3(T, hh, side), 0.0, "adobe", adobe, true, "stone")
	K.pbox(Vector3(ex, fy + sill + hh * 0.5, c.z + hw * 0.5 + side * 0.5), Vector3(T, hh, side), 0.0, "adobe", adobe, true, "stone")
	# a couple of broken glass teeth + the old frame
	K.pbox(Vector3(ex + 0.02, fy + sill + hh, c.z), Vector3(0.05, 0.05, hw + 0.1), 0.0, "wood", Color(0.5, 0.38, 0.28), false)
	K.pbox(Vector3(ex + 0.02, fy + sill + 0.01, c.z), Vector3(0.12, 0.03, hw + 0.1), 0.0, "wood", Color(0.5, 0.38, 0.28), true, "wood")
	# tin roof sloping down to the south, overhanging into a porch on posts
	var roof := K.pbox(Vector3(c.x, fy + H + 0.12, c.z + 0.45), Vector3(W + 0.5, 0.05, D + 1.6), 0.0, "corrugated", Color(0.7, 0.5, 0.38), true, "metal")
	roof.rotation.x = 0.09
	for s in [-1.0, 1.0]:
		K.pcyl(Vector3(c.x + s * 1.5, fy + 1.0, c.z + D * 0.5 + 0.95), 0.05, 2.0, "wood", Color(0.55, 0.42, 0.3))
	# rain barrel under the window
	K.pcyl(Vector3(ex + 0.4, fy + 0.4, c.z + 0.05), 0.28, 0.8, "wood", Color(0.62, 0.46, 0.32), true, 10)
	for yy in [0.15, 0.65]:
		K.pcyl(Vector3(ex + 0.4, fy + yy, c.z + 0.05), 0.29, 0.04, "rust", Color.WHITE, false, 10)
	# inside: a table, a chair on its side, and the box in the north west corner
	K.pbox(Vector3(c.x + 0.4, fy + 0.72, c.z - 0.5), Vector3(0.9, 0.04, 0.6), 0.0, "wood", Color(0.62, 0.48, 0.34), true, "wood")
	for sx in [-0.4, 0.4]:
		for sz in [-0.25, 0.25]:
			K.pbox(Vector3(c.x + 0.4 + sx, fy + 0.36, c.z - 0.5 + sz), Vector3(0.05, 0.7, 0.05), 0.0, "wood", Color(0.5, 0.38, 0.27), true)
	K.pbox(Vector3(c.x - 0.2, fy + 0.25, c.z + 0.6), Vector3(0.4, 0.04, 0.4), 0.7, "wood", Color(0.6, 0.46, 0.33), true)
	var bx := Vector3(c.x - W * 0.5 + 0.42, fy + 0.04, c.z - D * 0.5 + 0.36)
	var bw := Vector3(0.46, 0.24, 0.38)
	var cb := Color(0.82, 0.64, 0.42)
	K.pbox(bx + Vector3(0, 0.01, 0), Vector3(bw.x, 0.02, bw.z), 0.0, "cardboard", cb, true, "carpet")
	K.pbox(bx + Vector3(-bw.x * 0.5, bw.y * 0.5, 0), Vector3(0.02, bw.y, bw.z), 0.0, "cardboard", cb, true)
	K.pbox(bx + Vector3(bw.x * 0.5, bw.y * 0.5, 0), Vector3(0.02, bw.y, bw.z), 0.0, "cardboard", cb, true)
	K.pbox(bx + Vector3(0, bw.y * 0.5, -bw.z * 0.5), Vector3(bw.x, bw.y, 0.02), 0.0, "cardboard", cb, true)
	K.pbox(bx + Vector3(0, bw.y * 0.5, bw.z * 0.5), Vector3(bw.x, bw.y, 0.02), 0.0, "cardboard", cb, true)
	# flaps flopped open
	var f1 := K.pbox(bx + Vector3(bw.x * 0.5 + 0.08, bw.y + 0.02, 0), Vector3(0.16, 0.01, bw.z), 0.0, "cardboard", cb, false)
	f1.rotation.z = -0.5
	# sunlight through the window
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.55)
	l.light_energy = 1.4
	l.spot_range = 4.0
	l.spot_angle = 30.0
	l.position = Vector3(ex + 0.6, fy + sill + 0.5, c.z)
	l.rotation = Vector3(-0.35, PI * 0.5, 0)
	BiomeKit.lv.add_child(l)
	var o := OmniLight3D.new()
	o.light_color = Color(0.95, 0.75, 0.55)
	o.light_energy = 0.35
	o.omni_range = 2.6
	o.position = Vector3(c.x, fy + 1.4, c.z)
	BiomeKit.lv.add_child(o)
	shack_info = {"box": bx, "box_size": bw, "barrel": Vector3(ex + 0.4, fy + 0.8, c.z + 0.05), "sill": Vector3(ex, fy + sill, c.z)}
	ForestLevel.obstacles.append([SHACK, 2.2])
	ForestLevel.perches.append(Vector3(c.x, fy + H + 0.2, c.z))


static func _dead_tree() -> void:
	var b := BiomeKit.at(TREE.x, TREE.y)
	var bark := Color(0.6, 0.5, 0.42)
	var trunk := BiomeKit.pcyl(b + Vector3(0, 1.4, 0), 0.16, 2.8, "wood", bark, true, 7)
	_tree_climb(trunk)
	var limbs := [[Vector3(0, 2.2, 0), Vector3(0.5, 0, 0.85), 1.6], [Vector3(0, 2.6, 0), Vector3(-0.2, 0, -0.9), 1.4], [Vector3(0, 2.75, 0), Vector3(-0.8, 0, 0.3), 1.1]]
	for lm in limbs:
		var start: Vector3 = b + lm[0]
		var dir: Vector3 = (lm[1] as Vector3).normalized()
		var len: float = lm[2]
		var tilt := 0.85
		var axis := dir.cross(Vector3.UP).normalized()
		var bas := Basis(axis, -tilt)   # y axis tipped out toward dir
		var up := bas * Vector3.UP
		var mid := start + up * len * 0.5
		var limb := BiomeKit.pcyl(mid, 0.07, len, "wood", bark, true, 6)
		limb.basis = bas
		_tree_climb(limb)
		ForestLevel.perches.append(start + up * len)
	ForestLevel.trunks.append([b, 0.16, 2.8])
	ForestLevel.obstacles.append([TREE, 0.4])


static func roost() -> Vector3:
	var b := BiomeKit.at(TREE.x, TREE.y)
	return b + Vector3(0, 2.2, 0) + Basis(Vector3(0.5, 0, 0.85).normalized().cross(Vector3.UP).normalized(), -0.85) * Vector3.UP * 1.6 + Vector3(0, 0.1, 0)


static func _tree_climb(n: Node) -> void:
	n.set_meta("surface", "bark")
	n.add_to_group("climbable")
	n.add_to_group("scratchable")


static func _windmill() -> void:
	# wooden tower, 4 legs, braces every ~0.85 m (perches for a cat), ladder up the south face,
	# platform at 3.4 m, the wheel above. the brake wedge on the platform keeps it locked (puzzle)
	var c := BiomeKit.at(MILL.x, MILL.y)
	var g := c.y
	var wood := Color(0.62, 0.5, 0.38)
	var K := BiomeKit
	var top := 3.4
	var hw := 0.55
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := K.pbox(Vector3(c.x + sx * hw, g + top * 0.5, c.z + sz * hw), Vector3(0.12, top, 0.12), 0.0, "wood", wood, true, "wood")
			_tree_climb(leg)
	for k in 3:
		var y := 0.95 + k * 0.85
		for s in [-1.0, 1.0]:
			K.pbox(Vector3(c.x, g + y, c.z + s * hw), Vector3(hw * 2.0 + 0.12, 0.08, 0.15), 0.0, "wood", wood.darkened(0.1), true, "wood")
			K.pbox(Vector3(c.x + s * hw, g + y, c.z), Vector3(0.15, 0.08, hw * 2.0 + 0.12), 0.0, "wood", wood.darkened(0.1), true, "wood")
	# diagonal braces (visual)
	for s in [-1.0, 1.0]:
		var d := K.pbox(Vector3(c.x, g + top * 0.5, c.z + s * (hw + 0.03)), Vector3(0.05, top * 1.15, 0.03), 0.0, "wood", wood.darkened(0.2), false)
		d.rotation.z = 0.32 * s
	# ladder: rails + rungs on the south face
	for s in [-1.0, 1.0]:
		K.pbox(Vector3(c.x + s * 0.2, g + top * 0.5, c.z + hw + 0.12), Vector3(0.05, top, 0.05), 0.0, "wood", wood, true, "wood")
	for k in 11:
		var r := K.pbox(Vector3(c.x, g + 0.3 + k * 0.3, c.z + hw + 0.12), Vector3(0.42, 0.03, 0.04), 0.0, "wood", wood.lightened(0.05), true, "wood")
		_tree_climb(r)
	# platform
	K.pbox(Vector3(c.x, g + top + 0.03, c.z), Vector3(1.5, 0.06, 1.5), 0.0, "wood", wood.lightened(0.08), true, "wood")
	# head: gearbox, wheel (spins when the brake is off), tail vane
	var head := Node3D.new()
	head.position = Vector3(c.x, g + top + 0.65, c.z - 0.3)
	K.lv.add_child(head)
	K.pbox(Vector3.ZERO, Vector3(0.3, 0.3, 0.5), 0.0, "rust", Color.WHITE, false, "", head)
	var wheel := Node3D.new()
	wheel.position = Vector3(0, 0.05, -0.32)
	head.add_child(wheel)
	K.pcyl(Vector3.ZERO, 0.08, 0.12, "rust", Color.WHITE, false, 8, wheel, Vector3(PI * 0.5, 0, 0))
	for k in 14:
		var bl := Node3D.new()
		bl.rotation.z = k * TAU / 14.0
		wheel.add_child(bl)
		var blade := K.pbox(Vector3(0, 0.62, 0), Vector3(0.16, 0.95, 0.015), 0.0, "metal", Color(0.85, 0.82, 0.78), false, "", bl)
		blade.rotation.y = 0.35
	K.pbox(Vector3(0, 0, 0.9), Vector3(0.04, 0.04, 1.4), 0.0, "rust", Color.WHITE, false, "", head)
	K.pbox(Vector3(0, 0.1, 1.6), Vector3(0.02, 0.6, 0.8), 0.0, "metal", Color(0.85, 0.82, 0.78), false, "", head)
	# pump rod + pipe down to the trough
	K.pbox(Vector3(c.x, g + top * 0.5, c.z), Vector3(0.04, top, 0.04), 0.0, "metal", Color(0.6, 0.6, 0.6), false)
	var tc := Vector3(c.x + 1.7, g, c.z + 0.2)
	K.pbox(Vector3(c.x + 0.85, g + 0.75, c.z + 0.2), Vector3(1.0, 0.06, 0.06), 0.0, "rust", Color.WHITE, false)
	K.pbox(Vector3(c.x + 1.32, g + 0.62, c.z + 0.2), Vector3(0.06, 0.25, 0.06), 0.0, "rust", Color.WHITE, false)
	# trough: wooden walls, 0.45 high, 1.8 x 0.55, empty
	var tw := Vector3(0.55, 0.45, 1.8)
	K.pbox(tc + Vector3(0, 0.03, 0), Vector3(tw.x, 0.06, tw.z), 0.0, "wood", wood.darkened(0.15), true, "wood")
	for s in [-1.0, 1.0]:
		K.pbox(tc + Vector3(s * tw.x * 0.5, tw.y * 0.5, 0), Vector3(0.06, tw.y, tw.z), 0.0, "wood", wood, true, "wood")
		K.pbox(tc + Vector3(0, tw.y * 0.5, s * tw.z * 0.5), Vector3(tw.x, tw.y, 0.06), 0.0, "wood", wood, true, "wood")
	var water := MeshInstance3D.new()
	water.mesh = PSX.box_mesh(Vector3(tw.x - 0.08, 0.02, tw.z - 0.08), 1.0)
	water.material_override = PSX.mat("water", Color(0.7, 0.85, 1.0), 0.15, {"scroll": Vector2(0.05, 0.02)})
	water.position = tc + Vector3(0, 0.07, 0)
	water.visible = false
	K.lv.add_child(water)
	# a sun bleached skull by the trough
	K.pbox(tc + Vector3(-0.9, 0.08, 1.1), Vector3(0.22, 0.14, 0.32), 0.4, "paint", Color(0.92, 0.88, 0.8), true, "stone")
	mill_info = {"wheel": wheel, "platform": Vector3(c.x, g + top + 0.06, c.z), "trough": tc, "trough_size": tw, "water": water, "spout": Vector3(c.x + 1.32, g + 0.5, c.z + 0.2)}
	ForestLevel.obstacles.append([MILL, 1.0])
	ForestLevel.obstacles.append([Vector2(tc.x, tc.z), 1.0])


static func _truck() -> void:
	# rusted pickup sunk to its axles: bed rim 0.75, cab roof 1.5. snakes like the shade underneath
	var c := BiomeKit.at(TRUCK.x, TRUCK.y)
	var n := Node3D.new()
	n.position = c + Vector3(0, -0.15, 0)
	n.rotation.y = 0.35
	BiomeKit.lv.add_child(n)
	var K := BiomeKit
	var rust := Color(0.95, 0.85, 0.8)
	K.pbox(Vector3(0, 0.38, 0), Vector3(1.7, 0.18, 4.4), 0.0, "rust", rust, true, "metal", n)       # chassis
	var paint := Color(0.46, 0.64, 0.6)   # faded turquoise, rust bleeding through at the edges
	K.pbox(Vector3(0, 0.68, -1.55), Vector3(1.7, 0.5, 1.3), 0.0, "paint", paint, true, "metal", n)    # hood
	K.pbox(Vector3(0, 0.98, -0.45), Vector3(1.6, 1.1, 1.0), 0.0, "paint", paint.lightened(0.05), true, "metal", n)   # cab
	K.pbox(Vector3(0, 0.45, -2.22), Vector3(1.72, 0.2, 0.08), 0.0, "rust", rust, false, "", n)     # bumper
	K.pbox(Vector3(0, 1.1, -0.98), Vector3(1.4, 0.45, 0.04), 0.0, "water", Color(0.2, 0.25, 0.28), false, "", n)   # windscreen
	K.pbox(Vector3(0, 0.52, 1.05), Vector3(1.6, 0.06, 2.1), 0.0, "rust", rust, true, "metal", n)    # bed floor
	for s in [-1.0, 1.0]:
		K.pbox(Vector3(s * 0.8, 0.68, 1.05), Vector3(0.06, 0.36, 2.1), 0.0, "rust", rust, true, "metal", n)
		for zz in [-1.4, 1.4]:
			K.pcyl(Vector3(s * 0.78, 0.2, zz), 0.3, 0.2, "rubber", Color.WHITE, true, 8, n, Vector3(0, 0, PI * 0.5))
	K.pbox(Vector3(0, 0.68, 2.08), Vector3(1.6, 0.36, 0.06), 0.0, "rust", rust, true, "metal", n)
	ForestLevel.obstacles.append([TRUCK, 2.2])
	ForestLevel.perches.append(c + Vector3(0, 1.4, 0))


static func _rocks(rng: RandomNumberGenerator) -> void:
	# slickrock + boulders scattered over the flats (not in the wash or the dunes)
	var placed := 0
	var tries := 0
	while placed < 34 and tries < 400:
		tries += 1
		var x := rng.randf_range(-36, 36)
		var z := rng.randf_range(-36, 34)
		if wash_dist(x, z) < 3.5 or dune_w(x, z) > 0.3 or _near_pad(x, z, 2.0) or Vector2(x, z).distance_to(MESA) < 9.0:
			continue
		var s := rng.randf_range(0.35, 1.5) if rng.randf() < 0.8 else rng.randf_range(1.6, 2.4)
		BiomeKit.rock(BiomeKit.at(x, z), Vector3(s * rng.randf_range(0.9, 1.5), s * rng.randf_range(0.5, 0.9), s), rng.randf() * TAU, C_RED.lerp(C_PAN, rng.randf() * 0.5), placed)
		placed += 1
	# a few boulders down in the wash (cat sized step stones)
	for k in 8:
		var x := -30.0 + k * 8.0 + rng.randf_range(-2, 2)
		BiomeKit.rock(BiomeKit.at(x, wash_z(x) + rng.randf_range(-1.0, 1.0)), Vector3(0.5, 0.35, 0.45) * rng.randf_range(0.7, 1.4), rng.randf() * TAU, C_GRAVEL.lightened(0.1), 50 + k)


static func _near_pad(x: float, z: float, extra: float) -> bool:
	for p in pads:
		if Vector2(x, z).distance_to(p[0]) < float(p[1]) + extra:
			return true
	return Vector2(x, z).distance_to(TREE) < 2.0 or Vector2(x, z).distance_to(ROCK_ARCH) < 3.0


static func _plants(rng: RandomNumberGenerator) -> void:
	var K := BiomeKit
	# columnar cacti with arms (not climbable: claws + spines don't mix)
	var n := 0
	var tries := 0
	while n < 16 and tries < 300:
		tries += 1
		var x := rng.randf_range(-36, 36)
		var z := rng.randf_range(-34, 32)
		if wash_dist(x, z) < 3.2 or dune_w(x, z) > 0.2 or _near_pad(x, z, 2.5) or Vector2(x, z).distance_to(MESA) < 8.0:
			continue
		var b := K.at(x, z)
		var h := rng.randf_range(2.2, 4.2)
		K.pcyl(b + Vector3(0, h * 0.5, 0), 0.17, h, "grain", C_CACTUS, true, 8)
		for a in rng.randi_range(0, 2):
			var side := Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU)
			var ay := rng.randf_range(1.0, h - 0.8)
			var arm := K.pcyl(b + side * 0.3 + Vector3(0, ay, 0), 0.1, 0.36, "grain", C_CACTUS, false, 6)
			arm.basis = Basis(Vector3.UP, side, Vector3.UP.cross(side))
			K.pcyl(b + side * 0.46 + Vector3(0, ay + 0.45, 0), 0.1, 0.9, "grain", C_CACTUS, false, 6)
		ForestLevel.obstacles.append([Vector2(x, z), 0.35])
		n += 1
	# prickly pear pads, barrel cacti, sage + creosote bushes, dry grass tufts (no colliders)
	for k in 220:
		var x := rng.randf_range(-37, 37)
		var z := rng.randf_range(-37, 37)
		if _near_pad(x, z, 0.5):
			continue
		var b := K.at(x, z)
		var r := rng.randf()
		if dune_w(x, z) > 0.5 and r < 0.8:
			continue   # dunes are mostly bare
		if r < 0.12:
			for p in 4:
				var pad := K.pbox(b + Vector3(rng.randf_range(-0.2, 0.2), 0.14 + p * 0.08, rng.randf_range(-0.2, 0.2)), Vector3(0.2, 0.24, 0.04), rng.randf() * TAU, "grain", C_CACTUS.lightened(0.05), false)
				pad.rotation.z = rng.randf_range(-0.5, 0.5)
		elif r < 0.2:
			K.pcyl(b + Vector3(0, 0.16, 0), 0.16, 0.32, "grain", C_CACTUS.darkened(0.1), true, 8)
			K.pcyl(b + Vector3(0, 0.33, 0), 0.04, 0.03, "paint", Color(1.0, 0.45, 0.3), false, 6)   # flower
		elif r < 0.65:
			var s := rng.randf_range(0.3, 0.8)
			var bush := MeshInstance3D.new()
			bush.mesh = BiomeKit.rock_mesh(Vector3(s, s * 0.7, s), k)
			bush.material_override = PSX.mat("grain", C_SAGE.lerp(Color(0.6, 0.55, 0.35), rng.randf() * 0.6))
			bush.position = b + Vector3(0, s * 0.25, 0)
			K.lv.add_child(bush)
		else:
			for g in 4:
				var blade := K.pbox(b + Vector3(rng.randf_range(-0.1, 0.1), 0.08, rng.randf_range(-0.1, 0.1)), Vector3(0.015, 0.18, 0.015), rng.randf() * TAU, "grain", Color(0.85, 0.75, 0.5), false)
				blade.rotation.z = rng.randf_range(-0.4, 0.4)


static func _fence() -> void:
	# old ranch fence posts along the south, leaning, with the farm gate frame behind the spawn
	var K := BiomeKit
	for k in 26:
		var x := -36.0 + k * 3.0
		if absf(x) < 2.0:
			continue
		var z := 36.0 + sin(k * 1.7) * 0.4
		var p := K.pbox(K.at(x, z, 0.5), Vector3(0.1, 1.0, 0.1), 0.0, "wood", Color(0.55, 0.45, 0.36), true, "wood")
		p.rotation.z = sin(k * 2.3) * 0.12
		_tree_climb(p)
	var g := K.at(SPAWN.x, SPAWN.z + 3.4)
	for s in [-1.0, 1.0]:
		K.pbox(g + Vector3(s * 0.75, 0.75, 0), Vector3(0.12, 1.5, 0.12), 0.0, "wood", Color(0.5, 0.42, 0.31), true, "wood")
	K.pbox(g + Vector3(0, 1.55, 0), Vector3(1.62, 0.1, 0.12), 0.0, "wood", Color(0.5, 0.42, 0.31), false)
