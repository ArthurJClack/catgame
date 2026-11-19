class_name TitleScreen
extends CanvasLayer
## title screen: the first thing you see when the game boots. it sits over the live farm
## (main.tscn) while the camera circles the cat, so there's no separate menu scene and the farm
## is already loaded when you hit play. buttons: continue (last save, says where + how long),
## new game / load (3 save slots, save_game.gd), settings (the pause menu's page), play online
## (the m lobby), quit. shows once per run (Engine meta "title_done"), never in tests / previews
## (any `--` user arg or a --script run) or on the dedicated server.
## test: xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/title_test.gd

signal finished(how: String)

const GOLD := Color(0.95, 0.78, 0.2)
const ORBIT_SPEED := 0.12      # rad / s around the cat

var main: Node3D
var player: CatPlayer
var page := ""
var _root: Control
var _box: VBoxContainer
var _view_before := 0
var _orb_dist_before := 1.0
var _t := 0.0
var _closing := false
static var force := false      # tests: show even in a --script run


## autoloads by path: this class gets compiled by --script tests before autoload names exist
static func _al(n: String) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(n) if ml else null


static func should_show() -> bool:
	if Engine.has_meta("title_done") or _al("Net").server or DisplayServer.get_name() == "headless":
		return false
	if force:
		return true
	var args := OS.get_cmdline_args()
	return OS.get_cmdline_user_args().is_empty() and not ("--script" in args or "-s" in args)


static func show_on(m: Node3D, p: CatPlayer) -> TitleScreen:
	var t := TitleScreen.new()
	t.main = m
	t.player = p
	m.add_child(t)
	return t


func _ready() -> void:
	layer = 85
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("title_screen")
	CatKeys.blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_hud(false)
	if player:
		_view_before = player.view_mode
		_orb_dist_before = player.orb_dist
		player.set_view.call_deferred(2)
		player.orb_dist = 1.6
		player.orb_pitch = -0.22
	_build()
	show_page("main")
	if _al("GameMenu"):
		_al("GameMenu").closed.connect(_menu_closed)


func _set_hud(on: bool) -> void:
	var hud = main.get("hud") if main else null
	if hud is CanvasItem or hud is CanvasLayer:
		hud.visible = on
	if player and is_instance_valid(player) and player.souls_hud:
		player.souls_hud.hidden_by_menu = not on


func _process(dt: float) -> void:
	_t += dt
	if player and is_instance_valid(player) and not _closing:
		player.orb_yaw += ORBIT_SPEED * dt
		player.orb_pitch = -0.22 + sin(_t * 0.21) * 0.06
	if not _closing and not (_al("GameMenu") and _al("GameMenu").is_open) and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _menu_closed() -> void:
	if _closing:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	CatKeys.blocked = true
	_root.visible = true


# ---------------------------------------------------------------- ui

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	# dark wash down the left side so the menu reads over the farm
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.03, 0.05, 0.86))
	g.set_color(1, Color(0.03, 0.03, 0.05, 0.0))
	g.set_offset(1, 1.0)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var wash := TextureRect.new()
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.anchor_bottom = 1.0
	wash.anchor_right = 0.62
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wash)

	var col := VBoxContainer.new()
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 90
	col.offset_top = 120
	col.offset_right = 90 + 440
	col.add_theme_constant_override("separation", 6)
	_root.add_child(col)
	var title := Label.new()
	title.text = "cat game"
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 14)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "be the cat. knock things off. sit in the sun."
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", Color(0.9, 0.88, 0.84))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	sub.add_theme_constant_override("outline_size", 5)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 46
	col.add_child(gap)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	col.add_child(_box)

	var ver := Label.new()
	ver.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 18
	ver.offset_top = -34
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72, 0.8))
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ver)


func _btn(text: String, fn: Callable, sub := "") -> Button:
	var b := Button.new()
	b.text = text if sub == "" else "%s\n%s" % [text, sub]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 62 if sub != "" else 48)
	b.add_theme_font_size_override("font_size", 22 if sub == "" else 19)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.08, 0.075, 0.09, 0.72)
	flat.set_corner_radius_all(4)
	flat.content_margin_left = 18
	flat.content_margin_right = 18
	var hov := flat.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.2, 0.17, 0.08, 0.9)
	hov.border_color = GOLD
	hov.border_width_left = 4
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("focus", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.pressed.connect(fn)
	_box.add_child(b)
	return b


func show_page(p: String) -> void:
	page = p
	for c in _box.get_children():
		c.queue_free()
	match p:
		"main": _page_main()
		"slots": _page_slots()


static func describe(d: Dictionary) -> String:
	if d.is_empty():
		return "empty"
	var mins := int(float(d.get("play_s", 0.0)) / 60.0)
	var where := Hub.scene_name(str(d.get("scene", "")))
	var n := 0
	for k in d.get("solved", {}):
		n += 1
	return "%s · %s · %d puzzle%s · %d treats" % [where, ("%dh %dm" % [mins / 60, mins % 60]) if mins >= 60 else "%d min" % mins,
		n, "" if n == 1 else "s", int(d.get("treats", 0))]


func _page_main() -> void:
	var first: Button
	var last: Dictionary = _al("Save").peek(_al("Save").slot)
	if not last.is_empty():
		first = _btn("continue", _continue, describe(last))
	first = first if first else _btn("new game", show_page.bind("slots"))
	if not last.is_empty() or _any_save():
		_btn("load / new game", show_page.bind("slots"))
	_btn("settings", _settings)
	_btn("play online", _online)
	if not OS.has_feature("web"):
		_btn("quit", func(): get_tree().quit())
	first.grab_focus.call_deferred()


func _any_save() -> bool:
	for s in _al("Save").SLOTS:
		if _al("Save").exists(s):
			return true
	return false


func _page_slots() -> void:
	var first: Button
	for s in _al("Save").SLOTS:
		var d: Dictionary = _al("Save").peek(s)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var b := _btn("slot %d%s" % [s + 1, "  (last played)" if s == _al("Save").slot and not d.is_empty() else ""],
			_pick_slot.bind(s), describe(d) if not d.is_empty() else "empty: new game")
		b.custom_minimum_size.x = 380
		if first == null:
			first = b
		if not d.is_empty():
			# second button: start over in this slot (two clicks so it can't happen by accident)
			_box.remove_child(b)
			h.add_child(b)
			var del := Button.new()
			del.text = "start over"
			del.custom_minimum_size = Vector2(120, 62)
			del.pressed.connect(func():
				if del.text == "start over":
					del.text = "sure? click"
				else:
					_new_in(s))
			h.add_child(del)
			_box.add_child(h)
	_btn("back", show_page.bind("main"))
	if first:
		first.grab_focus.call_deferred()


func _pick_slot(s: int) -> void:
	if _al("Save").exists(s):
		_al("Save").slot = s
		_continue()
	else:
		_new_in(s)


# ---------------------------------------------------------------- actions

func _continue() -> void:
	var d: Dictionary = _al("Save").peek(_al("Save").slot)
	if d.is_empty():
		_new_in(_al("Save").slot)
		return
	_close("continue")
	_al("Save").load_slot(_al("Save").slot, true)
	# the save's coat on this cat too (if it stays on the farm there's no scene change to pick it up)
	var st: String = d.get("style", "")
	if st != "" and player and is_instance_valid(player) and player.style != st:
		player.set_style(st)


func _new_in(s: int) -> void:
	_close("new")
	_al("Save").new_game(s)
	# fresh farm: the boot may already have put the old save's coat / spot on this cat
	get_tree().reload_current_scene()


func _settings() -> void:
	_root.visible = false
	_al("GameMenu").open_menu()
	_al("GameMenu").settings_only = true
	_al("GameMenu").show_page("settings")


func _online() -> void:
	_close("online")
	if _al("Net").ui and _al("Net").ui.has_method("toggle") and not _al("Net").ui.visible:
		_al("Net").ui.toggle()


func _close(how: String) -> void:
	if _closing:
		return
	_closing = true
	Engine.set_meta("title_done", true)
	CatKeys.blocked = false
	_set_hud(true)
	if player and is_instance_valid(player):
		player.set_view(_view_before)
		player.orb_dist = _orb_dist_before
		player.last_event = ""
	if how != "online" and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	finished.emit(how)
	queue_free()
