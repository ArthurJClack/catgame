class_name MountainLevel
extends RefCounted
## the mountain (res://mountain.tscn), a cold bright morning, cat scale (80 x 80 m). built to climb:
##   meadow   where you arrive (south): grass, wildflowers, a meltwater stream from a little fall,
##            the stone hut under the first cliff, snowed in on its uphill side
##   band 1   the first cliff (3-4 m of layered rock, climbable everywhere) with a talus gully on the
##            east side for the long way round. marmots live at the foot of the gully, pikas up it
##   bench    a sloping shelf with snow patches and wind bent pines, goats about
##   band 2   the second cliff (4-5 m) with goat ledges zig-zagging up it, talus gully on the west
##   summit   a snowy knoll with a cairn on top. the view goes on forever
## every rock face is a climbable slab (cat_climb.gd), so there's always a way up for a cat

const HALF := 40.0
const SPAWN := Vector3(0.0, 0.0, 35.0)
const HUT := Vector2(-14.0, 6.6)
const CAIRN := Vector2(2.0, -30.0)
const SENTRY := Vector2(22.0, 10.5)
const B1 := 6.2       # bench height (m) just above band 1
const B2 := 11.8      # summit plateau height just above band 2

const C_GRASS := Color(0.44, 0.54, 0.3)
const C_GRASS2 := Color(0.54, 0.58, 0.34)
const C_DIRT := Color(0.5, 0.44, 0.36)
const C_ROCK := Color(0.6, 0.58, 0.56)
const C_ROCK_D := Color(0.46, 0.45, 0.46)
const C_SNOW := Color(0.9, 0.92, 0.97)
const C_PINE := Color(0.24, 0.38, 0.28)

static var _lo: FastNoiseLite
static var _hi: FastNoiseLite
static var pads := []
static var stream_pts: Array = []
static var goat_routes: Array = []
static var hut_info := {}
static var ball_at := Vector3.ZERO
static var summit_spot := Vector3.ZERO


static func _noises() -> void:
	_lo = FastNoiseLite.new()
	_lo.seed = 8848
	_lo.frequency = 0.035
	_hi = FastNoiseLite.new()
	_hi.seed = 8849
	_hi.frequency = 0.25


static func z1(x: float) -> float:
	return 2.0 + 1.5 * sin(x * 0.15)


static func z2(x: float) -> float:
	return -16.0 + 1.2 * sin(x * 0.2 + 1.0)


static func stream_x(z: float) -> float:
	return 8.0 + 2.5 * sin(z * 0.12) + 0.8 * sin(z * 0.31)


## 0 on the cliff, 1 in a talus gully (the long way round)
static func gully1(x: float) -> float:
	return smoothstep(16.0, 19.5, x) * (1.0 - smoothstep(25.0, 28.5, x))


static func gully2(x: float) -> float:
	return smoothstep(-31.0, -27.5, x) * (1.0 - smoothstep(-23.0, -19.5, x))


static func _raw(x: float, z: float) -> float:
	if _lo == null:
		_noises()
	var n := _lo.get_noise_2d(x, z) * 0.45 + _hi.get_noise_2d(x, z) * 0.05
	var c1 := z1(x)
	var c2 := z2(x)
	var meadow := 0.4 + (38.0 - z) * 0.07 + n
	var bench := B1 + (c1 - z) * 0.07 + n * 0.8
	var top := B2 + (c2 - z) * 0.04 + n * 0.6
	# summit knoll
	top += 1.6 * (1.0 - smoothstep(0.0, 9.0, Vector2(x, z).distance_to(CAIRN)))
	# cliff steps are sharp under the slabs (the slabs hide them); gullies get a long talus ramp
	var g1 := gully1(x)
	var g2 := gully2(x)
	var s1 := lerpf(smoothstep(c1, c1 - 1.2, z), smoothstep(c1 + 7.0, c1 - 5.0, z), g1)
	var s2 := lerpf(smoothstep(c2, c2 - 1.2, z), smoothstep(c2 + 7.0, c2 - 5.0, z), g2)
	var h := lerpf(meadow, bench, s1)
	h = lerpf(h, top, s2)
	# the stream channel on the meadow
	if z > c1 + 0.5:
		var sd := absf(x - stream_x(z))
		h -= 0.32 * (1.0 - smoothstep(0.35, 0.9, sd))
	return h


static func height(x: float, z: float) -> float:
	var h := _raw(x, z)
	for p in pads:
		var c: Vector2 = p[0]
		var w := 1.0 - smoothstep(float(p[1]) - 1.5, float(p[1]), Vector2(x, z).distance_to(c))
		h = lerpf(h, float(p[2]), w)
	return h


static func _snowy(x: float, z: float, h: float) -> bool:
	if h < B1 - 0.3:
		return false
	var patch := _lo.get_noise_2d(x * 1.7 + 40.0, z * 1.7)
	return h > B2 + 0.5 or patch > (0.15 if h > B2 - 1.0 else 0.32)


static func surface(x: float, z: float) -> String:
	var h := BiomeKit.y(x, z)
	if _snowy(x, z, h):
		return "snow"
	if z > z1(x) + 0.5 and absf(x - stream_x(z)) < 0.8:
		return "gravel"
	if gully1(x) > 0.3 and z < z1(x) + 6.0 and z > z1(x) - 4.0:
		return "gravel"
	if gully2(x) > 0.3 and z < z2(x) + 6.0 and z > z2(x) - 4.0:
		return "gravel"
	return "grass" if h < B1 - 0.5 else "dirt"


static func color(x: float, z: float, h: float, slope: float) -> Color:
	var hsh := fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)
	var c := C_GRASS.lerp(C_GRASS2, clampf(_lo.get_noise_2d(x * 2.0, z * 2.0) + 0.5, 0.0, 1.0))
	if h > B1 - 0.5:
		c = c.lerp(Color(0.5, 0.52, 0.38), clampf((h - B1) * 0.3, 0.0, 0.8))
	if slope > 0.35:
		c = c.lerp(C_ROCK_D, clampf((slope - 0.35) * 2.5, 0.0, 1.0))
	if (gully1(x) > 0.3 and z < z1(x) + 6.0 and z > z1(x) - 4.0) or (gully2(x) > 0.3 and z < z2(x) + 6.0 and z > z2(x) - 4.0):
		c = c.lerp(C_ROCK, 0.75)
	if z > z1(x) + 0.5 and absf(x - stream_x(z)) < 0.8:
		c = C_DIRT.darkened(0.15)
	if _snowy(x, z, h):
		c = C_SNOW.darkened(slope * 0.3)
	return c.darkened(hsh * 0.07)


static func build(root: Node3D) -> Dictionary:
	_noises()
	pads = []
	for p in [[HUT, 3.4], [Vector2(SPAWN.x, SPAWN.z), 3.0]]:
		var c: Vector2 = p[0]
		pads.append([c, p[1], _raw(c.x, c.y)])
	BiomeKit.begin(root, "Mountain", HALF, height)
	BiomeKit.terrain(color, surface)
	BiomeKit.apron(C_GRASS.darkened(0.25), 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4478
	goat_routes = []
	_backdrop(rng)
	_band(1, rng)
	_band(2, rng)
	_talus(rng)
	_stream()
	_hut()
	_summit()
	_plants(rng)
	var sp := BiomeKit.at(SPAWN.x, SPAWN.z)
	return {
		"spawn": sp,
		"spawn_yaw": 0.0,
		"exit": {"pos": BiomeKit.at(SPAWN.x, SPAWN.z + 3.2), "normal": Vector3(0, 0, -1)},
		"spots": [
			["the meadow", sp, 0.0],
			["the hut", BiomeKit.at(HUT.x + 2.5, HUT.y + 3.5), PI * 0.2],
			["the marmots", BiomeKit.at(SENTRY.x - 1.0, SENTRY.y - 6.0), PI],
			["band one", BiomeKit.at(0.0, z1(0.0) + 1.0), 0.0],
			["the bench", BiomeKit.at(0.0, -6.0), 0.0],
			["band two", BiomeKit.at(-6.0, z2(-6.0) + 1.2), 0.0],
			["the summit", BiomeKit.at(CAIRN.x - 1.5, CAIRN.y + 2.0), 0.0],
		],
		"tour": _tour(),
		"kill_y": -5.0,
	}


static func _tour() -> Array:
	var a := func(x: float, z: float, up: float) -> Vector3: return BiomeKit.at(x, z, up)
	return [
		[a.call(0.0, 38.5, 0.5), a.call(0.0, 30.0, 1.0), 3.0],
		[a.call(2.0, 30.0, 1.0), a.call(8.0, 18.0, 1.0), 3.5],
		[a.call(7.0, 18.0, 0.5), a.call(stream_x(5.0), 4.0, 1.0), 3.0],
		[a.call(-6.0, 13.0, 1.4), a.call(-14.0, 6.6, 1.2), 3.5],
		[a.call(-11.0, 2.5, 2.0), a.call(-14.0, 6.6, 0.5), 3.0],
		[a.call(-8.0, 4.0, 4.0), a.call(-14.0, 0.6, 6.4), 3.0],
		[a.call(16.0, 16.0, 1.2), a.call(22.0, 10.5, 1.0), 3.5],
		[a.call(21.0, 5.0, 2.4), a.call(22.0, -2.0, 4.0), 3.5],
		[a.call(14.0, -4.0, 2.0), a.call(0.0, -15.0, 4.0), 3.5],
		[a.call(-2.0, -10.0, 1.2), a.call(-4.0, -16.5, 3.5), 3.0],
		[a.call(-6.0, -12.5, 3.5), a.call(-4.0, -17.0, 5.5), 3.0],
		[a.call(-6.0, -22.0, 2.0), a.call(2.0, -30.0, 2.5), 3.5],
		[a.call(-1.0, -27.0, 1.5), a.call(2.0, -30.0, 1.4), 3.0],
		[a.call(2.0, -27.0, 4.0), a.call(0.0, 20.0, 0.0), 4.0],
		[a.call(2.0, -26.0, 7.0), a.call(0.0, 40.0, -2.0), 1.0],
	]


# ------------------------------------------------------------------ pieces

static func _backdrop(rng: RandomNumberGenerator) -> void:
	# big peaks behind (north) and to the sides, lower ridges + a valley haze to the south
	for k in 22:
		var a := k * TAU / 22.0 + rng.randf_range(-0.08, 0.08)
		var north := sin(a) < 0.0
		var r := rng.randf_range(90.0, 160.0)
		var h := rng.randf_range(40.0, 90.0) if north else rng.randf_range(14.0, 34.0)
		var w := h * rng.randf_range(0.9, 1.4)
		var c := Vector3(cos(a) * r, -8.0, sin(a) * r)
		BiomeKit.far(c, Vector3(w * 1.6, h, w * 1.6), a, Color(0.34, 0.36, 0.42) if north else Color(0.3, 0.36, 0.3), "rock", true)


## a cliff band: a row of layered slabs whose faces stand on the step line, tops flush with the shelf
## above. gaps where the gully runs. band 2 also gets goat ledges + a resting ledge partway up
static func _band(which: int, rng: RandomNumberGenerator) -> void:
	var zf: Callable = z1 if which == 1 else z2
	var gf: Callable = gully1 if which == 1 else gully2
	var x := -39.0
	var k := 0
	while x < 39.0:
		var w := rng.randf_range(2.2, 3.6)
		var cx := x + w * 0.5
		x += w - 0.05
		k += 1
		if float(gf.call(cx)) > 0.2:
			continue
		var face: float = float(zf.call(cx)) + rng.randf_range(-0.35, 0.35)
		var depth := 2.4
		var top := height(cx, face - depth * 0.55) + rng.randf_range(-0.25, 0.1)
		var foot := minf(height(cx, face + 0.3), height(cx - w * 0.5, face + 0.3))
		foot = minf(foot, height(cx + w * 0.5, face + 0.3)) - 0.3
		var slope_yaw := -atan((float(zf.call(cx + 0.5)) - float(zf.call(cx - 0.5))))
		var tint := C_ROCK.lerp(C_ROCK_D, rng.randf()).lerp(Color(0.6, 0.5, 0.42), rng.randf() * 0.3)
		BiomeKit.slab(Vector3(cx, foot, face - depth * 0.5), Vector3(w + 0.1, top - foot + 0.02, depth), slope_yaw, tint)
		# buttresses + fallen blocks in front of some of it: breaks the wall up, gives holds + rests
		var keep_clear := (which == 2 and cx > -12.5 and cx < 0.5) or (which == 1 and absf(cx - HUT.x) < 3.0)
		if rng.randf() < 0.45 and not keep_clear:
			var bh := (top - foot) * rng.randf_range(0.3, 0.65)
			var bw := w * rng.randf_range(0.35, 0.7)
			var bx := cx + rng.randf_range(-0.3, 0.3) * w
			BiomeKit.slab(Vector3(bx, foot, face + rng.randf_range(0.25, 0.5)), Vector3(bw, bh, rng.randf_range(0.6, 1.0)), slope_yaw + rng.randf_range(-0.15, 0.15), tint.darkened(0.08))
		if which == 1 and absf(cx - HUT.x) < 1.6:
			ball_at = Vector3(cx, top + 0.02, face - 0.55)
	if which == 2:
		# goat ledges zig-zagging up the face between x -12 and 0 (0.35 deep: a goat and a cat both fit)
		var lx := [-11.0, -8.6, -6.2, -3.8, -1.4]
		var route := []
		route.append(BiomeKit.at(-13.0, z2(-13.0) + 2.5))
		for i in lx.size():
			var cx: float = lx[i]
			var face: float = z2(cx)
			var foot := height(cx, face + 0.4)
			var ly := foot + 0.8 + i * 0.75
			BiomeKit.slab(Vector3(cx, ly - 0.25, face + 0.18), Vector3(2.0, 0.25, 0.4), 0.0, C_ROCK_D, true)
			route.append(Vector3(cx, ly, face + 0.2))
		route.append(BiomeKit.at(0.5, z2(0.5) - 2.0))
		route.append(BiomeKit.at(3.0, -24.0))
		route.append(BiomeKit.at(-2.0, -27.0))
		goat_routes.append(route)
		# a resting ledge halfway up the band near the middle
		for cx in [6.0, 9.0]:
			var face: float = z2(cx)
			var foot := height(cx, face + 0.4)
			BiomeKit.slab(Vector3(cx, foot + 2.0, face + 0.2), Vector3(2.4, 0.22, 0.45), 0.0, C_ROCK_D, true)
		# the bench goats wander along under band 2
		goat_routes.append([BiomeKit.at(10.0, -9.0), BiomeKit.at(4.0, -11.0), BiomeKit.at(-4.0, -10.0), BiomeKit.at(-10.0, -8.0), BiomeKit.at(-4.0, -6.0), BiomeKit.at(5.0, -5.0)])
	else:
		# a few ledges on band 1 too, so a tired cat can rest mid climb
		for cx in [-4.0, 3.5, 11.0]:
			var face: float = z1(cx)
			var foot := height(cx, face + 0.4)
			BiomeKit.slab(Vector3(cx, foot + 1.6, face + 0.22), Vector3(1.6, 0.2, 0.45), 0.0, C_ROCK_D, true)


static func _talus(rng: RandomNumberGenerator) -> void:
	# gully boulders (both gullies) + scattered rocks on the meadow and the bench
	for g in 2:
		var zf: Callable = z1 if g == 0 else z2
		var x0 := 18.0 if g == 0 else -29.5
		for k in 22:
			var x := rng.randf_range(x0, x0 + 8.0)
			if absf(x - (x0 + 4.0)) < 1.1:
				continue   # a clear lane up the middle: the walk-up route
			var z: float = float(zf.call(x)) + rng.randf_range(-4.5, 6.5)
			var s := rng.randf_range(0.35, 1.1)
			BiomeKit.rock(BiomeKit.at(x, z), Vector3(s * 1.2, s * 0.7, s), rng.randf() * TAU, C_ROCK.lerp(C_ROCK_D, rng.randf()), k + g * 30)
	# the marmot lookout rock
	BiomeKit.rock(BiomeKit.at(SENTRY.x, SENTRY.y), Vector3(1.2, 0.9, 1.0), 0.3, C_ROCK, 7, true, 0.2)
	var n := 0
	var tries := 0
	while n < 30 and tries < 300:
		tries += 1
		var x := rng.randf_range(-36, 36)
		var z := rng.randf_range(-36, 34)
		if absf(z - z1(x)) < 2.5 or absf(z - z2(x)) < 2.5 or Vector2(x, z).distance_to(HUT) < 4.5 or Vector2(x, z).distance_to(Vector2(0, 35)) < 4.0:
			continue
		if z > z1(x) and absf(x - stream_x(z)) < 1.5:
			continue
		var s := rng.randf_range(0.3, 1.4)
		BiomeKit.rock(BiomeKit.at(x, z), Vector3(s * 1.3, s * 0.7, s), rng.randf() * TAU, C_ROCK.lerp(C_ROCK_D, rng.randf() * 0.7), 100 + n)
		n += 1


static func _stream() -> void:
	# meltwater: a thin fall down band 1, then a channel across the meadow (water strip in segments)
	stream_pts = []
	var z := z1(stream_x(z1(8.0))) + 0.4
	var prev := Vector3.INF
	while z < 39.0:
		var x := stream_x(z)
		var p := Vector3(x, BiomeKit.y(x, z) + 0.06, z)
		stream_pts.append(p)
		if prev != Vector3.INF:
			var mid := (p + prev) * 0.5
			var d := p - prev
			var seg := MeshInstance3D.new()
			seg.mesh = PSX.box_mesh(Vector3(0.62, 0.02, d.length() + 0.08), 1.0)
			seg.material_override = PSX.mat("water", Color(0.75, 0.9, 1.0), 0.2, {"scroll": Vector2(0.0, 0.6)})
			seg.position = mid
			seg.basis = Basis.looking_at(d.normalized(), Vector3.UP)
			BiomeKit.lv.add_child(seg)
		prev = p
		z += 0.9
	# the little fall
	var fx := stream_x(z1(8.0))
	var top := height(fx, z1(fx) - 1.5)
	var fall := MeshInstance3D.new()
	fall.mesh = PSX.box_mesh(Vector3(0.5, top - BiomeKit.y(fx, z1(fx) + 0.4), 0.04), 1.0)
	fall.material_override = PSX.mat("water", Color(0.9, 0.95, 1.0), 0.3, {"scroll": Vector2(0.0, 1.4)})
	fall.position = Vector3(fx, (top + BiomeKit.y(fx, z1(fx) + 0.4)) * 0.5, z1(fx) + 0.05)
	BiomeKit.lv.add_child(fall)
	var spray := BiomeKit.drift_particles(BiomeKit.lv, Color(1, 1, 1, 0.35), 24, 0.12, Vector3(0, 0.5, 0.3), 1.2, Vector3(0.3, 0.1, 0.2))
	spray.position = Vector3(fx, BiomeKit.y(fx, z1(fx) + 0.4) + 0.1, z1(fx) + 0.4)
	spray.local_coords = true


static func _hut() -> void:
	# a stone bothy: dry stone walls 2 m, slate roof, the door on the uphill (north) side is buried
	# in a snow drift. inside: a stove that's still warm
	var c := BiomeKit.at(HUT.x, HUT.y)
	var fy := c.y
	var W := 3.4
	var D := 2.8
	var H := 2.0
	var T := 0.3
	var stone := Color(0.7, 0.68, 0.64)
	var K := BiomeKit
	K.pbox(Vector3(c.x, fy + 0.02, c.z), Vector3(W - T, 0.04, D - T), 0.0, "wood", Color(0.62, 0.5, 0.4), true, "wood")
	K.pbox(Vector3(c.x, fy + H * 0.5, c.z + D * 0.5), Vector3(W, H, T), 0.0, "rock", stone, true, "stone").add_to_group("climbable")
	K.pbox(Vector3(c.x - W * 0.5, fy + H * 0.5, c.z), Vector3(T, H, D), 0.0, "rock", stone, true, "stone").add_to_group("climbable")
	K.pbox(Vector3(c.x + W * 0.5, fy + H * 0.5, c.z), Vector3(T, H, D), 0.0, "rock", stone, true, "stone").add_to_group("climbable")
	# north wall with the door: door shut, cat flap at the bottom (opens when the drift is gone)
	var nz := c.z - D * 0.5
	K.pbox(Vector3(c.x - 1.05, fy + H * 0.5, nz), Vector3(1.3, H, T), 0.0, "rock", stone, true, "stone")
	K.pbox(Vector3(c.x + 1.05, fy + H * 0.5, nz), Vector3(1.3, H, T), 0.0, "rock", stone, true, "stone")
	K.pbox(Vector3(c.x, fy + 1.8, nz), Vector3(0.8, 0.4, T), 0.0, "rock", stone, true, "stone")
	var door := Node3D.new()
	door.position = Vector3(c.x, fy, nz)
	K.lv.add_child(door)
	K.pbox(Vector3(0, 0.98, 0), Vector3(0.8, 1.24, 0.08), 0.0, "wood", Color(0.5, 0.36, 0.26), true, "wood", door)
	K.pbox(Vector3(-0.22, 0.18, 0), Vector3(0.36, 0.36, 0.08), 0.0, "wood", Color(0.5, 0.36, 0.26), true, "wood", door)
	K.pbox(Vector3(0.31, 0.18, 0), Vector3(0.18, 0.36, 0.08), 0.0, "wood", Color(0.5, 0.36, 0.26), true, "wood", door)
	# the flap (0.24 x 0.26): a hinged board in the hole, solid until the puzzle swings it
	var flap := K.pbox(Vector3(0.1, 0.18, 0), Vector3(0.24, 0.34, 0.06), 0.0, "wood", Color(0.62, 0.46, 0.32), true, "wood", door)
	# slate roof, ridge east-west
	for s in [-1.0, 1.0]:
		var r := K.pbox(Vector3(c.x, fy + H + 0.42, c.z + s * 0.85), Vector3(W + 0.4, 0.08, 2.0), 0.0, "concrete_slab", Color(0.45, 0.47, 0.52), true, "stone")
		r.rotation.x = 0.45 * s
	# chimney + stove inside
	K.pbox(Vector3(c.x + 1.1, fy + H + 0.8, c.z + 0.6), Vector3(0.4, 1.0, 0.4), 0.0, "rock", stone.darkened(0.1), true, "stone")
	K.pbox(Vector3(c.x + 1.1, fy + 0.35, c.z + 0.7), Vector3(0.5, 0.7, 0.45), 0.0, "metal", Color(0.35, 0.33, 0.32), true, "metal")
	K.pbox(Vector3(c.x + 1.1, fy + 0.3, c.z + 0.47), Vector3(0.24, 0.16, 0.02), 0.0, "light", Color(1.0, 0.55, 0.2), false, "", null, 3.0)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.3)
	glow.light_energy = 1.2
	glow.omni_range = 3.2
	glow.position = Vector3(c.x + 1.0, fy + 0.5, c.z + 0.2)
	K.lv.add_child(glow)
	K.pbox(Vector3(c.x - 0.3, fy + 0.05, c.z + 0.3), Vector3(1.2, 0.02, 0.8), 0.0, "fabric", Color(0.7, 0.3, 0.25), true, "rug")
	K.pbox(Vector3(c.x - 1.0, fy + 0.35, c.z + 0.6), Vector3(1.0, 0.7, 0.5), 0.0, "wood", Color(0.55, 0.42, 0.3), true, "wood")   # bunk
	# the drift against the north wall: a mound of snow over the door, up the cliff foot behind
	var drift := StaticBody3D.new()
	drift.name = "Drift"
	drift.set_meta("surface", "snow")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 0.9, 2.2)
	cs.shape = bs
	drift.add_child(cs)
	drift.position = Vector3(c.x, fy + 0.3, nz - 1.2)
	drift.rotation.x = 0.18
	K.lv.add_child(drift)
	for k in 5:
		var mi := MeshInstance3D.new()
		mi.mesh = BiomeKit.rock_mesh(Vector3(1.2 + k * 0.15, 0.7 + (k % 2) * 0.3, 1.1), 3 + k)
		mi.material_override = PSX.mat("snow", Color(1, 1, 1))
		mi.position = Vector3(-1.0 + k * 0.5, 0.1 + (k % 2) * 0.12, -0.2 + sin(k * 1.9) * 0.4)
		drift.add_child(mi)
	hut_info = {"drift": drift, "flap": flap, "inside": Vector3(c.x - 0.3, fy + 0.06, c.z + 0.3), "door": Vector3(c.x, fy, nz)}
	ForestLevel.obstacles.append([HUT, 2.4])
	ForestLevel.perches.append(Vector3(c.x, fy + H + 0.8, c.z))


static func _summit() -> void:
	var c := BiomeKit.at(CAIRN.x, CAIRN.y)
	# cairn: stones piled smaller and smaller, the top one a perch
	var y := c.y - 0.1
	for k in 5:
		var s := 0.7 - k * 0.12
		BiomeKit.rock(Vector3(c.x + sin(k * 2.1) * 0.05, y, c.z + cos(k * 1.7) * 0.05), Vector3(s, s * 0.45, s * 0.9), k * 0.9, C_ROCK.darkened(k * 0.04), 200 + k, true, 0.0)
		y += s * 0.4
	summit_spot = BiomeKit.at(CAIRN.x + 1.0, CAIRN.y + 0.4)
	# a weathered marker post with a strip of cloth snapping in the wind
	var post := BiomeKit.pbox(BiomeKit.at(CAIRN.x - 0.9, CAIRN.y - 0.3, 0.55), Vector3(0.07, 1.1, 0.07), 0.0, "wood", Color(0.5, 0.4, 0.3), true, "wood")
	post.add_to_group("climbable")
	var cloth := BiomeKit.pbox(BiomeKit.at(CAIRN.x - 0.9, CAIRN.y - 0.05, 1.0), Vector3(0.02, 0.12, 0.42), 0.0, "fabric", Color(0.9, 0.35, 0.25), false)
	cloth.add_to_group("biome_flag")


static func _plants(rng: RandomNumberGenerator) -> void:
	var K := BiomeKit
	# wind bent pines (krummholz): low, flagged to the lee, more of them on the bench edges
	var n := 0
	var tries := 0
	while n < 26 and tries < 400:
		tries += 1
		var x := rng.randf_range(-36, 36)
		var z := rng.randf_range(-24, 30)
		if absf(z - z1(x)) < 3.0 or absf(z - z2(x)) < 3.0 or Vector2(x, z).distance_to(HUT) < 4.0 or Vector2(x, z).distance_to(Vector2(0, 35)) < 5.0:
			continue
		if z > z1(x) and absf(x - stream_x(z)) < 1.6:
			continue
		var b := K.at(x, z)
		var h := rng.randf_range(1.0, 2.6) if z > z1(x) else rng.randf_range(0.7, 1.6)
		var trunk := K.pcyl(b + Vector3(0, h * 0.35, 0), 0.07, h * 0.7, "wood", Color(0.5, 0.4, 0.3), true, 6)
		trunk.set_meta("surface", "bark")
		trunk.add_to_group("climbable")
		trunk.add_to_group("scratchable")
		for t in 3:
			var cone := MeshInstance3D.new()
			cone.mesh = LowPoly.cone(6)
			cone.material_override = PSX.mat("grain", C_PINE.darkened(t * 0.08))
			var s := (1.0 - t * 0.25) * h * 0.55
			cone.scale = Vector3(s * 1.4, s * 0.9, s)
			cone.position = b + Vector3(0.12 + t * 0.05, h * (0.25 + t * 0.25), 0.05)
			K.lv.add_child(cone)
		ForestLevel.trunks.append([b, 0.07, h * 0.7])
		ForestLevel.obstacles.append([Vector2(x, z), 0.3])
		ForestLevel.perches.append(b + Vector3(0, h * 0.75, 0))
		n += 1
	# wildflowers + grass tufts on the meadow, cushion plants up high
	var cols := [Color(0.95, 0.85, 0.25), Color(0.6, 0.45, 0.9), Color(0.95, 0.95, 0.95), Color(0.95, 0.4, 0.5)]
	for k in 320:
		var x := rng.randf_range(-37, 37)
		var z := rng.randf_range(-37, 37)
		var b := K.at(x, z)
		if _snowy(x, z, b.y) or Vector2(x, z).distance_to(HUT) < 2.6:
			continue
		if z > z1(x) + 0.5 and absf(x - stream_x(z)) < 0.8:
			continue
		if rng.randf() < 0.45 and b.y < B1:
			var f := K.pbox(b + Vector3(0, 0.08, 0), Vector3(0.05, 0.03, 0.05), rng.randf() * TAU, "paint", cols[k % cols.size()], false)
			K.pbox(b + Vector3(0, 0.035, 0), Vector3(0.012, 0.07, 0.012), 0.0, "grain", C_GRASS.darkened(0.2), false)
			f.rotation.z = rng.randf_range(-0.2, 0.2)
		else:
			for g in 4:
				var blade := K.pbox(b + Vector3(rng.randf_range(-0.08, 0.08), 0.07, rng.randf_range(-0.08, 0.08)), Vector3(0.015, 0.15, 0.015), rng.randf() * TAU, "grain", C_GRASS2.lightened(0.1) if b.y < B1 else Color(0.6, 0.6, 0.42), false)
				blade.rotation.z = rng.randf_range(-0.4, 0.4)
