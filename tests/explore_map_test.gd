extends SceneTree
## the explore map (explore_map.gd autoload): on the farm the map starts dark, walking reveals
## around the cat, the map key (real j press) opens it and the cat stops listening, j closes it,
## the pause menu has a "map" button, the farm's fog survives a trip to the city and back, the
## city reports its own rect, merge() folds another copy in (max per cell).
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/explore_map_test.gd

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


func _load(path: String) -> CatPlayer:
	change_scene_to_file(path)
	var t0 := Time.get_ticks_msec()
	await process_frame
	while (_player() == null or current_scene.scene_file_path != path) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	await _game(10)
	return _player()


func _run() -> void:
	Engine.set_meta("title_done", true)
	GameSettings.s("hints", false)
	var em = root.get_node("ExploreMap")
	em.mem = {}
	var p := await _load("res://main.tscn")
	_ok(p != null, "farm loads")
	var t0 := Time.get_ticks_msec()
	while em.gw == 0 and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	_ok(em.gw > 0 and em.gh > 0 and em.scene_path == "res://main.tscn", "farm map set up (%d x %d cells of %.2f m)" % [em.gw, em.gh, em.cell])
	var start: float = em.explored()
	_ok(start > 0.0 and start < 0.25, "only the bit round the cat is revealed (%.1f%%)" % (start * 100.0))
	var far := p.global_position + Vector3(14, 0, 0)
	_ok(em.fog_at(far) == 0, "14 m away is still fogged")
	em.reveal_at(far)
	_ok(em.fog_at(far) == 255 and em.explored() > start, "walking there reveals it (%.1f%%)" % (em.explored() * 100.0))
	# map key opens + blocks the cat, again closes
	_key(KEY_J, true)
	await _game(3)
	_key(KEY_J, false)
	await _game(3)
	_ok(em.is_open and CatKeys.blocked, "j opens the map and the cat stops taking keys")
	t0 = Time.get_ticks_msec()
	while em._map_tex == null and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	_ok(em._map_tex != null, "top down picture taken")
	_key(KEY_J, true)
	await _game(3)
	_key(KEY_J, false)
	await _game(3)
	_ok(not em.is_open and not CatKeys.blocked and not paused, "j again closes it, game unpaused")
	# pause menu button
	var gm = root.get_node("GameMenu")
	gm.open_menu()
	await _game(3)
	var btn: Button = null
	var stack: Array[Node] = [gm]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text.begins_with("map ("):
			btn = n
		for c in n.get_children():
			stack.append(c)
	_ok(btn != null, "pause menu has a map button (%s)" % (btn.text if btn else "none"))
	if btn:
		btn.pressed.emit()
		await _game(3)
		_ok(em.is_open and not gm.is_open, "the button swaps the menu for the map")
		em.close_map()
		await _game(2)
	else:
		gm.close_menu()
	var farm_seen: float = em.explored()
	# to the city: its own rect; back: the farm's fog is still there
	p = await _load("res://city.tscn")
	_ok(p != null, "city loads")
	t0 = Time.get_ticks_msec()
	while em.scene_path != "res://city.tscn" or em.gw == 0:
		await process_frame
		if Time.get_ticks_msec() - t0 > 10000:
			break
	_ok(is_equal_approx(em.rect.size.x, 92.0) and em.cell == 1.0, "city map uses the level's map_info (%s, cell %.2f)" % [em.rect, em.cell])
	_ok(em.labels.size() > 15, "city place names (%d)" % em.labels.size())
	p = await _load("res://main.tscn")
	t0 = Time.get_ticks_msec()
	while em.scene_path != "res://main.tscn" or em.gw == 0:
		await process_frame
		if Time.get_ticks_msec() - t0 > 10000:
			break
	_ok(em.explored() >= farm_seen - 0.001, "farm fog kept across levels (%.1f%% -> %.1f%%)" % [farm_seen * 100.0, em.explored() * 100.0])
	# merge: a remote copy that saw the far corner
	var e: Dictionary = em.entry().duplicate(true)
	var raw := Marshalls.base64_to_raw(e.fog)
	raw[raw.size() - 1] = 255
	e.fog = Marshalls.raw_to_base64(raw)
	em.merge("res://main.tscn", e)
	_ok(em.fog[em.fog.size() - 1] == 255, "merge folds in another copy (max per cell)")
	var stored: Dictionary = em.mem.get("res://main.tscn", {})
	_ok(stored.get("v", 0) == 1 and stored.has("fog") and int(stored.w) == em.gw, "stored as {v, rect, cell, w, h, fog}")
	print("explore map test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(0 if bad == 0 else 1)
