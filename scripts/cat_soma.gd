class_name CatSoma
extends RefCounted
## the soft, living layer on top of the cat rig's skeleton: everything a real cat does that is
## not locomotion. the rig owns the bones (paws, spine, head target), this owns
##   breathing that follows exertion (flanks, not just the chest; open mouth after a long sprint)
##   loose skin: the loin jiggles on impacts, the belly pouch swings under the hips
##   whiskers (fan forward to hunt / sniff, pin back at speed or in fear, quiver)
##   ears (airplane ears when startled, floppy tips on impacts and head shakes, radar when sat)
##   eyes (pupils go from slits to saucers, the eyes move before the head does, slow blinks)
##   idle acts (sniff, head tilt, yawn, full body shake, sit down, groom, loaf) and waking from them
##   startle: flinch, puffed tail, raised back
##   head lock on prey
##   wet paws: each wet paw flicks as it swings, and gets shaken off when the cat stops
##   fights (with rig.fight_anim): the hackles stand up along the spine and the tail bottle brushes,
##   ears pin flat back or swivel at the threat, and it hisses: mouth wide, fangs out, lips back,
##   head low and forward, with the hiss sound on the same frame (hiss act, so it syncs online)
##
## the rig calls pre() before it solves the body and legs (things that move bones) and post()
## after everything is posed (things that only dress the pose).
## every act the cat decides on by itself goes through act(), which writes it to the rig's
## life_log, so multiplayer copies of this cat do the same thing at the same moment.

var rig: CatRig

# ---- read by the rig (bone level) ----
var dip := 0.0        # body height offset (m): flinch, the sag at the bottom of a yawn
var roll_c := 0.0     # chest roll (rad): body shake
var roll_p := 0.0     # pelvis roll
var paw_off: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]  # rig space
var auto_sit := 0.0
var auto_groom := 0.0
var auto_loaf := 0.0
var auto_stretch := 0.0
var pitch := 0.0      # body pitch (rad, + = nose up): how it stops (cat_stop.gd)
var zoff := 0.0       # body fore / aft (m)
var rise_rate := 1.8  # how fast the cat gets up out of a sit (it scrambles up if told to move)

# ---- state other things may read ----
var exertion := 0.0   # 0 rested .. 1 blown
var startle := 0.0    # 0..1, fades over a few seconds
var wet: Array[float] = [0.0, 0.0, 0.0, 0.0]
var act_name := ""    # the timed act that is playing ("" = none)
## how it comes to a stop: a different stop every time (skid, paw lift, look round, ...)
var stop := CatStop.new()
var breath_hz := 0.42

var _act_t := 0.0
var _act_dur := 0.0
var _act_arg := 0.0
var _next_act := 4.0
var _sit_at := 9.0
var _rest := false      # sat down by itself
var _rest_t := 0.0
var _loafed := false
var _groom_left := 0.0
var _st_age := 9.0
var _br_ph := 0.0
var _mouth := 0.0
var _blink := 0.0       # slow blink envelope
var _jig := 0.0
var _jig_v := 0.0
var _py := 0.0
var _pvy := 0.0
var _px := 0.0
var _pvx := 0.0
var _pinit := false
var _pouch_a := 0.0     # pouch swing (rad), side to side
var _pouch_v := 0.0
var _pouch_b := 0.0     # fore-aft
var _pouch_bv := 0.0
var _ear_w := [0.0, 0.0]
var _ear_wv := [0.0, 0.0]
var _wh := 0.0          # whisker fan, -1 pinned back .. 1 forward
var _wh_q := 0.0        # quiver spring
var _wh_qv := 0.0
var _hq := Quaternion.IDENTITY
var _hq_init := false
var _pupil := 0.0
var _lock_w := 0.0
var _lock_yaw := 0.0
var _lock_pitch := 0.0
var _lock_t := 0.0
var _lock_node: Node3D
var _puff := 0.0
var _wet_any := 0.0
var _shake_paw := -1

var pouch: MeshInstance3D
var mouth: MeshInstance3D
var _pouch_s := Vector3.ONE
var _chin_p := Vector3.ZERO
var _pupil_s: Array = []
var _pupil_p: Array = []
var _tj_s: Array = []
var _puffed := false
var hackles: Array[MeshInstance3D] = []
var _hk: Array = []        # per shard: [parent kind, index, local point, splay, size]
var fangs: Array[MeshInstance3D] = []
var _hiss_cool := 2.0
var _fight_on := false
var hisses := 0            # tests

# timed acts: how long each one runs
const ACT_DUR := {"sniff": 1.5, "tilt": 1.4, "yawn": 2.1, "shake": 1.05, "blink": 1.3, "pawshake": 0.75, "stretch": 2.6, "hiss": 1.15}


func setup(r: CatRig) -> void:
	rig = r
	stop.setup(self)
	var gi: float = rig.S_.girth
	var ln: float = rig.S_.len
	# the primordial pouch: the loose flap of belly skin in front of the hind legs
	var col: Color = rig.belly if rig.pattern != "solid" else rig.fur.lightened(0.1)
	_pouch_s = Vector3(0.058 * gi, 0.034 * gi, 0.105 * ln)
	pouch = LowPoly.part(rig.pivot, LowPoly.box(), col, Vector3.ZERO, _pouch_s)
	rig._style_mat(pouch)
	# the inside of the mouth, only seen when the jaw drops (yawn, panting)
	mouth = LowPoly.part(rig.head, LowPoly.box(0.0), Color(0.42, 0.12, 0.16), Vector3(0, -0.026, -0.034), Vector3(0.018, 0.004, 0.02))
	mouth.visible = false
	if rig.chin:
		_chin_p = rig.chin.position
	for e in rig.eyes:
		var p: Node3D = (e as Node3D).get_child(1)
		_pupil_s.append(p.scale)
		_pupil_p.append(p.position)
	for j in rig.tail_joints:
		_tj_s.append((j as MeshInstance3D).scale)
	_build_hackles(gi, ln)
	# upper fangs, only seen with the mouth open (hissing, yawning)
	for sd in [-1.0, 1.0]:
		var mzs: float = rig.S_.get("muzzle", 1.0)
		var fg := LowPoly.part(rig.head, LowPoly.cone(3), Color(0.96, 0.94, 0.88), Vector3(sd * 0.0075, -0.0345, -0.03 - 0.013 * mzs), Vector3(0.0036, 0.012, 0.0036), Vector3(PI, 0, 0))
		fg.visible = false
		fangs.append(fg)
	_next_act = randf_range(2.5, 6.0)
	_sit_at = randf_range(7.0, 12.0)


# ------------------------------------------------------------------ acts

## start an act. the cat does this by itself when idle, and anything else may call it too
## (rig.soma.act("yawn")). kinds: sniff, tilt, yawn, shake, blink, pawshake, stretch,
## and the standing ones: sit, groom, loaf, up
func act(kind: String, arg := 0.0) -> void:
	if rig.remote_life and not rig._net_apply:
		return
	rig._log(["a", kind, arg])
	match kind:
		"stop":
			stop.begin(arg)
			return
		"brake":
			stop.begin_brake(arg)
			return
		"sit":
			_rest = true
			_rest_t = 0.0
			_loafed = false
		"groom":
			_groom_left = maxf(arg, 3.4)
		"loaf":
			_rest = true
			_loafed = true
		"up":
			_rest = false
			_loafed = false
			_groom_left = 0.0
		_:
			if not ACT_DUR.has(kind):
				return
			if kind == "hiss":
				hisses += 1
				if rig.is_inside_tree():
					CatSfx.play_at("hiss", rig.head.global_position, 0.8, randf_range(0.94, 1.08))
			act_name = kind
			_act_t = 0.0
			_act_dur = ACT_DUR[kind]
			_act_arg = arg
			if kind == "pawshake":
				_shake_paw = clampi(int(arg), 0, 3)


## something loud and close: the cat flinches down, ears flat, pupils wide, tail puffed
func scare(amount := 1.0) -> void:
	if amount < startle:
		return
	startle = clampf(amount, 0.0, 1.0)
	_st_age = 0.0
	if _rest and amount > 0.5:
		_rest = false
		_loafed = false
		_groom_left = 0.0


## the rig heard something (CatRig.hear)
func heard(pos: Vector3, loud: float) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var d: float = pos.distance_to(rig.global_position)
	if loud >= 0.8 and d < 3.5 and rig.speed_s < 1.5:
		scare(clampf(loud * (1.0 - d / 5.0), 0.0, 1.0))


func _env(a: float, b: float) -> float:
	# 0 -> 1 over the first a of the act, 1 -> 0 over the last b
	var u := _act_t / maxf(_act_dur, 0.001)
	return smoothstep(0.0, a, u) * (1.0 - smoothstep(1.0 - b, 1.0, u))


func _on(kind: String) -> bool:
	return act_name == kind


# ------------------------------------------------------------------ before the body is solved

func pre(dt: float) -> void:
	var spd: float = rig.speed_s
	# (carried: a climb move has the body, cat_climb.gd. no stops or idle acts till it's back on its paws)
	var grounded: bool = rig.on_floor and rig.climb < 0.1 and rig.clamber < 0.1 and rig.carried < 0.05 and not rig.on_wall
	var busy: bool = rig.crouch > 0.2 or rig.charge > 0.05 or rig.claw_on or rig.is_swatting() or rig.scratch > 0.05 or rig.rear > 0.05 or rig.pin > 0.05 or rig.grip > 0.05
	var calm: bool = grounded and not busy and spd < 0.12
	stop.tick(dt, grounded, busy)

	# ---- exertion: sprinting and climbing build it up, standing around pays it back
	var work := smoothstep(2.4, 9.0, spd) * 0.11 + rig.climb * 0.05
	exertion = clampf(exertion + (work - 0.04 * (1.0 - smoothstep(0.5, 3.0, spd))) * dt, 0.0, 1.0)

	# ---- startle
	_st_age += dt
	startle = maxf(startle - dt * 0.38, 0.0)
	var flinch := smoothstep(0.0, 0.05, _st_age) * exp(-_st_age * 4.5) * (1.0 if _st_age < 3.0 else 0.0)
	_puff = LowPoly.damp(_puff, smoothstep(0.35, 0.8, startle), 12.0 if startle > _puff else 1.6, dt)

	# ---- timed act clock
	if act_name != "":
		_act_t += dt
		if _act_t >= _act_dur or (not grounded and act_name != "blink" and act_name != "hiss"):
			act_name = ""
			_shake_paw = -1
	# moving off cancels the slow ones (a cat mid yawn that sees a mouse just goes)
	if act_name in ["yawn", "stretch", "tilt", "pawshake"] and (spd > 0.3 or busy):
		act_name = ""
		_shake_paw = -1

	# ---- resting: told to move, or anything interesting happens, and it is up at once
	if _rest and (not calm or startle > 0.5):
		_rest = false
		_loafed = false
		_groom_left = 0.0
	if _rest:
		_rest_t += dt
	_groom_left = maxf(_groom_left - dt, 0.0)
	rise_rate = 6.5 if (spd > 0.15 or busy or not grounded) else 1.8
	auto_sit = 1.0 if _rest else 0.0
	auto_loaf = 1.0 if (_rest and _loafed) else 0.0
	auto_groom = LowPoly.damp(auto_groom, 1.0 if (_rest and not _loafed and _groom_left > 0.0 and rig._sit_s > 0.95) else 0.0, 5.0, dt)
	auto_stretch = _env(0.22, 0.25) if _on("stretch") else 0.0

	# ---- wet paws
	_wet_any = 0.0
	var in_forest: bool = Water.mat != null
	for i in 4:
		var gp: Vector3 = rig.gait.pos[i]
		var in_water: bool = in_forest and gp.y < ForestLevel.WATER_Y + 0.03 and Water.is_water(gp.x, gp.z)
		if in_water and rig.gait.mode[i] == CatGait.PLANTED:
			wet[i] = 1.0
		else:
			wet[i] = maxf(wet[i] - dt * 0.11, 0.0)
		_wet_any = maxf(_wet_any, wet[i] * (0.0 if in_water else 1.0))
		# a wet paw is flicked out to the side and back as it swings forward
		var off := Vector3.ZERO
		var side := -1.0 if i % 2 == 0 else 1.0
		if wet[i] > 0.25 and not in_water and rig.gait.mode[i] == CatGait.SWING:
			var s := clampf(float(rig.gait.sw_t[i]), 0.0, 1.0)
			var e := sin(PI * s) * smoothstep(0.25, 0.6, wet[i]) * (1.0 - smoothstep(1.2, 2.5, spd))
			off = Vector3(side * 0.012 * sin(rig._t * 58.0), 0.014 + 0.006 * sin(rig._t * 58.0 + 1.0), 0.01 * sin(rig._t * 58.0 + 2.0)) * e
		if _on("pawshake") and _shake_paw == i:
			# stopped: the paw comes up, is held out and shaken hard, and goes back down
			var e2 := _env(0.2, 0.25)
			var k := sin(_act_t * 66.0)
			off = Vector3(side * (0.02 + 0.014 * k), 0.045 + 0.008 * k, (0.03 if i >= 2 else -0.02) + 0.012 * sin(_act_t * 66.0 + 1.3)) * e2
			wet[i] = maxf(wet[i] - dt * 1.2, 0.0)
		paw_off[i] = off

	# ---- body shake: starts at the head and runs down the spine to the tail
	roll_c = 0.0
	roll_p = 0.0
	if _on("shake"):
		var w := 62.0   # ~10 hz, what a cat really does
		roll_c = 0.13 * sin(_act_t * w - 1.1) * _win(0.12, 0.62)
		roll_p = 0.12 * sin(_act_t * w - 2.3) * _win(0.25, 0.78)
		if _act_t > 0.3 and _act_t < 0.95:
			rig._twitch(sin(_act_t * w - 3.4) * 3.2)

	# ---- body height: the flinch, the yawn's sag
	dip = -0.03 * flinch
	if _on("yawn"):
		dip -= 0.004 * _env(0.3, 0.3)
	# ---- how it stops
	dip += stop.dip
	pitch = stop.pitch
	zoff = stop.zoff
	roll_c += stop.roll
	for i in 4:
		paw_off[i] += stop.paw[i]

	# ---- fights: hiss going into one, and now and then while standing its ground
	_hiss_cool -= dt
	if not rig.remote_life and CatFightAnim.on:
		var f: float = rig.fight
		if f > 0.5 and not _fight_on:
			_fight_on = true
			if _hiss_cool <= 0.0 and act_name != "hiss":
				act("hiss")
				_hiss_cool = randf_range(3.0, 5.0)
		elif f < 0.2:
			_fight_on = false
		if rig.fight_anim.threat > 0.75 and _hiss_cool <= 0.0 and act_name == "":
			act("hiss")
			_hiss_cool = randf_range(3.5, 7.0)

	# ---- what to do next, when nothing is going on
	if rig.remote_life or not rig.idle_life:
		return
	var still_t: float = rig._still_t
	if not calm:
		_next_act = maxf(_next_act, randf_range(1.5, 3.5))
		# on the move: the odd sniff at a walk, and that is it
		if grounded and not busy and spd > 0.3 and spd < 1.0 and act_name == "":
			_next_act -= dt * 0.35
			if _next_act < 0.0:
				_next_act = randf_range(4.0, 9.0)
				act("sniff")
		return
	if act_name != "" or auto_groom > 0.05 or stop.kind != "":
		return
	if _wet_any > 0.3 and still_t > 0.5:
		var wi := 0
		for i in 4:
			if wet[i] > wet[wi]:
				wi = i
		act("pawshake", wi)
		return
	# (balancing along a beam it doesn't sit, but perched on a post / box / fence top it does,
	# and soon: a cat up on something small settles into a sit rather than standing bunched)
	var perched: bool = CatPerch.perch and rig.perch.w > 0.5
	var sit_wait := minf(_sit_at, 2.5 + 0.2 * _sit_at) if perched and rig.perch.bunch > 0.3 else _sit_at
	if not _rest and still_t > sit_wait and rig.balance < 0.3 and (rig._bal_auto < 0.5 or perched) and exertion < 0.6:
		_sit_at = randf_range(7.0, 12.0)
		act("sit")
		_next_act = randf_range(1.5, 3.0)
		return
	if _rest and not _loafed and _rest_t > 38.0:
		act("loaf")
		return
	_next_act -= dt
	if _next_act > 0.0 or still_t < 1.2:
		return
	_next_act = randf_range(2.2, 6.5)
	var r := randf()
	if _rest and not _loafed:
		if r < 0.3:
			act("groom", 3.4 * float(randi_range(1, 3)))
		elif r < 0.55:
			act("blink")
		elif r < 0.7:
			act("yawn")
		elif r < 0.85:
			act("tilt", 1.0 if randf() < 0.5 else -1.0)
		else:
			act("sniff")
	elif _loafed:
		act("blink" if r < 0.8 else "yawn")
	else:
		if r < 0.32:
			act("sniff")
		elif r < 0.52:
			act("blink")
		elif r < 0.68:
			act("tilt", 1.0 if randf() < 0.5 else -1.0)
		elif r < 0.8:
			act("yawn")
		elif r < 0.9:
			act("stretch")
		else:
			act("shake")


## 0..1 how far into a hiss the face is (mouth open, ears back)
func hiss_w() -> float:
	return _env(0.07, 0.28) if _on("hiss") else 0.0


func startle_gain() -> float:
	return 1.0 if _st_age < 3.0 else 0.0


func _win(a: float, b: float) -> float:
	# a bump between a and b of the act's length
	var u := _act_t / maxf(_act_dur, 0.001)
	return smoothstep(a - 0.1, a + 0.06, u) * (1.0 - smoothstep(b, b + 0.2, u))


# ------------------------------------------------------------------ after everything is posed

func post(dt: float) -> void:
	var gb: Basis = rig.global_transform.basis.orthonormalized()
	var air: float = rig._air_w
	var hunt: float = maxf(rig.crouch, rig.charge)
	var yawn := _env(0.28, 0.3) if _on("yawn") else 0.0
	var gape := _win(0.3, 0.62) if _on("yawn") else 0.0
	var sniff := _env(0.15, 0.2) if _on("sniff") else 0.0
	var shake_h := _win(0.02, 0.5) if _on("shake") else 0.0
	var hs := hiss_w()
	var fa: CatFightAnim = rig.fight_anim
	var brist := maxf(_puff, fa.bristle)

	# ---------- breathing ----------
	# ~25 breaths a minute at rest, slower lying down, up to ~2.3 a second after a long sprint.
	# the wave runs back along the body: ribs first, then the flanks
	var ex := maxf(exertion, stop.breath)
	var hz := lerpf(0.42, 2.3, smoothstep(0.05, 1.0, ex)) * lerpf(1.0, 0.72, rig._loaf_s)
	if sniff > 0.0:
		hz = maxf(hz, 5.5)   # sniffing is a string of quick shallow breaths
	breath_hz = hz
	_br_ph = fposmod(_br_ph + hz * TAU * dt, TAU)
	var amp := lerpf(0.011, 0.034, ex) * lerpf(1.0, 1.5, rig._loaf_s) * (1.0 - 0.6 * sniff)
	var b0 := sin(_br_ph) * amp + yawn * 0.035
	rig.chest.scale = Vector3(1.0 + b0, 1.0 + b0 * 0.8, 1.0)
	# panting: only when really blown, mouth a little open
	var pant := smoothstep(0.78, 0.95, exertion) * (1.0 - smoothstep(4.0, 6.0, rig.speed_s))
	_mouth = LowPoly.damp(_mouth, maxf(maxf(gape, hs * 1.3), pant * (0.3 + 0.12 * sin(_br_ph))), 26.0 if hs > _mouth else 18.0, dt)

	# ---------- loose skin ----------
	# track how the hips are being thrown about (world), drive two springs with it
	var pw: Vector3 = rig.pelvis.global_position
	var lat := pw.dot(gb.x)
	if not _pinit:
		_pinit = true
		_py = pw.y
		_px = lat
	var vy := (pw.y - _py) / dt
	var vx := (lat - _px) / dt
	var ay := clampf((vy - _pvy) / dt, -70.0, 70.0)
	var ax := clampf((vx - _pvx) / dt, -30.0, 30.0)
	_py = pw.y
	_px = lat
	_pvy = vy
	_pvx = vx
	# jiggle: the loin sags a beat after the skeleton stops, then bounces back (7 hz, loose)
	_jig_v += (-ay * 0.6 - _jig * 1900.0 - _jig_v * 20.0) * dt
	_jig = clampf(_jig + _jig_v * dt, -0.012, 0.012)
	var jg := _jig / 0.1
	for k in rig.spine.size():
		var sp: MeshInstance3D = rig.spine[k]
		var bk := sin(_br_ph - 0.45 - k * 0.3) * amp * 1.5 + yawn * 0.03
		var jk := jg * (0.6 + 0.4 * k)
		var ridge := brist * 0.09
		sp.transform.basis = sp.transform.basis * Basis.from_scale(Vector3(1.0 + bk + jk * 0.5, 1.0 + bk * 0.5 - jk + ridge, 1.0))
	# the pouch: a pendulum under the last loin block. walking swings it side to side,
	# running swings it fore and aft, landings make it slap
	_pouch_v += (-ax * 40.0 - float(rig._roll_p) * 900.0 - _pouch_a * 200.0 - _pouch_v * 4.0) * dt
	_pouch_a = clampf(_pouch_a + _pouch_v * dt, -0.6, 0.6)
	var az := clampf(-float(rig._acc.z), -30.0, 30.0)
	_pouch_bv += (az * 6.0 - ay * 0.9 - _pouch_b * 300.0 - _pouch_bv * 7.0) * dt
	_pouch_b = clampf(_pouch_b + _pouch_bv * dt, -0.5, 0.5)
	if pouch and rig.spine.size() >= 3:
		var s1: Transform3D = rig.spine[1].transform
		var s2: Transform3D = rig.spine[2].transform
		var ob := s2.basis.orthonormalized()
		var hinge := s1.origin.lerp(s2.origin, 0.62) - ob.y * (0.04 * float(rig.S_.girth))
		var rb := ob * Basis(Vector3(0, 0, 1), _pouch_a) * Basis(Vector3(1, 0, 0), _pouch_b)
		var hang := 1.0 - jg * 1.2 - rig._sit_h * 0.35 - rig._loaf_s * 0.5
		pouch.transform = Transform3D(rb * Basis.from_scale(_pouch_s * Vector3(1.0, hang, 1.0)), hinge - rb.y * (_pouch_s.y * 0.5 * hang))

	# ---------- head: how it is turning (drives whiskers + ear tips) ----------
	var hq: Quaternion = rig.head.global_transform.basis.orthonormalized().get_rotation_quaternion()
	if not _hq_init:
		_hq_init = true
		_hq = hq
	var dq := _hq.inverse() * hq
	_hq = hq
	var hav := Vector3.ZERO
	if absf(dq.w) < 0.999999:
		hav = dq.get_axis() * dq.get_angle() / dt
		if dq.get_angle() > PI:
			hav = Vector3.ZERO
	hav = hav.limit_length(25.0)

	# ---------- head lock on prey ----------
	_track_prey(dt, gb)

	# ---------- head acts ----------
	var hp := 0.0   # extra pitch (+ = up)
	var hy := 0.0
	var hr := 0.0
	var np_ := 0.0  # neck pitch
	if sniff > 0.0:
		# nose out and down a touch, bobbing with each sniff
		np_ -= 0.16 * sniff
		hp += (0.1 + 0.035 * sin(_act_t * 34.0)) * sniff
		hy += 0.12 * sin(_act_t * 3.1) * sniff
	if _on("tilt"):
		hr += 0.42 * _act_arg * _env(0.16, 0.25)
	if yawn > 0.0:
		np_ += 0.18 * yawn
		hp += 0.34 * gape + 0.08 * yawn
		hr += 0.1 * gape
	if shake_h > 0.0:
		hr += 0.6 * sin(_act_t * 62.0) * shake_h
		hy += 0.12 * sin(_act_t * 62.0 + 1.2) * shake_h
	if _on("stretch"):
		hp += 0.2 * auto_stretch
	if hs > 0.0:
		# hiss: head drawn back low between the shoulders, chin up to bare the teeth at it
		np_ += 0.14 * hs
		hp += 0.2 * hs + 0.025 * sin(_act_t * 41.0) * hs
	# startled: the head pulls back and down between the shoulders
	var fl := smoothstep(0.0, 0.05, _st_age) * exp(-_st_age * 3.0) * startle_gain()
	np_ += 0.22 * fl
	hp -= 0.12 * fl
	np_ += stop.neck_p
	hp += stop.head_p
	hy += stop.head_y
	hr += stop.head_r
	rig.neck.rotation.y += stop.neck_y
	# threat pose: the body turns side on, the head stays square on the threat
	var side_on: float = -float(rig._tyaw) * rig.fight_anim.threat * 0.65
	rig.neck.rotation.y += side_on * 0.55
	rig.head.rotation.y += side_on * 0.45
	rig.neck.rotation.x += np_ + _lock_pitch * 0.4 * _lock_w
	rig.neck.rotation.y += _lock_yaw * 0.45 * _lock_w
	rig.head.rotation.x += hp + _lock_pitch * 0.6 * _lock_w
	rig.head.rotation.y += hy + _lock_yaw * 0.55 * _lock_w
	rig.head.rotation.z += hr

	# ---------- jaw ----------
	if rig.chin:
		rig.chin.position = _chin_p + Vector3(0, -0.014, 0.001) * _mouth
		rig.chin.rotation.x = -0.5 * _mouth
	for fg in fangs:
		fg.visible = _mouth > 0.3
	if mouth:
		mouth.visible = _mouth > 0.08
		# (wide open it drops below the muzzle block, where it can be seen)
		mouth.position = Vector3(0, -0.027 - 0.0085 * _mouth, -0.036 - 0.004 * _mouth)
		mouth.scale = Vector3(0.018 + 0.003 * _mouth, 0.003 + 0.0125 * _mouth, 0.02 + 0.003 * _mouth)

	# ---------- ears ----------
	# flat and out to the side when scared or mid yawn; the tips flop on impacts and shakes
	var flat := maxf(maxf(smoothstep(0.2, 0.7, startle), gape * 0.7), shake_h * 0.5)
	var sat: float = rig._sit_s * (1.0 - rig._loaf_s * 0.6)
	for i in rig.ears.size():
		var side := -1.0 if i == 0 else 1.0
		var drive := -hav.z * side * 0.9 - ay * 0.12 + hav.x * 0.3
		_ear_wv[i] += (drive * 14.0 - _ear_w[i] * 900.0 - _ear_wv[i] * 16.0) * dt
		_ear_w[i] = clampf(_ear_w[i] + _ear_wv[i] * dt, -0.5, 0.5)
		var e: Node3D = rig.ears[i]
		e.rotation.x += flat * 0.55 + _ear_w[i] * 0.4
		e.rotation.z += side * (-0.75 * flat + _ear_w[i])
		# sat watching the world: each ear works on its own, in small quick turns
		var scan := sin(rig._t * 0.83 + i * 2.6) + 0.6 * sin(rig._t * 2.1 + i * 4.0)
		e.rotation.y += sat * (1.0 - flat) * 0.2 * signf(scan) * smoothstep(0.5, 0.9, absf(scan)) + _lock_yaw * 0.25 * _lock_w
		# fights: pinned flat back on the head when it means it, else turning in quick jerks
		# toward the threat and away (each ear on its own)
		var pin := maxf(fa.ear_pin, hs) * (1.0 - flat * 0.5)
		e.rotation.x += pin * 1.05
		e.rotation.z += side * -0.22 * pin
		e.rotation.y += side * 0.35 * pin
		if fa.swivel > 0.01:
			var sw := sin(rig._t * 1.9 + i * 2.3) + 0.55 * sin(rig._t * 4.7 + i * 1.1)
			e.rotation.y += fa.swivel * (0.42 * signf(sw) * smoothstep(0.45, 0.85, absf(sw)) - side * 0.12)
			e.rotation.x += fa.swivel * 0.12

	# ---------- whiskers ----------
	var fwd := maxf(maxf(hunt, sniff), maxf(gape, _lock_w * 0.7))
	if rig.is_swatting() or rig.claw_on:
		fwd = 1.0
	var back := maxf(maxf(rig.gait.gallop * 0.8, smoothstep(0.2, 0.7, startle)), maxf(rig._loaf_s * 0.4, rig.groom * 0.5))
	back = maxf(back, maxf(hs * 1.2, fa.ear_pin * 0.6))
	_wh = LowPoly.damp(_wh, clampf(fwd - back, -1.0, 1.0), 9.0, dt)
	_wh_qv += (-hav.y * 20.0 - _wh_q * 1400.0 - _wh_qv * 14.0) * dt
	_wh_q = clampf(_wh_q + _wh_qv * dt, -0.3, 0.3)
	var quiver := sniff * 0.07 * sin(_act_t * 34.0 + 0.7) + hunt * 0.02 * sin(rig._t * 23.0)
	for k in rig.whiskers.size():
		var wd: Array = rig.whiskers[k]
		var wn: MeshInstance3D = wd[0]
		var base: Transform3D = wd[1]
		var root: Vector3 = wd[2]
		var ws: float = wd[3]
		var row := float(k % 3)
		var fan := _wh * (0.55 if _wh > 0.0 else 0.4) + quiver * (1.0 + 0.3 * row) + air * -0.1
		var rot := Basis(Vector3.UP, ws * (fan + _wh_q * (0.7 + 0.2 * row))) * Basis(Vector3(0, 0, 1), ws * (-0.18 * maxf(_wh, 0.0) + 0.12 * maxf(-_wh, 0.0) + (row - 1.0) * 0.1 * _wh))
		wn.transform = Transform3D(rot * base.basis, root + rot * (base.origin - root))

	# ---------- eyes ----------
	# pupils: slits when calm, wide when hunting, playing or scared
	var want_p := maxf(maxf(rig.charge, rig.crouch * 0.65), maxf(smoothstep(0.1, 0.5, startle), _lock_w * 0.8))
	if rig.is_swatting():
		want_p = 1.0
	want_p = maxf(want_p, maxf(air * 0.5, maxf(hs, rig.fight * 0.7)))
	_pupil = LowPoly.damp(_pupil, clampf(want_p - rig._loaf_s * 0.3, 0.0, 1.0), 5.0 if want_p > _pupil else 1.5, dt)
	# the eyes go first, the head catches up
	var lead := clampf((float(rig._glance_to.x) - float(rig._glance.x)) * 0.006 + _lock_yaw * 0.002 * (1.0 - _lock_w), -0.0045, 0.0045)
	# slow blink: lids drift shut, hold, drift open
	var sb := 0.0
	if _on("blink"):
		sb = _env(0.35, 0.35)
	_blink = LowPoly.damp(_blink, maxf(sb, maxf(gape, shake_h)), 14.0, dt)
	var squint := smoothstep(0.75, 1.0, exertion) * 0.2 + hs * 0.35
	var wide := 1.0 + 0.22 * smoothstep(0.2, 0.6, startle) * (1.0 - _blink)
	for i in rig.eyes.size():
		var e: Node3D = rig.eyes[i]
		e.scale.y = minf(e.scale.y, maxf(1.0 - _blink * 0.93 - squint, 0.07)) * wide
		if i < _pupil_s.size():
			var p: Node3D = e.get_child(1)
			var ps: Vector3 = _pupil_s[i]
			p.scale = Vector3(lerpf(ps.x, ps.x * 3.1, _pupil), ps.y, ps.z)
			p.position = (_pupil_p[i] as Vector3) + Vector3(-lead, 0, 0)

	# ---------- fur standing up (scared, fighting) ----------
	_pose_hackles(brist)
	# ---------- tail: puffed up (bottle brush) when scared or fighting ----------
	if brist > 0.01:
		var n: int = rig.tail_segs.size()
		for i in n:
			var g := 1.0 + brist * (0.75 + 0.75 * sin(PI * float(i) / n))
			var ts: MeshInstance3D = rig.tail_segs[i]
			ts.transform.basis = ts.transform.basis * Basis.from_scale(Vector3(g, 1.0, g))
			(rig.tail_joints[i] as MeshInstance3D).scale = (_tj_s[i] as Vector3) * g
		_puffed = true
	elif _puffed:
		_puffed = false
		for i in rig.tail_joints.size():
			(rig.tail_joints[i] as MeshInstance3D).scale = _tj_s[i]


## watching prey: when something huntable is near and in front, the head locks onto it and
## follows it exactly, the way a cat at a window tracks a bird
func _track_prey(dt: float, gb: Basis) -> void:
	_lock_t -= dt
	if _lock_t < 0.0 and rig.is_inside_tree():
		_lock_t = 0.3
		_lock_node = null
		var best := 4.5
		var me: Vector3 = rig.head.global_position
		for n in rig.get_tree().get_nodes_in_group("prey"):
			if not (n is Node3D) or n.get("caught") == true:
				continue
			var rel: Vector3 = gb.inverse() * ((n as Node3D).global_position - me)
			var d := rel.length()
			if d < best and d > 0.12 and rel.z < 0.3 * d:
				best = d
				_lock_node = n
	var want := 0.0
	if _lock_node and is_instance_valid(_lock_node) and _lock_node.is_inside_tree():
		var calm: bool = rig.on_floor and rig.speed_s < 1.2 and rig.climb < 0.1 and rig.groom < 0.1
		if calm:
			want = 1.0
			# where the head would have to turn, on top of where the rig already put it
			var hb: Basis = rig.head.global_transform.basis.orthonormalized()
			var to: Vector3 = hb.inverse() * (_lock_node.global_position - rig.head.global_position)
			var ty := clampf(atan2(-to.x, -to.z), -1.1, 1.1)
			var tp := clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.7, 0.7)
			_lock_yaw = LowPoly.damp(_lock_yaw, ty, 14.0, dt)
			_lock_pitch = LowPoly.damp(_lock_pitch, tp, 14.0, dt)
	_lock_w = LowPoly.damp(_lock_w, want, 6.0 if want > _lock_w else 3.0, dt)
	if _lock_w < 0.01 and want == 0.0:
		_lock_yaw = 0.0
		_lock_pitch = 0.0


# ------------------------------------------------------------------ hackles

## the fur along the back that stands up: a ridge of shards down the spine and two splayed rows
## either side of it, flat (hidden) until the cat bristles
func _build_hackles(gi: float, ln: float) -> void:
	var col: Color = rig.fur_dark if rig.pattern != "solid" else rig.fur
	var mesh := LowPoly.cone(3)
	# [kind, index, local point on top of that block, splay (rad, + = out to the right), size]
	var spots := []
	for z in [-0.06, -0.025, 0.01, 0.045]:
		spots.append(["c", 0, Vector3(0, 0.057 * gi, z * ln), 0.0, 0.85 + 0.3 * (z + 0.06) / 0.1])
	for k in rig.spine.size():
		for z in [-0.25, 0.25]:
			spots.append(["s", k, Vector3(0, 0.47, z), 0.0, 1.2])
			for sd in [-1.0, 1.0]:
				spots.append(["s", k, Vector3(sd * 0.3, 0.42, z + 0.1), sd * 0.7, 0.75])
	for z in [-0.045, -0.01, 0.025, 0.06]:
		spots.append(["p", 0, Vector3(0, 0.06 * gi, z * ln), 0.0, 1.05 - 0.4 * (z + 0.045) / 0.1])
	for sd in [-1.0, 1.0]:
		for z in [-0.05, 0.0]:
			spots.append(["c", 0, Vector3(sd * 0.03 * gi, 0.05 * gi, z * ln), sd * 0.7, 0.6])
	for sp in spots:
		var mi := LowPoly.part(rig.pivot, mesh, col, Vector3.ZERO, Vector3.ONE * 0.001)
		rig._style_mat(mi)
		mi.visible = false
		hackles.append(mi)
		_hk.append(sp)


func _pose_hackles(b: float) -> void:
	var on := b > 0.02
	for i in hackles.size():
		var mi := hackles[i]
		mi.visible = on
		if not on:
			continue
		var sp: Array = _hk[i]
		var xf: Transform3D
		match str(sp[0]):
			"c": xf = rig.chest.transform
			"p": xf = rig.pelvis.transform
			_: xf = (rig.spine[int(sp[1])] as Node3D).transform
		var at: Vector3 = xf * (sp[2] as Vector3)
		var bs := xf.basis.orthonormalized()
		# each shard leans back along the body when it's half up, stands straight when it's full
		var flick := 0.06 * sin(rig._t * 9.0 + i * 1.7) * b
		var rb := bs * Basis(Vector3(0, 0, 1), -float(sp[3])) * Basis(Vector3(1, 0, 0), lerpf(1.1, 0.25, b) + flick)
		var len := 0.034 * float(sp[4]) * smoothstep(0.0, 1.0, b)
		var w := 0.011 * float(sp[4])
		mi.transform = Transform3D(rb * Basis.from_scale(Vector3(w, maxf(len, 0.001), w)), at + rb.y * (len * 0.5 - 0.004))
