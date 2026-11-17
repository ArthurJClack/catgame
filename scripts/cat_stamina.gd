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
const SWAT := 4.0
const RAKE := 3.0            # each rake of a held paw
const GRIP := 10.0           # rear up + two paw grab
const DASH := 22.0
const BACKSTEP := 15.0
# costs (per second, while doing it)
const GALLOP := 16.0
const CANTER := 4.0
const CLIMB := 6.0
const CLAW_DRAG := 4.0
const GRIP_HOLD := 9.0       # holding something down with both paws

var player: Node3D
var value := MAX
var winded := false
var infinite := false        # bots, cutscenes, tests that don't want it
var _delay := 0.0
var _drained_now := false
var spent_total := 0.0       # for tests
var _flash := 0.0            # red flash when you try something with an empty bar

# the bar itself is drawn by souls_hud.gd (health + stamina, top left)
var lag := MAX               # pale "damage trail" that catches up to value

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
	_update_lag(dt)



## for the hud: holds, then slides down to the real value (souls)
func _update_lag(dt: float) -> void:
	if value > lag:
		lag = value
	elif _delay < REGEN_DELAY - 0.35:
		lag = move_toward(lag, value, dt * 80.0)


func flash() -> float:
	return _flash
