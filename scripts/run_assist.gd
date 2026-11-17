class_name RunAssist
extends RefCounted
## running over rough ground, kept out of cat_player.gd so the controller only calls two hooks.
##
## step_up(): small stuff in the way (roots, branches, stone lips, up to STEP_MAX) the body glides up
##   over while the planted paws step onto it, like stairs in a shooter. the eye smoothing in
##   CatPlayer._post already turns the pop into a glide.
## bound(): at a run, anything bigger (logs, rocks, ledges up to BOUND_MAX_H, ditches) gets read off
##   a profile of the ground ahead. it finds the smallest real ballistic arc that clears it (or lands
##   on top of it when the top is flat and wide enough) and launches at the spot that arc needs, so
##   the cat keeps its pace and the rig does the takeoff, flight and front first landing by itself.

const STEP_MAX := 0.11          # glide up this much without leaving the ground
const BOUND_MIN_SPEED := 1.1    # slower than this the cat walks up to things (mantle / clamber)
const BOUND_MAX_H := 0.6        # taller than this isn't hopped at a run: it runs into it and climbs
const GAP_MIN := 0.2            # a dip deeper than this ahead is a ditch to clear
const CLEAR := 0.05             # paws clear the top by this much
const DX := 0.05                # profile sample spacing (m)
const LANES := [0.0, -0.065, 0.065]
const LAND_FLAT := 0.03         # landing spot must be this level over the body's length
const FACE := 0.15              # a rise of more than STEP_MAX within this run is a face, not a hill
const GAP_FACE := 0.4           # a drop of more than GAP_MIN within this run is a ditch edge

static var last_bound := {}     # what the last bound was (for logs / tests)
static var _tick := 0
static var _why := ""
static var dbg := ""           # why the last check did / didn't bound


# ------------------------------------------------------------------ step up
static func step_up(p: CharacterBody3D, hv: Vector3, dt: float) -> bool:
	var spd := hv.length()
	if spd < 0.15:
		return false
	var dir := hv / spd
	var probe := dir * maxf(spd * dt, 0.025)
	var xf := p.global_transform
	var col := KinematicCollision3D.new()
	if not p.test_move(xf, probe, col, 0.001):
		return false
	if col.get_normal().y > 0.72:
		return false   # just a slope, move_and_slide walks it
	if p.test_move(xf, Vector3.UP * STEP_MAX, null, 0.001):
		return false   # no head room
	var up := Transform3D(xf.basis, xf.origin + Vector3.UP * STEP_MAX)
	if p.test_move(up, probe, null, 0.001):
		return false   # still blocked higher up: a real wall / ledge
	var over := Transform3D(xf.basis, up.origin + probe)
	var down := KinematicCollision3D.new()
	if not p.test_move(over, Vector3.DOWN * (STEP_MAX + 0.03), down, 0.001):
		return false   # nothing to stand on past the lip
	if down.get_normal().y < 0.65:
		return false
	var rise := over.origin.y + down.get_travel().y - xf.origin.y
	if rise < 0.004 or rise > STEP_MAX:
		return false
	p.global_position.y += rise + 0.002
	return true


# ------------------------------------------------------------------ bound
## call on the ground with the horizontal velocity the cat is about to run at. returns true and sets
## p.velocity.y when it launches.
static func bound(p: CharacterBody3D, hv: Vector3, dt: float, g: float, radius: float) -> bool:
	var spd := hv.length()
	if spd < BOUND_MIN_SPEED:
		return false
	# the ground ahead is read every other tick (plenty at 144 hz, halves the ray cost)
	_tick += 1
	if _tick % 2 == 1:
		return false
	var dir := hv / spd
	var feet := p.global_position
	var fn := p.get_floor_normal()
	var slope := 0.0
	if fn.y > 0.5:
		slope = clampf(-(fn.x * dir.x + fn.z * dir.z) / fn.y, -0.6, 0.6)
	var reach := clampf(spd * 0.7, 1.4, 5.0)
	var n := int(reach / DX) + 1
	var prof := _profile(p, feet, dir, slope, n)
	# an obstacle is a sudden change: a rise of more than a step within FACE m (steeper than any
	# hillside), or a drop into a ditch that has a far side. hills and lumps never count
	var k := int(round(FACE / DX))
	var kg := int(round(GAP_FACE / DX))
	var first := -1
	var kind := ""
	var base := 0.0
	for i in range(maxi(int(ceil(radius * 0.5 / DX)), 1), n):
		var pre: float = prof[maxi(i - k, 0)]
		if prof[i] - pre > STEP_MAX:
			first = i
			kind = "bump"
			base = pre
			break
		var pre_g: float = prof[maxi(i - kg, 0)]
		if pre_g - prof[i] > GAP_MIN:
			first = i
			kind = "gap"
			base = pre_g
			break
	if first < 0:
		dbg = "clear"
		return false
	var last := n - 1     # bump: last cell of the obstacle. gap: first cell of the far side
	# the run-in tells the real grade better than the floor normal under the paws
	var lead := first - (k if kind == "bump" else kg)
	if lead >= 4:
		slope = clampf((prof[lead] - prof[0]) / (lead * DX), -0.6, 0.6)
	if kind == "bump":
		# it ends where the ground falls back at least halfway from its top (the back of a log or
		# rock). if it never does in view it's a ledge / plateau: land on it
		var top := -INF
		for j in range(first, n):
			var pk := top + base
			if j > first and prof[j] < pk - maxf(0.06, 0.5 * top):
				last = j - 1
				break
			top = maxf(top, prof[j] - base)
			if top > BOUND_MAX_H:
				dbg = "wall %.2f at d=%.2f" % [top, first * DX]
				return false   # a wall: run into it and climb instead
	else:
		last = -1
		for j in range(first, n):
			if prof[j] > base + minf(slope, 0.0) * (j - first + kg) * DX - 0.12:
				last = j
				break
		if last < 0:
			dbg = "drop at d=%.2f" % (first * DX)
			return false   # no far side in sight: it's a drop, just run off it
	var foot := int(ceil(radius / DX))
	var fmax := PackedFloat32Array()
	fmax.resize(n)
	for i in n:
		var m := -INF
		for j in range(maxi(i - foot, 0), mini(i + foot + 1, n)):
			m = maxf(m, prof[j])
		fmax[i] = m
	# launch speed cap: enough to clear the top (measured from the paws, it may sit up a slope)
	var top_feet := 0.25
	for j in range(first, mini(last + 1, n)):
		top_feet = maxf(top_feet, prof[j] - feet.y)
	var vmax := sqrt(2.0 * g * minf(top_feet + CLEAR + 0.14, 0.9))
	var ctx := {"vmax": vmax, "prof": prof, "fmax": fmax, "spd": spd, "g": g, "foot": foot, "slope": slope, "first": first, "last": last, "base": base, "bump": kind == "bump"}
	var d0 := first * DX
	if d0 > reach - 1.0:
		dbg = "%s at d=%.2f: not in full view yet" % [kind, d0]
		return false
	var step := spd * dt * 2.0
	# launch timing: go when the cheapest arc from here is no cheaper than from a moment later,
	# or when waiting would run into it / off the lip
	var now := _cheapest(ctx, 0.0, feet.y)
	if now.is_empty() and kind == "bump" and d0 < 0.6:
		# too slow or too close for the arc it's running at: a short hop up at a set pace
		for sp in [2.6, 2.0, 1.5]:
			ctx.spd = sp
			now = _cheapest(ctx, 0.0, feet.y)
			if not now.is_empty():
				p.velocity.x = dir.x * sp
				p.velocity.z = dir.z * sp
				spd = sp
				break
		ctx.spd = spd
		if not now.is_empty():
			p.velocity.y = now.vy
			dbg = "HOP %s d=%.2f vy %.2f at %.1f m/s" % [kind, d0, now.vy, spd]
			last_bound = {"kind": "hop " + now.how, "vy": now.vy, "d": d0, "h": now.h, "land": now.land, "speed": spd}
			return true
	if now.is_empty():
		_sim(ctx, 0.0, feet.y, 3.3)
		_why += " spd %.1f slope %.2f" % [spd, slope]
		dbg = "%s at d=%.2f (cells %d-%d, base %.2f): no arc [%s]. prof %s" % [kind, d0, first, last, base - feet.y, _why, str(Array(prof.slice(maxi(first - 4, 0), mini(last + 6, n))).map(func(v): return snappedf(v - feet.y, 0.01)))]
		return false
	var must := (kind == "bump" and d0 - step * 2.0 < radius + 0.03) or (kind == "gap" and d0 - step * 2.0 < radius + 0.1)
	if not must:
		# wait only while the arc from a little closer is clearly cheaper. looking a bit further
		# than the next check keeps a margin, so speed changes or a bump underfoot between checks
		# can't leave it too close to make it
		var look := 0.12 + step * 2.0
		var later := _cheapest(ctx, look, feet.y + slope * look)
		if not later.is_empty() and later.vy < now.vy - 0.04:
			dbg = "wait d=%.2f vy %.2f -> %.2f" % [d0, now.vy, later.vy]
			return false   # no dearer from a step closer: keep running in
	var vy: float = now.vy
	p.velocity.y = vy
	dbg = "GO %s d=%.2f vy %.2f cells %d-%d base %.2f prof %s" % [kind, d0, vy, first, last, base - feet.y, str(Array(prof.slice(maxi(first - 4, 0), mini(last + 6, n))).map(func(v): return snappedf(v - feet.y, 0.01)))]
	last_bound = {"kind": now.how if kind == "bump" else "gap", "vy": vy, "d": d0, "h": now.h, "land": now.land, "speed": spd}
	return true


## ground height (absolute y) every DX along the run, the highest of three lanes across the body.
## a ray that starts inside something (a trunk, a boulder) reads as a wall at the top of the range
static func _profile(p: CharacterBody3D, feet: Vector3, dir: Vector3, slope: float, n: int) -> PackedFloat32Array:
	var space := p.get_world_3d().direct_space_state
	var side := Vector3(-dir.z, 0, dir.x)
	var out := PackedFloat32Array()
	out.resize(n)
	var q := PhysicsRayQueryParameters3D.new()
	q.exclude = [p.get_rid()]
	q.hit_from_inside = true
	for i in n:
		var x := i * DX
		var gy := feet.y + slope * x
		var best := -INF
		for lane in LANES:
			var o: Vector3 = feet + dir * x + side * float(lane)
			q.from = Vector3(o.x, gy + BOUND_MAX_H + 0.3, o.z)
			q.to = Vector3(o.x, gy - 1.2, o.z)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				best = maxf(best, (hit.position as Vector3).y)
		if best == -INF:
			best = gy - 1.2   # deep hole
		out[i] = best
	return out


## smallest launch speed (up) whose arc, starting `off` metres further on, clears the obstacle and
## comes down on something walkable past it (or flat on top of it). {} if none up to the cap
static func _cheapest(ctx: Dictionary, off: float, y0: float) -> Dictionary:
	var vmax: float = ctx.vmax
	var vy := 0.9
	var found := {}
	# coarse pass, then back up one coarse step in fine steps
	while vy <= vmax:
		found = _sim(ctx, off, y0, vy)
		if not found.is_empty():
			break
		vy += 0.2
	if found.is_empty():
		return {}
	var hi := vy
	vy = maxf(hi - 0.18, 0.9)
	while vy < hi:
		var r := _sim(ctx, off, y0, vy)
		if not r.is_empty():
			r.vy = vy
			return r
		vy += 0.03
	found.vy = hi
	return found


static func _sim(ctx: Dictionary, off: float, y0: float, vy: float) -> Dictionary:
	var prof: PackedFloat32Array = ctx.prof
	var fmax: PackedFloat32Array = ctx.fmax
	var n := prof.size()
	var spd: float = ctx.spd
	var g: float = ctx.g
	var foot: int = ctx.foot
	var first: int = ctx.first
	var last: int = ctx.last
	var bump: bool = ctx.bump
	var base: float = ctx.base
	var slope: float = ctx.slope
	var peak := 0.0
	var x := off
	var t := 0.0
	var dt := DX / spd
	while true:
		t += dt
		x += DX
		var i := int(round(x / DX))
		var y := y0 + vy * t - 0.5 * g * t * t
		peak = maxf(peak, y - y0)
		if i + foot >= n:
			# flew past what we can see: fine once it's past the obstacle
			if (bump and i > last + foot) or (not bump and i >= last):
				return {"how": "over", "h": peak, "land": x}
			_why = "past view i=%d y=%.2f" % [i, y]
			return {}
		var under: float = fmax[i]
		var near_obst := bump and i + foot >= first and i - foot <= last
		if y >= under + (CLEAR if near_obst else 0.0):
			continue
		# arc meets the ground here: a landing if it's coming down onto something level
		if vy - g * t >= 0.0 or y < under - 0.08:
			_why = "hit i=%d y=%.2f under=%.2f" % [i, y, under]
			return {}
		var on_top := bump and i >= first and i <= last
		if bump and i < first:
			_why = "short i=%d y=%.2f under=%.2f" % [i, y, under]
			return {}   # came down short of it
		if not bump and (i < last or under < base - GAP_MIN * 0.5):
			_why = "ditch i=%d y=%.2f under=%.2f" % [i, y, under]
			return {}   # came down in the ditch
		# front paws touch down first: the spot ahead has to be level enough for the body
		var hi := mini(i + foot * 2 + 1, n - 1)
		var mn := INF
		var mx := -INF
		for kk in range(i, hi + 1):
			mn = minf(mn, prof[kk])
			mx = maxf(mx, prof[kk])
		if mx - mn > LAND_FLAT + absf(slope) * (hi - i) * DX:
			_why = "not flat i=%d y=%.2f under=%.2f" % [i, y, under]
			return {}
		return {"how": "onto" if on_top else "over", "h": peak, "land": x}
	return {}
