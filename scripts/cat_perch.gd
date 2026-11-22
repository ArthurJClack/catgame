class_name CatPerch
extends RefCounted
## perching: standing / sitting on top of something small or narrow (a fence top, a post, a
## railing, a branch, a bin lid, a box, a narrow ledge). real cats bunch all four paws onto
## whatever is there: fore paws right at the front edge, hind paws brought forward behind them,
## the back humped between, toes curled over the edges, the tail out as a counterweight.
##
## owned by the rig (`rig.perch`). every so often it feels out the top the cat is standing on
## with short down rays along the body's own axes (how far it goes left / right / ahead / behind
## before it drops away) and keeps a box of where paws can go, in rig space. the rig clamps each
## paw's home spot into that box, so the gait steps the paws onto the top by itself.
##
## static `perch` switch (CAT_OFF=perch = the old behaviour, paws step off into the air).

static var perch := true

const STEP := 0.012          # ray spacing along each axis
const MAX_X := 0.13          # how far out to feel to each side
const MAX_Z := 0.24          # ahead / behind
const DROP := 0.07           # the top has to fall away by this much to count as an edge
const TOL := 0.03            # still the same top: up / down by less than this
const EDGE_IN := 0.009       # paw centre this far in from an edge (the toes curl over it)
const PAIR_GAP := 0.034      # fore paws at least this far ahead of the hind paws
const RAIL_STAGGER := 0.014  # on a rail the left / right paws go one ahead of the other

var rig: Node3D
## 0..1 how much the paws are being fitted onto a small top (smoothed)
var w := 0.0
## 0..1 how narrow it is across the body (a fence top, a branch along the cat)
var narrow := 0.0
## 0..1 how short it is along the body: the stance doesn't fit, paws bunch (post, box, rail across)
var bunch := 0.0
## how much shorter the stance actually is this frame (0 none .. 1 all four paws together)
var squeeze := 0.0
## supported box in rig space (x across, z along, -z ahead) around the cat
var x0 := -MAX_X
var x1 := MAX_X
var z0 := -MAX_Z
var z1 := MAX_Z
var cx := 0.0     # box centre (rig space), what the body leans toward
var cz := 0.0
var top_y := 0.0  # rig space height of the top
var on := false   # the box limits the paws right now

var _t := 0.0
var _w_x := false
var _w_z := false
var _narrow_t := 0.0
var _bunch_t := 0.0
var _was_floor := true


## feel the top out (forced right after a landing, else every 0.1 s)
func update(dt: float, xf: Transform3D, on_floor: bool, speed: float, busy: bool) -> void:
	_t -= dt
	var landed := on_floor and not _was_floor
	_was_floor = on_floor
	if not perch or not on_floor or busy or rig == null or not rig.gait._can_ray():
		on = false
		_narrow_t = 0.0
		_bunch_t = 0.0
	elif _t <= 0.0 or landed:
		_t = 0.1
		_scan(xf, speed)
	w = LowPoly.damp(w, maxf(_narrow_t, _bunch_t), 8.0 if on else 4.0, dt)
	narrow = LowPoly.damp(narrow, _narrow_t, 6.0, dt)
	bunch = LowPoly.damp(bunch, _bunch_t, 6.0, dt)


## a ray straight down at rig space x,z: "top" (same height as the cat's), "drop" (falls away
## more than DROP, or nothing there), "step" (a little lower / higher, still ground), "wall"
func _probe(xf: Transform3D, x: float, z: float) -> String:
	var p := xf * Vector3(x, 0.0, z)
	var y0 := xf.origin.y
	var h: Array = rig.gait._ray(p.x, p.z, y0 + 0.045, y0 - 0.35, true)
	if h.is_empty():
		return "drop"
	if h.size() > 2:
		return "wall"
	var y: float = h[0]
	var ny: float = (h[1] as Vector3).y
	if absf(y - y0) <= TOL and ny > 0.6:
		return "top"
	if ny < 0.6 and y < y0 + TOL:
		return "drop"   # the rounded side of a branch / pole falling away
	if y > y0 + TOL:
		return "wall"
	return "step" if y > y0 - DROP else "drop"


## walks out from (sx, sz) along (dx, dz): [how far the top goes, what ends it]
func _reach(xf: Transform3D, sx: float, sz: float, dx: float, dz: float, mx: float) -> Array:
	var d := 0.0
	while d < mx:
		var nd := minf(d + STEP, mx)
		var k := _probe(xf, sx + dx * nd, sz + dz * nd)
		if k != "top":
			# the edge is between the last top sample and this one: close in on it
			var a := d
			var b := nd
			for _j in 3:
				var m := (a + b) * 0.5
				if _probe(xf, sx + dx * m, sz + dz * m) == "top":
					a = m
				else:
					b = m
			return [a, k]
		d = nd
	return [mx, "open"]


func _scan(xf: Transform3D, speed: float) -> void:
	var b := xf.basis.orthonormalized()
	var xfn := Transform3D(b, xf.origin)
	# the root may hang past the edge (the capsule rests on its rounded bottom): start from
	# the nearest bit of top under the body
	var sx := 0.0
	var sz := 0.0
	if _probe(xfn, 0.0, 0.0) != "top":
		var found := false
		for r in [0.03, 0.06]:
			for k in 8:
				var a := TAU * k / 8.0
				var ox: float = cos(a) * r
				var oz: float = sin(a) * r
				if _probe(xfn, ox, oz) == "top":
					sx = ox
					sz = oz
					found = true
					break
			if found:
				break
		if not found:
			on = false
			_narrow_t = 0.0
			_bunch_t = 0.0
			return
	var l := _reach(xfn, sx, sz, -1, 0, MAX_X + absf(sx))
	var r2 := _reach(xfn, sx, sz, 1, 0, MAX_X + absf(sx))
	var f := _reach(xfn, sx, sz, 0, -1, MAX_Z + absf(sz))
	var bk := _reach(xfn, sx, sz, 0, 1, MAX_Z + absf(sz))
	var wx := float(l[0]) + float(r2[0])
	var wz := float(f[0]) + float(bk[0])
	# an axis is a perch when it drops away at both ends, or drops at one and is a narrow
	# ledge against a wall at the other. a small step down or open floor isn't
	_w_x = _is_perch(l[1], r2[1], wx, 0.13)
	_w_z = _is_perch(f[1], bk[1], wz, 0.2)
	x0 = sx - float(l[0]) if _w_x or l[1] == "wall" else -1.0
	x1 = sx + float(r2[0]) if _w_x or r2[1] == "wall" else 1.0
	z0 = sz - float(f[0]) if _w_z else -1.0
	z1 = sz + float(bk[0]) if _w_z else 1.0
	cx = (x0 + x1) * 0.5 if _w_x else 0.0
	cz = (z0 + z1) * 0.5 if _w_z else 0.0
	top_y = 0.0
	on = _w_x or _w_z
	# how much it changes the stance: across, the paws are ~10 cm apart at most; along, a
	# standing cat's paws span ~27 cm (narrower while walking: it runs along a rail single file)
	var stance_l: float = absf((rig.HOME[2] as Vector3).z - (rig.HOME[0] as Vector3).z) + 0.03
	_narrow_t = clampf((0.15 - wx) / 0.06, 0.0, 1.0) if _w_x else 0.0
	_bunch_t = clampf((stance_l + 0.02 - wz) / 0.08, 0.0, 1.0) if _w_z else 0.0
	# (walking / running over a post or across a rail: no bunching mid stride, only once it
	# has slowed right down on top)
	_bunch_t *= 1.0 - smoothstep(0.2, 0.5, speed)


func _is_perch(a: String, b: String, width: float, ledge: float) -> bool:
	if a == "drop" and b == "drop":
		return true
	if (a == "drop" and b == "wall") or (a == "wall" and b == "drop"):
		return width < ledge
	return false


## fit the four home spots (rig space, already turned by the body's yaw lag) onto the top.
## homes are changed in place. stance: the fore / hind z the stance wants
func fit(homes: Array) -> void:
	squeeze = 0.0
	if not perch or not on or w < 0.02:
		return
	var m := EDGE_IN
	var lo_x := x0 + m
	var hi_x := x1 - m
	var lo_z := z0 + m
	var hi_z := z1 - m
	var out := []
	for i in 4:
		out.append(homes[i])
	if _w_x:
		var mid := (x0 + x1) * 0.5
		var half := maxf(0.0, (hi_x - lo_x) * 0.5)
		for i in 4:
			var h: Vector3 = out[i]
			# keep the left / right order, squash into the width
			var side := signf(h.x) if absf(h.x) > 0.001 else (-1.0 if i % 2 == 0 else 1.0)
			var ax := minf(absf(h.x), half)
			h.x = clampf(mid + side * minf(absf(h.x), half), lo_x, maxf(lo_x, hi_x))
			if ax < 0.022:
				# a rail: paws nearly in a line, one ahead of the other
				h.z += (-1.0 if i % 2 == 0 else 1.0) * RAIL_STAGGER * (1.0 - ax / 0.022) * (1.0 if i < 2 else -1.0)
			out[i] = h
	if _w_z:
		var fz := minf((out[0] as Vector3).z, (out[1] as Vector3).z)
		var hz := maxf((out[2] as Vector3).z, (out[3] as Vector3).z)
		var want := hz - fz
		var room := hi_z - lo_z
		var nf := fz
		var nh := hz
		if room >= want:
			# it fits: just slide the stance onto the top
			var sh := 0.0
			if fz < lo_z:
				sh = lo_z - fz
			elif hz > hi_z:
				sh = hi_z - hz
			nf += sh
			nh += sh
		elif room >= PAIR_GAP:
			# it doesn't: fore paws at the front edge, hind paws at the back edge
			nf = lo_z
			nh = hi_z
		else:
			# a post top: all four together, fore paws a paw's length ahead (toes over both edges)
			var c := (lo_z + hi_z) * 0.5
			nf = c - PAIR_GAP * 0.5
			nh = c + PAIR_GAP * 0.5
		squeeze = clampf(1.0 - (nh - nf) / maxf(want, 0.01), 0.0, 1.0)
		for i in 4:
			var h: Vector3 = out[i]
			if i < 2:
				h.z += nf - fz
			else:
				h.z += nh - hz
			out[i] = h
	for i in 4:
		homes[i] = (homes[i] as Vector3).lerp(out[i], clampf(w * 1.25, 0.0, 1.0))


## a paw coming down out of the air near world spot p: onto the top if it would miss it
func land_spot(i: int, p: Vector3, xf: Transform3D, homes: Array) -> Vector3:
	if not perch or not on:
		return p
	var lp := xf.affine_inverse() * p
	if lp.x >= x0 and lp.x <= x1 and lp.z >= z0 and lp.z <= z1:
		return p
	return xf * Vector3(clampf(lp.x, x0 + EDGE_IN, x1 - EDGE_IN), lp.y, (homes[i] as Vector3).z)


## a planted paw (world spot) that isn't on the top at all: it has to step onto it
func outside(p: Vector3, xf: Transform3D) -> bool:
	if not perch or not on or w < 0.5:
		return false
	var lp := xf.affine_inverse() * p
	return lp.x < x0 - 0.002 or lp.x > x1 + 0.002 or lp.z < z0 - 0.002 or lp.z > z1 + 0.002


## is rig space x,z over the top (true off a perch: everything is "over" ordinary ground)
func over(x: float, z: float) -> bool:
	if not perch or not on or w < 0.3:
		return true
	return x >= x0 - 0.01 and x <= x1 + 0.01 and z >= z0 - 0.01 and z <= z1 + 0.01
