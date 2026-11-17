class_name FieldMouse
extends RigidBody3D
## real (well, low poly) field mouse: huntable prey. scurries between cover in short dashes,
## bolts for the nearest log/rock when the cat rushes in. stalk low, aim, pounce: pinned() = caught.

var caught := false
var kind := "field mouse"
var _stun := 0.0
var _t := 1.0
var _rng := RandomNumberGenerator.new()
var _body: Node3D
var _tail: Node3D
var _gait: CritterGait


func _ready() -> void:
	_rng.seed = int(position.x * 97 + position.z * 31)
	mass = 0.03
	linear_damp = 2.0
	angular_damp = 8.0
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	add_to_group("prey")
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.035, 0.03, 0.075)
	cs.shape = b
	cs.position.y = 0.015
	add_child(cs)
	var fur := Color(0.5, 0.4, 0.3)
	_body = Node3D.new()
	add_child(_body)
	LowPoly.part(_body, LowPoly.sphere(6, 4), fur, Vector3(0, 0.017, 0.005), Vector3(0.036, 0.032, 0.065))
	LowPoly.part(_body, LowPoly.sphere(5, 3), Color(0.85, 0.8, 0.72), Vector3(0, 0.012, 0.0), Vector3(0.028, 0.02, 0.05))
	LowPoly.part(_body, LowPoly.cone(4), fur, Vector3(0, 0.017, -0.038), Vector3(0.026, 0.032, 0.024), Vector3(-PI / 2, PI / 4, 0))
	LowPoly.part(_body, LowPoly.box(0.0), Color(0.9, 0.6, 0.6), Vector3(0, 0.016, -0.055), Vector3.ONE * 0.007)
	for s in [-1, 1]:
		LowPoly.part(_body, LowPoly.sphere(5, 3), Color(0.75, 0.55, 0.5), Vector3(s * 0.012, 0.034, -0.018), Vector3(0.016, 0.016, 0.005))
		LowPoly.part(_body, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(s * 0.009, 0.024, -0.036), Vector3.ONE * 0.005)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.012, 0.04)
	_body.add_child(_tail)
	LowPoly.part(_tail, LowPoly.box(0.0), Color(0.7, 0.55, 0.5), Vector3(0, 0, 0.035), Vector3(0.004, 0.004, 0.07))
	# four little legs: mice half bound (hind feet together) at ~8 strides a second
	var legs: Array[Node3D] = []
	var lens: Array[float] = []
	for z in [-0.02, 0.025]:
		for s in [-1, 1]:
			var lg := Node3D.new()
			lg.position = Vector3(s * 0.012, 0.012, z)
			_body.add_child(lg)
			LowPoly.part(lg, LowPoly.box(0.0), Color(0.8, 0.62, 0.58), Vector3(0, -0.006, -0.002), Vector3(0.006, 0.012, 0.008 if z > 0 else 0.005))
			legs.append(lg)
			lens.append(0.012)
	_gait = CritterGait.new("field mouse", legs, lens)


## swatted: dazed for a moment (an easy pounce)
func stun(t: float) -> void:
	_stun = maxf(_stun, t)


## dropped out of the cat's mouth: shakes it off and bolts
func released() -> void:
	caught = false
	freeze = false
	_t = 0.15


func pinned() -> void:
	if caught:
		return
	caught = true
	linear_velocity = Vector3.ZERO
	freeze = true


func _physics_process(dt: float) -> void:
	if caught or freeze:
		return
	if _stun > 0.0:
		_stun -= dt
		return
	_tail.rotation.y = sin(Time.get_ticks_msec() * 0.01) * 0.4
	var fwd := -global_transform.basis.z
	_gait.step(dt, maxf(linear_velocity.dot(fwd), 0.0), "half_bound")
	_body.position.y = _gait.dy
	_body.rotation.x = _gait.pitch
	_t -= dt
	var flee := Vector3.ZERO
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p:
		var d := global_position - p.global_position
		d.y = 0
		var pv := p.velocity
		var fast := Vector2(pv.x, pv.z).length() > 1.4
		if (d.length() < 1.2 and fast) or d.length() < 0.35:
			flee = d.normalized()
	if _t < 0.0 or (flee != Vector3.ZERO and _t < 0.3):
		_t = _rng.randf_range(0.8, 2.6) if flee == Vector3.ZERO else _rng.randf_range(0.25, 0.45)
		var a := _rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		if flee != Vector3.ZERO:
			dir = (flee * 1.5 + dir * 0.4).normalized()
		look_at(global_position + dir, Vector3.UP)
		apply_central_impulse(dir * mass * _rng.randf_range(1.0, 1.8) * (2.2 if flee != Vector3.ZERO else 1.0))
	# don't wander off the map
	if global_position.length() > 36.0:
		apply_central_force(-global_position.normalized() * mass * 3.0)
