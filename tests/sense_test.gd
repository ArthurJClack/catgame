extends SceneTree
## cat sense (cat_sense.gd) + the puzzle tally page: on the farm, crouching (real ctrl press) and
## keeping still makes unsolved puzzles nearby shimmer; walking kills it; a solved puzzle stops
## showing; the pause menu lists x / 7 puzzles. `-- out/dir` saves a screenshot of the motes.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/sense_test.gd

var bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _game(n: int) -> void:
	for i in n:
		await process_frame
		await physics_frame


func _player() -> CatPlayer:
	var p = current_scene.get("player") if current_scene else null
	return p if p is CatPlayer and p.is_inside_tree() else null


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _run() -> void:
	var shots := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	Engine.set_meta("title_done", true)
	GameSettings.s("hints", false)
	Puzzles.solved = {}
	change_scene_to_file("res://main.tscn")
	var t0 := Time.get_ticks_msec()
	while _player() == null and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	var p := _player()
	_ok(p != null, "farm loads")
	await _game(20)
	var z: Puzzles = current_scene.get_node_or_null("Puzzles")
	_ok(z != null and z.sense != null, "farm puzzles have a cat sense")
	var s := z.sense
	_ok(s.points.size() == 5, "5 farm puzzle points (%d)" % s.points.size())
	# stand on the patio, a step out from the doormat, facing it
	var at := Vector3(2.3, 0.05, 6.2)
	p.global_position = at
	p._phys_curr = at
	p.velocity = Vector3.ZERO
	p.yaw = 0.0
	p.orb_yaw = 0.0
	p.pitch = -0.25
	await _game(30)
	_ok(s.level == 0.0, "standing up: no sense")
	_key(KEY_CTRL, true)
	var lvl := 0.0
	for i in 160:
		await process_frame
		await physics_frame
		lvl = s.level
		if lvl >= 1.0:
			break
	_ok(lvl >= 0.99, "crouched + still: the sense comes up (%.2f)" % lvl)
	var open := s.open_points()
	_ok("gift" in open, "the doormat is in range (%s)" % [open])
	_ok(s._vis.has("gift") and s._vis["gift"].size() == CatSense.MOTES, "motes over the doormat")
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots + "/cat_sense.png")
	Puzzles.solved["gift"] = 1
	await _game(4)
	_ok(not s._vis.has("gift"), "solved: the doormat stops showing")
	Puzzles.solved.erase("gift")
	_key(KEY_W, true)
	await _game(40)
	_key(KEY_W, false)
	_ok(s.level < 0.2, "moving: the sense fades (%.2f)" % s.level)
	_key(KEY_CTRL, false)
	await _game(5)

	Puzzles.solved = {"gift": 1, "herd": 1}
	var menu = root.get_node("GameMenu")
	menu.open_menu()
	await _game(3)
	var found := false
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text == "cat puzzles (2 / 7)":
			found = true
			(b as Button).pressed.emit()
	await _game(3)
	_ok(found, "pause menu: cat puzzles (2 / 7)")
	_ok(menu.page == "puzzles", "the puzzle page opens")
	var names := []
	for l in menu.find_children("*", "Label", true, false):
		names.append((l as Label).text)
	_ok("herd the chicks" in names and "???" in names and "pier 9" in names, "solved names + ??? + where")
	menu.close_menu()
	Puzzles.solved = {}
	print("sense_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
