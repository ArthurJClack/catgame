extends SceneTree
## cat vision (hold q / LB) + the jump bar, with real key presses on the farm:
## q lights up puzzles / climbables / loose props with an overlay and puts it all back on release,
## holding space shows the jump bar (hop height, then leap distance) and hides it on let go,
## an old settings file with q on another action doesn't get a double bind.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/vision_test.gd [-- out/dir saves a screenshot]

var bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float, until: Callable = func(): return false) -> bool:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		if until.call():
			return true
	return until.call()


## n frames of both kinds: parsed input only lands on a process frame, and at xvfb frame rates
## several physics ticks fit in one of those
func _game(n: int) -> void:
	for i in n:
		await process_frame
		await physics_frame


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _player() -> CatPlayer:
	var p = current_scene.get("player") if current_scene else null
	return p if p is CatPlayer and p.is_inside_tree() else null


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _mouse(b: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = Vector2(800, 450)
	Input.parse_input_event(e)


func _run() -> void:
	GameSettings.path = "user://vision_test_settings.cfg"
	GameSettings.reset_defaults()
	CatKeys.reset()
	Tutorial.force = false
	GameSettings.s("hints", false)
	Engine.set_meta("title_done", true)
	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _player() != null), "farm loads")
	var p := _player()
	await _game(30)

	_ok(CatKeys.describe("vision") == "q", "vision is on q (%s)" % CatKeys.describe("vision"))
	_ok(p.vision != null and p.vision.level == 0.0 and p.vision.lit.is_empty(), "nothing lit to start")

	# --- hold q
	_key(KEY_Q, true)
	_ok(await _wait(8.0, func(): return p.vision.level >= 0.99), "q brings cat vision up")
	await _game(4)
	var v: CatVision = p.vision
	print("     lit: puzzle %d  climb %d  prop %d  prey %d  cat %d" % [v.count("puzzle"), v.count("climb"), v.count("prop"), v.count("prey"), v.count("cat")])
	_ok(v.count("puzzle") > 0, "a puzzle glows")
	_ok(v.count("climb") > 0, "something to climb glows")
	var a_mesh: MeshInstance3D = v.lit.keys()[0] if not v.lit.is_empty() else null
	_ok(a_mesh != null and a_mesh.material_overlay is ShaderMaterial, "lit meshes carry the glow overlay")
	var mine := 0
	for m in v.lit:
		if p.is_ancestor_of(m):
			mine += 1
	_ok(mine == 0, "the cat doesn't light itself")
	_ok(v._screen != null and v._screen.visible, "the screen dims")
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			shots = a
	if shots != "":
		p.yaw += 2.4    # face the yard
		await _wait(1.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots + "/cat_vision.png")

	_key(KEY_Q, false)
	_ok(await _wait(6.0, func(): return v.lit.is_empty()), "letting go puts it all back")
	_ok(a_mesh == null or a_mesh.material_overlay == null, "overlay restored")
	_ok(not v._screen.visible, "screen back to normal")

	# --- jump bar
	await _game(10)
	var hud: SoulsHud = p.souls_hud
	_ok(not hud.jump_shown(), "no jump bar at rest")
	_key(KEY_SPACE, true)
	_ok(await _wait(3.0, func(): return hud.jump_shown()), "holding space shows the jump bar")
	var m0: Dictionary = p.jump_meter()
	print("     first: %s" % m0.text)
	_ok(m0.on and str(m0.text).begins_with("hop"), "it starts as a hop")
	_ok(await _wait(4.0, func(): return p.jump_meter().get("leap", false)), "held long it turns into a leap")
	var m1: Dictionary = p.jump_meter()
	print("     then: %s  fill %.2f" % [m1.text, m1.fill])
	_ok(str(m1.text).begins_with("leap") and m1.fill > 0.0, "leap shows a distance")
	_key(KEY_SPACE, false)
	_ok(await _wait(4.0, func(): return not hud.jump_shown()), "letting go hides it")

	# --- an old save with q on meow: no double bind
	CatKeys.from_dict({"_v": CatKeys.VERSION, "meow": [{"k": KEY_Q}]})
	_ok(CatKeys.describe("meow") == "q" and CatKeys.describe("vision") == "unbound", "q already used = vision starts unbound (%s)" % CatKeys.describe("vision"))
	CatKeys.reset()

	print("vision_test: %s" % ("PASS" if bad == 0 else "%d FAIL" % bad))
	quit(1 if bad > 0 else 0)
