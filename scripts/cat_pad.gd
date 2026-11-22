class_name CatPad
extends RefCounted
## gamepad reader for the cat (xbox layout names, works for any pad godot maps: ps, switch pro, 8bitdo...).
## cat_player._read_input() merges this with the keyboard, so every action has a button:
##   left stick   move. how far you push = how fast: a nudge is a slow walk, half way a walk, full tilt a trot
##   right stick  look / camera
##   L3 (click)   run: canter. click again while running = full gallop (same as double tapping shift)
##   A            same as space: tap hop, hold higher hop, hold long = pounce + aim line, wall kick   B   dodge
##   X            interact: scratch (hold at a post / wall), drop what's in your mouth
##   Y            meow
##   RT           swat (alternates paws), hold = hook with your claws
##   LT           grab / hold in your mouth
##   RB (hold)    crouch / sneak
##   R3 (click)   lock on (rat pit only)
##   LB (hold)    cat vision: lights up puzzles, prey, cats, things to climb or knock off
##   d-pad left   first / third person
## deadzones are radial with the range rescaled past them, so the slowest creep is right at the edge
## of the deadzone instead of jumping to 20 percent speed.

const MOVE_DEADZONE := 0.16
const LOOK_DEADZONE := 0.12
const OUTER := 0.94            # past this counts as full tilt (worn sticks never quite reach 1.0)
const TRIGGER_ON := 0.35
const TRIGGER_OFF := 0.2       # a bit of hysteresis so a half pulled trigger doesn't chatter
const LOOK_YAW_RATE := 3.4     # rad/s at full tilt
const LOOK_PITCH_RATE := 2.2
const LOOK_EXPO := 1.7         # response curve: fine aim near the centre, fast turns at the edge
const LOOK_BOOST := 1.6        # held at full tilt for a bit, the turn speeds up to this x (fast 180s)
const LOOK_BOOST_AFTER := 0.35

static var device := -1        # the pad in use (first connected one)
static var last_used_pad := false   # last real input came from the pad (for hud hints)


## tests: a fake pad. {"axes": {JoyAxis: value}, "buttons": {JoyButton: true}}. empty = real hardware
static var sim := {}


## axes that have been seen resting near centre on the current device. an axis only counts once it
## has been armed: wheels, flight sticks, throttles, headsets and unmapped pads often report an axis
## parked at -1 / +1 forever (e.g. a throttle on the "right stick y" slot), which used to read as
## the right stick held full up = the camera constantly looking up. a real stick rests at centre
## the moment you let go, so it arms on the first frame and nothing changes for real pads.
const ARM_REST := 0.25
static var _armed := {}
static var _armed_dev := -2


## forget which axes are armed (new device, or tests swapping the fake pad)
static func rearm() -> void:
	_armed.clear()
	_armed_dev = -2


static func _raw_axis(d: int, a: JoyAxis) -> float:
	if not sim.is_empty():
		return sim.get("axes", {}).get(a, 0.0)
	return Input.get_joy_axis(d, a)


static func _axis(d: int, a: JoyAxis) -> float:
	if d != _armed_dev:
		_armed.clear()
		_armed_dev = d
	var v := _raw_axis(d, a)
	if not _armed.get(a, false):
		# triggers rest at 0 (or -1 on some raw drivers), sticks rest at 0
		var trig := a == JOY_AXIS_TRIGGER_LEFT or a == JOY_AXIS_TRIGGER_RIGHT
		if (v < ARM_REST) if trig else (absf(v) < ARM_REST):
			_armed[a] = true
		else:
			return 0.0
	return v


static func _dev() -> int:
	if not sim.is_empty():
		return 0
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		device = -1
	elif not pads.has(device):
		# prefer a real gamepad (one godot has a mapping for) over wheels / hotas / odd hid devices
		device = pads[0]
		for p in pads:
			if Input.is_joy_known(p):
				device = p
				break
	return device


static func connected() -> bool:
	return _dev() >= 0


## radial deadzone with rescale: |out| goes 0..1 smoothly from the deadzone edge to OUTER
static func shape(raw: Vector2, dz: float) -> Vector2:
	var m := raw.length()
	if m <= dz:
		return Vector2.ZERO
	var k := clampf((m - dz) / (OUTER - dz), 0.0, 1.0)
	return raw / m * k


static func stick(left: bool) -> Vector2:
	var d := _dev()
	if d < 0:
		return Vector2.ZERO
	var ax := JOY_AXIS_LEFT_X if left else JOY_AXIS_RIGHT_X
	var ay := JOY_AXIS_LEFT_Y if left else JOY_AXIS_RIGHT_Y
	var raw := Vector2(_axis(d, ax), _axis(d, ay))
	return shape(raw, MOVE_DEADZONE if left else LOOK_DEADZONE)


## move stick in the game's convention: y+ = forward
static func move() -> Vector2:
	var s := stick(true)
	return Vector2(s.x, -s.y)


static var _trig := [false, false]


static func trigger(right: bool) -> bool:
	var d := _dev()
	if d < 0:
		return false
	var v := _axis(d, JOY_AXIS_TRIGGER_RIGHT if right else JOY_AXIS_TRIGGER_LEFT)
	var i := 1 if right else 0
	_trig[i] = v > (TRIGGER_OFF if _trig[i] else TRIGGER_ON)
	return _trig[i]


static func btn(b: JoyButton) -> bool:
	var d := _dev()
	if not sim.is_empty():
		return sim.get("buttons", {}).get(b, false)
	return d >= 0 and Input.is_joy_button_pressed(d, b)


static var _look_full_t := 0.0


## camera turn for this frame (rad): x = yaw, y = pitch. called at render rate so it's as smooth as the mouse
static func look_delta(dt: float) -> Vector2:
	var s := stick(false)
	var m := s.length()
	if m <= 0.0:
		_look_full_t = 0.0
		return Vector2.ZERO
	last_used_pad = true
	var c := s / m * pow(m, LOOK_EXPO)
	# horizontal full tilt held: ramp up so a full turn doesn't take forever
	_look_full_t = _look_full_t + dt if absf(s.x) > 0.9 else 0.0
	var boost := lerpf(1.0, LOOK_BOOST, clampf((_look_full_t - LOOK_BOOST_AFTER) / 0.3, 0.0, 1.0))
	return Vector2(-c.x * LOOK_YAW_RATE * boost * dt, -c.y * LOOK_PITCH_RATE * dt)


# ---- run toggle on L3 (canter, click again = gallop) ----
static var _l3_prev := false
static var _run := 0           # 0 off, 1 canter, 2 gallop


## reads every button into the same dict shape cat_player uses for the keyboard
static func read() -> Dictionary:
	if not connected():
		_run = 0
		return {}
	var mv := move()
	var l3 := btn(JOY_BUTTON_LEFT_STICK)
	if l3 and not _l3_prev:
		_run = mini(_run + 1, 2) if mv.length() > 0.5 else 1
	_l3_prev = l3
	# let off the stick (or stop pushing forward-ish hard) and the run ends, like letting go of shift
	if mv.length() < 0.5:
		_run = 0
	var d := {
		"move": mv,
		"canter": _run == 1,
		"sprint": _run == 2,
		"crouch": btn(JOY_BUTTON_RIGHT_SHOULDER),
		"jump": btn(JOY_BUTTON_A),
		"dash": btn(JOY_BUTTON_B),
		"interact": btn(JOY_BUTTON_X),
		"meow": btn(JOY_BUTTON_Y),
		"toggle_view": btn(JOY_BUTTON_DPAD_LEFT),
		"swat": trigger(true),
		"grab": trigger(false),
		"lock_on": btn(JOY_BUTTON_RIGHT_STICK),
		"vision": btn(JOY_BUTTON_LEFT_SHOULDER),
	}
	for k in d:
		if typeof(d[k]) == TYPE_BOOL and d[k]:
			last_used_pad = true
	if mv != Vector2.ZERO:
		last_used_pad = true
	return d


## keyboard + pad in one dict: buttons OR together, the bigger move vector wins (so a resting stick
## never cancels the keys), and the run flags come from whichever is actually driving
static func merge(kb: Dictionary, pad: Dictionary) -> Dictionary:
	if pad.is_empty():
		return kb
	var out := kb.duplicate()
	for k in pad:
		if typeof(pad[k]) == TYPE_BOOL:
			out[k] = out.get(k, false) or pad[k]
	var km: Vector2 = kb.get("move", Vector2.ZERO)
	var pm: Vector2 = pad.move
	if pm.length() > km.length():
		out.move = pm
		out.canter = pad.canter
		out.sprint = pad.sprint
	return out
