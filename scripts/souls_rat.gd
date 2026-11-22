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
## when it turns. scale 1 = a big sewer rat (~0.3 m body), 1.6 = the arena's brute, 2.2+ = the
## rat king (boss: darker, scarred, long combos with perilous tail sweeps and leaps).
##
## COMBOS (sekiro style, 2026-11-22): a bite is one step of a combo, a chain of strikes on a
## rhythm (COMBOS). each step = WINDUP (the tell) -> LUNGE (the strike) and the next step's tell
## starts straight after, so the hits come in a beat you can learn: snap.. snap, snap-swipe-snap,
## a delayed third bite that catches early presses. every strike shows a ParryCue above the head:
## a glint + closing ring (deflect it: dodge + swat, cat_parry.gd) or a red ! (perilous: a leap or
## a tail sweep, dodge it). deflects fill its POSTURE (bar under the cue); full = BROKEN, it
## slumps for a couple of seconds and the next swat is a finishing blow. the last hit of a combo
## deflected leaves it open a little longer.
##
## online (host authoritative): the host runs the brain, net_pack() -> snapshots, clients put
## the rat in puppet mode (net_puppet) and net_apply() them. the combo table is the same
## everywhere, so a puppet plays the same strikes on the same beat from (combo id, step, st_t) and
## each game resolves the hits on its own local cat (deflects included); a client's deflect fires
## `deflected` so the sync layer can hand the posture to the host (add_posture).

signal killed(rat: SoulsRat)
signal combo_started(id: String)
signal deflected(by: Node3D, posture_add: float)

enum { IDLE, CHASE, WINDUP, LUNGE, RECOVER, STAGGER, DEAD, BROKEN }

## each step: [tell (s, cue -> strike), kind, perilous]. step 0's tell is the rat's windup_t
## (bigger rats wind up longer), later ones x tempo. kinds: bite (snap in front), swipe (rears,
## forepaw sweep, wider), leap (long lunge from range, perilous), sweep (whips round, the tail
## hits all round it, perilous)
const COMBOS := {
	"snap": [[0.5, "bite", false]],
	"double": [[0.5, "bite", false], [0.3, "bite", false]],
	"triple": [[0.5, "bite", false], [0.28, "swipe", false], [0.28, "bite", false]],
	"delay": [[0.5, "bite", false], [0.26, "bite", false], [0.62, "bite", false]],
	"leap": [[0.6, "leap", true]],
	"snap_leap": [[0.5, "bite", false], [0.3, "swipe", false], [0.55, "leap", true]],
	"sweep": [[0.45, "bite", false], [0.3, "bite", false], [0.55, "sweep", true]],
	"frenzy": [[0.55, "swipe", false], [0.26, "bite", false], [0.26, "swipe", false], [0.45, "bite", false], [0.26, "bite", false]],
}
## per kind: [strike length (s), hit at (fraction of it), damage x, posture a deflect deals x]
const STRIKES := {
	"bite": [0.2, 0.35, 1.0, 1.0],
	"swipe": [0.2, 0.4, 0.8, 0.8],
	"leap": [0.38, 0.5, 1.3, 1.0],
	"sweep": [0.32, 0.45, 1.2, 1.0],
}
const POOL_SMALL := ["snap", "double", "double", "triple", "snap"]
const POOL_BRUTE := ["double", "triple", "delay", "sweep"]
const POOL_KING := ["triple", "delay", "sweep", "frenzy", "frenzy"]
const LEAPS_SMALL := ["leap"]
const LEAPS_BIG := ["snap_leap", "leap"]

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
# combos + posture
var combos: Array = []        # override the combo pool (tests: ["snap"] = the old single bite)
var leaps_on := true          # may open with a leap from range
var combo_id := ""
var step := 0
var strike := "bite"
var perilous := false
var tempo := 1.0
var posture_v := 0.0
var posture_max := 3.0
var broken_t := 2.0
var deathblows := 0
var deflected_n := 0          # tests
var combos_done := 0
var _posture_hold := 0.0
var _leap_cd := 1.5
var _open := 0.0              # extra recovery after a deflected last hit
var _defl := 0.0              # deflect recoil (anim)
var _spin := 0.0              # tail sweep spin (anim)
var cue: ParryCue
var net_puppet := false       # online client: the host runs the brain, net_apply() drives this one
var king := false


func _ready() -> void:
	add_to_group("prey")
	add_to_group("enemy")
	_rng.randomize()
	king = s >= 2.0
	max_hp = 4.0 if s < 1.3 else (11.0 if not king else 24.0)
	hp = max_hp
	poise = 2.0 if s < 1.3 else (4.0 if not king else 7.0)
	posture_max = 3.0 if s < 1.3 else (5.0 if not king else 8.0)
	broken_t = 2.0 if s < 1.3 else 2.6
	tempo = 1.0 if s < 1.3 else (1.12 if not king else 1.05)
	if king:
		fur = Color(0.24, 0.21, 0.2)
		fur_dark = Color(0.14, 0.12, 0.12)
		skin = Color(0.62, 0.42, 0.42)
	turn_rate = 3.0 / sqrt(s)
	run_speed = 2.2 * sqrt(s)
	reach = 0.42 * s
	bite_w = 0.16 * s
	bite_dmg = 22.0 if s < 1.3 else (38.0 if not king else 34.0)
	windup_t = 0.5 if s < 1.3 else (0.8 if not king else 0.75)
	recover_t = 0.7 if s < 1.3 else 1.0
	_rng.seed = hash(str(position)) if not net_puppet else 0
	floor_snap_length = 0.05
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.11, 0.11, 0.32) * s
	cs.shape = b
	cs.position = Vector3(0, 0.065 * s, 0.01 * s)
	add_child(cs)
	_build()
	rotation.y = yaw
	cue = ParryCue.new()
	cue.scale_k = sqrt(s)
	cue.position = Vector3(0, 0.27 * s + 0.05, -0.04 * s)
	add_child(cue)


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
	if s >= 2.0:
		# the rat king: a pale scar over the left eye, a torn right ear, a ridge of hackles
		_part(head, Color(0.75, 0.6, 0.55), Vector3(-0.031, 0.026, -0.05), Vector3(0.004, 0.03, 0.022), Vector3(0, 0, 0.5))
		_part(torso, fur_dark, Vector3(0, 0.07, 0.0), Vector3(0.02, 0.025, 0.2), Vector3(-0.1, 0, 0))
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
	take_hit(1.0, target.global_position)   # (online: target is always this game's own cat)


## a pounce landed on it
func pin_hit(by: Node3D) -> void:
	take_hit(2.5, by.global_position, true)


## online: a rat someone else's game runs shows the hit at once, the owner applies it (world_sync.gd)
func _net_forward(args: Array) -> bool:
	if NetWorld.forward(self, "take_hit", args):
		_hit_flash = 1.0
		return true
	return false


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
	if _net_forward([dmg, from, heavy, poise_mul]):
		return
	var back := behind(from)
	if state == BROKEN and poise_mul > 0.0:
		# posture broken: this one is the finishing blow
		deathblows += 1
		dmg = hp if s < 1.3 else maxf(max_hp * 0.4, 4.0)
		heavy = true
		back = false
		posture_v = 0.0
		cue.broken = false
		SlashFx.sparks(self, global_position + Vector3.UP * 0.12 * s, Vector3.UP, true, 30)
		if target and target.has_method("_event"):
			target.call("_event", "finishing blow!")
	elif back:
		dmg *= 2.0
	# hits wear its posture down a little too (deflects do the real work)
	if state != BROKEN:
		posture_v = minf(posture_v + 0.25 * poise_mul, posture_max - 0.01)
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
		_end_combo()
		state = STAGGER
		st_t = 0.0
		_stagger_t = 0.55 if not heavy else 0.9


## pinned under both fore paws of a cat (CatCombat grip). bigger rats wriggle out sooner
func grab(by: Node3D) -> void:
	if state == DEAD:
		return
	NetWorld.hold(self)
	held_by = by
	held_t = 0.0
	hold_point = global_position
	break_t = 1.6 / s
	_end_combo()
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
	_end_combo()
	cue.broken = false
	cue.posture_frac = 0.0
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
	_defl = maxf(_defl - dt * 5.0, 0.0)
	if state != BROKEN:
		if _posture_hold > 0.0:
			_posture_hold -= dt
		else:
			# like sekiro: it gets its breath back quicker the healthier it is
			posture_v = maxf(posture_v - dt * (0.25 + 0.45 * hp / max_hp) * (0.6 if king else 1.0), 0.0)
	if cue:
		cue.posture_frac = posture_v / posture_max
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
			_leap_cd -= dt
			if net_puppet:
				pass      # the host picks the combos (net_apply)
			elif dist < reach + 0.28 * s and absf(ang) < 0.45 and st_t > 0.3:
				_start_combo(_pick(combos if not combos.is_empty() else (POOL_SMALL if s < 1.3 else (POOL_BRUTE if not king else POOL_KING))))
			elif leaps_on and combos.is_empty() and _leap_cd <= 0.0 and dist < reach * 2.4 + 0.35 * s and absf(ang) < 0.3 and st_t > 0.5:
				_leap_cd = 2.5
				if _rng.randf() < 0.55:
					_start_combo(_pick(LEAPS_SMALL if s < 1.3 else LEAPS_BIG))
		WINDUP:
			# tracks you for most of the tell, then it's committed. later steps of a combo
			# re-aim quicker (it follows you round between bites)
			var track := (1.4 if step == 0 else 2.6) if st_t < windup_t * 0.6 else 0.0
			yaw += clampf(ang, -track * dt, track * dt)
			if strike == "leap":
				want_v = -fwd * 0.3 * smoothstep(0.0, windup_t, st_t)   # sinks back on its haunches
			if st_t >= windup_t:
				state = LUNGE
				st_t = 0.0
		LUNGE:
			var sk: Array = STRIKES[strike]
			var len: float = sk[0]
			match strike:
				"leap":
					want_v = fwd * 5.4 * sqrt(s) * (1.0 - st_t / len * 0.6)
				"sweep":
					want_v = Vector3.ZERO
					yaw += TAU * dt / len      # whips round, the tail sweeps the ground
				"swipe":
					want_v = fwd * 1.6 * sqrt(s) * (1.0 - st_t / len)
				_:
					want_v = fwd * 3.2 * sqrt(s) * (1.0 - st_t / len * 0.5)
			if not _bit and st_t > len * float(sk[1]):
				_bite(fwd)
			if st_t >= len:
				step += 1
				if step < (COMBOS[combo_id] as Array).size():
					_enter_step()
				else:
					combos_done += 1
					combo_id = ""
					state = RECOVER
					st_t = -_open
					_open = 0.0
		RECOVER:
			if st_t >= recover_t:
				state = CHASE
				st_t = 0.0
		STAGGER:
			if st_t >= _stagger_t:
				state = CHASE
				st_t = 0.0
		BROKEN:
			if st_t >= broken_t:
				posture_v = 0.0
				cue.broken = false
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


## the strike lands: only on what its hitbox covers. bite = in front of the snout, about one
## head length out. swipe = wider, a touch shorter. leap = the bite at the end of a long lunge.
## sweep = the tail, all round it. every local cat it covers gets a chance to deflect first
func _bite(fwd: Vector3) -> void:
	_bit = true
	bites += 1
	var sk: Array = STRIKES[strike]
	var dmg: float = bite_dmg * float(sk[2]) * (1.0 if (COMBOS.get(combo_id, [[]]) as Array).size() <= 1 else 0.7)
	for c in _victims():
		var d: Vector3 = (c as Node3D).global_position - global_position
		if absf(d.y) > 0.3 * s:
			continue
		var along := d.dot(fwd)
		var lat := (d - fwd * along)
		lat.y = 0.0
		var hit := false
		match strike:
			"swipe":
				hit = along > -0.02 and along < reach + 0.04 and lat.length() < bite_w * 2.2 + 0.085
			"leap":
				hit = along > 0.0 and along < reach + 0.14 and lat.length() < bite_w + 0.1
			"sweep":
				hit = Vector2(d.x, d.z).length() < reach * 1.25 + 0.1
			_:
				hit = along > 0.0 and along < reach + 0.09 and lat.length() < bite_w + 0.085
		if not hit:
			continue
		var pr = c.get("parry")
		if pr != null and pr.try_deflect(self, global_position, perilous):
			_on_deflected(c, pr.posture_dealt() * float(sk[3]))
		else:
			c.health.damage(dmg, global_position, 2.0 + s)


## the local cats this strike can hit: its target plus every local player cat (online: each
## game resolves hits on its own cat, see net_apply)
func _victims() -> Array:
	var out := []
	if is_instance_valid(target) and target.has_method("is_invulnerable") and target.get("health") != null:
		out.append(target)
	for c in get_tree().get_nodes_in_group("player"):
		if c != target and c.has_method("is_invulnerable") and c.get("health") != null:
			out.append(c)
	return out


func _on_deflected(by: Node3D, amount: float) -> void:
	deflected_n += 1
	_defl = 1.0
	_hit_flash = 0.5
	var away := global_position - by.global_position
	away.y = 0.0
	if away.length() > 0.01:
		velocity += away.normalized() * 0.9
	if step >= (COMBOS.get(combo_id, [[]]) as Array).size() - 1:
		_open = 0.35          # deflected the last one: it's left open a beat longer
	deflected.emit(by, amount)
	add_posture(amount)


## posture damage (deflects). full = broken: it slumps, the next swat finishes it
func add_posture(x: float) -> void:
	if state == DEAD or state == BROKEN:
		return
	posture_v += x
	_posture_hold = 1.4
	if posture_v >= posture_max:
		posture_v = posture_max
		_end_combo()
		state = BROKEN
		st_t = 0.0
		cue.broken = true
		SlashFx.sparks(self, global_position + Vector3.UP * 0.15 * s, Vector3.UP, false, 34)
		CatSfx.play_at("deflect", global_position, 1.1, 0.7)
		if target and target.has_method("_event"):
			target.call("_event", "posture broken!")


func _pick(pool: Array) -> String:
	return pool[_rng.randi() % pool.size()]


func _start_combo(id: String) -> void:
	combo_id = id
	step = 0
	_enter_step()
	combo_started.emit(id)


## the tell of step `step`: the cue goes up timed to the moment the strike lands
func _enter_step() -> void:
	var st: Array = (COMBOS[combo_id] as Array)[step]
	strike = st[1]
	perilous = st[2]
	windup_t = (0.5 if s < 1.3 else (0.8 if not king else 0.75)) * float(st[0]) / 0.5 if step == 0 else float(st[0]) * tempo
	state = WINDUP
	st_t = 0.0
	_bit = false
	var sk: Array = STRIKES[strike]
	cue.cue(windup_t + float(sk[0]) * float(sk[1]), perilous)


func _end_combo() -> void:
	combo_id = ""
	step = 0
	_open = 0.0
	if cue:
		cue.cancel()


## seconds until the current strike lands (-1 = none coming): tests + bots
func time_to_hit() -> float:
	if combo_id == "" or _bit:
		return -1.0
	var sk: Array = STRIKES[strike]
	var at: float = float(sk[0]) * float(sk[1])
	if state == WINDUP:
		return windup_t - st_t + at
	if state == LUNGE:
		return at - st_t
	return -1.0


# ---------------------------------------------------------------- online

func net_pack() -> Dictionary:
	return {"p": global_position, "y": yaw, "v": velocity, "st": state, "t": st_t, "c": combo_id,
		"k": step, "hp": hp, "po": posture_v}


## a host snapshot (puppet mode). a new combo step starts the same tell + cue here, so the
## strike lands on this cat on the host's beat; hits are then resolved locally (_bite)
func net_apply(d: Dictionary) -> void:
	net_puppet = true
	global_position = d.get("p", global_position)
	yaw = d.get("y", yaw)
	velocity = d.get("v", velocity)
	hp = d.get("hp", hp)
	posture_v = d.get("po", posture_v)
	var st: int = d.get("st", state)
	var c: String = d.get("c", "")
	var k: int = d.get("k", 0)
	if st == DEAD and state != DEAD:
		_die()
		return
	if st == BROKEN and state != BROKEN:
		posture_v = posture_max
		_end_combo()
		state = BROKEN
		st_t = d.get("t", 0.0)
		cue.broken = true
		return
	if c != "" and COMBOS.has(c) and (c != combo_id or k != step):
		combo_id = c
		step = k
		_enter_step()
		state = st
		st_t = d.get("t", 0.0)
		return
	if c == "" and combo_id != "":
		_end_combo()
	if st != state and c == "":
		state = st
		st_t = d.get("t", 0.0)


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
			var k := st_t / float(STRIKES[strike][0])
			ext_t = 1.0 if strike != "swipe" else 0.2
			if strike == "swipe":
				rear_t = 0.8 * (1.0 - k)
			jaw_t = 1.0 if k < 0.4 else 0.0     # snaps shut on the bite
			ear_t = 1.0
		BROKEN:
			ear_t = 0.2
			jaw_t = 0.35
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
	var slump := 0.0
	if state == BROKEN:
		# posture broken: sags low, sways, head hanging
		slump = smoothstep(0.0, 0.2, st_t) * (1.0 - smoothstep(broken_t - 0.3, broken_t, st_t))
		stg = sin(st_t * 5.0) * 0.35 * slump
	_roll = LowPoly.damp(_roll, stg * 0.35 + _death * 1.45, 12.0 if not dead else 5.0, dt)
	_pitch = LowPoly.damp(_pitch, -0.08 * moving * clampf(v / 2.0, 0.0, 1.0), 8.0, dt)
	torso.position = Vector3(0, (0.1 + 0.03 * _rear - 0.01 * _ext - 0.035 * _death - 0.03 * slump) * s + bounce, (0.03 * _rear - 0.06 * _ext + 0.02 * _defl) * s)
	torso.rotation = Vector3(_pitch + _rear * 0.42 - _ext * 0.12 + _defl * 0.25 - slump * 0.1, clampf(-_yaw_rate * 0.05, -0.2, 0.2), _roll)
	# a deflected strike snaps the head back up and to the side
	head.rotation = Vector3(_rear * -0.25 + _ext * 0.2 + (sin(_t * 1.7) * 0.05 if state == IDLE else 0.0) - _defl * 0.5 + slump * 0.45, stg * 0.4 + clampf(-_yaw_rate * 0.08, -0.3, 0.3) + _defl * 0.3, 0)
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
			if state == LUNGE and strike == "swipe":
				# one forepaw rakes across in front of it
				var k := clampf(st_t / float(STRIKES["swipe"][0]), 0.0, 1.0)
				var sd: float = leg.side
				if sd > 0.0:
					foot.x += lerpf(0.07, -0.08, smoothstep(0.1, 0.6, k)) * s
					foot.z -= 0.06 * s * sin(k * PI)
					lift += 0.035 * s * sin(k * PI)
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
