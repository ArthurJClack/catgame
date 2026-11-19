extends Node
## save / load (autoload "Save"). one json file per slot in user:// (3 slots, the title screen
## picks one). what's kept: which level you're in + where the cat stands there, the coat, play
## time, treats eaten, puzzles solved, lifetime stats (catches, rats, best pit wave, trail laps,
## levels seen) and achievements (achievements.gd writes into `data.achievements`).
##
## autosaves: every AUTOSAVE_S seconds, a moment after every scene change, on puzzle solves
## and when the window closes. `Save.save_now()` from the pause menu. on boot the last used slot's
## progress (coat, puzzles, stats) is loaded; `Save.continue_game()` also travels to the saved level
## and puts the cat back where it was.
##
## off in tests / previews / the dedicated server (any `--` user arg, --script runs): `Save.enabled`.
## test: xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/save_test.gd

signal saved(slot: int)
signal loaded(slot: int)

const VERSION := 1
const SLOTS := 3
const AUTOSAVE_S := 45.0
const DIR := "user://"

var enabled := true
var slot := 0
var data := {}
var dir := DIR                 # tests point this somewhere else
var _t := 0.0
var _pending_pos = null        # [scene, Vector3, yaw] put the cat back here when that scene's cat shows up
var _seen_catches := 0
var _seen_player: Node = null
var _last_scene := ""
var _scene_save_t := -1.0
var _scene_ms := 0
var last_save_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_args()
	enabled = OS.get_cmdline_user_args().is_empty() and not ("--script" in args or "-s" in args) \
		and not Net.server and DisplayServer.get_name() != "headless"
	data = fresh()
	get_tree().node_added.connect(_on_node_added)
	_build_badge()
	if not enabled:
		return
	slot = _last_slot()
	if exists(slot):
		load_slot(slot, false)


# ---------------------------------------------------------------- data

func fresh() -> Dictionary:
	return {
		"version": VERSION,
		"created": Time.get_datetime_string_from_system(),
		"saved_at": "",
		"play_s": 0.0,
		"scene": "res://main.tscn",
		"pos": [],
		"yaw": 0.0,
		"style": "",
		"treats": 0,
		"solved": {},
		"stats": {
			"catches": 0,
			"rats": 0,
			"best_wave": 0,
			"trail_best_laps": 0,
			"levels": {},
			"lives_lost": 0,
		},
		"achievements": {},
		"tutorial": {},
	}


func stat(key: String):
	return data.stats.get(key, 0)


func add_stat(key: String, n := 1) -> void:
	data.stats[key] = int(data.stats.get(key, 0)) + n


func max_stat(key: String, v: int) -> void:
	data.stats[key] = maxi(int(data.stats.get(key, 0)), v)


func path_for(s: int) -> String:
	return "%ssave_%d.json" % [dir, s]


func exists(s: int) -> bool:
	return FileAccess.file_exists(path_for(s))


## for the title screen's slot list: {} if empty
func peek(s: int) -> Dictionary:
	if not exists(s):
		return {}
	var f := FileAccess.open(path_for(s), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func delete_slot(s: int) -> void:
	if exists(s):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(s)))


func _last_slot() -> int:
	var cf := ConfigFile.new()
	if cf.load(dir + "save_meta.cfg") == OK:
		return clampi(int(cf.get_value("save", "slot", 0)), 0, SLOTS - 1)
	return 0


func _remember_slot() -> void:
	var cf := ConfigFile.new()
	cf.set_value("save", "slot", slot)
	cf.save(dir + "save_meta.cfg")


# ---------------------------------------------------------------- save

## grab the live state from the running game into `data`
func capture() -> void:
	data.treats = Puzzles.treats_eaten
	data.solved = Puzzles.solved.duplicate()
	var p := local_cat()
	var sc := get_tree().current_scene
	if sc and sc.scene_file_path != "":
		data.scene = sc.scene_file_path
	if p:
		data.style = p.style
		if p.is_on_floor() and not get_tree().root.has_node("HubFade"):
			var g := p.global_position
			data.pos = [g.x, g.y, g.z]
			data.yaw = p.orb_yaw


func save_now() -> bool:
	if not enabled:
		return false
	capture()
	data.version = VERSION
	data.saved_at = Time.get_datetime_string_from_system()
	var tmp := path_for(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# write then swap, so a crash mid save never eats the old file
	var d := DirAccess.open(dir)
	if d == null or d.rename(tmp.get_file(), path_for(slot).get_file()) != OK:
		return false
	_remember_slot()
	last_save_ms = Time.get_ticks_msec()
	_badge_t = 1.6
	saved.emit(slot)
	return true


# ---------------------------------------------------------------- load

## read a slot into `data` and push its progress into the game. travel = also go to the saved level
func load_slot(s: int, travel := true) -> bool:
	var d := peek(s)
	if d.is_empty():
		return false
	slot = s
	data = _merge(fresh(), d)
	_remember_slot()
	Puzzles.treats_eaten = int(data.treats)
	Puzzles.solved = (data.solved as Dictionary).duplicate()
	if data.style != "":
		Engine.set_meta("cat_style", data.style)
	if data.pos is Array and data.pos.size() == 3:
		_pending_pos = [data.scene, Vector3(data.pos[0], data.pos[1], data.pos[2]), float(data.yaw)]
	else:
		_pending_pos = null
	loaded.emit(s)
	if travel:
		var sc := get_tree().current_scene
		if sc and sc.scene_file_path == data.scene:
			_restore_pos(local_cat())
		elif ResourceLoader.exists(data.scene):
			get_tree().paused = false
			Hub.travel(get_tree(), data.scene, "", data.style)
	return true


func continue_game() -> bool:
	return load_slot(slot, true)


## fresh progress in slot `s` (title screen new game). the old file is replaced on the first save
func new_game(s: int) -> void:
	slot = s
	data = fresh()
	_pending_pos = null
	Puzzles.treats_eaten = 0
	Puzzles.solved = {}
	if Engine.has_meta("cat_style"):
		Engine.remove_meta("cat_style")
	_remember_slot()
	if enabled:
		save_now()


## keys in the file win, missing keys (older saves) come from fresh()
func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	for k in over:
		if base.has(k) and base[k] is Dictionary and over[k] is Dictionary and k in ["stats"]:
			base[k] = _merge(base[k], over[k])
		else:
			base[k] = over[k]
	return base


# ---------------------------------------------------------------- live

func local_cat() -> CatPlayer:
	for p in get_tree().get_nodes_in_group("player"):
		if p is CatPlayer and (p as CatPlayer).bot.is_empty() and p.is_inside_tree():
			return p
	return null


func _on_node_added(n: Node) -> void:
	if n is CatPlayer:
		_cat_arrived.call_deferred(n)
	elif n is SoulsRat:
		(n as SoulsRat).killed.connect(func(_r): add_stat("rats"))


func _cat_arrived(p: CatPlayer) -> void:
	if not is_instance_valid(p) or not p.bot.is_empty():
		return
	_seen_player = p
	_seen_catches = p.catches
	_restore_pos(p)
	_pending_pos = null    # only ever for the first cat after a load (booting elsewhere drops it)
	if p.health and not p.health.died.is_connected(_on_died):
		p.health.died.connect(_on_died)


func _on_died(_left: int) -> void:
	add_stat("lives_lost")


func _restore_pos(p: CatPlayer) -> void:
	if p == null or _pending_pos == null:
		return
	var sc := get_tree().current_scene
	if sc == null or sc.scene_file_path != _pending_pos[0]:
		return
	p.global_position = _pending_pos[1] + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.orb_yaw = _pending_pos[2]
	p.yaw = _pending_pos[2]
	_pending_pos = null


func _process(dt: float) -> void:
	_badge_tick(dt)
	if get_tree().paused:
		return
	var sc := get_tree().current_scene
	var path := sc.scene_file_path if sc else ""
	if path != _last_scene:
		_last_scene = path
		if path != "":
			data.stats.levels[path] = int(data.stats.levels.get(path, 0)) + 1
		_scene_save_t = 2.0
		_scene_ms = Time.get_ticks_msec()
	data.play_s = float(data.play_s) + dt
	_track(sc)
	if not enabled:
		return
	# a moment after a scene change. wall clock: a level's first seconds can run at a few fps
	if _scene_save_t > 0.0 and Time.get_ticks_msec() - _scene_ms >= int(_scene_save_t * 1000.0):
		_scene_save_t = -1.0
		save_now()
	_t += dt
	if _t >= AUTOSAVE_S:
		_t = 0.0
		save_now()


var _solved_n := 0


func _track(sc: Node) -> void:
	var p := _seen_player as CatPlayer if is_instance_valid(_seen_player) else null
	if p:
		if p.catches > _seen_catches:
			add_stat("catches", p.catches - _seen_catches)
		_seen_catches = p.catches
	if sc:
		var w = sc.get("wave")
		if w is int:
			max_stat("best_wave", w + 1)
		var lap = sc.get("lap_s")
		if lap is float and TrailLevel.trail_len > 1.0:
			max_stat("trail_best_laps", int(floor(lap / TrailLevel.trail_len)))
	var n := 0
	for k in Puzzles.solved:
		n += int(Puzzles.solved[k])
	if n != _solved_n:
		_solved_n = n
		if enabled and n > 0:
			save_now.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and enabled:
		save_now()


# ---------------------------------------------------------------- "saved" badge

var _badge: Label
var _badge_t := 0.0


func _build_badge() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 80
	add_child(cl)
	_badge = Label.new()
	_badge.text = "saved"
	_badge.anchor_left = 1.0
	_badge.anchor_right = 1.0
	_badge.anchor_top = 1.0
	_badge.anchor_bottom = 1.0
	_badge.offset_left = -110
	_badge.offset_top = -44
	_badge.add_theme_font_size_override("font_size", 16)
	_badge.add_theme_color_override("font_color", Color(0.95, 0.78, 0.2))
	_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_badge.add_theme_constant_override("outline_size", 4)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.modulate.a = 0.0
	cl.add_child(_badge)


func _badge_tick(dt: float) -> void:
	if _badge == null:
		return
	_badge_t = maxf(_badge_t - dt, 0.0)
	_badge.modulate.a = clampf(_badge_t / 0.5, 0.0, 1.0)
