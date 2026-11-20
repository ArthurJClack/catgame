class_name Preview
extends Node
## scripted showcase used to render the preview video:
##   part 1: gait reference studio (muybridge style), side tracking camera
##   part 2: first person run through the living room driven by a bot

var main: Node3D
var cam: Camera3D
var caption: Label
var sub: Label
var cat: CatRig
var t_total := 0.0
const G := 9.8


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 50
	cam.near = 0.01
	main.add_child(cam)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	caption = Label.new()
	caption.anchor_left = 0.0
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_left = 36
	caption.offset_top = -120
	caption.add_theme_font_size_override("font_size", 34)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(caption)
	sub = Label.new()
	sub.anchor_top = 1.0
	sub.anchor_bottom = 1.0
	sub.offset_left = 38
	sub.offset_top = -72
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	sub.add_theme_constant_override("outline_size", 6)
	layer.add_child(sub)

	print("preview ready")
	cat = CatRig.new()
	main.add_child(cat)
	cat.position = Vector3(40, 0, 30)
	main.player.bot = {"move": Vector2.ZERO}
	main.player.log_events = true
	if "--nettest" in OS.get_cmdline_user_args():
		var nt := NetTest.new()
		nt.main = main
		add_child(nt)
	var args := OS.get_cmdline_user_args()
	var si := args.find("--still")
	if si >= 0:
		var v := args[si + 1].split_floats(",")
		main.hud.visible = false
		cam.current = true
		cam.fov = 70
		cam.global_position = Vector3(v[0], v[1], v[2])
		cam.look_at(Vector3(v[3], v[4], v[5]), Vector3.UP)
		return
	if "--posetest" in args:
		cat.visible = false
		_run_posetest(args)
		return
	if "--parkour" in args:
		cat.visible = false
		_run_parkour()
		return
	if "--anim" in args:
		cat.visible = false
		_run_anim()
		return
	if "--showcase" in args:
		cat.visible = false
		await _run_anim(false)
		await _run_parkour()
		return
	if "--fpshot" in args:
		cat.visible = false
		var p: CatPlayer = main.player
		main.hud.visible = false
		p.bot.pitch = float(args[args.find("--fpshot") + 1])
		p.bot.yaw = -0.6
		p.bot.move = Vector2(0, float(args[args.find("--fpshot") + 2]))
		p.cam.current = true
		return
	if "--pawtest" in args:
		cat.visible = false
		_run_pawtest()
		return
	if "--hoptest" in args:
		cat.visible = false
		_run_hoptest()
		return
	if "--kickshow" in args or "--kicktest" in args:
		cat.visible = false
		_run_kickshow("--kicktest" in args)
		return
	if "--dustshow" in args:
		cat.visible = false
		_run_dustshow()
		return
	if "--dashtest" in args:
		cat.visible = false
		_run_dashtest()
		return
	if "--dashshow" in args:
		cat.visible = false
		_run_dashshow()
		return
	if "--dusttest" in args:
		cat.visible = false
		_run_dusttest()
		return
	if "--camtest" in args:
		cat.visible = false
		_run_camtest()
		return
	if "--swattest" in args:
		cat.visible = false
		_run_swattest()
		return
	if "--movecurve" in args:
		cat.visible = false
		_run_movecurve()
		return
	if "--movetest" in args:
		cat.visible = false
		_run_movetest()
		return
	if "--variants" in args:
		cat.visible = false
		_run_variants()
		return
	if "--house" in OS.get_cmdline_user_args():
		_run_house_only()
	else:
		_run()


func _run_house_only() -> void:
	await _house()
	get_tree().quit()


func _say(a: String, b: String = "") -> void:
	caption.text = a
	sub.text = b


func _frame() -> float:
	await get_tree().process_frame
	var dt := get_process_delta_time()
	t_total += dt
	return dt


# ------------------------------------------------------------------ studio
var cat_v := Vector3.ZERO
var cam_mode := "side"
var orbit_a := 0.0


func _studio_cam(dt: float) -> void:
	var p := cat.global_position
	var target_pos: Vector3
	var look := p + Vector3(0, 0.17, 0)
	if cam_mode == "face":
		var hp := cat.head.global_position
		target_pos = hp + Vector3(sin(orbit_a) * 0.32, 0.03, cos(orbit_a) * -0.32)
		look = hp
	elif cam_mode == "orbit":
		target_pos = p + Vector3(sin(orbit_a) * 1.15, 0.32, cos(orbit_a) * -1.15)
	else:
		target_pos = Vector3(p.x + 1.35, 0.26 + maxf(p.y * 0.5, 0.0), p.z - 0.15)
		look = Vector3(p.x, 0.17 + p.y * 0.6, p.z - 0.15)
	cam.global_position = cam.global_position.lerp(target_pos, 1.0 - exp(-6.0 * dt)) if cam_mode == "side_smooth" else target_pos
	cam.look_at(look, Vector3.UP)


func _studio_run(dur: float, speed_fn: Callable) -> void:
	var t := 0.0
	while t < dur:
		var dt: float = await _frame()
		t += dt
		var s: float = speed_fn.call(t)
		cat_v = Vector3(0, cat_v.y, -s)
		_integrate(dt)
		_studio_cam(dt)


func _integrate(dt: float) -> void:
	var p := cat.position
	if not cat.on_floor:
		cat_v.y -= G * dt
	p += cat_v * dt
	if p.y <= 0.0 and cat_v.y <= 0.0:
		p.y = 0.0
		cat_v.y = 0.0
		cat.on_floor = true
	cat.position = p
	cat.drive_velocity = cat_v


func _run() -> void:
	main.hud.visible = false
	cam.current = true
	# ---- idle orbit ----
	# ---- face closeup ----
	cam_mode = "face"
	_say("procedural low poly cat", "no imported assets: mesh, fur pattern and animation are all generated")
	var t := 0.0
	while t < 2.6:
		var dt: float = await _frame()
		t += dt
		orbit_a = lerpf(-0.7, 0.6, t / 2.6)
		cat.look_yaw = sin(t * 1.2) * 0.35
		cat.look_pitch = 0.1 + sin(t * 0.9) * 0.1
		_integrate(dt)
		_studio_cam(dt)
	cam_mode = "orbit"
	_say("procedural low poly cat", "ik rig · real proportions (0.46 m body, 0.25 m at the shoulder)")
	t = 0.0
	while t < 3.2:
		var dt: float = await _frame()
		t += dt
		orbit_a = lerpf(-0.9, 1.4, t / 3.2)
		cat.look_yaw = sin(t * 1.6) * 0.6
		cat.look_pitch = sin(t * 0.9) * 0.2
		_integrate(dt)
		_studio_cam(dt)
	cat.look_yaw = 0
	cat.look_pitch = 0
	cam_mode = "side"
	_say("walk", "0.8 m/s · lateral sequence, feet stay planted")
	await _studio_run(3.0, func(tt): return minf(tt * 1.5, 0.8))
	_say("trot", "2.8 m/s · diagonal pairs")
	await _studio_run(2.6, func(tt): return lerpf(0.8, 2.8, minf(tt / 0.6, 1.0)))
	_say("gallop", "up to 11 m/s (≈40 km/h) · rotary gallop, spine flex")
	await _studio_run(3.4, func(tt): return lerpf(2.8, 11.0, minf(tt / 1.6, 1.0)))
	_say("slow down")
	await _studio_run(1.2, func(tt): return lerpf(11.0, 0.5, minf(tt / 1.1, 1.0)))
	_say("stalk", "0.5 m/s · body low, ears back, tail tip lashing")
	t = 0.0
	while t < 2.6:
		var dt: float = await _frame()
		t += dt
		cat.crouch = minf(t * 3.0, 1.0)
		cat_v = Vector3(0, 0, -0.5)
		_integrate(dt)
		_studio_cam(dt)
	_say("pounce wind-up", "the butt wiggle")
	t = 0.0
	while t < 1.1:
		var dt: float = await _frame()
		t += dt
		cat.charge = minf(t / 0.8, 1.0)
		cat.crouch = 1.0 - cat.charge
		cat_v = Vector3(0, 0, move_toward(-cat_v.z, 0.0, dt * 4.0) * -1.0)
		_integrate(dt)
		_studio_cam(dt)
	cat.charge = 0.0
	cat.crouch = 0.0
	_say("pounce", "1.6 m high · real cats clear ~5x their own height")
	cat_v = Vector3(0, sqrt(2.0 * G * 1.6), -3.0)
	cat.on_floor = false
	t = 0.0
	while t < 1.7:
		var dt: float = await _frame()
		t += dt
		if cat.on_floor:
			cat_v.z = move_toward(cat_v.z, -1.8, dt * 6.0)
		_integrate(dt)
		_studio_cam(dt)
	_say("running hop", "1 m hop out of a trot")
	cat_v = Vector3(0, sqrt(2.0 * G * 1.0), -2.8)
	cat.on_floor = false
	await _studio_run(1.9, func(tt): return 2.8 if tt < 1.0 else lerpf(2.8, 0.0, minf((tt - 1.0) / 0.8, 1.0)))
	_say("sit", "tail wraps around, head keeps looking around")
	cam_mode = "orbit"
	t = 0.0
	while t < 3.4:
		var dt: float = await _frame()
		t += dt
		cat.sit = minf(t * 1.5, 1.0)
		orbit_a = lerpf(1.6, -0.3, t / 3.4)
		cat.look_yaw = sin(t * 1.3) * 0.5 if t > 1.0 else 0.0
		cat_v = Vector3.ZERO
		_integrate(dt)
		_studio_cam(dt)

	await _house()
	_say("", "")
	get_tree().quit()


# ------------------------------------------------------------------ house bot
var bot := {}


func _p() -> CatPlayer:
	return main.player


var chase := false
var chase2 := false


var _dbg := 0.0


func _bot_frame() -> float:
	_p().bot = bot.duplicate()
	var dt: float = await _frame()
	_dbg += dt
	if OS.get_cmdline_user_args().has("--debug") and _dbg > 0.1:
		_dbg = 0.0
		print("t=%.2f pos=%s floor=%s bot=%s" % [t_total, _p().global_position.snapped(Vector3.ONE * 0.01), _p().is_on_floor(), str(bot)])
	if chase:
		var pp := _p().global_position
		var want := Vector3(3.0, clampf(pp.y + 0.35, 0.6, 2.5), 1.25)
		cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-4.0 * dt)) if cam.global_position.distance_to(want) < 3.0 else want
		cam.fov = 60
		cam.look_at(pp + Vector3(0, 0.25, 0), Vector3.UP)
		_p().set_third_person(true)
		_p().cam_pivot.position = Vector3(0, 0.25, 0)
	elif chase2:
		var pp := _p().global_position
		var back := _p().global_transform.basis.z
		var want := pp + back * 1.0 + Vector3(0.35, 0.45, 0).rotated(Vector3.UP, _p().yaw)
		cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-3.5 * dt))
		cam.look_at(pp + Vector3(0, 0.2, 0), Vector3.UP)
		if not _p().third_person:
			_p().set_third_person(true)
		_p().cam_pivot.position = Vector3(0, 0.25, 0)
	elif _p().third_person:
		_p().set_third_person(false)
	return dt


func _yaw_to(target: Vector3) -> float:
	var d := target - _p().global_position
	return atan2(-d.x, -d.z)


func _turn(target_yaw: float, dt: float, rate := 7.0) -> void:
	var cur: float = bot.get("yaw", _p().yaw)
	bot.yaw = cur + clampf(wrapf(target_yaw - cur, -PI, PI), -rate * dt, rate * dt)


func _look(pitch: float, dur: float, yaw_add := 0.0) -> void:
	var t := 0.0
	var p0: float = bot.get("pitch", 0.0)
	var y0: float = bot.get("yaw", _p().yaw)
	bot.move = Vector2.ZERO
	while t < dur:
		var dt: float = await _bot_frame()
		t += dt
		var k := smoothstep(0.0, 1.0, t / dur)
		bot.pitch = lerpf(p0, pitch, k)
		bot.yaw = y0 + yaw_add * k


func _goto(target: Vector3, sprint := false, tol := 0.2, timeout := 6.0, jump_at := -1.0, pitch := -0.12) -> void:
	var t := 0.0
	var jumped := false
	while t < timeout:
		var d := target - _p().global_position
		d.y = 0
		if d.length() < tol:
			break
		_turn(_yaw_to(target), get_process_delta_time())
		bot.move = Vector2(0, 1)
		bot.sprint = sprint and d.length() > 1.4
		bot.pitch = LowPoly.damp(bot.get("pitch", 0.0), pitch, 4.0, get_process_delta_time())
		if jump_at > 0.0 and not jumped and d.length() < jump_at:
			bot.jump = true
			jumped = true
		elif jumped:
			bot.jump = false
		var dt: float = await _bot_frame()
		t += dt
	bot.jump = false
	bot.sprint = false


func _tap_jump() -> void:
	bot.jump = true
	await _bot_frame()
	await _bot_frame()
	bot.jump = false
	await _bot_frame()


func _house() -> void:
	var p := _p()
	main.hud.visible = true
	main.help_label.visible = false
	p.cam.current = true
	bot = {"move": Vector2.ZERO, "yaw": PI / 2 + 0.5, "pitch": -0.1}
	p.global_position = Vector3(0.0, 0.02, 1.0)
	_say("first person", "your own paws, same ik + gait as the full model")
	await _look(-0.6, 1.3, -0.5)
	await _look(-0.15, 0.6)
	# trot to the coffee table and hop up
	_say("trot", "3.2 m/s")
	await _goto(Vector3(-1.58, 0, 1.0), false, 0.08, 3.0)
	bot.move = Vector2.ZERO
	var t0 := 0.0
	while t0 < 0.25:
		t0 += await _bot_frame()
	_say("hop", "1 m straight up, onto the coffee table (0.42 m)")
	bot.move = Vector2(0, 1)
	bot.jump = true
	await _bot_frame()
	bot.jump = false
	t0 = 0.0
	while t0 < 0.3 or not p.is_on_floor():
		t0 += await _bot_frame()
	bot.move = Vector2.ZERO
	t0 = 0.0
	while t0 < 0.3:
		t0 += await _bot_frame()
	await _goto(Vector3(-2.68, 0, 1.03), false, 0.08, 1.0)
	bot.move = Vector2.ZERO
	# swat the mug off
	_say("swat", "knock things off tables (the most cat mechanic)")
	var mug_pos := Vector3(-3.0, 0.47, 1.12)
	var t := 0.0
	while t < 0.5:
		var dt: float = await _bot_frame()
		t += dt
		_turn(_yaw_to(mug_pos) + 0.15, dt)
		bot.pitch = LowPoly.damp(bot.get("pitch", 0.0), -0.45, 8.0, dt)
	bot.swat = true
	await _bot_frame()
	bot.swat = false
	t = 0.0
	while t < 0.8:
		var dt: float = await _bot_frame()
		t += dt
	# jump down and sprint to the chimney
	_say("sprint", "up to 11 m/s, fov kicks in with speed")
	await _goto(Vector3(-1.75, 0, 1.75), false, 0.3, 2.0)
	bot.move = Vector2.ZERO
	var tf := 0.0
	while tf < 0.35:
		var dt: float = await _bot_frame()
		tf += dt
		_turn(_yaw_to(Vector3(3.6, 0, 1.9)), dt, 12.0)
	await _goto(Vector3(3.6, 0, 1.9), true, 0.15, 4.0, -1.0, -0.05)
	bot.move = Vector2.ZERO
	var tw := 0.0
	while tw < 0.3:
		tw += await _bot_frame()
	# cut to an outside camera so you can see the whole cat climb
	_say("chimney", "wall kick: one per jump, touch down to get it back")
	cam.current = true
	chase = true
	await _goto(Vector3(4.62, 0, 1.875), false, 0.08, 2.5, -1.0, 0.1)
	bot.move = Vector2.ZERO
	t = 0.0
	while t < 0.35:
		t += await _bot_frame()
	# inside the shaft: lean toward the near wall, jump, then kick wall to wall
	bot.yaw = 0.0
	bot.move = Vector2(0, 1)
	bot.jump = true
	await _bot_frame()
	t = 0.0
	var since := 0.0
	var went_up := false
	while t < 3.0:
		var dt: float = await _bot_frame()
		t += dt
		since += dt
		bot.jump = false
		if t > 0.12:
			bot.yaw = PI
			bot.move = Vector2.ZERO
		if p.kicks_left == 0 and p.velocity.z > 0.5:
			bot.move = Vector2(0, 1)
			went_up = true
		if t > 0.08 and since > 0.09 and p.wall_time < 0.03 and absf(p.wall_normal.z) > 0.7 and p.kicks_left > 0 and p.velocity.y < 3.0:
			bot.jump = true
			since = 0.0
		if went_up and p.is_on_floor() and p.global_position.y > 1.5:
			break
	bot.jump = false
	t = 0.0
	bot.move = Vector2.ZERO
	while t < 0.5:
		var dt: float = await _bot_frame()
		t += dt
	chase = false
	p.cam.current = true
	_say("made it", "2.2 m up · the fish is the first puzzle goal")
	await _goto(Vector3(4.8, 0, 2.85), false, 0.12, 1.0, -1.0, -0.5)
	bot.move = Vector2.ZERO
	await _look(-0.9, 1.2, -1.2)
	await _look(-0.3, 1.0, -0.6)
	# ---- third person: drop off the shelf, pounce onto the dining table ----
	_say("third person", "same controller, camera pulled out")
	chase2 = true
	cam.current = true
	cam.fov = 62
	cam.global_position = p.global_position + Vector3(0.6, 0.5, 1.2)
	await _goto(Vector3(3.9, 0, 2.8), false, 0.2, 2.5, -1.0, -0.1)
	_say("2.2 m drop", "cats land it fine, the rig absorbs it")
	var tl := 0.0
	while tl < 0.3 or not p.is_on_floor():
		tl += await _bot_frame()
	await _goto(Vector3(3.1, 0, 0.62), false, 0.1, 3.0, -1.0, -0.1)
	bot.move = Vector2.ZERO
	tl = 0.0
	while tl < 0.4:
		var dt: float = await _bot_frame()
		tl += dt
		_turn(_yaw_to(Vector3(1.6, 0, 0.62)), dt, 8.0)
	_say("charged pounce", "crouch, wiggle, launch · 0.75 m table")
	bot.crouch = true
	tl = 0.0
	while tl < 0.75:
		var dt: float = await _bot_frame()
		tl += dt
		bot.jump = tl > 0.6
	bot.jump = false
	await _bot_frame()
	bot.crouch = false
	tl = 0.0
	while tl < 0.3 or not p.is_on_floor():
		tl += await _bot_frame()
	tl = 0.0
	while tl < 1.6:
		tl += await _bot_frame()
	chase2 = false


# ------------------------------------------------------------------ model variants
var vcats: Array[CatRig] = []
const VSTYLES := CatRig.STYLE_ORDER
const VFUR := {"painted": "painted facets", "tufts": "spiky tufts", "flecks": "dither flecks", "sawtooth": "sawtooth fringe", "shells": "chunky shell clumps"}


func _vplace(i: int, z0: float, yaw: float) -> void:
	var c := vcats[i]
	c.position = Vector3(40.0, 0, z0 - 1.1 + i * 0.55)
	c.rotation.y = yaw


func _run_variants() -> void:
	main.hud.visible = false
	main.player.process_mode = Node.PROCESS_MODE_DISABLED
	cam.current = true
	for i in VSTYLES.size():
		var c := CatRig.new()
		c.style = VSTYLES[i]
		main.add_child(c)
		vcats.append(c)
		var lab := Label3D.new()
		lab.text = "%d · %s\n%s" % [i + 1, CatRig.STYLES[VSTYLES[i]].label, ""]
		lab.font_size = 30
		lab.pixel_size = 0.0011
		lab.outline_size = 8
		lab.position = Vector3(0, 0.47, 0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.name = "Label"
		c.add_child(lab)
		_vplace(i, 0.0, -PI / 2 + 0.45)
	# 1) lineup, slow push in
	_say("blocky model variants", "same rig + animation, 5 takes on the mesh and the low poly fur")
	var t := 0.0
	while t < 3.5:
		var dt: float = await _frame()
		t += dt
		var k := t / 3.5
		cam.global_position = Vector3(41.35 - k * 0.15, 0.48 - k * 0.06, 0.05)
		cam.fov = 66
		cam.look_at(Vector3(40.0, 0.2, 0.0), Vector3.UP)
		for c in vcats:
			c.look_yaw = sin(t * 1.3 + c.position.x * 3.0) * 0.4
	# 2) portraits
	for c in vcats:
		c.get_node("Label").visible = false
	for i in vcats.size():
		var c := vcats[i]
		var st: Dictionary = CatRig.STYLES[VSTYLES[i]]
		_say("%d · %s" % [i + 1, st.label], "fur: %s" % VFUR[st.fur])
		t = 0.0
		while t < 1.7:
			var dt: float = await _frame()
			t += dt
			var hp := c.head.global_position
			var a := lerpf(-0.5, 0.35, t / 1.7)
			var fwd := -c.global_transform.basis.z
			var side := c.global_transform.basis.x
			cam.global_position = hp + (fwd * cos(a) + side * sin(a)) * 0.33 + Vector3(0, 0.035, 0)
			cam.fov = 50
			cam.look_at(hp + Vector3(0, -0.04, 0), Vector3.UP)
			c.look_yaw = sin(t * 2.0) * 0.25
	# 3) side view standing, then parade: all run together in an echelon
	for i in vcats.size():
		vcats[i].position = Vector3(39.6 - i * 0.28, 0, 4.0 + i * 0.62)
		vcats[i].rotation.y = 0.0
		vcats[i].look_yaw = 0.0
	var speeds := [[2.0, 0.0], [2.2, 0.9], [2.4, 2.8], [3.4, 9.5], [1.6, 0.0]]
	var labels := ["standing", "walk", "trot", "gallop", "stop"]
	var cur := 0.0
	for si in speeds.size():
		var dur: float = speeds[si][0]
		var target: float = speeds[si][1]
		_say(labels[si], "1 block · 2 chamfer · 3 hex facet · 4 wedge · 5 stepped fluff  (front to back)")
		t = 0.0
		var start := cur
		while t < dur:
			var dt: float = await _frame()
			t += dt
			cur = lerpf(start, target, clampf(t / 0.8, 0.0, 1.0))
			for c in vcats:
				c.position.z -= cur * dt
				c.drive_velocity = Vector3(0, 0, -cur)
			var mid := vcats[2].global_position
			cam.global_position = Vector3(41.25, 0.45, mid.z - 0.45)
			cam.fov = 58
			cam.look_at(Vector3(39.45, 0.12, mid.z - 0.25), Vector3.UP)
	# 4) sit in a row, front view
	_say("sit", "")
	var zc := vcats[2].position.z
	for i in vcats.size():
		vcats[i].drive_velocity = Vector3.ZERO
		_vplace(i, zc, -PI / 2)
	t = 0.0
	while t < 2.6:
		var dt: float = await _frame()
		t += dt
		for c in vcats:
			c.sit = minf(t * 1.5, 1.0)
			c.look_yaw = sin(t * 1.5 + c.position.x * 4.0) * 0.4
		var mid := vcats[2].global_position
		cam.global_position = mid + Vector3(1.25, 0.36, 0.0)
		cam.fov = 66
		cam.look_at(mid + Vector3(0, 0.12, 0), Vector3.UP)
	get_tree().quit()


# ------------------------------------------------------------------ pose test (stills for checking the rig)
func _wall(pos: Vector3, size: Vector3) -> void:
	Level.box(main, pos, size, Color(0.55, 0.5, 0.45))


func _run_posetest(args: PackedStringArray) -> void:
	print("posetest start")
	main.hud.visible = false
	main.player.process_mode = Node.PROCESS_MODE_DISABLED
	cam.current = true
	var sty := "block"
	var si := args.find("--style")
	if si >= 0:
		sty = args[si + 1]
	var poses := ["walk", "trot", "gallop", "stretch", "groom", "loaf", "scratch", "hang", "pull", "climb", "pounce", "pin", "sit", "stalk"]
	var cats := []
	for i in poses.size():
		var c := CatRig.new()
		c.style = sty
		main.add_child(c)
		var z := -6.0 + i * 1.0
		c.position = Vector3(40.0, 0, z)
		var lab := Label3D.new()
		lab.text = poses[i]
		lab.font_size = 40
		lab.pixel_size = 0.001
		lab.position = Vector3(0, 0.5, 0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		c.add_child(lab)
		cats.append(c)
		match poses[i]:
			"scratch":
				_wall(Vector3(40.0, 0.4, z - 0.115 - 0.05), Vector3(0.4, 0.8, 0.1))
				c.rear = 1.0
				c.scratch = 1.0
				c.scratch_dist = 0.115
			"hang", "pull":
				# ledge top 0.4 above the feet, wall face just in front
				var face_z := z - 0.097
				_wall(Vector3(40.0, 0.2 + 0.2, face_z - 0.2), Vector3(0.4, 0.4, 0.4))
				c.position.y = 0.0
				c.clamber = 1.0
				c.ledge_world = Vector3(40.0, 0.4, face_z)
				c.clamber_pull = 0.0 if poses[i] == "hang" else 0.5
			"climb":
				_wall(Vector3(40.0, 0.6, z - 0.15), Vector3(0.3, 1.2, 0.1))
				var n := Vector3(0, 0, 1)
				c.transform = Transform3D(Basis(n.cross(Vector3.DOWN), n, Vector3.DOWN), Vector3(40.0, 0.25, z - 0.1))
				c.climb = 1.0
			"stretch":
				c.stretch = 1.0
			"groom":
				c.sit = 1.0
				c.groom = 1.0
			"loaf":
				c.loaf = 1.0
			"sit":
				c.sit = 1.0
			"stalk":
				c.crouch = 1.0
	var t := 0.0
	var tt := 0.0
	var shot := 0
	var frame_t: float = float(args[args.find("--at") + 1]) if args.find("--at") >= 0 else 1.6
	while true:
		var dt: float = await _frame()
		t += dt
		for i in poses.size():
			var c: CatRig = cats[i]
			match poses[i]:
				"walk":
					c.drive_velocity = Vector3(0, 0, -0.7)
				"trot":
					c.drive_velocity = Vector3(0, 0, -2.6)
				"gallop":
					c.drive_velocity = Vector3(0, 0, -8.0)
				"stalk":
					c.drive_velocity = Vector3(0, 0, -0.5)
				"climb":
					c.drive_velocity = Vector3(0, 0.8, 0)
				"pounce":
					c.on_floor = false
					c.drive_velocity = Vector3(0, 1.5, -3.0)
				"pin":
					c.pin = 1.0
			c.position.z = -6.0 + i * 1.0 if poses[i] != "climb" else c.position.z
		# camera sweeps along the row: one still per cat
		var idx := maxi(int((t - 1.0) / 0.5), 0)
		if idx >= poses.size():
			get_tree().quit()
			return
		var c2: CatRig = cats[idx]
		var p := Vector3(40.0, 0, -6.0 + idx * 1.0)
		cam.fov = 50
		var view := "--front" in args
		cam.global_position = p + (Vector3(0.55, 0.3, -0.6) if view else Vector3(0.75, 0.32, -0.1))
		cam.look_at(p + Vector3(0, 0.22, -0.1), Vector3.UP)


# ------------------------------------------------------------------ parkour showcase (bot drives the real controller)
var follow := false


var _pk_dbg := 0.0


func _pk_frame() -> float:
	var dt: float = await _bot_frame()
	_pk_dbg += dt
	if _pk_dbg > 0.5:
		_pk_dbg = 0.0
		var pl := _p()
		var mm: Node3D = get_tree().get_first_node_in_group("prey")
		print("  t=%.1f pos=%s floor=%s climb=%s clamber=%s scratch=%s mouse=%s" % [t_total, pl.global_position.snapped(Vector3.ONE * 0.01), pl.is_on_floor(), pl.climbing, pl.clambering, pl.scratching, mm.global_position.snapped(Vector3.ONE * 0.01) if mm else Vector3.ZERO])
	if follow:
		var p := _p()
		var pp := p.global_position
		var back := Vector3(sin(p.yaw), 0, cos(p.yaw))
		var want := pp + back * 1.05 + Vector3(0, 0.55, 0) + back.cross(Vector3.UP) * 0.35
		# keep the camera out of furniture: pull it in front of whatever is in the way
		var piv := pp + Vector3(0, 0.3, 0)
		var q := PhysicsRayQueryParameters3D.create(piv, want)
		q.exclude = [p.get_rid()]
		var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			want = piv.lerp(hit.position, 0.85)
			cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-12.0 * dt))
		else:
			cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-3.0 * dt))
		var look := pp + Vector3(0, 0.22, 0)
		if p.climbing or p.clambering:
			look += Vector3.UP * 0.15
		cam.look_at(look, Vector3.UP)
		if not p.third_person:
			p.set_third_person(true)
		p.cam_pivot.position = Vector3(0, 0.25, 0)
	return dt


func _wait(dur: float) -> void:
	var t := 0.0
	while t < dur:
		t += await _pk_frame()


func _face(target: Vector3, dur := 0.4) -> void:
	var t := 0.0
	bot.move = Vector2.ZERO
	while t < dur:
		var dt: float = await _pk_frame()
		t += dt
		_turn(_yaw_to(target), dt, 9.0)


func _walk_to(target: Vector3, tol := 0.1, timeout := 4.0, crouch := false) -> void:
	var t := 0.0
	bot.crouch = crouch
	while t < timeout:
		var d := target - _p().global_position
		d.y = 0
		if d.length() < tol:
			break
		_turn(_yaw_to(target), get_process_delta_time(), 8.0)
		bot.move = Vector2(0, clampf(d.length() / 0.4, 0.3, 1.0))
		t += await _pk_frame()
	bot.move = Vector2.ZERO
	bot.crouch = false


func _aim_at(point: Vector3, hold := 0.7, track: Node3D = null) -> void:
	# look at a spot, hold right mouse, let go
	var p := _p()
	var t := 0.0
	bot.aim = true
	while t < hold:
		var dt: float = await _pk_frame()
		t += dt
		if track:
			point = track.global_position
		_turn(_yaw_to(point), dt, 9.0)
		var eye := p.cam.global_position
		var d := point - eye
		var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
		var fwd := -p.cam.global_transform.basis.z
		var cur_pitch := asin(clampf(fwd.y, -1.0, 1.0))
		bot.pitch = clampf(bot.get("pitch", 0.0) + (want_pitch - cur_pitch) * minf(dt * 12.0, 1.0), -1.4, 1.4)
	var fw := -p.cam.global_transform.basis.z
	print("[aim] valid=%s kind=%s point=%s target=%s cam=%s fwd=%s" % [p.aim_valid, p.aim_kind, p.aim_point, point, p.cam.global_position, fw])
	bot.aim = false
	await _pk_frame()
	var t2 := 0.0
	while t2 < 0.25 or not (p.is_on_floor() or p.clambering or p.climbing):
		t2 += await _pk_frame()
		if t2 > 3.0:
			break


func _run_parkour() -> void:
	var p := _p()
	main.hud.visible = false
	main.help_label.visible = false
	cam.current = true
	cam.fov = 60
	follow = true
	bot = {"move": Vector2.ZERO, "yaw": -PI / 2, "pitch": 0.0}
	p.global_position = Vector3(-0.2, 0.02, 0.6)
	cam.global_position = p.global_position + Vector3(-1.0, 0.6, 0.4)
	await _wait(0.6)

	_say("aim + release leap", "hold right mouse, look where you want to land, let go")
	await _aim_at(Vector3(0.8, 0.735, 0.6), 0.9)
	await _wait(0.5)

	_say("down", "aimed leaps work downward too")
	await _aim_at(Vector3(0.2, 0.0, -0.8), 0.6)
	await _wait(0.3)
	await _walk_to(Vector3(1.6, 0, -2.5), 0.1)
	_say("onto the counter", "0.92 m: look at the edge and it finds the top")
	await _aim_at(Vector3(1.6, 0.9, -3.38), 0.7)
	await _wait(0.4)
	await _aim_at(Vector3(2.9, 0.0, -2.0), 0.5)
	await _wait(0.2)
	await _walk_to(Vector3(4.45, 0, -2.3), 0.1)
	_say("too high to land? grab and haul", "fridge top 1.85 m: leap, hook the edge, hind paws scrabble, pull up")
	await _aim_at(Vector3(4.45, 1.82, -3.3), 0.7)
	var t := 0.0
	while t < 2.0 and (p.clambering or not p.is_on_floor()):
		t += await _pk_frame()
		bot.move = Vector2.ZERO if (p.clambering and p.clamber_phase == 1 and p.clamber_t < 0.35) else Vector2(0, 1)
	bot.move = Vector2.ZERO
	await _wait(0.6)
	_say("and back down", "1.85 m drop, the forelegs take it first")
	await _aim_at(Vector3(4.2, 0.0, -1.6), 0.6)
	await _wait(0.3)
	await _walk_to(Vector3(3.0, 0, -1.0), 0.15)
	await _walk_to(Vector3(3.0, 0, 2.1), 0.15)

	_say("climb", "jump at anything rough holding forward: claws in, bound up it")
	await _walk_to(Vector3(0.35, 0, 2.15), 0.08, 5.0)
	await _walk_to(Vector3(0.35, 0, 2.47), 0.04, 2.0)
	await _face(Vector3(0.35, 0.5, 2.7), 0.3)
	bot.move = Vector2(0, 1)
	bot.jump = true
	await _pk_frame()
	await _pk_frame()
	bot.jump = false
	t = 0.0
	while t < 5.0:
		t += await _pk_frame()
		if p.is_on_floor() and not p.climbing and not p.clambering and t > 1.0:
			break
		if not p.climbing and not p.clambering and p.global_position.y > 1.0:
			bot.move = Vector2.ZERO
	bot.move = Vector2.ZERO
	await _wait(0.8)

	_say("hunt", "stalk, wiggle, pounce: forepaws pin the toy mouse")
	var m: Node3D = get_tree().get_first_node_in_group("prey")
	await _aim_at(Vector3(0.6, 0.0, 1.7), 0.5)
	await _wait(0.3)
	if m:
		m.global_position = p.global_position + Vector3(-1.2, 0.0, -0.3)
		m.set("_t", 6.0)
		(m as RigidBody3D).sleeping = false
		await _walk_to(m.global_position + (p.global_position - m.global_position).normalized() * 0.75, 0.1, 4.0, true)
		await _aim_at(m.global_position, 0.9, m)
	await _wait(1.0)

	_say("scratch", "hold F at a wall, couch or post")
	await _walk_to(Vector3(0.0, 0, 1.6), 0.15, 4.0)
	await _walk_to(Vector3(-2.2, 0, 2.2), 0.1, 4.0)
	await _face(Vector3(-2.2, 0.2, 3.0), 0.4)
	bot.pitch = 0.3
	bot.scratch = true
	await _wait(2.6)
	bot.scratch = false
	await _wait(0.8)
	follow = false
	get_tree().quit()


# ------------------------------------------------------------------ slow motion animation study (all 5 models)
func _swap_cat(style: String) -> void:
	var old := cat
	cat = CatRig.new()
	cat.style = style
	main.add_child(cat)
	cat.position = Vector3(40.0, 0, 3.0)
	cat_v = Vector3.ZERO
	if old:
		old.queue_free()


func _slow_side(dur: float, speed: float, ts: float, h := 0.2, dist := 0.95) -> void:
	Engine.time_scale = ts
	var t := 0.0
	while t < dur * ts:
		var dt: float = await _frame()
		t += dt
		cat_v = Vector3(0, cat_v.y, -speed)
		_integrate(dt)
		var p := cat.global_position
		cam.global_position = Vector3(p.x + dist, h + p.y * 0.4, p.z - 0.05)
		cam.look_at(Vector3(p.x, 0.07 + p.y * 0.5, p.z - 0.05), Vector3.UP)
	Engine.time_scale = 1.0


func _run_anim(quit := true) -> void:
	main.hud.visible = false
	main.help_label.visible = false
	cam.current = true
	cam.fov = 45
	main.player.process_mode = Node.PROCESS_MODE_DISABLED
	main.player.global_position = Vector3(0, -50, 0)
	_swap_cat("block")
	_say("walk, 1/3 speed", "lateral sequence, paws placed single track, wrists flick on lift off, hocks rise before push off")
	cat.position.z = 3.0
	await _slow_side(4.0, 0.75, 0.33, 0.16, 0.8)
	_swap_cat("block_tux")
	_say("trot, 1/3 speed", "diagonal pairs, shoulder blades ride up under load, tail is a spring chain")
	await _slow_side(3.2, 2.6, 0.33, 0.18, 1.0)
	_swap_cat("stepped_coon")
	_say("gallop, 1/4 speed", "rotary gallop: spine coils and extends, head drops low, ears flatten")
	await _slow_side(3.0, 8.5, 0.25, 0.2, 1.25)
	# jump + front first landing
	_swap_cat("block_lean")
	_say("jump + landing, 1/3 speed", "forepaws tuck going up, reach for the ground coming down, front legs take the hit first")
	Engine.time_scale = 0.33
	var t := 0.0
	var jumped := false
	while t < 3.2 * 0.33:
		var dt: float = await _frame()
		t += dt
		if t > 0.35 * 0.33 and not jumped:
			jumped = true
			cat_v.y = 4.2
			cat.on_floor = false
		cat_v = Vector3(0, cat_v.y, -1.6)
		_integrate(dt)
		var p := cat.global_position
		cam.global_position = Vector3(p.x + 1.3, 0.22 + p.y * 0.85, p.z - 0.1)
		cam.look_at(Vector3(p.x, 0.08 + p.y * 0.9, p.z - 0.1), Vector3.UP)
	Engine.time_scale = 1.0
	cat.queue_free()
	cat = null
	# behaviours, one per model
	_say("behaviours", "stretch · groom · loaf · stalk wiggle · scratch")
	var acts := [["block", "stretch"], ["stepped_persian", "groom"], ["stepped_smoke", "loaf"], ["block_bob", "stalk"], ["stepped", "scratch"]]
	var cs := []
	for i in acts.size():
		var c := CatRig.new()
		c.style = acts[i][0]
		main.add_child(c)
		c.position = Vector3(40.0, 0, -1.2 + i * 0.6)
		c.rotation.y = -PI / 2 + 0.25
		if acts[i][1] == "scratch":
			c.rotation.y = 0.0
			_wall(Vector3(40.0, 0.45, c.position.z - 0.115 - 0.05), Vector3(0.4, 0.9, 0.1))
		cs.append(c)
	t = 0.0
	while t < 9.0:
		var dt: float = await _frame()
		t += dt
		for i in acts.size():
			var c: CatRig = cs[i]
			var k := smoothstep(0.2, 0.9, t)
			match acts[i][1]:
				"stretch":
					c.stretch = k * (1.0 - smoothstep(4.5, 5.5, t))
				"groom":
					c.sit = k
					c.groom = smoothstep(0.6, 1.2, t)
				"loaf":
					c.loaf = k
				"stalk":
					c.crouch = k
					c.charge = smoothstep(2.0, 2.4, t)
					if t > 4.8:
						c.charge = 0.0
				"scratch":
					c.rear = k
					c.scratch = k
		# slow dolly along the row, then close on the groomer
		var u := clampf(t / 9.0, 0.0, 1.0)
		var z := lerpf(-1.3, 1.3, smoothstep(0.0, 1.0, u))
		cam.fov = 50
		cam.global_position = Vector3(41.0, 0.36, z + 0.3)
		cam.look_at(Vector3(40.0, 0.1, z), Vector3.UP)
	for c in cs:
		c.queue_free()
	main.player.process_mode = Node.PROCESS_MODE_INHERIT
	if quit:
		get_tree().quit()


## headless-friendly check of swats + claw grabs + step hops: prints what the props do
func _run_swattest() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	p.global_position = Vector3(1.3, 0.77, 0.85)
	p.yaw = 0.0
	bot.pitch = -0.6
	bot.yaw = 0.0
	for i in 30:
		await get_tree().physics_frame
	var mugs := []
	for n in main.get_node("Level").get_children():
		if n is RigidBody3D and n.global_position.distance_to(p.global_position) < 0.8:
			mugs.append(n)
	print("near: ", mugs.map(func(m): return [m.global_position.snapped(Vector3.ONE * 0.01), m.mass]))
	bot.swat = true
	await get_tree().physics_frame
	bot.swat = false
	for i in 20:
		await get_tree().physics_frame
	for m in mugs:
		print("after swat: ", m.global_position.snapped(Vector3.ONE * 0.01), " v=", m.linear_velocity.snapped(Vector3.ONE * 0.01))
	for i in 90:
		await get_tree().physics_frame
	# claw grab the other mug and drag it by turning
	p.global_position = Vector3(1.9, 0.77, 1.1)
	bot.yaw = 0.0
	bot.pitch = -0.7
	for i in 30:
		await get_tree().physics_frame
	bot.paw_r = true      # hold a paw with nothing to rake = claw hook (cat_combat.gd)
	for i in 46:
		await get_tree().physics_frame
	print("claw rb: ", p.claw_rb, " static: ", p.claw_static)
	for i in 60:
		bot.yaw = -0.8 * i / 60.0
		await get_tree().physics_frame
	if p.claw_rb:
		print("dragged to: ", p.claw_rb.global_position.snapped(Vector3.ONE * 0.01))
	bot.paw_r = false
	await get_tree().physics_frame
	# claw at the floor and drag marks
	p.global_position = Vector3(-1.0, 0.02, 1.2)
	bot.yaw = 0.0
	bot.pitch = -0.9
	for i in 20:
		await get_tree().physics_frame
	bot.paw_r = true      # hold a paw with nothing to rake = claw hook (cat_combat.gd)
	for i in 46:
		await get_tree().physics_frame
	print("floor claw static: ", p.claw_static)
	for i in 60:
		bot.yaw = 0.6 * i / 60.0
		await get_tree().physics_frame
	print("marks: ", p._marks.size())
	bot.paw_r = false
	# stairs: walk up the bedroom wing stairs
	p.global_position = Vector3(5.8, 0.02, -3.55)
	bot.yaw = -PI / 2
	bot.pitch = 0.0
	bot.move = Vector2(0, 1)
	for i in 300:
		await get_tree().physics_frame
	print("stairs end pos: ", p.global_position.snapped(Vector3.ONE * 0.01))
	bot.move = Vector2.ZERO
	# step hop: walk into a 0.19 step (first stair from the side is the ramp; use the patio threshold-ish box)
	get_tree().quit()


## logs per-frame camera motion while trotting / turning / running along walls, flags spikes
func _run_camtest() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	if "--nointerp" in OS.get_cmdline_user_args():
		p.set_process(false)
	var segs := [
		["trot straight", Vector3(-3.0, 0.02, 0.0), 0.0, Vector2(0, 1), false, 0.0],
		["trot turning", Vector3(-3.0, 0.02, 0.0), 0.0, Vector2(0, 1), false, 1.2],
		["sprint straight", Vector3(-4.0, 0.02, -1.0), -PI / 2, Vector2(0, 1), true, 0.0],
		["along wall", Vector3(-4.0, 0.02, -3.85), -PI / 2, Vector2(0.3, 1), false, 0.0],
		["yard trot", Vector3(0.0, 0.02, 9.0), -PI / 2, Vector2(0, 1), false, 0.0],
	]
	for sg in segs:
		p.global_position = sg[1]
		p.velocity = Vector3.ZERO
		bot.yaw = sg[2]
		bot.pitch = 0.0
		bot.move = Vector2.ZERO
		for i in 20:
			await get_tree().physics_frame
		bot.move = sg[3]
		bot.sprint = sg[4]
		var prev := p.cam.global_position
		var prev_b := p.cam.global_transform.basis
		var maxd := 0.0
		var maxjerk := 0.0
		var maxrot := 0.0
		var prevd := Vector3.ZERO
		var yv: Array = []
		for i in 90:
			bot.yaw = bot.yaw + sg[5] / 60.0
			await get_tree().process_frame
			if p.is_processing():
				p._process(0.0)   # process_frame fires before _process: apply this frame's camera now
			var c := p.cam.global_position
			var d := c - prev
			var expect := p.velocity / 60.0
			var off := (d - expect).length()
			maxd = maxf(maxd, off)
			maxjerk = maxf(maxjerk, (d - prevd).length())
			var q := p.cam.global_transform.basis.get_rotation_quaternion()
			var q0 := prev_b.get_rotation_quaternion()
			maxrot = maxf(maxrot, q0.angle_to(q) - absf(sg[5] / 60.0))
			yv.append(snappedf(Vector2(d.x, d.z).length() * 1000.0, 0.1))
			prevd = d
			prev = c
			prev_b = p.cam.global_transform.basis
		print("%s: speed %.2f  max off-velocity step %.4f m  max jerk %.4f  max extra rot %.4f rad  gait_w %s" % [sg[0], Vector2(p.velocity.x, p.velocity.z).length(), maxd, maxjerk, maxrot, p.rig.gait_w])
		print("   step mm: ", yv.slice(15, 45))
		bot.sprint = false
	get_tree().quit()


func _run_hoptest() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	p.global_position = Vector3(0.0, 0.02, 10.0)
	bot.yaw = 0.0
	for i in 30:
		await get_tree().physics_frame
	var start := p.global_position
	var air := 0
	var maxy := 0.0
	bot.move = Vector2(1, 0)
	for i in 30:
		await get_tree().physics_frame
		if not p.is_on_floor():
			air += 1
		maxy = maxf(maxy, p.global_position.y - start.y)
	bot.move = Vector2.ZERO
	for i in 30:
		await get_tree().physics_frame
	print("tap right: moved ", (p.global_position - start).snapped(Vector3.ONE * 0.01), " air %.2fs peak %.3f" % [air / 144.0, maxy])
	# holding right: repeated hops
	start = p.global_position
	bot.move = Vector2(1, 0)
	for i in 288:
		await get_tree().physics_frame
	bot.move = Vector2.ZERO
	print("hold right 2s: moved ", (p.global_position - start).snapped(Vector3.ONE * 0.01))
	# sprint diagonal vs forward
	for case in [[Vector2(0.7, 0.7), "diag sprint"], [Vector2(0, 1), "fwd sprint"], [Vector2(0, -1), "back"]]:
		p.global_position = Vector3(8.0, 0.02, 9.0)
		p.velocity = Vector3.ZERO
		bot.yaw = PI / 2
		for i in 20:
			await get_tree().physics_frame
		bot.move = case[0]
		bot.sprint = true
		var top := 0.0
		for i in 144:
			await get_tree().physics_frame
			top = maxf(top, Vector2(p.velocity.x, p.velocity.z).length())
			if OS.has_environment("DBG") and i % 8 == 0:
				print("  ", i, " ", p.velocity.snapped(Vector3.ONE * 0.01), " floor=", p.is_on_floor(), " slip %.2f" % p.slip, " ", p.global_position.snapped(Vector3.ONE*0.01))
		bot.move = Vector2.ZERO
		bot.sprint = false
		print(case[1], ": top speed %.2f" % top, " mantle=%s clamber=%s climb=%s scratch=%s charging=%s" % [p.mantling, p.clambering, p.climbing, p.scratching, p.charging])
	# orbit cam: camera relative movement
	p.set_view(2)
	p.global_position = Vector3(0.0, 0.02, 12.0)
	p.orb_yaw = 0.0
	bot.erase("yaw")
	p.yaw = PI
	for i in 20:
		await get_tree().physics_frame
	var s0 := p.global_position
	bot.move = Vector2(1, 0)   # camera right = +x
	for i in 144:
		await get_tree().physics_frame
	bot.move = Vector2.ZERO
	print("orbit right: moved ", (p.global_position - s0).snapped(Vector3.ONE * 0.01), " yaw %.2f  cam d %.2f" % [p.yaw, p.cam.position.z])
	p.global_position = Vector3(4.5, 0.02, -2.0)   # tight spot in the living room near the wall
	p.orb_pitch = -0.2
	for oy in [0.0, PI / 2, PI, -PI / 2]:
		p.orb_yaw = oy
		for i in 60:
			await get_tree().physics_frame
		print("orbit near wall yaw %.2f cam d %.2f" % [oy, p.cam.position.z])
	# grip: gallop on grass / wood then yank the heading round
	p.set_view(0)
	for spot in [Vector3(0.0, 0.02, 9.0), Vector3(0.0, 0.02, -3.0)]:
		p.global_position = spot
		p.velocity = Vector3.ZERO
		bot.yaw = PI / 2
		for i in 20:
			await get_tree().physics_frame
		var sf0 := p.surface
		bot.move = Vector2(0, 1)
		bot.sprint = true
		for i in 100:
			await get_tree().physics_frame
		var top := Vector2(p.velocity.x, p.velocity.z).length()
		bot.yaw = -PI / 2
		var mx := 0.0
		for i in 60:
			await get_tree().physics_frame
			mx = maxf(mx, p.slip)
		bot.move = Vector2.ZERO
		bot.sprint = false
		print("grip on %s->%s: speed %.2f  max slip %.2f  turf %d" % [sf0, p.surface, top, mx, p._tears.size()])
	get_tree().quit()


# front paws must stay on the ground while running and slipping on the floor (bug: low grip threw
# them up into the wall-scramble pose). sprints on wood, yanks the heading round, starts/stops hard
func _run_pawtest() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	p.set_view(0)
	for spot in [Vector3(0.0, 0.02, -3.0), Vector3(0.0, 0.02, 9.0)]:
		p.global_position = spot
		p.velocity = Vector3.ZERO
		bot.yaw = PI / 2
		for i in 30:
			await get_tree().physics_frame
		var surf: String = p.surface
		var hi := 0.0
		var mslip := 0.0
		var msc := 0.0
		var n := 0
		for step in [[Vector2(0, 1), true, PI / 2, 90], [Vector2(0, 1), true, -PI / 2, 70], [Vector2.ZERO, false, -PI / 2, 30], [Vector2(0, 1), true, 0.0, 50], [Vector2(0, 1), false, PI, 60], [Vector2.ZERO, false, PI, 30]]:
			bot.move = step[0]
			bot.sprint = step[1]
			bot.yaw = step[2]
			for i in step[3]:
				await get_tree().physics_frame
				if p.is_on_floor():
					n += 1
					mslip = maxf(mslip, p.slip)
					msc = maxf(msc, p.rig.scramble)
					hi = maxf(hi, maxf(p.rig.fp_foot[0].y, p.rig.fp_foot[1].y))
		bot.move = Vector2.ZERO
		bot.sprint = false
		print("pawtest on %s: grounded frames %d  max slip %.2f  max scramble %.2f  max front paw height %.3f m" % [surf, n, mslip, msc, hi])
	# land out of a wall slide: scramble must not stay on afterwards
	p.global_position = Vector3(0.0, 0.02, -3.0)
	p.velocity = Vector3.ZERO
	for i in 20:
		await get_tree().physics_frame
	p.wall_sliding = true
	bot.move = Vector2(0, 1)
	var sc_end := 0.0
	for i in 60:
		await get_tree().physics_frame
		sc_end = p.rig.scramble
	bot.move = Vector2.ZERO
	print("pawtest after landing from a wall slide: wall_sliding=%s scramble %.2f" % [p.wall_sliding, sc_end])
	# baseline: plain straight trot, no slip
	p.global_position = Vector3(0.0, 0.02, -3.0)
	bot.yaw = PI / 2
	for i in 30:
		await get_tree().physics_frame
	var hb := 0.0
	bot.move = Vector2(0, 1)
	for i in 120:
		await get_tree().physics_frame
		if i > 40:
			hb = maxf(hb, maxf(p.rig.fp_foot[0].y, p.rig.fp_foot[1].y))
	bot.move = Vector2.ZERO
	print("pawtest baseline trot front paw height %.3f m" % hb)
	get_tree().quit()


## paw dust: counts puffs per move. steady running should throw none, hard pushes should
func _run_dusttest() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	p.dust.log_puffs = OS.has_environment("DUST_LOG")
	var cases := [
		["stand still", {"move": Vector2.ZERO}, 72],
		["trot start", {"move": Vector2(0, 1)}, 72],
		["steady trot", {"move": Vector2(0, 1)}, 288],
		["trot stop", {"move": Vector2.ZERO}, 100],
		["sprint start", {"move": Vector2(0, 1), "sprint": true}, 144],
		["steady sprint", {"move": Vector2(0, 1), "sprint": true}, 144],
		["hard stop", {"move": Vector2.ZERO}, 144],
		["hop", {"move": Vector2.ZERO, "jump": true}, 4],
		["hop air+land", {"move": Vector2.ZERO}, 200],
		["side hop", {"move": Vector2(1, 0)}, 10],
		["side hop land", {"move": Vector2.ZERO}, 120],
	]
	# a big flat test pad up in the sky so nothing gets in the way
	var pad := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 120)
	cs.shape = bs
	pad.add_child(cs)
	main.add_child(pad)
	pad.global_position = Vector3(0, 49.5, 0)
	for sf in ["dirt", "wood"]:
		pad.set_meta("surface", sf)
		var spot := Vector3(40.0, 50.02, 0.0)
		p.global_position = spot
		p.velocity = Vector3.ZERO
		bot.clear()
		bot.yaw = PI / 2
		p.orb_yaw = PI / 2
		for i in 60:
			await get_tree().physics_frame
		print("-- surface ", p.surface)
		for c in cases:
			for k in c[1]:
				bot[k] = c[1][k]
			if not c[1].has("sprint"):
				bot.sprint = false
			if not c[1].has("jump"):
				bot.jump = false
			var n0: int = p.dust.puffs
			var k0: Dictionary = p.dust.last_kinds.duplicate()
			for i in c[2]:
				await get_tree().physics_frame
			var kinds := {}
			for k in p.dust.last_kinds:
				var d: int = p.dust.last_kinds[k] - int(k0.get(k, 0))
				if d > 0:
					kinds[k] = d
			print("%-14s puffs %2d %s  speed %.1f x %.1f" % [c[0], p.dust.puffs - n0, str(kinds), Vector2(p.velocity.x, p.velocity.z).length(), p.global_position.x])
		# sharp cut at a sprint
		bot.move = Vector2(0, 1)
		bot.sprint = true
		p.global_position = spot
		for i in 220:
			await get_tree().physics_frame
		var n1: int = p.dust.puffs
		bot.yaw = -PI / 2
		p.orb_yaw = -PI / 2
		for i in 72:
			await get_tree().physics_frame
			if OS.has_environment("DUST_LOG") and i % 8 == 0:
				print("   v ", p.velocity.snapped(Vector3.ONE * 0.1), " slip %.2f" % p.slip, " modes ", p.rig.gait.mode)
		print("%-14s puffs %2d" % ["sprint u-turn", p.dust.puffs - n1])
		bot.move = Vector2.ZERO
		bot.sprint = false
		for i in 144:
			await get_tree().physics_frame
		# drop from 1.2 m
		p.global_position = spot + Vector3(0, 1.2, 0)
		p.velocity = Vector3.ZERO
		var n2: int = p.dust.puffs
		for i in 200:
			await get_tree().physics_frame
		print("%-14s puffs %2d %s" % ["drop 1.2m", p.dust.puffs - n2, str(p.dust.last_kinds)])
	get_tree().quit()


## paw dust showcase: side tracking camera on a dirt pad, slowed down so each puff reads
func _run_dustshow() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	main.hud.visible = false
	var pad := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 12)
	cs.shape = bs
	pad.add_child(cs)
	pad.set_meta("surface", "dirt")
	main.add_child(pad)
	pad.global_position = Vector3(0, 49.5, 0)
	LowPoly.part(pad, LowPoly.box(), Color(0.55, 0.43, 0.3), Vector3.ZERO, Vector3(120, 1, 12))
	for k in 120:
		# a stripe every metre so you can see the speed
		LowPoly.part(pad, LowPoly.box(), Color(0.48, 0.37, 0.25), Vector3(-60 + k, 0.501, 0), Vector3(0.08, 0.002, 12))
	p.set_third_person(true)
	cam.current = true
	cam.fov = 38
	p.global_position = Vector3(40, 50.02, 0)
	p.velocity = Vector3.ZERO
	bot.clear()
	bot.yaw = PI / 2
	p.orb_yaw = PI / 2
	Engine.time_scale = 0.4
	var shots := [
		["steady trot", "no dust: the paws aren't pushing any harder than it takes to keep going", {"move": Vector2(0, 1)}, 2.6, false],
		["hard stop", "each paw that digs in throws a puff from right where it stands", {"move": Vector2.ZERO}, 1.4, false],
		["sprint start", "the push off kicks dirt back off each paw", {"move": Vector2(0, 1), "sprint": true}, 1.6, false],
		["steady gallop", "constant speed: nothing", {"move": Vector2(0, 1), "sprint": true}, 1.2, false],
		["skid to a stop", "", {"move": Vector2.ZERO}, 1.6, false],
		["hop + landing", "hind paws push off, then a splash under each paw as it lands", {"move": Vector2.ZERO, "jump": true}, 0.05, false],
		["hop + landing", "hind paws push off, then a splash under each paw as it lands", {"move": Vector2.ZERO}, 1.6, false],
		["drop from 1.2 m", "", {"move": Vector2.ZERO}, 1.8, true],
	]
	var look := p.global_position
	for sh in shots:
		_say(sh[0], sh[1])
		bot.sprint = false
		bot.jump = false
		for k in sh[2]:
			bot[k] = sh[2][k]
		if sh[4]:
			p.global_position += Vector3(0, 1.2, 0)
			p.velocity = Vector3.ZERO
		var t := 0.0
		while t < sh[3]:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			var pp := p.global_position
			look = look.lerp(pp, 1.0 - exp(-30.0 * dt))
			look.y = pp.y
			var cy := maxf(50.0, pp.y - 0.05)
			cam.global_position = Vector3(look.x - 0.25, cy + 0.3, 1.45)
			cam.look_at(Vector3(look.x, cy + 0.1, 0), Vector3.UP)
	Engine.time_scale = 1.0
	get_tree().quit()


func _pad(w: float, d: float, y: float, surf: String, visual := false) -> StaticBody3D:
	var pad := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 1, d)
	cs.shape = bs
	pad.add_child(cs)
	pad.set_meta("surface", surf)
	main.add_child(pad)
	pad.global_position = Vector3(0, y - 0.5, 0)
	if visual:
		LowPoly.part(pad, LowPoly.box(), Color(0.55, 0.43, 0.3), Vector3.ZERO, Vector3(w, 1, d))
		for k in int(w):
			LowPoly.part(pad, LowPoly.box(), Color(0.48, 0.37, 0.25), Vector3(-w * 0.5 + k, 0.501, 0), Vector3(0.06, 0.002, d))
	return pad


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## one dodge from standing: returns what it did
func _dodge(p: CatPlayer, move: Vector2) -> Dictionary:
	var bot: Dictionary = p.bot
	var y0 := p.yaw
	var s0 := p.stamina.value
	var c0 := p.dash.count
	var from := p.global_position
	bot.move = move
	bot.dash = true
	await get_tree().physics_frame
	bot.dash = false
	var t := 0.0
	var air := 0.0
	var ifr := 0.0
	var pushed_at := -1.0
	var hmax := 0.0
	var was_air := false
	var touch := Vector3.INF
	var miss := -1.0
	while t < 1.5:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if p.dash.state == CatDash.AIR:
			air += dt
			if pushed_at < 0.0:
				pushed_at = t
		if p.is_invulnerable():
			ifr += dt
		if was_air and p.dash.state != CatDash.AIR and touch == Vector3.INF:
			touch = p.global_position
			bot.move = Vector2.ZERO   # let go on touch down (a held a / d is a side hop of its own)
			if p.dash.land_at != Vector3.INF:
				miss = Vector2(touch.x - p.dash.land_at.x, touch.z - p.dash.land_at.z).length()
		was_air = p.dash.state == CatDash.AIR
		hmax = maxf(hmax, p.global_position.y - from.y)
		if t > 0.2 and p.dash.state == CatDash.IDLE and p.dash.recover <= 0.0:
			bot.move = Vector2.ZERO
			if Vector2(p.velocity.x, p.velocity.z).length() < 0.15:
				break
	var d := p.global_position - from
	var slide := Vector2(p.global_position.x - touch.x, p.global_position.z - touch.z).length() if touch != Vector3.INF else 99.0
	return {"slide": slide, "miss": miss, "kind": p.dash.last_kind if p.dash.count > c0 else "none", "dist": Vector2(d.x, d.z).length(), "air": air, "iframes": ifr,
		"push_at": pushed_at, "h": hmax, "cost": s0 - p.stamina.value, "turn": rad_to_deg(wrapf(p.yaw - y0, -PI, PI)), "t": t,
		"fwd": -d.dot(Vector3(sin(y0), 0, cos(y0))), "side": d.dot(Vector3(cos(y0), 0, -sin(y0)))}


## dodge + stamina checks: `-- --preview --dashtest`
func _run_dashtest() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	_pad(120, 120, 50.0, "wood")
	var spot := Vector3(40.0, 50.02, 0.0)
	var ok := true
	bot.clear()
	bot.stamina = true
	p.yaw = PI / 2
	p.orb_yaw = PI / 2
	p.global_position = spot
	p.velocity = Vector3.ZERO
	await _ticks(60)
	print("-- dodges from standing (wood)")
	for c in [["dart (w)", Vector2(0, 1)], ["side (d)", Vector2(1, 0)], ["side (a)", Vector2(-1, 0)], ["whirl (s)", Vector2(0, -1)], ["backstep", Vector2.ZERO]]:
		p.stamina.value = CatStamina.MAX
		p.yaw = PI / 2
		p.orb_yaw = PI / 2
		await _ticks(30)
		var r := await _dodge(p, c[1])
		print("%-10s -> slid %.3f m after touch down, %.3f m off the traced spot" % [c[0], r.slide, r.miss])
		ok = ok and r.slide < 0.03 and r.miss >= 0.0 and r.miss < 0.05
		print("%-10s -> %-9s dist %.2f m (fwd %+.2f side %+.2f)  air %.2f s  peak %.2f m  iframes %.2f s (push at %.2f s)  cost %.0f  body turned %+.0f deg  done in %.2f s" % [c[0], r.kind, r.dist, r.fwd, r.side, r.air, r.h, r.iframes, r.push_at, r.cost, r.turn, r.t])
	# out of a gallop the dart carries the run
	p.global_position = spot + Vector3(-30, 0, 0)
	p.orb_yaw = -PI / 2
	p.stamina.value = CatStamina.MAX
	bot.move = Vector2(0, 1)
	bot.sprint = true
	await _ticks(120)
	var v0 := Vector2(p.velocity.x, p.velocity.z).length()
	bot.dash = true
	await get_tree().physics_frame
	bot.dash = false
	bot.sprint = false
	var vmax := 0.0
	for i in 40:
		await get_tree().physics_frame
		vmax = maxf(vmax, Vector2(p.velocity.x, p.velocity.z).length())
	print("gallop dart: %.1f m/s before, %.1f m/s peak in the dart (%s)" % [v0, vmax, p.dash.last_kind])
	bot.move = Vector2.ZERO
	await _ticks(120)
	# chaining: press again during the recovery -> buffered
	p.stamina.value = CatStamina.MAX
	var c0 := p.dash.count
	bot.move = Vector2(1, 0)
	bot.dash = true
	await get_tree().physics_frame
	bot.dash = false
	var pressed := false
	for i in 120:
		await get_tree().physics_frame
		if not pressed and p.dash.recover > 0.0:
			bot.dash = true
			pressed = true
		elif pressed:
			bot.dash = false
	print("chain: %d dodges from 2 presses (second pressed during recovery)" % (p.dash.count - c0))
	ok = ok and p.dash.count - c0 == 2
	bot.move = Vector2.ZERO
	await _ticks(120)
	# empty bar: no dodge
	p.stamina.value = 0.0
	p.stamina.winded = true
	c0 = p.dash.count
	bot.dash = true
	await _ticks(2)
	bot.dash = false
	await _ticks(40)
	print("empty bar dodge refused: %s" % str(p.dash.count == c0))
	ok = ok and p.dash.count == c0
	# regen
	p.stamina.value = 0.0
	var t := 0.0
	while p.stamina.value < CatStamina.MAX and t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("regen 0 -> full standing still: %.1f s" % t)
	# gallop drain + winded
	p.global_position = spot + Vector3(-30, 0, 0)
	p.orb_yaw = -PI / 2
	await _ticks(10)
	bot.move = Vector2(0, 1)
	bot.sprint = true
	t = 0.0
	var winded_at := -1.0
	var vw := 0.0
	while t < 12.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if winded_at < 0.0 and p.stamina.winded:
			winded_at = t
		if OS.has_environment("DASH_DBG") and int(t * 60) % 30 == 0:
			print("  t %.1f v %.1f st %.0f pos %s floor %s" % [t, Vector2(p.velocity.x, p.velocity.z).length(), p.stamina.value, p.global_position.snapped(Vector3.ONE * 0.1), p.is_on_floor()])
		if winded_at > 0.0 and t > winded_at + 1.0:
			vw = Vector2(p.velocity.x, p.velocity.z).length()
			break
		if absf(p.global_position.x) > 50.0:
			p.global_position.x = -signf(p.global_position.x) * 45.0
			p._phys_prev = p.global_position
	print("gallop from full: winded after %.1f s, 1 s later running %.1f m/s (trot is %.1f)" % [winded_at, vw, CatPlayer.TROT_SPEED])
	ok = ok and winded_at > 2.5 and winded_at < 6.0 and vw < CatPlayer.TROT_SPEED + 0.4
	bot.sprint = false
	bot.move = Vector2.ZERO
	await _ticks(60)
	# hop costs
	p.stamina.value = CatStamina.MAX
	await _ticks(10)
	bot.jump = true
	await _ticks(3)
	bot.jump = false
	var hm := 0.0
	var y0 := p.global_position.y
	for i in 100:
		await get_tree().physics_frame
		hm = maxf(hm, p.global_position.y - y0)
	print("hop: cost %.0f, height %.2f m" % [CatStamina.MAX - p.stamina.value - 0.0, hm])
	p.stamina.value = 0.0
	p.stamina.winded = true
	await _ticks(2)
	bot.jump = true
	await _ticks(3)
	bot.jump = false
	hm = 0.0
	for i in 100:
		await get_tree().physics_frame
		hm = maxf(hm, p.global_position.y - y0)
	print("hop with an empty bar: height %.2f m" % hm)
	print("DASHTEST ", "PASS" if ok else "FAIL")
	get_tree().quit()


## dodge showcase for the preview video: side camera on a dirt pad, real speed then slow-mo
func _run_dashshow() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	main.hud.visible = false
	_pad(120, 12, 50.0, "dirt", true)
	p.set_third_person(true)
	cam.current = true
	cam.fov = 40
	p.global_position = Vector3(30, 50.02, 0)
	p.velocity = Vector3.ZERO
	bot.clear()
	bot.stamina = true
	p.yaw = PI / 2
	p.orb_yaw = PI / 2
	await _ticks(30)
	# [title, sub, move, dash?, sprint?, seconds, timescale]
	var shots := [
		["dodge (alt / mouse4)", "wasd picks the way. the bar under the screen is stamina", Vector2.ZERO, false, false, 1.0, 1.0],
		["dart", "all four paws gather, the hind legs fire, flat and low, forepaws land first", Vector2(0, 1), true, false, 1.2, 1.0],
		["dart, slow-mo", "", Vector2(0, 1), true, false, 2.0, 0.3],
		["side leap", "the startled sideways spring: body stays square, head on the threat", Vector2(0, 0), false, false, 0.01, 1.0],
		["side leap", "the startled sideways spring: body stays square, head on the threat", Vector2(1, 0), true, false, 1.2, 1.0],
		["side leap, slow-mo", "", Vector2(-1, 0), true, false, 2.0, 0.3],
		["backstep", "no direction held: hops straight back, still facing forward", Vector2.ZERO, true, false, 1.2, 1.0],
		["whirl", "s / away from the body: pivots round on the forepaws, then darts", Vector2(0, -1), true, false, 1.4, 0.5],
		["chained", "a press during the landing is buffered, so dodges chain", Vector2(0, 1), true, false, 2.4, 1.0],
		["gallop until winded", "the gallop drains the bar in ~6 s, then the cat can only trot", Vector2(0, 1), false, true, 8.5, 1.0],
		["empty bar", "no stamina, no dodge (it flashes red)", Vector2(0, 1), true, false, 1.2, 1.0],
		["breather", "stops, gets its breath back", Vector2.ZERO, false, false, 3.6, 1.0],
	]
	var look := p.global_position
	for sh in shots:
		_say(sh[0], sh[1])
		Engine.time_scale = sh[6]
		bot.move = sh[2]
		bot.sprint = sh[4]
		if sh[0] != "empty bar" and sh[0] != "gallop until winded" and sh[0] != "breather":
			p.stamina.value = maxf(p.stamina.value, 60.0)
		if sh[0] in ["chained", "gallop until winded"]:
			# fresh run down the middle of the pad, heading -x
			p.global_position = Vector3(40, 50.02, 0)
			p.velocity = Vector3.ZERO
			p._phys_prev = p.global_position
			look = p.global_position
			p.yaw = PI / 2
			p.rotation.y = p.yaw
		if sh[0] in ["whirl", "chained", "gallop until winded", "dart", "dart, slow-mo"]:
			p.orb_yaw = p.yaw
		if sh[0] == "empty bar":
			p.stamina.value = 0.0
			p.stamina.winded = true
		var t := 0.0
		var presses := 0
		var turned := false
		while t < sh[5]:
			var want_press: bool = sh[3] and (presses == 0 or (sh[0] == "chained" and presses < 3 and p.dash.recover > 0.0))
			bot.dash = want_press and not bot.get("dash", false)
			if bot.dash:
				presses += 1
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			if sh[0] == "whirl" and p.dash.count > 0 and p.dash.state == CatDash.IDLE and not turned and t > 0.3:
				turned = true
			if p.dash.state == CatDash.AIR and sh[0] != "chained" and absf(float(sh[2].x)) > 0.5:
				bot.move = Vector2.ZERO   # let go of a/d once it's off the ground (else a side hop follows)
			if p.dash.state == CatDash.IDLE and p.dash.recover <= 0.0 and t > 0.25 and not sh[4] and sh[0] != "chained":
				bot.move = Vector2.ZERO
			if sh[0] == "chained" and presses >= 3 and p.dash.state == CatDash.IDLE and p.dash.recover <= 0.0:
				bot.move = Vector2.ZERO
			var pp := p.global_position
			if pp.x > 55.0 or pp.x < -55.0:
				p.global_position.x = 0.0
				p._phys_prev = p.global_position
				look.x = 0.0
				pp = p.global_position
			look = look.lerp(pp, 1.0 - exp(-12.0 * dt))
			look.y = pp.y
			look.z = lerpf(look.z, pp.z, 1.0 - exp(-6.0 * dt))
			var cy := maxf(50.0, pp.y - 0.05)
			cam.global_position = Vector3(look.x - 0.35, cy + 0.42, look.z + 1.9)
			cam.look_at(Vector3(look.x, cy + 0.1, look.z), Vector3.UP)
		bot.dash = false
		# turn round at the end of the pad
		if p.global_position.x > 45.0:
			p.orb_yaw = -PI / 2
		elif p.global_position.x < -45.0:
			p.orb_yaw = PI / 2
	Engine.time_scale = 1.0
	get_tree().quit()


## wall kick + wall clipping check: trot nose first into a wall, then run, hop and kick off it.
## prints how deep any part of the visible cat went past the wall face (KICK lines).
## --kicktest: headless numbers only. --kickshow: render (side camera, slow motion)
func _run_kickshow(test: bool) -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	main.hud.visible = false
	var pad := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30, 1, 12)
	cs.shape = bs
	pad.add_child(cs)
	main.add_child(pad)
	pad.global_position = Vector3(40, 49.5, 0)
	LowPoly.part(pad, LowPoly.box(), Color(0.5, 0.47, 0.42), Vector3.ZERO, Vector3(30, 1, 12))
	for k in 30:
		LowPoly.part(pad, LowPoly.box(), Color(0.44, 0.41, 0.37), Vector3(-15 + k, 0.501, 0), Vector3(0.03, 0.002, 12))
	# the wall: face at x = 36, normal +x
	var wall_x := 36.0
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(0.3, 2.2, 6)
	wcs.shape = wbs
	wall.add_child(wcs)
	main.add_child(wall)
	wall.global_position = Vector3(wall_x - 0.15, 51.1, 0)
	LowPoly.part(wall, LowPoly.box(), Color(0.78, 0.74, 0.66), Vector3.ZERO, Vector3(0.3, 2.2, 6))
	for k in 11:
		LowPoly.part(wall, LowPoly.box(), Color(0.7, 0.66, 0.58), Vector3(0.151, -1.1 + k * 0.2, 0), Vector3(0.002, 0.012, 6))
	p.set_third_person(true)
	if not test:
		cam.current = true
		cam.fov = 40
	var shots := [
		# name, caption, start x, bot keys, seconds, kick when touching
		["trot into a wall", "nose first at 3.2 m/s and keep pushing", 39.2, {"move": Vector2(0, 1)}, 1.6, null],
		["wall kick", "hop at the wall, rear up on it, hind legs kick off where you look", 38.6, {"move": Vector2(0, 1), "sprint": false}, 1.5, -PI / 2],
		["wall kick, aimed off to the side", "look 45 deg off the wall: the kick goes that way", 39.6, {"move": Vector2(0, 1), "canter": true}, 1.5, -PI * 0.75],
	]
	Engine.time_scale = 1.0 if test else 0.3
	var report := {}
	for sh in shots:
		_say(sh[0], sh[1])
		p.global_position = Vector3(sh[2], 50.02, 0.0)
		p.velocity = Vector3.ZERO
		bot.clear()
		bot.yaw = PI / 2
		p.orb_yaw = PI / 2
		p.yaw = PI / 2
		var t := 0.0
		while t < 0.4:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		for k in sh[3]:
			bot[k] = sh[3][k]
		t = 0.0
		var deep := 0.0
		var upright := 0.0
		var hopped := false
		var kicked := false
		var events := []
		while t < sh[4]:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			bot.jump = false
			if sh[5] != null:
				var gap := p.global_position.x - wall_x
				if not hopped and gap < 0.75 and p.is_on_floor():
					bot.jump = true
					hopped = true
				elif hopped and not kicked and not p.is_on_floor() and p.wall_time < 0.05:
					# look where the kick should go (the bot's yaw is its camera) and kick
					bot.jump = true
					bot.yaw = sh[5]
					kicked = true
					events.append("kick at t=%.2f vy=%.2f" % [t, p.velocity.y])
				elif kicked:
					if p.kick_plant_t <= 0.0 and events.size() == 1:
						var hv := Vector2(p.velocity.x, p.velocity.z)
						events.append("launch dir=(%.2f, %.2f) speed=%.2f vy=%.2f" % [hv.normalized().x, hv.normalized().y, hv.length(), p.velocity.y])
					bot.move = Vector2.ZERO
					bot.yaw = p.yaw
			# measure what gets drawn: the rig poses itself (tail, legs) in _process, so wait for the draw
			if test:
				await RenderingServer.frame_pre_draw
			# deepest point of the visible cat past the wall face (only parts that sit above
			# the floor near the wall count)
			for mi in p.rig.find_children("*", "MeshInstance3D", true, false):
				var m3 := mi as MeshInstance3D
				if not m3.is_visible_in_tree() or m3.mesh == null:
					continue
				var ab := m3.get_aabb()
				for c in 8:
					var wp: Vector3 = m3.global_transform * ab.get_endpoint(c)
					if wp.y > 50.0 and wp.y < 52.0 and absf(wp.z) < 2.5:
						if OS.get_environment("KICK_DBG") != "" and wall_x - wp.x > 0.03:
							print("  deep %.0fmm t=%.2f %s plant=%.2f wk=%.2f clip=%.3f px=%.3f py=%.3f floor=%s wf=%.2f" % [(wall_x - wp.x) * 1000.0, t, str(p.rig.get_path_to(m3)), p.kick_plant_t, p.w_kick, p._clip_off, p.global_position.x, p.global_position.y, p.is_on_floor(), p.w_face])
						deep = maxf(deep, wall_x - wp.x)
			if p.kick_plant_t > 0.0:
				# spine angle above horizontal during the plant (chest relative to the hips)
				var sp: Vector3 = p.rig.chest.global_position - p.rig.pelvis.global_position
				upright = maxf(upright, rad_to_deg(atan2(sp.y, Vector2(sp.x, sp.z).length())))
			if not test:
				var pp := p.global_position
				cam.global_position = Vector3(wall_x + 0.9, 50.35, 1.7)
				cam.look_at(Vector3(wall_x + 0.45, maxf(pp.y, 50.0) + 0.12, 0), Vector3.UP)
		report[sh[0]] = {"deepest_mm": snappedf(deep * 1000.0, 0.1), "spine_deg": snappedf(upright, 1.0), "events": events, "end_x": snappedf(p.global_position.x, 0.01)}
		print("KICK ", sh[0], " ", JSON.stringify(report[sh[0]]))
	Engine.time_scale = 1.0
	get_tree().quit()


# speed over time for a fixed script (trot, gallop, let go, walk), one csv line per tick. for the momentum chart
func _run_movecurve() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	_pad(300, 300, 50.0, "wood")
	p.global_position = Vector3(-120.0, 50.02, 0.0)
	p.velocity = Vector3.ZERO
	bot.clear()
	bot.yaw = -PI / 2
	bot.move = Vector2.ZERO
	await _ticks(20)
	var seq := [[{"move": Vector2(0, 1)}, 1.5], [{"move": Vector2(0, 1), "sprint": true}, 3.0], [{"move": Vector2(0, 1)}, 1.5], [{"move": Vector2.ZERO}, 1.5], [{"move": Vector2(0, 0.45)}, 1.5], [{"move": Vector2.ZERO}, 1.0]]
	var t := 0.0
	for st in seq:
		for k in ["move", "sprint"]:
			bot.erase(k)
		for k in st[0]:
			bot[k] = st[0][k]
		for i in int(st[1] * 144):
			await get_tree().physics_frame
			t += 1.0 / 144.0
			if i % 4 == 0:
				print("CURVE %.3f,%.3f" % [t, Vector2(p.velocity.x, p.velocity.z).length()])
	get_tree().quit()


# momentum + gamepad: speed builds and bleeds with weight, analog tilt picks walk/trot, deadzones.
# headless: godot --headless --path . -- --preview --movetest  (prints MOVETEST PASS)
func _run_movetest() -> void:
	var p: CatPlayer = main.player
	var bot: Dictionary = p.bot
	_pad(200, 200, 50.0, "wood")
	var spot := Vector3(-60.0, 50.02, 0.0)
	var ok := true
	var hs := func() -> float: return Vector2(p.velocity.x, p.velocity.z).length()
	var reset := func() -> void:
		bot.clear()
		bot.move = Vector2.ZERO
		bot.yaw = -PI / 2     # run along +x
		p.global_position = spot
		p.velocity = Vector3.ZERO
	# 1. ramp up: time to reach 90% of each gait from a stand
	for c in [["walk (half tilt)", {"move": Vector2(0, CatPlayer.WALK_TILT)}, CatPlayer.speed_for_tilt(CatPlayer.WALK_TILT)],
			["trot", {"move": Vector2(0, 1)}, CatPlayer.TROT_SPEED],
			["canter", {"move": Vector2(0, 1), "canter": true}, CatPlayer.CANTER_SPEED],
			["gallop", {"move": Vector2(0, 1), "sprint": true}, CatPlayer.SPRINT_SPEED]]:
		reset.call()
		await _ticks(20)
		for k in c[1]:
			bot[k] = c[1][k]
		var t90 := -1.0
		var top := 0.0
		for i in 720:
			await get_tree().physics_frame
			var v: float = hs.call()
			top = maxf(top, v)
			if t90 < 0.0 and v >= c[2] * 0.9:
				t90 = (i + 1) / 144.0
		print("%-17s target %.2f m/s  reached 90%% in %.2f s  top %.2f" % [c[0], c[2], t90, top])
		ok = ok and t90 > 0.0 and absf(top - c[2]) < 0.25
		if c[0] == "trot":
			ok = ok and t90 > 0.2 and t90 < 0.8
		if c[0] == "gallop":
			ok = ok and t90 > 1.2 and t90 < 4.0
		# 2. let go: coast to a stop
		bot.move = Vector2.ZERO
		bot.erase("canter")
		bot.erase("sprint")
		var x0 := p.global_position
		var ts := -1.0
		for i in 720:
			await get_tree().physics_frame
			if hs.call() < 0.05:
				ts = (i + 1) / 144.0
				break
		var dist := Vector2(p.global_position.x - x0.x, p.global_position.z - x0.z).length()
		print("%-17s let go: stops in %.2f s over %.2f m" % ["", ts, dist])
		ok = ok and ts > 0.1
		if c[0] == "gallop":
			ok = ok and ts > 0.8 and ts < 2.5 and dist > 3.0
	# 3. analog curve: tilt -> speed
	var line := "tilt -> speed:"
	for m in [0.1, 0.25, 0.45, 0.6, 0.75, 1.0]:
		reset.call()
		await _ticks(10)
		bot.move = Vector2(0, m)
		await _ticks(200)
		line += "  %.2f=%.2f" % [m, hs.call()]
	print(line)
	ok = ok and CatPlayer.speed_for_tilt(CatPlayer.WALK_TILT) < 1.05 and CatPlayer.speed_for_tilt(1.0) == CatPlayer.TROT_SPEED
	# 4. release the gallop button but keep running: settles to a trot within ~1.3 s
	reset.call()
	bot.move = Vector2(0, 1)
	bot.sprint = true
	await _ticks(500)
	bot.sprint = false
	var tdown := -1.0
	for i in 400:
		await get_tree().physics_frame
		if hs.call() < CatPlayer.TROT_SPEED + 0.3:
			tdown = (i + 1) / 144.0
			break
	print("gallop -> trot (let go of run): %.2f s" % tdown)
	ok = ok and tdown > 0.3 and tdown < 1.6
	# 5. orbit controls: reverse the stick at a gallop = brake (skid) then come round, wide arcs when turning
	reset.call()
	bot.erase("yaw")
	p.yaw = -PI / 2
	p.orb_yaw = -PI / 2
	bot.move = Vector2(0, 1)
	bot.sprint = true
	await _ticks(500)
	var y0 := p.yaw
	var d0 := Vector2(p.velocity.x, p.velocity.z).normalized()
	bot.move = Vector2(0, -1)    # stick straight back (camera stays)
	bot.sprint = false
	var t_slow := -1.0
	var maxslip := 0.0
	for i in 400:
		await get_tree().physics_frame
		maxslip = maxf(maxslip, p.slip)
		if t_slow < 0.0 and Vector2(p.velocity.x, p.velocity.z).dot(d0) < 0.5:
			t_slow = (i + 1) / 144.0
	print("gallop, stick reversed: forward run killed after %.2f s, now %.2f m/s, max slip %.2f, body turned %.0f deg" % [t_slow, hs.call(), maxslip, rad_to_deg(absf(wrapf(p.yaw - y0, -PI, PI)))])
	ok = ok and t_slow > 0.3 and t_slow < 2.0
	reset.call()
	bot.erase("yaw")
	p.yaw = -PI / 2
	p.orb_yaw = -PI / 2
	bot.move = Vector2(0, 1)
	bot.sprint = true
	await _ticks(500)
	bot.move = Vector2(1, 0)     # hard right at a gallop
	var tq := -1.0
	var y1 := p.yaw
	for i in 300:
		await get_tree().physics_frame
		if tq < 0.0 and absf(wrapf(p.yaw - y1, -PI, PI)) > PI / 2 - 0.1:
			tq = (i + 1) / 144.0
	print("gallop, hard right: body turned 90 deg in %.2f s (standing: %.2f s)" % [tq, (PI / 2) / CatPlayer.TURN_RATE_SLOW])
	ok = ok and tq > 0.3
	# 6. gamepad maths
	var z := CatPad.shape(Vector2(0.1, 0.05), CatPad.MOVE_DEADZONE)
	var e := CatPad.shape(Vector2(0.0, 0.2), CatPad.MOVE_DEADZONE)
	var f := CatPad.shape(Vector2(0.0, 0.97), CatPad.MOVE_DEADZONE)
	print("pad deadzone: rest %s  just past %.3f  full %.2f" % [z, e.length(), f.length()])
	ok = ok and z == Vector2.ZERO and e.length() < 0.06 and is_equal_approx(f.length(), 1.0)
	var mg := CatPad.merge({"move": Vector2(0, 1), "canter": true, "sprint": false, "jump": false}, {"move": Vector2(0.1, 0), "canter": false, "sprint": false, "jump": true})
	ok = ok and mg.move == Vector2(0, 1) and mg.canter and mg.jump
	# 7. a (virtual) pad driving the real input path: half tilt walks, full tilt trots, L3 runs, right stick turns the camera
	CatPad.sim = {"axes": {}, "buttons": {}}
	if CatPad.connected():
		reset.call()
		bot.clear()          # empty bot = real input
		p.orb_yaw = -PI / 2
		p.yaw = -PI / 2
		var axis := func(a: JoyAxis, v: float) -> void:
			CatPad.sim.axes[a] = v
		var button := func(b: JoyButton, down: bool) -> void:
			CatPad.sim.buttons[b] = down
		# 7a. a device whose "right stick y" is parked at -1 (throttle, wheel pedal, unmapped pad) used to
		# read as the stick held up = camera stuck looking up. it must stay ignored until it centres once
		CatPad.rearm()
		p.pitch = 0.0
		axis.call(JOY_AXIS_RIGHT_Y, -1.0)
		for i in 30:
			await get_tree().process_frame
		var stuck_pitch := p.pitch
		axis.call(JOY_AXIS_RIGHT_Y, 0.0)
		await get_tree().process_frame
		axis.call(JOY_AXIS_RIGHT_Y, -1.0)    # now a real push up works
		for i in 10:
			await get_tree().process_frame
		var real_pitch := p.pitch
		axis.call(JOY_AXIS_RIGHT_Y, 0.0)
		p.pitch = 0.0
		print("pad: parked axis 30 frames -> pitch %.3f, after centring a real push -> %.3f" % [stuck_pitch, real_pitch])
		ok = ok and absf(stuck_pitch) < 0.001 and real_pitch > 0.05
		await _ticks(2)    # every axis seen at rest = armed
		axis.call(JOY_AXIS_LEFT_Y, -0.55)    # a bit over half forward
		await _ticks(300)
		var v_half: float = hs.call()
		axis.call(JOY_AXIS_LEFT_Y, -1.0)
		await _ticks(300)
		var v_full: float = hs.call()
		button.call(JOY_BUTTON_LEFT_STICK, true)
		await _ticks(2)
		button.call(JOY_BUTTON_LEFT_STICK, false)
		await _ticks(300)
		var v_run: float = hs.call()
		p.stamina.value = CatStamina.MAX    # the gallop only lasts ~3 s on a full bar (souls stamina)
		button.call(JOY_BUTTON_LEFT_STICK, true)
		await _ticks(2)
		button.call(JOY_BUTTON_LEFT_STICK, false)
		await _ticks(380)
		var v_gal: float = hs.call()
		axis.call(JOY_AXIS_LEFT_Y, 0.0)
		await _ticks(500)
		var oy := p.orb_yaw
		axis.call(JOY_AXIS_RIGHT_X, 1.0)
		for i in 30:
			await get_tree().process_frame
		axis.call(JOY_AXIS_RIGHT_X, 0.0)
		var turned := p.orb_yaw - oy    # no wrap: on a slow renderer 30 frames can spin past a full turn
		axis.call(JOY_AXIS_TRIGGER_LEFT, 1.0)
		await _ticks(2)
		var lt: bool = p._read_input().paw_l
		axis.call(JOY_AXIS_TRIGGER_LEFT, 0.0)
		print("pad: tilt 0.55 -> %.2f m/s, full -> %.2f, L3 -> %.2f, L3 again -> %.2f, right stick 30 frames -> %.2f rad, LT paw_l %s" % [v_half, v_full, v_run, v_gal, turned, lt])
		ok = ok and v_half > 0.6 and v_half < 1.6 and absf(v_full - CatPlayer.TROT_SPEED) < 0.2 and absf(v_run - CatPlayer.CANTER_SPEED) < 0.3 and v_gal > 9.0 and turned < -0.05 and lt
		CatPad.sim = {}
	else:
		print("pad: couldn't fake a pad here, skipped")
	print("MOVETEST %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
