extends SceneTree
## the simplified controls (simplify pass 2026-11-21) with real key / mouse presses on the farm:
## one swat button alternates paws, e drops what's in the mouth or scratches, no aim key,
## no walk keys, lock on + the health bar only in the rat pit (stamina everywhere), v flips first / third
## person (orbit only with the photo cam setting), dev keys are off in release builds,
## binds saved with the old layout fall back to the new defaults.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/controls_test.gd

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


func _tap_mouse(b: MouseButton) -> void:
	_mouse(b, true)
	await _game(3)
	_mouse(b, false)
	await _game(3)


func _run() -> void:
	GameSettings.path = "user://controls_test_settings.cfg"
	GameSettings.reset_defaults()
	CatKeys.reset()
	Tutorial.force = false
	GameSettings.s("hints", false)
	Engine.set_meta("title_done", true)    # straight into the game, no title screen
	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _player() != null), "farm loads")
	var p := _player()
	await _game(30)

	# --- the key list
	var ids := []
	for a in CatKeys.ACTIONS:
		ids.append(a[0])
	_ok(ids.size() <= 16, "16 or fewer rebindable actions (%d)" % ids.size())   # 15th = cat vision, 16th = the explore map
	for gone in ["aim", "walk", "walk_toggle", "paw_l", "paw_r", "scratch", "drop"]:
		_ok(not gone in ids, "no '%s' key any more" % gone)
	_ok(CatKeys.describe("grab").begins_with("mouse2"), "grab is on mouse2 (%s)" % CatKeys.describe("grab"))
	_ok(CatKeys.describe("interact").begins_with("e"), "interact is on e (%s)" % CatKeys.describe("interact"))

	# --- old saved layout falls back to the new defaults, a v2 save round trips
	CatKeys.from_dict({"jump": [{"k": KEY_J}], "grab": [{"k": KEY_G}]})
	_ok(CatKeys.describe("jump") == "space" and CatKeys.describe("grab").begins_with("mouse2"), "binds saved before the new layout are dropped")
	CatKeys.set_bind("jump", 0, {"k": KEY_J})
	var d := CatKeys.to_dict()
	CatKeys.from_dict(d)
	_ok(CatKeys.describe("jump") == "j", "new layout binds survive a save + load")
	CatKeys.reset()

	# --- swat alternates paws
	var c := p.combat
	var sw0: int = p._swat_paw
	await _tap_mouse(MOUSE_BUTTON_LEFT)
	var first: int = p._swat_paw
	await _game(40)
	await _tap_mouse(MOUSE_BUTTON_LEFT)
	_ok(first != sw0 and p._swat_paw != first, "mouse1 alternates paws (%d -> %d -> %d)" % [sw0, first, p._swat_paw])
	_ok(c.swats >= 1 if "swats" in c else true, "it swats")

	# --- interact: drop when carrying, scratch otherwise
	var mouse := Node3D.new()
	current_scene.add_child(mouse)
	p.carried = mouse
	var inp := {"interact": true}
	p._human_buttons(inp)
	_ok(inp.drop and not inp.scratch, "e with something in the mouth = drop")
	p.carried = null
	inp = {"interact": true}
	p._human_buttons(inp)
	_ok(not inp.scratch, "and the same held press doesn't turn into a scratch")
	inp = {"interact": false}
	p._human_buttons(inp)
	inp = {"interact": true}
	p._human_buttons(inp)
	_ok(inp.scratch and not inp.drop, "e with nothing in the mouth = scratch")
	inp = {"interact": false}
	p._human_buttons(inp)
	mouse.queue_free()

	# --- no combat systems on the farm
	_ok(not p.combat_on(), "farm: combat systems off")
	p.stamina.value = 10.0
	await _game(3)
	_ok(p.stamina.value < CatStamina.MAX - 1.0, "farm: stamina is real (%.1f)" % p.stamina.value)
	p.stamina.value = CatStamina.MAX
	_ok(p.souls_hud.visible and p.souls_hud._st_fill.visible and not p.souls_hud._hp_fill.visible, "farm: stamina bar, no health bar")
	_key(KEY_TAB, true)
	await _game(3)
	_key(KEY_TAB, false)
	await _game(3)
	_ok(not p.lock.active(), "farm: tab doesn't lock on")
	p.combat_zone = true
	await _game(3)
	_ok(p.souls_hud._hp_fill.visible, "rat pit flag: health bar comes back")
	p.combat_zone = false

	# --- a / d walk, never side hop, for a human
	var y0 := p.global_position.y
	_key(KEY_A, true)
	var hopped := false
	for i in 60:
		await physics_frame
		if p.global_position.y > y0 + 0.08:
			hopped = true
	_key(KEY_A, false)
	_ok(not hopped, "a doesn't side hop")

	# --- v flips first / third person only
	_ok(p.view_mode == 0, "starts first person")
	for i in 3:
		_key(KEY_V, true)
		await _game(3)
		_key(KEY_V, false)
		await _game(3)
		_ok(p.view_mode in [0, 1], "v press %d -> view %d (no orbit)" % [i + 1, p.view_mode])
	GameSettings.s("photo_cam", true)
	GameSettings.apply_player(p)
	p.set_view(1)
	_key(KEY_V, true)
	await _game(3)
	_key(KEY_V, false)
	await _game(3)
	_ok(p.view_mode == 2, "photo cam setting: v reaches orbit")
	GameSettings.s("photo_cam", false)
	GameSettings.apply_player(p)
	_ok(p.view_mode == 0, "turning it off leaves orbit")

	# --- dev keys
	_ok(DevKeys.on() == OS.is_debug_build(), "dev keys follow the build type")
	_ok(not DevKeys.blocked(KEY_R) and not DevKeys.blocked(KEY_F5) and not DevKeys.blocked(KEY_H), "r / f5 / h always work")
	if not DevKeys.on():
		_ok(DevKeys.blocked(KEY_F6) and DevKeys.blocked(KEY_1), "release: level jumps + coat keys are off")

	GameSettings.reset_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://controls_test_settings.cfg"))
	print("controls_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
