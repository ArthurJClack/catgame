class_name CatStop
extends RefCounted
## how the cat comes to a stop. a real cat almost never stops the same way twice: it depends on
## how fast it was going, what gait it was in, and what it feels like doing. this picks one of a
## set of procedural stops every time the cat pulls up, and drives it through the same hooks the
## rest of the living layer uses (body height / pitch, paw offsets on top of the gait, head,
## tail springs, ear flicks, claws), so it sits on top of the biomechanics instead of replacing it.
##
##   braking (canter / gallop, while it is still slowing down):
##     skid    fore legs braced out in front, hips sit down, claws out, head comes up; the body
##             rocks forward over the fore paws as it lets go
##   stopped (picked from how fast it came in, never the same one twice running):
##     halt      just stops, a small settle
##     pawlift   a fore paw is left hanging mid step, held, then put down (walking up to things)
##     look      head turns off to one side, sometimes the other side too, ears go with it
##     glance    a look back over the shoulder (after a run)
##     tailflick a couple of flicks of the tail and an ear
##     shuffle   paws pick up and put down again on the spot, weight shifting over them
##     rockback  the body rocks forward over the fore legs and back again
##     blown     head drops, chest heaving (after a sprint)
##     sit / shake / stretch / sniff: a short beat, then the matching soma act
##
## starting a stop goes through soma.act("stop", code) / soma.act("brake", 1), so it is written
## to the life log and multiplayer copies play the same stop (code carries the random seed).

## master switch (static, like the biomech switches; CAT_OFF=stops turns it off)
static var stops := true

var soma: CatSoma
var rig: CatRig

# ---- outputs, rebuilt every frame (all zero when nothing is playing) ----
var dip := 0.0        # body height (m)
var pitch := 0.0      # body pitch (rad, + = nose up)
var zoff := 0.0       # body fore / aft (m, + = back)
var roll := 0.0       # chest roll (rad)
var paw: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var head_p := 0.0     # head pitch (+ = up)
var head_y := 0.0     # head yaw (+ = left)
var head_r := 0.0
var neck_p := 0.0
var neck_y := 0.0
var tail_p := 0.0     # tail lift (rad, at the base, more toward the tip)
var tail_y := 0.0
var claws := 0.0
var breath := 0.0     # extra exertion while blown

var kind := ""        # the stop playing now ("" = none)
var brake := 0.0      # 0..1 skid brace while slowing
var last: Array[String] = []

const KINDS := ["halt", "pawlift", "look", "glance", "tailflick", "shuffle", "rockback", "blown", "sit", "shake", "stretch", "sniff"]
## how likely each stop is, by how fast the cat was going before it stopped:
## [walk (< 1.4 m/s), trot (< 4.5), run (canter / gallop)]
const WEIGHTS := {
	"halt":      [1.0, 0.6, 0.0],
	"pawlift":   [1.6, 0.5, 0.0],
	"look":      [1.4, 1.2, 0.8],
	"glance":    [0.0, 0.5, 1.2],
	"tailflick": [1.2, 1.0, 0.6],
	"shuffle":   [0.3, 1.4, 1.2],
	"rockback":  [0.0, 1.2, 1.4],
	"blown":     [0.0, 0.0, 1.4],
	"sit":       [0.7, 0.7, 0.5],
	"shake":     [0.0, 0.5, 0.7],
	"stretch":   [0.25, 0.4, 0.0],
	"sniff":     [1.0, 0.6, 0.0],
}

var _t := 0.0
var _dur := 0.0
var _rng := RandomNumberGenerator.new()
var _side := 1.0
var _hold := 0.6
var _seq: Array = []      # shuffle: [paw, start time] pairs; look: second side or not
var _amp := 1.0
var _peak := 0.0          # fastest the cat went since it last stood still
var _tier := 0
var _moved_t := 0.0
var _spd_prev := 0.0
var _decel := 0.0
var _brake_on := false
var _no_skid := false
var _brake_rel := 0.0     # after the skid: the rock forward as the brace lets go
var _brake_peak := 0.0
var _chain := ""          # soma act to fire after the beat (sit / shake / stretch / sniff)
var _chain_at := 0.0
var _flicks: Array = []   # tail flick impulse times
var _sm := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _smp: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _dt := 0.016


func setup(s: CatSoma) -> void:
	soma = s
	rig = s.rig


func active() -> bool:
	return kind != "" or brake > 0.02


## start a stop (from soma.act, so it is logged / replayed). code = kind index * 1000 + seed
func begin(code: float) -> void:
	var c := int(code)
	var i := clampi(c / 1000, 0, KINDS.size() - 1)
	kind = KINDS[i]
	_rng.seed = c % 1000 + 7919 * i
	_t = 0.0
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_amp = _rng.randf_range(0.8, 1.15)
	_chain = ""
	_flicks.clear()
	_seq.clear()
	last.push_front(kind)
	if last.size() > 2:
		last.resize(2)
	match kind:
		"halt":
			_dur = 0.7
		"pawlift":
			_hold = _rng.randf_range(0.45, 1.1)
			_dur = _hold + 0.45
		"look":
			_hold = _rng.randf_range(0.5, 1.0)
			var two := _rng.randf() < 0.45
			_seq = [two]
			_dur = (0.35 + _hold) * (2.0 if two else 1.0) + 0.45
		"glance":
			_hold = _rng.randf_range(0.4, 0.8)
			_dur = _hold + 0.9
		"tailflick":
			var n := _rng.randi_range(2, 4)
			var at := _rng.randf_range(0.05, 0.2)
			for k in n:
				_flicks.append(at)
				at += _rng.randf_range(0.22, 0.42)
			_dur = at + 0.4
		"shuffle":
			# fore paws mostly, sometimes the hind ones come up to them after
			var order := [0, 1] if _side > 0.0 else [1, 0]
			var at := 0.08
			for p in order:
				_seq.append([p, at])
				at += _rng.randf_range(0.2, 0.3)
			if _rng.randf() < 0.55:
				_seq.append([order[0], at])
				at += 0.26
			if _rng.randf() < 0.5:
				for p in ([2, 3] if _rng.randf() < 0.5 else [3, 2]):
					_seq.append([p, at])
					at += _rng.randf_range(0.18, 0.26)
			_dur = at + 0.3
		"rockback":
			_dur = 1.1
		"blown":
			_hold = _rng.randf_range(1.2, 2.2)
			_dur = _hold + 0.5
			if _rng.randf() < 0.4:
				_chain = "sit" if _rng.randf() < 0.6 else "shake"
				_chain_at = _hold
		"sit", "shake", "stretch", "sniff":
			_chain = kind
			_chain_at = _rng.randf_range(0.15, 0.45)
			_dur = _chain_at + 0.05


## brake: the skid brace while a fast cat is still slowing down (v = 1 on, 0 = let go)
func begin_brake(v: float) -> void:
	_brake_on = v > 0.5
	if _brake_on:
		_brake_peak = rig.speed_s
	else:
		_brake_rel = 1.0


## pick a stop for how fast the cat was going (only the owner does this)
func _pick() -> void:
	var tot := 0.0
	var opts := []
	for k in KINDS:
		var w: float = (WEIGHTS[k] as Array)[_tier]
		if k in last:
			w *= 0.0 if k == last[0] else 0.35
		if k == "sit" and soma.exertion > 0.6:
			w *= 0.3
		if k == "stretch" and soma.exertion > 0.4:
			w = 0.0
		if w > 0.0:
			opts.append([k, w])
			tot += w
	if opts.is_empty():
		return
	var r := randf() * tot
	var pick: String = opts[0][0]
	for o in opts:
		r -= float(o[1])
		if r <= 0.0:
			pick = o[0]
			break
	soma.act("stop", KINDS.find(pick) * 1000 + randi() % 1000)


func _clear() -> void:
	dip = 0.0
	pitch = 0.0
	zoff = 0.0
	roll = 0.0
	head_p = 0.0
	head_y = 0.0
	head_r = 0.0
	neck_p = 0.0
	neck_y = 0.0
	tail_p = 0.0
	tail_y = 0.0
	claws = 0.0
	breath = 0.0
	for i in 4:
		paw[i] = Vector3.ZERO


static func _bump(t: float, a: float, b: float, c: float, d: float) -> float:
	# 0 before a, up to 1 by b, held to c, back to 0 by d
	return smoothstep(a, b, t) * (1.0 - smoothstep(c, d, t))


## a paw picked up and put down again on its spot (u 0..1 over the step)
static func _tap(u: float, side: float, fwd: float) -> Vector3:
	if u <= 0.0 or u >= 1.0:
		return Vector3.ZERO
	var s := sin(PI * u)
	return Vector3(side * 0.004 * s, 0.026 * s, fwd * 0.012 * sin(TAU * u * 0.5) * s)


func tick(dt: float, grounded: bool, busy: bool) -> void:
	_clear()
	_tick(dt, grounded, busy)
	# first person: the camera rides the head, and the look stays on the mouse. head turns
	# would only slide the eye sideways, so they're kept small there; body moves stay
	if rig._head_hidden:
		head_y *= 0.15
		neck_y *= 0.15
		head_p *= 0.4
		neck_p *= 0.4
	# everything eases (a stop cut short by moving off fades out in a few frames, no pop)
	var raw := [dip, pitch, zoff, roll, head_p, head_y, head_r, neck_p, neck_y, tail_p, tail_y, claws, breath]
	var k := 1.0 - exp(-22.0 * dt)
	for i in raw.size():
		_sm[i] = lerpf(_sm[i], raw[i], k)
	dip = _sm[0]; pitch = _sm[1]; zoff = _sm[2]; roll = _sm[3]
	head_p = _sm[4]; head_y = _sm[5]; head_r = _sm[6]; neck_p = _sm[7]; neck_y = _sm[8]
	tail_p = _sm[9]; tail_y = _sm[10]; claws = _sm[11]; breath = _sm[12]
	for i in 4:
		_smp[i] = _smp[i].lerp(paw[i], k)
		paw[i] = _smp[i]


func _tick(dt: float, grounded: bool, busy: bool) -> void:
	var spd: float = rig.speed_s
	# how hard the cat is slowing (m/s^2, smoothed)
	var dv := (_spd_prev - spd) / maxf(dt, 0.0001)
	_spd_prev = spd
	_decel = LowPoly.damp(_decel, dv, 4.0, dt)

	if not stops:
		kind = ""
		brake = 0.0
		return

	# ---- what the cat came in with
	if spd > 0.3 and grounded:
		_moved_t += dt
		if spd > _peak:
			_peak = spd
			_tier = 0 if _peak < 1.4 else (1 if _peak < 4.5 else 2)
	var owner: bool = not rig.remote_life and rig.idle_life

	# ---- moving again (or busy, or off the ground): whatever stop was playing gives way
	if kind != "" and (spd > 0.4 or busy or not grounded):
		kind = ""
		_chain = ""

	# ---- skid: a fast cat slowing hard braces its fore legs out and sits back on its hips
	if owner and grounded and not busy:
		if not _brake_on and not _no_skid and spd > 3.0 and _decel > 2.6 and _peak > 4.5:
			if randf() < (1.0 if _decel > 6.0 else 0.6):
				soma.act("brake", 1.0)
			else:
				_no_skid = true   # it chops down through its strides instead this time
		elif _brake_on and (spd < 0.45 or _decel < 0.6):
			soma.act("brake", 0.0)
	if _brake_on and (busy or not grounded or spd > _brake_peak + 0.6):
		_brake_on = false
		_brake_rel = 0.0
	brake = LowPoly.damp(brake, clampf(_decel / 5.0, 0.6, 1.0) if _brake_on else 0.0, 10.0 if _brake_on else 6.0, dt)
	if brake > 0.01:
		# fore paws out in front (reach forward and plant, the paw tips dig in), hind end sits
		# down, body pitched back over the hips, head up and back
		var b := brake
		for i in 2:
			paw[i] += Vector3(0.0, 0.0, -0.022 * b)
		for i in range(2, 4):
			paw[i] += Vector3(0.0, 0.0, -0.012 * b)
		pitch += 0.13 * b
		dip -= 0.022 * b
		zoff += 0.012 * b
		head_p += 0.12 * b
		neck_p += 0.08 * b
		tail_p += 0.25 * b
		claws = maxf(claws, b)
	if _brake_rel > 0.0:
		# letting go of the brace: the body carries on forward over the fore legs, then settles
		var u := 1.0 - _brake_rel
		var rk := sin(u * PI * 1.6) * exp(-u * 2.6) * smoothstep(0.0, 0.08, u)
		pitch -= 0.1 * rk
		zoff -= 0.014 * rk
		dip -= 0.01 * absf(rk)
		head_p += 0.06 * rk
		_brake_rel = maxf(_brake_rel - dt / 0.9, 0.0)

	# ---- came to a stop: pick how it stops
	if owner and grounded and not busy and spd < 0.15 and _peak > 0.35 and _moved_t > 0.35 and kind == "" and soma.act_name == "" and not _brake_on:
		_pick()
	if spd < 0.15 and not _brake_on:
		_peak = 0.0
		_no_skid = false
		_moved_t = 0.0

	if kind == "":
		return
	_t += dt
	if _chain != "" and _t >= _chain_at:
		var ch := _chain
		_chain = ""
		if owner:
			soma.act(ch, (1.0 if _side > 0.0 else -1.0) if ch == "tilt" else 0.0)
	if _t >= _dur:
		kind = ""
		return
	_dt = dt
	_play()


func _play() -> void:
	var t := _t
	var s := _side
	var a := _amp
	match kind:
		"halt":
			# the weight comes down onto the legs once and settles
			dip -= 0.006 * sin(clampf(t / 0.45, 0.0, 1.0) * PI) * a
			pitch -= 0.025 * sin(clampf(t / 0.5, 0.0, 1.0) * PI) * a
		"pawlift":
			# the fore paw on one side stays up, held just off the ground, then goes down
			var pi_ := 0 if s > 0.0 else 1
			var up := _bump(t, 0.0, 0.16, _hold, _hold + 0.22)
			var side := -1.0 if pi_ == 0 else 1.0
			paw[pi_] += Vector3(side * 0.003, 0.036 * up, -0.012 * up + 0.004 * sin(t * 2.3) * up)
			# weight onto the other three: the chest leans off the lifted side a touch
			roll -= side * 0.035 * up
			head_p -= 0.08 * up
			neck_p -= 0.05 * up
			head_y += 0.12 * sin(t * 1.7) * up
			if t > _hold and t - _dt <= _hold:
				rig._ear_flick[pi_] = 1.0
		"look", "glance":
			var ang := 0.7 * a if kind == "look" else 1.15
			var turn := 0.35
			var w1 := _bump(t, 0.0, turn, turn + _hold, turn * 2.0 + _hold)
			var y := s * ang * w1
			if kind == "look" and _seq.size() > 0 and bool(_seq[0]):
				var t0 := turn * 2.0 + _hold
				y -= s * ang * 0.85 * _bump(t, t0 - 0.1, t0 + turn, t0 + turn + _hold, t0 + turn * 2.0 + _hold)
			# the neck does most of a big turn, the head the rest; a look back rolls the chest
			neck_y += y * 0.55
			head_y += y * 0.45
			head_p += 0.05 * absf(y)
			if kind == "glance":
				roll += 0.06 * y
				pitch += 0.02 * absf(y)
			if absf(y) > 0.2 and t < 0.05:
				rig._ear_flick[0 if s > 0.0 else 1] = 1.0
		"tailflick":
			tail_p += 0.3 * _bump(t, 0.0, 0.25, _dur - 0.4, _dur)
			for k in _flicks.size():
				var at: float = _flicks[k]
				if t >= at and t - _dt < at:
					rig._twitch((8.5 if k % 2 == 0 else -8.5) * s * a)
					if k == 0:
						rig._ear_flick[0 if s > 0.0 else 1] = 1.0
		"shuffle":
			for e in _seq:
				var p: int = e[0]
				var u := (t - float(e[1])) / 0.24
				if u > 0.0 and u < 1.0:
					var side := -1.0 if p % 2 == 0 else 1.0
					paw[p] += _tap(u, side, 1.0 if p < 2 else -0.6)
					# weight over to the other side while that paw is up
					var lift := sin(PI * u)
					if p < 2:
						roll -= side * 0.04 * lift
					else:
						pitch -= 0.015 * lift
					dip -= 0.004 * lift
		"rockback":
			# a damped rock: forward over the fore legs, back onto the hips, settle
			var rk := sin(t * 8.2) * exp(-t * 3.6) * smoothstep(0.0, 0.05, t) * a
			pitch -= 0.075 * rk
			zoff -= 0.012 * rk
			dip -= 0.008 * absf(rk)
			head_p += 0.05 * rk
			tail_p -= 0.15 * rk
		"blown":
			# head hangs low, back sags a little, flanks heaving (soma breathing)
			var w := _bump(t, 0.0, 0.5, _hold, _hold + 0.5)
			head_p -= 0.14 * w
			neck_p -= 0.16 * w
			dip -= 0.01 * w
			pitch -= 0.03 * w
			breath = 0.9 * w
			tail_p -= 0.2 * w
		_:
			pass
