extends Node3D
## first person paws lab: the real CatPlayer on a flat test floor, rendered three ways at once
##   left  = the old standalone viewmodel (its own fake animation)
##   right = the new viewmodel (copies of the rig's real forelegs)
##   inset = the full body cat from outside, so you can check they match
## run:  godot --path . res://fplab.tscn -- [--fptest] [--slow 0.5] [--style block]
##   --fptest no video, just measures and prints FPLAB lines + FPLAB PASS/FAIL

const VM_OLD := 1 << 1   # render layer 2
const VM_NEW := 1 << 2   # render layer 3
const BODY := 1 << 3     # render layer 4

var player: CatPlayer
var old_vm: PawView
var cams: Array[Camera3D] = []
var side_cam: Camera3D
var caption: Label
var test := false
var slow := 1.0
var bot := {}
var wall_x := 0.0
var errors: Array[String] = []
var _t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	test = "--fptest" in args
	var si := args.find("--slow")
	if si >= 0:
		slow = float(args[si + 1])
	_env()
	player = CatPlayer.new()
	player.position = Vector3(0, 0.02, 0)
	player.yaw = 0.0
	player.bot = {"move": Vector2.ZERO, "yaw": 0.0, "pitch": -0.15}
	player.log_events = test
	add_child(player)
	var vs := args.find("--style")
	player.set_style(args[vs + 1] if vs >= 0 else "block")
	await get_tree().process_frame
	_setup_views()
	_run()


func _env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12.0
	add_child(sun)
	# long checker floor (wood) so you can see planted paws hold still on it
	var floor_body := StaticBody3D.new()
	floor_body.set_meta("surface", "wood")
	add_child(floor_body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12, 1, 140)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, -60)
	floor_body.add_child(cs)
	var tiles := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.02, 0.5)
	mm.mesh = bm
	var nx := 24
	var nz := 280
	mm.instance_count = nx * nz
	var k := 0
	for z in nz:
		for x in nx:
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(-6 + 0.25 + x * 0.5, -0.01, 10 - 0.25 - z * 0.5)))
			var c := Color(0.55, 0.42, 0.3) if (x + z) % 2 == 0 else Color(0.66, 0.53, 0.38)
			mm.set_instance_color(k, c)
			k += 1
	tiles.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	tiles.material_override = mat
	add_child(tiles)
	# a wall along the right for wall kicks
	wall_x = 1.2
	_box(Vector3(wall_x + 0.1, 0.8, -40), Vector3(0.2, 1.6, 100), Color(0.78, 0.76, 0.72), "wood")
	# end wall
	_box(Vector3(0, 0.8, -95), Vector3(12, 1.6, 0.2), Color(0.78, 0.76, 0.72), "wood")


func _box(pos: Vector3, size: Vector3, col: Color, surface: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = pos
	b.set_meta("surface", surface)
	add_child(b)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	b.add_child(mi)
	return b


func _layer(root: Node, bits: int) -> void:
	for c in root.find_children("*", "VisualInstance3D", true, false):
		(c as VisualInstance3D).layers = bits
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = bits


func _setup_views() -> void:
	# old viewmodel: a plain PawView (no rig) on the same anchor, fed the same inputs
	old_vm = PawView.new()
	old_vm.fur = player.rig.fur
	old_vm.fur_dark = player.rig.fur_dark
	old_vm.pattern = player.rig.pattern
	old_vm.socks = player.rig.socks
	old_vm.sock_col = player.rig.belly
	old_vm.process_priority = 11
	player.paw_anchor.add_child(old_vm)
	await get_tree().process_frame
	_layer(old_vm, VM_OLD)
	_layer(player.paws, VM_NEW)
	# the body: visible (not shadow only) but on its own layer
	player.rig.set_shadow_only(false)
	_layer(player.rig, BODY)
	player.cam.current = false
	if test:
		return
	var win := get_window()
	win.size = Vector2i(1920, 600)
	var W := 960
	var H := 540
	for i in 2:
		var svc := SubViewportContainer.new()
		svc.position = Vector2(i * W, 0)
		svc.size = Vector2(W, H)
		svc.stretch = true
		add_child(svc)
		var sv := SubViewport.new()
		sv.size = Vector2i(W, H)
		sv.msaa_3d = Viewport.MSAA_4X
		svc.add_child(sv)
		var c := Camera3D.new()
		c.near = 0.01
		c.fov = player.cam.fov
		c.cull_mask = 1 | (VM_OLD if i == 0 else VM_NEW)
		sv.add_child(c)
		c.current = true
		cams.append(c)
		var lab := Label.new()
		lab.text = ["before: separate fake paw animation", "after: the body's real forelegs"][i]
		lab.position = Vector2(i * W + 20, 14)
		lab.add_theme_font_size_override("font_size", 30)
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lab.add_theme_constant_override("outline_size", 8)
		add_child(lab)
	# third person inset (top right of the "after" panel)
	var svc2 := SubViewportContainer.new()
	svc2.position = Vector2(1920 - 360 - 12, 60)
	svc2.size = Vector2(360, 270)
	svc2.stretch = true
	add_child(svc2)
	var sv2 := SubViewport.new()
	sv2.size = Vector2i(360, 270)
	sv2.msaa_3d = Viewport.MSAA_4X
	svc2.add_child(sv2)
	side_cam = Camera3D.new()
	side_cam.fov = 40
	side_cam.near = 0.02
	side_cam.cull_mask = 1 | BODY
	sv2.add_child(side_cam)
	side_cam.current = true
	var lab2 := Label.new()
	lab2.text = "the body"
	lab2.position = Vector2(1920 - 360, 64)
	lab2.add_theme_font_size_override("font_size", 20)
	lab2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lab2.add_theme_constant_override("outline_size", 6)
	add_child(lab2)
	var bar := ColorRect.new()
	bar.color = Color(0.08, 0.08, 0.1)
	bar.position = Vector2(0, H)
	bar.size = Vector2(1920, 600 - H)
	add_child(bar)
	caption = Label.new()
	caption.position = Vector2(24, H + 10)
	caption.add_theme_font_size_override("font_size", 28)
	add_child(caption)


func _process(_dt: float) -> void:
	if player == null or old_vm == null:
		return
	# keep the old viewmodel fed with exactly what the player gives the real one
	var p := player.paws
	for f in ["phase", "speed", "gait_w", "on_floor", "vy", "crouch", "charge", "scramble", "climb", "hang", "hang_pull", "scratch", "claws_out", "foot", "use_feet", "look_vel",
			"_swat_t", "_swat_i", "_swat_target", "_kick_t", "_kick_side", "_mantle_t", "_pin_t", "_land", "claw_on", "claw_i", "claw_target"]:
		old_vm.set(f, p.get(f))
	for c in cams:
		c.global_transform = player.cam.global_transform
		c.fov = player.cam.fov
	if side_cam:
		var b := player.global_transform
		var tgt := b * Vector3(0, 0.16, -0.05)
		side_cam.global_position = b * Vector3(-1.05, 0.42, -0.55)
		side_cam.look_at(tgt, Vector3.UP)


func _say(t: String) -> void:
	_section = t.split(" (")[0]
	if caption:
		caption.text = t
	print("FPLAB step: ", t)


func _frame() -> float:
	player.bot = bot.duplicate()
	await get_tree().physics_frame
	var dt := get_physics_process_delta_time()
	_t += dt
	if test:
		await RenderingServer.frame_pre_draw
		_measure()
	return dt


var _stats := {}
var _section := ""


## how much of the new viewmodel is on screen, and that it really is a copy of the rig's legs
func _measure() -> void:
	var pv := player.paws
	if not pv._mirror_on() or pv._mir.is_empty():
		errors.append("%s: mirror not running" % _section)
		return
	var st: Dictionary = _stats.get(_section, {"n": 0, "on": 0, "raise": 0.0, "bad": 0})
	st.n += 1
	var cam := player.cam
	var vp := get_viewport().get_visible_rect().size
	var any_on := false
	var legs: Array = player.rig.legs
	for i in 2:
		var src: Node3D = legs[i].paw
		var dup: Node3D = null
		for pr in pv._mir:
			if pr[0] == src:
				dup = pr[1]
		if dup == null:
			continue
		var wp := dup.global_position
		if not cam.is_position_behind(wp):
			var sp := cam.unproject_position(wp)
			if sp.x >= 0 and sp.y >= 0 and sp.x <= vp.x and sp.y <= vp.y:
				any_on = true
		# the copy's pose relative to its own forearm must match the rig's (rigid per leg)
		var src_rel: Transform3D = (legs[i].lower as Node3D).transform.affine_inverse() * src.transform
		var dup_lower: Node3D = null
		for pr in pv._mir:
			if pr[0] == legs[i].lower:
				dup_lower = pr[1]
		var dup_rel: Transform3D = dup_lower.transform.affine_inverse() * dup.transform
		if not src_rel.origin.is_equal_approx(dup_rel.origin) and src_rel.origin.distance_to(dup_rel.origin) > 1e-4:
			st.bad += 1
		st.raise = maxf(st.raise, maxf(pv._raise[0], pv._raise[1]))
	if any_on:
		st.on += 1
	_stats[_section] = st


func _hold(dur: float) -> void:
	var t := 0.0
	while t < dur:
		t += await _frame()


func _tap(key: String, hold := 0.08) -> void:
	bot[key] = true
	await _hold(hold)
	bot.erase(key)


func _go_to_start() -> void:
	player.global_position = Vector3(0, 0.02, 0)
	player.velocity = Vector3.ZERO
	player._phys_prev = player.global_position
	player._phys_curr = player.global_position


func _place(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.yaw = yaw
	player.orb_yaw = yaw
	player._phys_prev = pos
	player._phys_curr = pos
	bot = {"move": Vector2.ZERO, "yaw": yaw, "pitch": -0.15}


func _speed(ts: float) -> void:
	Engine.time_scale = ts * slow


func _run() -> void:
	_speed(1.0)
	_place(Vector3(0, 0.02, 0), 0.0)
	_say("standing")
	await _hold(1.4)
	_say("walk")
	bot.move = Vector2(0, 0.3)
	await _hold(2.4)
	_say("trot (3.2 m/s)")
	bot.move = Vector2(0, 1.0)
	await _hold(2.4)
	_say("gallop")
	bot.sprint = true
	await _hold(2.0)
	bot.erase("sprint")
	bot.move = Vector2.ZERO
	_say("stop")
	await _hold(1.2)

	_place(Vector3(-2, 0.02, -40), 0.0)
	_speed(0.5)
	_say("swats (half speed)")
	await _hold(0.3)
	for k in 4:
		await _tap("swat")
		await _hold(0.45)
	_say("crouch + pounce (half speed)")
	bot.crouch = true
	await _hold(0.6)
	bot.jump = true
	await _hold(0.5)
	bot.erase("jump")
	await _hold(0.05)
	bot.erase("crouch")
	await _hold(1.3)

	_say("dodges: side leap, backstep, dart (half speed)")
	await _hold(0.3)
	for mv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1), Vector2(0, 1)]:
		bot.stamina = false
		bot.move = mv
		bot.dash = true
		await _frame()
		bot.erase("dash")
		await _hold(0.25)
		bot.move = Vector2.ZERO
		await _hold(0.75)

	_say("wall kick (half speed)")
	_place(Vector3(wall_x - 1.3, 0.02, -20), -PI / 2)
	await _hold(0.3)
	bot.move = Vector2(0, 1)
	var hopped := false
	var kicked := false
	var t := 0.0
	while t < 2.2:
		bot.erase("jump")
		var gap := wall_x - player.global_position.x
		if not hopped and gap < 0.75 and player.is_on_floor():
			bot.jump = true
			hopped = true
		elif hopped and not kicked and not player.is_on_floor() and player.wall_time < 0.05:
			bot.jump = true
			bot.yaw = PI * 0.25
			kicked = true
		elif kicked:
			bot.move = Vector2.ZERO
			bot.yaw = player.yaw
		t += await _frame()
	_speed(1.0)
	if test:
		_report()
	get_tree().quit()


func _report() -> void:
	for k in _stats:
		var st: Dictionary = _stats[k]
		var on := float(st.on) / maxf(st.n, 1)
		print("FPLAB %s: paws on screen %d%%, max raise %.2f, pose mismatches %d" % [k, int(on * 100.0), st.raise, st.bad])
		if st.bad > 0:
			errors.append("%s: copied legs don't match the rig" % k)
		# a gallop really does throw both forepaws back under the chest for part of each stride
		var need := 0.75 if k == "gallop" else 0.9
		if k in ["standing", "walk", "trot", "gallop", "swats"] and on < need:
			errors.append("%s: paws off screen too often (%d%%)" % [k, int(on * 100.0)])
	if not _stats.get("swats", {}).is_empty() and _stats.swats.raise < 0.4:
		errors.append("swats: the swatting paw never registered as raised")
	if errors.is_empty():
		print("FPLAB PASS")
	else:
		for e in errors:
			print("FPLAB FAIL ", e)
