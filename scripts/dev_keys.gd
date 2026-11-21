class_name DevKeys
extends RefCounted
## level shortcut keys (1-9 coats, f4 / f6 / f7 / f8 / f10 level jumps, t next spot, f1-f3 psx look)
## are for building the game, not playing it. release exports drop them: coats live in the
## settings page, travel goes through the farm's gates and "back to the farm" in the menu.
## r (restart), f5 (home), h (help), m stay for everyone.

const PLAYER_KEYS := [KEY_R, KEY_F5, KEY_H, KEY_M]


static func on() -> bool:
	return OS.is_debug_build()


## true when the key should be ignored in this build
static func blocked(k: int) -> bool:
	return not on() and not (k in PLAYER_KEYS)
