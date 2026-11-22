class_name BiomePuzzles
extends Node
## cat puzzles for the desert + the mountain. same rules as the rest (puzzles.gd): real cat things,
## verbs the cat already has, no words on screen, the world answers with a chime + treats. they
## count in the pause menu tally (Puzzles.LIST) and show up under cat sense (crouch + keep still).
## desert
##   windmill    the windmill's brake wedge is jammed on the platform (3.4 m) and the trough is bone
##               dry. climb the tower, swat the wedge off: the wheel spins up, the pump pours, the
##               trough fills. then have a drink (keep still at the trough)
##   tumbleweed  tumbleweeds bowl down the wash on the wind. catch one: pounce on it or swat it while
##               it's rolling
##   box         there's a cardboard box in the locked shack. if it fits, i sits: in through the broken
##               window off the rain barrel, then sit in the box
## mountain
##   snowball    a snowball on the lip of the first cliff, right above the hut, whose door is snowed in.
##               knock it off: it thumps into the drift, the drift collapses, the cat flap swings open,
##               the stove's warm inside
##   marmot      the marmot sentry scans from its lookout rock and whistles at anything it sees. sneak
##               right up to it without being spotted (come from behind, crouched and slow)
##   summit      climb to the cairn on the summit and sit a moment
## online: everything is built from fixed seeds, so every player gets the same props in the same
## places. the two puzzles that change the world (mill running, drift gone) keep that in `stage`;
## `net_state()` / `net_apply()` give a host a small dictionary to send and replay on others.

var z                    # the Puzzles node this hangs off (untyped, like MorePuzzles)
var biome := ""
var stage := {}          # puzzle id -> 0 untouched, 1 world changed (mill running / drift gone), 2 solved
var t := 0.0
# desert
var wedge: RigidBody3D
var wedge_peak := 0.0
var mill: Dictionary
var mill_spin := 0.0
var pour_t := 0.0
var drink_t := 0.0
var _creak_t := 0.0
var pour_fx: CPUParticles3D
var weeds: Array[RigidBody3D] = []
var box_t := 0.0
var shack: Dictionary
# mountain
var ball: RigidBody3D
var ball_peak := 0.0
var ball_idle := 0.0
var hut: Dictionary
var sentry: Beast

const WIND := 1.4         # tumbleweed push (N per kg-ish)
const WEED_R := 0.28
const DRINK_T := 1.5
const BOX_T := 2.0


static func desert(root: Node3D, p: CatPlayer) -> Puzzles:
	var zz := Puzzles._plain(root, p)
	var b := BiomePuzzles.new()
	b.name = "BiomePuzzles"
	b.z = zz
	b.biome = "desert"
	zz.add_child(b)
	b._build_desert()
	return zz


static func mountain(root: Node3D, p: CatPlayer) -> Puzzles:
	var zz := Puzzles._plain(root, p)
	var b := BiomePuzzles.new()
	b.name = "BiomePuzzles"
	b.z = zz
	b.biome = "mountain"
	zz.add_child(b)
	b._build_mountain()
	return zz


func _ready() -> void:
	process_physics_priority = 5


# ================================================================== desert

func _build_desert() -> void:
	mill = DesertLevel.mill_info
	shack = DesertLevel.shack_info
	stage = {"windmill": 0, "tumbleweed": 0, "box": 0}
	# the brake wedge, jammed at the north edge of the platform under the wheel
	var pf: Vector3 = mill.platform
	wedge = RigidBody3D.new()
	wedge.name = "BrakeWedge"
	wedge.mass = 0.3
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.16, 0.09, 0.11)
	cs.shape = bs
	wedge.add_child(cs)
	wedge.position = pf + Vector3(0.25, 0.046, -0.6)
	wedge.rotation.y = 0.3
	z.add_child(wedge)
	var mi := MeshInstance3D.new()
	mi.mesh = PSX.box_mesh(Vector3(0.16, 0.09, 0.11), 2.0)
	mi.material_override = PSX.mat("wood", Color(0.8, 0.55, 0.35))
	wedge.add_child(mi)
	wedge.set_meta("loud", true)
	wedge_peak = wedge.position.y
	# water pouring from the spout (off till the mill runs)
	pour_fx = CPUParticles3D.new()
	pour_fx.amount = 40
	pour_fx.lifetime = 0.5
	pour_fx.direction = Vector3(0.3, -1, 0)
	pour_fx.spread = 8.0
	pour_fx.initial_velocity_min = 0.4
	pour_fx.initial_velocity_max = 0.7
	pour_fx.gravity = Vector3(0, -9.8, 0)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.03, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.7, 0.85, 1.0)
	qm.material = m
	pour_fx.mesh = qm
	pour_fx.position = mill.spout
	pour_fx.emitting = false
	z.add_child(pour_fx)
	# three tumbleweeds bowling down the wash
	for k in 3:
		var w := _tumbleweed(k)
		_respawn_weed(w, -34.0 + k * 22.0)
	z.sense.add_point("windmill", pf + Vector3(0, 0.3, 0))
	z.sense.add_point("tumbleweed", BiomeKit.at(0.0, DesertLevel.wash_z(0.0), 0.3))
	z.sense.add_point("box", shack.box + Vector3(0, 0.1, 0))


func _tumbleweed(k: int) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "Tumbleweed%d" % k
	rb.mass = 0.25
	rb.linear_damp = 0.4
	rb.angular_damp = 0.3
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.6
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = WEED_R
	cs.shape = sp
	rb.add_child(cs)
	z.add_child(rb)
	# a ball of dry twigs: thin sticks criss-crossing every which way
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + k
	var mat := PSX.mat("wood", Color(0.86, 0.72, 0.5))
	for i in 26:
		var st := MeshInstance3D.new()
		st.mesh = PSX.box_mesh(Vector3(0.012, 0.012, WEED_R * 2.0 * rng.randf_range(0.7, 1.0)), 4.0)
		st.material_override = mat
		st.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		st.position = Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05))
		rb.add_child(st)
	rb.set_meta("recent", 0.0)
	rb.set_meta("stuck", 0.0)
	weeds.append(rb)
	return rb


func _respawn_weed(w: RigidBody3D, x := -36.0) -> void:
	var p := BiomeKit.at(x, DesertLevel.wash_z(x) + randf_range(-0.6, 0.6), WEED_R + 0.3)
	w.global_position = p
	w.linear_velocity = Vector3(1.5, 0, 0)
	w.angular_velocity = Vector3.ZERO
	w.freeze = false
	w.sleeping = false
	w.set_meta("stuck", 0.0)


func _desert_tick(dt: float) -> void:
	var p: CatPlayer = z.player
	# --- windmill
	if stage.windmill == 0 and is_instance_valid(wedge):
		wedge_peak = maxf(wedge_peak, wedge.global_position.y)
		if wedge_peak - wedge.global_position.y > 1.2 and wedge.linear_velocity.length() < 0.6:
			z._play("crash", wedge.global_position, 0.6, 1.8)
			_mill_on()
	if stage.windmill >= 1:
		mill_spin = LowPoly.damp(mill_spin, 2.6, 0.6, dt)
		(mill.wheel as Node3D).rotation.z += mill_spin * dt
		_creak_t -= dt
		if _creak_t <= 0.0:
			_creak_t = 2.4
			_snd("creak", (mill.wheel as Node3D).global_position, 0.6)
		var water := mill.water as MeshInstance3D
		var tc: Vector3 = mill.trough
		if pour_t < 4.0:
			pour_t += dt
			pour_fx.emitting = true
			water.visible = true
			water.position.y = tc.y + 0.07 + 0.3 * clampf(pour_t / 4.0, 0.0, 1.0)
			if fmod(pour_t, 1.9) < dt:
				_snd("pour", mill.spout, 0.6)
		else:
			pour_fx.emitting = fmod(t, 6.0) < 1.5   # the pump keeps topping it up now and then
	if stage.windmill == 1 and pour_t >= 4.0:
		var tc: Vector3 = mill.trough
		var ts: Vector3 = mill.trough_size
		var rel := p.global_position - tc
		var dx := maxf(absf(rel.x) - ts.x * 0.5, 0.0)
		var dz := maxf(absf(rel.z) - ts.z * 0.5, 0.0)
		var near := Vector2(dx, dz).length() < 0.35 and rel.y > -0.2 and rel.y < ts.y + 0.25
		drink_t = drink_t + dt if (near and _still(p)) else maxf(drink_t - dt * 2.0, 0.0)
		if drink_t >= DRINK_T:
			stage.windmill = 2
			z._spill(tc + Vector3(-0.6, 0, 0.0), 4, 0.25, tc.y)
			z._solve("windmill", tc)
	# --- tumbleweeds
	for w in weeds:
		if not is_instance_valid(w):
			continue
		var wp := w.global_position
		if w.freeze:
			if float(w.get_meta("held", 0.0)) <= 0.0:
				_respawn_weed(w)
			w.set_meta("held", float(w.get_meta("held", 0.0)) - dt)
			continue
		# wind along the wash (+x), pulled toward its middle so they follow the bends, little hops
		var gust := 0.7 + 0.5 * sin(t * 0.7 + wp.z) + 0.3 * sin(t * 2.3)
		var toward := clampf((DesertLevel.wash_z(wp.x) - wp.z) * 0.8, -1.0, 1.0)
		w.apply_central_force(Vector3(WIND * gust, 0, toward * 0.6) * w.mass * 4.0)
		if randf() < dt * 0.8 and wp.y - BiomeKit.y(wp.x, wp.z) < WEED_R + 0.05:
			w.apply_central_impulse(Vector3(0, 0.35, 0) * w.mass * 4.0)
		var sp := w.linear_velocity.length()
		w.set_meta("recent", maxf(float(w.get_meta("recent")) - dt * 2.0, sp))
		w.set_meta("stuck", float(w.get_meta("stuck")) + dt if sp < 0.15 else 0.0)
		if wp.x > 37.0 or wp.y < -3.0 or float(w.get_meta("stuck")) > 8.0 or absf(wp.z) > 38.0:
			_respawn_weed(w)
			continue
		# caught: paws on it while it's on the move (a pounce, a swat, or landing on it)
		var d := Vector2(p.global_position.x - wp.x, p.global_position.z - wp.z).length()
		var dy := p.global_position.y - wp.y
		var strike := p.pounce_air or (p.combat != null and p.combat.atk != "") or not p.is_on_floor()
		if d < WEED_R + 0.25 and dy > -0.4 and dy < 0.6 and float(w.get_meta("recent")) > 0.6 and strike:
			w.freeze = true
			w.set_meta("held", 2.5)
			_snd("scuttle", wp, 0.6, 0.6)
			if stage.tumbleweed < 2:
				stage.tumbleweed = 2
				z._spill(Vector3(wp.x, BiomeKit.y(wp.x, wp.z), wp.z), 3, 0.3)
				z._solve("tumbleweed", wp)
	# --- box
	if stage.box < 2:
		var bx: Vector3 = shack.box
		var bw: Vector3 = shack.box_size
		var rel := p.global_position - bx
		var inside := absf(rel.x) < bw.x * 0.5 - 0.04 and absf(rel.z) < bw.z * 0.5 - 0.04 and rel.y > -0.05 and rel.y < 0.2
		box_t = box_t + dt if (inside and _still(p)) else maxf(box_t - dt * 2.0, 0.0)
		if box_t >= BOX_T:
			stage.box = 2
			z._spill(bx + Vector3(0.6, 0, 0.5), 4, 0.2, bx.y - 0.02)
			z._solve("box", bx)


func _mill_on() -> void:
	stage.windmill = maxi(stage.windmill, 1)
	_snd("creak", (mill.wheel as Node3D).global_position, 0.9)


# ================================================================== mountain

func _build_mountain() -> void:
	hut = MountainLevel.hut_info
	stage = {"snowball": 0, "marmot": 0, "summit": 0}
	ball = RigidBody3D.new()
	ball.name = "Snowball"
	ball.mass = 0.5
	ball.angular_damp = 1.5
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	ball.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.2
	cs.shape = sp
	ball.add_child(cs)
	z.add_child(ball)
	var mi := MeshInstance3D.new()
	mi.mesh = BiomeKit.rock_mesh(Vector3(0.42, 0.4, 0.42), 5)
	mi.material_override = PSX.mat("snow", Color(1, 1, 1))
	ball.add_child(mi)
	ball.set_meta("loud", true)
	_reset_ball()
	for b in get_tree().get_nodes_in_group("wild"):
		if b is Beast and (b as Beast).kind == "marmot" and (b as Beast).sentry:
			sentry = b
	z.more.sit(MountainLevel.summit_spot, "summit", 0.5)
	z.sense.add_point("snowball", MountainLevel.ball_at + Vector3(0, 0.2, 0))
	z.sense.add_point("marmot", sentry.home if sentry else BiomeKit.at(MountainLevel.SENTRY.x, MountainLevel.SENTRY.y, 0.6))
	z.sense.add_point("summit", MountainLevel.summit_spot)


func _reset_ball() -> void:
	ball.global_position = MountainLevel.ball_at + Vector3(0, 0.21, 0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.sleeping = true
	ball_peak = ball.global_position.y
	ball_idle = 0.0


func _mountain_tick(dt: float) -> void:
	# --- snowball into the drift
	if stage.snowball == 0 and is_instance_valid(ball):
		var bp := ball.global_position
		ball_peak = maxf(ball_peak, bp.y)
		var dropped := ball_peak - bp.y > 1.5
		var drift := hut.drift as Node3D
		var dd := Vector2(bp.x - drift.global_position.x, bp.z - drift.global_position.z).length()
		if dropped and dd < 2.4:
			_drift_burst(true)
		elif dropped and ball.linear_velocity.length() < 0.3:
			ball_idle += dt
			if ball_idle > 4.0:
				_reset_ball()     # missed: another one rolls up on the lip
		elif bp.y < -3.0:
			_reset_ball()
	# --- marmot sentry
	if stage.marmot < 2 and sentry and sentry.startled:
		stage.marmot = 2
		var at := sentry.global_position
		z._spill(Vector3(at.x, BiomeKit.y(at.x, at.z + 0.9), at.z + 0.9), 3, 0.2)
		z._solve("marmot", at)
	if stage.summit < 2 and int(Puzzles.solved.get("summit", 0)) > 0:
		stage.summit = 2


## the drift collapses, the flap swings open. `award` = this cat did it (false: replaying a host's world)
func _drift_burst(award: bool) -> void:
	stage.snowball = maxi(stage.snowball, 1)
	var drift := hut.drift as Node3D
	var at := drift.global_position
	_snd("thump", at, 1.0)
	z._play("crash", at, 0.5, 0.6)
	# snow chunks flying
	var fx := CPUParticles3D.new()
	fx.one_shot = true
	fx.amount = 60
	fx.lifetime = 1.2
	fx.explosiveness = 0.95
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fx.emission_box_extents = Vector3(1.2, 0.4, 1.0)
	fx.direction = Vector3(0, 1, 0)
	fx.spread = 60.0
	fx.initial_velocity_min = 1.0
	fx.initial_velocity_max = 3.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1)
	qm.material = m
	fx.mesh = qm
	fx.position = at
	z.add_child(fx)
	fx.emitting = true
	drift.queue_free()
	if is_instance_valid(ball):
		ball.queue_free()
	# what's left: a low ring of slush, and the flap swung up out of the way
	var rest := MeshInstance3D.new()
	rest.mesh = BiomeKit.rock_mesh(Vector3(2.6, 0.12, 1.6), 1)
	rest.material_override = PSX.mat("snow", Color(1, 1, 1))
	rest.position = Vector3(at.x, at.y - 0.25, at.z - 0.3)
	z.add_child(rest)
	var flap := hut.flap as Node3D
	var cs := flap.get_child(0) as CollisionShape3D
	if cs:
		cs.disabled = true
	flap.position += Vector3(0, 0.12, -0.12)
	flap.rotation.x = -1.35
	if award:
		stage.snowball = 2
		var inside: Vector3 = hut.inside
		z._spill(inside, 5, 0.3, inside.y)
		z._solve("snowball", hut.door)


# ================================================================== shared

func _physics_process(dt: float) -> void:
	t += dt
	if z == null or not is_instance_valid(z.player):
		return
	if biome == "desert":
		_desert_tick(dt)
	else:
		_mountain_tick(dt)


func _still(p: CatPlayer) -> bool:
	return Vector2(p.velocity.x, p.velocity.z).length() < 0.3 and p.is_on_floor()


func _snd(clip: String, at: Vector3, vol := 1.0, pitch := 1.0) -> void:
	var s = get_tree().current_scene.get("sound") if get_tree().current_scene else null
	if s is BiomeSound:
		(s as BiomeSound).play(clip, at, vol, pitch)


## world state for online play: only what changes the level for everyone (the mill turning, the
## drift gone). per-cat puzzle credit stays per cat
func net_state() -> Dictionary:
	if biome == "desert":
		return {"mill": stage.get("windmill", 0) >= 1}
	return {"drift": stage.get("snowball", 0) >= 1}


func net_apply(d: Dictionary) -> void:
	if d.get("mill", false) and stage.get("windmill", 0) == 0:
		if is_instance_valid(wedge):
			wedge.queue_free()
		_mill_on()
	if d.get("drift", false) and stage.get("snowball", 0) == 0 and is_instance_valid(hut.get("drift")):
		_drift_burst(false)
