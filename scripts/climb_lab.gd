extends Node3D
## climbing lab: the real CatPlayer (bot driven) climbs, grabs, hauls up and tops out on a
## course of fixtures, and every run is checked for jank as well as for doing the thing.
##   godot --headless --fixed-fps 60 --path . res://climblab.tscn -- --climbtest [--only box,trunk] [--dbg pop|snap|clip|trace]
##   godot --path . --write-movie out/f.png --fixed-fps 30 res://climblab.tscn -- --show [--fp] [--only a,b]   (xvfb; engine flags go before the --)
## (only uses climbing / clambering / mantling, so it runs on old builds too for before / after)
##
## free climb runs (start with the claws already in, facing the thing):
##   box      0.4 m square bark trunk: up a bit, then right all the way round it (4 outside corners)
##   trunk    round tree trunk (cylinder): sideways round it, then diagonal up-left
##   inside   L of two fence walls: right into the inside corner, onto the second wall
##   post     10 cm sisal post: round it, then up onto the platform on top
##   down     down and left on the box, ends on the floor
##   lunge    space + direction = climb lunge along the wall, stays on
##   stamina  bar empty -> claws give out, falls off
##   top      straight up the box to its top, over onto it
## getting on and off things:
##   run_up   walk at a 1.6 m bark wall, jump onto it, climb, top out
##   grab     trot at a 0.6 m smooth crate, jump: grab the edge, haul up
##   mantle   trot into a 27 cm box: hops up and keeps going
##   step     walk into an 18 cm curb: steps up onto it
##   ceiling  climb a bark wall whose top has no headroom: stops at the top, no clip, back down
##   lip      climb into the underside of an overhanging shelf: round the lip and onto it
##   side     climb sideways into a smooth block sticking out of the wall: stops at it, no clip
##   drop     crouch = let go: falls clean to the floor, doesn't grab straight back on
##   kick     space with no direction = kick off the wall
##   corner   diagonal up past the top corner of the box: onto the top
##
## jank checked on every run (CLIMBTEST <run> ... prints them):
##   pop   a visible body part (head / chest / pelvis) changes speed more in one frame than a
##         body can (1.6 m/s + 0.12 x speed, more right after grabbing on from a jump)
##   snap  the capsule moved further in one tick than its speed says (a teleport)
##   clip  the capsule or a body part inside something solid
##   stuck a scripted move held but the cat hasn't moved 1.5 cm in a second while on a wall /
##         in a haul, or a haul / hop lasting over 1.5 s

const RUNS := ["box", "trunk", "inside", "post", "down", "lunge", "stamina", "top", "run_up", "grab", "mantle", "step", "ceiling", "lip", "side", "drop", "kick", "corner"]
const SHOW_RUNS := ["run_up", "box", "post", "grab", "lip", "ceiling", "corner", "mantle"]
const PARTS := ["head", "chest", "pelvis"]
const STOP_OK := ["ceiling", "side", "box", "inside"]   # runs where standing still against an edge is the right answer

var player: CatPlayer
var cam: Camera3D
var show := false
var fp := false
var dbg := ""
var runs: Array = []
var ri := -1
var t := 0.0
var m := {}
var results := {}
var jank_tot := {"pop": 0, "snap": 0, "clip": 0, "stuck": 0}
var caption: Label
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_init := false
var _prev := {}
var _ph := {}

const BOX_C := Vector3(0, 0, 0)        # bark box trunk, 0.4 x 2.6 x 0.4
const TRUNK_C := Vector3(4, 0, 0)      # cylinder r 0.2
const TRUNK_R := 0.2
const L_C := Vector3(-4, 0, 0)         # inside corner
const POST_C := Vector3(8, 0, 0)       # sisal post 0.1, platform on top at 1.3 m
# second row (z -6): every fixture's climbable face looks +z
const RUN_C := Vector3(0, 0, -6)       # 1.6 m bark wall, 1.2 wide, 0.6 deep
const GRAB_C := Vector3(4, 0, -6)      # 0.95 m smooth crate (too tall to hop onto)
const MANTLE_C := Vector3(8, 0, -6)    # 0.22 m box, 4 m deep
const STEP_C := Vector3(12, 0, -6)     # 0.15 m curb, 3 m deep
const CEIL_C := Vector3(-4, 0, -6)     # 1.2 m bark wall, slab 0.16 over its top
const LIP_C := Vector3(-8, 0, -6)      # 1.0 m bark wall, shelf on it sticking out 0.3 m
const SIDE_C := Vector3(-12, 0, -6)    # bark wall with a smooth block sticking out to the right


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	show = "--show" in args
	process_priority = 100
	process_physics_priority = 100
	var k := args.find("--dbg")
	if k >= 0:
		dbg = args[k + 1]
	var only := []
	k = args.find("--only")
	if k >= 0:
		only = Array(args[k + 1].split(","))
	for r in (SHOW_RUNS if show and only.is_empty() else RUNS):
		if only.is_empty() or r in only:
			runs.append(r)
	_build()
	fp = "--fp" in args
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
	_box(Vector3(0, -0.05, -3), Vector3(34, 0.1, 14), Color(0.42, 0.5, 0.32), "grass", false)
	var bark := Color(0.4, 0.29, 0.2)
	var wood := Color(0.62, 0.5, 0.36)
	_box(BOX_C + Vector3(0, 1.3, 0), Vector3(0.4, 2.6, 0.4), bark, "bark", false)
	_cyl(TRUNK_C + Vector3(0, 1.5, 0), TRUNK_R, 3.0, bark.lightened(0.1), "bark")
	# inside corner: wall along x (facing +z) meets wall along z (facing -x) at L_C
	_box(L_C + Vector3(-0.6, 1.0, -0.05), Vector3(1.2, 2.0, 0.1), wood, "wood", true)
	_box(L_C + Vector3(0.05, 1.0, 0.6), Vector3(0.1, 2.0, 1.2), wood.darkened(0.06), "wood", true)
	_box(POST_C + Vector3(0, 0.65, 0), Vector3(0.1, 1.3, 0.1), Color(0.78, 0.66, 0.46), "sisal", false)
	_box(POST_C + Vector3(0, 1.32, 0), Vector3(0.5, 0.04, 0.5), Color(0.82, 0.78, 0.72), "carpet", false)
	# row 2
	_box(RUN_C + Vector3(0, 0.8, -0.3), Vector3(1.2, 1.6, 0.6), bark, "bark", false)
	_box(GRAB_C + Vector3(0, 0.475, -0.9), Vector3(0.8, 0.95, 1.8), wood, "wood", false)
	_box(MANTLE_C + Vector3(0, 0.11, -2.0), Vector3(0.8, 0.22, 4.0), wood.lightened(0.1), "wood", false)
	_box(STEP_C + Vector3(0, 0.075, -1.5), Vector3(1.2, 0.15, 3.0), Color(0.6, 0.6, 0.58), "tile", false)
	_box(CEIL_C + Vector3(0, 0.6, -0.3), Vector3(1.0, 1.2, 0.6), bark, "bark", false)
	_box(CEIL_C + Vector3(0, 1.36 + 0.03, -0.45), Vector3(1.0, 0.06, 0.6), Color(0.7, 0.7, 0.72), "wood", false)   # no headroom over the top
	_box(CEIL_C + Vector3(0, 1.36 / 2.0 + 0.6, -0.72), Vector3(1.0, 0.16, 0.06), Color(0.7, 0.7, 0.72), "wood", false)   # back wall holds the slab
	_box(LIP_C + Vector3(0, 0.5, -0.3), Vector3(1.0, 1.0, 0.6), bark, "bark", false)
	_box(LIP_C + Vector3(0, 1.02, -0.15), Vector3(1.0, 0.04, 0.9), Color(0.82, 0.78, 0.72), "carpet", false)   # shelf: overhangs 0.3 m
	_box(SIDE_C + Vector3(-0.2, 0.9, -0.3), Vector3(1.6, 1.8, 0.6), bark, "bark", false)
	_box(SIDE_C + Vector3(0.45, 0.9, 0.2), Vector3(0.3, 1.8, 0.4), Color(0.75, 0.75, 0.78), "tile", false)   # smooth block sticking out


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

func _on_wall() -> bool:
	return player.climbing or player.clambering or player.mantling


## puts the cat on the face of a thing (n = face normal, p = point on the face) with claws in
func _cling(p: Vector3, n: Vector3, h: float) -> void:
	var feet := Vector3(p.x, h, p.z) + n * (CatPlayer.RADIUS + 0.012)
	player.global_position = feet
	player.velocity = Vector3.ZERO
	var y := atan2(n.x, n.z)
	player.yaw = y
	player.orb_yaw = y
	player.rotation.y = y
	player._start_climb(n)


## stands the cat on the floor at p facing -z (toward the row 2 fixtures)
func _stand(p: Vector3) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.orb_yaw = 0.0
	player.rotation.y = 0.0


func _next() -> void:
	if ri >= 0:
		_report(runs[ri])
	ri += 1
	if ri >= runs.size():
		_summary()
		get_tree().quit()
		return
	var r: String = runs[ri]
	# a fresh cat every run (nothing carried over from the last one)
	if player:
		remove_child(player)
		player.queue_free()
	seed(hash(r))   # same dice every time (idle life, stop picks) so a run scores the same twice
	player = CatPlayer.new()
	add_child(player)
	if show:
		player.set_third_person(not fp)
		if cam:
			cam.make_current()
	t = 0.0
	_prev = {}
	_ph = {}
	m = {"turn": 0.0, "prev_n": Vector3.ZERO, "max_y": 0.0, "min_y": 99.0, "off_t": -1.0, "on_t": -1.0, "lunge": false, "dist_err": 0.0, "end_climb": false,
		"pop": 0, "pop_max": 0.0, "pop_what": "", "snap": 0, "snap_max": 0.0, "clip": 0, "clip_max": 0.0, "clip_what": "", "stuck": 0, "stuck_what": "",
		"kick_t": 9.0, "hop_t": 9.0, "still_t": 0.0, "still_from": Vector3.INF, "move_t": 0.0, "grab_t": 9.0, "grab_v": 0.0, "regrab": false, "was_wall": false, "ev": [], "speed_after": 0.0, "vmax": 0.0}
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
		"box", "down", "lunge", "top", "drop", "kick":
			_cling(BOX_C + Vector3(0, 0, 0.2), Vector3(0, 0, 1), 0.6 if r != "down" else 1.0)
		"corner":
			_cling(BOX_C + Vector3(0.08, 0, 0.2), Vector3(0, 0, 1), 2.05)
		"stamina":
			player.bot["stamina"] = true
			_cling(BOX_C + Vector3(0, 0, 0.2), Vector3(0, 0, 1), 0.8)
		"trunk":
			_cling(TRUNK_C + Vector3(0, 0, TRUNK_R), Vector3(0, 0, 1), 0.6)
		"inside":
			_cling(L_C + Vector3(-0.5, 0, 0.0), Vector3(0, 0, 1), 0.6)
		"post":
			_cling(POST_C + Vector3(0, 0, 0.05), Vector3(0, 0, 1), 0.5)
		"run_up":
			_stand(RUN_C + Vector3(0, 0.02, 0.75))
		"grab":
			_stand(GRAB_C + Vector3(0, 0.02, 0.95))
		"mantle":
			_stand(MANTLE_C + Vector3(0, 0.02, 1.6))
		"step":
			_stand(STEP_C + Vector3(0, 0.02, 0.8))
		"ceiling":
			_cling(CEIL_C, Vector3(0, 0, 1), 0.4)
		"lip":
			_cling(LIP_C, Vector3(0, 0, 1), 0.3)
		"side":
			_cling(SIDE_C + Vector3(-0.4, 0, 0), Vector3(0, 0, 1), 0.6)
	player.bot["yaw"] = player.yaw
	m.prev_n = player.climb_n
	if caption:
		var tag := OS.get_environment("CL_TAG")
		caption.text = (tag + "  -  " if tag != "" else "") + {"box": "round a square trunk", "trunk": "round a tree trunk", "inside": "into an inside corner", "post": "round a thin post, onto the top",
			"run_up": "jump on, climb, top out", "grab": "grab a ledge, haul up", "lip": "round an overhanging shelf", "ceiling": "top with no headroom",
			"corner": "over the top corner", "mantle": "onto a low box at a trot"}.get(r, r)


func _script(r: String) -> Dictionary:
	# returns {"move": Vector2, "jump": bool, "crouch": bool, "done": bool}
	var mv := Vector2.ZERO
	var jump := false
	var crouch := false
	var done := false
	var on := _on_wall()
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
			elif t < 3.4: mv = Vector2(0, 1) if on else Vector2.ZERO
			else: done = true
		"post":
			if t < 2.5: mv = Vector2(1, 0)
			elif on: mv = Vector2(0, 1)
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
			mv = Vector2(0, 1) if (on or t < 0.3) else Vector2.ZERO
			done = t > 6.0
		"run_up":
			mv = Vector2(0, 1) if (on or (t < 1.0 and not (player.is_on_floor() and player.global_position.y > 0.5))) else Vector2.ZERO
			jump = t > 0.35 and t < 0.45
			done = t > 5.0
		"grab":
			mv = Vector2(0, 1) if (on or (t < 1.2 and not (player.is_on_floor() and player.global_position.y > 0.5))) else Vector2.ZERO
			jump = t > 0.3 and t < 0.4
			done = t > 4.0
		"mantle":
			mv = Vector2(0, 1)
			done = t > 1.6
		"step":
			mv = Vector2(0, 0.45)
			done = t > 2.2
		"ceiling":
			if t < 3.5: mv = Vector2(0, 1)
			elif player.climbing: mv = Vector2(0, -1)
			done = t > 7.5
		"lip":
			mv = Vector2(0, 1) if (on or t < 0.3) else Vector2.ZERO
			done = t > 5.0
		"side":
			mv = Vector2(1, 0)
			done = t > 3.0
		"drop":
			crouch = t > 0.4 and t < 0.5
			done = t > 2.0
		"kick":
			jump = t > 0.4 and t < 0.48
			done = t > 1.6
		"corner":
			mv = Vector2(0.7, 0.7) if (on or t < 0.3) else Vector2.ZERO
			done = t > 4.0
	return {"move": mv, "jump": jump, "crouch": crouch, "done": done}


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
	player.bot["crouch"] = s.crouch
	var on := _on_wall()
	if player.climbing:
		var n: Vector3 = player.climb_n
		var pn: Vector3 = m.prev_n
		var a := atan2(pn.cross(n).y, pn.dot(n))
		m.turn += a
		m.prev_n = n
		var c := player.global_position + Vector3.UP * 0.12
		var hit := _ray(c, c - n * 0.5)
		if not hit.is_empty():
			m.dist_err = maxf(m.dist_err, absf((hit.position - c).dot(-n) - (CatPlayer.RADIUS + 0.01)))
		if player.climb_lunge_t > 0.0:
			m.lunge = true
	elif m.off_t < 0.0 and m.was_wall:
		m.off_t = t
	if on and not m.was_wall:
		if m.off_t >= 0.0 and r == "drop":
			m.regrab = true
		m.on_t = t
		m.grab_t = 0.0
		m.grab_v = _ph.get("v", Vector3.ZERO).length()
	m.grab_t += dt
	m.kick_t += dt
	m.hop_t += dt
	if player.last_event == "hop" and player.last_event_t <= dt * 1.5:
		m.hop_t = 0.0
	if player.last_event == "leap off" and player.last_event_t <= dt * 1.5:
		m.kick_t = 0.0
	m.was_wall = on
	if not on and player.is_on_floor() and player.global_position.y > 0.1:
		m.speed_after = maxf(m.speed_after, Vector2(player.velocity.x, player.velocity.z).length())
	m.vmax = maxf(m.vmax, Vector2(player.velocity.x, player.velocity.z).length())
	_jank_phys(dt, s, on)
	if player.last_event_t <= dt * 1.5 and player.last_event != "" and (m.ev.is_empty() or m.ev[-1] != player.last_event):
		m.ev.append(player.last_event)
	if dbg == "trace":
		print("  t=%.3f pos %s v %s climb %s clamb %s mant %s floor %s ev %s" % [t, player.global_position.snapped(Vector3.ONE * 0.001), player.velocity.snapped(Vector3.ONE * 0.01), player.climbing, player.clambering, player.mantling, player.is_on_floor(), player.last_event])
	m.max_y = maxf(m.max_y, player.global_position.y)
	m.min_y = minf(m.min_y, player.global_position.y)
	if s.done or t > 14.0:
		m.end_climb = player.climbing
		m.end_pos = player.global_position
		m.end_floor = player.is_on_floor()
		_next()


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


## capsule: teleports, overlap, stuck
func _jank_phys(dt: float, s: Dictionary, on: bool) -> void:
	var p := player.global_position
	var soft = player.get("_soft_off")
	if soft != null:
		p += soft
	if _ph.has("p"):
		var d: Vector3 = p - _ph.p
		var exp_d := maxf(player.velocity.length(), float(_ph.vl)) * dt
		var extra := d.length() - exp_d
		if extra > 0.02 and (on or _ph.on):
			m.snap += 1
			m.snap_max = maxf(m.snap_max, extra)
			if dbg == "snap":
				print("  snap %.0f mm t=%.2f climb %s clamb %s mant %s ev %s" % [extra * 1000.0, t, player.climbing, player.clambering, player.mantling, player.last_event])
		_ph.v = d / dt
	# capsule inside something (a little smaller than the real one: touching is fine)
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CatPlayer.RADIUS - 0.012
	cap.height = player.capsule.height - 0.024
	q.shape = cap
	q.transform = player.shape.global_transform
	q.exclude = [player.get_rid()]
	for h in get_world_3d().direct_space_state.intersect_shape(q, 4):
		if h.collider is StaticBody3D:
			m.clip += 1
			if m.clip_what == "":
				m.clip_what = "capsule @%.2fs" % t
			if dbg == "clip":
				print("  clip capsule t=%.2f pos %s" % [t, player.global_position])
			break
	# stuck: holding a move on a wall / in a haul and going nowhere
	var held: bool = (s.move as Vector2).length() > 0.1
	if on and held and not (runs[ri] in STOP_OK):
		if not m.still_from.is_finite() or player.global_position.distance_to(m.still_from) > 0.015:
			m.still_from = player.global_position
			m.still_t = 0.0
		else:
			m.still_t += dt
			if m.still_t > 1.0:
				m.stuck += 1
				m.stuck_what = "no progress @%.2fs" % t
				m.still_t = -99.0
	else:
		m.still_from = Vector3.INF
		m.still_t = 0.0
	if player.clambering or player.mantling:
		m.move_t += dt
		if m.move_t > 1.5 and m.move_t - dt <= 1.5:
			m.stuck += 1
			m.stuck_what = "haul / hop over 1.5 s @%.2fs" % t
	else:
		m.move_t = 0.0
	_ph.p = p
	_ph.vl = player.velocity.length()
	_ph.on = on


func _process(dt: float) -> void:
	if ri < 0 or ri >= runs.size() or dt <= 0.0:
		return
	if cam:
		_camera(dt)
	var rig := player.rig
	var cur := {}
	var spd := player.velocity.length()
	for pn in PARTS:
		var n: Node3D = rig.get(pn)
		cur[pn] = n.global_position
		if t < 0.15:
			continue   # (the lab drops the cat straight onto the wall: the rig is still turning onto it)
		# a body part inside something solid
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = n.global_position
		pq.exclude = [player.get_rid()]
		for h in get_world_3d().direct_space_state.intersect_point(pq, 4):
			if h.collider is StaticBody3D:
				m.clip += 1
				if m.clip_what == "":
					m.clip_what = "%s @%.2fs" % [pn, t]
				if dbg == "clip":
					print("  clip %s t=%.2f" % [pn, t])
				break
	if not _prev.is_empty() and _prev.has("dt") and t > 0.25:   # (the lab sets the cat straight onto the wall)
		for key in PARTS:
			var v: Vector3 = ((cur[key] as Vector3) - (_prev[key] as Vector3)) / dt
			cur["v" + key] = v
			if _prev.has("v" + key):
				var dv: float = (v - (_prev["v" + key] as Vector3)).length()
				var lim: float = 1.6 + 0.12 * spd
				# grabbing on out of a jump: the forelegs soak up the incoming speed over ~12 cm
				if m.grab_t < 0.25:
					lim = maxf(lim, m.grab_v * m.grab_v / (2.0 * 0.12) / 60.0 * 1.3)
				# the jump onto the wall leaving the floor is a take off: the gait's business (biolab)
				if m.on_t < 0.0 and m.hop_t < 0.15:
					lim = maxf(lim, 4.0)
				# kicking off: the hind legs shove the body away (a take off, like a jump's)
				if m.kick_t < 0.3:
					lim = maxf(lim, 2.4)
				# landing on the floor after letting go / kicking off is the gait's business (biolab)
				if player.is_on_floor() and not _on_wall() and m.off_t >= 0.0 and t - m.off_t < 1.2:
					lim = maxf(lim, 4.0)
				if dv > lim:
					m.pop += 1
					if dv / lim > m.pop_max:
						m.pop_max = dv / lim
						m.pop_what = "%s %.1f m/s @%.2fs %s" % [key, dv, t, player.last_event]
					if dbg == "pop":
						print("  pop %s dv=%.1f lim=%.1f t=%.2f climb %s clamb %s mant %s floor %s ev %s" % [key, dv, lim, t, player.climbing, player.clambering, player.mantling, player.is_on_floor(), player.last_event])
	if dbg == "rig2":
		print("  t=%.3f fgy %.3f hgy %.3f landf %.3f land %.3f piv %s pivrot %s chest %s pelv %s air %.2f cl %.2f iner %s" % [t, rig._fgy, rig._hgy, rig._land_f, rig._land, rig.pivot.position.snapped(Vector3.ONE * 0.001), rig.pivot.rotation.snapped(Vector3.ONE * 0.01), rig.chest.position.snapped(Vector3.ONE * 0.001), rig.pelvis.position.snapped(Vector3.ONE * 0.001), rig._air_w, rig.climb, str(rig._iner) if "_iner" in rig else ""])
	if dbg == "rig":
		var rg := rig.global_position
		print("  t=%.3f cap %s root %s chest-root %s pelv-root %s clamber %.2f pull %.2f climb %.2f onfl %s air %.2f lift %.3f soft %s ev %s" % [t, player.global_position.snapped(Vector3.ONE * 0.001), rg.snapped(Vector3.ONE * 0.001), (rig.chest.global_position - rg).snapped(Vector3.ONE * 0.001), (rig.pelvis.global_position - rg).snapped(Vector3.ONE * 0.001), rig.clamber, rig.clamber_pull, rig.climb, rig.on_floor, rig._air_w, player._lift, player._soft_off.snapped(Vector3.ONE * 0.001), player.last_event])
	cur["dt"] = dt
	_prev = cur


func _camera(dt: float) -> void:
	var r: String = runs[ri]
	var target: Vector3 = player.rig.chest.global_position
	var centre: Vector3 = {"box": BOX_C, "trunk": TRUNK_C, "inside": L_C + Vector3(-0.3, 0, 0.3), "post": POST_C, "corner": BOX_C, "top": BOX_C}.get(r, Vector3.INF)
	var want: Vector3
	if centre.is_finite():
		# orbit slowly with the cat, from a bit out and up
		var to_cat := Vector3(target.x - centre.x, 0, target.z - centre.z)
		if to_cat.length() < 0.05:
			to_cat = Vector3(0, 0, 1)
		to_cat = to_cat.normalized()
		want = centre + to_cat.rotated(Vector3.UP, 0.5) * 1.9 + Vector3.UP * (target.y + 0.35)
		if r == "inside":
			want = L_C + Vector3(-1.5, target.y + 0.5, 1.7)
	else:
		# row 2: three quarter side view of the face
		want = target + Vector3(1.5, 0.45, 1.3)
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
	var fl: bool = m.get("end_floor", false)
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
			ok = fl and not m.end_climb and m.off_t > 0.0
			why = "reached floor %s, let go at %.2f s" % [fl, m.off_t]
		"lunge":
			ok = m.lunge and m.end_climb
			why = "lunged %s, still on %s" % [m.lunge, m.end_climb]
		"stamina":
			ok = m.off_t > 0.0 and m.off_t < 0.6
			why = "fell off at %.2f s (bar emptied at 0.3 s)" % m.off_t
		"top":
			ok = ep.y > 2.55 and not m.end_climb and fl
			why = "ended at y %.2f (top 2.6), climbing %s, standing %s" % [ep.y, m.end_climb, fl]
		"run_up":
			ok = ep.y > 1.55 and fl and not m.end_climb
			why = "ended at y %.2f (wall top 1.6), standing %s" % [ep.y, fl]
		"grab":
			ok = ep.y > 0.9 and fl
			why = "ended at y %.2f (crate top 0.95), standing %s" % [ep.y, fl]
		"mantle":
			ok = ep.y > 0.2 and m.speed_after > 2.0
			why = "ended at y %.2f (box 0.22), kept %.1f m/s after" % [ep.y, m.speed_after]
		"step":
			ok = ep.y > 0.14 and fl
			why = "ended at y %.2f (curb 0.15)" % ep.y
		"ceiling":
			ok = fl and ep.y < 0.05 and m.max_y < 1.2
			why = "highest feet %.2f (top 1.2, no room), back on the floor %s" % [m.max_y, fl]
		"lip":
			ok = ep.y > 1.02 and fl and not m.end_climb
			why = "ended at y %.2f (shelf 1.04), standing %s" % [ep.y, fl]
		"side":
			ok = m.end_climb and ep.x < SIDE_C.x + 0.3
			why = "still on %s, ended x %+.2f (block face at %+.2f)" % [m.end_climb, ep.x - SIDE_C.x, 0.3]
		"drop":
			ok = fl and not m.end_climb and not m.regrab
			why = "on the floor %s, grabbed back on %s" % [fl, m.regrab]
		"kick":
			ok = not m.end_climb and m.off_t > 0.0 and ep.z > BOX_C.z + 0.5
			why = "off the wall %s, ended %.2f m out" % [m.off_t > 0.0, ep.z - BOX_C.z - 0.2]
		"corner":
			ok = ep.y > 2.55 and fl
			why = "ended at y %.2f (top 2.6), standing %s" % [ep.y, fl]
	var jank := "pop %d%s snap %d%s clip %d%s stuck %d%s" % [m.pop, (" (x%.1f %s)" % [m.pop_max, m.pop_what]) if m.pop > 0 else "", m.snap, (" (%.0f mm)" % (m.snap_max * 1000.0)) if m.snap > 0 else "", m.clip, (" (" + m.clip_what + ")") if m.clip > 0 else "", m.stuck, (" (" + m.stuck_what + ")") if m.stuck > 0 else ""]
	var clean: bool = m.pop == 0 and m.snap == 0 and m.clip == 0 and m.stuck == 0
	for k in jank_tot:
		jank_tot[k] += int(m[k])
	results[r] = ok and clean
	print("CLIMBTEST %-8s %s  %s | %s" % [r, "ok" if (ok and clean) else ("JANK" if ok else "FAIL"), why, jank])
	if OS.get_environment("CL_LOG") != "":
		print("    events: ", m.ev)


func _summary() -> void:
	var n := 0
	for r in results:
		n += 1 if results[r] else 0
	print("CLIMBTEST %s %d / %d  jank total %s" % ["PASS" if n == results.size() else "FAIL", n, results.size(), str(jank_tot)])
