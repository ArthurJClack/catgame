class_name ToyMouse
extends RigidBody3D
## wind up toy mouse: skitters around in short bursts, bolts when the cat gets close.
## pounce on it (forepaws pin it) to catch it.

var caught := false
var _t := 0.8
var _rng := RandomNumberGenerator.new()
var _wheels: Node3D


func _ready() -> void:
	_rng.seed = 11
	mass = 0.05
	linear_damp = 1.6
	angular_damp = 6.0
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	add_to_group("prey")
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.035, 0.03, 0.07)
	cs.shape = b
	cs.position.y = 0.015
	add_child(cs)
	var grey := Color(0.62, 0.6, 0.6)
	LowPoly.part(self, LowPoly.box(), grey, Vector3(0, 0.017, 0.004), Vector3(0.036, 0.028, 0.062))
	LowPoly.part(self, LowPoly.cone(4), grey, Vector3(0, 0.014, -0.038), Vector3(0.026, 0.03, 0.026), Vector3(-PI / 2, PI / 4, 0))
	LowPoly.part(self, LowPoly.box(), Color(0.95, 0.6, 0.65), Vector3(0, 0.014, -0.055), Vector3(0.008, 0.008, 0.008))
	for s in [-1, 1]:
		LowPoly.part(self, LowPoly.box(), Color(0.95, 0.7, 0.72), Vector3(s * 0.013, 0.035, -0.012), Vector3(0.016, 0.016, 0.004))
		LowPoly.part(self, LowPoly.box(), Color(0.05, 0.05, 0.05), Vector3(s * 0.009, 0.022, -0.04), Vector3(0.004, 0.004, 0.004))
	# string tail
	var tail := LowPoly.part(self, LowPoly.box(0.0), Color(0.85, 0.3, 0.3), Vector3(0, 0.008, 0.07), Vector3(0.003, 0.003, 0.07))
	tail.rotation.y = 0.2


var _stun := 0.0


## swatted: dazed for a moment (an easy pounce)
func stun(t: float) -> void:
	_stun = maxf(_stun, t)


## dropped out of the cat's mouth: shakes it off and skitters again
func released() -> void:
	caught = false
	freeze = false
	_t = 0.2


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
	_t -= dt
	var flee := Vector3.ZERO
	for p in get_tree().get_nodes_in_group("player"):
		var d: Vector3 = global_position - (p as Node3D).global_position
		d.y = 0
		# stalking low and slow doesn't spook it, rushing in does
		var pv: Vector3 = (p as CharacterBody3D).velocity
		if d.length() < 0.9 and Vector2(pv.x, pv.z).length() > 1.2 and (p as CharacterBody3D).is_on_floor():
			flee = d.normalized()
	if _t < 0.0 or (flee != Vector3.ZERO and _t < 0.4):
		_t = _rng.randf_range(1.6, 3.0) if flee == Vector3.ZERO else _rng.randf_range(0.35, 0.6)
		var a := _rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		if flee != Vector3.ZERO:
			dir = (flee + dir * 0.5).normalized()
		look_at(global_position + dir, Vector3.UP)
		apply_central_impulse(dir * mass * _rng.randf_range(1.2, 2.0))
