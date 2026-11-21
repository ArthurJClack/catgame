class_name GameSettings
extends RefCounted
## player settings: volume, mouse, fov, display, graphics quality and the key binds (cat_keys.gd).
## saved to user://settings.cfg. the pause menu (game_menu.gd) edits them and calls apply(),
## GameMenu also applies them to every new scene (world environments, audio players, the cat).
## the defaults are exactly what the game did before settings existed, so tests don't change.

const PATH := "user://settings.cfg"
const BASE_SENS := 0.0022
const DEFAULTS := {
	"master": 0.8,
	"ambience": 1.0,
	"sfx": 1.0,
	"sens": 1.0,          # x BASE_SENS
	"invert_y": false,
	"fov": 82.0,
	"head_bob": true,     # false = first person camera stays level (motion sickness)
	"fullscreen": false,
	"vsync": false,
	"max_fps": 0,         # 0 = no cap
	"render_scale": 1.0,
	"quality": 2,         # 0 low, 1 medium, 2 high
	"show_fps": false,
	"hints": true,        # tutorial hint cards on the farm (tutorial.gd)
	"vr": false,          # play in vr (vr/cat_vr.gd): the game restarts itself with OpenXR on
	"vr_turn": 0,         # 0 snap turn, 1 smooth turn (right stick)
	"vr_snap": 30.0,      # degrees per snap
	"vr_turn_speed": 120.0, # degrees / s smooth turning
	"vr_vignette": 0.6,   # tunnel vignette while moving fast / turning (0 = off)
	"vr_scale": 0.5,      # world scale: 0.5 = cat sized eyes (the world looks twice as big), 1 = human
	"vr_hand": 1,         # menu pointer hand: 0 left, 1 right
	"vr_paws": true,      # raising your hands lifts the cat's forepaws (swing = swat)
}
const QUALITY_NAMES := ["low", "medium", "high"]
const FPS_CAPS := [0, 30, 60, 120, 144, 165, 240]

static var values := {}
static var _loaded := false
static var path := PATH   # tests point this somewhere else


static func ensure() -> void:
	if not _loaded:
		load_file()


static func g(key: String):
	ensure()
	return values.get(key, DEFAULTS.get(key))


static func s(key: String, v) -> void:
	ensure()
	values[key] = v


static func reset_defaults() -> void:
	values = DEFAULTS.duplicate(true)
	_loaded = true


static func load_file() -> void:
	values = DEFAULTS.duplicate(true)
	_loaded = true
	CatKeys.reset()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for k in DEFAULTS:
		if cf.has_section_key("settings", k):
			var v = cf.get_value("settings", k)
			if typeof(v) == typeof(DEFAULTS[k]) or (DEFAULTS[k] is float and v is int):
				values[k] = v
	if cf.has_section_key("keys", "map"):
		var m = cf.get_value("keys", "map")
		if m is Dictionary:
			CatKeys.from_dict(m)


static func save_file() -> void:
	ensure()
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("settings", k, values[k])
	cf.set_value("keys", "map", CatKeys.to_dict())
	cf.save(path)


# ---------------------------------------------------------------- applying

static func bus(name: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	return i


static func _vol(i: int, v: float) -> void:
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


static func apply_audio() -> void:
	_vol(0, g("master"))
	_vol(bus("Ambience"), g("ambience"))
	_vol(bus("SFX"), g("sfx"))


static func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if CatVR.active and not CatVR.sim:
		return   # the headset paces frames; the desktop window is only a mirror
	if not OS.has_feature("web"):
		var fs: bool = g("fullscreen")
		var cur := DisplayServer.window_get_mode()
		var is_fs := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if g("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(g("max_fps"))


static func apply_viewport(vp: Viewport) -> void:
	if vp == null:
		return
	var rs: float = g("render_scale")
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = rs
	var q: int = g("quality")
	if not vp.has_meta("orig_msaa"):
		vp.set_meta("orig_msaa", vp.msaa_3d)
	vp.msaa_3d = vp.get_meta("orig_msaa") if q >= 1 else Viewport.MSAA_DISABLED


## graphics quality on one Environment. the scene's own values are kept in metas so going back
## up to high gives exactly what the level was built with
const _ENV_PROPS := {
	# prop: lowest quality that keeps it on
	"ssil_enabled": 2,
	"volumetric_fog_enabled": 2,
	"ssr_enabled": 2,
	"ssao_enabled": 1,
	"sdfgi_enabled": 2,
	"glow_enabled": 1,
}


static func apply_env(env: Environment) -> void:
	if env == null:
		return
	var q: int = g("quality")
	for p in _ENV_PROPS:
		var key: String = "orig_" + p
		if not env.has_meta(key):
			env.set_meta(key, env.get(p))
		env.set(p, env.get_meta(key) and q >= _ENV_PROPS[p])


static func apply_light(l: Light3D) -> void:
	if not l is DirectionalLight3D:
		return
	if not l.has_meta("orig_shadow"):
		l.set_meta("orig_shadow", l.shadow_enabled)
		l.set_meta("orig_dist", (l as DirectionalLight3D).directional_shadow_max_distance)
	var q: int = g("quality")
	l.shadow_enabled = l.get_meta("orig_shadow")
	(l as DirectionalLight3D).directional_shadow_max_distance = l.get_meta("orig_dist") * (0.5 if q == 0 else 1.0)


static func apply_player(p: Node) -> void:
	if p == null or not p is CatPlayer:
		return
	var cp := p as CatPlayer
	if not cp.bot.is_empty():
		return
	cp.mouse_sens = BASE_SENS * float(g("sens"))
	cp.invert_y = g("invert_y")
	cp.fov_base = float(g("fov"))
	cp.calm_cam = not g("head_bob")


## everything, on the whole running tree
static func apply_all(tree: SceneTree) -> void:
	apply_audio()
	apply_display()
	if tree == null:
		return
	apply_viewport(tree.root)
	_walk(tree.root)


static func _walk(n: Node) -> void:
	apply_node(n)
	for c in n.get_children():
		_walk(c)


static func apply_node(n: Node) -> void:
	if n is WorldEnvironment:
		apply_env((n as WorldEnvironment).environment)
	elif n is Camera3D and (n as Camera3D).environment:
		apply_env((n as Camera3D).environment)
	elif n is DirectionalLight3D:
		apply_light(n)
	elif n is CatPlayer:
		apply_player(n)
	elif n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
		route_audio(n)


## new audio players default to Master: ambience (soundscape, wind, water, music) or sfx
static func route_audio(n: Node) -> void:
	if n.get("bus") != &"Master":
		return
	var amb := n.has_meta("ambience")
	var p := n.get_parent()
	while p and not amb:
		if p is Soundscape or p.has_meta("ambience"):
			amb = true
		p = p.get_parent()
	n.set("bus", "Ambience" if amb else "SFX")
	bus("Ambience")
	bus("SFX")
