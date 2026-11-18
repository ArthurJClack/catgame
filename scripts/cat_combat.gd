class_name CatCombat
extends Node
## paw combat for the player cat. each mouse button is one fore paw:
##
##   tap left / right mouse   -> SWAT with that paw (left paw / right paw, not random any more)
##   hold one button          -> RAKE: that paw keeps raking at whatever is in front, a swipe every
##                               RAKE_EVERY s, each one cheap on damage and stamina. with nothing to
##                               rake in reach it's the old claw hold instead (hook + drag things,
##                               drag claw marks down surfaces)
##   hold both, let go of both -> POUNCE (see below)
##   hold both                -> GRIP: the cat rears up on its hind legs (~0.24 s), comes down with
##                               both fore paws on the target and keeps holding it while both are
##                               held: claws squeezing + bites every GRIP_TICK s. a cat needs a
##                               free fore paw to walk, so while both paws hold it can't move,
##                               hop or dodge. let go of either button and you're free again.
##                               the held one struggles and breaks out after a while (rat break_t),
##                               holding drains stamina and the grip slips when the bar runs dry
##
## POUNCE: holding both rears the cat up. no target in paw reach when it comes down = it drops
## into a pounce crouch and winds up (bum wiggle) while you aim with the mouse; the arc shows
## where it'll land. let go of both (within RELEASE_WIN of each other) and it launches: a free
## ballistic projectile along the look direction, speed from how long it wound up, no air
## steering. it soft locks: prey / rats near where the arc comes down, the tab lock-on target
## (player.lock_target) and ledges the arc would smack into just under the top all bend the
## launch so it comes down exactly on them. on touch down it sticks the landing: no slide, no
## extra steps (player.stick_armed / land_stick), and the forepaws pin whatever is under them.
## let go of one only = cancel, the cat's free to walk again. releasing both while gripping a
## rat pounces too (point blank: a heavy pin)
##
## a press waits CHORD_WIN before it swats, so mashing both buttons together reads as the grip
## and not a swat first. 70 ms is under what you notice, the strike still lands ~0.19 s after
## the click.
##
## damage (souls rat take_hit): swat 1, rake 0.5 (half poise), grip slam 1.5 heavy, grip tick 0.5.
## all of it x2 from behind, so getting round a rat and grabbing it is the big play.

enum { NONE, RAKE, CLAW, SPENT }
enum { G_OFF, G_REAR, G_HOLD, G_AIM }

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
const GRAB_DIST := 0.5        # target this close when the rear up ends = grab it, else pounce aim
const RELEASE_WIN := 0.12     # both buttons up within this = pounce, one only = cancel
const POUNCE_WIND_T := 0.7    # crouched this long = full power
const POUNCE_SPD_MIN := 2.4   # m/s off the hind legs, no wind up
const POUNCE_SPD_MAX := 6.2   # full wind up (~1.8 m up / ~3.6 m out, real cat numbers)
const POUNCE_LIFT := 0.35     # rad: launches this much above the look line
const POUNCE_RANGE := 3.6     # soft lock reach (horizontal)
const MAGNET_R := 0.55        # prey this close to where the free arc lands gets locked

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
var _rel_t := -1.0
var pounce := {}               # current aim solve: vel, point, kind, ok, t
var pounces := 0
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


func aiming() -> bool:
	return grip_phase == G_AIM


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
		if l and r:
			_rel_t = -1.0
			_grip_step(dt)
		elif not l and not r:
			_launch()             # both let go (together, or the second inside RELEASE_WIN)
		else:
			# one let go: give the other a moment to follow, else it's a cancel
			_rel_t = maxf(_rel_t, 0.0) + dt
			if _rel_t > RELEASE_WIN:
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
	if p.stamina.value <= 0.0:
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
	_rel_t = -1.0
	p.charge = 0.0
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
			var near: bool = valid and grip_target.global_position.distance_to(p.global_position) < GRAB_DIST + 0.16 * float(grip_target.get("s") if "s" in grip_target else 1.0)
			if near:
				p.stamina.spend(CatStamina.GRIP)
				_slam(valid)
			else:
				# nothing to grab: down into the pounce crouch, wind up + aim
				grip_phase = G_AIM
				grip_t = 0.0
				grip_target = null
		return
	if grip_phase == G_AIM:
		p.charge = minf(p.charge + dt / POUNCE_WIND_T, 1.0)
		# the body swings round to where you aim (the hind feet shuffle)
		var aim_yaw: float = p.orb_yaw
		if p.get("lock_target") != null and is_instance_valid(p.lock_target):
			var tl: Vector3 = p.lock_target.global_position - p.global_position
			aim_yaw = atan2(-tl.x, -tl.z)
		var dy: float = wrapf(aim_yaw - p.yaw, -PI, PI)
		p.yaw += clampf(dy, -6.0 * dt, 6.0 * dt)
		pounce = _solve()
		_show_aim(pounce)
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
			var up := Vector3.UP + (p.global_position - grip_point).normalized() * 0.5
			SlashFx.sparks(p, grip_point, up, true, 6)


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
		_slam_fx(grip_target)
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
	_rel_t = -1.0
	player.charge = 0.0
	player._aim_root.visible = false
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
		fired[i] = true
		mode[i] = SPENT if down[i] else NONE


# ------------------------------------------------------------------ pounce

func _launch() -> void:
	var p := player
	var sol := _solve()
	_let_go()
	grip_phase = G_OFF
	_rel_t = -1.0
	for i in 2:
		fired[i] = true
		mode[i] = NONE
	p._aim_root.visible = false
	var c: float = p.charge
	p.charge = 0.0
	if not p.is_on_floor():
		return
	if not p.stamina.spend(CatStamina.POUNCE + CatStamina.POUNCE_CHARGE * c):
		sol = _solve(minf(c, 0.25))   # spent: a feeble little pounce
	pounces += 1
	p.velocity = sol.vel
	p.leap_lock = true          # a projectile now: no steering in the air
	p.pounce_air = true
	p.stick_armed = true
	p.jumped_this_air = true
	p._hopped_now = true        # leave the floor this tick (no snap back down)
	p._event("pounce! %s %.1f m" % [sol.kind, Vector2(sol.point.x - p.global_position.x, sol.point.z - p.global_position.z).length()])


## where a pounce launched now goes. free: along the look line + POUNCE_LIFT, speed from the
## wind up, traced through the world. then soft lock: lock-on target, prey / rats near the
## landing, or a ledge the arc smacks into just under its top -> re-solve to land right there.
func _solve(c := -1.0) -> Dictionary:
	var p := player
	if c < 0.0:
		c = p.charge
	var feet: Vector3 = p.global_position
	var look: Vector3 = p._look_dir()
	var flat := Vector3(look.x, 0, look.z)
	if flat.length() < 0.01:
		flat = -p.global_transform.basis.z
	flat = flat.normalized()
	var el := clampf(asin(clampf(look.y, -1.0, 1.0)) + POUNCE_LIFT, 0.3, 1.15)
	var spd := lerpf(POUNCE_SPD_MIN, POUNCE_SPD_MAX, c)
	var v0 := flat * cos(el) * spd + Vector3.UP * sin(el) * spd
	var tr := _trace(feet, v0)
	var out := {"vel": v0, "point": tr.point, "kind": "free", "ok": true, "t": tr.t}
	# soft lock targets, best first
	var tgt := Vector3.INF
	var kind := ""
	var lock: Node3D = p.get("lock_target") if "lock_target" in p else null
	if lock != null and is_instance_valid(lock):
		tgt = _paws_on(lock, feet)
		kind = "lock"
	if tgt == Vector3.INF:
		var best := MAGNET_R + 0.12 * Vector2(tr.point.x - feet.x, tr.point.z - feet.z).length()
		var eye: Vector3 = p._aim_pos()
		for n in p.get_tree().get_nodes_in_group("prey"):
			if not n is Node3D or n == p.carried or (n.has_method("alive") and not n.alive()):
				continue
			var q: Vector3 = (n as Node3D).global_position
			var dl := Vector2(q.x - tr.point.x, q.z - tr.point.z).length()
			if look.angle_to(q - eye) < 0.12:
				dl = minf(dl, MAGNET_R * 0.5)   # right under the crosshair counts too
			if dl < best and absf(q.y - tr.point.y) < 1.0:
				best = dl
				tgt = _paws_on(n, feet)
				kind = "prey"
	if tgt == Vector3.INF and tr.n.y < 0.5 and tr.n != Vector3.ZERO:
		# smacks into the side of something: if the top is close above, land on top instead
		var nh := Vector3(tr.n.x, 0, tr.n.z).normalized()
		var top: Dictionary = p._ray(tr.point - nh * 0.12 + Vector3.UP * 0.7, tr.point - nh * 0.12 - Vector3.UP * 0.05)
		if not top.is_empty() and top.normal.y > 0.7 and p._fits(top.position + Vector3.UP * 0.02):
			tgt = top.position
			kind = "ledge"
	if tgt != Vector3.INF:
		var sv := _arc_to(feet, tgt)
		if not sv.is_empty() and sv.vel.length() <= POUNCE_SPD_MAX * 1.2:
			out = {"vel": sv.vel, "point": tgt, "kind": kind, "ok": true, "t": sv.t}
	return out


## where the forepaws should come down on something: just short of it, on its side facing you
func _paws_on(n: Node3D, feet: Vector3) -> Vector3:
	var q := n.global_position
	var to := Vector3(q.x - feet.x, 0, q.z - feet.z)
	var big := float(n.get("s")) if "s" in n else 0.0
	var back := 0.15 if big <= 0.0 else 0.1 + 0.16 * big
	if to.length() < back + 0.05:
		return Vector3(feet.x, q.y, feet.z)
	var pt := q - to.normalized() * back
	if Vector2(pt.x - feet.x, pt.z - feet.z).length() > POUNCE_RANGE:
		return Vector3.INF
	return pt


## arc from feet that lands exactly on tgt: apex a little above the higher end (flatter than
## the aimed leap, it's an attack)
func _arc_to(feet: Vector3, tgt: Vector3) -> Dictionary:
	var dh := tgt.y - feet.y
	var flat := Vector3(tgt.x - feet.x, 0, tgt.z - feet.z)
	var d := flat.length()
	if d > POUNCE_RANGE + 0.2:
		return {}
	var apex := maxf(dh, 0.0) + 0.12 + 0.09 * d
	var vy := sqrt(2.0 * CatPlayer.G * apex)
	var t := vy / CatPlayer.G + sqrt(2.0 * maxf(apex - dh, 0.0) / CatPlayer.G)
	var vh := d / maxf(t, 0.05)
	var hd := flat / d if d > 0.001 else Vector3.ZERO
	return {"vel": hd * vh + Vector3.UP * vy, "t": t}


## step the projectile through the world (physics tick segments) until it hits something
func _trace(feet: Vector3, v0: Vector3) -> Dictionary:
	var p := player
	# the feet point. while it's still rising it can't land on a floor (that's the one it's
	# standing on), only smack into walls / ceilings
	var pos := feet
	var v := v0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)   # same steps the real flight takes
	var t := 0.0
	while t < 2.5:
		v.y -= CatPlayer.G * dt
		var nxt := pos + v * dt
		var rising := v.y > 0.0
		var hit: Dictionary = p._ray(pos, nxt)
		t += dt
		if not hit.is_empty() and not (rising and hit.normal.y > 0.5):
			return {"point": hit.position, "n": hit.normal, "t": t}
		pos = nxt
	return {"point": pos, "n": Vector3.ZERO, "t": t}


func _show_aim(sol: Dictionary) -> void:
	var p := player
	p._aim_root.visible = true
	p._aim_root.global_transform = Transform3D.IDENTITY
	var col := Color(1.0, 0.45, 0.3, 0.85) if sol.kind in ["prey", "lock"] else (Color(1.0, 0.85, 0.3, 0.85) if sol.kind == "ledge" else Color(0.45, 1.0, 0.55, 0.8))
	(p._aim_ring.material_override as StandardMaterial3D).albedo_color = col
	var pt: Vector3 = sol.point
	p._aim_ring.global_transform = Transform3D(Basis().scaled(Vector3(0.16, 0.004, 0.16)), pt + Vector3.UP * 0.006)
	var start: Vector3 = p.global_position + Vector3.UP * 0.12
	var dots: Array = p._aim_dots
	for k in dots.size():
		var tt: float = sol.t * float(k + 1) / (dots.size() + 1)
		var v: Vector3 = sol.vel
		dots[k].global_position = start + v * tt + Vector3.DOWN * 0.5 * CatPlayer.G * tt * tt
		dots[k].visible = true


## both fore paws rake down onto it: two claw streaks + red bits + scratch lines
func _slam_fx(n: Node3D) -> void:
	var p := player
	var fwd: Vector3 = -p.global_transform.basis.z
	var right: Vector3 = p.global_transform.basis.x
	var top := n.global_position + Vector3.UP * 0.1 * float(n.get("s") if "s" in n else 1.0)
	for sd in [-1.0, 1.0]:
		var a: Vector3 = top + right * sd * 0.05 + Vector3.UP * 0.12 - fwd * 0.04
		var b: Vector3 = top + right * sd * 0.035 + fwd * 0.03
		SlashFx.streak(p, a, b, fwd * 0.03, Color(1.0, 0.8, 0.75))
	SlashFx.sparks(p, top, Vector3.UP, true, 14)
	SlashFx.wound(n, top, Vector3.UP, fwd)
