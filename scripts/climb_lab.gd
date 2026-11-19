extends Node3D
## free climbing lab: the real CatPlayer (bot driven) clings to things and climbs every which way.
##   godot --headless --path . res://climblab.tscn -- --climbtest [--only box,trunk]
##   godot --path . res://climblab.tscn -- --show [--legacy] --write-movie out/f.png --fixed-fps 30   (xvfb)
## --legacy = FreeClimb.off (old up only climb) for before / after.
##
## runs (each starts with the claws already in, facing the thing):
##   box     a 0.4 m square bark trunk: climb up a bit, then right all the way round it (4 outside corners)
##   trunk   a round tree trunk (CylinderShape3D): sideways round it, then diagonal up-left
##   inside  an L of two fence walls: right into the inside corner, onto the second wall
##   post    a 10 cm sisal post: round it, then up and mantle onto the top platform
##   down    down and left on the box, ends on the floor
##   lunge   space + direction = climb lunge along the wall, stays on
##   stamina bar empty -> claws give out, falls off
##   top     straight up the box to its top, mantles over

const RUNS := ["box", "trunk", "inside", "post", "down", "lunge", "stamina", "top"]
const SHOW_RUNS := ["box", "trunk", "inside", "post"]

var player: CatPlayer
var cam: Camera3D
var show := false
var runs: Array = []
var ri := -1
var t := 0.0
var m := {}
var results := {}
var caption: Label
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_init := false

const BOX_C := Vector3(0, 0, 0)        # bark box trunk, 0.4 x 2.6 x 0.4
const TRUNK_C := Vector3(4, 0, 0)      # cylinder r 0.2
const TRUNK_R := 0.2
const L_C := Vector3(-4, 0, 0)         # inside corner
const POST_C := Vector3(8, 0, 0)       # sisal post 0.1, platform on top at 1.3 m


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	show = "--show" in args
	process_priority = 100
	FreeClimb.off = "--legacy" in args
	var only := []
	var k := args.find("--only")
	if k >= 0:
		only = Array(args[k + 1].split(","))
	for r in (SHOW_RUNS if show and only.is_empty() else RUNS):
		if only.is_empty() or r in only:
			runs.append(r)
	_build()
	player = CatPlayer.new()
	add_child(player)
	var fp := "--fp" in args
	if show:
		player.set_third_person(not fp)
	if show and not fp:
		cam = Camera3D.new()
		cam.fov = 45.0
		cam.near = 0.02
		add_child(cam)
		cam.make_current()
	if show:
		var cl := CanvasLayer.new()
		add_child(cl)
		caption = Label.new()
		caption.position = Vector2(24, 18)
		caption.add_theme_font_size_override("font_size", 30)
		caption.add_theme_color_override("font_outline_color", Color.BLACK)
		caption.add_theme_constant_override("outline_size", 8)
		cl.add_child(caption)
	_next.call_deferred()


# ---------------------------------------------------------------- world

func _build() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.64, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.63, 0.68)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 14.0
	add_child(sun)
	_box(Vector3(2, -0.05, 0), Vector3(20, 0.1, 8), Color(0.42, 0.5, 0.32), "grass", false)
	var bark := Color(0.4, 0.29, 0.2)
	_box(BOX_C + Vector3(0, 1.3, 0), Vector3(0.4, 2.6, 0.4), bark, "bark", false)
	_cyl(TRUNK_C + Vector3(0, 1.5, 0), TRUNK_R, 3.0, bark.lightened(0.1), "bark")
	# inside corner: wall along x (facing +z) meets wall along z (facing -x) at L_C
	_box(L_C + Vector3(-0.6, 1.0, -0.05), Vector3(1.2, 2.0, 0.1), Color(0.62, 0.5, 0.36), "wood", true)
	_box(L_C + Vector3(0.05, 1.0, 0.6), Vector3(0.1, 2.0, 1.2), Color(0.58, 0.47, 0.34), "wood", true)
	_box(POST_C + Vector3(0, 0.65, 0), Vector3(0.1, 1.3, 0.1), Color(0.78, 0.66, 0.46), "sisal", false)
	_box(POST_C + Vector3(0, 1.32, 0), Vector3(0.5, 0.04, 0.5), Color(0.82, 0.78, 0.72), "carpet", false)


func _box(c: Vector3, s: Vector3, col: Color, surf: String, group: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = c
	body.set_meta("surface", surf)
	if group:
		body.add_to_group("climbable")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	return body


func _cyl(c: Vector3, r: float, h: float, col: Color, surf: String) -> void:
	var body := StaticBody3D.new()
	body.position = c
	body.set_meta("surface", surf)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


# ---------------------------------------------------------------- runs

## puts the cat on the face of a thing (n = face normal, p = point on the face) with claws in
func _cling(p: Vector3, n: Vector3, h: float) -> void:
	var feet := Vector3(p.x, h, p.z) + n * (CatPlayer.RADIUS + 0.012)
	player.global_position = feet
	player.velocity = Vector3.ZERO
	var y := atan2(n.x, n.z)
	player.yaw = y
	player.orb_yaw = y
	player._start_climb(n)


func _next() -> void:
	if ri >= 0:
		_report(runs[ri])
	ri += 1
	if ri >= runs.size():
		_summary()
		get_tree().quit()
		return
	var r: String = runs[ri]
	t = 0.0
	m = {"turn": 0.0, "prev_n": Vector3.ZERO, "events": [], "max_y": 0.0, "min_y": 99.0, "off_t": -1.0, "lunge": false, "dist_err": 0.0, "dist_n": 0, "end_climb": false}
	player.bot = {"move": Vector2.ZERO, "yaw": 0.0, "pitch": -0.1}
	player.climb_cool = 0.0
	player.mantling = false
	player.clambering = false
	player.scratching = false
	player.climbing = false
	player.log_events = OS.get_environment("CL_LOG") != ""
	player.stamina.value = CatStamina.MAX
	player.stamina.winded = false
	match r:
		"box", "down", "lunge", "top":
			_cling(BOX_C + Vector3(0, 0, 0.2), Vector3(0, 0, 1), 0.6 if r != "down" else 1.0)
		"stamina":
			player.bot["stamina"] = true
			_cling(BOX_C + Vector3(0, 0, 0.2), Vector3(0, 0, 1), 0.8)
		"trunk":
			_cling(TRUNK_C + Vector3(0, 0, TRUNK_R), Vector3(0, 0, 1), 0.6)
		"inside":
			# on the x wall (faces +z), 0.5 m left of the corner
			_cling(L_C + Vector3(-0.5, 0, 0.0), Vector3(0, 0, 1), 0.6)
		"post":
			_cling(POST_C + Vector3(0, 0, 0.05), Vector3(0, 0, 1), 0.5)
	player.bot["yaw"] = player.yaw
	m.prev_n = player.climb_n
	if caption:
		caption.text = ("before (up only)" if FreeClimb.off else "free climb") + "  -  " + {"box": "round a square trunk", "trunk": "round a tree trunk", "inside": "into an inside corner", "post": "round a thin post + mantle"}.get(r, r)


func _script(r: String) -> Dictionary:
	# returns {"move": Vector2, "jump": bool, "done": bool}
	var mv := Vector2.ZERO
	var jump := false
	var done := false
	match r:
		"box":
			if t < 0.8: mv = Vector2(0, 1)
			elif t < (5.2 if show else 8.5): mv = Vector2(1, 0)
			else: done = true
		"trunk":
			if t < 5.5: mv = Vector2(1, 0)
			elif t < 7.5: mv = Vector2(-0.7, 0.7)
			else: done = true
		"inside":
			if t < 1.1: mv = Vector2(1, 0)
			elif t < 3.4: mv = Vector2(0, 1) if (player.climbing or player.mantling or player.clambering) else Vector2.ZERO
			else: done = true
		"post":
			if t < 2.5: mv = Vector2(1, 0)
			elif player.climbing or player.mantling or player.clambering: mv = Vector2(0, 1)
			done = t > 7.0
		"down":
			if player.climbing: mv = Vector2(-0.6, -1)
			done = t > 3.5
		"lunge":
			if t < 0.4: mv = Vector2(0, 0)
			elif t < 0.5: mv = Vector2(1, 0.3); jump = true
			elif t < 1.6: mv = Vector2(1, 0.3)
			else: done = true
		"stamina":
			if t > 0.3 and t < 0.35:
				player.stamina.value = 0.0
			mv = Vector2(0, 1)
			done = t > 1.5
		"top":
			mv = Vector2(0, 1) if (player.climbing or player.mantling or player.clambering or t < 0.3) else Vector2.ZERO
			done = t > 6.0
	return {"move": mv, "jump": jump, "done": done}


func _physics_process(dt: float) -> void:
	if ri < 0 or ri >= runs.size():
		return
	t += dt
	var r: String = runs[ri]
	var s := _script(r)
	if player.climbing:
		player.bot["yaw"] = player.orb_yaw   # bot camera turns round with the climb like a player's would
	player.bot["move"] = s.move
	player.bot["jump"] = s.jump
	if player.climbing:
		var n: Vector3 = player.climb_n
		var pn: Vector3 = m.prev_n
		var a := atan2(pn.cross(n).y, pn.dot(n))
		m.turn += a
		m.prev_n = n
		# body stays snug on the surface: distance from feet to the face along -n
		var c := player.global_position + Vector3.UP * 0.12
		var q := PhysicsRayQueryParameters3D.create(c, c - n * 0.5)
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			m.dist_err = maxf(m.dist_err, absf((hit.position - c).dot(-n) - (CatPlayer.RADIUS + 0.01)))
			m.dist_n += 1
		if player.climb_lunge_t > 0.0:
			m.lunge = true
	elif m.off_t < 0.0:
		m.off_t = t
	if OS.get_environment("CL_DBG") == r and fmod(t, 0.05) < dt:
		print("DBG t=%.2f pos=%s climb=%s cl=%s mant=%s floor=%s ceil=%s n=%s st=%.2f" % [t, player.global_position.snapped(Vector3.ONE * 0.01), player.climbing, player.clambering, player.mantling, player.is_on_floor(), player.is_on_ceiling(), player.climb_n.snapped(Vector3.ONE * 0.01), player.stamina.value])
	m.max_y = maxf(m.max_y, player.global_position.y)
	m.min_y = minf(m.min_y, player.global_position.y)
	if s.done or t > 14.0:
		m.end_climb = player.climbing
		m.end_pos = player.global_position
		m.end_floor = player.is_on_floor()
		_next()


func _process(dt: float) -> void:
	if cam and ri >= 0 and ri < runs.size():
		_camera(dt)


func _camera(dt: float) -> void:
	var r: String = runs[ri]
	var centre: Vector3 = {"box": BOX_C, "trunk": TRUNK_C, "inside": L_C + Vector3(-0.3, 0, 0.3), "post": POST_C}.get(r, BOX_C)
	var target: Vector3 = player.rig.chest.global_position
	# orbit slowly with the cat, from a bit out and up
	var to_cat := Vector3(target.x - centre.x, 0, target.z - centre.z)
	if to_cat.length() < 0.05:
		to_cat = Vector3(0, 0, 1)
	to_cat = to_cat.normalized()
	var want := centre + to_cat.rotated(Vector3.UP, 0.5) * 1.9 + Vector3.UP * (target.y + 0.35)
	if r == "inside":
		want = L_C + Vector3(-1.5, target.y + 0.5, 1.7)   # out in the open quadrant, both walls in view
	if not _cam_init or t < 0.05:
		_cam_pos = want
		_cam_look = target
		_cam_init = true
	_cam_pos = _cam_pos.lerp(want, clampf(dt * 2.5, 0, 1))
	_cam_look = _cam_look.lerp(target, clampf(dt * 6.0, 0, 1))
	cam.global_position = _cam_pos
	cam.look_at(_cam_look, Vector3.UP)


func _report(r: String) -> void:
	var turn_deg: float = rad_to_deg(m.turn)
	var ok := true
	var why := ""
	var ep: Vector3 = m.get("end_pos", player.global_position)
	match r:
		"box":
			ok = absf(turn_deg) > 330.0 and m.end_climb
			why = "turned %.0f deg round the box, still on: %s" % [turn_deg, m.end_climb]
		"trunk":
			ok = absf(turn_deg) > 200.0 and m.end_climb and m.dist_err < 0.04
			why = "turned %.0f deg round the trunk, still on: %s, worst gap error %.0f mm" % [turn_deg, m.end_climb, m.dist_err * 1000]
		"inside":
			ok = absf(turn_deg) > 70.0 and (m.end_climb or ep.y > 1.9)
			why = "turned %.0f deg into the corner, then up: ended y %.2f (wall top 2.0)" % [turn_deg, ep.y]
		"post":
			ok = absf(turn_deg) > 150.0 and ep.y > 1.3 and not m.end_climb
			why = "turned %.0f deg round the post, ended at y %.2f (platform 1.34), climbing %s" % [turn_deg, ep.y, m.end_climb]
		"down":
			ok = m.get("end_floor", false) and not m.end_climb and m.off_t > 0.0
			why = "reached floor %s, let go at %.2f s" % [m.get("end_floor", false), m.off_t]
		"lunge":
			ok = m.lunge and m.end_climb
			why = "lunged %s, still on %s" % [m.lunge, m.end_climb]
		"stamina":
			ok = m.off_t > 0.0 and m.off_t < 0.6
			why = "fell off at %.2f s (bar emptied at 0.3 s)" % m.off_t
		"top":
			ok = ep.y > 2.55 and not m.end_climb
			why = "ended at y %.2f (top 2.6), climbing %s" % [ep.y, m.end_climb]
	results[r] = ok
	print("CLIMBTEST %s %s  %s" % [r, "ok" if ok else "FAIL", why])


func _summary() -> void:
	var all := true
	for r in results:
		all = all and results[r]
	print("CLIMBTEST " + ("PASS" if all else "FAIL") + " " + str(results))
