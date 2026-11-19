extends SceneTree
## cat audio (cat_sfx.gd): every clip bakes, isn't silent and doesn't clip, the cat gets its
## CatSfx, walking makes paw steps of the right surface, a hop + landing, a paw strike whooshes,
## n meows, sitting still starts the purr and moving stops it, menu buttons click, rats squeak,
## everything is on the SFX bus. `-- out/dir` also writes every clip as a .wav to listen to.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/audio_test.gd [-- out/sfx]

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


## game time, not wall time: under xvfb the frame rate is low enough that physics runs slow
func _game(sec: float, until: Callable = func(): return false) -> bool:
	var n := int(sec * Engine.physics_ticks_per_second)
	for i in n:
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


func _played(prefix: String) -> int:
	var n := 0
	for c in CatSfx.played:
		if c.begins_with(prefix):
			n += 1
	return n


func _run() -> void:
	var t0 := Time.get_ticks_usec()
	CatSfx.bake()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_ok(CatSfx.clips.size() >= 30, "%d clips baked in %.0f ms" % [CatSfx.clips.size(), ms])
	var dir := ""
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		dir = a[0]
		DirAccess.make_dir_recursive_absolute(dir)
	var quiet := []
	var loud := []
	for k in CatSfx.clips:
		var w: AudioStreamWAV = CatSfx.clips[k]
		var peak := 0
		var clipped := 0
		for i in range(0, w.data.size(), 2):
			var v := absi(w.data.decode_s16(i))
			peak = maxi(peak, v)
			if v >= 31990:
				clipped += 1
		if peak < 1200:
			quiet.append(k)
		if clipped > 4:
			loud.append(k)
		if dir != "":
			w.save_to_wav("%s/%s.wav" % [dir, k])
	_ok(quiet.is_empty(), "no silent clips %s" % str(quiet))
	_ok(loud.is_empty(), "no clipping %s" % str(loud))

	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _player() != null), "farm loads")
	await _wait(1.0)
	var p := _player()
	var sfx := p.get_node_or_null("CatSfx") as CatSfx
	_ok(sfx != null, "the cat has its CatSfx")
	if sfx == null:
		quit(1)
		return
	_ok(sfx.pool[0].bus == &"SFX" and sfx.purr.bus == &"SFX", "on the SFX bus (settings volume)")

	# walk on the wooden floor
	CatSfx.played.clear()
	_key(KEY_W, true)
	for i in 8:
		await _wait(0.2)
		print("  floor %s spd %.2f pos %s played %d" % [p.is_on_floor(), Vector2(p.velocity.x, p.velocity.z).length(), p.global_position, CatSfx.played.size()])
	_key(KEY_W, false)
	await _wait(0.4)
	var steps := _played("step_")
	_ok(steps >= 4, "walking makes paw steps (%d, surface %s)" % [steps, p.surface])
	_ok(p.surface != "wood" or _played("step_tap") == steps, "the right kind for the floor")

	# hop
	CatSfx.played.clear()
	_key(KEY_SPACE, true)
	await _wait(0.12)
	_key(KEY_SPACE, false)
	await _game(1.5, func(): return _played("land_") > 0)
	_ok(_played("jump") > 0, "hop push off")
	_ok(_played("land_") > 0, "landing thump")

	# paw strike
	CatSfx.played.clear()
	await _wait(0.4)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _wait(0.08)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _game(0.8)
	_ok(_played("swish") > 0, "a swat whooshes")

	# meow
	CatSfx.played.clear()
	_key(KEY_N, true)
	await _wait(0.1)
	_key(KEY_N, false)
	await _wait(0.2)
	_ok(_played("meow") == 1, "n = one meow")

	# purr after sitting still
	await _game(CatSfx.PURR_AFTER + 2.5)
	_ok(sfx.purr.playing and sfx.purr.volume_db > -30.0, "sat still: purring (%.0f db)" % sfx.purr.volume_db)
	_key(KEY_W, true)
	await _game(1.2)
	_key(KEY_W, false)
	_ok(not sfx.purr.playing or sfx.purr.volume_db < -30.0, "moving stops the purr")

	# menu clicks
	var menu = root.get_node("GameMenu")
	CatSfx.played.clear()
	menu.open_menu()
	await process_frame
	await process_frame
	var btns := menu.find_children("*", "Button", true, false)
	if btns.size() > 0:
		(btns[0] as Button).pressed.emit()
	await process_frame
	_ok(_played("ui_click") > 0, "menu buttons click")
	if menu.is_open:
		menu.close_menu()

	# rats
	change_scene_to_file("res://arena.tscn")
	await _wait(20.0, func(): return _player() != null and current_scene.scene_file_path == "res://arena.tscn")
	CatSfx.played.clear()
	var rats := get_nodes_in_group("souls_rat")
	var has_voice := false
	for r in current_scene.find_children("*", "SoulsRat", true, false):
		if r.find_children("*", "", false, false).any(func(c): return c is CatSfx.RatVoice):
			has_voice = true
	_ok(has_voice, "rats get a voice")
	var rr := current_scene.find_children("*", "SoulsRat", true, false)
	var pp := _player()
	if rr.size() > 0 and pp:
		var r0: Node3D = rr[0]
		pp.global_position = r0.global_position + Vector3(0.6, 0.05, 0)
		pp.velocity = Vector3.ZERO
	await _game(12.0, func(): return _played("rat_") > 0)
	_ok(_played("rat_") > 0, "rats squeak at you (%s)" % str(CatSfx.played.filter(func(c): return c.begins_with("rat_")).slice(0, 4)))

	print("audio_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
