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
	if "--camtest" in args:
		cat.visible = false
		_run_camtest()
		return
	if "--swattest" in args:
		cat.visible = false
		_run_swattest()
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
	_say("chimney", "wall kick back and forth, 3 kicks per jump")
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
	bot.claw = true
	await get_tree().physics_frame
	print("claw rb: ", p.claw_rb, " static: ", p.claw_static)
	for i in 60:
		bot.yaw = -0.8 * i / 60.0
		await get_tree().physics_frame
	if p.claw_rb:
		print("dragged to: ", p.claw_rb.global_position.snapped(Vector3.ONE * 0.01))
	bot.claw = false
	await get_tree().physics_frame
	# claw at the floor and drag marks
	p.global_position = Vector3(-1.0, 0.02, 1.2)
	bot.yaw = 0.0
	bot.pitch = -0.9
	for i in 20:
		await get_tree().physics_frame
	bot.claw = true
	await get_tree().physics_frame
	print("floor claw static: ", p.claw_static)
	for i in 60:
		bot.yaw = 0.6 * i / 60.0
		await get_tree().physics_frame
	print("marks: ", p._marks.size())
	bot.claw = false
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
