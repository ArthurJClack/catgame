class_name CatGait
extends RefCounted
## footfall solver for the cat rig.
## every paw is either PLANTED at a fixed spot in the world, SWINGing to a predicted
## landing spot, or FREE (airborne / climbing: the rig poses it and writes it back).
## a planted paw never moves until it lifts, the body is solved from the paws afterwards.
##
## timing is distance driven: the gait clock advances by distance / stride length, and
## stride length, duty factor and the fore-hind phase lag come from speed curves measured
## off real cats (walk -> trot is a continuous lag change, trot -> gallop is a snap with hysteresis.
## real cats break into a gallop near 2.7 m/s; it is held back to 3.9 here so the default 3.2 m/s run is a trot).

enum { PLANTED, SWING, FREE }

# stride length (m) by speed (m/s), from treadmill cats (goslow et al. 1973, halbertsma 1983:
# cycle ~1.0 s at 0.5 m/s, ~0.7 s at 1 m/s, ~0.45 s trotting at 2 m/s, ~0.3 s galloping) scaled
# by froude to this cat's ~0.88x leg. stride frequency: 0.9 hz stalking, 1.2 walk, 2.0 trot, 3.3+ gallop.
# swing time stays near 0.22-0.26 s at every walk/trot speed (stance is what shrinks), as in real cats.
# direct register at a walk comes from where the stance sits under each girdle (STANCE_BIAS), not short steps
const STRIDE_V := [0.0, 0.25, 0.5, 0.9, 1.5, 2.4, 3.2, 6.0, 11.0]
const STRIDE_L := [0.26, 0.27, 0.36, 0.50, 0.66, 0.90, 1.14, 1.78, 2.65]
# where each paw's stance sits relative to its girdle, as a fraction of stance length (+ = forward).
# a cat's forepaw touches down well ahead of the shoulder (the blade swings it forward) and leaves
# just behind it; the hind paw lands only a little ahead of the hip and drives back far behind it.
# that offset is what lets the hind paw land in the forepaw's print at a real walking stride
const STANCE_BIAS := [-0.06, -0.06, -0.2, -0.2]
# fraction of the stride each paw spends on the ground
const DUTY_V := [0.0, 0.3, 0.5, 0.9, 1.5, 2.4, 3.2, 6.0, 11.0]
const DUTY_D := [0.80, 0.76, 0.70, 0.62, 0.48, 0.40, 0.36, 0.28, 0.20]
const GALLOP_UP := 3.9
const GALLOP_DOWN := 3.4
## rough ground footwork (longer reach rays, foothold picking, swing clearance, girdles
## tilting with the ground). false = the old flat ground behaviour (before / after renders)
static var rough := true
## a planted paw lifts as soon as its leg runs out of reach, instead of being dragged (false =
## the old behaviour, for before / after)
static var reach_lift := true
## ground rays know when they start inside something solid, and paws aim for where the body will
## be (stairs, kerbs). false = old
static var solid_rays := true
## one paw of each pair (fore, hind) stays on the ground below a run
static var support_rule := true
var _ref_y := NAN
var _ref_vy := 0.0
const REACH_LIFT := 1.03

var rig: Node3D
var phase := 0.0
var stride := 0.3
var duty := 0.7
var freq := 0.0
var bias_w := 1.0     # how much of STANCE_BIAS applies at this speed
var lag := 0.25       # fore paw touches down this fraction of a stride after the hind on its side
var gallop := 0.0     # 0..1
var moving := 0.0     # 0..1
var w_walk := 1.0
var w_trot := 0.0
var max_stance := 0.26
var max_stance_gallop := 0.34
var use_rays := true
var exclude: Array[RID] = []
## multiplayer copy: never decide to lift a paw itself, only lift the ones queue_lift() hands it
## (the owner's lifts, replayed), so every step, settle step and turn-in-place step is taken by
## the same paw at the same moment on every screen. landing and the rest run as normal
var remote := false
var _queued: Array = []   # [[paw, dur, lift, age], ...]
var owner_modes := -1     # copy: the owner's paw modes right now, 2 bits per paw (-1 = unknown)

var offs: Array[float] = [0.25, 0.75, 0.0, 0.5]
var pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO] # world
var nrm: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
var mode: Array[int] = [PLANTED, PLANTED, PLANTED, PLANTED]
var sw_t: Array[float] = [0.0, 0.0, 0.0, 0.0]     # swing progress 0..1
var sw_amp: Array[float] = [1.0, 1.0, 1.0, 1.0]   # how big this step is (small settling steps flick less)
var st_s: Array[float] = [0.5, 0.5, 0.5, 0.5]     # stance progress 0..1
var load: Array[float] = [0.6, 0.6, 0.6, 0.6]     # smoothed weight on the paw
var free_w: Array[float] = [0.0, 0.0, 0.0, 0.0]   # 0 = world planted, 1 = posed by the rig
var stretch: Array[float] = [0.0, 0.0, 0.0, 0.0]  # leg extension 0..1, written by the rig's ik
var touched: Array[bool] = [false, false, false, false] # paw touched down this frame

var _from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _dur: Array[float] = [0.2, 0.2, 0.2, 0.2]
var _lift: Array[float] = [0.03, 0.03, 0.03, 0.03]
var _gy: Array[float] = [0.0, 0.0, 0.0, 0.0]
# rough ground: swing ends kept as world heights (the root rides up and down over bumps mid
# swing, a body space height would land the paw in the air or under the ground), the foothold
# nudge picked for this step (body space) and the extra lift needed to clear what's in between
var _gyw: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _fyw: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _adj: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _clr: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _aim: Array[int] = [0, 0, 0, 0]
## 0 on flat floors, cm-ish on rough ground (biggest recent paw height vs the root, m)
var uneven := 0.0
var _clr_t: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _grd: Array[float] = [0.0, 0.0, 0.0, 0.0]
var floor_y: Array[float] = [-INF, -INF, -INF, -INF]   # ground under each swinging paw (world), -INF unknown
var st_time := 1.0
var gap_time := 0.0
## how far below the root a paw may reach / how high above it it may step (rough ground)
const REACH_DOWN := 0.26
const REACH_UP := 0.24
# foothold candidates around the planned spot (sideways, forward) in m, nearest first
const HOLDS := [Vector2(0, 0), Vector2(0, 0.028), Vector2(0, -0.028), Vector2(0.02, 0), Vector2(-0.02, 0), Vector2(0, 0.055), Vector2(0, -0.05), Vector2(0.02, 0.03), Vector2(-0.02, 0.03)]
var _ray2: Array[bool] = [false, false, false, false]
var _st_t: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _idle_t: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _hold: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _vary: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _gal_on := false
var _ready_done := false
var _since_land := 1.0
var _rng := RandomNumberGenerator.new()


static func _curve(xs: Array, ys: Array, x: float) -> float:
	if x <= xs[0]:
		return ys[0]
	for k in range(1, xs.size()):
		if x <= xs[k]:
			return lerpf(ys[k - 1], ys[k], (x - xs[k - 1]) / (xs[k] - xs[k - 1]))
	return ys[-1]


func reset(xf: Transform3D, homes: Array) -> void:
	for i in 4:
		pos[i] = _ground(xf * (homes[i] as Vector3), xf.origin.y, i)
		mode[i] = PLANTED
		free_w[i] = 0.0
		_st_t[i] = 0.0
		st_s[i] = 0.5
	_ready_done = true


## ray down onto static ground near the rig's feet. falls back to the rig's own height
func _ground(p: Vector3, root_y: float, i: int) -> Vector3:
	if rough:
		return _ground_rough(p, root_y, i)
	nrm[i] = Vector3.UP
	if not use_rays or rig == null or not rig.is_inside_tree():
		return Vector3(p.x, root_y, p.z)
	var space := rig.get_world_3d().direct_space_state
	if space == null:
		return Vector3(p.x, root_y, p.z)
	var ex := exclude.duplicate()
	for _k in 3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, root_y + 0.17, p.z), Vector3(p.x, root_y - 0.16, p.z))
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		if hit.collider is StaticBody3D or hit.collider is CSGShape3D or hit.collider is GridMap:
			if (hit.normal as Vector3).y > 0.5:
				nrm[i] = hit.normal
				# a drop the leg can't reach down: the paw stops at the edge's height
				return Vector3(p.x, maxf((hit.position as Vector3).y, root_y - 0.07), p.z)
			break
		ex.append(hit.rid)
	return Vector3(p.x, root_y, p.z)


## first ground hit (static, facing up-ish) going down the vertical line at x,z between
## y0 and y1. returns [y, normal] or [] when there's nothing in reach
func _ray(x: float, z: float, y0: float, y1: float, solid := false) -> Array:
	var space := rig.get_world_3d().direct_space_state
	var ex := exclude.duplicate()
	for _k in 3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, y0, z), Vector3(x, y1, z))
		q.exclude = ex
		q.hit_from_inside = solid
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return []
		if hit.collider is StaticBody3D or hit.collider is CSGShape3D or hit.collider is GridMap:
			if solid and (hit.normal as Vector3) == Vector3.ZERO:
				# the line starts inside something (a stair two steps up, a kerb taller than the
				# reach): the ground here is at least this high. without this the ray went on
				# down through the block and found the floor underneath it
				return [y0, Vector3.UP, true]
			return [(hit.position as Vector3).y, hit.normal]
		ex.append(hit.rid)
	return []


## how high above the root the down rays may start at x,z: up to REACH_UP, but under a
## ceiling (a chair seat, a shelf, a log the cat ducks under) only up to just below it, so a
## paw never lands on top of something the cat is walking under. an upward ray that starts
## inside a rock or under the terrain skin hits nothing / a back face (normal up): no ceiling
func _top(x: float, z: float, root_y: float) -> float:
	var space := rig.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, root_y + 0.03, z), Vector3(x, root_y + REACH_UP, z))
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and (hit.normal as Vector3).y < -0.3:
		if solid_rays:
			# the underside of something low and thin whose top is in stepping reach (the foot
			# of a ramp, a plank, a low platform) is not a ceiling: the cat is about to walk
			# onto it, not under it
			var h := _ray(x, z, root_y + REACH_UP + 0.3, (hit.position as Vector3).y)
			if not h.is_empty() and (h[1] as Vector3).y > 0.5 and float(h[0]) < root_y + REACH_UP + 0.12:
				return maxf(root_y + REACH_UP, float(h[0]) + 0.02)
		return maxf((hit.position as Vector3).y - 0.01, root_y + 0.03)
	return root_y + REACH_UP


func _can_ray() -> bool:
	return use_rays and rig != null and rig.is_inside_tree() and rig.get_world_3d().direct_space_state != null


func _ground_rough(p: Vector3, root_y: float, i: int) -> Vector3:
	nrm[i] = Vector3.UP
	if not _can_ray():
		return Vector3(p.x, root_y, p.z)
	var h := _ray(p.x, p.z, _top(p.x, p.z, root_y), root_y - REACH_DOWN - 0.06, solid_rays)
	if h.is_empty():
		return Vector3(p.x, root_y, p.z)
	var n: Vector3 = h[1]
	nrm[i] = n if n.y > 0.5 else Vector3.UP.slerp(n, 0.4)
	# a drop the leg can't reach down: the paw stops at the edge's height
	return Vector3(p.x, maxf(float(h[0]), root_y - REACH_DOWN), p.z)


## where to put the paw near the planned spot p (world). real cats look where they step:
## off the edge of a rock or a root, off a steep face, onto the nearest flat bit, and not
## much higher / lower than the paws already are. fwd: travel direction (world, flat).
## returns the chosen spot (y = ground) and sets nrm[i]
func _foothold(p: Vector3, root_y: float, i: int, fwd: Vector3) -> Vector3:
	nrm[i] = Vector3.UP
	if not _can_ray():
		return Vector3(p.x, root_y, p.z)
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var top := _top(p.x, p.z, root_y)
	var bot := root_y - REACH_DOWN - 0.06
	var best := Vector3(p.x, root_y, p.z)
	var best_n := Vector3.UP
	var best_s := INF
	for c in HOLDS:
		var cv: Vector2 = c
		var q: Vector3 = p + side * cv.x + fwd * cv.y
		var h := _ray(q.x, q.z, top, bot, solid_rays)
		if h.is_empty():
			continue
		var y: float = h[0]
		var n: Vector3 = h[1]
		# an edge under the pad: ground a pad's length ahead / behind / beside is at another height
		var spread := 0.0
		for o in [fwd * 0.018, -fwd * 0.018, side * 0.014, -side * 0.014]:
			var ov: Vector3 = o
			var h2 := _ray(q.x + ov.x, q.z + ov.z, top, bot)
			spread = maxf(spread, absf(float(h2[0]) - y) if not h2.is_empty() else 0.1)
		var sc := cv.length() * 0.9 + maxf(0.0, spread - 0.005) * 5.0 + (1.0 - n.y) * 0.35
		sc += maxf(0.0, absf(y - root_y) - 0.03) * 0.5
		if y < root_y - REACH_DOWN:
			sc += 1.0
		if sc < best_s:
			best_s = sc
			best = Vector3(q.x, maxf(y, root_y - REACH_DOWN), q.z)
			best_n = n
		# the planned spot is fine: take it (most steps on flat floors end here, 5 rays)
		if cv == Vector2.ZERO and sc < 0.02:
			break
	nrm[i] = best_n if best_n.y > 0.5 else Vector3.UP.slerp(best_n, 0.4)
	return best


## the ground between where a swinging paw left and where it lands, against the higher end:
## how much more it has to lift to clear a root / rock edge in the way (0 = nothing in the way)
func _clearance(a: Vector3, b: Vector3, root_y: float) -> float:
	if not _can_ray():
		return 0.0
	var hi := maxf(a.y, b.y)
	var worst := -1.0
	for u in [0.25, 0.5, 0.75]:
		var q := a.lerp(b, u)
		var h := _ray(q.x, q.z, root_y + REACH_UP, root_y - 0.1, solid_rays)
		if not h.is_empty():
			# the swing arc rises toward hi in the middle, less near the ends
			var arc := lerpf(lerpf(a.y, b.y, u), hi, sin(PI * u))
			worst = maxf(worst, float(h[0]) - arc)
	return clampf(worst + 0.016, 0.0, 0.12) if worst > -0.016 else 0.0


## timing numbers for this speed
func plan(speed: float, dt: float) -> void:
	if speed > GALLOP_UP:
		_gal_on = true
	elif speed < GALLOP_DOWN:
		_gal_on = false
	gallop = move_toward(gallop, 1.0 if _gal_on else 0.0, dt * 5.0)
	stride = _curve(STRIDE_V, STRIDE_L, speed)
	duty = _curve(DUTY_V, DUTY_D, speed)
	var ms := lerpf(max_stance, max_stance_gallop, gallop)
	if duty * stride > ms:
		duty = ms / stride
	freq = speed / stride
	# walk: fore follows the hind on its side by a quarter stride. trot: by half (diagonals in step)
	lag = lerpf(0.25, 0.5, smoothstep(0.85, 1.35, speed))
	# stance offsets fade out toward the trot (diagonal pairs push together) and are gone in the gallop
	bias_w = lerpf(1.0, 0.45, smoothstep(0.85, 1.35, speed)) * (1.0 - gallop)
	var g := gallop
	offs[2] = 0.0
	offs[3] = lerpf(0.5, 0.10, g)
	offs[0] = lerpf(lag, 0.62, g)
	offs[1] = fposmod(lerpf(lag + 0.5, 0.52, g), 1.0)
	moving = clampf((speed - 0.04) / 0.1, 0.0, 1.0)
	w_trot = smoothstep(0.85, 1.35, speed) * (1.0 - g)
	w_walk = (1.0 - smoothstep(0.85, 1.35, speed)) * (1.0 - g)


## xf: the rig's world transform (orthonormal). vel: world velocity. homes: rest spots
## under each hip in rig space. want_free: legs the rig poses itself this frame
func update(dt: float, xf: Transform3D, vel: Vector3, yaw_rate: float, homes: Array, want_free: Array, lift_h: float, on_floor: bool) -> void:
	var up := xf.basis.y
	var hv := vel - up * vel.dot(up)
	var spd := hv.length()
	if not _ready_done:
		reset(xf, homes)
	# teleported / respawned: start over
	var far := 0.0
	for i in 4:
		if mode[i] == PLANTED:
			far = maxf(far, (pos[i] - xf * (homes[i] as Vector3)).length())
	if far > 0.75:
		reset(xf, homes)
	phase = fposmod(phase + spd * dt / maxf(stride, 0.05), 1.0)
	# how fast the ground under the cat is rising / falling (stairs, ramps), smoothed
	if not is_nan(_ref_y) and absf(xf.origin.y - _ref_y) < 0.2 and dt > 0.0:
		_ref_vy = lerpf(_ref_vy, (xf.origin.y - _ref_y) / dt, 1.0 - exp(-6.0 * dt))
	else:
		_ref_vy = 0.0
	_ref_y = xf.origin.y
	# how uneven the ground has been lately (planted paws above / below the root), decays in ~0.5 s
	var dev := 0.0
	for i in 4:
		if mode[i] == PLANTED:
			dev = maxf(dev, absf(pos[i].y - xf.origin.y))
	uneven = maxf(dev, uneven - dt * 0.03)
	_since_land += dt
	var stance_len := minf(duty * stride, lerpf(max_stance, max_stance_gallop, gallop)) * clampf(spd / 0.25, 0.0, 1.0)
	# how long a paw stays down at this speed, and how long each end of the body then has no
	# paw down before the next one lands (zero below a run; a run is a string of small jumps)
	st_time = stance_len / maxf(spd, 0.1) if moving > 0.5 else 1.0
	var half := lerpf(0.5, 1.0, gallop) / maxf(freq, 0.01)
	gap_time = clampf(half - st_time * lerpf(1.0, 1.5, gallop), 0.0, 0.25) if moving > 0.5 else 0.0
	var inv := xf.affine_inverse()
	var ldir := inv.basis * (hv / spd) if spd > 0.001 else Vector3.ZERO
	var n_swing := 0
	var worst := -1
	var worst_err := 0.0
	for i in 4:
		touched[i] = false
		if mode[i] == SWING:
			n_swing += 1
	for i in 4:
		var home_w: Vector3 = xf * (homes[i] as Vector3)
		var q := fposmod(phase - offs[i], 1.0)
		# ---- free <-> planted
		if want_free[i]:
			if mode[i] != FREE and remote and owner_modes >= 0:
				# copy: the hind paws let go of the ground when the owner's did (unless the leg
				# would tear off first)
				if ((owner_modes >> (i * 2)) & 3) == FREE or stretch[i] > 0.998:
					mode[i] = FREE
			elif mode[i] != FREE:
				if _hold[i] > 0.0 and stretch[i] < 0.985:
					_hold[i] -= dt  # hind paws stay on the ground while the legs push off
				else:
					mode[i] = FREE
		elif mode[i] == FREE:
			# coming back to the ground: fore paws plant where they are, hind paws swing in after
			var p: Vector3 = pos[i]
			if i < 2 or not on_floor:
				pos[i] = _ground(p, xf.origin.y, i)
				mode[i] = PLANTED
				_st_t[i] = 0.0
				touched[i] = true
			else:
				_begin_swing(i, 0.085, 0.012, home_w, xf)
			_since_land = 0.0
		free_w[i] = move_toward(free_w[i], 1.0 if mode[i] == FREE else 0.0, dt * (16.0 if mode[i] == FREE else 22.0))
		if mode[i] == FREE:
			load[i] = move_toward(load[i], 0.0, dt * 12.0)
			continue

		if mode[i] == PLANTED:
			_st_t[i] += dt
			var err := pos[i] - home_w
			err -= up * err.dot(up)
			var e := err.length()
			var lift := false
			if moving > 0.5:
				_idle_t[i] = 0.0
				st_s[i] = clampf(q / maxf(duty, 0.05), 0.0, 1.0)
				# the clock says swing, and this paw has done its time on the ground
				var st_min := minf(0.035, 0.5 * duty / maxf(freq, 0.01))
				if q >= duty and q < duty + 0.6 * (1.0 - duty) and _st_t[i] > st_min:
					lift = true
				# left behind or over stretched (sharp turn, sudden stop): step early
				elif (e > stance_len * 0.5 + 0.09 or stretch[i] > 0.998) and _st_t[i] > minf(0.06, duty / maxf(freq, 0.01)) and (mode[i ^ 1] == PLANTED or gallop > 0.5 or e > 0.3 or (rough and stretch[i] > 1.03 and uneven > 0.01)):
					lift = true
				# the leg is out of length (hard start, stop or turn, the gait clock re-timed by a gait
				# change): no leg holds a paw down past its reach, it lets go whatever the other paws do
				elif reach_lift and _st_t[i] > 0.03 and (stretch[i] > REACH_LIFT or (spd > 0.001 and stretch[i] + 0.4 * maxf(-err.dot(hv / spd), 0.0) * spd * dt / (stretch[i] * 0.04) > REACH_LIFT)):
					# (second test: it's behind its hip and the first half of this frame's travel
					# already takes it out of reach. at a run the body covers 10-18 cm a frame)
					lift = true
				# a walking / slow trotting cat always has one paw of each pair on the ground: this
				# one waits until the other is down (only a run, duty under half, has both in the air)
				if lift and support_rule and not remote and mode[i ^ 1] != PLANTED and duty >= 0.5 and gallop < 0.5 and stretch[i] < 1.06:
					lift = false
			else:
				st_s[i] = 0.5
				# standing: settle paws that ended up away from their spot, one at a time
				# (a diagonal pair at once when the body turned a lot)
				if e > 0.042 or stretch[i] > 0.97:
					_idle_t[i] += dt
					if _idle_t[i] > 0.1 and e > worst_err:
						worst_err = e
						worst = i
				else:
					_idle_t[i] = 0.0
			if remote:
				lift = false
				worst = -1
				for qi in _queued.size():
					if int(_queued[qi][0]) == i:
						var qd: Array = _queued.pop_at(qi)
						_begin_swing(i, qd[1], qd[2], home_w, xf, true)
						n_swing += 1
						break
			if lift:
				var d := clampf((1.0 - duty) / maxf(freq, 0.01), 0.085, 0.36)
				_begin_swing(i, d, lift_h * (1.0 if i < 2 else 0.85), home_w, xf, true)
				n_swing += 1
		if mode[i] == SWING:
			if support_rule and moving > 0.5 and not remote:
				# the cat sped up since this paw left the ground: the swing speeds up with it,
				# or the paw would still be in the air when its turn on the ground is over
				_dur[i] = minf(_dur[i], maxf(clampf((1.0 - duty) / maxf(freq, 0.01), 0.085, 0.36), 0.6 * _dur[i]))
			sw_t[i] += dt / _dur[i]
			# the swing is planned in body space: from where the paw left the ground (as the body
			# saw it then) to its rest spot plus half a stance ahead. at touch down the hip is
			# exactly half a stance behind the paw, whatever the body did in between
			var tl: Vector3 = (homes[i] as Vector3) + ldir * stance_len * (0.5 * _vary[i] + STANCE_BIAS[i] * bias_w)
			if rough and (_aim[i] == 0 or (_aim[i] == 1 and sw_t[i] > 0.45)):
				# pick the foothold where the paw will actually come down: the target rides with
				# the body, so it's ahead of where it is now by however far the body still travels
				_aim[i] += 1
				_ray2[i] = true
				var fw := xf.basis * (ldir if spd > 0.05 else Vector3(0, 0, -1))
				var ahead := hv * maxf(0.0, 1.0 - sw_t[i]) * _dur[i]
				var aimp: Vector3 = xf * tl + ahead
				# (going up / down stairs or a slope the body will be higher / lower by then)
				var ry_then := xf.origin.y + clampf(_ref_vy * maxf(0.0, 1.0 - sw_t[i]) * _dur[i], -0.3, 0.3)
				var fh := _foothold(aimp, ry_then if solid_rays else xf.origin.y, i, Vector3(fw.x, 0, fw.z).normalized())
				var adj := xf.basis.inverse() * (fh - aimp)
				_adj[i] = Vector3(adj.x, 0.0, adj.z)
				_gyw[i] = fh.y
				var c := _clearance(pos[i], fh, xf.origin.y)
				_clr_t[i] = c if _aim[i] == 1 else maxf(_clr_t[i], c)
				if _aim[i] == 1:
					_clr[i] = c
			elif rough and _aim[i] == 2 and sw_t[i] > 0.78:
				# last look: the body may have sped up / slowed down since (a step up, a mantle),
				# so check the height right where the paw is now going to land
				_aim[i] = 3
				var lp: Vector3 = xf * (tl + _adj[i]) + hv * maxf(0.0, 1.0 - sw_t[i]) * _dur[i]
				var h := _ray(lp.x, lp.z, _top(lp.x, lp.z, xf.origin.y), xf.origin.y - REACH_DOWN - 0.06, solid_rays)
				if not h.is_empty():
					_gyw[i] = maxf(float(h[0]), xf.origin.y - REACH_DOWN)
			if not rough and not _ray2[i] and sw_t[i] > 0.45:
				_ray2[i] = true
				_gy[i] = (inv * _ground(xf * tl, xf.origin.y, i)).y
			var s: float = clampf(sw_t[i], 0.0, 1.0)
			var fr: Vector3 = _from[i]
			if rough:
				tl += _adj[i]
				tl.y = _gyw[i] - xf.origin.y
				fr.y = _fyw[i] - xf.origin.y
			else:
				tl.y = _gy[i]
			var ease := s * s * (3.0 - 2.0 * s)
			var p: Vector3 = fr.lerp(tl, ease)
			# leave and meet the ground at ground speed (the paw is already travelling backwards
			# under the body when it touches down), as far as the leg's reach allows
			var back := minf(spd * _dur[i], 1.25 * Vector2(tl.x - fr.x, tl.z - fr.z).length())
			p -= ldir * back * s * (2.0 * s - 1.0) * (s - 1.0)
			# whatever ground speed that could not cover is matched right at the two ends, so the
			# paw neither skids forward on touch down nor gets yanked off the ground at lift off
			var rem := spd * _dur[i] - back
			if rem > 0.0:
				p += ldir * rem * ((1.0 - s) * smoothstep(0.7, 1.0, s) - s * (1.0 - smoothstep(0.0, 0.3, s)))
			# lift early, reach late, plant softly. clear the higher of the two ends
			var hi := maxf(fr.y, tl.y)
			_clr[i] = move_toward(_clr[i], _clr_t[i], dt * 0.8)
			p.y = lerpf(p.y, hi, sin(PI * s)) + (_lift[i] + _clr[i]) * sin(PI * pow(s, 0.65))
			if rough and s > 0.05 and s < 0.92 and _can_ray():
				# never drag the toes through a root or a step's edge on the way: keep the paw
				# (and a toe's length ahead of it) over the ground it's passing
				var wp: Vector3 = xf * p
				var fw2 := xf.basis * (ldir if spd > 0.05 else Vector3(0, 0, -1))
				var gmax := -INF
				for o in [Vector3.ZERO, fw2 * 0.025]:
					var ov: Vector3 = o
					var h := _ray(wp.x + ov.x, wp.z + ov.z, maxf(xf.origin.y + REACH_UP, wp.y + 0.05), wp.y - 0.08, solid_rays)
					if not h.is_empty():
						gmax = maxf(gmax, float(h[0]))
				floor_y[i] = gmax
				var under := maxf(gmax + 0.014 - wp.y, 0.0)
				if solid_rays:
					# eased in over a couple of frames and out slowly: the paw rides over the
					# edge instead of jumping to it for one frame
					_grd[i] = LowPoly.damp(_grd[i], under, 45.0 if under > _grd[i] else 12.0, dt)
					p.y += _grd[i]
				else:
					p.y += under
			elif solid_rays:
				floor_y[i] = _gyw[i] if s >= 0.92 else _fyw[i]
				_grd[i] = LowPoly.damp(_grd[i], 0.0, 12.0, dt)
				p.y += _grd[i] * (1.0 - smoothstep(0.92, 1.0, s))
			pos[i] = xf * p
			if sw_t[i] >= 1.0:
				pos[i] = xf * tl
				if rough:
					pos[i] = _ground_rough(pos[i], xf.origin.y, i)
				mode[i] = PLANTED
				_st_t[i] = 0.0
				st_s[i] = 0.0
				touched[i] = true
				_idle_t[i] = -0.05
		load[i] = move_toward(load[i], 1.0 if mode[i] == PLANTED else 0.0, dt * 14.0)

	# settling / turn in place steps
	# a replayed lift that never found its paw on the ground (it was still landing) expires
	for q in _queued:
		q[3] += dt
	_queued = _queued.filter(func(q): return q[3] < 0.25)
	if worst >= 0 and _since_land > 0.12 and not remote:
		var diag := 3 - worst
		var others := 0
		for i in 4:
			if mode[i] == SWING and i != diag:
				others += 1
		var ok: bool = n_swing == 0 or (others == 0 and worst_err > 0.11 and mode[worst ^ 1] == PLANTED)
		if ok:
			var d := clampf(0.13 + worst_err * 0.5, 0.13, 0.24)
			if worst_err > 0.2:
				d = 0.1
			_begin_swing(worst, d, clampf(0.012 + worst_err * 0.2, 0.014, 0.04), xf * (homes[worst] as Vector3), xf, true)
			_idle_t[worst] = 0.0


## world height of the ground a paw stands on, or is about to land on (swinging)
func ground_y(i: int) -> float:
	return _gyw[i] if mode[i] == SWING else pos[i].y


## 0..1 how much of its push a planted paw has: full a moment after touch down
func push(i: int) -> float:
	return smoothstep(0.0, 0.022, _st_t[i]) if mode[i] == PLANTED else 0.0


## the height a paw is carrying the body at: where it stands, or (swinging) easing from where
## it left to where it lands. no jump at lift off or touch down, so the body can follow it
func support_y(i: int) -> float:
	if mode[i] != SWING:
		return pos[i].y
	var s := clampf(sw_t[i], 0.0, 1.0)
	return lerpf(_fyw[i], _gyw[i], s * s * (3.0 - 2.0 * s))


## a lift the owner made (multiplayer copy only)
func queue_lift(i: int, dur: float, lift: float) -> void:
	_queued.append([clampi(i, 0, 3), dur, lift, 0.0])


func _begin_swing(i: int, dur: float, lift: float, home_w: Vector3, xf: Transform3D, decided := false) -> void:
	if decided and rig and rig.get("net_record"):
		rig.call("_log", ["L", i, dur, lift])   # a step this cat chose to take: copies replay it
	mode[i] = SWING
	sw_t[i] = 0.0
	_dur[i] = dur
	_lift[i] = lift
	_from[i] = xf.affine_inverse() * pos[i]
	_ray2[i] = false
	_vary[i] = 1.0 + _rng.randf_range(-0.05, 0.05)
	_gy[i] = (xf.affine_inverse() * _ground(home_w, xf.origin.y, i)).y
	_fyw[i] = pos[i].y
	_gyw[i] = xf.origin.y + _gy[i]
	_adj[i] = Vector3.ZERO
	_clr[i] = 0.0
	_clr_t[i] = 0.0
	_grd[i] = 0.0
	_aim[i] = 0
	sw_amp[i] = clampf((home_w - pos[i]).length() / 0.1, 0.3, 1.0) if moving < 0.5 else 1.0


## call when the body leaves the ground by its own push: hind paws stay planted a moment
func takeoff() -> void:
	_hold[2] = 0.05
	_hold[3] = 0.05
	_hold[0] = 0.0
	_hold[1] = 0.0
