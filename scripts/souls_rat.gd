class_name SoulsRat
extends CharacterBody3D
## arena rat, souls style. it can ONLY bite what is in front of its face: a short telegraphed
## wind up (rears back, jaw opens), a lunge, then a recovery where it can't turn. it turns much
## slower than the cat can circle it, so the play is to bait the bite, dodge through it (i-frames,
## see CatPlayer.is_invulnerable()) or round it, and swat it from behind (double damage + stagger).
## a pounce that lands on it is a heavy hit. too big to carry.
##
## body + gait are built to rat proportions (blocky, like the cat): a hunched lumbar back, short
## forelegs with the elbow back, long plantigrade hind feet with the knee forward, a low head,
## a long thick tail carried low. it trots on diagonal pairs (the gait rats use from a fast walk
## up), its stride solved from its own speed so planted feet don't slide, and steps on the spot
## when it turns. scale 1 = a big sewer rat (~0.3 m body), 1.6 = the arena's brute.

signal killed(rat: SoulsRat)

enum { IDLE, CHASE, WINDUP, LUNGE, RECOVER, STAGGER, DEAD }

var s := 1.0                  # size scale
var kind := "rat"
var caught := false           # prey duck type (never carried)
var hp := 4.0
var max_hp := 4.0
var poise := 2.0              # hits before a front hit staggers it
var state := IDLE
var st_t := 0.0
var target: Node3D            # the player
var yaw := 0.0
var aggro := 9.0
var fur := Color(0.44, 0.39, 0.35)
var fur_dark := Color(0.3, 0.27, 0.24)
var skin := Color(0.82, 0.58, 0.58)

# tuning (scaled in _ready)
var turn_rate := 3.0          # rad/s. the cat circles a rat at ~0.6 m at 5+ rad/s at a trot
var run_speed := 2.2
var reach := 0.42             # bite reach from the body centre, along its facing
var bite_w := 0.16            # half width of the bite in front
var bite_dmg := 22.0
var windup_t := 0.5
var lunge_t := 0.2
var recover_t := 0.7
var _bit := false
var _poise := 0.0
var _stagger_t := 0.55
var hits := 0                 # for tests
var bites := 0
var _hit_flash := 0.0
# held down under a cat's fore paws (two paw grip): can't move or bite, wriggles free after break_t
var held_by: Node3D = null
var hold_point := Vector3.ZERO
var held_t := 0.0
var break_t := 1.6

# rig
var torso: Node3D
var head: Node3D
var jaw: Node3D
var _ears: Array[Node3D] = []
var _legs: Array = []         # {up, lo, foot, root(Vector3 torso local), front, side, phase_off, pos(world)}
var _tail: Array[MeshInstance3D] = []
var _tail_y := PackedFloat32Array()
var _phase := 0.0
var _yaw_rate := 0.0
var _speed := 0.0
var _pitch := 0.0
var _rear := 0.0              # wind up: back on the haunches
var _ext := 0.0               # lunge: stretched out
var _roll := 0.0
var _death := 0.0
var _mats: Array[MeshInstance3D] = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("prey")
	add_to_group("enemy")
	_rng.randomize()
	max_hp = 4.0 if s < 1.3 else 11.0
	hp = max_hp
	poise = 2.0 if s < 1.3 else 4.0
	turn_rate = 3.0 / sqrt(s)
	run_speed = 2.2 * sqrt(s)
	reach = 0.42 * s
	bite_w = 0.16 * s
	bite_dmg = 22.0 if s < 1.3 else 38.0
	windup_t = 0.5 if s < 1.3 else 0.8
	recover_t = 0.7 if s < 1.3 else 1.0
	floor_snap_length = 0.05
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.11, 0.11, 0.32) * s
	cs.shape = b
	cs.position = Vector3(0, 0.065 * s, 0.01 * s)
	add_child(cs)
	_build()
	rotation.y = yaw


func _part(parent: Node, c: Color, pos: Vector3, scl: Vector3, rot := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var m := LowPoly.part(parent, LowPoly.box(), c, pos * s, scl * s, rot, emission)
	_mats.append(m)
	return m


func _build() -> void:
	torso = Node3D.new()
	torso.position = Vector3(0, 0.1 * s, 0)
	add_child(torso)
	# hindquarters are the big part of a rat: a high rounded lumbar hump over long hind legs
	_part(torso, fur, Vector3(0, 0.012, 0.075), Vector3(0.105, 0.095, 0.13), Vector3(-0.12, 0, 0))
	_part(torso, fur_dark, Vector3(0, 0.052, 0.07), Vector3(0.07, 0.03, 0.1), Vector3(-0.14, 0, 0))
	_part(torso, fur, Vector3(0, -0.003, -0.035), Vector3(0.088, 0.078, 0.11), Vector3(0.1, 0, 0))
	_part(torso, Color(0.5, 0.45, 0.42), Vector3(0, -0.035, 0.0), Vector3(0.07, 0.025, 0.17))   # pale belly
	# neck + head: low, wedge snout, eyes high and to the sides
	head = Node3D.new()
	head.position = Vector3(0, 0.0, -0.09) * s
	torso.add_child(head)
	_part(head, fur, Vector3(0, 0.005, -0.03), Vector3(0.066, 0.06, 0.065))
	_part(head, fur, Vector3(0, -0.004, -0.075), Vector3(0.046, 0.04, 0.05), Vector3(0.12, 0, 0))
	_part(head, fur_dark, Vector3(0, -0.006, -0.103), Vector3(0.03, 0.026, 0.02))
	_part(head, skin, Vector3(0, 0.0, -0.115), Vector3(0.016, 0.013, 0.01))
	for sd in [-1.0, 1.0]:
		_part(head, Color(0.85, 0.08, 0.04), Vector3(sd * 0.031, 0.018, -0.055), Vector3(0.008, 0.01, 0.014), Vector3.ZERO, 2.2)
		var ear := Node3D.new()
		ear.position = Vector3(sd * 0.026, 0.035, -0.02) * s
		head.add_child(ear)
		_part(ear, skin, Vector3(sd * 0.008, 0.014, 0), Vector3(0.026, 0.03, 0.006), Vector3(0, sd * 0.4, sd * -0.3))
		_ears.append(ear)
		# whiskers
		_part(head, Color(0.75, 0.72, 0.68), Vector3(sd * 0.04, -0.004, -0.098), Vector3(0.06, 0.0015, 0.0015), Vector3(0, sd * 0.25, 0))
	jaw = Node3D.new()
	jaw.position = Vector3(0, -0.02, -0.06) * s
	head.add_child(jaw)
	_part(jaw, fur_dark, Vector3(0, -0.006, -0.025), Vector3(0.036, 0.014, 0.045))
	_part(jaw, Color(0.9, 0.78, 0.35), Vector3(0, 0.004, -0.046), Vector3(0.012, 0.014, 0.004))
	_part(head, Color(0.9, 0.78, 0.35), Vector3(0, -0.02, -0.108), Vector3(0.012, 0.014, 0.004))   # top incisors
	# legs: fore = short, elbow back, small paw. hind = knee forward, long flat foot
	var defs := [
		{"root": Vector3(-0.034, -0.03, -0.055), "front": true, "side": -1.0, "off": 0.0},
		{"root": Vector3(0.034, -0.03, -0.055), "front": true, "side": 1.0, "off": 0.5},
		{"root": Vector3(-0.042, -0.02, 0.09), "front": false, "side": -1.0, "off": 0.5},
		{"root": Vector3(0.042, -0.02, 0.09), "front": false, "side": 1.0, "off": 0.0},
	]
	for d in defs:
		var leg: Dictionary = d.duplicate()
		var w: float = 0.026 if d.front else 0.036
		leg.up = _part(self, fur, Vector3.ZERO, Vector3(w, 1, w))
		leg.lo = _part(self, fur_dark if d.front else fur, Vector3.ZERO, Vector3(w * 0.7, 1, w * 0.7))
		leg.foot = _part(self, skin, Vector3.ZERO, Vector3(0.02, 0.008, 0.03 if d.front else 0.055))
		leg.w = w
		leg.pos = global_position
		leg.init = false
		_legs.append(leg)
	for i in 8:
		var r := 0.013 * (1.0 - i / 9.0) + 0.003
		var seg := LowPoly.part(self, LowPoly.box(), skin.darkened(0.12), Vector3.ZERO, Vector3.ONE)
		seg.set_meta("r", r * s)
		_tail.append(seg)
		_mats.append(seg)
	_tail_y.resize(8)


# ---------------------------------------------------------------- combat hooks

## swatted (the cat's swat calls stun on prey)
func stun(_t: float) -> void:
	if target == null:
		return
	take_hit(1.0, target.global_position)


## a pounce landed on it
func pin_hit(by: Node3D) -> void:
	take_hit(2.5, by.global_position, true)


func pinned() -> void:
	pass


func released() -> void:
	pass


func behind(from: Vector3) -> bool:
	var to := from - global_position
	to.y = 0.0
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	return to.normalized().dot(fwd) < -0.3


## poise_mul: how much this hit counts toward a stagger (rakes 0.5, grip squeezes 0)
func take_hit(dmg: float, from: Vector3, heavy := false, poise_mul := 1.0) -> void:
	if state == DEAD:
		return
	var back := behind(from)
	if back:
		dmg *= 2.0
	hp -= dmg
	hits += 1
	_hit_flash = 1.0
	_poise += (2.0 if (back or heavy) else 1.0) * poise_mul
	var away := global_position - from
	away.y = 0.0
	if held_by == null:
		velocity += away.normalized() * (1.4 if heavy else 0.7)
	if target and target.has_method("_event"):
		target.call("_event", ("backstab! " if back else "hit! ") + "rat %d/%d" % [maxi(ceili(hp), 0), int(max_hp)])
	if hp <= 0.0:
		_die()
	elif held_by != null:
		pass     # it's pinned already
	elif _poise >= poise or ((back or heavy) and poise_mul > 0.0):
		_poise = 0.0
		state = STAGGER
		st_t = 0.0
		_stagger_t = 0.55 if not heavy else 0.9


## pinned under both fore paws of a cat (CatCombat grip). bigger rats wriggle out sooner
func grab(by: Node3D) -> void:
	if state == DEAD:
		return
	held_by = by
	held_t = 0.0
	hold_point = global_position
	break_t = 1.6 / s
	state = STAGGER
	st_t = 0.0


func ungrab(by: Node3D) -> void:
	if held_by == by:
		_break_free(false)


func _break_free(struggled: bool) -> void:
	held_by = null
	state = STAGGER
	st_t = 0.0
	_stagger_t = 0.25 if struggled else 0.5
	_poise = 0.0
	if struggled and is_instance_valid(target):
		var away := global_position - target.global_position
		away.y = 0.0
		velocity += away.normalized() * 1.2


func _die() -> void:
	held_by = null
	state = DEAD
	st_t = 0.0
	remove_from_group("prey")
	remove_from_group("enemy")
	collision_layer = 0
	killed.emit(self)


func alive() -> bool:
	return state != DEAD


## where a lock on (cat_lock_on.gd) aims: the middle of the body
func lock_point() -> Vector3:
	return global_position + Vector3.UP * 0.1 * s


# ---------------------------------------------------------------- brain

func _physics_process(dt: float) -> void:
	_t += dt
	st_t += dt
	_hit_flash = maxf(_hit_flash - dt * 4.0, 0.0)
	_poise = maxf(_poise - dt * 0.25, 0.0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var to := Vector3.ZERO
	var dist := 99.0
	var ang := 0.0
	if is_instance_valid(target):
		to = target.global_position - global_position
		to.y = 0.0
		dist = to.length()
		ang = fwd.signed_angle_to(to, Vector3.UP) if dist > 0.01 else 0.0
	if held_by != null:
		if not is_instance_valid(held_by) or state == DEAD:
			held_by = null
		else:
			held_t += dt
			if held_t >= break_t:
				_break_free(true)
				if target and target.has_method("_event"):
					target.call("_event", "the rat wriggles free!")
	if held_by != null:
		# pinned: dragged to where the paws hold it, legs scrabbling (the stagger anim)
		state = STAGGER
		st_t = 0.0
		var pull := hold_point - global_position
		pull.y = 0.0
		velocity.x = pull.x * 10.0
		velocity.z = pull.z * 10.0
		velocity.y = -0.1 if is_on_floor() else velocity.y - 9.8 * dt
		move_and_slide()
		_speed = LowPoly.damp(_speed, 0.6, 12.0, dt)
		return
	# a cat that ends up on its back gets bucked off (no standing on the rats)
	if is_instance_valid(target) and state != DEAD:
		var rel := target.global_position - global_position
		var sd := Vector3(cos(yaw), 0, -sin(yaw))
		if rel.y > 0.07 * s and rel.y < 0.25 * s and Vector2(rel.x, rel.z).length() < 0.2 * s and target is CharacterBody3D:
			(target as CharacterBody3D).velocity = sd * (1.0 if rel.dot(sd) >= 0.0 else -1.0) * 2.2 + Vector3.UP * 1.6
			if "mantling" in target:
				target.set("mantling", false)
	var want_v := Vector3.ZERO
	var prev_yaw := yaw
	var player_down: bool = is_instance_valid(target) and "health" in target and target.health.dead
	match state:
		IDLE:
			if dist < aggro and not player_down:
				state = CHASE
				st_t = 0.0
		CHASE:
			if player_down:
				state = IDLE
			yaw += clampf(ang, -turn_rate * dt, turn_rate * dt)
			# like every quadruped it runs where it faces: way off and it slows to turn
			var face := clampf(1.0 - absf(ang) / 1.2, 0.0, 1.0)
			var spd := run_speed * face * smoothstep(0.4 * s, 0.9 * s, dist)
			want_v = fwd * spd
			if dist < reach + 0.28 * s and absf(ang) < 0.45 and st_t > 0.3:
				state = WINDUP
				st_t = 0.0
				_bit = false
		WINDUP:
			# tracks you for most of the wind up, then it's committed
			var track := 1.4 if st_t < windup_t * 0.6 else 0.0
			yaw += clampf(ang, -track * dt, track * dt)
			if st_t >= windup_t:
				state = LUNGE
				st_t = 0.0
		LUNGE:
			want_v = fwd * 3.2 * sqrt(s) * (1.0 - st_t / lunge_t * 0.5)
			if not _bit and st_t > lunge_t * 0.35:
				_bite(fwd)
			if st_t >= lunge_t:
				state = RECOVER
				st_t = 0.0
		RECOVER:
			if st_t >= recover_t:
				state = CHASE
				st_t = 0.0
		STAGGER:
			if st_t >= _stagger_t:
				state = CHASE
				st_t = 0.0
		DEAD:
			if st_t > 8.0:
				position.y -= dt * 0.05
				if st_t > 11.0:
					queue_free()
	yaw = wrapf(yaw, -PI, PI)
	rotation.y = yaw
	_yaw_rate = LowPoly.damp(_yaw_rate, wrapf(yaw - prev_yaw, -PI, PI) / dt, 10.0, dt)
	# keep apart from the other rats
	for o in get_tree().get_nodes_in_group("enemy"):
		if o != self and o is Node3D:
			var d: Vector3 = global_position - (o as Node3D).global_position
			d.y = 0.0
			var l := d.length()
			if l < 0.42 * s and l > 0.001:
				want_v += d / l * (0.42 * s - l) * 6.0
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(want_v, (14.0 if state != STAGGER else 4.0) * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= 9.8 * dt
	move_and_slide()
	_speed = LowPoly.damp(_speed, Vector2(velocity.x, velocity.z).length(), 12.0, dt)


## the snap: only lands on what's in front of the snout, about one head length out
func _bite(fwd: Vector3) -> void:
	_bit = true
	bites += 1
	if not is_instance_valid(target) or not target.has_method("is_invulnerable"):
		return
	var d: Vector3 = target.global_position - global_position
	var along := d.dot(fwd)
	var lat := (d - fwd * along)
	lat.y = 0.0
	if along > 0.0 and along < reach + 0.09 and lat.length() < bite_w + 0.085 and absf(d.y) < 0.3 * s:
		target.health.damage(bite_dmg, global_position, 2.0 + s)


# ---------------------------------------------------------------- animation

func _process(dt: float) -> void:
	if dt <= 0.0 or torso == null:
		return
	dt = minf(dt, 0.05)
	var dead := state == DEAD
	_death = move_toward(_death, 1.0 if dead else 0.0, dt * 3.0)
	# pose targets
	var rear_t := 0.0
	var ext_t := 0.0
	var jaw_t := 0.0
	var ear_t := 0.0
	match state:
		WINDUP:
			var k := clampf(st_t / (windup_t * 0.7), 0.0, 1.0)
			rear_t = smoothstep(0.0, 1.0, k)
			jaw_t = 0.25 + 0.75 * k
			ear_t = 1.0
		LUNGE:
			var k := st_t / lunge_t
			ext_t = 1.0
			jaw_t = 1.0 if k < 0.4 else 0.0     # snaps shut on the bite
			ear_t = 1.0
		RECOVER:
			ext_t = 0.35 * (1.0 - st_t / recover_t)
			jaw_t = 0.15 * (0.5 + 0.5 * sin(_t * 22.0))   # panting
		STAGGER:
			ear_t = 0.6
	_rear = LowPoly.damp(_rear, rear_t, 14.0, dt)
	_ext = LowPoly.damp(_ext, ext_t, 22.0, dt)
	jaw.rotation.x = LowPoly.damp(jaw.rotation.x, jaw_t * 0.75, 30.0, dt)
	for i in 2:
		var sd := -1.0 if i == 0 else 1.0
		_ears[i].rotation = Vector3(-ear_t * 0.7, 0, sd * ear_t * 0.5)

	# gait: diagonal trot. step frequency from speed (bigger rat = slower, longer strides),
	# stride = speed / frequency so the planted paws hold still on the ground
	var turn_v := absf(_yaw_rate) * 0.1 * s
	var v := maxf(_speed, turn_v) if not dead else 0.0
	var freq := (3.2 + 2.6 * minf(v, 2.5)) / sqrt(s)
	var moving := smoothstep(0.03, 0.15, v)
	_phase = fposmod(_phase + freq * dt * moving, 1.0)
	var stride := v / freq
	var duty := 0.6 - 0.12 * clampf(v / 2.0, 0.0, 1.0)

	# body: trot bounce twice per cycle, lumbar flex, rearing / lunging, stagger wobble
	var bounce := -absf(sin(_phase * TAU)) * 0.006 * s * moving
	var stg := 0.0
	if state == STAGGER:
		stg = sin(st_t * 30.0) * exp(-st_t * 4.0)
	_roll = LowPoly.damp(_roll, stg * 0.35 + _death * 1.45, 12.0 if not dead else 5.0, dt)
	_pitch = LowPoly.damp(_pitch, -0.08 * moving * clampf(v / 2.0, 0.0, 1.0), 8.0, dt)
	torso.position = Vector3(0, (0.1 + 0.03 * _rear - 0.01 * _ext - 0.035 * _death) * s + bounce, (0.03 * _rear - 0.06 * _ext) * s)
	torso.rotation = Vector3(_pitch + _rear * 0.42 - _ext * 0.12, clampf(-_yaw_rate * 0.05, -0.2, 0.2), _roll)
	head.rotation = Vector3(_rear * -0.25 + _ext * 0.2 + (sin(_t * 1.7) * 0.05 if state == IDLE else 0.0), stg * 0.4 + clampf(-_yaw_rate * 0.08, -0.3, 0.3), 0)
	head.position.z = (-0.09 - 0.03 * _ext) * s

	# legs (root space)
	var tx := torso.transform
	for leg in _legs:
		var front: bool = leg.front
		var u := fposmod(_phase + float(leg.off), 1.0)
		var root: Vector3 = tx * ((leg.root as Vector3) * s)
		var home := Vector3((leg.root as Vector3).x * s * 1.05, 0.0, (leg.root as Vector3).z * s + (-0.012 if front else 0.035) * s)
		var foot := home
		var lift := 0.0
		if moving > 0.01:
			if u < duty:
				foot.z += lerpf(-stride * 0.5, stride * 0.5, u / duty)
			else:
				var k := (u - duty) / (1.0 - duty)
				foot.z += lerpf(stride * 0.5, -stride * 0.5, smoothstep(0.0, 1.0, k))
				lift = sin(k * PI) * (0.022 if front else 0.03) * s * moving
		# rearing: forepaws come off the ground a little; lunging: they reach forward
		if front:
			foot.z -= (0.03 * _rear + 0.07 * _ext) * s
			lift += 0.03 * _rear * s
		else:
			foot.z += 0.02 * _ext * s
		foot.y = lift
		if _death > 0.0:
			foot = foot.lerp(root + Vector3((leg.side as float) * 0.04 * s, -0.03 * s, 0), _death)
		var lu := (0.052 if front else 0.066) * s
		var ll := (0.05 if front else 0.06) * s
		# fore: elbow points back. hind: knee forward, the long foot does the rest
		var ank := foot + (Vector3(0, 0.008, 0.0) if front else Vector3(0, 0.012, 0.03)) * s
		var hint := Vector3(0, 0, 1) if front else Vector3(0, 0, -1)
		var ik := LowPoly.ik2(root, ank, lu, ll, hint)
		var mid: Vector3 = ik[0]
		var end: Vector3 = ik[1]
		var w: float = leg.w
		var a := LowPoly.seg_xform(root, mid)
		(leg.up as MeshInstance3D).transform = Transform3D(a.basis * Basis.from_scale(Vector3(w * s, 1, w * s)), a.origin)
		var b := LowPoly.seg_xform(mid, end)
		(leg.lo as MeshInstance3D).transform = Transform3D(b.basis * Basis.from_scale(Vector3(w * 0.7 * s, 1, w * 0.7 * s)), b.origin)
		var fl := (0.03 if front else 0.055) * s
		# hind foot: heel on the ground in stance (plantigrade), peels up in swing
		var fp := foot + Vector3(0, 0.004 * s, -fl * 0.35 if front else -fl * 0.25)
		(leg.foot as MeshInstance3D).position = fp
		(leg.foot as MeshInstance3D).rotation = Vector3(-lift * 6.0 / s, 0, 0)

	# tail: thick at the root, carried low, swings opposite to turns and lags behind
	var base: Vector3 = tx * (Vector3(0, -0.005, 0.14) * s)
	var dir := (tx.basis * Vector3(0, -0.35, 1)).normalized()
	var p := base
	var seg_l := 0.04 * s
	for i in _tail.size():
		var target_y := clampf(_yaw_rate * 0.12, -0.5, 0.5) * (0.4 + i * 0.12) + sin(_t * 2.1 - i * 0.6) * 0.06 * (1.0 - _death)
		_tail_y[i] = LowPoly.damp(_tail_y[i], target_y, 10.0 - i * 0.8, dt)
		var d := (Basis(Vector3.UP, _tail_y[i]) * dir)
		# the tail lies on the ground further back
		var q := p + d * seg_l
		q.y = maxf(q.y, 0.006 * s)
		if i > 1:
			dir = (dir + Vector3(0, -0.12, 0)).normalized()
			dir.y = maxf(dir.y, -0.15)
		var r: float = _tail[i].get_meta("r")
		var x := LowPoly.seg_xform(q, p)
		_tail[i].transform = Transform3D(x.basis * Basis.from_scale(Vector3(r * 2.0, 1, r * 2.0)), x.origin)
		p = q

	# hit flash
	var fl_c := _hit_flash
	if fl_c > 0.01 or _was_flash:
		_was_flash = fl_c > 0.01
		for m in _mats:
			(m as GeometryInstance3D).material_overlay = _flash_mat if fl_c > 0.01 else null
		if fl_c > 0.01:
			_flash_mat.albedo_color = Color(1, 0.9, 0.8, fl_c * 0.35)


var _was_flash := false
var _flash_mat: StandardMaterial3D = _make_flash()


static func _make_flash() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 0.9, 0.8, 0.0)
	return m
