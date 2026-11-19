extends SceneTree
## pause menu + settings + key rebinding (game_menu.gd, game_settings.gd, cat_keys.gd).
## opens the menu with esc on the farm, checks the game pauses and the cat ignores keys, rebinds
## keys through the real controls page, changes fov / sensitivity / quality / volume, saves and
## reloads the file, closes the menu and drives the cat with the rebound key. needs a display:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/menu_test.gd

const TEST_PATH := "user://settings_menu_test.cfg"
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


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	await process_frame
	await process_frame
	_key(code, false)
	await process_frame


func _env() -> Environment:
	for n in current_scene.get_children():
		if n is WorldEnvironment:
			return n.environment
	return null


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	GameSettings.path = TEST_PATH
	GameSettings.load_file()
	var menu = root.get_node("GameMenu")
	_ok(menu != null, "GameMenu autoload is there")

	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _player() != null), "farm loads")
	await _wait(1.5)
	var p := _player()
	_ok(is_equal_approx(p.fov_base, 82.0) and is_equal_approx(p.mouse_sens, GameSettings.BASE_SENS), "defaults = the old hard coded fov / sens")

	# --- open
	await _tap(KEY_ESCAPE)
	_ok(menu.is_open, "esc opens the menu")
	_ok(paused, "single player: the game pauses")
	_ok(CatKeys.blocked and not CatKeys.down("forward"), "cat ignores keys while it's open")
	var pos := p.global_position
	_key(KEY_W, true)
	await _wait(0.4)
	_key(KEY_W, false)
	_ok(p.global_position.distance_to(pos) < 0.01, "holding w in the menu doesn't move the cat")

	# --- controls page: rebind through the real buttons
	menu.show_page("controls")
	await process_frame
	await process_frame
	var jb := _find_button(menu, "space")
	_ok(jb != null, "controls page lists jump = space")
	if jb:
		jb.pressed.emit()
		await process_frame
		await _tap(KEY_J)
		await process_frame
	_ok(CatKeys.binds("jump").size() > 0 and CatKeys.binds("jump")[0].get("k", -1) == KEY_J, "jump rebound to j")
	var wb := _find_button(menu, "w")
	if wb:
		wb.pressed.emit()
		await process_frame
		await _tap(KEY_J)
		await process_frame
	_ok(CatKeys.binds("forward")[0].get("k", -1) == KEY_J, "forward rebound to j")
	_ok(CatKeys.binds("jump").is_empty(), "j comes off jump (no double binds)")
	var fb := _find_button(menu, "f")
	if fb:
		fb.pressed.emit()
		await process_frame
		await _tap(KEY_ESCAPE)
	_ok(menu.is_open and CatKeys.binds("scratch")[0].get("k", -1) == KEY_F, "esc cancels a rebind, menu stays open")
	_ok(CatKeys.from_event(_ev(KEY_F5)).is_empty(), "reserved keys can't be bound")

	# --- settings
	menu.show_page("settings")
	await process_frame
	GameSettings.s("fov", 100.0)
	GameSettings.s("sens", 2.0)
	GameSettings.s("invert_y", true)
	GameSettings.s("sfx", 0.5)
	GameSettings.apply_all(self)
	_ok(is_equal_approx(p.fov_base, 100.0), "fov applies to the cat")
	_ok(is_equal_approx(p.mouse_sens, GameSettings.BASE_SENS * 2.0) and p.invert_y, "sens + invert apply")
	var sfx := AudioServer.get_bus_index("SFX")
	_ok(sfx != -1 and absf(AudioServer.get_bus_volume_db(sfx) - linear_to_db(0.5)) < 0.1, "sfx bus volume")
	var env := _env()
	GameSettings.s("quality", 0)
	GameSettings.apply_all(self)
	_ok(env and not env.ssao_enabled and not env.volumetric_fog_enabled, "low quality turns ssao / fog off")
	GameSettings.s("quality", 2)
	GameSettings.apply_all(self)
	_ok(env and env.ssao_enabled and env.volumetric_fog_enabled and env.ssil_enabled, "high quality brings the level's own look back")

	# --- save + reload
	GameSettings.save_file()
	GameSettings.s("fov", 70.0)
	CatKeys.reset()
	GameSettings.load_file()
	_ok(is_equal_approx(float(GameSettings.g("fov")), 100.0) and GameSettings.g("invert_y") == true, "settings survive a reload")
	_ok(CatKeys.binds("forward")[0].get("k", -1) == KEY_J, "key binds survive a reload")

	# --- close + play with the new key
	await _tap(KEY_ESCAPE)   # settings -> main page
	await _tap(KEY_ESCAPE)   # close
	_ok(not menu.is_open and not paused and not CatKeys.blocked, "esc closes it and unpauses")
	_key(KEY_J, true)
	await process_frame
	var mj: Vector2 = p._read_input().move
	var peak := 0.0
	for k in 40:
		await physics_frame
		peak = maxf(peak, Vector2(p.velocity.x, p.velocity.z).length())
	_key(KEY_J, false)
	await process_frame
	await process_frame
	_ok(mj.y > 0.5 and peak > 1.0, "j (rebound forward) drives the cat: move %s, speed %.2f" % [mj, peak])
	_key(KEY_W, true)
	await process_frame
	await process_frame
	var mw: Vector2 = p._read_input().move
	_key(KEY_W, false)
	_ok(mw == Vector2.ZERO, "w does nothing now")

	# --- back to the farm from another level
	change_scene_to_file("res://arena.tscn")
	await _wait(20.0, func(): return _player() != null and current_scene.scene_file_path == "res://arena.tscn")
	await _wait(0.5)
	await _tap(KEY_ESCAPE)
	_ok(menu.is_open and _find_button(menu, "back to the farm") != null, "menu in the rat pit offers back to the farm")
	var farm := _find_button(menu, "back to the farm")
	if farm:
		farm.pressed.emit()
	_ok(await _wait(20.0, func(): return current_scene and current_scene.scene_file_path == "res://main.tscn" and _player() != null and not root.has_node("HubFade")), "back to the farm works")
	_ok(not paused and not menu.is_open, "and the game isn't left paused")

	CatKeys.reset()
	GameSettings.reset_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("menu_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)


func _ev(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e
