class_name CatSparHud
extends CanvasLayer
## play fight hud: two play meters at the top (yours left, theirs right), round pips under them,
## and a big word in the middle for round flow only (round n / play! / who took it). no hit words.

var spar: CatSpar
var _c: Control
var _shown := {"me": 0.0, "them": 0.0}


func _ready() -> void:
	layer = 6
	_c = Control.new()
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.anchor_right = 1.0
	_c.anchor_bottom = 1.0
	_c.draw.connect(_draw)
	add_child(_c)


func _process(dt: float) -> void:
	if spar == null:
		return
	_shown.me = move_toward(_shown.me, spar.meter(true), dt * 1.6)
	_shown.them = move_toward(_shown.them, spar.meter(false), dt * 1.6)
	_c.queue_redraw()


func _draw() -> void:
	if spar == null or not spar.in_match():
		if spar and spar.target() != null and spar.they_lock >= CatSpar.PAIR_KEEP:
			_text("waiting for them to lock on to you", Vector2(_c.size.x * 0.5, 64), 18, Color(1, 1, 1, 0.75))
		if spar and spar.banner != "" and spar.banner_t < 1.6:
			_text(spar.banner, _c.size * Vector2(0.5, 0.36), 40, Color(1, 1, 1, 1.0 - spar.banner_t / 1.6))
		return
	var w := minf(_c.size.x * 0.34, 420.0)
	var h := 14.0
	var cx := _c.size.x * 0.5
	var y := 26.0
	var gap := 18.0
	var me_col := Color(1.0, 0.82, 0.35)
	var them_col := Color(0.55, 0.8, 1.0)
	# frames
	_c.draw_rect(Rect2(cx - gap - w, y, w, h), Color(0, 0, 0, 0.45))
	_c.draw_rect(Rect2(cx + gap, y, w, h), Color(0, 0, 0, 0.45))
	# yours fills toward the middle from the left, theirs toward the middle from the right
	var mw: float = w * _shown.me
	var tw: float = w * _shown.them
	_c.draw_rect(Rect2(cx - gap - mw, y, mw, h), me_col)
	_c.draw_rect(Rect2(cx + gap, y, tw, h), them_col)
	_c.draw_rect(Rect2(cx - gap - w, y, w, h), Color(1, 1, 1, 0.5), false, 1.5)
	_c.draw_rect(Rect2(cx + gap, y, w, h), Color(1, 1, 1, 0.5), false, 1.5)
	# round pips
	for i in CatSpar.ROUNDS_TO_WIN:
		var on_me := i < spar.my_wins
		var on_them := i < spar.their_wins
		_c.draw_circle(Vector2(cx - gap - 10 - i * 18, y + h + 13), 5.5, me_col if on_me else Color(1, 1, 1, 0.25))
		_c.draw_circle(Vector2(cx + gap + 10 + i * 18, y + h + 13), 5.5, them_col if on_them else Color(1, 1, 1, 0.25))
	_text("you", Vector2(cx - gap - w + 22, y + h + 18), 15, me_col)
	var nm := "them"
	if spar.opp is RemoteCat and (spar.opp as RemoteCat).peer:
		nm = (spar.opp as RemoteCat).peer.name
	elif spar.opp and spar.opp.is_in_group("spar_dummy"):
		nm = "practice cat"
	_text(nm, Vector2(cx + gap + w - 40, y + h + 18), 15, them_col)
	if spar.banner != "" and spar.banner_t < 1.4:
		var a := 1.0 - clampf((spar.banner_t - 0.9) / 0.5, 0.0, 1.0)
		var sz := 44 if spar.banner == "play!" else 38
		_text(spar.banner, _c.size * Vector2(0.5, 0.34), sz, Color(1, 1, 1, a))


func _text(t: String, at: Vector2, size: int, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_c.draw_string_outline(f, at - Vector2(tw * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, col.a * 0.8))
	_c.draw_string(f, at - Vector2(tw * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
