class_name CatKeys
extends RefCounted
## rebindable keyboard + mouse controls. every action holds up to two binds, each one is
## {"k": physical keycode} or {"m": mouse button}. cat_player reads `CatKeys.down("jump")`
## instead of hard coded keys, the pause menu (game_menu.gd) rebinds them and GameSettings
## saves them to user://settings.cfg. the gamepad map lives in cat_pad.gd and isn't touched.

const ACTIONS := [
	# [id, label]. kept short on purpose (simplify pass 2026-11-21): one leap on space,
	# one swat button, e does whatever fits (scratch / drop), crouch is the slow sneak
	["forward", "move forward"],
	["back", "move back"],
	["left", "move left"],
	["right", "move right"],
	["run", "trot (double tap = gallop)"],
	["crouch", "crouch / sneak"],
	["jump", "hop (tap) / leap + pounce (hold, aim, let go)"],
	["swat", "swat (hold = hook with your claws)"],
	["grab", "grab / hold in your mouth"],
	["interact", "scratch / drop (whatever's in front)"],
	["dash", "dodge"],
	["meow", "meow"],
	["toggle_view", "first / third person"],
	["lock_on", "lock on (rat pit / play fight)"],
	["vision", "cat vision (hold: light up stuff worth a look)"],
	["map", "explore map"],
]

## bump when the default layout changes: older saved binds are dropped so nobody keeps a
## half old layout (v2 = simplify pass: swat / grab on the mouse, e interact, no aim key)
const VERSION := 2

const DEFAULTS := {
	"forward": [{"k": KEY_W}],
	"back": [{"k": KEY_S}],
	"left": [{"k": KEY_A}],
	"right": [{"k": KEY_D}],
	"run": [{"k": KEY_SHIFT}],
	"crouch": [{"k": KEY_CTRL}, {"k": KEY_C}],
	"jump": [{"k": KEY_SPACE}],
	"swat": [{"m": MOUSE_BUTTON_LEFT}],
	"grab": [{"m": MOUSE_BUTTON_RIGHT}, {"k": KEY_G}],
	"interact": [{"k": KEY_E}, {"k": KEY_F}],
	"dash": [{"k": KEY_ALT}, {"m": MOUSE_BUTTON_XBUTTON1}],
	"meow": [{"k": KEY_N}],
	"toggle_view": [{"k": KEY_V}],
	"lock_on": [{"k": KEY_TAB}],
	"vision": [{"k": KEY_Q}],
	"map": [{"k": KEY_J}],
}

## keys the game keeps for itself (menus, level keys): can't be bound
const RESERVED := [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8,
	KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_M, KEY_R, KEY_H,
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

static var map := {}
static var blocked := false   # pause menu open: every action reads as up


static func _ensure() -> void:
	if map.is_empty():
		reset()


static func reset() -> void:
	map = {}
	for a in DEFAULTS:
		map[a] = DEFAULTS[a].duplicate(true)


static func binds(action: String) -> Array:
	_ensure()
	return map.get(action, [])


static func bind_down(b: Dictionary) -> bool:
	if b.has("k"):
		return Input.is_physical_key_pressed(b.k)
	if b.has("m"):
		return Input.is_mouse_button_pressed(b.m)
	return false


static func down(action: String) -> bool:
	if blocked:
		return false
	for b in binds(action):
		if bind_down(b):
			return true
	return false


## a bind from an input event, or {} if it can't be bound
static func from_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey and ev.pressed:
		var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		if code in RESERVED or code == KEY_NONE:
			return {}
		return {"k": code}
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return {}
		return {"m": ev.button_index}
	return {}


static func same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("k", -1) == b.get("k", -1) and a.get("m", -1) == b.get("m", -1)


## put `b` in slot 0 or 1 of `action`. the same bind anywhere else is taken off (no double binds)
static func set_bind(action: String, slot: int, b: Dictionary) -> void:
	_ensure()
	for a in map:
		var arr: Array = map[a]
		for i in range(arr.size() - 1, -1, -1):
			if same(arr[i], b):
				arr.remove_at(i)
	var mine: Array = map.get(action, [])
	if slot < mine.size():
		mine[slot] = b
	else:
		mine.append(b)
	map[action] = mine


static func clear_bind(action: String, slot: int) -> void:
	_ensure()
	var mine: Array = map.get(action, [])
	if slot < mine.size():
		mine.remove_at(slot)


static func label(b: Dictionary) -> String:
	if b.has("k"):
		var s := OS.get_keycode_string(b.k)
		return s.to_lower() if s != "" else "key %d" % b.k
	if b.has("m"):
		match int(b.m):
			MOUSE_BUTTON_LEFT: return "mouse1"
			MOUSE_BUTTON_RIGHT: return "mouse2"
			MOUSE_BUTTON_MIDDLE: return "mouse3"
			MOUSE_BUTTON_XBUTTON1: return "mouse4"
			MOUSE_BUTTON_XBUTTON2: return "mouse5"
		return "mouse%d" % b.m
	return "-"


static func describe(action: String) -> String:
	var parts := []
	for b in binds(action):
		parts.append(label(b))
	return " / ".join(parts) if parts.size() > 0 else "unbound"


## "{swat} swat" -> "mouse1 swat": help text that follows rebinds (plain text, no bbcode)
static func fill(text: String) -> String:
	var out := text
	for a in ACTIONS:
		out = out.replace("{%s}" % a[0], describe(a[0]))
	return out


## a help label that rewrites itself when keys change (game_menu.gd calls refresh_help)
static func help(l: Label, template: String) -> void:
	l.set_meta("keys_template", template)
	l.text = fill(template)
	if not l.is_in_group("key_help"):
		l.add_to_group("key_help")


static func refresh_help(tree: SceneTree) -> void:
	for l in tree.get_nodes_in_group("key_help"):
		if l is Label and l.has_meta("keys_template"):
			(l as Label).text = fill(l.get_meta("keys_template"))


static func to_dict() -> Dictionary:
	_ensure()
	var d := map.duplicate(true)
	d["_v"] = VERSION
	return d


static func from_dict(d: Dictionary) -> void:
	reset()
	if int(d.get("_v", 1)) != VERSION:
		return      # saved with an older layout: start from the new defaults
	for a in d:
		if not DEFAULTS.has(a) or not d[a] is Array:
			continue
		var arr := []
		for b in d[a]:
			if b is Dictionary and (b.has("k") or b.has("m")):
				var nb := {}
				if b.has("k"): nb.k = int(b.k)
				if b.has("m"): nb.m = int(b.m)
				arr.append(nb)
		map[a] = arr
	# actions added since this file was saved keep their defaults, minus any key the player
	# already uses for something else (no double binds)
	for a in DEFAULTS:
		if d.has(a):
			continue
		var mine: Array = map[a]
		for i in range(mine.size() - 1, -1, -1):
			for o in map:
				if o == a:
					continue
				for b in map[o]:
					if i < mine.size() and same(b, mine[i]):
						mine.remove_at(i)
