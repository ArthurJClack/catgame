class_name Beast
extends Fauna
## desert + mountain wildlife, on the same Critter / Fauna base as the forest animals (real sizes,
## the same prey interface, panic spreading through the "wild" group, CritterGait legs):
## desert
##   snake     a rattlesnake coiled in the shade of a rock. come close and it rattles and draws its
##             head back, closer still and it strikes (a shove, not a kill). keep bothering it and it
##             slithers off to the next rock
##   scorpion  hides under a rock edge, wanders out a little. a cat nearby gets the tail up + claws
##             open while it backs off; swat at it and it bolts
##   vulture   circles high on the thermals, rocking on its v-shaped wings, now and then lands on the
##             dead tree and hunches there
##   rabbit    (jackrabbit: the forest rabbit with the long ears) + lizard + bird (quail) reused as is
## mountain
##   goat      mountain goats walking the ledges and the upper bench, hopping ledge to ledge. they stare
##             you down and stamp, then move off along their route
##   marmot    grazes by its burrow. the sentry sits up on its rock and scans left and right; anything
##             it spots gets a whistle and the whole colony dives underground (marmot puzzle)
##   pika      tiny, round, sits on the talus going "eep", vanishes between the rocks. huntable
##   eagle     soars over the meadow, stoops at marmots + pikas now and then: everything dives
## ground height comes from `Beast.ground` (the level's terrain), set before any are spawned.

static var ground: Callable
static var sound: BiomeSound

var seg: Array[MeshInstance3D] = []     # snake body pieces (world space)
var seg_p := PackedVector3Array()       # snake joint points, head first
var strikes := 0
var route: Array = []                   # goat: points to walk between (on ledges / the bench)
var route_i := 0
var burrow := Vector3.ZERO              # marmot / pika hole
var sentry := false
var scan_base := 0.0
var noticed := false                    # marmot sentry: spotted the cat this round (the puzzle reads it)
var startled := false                   # marmot sentry: the cat got right up close unseen
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_t := -1.0
var _hop_dur := 0.5
var _rattle_t := 0.0

const SNAKE_N := 10
const SNAKE_SEG := 0.1


const FAR_B := {"snake": 22.0, "scorpion": 8.0, "vulture": 200.0, "eagle": 200.0, "goat": 90.0, "marmot": 40.0, "pika": 16.0, "rabbit": 30.0, "bird": 20.0, "lizard": 14.0}


func _ready() -> void:
	super._ready()
	_hushed = true
	var far: float = FAR_B.get(kind, 30.0)
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for c in nd.get_children():
			stack.append(c)
		if nd is GeometryInstance3D:
			(nd as GeometryInstance3D).visibility_range_end = far
	match kind:
		"snake":
			_set_state("coil", rng.randf_range(2.0, 5.0))
		"scorpion":
			_set_state("hide", rng.randf_range(1.0, 4.0))
		"vulture", "eagle":
			trunk_a = rng.randf() * TAU
			_set_state("soar", rng.randf_range(20.0, 40.0))
		"goat":
			route = get_meta("route", [home])
			route_i = 0
			position = route[0]
			_set_state("stand", rng.randf_range(1.0, 4.0))
			_solid_body(Vector3(0.36, 0.9, 1.25), 0.55)
		"marmot":
			burrow = get_meta("burrow", home)
			sentry = get_meta("sentry", false)
			scan_base = float(get_meta("face", yaw))
			yaw = scan_base
			_set_state("sentry" if sentry else "graze", rng.randf_range(2.0, 5.0))
		"pika":
			burrow = home
			_set_state("sit", rng.randf_range(1.0, 5.0))
			add_to_group("prey")
		"rabbit":
			for e in ears:
				e.scale = Vector3(1.3, 1.8, 1.0)   # jackrabbit ears: radiators for the heat


func _ground_y(x: float, z: float) -> float:
	return float(ground.call(x, z)) if ground.is_valid() else 0.0


func _snap_ground(dt: float, lift := 0.0) -> void:
	position.y = LowPoly.damp(position.y, _ground_y(position.x, position.z) + lift, 18.0, dt)


func _say(clip: String, vol := 1.0, pitch := 1.0) -> void:
	get_tree().call_group("cat_ears", "hear", global_position, vol)
	if sound:
		sound.play(clip, global_position, vol, pitch * rng.randf_range(0.94, 1.06))


func _solid_body(size: Vector3, y: float) -> void:
	solid = AnimatableBody3D.new()
	solid.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = y
	solid.add_child(cs)
	solid.top_level = true
	add_child(solid)


func alarmed(from: Vector3, by: String, src: Node) -> void:
	if src == self or caught or _stun > 0.0:
		return
	var d := Vector2(global_position.x - from.x, global_position.z - from.z).length()
	match kind:
		"marmot":
			if state in ["graze", "sentry", "peek"] and (d < 14.0 or by == "hawk"):
				_dive()
		"pika":
			if state in ["sit", "hop"] and (d < 6.0 or by == "hawk"):
				_set_state("hidden", rng.randf_range(4.0, 8.0))
		"goat", "snake", "scorpion", "vulture", "eagle":
			pass
		_:
			super.alarmed(from, by, src)


# ================================================================== models (real sizes, meters)

func _build_snake() -> void:
	var col := Color(0.62, 0.52, 0.36)
	var dark := Color(0.36, 0.27, 0.18)
	body = _pivot(self, Vector3.ZERO)
	for i in SNAKE_N:
		var m := MeshInstance3D.new()
		m.mesh = LowPoly.box(0.0)
		var w := 0.05 - absf(i - 3.0) * 0.0035 if i > 2 else 0.042 + i * 0.003
		m.material_override = LowPoly.mat(dark if i % 2 == 1 else col)
		m.scale = Vector3(w, w * 0.75, SNAKE_SEG * 1.15)
		m.top_level = true
		add_child(m)
		seg.append(m)
	head = _pivot(self, Vector3.ZERO)
	head.top_level = true
	_p(head, LowPoly.box(0.0), col.darkened(0.1), Vector3(0, 0, -0.025), Vector3(0.05, 0.026, 0.06))
	_p(head, LowPoly.box(0.0), col, Vector3(0, -0.004, -0.06), Vector3(0.034, 0.018, 0.03))
	for s in [-1, 1]:
		_p(head, LowPoly.box(0.0), Color(0.9, 0.7, 0.2), Vector3(s * 0.02, 0.008, -0.04), Vector3.ONE * 0.008)
	# tongue + rattle
	parts["tongue"] = _p(head, LowPoly.box(0.0), Color(0.8, 0.15, 0.2), Vector3(0, -0.006, -0.09), Vector3(0.004, 0.002, 0.03))
	tail = _pivot(self, Vector3.ZERO)
	tail.top_level = true
	for k in 3:
		_p(tail, LowPoly.box(0.0), Color(0.78, 0.7, 0.55).darkened(k * 0.1), Vector3(0, 0, 0.012 + k * 0.014), Vector3(0.018 - k * 0.003, 0.014, 0.012))
	seg_p.resize(SNAKE_N + 1)
	for i in SNAKE_N + 1:
		seg_p[i] = home + Vector3(0, 0, i * SNAKE_SEG)


func _build_scorpion() -> void:
	var col := Color(0.72, 0.6, 0.32)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.box(0.0), col, Vector3(0, 0.012, 0), Vector3(0.024, 0.012, 0.042))
	head = _pivot(body, Vector3(0, 0.012, -0.022))
	_p(head, LowPoly.box(0.0), col.darkened(0.1), Vector3(0, 0, -0.006), Vector3(0.02, 0.01, 0.014))
	for s in [-1, 1]:
		var cl := _pivot(head, Vector3(s * 0.01, 0, -0.01))
		_p(cl, LowPoly.box(0.0), col, Vector3(s * 0.008, 0, -0.012), Vector3(0.006, 0.005, 0.024))
		_p(cl, LowPoly.box(0.0), col.darkened(0.15), Vector3(s * 0.012, 0, -0.03), Vector3(0.012, 0.007, 0.016))
		parts["claw%d" % s] = cl
	# tail: 4 segments curling up over the back, sting at the end
	var prev := _pivot(body, Vector3(0, 0.014, 0.02))
	tail = prev
	for k in 4:
		_p(prev, LowPoly.box(0.0), col.darkened(0.04 * k), Vector3(0, 0, 0.007), Vector3(0.008 - k * 0.001, 0.008, 0.014))
		var nx := _pivot(prev, Vector3(0, 0, 0.014))
		parts["t%d" % k] = prev
		prev = nx
	_p(prev, LowPoly.cone(4), Color(0.25, 0.15, 0.08), Vector3(0, 0, 0.004), Vector3(0.006, 0.012, 0.006), Vector3(PI / 2, 0, 0))
	for k in 8:
		var s := -1.0 if k % 2 == 0 else 1.0
		var lz := -0.012 + (k / 2) * 0.008
		var l := _pivot(body, Vector3(s * 0.012, 0.01, lz))
		_p(l, LowPoly.box(0.0), col.darkened(0.2), Vector3(s * 0.012, -0.005, 0), Vector3(0.022, 0.003, 0.003), Vector3(0, 0, s * 0.5))
		parts["l%d" % k] = l


func _build_raptor(col: Color, pale: Color, span: float, head_col: Color) -> void:
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(6, 4), col, Vector3.ZERO, Vector3(0.2, 0.17, 0.55) * span)
	head = _pivot(body, Vector3(0, 0.03, -0.3) * span)
	_p(head, LowPoly.sphere(5, 4), head_col, Vector3.ZERO, Vector3(0.11, 0.1, 0.13) * span)
	_p(head, LowPoly.cone(4), Color(0.85, 0.75, 0.45), Vector3(0, -0.01, -0.08) * span, Vector3(0.035, 0.06, 0.035) * span, Vector3(-PI / 2 - 0.4, 0, 0))
	tail = _pivot(body, Vector3(0, 0, 0.26) * span)
	_p(tail, LowPoly.box(), col.darkened(0.1), Vector3(0, 0, 0.12) * span, Vector3(0.2, 0.014, 0.26) * span)
	for s in [-1, 1]:
		var w := _pivot(body, Vector3(s * 0.08, 0.03, 0.0) * span)
		_p(w, LowPoly.box(), col, Vector3(s * 0.25, 0, 0.0) * span, Vector3(0.5, 0.02, 0.32) * span)
		var tip := _pivot(w, Vector3(s * 0.5, 0, 0) * span)
		_p(tip, LowPoly.box(), col.darkened(0.15), Vector3(s * 0.22, 0, 0.03) * span, Vector3(0.44, 0.016, 0.26) * span)
		_p(tip, LowPoly.box(0.0), pale, Vector3(s * 0.2, -0.004, 0.08) * span, Vector3(0.36, 0.006, 0.07) * span)
		for f in 4:
			_p(tip, LowPoly.box(0.0), col.darkened(0.3), Vector3(s * 0.46, 0, -0.06 + f * 0.05) * span, Vector3(0.14, 0.008, 0.035) * span, Vector3(0, s * (0.3 - f * 0.2), 0))
		wings.append(w)
		parts["tip%d" % wings.size()] = tip


func _build_vulture() -> void:
	# turkey vulture: 1.7 m span, dark brown-black, pale flight feathers, small bald red head
	_build_raptor(Color(0.16, 0.12, 0.11), Color(0.55, 0.52, 0.5), 1.0, Color(0.7, 0.25, 0.22))


func _build_eagle() -> void:
	# golden eagle: 2 m span, dark brown with a golden nape
	_build_raptor(Color(0.3, 0.2, 0.12), Color(0.36, 0.26, 0.16), 1.15, Color(0.75, 0.55, 0.25))


func _build_goat() -> void:
	var fur := Color(0.9, 0.88, 0.8)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.box(), fur, Vector3(0, 0.82, 0.02), Vector3(0.36, 0.42, 0.95))
	_p(body, LowPoly.box(), fur.darkened(0.04), Vector3(0, 0.9, -0.3), Vector3(0.4, 0.52, 0.42))   # shoulder hump
	_p(body, LowPoly.box(), fur.darkened(0.08), Vector3(0, 0.6, 0.05), Vector3(0.32, 0.14, 0.8))   # shaggy skirt
	head = _pivot(body, Vector3(0, 1.0, -0.5))
	_p(head, LowPoly.box(), fur, Vector3(0, 0.0, -0.12), Vector3(0.16, 0.2, 0.3))
	_p(head, LowPoly.box(), fur.darkened(0.06), Vector3(0, -0.14, -0.18), Vector3(0.08, 0.14, 0.06))   # beard
	for s in [-1, 1]:
		_p(head, LowPoly.cone(4), Color(0.1, 0.09, 0.08), Vector3(s * 0.05, 0.16, -0.06), Vector3(0.03, 0.18, 0.03), Vector3(0.35, 0, 0))
		_p(head, LowPoly.box(0.0), Color(0.05, 0.05, 0.05), Vector3(s * 0.075, 0.03, -0.18), Vector3.ONE * 0.02)
		var e := _pivot(head, Vector3(s * 0.08, 0.1, 0.0))
		_p(e, LowPoly.box(), fur, Vector3(s * 0.04, 0, 0), Vector3(0.08, 0.03, 0.04))
		ears.append(e)
	_p(head, LowPoly.box(0.0), Color(0.15, 0.13, 0.12), Vector3(0, -0.06, -0.27), Vector3(0.07, 0.05, 0.03))
	tail = _pivot(body, Vector3(0, 0.95, 0.5))
	_p(tail, LowPoly.box(), fur, Vector3(0, -0.04, 0.03), Vector3(0.08, 0.1, 0.06))
	var hoof := Color(0.12, 0.1, 0.09)
	_leg(body, Vector3(0.12, 0.62, -0.32), 0.62, 0.09, fur.darkened(0.05), hoof)
	_leg(body, Vector3(-0.12, 0.62, -0.32), 0.62, 0.09, fur.darkened(0.05), hoof)
	_leg(body, Vector3(0.12, 0.62, 0.36), 0.62, 0.09, fur.darkened(0.05), hoof)
	_leg(body, Vector3(-0.12, 0.62, 0.36), 0.62, 0.09, fur.darkened(0.05), hoof)


func _build_marmot() -> void:
	var fur := Color(0.5, 0.4, 0.3)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(7, 5), fur, Vector3(0, 0.12, 0.02), Vector3(0.22, 0.2, 0.42))
	_p(body, LowPoly.sphere(6, 4), Color(0.72, 0.62, 0.48), Vector3(0, 0.08, -0.06), Vector3(0.16, 0.12, 0.2))
	head = _pivot(body, Vector3(0, 0.16, -0.2))
	_p(head, LowPoly.sphere(6, 4), fur.lightened(0.05), Vector3(0, 0, -0.04), Vector3(0.13, 0.11, 0.13))
	_p(head, LowPoly.box(0.0), Color(0.85, 0.82, 0.76), Vector3(0, -0.015, -0.1), Vector3(0.06, 0.04, 0.03))
	for s in [-1, 1]:
		_p(head, LowPoly.box(0.0), Color(0.04, 0.03, 0.03), Vector3(s * 0.04, 0.025, -0.08), Vector3.ONE * 0.015)
		var e := _pivot(head, Vector3(s * 0.045, 0.05, -0.01))
		_p(e, LowPoly.sphere(4, 3), fur.darkened(0.1), Vector3.ZERO, Vector3(0.03, 0.025, 0.012))
		ears.append(e)
	tail = _pivot(body, Vector3(0, 0.12, 0.22))
	_p(tail, LowPoly.box(), fur.darkened(0.2), Vector3(0, 0, 0.08), Vector3(0.05, 0.05, 0.17))
	_leg(body, Vector3(0.07, 0.07, -0.13), 0.07, 0.04, fur.darkened(0.15))
	_leg(body, Vector3(-0.07, 0.07, -0.13), 0.07, 0.04, fur.darkened(0.15))
	_leg(body, Vector3(0.08, 0.07, 0.12), 0.07, 0.05, fur.darkened(0.15))
	_leg(body, Vector3(-0.08, 0.07, 0.12), 0.07, 0.05, fur.darkened(0.15))


func _build_pika() -> void:
	var fur := Color(0.55, 0.5, 0.44)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(6, 4), fur, Vector3(0, 0.045, 0), Vector3(0.09, 0.08, 0.15))
	head = _pivot(body, Vector3(0, 0.06, -0.06))
	_p(head, LowPoly.sphere(5, 4), fur.lightened(0.05), Vector3(0, 0, -0.02), Vector3(0.065, 0.06, 0.06))
	for s in [-1, 1]:
		_p(head, LowPoly.box(0.0), Color(0.04, 0.03, 0.03), Vector3(s * 0.022, 0.012, -0.04), Vector3.ONE * 0.009)
		var e := _pivot(head, Vector3(s * 0.025, 0.03, 0.0))
		_p(e, LowPoly.sphere(4, 3), fur.darkened(0.1), Vector3(0, 0.01, 0), Vector3(0.026, 0.026, 0.008))
		ears.append(e)
	_leg(body, Vector3(0.025, 0.03, -0.04), 0.03, 0.015, fur.darkened(0.1))
	_leg(body, Vector3(-0.025, 0.03, -0.04), 0.03, 0.015, fur.darkened(0.1))
	_leg(body, Vector3(0.03, 0.03, 0.04), 0.03, 0.02, fur.darkened(0.1))
	_leg(body, Vector3(-0.03, 0.03, 0.04), 0.03, 0.02, fur.darkened(0.1))


# ================================================================== behaviour

# ---------------- snake
func _think_snake(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var away: Vector3 = th[4]
	var tongue := parts["tongue"] as Node3D
	tongue.visible = fmod(Time.get_ticks_msec() * 0.001 + home.x, 1.6) < 0.25
	match state:
		"coil", "rattle":
			speed = 0.0
			var to_cat := -away
			if state == "coil":
				if d < 4.0:
					_face(position - away, dt, 0.6)
				if d < 1.7 or (d < 2.6 and cs > 2.0):
					_set_state("rattle", 4.0)
					_say("rattle", 0.8)
				elif state_t < 0.0:
					state_t = rng.randf_range(6.0, 14.0)
					if rng.randf() < 0.3:
						_pick_shade()
			else:
				_face(position + to_cat, dt, 6.0)
				_rattle_t -= dt
				if _rattle_t <= 0.0:
					_rattle_t = 1.1
					_say("rattle", 0.9)
				if d < 0.6:
					_set_state("strike", 0.35)
					_say("hiss", 1.0)
				elif d > 2.4 and state_t < 0.0:
					_set_state("coil", rng.randf_range(4.0, 8.0))
			_coil_pose(dt, state == "rattle")
		"strike":
			var k := 1.0 - clampf(state_t / 0.35, 0.0, 1.0)
			_coil_pose(dt, true, sin(k * PI) * 0.4)
			var c := _cat()
			if c and k > 0.35 and k < 0.6 and d < 0.62 and not has_meta("hit"):
				set_meta("hit", true)
				var v: Vector3 = c.get("velocity")
				c.set("velocity", v + Vector3(-away.x, 0, -away.z) * -2.6 + Vector3(0, 1.2, 0))
				if c.has_method("_event"):
					c.call("_event", "!")
			if state_t < 0.0:
				remove_meta("hit")
				strikes += 1
				if strikes >= 2:
					strikes = 0
					_pick_shade(away)
				else:
					_set_state("rattle", 3.0)
		"slither":
			var dist := _move_toward(target, 0.45, dt, 2.5)
			_slither(dt)
			if dist < 0.1:
				home = target
				_set_state("coil", rng.randf_range(6.0, 12.0))
	_draw_snake()


## somewhere shady to coil up: next to a rock, away from the cat if it's being a pest
func _pick_shade(away := Vector3.ZERO) -> void:
	var best := home
	var bs := -1e9
	for p in ForestLevel.perches:
		var pp: Vector3 = p
		var off := Vector3(pp.x - position.x, 0, pp.z - position.z)
		var dd := off.length()
		if dd < 2.0 or dd > 9.0 or pp.y - _ground_y(pp.x, pp.z) > 1.4:
			continue
		var sc := off.normalized().dot(away) * 3.0 - dd * 0.2 + rng.randf()
		if sc > bs:
			bs = sc
			best = Vector3(pp.x + 0.5, 0, pp.z + 0.5)   # tucked on the shady (south east) side
	target = Vector3(best.x, _ground_y(best.x, best.z), best.z)
	_set_state("slither", 30.0)


func _coil_pose(dt: float, raised: bool, lunge := 0.0) -> void:
	position.y = _ground_y(position.x, position.z)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(fwd.z, 0, -fwd.x)
	var want := PackedVector3Array()
	want.resize(SNAKE_N + 1)
	# head + neck held in an s ready to strike, the rest in a flat spiral under it
	var hy := 0.12 if raised else 0.05
	want[0] = position + fwd * (0.08 + lunge * 0.9) + Vector3(0, hy + lunge * 0.05, 0)
	want[1] = position + fwd * (0.02 + lunge * 0.6) + right * 0.04 + Vector3(0, hy * 0.7, 0)
	want[2] = position - fwd * 0.03 - right * 0.03 + Vector3(0, hy * 0.35, 0)
	for i in range(3, SNAKE_N + 1):
		var a := yaw + (i - 3) * 0.9
		var r := 0.13 - (i - 3) * 0.008
		want[i] = position + Vector3(cos(a) * r, 0.02, sin(a) * r)
	for i in SNAKE_N + 1:
		seg_p[i] = seg_p[i].lerp(want[i], 1.0 - exp(-(30.0 if i < 3 else 6.0) * dt))
	tail.rotation.z = sin(Time.get_ticks_msec() * 0.09) * 0.4 if state == "rattle" or state == "strike" else 0.0


func _slither(dt: float) -> void:
	position.y = _ground_y(position.x, position.z)
	phase += dt * 9.0
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(fwd.z, 0, -fwd.x)
	seg_p[0] = position + right * sin(phase) * 0.05 + Vector3(0, 0.02, 0)
	# follow the leader: every joint keeps its spacing behind the one in front
	for i in range(1, SNAKE_N + 1):
		var dv := seg_p[i] - seg_p[i - 1]
		dv.y = 0
		if dv.length() > SNAKE_SEG:
			seg_p[i] = seg_p[i - 1] + dv.normalized() * SNAKE_SEG
		seg_p[i].y = _ground_y(seg_p[i].x, seg_p[i].z) + 0.02
	tail.rotation.z = 0.0


func _draw_snake() -> void:
	for i in SNAKE_N:
		var a := seg_p[i]
		var b := seg_p[i + 1]
		var m := seg[i]
		var mid := (a + b) * 0.5
		var dv := b - a
		if dv.length() < 0.001:
			continue
		var bas := Basis.looking_at(dv.normalized() if absf(dv.normalized().y) < 0.98 else Vector3.FORWARD, Vector3.UP)
		m.global_transform = Transform3D(bas, mid)
		m.scale = Vector3(m.scale.x, m.scale.y, dv.length() * 1.2)
	var hd := seg_p[0] - seg_p[1]
	if hd.length() > 0.001:
		head.global_transform = Transform3D(Basis.looking_at(hd.normalized() if absf(hd.normalized().y) < 0.98 else Vector3.FORWARD, Vector3.UP), seg_p[0])
	var td := seg_p[SNAKE_N] - seg_p[SNAKE_N - 1]
	if td.length() > 0.001:
		var tb := Basis.looking_at(-td.normalized() if absf(td.normalized().y) < 0.98 else Vector3.FORWARD, Vector3.UP)
		var wiggle := tail.rotation.z
		tail.global_transform = Transform3D(tb.rotated(tb.z, wiggle) if wiggle != 0.0 else tb, seg_p[SNAKE_N] + Vector3(0, 0.02 if state in ["rattle", "strike"] else 0.0, 0))


# ---------------- scorpion
func _think_scorpion(dt: float, th: Array) -> void:
	var d: float = th[0]
	var away: Vector3 = th[4]
	var c := _cat()
	var swat := false
	if c and d < 0.45:
		var cb = c.get("combat")
		swat = bool(c.get("pounce_air")) or (cb != null and str(cb.get("atk")) != "")
	var legs_on := speed > 0.05
	for k in 8:
		var l := parts["l%d" % k] as Node3D
		l.rotation.y = sin(Time.get_ticks_msec() * 0.05 + k * 1.7) * 0.4 if legs_on else 0.0
	match state:
		"hide":
			speed = 0.0
			visible = d < 6.0
			_tail_pose(dt, 0.6)
			if state_t < 0.0 and d > 1.5:
				_pick_wander(0.8)
				_set_state("walk", rng.randf_range(3.0, 7.0))
		"walk":
			visible = true
			var dist := _move_toward(target, 0.12, dt, 6.0)
			_snap_ground(dt)
			_tail_pose(dt, 0.9)
			if dist < 0.04:
				_pick_wander(0.8)
			if d < 0.9:
				_set_state("threat", 2.0)
			elif state_t < 0.0:
				target = home
				_set_state("back", 6.0)
		"threat":
			speed = 0.0
			_face(position - away, dt, 10.0)
			position -= Vector3(-sin(yaw), 0, -cos(yaw)) * 0.03 * dt   # backing off
			_snap_ground(dt)
			_tail_pose(dt, 1.6)
			for s in [-1, 1]:
				(parts["claw%d" % s] as Node3D).rotation.y = LowPoly.damp((parts["claw%d" % s] as Node3D).rotation.y, s * 0.6, 10.0, dt)
			if swat:
				target = position + away * 0.8
				_say("scuttle", 0.4)
				_set_state("bolt", 1.2)
			elif d > 1.4 and state_t < 0.0:
				target = home
				_set_state("back", 6.0)
		"bolt", "back":
			var dist := _move_toward(target, 0.5 if state == "bolt" else 0.14, dt, 12.0)
			_snap_ground(dt)
			_tail_pose(dt, 1.2)
			if dist < 0.04 or state_t < 0.0:
				home = position if state == "bolt" else home
				_set_state("hide", rng.randf_range(4.0, 9.0))


func _tail_pose(dt: float, curl: float) -> void:
	for k in 4:
		var t := parts["t%d" % k] as Node3D
		t.rotation.x = LowPoly.damp(t.rotation.x, curl * (0.55 if k < 3 else 0.3), 8.0, dt)


# ---------------- vulture / eagle (soar on a circle, the eagle stoops)
func _think_vulture(dt: float, th: Array) -> void:
	_raptor(dt, th, false)


func _think_eagle(dt: float, th: Array) -> void:
	_raptor(dt, th, true)


func _raptor(dt: float, th: Array, hunter: bool) -> void:
	var c: Vector3 = get_meta("circle", Vector3(0, 20, 0))
	var r0: float = get_meta("radius", 14.0)
	match state:
		"soar":
			trunk_a += dt * (0.12 if not hunter else 0.16)
			var r := r0 + sin(trunk_a * 0.7) * r0 * 0.3
			var want := Vector3(c.x + cos(trunk_a) * r, c.y + sin(trunk_a * 1.3) * 2.5, c.z + sin(trunk_a) * r)
			var to := want - position
			position += to.limit_length(7.0 * dt)
			if to.length() > 0.01:
				var ny := atan2(-to.x, -to.z)
				body.rotation.z = LowPoly.damp(body.rotation.z, clampf(wrapf(ny - yaw, -PI, PI) * 4.0, -0.5, 0.5) + (sin(Time.get_ticks_msec() * 0.0021 + home.x) * 0.16 if not hunter else 0.0), 2.0, dt)
				yaw = lerp_angle(yaw, ny, 1.0 - exp(-2.0 * dt))
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 2.0, dt)
			# vultures hold their wings in a shallow v (dihedral), eagles flatter; the odd few flaps
			var dihedral := -0.22 if not hunter else -0.08
			var fl := sin(Time.get_ticks_msec() * 0.006) * 0.3 if fmod(Time.get_ticks_msec() * 0.001 + home.z, 11.0) < 1.2 else 0.0
			for i in wings.size():
				wings[i].rotation.z = LowPoly.damp(wings[i].rotation.z, (dihedral + fl) * (1.0 if i == 0 else -1.0), 4.0, dt)
				(parts["tip%d" % (i + 1)] as Node3D).rotation.z = wings[i].rotation.z * 0.5
			if state_t < 0.0:
				if hunter:
					var q := _quarry()
					if q:
						set_meta("quarry", q)
						_launch(q.global_position + Vector3(0, 0.5, 0), 15.0, 1.6)
						_say("screech", 1.0)
						_set_state("stoop", 99.0)
					else:
						state_t = rng.randf_range(10.0, 20.0)
				elif has_meta("roost"):
					_launch(get_meta("roost"), 6.0, 3.0)
					_set_state("land", 99.0)
				else:
					state_t = 30.0
		"stoop":
			var q: Node3D = get_meta("quarry") if has_meta("quarry") and is_instance_valid(get_meta("quarry")) else null
			if q and fly_t < 0.75:
				target = q.global_position + Vector3(0, 0.5, 0)
			fly_t += dt / fly_dur
			var k := clampf(fly_t, 0.0, 1.0)
			var p := fly_from.lerp(target, k * k)
			var dd := p - position
			if dd.length() > 0.001:
				yaw = lerp_angle(yaw, atan2(-dd.x, -dd.z), 1.0 - exp(-6.0 * dt))
				body.rotation.x = LowPoly.damp(body.rotation.x, clampf(dd.y / dd.length(), -1.2, 0.3), 5.0, dt)
			position = p
			for i in wings.size():
				wings[i].rotation.z = LowPoly.damp(wings[i].rotation.z, (-1.0 if i == 0 else 1.0) * 0.9, 6.0, dt)
			if fly_t > 0.3 and not has_meta("warned"):
				set_meta("warned", true)
				get_tree().call_group("wild", "alarmed", target, "hawk", self)
			if k >= 1.0:
				remove_meta("warned")
				_set_state("climb", 7.0)
		"climb":
			var want := Vector3(position.x - sin(yaw) * 4.0, c.y, position.z - cos(yaw) * 4.0)
			position += (want - position).limit_length(7.0 * dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.35, 3.0, dt)
			yaw += dt * 0.5
			_flap(18.0, 0.6)
			if state_t < 0.0 or position.y > c.y - 2.0:
				trunk_a = atan2(position.z - c.z, position.x - c.x)
				_set_state("soar", rng.randf_range(40.0, 70.0))
		"land":
			if _fly_step(dt, 1.5, 12.0, 0.5):
				_set_state("perch", rng.randf_range(15.0, 30.0))
		"perch":
			_fold(dt)
			body.rotation = Vector3(-0.15, 0, 0)
			head.rotation.y = sin(Time.get_ticks_msec() * 0.0007 + home.x) * 0.8
			var d: float = th[0]
			if state_t < 0.0 or d < 2.2:
				_launch(Vector3(c.x + cos(trunk_a) * r0, c.y, c.z + sin(trunk_a) * r0), 7.0, 3.0)
				_set_state("leave", 99.0)
		"leave":
			if _fly_step(dt, 2.0, 16.0, 0.7):
				_set_state("soar", rng.randf_range(40.0, 80.0))


func _quarry() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	var c := _cat()
	for n in get_tree().get_nodes_in_group("wild"):
		if not (n is Beast) or not ((n as Beast).kind in ["marmot", "pika", "rabbit"]) or (n as Beast).state in ["hidden", "under"]:
			continue
		var b := n as Beast
		if c and c.global_position.distance_to(b.global_position) < 3.5:
			continue   # not with the cat right there
		var dd := Vector2(b.position.x - position.x, b.position.z - position.z).length()
		if dd < bd:
			bd = dd
			best = b
	return best


# ---------------- goat
func _think_goat(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var crouched: bool = th[2]
	if _hop_t >= 0.0:
		# a hop between ledges: hind legs fold, front legs reach, then it lands and steadies
		_hop_t += dt / _hop_dur
		var k := clampf(_hop_t, 0.0, 1.0)
		var p := _hop_from.lerp(_hop_to, k)
		p.y += sin(k * PI) * (0.35 + absf(_hop_to.y - _hop_from.y) * 0.4)
		position = p
		body.rotation.x = LowPoly.damp(body.rotation.x, (0.25 if k < 0.5 else -0.2), 10.0, dt)
		for i in legs.size():
			legs[i].rotation.x = (-0.6 if i < 2 else 0.6) * sin(k * PI)
		speed = 0.0
		if k >= 1.0:
			_hop_t = -1.0
			body.rotation.x = 0.0
			for l in legs:
				l.rotation.x = 0.0
			_say("clatter", 0.5)
		return
	match state:
		"stand", "stare":
			speed = LowPoly.damp(speed, 0.0, 6.0, dt)
			_gait_on()
			if state == "stare":
				_face(position - th[4], dt, 4.0)
				head.rotation.x = LowPoly.damp(head.rotation.x, 0.25, 6.0, dt)
				if fmod(state_t, 1.4) < 0.05:
					_say("clatter", 0.4, 0.8)   # stamps a foot
				if state_t < 0.0:
					_next_route(true)
			else:
				head.rotation.x = LowPoly.damp(head.rotation.x, -0.35 + sin(Time.get_ticks_msec() * 0.001 + home.x) * 0.2, 2.0, dt)
				if d < 3.0 and not (crouched and cs < 0.5):
					_set_state("stare", rng.randf_range(1.5, 3.0))
					if rng.randf() < 0.5:
						_say("bleat", 0.7)
				elif state_t < 0.0:
					_next_route(false)
		"walk":
			var to: Vector3 = route[route_i]
			var flat := Vector3(to.x - position.x, 0, to.z - position.z)
			var dist := flat.length()
			if dist > 0.02:
				yaw = lerp_angle(yaw, atan2(-flat.x, -flat.z), 1.0 - exp(-4.0 * dt))
				speed = LowPoly.damp(speed, 0.7 if state_t > 0.0 else 0.5, 3.0, dt)
				var step := minf(speed * dt, dist)
				var py := position.y
				position += flat / dist * step
				position.y = lerpf(py, to.y, step / maxf(dist, 0.001))
			_gait_on()
			if dist < 0.06:
				position = to
				_set_state("stand", rng.randf_range(3.0, 9.0))


func _next_route(away: bool) -> void:
	if route.size() < 2:
		_set_state("stand", 5.0)
		return
	var nxt := (route_i + 1) % route.size()
	if away:
		# go whichever way along the route leads away from the cat
		var c := _cat()
		var prv := (route_i - 1 + route.size()) % route.size()
		if c and (route[prv] as Vector3).distance_to(c.global_position) > (route[nxt] as Vector3).distance_to(c.global_position):
			nxt = prv
	var to: Vector3 = route[nxt]
	route_i = nxt
	if absf(to.y - position.y) > 0.25 or Vector2(to.x - position.x, to.z - position.z).length() > 2.6:
		_hop_from = position
		_hop_to = to
		_hop_t = 0.0
		_hop_dur = 0.55 + absf(to.y - position.y) * 0.1
		yaw = atan2(-(to.x - position.x), -(to.z - position.z))
		_set_state("stand", rng.randf_range(2.0, 6.0))
	else:
		_set_state("walk", rng.randf_range(4.0, 8.0))


# ---------------- marmot
func _dive() -> void:
	if state in ["run", "hidden"]:
		return
	if sentry:
		noticed = true
	_set_state("run", 3.0)


func _think_marmot(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var crouched: bool = th[2]
	var away: Vector3 = th[4]
	match state:
		"graze":
			speed = LowPoly.damp(speed, 0.0, 8.0, dt)
			visible = true
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 6.0, dt)
			head.rotation.x = LowPoly.damp(head.rotation.x, 0.5, 3.0, dt)
			_snap_ground(dt)
			if _sees(d, cs, crouched, -away, 0.0):
				_alarm()
			elif state_t < 0.0:
				_pick_wander(1.5)
				target = burrow + (target - home)
				_set_state("amble", 4.0)
		"amble":
			var dist := _move_toward(target, 0.35, dt)
			_snap_ground(dt)
			_gait_on()
			if _sees(d, cs, crouched, -away, 0.0):
				_alarm()
			elif dist < 0.08 or state_t < 0.0:
				_set_state("graze", rng.randf_range(3.0, 8.0))
		"sentry":
			# sits bolt upright on its rock, scanning slowly left and right
			visible = true
			speed = 0.0
			position = position.lerp(home, 1.0 - exp(-6.0 * dt))
			body.rotation.x = LowPoly.damp(body.rotation.x, -1.15, 6.0, dt)
			head.rotation.x = LowPoly.damp(head.rotation.x, 1.0, 6.0, dt)
			var scan := sin(t_scan()) * 1.5
			yaw = lerp_angle(yaw, scan_base + scan, 1.0 - exp(-3.0 * dt))
			if _sees(d, cs, crouched, -away, 1.0):
				_alarm()
			elif d < 0.8:
				startled = true
				_say("whistle", 1.0, 1.3)
				_alarm()
		"run":
			var to := burrow - position
			to.y = 0
			speed = 2.0
			if to.length() > 0.05:
				yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 1.0 - exp(-12.0 * dt))
				position += to.limit_length(speed * dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 12.0, dt)
			head.rotation.x = 0.0
			_snap_ground(dt)
			_gait_on("half_bound")
			if to.length() < 0.08:
				_set_state("hidden", rng.randf_range(7.0, 11.0))
		"hidden":
			speed = 0.0
			visible = false
			position = burrow + Vector3(0, -0.3, 0)
			if state_t < 0.0:
				if d > 4.0:
					_set_state("peek", 2.5)
				else:
					state_t = 2.0
		"peek":
			visible = true
			position = burrow + Vector3(0, -0.14, 0)
			body.rotation.x = -1.2
			head.rotation.x = 1.1
			_face(position - away, dt, 3.0)
			if d < 2.5 and cs > 0.4:
				_set_state("hidden", 5.0)
			elif state_t < 0.0:
				position = burrow + Vector3(0, -0.02, 0)
				if sentry:
					noticed = false
					startled = false
					position = home
					_set_state("sentry", 4.0)
				else:
					_set_state("graze", 3.0)


## the sentry's head sweeps on its own slow clock (the puzzle tests read it the same way)
func t_scan() -> float:
	return Time.get_ticks_msec() * 0.00055 + home.x


## does the marmot see the cat? in front (its head's cone) it's sharp, behind only noise gives you away.
## `upright` = sitting up on the lookout rock (sees further)
func _sees(d: float, cs: float, crouched: bool, to_cat: Vector3, upright: float) -> bool:
	var look := Vector3(-sin(yaw), 0, -cos(yaw))
	var front := look.dot(to_cat) > 0.45
	var sneaky := crouched and cs < 0.7
	var r := 0.0
	if front:
		r = 1.8 if sneaky else (6.0 if cs < 2.5 else 11.0)
	else:
		r = 0.45 if sneaky else (2.6 if cs < 2.5 else 6.0)
	return d < r * (1.0 + upright * 0.3)


func _alarm() -> void:
	_say("whistle", 1.0)
	_dive()
	_shout()


# ---------------- pika
func _think_pika(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var crouched: bool = th[2]
	match state:
		"sit":
			visible = true
			speed = 0.0
			position = position.lerp(home, 1.0 - exp(-8.0 * dt))
			head.rotation.y = sin(Time.get_ticks_msec() * 0.002 + home.z) * 0.5
			if fmod(state_t, 5.0) < 0.03 and d < 12.0:
				_say("eep", 0.5)
			if d < (0.9 if crouched and cs < 0.6 else 2.4):
				_say("eep", 0.8, 1.2)
				_set_state("hidden", rng.randf_range(4.0, 8.0))
			elif state_t < 0.0:
				# hop to another rock nearby with a mouthful of "hay"
				var best := home
				for i in 6:
					var p: Vector3 = ForestLevel.perches[rng.randi() % ForestLevel.perches.size()] if not ForestLevel.perches.is_empty() else home
					if p.distance_to(burrow) < 2.5 and p.distance_to(home) > 0.4:
						best = p
						break
				target = best
				_set_state("hop", 3.0)
		"hop":
			var dist := _move_toward(target, 1.0, dt)
			var gy := _ground_y(position.x, position.z)
			position.y = LowPoly.damp(position.y, maxf(gy, lerpf(position.y, target.y, 0.2)), 12.0, dt)
			_gait_on("half_bound")
			if dist < 0.05 or state_t < 0.0:
				home = target
				_set_state("sit", rng.randf_range(2.0, 6.0))
		"hidden":
			visible = false
			speed = 0.0
			if state_t < 0.0 and d > 2.5:
				position = home
				_set_state("sit", rng.randf_range(3.0, 6.0))


# keep pikas + marmots out of the forest-only bits of the base class
func released() -> void:
	super.released()
	if kind == "pika":
		_set_state("hidden", 4.0)
