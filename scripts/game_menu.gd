extends CanvasLayer
## pause menu (autoload "GameMenu"): esc / pad start opens it in any level with a local cat.
## pages: paused (resume, settings, controls, back to the farm, quit), settings (audio, mouse,
## camera, display, graphics) and controls (rebind every keyboard / mouse action, cat_keys.gd).
## single player pauses the game, online it doesn't (the other cats keep going) but your cat
## stops listening to keys while it's open. settings save to user://settings.cfg (game_settings.gd)
## and get applied to every scene as it loads.

signal opened
signal closed

const PANEL_W := 560

var is_open := false
var page := ""
var _root: Control
var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _fps: Label
var _rebind: Array = []        # [action, slot, button] while waiting for a key
var _mouse_before := Input.MOUSE_MODE_CAPTURED
var _paused_tree := false
var settings_only := false     # opened from the title screen: back closes instead of the paused page


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.ensure()
	CatSfx.ui("warm")      # makes the ui player
	_build()
	get_tree().node_added.connect(_on_node_added)
	GameSettings.apply_all.call_deferred(get_tree())
	CatVR.boot(get_tree())


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		# menu clicks everywhere (pause menu, title, lobby)
		(n as BaseButton).pressed.connect(func(): CatSfx.ui("click"))
		(n as BaseButton).mouse_entered.connect(func(): CatSfx.ui("hover"))
	elif n is SoulsRat and CatSfx.available():
		var v := CatSfx.RatVoice.new()
		v.rat = n
		n.add_child.call_deferred(v)
	# a fresh scene: give its environment / lights / audio / cat the saved settings
	if n is WorldEnvironment or n is DirectionalLight3D or n is Camera3D \
			or n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
		GameSettings.apply_node.call_deferred(n)


func _process(_dt: float) -> void:
	_fps.visible = GameSettings.g("show_fps")
	if _fps.visible:
		_fps.text = "%d fps" % Engine.get_frames_per_second()


# ---------------------------------------------------------------- open / close

func local_cat() -> CatPlayer:
	for p in get_tree().get_nodes_in_group("player"):
		if p is CatPlayer and (p as CatPlayer).bot.is_empty() and p.is_inside_tree():
			return p
	return null


func can_open() -> bool:
	if Net.server or DisplayServer.get_name() == "headless":
		return false
	if Net.ui and Net.ui is CanvasItem and (Net.ui as CanvasItem).visible:
		return false     # the lobby (m) has its own esc
	if get_tree().root.has_node("HubFade") or not get_tree().get_nodes_in_group("title_screen").is_empty():
		return false
	return local_cat() != null


func online() -> bool:
	return not Net.peers.is_empty() or Net.on_server()


func open_menu() -> void:
	if is_open:
		return
	is_open = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	CatKeys.blocked = true
	_paused_tree = not online()
	if _paused_tree:
		get_tree().paused = true
	_root.visible = true
	show_page("main")
	opened.emit()


func close_menu() -> void:
	if not is_open:
		return
	_rebind = []
	is_open = false
	settings_only = false
	_root.visible = false
	CatKeys.blocked = false
	if _paused_tree:
		get_tree().paused = false
	_paused_tree = false
	GameSettings.save_file()
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _rebind.is_empty():
		_rebind_input(event)
		return
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	var start: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START
	var back: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B
	if esc or start:
		if is_open:
			if page != "main":
				show_page("main")
			else:
				close_menu()
			get_viewport().set_input_as_handled()
		elif can_open():
			open_menu()
			get_viewport().set_input_as_handled()
	elif back and is_open:
		if page != "main":
			show_page("main")
		else:
			close_menu()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- ui

func _build() -> void:
	_fps = Label.new()
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.position = Vector2(-90, 8)
	_fps.add_theme_font_size_override("font_size", 14)
	_fps.add_theme_color_override("font_color", Color(0.85, 1, 0.85))
	_fps.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps.add_theme_constant_override("outline_size", 4)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps.visible = false
	add_child(_fps)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # clicks off the panel don't reach the game
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.085, 0.1, 0.96)
	sb.border_color = Color(0.95, 0.78, 0.2, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 20
	sb.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	center.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.2))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	v.add_child(_body)


func show_page(p: String) -> void:
	if p == "main" and settings_only and is_open:
		close_menu.call_deferred()
		return
	page = p
	_rebind = []
	for c in _body.get_children():
		c.queue_free()
	match p:
		"main": _page_main()
		"settings": _page_settings()
		"controls": _page_controls()
		"achievements": _page_achievements()


func _button(parent: Node, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _page_main() -> void:
	_title.text = "paused" if _paused_tree else "menu (online, the game keeps going)"
	var first := _button(_body, "resume", close_menu)
	if Save.enabled:
		var ago := (Time.get_ticks_msec() - Save.last_save_ms) / 1000
		var txt := "save" if Save.last_save_ms == 0 else "save (last saved %s ago)" % _ago(ago)
		_button(_body, txt, func(): Save.save_now(); show_page("main"))
	_button(_body, "settings", show_page.bind("settings"))
	_button(_body, "controls", show_page.bind("controls"))
	var ach = Save.achievements
	if ach:
		_button(_body, "achievements (%d / %d)" % [ach.count(), Achievements.LIST.size()], show_page.bind("achievements"))
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path != "" and scene.scene_file_path != "res://main.tscn":
		_button(_body, "back to the farm", _go_farm)
	if not OS.has_feature("web"):
		_button(_body, "quit to desktop", func(): GameSettings.save_file(); get_tree().quit())
	first.grab_focus.call_deferred()


func _ago(sec: int) -> String:
	if sec < 60:
		return "%ds" % sec
	return "%dm" % (sec / 60)


func _go_farm() -> void:
	var cat := local_cat()
	var st: String = cat.style if cat and "style" in cat else ""
	close_menu()
	Hub.travel(get_tree(), "res://main.tscn", "", st)


func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.95, 0.78, 0.2, 0.85))
	_body_target().add_child(l)


var _scroll_box: VBoxContainer


func _body_target() -> Node:
	return _scroll_box if is_instance_valid(_scroll_box) else _body


func _scroll() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(PANEL_W, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	_scroll_box = v
	return v


func _row(text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 16)
	h.add_child(l)
	_body_target().add_child(h)
	return h


func _slider(text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> HSlider:
	var h := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(GameSettings.g(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(180, 28)
	var val := Label.new()
	val.custom_minimum_size = Vector2(64, 0)
	val.text = fmt.call(s.value)
	h.add_child(s)
	h.add_child(val)
	s.value_changed.connect(func(x):
		GameSettings.s(key, x)
		val.text = fmt.call(x)
		_apply())
	return s


func _check(text: String, key: String) -> CheckButton:
	var h := _row(text)
	var c := CheckButton.new()
	c.button_pressed = GameSettings.g(key)
	c.toggled.connect(func(on): GameSettings.s(key, on); _apply())
	h.add_child(c)
	return c


func _option(text: String, key: String, labels: Array, values: Array) -> Control:
	var h := _row(text)
	if CatVR.active:
		# vr: a dropdown's popup is its own window, which the vr panel can't show. click to cycle
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(160, 32)
		var at := [maxi(values.find(GameSettings.g(key)), 0)]
		cb.text = str(labels[at[0]])
		cb.pressed.connect(func():
			at[0] = (at[0] + 1) % values.size()
			cb.text = str(labels[at[0]])
			GameSettings.s(key, values[at[0]])
			_apply())
		h.add_child(cb)
		return cb
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(160, 32)
	for i in labels.size():
		o.add_item(labels[i], i)
	var cur = GameSettings.g(key)
	o.selected = maxi(values.find(cur), 0)
	o.item_selected.connect(func(i): GameSettings.s(key, values[i]); _apply())
	h.add_child(o)
	return o


func _apply() -> void:
	GameSettings.apply_all(get_tree())
	if CatVR.body and is_instance_valid(CatVR.body):
		CatVR.body.apply_settings()


func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


func _page_settings() -> void:
	_title.text = "settings"
	_scroll()
	_section("audio")
	_slider("master volume", "master", 0.0, 1.0, 0.05, _pct)
	_slider("world / ambience", "ambience", 0.0, 1.0, 0.05, _pct)
	_slider("cat + effects", "sfx", 0.0, 1.0, 0.05, _pct)
	_section("mouse + camera")
	_slider("mouse sensitivity", "sens", 0.2, 3.0, 0.05, func(x): return "%.2fx" % x)
	_check("invert look up / down", "invert_y")
	_slider("field of view", "fov", 60.0, 110.0, 1.0, func(x): return "%d°" % roundi(x))
	_check("head bob (first person)", "head_bob")
	_section("display")
	if not OS.has_feature("web"):
		_check("fullscreen", "fullscreen")
		_check("vsync", "vsync")
	var caps := []
	for c in GameSettings.FPS_CAPS:
		caps.append("no cap" if c == 0 else "%d" % c)
	_option("max fps", "max_fps", caps, GameSettings.FPS_CAPS)
	_check("show fps", "show_fps")
	_section("help")
	_check("tutorial hints", "hints")
	var rt := _row("")
	var rb := Button.new()
	rb.text = "restart the tutorial"
	rb.custom_minimum_size = Vector2(220, 32)
	rb.pressed.connect(func():
		GameSettings.s("hints", true)
		close_menu()
		Tutorial.restart())
	rt.add_child(rb)
	_page_vr()
	_section("graphics")
	_option("quality", "quality", GameSettings.QUALITY_NAMES, [0, 1, 2])
	_slider("render scale", "render_scale", 0.5, 1.0, 0.05, _pct)
	_scroll_box = null
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_body.add_child(h)
	var b := _button(h, "back", show_page.bind("main"))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := _button(h, "reset to defaults", func():
		var keys := CatKeys.to_dict()
		GameSettings.reset_defaults()
		CatKeys.from_dict(keys)
		_apply()
		show_page("settings"))
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.grab_focus.call_deferred()


## vr (vr/cat_vr.gd). turning vr on / off restarts the game (OpenXR can only start with the engine)
func _page_vr() -> void:
	if OS.has_feature("web"):
		return
	_section("vr")
	var r := _row("vr mode (SteamVR, Quest Link...)")
	var b := Button.new()
	b.custom_minimum_size = Vector2(220, 32)
	b.text = "turn vr off (restarts)" if CatVR.active else "turn vr on (restarts)"
	b.pressed.connect(func():
		var on := not CatVR.active
		GameSettings.s("vr", on)
		CatVR.relaunch(get_tree(), on))
	r.add_child(b)
	if CatVR.failed != "":
		var l := Label.new()
		l.text = CatVR.failed
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.modulate = Color(1, 0.8, 0.6)
		_body_target().add_child(l)
	_option("turning", "vr_turn", ["snap", "smooth"], [0, 1])
	_slider("snap turn angle", "vr_snap", 15.0, 90.0, 15.0, func(x): return "%d°" % roundi(x))
	_slider("smooth turn speed", "vr_turn_speed", 45.0, 240.0, 15.0, func(x): return "%d°/s" % roundi(x))
	_slider("comfort vignette", "vr_vignette", 0.0, 1.0, 0.05, func(x): return "off" if x <= 0.0 else _pct(x))
	_slider("cat size (world scale)", "vr_scale", 0.25, 1.0, 0.05, func(x): return "%.2fx" % x)
	_option("menu pointer hand", "vr_hand", ["left", "right"], [0, 1])
	_check("your hands move the paws", "vr_paws")
	if CatVR.active and CatVR.body:
		var rr := _row("")
		var rc := Button.new()
		rc.text = "recenter view"
		rc.custom_minimum_size = Vector2(220, 32)
		rc.pressed.connect(func(): CatVR.body.recenter())
		rr.add_child(rc)


func _page_controls() -> void:
	_title.text = "controls"
	var hint := Label.new()
	hint.text = "click a key to change it, then press the new key or mouse button. esc cancels, backspace clears."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = PANEL_W
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.65, 0.66, 0.7))
	_body.add_child(hint)
	_scroll()
	for a in CatKeys.ACTIONS:
		var h := _row(a[1])
		for slot in 2:
			var bs := CatKeys.binds(a[0])
			var b := Button.new()
			b.custom_minimum_size = Vector2(130, 32)
			b.text = CatKeys.label(bs[slot]) if slot < bs.size() else "-"
			b.pressed.connect(_start_rebind.bind(a[0], slot, b))
			h.add_child(b)
	_section("gamepad")
	var pad := Label.new()
	pad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pad.custom_minimum_size.x = PANEL_W - 30
	pad.add_theme_font_size_override("font_size", 13)
	pad.text = "left stick move (tilt = speed), right stick look, L3 run / gallop, A hop / pounce, B dodge, X scratch, Y grab, LT / RT paws, LB aim leap, RB crouch, R3 lock on, d-pad down drop, up walk, left view, start = this menu"
	_scroll_box.add_child(pad)
	_section("other keys")
	var other := Label.new()
	other.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	other.custom_minimum_size.x = PANEL_W - 30
	other.add_theme_font_size_override("font_size", 13)
	other.text = "esc menu, m online lobby, 1-9 coats, f5 back to the farm, r restart (pit / trail), f9 update, mouse wheel zoom (orbit view)"
	_scroll_box.add_child(other)
	_scroll_box = null
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 10)
	_body.add_child(h2)
	var back := _button(h2, "back", show_page.bind("main"))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := _button(h2, "reset keys", func(): CatKeys.reset(); GameSettings.save_file(); show_page("controls"))
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.grab_focus.call_deferred()


func _page_achievements() -> void:
	var ach = Save.achievements
	_title.text = "achievements  %d / %d" % [ach.count() if ach else 0, Achievements.LIST.size()]
	_scroll()
	for id in Achievements.LIST:
		var a: Array = Achievements.LIST[id]
		var got: bool = ach != null and ach.has(id)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var mark := Achievements.PawIcon.new()
		mark.lit = got
		mark.custom_minimum_size = Vector2(26, 26)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(mark)
		var v := VBoxContainer.new()
		var t := Label.new()
		t.text = a[0] if (got or not a[2]) else "???"
		t.add_theme_font_size_override("font_size", 17)
		t.add_theme_color_override("font_color", Color(0.95, 0.78, 0.2) if got else Color(0.75, 0.75, 0.78))
		v.add_child(t)
		var d := Label.new()
		d.text = (a[1] + ("  ·  " + str(ach.data()[id]) if got else "")) if (got or not a[2]) else "a secret"
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", Color(0.6, 0.6, 0.64))
		v.add_child(d)
		h.add_child(v)
		_scroll_box.add_child(h)
	_scroll_box = null
	var b := _button(_body, "back", show_page.bind("main"))
	b.grab_focus.call_deferred()


func _start_rebind(action: String, slot: int, b: Button) -> void:
	_rebind = [action, slot, b]
	b.text = "press a key..."


func _rebind_input(event: InputEvent) -> void:
	var action: String = _rebind[0]
	var slot: int = _rebind[1]
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE:
			_rebind = []
			show_page("controls")
			return
		if event.physical_keycode in [KEY_BACKSPACE, KEY_DELETE]:
			CatKeys.clear_bind(action, slot)
			_finish_rebind()
			return
		var bk := CatKeys.from_event(event)
		if bk.is_empty():
			(_rebind[2] as Button).text = "that key's taken"
			return
		CatKeys.set_bind(action, slot, bk)
		_finish_rebind()
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		var bm := CatKeys.from_event(event)
		if bm.is_empty():
			return
		CatKeys.set_bind(action, slot, bm)
		_finish_rebind()


func _finish_rebind() -> void:
	_rebind = []
	GameSettings.save_file()
	show_page.call_deferred("controls")
