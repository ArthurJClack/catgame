extends SceneTree
## achievements (achievements.gd): stats / puzzles / live cat unlock them once, a card shows with
## the title, they're in the save and survive a reload, the pause menu page lists them (secrets
## stay ???). `-- out/dir` saves screenshots of the card + the page.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/achievements_test.gd

const DIR := "user://achtest/"
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


func _labels(n: Node, out: Array) -> Array:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_labels(c, out)
	return out


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
	var ach: Achievements = save.achievements
	_ok(ach != null and ach.count() == 0, "achievements live under Save, none yet")
	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _player() != null), "farm loads")
	await _wait(1.5)
	_ok(ach.count() == 0, "nothing unlocks by just standing there")
	var got := []
	ach.unlocked.connect(func(id): got.append(id))
	Puzzles.treats_eaten = 10
	_ok(await _wait(3.0, func(): return ach.has("treats_10")), "10 treats -> snack time")
	_ok(await _wait(2.0, func(): return ach.showing()), "card shows")
	_ok("snack time" in _labels(ach, []), "card says snack time")
	if shots != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots + "/achievement_card.png")
	save.data.stats.rats = 12
	Puzzles.solved["knock_it_off"] = 1
	await _wait(2.0, func(): return ach.has("ratter") and ach.has("knock_it_off"))
	_ok(ach.has("ratter") and ach.has("knock_it_off"), "rats + puzzle unlock theirs")
	_ok(not ach.has("treats_50") and not ach.has("exterminator"), "but not the bigger ones")
	await _wait(1.5)
	_ok(got.count("treats_10") == 1, "each unlocks once")
	_ok(not ach.unlock("treats_10"), "unlock() again is a no-op")

	# saved + reloaded
	save.save_now()
	save.data.achievements = {}
	_ok(save.load_slot(0, false) and ach.has("treats_10") and ach.has("ratter"), "they survive a save + load")

	# pause menu page
	var menu = root.get_node("GameMenu")
	menu.open_menu()
	await process_frame
	await process_frame
	var main_txt := []
	for b in menu.find_children("*", "Button", true, false):
		main_txt.append(b.text)
	_ok(main_txt.any(func(t): return t.begins_with("achievements (3 / %d)" % Achievements.LIST.size())), "menu button shows the count: %s" % str(main_txt))
	menu.show_page("achievements")
	await process_frame
	await process_frame
	var txt := _labels(menu, [])
	_ok("snack time" in txt and "pest control" in txt and "???" in txt, "page lists them, secrets hidden")
	if shots != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots + "/achievements_page.png")
	menu.close_menu()

	save.enabled = false
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)
	print("achievements_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
