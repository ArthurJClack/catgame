class_name Critter
extends Node3D
## forest wildlife: procedural low poly animals with a small state machine each.
## they all watch the player cat (distance, speed, crouch, how high up it is) and react:
##   rabbit   grazes, freezes when it notices you, bolts zig-zag if you rush it. stalk low to get close
##   bird     pecks around in little flocks, flushes up to a branch when you get near, comes back later
##   squirrel forages near a tree, races up the trunk when spooked and chatters at you from a limb
##   deer     grazes in the meadow, heads up and stares when you move fast, bounds off if you get close.
##            it's solid (1 m at the shoulder) so you can't just walk through its legs
##   fox      wanders, gets curious: trots over, circles and sniffs. go up high and it sits and stares.
##            run straight at it and it backs off
##   frog     sits on the banks, plops into the water when you come close
##   butterfly flutters between flowers, swerves away from paws

var kind := "rabbit"
var home := Vector3.ZERO
var state := "idle"
var state_t := 0.0
var target := Vector3.ZERO
var vel := Vector3.ZERO
var speed := 0.0
var yaw := 0.0
var phase := 0.0
var rng := RandomNumberGenerator.new()
var climb_trunk: Array = []
var perch := Vector3.ZERO
var fly_from := Vector3.ZERO
var fly_t := 0.0
var fly_dur := 1.0
var interest := 0.0
var body: Node3D
var head: Node3D
var tail: Node3D
var legs: Array[Node3D] = []
var wings: Array[Node3D] = []
var ears: Array[Node3D] = []
var solid: AnimatableBody3D
var alert := 0.0
var caught := false
var _stun := 0.0
const PREY := ["bird", "frog", "squirrel", "butterfly"]  # 0..1 how tense it is (head up / ears up)

const SIZE := {"rabbit": 1.0, "bird": 1.0, "squirrel": 1.0, "deer": 1.0, "fox": 1.0, "frog": 1.0, "butterfly": 1.0}


func _ready() -> void:
	rng.seed = hash(str(home) + kind)
	yaw = rng.randf() * TAU
	position = home
	call("_build_" + kind)
	_lod()
	if kind in PREY:
		add_to_group("prey")
	_pick_wander()
	state_t = rng.randf_range(0.5, 3.0)


# ------------------------------------------------------------------ models (real sizes, meters)
func _p(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, scl: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return LowPoly.part(parent, mesh, col, pos, scl, rot)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _leg(parent: Node3D, pos: Vector3, len: float, w: float, col: Color, hoof := Color.TRANSPARENT) -> Node3D:
	var piv := _pivot(parent, pos)
	_p(piv, LowPoly.box(), col, Vector3(0, -len * 0.5, 0), Vector3(w, len, w))
	if hoof.a > 0.0:
		_p(piv, LowPoly.box(), hoof, Vector3(0, -len + 0.02, 0.005), Vector3(w * 1.05, 0.04, w * 1.2))
	legs.append(piv)
	return piv


func _build_rabbit() -> void:
	var fur := Color(0.55, 0.45, 0.35)
	body = _pivot(self, Vector3(0, 0.0, 0))
	_p(body, LowPoly.sphere(7, 5), fur, Vector3(0, 0.14, 0.04), Vector3(0.2, 0.19, 0.32))
	head = _pivot(body, Vector3(0, 0.2, -0.13))
	_p(head, LowPoly.sphere(6, 4), fur, Vector3(0, 0, -0.03), Vector3(0.11, 0.1, 0.13))
	_p(head, LowPoly.box(0.0), Color(0.05, 0.04, 0.04), Vector3(0.045, 0.02, -0.05), Vector3.ONE * 0.018)
	_p(head, LowPoly.box(0.0), Color(0.05, 0.04, 0.04), Vector3(-0.045, 0.02, -0.05), Vector3.ONE * 0.018)
	for s in [-1, 1]:
		var e := _pivot(head, Vector3(s * 0.025, 0.04, 0.0))
		_p(e, LowPoly.box(), fur.lightened(0.05), Vector3(0, 0.06, 0), Vector3(0.03, 0.12, 0.015))
		_p(e, LowPoly.box(0.0), Color(0.85, 0.65, 0.6), Vector3(0, 0.06, -0.008), Vector3(0.018, 0.09, 0.004))
		ears.append(e)
	tail = _pivot(body, Vector3(0, 0.17, 0.2))
	_p(tail, LowPoly.sphere(5, 3), Color(0.95, 0.93, 0.9), Vector3.ZERO, Vector3.ONE * 0.06)
	_leg(body, Vector3(0.06, 0.08, -0.1), 0.08, 0.03, fur)
	_leg(body, Vector3(-0.06, 0.08, -0.1), 0.08, 0.03, fur)
	_p(body, LowPoly.box(), fur.darkened(0.1), Vector3(0.07, 0.03, 0.12), Vector3(0.05, 0.05, 0.14))
	_p(body, LowPoly.box(), fur.darkened(0.1), Vector3(-0.07, 0.03, 0.12), Vector3(0.05, 0.05, 0.14))


func _build_bird() -> void:
	var col: Color = [Color(0.5, 0.36, 0.25), Color(0.25, 0.35, 0.6), Color(0.72, 0.3, 0.2)][rng.randi() % 3]
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(6, 4), col, Vector3(0, 0.05, 0), Vector3(0.06, 0.06, 0.11))
	_p(body, LowPoly.sphere(5, 3), col.lightened(0.4), Vector3(0, 0.04, -0.015), Vector3(0.05, 0.045, 0.07))
	head = _pivot(body, Vector3(0, 0.085, -0.045))
	_p(head, LowPoly.sphere(5, 4), col.darkened(0.1), Vector3.ZERO, Vector3.ONE * 0.042)
	_p(head, LowPoly.cone(4), Color(0.85, 0.65, 0.2), Vector3(0, -0.002, -0.028), Vector3(0.012, 0.025, 0.012), Vector3(-PI / 2, 0, 0))
	tail = _pivot(body, Vector3(0, 0.06, 0.05))
	_p(tail, LowPoly.box(), col.darkened(0.2), Vector3(0, 0, 0.03), Vector3(0.035, 0.008, 0.06))
	for s in [-1, 1]:
		var w := _pivot(body, Vector3(s * 0.025, 0.065, 0.0))
		_p(w, LowPoly.box(), col.darkened(0.15), Vector3(s * 0.045, 0, 0.01), Vector3(0.09, 0.006, 0.05))
		wings.append(w)
	_leg(body, Vector3(0.012, 0.025, 0.0), 0.025, 0.006, Color(0.6, 0.45, 0.3))
	_leg(body, Vector3(-0.012, 0.025, 0.0), 0.025, 0.006, Color(0.6, 0.45, 0.3))


func _build_squirrel() -> void:
	var fur := Color(0.62, 0.32, 0.15)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(6, 4), fur, Vector3(0, 0.08, 0), Vector3(0.09, 0.09, 0.2))
	_p(body, LowPoly.sphere(5, 3), Color(0.9, 0.85, 0.75), Vector3(0, 0.065, -0.02), Vector3(0.07, 0.06, 0.13))
	head = _pivot(body, Vector3(0, 0.12, -0.1))
	_p(head, LowPoly.sphere(6, 4), fur, Vector3(0, 0, -0.02), Vector3(0.065, 0.06, 0.08))
	_p(head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(0.028, 0.012, -0.035), Vector3.ONE * 0.012)
	_p(head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(-0.028, 0.012, -0.035), Vector3.ONE * 0.012)
	for s in [-1, 1]:
		var e := _pivot(head, Vector3(s * 0.02, 0.03, 0))
		_p(e, LowPoly.cone(4), fur, Vector3(0, 0.015, 0), Vector3(0.018, 0.03, 0.012))
		ears.append(e)
	tail = _pivot(body, Vector3(0, 0.1, 0.1))
	_p(tail, LowPoly.sphere(6, 4), fur.lightened(0.08), Vector3(0, 0.1, 0.04), Vector3(0.08, 0.22, 0.09), Vector3(-0.35, 0, 0))
	_leg(body, Vector3(0.03, 0.05, -0.06), 0.05, 0.018, fur)
	_leg(body, Vector3(-0.03, 0.05, -0.06), 0.05, 0.018, fur)
	_leg(body, Vector3(0.035, 0.05, 0.06), 0.05, 0.024, fur)
	_leg(body, Vector3(-0.035, 0.05, 0.06), 0.05, 0.024, fur)


func _build_deer() -> void:
	var fur := Color(0.58, 0.4, 0.24)
	var hoof := Color(0.15, 0.12, 0.1)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(8, 5), fur, Vector3(0, 1.05, 0.05), Vector3(0.42, 0.48, 1.25))
	_p(body, LowPoly.sphere(6, 4), Color(0.92, 0.88, 0.8), Vector3(0, 0.92, 0.05), Vector3(0.3, 0.2, 0.9))
	var neck := _pivot(body, Vector3(0, 1.2, -0.5))
	_p(neck, LowPoly.box(), fur, Vector3(0, 0.2, -0.08), Vector3(0.18, 0.5, 0.2), Vector3(-0.45, 0, 0))
	head = _pivot(neck, Vector3(0, 0.45, -0.2))
	_p(head, LowPoly.box(), fur, Vector3(0, 0, -0.08), Vector3(0.16, 0.16, 0.3))
	_p(head, LowPoly.box(), Color(0.1, 0.08, 0.07), Vector3(0, -0.02, -0.24), Vector3(0.07, 0.06, 0.04))
	_p(head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(0.075, 0.03, -0.06), Vector3.ONE * 0.03)
	_p(head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(-0.075, 0.03, -0.06), Vector3.ONE * 0.03)
	for s in [-1, 1]:
		var e := _pivot(head, Vector3(s * 0.08, 0.08, 0.04))
		_p(e, LowPoly.box(), fur, Vector3(s * 0.05, 0.04, 0), Vector3(0.12, 0.06, 0.03), Vector3(0, 0, s * 0.5))
		ears.append(e)
		# small antlers
		_p(head, LowPoly.box(), Color(0.78, 0.7, 0.55), Vector3(s * 0.05, 0.16, 0.02), Vector3(0.025, 0.18, 0.025), Vector3(0.2, 0, s * 0.3))
		_p(head, LowPoly.box(), Color(0.78, 0.7, 0.55), Vector3(s * 0.08, 0.22, -0.04), Vector3(0.02, 0.1, 0.02), Vector3(-0.6, 0, s * 0.2))
	tail = _pivot(body, Vector3(0, 1.15, 0.66))
	_p(tail, LowPoly.box(), Color(0.95, 0.93, 0.9), Vector3(0, -0.06, 0.02), Vector3(0.08, 0.14, 0.04))
	_leg(body, Vector3(0.12, 0.85, -0.42), 0.85, 0.07, fur, hoof)
	_leg(body, Vector3(-0.12, 0.85, -0.42), 0.85, 0.07, fur, hoof)
	_leg(body, Vector3(0.13, 0.88, 0.5), 0.88, 0.08, fur, hoof)
	_leg(body, Vector3(-0.13, 0.88, 0.5), 0.88, 0.08, fur, hoof)
	# solid body: the cat bumps into it (and can hop on its back if it's brave)
	solid = AnimatableBody3D.new()
	solid.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.38, 0.45, 1.1)
	cs.shape = bs
	cs.position = Vector3(0, 1.05, 0.05)
	solid.add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(0.3, 0.8, 1.0)
	cs2.shape = bs2
	cs2.position = Vector3(0, 0.42, 0.05)
	solid.add_child(cs2)
	solid.top_level = true
	add_child(solid)


func _build_fox() -> void:
	var fur := Color(0.82, 0.42, 0.16)
	var dark := Color(0.12, 0.08, 0.07)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(7, 4), fur, Vector3(0, 0.36, 0.02), Vector3(0.2, 0.2, 0.6))
	_p(body, LowPoly.sphere(5, 3), Color(0.95, 0.92, 0.85), Vector3(0, 0.31, -0.18), Vector3(0.14, 0.12, 0.2))
	head = _pivot(body, Vector3(0, 0.44, -0.3))
	_p(head, LowPoly.sphere(6, 4), fur, Vector3(0, 0, -0.03), Vector3(0.15, 0.12, 0.15))
	_p(head, LowPoly.cone(4), fur, Vector3(0, -0.015, -0.13), Vector3(0.08, 0.14, 0.06), Vector3(-PI / 2, PI / 4, 0))
	_p(head, LowPoly.cone(4), Color(0.95, 0.92, 0.85), Vector3(0, -0.035, -0.12), Vector3(0.06, 0.1, 0.03), Vector3(-PI / 2, PI / 4, 0))
	_p(head, LowPoly.box(0.0), dark, Vector3(0, -0.012, -0.2), Vector3.ONE * 0.025)
	_p(head, LowPoly.box(0.0), Color(0.9, 0.7, 0.1), Vector3(0.042, 0.02, -0.07), Vector3(0.02, 0.014, 0.01))
	_p(head, LowPoly.box(0.0), Color(0.9, 0.7, 0.1), Vector3(-0.042, 0.02, -0.07), Vector3(0.02, 0.014, 0.01))
	for s in [-1, 1]:
		var e := _pivot(head, Vector3(s * 0.045, 0.05, 0.01))
		_p(e, LowPoly.cone(4), fur, Vector3(0, 0.04, 0), Vector3(0.05, 0.08, 0.025))
		_p(e, LowPoly.cone(4), dark, Vector3(0, 0.07, 0.002), Vector3(0.025, 0.03, 0.02))
		ears.append(e)
	tail = _pivot(body, Vector3(0, 0.38, 0.3))
	_p(tail, LowPoly.sphere(6, 4), fur, Vector3(0, -0.03, 0.18), Vector3(0.11, 0.11, 0.4), Vector3(0.35, 0, 0))
	_p(tail, LowPoly.sphere(5, 3), Color(0.97, 0.95, 0.9), Vector3(0, -0.1, 0.36), Vector3(0.07, 0.07, 0.1))
	_leg(body, Vector3(0.06, 0.3, -0.2), 0.3, 0.04, dark)
	_leg(body, Vector3(-0.06, 0.3, -0.2), 0.3, 0.04, dark)
	_leg(body, Vector3(0.06, 0.3, 0.22), 0.3, 0.045, dark)
	_leg(body, Vector3(-0.06, 0.3, 0.22), 0.3, 0.045, dark)


func _build_frog() -> void:
	var col := Color(0.35, 0.55, 0.2)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(6, 4), col, Vector3(0, 0.025, 0), Vector3(0.06, 0.04, 0.07))
	head = _pivot(body, Vector3(0, 0.035, -0.03))
	for s in [-1, 1]:
		_p(head, LowPoly.sphere(4, 3), col.lightened(0.1), Vector3(s * 0.018, 0.012, 0), Vector3.ONE * 0.018)
		_p(head, LowPoly.box(0.0), Color(0.05, 0.05, 0.02), Vector3(s * 0.02, 0.016, -0.006), Vector3.ONE * 0.008)
	_leg(body, Vector3(0.03, 0.02, 0.02), 0.02, 0.015, col.darkened(0.1))
	_leg(body, Vector3(-0.03, 0.02, 0.02), 0.02, 0.015, col.darkened(0.1))


func _build_butterfly() -> void:
	var col: Color = [Color(0.95, 0.6, 0.1), Color(0.95, 0.95, 0.9), Color(0.4, 0.55, 0.95)][rng.randi() % 3]
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.box(), Color(0.1, 0.08, 0.06), Vector3.ZERO, Vector3(0.006, 0.006, 0.03))
	for s in [-1, 1]:
		var w := _pivot(body, Vector3(s * 0.003, 0, 0))
		_p(w, LowPoly.box(0.0), col, Vector3(s * 0.022, 0, -0.004), Vector3(0.042, 0.002, 0.036))
		wings.append(w)


# ------------------------------------------------------------------ helpers
## small animals are made of lots of little parts: hide them past a distance + no shadows for the tiny ones
## (keeps the draw calls sane, especially in the browser build)
func _lod() -> void:
	var far: float = {"bird": 16.0, "frog": 12.0, "butterfly": 14.0, "rabbit": 24.0, "squirrel": 22.0, "fox": 34.0, "deer": 60.0}.get(kind, 30.0)
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is GeometryInstance3D:
			var g := n as GeometryInstance3D
			g.visibility_range_end = far
			g.visibility_range_end_margin = 2.0
			if kind in ["bird", "frog", "butterfly", "squirrel"]:
				g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _cat() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _ground_y(x: float, z: float) -> float:
	return ForestLevel.height(x, z)


func _pick_wander(radius := 6.0) -> void:
	for i in 12:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.0, radius)
		var t := home + Vector3(cos(a) * r, 0, sin(a) * r)
		t.x = clampf(t.x, -34, 34)
		t.z = clampf(t.z, -34, 34)
		var h := _ground_y(t.x, t.z)
		if kind != "deer" and kind != "frog" and h < ForestLevel.WATER_Y + 0.05:
			continue
		target = Vector3(t.x, h, t.z)
		return
	target = home


func _avoid(dir: Vector3) -> Vector3:
	# steer around trunks / rocks / logs (ground animals)
	var p := Vector2(position.x, position.z)
	var push := Vector2.ZERO
	for o in ForestLevel.obstacles:
		var c: Vector2 = o[0]
		var r: float = o[1] + (0.6 if kind == "deer" else 0.15)
		var d := p - c
		var l := d.length()
		if l < r + 0.6 and l > 0.001:
			push += d / l * (r + 0.6 - l) * 2.0
	var out := Vector2(dir.x, dir.z) + push
	if out.length() < 0.001:
		return dir
	out = out.normalized()
	return Vector3(out.x, 0, out.y)


func _move_toward(dest: Vector3, spd: float, dt: float, turn := 8.0) -> float:
	var d := dest - position
	d.y = 0
	var dist := d.length()
	if dist < 0.05:
		speed = LowPoly.damp(speed, 0.0, 10.0, dt)
		return dist
	var dir := _avoid(d / dist)
	speed = LowPoly.damp(speed, spd, 6.0, dt)
	var want_yaw := atan2(-dir.x, -dir.z)
	yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-turn * dt))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	position += fwd * speed * dt
	position.x = clampf(position.x, -35, 35)
	position.z = clampf(position.z, -35, 35)
	return dist


func _face(p: Vector3, dt: float, rate := 5.0) -> void:
	var d := p - position
	yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-rate * dt))


## how threatening the cat is right now: returns [dist, speed, crouched, cat_alt, flat_dir_from_cat]
func _threat() -> Array:
	var c := _cat()
	if c == null:
		return [999.0, 0.0, false, 0.0, Vector3.FORWARD]
	var d := position - c.global_position
	var alt := c.global_position.y - _ground_y(c.global_position.x, c.global_position.z)
	var v: Vector3 = c.get("velocity") if c.get("velocity") != null else Vector3.ZERO
	var crouch: float = c.get("crouch_amt") if c.get("crouch_amt") != null else 0.0
	var flat := Vector3(d.x, 0, d.z)
	return [flat.length(), Vector2(v.x, v.z).length(), crouch > 0.5, alt, flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD]


func _set_state(s: String, t: float) -> void:
	state = s
	state_t = t


# ------------------------------------------------------------------ update
## prey interface for the player's hunting (same duck type as toy_mouse.gd)
func pinned() -> void:
	caught = true
	speed = 0.0


func stun(t: float) -> void:
	_stun = maxf(_stun, t)


func released() -> void:
	caught = false
	_stun = 0.0
	home = global_position
	rotation = Vector3(0, yaw, 0)
	if body:
		body.rotation = Vector3.ZERO
		body.position = Vector3.ZERO
	# shake it off and get away from the cat
	_set_state("idle", 0.0)
	if kind == "bird":
		_fly_to_perch(_threat())
	elif kind == "squirrel":
		_flee_up_tree()


func _physics_process(dt: float) -> void:
	if caught:
		return
	if _stun > 0.0:
		_stun -= dt
		return
	state_t -= dt
	var th := _threat()
	call("_think_" + kind, dt, th)
	rotation = Vector3(0, yaw, 0)
	if solid:
		solid.global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position)


func _snap_ground(dt: float, lift := 0.0) -> void:
	var gy := _ground_y(position.x, position.z)
	if kind != "frog" and kind != "deer":
		gy = maxf(gy, ForestLevel.WATER_Y - 0.02)
	position.y = LowPoly.damp(position.y, gy + lift, 18.0, dt)


func _walk_anim(dt: float, stride: float, amp: float) -> void:
	phase += speed / stride * dt * TAU
	for i in legs.size():
		var off := 0.0 if i % 2 == 0 else PI
		if i >= 2:
			off += PI * 0.5
		legs[i].rotation.x = sin(phase + off) * amp * clampf(speed / 1.0, 0.0, 1.0)


# ---------------- rabbit
func _think_rabbit(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var crouched: bool = th[2]
	var notice := 2.2 if (crouched and cs < 1.0) else (7.0 if cs > 2.5 else 4.5)
	var hop_y := 0.0
	match state:
		"idle", "graze":
			speed = LowPoly.damp(speed, 0.0, 8.0, dt)
			alert = LowPoly.damp(alert, 0.0, 2.0, dt)
			if body:
				head.rotation.x = LowPoly.damp(head.rotation.x, 0.5 if state == "graze" else 0.0, 4.0, dt)
			if d < notice:
				_set_state("freeze", rng.randf_range(0.5, 1.0))
			elif state_t < 0.0:
				if rng.randf() < 0.5:
					_set_state("graze", rng.randf_range(1.5, 4.0))
				else:
					_pick_wander(5.0)
					_set_state("hop", 4.0)
		"hop":
			var rem := _move_toward(target, 1.4, dt)
			phase += dt * 5.0
			hop_y = absf(sin(phase * PI)) * 0.08
			if rem < 0.2 or state_t < 0.0:
				_set_state("idle", rng.randf_range(0.8, 2.5))
			if d < notice:
				_set_state("freeze", rng.randf_range(0.4, 0.8))
		"freeze":
			speed = 0.0
			alert = LowPoly.damp(alert, 1.0, 10.0, dt)
			head.rotation.x = LowPoly.damp(head.rotation.x, -0.2, 8.0, dt)
			if d < 2.0 or (cs > 2.0 and d < notice) or state_t < -1.5:
				var away: Vector3 = th[4]
				target = position + away * 10.0
				_set_state("flee", rng.randf_range(2.0, 3.0))
			elif state_t < 0.0 and d > notice + 1.0:
				_set_state("idle", 1.0)
		"flee":
			if fmod(state_t, 0.6) < dt:  # zig zag
				var side := Vector3(-sin(yaw), 0, -cos(yaw)).cross(Vector3.UP) * rng.randf_range(-3.0, 3.0)
				target += side
			_move_toward(target, 7.0, dt, 12.0)
			phase += dt * 9.0
			hop_y = absf(sin(phase * PI)) * 0.14
			if state_t < 0.0:
				home = position
				_set_state("idle", rng.randf_range(2.0, 4.0))
	_snap_ground(dt)
	body.position.y = hop_y
	body.rotation.x = -hop_y * 2.0
	for e in ears:
		e.rotation.x = lerpf(0.5, -0.1, alert) + sin(Time.get_ticks_msec() * 0.003 + e.position.x * 50.0) * 0.05
	if state == "graze":
		head.position.y = 0.2 + sin(Time.get_ticks_msec() * 0.02) * 0.004


# ---------------- bird
func _think_bird(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var crouched: bool = th[2]
	var flush := 1.6 if (crouched and cs < 0.8) else (4.5 if cs > 2.0 else 3.0)
	match state:
		"idle", "peck":
			for w in wings:
				w.rotation.z = LowPoly.damp(w.rotation.z, 0.0, 10.0, dt)
			if state == "peck":
				head.rotation.x = 0.7 if fmod(state_t, 0.5) < 0.12 else 0.0
			else:
				head.rotation.x = 0.0
				head.rotation.y = sin(Time.get_ticks_msec() * 0.004 + home.x) * 0.6
			if d < flush:
				_fly_to_perch(th)
			elif state_t < 0.0:
				var roll := rng.randf()
				if roll < 0.4:
					_set_state("peck", rng.randf_range(1.0, 2.5))
				elif roll < 0.8:
					_pick_wander(2.5)
					_set_state("hop", 2.0)
				else:
					_set_state("idle", rng.randf_range(0.5, 2.0))
			_snap_ground(dt)
		"hop":
			var rem := _move_toward(target, 0.6, dt, 14.0)
			phase += dt * 10.0
			body.position.y = absf(sin(phase * PI)) * 0.025
			_snap_ground(dt)
			if rem < 0.1 or state_t < 0.0:
				body.position.y = 0.0
				_set_state("idle", rng.randf_range(0.3, 1.5))
			if d < flush:
				_fly_to_perch(th)
		"fly":
			fly_t += dt / fly_dur
			var k := clampf(fly_t, 0.0, 1.0)
			var p := fly_from.lerp(target, k)
			p.y += sin(k * PI) * maxf(1.2, fly_from.distance_to(target) * 0.25)
			var dd := p - position
			if dd.length() > 0.001:
				yaw = lerp_angle(yaw, atan2(-dd.x, -dd.z), 1.0 - exp(-10.0 * dt))
			position = p
			var flap := sin(Time.get_ticks_msec() * 0.06) * 1.1
			for i in wings.size():
				wings[i].rotation.z = flap * (1.0 if i == 0 else -1.0)
			body.rotation.x = -0.2
			if k >= 1.0:
				body.rotation.x = 0.0
				_set_state("perched", rng.randf_range(6.0, 14.0))
		"perched":
			for w in wings:
				w.rotation.z = LowPoly.damp(w.rotation.z, 0.0, 10.0, dt)
			head.rotation.y = sin(Time.get_ticks_msec() * 0.003 + home.z) * 0.8
			var c := _cat()
			if c and c.global_position.distance_to(position) < 1.3:
				_fly_to_perch(th)
			elif state_t < 0.0 and d > 5.0:
				# come back down to the ground near home
				fly_from = position
				_pick_wander(4.0)
				fly_t = 0.0
				fly_dur = maxf(0.8, fly_from.distance_to(target) / 5.0)
				_set_state("fly_down", 10.0)
		"fly_down":
			fly_t += dt / fly_dur
			var k := clampf(fly_t, 0.0, 1.0)
			position = fly_from.lerp(target, k) + Vector3(0, sin(k * PI) * 0.6, 0)
			var flap := sin(Time.get_ticks_msec() * 0.06) * (1.1 if k < 0.8 else 0.5)
			for i in wings.size():
				wings[i].rotation.z = flap * (1.0 if i == 0 else -1.0)
			var dd := target - fly_from
			yaw = lerp_angle(yaw, atan2(-dd.x, -dd.z), 1.0 - exp(-10.0 * dt))
			if k >= 1.0:
				_set_state("idle", rng.randf_range(0.5, 2.0))


func _fly_to_perch(th: Array) -> void:
	var best := Vector3.ZERO
	var best_score := -1e9
	var away: Vector3 = th[4]
	for i in 10:
		if ForestLevel.perches.is_empty():
			break
		var p: Vector3 = ForestLevel.perches[rng.randi() % ForestLevel.perches.size()]
		var off := p - position
		var dist := off.length()
		if dist < 2.0 or dist > 22.0:
			continue
		var score := Vector3(off.x, 0, off.z).normalized().dot(away) * 3.0 + p.y * 0.4 - dist * 0.08
		if score > best_score:
			best_score = score
			best = p
	if best == Vector3.ZERO:
		best = position + away * 8.0 + Vector3(0, 4, 0)
	fly_from = position
	target = best
	fly_t = 0.0
	fly_dur = maxf(0.7, fly_from.distance_to(target) / 6.0)
	_set_state("fly", 99.0)


# ---------------- squirrel
func _think_squirrel(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var crouched: bool = th[2]
	var spook := 2.0 if crouched and cs < 0.8 else 4.5
	match state:
		"idle", "forage":
			if state == "forage":
				head.rotation.x = 0.6
				body.position.y = 0.0
			else:
				head.rotation.x = -0.2
				body.position.y = 0.0
			tail.rotation.x = sin(Time.get_ticks_msec() * 0.01) * 0.15
			speed = LowPoly.damp(speed, 0.0, 10.0, dt)
			if d < spook:
				_flee_up_tree()
			elif state_t < 0.0:
				if rng.randf() < 0.5:
					_set_state("forage", rng.randf_range(1.0, 3.0))
				else:
					_pick_wander(4.0)
					_set_state("scamper", 3.0)
			_snap_ground(dt)
		"scamper":
			var rem := _move_toward(target, 2.2, dt, 14.0)
			phase += dt * 14.0
			body.position.y = absf(sin(phase)) * 0.04
			_snap_ground(dt)
			if rem < 0.15 or state_t < 0.0:
				_set_state("idle", rng.randf_range(0.5, 2.0))
			if d < spook:
				_flee_up_tree()
		"run_to_tree":
			var base: Vector3 = climb_trunk[0]
			var r: float = climb_trunk[1]
			var dir := Vector3(position.x - base.x, 0, position.z - base.z).normalized()
			var dest := base + dir * (r + 0.05)
			var rem := _move_toward(dest, 5.0, dt, 16.0)
			phase += dt * 18.0
			body.position.y = absf(sin(phase)) * 0.05
			_snap_ground(dt)
			if rem < 0.1:
				fly_t = atan2(dir.z, dir.x)
				_set_state("climb", 99.0)
		"climb":
			var base: Vector3 = climb_trunk[0]
			var r: float = climb_trunk[1]
			var top: float = climb_trunk[2]
			fly_t += dt * 2.5   # angle around the trunk: spiral up
			position.y += dt * 2.2
			position.x = base.x + cos(fly_t) * (r + 0.05)
			position.z = base.z + sin(fly_t) * (r + 0.05)
			# belly to the bark, head up
			yaw = atan2(cos(fly_t), sin(fly_t)) * -1.0 + PI * 0.5
			yaw = atan2(-(base.x - position.x), -(base.z - position.z))
			body.rotation.x = -PI * 0.5
			phase += dt * 16.0
			_walk_anim(dt, 0.1, 0.8)
			if position.y > base.y + top:
				_set_state("perched", rng.randf_range(8.0, 15.0))
		"perched":
			body.rotation.x = LowPoly.damp(body.rotation.x, -PI * 0.5, 6.0, dt)
			# chatter: tail flicks + head bobs toward the cat
			tail.rotation.x = sin(Time.get_ticks_msec() * 0.03) * 0.5
			head.rotation.y = sin(Time.get_ticks_msec() * 0.005) * 0.4
			if state_t < 0.0 and d > 7.0:
				_set_state("descend", 99.0)
		"descend":
			var base: Vector3 = climb_trunk[0]
			var r: float = climb_trunk[1]
			fly_t -= dt * 2.0
			position.y -= dt * 1.6
			position.x = base.x + cos(fly_t) * (r + 0.05)
			position.z = base.z + sin(fly_t) * (r + 0.05)
			body.rotation.x = PI * 0.5
			_walk_anim(dt, 0.1, 0.8)
			if position.y <= _ground_y(position.x, position.z) + 0.02:
				body.rotation.x = 0.0
				home = position
				_set_state("idle", 1.0)
			if d < 1.5:
				_set_state("climb", 99.0)
				body.rotation.x = -PI * 0.5
	if state in ["idle", "forage", "scamper", "run_to_tree"]:
		body.rotation.x = 0.0
		_walk_anim(dt, 0.12, 0.9)


func _flee_up_tree() -> void:
	var best: Array = []
	var bd := 1e9
	for t in ForestLevel.trunks:
		var b: Vector3 = t[0]
		var dd := Vector2(b.x - position.x, b.z - position.z).length()
		if dd < bd:
			bd = dd
			best = t
	if best.is_empty() or bd > 12.0:
		_pick_wander(8.0)
		_set_state("scamper", 2.0)
		return
	climb_trunk = best
	_set_state("run_to_tree", 6.0)


# ---------------- deer
func _think_deer(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var crouched: bool = th[2]
	var c := _cat()
	var notice := 6.0 if crouched else (14.0 if cs > 3.0 else 9.0)
	var neck := head.get_parent() as Node3D
	match state:
		"idle", "graze":
			speed = LowPoly.damp(speed, 0.0, 4.0, dt)
			alert = LowPoly.damp(alert, 0.0, 1.0, dt)
			neck.rotation.x = LowPoly.damp(neck.rotation.x, 1.3 if state == "graze" else 0.0, 3.0, dt)
			if d < notice:
				_set_state("alert", rng.randf_range(2.0, 4.0))
			elif state_t < 0.0:
				if rng.randf() < 0.6:
					_set_state("graze", rng.randf_range(3.0, 7.0))
				else:
					_pick_wander(7.0)
					_set_state("walk", 8.0)
		"walk":
			var rem := _move_toward(target, 0.9, dt, 2.5)
			neck.rotation.x = LowPoly.damp(neck.rotation.x, 0.2, 3.0, dt)
			if rem < 0.4 or state_t < 0.0:
				_set_state("idle", rng.randf_range(1.0, 3.0))
			if d < notice:
				_set_state("alert", rng.randf_range(2.0, 4.0))
		"alert":
			speed = LowPoly.damp(speed, 0.0, 6.0, dt)
			alert = LowPoly.damp(alert, 1.0, 6.0, dt)
			neck.rotation.x = LowPoly.damp(neck.rotation.x, -0.25, 6.0, dt)
			if c:
				_face(c.global_position, dt, 2.0)
			# tail flag + stamp a foreleg
			tail.rotation.x = -1.2
			legs[0].rotation.x = sin(Time.get_ticks_msec() * 0.012) * 0.3 if state_t > 1.0 else 0.0
			if d < 4.0 or (cs > 4.0 and d < notice):
				var away: Vector3 = th[4]
				target = position + away * 16.0
				_set_state("flee", rng.randf_range(3.0, 4.5))
			elif state_t < 0.0:
				tail.rotation.x = 0.0
				_set_state("idle" if d > notice else "alert", rng.randf_range(2.0, 3.0))
		"flee":
			_move_toward(target, 8.5, dt, 3.5)
			neck.rotation.x = LowPoly.damp(neck.rotation.x, 0.25, 6.0, dt)
			phase += dt * 4.5
			# bounding: all four legs fold + body arcs
			var b := sin(phase * PI)
			body.position.y = maxf(b, 0.0) * 0.45
			body.rotation.x = -cos(phase * PI) * 0.15
			for i in legs.size():
				legs[i].rotation.x = (0.9 if i < 2 else -0.9) * maxf(b, 0.0)
			if state_t < 0.0:
				body.position.y = 0.0
				body.rotation.x = 0.0
				tail.rotation.x = 0.0
				home = position
				_set_state("idle", rng.randf_range(3.0, 6.0))
	_snap_ground(dt)
	if state != "flee":
		_walk_anim(dt, 1.3, 0.45)
		body.position.y = LowPoly.damp(body.position.y, 0.0, 8.0, dt)
	for e in ears:
		e.rotation.y = lerpf(0.0, -0.4 if e.position.x > 0 else 0.4, alert)


# ---------------- fox
func _think_fox(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var alt: float = th[3]
	var c := _cat()
	interest = maxf(interest - dt * 0.04, 0.0)
	match state:
		"idle":
			speed = LowPoly.damp(speed, 0.0, 6.0, dt)
			head.rotation.x = LowPoly.damp(head.rotation.x, 0.3, 3.0, dt)
			if d < 11.0 and interest < 0.6:
				_set_state("approach", 12.0)
			elif state_t < 0.0:
				_pick_wander(10.0)
				_set_state("trot", 10.0)
		"trot":
			var rem := _move_toward(target, 2.0, dt, 4.0)
			head.rotation.x = LowPoly.damp(head.rotation.x, 0.35, 3.0, dt)  # nose down, sniffing
			if rem < 0.4 or state_t < 0.0:
				_set_state("idle", rng.randf_range(1.0, 4.0))
			if d < 11.0 and interest < 0.6:
				_set_state("approach", 12.0)
		"approach":
			if c == null:
				_set_state("idle", 1.0)
				return
			head.rotation.x = LowPoly.damp(head.rotation.x, -0.1, 4.0, dt)
			if alt > 0.9:
				_set_state("watch", rng.randf_range(4.0, 8.0))
			elif d > 2.0:
				_move_toward(c.global_position, 1.6 if d < 5.0 else 3.0, dt, 5.0)
			else:
				_set_state("circle", rng.randf_range(3.0, 5.0))
			if _rushed(th):
				_set_state("retreat", 2.5)
			if state_t < 0.0:
				interest = 1.0
				_set_state("idle", 2.0)
		"circle":
			if c == null:
				return
			var off := position - c.global_position
			off.y = 0
			var ang := atan2(off.z, off.x) + dt * 0.7
			var dest := c.global_position + Vector3(cos(ang), 0, sin(ang)) * 1.8
			_move_toward(dest, 1.2, dt, 6.0)
			head.rotation.y = LowPoly.damp(head.rotation.y, 0.6, 4.0, dt)
			if _rushed(th):
				_set_state("retreat", 2.5)
			elif alt > 0.9:
				_set_state("watch", rng.randf_range(4.0, 8.0))
			elif state_t < 0.0:
				interest += 0.5
				head.rotation.y = 0.0
				_set_state("approach" if interest < 0.8 else "idle", 4.0)
		"watch":
			# the cat's up a tree: sit underneath, stare up, tail curled
			speed = LowPoly.damp(speed, 0.0, 8.0, dt)
			if c:
				_face(c.global_position, dt, 3.0)
				head.rotation.x = LowPoly.damp(head.rotation.x, -0.7, 3.0, dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, -0.35, 4.0, dt)
			if state_t < 0.0 or alt < 0.5:
				body.rotation.x = 0.0
				interest += 0.4
				_set_state("idle" if interest > 0.8 else "approach", 3.0)
		"retreat":
			var away: Vector3 = th[4]
			_move_toward(position + away * 4.0, 5.5, dt, 10.0)
			head.rotation.x = 0.1
			if state_t < 0.0:
				interest = 1.0
				_set_state("idle", 3.0)
	if state != "watch":
		body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 6.0, dt)
	_snap_ground(dt)
	_walk_anim(dt, 0.55, 0.6)
	tail.rotation.y = sin(Time.get_ticks_msec() * 0.004) * 0.25


func _rushed(th: Array) -> bool:
	var c := _cat()
	if c == null:
		return false
	var v: Vector3 = c.get("velocity")
	var to_me := position - c.global_position
	to_me.y = 0
	return to_me.length() < 3.0 and Vector3(v.x, 0, v.z).dot(to_me.normalized()) > 2.5


# ---------------- frog
func _think_frog(dt: float, th: Array) -> void:
	var d: float = th[0]
	match state:
		"idle":
			speed = 0.0
			body.scale.y = 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.05  # throat pulse
			if d < 1.4:
				# leap away toward the water
				var away: Vector3 = th[4]
				fly_from = position
				target = position + away * 0.9
				target.y = maxf(_ground_y(target.x, target.z), ForestLevel.WATER_Y - 0.03)
				fly_t = 0.0
				_set_state("leap", 99.0)
			elif state_t < 0.0:
				_set_state("idle", rng.randf_range(2.0, 6.0))
		"leap":
			fly_t += dt / 0.35
			var k := clampf(fly_t, 0.0, 1.0)
			position = fly_from.lerp(target, k) + Vector3(0, sin(k * PI) * 0.25, 0)
			var dd := target - fly_from
			yaw = atan2(-dd.x, -dd.z)
			for l in legs:
				l.rotation.x = -1.2 if k < 0.6 else 0.0
			if k >= 1.0:
				home = position
				_set_state("idle", rng.randf_range(1.0, 3.0))


# ---------------- butterfly
func _think_butterfly(dt: float, th: Array) -> void:
	var c := _cat()
	phase += dt
	var flap := sin(Time.get_ticks_msec() * 0.045) * 1.2
	for i in wings.size():
		wings[i].rotation.z = flap * (1.0 if i == 0 else -1.0)
	if state_t < 0.0 or position.distance_to(target) < 0.2:
		if not ForestLevel.flowers.is_empty() and rng.randf() < 0.6:
			target = ForestLevel.flowers[rng.randi() % ForestLevel.flowers.size()] + Vector3(0, 0.05, 0)
			if target.distance_to(home) > 12.0:
				target = home + Vector3(rng.randf_range(-3, 3), rng.randf_range(0.3, 1.2), rng.randf_range(-3, 3))
		else:
			target = home + Vector3(rng.randf_range(-3, 3), rng.randf_range(0.3, 1.4), rng.randf_range(-3, 3))
			target.y += _ground_y(target.x, target.z) - home.y + 0.3
		state_t = rng.randf_range(2.0, 5.0)
	var to := target - position
	var wob := Vector3(sin(phase * 7.0), sin(phase * 9.0 + 1.0) * 0.8, cos(phase * 6.0)) * 0.6
	var want := to.normalized() * 0.9 + wob
	if c and c.global_position.distance_to(position) < 0.8:
		want += (position - c.global_position).normalized() * 3.0 + Vector3.UP * 1.5
	vel = vel.lerp(want, 1.0 - exp(-3.0 * dt))
	position += vel * dt
	position.y = maxf(position.y, _ground_y(position.x, position.z) + 0.08)
	if vel.length() > 0.05:
		yaw = lerp_angle(yaw, atan2(-vel.x, -vel.z), 1.0 - exp(-6.0 * dt))


# ------------------------------------------------------------------ spawning
static func spawn_all(parent: Node3D) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var add := func(k: String, p: Vector3) -> void:
		var c := Critter.new()
		c.kind = k
		c.home = Vector3(p.x, ForestLevel.height(p.x, p.z), p.z)
		parent.add_child(c)
		out.append(c)
	var m := ForestLevel.MEADOW
	# meadow: deer family + rabbits + butterflies
	add.call("deer", Vector3(m.x + 2.0, 0, m.y - 2.0))
	add.call("deer", Vector3(m.x - 1.5, 0, m.y - 3.5))
	add.call("deer", Vector3(m.x + 4.0, 0, m.y + 1.0))
	for k in 5:
		add.call("rabbit", Vector3(m.x + rng.randf_range(-6, 6), 0, m.y + rng.randf_range(-6, 6)))
	for k in 6:
		add.call("butterfly", Vector3(m.x + rng.randf_range(-6, 6), 0, m.y + rng.randf_range(-6, 6)))
	# rabbits near the spawn path too, so you meet one quickly
	add.call("rabbit", Vector3(4.0, 0, 26.0))
	add.call("rabbit", Vector3(-5.0, 0, 18.0))
	# bird flocks
	for flock in [Vector2(2, 22), Vector2(-8, 6), Vector2(10, -6), Vector2(-4, -12), Vector2(16, 18)]:
		for k in rng.randi_range(3, 5):
			add.call("bird", Vector3(flock.x + rng.randf_range(-1.5, 1.5), 0, flock.y + rng.randf_range(-1.5, 1.5)))
	# squirrels near trees
	var tr := ForestLevel.trunks
	for k in 7:
		if tr.is_empty():
			break
		var t: Array = tr[(k * 13 + 5) % tr.size()]
		var b: Vector3 = t[0]
		add.call("squirrel", b + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)))
	# foxes
	add.call("fox", Vector3(-12.0, 0, 20.0))
	add.call("fox", Vector3(14.0, 0, -18.0))
	# frogs on the banks + pond edge
	for k in 10:
		var x := rng.randf_range(-28, 28)
		var z := ForestLevel.stream_z(x) + (2.2 if k % 2 == 0 else -2.2)
		add.call("frog", Vector3(x, 0, z))
	for k in 5:
		var a := rng.randf() * TAU
		add.call("frog", Vector3(ForestLevel.POND.x + cos(a) * 5.0, 0, ForestLevel.POND.y + sin(a) * 5.0))
	return out
