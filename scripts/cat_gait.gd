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

# stride length (m) by speed (m/s). walk strides sit near 0.34 so the hind paw lands
# in the front paw's print (direct register), then lengthen
const STRIDE_V := [0.0, 0.5, 0.9, 1.5, 2.4, 3.2, 6.0, 11.0]
const STRIDE_L := [0.30, 0.335, 0.42, 0.56, 0.80, 1.10, 1.75, 2.60]
# fraction of the stride each paw spends on the ground
const DUTY_V := [0.0, 0.3, 0.5, 0.9, 1.5, 2.4, 3.2, 6.0, 11.0]
const DUTY_D := [0.80, 0.76, 0.70, 0.62, 0.48, 0.40, 0.36, 0.28, 0.20]
const GALLOP_UP := 3.9
const GALLOP_DOWN := 3.4

var rig: Node3D
var phase := 0.0
var stride := 0.3
var duty := 0.7
var freq := 0.0
var lag := 0.25       # fore paw touches down this fraction of a stride after the hind on its side
var gallop := 0.0     # 0..1
var moving := 0.0     # 0..1
var w_walk := 1.0
var w_trot := 0.0
var max_stance := 0.26
var max_stance_gallop := 0.34
var use_rays := true
var exclude: Array[RID] = []

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
	_since_land += dt
	var stance_len := minf(duty * stride, lerpf(max_stance, max_stance_gallop, gallop)) * clampf(spd / 0.25, 0.0, 1.0)
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
			if mode[i] != FREE:
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
				elif (e > stance_len * 0.5 + 0.09 or stretch[i] > 0.998) and _st_t[i] > minf(0.06, duty / maxf(freq, 0.01)) and (mode[i ^ 1] == PLANTED or gallop > 0.5 or e > 0.3):
					lift = true
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
			if lift:
				var d := clampf((1.0 - duty) / maxf(freq, 0.01), 0.085, 0.36)
				_begin_swing(i, d, lift_h * (1.0 if i < 2 else 0.85), home_w, xf)
				n_swing += 1
		if mode[i] == SWING:
			sw_t[i] += dt / _dur[i]
			# the swing is planned in body space: from where the paw left the ground (as the body
			# saw it then) to its rest spot plus half a stance ahead. at touch down the hip is
			# exactly half a stance behind the paw, whatever the body did in between
			var tl: Vector3 = (homes[i] as Vector3) + ldir * stance_len * 0.5 * _vary[i]
			if not _ray2[i] and sw_t[i] > 0.45:
				_ray2[i] = true
				_gy[i] = (inv * _ground(xf * tl, xf.origin.y, i)).y
			tl.y = _gy[i]
			var s: float = clampf(sw_t[i], 0.0, 1.0)
			var ease := s * s * (3.0 - 2.0 * s)
			var fr: Vector3 = _from[i]
			var p: Vector3 = fr.lerp(tl, ease)
			# leave and meet the ground at ground speed (the paw is already travelling backwards
			# under the body when it touches down), as far as the leg's reach allows
			var back := minf(spd * _dur[i], 1.25 * Vector2(tl.x - fr.x, tl.z - fr.z).length())
			p -= ldir * back * s * (2.0 * s - 1.0) * (s - 1.0)
			# lift early, reach late, plant softly. clear the higher of the two ends
			var hi := maxf(fr.y, tl.y)
			p.y = lerpf(p.y, hi, sin(PI * s)) + _lift[i] * sin(PI * pow(s, 0.65))
			pos[i] = xf * p
			if sw_t[i] >= 1.0:
				pos[i] = xf * tl
				mode[i] = PLANTED
				_st_t[i] = 0.0
				st_s[i] = 0.0
				touched[i] = true
				_idle_t[i] = -0.05
		load[i] = move_toward(load[i], 1.0 if mode[i] == PLANTED else 0.0, dt * 14.0)

	# settling / turn in place steps
	if worst >= 0 and _since_land > 0.12:
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
			_begin_swing(worst, d, clampf(0.012 + worst_err * 0.2, 0.014, 0.04), xf * (homes[worst] as Vector3), xf)
			_idle_t[worst] = 0.0


func _begin_swing(i: int, dur: float, lift: float, home_w: Vector3, xf: Transform3D) -> void:
	mode[i] = SWING
	sw_t[i] = 0.0
	_dur[i] = dur
	_lift[i] = lift
	_from[i] = xf.affine_inverse() * pos[i]
	_ray2[i] = false
	_vary[i] = 1.0 + _rng.randf_range(-0.05, 0.05)
	_gy[i] = (xf.affine_inverse() * _ground(home_w, xf.origin.y, i)).y
	sw_amp[i] = clampf((home_w - pos[i]).length() / 0.1, 0.3, 1.0) if moving < 0.5 else 1.0


## call when the body leaves the ground by its own push: hind paws stay planted a moment
func takeoff() -> void:
	_hold[2] = 0.05
	_hold[3] = 0.05
	_hold[0] = 0.0
	_hold[1] = 0.0
