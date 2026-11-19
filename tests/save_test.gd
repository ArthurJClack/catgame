extends SceneTree
## save / load (save_game.gd): new game in a slot, play a bit (treats, a puzzle, a coat, catches,
## move the cat), save, go to the rat pit, wipe the live state, load the slot and check it all comes
## back (level, spot, coat, progress), autosave after a scene change, broken / old files, the pause
## menu save button. needs a display:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/save_test.gd

const DIR := "user://savetest/"
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


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _player() -> CatPlayer:
	var p = current_scene.get("player") if current_scene else null
	return p if p is CatPlayer and p.is_inside_tree() else null


func _at(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path and _player() != null and not root.has_node("HubFade")


func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var b := _find_button(c, prefix)
		if b:
			return b
	return null


func _run() -> void:
	var save = root.get_node("Save")
	_ok(save != null and not save.enabled, "Save autoload is there and off in --script runs")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	save.dir = DIR
	_clean()
	save.enabled = true
	save.new_game(1)
	_ok(save.exists(1) and save.slot == 1, "new game writes slot 2 (index 1)")

	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _at("res://main.tscn")), "farm loads")
	await _wait(1.0)
	var p := _player()
	Puzzles.treats_eaten = 5
	Puzzles.solved = {"knock_it_off": 1, "perch": 2}
	p.set_style("stepped_coon")
	await process_frame
	p = _player()
	var spot := p.global_position + Vector3(0.6, 0, 0.4)
	p.global_position = spot
	p.velocity = Vector3.ZERO
	p.orb_yaw = 1.1
	await _wait(1.0, func(): return p.is_on_floor())
	await _wait(0.3)
	spot = p.global_position
	p.catches += 2
	await _wait(0.3)
	_ok(int(save.stat("catches")) == 2, "catches are counted (%d)" % int(save.stat("catches")))
	_ok(save.save_now(), "save_now() writes")
	var pk: Dictionary = save.peek(1)
	_ok(int(pk.get("treats", -1)) == 5 and pk.get("style", "") == "stepped_coon" and pk.get("scene", "") == "res://main.tscn", "file has treats / coat / level")

	# away + wipe the live state
	change_scene_to_file("res://arena.tscn")
	_ok(await _wait(20.0, func(): return _at("res://arena.tscn")), "rat pit loads")
	Puzzles.treats_eaten = 0
	Puzzles.solved = {}
	Engine.remove_meta("cat_style")
	await _wait(5.0)
	print("  autosave: last %d ms ago, scene in file %s" % [Time.get_ticks_msec() - save.last_save_ms, save.peek(1).get("scene", "")])
	_ok(save.peek(1).get("scene", "") == "res://arena.tscn", "autosaved after the scene change")
	# put the farm spot back in the file as the "last save" to load
	var f := FileAccess.open(save.path_for(1), FileAccess.WRITE)
	f.store_string(JSON.stringify(pk))
	f.close()

	_ok(save.load_slot(1, true), "load_slot travels")
	_ok(await _wait(25.0, func(): return _at("res://main.tscn")), "back on the farm")
	await _wait(0.5)
	p = _player()
	var d := p.global_position.distance_to(spot) if p else 99.0
	_ok(d < 0.3, "cat is back where it was saved (%.2f m off)" % d)
	_ok(p and absf(wrapf(p.orb_yaw - 1.1, -PI, PI)) < 0.05, "facing the same way")
	_ok(p and p.style == "stepped_coon", "same coat (%s)" % (p.style if p else "?"))
	_ok(Puzzles.treats_eaten == 5 and int(Puzzles.solved.get("perch", 0)) == 2, "treats + puzzles restored")
	_ok(int(save.stat("catches")) == 2, "stats restored")

	# a level change after loading doesn't teleport the cat to the old spot
	change_scene_to_file("res://arena.tscn")
	await _wait(20.0, func(): return _at("res://arena.tscn"))
	change_scene_to_file("res://main.tscn")
	await _wait(20.0, func(): return _at("res://main.tscn"))
	await _wait(0.3)
	_ok(_player().global_position.distance_to(spot) > 0.3, "later visits use the normal spawn")

	# broken + old files
	f = FileAccess.open(save.path_for(2), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	_ok(save.peek(2).is_empty() and not save.load_slot(2, false), "a broken file doesn't load (and doesn't crash)")
	_ok(save.slot == 1, "and the current slot stays")
	f = FileAccess.open(save.path_for(2), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "treats": 3}))
	f.close()
	_ok(save.load_slot(2, false) and Puzzles.treats_eaten == 3 and save.data.stats.has("catches"), "an old file with missing keys loads with defaults")

	# pause menu button
	var menu = root.get_node("GameMenu")
	menu.open_menu()
	await process_frame
	await process_frame
	var b := _find_button(menu, "save")
	_ok(b != null, "pause menu has a save button")
	var before: int = save.last_save_ms
	await _wait(0.05)
	if b:
		b.pressed.emit()
	_ok(save.last_save_ms > before, "and it saves")
	menu.close_menu()

	_clean()
	save.enabled = false
	print("save_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
