class_name SoulsHud
extends CanvasLayer
## health (red) over stamina (green), top left, each with a pale trail that holds a moment
## then slides down to what you've really got left. the bars are as long as their maximum.
## a row of paw marks under them = lives left. hits flash the screen edge red.
## every Control here ignores the mouse (the captured cursor parks at screen centre).

const X := 22.0
const Y := 18.0
const PX_PER := 2.6          # pixels per point of max
const H_HP := 10.0
const H_ST := 7.0

var player: Node3D
var _hp_back: ColorRect
var _hp_lag: ColorRect
var _hp_fill: ColorRect
var _st_back: ColorRect
var _st_lag: ColorRect
var _st_fill: ColorRect
var _lives: Label
var _vignette: ColorRect
var show_lives := false


func _ready() -> void:
	layer = 4
	var w_hp := CatHealth.MAX * PX_PER
	var w_st := CatStamina.MAX * PX_PER
	_hp_back = _rect(Vector2(X - 2, Y - 2), Vector2(w_hp + 4, H_HP + 4), Color(0.04, 0.03, 0.03, 0.75))
	_hp_lag = _rect(Vector2(X, Y), Vector2(w_hp, H_HP), Color(0.92, 0.82, 0.55, 0.9))
	_hp_fill = _rect(Vector2(X, Y), Vector2(w_hp, H_HP), Color(0.62, 0.08, 0.06))
	var y2 := Y + H_HP + 7.0
	_st_back = _rect(Vector2(X - 2, y2 - 2), Vector2(w_st + 4, H_ST + 4), Color(0.04, 0.03, 0.03, 0.75))
	_st_lag = _rect(Vector2(X, y2), Vector2(w_st, H_ST), Color(0.92, 0.88, 0.6, 0.85))
	_st_fill = _rect(Vector2(X, y2), Vector2(w_st, H_ST), Color(0.28, 0.6, 0.26))
	_lives = Label.new()
	_lives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives.position = Vector2(X, y2 + H_ST + 6.0)
	_lives.add_theme_font_size_override("font_size", 15)
	_lives.add_theme_color_override("font_color", Color(0.9, 0.86, 0.78))
	_lives.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_lives.add_theme_constant_override("outline_size", 5)
	add_child(_lives)
	# red edge flash when hit
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.anchor_right = 1.0
	_vignette.anchor_bottom = 1.0
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amt = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float e = smoothstep(0.32, 0.72, length(d * vec2(1.0, 0.8)));
	COLOR = vec4(0.55, 0.0, 0.0, e * amt);
}"""
	sm.shader = sh
	_vignette.material = sm
	add_child(_vignette)
	move_child(_vignette, 0)


func _rect(pos: Vector2, size: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = pos
	r.size = size
	r.color = c
	add_child(r)
	return r


func _process(_dt: float) -> void:
	if player == null:
		return
	# scripted bots (preview videos) don't show it unless they play with the real bars
	visible = player.bot.is_empty() or player.bot.get("stamina", false)
	var h: CatHealth = player.health
	var s: CatStamina = player.stamina
	_hp_fill.size.x = h.value * PX_PER
	_hp_lag.size.x = h.lag * PX_PER
	_hp_back.color = Color(0.04, 0.03, 0.03, 0.75).lerp(Color(0.9, 0.2, 0.1, 0.9), h.flash * 0.6)
	_st_fill.size.x = s.value * PX_PER
	_st_lag.size.x = s.lag * PX_PER
	var c := Color(0.28, 0.6, 0.26)
	if s.winded:
		c = Color(0.62, 0.5, 0.16).lerp(Color(0.75, 0.28, 0.14), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	_st_fill.color = c.lerp(Color(1, 0.2, 0.15), s.flash())
	_st_back.color = Color(0.04, 0.03, 0.03, 0.75).lerp(Color(0.6, 0.08, 0.05, 0.85), s.flash())
	_lives.visible = show_lives
	_lives.text = "lives  " + "■ ".repeat(h.lives) + "□ ".repeat(maxi(9 - h.lives, 0))
	(_vignette.material as ShaderMaterial).set_shader_parameter("amt", h.flash * 0.85)
