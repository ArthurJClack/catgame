class_name Puzzles
extends Node3D
## cat puzzles, first milestone (see the "cat puzzle plan" doc). everything is things real cats do,
## solved with the verbs the cat already has, and no on screen words: the world answers instead
## (treats spill, a chime, a crash, a fire). all optional side treats, nothing gates the hub yet.
##
## farm (main.tscn):
##   knock it off  treat bag on top of the kitchen wall cabinets (2.2 m). get up there (fridge ->
##                 cabinet jump), swat it off, it bursts on the floor and treats go everywhere.
##   perch route   a sunbeam lands on the barn tie beam over the open floor (3.38 m). loft -> tie
##                 beam -> spine beam -> sunbeam. sit still in it and it pays out.
##   gift          drop something you caught (e) on the doormat outside the patio door. the bowl
##                 next to it fills up. every different catch counts once.
## rat pit (arena.tscn):
##   lanterns      oil lanterns sit on the pillar tops (pillars are rough stone now: climbable).
##                 swat one off and it smashes: rats near it take a heavy hit, then the oil burns
##                 for a few seconds (rats and cats both). they come back each wave.
##
## treats are eaten by walking over them (crunch). `Puzzles.treats_eaten` and `Puzzles.solved`
## live for the whole session (survive scene changes); the puzzles themselves reset each visit.
## test: `godot --headless --path . res://main.tscn -- --puzzletest` and
##       `godot --headless --path . res://arena.tscn -- --puzzletest`, each prints PUZZLETEST PASS/FAIL.
## `--puzzleshow` runs the same thing in third person for a clip (xvfb + --write-movie).

const C_TREAT := Color(1.0, 0.65, 0.25)
const EAT_R := 0.28
const SUN_SIT := 1.5           # seconds sitting in the sunbeam
const LANTERN_HIT := 2.5       # smash damage (heavy)
const LANTERN_R := 1.3
const FIRE_T := 3.5
const FIRE_R := 0.9
const FIRE_TICK := 0.5

static var treats_eaten := 0
static var solved := {}        # puzzle id -> times solved this session

var player: CatPlayer
var arena: Node = null
var treats: Array[Node3D] = []
var t := 0.0
var _sfx := {}

# knock it off
var bag: RigidBody3D
var bag_peak := 0.0
var bag_burst := false
# perch
var sun_spot := Vector3.ZERO
var sun_t := 0.0
var sun_done := false
var _sun_glow: MeshInstance3D
# gift
var mat_pos := Vector3.ZERO
var bowl_pos := Vector3.ZERO
var gifts := 0
var _carried_prev: Node3D = null
# lanterns
var lanterns: Array[RigidBody3D] = []
var fires: Array[Dictionary] = []
var _wave_seen := -1


# ---------------------------------------------------------------- setup

static func farm(root: Node3D, p: CatPlayer) -> Puzzles:
	var z := Puzzles.new()
	z.name = "Puzzles"
	z.player = p
	root.add_child(z)
	z._build_farm()
	z._maybe_test()
	return z


static func pit(root: Node3D, p: CatPlayer) -> Puzzles:
	var z := Puzzles.new()
	z.name = "Puzzles"
	z.player = p
	z.arena = root
	root.add_child(z)
	z._build_pit()
	z._maybe_test()
	return z


func _maybe_test() -> void:
	var a := OS.get_cmdline_user_args()
	if "--puzzletest" in a or "--puzzleshow" in a:
		var pt := PuzzleTest.new()
		pt.z = self
		add_child(pt)


func _build_farm() -> void:
	_sfx_init()
	# knock it off: treat bag on the upper cabinets (top 2.2, front edge z -3.825)
	bag = _treat_bag(Vector3(1.75, 2.2, -3.9))
	# perch: sunbeam on the tie beam at z 20.5 over the barn floor (barn centre 12,0,22; top 3.38)
	sun_spot = Vector3(8.2, 3.38, 20.5)
	_sunbeam(sun_spot)
	# gift: doormat outside the patio door (door x 1.8..2.8, wall z 4.0) + a bowl beside it
	mat_pos = Vector3(2.3, 0.0, 4.55)
	bowl_pos = Vector3(3.05, 0.0, 4.5)
	_doormat(mat_pos)
	_bowl(bowl_pos)


func _build_pit() -> void:
	_sfx_init()
	# pillar tops are rough broken stone: let cats climb them to get above the rats
	var tops: Array[Vector3] = []
	for i in 4:
		var a := TAU * i / 4 + PI / 4
		var h: float = [2.2, 1.3, 2.2, 0.7][i]
		var pp := Vector3(sin(a), 0, cos(a)) * 3.3
		for c in arena.get_children():
			if c is StaticBody3D and Vector2(c.position.x - pp.x, c.position.z - pp.z).length() < 0.05 and absf(c.position.y - h * 0.5) < 0.05:
				c.add_to_group("climbable")
		if i < 3:
			tops.append(pp + Vector3(0, h, 0) - pp.normalized() * 0.12)
	set_meta("tops", tops)
	_place_lanterns()
	_wave_seen = int(arena.get("wave")) if "wave" in arena else 0


# ---------------------------------------------------------------- props

func _treat_bag(pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "TreatBag"
	rb.mass = 0.2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.11, 0.15, 0.06)
	cs.shape = bs
	rb.add_child(cs)
	rb.position = pos + Vector3(0, 0.076, 0)
	add_child(rb)
	LowPoly.part(rb, LowPoly.box(0.01), Color(0.85, 0.2, 0.25), Vector3.ZERO, Vector3(0.11, 0.15, 0.06))
	LowPoly.part(rb, LowPoly.box(0.0), Color(0.95, 0.85, 0.3), Vector3(0, 0.083, 0), Vector3(0.112, 0.018, 0.04))
	LowPoly.part(rb, LowPoly.sphere(6, 4), C_TREAT, Vector3(0, 0.01, 0.031), Vector3(0.05, 0.035, 0.004), Vector3.ZERO, 0.5)
	rb.set_meta("loud", true)
	return rb


func _sunbeam(at: Vector3) -> void:
	# a slanted shaft of dusty light from a gap in the roof boards, and a warm patch on the beam
	var sh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 3.0, 0.3)
	sh.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.92, 0.6, 0.12)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	sh.material_override = m
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.position = at + Vector3(-0.45, 1.45, 0)
	sh.rotation = Vector3(0, 0, -0.3)
	add_child(sh)
	_sun_glow = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 0.004, 0.17)
	_sun_glow.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1.0, 0.9, 0.55, 0.55)
	_sun_glow.material_override = gm
	_sun_glow.position = at + Vector3(0, 0.003, 0)
	add_child(_sun_glow)
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.9, 0.65)
	l.light_energy = 3.0
	l.spot_range = 4.0
	l.spot_angle = 12.0
	l.position = at + Vector3(-0.9, 3.0, 0)
	l.look_at_from_position(l.position, at, Vector3.FORWARD)
	l.light_volumetric_fog_energy = 2.0
	add_child(l)


func _doormat(at: Vector3) -> void:
	var b := StaticBody3D.new()
	b.position = at + Vector3(0, 0.006, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.75, 0.012, 0.45)
	cs.shape = bs
	b.add_child(cs)
	b.set_meta("surface", "rug")
	add_child(b)
	LowPoly.part(b, LowPoly.box(0.0), Color(0.45, 0.3, 0.18), Vector3.ZERO, Vector3(0.75, 0.012, 0.45))
	for k in 5:
		LowPoly.part(b, LowPoly.box(0.0), Color(0.36, 0.23, 0.13), Vector3(-0.3 + k * 0.15, 0.007, 0), Vector3(0.05, 0.003, 0.4))


func _bowl(at: Vector3) -> void:
	var b := StaticBody3D.new()
	b.position = at
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.1
	cy.height = 0.05
	cs.shape = cy
	cs.position.y = 0.025
	b.add_child(cs)
	add_child(b)
	LowPoly.part(b, LowPoly.cyl(0.1, 0.075, 10), Color(0.25, 0.45, 0.75), Vector3(0, 0.025, 0), Vector3(1, 0.05, 1))
	LowPoly.part(b, LowPoly.cyl(0.08, 0.08, 10), Color(0.12, 0.2, 0.35), Vector3(0, 0.049, 0), Vector3(1, 0.004, 1))


func _lantern(pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "Lantern"
	rb.mass = 0.6
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.12, 0.2, 0.12)
	cs.shape = bs
	rb.add_child(cs)
	rb.position = pos + Vector3(0, 0.101, 0)
	rb.freeze = true      # sits put until a paw sends it (the swat code unfreezes non-prey)
	add_child(rb)
	LowPoly.part(rb, LowPoly.box(0.0), Color(0.2, 0.18, 0.15), Vector3(0, -0.09, 0), Vector3(0.12, 0.02, 0.12))
	LowPoly.part(rb, LowPoly.box(0.0), Color(0.2, 0.18, 0.15), Vector3(0, 0.08, 0), Vector3(0.13, 0.03, 0.13))
	LowPoly.part(rb, LowPoly.box(0.0), Color(1.0, 0.7, 0.3), Vector3(0, 0.0, 0), Vector3(0.09, 0.14, 0.09), Vector3.ZERO, 3.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = 0.9
	l.omni_range = 2.2
	rb.add_child(l)
	rb.set_meta("peak", pos.y)
	return rb


func _place_lanterns() -> void:
	for l in lanterns:
		if is_instance_valid(l):
			l.queue_free()
	lanterns.clear()
	for tp in get_meta("tops", []):
		lanterns.append(_lantern(tp))


func _spill(at: Vector3, n: int, spread: float, floor_y := -1.0) -> void:
	for k in n:
		var a := TAU * k / n + randf() * 0.6
		var r := spread * (0.35 + randf() * 0.65)
		var p := at + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = (floor_y if floor_y >= 0.0 else at.y) + 0.03
		_treat(p)


func _treat(p: Vector3) -> void:
	var f := Node3D.new()
	f.position = p
	add_child(f)
	LowPoly.part(f, LowPoly.sphere(6, 4), C_TREAT, Vector3.ZERO, Vector3(0.035, 0.028, 0.07), Vector3.ZERO, 0.8)
	LowPoly.part(f, LowPoly.cone(3), C_TREAT, Vector3(0, 0, 0.045), Vector3(0.035, 0.028, 0.02), Vector3(PI / 2, 0, 0), 0.8)
	f.rotation.y = randf() * TAU
	f.set_meta("base_y", p.y)
	treats.append(f)


# ---------------------------------------------------------------- tick

func _physics_process(dt: float) -> void:
	t += dt
	if not is_instance_valid(player):
		return
	_eat_check()
	if bag:
		_bag_tick()
	if sun_spot != Vector3.ZERO:
		_sun_tick(dt)
	if mat_pos != Vector3.ZERO:
		_gift_tick()
	if arena:
		_lantern_tick()
		_fire_tick(dt)


func _process(_dt: float) -> void:
	for f in treats:
		if is_instance_valid(f):
			f.rotation.y += 0.02
			f.position.y = float(f.get_meta("base_y")) + 0.012 + sin(t * 3.0 + f.position.x * 7.0) * 0.008
	if _sun_glow:
		var gm := _sun_glow.material_override as StandardMaterial3D
		gm.albedo_color.a = 0.25 if sun_done else 0.45 + sin(t * 1.3) * 0.1


func _eat_check() -> void:
	var pp := player.global_position
	for i in range(treats.size() - 1, -1, -1):
		var f := treats[i]
		if not is_instance_valid(f):
			treats.remove_at(i)
			continue
		var d := f.global_position - pp
		if Vector2(d.x, d.z).length() < EAT_R and d.y > -0.3 and d.y < 0.4:
			treats_eaten += 1
			_play("crunch", f.global_position, 0.7, randf_range(0.9, 1.15))
			player.call("_event", "ate a treat (%d)" % treats_eaten)
			f.queue_free()
			treats.remove_at(i)


func _solve(id: String, at: Vector3) -> void:
	solved[id] = int(solved.get(id, 0)) + 1
	_play("chime", at, 0.8)
	player.call("_event", "puzzle: " + id)


func _bag_tick() -> void:
	if bag_burst or not is_instance_valid(bag):
		return
	var y := bag.global_position.y
	bag_peak = maxf(bag_peak, y)
	# it went over the edge and hit the floor
	if y < 0.2 and bag_peak > 1.2:
		bag_burst = true
		var at := bag.global_position
		_play("crash", at, 0.9, 1.4)
		_spill(Vector3(at.x, 0, at.z), 7, 0.45, 0.0)
		# the torn bag stays where it landed
		for c in bag.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).scale.y *= 0.4
		_solve("knock_it_off", at)


func _sun_tick(dt: float) -> void:
	if sun_done:
		return
	var d := player.global_position - sun_spot
	var in_sun := Vector2(d.x, d.z).length() < 0.35 and absf(d.y) < 0.3
	var still := Vector2(player.velocity.x, player.velocity.z).length() < 0.3 and player.is_on_floor()
	sun_t = sun_t + dt if (in_sun and still) else maxf(sun_t - dt * 2.0, 0.0)
	if sun_t >= SUN_SIT:
		sun_done = true
		_spill(sun_spot + Vector3(0.35, 0, 0), 3, 0.12)
		_solve("perch_sunbeam", sun_spot)


func _gift_tick() -> void:
	var c: Node3D = player.carried
	if c == null and is_instance_valid(_carried_prev):
		var g := _carried_prev
		var d := g.global_position - mat_pos
		if absf(d.x) < 0.5 and absf(d.z) < 0.4 and absf(d.y) < 0.3 and not g.has_meta("gifted"):
			g.set_meta("gifted", true)
			gifts += 1
			_spill(bowl_pos + Vector3(0, 0.03, 0), 2 + mini(gifts, 3), 0.05, 0.03)
			_solve("gift", mat_pos)
	_carried_prev = c


func _lantern_tick() -> void:
	var w: int = int(arena.get("wave")) if "wave" in arena else 0
	if w != _wave_seen:
		_wave_seen = w
		_place_lanterns()
	for i in range(lanterns.size() - 1, -1, -1):
		var l := lanterns[i]
		if not is_instance_valid(l):
			lanterns.remove_at(i)
			continue
		if l.freeze:
			continue
		var peak: float = l.get_meta("peak")
		var y := l.global_position.y
		if y < 0.16 and peak - y > 0.45:
			_smash(l.global_position)
			l.queue_free()
			lanterns.remove_at(i)


func _smash(at: Vector3) -> void:
	_play("crash", at, 1.0, 0.8)
	var floor_pt := Vector3(at.x, 0.0, at.z)
	for r in get_tree().get_nodes_in_group("enemy"):
		if r is Node3D and r.has_method("take_hit") and (r as Node3D).global_position.distance_to(floor_pt) < LANTERN_R:
			r.call("take_hit", LANTERN_HIT, floor_pt, true, 2.0)
	# burning oil puddle
	var f := Node3D.new()
	f.position = floor_pt
	add_child(f)
	for k in 7:
		var a := TAU * k / 7.0
		LowPoly.part(f, LowPoly.box(0.0), Color(1.0, 0.45 + 0.1 * (k % 3), 0.1), Vector3(cos(a), 0, sin(a)) * randf_range(0.1, FIRE_R * 0.8) + Vector3(0, 0.08, 0), Vector3(0.12, 0.16, 0.12), Vector3(0, a, 0), 4.0)
	LowPoly.part(f, LowPoly.cyl(FIRE_R, FIRE_R, 12), Color(0.15, 0.08, 0.03), Vector3(0, 0.004, 0), Vector3(1, 0.006, 1))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.15)
	l.light_energy = 2.5
	l.omni_range = 3.0
	l.position.y = 0.4
	f.add_child(l)
	fires.append({"node": f, "pos": floor_pt, "t": 0.0, "tick": 0.0})


func _fire_tick(dt: float) -> void:
	for i in range(fires.size() - 1, -1, -1):
		var fd: Dictionary = fires[i]
		fd.t += dt
		fd.tick -= dt
		var n: Node3D = fd.node
		var k := 1.0 - clampf((fd.t - FIRE_T + 0.6) / 0.6, 0.0, 1.0)
		n.scale = Vector3(1, 0.6 + 0.4 * absf(sin(t * 13.0 + i)), 1) * maxf(k, 0.05)
		if fd.tick <= 0.0:
			fd.tick = FIRE_TICK
			for r in get_tree().get_nodes_in_group("enemy"):
				if r is Node3D and r.has_method("take_hit") and (r as Node3D).global_position.distance_to(fd.pos) < FIRE_R:
					r.call("take_hit", 0.6, fd.pos, false, 0.5)
			if player.global_position.distance_to(fd.pos) < FIRE_R and player.health:
				player.health.damage(0.5, fd.pos, 1.2)
		if fd.t >= FIRE_T:
			n.queue_free()
			fires.remove_at(i)


# ---------------------------------------------------------------- sound (synthesised, no assets)

func _sfx_init() -> void:
	_sfx["chime"] = _wav(0.7, func(s: float) -> float:
		var e := exp(-s * 5.0)
		var f := 880.0 if s < 0.12 else 1318.5
		return (sin(TAU * f * s) * 0.6 + sin(TAU * f * 2.0 * s) * 0.15) * e)
	_sfx["crash"] = _wav(0.45, func(s: float) -> float:
		return randf_range(-1.0, 1.0) * exp(-s * 9.0) * (0.6 + 0.4 * sin(TAU * 140.0 * s)))
	_sfx["crunch"] = _wav(0.12, func(s: float) -> float:
		return randf_range(-1.0, 1.0) * exp(-s * 40.0) * (1.0 if fmod(s, 0.03) < 0.012 else 0.3))


func _wav(len_s: float, f: Callable) -> AudioStreamWAV:
	var rate := 22050
	var n := int(len_s * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(float(f.call(float(i) / rate)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _play(clip: String, at: Vector3, vol := 1.0, pitch := 1.0) -> void:
	if not _sfx.has(clip) or DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _sfx[clip]
	p.volume_db = linear_to_db(vol)
	p.pitch_scale = pitch
	p.unit_size = 3.0
	add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
