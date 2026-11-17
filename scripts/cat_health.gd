class_name CatHealth
extends Node
## the cat's health, souls style: hits take a chunk (a pale trail shows what you just lost),
## a dodge's i-frames ignore them, a hit knocks the cat back and gives a short grace window.
## cats get nine lives: run out of health and you lose one, then `died` fires and the level
## puts you back (arena: at the start of the wave). nothing outside the arena hurts yet.

signal hurt(amount: float, from: Vector3)
signal died(lives_left: int)

const MAX := 100.0
const GRACE := 0.45           # after a hit: no second hit straight away (no stun lock)

var player: Node3D            # CatPlayer
var value := MAX
var lag := MAX                # damage trail for the hud
var lives := 9
var grace := 0.0
var flash := 0.0              # red flash on the hud / screen edge
var dead := false
var _lag_hold := 0.0
var hits_taken := 0           # for tests
var hits_dodged := 0


## something hit the cat. from = where the blow came from (world), knock = m/s shove.
## returns true if it landed (false = dodged through it, grace window, or already down)
func damage(amount: float, from: Vector3, knock := 2.2) -> bool:
	if dead or player == null:
		return false
	if player.is_invulnerable():
		hits_dodged += 1
		return false
	if grace > 0.0:
		return false
	value = maxf(value - amount, 0.0)
	grace = GRACE
	flash = 1.0
	_lag_hold = 0.6
	hits_taken += 1
	var p = player
	var away: Vector3 = p.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3(sin(p.yaw), 0, cos(p.yaw))
	p.velocity = away * knock + Vector3.UP * 1.1
	p.land_dip_v -= 0.6
	p.cam_roll += 0.05 * (1.0 if p.global_transform.basis.x.dot(away) > 0.0 else -1.0)
	p._hopped_now = true
	p.leap_lock = false
	if p.charging:
		p.charging = false
		p.charge = 0.0
	hurt.emit(amount, from)
	p._event("ouch! (%.0f)" % value)
	if value <= 0.0:
		dead = true
		lives -= 1
		p._event("lost a life · %d left" % lives)
		died.emit(lives)
	return true


func heal_full() -> void:
	value = MAX
	lag = MAX
	dead = false


func physics_tick(dt: float) -> void:
	grace = maxf(grace - dt, 0.0)
	flash = maxf(flash - dt * 1.8, 0.0)
	if value > lag:
		lag = value
	elif _lag_hold > 0.0:
		_lag_hold -= dt
	else:
		lag = move_toward(lag, value, dt * 60.0)
