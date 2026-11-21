class_name Tutorial
extends CanvasLayer
## first time on the farm: one small hint card at a time (bottom centre), showing the keys you
## actually have bound (cat_keys.gd) or the pad buttons if you're on a pad. each card ticks off
## when you do the thing, or moves on by itself after a while. it's only ever about controls:
## the puzzles keep the "no words, the world answers" rule. progress lives in the save
## (`Save.data.tutorial`), settings -> "tutorial hints" turns it off, the pause menu can restart it.
## the old wall of help text on the farm is hidden while this runs (h still shows it).
## test: xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/tutorial_test.gd

signal step_done(id: String)
signal finished

const GOLD := Color(0.95, 0.78, 0.2)
const SKIP_AFTER := 40.0        # a card nobody does moves on by itself
const DONE_HOLD := 0.9          # the tick shows this long before the next card

## [id, text with {action} keys, pad text]
const STEPS := [
	["move", "{forward} {left} {back} {right}  to walk around", "left stick to walk around"],
	["look", "move the mouse to look", "right stick to look"],
	["run", "hold {run} to run, double tap it and hold for a full gallop", "click L3 to run, again to gallop"],
	["hop", "tap {jump} to hop", "tap A to hop"],
	["pounce", "hold {jump}: the cat crouches and shows where it'll land. let go to leap there (onto prey = a pounce)", "hold A: aim where to land, let go to leap (onto prey = a pounce)"],
	["climb", "jump at the cat tree, a fence or a tree trunk holding {forward} to climb it", "jump at a cat tree or trunk holding forward to climb"],
	["swat", "{swat} swat (hold it to hook things with your claws)", "RT swat (hold to hook with your claws)"],
	["scratch", "{interact} at a post or the cat tree: scratch. it also drops whatever's in your mouth", "hold X at a post or the cat tree: scratch. X also drops what's in your mouth"],
	["meow", "{meow} meow", "Y meow"],
	["explore", "that's it. esc opens the menu, the gaps in the yard fence lead out to other places", "start opens the menu. the gaps in the yard fence lead out to other places"],
]

static var force := false

var player: CatPlayer
var main: Node
var idx := -1
var _t := 0.0
var _done_t := -1.0
var _card: PanelContainer
var _label: RichTextLabel
var _tick: Label
var _bar: ColorRect
# what we measure from
var _start_pos := Vector3.ZERO
var _yaw0 := 0.0
var _look := 0.0
var _hops := 0
var _was_floor := true
var _leaps0 := 0
var _pounces0 := 0
var _meowed := false


static func _al(n: String) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(n) if ml else null


static func should_run() -> bool:
	if not GameSettings.g("hints") or DisplayServer.get_name() == "headless":
		return false
	var save := _al("Save")
	if save and save.data.get("tutorial", {}).get("done", false):
		return false
	if force:
		return true
	var args := OS.get_cmdline_args()
	return OS.get_cmdline_user_args().is_empty() and not ("--script" in args or "-s" in args)


static func start(m: Node, p: CatPlayer) -> Tutorial:
	var t := Tutorial.new()
	t.main = m
	t.player = p
	t.name = "Tutorial"
	m.add_child(t)
	return t


func _ready() -> void:
	layer = 70
	add_to_group("tutorial")
	_build()
	var hl = main.get("help_label") if main else null
	if hl is Control:
		(hl as Control).visible = false
	var save := _al("Save")
	var from := 0
	if save:
		from = int(save.data.get("tutorial", {}).get("step", 0))
	_next(from)


func _state() -> Dictionary:
	var save := _al("Save")
	if save == null:
		return {}
	if not save.data.has("tutorial") or not save.data.tutorial is Dictionary:
		save.data.tutorial = {}
	return save.data.tutorial


func _build() -> void:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.065, 0.08, 0.82)
	sb.border_color = Color(GOLD, 0.6)
	sb.border_width_left = 4
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 18
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_card.add_theme_stylebox_override("panel", sb)
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_left = -330
	_card.offset_right = 330
	_card.offset_top = -150
	_card.offset_bottom = -92
	anchor.add_child(_card)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 19)
	_label.add_theme_font_size_override("bold_font_size", 19)
	h.add_child(_label)
	_tick = Label.new()
	_tick.text = "✓"
	_tick.add_theme_font_size_override("font_size", 28)
	_tick.add_theme_color_override("font_color", Color(0.5, 0.95, 0.45))
	_tick.visible = false
	h.add_child(_tick)
	_bar = ColorRect.new()
	_bar.color = Color(GOLD, 0.5)
	_bar.custom_minimum_size = Vector2(0, 2)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_bar)


func id() -> String:
	return STEPS[idx][0] if idx >= 0 and idx < STEPS.size() else ""


static func keycap(action: String) -> String:
	var parts := []
	for b in CatKeys.binds(action):
		parts.append("[b][color=#f2c733]%s[/color][/b]" % CatKeys.label(b))
	return " / ".join(parts) if parts.size() > 0 else "[i](unbound)[/i]"


static func render(text: String) -> String:
	var out := text
	for a in CatKeys.ACTIONS:
		out = out.replace("{%s}" % a[0], keycap(a[0]))
	return out


func _refresh_text() -> void:
	if idx < 0 or idx >= STEPS.size():
		return
	var s: Array = STEPS[idx]
	var pad: bool = CatPad.last_used_pad and CatPad.connected() and s[2] != ""
	_label.text = render(s[2] if pad else s[1])


func _next(i: int) -> void:
	idx = i
	_t = 0.0
	_done_t = -1.0
	_tick.visible = false
	var st := _state()
	st["step"] = i
	if i >= STEPS.size():
		st["done"] = true
		finished.emit()
		queue_free()
		return
	_refresh_text()
	_card.modulate.a = 0.0
	if player and is_instance_valid(player):
		_start_pos = player.global_position
		_yaw0 = player.orb_yaw
		_look = 0.0
		_hops = 0
		_leaps0 = player.leaps
		_pounces0 = player.combat.pounces if player.combat else 0
	_meowed = false


func _process(dt: float) -> void:
	if player == null or not is_instance_valid(player) or idx >= STEPS.size():
		return
	if not GameSettings.g("hints"):
		queue_free()       # turned off in settings
		return
	var paused := get_tree().paused or not get_tree().get_nodes_in_group("title_screen").is_empty()
	_card.visible = not paused
	if paused:
		return
	_t += dt
	_card.modulate.a = minf(_card.modulate.a + dt * 3.0, 1.0)
	_refresh_text()
	if _done_t >= 0.0:
		_done_t += dt
		_card.modulate.a = 1.0 - clampf((_done_t - DONE_HOLD * 0.6) / (DONE_HOLD * 0.4), 0.0, 1.0)
		if _done_t >= DONE_HOLD:
			_next(idx + 1)
		return
	_bar.custom_minimum_size.x = 0.0
	_bar.size.x = (1.0 - clampf(_t / SKIP_AFTER, 0.0, 1.0)) * (_card.size.x - 38.0)
	var ok := _check(dt)
	if ok:
		complete()
	elif _t >= SKIP_AFTER or (id() == "explore" and _t > 9.0):
		_next(idx + 1)


func complete() -> void:
	if _done_t >= 0.0:
		return
	_done_t = 0.0
	_tick.visible = true
	CatSfx.ui("click")
	step_done.emit(id())


func _check(dt: float) -> bool:
	var p := player
	var floor := p.is_on_floor()
	var hop := floor == false and _was_floor and p.velocity.y > 1.0
	_was_floor = floor
	match id():
		"move":
			var d := p.global_position - _start_pos
			return Vector2(d.x, d.z).length() > 2.0
		"look":
			_look += absf(wrapf(p.orb_yaw - _yaw0, -PI, PI))
			_yaw0 = p.orb_yaw
			return _look > 1.6
		"run":
			return Vector2(p.velocity.x, p.velocity.z).length() > 5.0
		"hop":
			if hop:
				_hops += 1
			return _hops >= 1
		"scratch":
			return p.scratching
		"climb":
			return p.climbing
		"swat":
			return p.combat != null and p.combat.atk in ["swat", "rake"]
		"pounce":
			return p.combat != null and p.combat.pounces > _pounces0
		"meow":
			if CatKeys.down("meow") or (CatPad.connected() and CatPad.btn(JOY_BUTTON_Y)):
				_meowed = true
			return _meowed
	return false


## pause menu: run it again from the top
static func restart() -> void:
	var save := _al("Save")
	if save:
		save.data["tutorial"] = {}
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null:
		return
	for t in ml.get_nodes_in_group("tutorial"):
		t.queue_free()
	var sc := ml.current_scene
	var p = sc.get("player") if sc else null
	if p is CatPlayer and sc.scene_file_path == "res://main.tscn":
		Tutorial.start(sc, p)
