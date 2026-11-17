class_name CatStamina
extends Node
## souls style stamina for the player cat. everything athletic costs some: a burst (hop,
## pounce, wall kick, dash) takes a chunk, holding a canter / gallop or climbing drains it
## while you do it. it only comes back after a short breather, and if you run it right out the
## cat is winded: no canter or gallop until it's back over WINDED_UNTIL.
##
## real cats are sprinters, not distance runners: a flat out gallop lasts a few seconds, then
## they have to stop and pant. so the gallop empties a full bar in ~6 s, a canter in ~25 s.
##
## the rule for bursts is the souls one: you can start anything as long as the bar isn't empty,
## even if it costs more than is left (the bar just goes to 0). a hop never fails (a cat always
## gets off the ground), it's just lower when you're spent.

const MAX := 100.0
const REGEN := 34.0          # per second, once the breather is over
const REGEN_DELAY := 0.75    # seconds after the last spend before it starts coming back
const WINDED_UNTIL := 35.0   # run dry and you can't canter / gallop until it's back to this

# costs (one off)
const HOP := 7.0
const POUNCE := 8.0          # + POUNCE_CHARGE * charge
const POUNCE_CHARGE := 12.0
const LEAP := 12.0
const SIDE_HOP := 4.0
const WALL_KICK := 12.0
const SCRAMBLE := 8.0
const CLAMBER := 8.0
const SWAT := 2.0
const DASH := 22.0
const BACKSTEP := 15.0
# costs (per second, while doing it)
const GALLOP := 16.0
const CANTER := 4.0
const CLIMB := 6.0
const CLAW_DRAG := 4.0

var player: Node3D
var value := MAX
var winded := false
var infinite := false        # bots, cutscenes, tests that don't want it
var _delay := 0.0
var _drained_now := false
var spent_total := 0.0       # for tests
var _flash := 0.0            # red flash when you try something with an empty bar

# hud
var layer: CanvasLayer
var _root: Control
var _back: ColorRect
var _lag: ColorRect          # the souls "damage trail": a pale bar that catches up to the real one
var _fill: ColorRect
var _lag_v := MAX
var _vis := 0.0
var show_bar := true
const BAR_W := 240.0
const BAR_H := 7.0


func _ready() -> void:
	_build_hud()


func ratio() -> float:
	return value / MAX


func is_empty() -> bool:
	return value <= 0.0


## one off cost. returns false (and spends nothing) when the bar is empty
func spend(amount: float) -> bool:
	if infinite:
		return true
	if value <= 0.0:
		_flash = 1.0
		return false
	value = maxf(value - amount, 0.0)
	spent_total += amount
	_delay = REGEN_DELAY
	if value <= 0.0:
		winded = true
	return true


## held cost (call every physics tick you're doing it)
func drain(rate: float, dt: float) -> void:
	if infinite:
		return
	_drained_now = true
	var a := minf(rate * dt, value)
	value -= a
	spent_total += a
	_delay = REGEN_DELAY
	if value <= 0.0:
		value = 0.0
		winded = true


## can the cat canter / gallop right now?
func can_run() -> bool:
	return infinite or (not winded and value > 0.0)


func physics_tick(dt: float, still: bool) -> void:
	if infinite:
		value = MAX
		winded = false
	if _drained_now:
		_drained_now = false
	elif _delay > 0.0:
		_delay -= dt
	else:
		# standing still you get your breath back quicker
		value = minf(value + REGEN * (1.35 if still else 1.0) * dt, MAX)
	if winded and value >= WINDED_UNTIL:
		winded = false
	_flash = maxf(_flash - dt * 2.5, 0.0)
	_update_hud(dt)


func _build_hud() -> void:
	layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.anchor_left = 0.5
	_root.anchor_right = 0.5
	_root.anchor_top = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -BAR_W * 0.5
	_root.offset_right = BAR_W * 0.5
	_root.offset_top = -46
	_root.offset_bottom = -46 + BAR_H
	layer.add_child(_root)
	_back = _rect(Color(0.05, 0.05, 0.04, 0.6), -2)
	_lag = _rect(Color(0.95, 0.9, 0.6, 0.85), 0)
	_fill = _rect(Color(0.36, 0.78, 0.36), 0)


func _rect(c: Color, pad: float) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never under the crosshair, but keep it safe
	r.color = c
	r.position = Vector2(pad, pad)
	r.size = Vector2(BAR_W - pad * 2.0, BAR_H - pad * 2.0)
	_root.add_child(r)
	return r


func _update_hud(dt: float) -> void:
	if _root == null:
		return
	# full and resting: fade out. anything else: show it
	var want := 1.0 if (value < MAX - 0.01 or _flash > 0.0) else 0.0
	_vis = move_toward(_vis, want, dt * (6.0 if want > _vis else 1.2))
	_root.visible = show_bar and _vis > 0.01
	_root.modulate.a = _vis
	# the pale trail holds a moment then slides down to the real value
	if value > _lag_v:
		_lag_v = value
	elif _delay < REGEN_DELAY - 0.35:
		_lag_v = move_toward(_lag_v, value, dt * 80.0)
	_fill.size.x = BAR_W * value / MAX
	_lag.size.x = BAR_W * _lag_v / MAX
	var c := Color(0.36, 0.78, 0.36)
	if winded:
		c = Color(0.85, 0.62, 0.2).lerp(Color(0.95, 0.3, 0.2), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	c = c.lerp(Color(1, 0.2, 0.15), _flash)
	_fill.color = c
	_back.color = Color(0.05, 0.05, 0.04, 0.6).lerp(Color(0.6, 0.08, 0.05, 0.8), _flash)
