class_name CatCombat
extends Node
## paw combat for the player cat. each mouse button is one fore paw:
##
##   tap left / right mouse   -> SWAT with that paw (left paw / right paw, not random any more)
##   hold one button          -> RAKE: that paw keeps raking at whatever is in front, a swipe every
##                               RAKE_EVERY s, each one cheap on damage and stamina. with nothing to
##                               rake in reach it's the old claw hold instead (hook + drag things,
##                               drag claw marks down surfaces)
##   hold both                -> GRIP: the cat rears up on its hind legs (~0.24 s), comes down with
##                               both fore paws on the target and keeps holding it while both are
##                               held: claws squeezing + bites every GRIP_TICK s. a cat needs a
##                               free fore paw to walk, so while both paws hold it can't move,
##                               hop or dodge. let go of either button and you're free again.
##                               the held one struggles and breaks out after a while (rat break_t),
##                               holding drains stamina and the grip slips when the bar runs dry
##
## a press waits CHORD_WIN before it swats, so mashing both buttons together reads as the grip
## and not a swat first. 70 ms is under what you notice, the strike still lands ~0.19 s after
## the click.
##
## damage (souls rat take_hit): swat 1, rake 0.5 (half poise), grip slam 1.5 heavy, grip tick 0.5.
## all of it x2 from behind, so getting round a rat and grabbing it is the big play.

enum { NONE, RAKE, CLAW, SPENT }
enum { G_OFF, G_REAR, G_HOLD }

const CHORD_WIN := 0.07       # second button inside this = grip, not swat + swat
const CHORD_WAIT := 0.15     # both down but the cat can't grip yet: keep trying this long
const HOLD_T := 0.28          # held this long = rake / claw hold
const RAKE_EVERY := 0.24      # one rake per this (the fp swat anim can restart from 0.22 s)
const RAKE_DMG := 0.5
const RAKE_POISE := 0.5       # rakes stagger half as fast as swats
const GRIP_REAR_T := 0.24     # up on the hind legs before the paws come down
const GRIP_REACH := 0.6
const GRIP_SLAM_DMG := 1.5
const GRIP_TICK := 0.4
const GRIP_TICK_DMG := 0.5

var player: Node3D            # CatPlayer
var down := [false, false]
var age := [0.0, 0.0]
var fired := [false, false]
var mode := [NONE, NONE]
var rake_t := [0.0, 0.0]

var grip_phase := G_OFF
var grip_t := 0.0
var grip_target: Node3D = null
var grip_point := Vector3.ZERO    # world: where both paws are clamped
var _tick_t := 0.0
var _chord_wait := 0.0
# blend weights the player hands to the rig / fp paws
var rear_w := 0.0
var grip_w := 0.0
# test counters
var swats := 0
var rakes := 0
var grips := 0
var grip_ticks := 0


func gripping() -> bool:
	return grip_phase != G_OFF


## both fore paws busy: no walking, hopping, leaping or dodging
func locks_move() -> bool:
	return grip_phase != G_OFF


func any_down() -> bool:
	return down[0] or down[1]


func busy() -> bool:
	return grip_phase != G_OFF or mode[0] == RAKE or mode[1] == RAKE


func tick(dt: float, l: bool, r: bool) -> void:
	var p := player
	var now := [l, r]
	var pressed := [l and not down[0], r and not down[1]]
	for i in 2:
		if pressed[i]:
			age[i] = 0.0
			fired[i] = false
			mode[i] = NONE
			rake_t[i] = 0.0
	if grip_phase != G_OFF:
		if not (l and r) or not is_instance_valid(p):
			_grip_end()
		else:
			_grip_step(dt)
	elif l and r and (pressed[0] or pressed[1] or _chord_wait > 0.0):
		# both down: grip. if the cat can't right now (a bump left it off the floor for a
		# tick, mid dodge) it keeps trying for a moment instead of turning into two swats
		if pressed[0] or pressed[1]:
			_chord_wait = CHORD_WAIT
		_chord_wait -= dt
		if _can_grip():
			_chord_wait = 0.0
			_grip_start()
		elif _chord_wait > 0.0:
			down[0] = l
			down[1] = r
			return
	else:
		_chord_wait = 0.0
	if grip_phase == G_OFF:
		for i in 2:
			_paw_step(i, dt, now[i])
	down[0] = l
	down[1] = r
	var hold := grip_phase == G_HOLD
	rear_w = LowPoly.damp(rear_w, 1.0 if grip_phase == G_REAR else (0.18 if hold else 0.0), 16.0 if grip_phase == G_REAR else 22.0, dt)
	grip_w = LowPoly.damp(grip_w, 1.0 if hold else 0.0, 30.0 if hold else 12.0, dt)


func _paw_step(i: int, dt: float, held: bool) -> void:
	var p := player
	if held:
		if mode[i] == SPENT:
			return
		age[i] += dt
		if not fired[i] and age[i] >= CHORD_WIN:
			_swat(i)
		if mode[i] == NONE and age[i] >= HOLD_T:
			var t: Dictionary = p._paw_target(p.SWAT_RANGE, 0.5)
			if not t.is_empty() and t.get("prey") != null and t.prey != p.carried:
				mode[i] = RAKE
				rake_t[i] = RAKE_EVERY   # first rake right away
			else:
				mode[i] = CLAW
				p._claw_start(i)
		if mode[i] == RAKE:
			rake_t[i] += dt
			if rake_t[i] >= RAKE_EVERY:
				rake_t[i] = 0.0
				if p.stamina.spend(CatStamina.RAKE):
					rakes += 1
					p._do_swat(i, true)
				else:
					mode[i] = SPENT   # bar's empty: the paw drops
		elif mode[i] == CLAW and not p.clawing:
			mode[i] = SPENT          # hook came loose (out of reach, swatted with it, ...)
	elif down[i]:
		# released
		if not fired[i] and mode[i] != SPENT:
			_swat(i)              # quick tap, shorter than the chord window
		if mode[i] == CLAW and p.clawing and p.paws.claw_i == i:
			p._claw_release()
		mode[i] = NONE


func _swat(i: int) -> void:
	fired[i] = true
	if player.stamina.spend(CatStamina.SWAT):
		swats += 1
		player._do_swat(i)


func _can_grip() -> bool:
	var p := player
	return p.is_on_floor() and not (p.climbing or p.clambering or p.mantling or p.scratching or p.charging or p.dash.busy())


# ------------------------------------------------------------------ grip

func _grip_start() -> void:
	var p := player
	if not p.stamina.spend(CatStamina.GRIP):
		return
	# whatever the paws were doing stops: both are needed now
	for i in 2:
		fired[i] = true
		if mode[i] == CLAW and p.clawing:
			p._claw_release()
		mode[i] = NONE
	grips += 1
	grip_phase = G_REAR
	grip_t = 0.0
	_tick_t = 0.0
	var t: Dictionary = p._paw_target(GRIP_REACH, 0.6)
	grip_target = t.get("prey") if not t.is_empty() and t.get("prey") != p.carried else null
	grip_point = t.point if not t.is_empty() else p.global_position - p.global_transform.basis.z * 0.24
	p._event("rears up!")


func _grip_step(dt: float) -> void:
	var p := player
	grip_t += dt
	# planted: no paw free to walk on
	p.velocity.x *= 0.6
	p.velocity.z *= 0.6
	var valid: bool = is_instance_valid(grip_target) and (not grip_target.has_method("alive") or grip_target.alive())
	if valid:
		# turn the body square to it (slowly, the hind legs shuffle round)
		var to: Vector3 = grip_target.global_position - p.global_position
		to.y = 0.0
		if to.length() > 0.01:
			var ty: float = atan2(-to.x, -to.z)
			var d: float = wrapf(ty - p.yaw, -PI, PI)
			p.yaw += clampf(d, -4.0 * dt, 4.0 * dt)
	if grip_phase == G_REAR:
		if valid:
			grip_point = grip_target.global_position + Vector3.UP * 0.05
		if grip_t >= GRIP_REAR_T:
			_slam(valid)
		return
	# holding
	p.stamina.drain(CatStamina.GRIP_HOLD, dt)
	p.rig.pin = 1.0
	if p.stamina.value <= 0.0:
		p._event("grip slips (no stamina)")
		_grip_end()
		return
	if grip_target == null:
		return       # paws planted on the floor, nothing in them
	if not valid or ("held_by" in grip_target and grip_target.held_by != p):
		p._event("it broke free!" if valid else "got it!")
		_let_go()
		return
	var fwd: Vector3 = -p.global_transform.basis.z
	var hold_pt: Vector3 = p.global_position + fwd * (0.1 + 0.16 * float(grip_target.get("s") if "s" in grip_target else 1.0))
	if "hold_point" in grip_target:
		grip_target.hold_point = hold_pt
	grip_point = grip_target.global_position + Vector3.UP * 0.05
	_tick_t += dt
	if _tick_t >= GRIP_TICK:
		_tick_t = 0.0
		grip_ticks += 1
		if p.rig.has_method("grip_squeeze"):
			p.rig.grip_squeeze()
		if grip_target.has_method("take_hit"):
			grip_target.take_hit(GRIP_TICK_DMG, p.global_position, false, 0.0)


func _slam(valid: bool) -> void:
	var p := player
	grip_phase = G_HOLD
	_tick_t = 0.0
	p.rig.pin = 1.0
	if p.paws.has_method("pin"):
		p.paws.pin()
	if not valid:
		grip_target = null
		p._event("paws down")
		return
	var d: float = grip_target.global_position.distance_to(p.global_position)
	if d > GRIP_REACH + 0.25:
		grip_target = null       # it got away while you reared up
		p._event("missed the grab")
		return
	if grip_target.has_method("take_hit"):
		grip_target.take_hit(GRIP_SLAM_DMG, p.global_position, true)
		if grip_target.has_method("grab") and (not grip_target.has_method("alive") or grip_target.alive()):
			grip_target.grab(p)
			p._event("got a grip on the " + p._prey_name(grip_target) + "!")
		else:
			grip_target = null
	else:
		# small prey: pinned under both paws = caught
		p._catch(grip_target)
		grip_target = null


func _let_go() -> void:
	if is_instance_valid(grip_target) and grip_target.has_method("ungrab"):
		grip_target.ungrab(player)
	grip_target = null


func _grip_end() -> void:
	_let_go()
	grip_phase = G_OFF
	# a paw still held after the grip is done does nothing until it's pressed again
	for i in 2:
		fired[i] = true
		mode[i] = SPENT


func cancel() -> void:
	if grip_phase != G_OFF:
		_grip_end()
	for i in 2:
		if mode[i] == CLAW and player.clawing:
			player._claw_release()
		mode[i] = NONE
