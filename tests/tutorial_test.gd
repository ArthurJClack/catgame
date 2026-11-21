extends SceneTree
## tutorial hint cards (tutorial.gd): a fresh save on the farm gets the cards, the old help text
## is hidden, cards show the bound keys (and follow a rebind), each one ticks off when you do the
## thing (real key presses for move / run / hop / swat / meow, the counters for look / leap /
## climb / pounce), progress is in the save, it ends after "explore", restart works, the setting
## turns it off. `-- out/dir` saves a screenshot of a card.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/tutorial_test.gd

const DIR := "user://tuttest/"
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


func _game(sec: float, until: Callable = func(): return false) -> bool:
	for i in int(sec * Engine.physics_ticks_per_second):
		await physics_frame
		if until.call():
			return true
	return until.call()


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _player() -> CatPlayer:
	var p = current_scene.get("player") if current_scene else null
	return p if p is CatPlayer and p.is_inside_tree() else null


func _tut() -> Tutorial:
	var t := get_nodes_in_group("tutorial")
	return t[0] if t.size() > 0 and is_instance_valid(t[0]) and not t[0].is_queued_for_deletion() else null


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


func _on(step: String) -> bool:
	return await _game(4.0, func(): return _tut() != null and _tut().id() == step)


func _run() -> void:
	var shots := ""
	if OS.get_cmdline_user_args().size() > 0:
		shots = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var save = root.get_node("Save")
	save.dir = DIR
	save.enabled = true
	save.new_game(0)
	GameSettings.reset_defaults()
	Tutorial.force = true
	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _player() != null and _tut() != null), "fresh save: tutorial starts on the farm")
	var p := _player()
	var t := _tut()
	_ok(not current_scene.help_label.visible, "the wall of help text is hidden")
	_ok(t.id() == "move" and "w" in t._label.text and "[b]" in t._label.text, "first card: move, shows the keys")
	await _wait(1.0)
	if shots != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots + "/tutorial_card.png")

	_key(KEY_W, true)
	await _game(1.5)
	_key(KEY_W, false)
	_ok(await _on("look"), "walking ticks off move")
	_ok(int(save.data.tutorial.get("step", -1)) == 1, "progress is in the save")
	for i in 20:
		p.orb_yaw += 0.12
		await physics_frame
	_ok(await _on("sense"), "looking around ticks off look")
	var z = current_scene.get_node_or_null("Puzzles")
	_ok(z != null and z.sense != null, "farm has the cat sense")
	_key(KEY_CTRL, true)      # crouch + keep still
	_ok(await _on("hop"), "sensing ticks off sense")
	_key(KEY_CTRL, false)
	var yard := Vector3(6.0, 0.05, 10.0)   # out in the yard, far from the kitchen
	p.global_position = yard
	p._phys_curr = yard
	p.velocity = Vector3.ZERO
	await _game(0.8)
	_key(KEY_SPACE, true)
	await _game(0.1)
	_key(KEY_SPACE, false)
	_ok(await _on("pounce"), "a hop ticks off hop")
	# the leap card waits for the kitchen (out on the patio it's hidden)
	await _game(0.5)
	_ok(_tut()._card.modulate.a == 0.0 and _tut()._t == 0.0, "leap card waits for its moment")
	var at := Vector3(2.0, 0.05, -1.5)    # in the kitchen, a couple of metres from the counters
	p.global_position = at
	p._phys_curr = at
	p.velocity = Vector3.ZERO
	_ok(await _game(1.0, func(): return _tut()._t > 0.0), "in the kitchen the leap card comes up")
	# the cards follow rebinds
	CatKeys.set_bind("jump", 0, {"k": KEY_J})
	await process_frame
	await process_frame
	_ok("j" in _tut()._label.text, "a rebound key shows on the card")
	CatKeys.reset()
	p.combat.pounces += 1
	_ok(await _on("swat"), "a pounce (hold space leap) ticks off pounce")
	_tut()._gate_t = Tutorial.GATE_MAX
	await _game(0.5)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _game(0.1)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_ok(await _on("climb"), "a swat ticks off swat")
	_tut()._gate_t = Tutorial.GATE_MAX
	await _game(0.3)
	for i in 4:
		p.climbing = true    # (the controller drops it again with no wall: hold it a few frames)
		await process_frame
	p.climbing = false
	_ok(await _on("scratch"), "climbing ticks off climb")
	_tut()._gate_t = Tutorial.GATE_MAX
	await _game(0.3)
	for i in 4:
		p.scratching = true
		await process_frame
	p.scratching = false
	_ok(await _on("run"), "scratching ticks off scratch")
	_tut()._gate_t = Tutorial.GATE_MAX
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	await _game(1.8)
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)
	_ok(await _on("meow"), "running ticks off run")
	await _game(0.5)
	_ok(_tut()._t == 0.0, "meow card waits for the treat bag")
	Puzzles.solved["knock_it_off"] = 1
	_ok(await _game(1.0, func(): return _tut()._t > 0.0), "bag down: the meow card comes up")
	_key(KEY_N, true)
	await _game(0.1)
	_key(KEY_N, false)
	_ok(await _on("explore"), "a meow ticks off meow")
	Puzzles.solved.erase("knock_it_off")
	_ok(await _game(12.0, func(): return _tut() == null), "explore card goes away by itself, tutorial over")
	_ok(save.data.tutorial.get("done", false) == true, "done is saved")
	_ok(not Tutorial.should_run(), "and it won't start again")

	Tutorial.restart()
	await process_frame
	_ok(_tut() != null and _tut().id() == "move", "restart from the menu starts it from the top")
	GameSettings.s("hints", false)
	await process_frame
	await process_frame
	_ok(_tut() == null and not Tutorial.should_run(), "the setting turns it off")
	GameSettings.reset_defaults()

	Tutorial.force = false
	save.enabled = false
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)
	print("tutorial_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
