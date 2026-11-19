class_name CatKeys
extends RefCounted
## rebindable keyboard + mouse controls. every action holds up to two binds, each one is
## {"k": physical keycode} or {"m": mouse button}. cat_player reads `CatKeys.down("jump")`
## instead of hard coded keys, the pause menu (game_menu.gd) rebinds them and GameSettings
## saves them to user://settings.cfg. the gamepad map lives in cat_pad.gd and isn't touched.

const ACTIONS := [
	# [id, label]
	["forward", "move forward"],
	["back", "move back"],
	["left", "move left / side hop"],
	["right", "move right / side hop"],
	["run", "run (double tap = gallop)"],
	["walk", "walk (hold)"],
	["walk_toggle", "walk toggle"],
	["crouch", "crouch / stalk"],
	["jump", "hop / pounce (hold)"],
	["paw_l", "left paw"],
	["paw_r", "right paw"],
	["grab", "grab"],
	["aim", "aim leap"],
	["dash", "dodge"],
	["scratch", "scratch"],
	["drop", "drop what's in your mouth"],
	["lock_on", "lock on"],
	["toggle_view", "switch view"],
]

const DEFAULTS := {
	"forward": [{"k": KEY_W}],
	"back": [{"k": KEY_S}],
	"left": [{"k": KEY_A}],
	"right": [{"k": KEY_D}],
	"run": [{"k": KEY_SHIFT}],
	"walk": [{"k": KEY_X}],
	"walk_toggle": [{"k": KEY_CAPSLOCK}],
	"crouch": [{"k": KEY_CTRL}, {"k": KEY_C}],
	"jump": [{"k": KEY_SPACE}],
	"paw_l": [{"m": MOUSE_BUTTON_LEFT}],
	"paw_r": [{"m": MOUSE_BUTTON_RIGHT}],
	"grab": [{"k": KEY_G}, {"m": MOUSE_BUTTON_XBUTTON2}],
	"aim": [{"k": KEY_Q}, {"m": MOUSE_BUTTON_MIDDLE}],
	"dash": [{"k": KEY_ALT}, {"m": MOUSE_BUTTON_XBUTTON1}],
	"scratch": [{"k": KEY_F}],
	"drop": [{"k": KEY_E}],
	"lock_on": [{"k": KEY_TAB}],
	"toggle_view": [{"k": KEY_V}],
}

## keys the game keeps for itself (menus, level keys): can't be bound
const RESERVED := [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8,
	KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_M, KEY_R]

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


static func to_dict() -> Dictionary:
	_ensure()
	return map.duplicate(true)


static func from_dict(d: Dictionary) -> void:
	reset()
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
