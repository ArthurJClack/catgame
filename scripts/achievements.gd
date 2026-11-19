class_name Achievements
extends CanvasLayer
## achievements: cat things worth a little card. checked twice a second from the save's stats +
## the live cat, unlocks are stored in the save (`Save.data.achievements`: id -> date), a card
## slides in top right with a chime, the pause menu lists them all (locked ones show what to do,
## secret ones stay "???"). lives under the Save autoload (save_game.gd adds it).
## `Achievements.unlocked` (signal on the node) is the hook for steam achievements later.
## test: xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/achievements_test.gd

signal unlocked(id: String)

## id: [title, how, secret]
const LIST := {
	"first_steps": ["first steps", "finish the tutorial", false],
	"knock_it_off": ["it was on the edge", "knock the treat bag off the kitchen cabinets", false],
	"sunbather": ["sunbather", "find the sunbeam up in the barn and sit in it", false],
	"gift": ["for you, human", "leave something you caught on the doormat", false],
	"lantern": ["oops", "knock a lantern off a pillar in the rat pit", false],
	"pull_string": ["tug of war", "pull the rope in the barn until something gives", false],
	"herd": ["sheepdog", "walk all five chicks back into their pen", false],
	"quiet_paws": ["let sleeping dogs lie", "eat the guard dog's dinner on pier 9 without waking it", false],
	"treats_10": ["snack time", "eat 10 treats", false],
	"treats_50": ["round boy", "eat 50 treats", false],
	"hunter": ["hunter", "catch something", false],
	"apex": ["apex predator", "catch 25 things", false],
	"ratter": ["ratter", "beat 10 rats", false],
	"exterminator": ["pest control", "beat 100 rats", false],
	"brute": ["the big one", "reach the last wave of the rat pit", false],
	"trail_lap": ["zoom zoom", "run a full lap of the trail", false],
	"explorer": ["outdoor cat", "visit every place", false],
	"zoomies": ["the zoomies", "hit a full gallop", false],
	"high_ground": ["high ground", "get 3 m up", false],
	"chatty": ["chatty", "meow 50 times", false],
	"loaf": ["loaf", "sit still for a whole minute", false],
	"nine_lives": ["eight to go", "lose a life", true],
	"friends": ["not alone", "play with another cat online", true],
}
const PLACES := ["res://main.tscn", "res://forest.tscn", "res://stealth.tscn", "res://trail.tscn", "res://arena.tscn"]

var save: Node
var _t := 0.0
var _still := 0.0
var _queue: Array[String] = []
var _card: PanelContainer
var _title: Label
var _how: Label
var _card_t := -1.0


func _ready() -> void:
	layer = 88
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func data() -> Dictionary:
	if save == null:
		return {}
	if not save.data.has("achievements") or not save.data.achievements is Dictionary:
		save.data.achievements = {}
	return save.data.achievements


func has(id: String) -> bool:
	return data().has(id)


func count() -> int:
	return data().size()


func unlock(id: String) -> bool:
	if not LIST.has(id) or has(id):
		return false
	data()[id] = Time.get_date_string_from_system()
	_queue.append(id)
	unlocked.emit(id)
	if save.enabled:
		save.save_now.call_deferred()
	return true


func _process(dt: float) -> void:
	_card_tick(dt)
	if save == null or get_tree().paused or not save.enabled:
		return     # (off with the save: tests, previews, the server)
	var p: CatPlayer = save.local_cat()
	if p and Vector2(p.velocity.x, p.velocity.z).length() < 0.1 and p.is_on_floor():
		_still += dt
	else:
		_still = 0.0
	_t += dt
	if _t < 0.5:
		return
	_t = 0.0
	check(p)


func check(p: CatPlayer) -> void:
	if not get_tree().get_nodes_in_group("title_screen").is_empty():
		return
	var st: Dictionary = save.data.get("stats", {})
	var solved: Dictionary = Puzzles.solved
	var treats: int = Puzzles.treats_eaten
	if save.data.get("tutorial", {}).get("done", false):
		unlock("first_steps")
	if solved.has("knock_it_off"): unlock("knock_it_off")
	if solved.has("perch_sunbeam"): unlock("sunbather")
	if solved.has("gift"): unlock("gift")
	if solved.has("lantern"): unlock("lantern")
	if solved.has("pull_string"): unlock("pull_string")
	if solved.has("herd"): unlock("herd")
	if solved.has("quiet_paws"): unlock("quiet_paws")
	if treats >= 10: unlock("treats_10")
	if treats >= 50: unlock("treats_50")
	var c := int(st.get("catches", 0))
	if c >= 1: unlock("hunter")
	if c >= 25: unlock("apex")
	var r := int(st.get("rats", 0))
	if r >= 10: unlock("ratter")
	if r >= 100: unlock("exterminator")
	if int(st.get("best_wave", 0)) >= 4: unlock("brute")
	if int(st.get("trail_best_laps", 0)) >= 1: unlock("trail_lap")
	var lv: Dictionary = st.get("levels", {})
	if PLACES.all(func(x): return lv.has(x)): unlock("explorer")
	if int(st.get("meows", 0)) >= 50: unlock("chatty")
	if int(st.get("lives_lost", 0)) >= 1: unlock("nine_lives")
	var net := get_node_or_null("/root/Net")
	if net and not net.peers.is_empty(): unlock("friends")
	if p:
		if Vector2(p.velocity.x, p.velocity.z).length() > 10.0: unlock("zoomies")
		if p.global_position.y > 3.0 and p.is_on_floor(): unlock("high_ground")
		if _still >= 60.0: unlock("loaf")


# ---------------------------------------------------------------- the card

func _build() -> void:
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.065, 0.08, 0.92)
	sb.border_color = Color(0.95, 0.78, 0.2, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_card.add_theme_stylebox_override("panel", sb)
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.offset_left = -360
	_card.offset_right = -20
	_card.offset_top = 70
	_card.visible = false
	add_child(_card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(h)
	var paw := PawIcon.new()
	paw.custom_minimum_size = Vector2(34, 34)
	paw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(paw)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top := Label.new()
	top.text = "achievement"
	top.add_theme_font_size_override("font_size", 12)
	top.add_theme_color_override("font_color", Color(0.95, 0.78, 0.2, 0.8))
	v.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	v.add_child(_title)
	_how = Label.new()
	_how.add_theme_font_size_override("font_size", 13)
	_how.add_theme_color_override("font_color", Color(0.7, 0.7, 0.74))
	v.add_child(_how)


func _card_tick(dt: float) -> void:
	if _card_t < 0.0:
		if _queue.is_empty():
			return
		var id: String = _queue.pop_front()
		_title.text = LIST[id][0]
		_how.text = LIST[id][1]
		_card_t = 0.0
		_card.visible = true
		CatSfx.ui("unlock")
	_card_t += dt
	var slide := clampf(_card_t / 0.25, 0.0, 1.0) * (1.0 - clampf((_card_t - 3.6) / 0.3, 0.0, 1.0))
	_card.modulate.a = slide
	_card.position.x = get_viewport().get_visible_rect().size.x - 360.0 + (1.0 - slide) * 80.0
	if _card_t > 4.0:
		_card_t = -1.0
		_card.visible = false


func showing() -> bool:
	return _card.visible


## a little paw print (the default font has no emoji)
class PawIcon extends Control:
	var col := Color(0.95, 0.78, 0.2)
	var lit := true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := col if lit else Color(0.6, 0.6, 0.64, 0.35)
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		draw_circle(o + Vector2(0.5, 0.66) * s, 0.2 * s, c)
		draw_circle(o + Vector2(0.38, 0.56) * s, 0.14 * s, c)
		draw_circle(o + Vector2(0.62, 0.56) * s, 0.14 * s, c)
		for t in [[0.18, 0.36], [0.38, 0.2], [0.62, 0.2], [0.82, 0.36]]:
			draw_circle(o + Vector2(t[0], t[1]) * s, 0.095 * s, c)
