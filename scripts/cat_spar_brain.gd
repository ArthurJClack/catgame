class_name CatSparBrain
extends RefCounted
## the practice cat's head: drives a bot CatPlayer (its CatSpar.filter calls think() every tick
## and the result is the bot's input). it squares up to you, keeps a bop's distance, throws
## strings and mixups at you, and reads what you're winding up: guards highs, ducks lows and
## highs, counters, breaks throws, kicks like mad in a wrestle. `style` pins one behaviour for
## tests / films: "auto" (sparring partner), "guard", "duck", "idle", "counter", "script"
## (plays `plan` = [[t, action], ...] once, actions: swat, low, lunge, hold, grab, guard, duck,
## side_l, side_r, counter).

var spar: CatSpar
var style := "auto"
var skill := 0.55             # 0..1: how often it reads you right
var plan: Array = []
var rng := RandomNumberGenerator.new()

var _t := 0.0
var _next := 0.6
var _queue: Array = []        # [time, action] for the current string
var _qt := 0.0
var _press := {}              # button -> ticks left held
var _hold := {}               # button -> seconds left held
var _guard_t := 0.0
var _duck_t := 0.0
var _read_seq := ""
var _mash := 0.0


func _init() -> void:
	rng.seed = 7


func think(dt: float) -> Dictionary:
	_t += dt
	var p := spar.player
	var d := {"stamina": false, "move": Vector2.ZERO, "yaw": p.yaw}
	var opp := spar.forced
	if opp == null or not is_instance_valid(opp):
		return d
	var to := CatSpar.pos_of(opp) - p.global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.05:
		d.yaw = atan2(-to.x, -to.z)
	var os := CatSpar.spar_of(opp)
	if style == "idle":
		return d
	if not spar.in_match() and style == "auto":
		# not playing: sit tight, just keep an eye on you when you're close
		if dist > 4.0:
			d.yaw = p.yaw
		return d
	# footsies: hold a bop's distance
	var mv := Vector2.ZERO
	if not spar.busy() and style != "script":
		if dist > 1.05:
			mv.y = 1.0
		elif dist < 0.5:
			mv.y = -0.7
	_guard_t -= dt
	_duck_t -= dt
	match style:
		"guard":
			_guard_t = 1.0
		"duck":
			_duck_t = 1.0
		"counter":
			if os and os.exposed() and os.move != "throw" and spar.counter_rec <= 0.0 and os.move != _read_seq:
				_read_seq = os.move
				_tap("dash", 10)
				_queue = [[0.0, "swat"]]
				_qt = 0.03
		"script":
			for s in plan.duplicate():
				if _t >= float(s[0]):
					plan.erase(s)
					_queue.append([0.0, s[1]])
		"auto":
			_auto(dt, dist, os)
	if style == "counter" and (os == null or not os.exposed()):
		_read_seq = ""
	# wrestle: kick like mad
	if spar.wrestle > 0.0:
		_mash += dt * lerpf(6.0, 11.0, skill)
		if _mash >= 1.0:
			_mash -= 1.0
			_tap("swat", 1)
	# string playback
	if not _queue.is_empty():
		_qt -= dt
		if _qt <= 0.0:
			var a = _queue.pop_front()
			_act(str(a[1]))
			_qt = 0.16 if not _queue.is_empty() else 0.0
	if _guard_t > 0.0 and not spar.busy():
		mv = Vector2(0, -1.0)
	if _duck_t > 0.0:
		d.crouch = true
	for k in _hold.keys():
		_hold[k] -= dt
		d[k] = true
		if _hold[k] <= 0.0:
			_hold.erase(k)
	for k in _press.keys():
		if _press[k] > 0:
			d[k] = true
			_press[k] -= 1
		else:
			_press.erase(k)
	if d.get("fwd_hold", false):
		mv.y = 1.0
	if d.get("side", false):
		mv = Vector2(float(_hold_side), 0.0)
		d.erase("side")
	d.move = mv
	if d.has("swat"):
		d.paw_l = d.swat
		d.erase("swat")
	return d


func _auto(_dt: float, dist: float, os: CatSpar) -> void:
	# read what's coming
	if os and os.exposed() and os.move != _read_seq:
		_read_seq = os.move
		if rng.randf() < skill:
			var lvl: String = CatSpar.MOVES[os.move].lvl
			var r := rng.randf()
			if lvl == "throw":
				if r < 0.5:
					_duck_t = 0.35
				else:
					_tap("grab", 2)
			elif r < 0.22 and spar.counter_rec <= 0.0:
				_tap("dash", 10)
				_queue = [[0.0, "swat"]]
				_qt = 0.02
			elif r < 0.38 and lvl != "low":
				_act("side_l" if rng.randf() < 0.5 else "side_r")
			elif lvl == "low" or (lvl == "high" and r < 0.7):
				_duck_t = 0.45
			else:
				_guard_t = 0.45
	if os == null or not os.exposed():
		_read_seq = ""
	if not spar.fighting() or spar.busy() or not _queue.is_empty():
		return
	if _t < _next:
		return
	_next = _t + rng.randf_range(0.45, 1.1)
	if dist > 1.15:
		return
	var r := rng.randf()
	if r < 0.18:
		_queue = [[0.0, "swat"], [0.0, "swat"], [0.0, "swat"]]
	elif r < 0.32:
		_queue = [[0.0, "swat"], [0.0, "swat"], [0.0, "low"]]
	elif r < 0.44:
		_queue = [[0.0, "low"]]
	elif r < 0.54:
		_queue = [[0.0, "lunge"]]
	elif r < 0.64:
		_queue = [[0.0, "hold"]]
	elif r < 0.74:
		_queue = [[0.0, "grab"]]
	elif r < 0.82:
		_queue = [[0.0, "swat"], [0.0, "grab"]]
	elif r < 0.92:
		_guard_t = 0.7
	else:
		_duck_t = 0.5


func _tap(btn: String, ticks := 2) -> void:
	_press[btn] = ticks


func _act(a: String) -> void:
	match a:
		"swat":
			_tap("swat", 2)
		"low":
			_duck_t = maxf(_duck_t, 0.12)
			_tap("swat", 2)
			_hold["crouch"] = 0.1
		"lunge":
			_hold["fwd_hold"] = 0.08
			_tap("swat", 2)
		"hold":
			_hold["swat"] = CatSpar.HOLD_T + 0.08
		"grab":
			_tap("grab", 2)
		"guard":
			_guard_t = 0.8
		"duck":
			_duck_t = 0.8
		"side_l", "side_r":
			_hold["side"] = 0.06
			_tap("dash", 2)
			_hold_side = -1 if a == "side_l" else 1
		"counter":
			_tap("dash", 10)
			_queue.push_front([0.0, "swat"])
			_qt = 0.03

var _hold_side := 0
