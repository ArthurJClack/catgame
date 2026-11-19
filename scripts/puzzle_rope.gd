class_name PullString
extends Node3D
## cat puzzle "pull the string" (plan #11): a frayed rope hangs from the barn loft edge, its tail
## just low enough for a cat to bat (bottom ~0.4 m). up top it's tied round a hay bale sitting
## right on the edge of the loft. batting it makes it swing (fun, nothing else). hook it with
## your claws (hold a paw) and drag it away / down a few times, and the bale tips off the edge,
## drops 2.5 m and bursts on the floor: the farmer hid treats in that one.
## the rope is a real chain: ROPE_SEGS rigid bodies on pin joints, so claws hook any bit of it.
## made by Puzzles.farm (puzzles.gd), tested in puzzle_test.gd (E pull string).

const SEGS := 4
const SEG_LEN := 0.46
const SEG_R := 0.022
const TUG_DIST := 0.22         # the tail pulled this far from where it hangs = a tug
const TUGS := 2                # tugs to work the knot loose
const STRAIN := 0.1            # m between where the paw pulls and where the hook is held back
const PULL_T := 0.3            # s of straining = a tug
const C_ROPE := Color(0.8, 0.7, 0.5)
const C_HAY := Color(0.86, 0.74, 0.4)

var z: Node3D           # the Puzzles node (untyped: avoids a class cycle)
var top := Vector3.ZERO        # where the rope is tied under the loft edge
var segs: Array[RigidBody3D] = []
var bale: RigidBody3D
var tugs := 0
var _tugging := false
var _pull_t := 0.0
var strain := 0.0
var falling := false
var done := false
var _fall_t := 0.0
var _peak := 0.0


static func build(puz: Node3D, top_pos: Vector3, bale_pos: Vector3) -> PullString:
	var r := PullString.new()
	r.name = "PullString"
	r.z = puz
	r.top = top_pos
	puz.add_child(r)
	r._build_rope()
	r._build_bale(bale_pos)
	return r


func _build_rope() -> void:
	var anchor := StaticBody3D.new()
	anchor.name = "RopeAnchor"
	anchor.position = top
	var acs := CollisionShape3D.new()
	var asp := SphereShape3D.new()
	asp.radius = 0.01
	acs.shape = asp
	acs.disabled = true
	anchor.add_child(acs)
	add_child(anchor)
	var prev: PhysicsBody3D = anchor
	for i in SEGS:
		var s := RigidBody3D.new()
		s.name = "Rope%d" % i
		s.mass = 0.12
		s.linear_damp = 0.6
		s.angular_damp = 2.0
		s.set_meta("rope", true)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = SEG_R
		cap.height = SEG_LEN
		cs.shape = cap
		s.add_child(cs)
		s.position = top + Vector3(0, -SEG_LEN * (i + 0.5), 0)
		add_child(s)
		# a little twist in the strand so it reads as rope, darker every other bit
		LowPoly.part(s, LowPoly.box(0.0), C_ROPE.darkened(0.08 * (i % 2)), Vector3.ZERO, Vector3(SEG_R * 1.7, SEG_LEN * 1.02, SEG_R * 1.7), Vector3(0, 0.4 * i, 0))
		if i == SEGS - 1:
			# frayed tassel at the end: the bit cats can't leave alone
			for k in 5:
				var a := TAU * k / 5.0
				LowPoly.part(s, LowPoly.box(0.0), C_ROPE.lightened(0.1), Vector3(cos(a) * 0.012, -SEG_LEN * 0.5 - 0.035, sin(a) * 0.012), Vector3(0.008, 0.07, 0.008), Vector3(cos(a) * 0.3, 0, sin(a) * 0.3))
		var j := PinJoint3D.new()
		j.position = top + Vector3(0, -SEG_LEN * i, 0)
		add_child(j)
		j.node_a = j.get_path_to(prev)
		j.node_b = j.get_path_to(s)
		segs.append(s)
		prev = s


func _build_bale(at: Vector3) -> void:
	bale = RigidBody3D.new()
	bale.name = "LooseBale"
	bale.mass = 12.0
	bale.freeze = true
	bale.set_meta("surface", "hay")
	bale.add_to_group("climbable")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.35, 0.45)
	cs.shape = bs
	bale.add_child(cs)
	bale.position = at + Vector3(0, 0.175, 0)
	add_child(bale)
	LowPoly.part(bale, LowPoly.box(0.01), C_HAY.darkened(0.03), Vector3.ZERO, Vector3(0.9, 0.35, 0.45))
	for k in 2:
		LowPoly.part(bale, LowPoly.box(0.0), C_HAY.darkened(0.3), Vector3(-0.2 + k * 0.4, 0, 0), Vector3(0.015, 0.36, 0.46))
	# the rope's knot round the bale's front band
	LowPoly.part(bale, LowPoly.box(0.0), C_ROPE, Vector3(0.0, -0.05, -0.235), Vector3(0.06, 0.06, 0.03))


func tail() -> Vector3:
	return segs[-1].global_position + segs[-1].global_transform.basis.y * -SEG_LEN * 0.5


func rest_tail() -> Vector3:
	return top + Vector3(0, -SEG_LEN * SEGS, 0)


func hooked() -> bool:
	var p: CatPlayer = z.get("player")
	return is_instance_valid(p) and is_instance_valid(p.claw_rb) and p.claw_rb in segs


func _physics_process(dt: float) -> void:
	if done:
		return
	if falling:
		_fall_tick(dt)
		return
	# a tug = hooked and pulling: the tail swung well out, or the cat is straining against the
	# knot (where the paw wants the hook vs where the rope lets it be) for a moment
	if hooked():
		var p: CatPlayer = z.get("player")
		var g := p.claw_rb.to_global(p.claw_local)
		var hold: Vector3 = p.call("_eye_pos") + p.call("_look_dir") * p.claw_dist
		strain = (hold - g).length()
		_pull_t = _pull_t + dt if strain > STRAIN else maxf(_pull_t - dt, 0.0)
		var off := tail().distance_to(rest_tail())
		if not _tugging and (off > TUG_DIST or _pull_t > PULL_T):
			_tugging = true
			tugs += 1
			z._play("crash", bale.global_position, 0.25, 2.2)    # the bale creaks on the edge
			bale.position.z -= 0.06                               # ...and shifts toward the drop
			if tugs >= TUGS:
				_release()
	else:
		_tugging = false      # let go: the next hook + drag is a new tug
		_pull_t = 0.0
		strain = 0.0


func _release() -> void:
	falling = true
	bale.freeze = false
	bale.remove_from_group("climbable")
	bale.apply_central_impulse(Vector3(0, 0.6, -2.4) * bale.mass)
	bale.apply_torque_impulse(Vector3(-1.2, 0, 0.3) * bale.mass * 0.15)
	_peak = bale.global_position.y
	# the rope comes down with it: cut it loose from the anchor
	for c in get_children():
		if c is PinJoint3D and (c as PinJoint3D).node_a == (c as PinJoint3D).get_path_to(get_node("RopeAnchor")):
			c.queue_free()


func _fall_tick(dt: float) -> void:
	_fall_t += dt
	var y := bale.global_position.y
	_peak = maxf(_peak, y)
	if (y < 0.4 and _peak - y > 1.2) or _fall_t > 4.0:
		done = true
		var at := bale.global_position
		z._play("crash", at, 1.0, 0.7)
		z._spill(Vector3(at.x, 0, at.z), 8, 0.6, 0.0)
		z._solve("pull_string", at)
		# it stays where it lands (heavy, swats barely move it): a new step to climb from
		bale.add_to_group("climbable")
