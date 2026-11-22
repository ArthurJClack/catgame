extends SceneTree
## clip of forest hunting (hunt_prey.gd): mice foraging round their holes, a loud cat sending
## them down the holes, one peeking back out, then a proper stalk (crouch, freeze when it sits up,
## pounce) on a mouse and a rat, carried off in the mouth. the cat is driven like a player would.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --write-movie out/hunt.avi --fixed-fps 30 --script res://tests/hunt_show.gd

var p: CatPlayer
var bot := {"move": Vector2.ZERO, "yaw": 0.0, "pitch": -0.2}
var cam: Camera3D
var label: Label
var cam_focus := Vector3.ZERO
var cam_off := Vector3(0.9, 0.5, 1.4)
var cam_follow: Node3D = null
var _cp := Vector3.INF


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	var e := 0.0
	while e < sec:
		await process_frame
		e += 1.0 / 30.0
		_cam_update()


func _cam_update() -> void:
	var f := cam_focus
	if is_instance_valid(cam_follow):
		f = cam_follow.global_position
	var want := f + cam_off
	want.y = maxf(want.y, ForestLevel.height(want.x, want.z) + 0.12)
	_cp = want if _cp == Vector3.INF else _cp.lerp(want, 0.08)
	cam.global_position = _cp
	cam.look_at(f + Vector3.UP * 0.06, Vector3.UP)


func _say(t: String) -> void:
	label.text = t


func _face(at: Vector3) -> void:
	var d := at - p.global_position
	bot.yaw = atan2(-d.x, -d.z)


func _aim(at: Vector3) -> void:
	for k in 4:
		var dd := at + Vector3.UP * 0.02 - p._aim_pos()
		var want := atan2(dd.y, Vector2(dd.x, dd.z).length())
		var have := asin(clampf(p._look_dir().y, -1.0, 1.0))
		bot.pitch += want - have
		await _wait(0.07)


func _place(at: Vector3, look: Vector3) -> void:
	at.y = ForestLevel.height(at.x, at.z) + 0.03
	p.global_position = at
	p._phys_prev = at
	p._phys_curr = at
	p.velocity = Vector3.ZERO
	_face(look)
	p.yaw = bot.yaw
	p.orb_yaw = bot.yaw


func _calm(list: Array) -> void:
	for h in list:
		h.aware = 0.0
		h.threat = Vector3.INF
		h._react = -1.0
		h.global_position = h._on_ground(h.home)
		h._go(HuntPrey.FORAGE, 4.0)
		h._nibble = true


## creep crouched toward prey, freezing whenever it sits up to look, until `stop` m off
func _stalk(q: HuntPrey, stop: float) -> void:
	bot.crouch = true
	var t := 0.0
	while t < 14.0:
		var d := q.global_position - p.global_position
		d.y = 0
		if d.length() < stop:
			break
		_face(q.global_position)
		var look_up := q.state == HuntPrey.ALERT
		bot.move = Vector2.ZERO if look_up else Vector2(0, 1)
		_say("crouch = creep low and quiet.%s" % ("   it sat up: FREEZE" if look_up else ""))
		await _wait(1.0 / 30.0)
		t += 1.0 / 30.0
	bot.move = Vector2.ZERO


func _pounce(q: HuntPrey) -> void:
	_face(q.global_position)
	await _wait(0.25)
	await _aim(q.global_position)
	_say("hold space to wind up, let go: pounce")
	bot.pounce = true
	await _wait(0.65)
	bot.pounce = false
	await _wait(1.0)


func _run() -> void:
	Engine.set_meta("title_done", true)
	GameSettings.s("hints", false)
	change_scene_to_file("res://forest.tscn")
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.get("player") == null) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	var main: Node = current_scene
	main.atmos.hour = 9.5
	main.atmos.day_speed = 0.0
	main.atmos.apply_time()
	main.hud.visible = false
	p = main.player
	p.bot = bot
	p.set_view(1)
	cam = Camera3D.new()
	cam.fov = 55
	cam.near = 0.01
	main.add_child(cam)
	cam.current = true
	var ui := CanvasLayer.new()
	main.add_child(ui)
	label = Label.new()
	label.position = Vector2(40, 30)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	ui.add_child(label)
	var mice := HuntPrey.all.filter(func(h): return h.kind == "mouse")
	var rats := HuntPrey.all.filter(func(h): return h.kind == "rat")
	var m: HuntPrey = mice[0]
	var m2: HuntPrey = mice[1]
	var r: HuntPrey = rats[0]
	var colony := [m, m2, r, rats[1]]
	_place(Vector3(2.0, 0, 30.0), m.global_position)
	_calm(HuntPrey.all)

	# 1: foraging
	_say("mice + rats forage round their den holes")
	cam_follow = null
	cam_focus = m.home
	cam_off = Vector3(0.55, 0.28, 0.75)
	_cp = Vector3.INF
	await _wait(4.0)
	cam_focus = r.home
	cam_off = Vector3(-0.7, 0.35, 0.9)
	_say("rats are bigger, bolder, slower to spook")
	await _wait(3.5)

	# 2: loud cat: down the holes
	_calm(colony)
	_place(m.home + Vector3(0.5, 0, 5.0), m.home)
	cam_follow = null
	cam_focus = m.home + Vector3(0, 0, 0.8)
	cam_off = Vector3(2.2, 1.0, 1.2)
	_cp = Vector3.INF
	await _wait(0.8)
	_say("run at them and they hear you coming...")
	bot.move = Vector2(0, 1)
	bot.canter = true
	var tt := 0.0
	while tt < 2.6:
		if p.global_position.distance_to(m.home) < 0.8:
			bot.move = Vector2.ZERO
		await _wait(1.0 / 30.0)
		tt += 1.0 / 30.0
	bot.move = Vector2.ZERO
	bot.canter = false
	_say("...straight down the nearest hole")
	await _wait(2.0)

	# 3: peek
	_place(m.home + Vector3(3.5, 0, 3.5), m.home)
	bot.crouch = true
	await _wait(0.3)
	var hole: Vector3 = m.global_position
	cam_focus = hole
	cam_off = Vector3(0.45, 0.2, 0.55)
	_cp = Vector3.INF
	m.state_t = 0.4
	_say("wait quietly and it peeks out first")
	await _wait(4.5)
	bot.crouch = false

	# 4: the stalk + pounce, mouse
	_calm(colony)
	m.state_t = 9.0
	_place(m.home + Vector3(2.6, 0, 2.4), m.home)
	cam_follow = p
	cam_off = Vector3(1.1, 0.55, 0.3)
	_cp = Vector3.INF
	await _wait(0.5)
	await _stalk(m, 1.4)
	await _pounce(m)
	_say("caught a mouse!" if p.carried == m else "missed! (it happens)")
	cam_follow = p
	cam_off = Vector3(0.5, 0.25, -0.6)
	await _wait(2.4)
	if p.carried:
		p._drop_carried()
	await _wait(0.4)

	# 5: rat, with cat sense: crouch + keep still and nearby prey shimmer
	_calm(colony)
	r.state_t = 9.0
	_place(r.home + Vector3(-2.4, 0, 2.2), r.home)
	bot.crouch = true
	cam_follow = null
	cam_focus = r.home + Vector3(-1.0, 0, 1.0)
	cam_off = Vector3(-1.2, 0.8, 1.6)
	_cp = Vector3.INF
	_say("crouch + keep still: cat sense picks them out")
	await _wait(2.8)
	cam_follow = p
	cam_off = Vector3(-1.0, 0.55, 0.5)
	await _stalk(r, 1.4)
	await _pounce(r)
	_say("caught a rat!" if p.carried == r else "missed! (it happens)")
	cam_off = Vector3(-0.5, 0.25, -0.6)
	bot.crouch = false
	bot.move = Vector2(0, 1)
	await _wait(1.5)
	bot.move = Vector2.ZERO
	await _wait(1.0)
	print("HUNTSHOW done, carried: ", p.carried)
	quit()
