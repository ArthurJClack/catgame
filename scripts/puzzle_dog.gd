class_name QuietPaws
extends Node3D
## cat puzzle "quiet paws" (plan #9) on pier 9: the night guard's dog is asleep on a mat outside
## the guard hut, on a chain. its dinner bowl (sausage bits) sits by the hut wall, right under its nose.
## everything the cat does makes noise: how fast it moves, what it walks on (grating clangs,
## puddles splash, concrete is ok, stalking is near silent), hard landings, meowing. the dog hears
## it by distance, with its ears at its head end, and walls in between muffle it. it stirs (ear
## flick, head up) before it wakes; awake, it barks and lunges as far as the chain goes, then
## settles back down once things are quiet. stalk in, eat for a few seconds, and get
## out without waking it.
## made by Puzzles.docks (puzzles.gd), tested in puzzle_test.gd (G quiet paws).

const CHAIN := 3.2              # chain length from the post
const HEAR := 2.0               # loudness scale: heard = noise * HEAR / d^2
const HEAR_MIN := 0.3           # below this it sleeps through it
const WAKE := 1.0
const DECAY := 0.12             # alert lost per quiet second
const EAT_T := 2.5              # seconds at the bowl to clear it
const CALM_T := 6.0             # awake: quiet this long and it lies back down
const RUN := 4.2                # dog chase speed (a cantering cat gets away)
const SURF := {"metal": 1.6, "grate": 1.8, "corrugated": 1.6, "concrete": 1.0, "paint": 0.9, "wood": 0.9,
	"hazard": 1.0, "fabric": 0.4, "default": 1.0}
const C_DOG := Color(0.45, 0.32, 0.2)
const C_DARK := Color(0.16, 0.12, 0.1)

var z: Node3D                   # the Puzzles node (untyped: avoids a class cycle)
var puddles: Array = []         # [Rect2] in xz: splashy
var dog: Node3D
var _parts := {}
var bed := Vector3.ZERO         # where it sleeps (centre of the body)
var post := Vector3.ZERO
var bowl := Vector3.ZERO
var _bowl_food: Node3D
var alert := 0.0                # 0 asleep .. 1 awake
var awake := false
var wakes := 0
var _quiet_t := 0.0
var _bark_t := 0.0
var _up := 0.0                  # 0 lying .. 1 standing (pose)
var eat_t := 0.0
var done := false
var noise := 0.0                # last tick's cat noise (tests / hud)
var heard := 0.0
var max_alert := 0.0            # highest alert since reset_max() (tests)
var _was_floor := true
var _vy := 0.0
var _meows := 0
var _shoved_t := 0.0
var shoves := 0
var _chain: Array[MeshInstance3D] = []
var t := 0.0


static func build(puz: Node3D, bed_pos: Vector3, post_pos: Vector3, bowl_pos: Vector3, puddle_rects: Array) -> QuietPaws:
	var q := QuietPaws.new()
	q.name = "QuietPaws"
	q.z = puz
	q.bed = bed_pos
	q.post = post_pos
	q.bowl = bowl_pos
	q.puddles = puddle_rects
	puz.add_child(q)
	q._build()
	if puz.get("_sfx") is Dictionary:
		puz._sfx["bark"] = puz._wav(0.22, func(s: float) -> float:
			var f := 260.0 + 220.0 * exp(-s * 18.0)
			var e := minf(s * 60.0, 1.0) * exp(-s * 11.0)
			return (sin(TAU * f * s) * 0.6 + sin(TAU * f * 2.02 * s) * 0.35 + randf_range(-1, 1) * 0.35) * e)
		puz._sfx["growl"] = puz._wav(0.6, func(s: float) -> float:
			return (sin(TAU * 95.0 * s + sin(TAU * 30.0 * s) * 2.0) * 0.5 + randf_range(-1, 1) * 0.15) * sin(PI * s / 0.6))
	return q


# ---------------------------------------------------------------- build

func _p(parent: Node3D, key: String, col: Color, pos: Vector3, scl: Vector3, rot := Vector3.ZERO, mesh: Mesh = null) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	LowPoly.part(n, mesh if mesh else LowPoly.box(0.02), col, Vector3.ZERO, scl)
	if key != "":
		_parts[key] = n
	return n


func _build() -> void:
	# mat, chain post, bowl
	LowPoly.part(self, LowPoly.box(0.0), Color(0.35, 0.18, 0.15), bed + Vector3(0, 0.01, 0), Vector3(1.1, 0.02, 0.7))
	LowPoly.part(self, LowPoly.box(0.0), Color(0.3, 0.3, 0.32), post + Vector3(0, 0.25, 0), Vector3(0.06, 0.5, 0.06))
	LowPoly.part(self, LowPoly.box(0.0), Color(0.55, 0.55, 0.58), bowl + Vector3(0, 0.04, 0), Vector3(0.26, 0.08, 0.26))
	_bowl_food = Node3D.new()
	_bowl_food.position = bowl + Vector3(0, 0.085, 0)
	add_child(_bowl_food)
	for k in 7:
		var a := TAU * k / 7.0
		LowPoly.part(_bowl_food, LowPoly.box(0.0), Color(0.75, 0.35, 0.3), Vector3(cos(a) * 0.06, 0, sin(a) * 0.06), Vector3(0.05, 0.025, 0.03), Vector3(0, a, 0))
	# the dog: a ~25 kg farm dog, built as a pivot (dog) -> body -> head etc, posed in _pose()
	dog = Node3D.new()
	dog.name = "GuardDog"
	dog.position = bed
	dog.rotation.y = PI * 0.5       # head toward -x: nose right by its bowl
	add_child(dog)
	var body := _p(dog, "body", C_DOG, Vector3(0, 0.2, 0), Vector3(0.3, 0.3, 0.72))
	LowPoly.part(body, LowPoly.box(0.02), C_DOG.lightened(0.25), Vector3(0, -0.1, -0.15), Vector3(0.24, 0.1, 0.3))
	var neck := _p(body, "neck", C_DOG, Vector3(0, 0.08, -0.38), Vector3(0.18, 0.2, 0.18))
	var head := _p(neck, "head", C_DOG, Vector3(0, 0.08, -0.1), Vector3(0.2, 0.19, 0.22))
	LowPoly.part(head, LowPoly.box(0.01), C_DOG.lightened(0.15), Vector3(0, -0.04, -0.17), Vector3(0.12, 0.1, 0.16))
	LowPoly.part(head, LowPoly.box(0.0), C_DARK, Vector3(0, -0.01, -0.255), Vector3(0.05, 0.04, 0.02))
	for s in [-1, 1]:
		_p(head, "ear%d" % s, C_DOG.darkened(0.25), Vector3(s * 0.08, 0.07, 0.03), Vector3(0.07, 0.12, 0.03), Vector3(0, 0, s * 0.5))
		_p(head, "eye%d" % s, C_DARK, Vector3(s * 0.06, 0.03, -0.11), Vector3(0.03, 0.006, 0.01))
	var tail := _p(body, "tail", C_DOG.darkened(0.1), Vector3(0, 0.08, 0.36), Vector3(0.05, 0.05, 0.3), Vector3(0.6, 0, 0))
	tail.get_child(0).position = Vector3(0, 0, 0.15)
	for i in 4:
		var fx := -0.1 if i % 2 == 0 else 0.1
		var fz := -0.27 if i < 2 else 0.25
		var leg := _p(body, "leg%d" % i, C_DOG.darkened(0.05), Vector3(fx, -0.1, fz), Vector3(0.07, 0.3, 0.07))
		leg.get_child(0).position = Vector3(0, -0.15, 0)
	# chain: a few dark links between the post and the collar
	for k in 8:
		var mi := MeshInstance3D.new()
		mi.mesh = LowPoly.box(0.0)
		mi.material_override = LowPoly.mat(Color(0.25, 0.25, 0.27))
		add_child(mi)
		_chain.append(mi)
	_pose(0.0)


## up 0 = curled up asleep on its side of the mat, 1 = standing
func _pose(dt: float) -> void:
	var body: Node3D = _parts.body
	var head: Node3D = _parts.head
	var neck: Node3D = _parts.neck
	var stir := clampf((alert - 0.25) / 0.4, 0.0, 1.0) if not awake else 1.0
	var breathe := sin(t * (2.0 if not awake else 5.0)) * (0.012 if not awake else 0.006)
	body.position.y = lerpf(0.16, 0.48, _up) + breathe
	body.scale = Vector3(1.0 + breathe * 2.0, 1.0, 1.0)
	body.rotation.z = lerpf(0.35, 0.0, _up)
	# head: on its paws asleep, lifts when it stirs, up when awake
	neck.rotation.x = lerpf(0.55, -0.35, maxf(stir * 0.7, _up))
	head.rotation.x = lerpf(0.0, 0.2, _up)
	for s in [-1, 1]:
		var ear: Node3D = _parts["ear%d" % s]
		var flick := sin(t * 23.0) * 0.4 if alert > 0.25 and fmod(t, 2.1) < 0.25 and not awake else 0.0
		ear.rotation = Vector3(lerpf(0.5, -0.1, maxf(stir, _up)) + flick, 0, s * lerpf(0.9, 0.3, maxf(stir, _up)))
		var eye: Node3D = _parts["eye%d" % s]
		eye.scale.y = lerpf(1.0, 4.0, maxf(stir * 0.6, _up))
	for i in 4:
		var leg: Node3D = _parts["leg%d" % i]
		# asleep: legs tucked forward along the ground. awake: under it
		leg.rotation.x = lerpf(-1.45 if i < 2 else 1.3, 0.0, _up)
		if awake and dog.get_meta("moving", false):
			leg.rotation.x += sin(t * 14.0 + (PI if i in [0, 3] else 0.0)) * 0.5
	var tail: Node3D = _parts.tail
	tail.rotation.x = lerpf(-0.9, 0.5, _up)
	tail.rotation.y = sin(t * 9.0) * 0.3 * _up
	# chain from the post to the collar, sagging
	var collar: Vector3 = neck.global_position
	for k in _chain.size():
		var u := (k + 0.5) / _chain.size()
		var p := post + Vector3(0, 0.45, 0)
		var a := p.lerp(collar, u)
		var span := Vector2(collar.x - p.x, collar.z - p.z).length()
		a.y = lerpf(p.y, collar.y, u) - sin(u * PI) * maxf(CHAIN - span, 0.0) * 0.35
		a.y = maxf(a.y, 0.015)
		var b := p.lerp(collar, u + 1.0 / _chain.size())
		var dir := b - a
		if dir.length() < 0.001 or absf(dir.normalized().y) > 0.98:
			dir = Vector3(collar.x - p.x, 0.0, collar.z - p.z) + Vector3(0.001, 0, 0)
		_chain[k].global_transform = Transform3D(Basis.looking_at(dir.normalized()) * Basis.from_scale(Vector3(0.02, 0.02, CHAIN / _chain.size() * 0.9)), a)


# ---------------------------------------------------------------- noise

func _cat() -> CatPlayer:
	var p = z.get("player")
	return p if p is CatPlayer and is_instance_valid(p) else null


func _surface_mul(p: CatPlayer) -> float:
	var pos := p.global_position
	for r in puddles:
		if (r as Rect2).has_point(Vector2(pos.x, pos.z)) and pos.y < 0.1:
			return 2.4
	return float(SURF.get(p.surface, 1.0))


## how much noise the cat is making right now (a steady level) + one off spikes (landings, meows)
func cat_noise(p: CatPlayer, dt: float) -> Vector2:
	var hv := Vector2(p.velocity.x, p.velocity.z).length()
	var on_floor := p.is_on_floor()
	var sneaking: bool = p.crouch_amt > 0.5
	var steady := 0.0
	if on_floor and hv > 0.05:
		# real cats are near silent stalking, padding is soft, running thumps
		steady = (0.12 if sneaking else 0.3) * minf(hv / 0.7, 1.0) if hv < 1.2 else 0.25 + (hv - 1.2) * 0.32
		steady *= _surface_mul(p)
	var spike := 0.0
	if on_floor and not _was_floor:
		var drop := maxf(-_vy - 2.2, 0.0)
		spike += drop * 0.45 * _surface_mul(p) * (0.6 if sneaking else 1.0)
	_was_floor = on_floor
	_vy = p.velocity.y
	# meows (the cat's own sounds log them)
	var m := 0
	for c in CatSfx.played:
		if c.begins_with("meow") or c == "yowl":
			m += 1
	if m > _meows:
		spike += 2.5
	_meows = m
	if eat_t > 0.0 and hv < 0.2:
		steady += 0.1     # crunching
	return Vector2(steady, spike)


func _muffled(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var p := _cat()
	if p:
		q.exclude = [p.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func ears() -> Vector3:
	return (_parts.head as Node3D).global_position


# ---------------------------------------------------------------- tick

func _physics_process(dt: float) -> void:
	t += dt
	var p := _cat()
	if p == null:
		return
	var n := cat_noise(p, dt)
	noise = n.x
	var e := ears()
	var cp := p.global_position + Vector3(0, 0.15, 0)
	var d := maxf(e.distance_to(cp), 0.6)
	var mul := HEAR / (d * d)
	if d < 6.0 and _muffled(e, cp):
		mul *= 0.35
	heard = n.x * mul
	if heard > HEAR_MIN:
		alert += (heard - HEAR_MIN) * 1.4 * dt
	else:
		alert -= DECAY * dt
	alert += n.y * mul * 0.5
	alert = clampf(alert, 0.0, 1.2)
	max_alert = maxf(max_alert, alert)
	if not awake and alert >= WAKE:
		_wake()
	if awake:
		_awake_tick(p, dt, heard > HEAR_MIN or n.y * mul > 0.2)
	else:
		_up = move_toward(_up, 0.0, dt * 1.2)
		dog.position = dog.position.move_toward(bed, dt * 1.5)
	_pose(dt)
	_eat_tick(p, dt)


func _wake() -> void:
	awake = true
	wakes += 1
	_quiet_t = 0.0
	_bark_t = 0.0
	eat_t = 0.0
	z._play("growl", ears(), 0.6)


func _awake_tick(p: CatPlayer, dt: float, noisy: bool) -> void:
	_up = move_toward(_up, 1.0, dt * 4.0)
	_quiet_t = 0.0 if noisy else _quiet_t + dt
	var cp := p.global_position
	var to := Vector3(cp.x - dog.position.x, 0, cp.z - dog.position.z)
	var near := to.length() < 6.0 and cp.y < 0.8
	# go for the cat, as far as the chain lets it
	var goal := dog.position
	if near and _up > 0.8:
		goal = cp
		var off := Vector3(goal.x - post.x, 0, goal.z - post.z)
		if off.length() > CHAIN:
			goal = post + off.normalized() * CHAIN
		goal.y = 0
	var before := dog.position
	dog.position = dog.position.move_toward(Vector3(goal.x, 0, goal.z), RUN * dt)
	dog.set_meta("moving", dog.position.distance_to(before) > 0.2 * dt)
	if to.length() > 0.05:
		dog.rotation.y = lerp_angle(dog.rotation.y, atan2(-to.x, -to.z), minf(dt * 8.0, 1.0))
	# barking, a lot
	_bark_t -= dt
	if _bark_t <= 0.0 and (near or _quiet_t < 2.0):
		_bark_t = randf_range(0.35, 0.7)
		z._play("bark", ears(), 1.0, randf_range(0.92, 1.08))
	# caught up with the cat: shoves it away (no bite)
	_shoved_t -= dt
	var cd := Vector2(cp.x - dog.position.x, cp.z - dog.position.z)
	if cd.length() < 0.55 and cp.y < 0.6 and _shoved_t <= 0.0:
		_shoved_t = 0.8
		shoves += 1
		var push := Vector3(cd.x, 0, cd.y).normalized() * 5.0
		p.velocity = push + Vector3(0, 2.5, 0)
		CatSfx.play_at("hiss", cp, 0.8)
	# lies back down once nothing has bothered it for a while
	if _quiet_t > CALM_T and (not near or to.length() > CHAIN + 1.0):
		awake = false
		alert = 0.45
		dog.set_meta("moving", false)


func _eat_tick(p: CatPlayer, dt: float) -> void:
	if done:
		return
	var d := p.global_position - bowl
	var at_bowl := Vector2(d.x, d.z).length() < 0.4 and absf(d.y) < 0.3
	if at_bowl and not awake:
		eat_t += dt
		if fmod(eat_t, 0.45) < dt:
			z._play("crunch", bowl, 0.4, randf_range(0.9, 1.1))
		_bowl_food.scale = Vector3.ONE * clampf(1.0 - eat_t / EAT_T, 0.05, 1.0)
		if eat_t >= EAT_T:
			done = true
			_bowl_food.visible = false
			z._ate(6)
			z._solve("quiet_paws", bowl)


func reset_max() -> void:
	max_alert = alert
