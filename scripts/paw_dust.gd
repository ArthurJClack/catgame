class_name PawDust
extends Node
## dirt / dust kicked up right under a paw, and only when that paw actually pushes hard:
## takeoffs (hop, pounce, leap, auto bound), hard landings, sprint starts, hard stops,
## sharp cuts, wall kicks. steady running at a constant speed kicks up nothing.
##
## how it works: every physics tick the body's change in velocity (the push the ground had
## to give) is handed out to the paws that were planted for it (hind paws take a bigger
## share). when a paw lifts off, if the push it delivered over its stance was big enough it
## throws a puff from exactly where it stood, away from the way the body accelerated.
## landings throw a puff at each paw as it touches down.

const PUSH_MIN := 0.95     # m/s of body velocity one paw has to deliver over its stance
const PUSH_FULL := 2.0     # ... for a full size puff
const LAND_MIN := 2.4      # m/s downward at touch down before the paws throw anything
const LAND_FULL := 6.0
const WALL_MIN := 2.5      # m/s velocity change pushing off a wall / climb
const HIND_W := 1.4        # hind paws do more of the pushing
const MAX_LIVE := 28       # emitters alive at once (cheap cpu particles, but still)

var player: CharacterBody3D
var enabled := true
var log_puffs := false     # tests: print every puff
var puffs := 0             # tests: how many puffs so far
var last_kinds := {}       # tests: kind -> count

var _imp := Vector3.ZERO
var _acc: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _was: Array[bool] = [false, false, false, false]
var _at: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _st: Array[float] = [0.0, 0.0, 0.0, 0.0]   # time on the ground this stance
var _land_t := 0.0
var _land_s := 0.0
var _land_done: Array[bool] = [true, true, true, true]
var _prev_v := Vector3.ZERO
var _prev_floor := true
var _prev_wallish := false
var _live := 0
var _rig: Node3D = null


func _ready() -> void:
	process_priority = 100   # after the rig has stepped its paws this frame


## called by the player at the end of every physics tick
func physics_tick(_dt: float) -> void:
	var p: Variant = player
	var v: Vector3 = p.velocity
	var fl: bool = p.is_on_floor()
	var wallish: bool = p.climbing or p.clambering or p.mantling or p.scratching
	var dv := v - _prev_v
	var bumped := false
	for k in p.get_slide_collision_count():
		if (p.get_slide_collision(k) as KinematicCollision3D).get_normal().y < 0.7:
			bumped = true   # ran into something: that's the wall stopping the cat, not a paw push
	if fl and _prev_floor and not wallish:
		# grip limited ground pushes: starts, stops, cuts (vertical is just slopes / snapping)
		# paws slipping = pushing right at their grip limit: that's as hard as it gets, so
		# skids and carved turns count extra (they're spread over short gallop stances)
		if not bumped:
			_imp += Vector3(dv.x, 0.0, dv.z) * (1.0 + 1.5 * clampf(float(p.slip), 0.0, 1.0))
	elif _prev_floor and not fl and dv.y > 0.5:
		# left the ground by its own push: hop, pounce, aimed leap, side hop, bound
		_imp += dv
	elif not _prev_floor and fl:
		var impact := maxf(-_prev_v.y, -float(p.prev_vy))
		if impact > LAND_MIN:
			_land_s = clampf((impact - LAND_MIN) / (LAND_FULL - LAND_MIN), 0.15, 1.0)
			_land_t = 0.3
			_land_done = [false, false, false, false]
	elif not fl and (dv.length() > WALL_MIN) and dv.y > 0.5 and (_prev_wallish or float(p.wall_time) < 0.1):
		# kicked off a wall / jumped off a climb: the hind paws push against the wall
		var n: Vector3 = p.climb_n if _prev_wallish else p.wall_normal
		if n.length() > 0.5:
			_wall_puffs(n, clampf((dv.length() - WALL_MIN) / 3.0, 0.2, 1.0))
	_prev_v = v
	_prev_floor = fl
	_prev_wallish = wallish


func _process(dt: float) -> void:
	if player == null or not enabled:
		return
	var rig: Node3D = player.rig
	if rig == null or not rig.use_planting:
		_imp = Vector3.ZERO
		return
	if rig != _rig:
		# cat model swapped: start the bookkeeping over
		_rig = rig
		for i in 4:
			_was[i] = false
			_acc[i] = Vector3.ZERO
	var g: CatGait = rig.gait
	# hand this frame's push to the paws that were on the ground for it
	var wsum := 0.0
	for i in 4:
		if _was[i]:
			wsum += HIND_W if i >= 2 else 1.0
	if wsum > 0.0:
		for i in 4:
			if _was[i]:
				_acc[i] += _imp * ((HIND_W if i >= 2 else 1.0) / wsum)
		_imp = Vector3.ZERO
	elif not player.is_on_floor():
		_imp = Vector3.ZERO
	# (all paws mid swing at a gallop: the push waits for the next paw that comes down)
	for i in 4:
		var planted: bool = g.mode[i] == CatGait.PLANTED
		if planted and not _was[i]:
			_acc[i] = Vector3.ZERO
			_st[i] = 0.0
			if _land_t > 0.0 and not _land_done[i]:
				_land_done[i] = true
				_puff(g.pos[i], _land_s * (1.0 if i < 2 else 0.8), Vector3.ZERO, "land")
		elif _was[i] and not planted:
			# lift off: this is the moment the paw finishes its push
			var a := _acc[i].length()
			if a > PUSH_MIN:
				var s := clampf((a - PUSH_MIN) / (PUSH_FULL - PUSH_MIN), 0.15, 1.0)
				_puff(_at[i], s, _acc[i] / a, "push")
			_acc[i] = Vector3.ZERO
		elif planted and _st[i] > 0.12 and _acc[i].length() > PUSH_MIN * 1.2:
			# a long stance that keeps digging in (skid to a stop, a slow hard shove): puff
			# from where it stands and keep counting
			var a2 := _acc[i].length()
			_puff(g.pos[i], clampf((a2 - PUSH_MIN) / (PUSH_FULL - PUSH_MIN), 0.15, 1.0), _acc[i] / a2, "dig")
			_acc[i] = Vector3.ZERO
		if planted:
			_at[i] = g.pos[i]
			_st[i] += dt
		_was[i] = planted
	_land_t -= dt


func _wall_puffs(n: Vector3, s: float) -> void:
	var rig: Node3D = player.rig
	if rig == null:
		return
	for i in [2, 3]:
		var paw: Node3D = rig.legs[i].paw
		var hit := _ray(paw.global_position + n * 0.06, paw.global_position - n * 0.1)
		if not hit.is_empty():
			_emit(hit, s, n, "wall")


func _puff(at: Vector3, s: float, push_dir: Vector3, kind: String) -> void:
	var hit := _ray(at + Vector3.UP * 0.06, at + Vector3.DOWN * 0.08)
	if hit.is_empty():
		return   # the paw wasn't on anything
	_emit(hit, s, push_dir, kind)


func _emit(hit: Dictionary, s: float, push_dir: Vector3, kind: String) -> void:
	if _live >= MAX_LIVE:
		return
	var n: Vector3 = hit.normal
	var sf := _surface_of(hit)
	var soft: bool = sf in ["grass", "dirt", "hay"]
	var plush: bool = sf in ["carpet", "rug"]
	var col := Color(0.8, 0.75, 0.7)   # a little dust off a hard floor
	match sf:
		"grass": col = Color(0.35, 0.55, 0.22)
		"dirt": col = Color(0.45, 0.35, 0.22)
		"hay": col = Color(0.85, 0.74, 0.42)
		"carpet", "rug": col = Color(0.75, 0.72, 0.68)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(2, int(round(lerpf(3.0, 11.0, s) * (1.0 if soft else (0.35 if plush else 0.6)))))
	p.lifetime = 0.55 if soft else 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.012   # about a paw print
	if kind == "land":
		# splash out round the paw
		p.direction = n
		p.spread = 80.0
		p.initial_velocity_min = 0.25 + 0.3 * s
		p.initial_velocity_max = 0.6 + 0.9 * s
	else:
		# thrown back off the paw, opposite to where the body went
		var back := -push_dir
		back -= n * back.dot(n)
		p.direction = (back.normalized() * 0.9 + n).normalized() if back.length() > 0.1 else n
		p.spread = 28.0
		p.initial_velocity_min = 0.5 + 0.6 * s
		p.initial_velocity_max = 1.0 + 1.4 * s
	# grit falls, dust hangs
	p.gravity = Vector3(0, -9.8, 0) if soft else Vector3(0, -2.5, 0)
	p.damping_min = 0.0 if soft else 2.0
	p.damping_max = 0.0 if soft else 3.0
	p.scale_amount_min = 0.006
	p.scale_amount_max = 0.014 + 0.006 * s
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(0.7, 0.8))
	shrink.add_point(Vector2(1, 0))
	p.scale_amount_curve = shrink
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE
	pm.material = LowPoly.mat(col, 1.0)
	p.mesh = pm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_tree().current_scene.add_child(p)
	p.global_position = (hit.position as Vector3) + n * 0.006
	p.emitting = true
	_live += 1
	player.get_tree().create_timer(p.lifetime + 0.3).timeout.connect(func() -> void:
		_live -= 1
		p.queue_free())
	puffs += 1
	last_kinds[kind] = int(last_kinds.get(kind, 0)) + 1
	if log_puffs:
		print("puff %s %.2f %s at %s" % [kind, s, sf, (hit.position as Vector3).snapped(Vector3.ONE * 0.01)])


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q)


func _surface_of(hit: Dictionary) -> String:
	var c: Object = hit.collider
	if c is Node:
		var nd := c as Node
		if nd.has_meta("surface_at"):
			return (nd.get_meta("surface_at") as Callable).call(hit.position)
		if nd.has_meta("surface"):
			return nd.get_meta("surface")
		if nd.is_in_group("climbable") or nd.is_in_group("scratchable"):
			return "carpet"
	return "default"
