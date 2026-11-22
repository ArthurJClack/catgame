class_name CatWallRun
extends RefCounted
## short wall runs, real cat style: jump at a wall at an angle with some speed and the cat
## gets one or two quick paw steps along / up the face (fore pair, then the hind pair
## shoves), then it drops off. space while it's on the wall (or just after the last step)
## kicks off from those steps: all four paws plant, the body coils down onto them, the hind
## legs straighten and the body twists round in the air to the new heading.
## not a parkour run: no holding on, no long runs, it only ever turns speed you brought into
## a little height and a better angle for the kick.
##
## instance: player.wallrun. the player calls try_start() after its air move, step() while
## active, and orient() poses the rig while posing(). CatWallRun.off = true = old behaviour
## (for before / after films).

static var off := false

const MIN_SPEED := 2.8      # m/s across the floor coming in (a trot is 3.2)
const MIN_ALONG := 1.9      # of that, along the face
const MAX_ANGLE := 1.05     # rad off the face (60 deg). more head on than that = kick / climb / scramble
const MIN_INTO := 0.25      # m/s into the face: has to actually be going at it, not brushing past
const TALL := 0.42          # needs this much wall above the feet (lower = a ledge, hop onto it)
const STEP_T := 0.13        # one step on the wall: fore pair touches, hind pair pushes
const TWO_STEPS := 3.9      # along speed for a second step
const STEP_UP := [2.1, 1.5] # what each hind push gives upward (m/s), on top of what's left of the jump
const STEP_KEEP := 0.9      # along speed kept through each step
const PRESS := 0.35         # m/s held into the face (claws catch, contact kept)
const PEEL := 0.45          # m/s off the face when the steps run out
const COST := 5.0           # stamina
const COYOTE := 0.16        # space this long after the last step still kicks off the run
const ROLL := 0.95          # rad the body rolls onto the face (~55 deg: paws on it, back off it)
const PITCH_MAX := 0.45     # most the body points up the face
const FORE_STANCE := 0.05
const HIND_STANCE := 0.06
const HIND_AT := 0.045      # hind pair lands this long after the fore pair
const COIL := 0.1           # kick off a run: paws planted, body sinking onto them, before the push
const TWIST := 0.24         # after the push the body turns round to the flight over this long
const PUSH := 0.08          # the hind legs' push: the body comes up to the kick's speed over this
const HIND_HOLD := 0.07     # hind paws stay on the wall this long into the push (the legs extend)
const KICK_CARRY := 0.6     # of the run's speed along the kick heading that survives the kick
const KICK_OFF_MIN := 0.5   # kick heading is at least this far off the wall (dot with n, ~30 deg)

enum { NONE, RUN, COIL_ST, PUSH_ST, OUT }

var p: CatPlayer
var state := NONE
var n := Vector3.ZERO        # wall normal (flat)
var dir := Vector3.ZERO      # along the face, the way it's running (flat)
var along := 0.0             # speed along the face
var steps := 0
var step_i := 0              # hind pushes done
var t := 0.0
var used := false            # one run per time in the air
var since := 9.0             # time since the run ended
var kick_from := false       # the kick under way came off a run
var _wall_d := 0.0           # n . point on the face
var _w := 0.0                # blend onto the wall pose (critically damped spring)
var _wv := 0.0
var _out_t := 0.0
var _b0 := Basis()           # visible body when the push / drop off started
var _p0 := Vector3.ZERO      #   (offset from the capsule)
var _last_b := Basis()
var _b_in := Basis()          # body when the run started (the blend onto the wall pose starts from it)
var _clip_in := Vector3.ZERO  # and the clip guard's shove then
var _last_p := Vector3.ZERO
var _push_from := Vector3.ZERO   # velocity at the end of the coil
var _push_v := Vector3.ZERO      # the kick's velocity, reached at the end of the push
var _push_t := 0.0
var _paw_t := [-1.0, -1.0, -1.0, -1.0]   # time each paw planted (-1 = free)
var _paw_hold := [0.0, 0.0, 0.0, 0.0]    # how long it stays planted
var _paw_w := [0.0, 0.0, 0.0, 0.0]


func _init(owner_player: CatPlayer) -> void:
	p = owner_player


func active() -> bool:
	return state == RUN


## the rig takes its pose from here (run, coil, the twist out)
func posing() -> bool:
	return state != NONE


## a press of space now kicks off the run (on it, or a moment after the last step)
func kick_ready() -> bool:
	return state == RUN or (state == OUT and not kick_from and since < COYOTE)


## crouch the rig sinks to: coiling onto the planted paws before a kick
func coil() -> float:
	if state == COIL_ST:
		return 0.35 + 0.65 * smoothstep(0.0, COIL, t)
	if state == RUN:
		return 0.35   # legs flexed under it on the wall
	return 0.0


func reset_air() -> void:
	used = false


## after the air move: a fresh wall contact at an angle, at speed, out of a jump starts a run.
## hv = the horizontal velocity the cat had going into the contact
func try_start(hv: Vector3, wish_dir: Vector3, wish_len: float) -> bool:
	if off or used or state == RUN or state == COIL_ST:
		return false
	if p.is_on_floor() or p.wall_time > 0.0 or not p.jumped_this_air or p.pounce_air:
		return false
	if p.climber.active() or p.kick_plant_t > 0.0 or p.dash.busy() or p.combat.committed() or p.scratching:
		return false
	if p.velocity.y < -2.5 or wish_len < 0.3:
		return false
	var c: Object = p.wall_collider
	if c == null or not is_instance_valid(c) or c is RigidBody3D or c is CharacterBody3D:
		return false
	var wn := p.wall_normal
	if wn == Vector3.ZERO or wish_dir.dot(wn) > 0.2:
		return false   # steering away from it: let it go
	var into := -hv.dot(wn)
	var av := hv + wn * into
	var al := av.length()
	if hv.length() < MIN_SPEED or al < MIN_ALONG or into < MIN_INTO or atan2(into, al) > MAX_ANGLE:
		return false
	# enough wall to put paws on (low stuff is a hop / mantle), and somewhere to run
	var feet := p.global_position
	var hi := _ray(feet + Vector3.UP * TALL + wn * 0.12, feet + Vector3.UP * TALL - wn * (CatPlayer.RADIUS + 0.12))
	if hi.is_empty() or absf((hi.normal as Vector3).y) > 0.3 or (hi.normal as Vector3).dot(wn) < 0.85:
		return false
	var chest := feet + Vector3.UP * 0.12
	var ahead := _ray(chest, chest + av / al * 0.35)
	if not ahead.is_empty():
		return false
	var face := _ray(chest, chest - wn * (CatPlayer.RADIUS + 0.1))
	if face.is_empty():
		return false
	if not p.stamina.spend(COST):
		return false
	used = true
	state = RUN
	n = wn
	dir = av / al
	along = al
	steps = 2 if al >= TWO_STEPS else 1
	step_i = 0
	t = 0.0
	kick_from = false
	_wall_d = (face.position as Vector3).dot(n)
	_b_in = p.rig.global_transform.basis.orthonormalized()
	_clip_in = p.global_transform.basis.z * p._clip_off
	for i in 4:
		_paw_t[i] = -1.0
	p.velocity = dir * along - n * PRESS + Vector3.UP * p.velocity.y
	p._event("wall run")
	if OS.get_environment("WR_DBG") != "":
		print("  wallrun: speed %.2f along %.2f into %.2f angle %.0f deg vy %.2f steps %d" % [hv.length(), al, into, rad_to_deg(atan2(into, al)), p.velocity.y, steps])
	return true


## one tick on the wall
func step(dt: float, wish_dir: Vector3, jump_pressed: bool) -> void:
	t += dt
	# paws: the fore pair touches at the start of each step, the hind pair lands just after
	# and that's the push
	var k := mini(int(t / STEP_T), steps - 1)
	var ts := k * STEP_T
	for i in 4:
		var at := ts + (0.0 if i < 2 else HIND_AT) + (0.012 if i % 2 == 1 else 0.0)
		if t >= at and t - dt < at and t < steps * STEP_T + 0.02:
			_plant(i, FORE_STANCE if i < 2 else HIND_STANCE)
			if i == 2:
				p.velocity.y = maxf(p.velocity.y, STEP_UP[mini(step_i, STEP_UP.size() - 1)])
				along *= STEP_KEEP
				step_i += 1
				p._event("wall step %d" % step_i)
	if jump_pressed and p.kicks_left > 0:
		p._try_wall_kick(wish_dir)
		if p.kick_plant_t > 0.0:
			return
	p.velocity.y -= CatPlayer.G * dt
	var vy := p.velocity.y
	p.velocity = dir * along - n * PRESS + Vector3.UP * vy
	# the body turns to run along it
	var ty := atan2(-dir.x, -dir.z)
	p.yaw += clampf(wrapf(ty - p.yaw, -PI, PI), -9.0 * dt, 9.0 * dt)
	p.rotation.y = p.yaw
	p.move_and_slide()
	p._track_walls()
	var chest := p.global_position + Vector3.UP * 0.12
	var face := _ray(chest, chest - n * (CatPlayer.RADIUS + 0.12))
	if not face.is_empty() and (face.normal as Vector3).dot(n) > 0.85:
		_wall_d = (face.position as Vector3).dot(n)
	var blocked := false
	for i in p.get_slide_collision_count():
		var cn := p.get_slide_collision(i).get_normal()
		if cn.dot(dir) < -0.6:
			blocked = true   # ran into something along the face (an inside corner, a post)
	if p.is_on_floor() or face.is_empty() or blocked:
		_end(0.0)
	elif t >= steps * STEP_T:
		_end(PEEL)


## space on the run: the player's kick starts its plant. the body stays in its run pose,
## paws planted where they are, and coils onto them
func begin_kick() -> void:
	kick_from = true
	state = COIL_ST
	t = 0.0
	for i in 4:
		_plant(i, 9.0)


## the kick's push (player._kick_release): body twists from the wall pose to the flight
func release_kick(v_coil: Vector3) -> void:
	if state != COIL_ST:
		return
	_start_out()
	# the hind legs straighten over PUSH: the body comes up to the kick's speed over that
	# (constant shove), not in one tick
	state = PUSH_ST
	_push_t = 0.0
	_push_from = v_coil
	_push_v = p.velocity
	p.velocity = v_coil


func pushing() -> bool:
	return state == PUSH_ST


func push_step(dt: float) -> void:
	_push_t += dt
	var f := clampf(_push_t / PUSH, 0.0, 1.0)
	p.velocity = _push_from.lerp(_push_v, f)
	p.move_and_slide()
	p._track_walls()
	if f >= 1.0:
		p.velocity = _push_v
		state = OUT


func _end(peel: float) -> void:
	p.velocity += n * peel
	_start_out()


func _start_out() -> void:
	state = OUT
	_out_t = 0.0
	since = 0.0
	_b0 = _last_b
	_p0 = _last_p


func _plant(i: int, hold: float) -> void:
	_paw_t[i] = t
	_paw_hold[i] = hold
	var b := _run_basis()
	var o := _run_origin(b)
	var lead := along * minf(hold, 0.06) * 0.5   # land ahead, the stance sweeps it back under
	var loc: Vector3 = p.rig.HOME[i] + Vector3(0, 0, -lead if state == RUN else 0.0)
	var w := o + b * loc
	p.rig.wall_paws[i] = w - n * (w.dot(n) - _wall_d) + n * 0.022


## body pose on the face: pointing along the way it's going on the wall (a little up it),
## rolled so the paws are on the face and the back is off it
func _run_basis() -> Basis:
	var v := p.velocity - n * p.velocity.dot(n)
	var f := dir
	if v.length() > 0.3:
		var vf := v.normalized()
		var pit := clampf(asin(clampf(vf.y, -1.0, 1.0)), -0.3, PITCH_MAX)
		var flat := Vector3(vf.x, 0.0, vf.z)
		flat = flat.normalized() if flat.length() > 0.1 else dir
		f = (flat * cos(pit) + Vector3.UP * sin(pit)).normalized()
	var u := Vector3.UP * cos(ROLL) + n * sin(ROLL)
	var z := -f
	var x := u.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


func _run_origin(b: Basis) -> Vector3:
	# chest stays out off the face, the paws reach in to it
	var centre := p.global_position + Vector3.UP * 0.1 + n * 0.06
	return centre - b.y * 0.13


## poses the rig (player._orient_rig_base, after the clip guard)
func orient(dt: float) -> void:
	var rig := p.rig
	var body := p.global_transform.basis.orthonormalized()
	var bpos := p.global_position + body.z * p._clip_off
	var target_w := 1.0 if state == RUN or state == COIL_ST else 0.0
	var b: Basis
	var pos: Vector3
	if state == OUT or state == PUSH_ST:
		_out_t += dt
		since += dt
		var u := smoothstep(0.0, TWIST if kick_from else 0.2, _out_t)
		var q0 := _b0.get_rotation_quaternion()
		b = Basis(q0.slerp(body.get_rotation_quaternion(), u))
		pos = (p.global_position + _p0).lerp(bpos, u)
		if u >= 1.0:
			state = NONE
			_w = 0.0
			_wv = 0.0
	else:
		if state == COIL_ST:
			t += dt
		_wv += (20.0 * 20.0 * (target_w - _w) - 40.0 * _wv) * dt
		_w = clampf(_w + _wv * dt, 0.0, 1.0)
		var rb := _run_basis()
		b = Basis(_b_in.get_rotation_quaternion().slerp(rb.get_rotation_quaternion(), _w))
		pos = bpos.lerp(_run_origin(rb), _w)
	_last_b = b
	_last_p = pos - p.global_position
	if OS.get_environment("WR_DBG") == "2":
		print("  wr st %d t %.3f out %.3f w %.2f cap %s v %s vis %s plant %.3f" % [state, t, _out_t, _w, p.global_position.snapped(Vector3.ONE * 0.001), p.velocity.snapped(Vector3.ONE * 0.01), pos.snapped(Vector3.ONE * 0.001), p.kick_plant_t])
	rig.global_transform = Transform3D(b, pos)
	# paws on the face while they're planted, eased on and off
	for i in 4:
		var on := false
		if _paw_t[i] >= 0.0:
			match state:
				RUN: on = t - _paw_t[i] < _paw_hold[i]
				COIL_ST: on = true
				OUT, PUSH_ST: on = kick_from and i >= 2 and _out_t < HIND_HOLD
		_paw_w[i] = move_toward(_paw_w[i], 1.0 if on else 0.0, dt / (0.02 if on else 0.045))
		rig.wall_paw_w[i] = _paw_w[i]
	if state == NONE:
		for i in 4:
			_paw_w[i] = 0.0
			rig.wall_paw_w[i] = 0.0


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(q)
