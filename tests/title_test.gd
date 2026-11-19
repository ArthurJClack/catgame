extends SceneTree
## title screen (title_screen.gd): shows over the farm on boot, settings round trip, continue
## goes to the saved level, a new game in an empty slot starts a fresh farm, it shows once a run.
## saves screenshots when given a folder:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/title_test.gd [-- out/title]

const DIR := "user://titletest/"
var bad := 0
var shots := ""


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


func _title() -> TitleScreen:
	var t := get_nodes_in_group("title_screen")
	return t[0] if t.size() > 0 else null


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).visible and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var b := _find_button(c, prefix)
		if b:
			return b
	return null


func _shot(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [shots, name])


func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		shots = a[0]
		DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var save = root.get_node("Save")
	var GameMenu = root.get_node("GameMenu")
	save.dir = DIR
	_clean()
	save.enabled = true
	# a save sitting in the rat pit, slot 1
	save.new_game(0)
	save.data.scene = "res://arena.tscn"
	save.data.play_s = 754.0
	save.data.treats = 9
	save.data.solved = {"knock_it_off": 1}
	var f := FileAccess.open(save.path_for(0), FileAccess.WRITE)
	f.store_string(JSON.stringify(save.data))
	f.close()

	TitleScreen.force = true
	if Engine.has_meta("title_done"):
		Engine.remove_meta("title_done")
	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _player() != null and _title() != null), "boot: the title screen is up over the farm")
	var p := _player()
	var t := _title()
	await _wait(2.5)
	_ok(CatKeys.blocked and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "cat ignores keys, mouse is free")
	_ok(p.view_mode == 2, "camera circles the cat (orbit view)")
	var y0 := p.orb_yaw
	await _wait(0.5)
	_ok(absf(p.orb_yaw - y0) > 0.01, "and it moves")
	_ok(not current_scene.hud.visible, "game hud hidden")
	var cont := _find_button(t, "continue")
	_ok(cont != null and "the rat pit" in cont.text and "12 min" in cont.text and "9 treats" in cont.text, "continue says where + how long: %s" % (cont.text.replace("\n", " | ") if cont else "none"))
	_ok(not GameMenu.can_open(), "esc pause menu stays shut under the title")
	await _shot("title_main")

	# settings round trip
	_find_button(t, "settings").pressed.emit()
	await process_frame
	await process_frame
	_ok(GameMenu.is_open and GameMenu.page == "settings", "settings opens the settings page")
	await _shot("title_settings")
	GameMenu.show_page("main")   # = the back button
	await process_frame
	await process_frame
	_ok(not GameMenu.is_open and _title() != null and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "back returns to the title")

	# slots page
	_find_button(t, "load / new game").pressed.emit()
	await process_frame
	await process_frame
	_ok(_find_button(t, "slot 1") != null and _find_button(t, "slot 2") != null and _find_button(t, "slot 3") != null, "slots page lists 3 slots")
	await _shot("title_slots")
	_find_button(t, "back").pressed.emit()
	await process_frame
	await process_frame

	# continue -> the saved level
	_find_button(t, "continue").pressed.emit()
	_ok(await _wait(25.0, func(): return _at("res://arena.tscn")), "continue goes to the rat pit")
	_ok(_title() == null and not CatKeys.blocked, "title gone, cat listens again")
	_ok(Puzzles.treats_eaten == 9, "progress loaded")

	# shows once a run
	change_scene_to_file("res://main.tscn")
	await _wait(20.0, func(): return _at("res://main.tscn"))
	await _wait(0.3)
	_ok(_title() == null, "no title on later farm visits")

	# new game in an empty slot
	Engine.remove_meta("title_done")
	get_current_scene().get_tree().reload_current_scene()
	await _wait(20.0, func(): return _player() != null and _title() != null)
	t = _title()
	_find_button(t, "load / new game").pressed.emit()
	await process_frame
	await process_frame
	var s3 := _find_button(t, "slot 3")
	_ok(s3 != null and "empty" in s3.text, "slot 3 is empty")
	if s3:
		s3.pressed.emit()
	await _wait(2.0)
	await _wait(20.0, func(): return _at("res://main.tscn") and _title() == null)
	_ok(_title() == null and save.slot == 2 and save.exists(2), "new game in slot 3, file written")
	_ok(Puzzles.treats_eaten == 0 and Puzzles.solved.is_empty(), "fresh progress")
	var info: Dictionary = current_scene.info
	_ok(_player().global_position.distance_to(info.spawn) < 1.0, "fresh farm spawn")

	TitleScreen.force = false
	_clean()
	save.enabled = false
	print("title_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
