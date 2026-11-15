class_name TrailLevel
extends RefCounted
## the running trail: a ~120 m loop of dirt singletrack through the woods at real cat scale, built to
## show off running. the ground is fine grained (0.5 m terrain grid with ruts and lumps, gravel,
## pebbles, leaf litter, twigs) and the trail runs through sections of small stuff to bound over:
##   roots   - two old oaks throw roots across the path (glide / step over them)
##   logs    - fallen logs of every size lying across the path (bound over)
##   rocks   - a rock garden, some flat topped slabs to land on (bound onto)
##   ledges  - natural stone steps up a ridge and drop offs down the far side
##   creek   - a ditch with water across the path (leap it)
##   debris  - stumps, branches and loose rocks all mixed up
## trees, boulders, logs and stumps come from ForestLevel's builders.

const HALF := 32.0
const S := 0.5                 # terrain grid spacing (m)
const N := 128                 # cells per side (HALF * 2 / S)
const TRAIL_W := 0.62          # half width of the dirt tread
const C_DIRT := Color(0.47, 0.36, 0.25)
const C_DIRT_D := Color(0.36, 0.27, 0.19)
const C_HUMUS := Color(0.27, 0.21, 0.15)
const C_GRASS := Color(0.29, 0.42, 0.18)
const C_GRASS2 := Color(0.36, 0.48, 0.2)
const C_MOSS := Color(0.3, 0.42, 0.18)
const C_STONE := Color(0.47, 0.45, 0.41)
const C_ROOT := Color(0.36, 0.27, 0.19)
const C_LEAVES := [Color(0.5, 0.34, 0.18), Color(0.58, 0.45, 0.22), Color(0.42, 0.28, 0.15), Color(0.48, 0.42, 0.24), Color(0.36, 0.28, 0.18)]

## loop control points (closed)
const CTRL := [
	Vector2(0, 23), Vector2(9, 21.5), Vector2(16.5, 15), Vector2(21, 5), Vector2(19.5, -5),
	Vector2(14, -14), Vector2(5, -20), Vector2(-5, -21), Vector2(-14, -16.5), Vector2(-20.5, -7),
	Vector2(-22, 4), Vector2(-17, 14), Vector2(-8.5, 21),
]

## sections by distance along the trail (m)
const SEC := {
	"start": [0.0, 9.0], "roots": [9.0, 26.0], "logs": [26.0, 45.0], "rocks": [45.0, 60.0],
	"ledges": [60.0, 75.0], "drops": [75.0, 86.0], "creek": [86.0, 97.0], "debris": [97.0, 999.0],
}

static var lv: Node3D
static var ridge := Vector2.ZERO        # top of the ridge the ledge section climbs (on the trail)
static var hs := PackedFloat32Array()
static var pts: Array[Vector2] = []     # trail centre line, every ~0.25 m
static var dist_s := PackedFloat32Array()
static var trail_len := 0.0
static var _grid := {}                 # 2 m cells -> point indices (fast nearest lookups)
static var _lo: FastNoiseLite
static var _mid: FastNoiseLite
static var _hi: FastNoiseLite
static var creek_s := 0.0
static var creek_a := Vector2.ZERO
static var creek_b := Vector2.ZERO
static var _blockers: Array = []       # [Vector2, r] spots the trees keep clear of
static var markers: Array = []         # [name, s] for the hud / tour


# ------------------------------------------------------------------ trail line
static func _build_line() -> void:
	pts.clear()
	var m := CTRL.size()
	for i in m:
		var p0: Vector2 = CTRL[(i - 1 + m) % m]
		var p1: Vector2 = CTRL[i]
		var p2: Vector2 = CTRL[(i + 1) % m]
		var p3: Vector2 = CTRL[(i + 2) % m]
		var segs := int(p1.distance_to(p2) / 0.25)
		for k in segs:
			var t := float(k) / segs
			var t2 := t * t
			var t3 := t2 * t
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	# a bit of wander so it isn't a perfect spline
	for i in pts.size():
		var p := pts[i]
		pts[i] = p + Vector2(sin(p.y * 0.9 + 1.3), cos(p.x * 0.8)) * 0.18
	dist_s.resize(pts.size() + 1)
	dist_s[0] = 0.0
	for i in pts.size():
		dist_s[i + 1] = dist_s[i] + pts[i].distance_to(pts[(i + 1) % pts.size()])
	trail_len = dist_s[pts.size()]
	_grid.clear()
	for i in pts.size():
		var c := Vector2i(floori(pts[i].x / 2.0), floori(pts[i].y / 2.0))
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(i)


## [distance to the centre line, s along it, signed side (+ = left of travel)]
static func nearest(x: float, z: float) -> Array:
	var p := Vector2(x, z)
	var c := Vector2i(floori(x / 2.0), floori(z / 2.0))
	var best := 1e9
	var bi := -1
	for r in [1, 3]:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var key := c + Vector2i(dx, dz)
				if not _grid.has(key):
					continue
				for i in _grid[key]:
					var d := p.distance_squared_to(pts[i])
					if d < best:
						best = d
						bi = i
		if bi >= 0:
			break
	if bi < 0:
		return [99.0, 0.0, 0.0]
	# refine on the two neighbouring segments
	var n := pts.size()
	var out := [sqrt(best), dist_s[bi], 0.0]
	for j in [bi, (bi - 1 + n) % n]:
		var a := pts[j]
		var b := pts[(j + 1) % n]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d <= out[0] + 1e-5:
			var side := signf(ab.cross(p - a))
			out = [d, dist_s[j] + ab.length() * t, side]
	return out


## trail point + heading at distance s
static func at(s: float) -> Array:
	s = fposmod(s, trail_len)
	var lo := 0
	var hi := pts.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if dist_s[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var a := pts[lo]
	var b := pts[(lo + 1) % pts.size()]
	var seg := dist_s[lo + 1] - dist_s[lo]
	var t := (s - dist_s[lo]) / maxf(seg, 1e-6)
	var p := a.lerp(b, t)
	var d := (b - a).normalized()
	return [p, d]


static func section(s: float) -> String:
	for k in SEC:
		var r: Array = SEC[k]
		if s >= r[0] and s < r[1]:
			return k
	return "debris"


# ------------------------------------------------------------------ terrain
static func _noises() -> void:
	_lo = FastNoiseLite.new()
	_lo.seed = 9101
	_lo.frequency = 0.035
	_lo.fractal_octaves = 3
	_mid = FastNoiseLite.new()
	_mid.seed = 77
	_mid.frequency = 0.22
	_mid.fractal_octaves = 2
	_hi = FastNoiseLite.new()
	_hi.seed = 5
	_hi.frequency = 1.1
	_hi.fractal_octaves = 1


static func _base(x: float, z: float) -> float:
	var h := 0.5 + _lo.get_noise_2d(x, z) * 1.5
	# the ridge the ledge section climbs over
	var dr := Vector2(x, z).distance_to(ridge) / 9.0
	h += 2.3 * exp(-dr * dr)
	# hills around the edge so the loop sits in a hollow
	var edge := maxf(absf(x), absf(z))
	h += smoothstep(25.0, HALF, edge) * 3.5
	# lumpy forest floor
	h += _mid.get_noise_2d(x, z) * 0.16
	return h


static func height(x: float, z: float) -> float:
	var h := _base(x, z)
	var nr := nearest(x, z)
	var d: float = nr[0]
	var s: float = nr[1]
	if d < 4.0:
		# the tread: a smoothed version of the ground, sunk a little, with ruts and lumps
		var hc := _center_h(s)
		# the ridge section is a straight grade up to the crest and down again, so the stone
		# steps sit in an even staircase
		var l0: float = SEC.ledges[0] - 2.0
		var l1: float = SEC.drops[1] + 2.0
		if s > l0 and s < l1:
			var w := smoothstep(l0, l0 + 2.0, s) * (1.0 - smoothstep(l1 - 2.0, l1, s))
			hc = lerpf(hc, _stair_bed(s), w)
		var bed := hc - 0.06 * (1.0 - smoothstep(0.3, 1.0, d))
		# two worn ruts and a crown, then fine lumps
		bed -= 0.025 * exp(-pow((d - 0.28) / 0.12, 2.0))
		bed += _hi.get_noise_2d(x * 1.0, z * 1.0) * 0.035
		h = lerpf(h, bed, 1.0 - smoothstep(0.7, 2.6, d))
	# creek ditch across the trail
	var dc := _creek_dist(x, z)
	if dc < 2.0:
		h -= 0.55 * (1.0 - smoothstep(0.45, 1.05, dc))
	return h


## natural height of the trail centre line at s (before the ridge staircase is laid in)
static func _center_h(s: float) -> float:
	var cp: Vector2 = at(s)[0]
	var hc := 0.5 + _lo.get_noise_2d(cp.x, cp.y) * 1.5
	var dr := cp.distance_to(ridge) / 9.0
	hc += 2.3 * exp(-dr * dr)
	hc += smoothstep(25.0, HALF, maxf(absf(cp.x), absf(cp.y))) * 3.5
	hc += _mid.get_noise_2d(cp.x, cp.y) * 0.05
	return hc


static var _stair := PackedFloat32Array([0.0, 0.0, 0.0])

## straight grade bed over the ridge: up from before the ledges to the crest, down to after the drops
static func _stair_bed(s: float) -> float:
	var l0: float = SEC.ledges[0] - 2.0
	var cr: float = SEC.ledges[1]
	var l1: float = SEC.drops[1] + 2.0
	if s < cr:
		return lerpf(_stair[0], _stair[1], clampf((s - l0) / (cr - l0), 0.0, 1.0))
	return lerpf(_stair[1], _stair[2], clampf((s - cr) / (l1 - cr), 0.0, 1.0))


static func _creek_dist(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var ab := creek_b - creek_a
	var t := clampf((p - creek_a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var q := creek_a + ab * t
	# wobble the banks so it isn't a ruler line
	return p.distance_to(q) + sin(t * 23.0) * 0.06


## exact height of the triangulated ground (matches the collider)
static func surface_y(x: float, z: float) -> float:
	var fx := (x + HALF) / S
	var fz := (z + HALF) / S
	var ix := clampi(floori(fx), 0, N - 1)
	var iz := clampi(floori(fz), 0, N - 1)
	var u := clampf(fx - ix, 0.0, 1.0)
	var v := clampf(fz - iz, 0.0, 1.0)
	var h00 := hs[iz * (N + 1) + ix]
	var h10 := hs[iz * (N + 1) + ix + 1]
	var h01 := hs[(iz + 1) * (N + 1) + ix]
	var h11 := hs[(iz + 1) * (N + 1) + ix + 1]
	# triangles split along the 00 -> 11 diagonal
	if u >= v:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h11 - h01) * u + (h01 - h00) * v


static func ground(x: float, z: float) -> Vector3:
	return Vector3(x, surface_y(x, z), z)


static func surface_at(x: float, z: float) -> String:
	var nr := nearest(x, z)
	return "dirt" if nr[0] < TRAIL_W + 0.25 else "grass"


static func _color(x: float, z: float, h: float, rng: RandomNumberGenerator) -> Color:
	var nr := nearest(x, z)
	var d: float = nr[0]
	var c := C_GRASS.lerp(C_GRASS2, clampf(0.5 + _mid.get_noise_2d(x * 3.0, z * 3.0) * 2.0, 0.0, 1.0))
	# leaf litter and humus under the trees, moss in the hollows
	var litter := clampf(0.5 + _lo.get_noise_2d(x * 4.0 + 50.0, z * 4.0) * 2.2, 0.0, 1.0)
	c = c.lerp(C_HUMUS.lerp(Color(0.5, 0.33, 0.16), 0.4), litter * 0.55)
	if d < 1.3:
		var tread := 1.0 - smoothstep(TRAIL_W - 0.15, 1.3, d)
		var dirt := C_DIRT.lerp(C_DIRT_D, clampf(0.5 + _hi.get_noise_2d(x * 2.0, z * 2.0) * 1.5, 0.0, 1.0))
		if d > 0.18 and d < 0.38:
			dirt = dirt.darkened(0.12)   # ruts
		c = c.lerp(dirt, tread)
	if _creek_dist(x, z) < 1.0:
		c = c.lerp(Color(0.25, 0.22, 0.17), 0.7)
	var j := rng.randf_range(-0.03, 0.03)
	return Color(c.r + j, c.g + j, c.b + j * 0.7)


static func _terrain() -> void:
	hs.resize((N + 1) * (N + 1))
	for iz in N + 1:
		for ix in N + 1:
			hs[iz * (N + 1) + ix] = height(ix * S - HALF, iz * S - HALF)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var tile := 16
	for tz in range(0, N, tile):
		for tx in range(0, N, tile):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var faces := PackedVector3Array()
			for iz in range(tz, tz + tile):
				for ix in range(tx, tx + tile):
					var x0 := ix * S - HALF
					var z0 := iz * S - HALF
					var p00 := Vector3(x0, hs[iz * (N + 1) + ix], z0)
					var p10 := Vector3(x0 + S, hs[iz * (N + 1) + ix + 1], z0)
					var p01 := Vector3(x0, hs[(iz + 1) * (N + 1) + ix], z0 + S)
					var p11 := Vector3(x0 + S, hs[(iz + 1) * (N + 1) + ix + 1], z0 + S)
					for tri in [[p00, p10, p11], [p00, p11, p01]]:
						var a: Vector3 = tri[0]
						var b: Vector3 = tri[1]
						var c: Vector3 = tri[2]
						var nrm := (c - a).cross(b - a).normalized()
						var cen := (a + b + c) / 3.0
						var col := _color(cen.x, cen.z, cen.y, rng)
						for v in [a, b, c]:
							st.set_normal(nrm)
							st.set_color(col)
							st.add_vertex(v)
							faces.append(v)
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = LowPoly.mat(Color.WHITE, 0.95)
			mi.name = "Ground_%d_%d" % [tx, tz]
			lv.add_child(mi)
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(faces)
			cs.shape = sh
			sb.add_child(cs)
			sb.set_meta("surface_at", func(p: Vector3) -> String: return TrailLevel.surface_at(p.x, p.z))
			sb.name = "GroundBody_%d_%d" % [tx, tz]
			lv.add_child(sb)
	# walls at the edge
	for sgn in [-1, 1]:
		_wall(Vector3(sgn * (HALF - 0.5), 8, 0), Vector3(0.5, 20, HALF * 2))
		_wall(Vector3(0, 8, sgn * (HALF - 0.5)), Vector3(HALF * 2, 20, 0.5))
	# beyond the edge: ground + a ring of far trees so there's no void
	for sx in [-1, 1]:
		LowPoly.part(lv, LowPoly.box(0.0), Color(0.26, 0.36, 0.18), Vector3(sx * (HALF + 100.0 - 0.3), 3.9, 0), Vector3(200, 0.2, 400))
		LowPoly.part(lv, LowPoly.box(0.0), Color(0.26, 0.36, 0.18), Vector3(0, 3.9, sx * (HALF + 100.0 - 0.3)), Vector3(400, 0.2, 200))
	var r2 := RandomNumberGenerator.new()
	r2.seed = 12
	for k in 80:
		var a := k * TAU / 80.0 + r2.randf_range(-0.03, 0.03)
		var rad := r2.randf_range(34.0, 52.0)
		var p := Vector3(cos(a) * rad, 3.9, sin(a) * rad)
		var th := r2.randf_range(7.0, 12.0)
		LowPoly.part(lv, LowPoly.cyl(0.0, 0.5, 6), ForestLevel.C_PINE.darkened(r2.randf() * 0.25), p + Vector3(0, th * 0.5, 0), Vector3(3.0, th, 3.0))


static func _wall(c: Vector3, s: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	sb.add_child(cs)
	sb.position = c
	lv.add_child(sb)


# ------------------------------------------------------------------ props
## trail frame at s: [centre point on the ground, forward, left]
static func frame(s: float, side_off := 0.0) -> Array:
	var a := at(s)
	var p: Vector2 = a[0]
	var d: Vector2 = a[1]
	var left := Vector2(d.y, -d.x)
	var q := p + left * side_off
	return [ground(q.x, q.y), Vector3(d.x, 0, d.y), Vector3(left.x, 0, left.y)]


## a log lying across the trail at s (radius r, sunk a little into the dirt)
static func log_across(s: float, r: float, len: float, skew := 0.0, sink := 0.25) -> void:
	var f := frame(s)
	var c: Vector3 = f[0]
	var fwd: Vector3 = f[1]
	var left: Vector3 = (f[2] as Vector3).rotated(Vector3.UP, skew)
	var a := c + left * len * 0.5
	var b := c - left * len * 0.5
	a.y = surface_y(a.x, a.z) + r * (1.0 - sink)
	b.y = surface_y(b.x, b.z) + r * (1.0 - sink)
	# not climbable: bumping one mid-bound should scramble over it (ledge), not cling to it
	var node := ForestLevel.fallen_log(a, b, r, false)
	node.set_meta("surface", "wood")
	node.add_to_group("scratchable")
	# bark knots + a broken branch stub
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s * 100)
	for k in 3:
		var t := rng.randf_range(0.15, 0.85)
		var p := a.lerp(b, t)
		var ang := rng.randf() * TAU
		var off := (Vector3.UP * cos(ang) + fwd * sin(ang)) * r
		LowPoly.part(lv, LowPoly.box(0.1), ForestLevel.C_BARK_D, p + off, Vector3(0.05, 0.05, 0.05) + Vector3.ONE * r * 0.2, Vector3(rng.randf(), rng.randf(), rng.randf()))
	_blockers.append([Vector2(c.x, c.z), len * 0.5 + 0.5])


## a low stump on the trail (to hop onto / over). not climbable, it's a step not a tree
static func low_stump(pos: Vector3, r: float, h: float) -> void:
	var s := ForestLevel._cyl_body(pos + Vector3(0, h * 0.5, 0), Basis(), r, h, ForestLevel.C_BARK, 8)
	s.set_meta("surface", "wood")
	s.add_to_group("scratchable")
	LowPoly.part(lv, LowPoly.cyl(0.5, 0.5, 8), Color(0.74, 0.6, 0.42), pos + Vector3(0, h + 0.005, 0), Vector3(r * 1.9, 0.01, r * 1.9))
	LowPoly.part(lv, LowPoly.cyl(0.5, 0.5, 8), Color(0.55, 0.42, 0.28), pos + Vector3(0, h + 0.007, 0), Vector3(r * 1.0, 0.01, r * 1.0))


## flat topped stone slab (a step / a rock to land on). top centre given
static func slab(top: Vector3, size: Vector3, yaw: float, col := C_STONE) -> Node3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = top - Vector3(0, size.y * 0.5, 0)
	sb.rotation.y = yaw
	sb.set_meta("surface", "stone")
	lv.add_child(sb)
	var mi := MeshInstance3D.new()
	mi.mesh = _stone_mesh(size, int(top.x * 97.0 + top.z * 31.0), col)
	mi.material_override = LowPoly.mat(Color.WHITE, 0.92)
	sb.add_child(mi)
	return sb


## a weathered block of stone: a subdivided box with every vertex nudged, the edges knocked in so
## it reads as rock not a crate, the top kept near flat (it's walked on), flat shaded with lichen
## and moss on some of the up facing facets
static func _stone_mesh(size: Vector3, seed_i: int, col: Color) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.subdivide_width = 2
	bm.subdivide_height = 1
	bm.subdivide_depth = 2
	var arr := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	var moved := {}
	for i in verts.size():
		var v := verts[i]
		var key := v.snapped(Vector3.ONE * 0.001)
		if not moved.has(key):
			rng.seed = hash(key) ^ seed_i
			var w := v
			# round off the corners and edges
			var edge := (absf(v.x) > 0.49 as int) + (absf(v.y) > 0.49 as int) + (absf(v.z) > 0.49 as int)
			var shrink := 0.0
			if edge >= 2:
				shrink = rng.randf_range(0.04, 0.11)
			w.x *= 1.0 - shrink * (1.0 if absf(v.y) > 0.49 else 0.5)
			w.z *= 1.0 - shrink * (1.0 if absf(v.y) > 0.49 else 0.5)
			w = w * size
			w.x += rng.randf_range(-0.04, 0.04) * size.x
			w.z += rng.randf_range(-0.04, 0.04) * size.z
			if v.y > 0.49:
				w.y += rng.randf_range(-0.012, 0.008) - (0.02 if edge >= 2 else 0.0)
			elif v.y > -0.49:
				w.y += rng.randf_range(-0.03, 0.03)
			moved[key] = w
		verts[i] = moved[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	rng.seed = seed_i
	var base := col.lightened(rng.randf_range(-0.05, 0.05))
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if n.dot((a + b + c) / 3.0) < 0.0:
			n = -n
			var tmp := b
			b = c
			c = tmp
		var cc := base.lightened(ForestLevel._hash3(a + c) * 0.07)
		if n.y > 0.8:
			var r := absf(ForestLevel._hash3(a * 3.1 + b))
			if r < 0.3:
				cc = C_MOSS.lightened(r * 0.2)
			elif r < 0.42:
				cc = Color(0.55, 0.56, 0.45)   # pale lichen
		elif n.y < -0.5:
			cc = cc.darkened(0.3)
		for v in [a, c, b]:
			st.set_normal(n)
			st.set_color(cc)
			st.add_vertex(v)
	return st.commit()


## a gnarly surface root from a tree base out across the ground: chain of tapered segments,
## half buried, each with a thin collider (roots are what the step up glides over)
static func root(from: Vector3, dir: Vector3, len: float, r0: float, rng: RandomNumberGenerator) -> void:
	var segs := int(len / 0.35) + 1
	var p := from
	var d := dir.normalized()
	for k in segs:
		var t := float(k) / segs
		var r := lerpf(r0, r0 * 0.3, t)
		d = d.rotated(Vector3.UP, rng.randf_range(-0.35, 0.35)).normalized()
		var q := p + d * (len / segs)
		q.y = surface_y(q.x, q.z) + r * 0.35
		var pp := Vector3(p.x, surface_y(p.x, p.z) + lerpf(r0, r0 * 0.3, maxf(t - 1.0 / segs, 0.0)) * 0.35, p.z)
		if k == 0:
			pp.y = from.y
		var mid := (pp + q) * 0.5
		var axis := q - pp
		var l := axis.length()
		var y := axis / l
		var x := y.cross(Vector3.UP).normalized() if absf(y.y) < 0.95 else Vector3.RIGHT
		var z := x.cross(y).normalized()
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = l + r
		cs.shape = sh
		sb.add_child(cs)
		sb.transform = Transform3D(Basis(x, y, z), mid)
		sb.set_meta("surface", "wood")
		lv.add_child(sb)
		LowPoly.part(sb, LowPoly.cyl(0.42, 0.5, 6), C_ROOT.lightened(rng.randf() * 0.08), Vector3.ZERO, Vector3(r * 2.0, l + r * 1.2, r * 2.0))
		p = q
		# side rootlets (visual)
		if rng.randf() < 0.45:
			var sd := d.rotated(Vector3.UP, rng.randf_range(0.6, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0))
			var e := p + sd * rng.randf_range(0.2, 0.45)
			e.y = surface_y(e.x, e.z)
			var xf := LowPoly.seg_xform(e, p)
			var mi := MeshInstance3D.new()
			mi.mesh = LowPoly.cyl(0.4, 0.5, 5)
			mi.material_override = LowPoly.mat(C_ROOT.darkened(0.1))
			mi.transform = Transform3D(xf.basis * Basis.from_scale(Vector3(r * 0.9, 1.0, r * 0.9)), xf.origin)
			lv.add_child(mi)


## dead branch lying on the ground with a collider (they're under the step height: glide over)
static func branch(p: Vector3, yaw: float, len: float, r: float, rng: RandomNumberGenerator) -> void:
	var d := Vector3(cos(yaw), 0, sin(yaw))
	var a := p - d * len * 0.5
	var b := p + d * len * 0.5
	a.y = surface_y(a.x, a.z) + r * 0.8
	b.y = surface_y(b.x, b.z) + r * 0.8
	var axis := b - a
	var l := axis.length()
	var y := axis / l
	var x := y.cross(Vector3.UP).normalized()
	var z := x.cross(y).normalized()
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = l
	cs.shape = sh
	sb.add_child(cs)
	sb.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	sb.set_meta("surface", "wood")
	lv.add_child(sb)
	LowPoly.part(sb, LowPoly.cyl(0.6, 0.5, 5), Color(0.42, 0.33, 0.24).lightened(rng.randf() * 0.1), Vector3.ZERO, Vector3(r * 2.0, l, r * 2.0))
	# twiggy offshoots
	for k in rng.randi_range(1, 3):
		var t := rng.randf_range(0.2, 0.8)
		var s := (t - 0.5) * l
		var ang := rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		LowPoly.part(sb, LowPoly.box(0.0), Color(0.4, 0.31, 0.22), Vector3(0, s, 0) + Vector3(sin(ang), 0, cos(ang)) * 0.08, Vector3(r * 0.9, 0.18, r * 0.9), Vector3(0, 0, ang))


## a small loose stone (collider) sitting in the dirt
static func stone(p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	ForestLevel.rock(Vector3(p.x, surface_y(p.x, p.z) + s * 0.12, p.z), Vector3(s * rng.randf_range(1.0, 1.5), s, s * rng.randf_range(0.9, 1.4)), rng.randf() * TAU, C_STONE.lightened(rng.randf_range(-0.08, 0.06)), rng.randf() < 0.4)


# ------------------------------------------------------------------ sections
static func _sections(rng: RandomNumberGenerator) -> void:
	# --- start: packed dirt, a few loose stones and twigs to glide over
	for s in [3.0, 5.5, 7.5]:
		var f := frame(s, rng.randf_range(-0.3, 0.3))
		stone(f[0], rng.randf_range(0.05, 0.08), rng)
	# --- roots: two old oaks right beside the path throw roots across it
	for spec in [[12.5, 1.6], [19.0, -1.7], [23.5, 1.5]]:
		var f := frame(spec[0], spec[1])
		var base: Vector3 = f[0]
		ForestLevel.oak(base - Vector3(0, 0.1, 0), rng.randf_range(6.5, 8.0), rng)
		_blockers.append([Vector2(base.x, base.z), 2.6])
		var left: Vector3 = f[2]
		var toward := -left * signf(spec[1])
		for k in 7:
			var dir := toward.rotated(Vector3.UP, rng.randf_range(-1.0, 1.0))
			var r0 := rng.randf_range(0.04, 0.075)
			root(base + Vector3(0, r0 * 0.6, 0) + dir * 0.3, dir, rng.randf_range(2.2, 4.0), r0, rng)
		for k in 4:
			var dir := (-toward).rotated(Vector3.UP, rng.randf_range(-1.3, 1.3))
			root(base + Vector3(0, 0.05, 0) + dir * 0.3, dir, rng.randf_range(1.0, 2.0), 0.06, rng)
	# --- logs: hurdles of every size, a couple skewed, one with a smaller log behind it
	var logs := [[28.5, 0.09], [31.5, 0.13], [35.0, 0.17], [38.5, 0.21], [41.5, 0.12], [43.6, 0.15]]
	for i in logs.size():
		var spec: Array = logs[i]
		log_across(spec[0], spec[1], rng.randf_range(2.2, 2.8), rng.randf_range(-0.25, 0.25))
	# --- rock garden: lumpy rocks to clear, flat slabs to land on
	var rocks := [[46.5, 0.25, 0.18], [48.0, -0.2, 0.3], [49.6, 0.1, 0.24], [52.8, -0.3, 0.2], [56.5, 0.25, 0.32], [58.6, -0.1, 0.22]]
	for spec in rocks:
		var f := frame(spec[0], spec[1])
		var hgt: float = spec[2]
		ForestLevel.rock((f[0] as Vector3) + Vector3(0, hgt * 0.22, 0), Vector3(hgt * 1.7, hgt * 1.3, hgt * 1.5), rng.randf() * TAU, C_STONE.lightened(rng.randf_range(-0.1, 0.05)), true)
	for spec in [[51.0, 0.0, 0.27, 0.9], [54.6, 0.1, 0.33, 1.1]]:
		var f := frame(spec[0], spec[1])
		var c: Vector3 = f[0]
		var fwd: Vector3 = f[1]
		var top := c + Vector3(0, spec[2], 0)
		var yaw := atan2(-fwd.x, -fwd.z)
		slab(top, Vector3(1.3, (spec[2] as float) + 0.25, spec[3]), yaw, C_STONE.darkened(0.05))
	for k in 14:
		var s := rng.randf_range(45.0, 60.0)
		var f := frame(s, rng.randf_range(-0.7, 0.7))
		stone(f[0], rng.randf_range(0.04, 0.09), rng)
	# boulders flanking
	for k in 6:
		var s := rng.randf_range(45.0, 60.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var f := frame(s, side * rng.randf_range(1.4, 2.4))
		var sz := rng.randf_range(0.5, 1.1)
		ForestLevel.rock((f[0] as Vector3) + Vector3(0, sz * 0.2, 0), Vector3(sz * 1.3, sz, sz * 1.2), rng.randf() * TAU)
	# --- ledges: stone steps up the ridge, an even staircase of 20-30 cm risers on the straight grade
	var sa: float = SEC.ledges[0] + 0.5
	var sb: float = SEC.ledges[1] - 0.6
	var gain := _stair_bed(sb) - _stair_bed(sa)
	var nst := maxi(int(round(gain / 0.25)), 1)
	var tread := (sb - sa) / nst
	for k in nst:
		var sf := sa + k * tread
		var sk := sf + tread
		var f := frame((sf + sk) * 0.5)
		var c: Vector3 = f[0]
		var fwd: Vector3 = f[1]
		var top_y := _stair_bed(sk) + 0.1
		var hgt := top_y - _stair_bed(sf) + 0.25
		var yaw := atan2(-fwd.x, -fwd.z)
		slab(Vector3(c.x, top_y, c.z), Vector3(rng.randf_range(1.5, 1.9), hgt, tread + 0.03), yaw + rng.randf_range(-0.06, 0.06))
	# boulders along the ridge
	for k in 7:
		var ss := rng.randf_range(SEC.ledges[0], SEC.drops[1])
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var f := frame(ss, side * rng.randf_range(1.5, 3.0))
		var sz := rng.randf_range(0.6, 1.5)
		ForestLevel.rock((f[0] as Vector3) + Vector3(0, sz * 0.15, 0), Vector3(sz * 1.3, sz, sz * 1.2), rng.randf() * TAU)
	# --- drops: down the far side off stone lips, ~30 cm each (runs off them, the landing is in the rig)
	sa = SEC.ledges[1] + 0.4
	sb = SEC.drops[1]
	var loss := _stair_bed(sa) - _stair_bed(sb)
	nst = maxi(int(round(loss / 0.3)), 1)
	tread = (sb - sa) / nst
	for k in nst:
		var sf := sa + k * tread
		var sk := sf + tread
		var f := frame((sf + sk) * 0.5)
		var c: Vector3 = f[0]
		var fwd: Vector3 = f[1]
		var top_y := _stair_bed(sf) + 0.1
		var hgt := top_y - _stair_bed(sk) + 0.25
		var yaw := atan2(-fwd.x, -fwd.z)
		slab(Vector3(c.x, top_y, c.z), Vector3(rng.randf_range(1.5, 1.9), hgt, tread - 0.05), yaw + rng.randf_range(-0.06, 0.06))
	# --- creek: stones lining the banks + water
	_creek_props(rng)
	# --- debris: a bit of everything
	var dstart: float = SEC.debris[0]
	var stuff := [
		[dstart + 2.0, "stump", 0.22], [dstart + 4.5, "log", 0.11], [dstart + 6.0, "rock", 0.2],
		[dstart + 8.5, "stump", 0.3], [dstart + 10.5, "log", 0.16], [dstart + 12.0, "rock", 0.26],
		[dstart + 14.5, "log", 0.1], [dstart + 16.5, "rock", 0.15], [dstart + 18.5, "stump", 0.18],
	]
	for spec in stuff:
		var off := rng.randf_range(-0.25, 0.25)
		var f := frame(spec[0], off)
		match spec[1]:
			"stump":
				var c: Vector3 = f[0]
				low_stump(c - Vector3(0, 0.03, 0), rng.randf_range(0.17, 0.24), spec[2])
			"log":
				log_across(spec[0], spec[2], rng.randf_range(1.8, 2.8), rng.randf_range(-0.4, 0.4))
			"rock":
				ForestLevel.rock((f[0] as Vector3) + Vector3(0, (spec[2] as float) * 0.22, 0), Vector3(spec[2] * 1.6, spec[2] * 1.3, spec[2] * 1.4), rng.randf() * TAU, C_STONE, true)
	# branches (step-height) and small stones all round the loop, kept off the hurdles a little
	for k in 46:
		var ss := rng.randf() * trail_len
		var sec := section(ss)
		if sec == "ledges" or sec == "creek":
			continue
		var f := frame(ss, rng.randf_range(-0.5, 0.5))
		var fwd: Vector3 = f[1]
		var yaw := atan2(fwd.z, fwd.x) + PI * 0.5 + rng.randf_range(-0.6, 0.6)
		if rng.randf() < 0.55:
			branch(f[0], yaw, rng.randf_range(0.4, 1.1), rng.randf_range(0.012, 0.03), rng)
		else:
			stone(f[0], rng.randf_range(0.035, 0.07), rng)


static func _creek_props(rng: RandomNumberGenerator) -> void:
	var c := Vector3(creek_a.x, 0, creek_a.y).lerp(Vector3(creek_b.x, 0, creek_b.y), 0.5)
	var d := (creek_b - creek_a).normalized()
	var n := 24
	# water: flat strips following the creek bed
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.32, 0.36)
	wm.roughness = 0.05
	wm.metallic_specular = 0.9
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var a := creek_a.lerp(creek_b, t0)
		var b := creek_a.lerp(creek_b, t1)
		var m := (a + b) * 0.5
		var bed := surface_y(m.x, m.y)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.02, a.distance_to(b) + 0.05)
		mi.mesh = bm
		mi.material_override = wm
		mi.position = Vector3(m.x, bed + 0.12, m.y)
		mi.rotation.y = atan2(d.x, d.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lv.add_child(mi)
	# bank stones (off the trail tread so the jump stays clean) + pebbles in the bed
	for k in 40:
		var t := rng.randf()
		var p := creek_a.lerp(creek_b, t)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var q := p + Vector2(-d.y, d.x) * side * rng.randf_range(0.75, 1.1)
		if nearest(q.x, q.y)[0] < TRAIL_W + 0.3:
			continue
		var sz := rng.randf_range(0.12, 0.35)
		ForestLevel.rock(Vector3(q.x, surface_y(q.x, q.y) + sz * 0.1, q.y), Vector3(sz * 1.4, sz, sz * 1.2), rng.randf() * TAU, C_STONE.darkened(rng.randf() * 0.15), true)


# ------------------------------------------------------------------ trees + scatter
static func _ok_tree(p: Vector2, gap: float) -> bool:
	if nearest(p.x, p.y)[0] < 1.6 or _creek_dist(p.x, p.y) < 1.6:
		return false
	for b in _blockers:
		if p.distance_to(b[0]) < (b[1] as float) + gap * 0.5:
			return false
	return true


static func _trees(rng: RandomNumberGenerator) -> void:
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 110 and tries < 6000:
		tries += 1
		var p := Vector2(rng.randf_range(-29, 29), rng.randf_range(-29, 29))
		if not _ok_tree(p, 0.0):
			continue
		var ok := true
		for q in placed:
			if p.distance_to(q) < 2.6:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var g := ground(p.x, p.y) - Vector3(0, 0.1, 0)
		var roll := rng.randf()
		if roll < 0.5:
			ForestLevel.pine(g, rng.randf_range(7.0, 12.5), rng)
		elif roll < 0.75:
			ForestLevel.oak(g, rng.randf_range(5.0, 7.0), rng)
		else:
			ForestLevel.birch(g, rng.randf_range(5.0, 8.0), rng)
		_blockers.append([p, 0.8])
		# a couple of short roots flaring at the base
		if nearest(p.x, p.y)[0] < 3.5:
			for k in 3:
				var dir := Vector3(cos(k * 2.1 + rng.randf()), 0, sin(k * 2.1 + rng.randf()))
				root(ground(p.x, p.y) + dir * 0.2 + Vector3(0, 0.04, 0), dir, rng.randf_range(0.6, 1.3), 0.05, rng)
		if rng.randf() < 0.3:
			var a := rng.randf() * TAU
			var bp := p + Vector2(cos(a), sin(a)) * 1.4
			if nearest(bp.x, bp.y)[0] > 1.4:
				ForestLevel.bush(ground(bp.x, bp.y), rng.randf_range(0.7, 1.2), rng, rng.randf() < 0.25)
	# fallen trees off the trail, stumps, boulders
	for k in 8:
		var p := Vector2(rng.randf_range(-27, 27), rng.randf_range(-27, 27))
		var a := rng.randf() * TAU
		var dl := Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 3.5)
		if not _ok_tree(p, 0.0) or not _ok_tree(p + dl, 0.0) or not _ok_tree(p - dl, 0.0):
			continue
		var r := rng.randf_range(0.18, 0.32)
		ForestLevel.fallen_log(ground(p.x - dl.x, p.y - dl.y) + Vector3(0, r * 0.8, 0), ground(p.x + dl.x, p.y + dl.y) + Vector3(0, r * 0.8, 0), r)
	for k in 30:
		var p := Vector2(rng.randf_range(-28, 28), rng.randf_range(-28, 28))
		if not _ok_tree(p, 0.0):
			continue
		if rng.randf() < 0.4:
			ForestLevel.stump(ground(p.x, p.y), rng.randf_range(0.18, 0.3), rng.randf_range(0.25, 0.6))
		else:
			var s := rng.randf_range(0.35, 1.2)
			ForestLevel.rock(ground(p.x, p.y) + Vector3(0, s * 0.15, 0), Vector3(s * rng.randf_range(1.0, 1.5), s, s * rng.randf_range(0.9, 1.4)), rng.randf() * TAU)


## the fine stuff: gravel + pebbles on the tread, leaf litter, twigs, cones, grass, ferns, moss.
## multimeshes, no collision (the cat's paws just pass over them)
static func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	var sets := {
		"gravel": {"mesh": LowPoly.box(0.2), "n": 9000},
		"pebble": {"mesh": LowPoly.sphere(5, 3), "n": 2600},
		"leaf": {"mesh": LowPoly.box(0.0), "n": 14000},
		"twig": {"mesh": LowPoly.box(0.0), "n": 2400},
		"cone": {"mesh": LowPoly.sphere(5, 4), "n": 400},
		"grass": {"mesh": LowPoly.cyl(0.0, 0.5, 3), "n": 9000},
		"fern": {"mesh": LowPoly.cyl(0.0, 0.5, 5), "n": 700},
		"moss": {"mesh": LowPoly.box(0.0), "n": 900},
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
		while xfs.size() < want and tries < want * 5:
			tries += 1
			var x: float
			var z: float
			var on_trail: bool = key in ["gravel", "pebble"] or (key in ["leaf", "twig"] and rng.randf() < 0.35)
			if on_trail:
				var s := rng.randf() * trail_len
				var a := at(s)
				var p: Vector2 = a[0]
				var dd: Vector2 = a[1]
				var w := rng.randf_range(-1.0, 1.0)
				w = w * absf(w) * (TRAIL_W + 0.35)
				p += Vector2(dd.y, -dd.x) * w
				x = p.x
				z = p.y
			else:
				x = rng.randf_range(-HALF + 1, HALF - 1)
				z = rng.randf_range(-HALF + 1, HALF - 1)
			if _creek_dist(x, z) < 0.8 and key != "pebble":
				continue
			var h := surface_y(x, z)
			var td: float = nearest(x, z)[0]
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			match key:
				"gravel":
					var s := rng.randf_range(0.006, 0.016)
					xfs.append(Transform3D(b.scaled(Vector3(s, s * 0.6, s * 1.2)), Vector3(x, h + s * 0.15, z)))
					cols.append(C_STONE.lerp(C_DIRT, rng.randf() * 0.6).lightened(rng.randf_range(-0.1, 0.15)))
				"pebble":
					var s := rng.randf_range(0.018, 0.045)
					xfs.append(Transform3D(b.scaled(Vector3(s * 1.3, s * 0.7, s)), Vector3(x, h + s * 0.15, z)))
					cols.append(C_STONE.lightened(rng.randf_range(-0.15, 0.12)))
				"leaf":
					var s := rng.randf_range(0.018, 0.04)
					var tilt := Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.35))
					xfs.append(Transform3D((tilt * b).scaled(Vector3(s, 0.003, s * 1.4)), Vector3(x, h + 0.004, z)))
					cols.append((C_LEAVES[rng.randi() % C_LEAVES.size()] as Color).darkened(rng.randf() * 0.25 if td < TRAIL_W else rng.randf() * 0.1))
				"twig":
					var l := rng.randf_range(0.08, 0.32)
					var r := rng.randf_range(0.004, 0.009)
					xfs.append(Transform3D(b.scaled(Vector3(r, r, l)), Vector3(x, h + r, z)))
					cols.append(Color(0.4, 0.31, 0.22).lightened(rng.randf() * 0.15))
				"cone":
					if td < TRAIL_W:
						continue
					var s := rng.randf_range(0.03, 0.045)
					xfs.append(Transform3D(b.rotated(Vector3.RIGHT, PI * 0.5).scaled(Vector3(s, s * 1.6, s)), Vector3(x, h + s * 0.5, z)))
					cols.append(Color(0.42, 0.28, 0.16))
				"grass":
					if td < TRAIL_W + 0.15:
						continue
					var s := rng.randf_range(0.08, 0.28) * (0.6 if td < 1.2 else 1.0)
					xfs.append(Transform3D(b.scaled(Vector3(0.045, s, 0.045) * rng.randf_range(0.8, 1.4)), Vector3(x, h + s * 0.5, z)))
					cols.append(C_GRASS2.lerp(Color(0.62, 0.66, 0.32), rng.randf() * 0.6))
				"fern":
					if td < 1.2:
						continue
					var s := rng.randf_range(0.3, 0.6)
					xfs.append(Transform3D(b.scaled(Vector3(s, s * 0.35, s)), Vector3(x, h + s * 0.15, z)))
					cols.append(Color(0.24, 0.42, 0.18).lightened(rng.randf() * 0.1))
				"moss":
					if td < TRAIL_W + 0.1:
						continue
					var s := rng.randf_range(0.12, 0.35)
					xfs.append(Transform3D(b.scaled(Vector3(s, 0.01, s * rng.randf_range(0.6, 1.0))), Vector3(x, h + 0.006, z)))
					cols.append(C_MOSS.lightened(rng.randf() * 0.12))
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = LowPoly.mat(Color.WHITE, 0.9)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "Scatter_" + key
		lv.add_child(mmi)


# ------------------------------------------------------------------ build
static func build(root: Node3D) -> Dictionary:
	lv = Node3D.new()
	lv.name = "Trail"
	root.add_child(lv)
	# ForestLevel's builders write into its own node + lists
	ForestLevel.lv = lv
	ForestLevel.perches.clear()
	ForestLevel.trunks.clear()
	ForestLevel.obstacles.clear()
	ForestLevel.flowers.clear()
	_blockers.clear()
	_noises()
	_build_line()
	ridge = at(SEC.ledges[1])[0]
	# the creek crosses the trail at the start of the creek section, square to it
	creek_s = SEC.creek[0] + 5.0
	var cf := at(creek_s)
	var cp: Vector2 = cf[0]
	var cd: Vector2 = cf[1]
	var cn := Vector2(cd.y, -cd.x)
	creek_a = cp - cn * 9.0 + cd * 1.5
	creek_b = cp + cn * 9.0 - cd * 1.5
	_stair = PackedFloat32Array([_center_h(SEC.ledges[0] - 2.0), _center_h(SEC.ledges[1]) + 0.2, _center_h(SEC.drops[1] + 2.0)])
	_terrain()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	_sections(rng)
	_trees(rng)
	_scatter()
	ForestLevel.batch(lv)
	markers = []
	for k in SEC:
		markers.append([k, SEC[k][0]])
	var f := frame(0.3)
	var fwd: Vector3 = f[1]
	return {
		"spawn": (f[0] as Vector3) + Vector3(0, 0.06, 0),
		"spawn_yaw": atan2(-fwd.x, -fwd.z),
	}
