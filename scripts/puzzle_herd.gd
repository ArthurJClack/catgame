class_name HerdChicks
extends Node3D
## cat puzzle "herd the chicks" (plan #8, farm version of the ducklings): five chicks are loose
## in the yard north of the house, east of the barn door. their pen (low wire fence, a little
## coop, grain inside) has one gap on the west side. chicks keep a flight distance from the cat
## like real ones: walk up slowly and they trot away from you, so where you stand steers them.
## run at them, swat or pounce near them and they panic and scatter every which way. get all five
## inside at once and the gate swings shut behind them, and the farmer's treats spill outside.
## chicks aren't prey (no catching them) and the fence is low: cats hop it, chicks can't.
## made by Puzzles.farm (puzzles.gd), tested in puzzle_test.gd (F herd the chicks).

const N := 5
const R := 0.07                 # chick body radius
const FLEE_R := 1.7             # flight distance: inside this a chick walks away from the cat
const PANIC_R := 3.0            # a running cat inside this scatters them
const PANIC_SPD := 3.5          # m/s of cat that counts as running at them
const WALK := 0.18              # pottering about
const TROT := 0.9               # walking away from a close cat
const BOLT := 2.0               # panicking
const SOLVE_T := 1.2            # all inside this long = done
# the pen (x0, z0, x1, z1) and its west gap
const PEN := Rect2(21.4, 10.4, 3.2, 3.6)
const GAP_Z := Vector2(11.55, 12.85)
const WALL_H := 0.5
# where they roam: between the barn's north wall, the east fence and the house side
const YARD := Rect2(13.5, 4.5, 12.0, 11.0)
const C_FENCE := Color(0.62, 0.55, 0.45)
const C_WIRE := Color(0.75, 0.78, 0.8, 0.35)
const C_CHICK := Color(1.0, 0.86, 0.35)
const C_BEAK := Color(0.95, 0.55, 0.15)

var z: Node3D                   # the Puzzles node (untyped: avoids a class cycle)
var chicks: Array[CharacterBody3D] = []
var _st: Array[Dictionary] = []
var grain := Vector3.ZERO
var gate: Node3D
var _gate_a := 0.0
var _in_t := 0.0
var done := false
var panics := 0                 # times a chick bolted (tests / tuning)
var rng := RandomNumberGenerator.new()


static func build(puz: Node3D) -> HerdChicks:
	var h := HerdChicks.new()
	h.name = "HerdChicks"
	h.z = puz
	puz.add_child(h)
	h.rng.seed = 4242
	h._build_pen()
	var starts := [Vector3(16.2, 0, 7.6), Vector3(17.4, 0, 9.4), Vector3(15.6, 0, 11.0), Vector3(18.8, 0, 13.4), Vector3(17.0, 0, 14.6)]
	for p in starts:
		h._chick(p)
	if puz.has_method("_wav") and puz.get("_sfx") is Dictionary:
		puz._sfx["peep"] = puz._wav(0.09, func(s: float) -> float:
			var f := 4300.0 - s * 14000.0
			return sin(TAU * f * s) * sin(PI * s / 0.09) * 0.7)
	return h


# ---------------------------------------------------------------- build

func _wall(a: Vector2, b: Vector2) -> void:
	var c := (a + b) * 0.5
	var horiz := absf(b.x - a.x) > absf(b.y - a.y)
	var len := a.distance_to(b)
	var sb := StaticBody3D.new()
	sb.position = Vector3(c.x, WALL_H * 0.5, c.y)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(len, WALL_H, 0.05) if horiz else Vector3(0.05, WALL_H, len)
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	# chicken wire: a see-through panel, top + bottom rails, a post every ~0.8 m
	var sz := bs.size
	_wire(sb, sz * 0.98)
	for y in [WALL_H * 0.5 - 0.02, -WALL_H * 0.5 + 0.03]:
		LowPoly.part(sb, LowPoly.box(0.0), C_FENCE, Vector3(0, y, 0), Vector3(len, 0.03, 0.035) if horiz else Vector3(0.035, 0.03, len))
	var posts := int(ceil(len / 0.8))
	for k in posts + 1:
		var t := -0.5 + float(k) / posts
		var o := Vector3(t * len, 0.03, 0) if horiz else Vector3(0, 0.03, t * len)
		LowPoly.part(sb, LowPoly.box(0.01), C_FENCE.darkened(0.15), o, Vector3(0.05, WALL_H + 0.06, 0.05))


var _wire_m: StandardMaterial3D


## chicken wire: a see-through grey sheet (a mesh of real wires would be hundreds of parts)
func _wire(parent: Node3D, sz: Vector3) -> void:
	if _wire_m == null:
		_wire_m = StandardMaterial3D.new()
		_wire_m.albedo_color = C_WIRE
		_wire_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wire_m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_wire_m.roughness = 0.6
		_wire_m.metallic = 0.3
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = _wire_m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _build_pen() -> void:
	var x0 := PEN.position.x
	var z0 := PEN.position.y
	var x1 := PEN.end.x
	var z1 := PEN.end.y
	_wall(Vector2(x0, z0), Vector2(x1, z0))
	_wall(Vector2(x0, z1), Vector2(x1, z1))
	_wall(Vector2(x1, z0), Vector2(x1, z1))
	_wall(Vector2(x0, z0), Vector2(x0, GAP_Z.x))
	_wall(Vector2(x0, GAP_Z.y), Vector2(x0, z1))
	# the gate: hinged on the gap's north post, stands open (swung out flat against the fence)
	gate = Node3D.new()
	gate.name = "PenGate"
	gate.position = Vector3(x0, 0, GAP_Z.y)
	add_child(gate)
	var gl := GAP_Z.y - GAP_Z.x
	var gb := StaticBody3D.new()
	gb.position = Vector3(0, WALL_H * 0.5, -gl * 0.5)
	var gcs := CollisionShape3D.new()
	var gbs := BoxShape3D.new()
	gbs.size = Vector3(0.05, WALL_H, gl - 0.04)
	gcs.shape = gbs
	gcs.disabled = true          # open: nothing in the way until it shuts
	gcs.name = "Shape"
	gb.add_child(gcs)
	gb.name = "Body"
	gate.add_child(gb)
	_wire(gb, gbs.size * 0.98)
	for y in [WALL_H * 0.5 - 0.02, -WALL_H * 0.5 + 0.03]:
		LowPoly.part(gb, LowPoly.box(0.0), C_FENCE.lightened(0.1), Vector3(0, y, 0), Vector3(0.035, 0.03, gl - 0.04))
	LowPoly.part(gb, LowPoly.box(0.0), C_FENCE.lightened(0.1), Vector3.ZERO, Vector3(0.03, 0.03, gl * 1.08), Vector3(atan2(WALL_H, gl), 0, 0))
	_gate_a = PI * 0.5
	gate.rotation.y = _gate_a
	# the coop: a little hut in the back corner (climbable, a perch over the pen)
	var coop := StaticBody3D.new()
	coop.name = "Coop"
	coop.position = Vector3(x1 - 0.55, 0.35, z1 - 0.6)
	coop.add_to_group("climbable")
	coop.set_meta("surface", "wood")
	var ccs := CollisionShape3D.new()
	var cbs := BoxShape3D.new()
	cbs.size = Vector3(0.9, 0.7, 0.9)
	ccs.shape = cbs
	coop.add_child(ccs)
	add_child(coop)
	LowPoly.part(coop, LowPoly.box(0.01), Color(0.6, 0.32, 0.25), Vector3.ZERO, cbs.size)
	LowPoly.part(coop, LowPoly.box(0.0), Color(0.12, 0.08, 0.06), Vector3(-0.451, -0.15, 0), Vector3(0.01, 0.3, 0.26))
	LowPoly.part(coop, LowPoly.box(0.01), Color(0.4, 0.38, 0.36), Vector3(0, 0.39, 0), Vector3(1.0, 0.08, 1.0))
	LowPoly.part(coop, LowPoly.box(0.0), C_FENCE, Vector3(-0.62, -0.24, 0), Vector3(0.36, 0.02, 0.18), Vector3(0, 0, 0.55))
	# grain scattered on the ground inside: what they'd rather be doing
	grain = Vector3(x0 + 1.3, 0, (z0 + z1) * 0.5 - 0.1)
	for k in 40:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.45
		LowPoly.part(self, LowPoly.box(0.0), Color(0.85, 0.72, 0.38), grain + Vector3(cos(a) * r, 0.006, sin(a) * r), Vector3(0.012, 0.008, 0.008), Vector3(0, a, 0))


func _chick(at: Vector3) -> void:
	var c := CharacterBody3D.new()
	c.name = "Chick%d" % chicks.size()
	c.collision_layer = 0          # cats walk through them: no shoving a chick about
	c.collision_mask = 1
	c.floor_snap_length = 0.1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = R
	cs.shape = sp
	cs.position = Vector3(0, R, 0)
	c.add_child(cs)
	c.position = at
	add_child(c)
	var body := Node3D.new()
	body.name = "Body"
	c.add_child(body)
	var fluff := C_CHICK.lightened(rng.randf_range(-0.08, 0.08))
	LowPoly.part(body, LowPoly.sphere(7, 5), fluff, Vector3(0, R + 0.01, 0.01), Vector3(0.12, 0.11, 0.14))
	LowPoly.part(body, LowPoly.sphere(6, 4), fluff.lightened(0.05), Vector3(0, R + 0.075, -0.055), Vector3(0.075, 0.075, 0.075))
	LowPoly.part(body, LowPoly.cone(4), C_BEAK, Vector3(0, R + 0.07, -0.1), Vector3(0.02, 0.03, 0.02), Vector3(-PI / 2, 0, 0))
	for s in [-1, 1]:
		LowPoly.part(body, LowPoly.box(0.0), Color(0.08, 0.06, 0.05), Vector3(s * 0.026, R + 0.088, -0.086), Vector3(0.012, 0.012, 0.006))
		LowPoly.part(body, LowPoly.box(0.0), C_BEAK, Vector3(s * 0.025, 0.02, 0.0), Vector3(0.008, 0.045, 0.008))
		LowPoly.part(body, LowPoly.sphere(5, 3), fluff.darkened(0.08), Vector3(s * 0.055, R + 0.015, 0.02), Vector3(0.03, 0.06, 0.09))
	chicks.append(c)
	_st.append({"dir": Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), "wander_t": 0.0,
		"panic_t": 0.0, "pdir": Vector3.ZERO, "peck_t": 0.0, "peep_t": rng.randf_range(0.5, 4.0), "phase": rng.randf() * TAU,
		"yaw": rng.randf() * TAU})


# ---------------------------------------------------------------- tick

func in_pen(p: Vector3) -> bool:
	return p.x > PEN.position.x + 0.05 and p.x < PEN.end.x - 0.05 and p.z > PEN.position.y + 0.05 and p.z < PEN.end.y - 0.05


func inside() -> int:
	var n := 0
	for c in chicks:
		if in_pen(c.global_position):
			n += 1
	return n


func _cat() -> CatPlayer:
	var p = z.get("player")
	return p if p is CatPlayer and is_instance_valid(p) else null


func _physics_process(dt: float) -> void:
	var p := _cat()
	var cp := p.global_position if p else Vector3(1e6, 0, 1e6)
	var cv := Vector2(p.velocity.x, p.velocity.z).length() if p else 0.0
	# a paw strike or a pounce close by is as scary as running at them
	var lunge := false
	if p and p.combat:
		lunge = p.combat.atk != "" or p.pounce_air
	var centre := Vector3.ZERO
	var nout := 0
	for c in chicks:
		if not in_pen(c.global_position):
			centre += c.global_position
			nout += 1
	if nout > 0:
		centre /= nout
	for i in chicks.size():
		_step(i, dt, cp, cv, lunge, centre, nout)
	_gate_tick(dt)
	if done:
		return
	if inside() == N:
		_in_t += dt
		if _in_t >= SOLVE_T:
			_solve()
	else:
		_in_t = 0.0


func _step(i: int, dt: float, cp: Vector3, cv: float, lunge: bool, centre: Vector3, nout: int) -> void:
	var c := chicks[i]
	var s := _st[i]
	var pos := c.global_position
	var away := Vector3(pos.x - cp.x, 0, pos.z - cp.z)
	var dist := away.length()
	away = away / maxf(dist, 0.001)
	var penned := in_pen(pos)
	var cat_in_pen := in_pen(cp)
	var want := Vector3.ZERO
	var spd := WALK
	s.panic_t = maxf(float(s.panic_t) - dt, 0.0)
	# panic: a cat running at them (or swiping) inside the scare radius. settled chicks in the pen
	# feel safe behind the wire unless the cat is in there too
	var scared_by_run := dist < PANIC_R and (cv > PANIC_SPD or (lunge and dist < 1.4))
	if scared_by_run and (not penned or cat_in_pen or dist < 0.8) and float(s.panic_t) <= 0.0:
		s.panic_t = rng.randf_range(0.9, 1.5)
		s.pdir = away.rotated(Vector3.UP, rng.randf_range(-1.3, 1.3))
		panics += 1
		s.peep_t = 0.0
	if float(s.panic_t) > 0.0:
		want = s.pdir
		spd = BOLT
	elif dist < FLEE_R and (not penned or cat_in_pen):
		# the flight zone: the closer the cat, the quicker they walk off, straight away from it
		var k := 1.0 - dist / FLEE_R
		want = away
		spd = lerpf(WALK * 1.5, TROT, k)
		s.peck_t = 0.0
	else:
		# calm: potter, peck, drift back toward the others; in the pen, stay near the grain
		s.wander_t = float(s.wander_t) - dt
		if float(s.wander_t) <= 0.0:
			s.wander_t = rng.randf_range(0.8, 2.4)
			s.dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			s.peck_t = rng.randf_range(0.3, 1.2) if rng.randf() < 0.5 else 0.0
		want = s.dir
		if penned or done:
			var g := grain - pos
			g.y = 0
			if g.length() > 0.3:
				want += g.normalized() * 1.5
		elif nout > 1:
			var tc := centre - pos
			tc.y = 0
			if tc.length() > 1.0:
				want += tc.normalized() * 0.8
		if float(s.peck_t) > 0.0:
			s.peck_t = float(s.peck_t) - dt
			spd = 0.0
	# a little room from each other
	for j in chicks.size():
		if j != i:
			var o := pos - chicks[j].global_position
			o.y = 0
			var l := o.length()
			if l < 0.22 and l > 0.001:
				want += o / l * (0.22 - l) * 6.0
	# keep to the yard (soft walls: they turn along it, no hard bounces)
	var m := 0.6
	if pos.x < YARD.position.x + m: want.x += (YARD.position.x + m - pos.x) * 3.0
	if pos.x > YARD.end.x - m: want.x -= (pos.x - YARD.end.x + m) * 3.0
	if pos.z < YARD.position.y + m: want.z += (YARD.position.y + m - pos.z) * 3.0
	if pos.z > YARD.end.y - m: want.z -= (pos.z - YARD.end.y + m) * 3.0
	want.y = 0
	if want.length() > 0.001:
		want = want.normalized()
	var v := want * spd
	c.velocity.x = lerpf(c.velocity.x, v.x, minf(dt * 8.0, 1.0))
	c.velocity.z = lerpf(c.velocity.z, v.z, minf(dt * 8.0, 1.0))
	c.velocity.y = 0.0 if c.is_on_floor() else c.velocity.y - 9.8 * dt
	c.move_and_slide()
	# hard stop at the yard edge (gate gaps in the fence lead out of the level)
	var np := c.global_position
	np.x = clampf(np.x, YARD.position.x, YARD.end.x)
	np.z = clampf(np.z, YARD.position.y, YARD.end.y)
	if np.y < -0.5:
		np.y = 0.0
	c.global_position = np
	_anim(c, s, dt)
	# peeps: now and then, a lot when scared
	s.peep_t = float(s.peep_t) - dt
	if float(s.peep_t) <= 0.0:
		var scared := float(s.panic_t) > 0.0
		s.peep_t = rng.randf_range(0.12, 0.3) if scared else rng.randf_range(1.5, 5.0)
		z._play("peep", c.global_position, 0.5 if scared else 0.25, rng.randf_range(0.9, 1.25))


func _anim(c: CharacterBody3D, s: Dictionary, dt: float) -> void:
	var b := c.get_node("Body") as Node3D
	var hv := Vector2(c.velocity.x, c.velocity.z)
	var sp := hv.length()
	if sp > 0.05:
		var ty := atan2(c.velocity.x, c.velocity.z) + PI
		s.yaw = lerp_angle(float(s.yaw), ty, minf(dt * 10.0, 1.0))
	b.rotation.y = float(s.yaw)
	s.phase = float(s.phase) + dt * (6.0 + sp * 18.0)
	var ph := float(s.phase)
	b.position.y = absf(sin(ph)) * minf(sp, 1.0) * 0.025
	# pecking: tip forward and back
	b.rotation.x = -0.5 * maxf(sin(ph * 0.8), 0.0) if float(s.peck_t) > 0.0 else -0.15 * minf(sp, 1.5)
	b.rotation.z = sin(ph) * 0.08 * minf(sp, 1.0)


func _gate_tick(dt: float) -> void:
	var target := 0.0 if done else PI * 0.5
	_gate_a = move_toward(_gate_a, target, dt * 2.5)
	gate.rotation.y = _gate_a


func _solve() -> void:
	done = true
	(gate.get_node("Body/Shape") as CollisionShape3D).set_deferred("disabled", false)
	var at := Vector3(PEN.position.x - 0.9, 0, (GAP_Z.x + GAP_Z.y) * 0.5)
	z._play("crash", gate.global_position, 0.35, 2.6)     # the gate clacks shut
	z._spill(at, 7, 0.55, 0.0)
	z._solve("herd", at)
