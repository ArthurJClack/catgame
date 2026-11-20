class_name CatCombat
extends Node
## paw combat for the player cat. each mouse button is one fore paw:
##
##   tap left / right mouse   -> SWAT with that paw (left paw / right paw, not random any more)
##   hold one button          -> RAKE: that paw keeps raking at whatever is in front, a swipe every
##                               RAKE_EVERY s, each one cheap on damage and stamina. with nothing to
##                               rake in reach it's the old claw hold instead (hook + drag things,
##                               drag claw marks down surfaces)
##   both at once             -> a swat each (the second one buffered)
##   hold space (pounce)       -> POUNCE, the one and only pounce (see below). the player turns
##                               tap / hold / long hold of space into hop / big hop / pounce
##                               (cat_player._space_filter), bots pass `pounce` directly
##   grab button (g / mouse5, pad Y) -> GRIP: a quick committed reach (~0.16 s, all four feet
##                               stay down, no rearing up), both fore paws clamp on the target and
##                               keep holding it while the button is held: claws squeezing + bites every
##                               GRIP_TICK s. a cat needs a free fore paw to walk, so while it holds
##                               it can't move, hop or dodge. let go and you're free again. nothing
##                               in reach = it grabs at air and recovers. the held one struggles
##                               and breaks out after a while (rat break_t), holding drains
##                               stamina and the grip slips when the bar runs dry
##
## POUNCE: holding space past the hop drops the cat into the pounce crouch, winding up (bum
## wiggle) while you aim with the mouse; a dense dotted line shows the exact path. let go and it
## launches: a free ballistic projectile, low and mostly forward (POUNCE_LIFT, the view pitch only
## tilts it a little, capped at POUNCE_EL_MAX), speed from how long it wound up, no air steering.
## it soft locks: prey / rats near where the arc comes down, the tab lock-on target
## (player.lock_target) and ledges the arc would smack into just under the top all bend the launch
## so it comes down exactly on them, and moving ones are LED (_lead_on: velocity x flight time,
## iterated). on touch down it sticks the landing: no slide, no extra steps (player.stick_armed /
## land_stick, then the committed "land" recovery), and the forepaws pin whatever is under them.
## a paw press while aiming calls it off.
##
## COMMITMENT (souls style): every attack is a move with WIND (wind up) -> ACTIVE (the paw is
## out) -> RECOVER phases (MOVES). once it starts you're in it: wasd only creeps (move_scale),
## the body can barely turn (turn_cap: tracks a little in the wind up, frozen while the paw is
## out), no jumping / hopping / leaping / running / scratching, and a dodge pressed mid attack
## waits for the move's cancel point (can_dodge) and then rolls straight out of the recovery.
## a paw pressed mid attack is buffered (BUFFER) and comes out at the chain point, so mashing
## left / right strings swats together at a fixed rhythm instead of ignoring clicks. getting hit
## in the wind up staggers you out of it (the paw never lands). rakes are the same thing on a
## loop, the grab's reach is committed too (let go mid reach and it still finishes, then
## recovers), and a stuck pounce landing has its own recovery ("land").
##
## damage (souls rat take_hit): swat 1, rake 0.5 (half poise), grip slam 1.5 heavy, grip tick 0.5.
## all of it x2 from behind, so getting round a rat and grabbing it is the big play.

enum { NONE, RAKE, CLAW, SPENT }
enum { G_OFF, G_REACH, G_HOLD, G_AIM }

const CHORD_WIN := 0.0        # swat comes out on the press (the pounce moved to space, no chord to wait for)
const HOLD_T := 0.28          # held this long = rake / claw hold
const RAKE_EVERY := 0.24      # one rake per this (the fp swat anim can restart from 0.22 s)
const RAKE_DMG := 0.5
const RAKE_POISE := 0.5       # rakes stagger half as fast as swats
const GRIP_REACH_T := 0.16    # the paws reach out before they clamp down
const GRIP_REACH := 0.6
const GRIP_SLAM_DMG := 1.5
const GRIP_TICK := 0.4
const GRIP_TICK_DMG := 0.5
const GRAB_DIST := 0.5        # target this close when the reach ends = grab it
const POUNCE_WIND_T := 0.7    # crouched this long = full power
const POUNCE_SPD_MIN := 2.4   # m/s off the hind legs, no wind up
const POUNCE_SPD_MAX := 6.2   # full wind up (~1.8 m up / ~3.6 m out, real cat numbers)
const POUNCE_LIFT := 0.3      # rad: launch angle with the view level (mostly forward, a low arc)
const POUNCE_PITCH := 0.35    # how much looking up / down tilts it
const POUNCE_EL_MIN := 0.2
const POUNCE_EL_MAX := 0.62   # never a high lob: that's the q leap's job
const POUNCE_RANGE := 3.6     # soft lock reach (horizontal)
const MAGNET_R := 0.55        # prey this close to where the free arc lands gets locked

const STRIKE_T := 0.12        # click -> paw lands (cat_player._do_swat impact timer, rig whip at ~0.12)
const LUNGE_FROM := 0.35      # into the wind up the hind legs push: the lunge starts here (fraction)
const LUNGE_STOP := 0.24      # stops this short of the target's near side (m), never shoves into it
const BUFFER := 0.4           # a paw / dodge pressed mid attack waits this long for its slot
const DODGE_BUFFER := 0.5
enum { A_OFF, A_WIND, A_ACTIVE, A_RECOVER }
## wind / active / recover: phase lengths (s). chain: into the recovery, the next attack may start.
## cancel: into the recovery, a dodge may roll out of it. move / turn: per phase (wind, active,
## recover) wasd scale and body turn rate (rad/s). plant: how hard the feet brake per phase
const MOVES := {
	"swat": {"wind": STRIKE_T, "active": 0.06, "recover": 0.24, "chain": 0.10, "cancel": 0.14, "lunge": 1.5,
		"move": [0.3, 0.1, 0.5], "turn": [3.0, 0.0, 2.0], "plant": [5.0, 7.0, 14.0]},
	"rake": {"wind": STRIKE_T, "active": 0.04, "recover": 0.20, "chain": 0.08, "cancel": 0.12, "lunge": 1.0,
		"move": [0.25, 0.1, 0.4], "turn": [3.0, 0.0, 1.5], "plant": [5.0, 7.0, 14.0]},
	"grab_out": {"wind": 0.0, "active": 0.0, "recover": 0.26, "chain": 0.18, "cancel": 0.16,
		"move": [0.0, 0.0, 0.2], "turn": [0.0, 0.0, 1.5], "plant": [0.0, 0.0, 8.0]},
	"land": {"wind": 0.0, "active": 0.0, "recover": 0.45, "chain": 0.3, "cancel": 0.25,
		"move": [0.0, 0.0, 0.15], "turn": [0.0, 0.0, 1.5], "plant": [0.0, 0.0, 12.0]},
}

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
var _rel_t := -1.0
var _reach_rel := false        # let go during the (committed) reach
var grab_mode := false        # this grip came from the grab button (else it's the pounce crouch)
var _grab_prev := false
var _grab_pending := false
var _pounce_prev := false
var _pounce_pending := false
var _seen := {}               # instance id -> [last position, estimated velocity] for lead aiming
# the committed move ("" = free) and its buffers
var atk := ""
var atk_phase := A_OFF
var atk_t := 0.0
var atk_paw := 0
var buf_paw := -1
var buf_rake := false
var buf_t := 0.0
var dodge_buf := 0.0
var interrupts := 0
var atk_target: Node3D = null # what the strike went for (lunge aims at it, stops short of it)
var lunge_d := 0.0            # how far the last lunge carried (tests)
var _lunge_start := Vector3.ZERO
var clock := 0.0              # combat time, for tests (fire_clock = when the last strike started)
var fire_clock := 0.0
var dodge_cancels := 0
var pounce := {}               # current aim solve: vel, point, kind, ok, t
var pounces := 0
# blend weights the player hands to the rig / fp paws
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
	return grip_phase != G_OFF or mode[0] == RAKE or mode[1] == RAKE or atk != ""


# ------------------------------------------------------------------ commitment

## in the middle of an attack (any phase)
func committed() -> bool:
	return atk != ""


## a new attack may start: free, or far enough into the recovery to chain
func atk_free() -> bool:
	return atk == "" or (atk_phase == A_RECOVER and atk_t >= MOVES[atk].chain)


## a dodge may come out now
func can_dodge() -> bool:
	return atk == "" or (atk_phase == A_RECOVER and atk_t >= MOVES[atk].cancel)


func move_scale() -> float:
	return 1.0 if atk == "" else MOVES[atk].move[atk_phase - 1]


func turn_cap() -> float:
	return INF if atk == "" else MOVES[atk].turn[atk_phase - 1]


## 0..1 how much the body gathers low into the strike (rig crouch): chest drops in the wind up
func gather_w() -> float:
	if not atk in ["swat", "rake"]:
		return 0.0
	match atk_phase:
		A_WIND:
			return 0.4 * smoothstep(0.0, MOVES[atk].wind, atk_t)
		A_ACTIVE:
			return 0.4
		A_RECOVER:
			return 0.4 * (1.0 - smoothstep(0.0, MOVES[atk].recover, atk_t))
	return 0.0


func phase_name() -> String:
	return ["", "wind", "active", "recover"][atk_phase] if atk != "" else ""


func start_move(kind: String, paw := 0) -> void:
	atk = kind
	atk_paw = paw
	atk_t = 0.0
	var m: Dictionary = MOVES[kind]
	atk_phase = A_WIND if m.wind > 0.0 else (A_ACTIVE if m.active > 0.0 else A_RECOVER)


## stuck a pounce landing: legs soak it up before anything else can happen
func land_recover() -> void:
	start_move("land")


## dodge pressed: rolls now if allowed, else waits for the cancel point
func dodge_pressed() -> bool:
	if can_dodge():
		_end_move()
		return true
	dodge_buf = DODGE_BUFFER
	return false


## hit while attacking: a strike still winding up never lands
func interrupt() -> void:
	if atk == "":
		return
	if atk_phase == A_WIND and atk in ["swat", "rake"]:
		player._swat_hit_t = -1.0
	interrupts += 1
	_end_move()


func _end_move() -> void:
	atk = ""
	atk_phase = A_OFF
	atk_t = 0.0
	buf_paw = -1


func _atk_step(dt: float) -> void:
	var p := player
	clock += dt
	buf_t -= dt
	if buf_t <= 0.0:
		buf_paw = -1
	dodge_buf = maxf(dodge_buf - dt, 0.0)
	if atk != "":
		var m: Dictionary = MOVES[atk]
		atk_t += dt
		if atk_phase == A_WIND and atk_t >= m.wind:
			atk_t -= m.wind
			atk_phase = A_ACTIVE if m.active > 0.0 else A_RECOVER
		if atk_phase == A_ACTIVE and atk_t >= m.active:
			atk_t -= m.active
			atk_phase = A_RECOVER
		if atk_phase == A_RECOVER and atk_t >= m.recover:
			_end_move()
	if atk != "" and p.is_on_floor():
		var m2: Dictionary = MOVES[atk]
		var lv: float = m2.get("lunge", 0.0)
		var lunging: bool = lv > 0.0 and ((atk_phase == A_WIND and atk_t >= m2.wind * LUNGE_FROM) or atk_phase == A_ACTIVE)
		if lunging:
			# the lunge: the hind legs drive the body forward into the strike, onto the target
			var fwd: Vector3 = -p.global_transform.basis.z
			var room := 9.0
			if is_instance_valid(atk_target):
				var to: Vector3 = atk_target.global_position - p.global_position
				to.y = 0.0
				var rad: float = 0.16 * float(atk_target.get("s")) if "s" in atk_target else 0.06
				room = to.length() - rad - LUNGE_STOP
				if to.length() > 0.01:
					fwd = fwd.slerp(to.normalized(), 0.5).normalized()
			var spd := clampf(room / maxf(dt, 0.001), 0.0, lv) if room > 0.0 else 0.0
			p.velocity.x = fwd.x * spd
			p.velocity.z = fwd.z * spd
			lunge_d = Vector2(p.global_position.x - _lunge_start.x, p.global_position.z - _lunge_start.z).length()
		else:
			# feet planted: whatever speed it came in with bleeds off
			var k: float = exp(-float(m2.plant[atk_phase - 1]) * dt)
			p.velocity.x *= k
			p.velocity.z *= k
	if dodge_buf > 0.0 and can_dodge():
		dodge_buf = 0.0
		if atk != "":
			dodge_cancels += 1
		_end_move()
		p.dash.press()
		return
	if buf_paw >= 0 and atk_free() and grip_phase == G_OFF and not p.dash.busy():
		var i := buf_paw
		buf_paw = -1
		if not _fire(i, buf_rake) and buf_rake:
			mode[i] = SPENT


func tick(dt: float, l: bool, r: bool, grab := false, pounce := false) -> void:
	var p := player
	var now := [l, r]
	var pressed := [l and not down[0], r and not down[1]]
	_atk_step(dt)
	# grab button: reach out and pin whatever's in front with both paws, held as long as it's held.
	# pressed mid swat it waits (while still held) for the swat's recovery to allow it
	if grab and not _grab_prev:
		_grab_pending = true
	if not grab:
		_grab_pending = false
	_grab_prev = grab
	if _grab_pending and grip_phase == G_OFF and _can_grip():
		_grab_pending = false
		_grip_start(true)
	# pounce (hold space): crouch + wind up + aim, let go to launch. waits out a swat like the grab
	if pounce and not _pounce_prev:
		_pounce_pending = true
	if not pounce:
		_pounce_pending = false
	_pounce_prev = pounce
	if _pounce_pending and grip_phase == G_OFF and _can_grip():
		_pounce_pending = false
		_grip_start(false)
	for i in 2:
		if pressed[i]:
			age[i] = 0.0
			fired[i] = false
			mode[i] = NONE
			rake_t[i] = 0.0
	if grip_phase == G_REACH:
		# the reach is committed: letting go now still finishes it (see _grip_step)
		if not grab:
			_reach_rel = true
		_grip_step(dt)
	elif grip_phase != G_OFF and grab_mode:
		if grab:
			_grip_step(dt)
		else:
			_grip_end()           # let go of the grab button: let go of it
	elif grip_phase == G_AIM:
		if pressed[0] or pressed[1]:
			_grip_end()           # a paw instead: the pounce is called off
			p._event("pounce called off")
		elif pounce:
			_grip_step(dt)
		else:
			_launch()             # let go of space: go
	if grip_phase == G_OFF:
		for i in 2:
			_paw_step(i, dt, now[i])
	down[0] = l
	down[1] = r
	var hold := grip_phase == G_HOLD
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
			# each rake is its own committed strike: the next comes out at the chain point
			# (wind + active + chain = RAKE_EVERY)
			if atk_free() and buf_paw < 0 and not p.dash.busy():
				if not _fire(i, true):
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
	if not atk_free() or player.dash.busy():
		# mid attack / mid dodge: buffered, comes out at the chain point
		buf_paw = i
		buf_rake = false
		buf_t = BUFFER
		return
	_fire(i, false)


## auto swat (crosshair on something loose): only when nothing else is going on
func auto_swat() -> void:
	if atk == "" and buf_paw < 0:
		_fire(randi() % 2, false)


func _fire(i: int, rake: bool) -> bool:
	if not player.stamina.spend(CatStamina.RAKE if rake else CatStamina.SWAT):
		return false
	if rake:
		rakes += 1
	else:
		swats += 1
	start_move("rake" if rake else "swat", i)
	fire_clock = clock
	player._do_swat(i, rake)
	atk_target = player._swat_prey if is_instance_valid(player._swat_prey) else (player._swat_rb if is_instance_valid(player._swat_rb) else null)
	_lunge_start = player.global_position
	lunge_d = 0.0
	return true


func _can_grip() -> bool:
	var p := player
	return p.is_on_floor() and atk_free() and not (p.climbing or p.clambering or p.mantling or p.scratching or p.charging or p.dash.busy())


# ------------------------------------------------------------------ grip

## grab = the grab button's reach + pin. else both paws: straight into the pounce crouch
func _grip_start(grab: bool) -> void:
	var p := player
	if p.stamina.value <= 0.0:
		return
	# whatever the paws were doing stops: both are needed now
	for i in 2:
		fired[i] = true
		if mode[i] == CLAW and p.clawing:
			p._claw_release()
		mode[i] = NONE
	_end_move()
	_reach_rel = false
	grab_mode = grab
	grip_t = 0.0
	_tick_t = 0.0
	_rel_t = -1.0
	p.charge = 0.0
	if not grab:
		grip_phase = G_AIM
		# space has already been held POUNCE_HOLD to get here: that WAS the wind up, so the
		# pounce is at full power from the first frame of aiming (no second charge to wait out)
		p.charge = 1.0
		grip_target = null
		_seen.clear()
		p._event("pounce crouch")
		return
	grips += 1
	grip_phase = G_REACH
	var t: Dictionary = p._paw_target(GRIP_REACH, 0.6)
	grip_target = t.get("prey") if not t.is_empty() and t.get("prey") != p.carried else null
	grip_point = t.point if not t.is_empty() else p.global_position - p.global_transform.basis.z * 0.24
	p._event("grab!")


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
	if grip_phase == G_REACH:
		if valid:
			grip_point = grip_target.global_position + Vector3.UP * 0.05
		if grip_t >= GRIP_REACH_T:
			var near: bool = valid and grip_target.global_position.distance_to(p.global_position) < GRAB_DIST + 0.16 * float(grip_target.get("s") if "s" in grip_target else 1.0)
			if near:
				p.stamina.spend(CatStamina.GRIP)
				_slam(valid)
			if _reach_rel or not near:
				# let go mid reach, or nothing in reach: it still clamped down (slam and all), now it
				# recovers before it can do anything else
				if not near:
					p._event("grabbed at nothing")
				_grip_end()
				start_move("grab_out")
				return
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
		_track(dt)
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
		grip_target = null       # it got away while you reached
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
	grab_mode = false
	_rel_t = -1.0
	_reach_rel = false
	player.charge = 0.0
	player._aim_root.visible = false
	# a paw still held after the grip is done does nothing until it's pressed again
	for i in 2:
		fired[i] = true
		mode[i] = SPENT


func cancel() -> void:
	if grip_phase != G_OFF:
		_grip_end()
	_end_move()
	dodge_buf = 0.0
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
	var fl := Vector2(sol.vel.x, sol.vel.z)
	p.pounce_yaw = float(sol.get("yaw", atan2(-sol.vel.x, -sol.vel.z) if fl.length() > 0.05 else p.yaw))
	p.pounce_land = sol.point if sol.get("land", false) else Vector3.INF
	if sol.get("land", false):
		p.set_spots(sol.spots)
	else:
		p._clear_spots()
	p._end_pounce_prey()
	var prey: Node = sol.get("prey")
	if prey != null and is_instance_valid(prey) and prey is PhysicsBody3D:
		# flying onto it, not into it: no capsule shove (the paws come down on it, _pin_check)
		p.add_collision_exception_with(prey)
		p.pounce_prey = prey
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
	var el := clampf(asin(clampf(look.y, -1.0, 1.0)) * POUNCE_PITCH + POUNCE_LIFT, POUNCE_EL_MIN, POUNCE_EL_MAX)
	var spd := lerpf(POUNCE_SPD_MIN, POUNCE_SPD_MAX, c)
	var v0 := flat * cos(el) * spd + Vector3.UP * sin(el) * spd
	var tr := _trace(feet, v0)
	var out := _sol(v0, tr, "free", null)
	# soft lock targets, best first
	var tgt := Vector3.INF
	var kind := ""
	var prey: Node3D = null
	var lock: Node3D = p.get("lock_target") if "lock_target" in p else null
	if lock != null and is_instance_valid(lock):
		tgt = _lead_on(lock, feet)
		kind = "lock"
		prey = lock
	if tgt == Vector3.INF:
		var best := MAGNET_R + 0.12 * Vector2(tr.point.x - feet.x, tr.point.z - feet.z).length()
		var eye: Vector3 = p._aim_pos()
		for n in p.get_tree().get_nodes_in_group("prey"):
			if not n is Node3D or n == p.carried or (n.has_method("alive") and not n.alive()):
				continue
			# where it'll be when the free arc comes down
			var q: Vector3 = (n as Node3D).global_position + _vel_of(n) * tr.t
			var dl := Vector2(q.x - tr.point.x, q.z - tr.point.z).length()
			if look.angle_to(q - eye) < 0.12:
				dl = minf(dl, MAGNET_R * 0.5)   # right under the crosshair counts too
			if dl < best and absf(q.y - tr.point.y) < 1.0:
				best = dl
				tgt = _lead_on(n, feet)
				kind = "prey"
				prey = n
	if tgt == Vector3.INF and not tr.land and tr.n.y < 0.5 and tr.n != Vector3.ZERO:
		# smacks into the side of something: if the top is close above, land on top instead,
		# far enough in that the whole cat (hind paws too) is up there
		var nh := Vector3(tr.n.x, 0, tr.n.z).normalized()
		for depth in [0.24, 0.17, 0.12]:
			var top: Dictionary = p._ray(tr.point - nh * depth + Vector3.UP * 0.7, tr.point - nh * depth - Vector3.UP * 0.05)
			if not top.is_empty() and top.normal.y > 0.7 and top.position.y > tr.point.y - 0.02 and p._fits(top.position + Vector3.UP * 0.02):
				tgt = top.position
				kind = "ledge"
				break
	if tgt != Vector3.INF:
		# the snap only counts if the real body really comes down there (traced with the cat's own
		# capsule, so a lip, a crate edge or the prey itself can't knock it off the spot)
		var ex: RID = (prey as PhysicsBody3D).get_rid() if prey is PhysicsBody3D else RID()
		for lift in [0.0, 0.1, 0.22]:
			var sv := _arc_to(feet, tgt, lift)
			if sv.is_empty() or sv.vel.length() > POUNCE_SPD_MAX * 1.2:
				break
			var t2 := _trace(feet, sv.vel, ex)
			if t2.land and Vector2(t2.point.x - tgt.x, t2.point.z - tgt.z).length() < 0.07 and absf(t2.point.y - tgt.y) < 0.08:
				out = _sol(sv.vel, t2, kind, prey if kind != "ledge" else null)
				break
	return out


## a solve: launch velocity + the traced flight (path, where it comes down) + the four paw spots
func _sol(vel: Vector3, tr: Dictionary, kind: String, prey: Node) -> Dictionary:
	var out := {"vel": vel, "point": tr.point, "kind": kind, "ok": true, "t": tr.t, "path": tr.path, "land": tr.land, "prey": prey, "spots": []}
	if tr.land:
		var fl := Vector2(vel.x, vel.z)
		var yaw: float = atan2(-vel.x, -vel.z) if fl.length() > 0.05 else player.yaw
		out.yaw = yaw
		var spots := CatRig.pounce_paw_spots(tr.point, yaw)
		for i in 4:
			var q: Vector3 = spots[i]
			var g: Dictionary = player._ray(q + Vector3.UP * 0.12, q - Vector3.UP * 0.12)
			if not g.is_empty() and g.normal.y > 0.5:
				spots[i] = Vector3(q.x, g.position.y, q.z)
		out.spots = spots
	return out


## how fast something is moving (m/s): its own velocity if it has one, else measured from how far
## it moved since it was last looked at (critters that move themselves by position)
func _vel_of(n: Node) -> Vector3:
	var v := Vector3.ZERO
	if n is RigidBody3D:
		v = (n as RigidBody3D).linear_velocity
	elif n is CharacterBody3D:
		v = (n as CharacterBody3D).velocity
		if v.length() < 0.01:
			v = (n as CharacterBody3D).get_real_velocity()
	if v.length() < 0.01:
		var e: Array = _seen.get(n.get_instance_id(), [])
		if e.size() == 3 and e[2]:
			v = e[1]
	if n.has_method("pinned") and n.pinned():
		return Vector3.ZERO
	v.y = 0.0               # land where it'll be on the ground, not where a hop would take it
	return v


## the estimate for things without a velocity: called every physics tick while aiming
func _track(dt: float) -> void:
	var cands: Array = player.get_tree().get_nodes_in_group("prey")
	var lock: Node3D = player.get("lock_target") if "lock_target" in player else null
	if lock != null and is_instance_valid(lock) and not cands.has(lock):
		cands.append(lock)
	for n in cands:
		if not n is Node3D:
			continue
		var id: int = n.get_instance_id()
		var q: Vector3 = (n as Node3D).global_position
		var e: Array = _seen.get(id, [])
		if e.is_empty():
			_seen[id] = [q, Vector3.ZERO, false]
		else:
			var vm: Vector3 = (q - e[0]) / maxf(dt, 0.001)
			_seen[id] = [q, (e[1] as Vector3).lerp(vm, 0.3), true]


## lead a moving target: solve the arc to it, see how long the flight takes, aim at where it'll
## be by then, repeat (converges in a couple of rounds at cat speeds)
func _lead_on(n: Node3D, feet: Vector3) -> Vector3:
	var v := _vel_of(n)
	var pt := _paws_on(n, feet)
	if v.length() < 0.05 or pt == Vector3.INF:
		return pt
	var t := 0.0
	for k in 3:
		var sv := _arc_to(feet, pt)
		if sv.is_empty():
			return Vector3.INF
		t = sv.t
		pt = _paws_on(n, feet, v * t)
		if pt == Vector3.INF:
			return pt
	# keep it on the ground out there (it may run onto a step or off an edge)
	var g: Dictionary = player._ray(pt + Vector3.UP * 0.4, pt - Vector3.UP * 0.6)
	if not g.is_empty() and g.normal.y > 0.7:
		pt.y = g.position.y
	return pt


## where the forepaws should come down on something: just short of it, on its side facing you
## (ahead = how far it will have moved by then)
func _paws_on(n: Node3D, feet: Vector3, ahead := Vector3.ZERO) -> Vector3:
	var q := n.global_position + ahead
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
func _arc_to(feet: Vector3, tgt: Vector3, lift := 0.0) -> Dictionary:
	var dh := tgt.y - feet.y
	var flat := Vector3(tgt.x - feet.x, 0, tgt.z - feet.z)
	var d := flat.length()
	if d > POUNCE_RANGE + 0.2:
		return {}
	var apex := maxf(dh, 0.0) + 0.12 + 0.09 * d + lift
	var vy := sqrt(2.0 * CatPlayer.G * apex)
	var t := vy / CatPlayer.G + sqrt(2.0 * maxf(apex - dh, 0.0) / CatPlayer.G)
	var vh := d / maxf(t, 0.05)
	var hd := flat / d if d > 0.001 else Vector3.ZERO
	# the flight is stepped (v -= g dt, then x += v dt), which sinks g dt t / 2 below the smooth
	# parabola: half a tick of extra up speed puts the stepped arc right back on it, so it lands
	# on the spot instead of a few cm short
	vy += CatPlayer.G * 0.5 / float(Engine.physics_ticks_per_second)
	return {"vel": hd * vh + Vector3.UP * vy, "t": t}


## fly the cat's own capsule through the world exactly the way the physics will (same tick, same
## stepping, same collision shape): where it comes down, what it hits, and every point on the way.
## ex = a body to fly through (the prey being pounced on)
func _trace(feet: Vector3, v0: Vector3, ex := RID()) -> Dictionary:
	var p := player
	var pos := feet
	var v := v0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var t := 0.0
	var path := PackedVector3Array([feet])
	var prm := PhysicsTestMotionParameters3D.new()
	prm.margin = p.safe_margin
	prm.max_collisions = 1
	if ex.is_valid():
		prm.exclude_bodies = [ex]
	var res := PhysicsTestMotionResult3D.new()
	var basis: Basis = p.global_transform.basis
	var floor_y := cos(p.floor_max_angle)
	var rid: RID = p.get_rid()
	while t < 2.5:
		v.y -= CatPlayer.G * dt
		var mo := v * dt
		t += dt
		prm.from = Transform3D(basis, pos)
		prm.motion = mo
		if PhysicsServer3D.body_test_motion(rid, prm, res):
			var n := res.get_collision_normal()
			# rising it can't land on a floor (that's the one it's leaving), only hit walls / ceilings
			if not (v.y > 0.0 and n.y > 0.5):
				pos += res.get_travel()
				path.append(pos)
				if n.y >= floor_y:
					return {"point": pos, "n": n, "t": t, "path": path, "land": true}
				return {"point": res.get_collision_point(), "n": n, "t": t, "path": path, "land": false}
		pos += mo
		path.append(pos)
	return {"point": pos, "n": Vector3.ZERO, "t": t, "path": path, "land": false}


func _show_aim(sol: Dictionary) -> void:
	var p := player
	p._aim_root.visible = true
	p._aim_root.global_transform = Transform3D.IDENTITY
	var col := Color(1.0, 0.45, 0.3, 0.85) if sol.kind in ["prey", "lock"] else (Color(1.0, 0.85, 0.3, 0.85) if sol.kind == "ledge" else Color(0.45, 1.0, 0.55, 0.8))
	(p._aim_ring.material_override as StandardMaterial3D).albedo_color = col
	var pt: Vector3 = sol.point
	p._aim_ring.global_transform = Transform3D(Basis().scaled(Vector3(0.16, 0.004, 0.16)), pt + Vector3.UP * 0.006)
	# the line IS the flight: the traced feet path (the same steps and collisions the real
	# jump takes), laid out evenly along its length so it reads as one line from paws to circle
	var path: PackedVector3Array = sol.path
	var dots: Array = p._aim_dots
	var cum := PackedFloat32Array([0.0])
	for k in range(1, path.size()):
		cum.append(cum[k - 1] + path[k].distance_to(path[k - 1]))
	var total: float = cum[cum.size() - 1]
	var j := 1
	for k in dots.size():
		var want: float = total * float(k + 1) / float(dots.size())
		while j < path.size() - 1 and cum[j] < want:
			j += 1
		var seg := maxf(cum[j] - cum[j - 1], 0.00001)
		dots[k].global_position = path[j - 1].lerp(path[j], clampf((want - cum[j - 1]) / seg, 0.0, 1.0)) + Vector3.UP * 0.006
		dots[k].visible = path.size() > 1
	# where each paw comes down
	var spots: Array = sol.get("spots", [])
	for i in p._paw_rings.size():
		var r: MeshInstance3D = p._paw_rings[i]
		r.visible = spots.size() == 4
		if r.visible:
			(r.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.95)
			r.global_transform = Transform3D(Basis(Vector3.UP, float(sol.get("yaw", p.yaw))), (spots[i] as Vector3) + Vector3.UP * 0.008)


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
