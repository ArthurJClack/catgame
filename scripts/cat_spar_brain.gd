class_name CatSparBrain
extends RefCounted
## the practice cat's head: drives a bot CatPlayer with the normal controls (its CatSpar.filter
## calls think() every tick and the result is the bot's input). while you're locked on to it it
## squares up, keeps a swat's distance, bops you (strings of swats, a held rake now and then, the
## odd pounce or grab) and dodges some of yours. when you're not playing it just sits there
## watching you. `style` pins one behaviour for tests / films: "auto", "idle", "dodge" (dodges
## every swat it sees coming), "script" (plays `plan` = [[t, action], ...] once; actions: swat,
## rake, pounce, grab, dodge).

var spar: CatSpar
var style := "auto"
var skill := 0.5              # 0..1: how often it dodges what it sees coming
var plan: Array = []
var rng := RandomNumberGenerator.new()

var _t := 0.0
var _next := 0.8
var _queue: Array = []        # actions still to throw in this string
var _qt := 0.0
var _press := {}              # input -> ticks left held
var _hold := {}               # input -> seconds left held
var _read_t := -1.0


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
	if style == "idle":
		return d
	# only plays while you're locked on to it (or a test / film says so)
	var os := CatSpar.spar_of(opp)
	var playing: bool = style != "auto" or (os != null and os.playmate() == p)
	if not playing:
		if dist > 4.0:
			d.yaw = p.yaw
		return d
	var mv := Vector2.ZERO
	if style != "script" and spar.stun <= 0.0:
		if dist > 0.95:
			mv.y = 1.0
		elif dist < 0.5:
			mv.y = -0.7
	match style:
		"dodge":
			_dodge_read(opp, 1.0)
		"script":
			for s in plan.duplicate():
				if _t >= float(s[0]):
					plan.erase(s)
					_queue.append(s[1])
		"auto":
			_dodge_read(opp, skill)
			if _queue.is_empty() and _t >= _next and dist < 1.2 and spar.stun <= 0.0:
				_next = _t + rng.randf_range(0.5, 1.2)
				var r := rng.randf()
				if r < 0.45:
					_queue = ["swat", "swat"]
				elif r < 0.65:
					_queue = ["swat", "swat", "swat"]
				elif r < 0.75:
					_queue = ["rake"]
				elif r < 0.87:
					_queue = ["grab"]
				else:
					_queue = ["pounce"]
	if not _queue.is_empty():
		_qt -= dt
		if _qt <= 0.0:
			var a: String = _queue.pop_front()
			_act(a)
			_qt = 0.3
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
	if d.get("side_l", false):
		mv = Vector2(-1, 0)
		d.erase("side_l")
	d.move = mv
	return d


## the other cat is winding up a swat: sometimes side step it (the normal dodge)
func _dodge_read(opp: Node3D, chance: float) -> void:
	var c = opp.get("combat")
	if c == null:
		return
	var winding: bool = c.atk in ["swat", "rake"] and c.atk_phase == CatCombat.A_WIND
	if winding and _read_t < 0.0:
		_read_t = 0.0
		if rng.randf() < chance:
			_act("dodge")
	elif not winding:
		_read_t = -1.0


func _act(a: String) -> void:
	match a:
		"swat":
			_press["paw_l" if rng.randf() < 0.5 else "paw_r"] = 2
		"rake":
			_hold["paw_r"] = CatCombat.HOLD_T + CatCombat.RAKE_EVERY * 2.5
		"pounce":
			_hold["pounce"] = 0.35
		"grab":
			_hold["grab"] = 0.6
		"dodge":
			_hold["side_l"] = 0.05
			_press["dash"] = 3
