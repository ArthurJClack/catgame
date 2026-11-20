class_name CatDash
extends Node
## souls style dodge, done the way a cat actually does it. tap alt (or mouse4) on the ground:
##
##   wasd toward where the body faces -> DART: a low, flat bound. all four paws gather under the
##     body (~70 ms), the hind legs fire, the spine stretches out flat, forepaws land first and
##     the hind paws come through under them. ~1.7 m, more if you were already running
##   wasd off to the side          -> SIDE LEAP: the startled sideways spring. the body stays
##     square to the threat, head on it, and the cat springs a little higher than a dart
##   wasd behind the body          -> WHIRL: pivots round on the forepaws first (~110 ms), then darts
##   no wasd                       -> BACKSTEP: hops straight back, still facing the way it was
##
## the souls part: once you press it you're committed (no steering in the air, a short recovery
## after the landing), there's a window of i-frames from the push off (`iframes` > 0, see
## CatPlayer.is_invulnerable()), it costs stamina and needs some in the bar, and a press during
## the recovery / in the air is buffered so dodges chain.
##
## the wind up runs as its own little state inside CatPlayer._physics_process; after the push
## the normal air code flies it (leap_lock on), so a dart into a wall can still wall kick.

enum { IDLE, WIND, AIR }
enum Kind { DART, SIDE, WHIRL, BACK }

const WIND_T := 0.07          # gather: all four paws load up under the body
const WHIRL_T := 0.11         # turning round first takes a little longer
const DART_V := 5.0           # horizontal m/s off the push
const DART_UP := 1.25         # vertical m/s: ~0.26 s of air, flat
const DART_CARRY := 1.2       # already running: push adds this on top (capped)
const DART_CAP := 12.5
const SIDE_V := 4.0
const SIDE_UP := 1.9          # ~0.39 s: the sideways spring goes up more than along
const BACK_V := 3.0
const BACK_UP := 1.7
const IFRAMES := 0.34         # from the push off (souls roll is ~13 of 30 frames)
const IFRAMES_BACK := 0.2
const RECOVER := 0.16         # after landing: paws absorbing, no new inputs
const STICK := 0.24           # after landing: all four paws planted where they came down (like the pounce)
const BUFFER := 0.25

var player: Node3D            # CatPlayer (untyped to keep this file free of a cycle)
var state := IDLE
var kind := Kind.DART
var t := 0.0
var wind_t := WIND_T
var dir := Vector3.FORWARD    # world, flat
var target_yaw := 0.0
var iframes := 0.0
var recover := 0.0
var buffer := 0.0
var gather := 0.0             # 0..1 rig crouch while winding up
var count := 0                # for tests
var last_kind := ""
var last_push := Vector3.ZERO
var air_t := 0.0              # time since the push (rig pose progress)
var air_total := 0.3          # how long the traced flight lasts
var land_at := Vector3.INF    # where the capsule trace says the feet come down (tests)
var slide_d := 0.0            # how far the feet moved after touch down (tests: should be ~0)


func busy() -> bool:
	return state != IDLE or recover > 0.0


func winding() -> bool:
	return state == WIND


func kind_name(k: int) -> String:
	return ["dart", "side leap", "whirl", "backstep"][k]


## ticks the timers. call once per physics tick before anything reads them
func tick(dt: float) -> void:
	iframes = maxf(iframes - dt, 0.0)
	recover = maxf(recover - dt, 0.0)
	buffer = maxf(buffer - dt, 0.0)
	if state == AIR:
		air_t += dt
	if state != WIND:
		gather = move_toward(gather, 0.0, dt * 9.0)


func press() -> void:
	buffer = BUFFER


## try to start a buffered dodge. wish = camera relative wasd as a world direction (or zero)
func try_start(wish: Vector3, grounded: bool) -> bool:
	if buffer <= 0.0 or not grounded or state != IDLE or recover > 0.0:
		return false
	var p = player
	var back: bool = wish.length() < 0.1
	# locked on (cat_lock_on.gd): the dodge reads wasd relative to the target and the cat keeps
	# its face on it the whole way. s = backstep away from it, a/d = side leap round it
	var locked: bool = p.lock != null and p.lock.active()
	var k := Kind.BACK
	if locked and not back:
		var tf := Vector3(-sin(p.lock.yaw_to()), 0, -cos(p.lock.yaw_to()))
		var la := tf.signed_angle_to(wish, Vector3.UP)
		if absf(la) < 0.8:
			k = Kind.DART
		elif absf(la) < 2.3:
			k = Kind.SIDE
		else:
			k = Kind.BACK
	elif not back:
		var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		var a := fwd.signed_angle_to(wish, Vector3.UP)
		if absf(a) < 1.0:
			k = Kind.DART
		elif absf(a) < 2.25:
			k = Kind.SIDE
		else:
			k = Kind.WHIRL
	if not p.stamina.spend(CatStamina.BACKSTEP if k == Kind.BACK else CatStamina.DASH):
		buffer = 0.0
		p._event("too tired to dodge")
		return false
	buffer = 0.0
	kind = k
	state = WIND
	t = 0.0
	wind_t = WHIRL_T if k == Kind.WHIRL else WIND_T
	if back:
		dir = Vector3(sin(p.yaw), 0, cos(p.yaw))
	else:
		dir = wish.normalized()
	target_yaw = atan2(-dir.x, -dir.z) if k in [Kind.DART, Kind.WHIRL] else p.yaw
	if locked:
		target_yaw = p.lock.yaw_to()
	# planting all four: the camera sinks a touch with the body
	p.land_dip_v -= 0.35
	return true


## wind up (on the ground). the player moves + posts after this
func wind_step(dt: float) -> void:
	var p = player
	t += dt
	gather = clampf(t / wind_t, 0.0, 1.0)
	if not p.is_on_floor():
		# walked off something mid gather: just fall, the stamina is gone (committed)
		state = IDLE
		return
	# the paws dig in and stop the body dead while it loads
	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	var keep := 0.0
	if kind == Kind.DART:
		keep = hv.dot(dir)   # a dart out of a run keeps the run
	hv = hv.move_toward(dir * maxf(keep, 0.0), 40.0 * dt)
	p.velocity = Vector3(hv.x, minf(p.velocity.y, 0.0), hv.z)
	# whirl / dart: the forepaws pivot the body round while it gathers
	var dy := wrapf(target_yaw - p.yaw, -PI, PI)
	var rate := (absf(wrapf(target_yaw - p.yaw, -PI, PI)) + 0.3) / maxf(wind_t - t, dt)
	p.yaw += clampf(dy, -rate * dt, rate * dt)
	p.rotation.y = p.yaw
	if t >= wind_t:
		_push()


func _push() -> void:
	var p = player
	p.yaw = target_yaw if (kind in [Kind.DART, Kind.WHIRL] or (p.lock != null and p.lock.active())) else p.yaw
	p.rotation.y = p.yaw
	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	var v := Vector3.ZERO
	match kind:
		Kind.DART, Kind.WHIRL:
			var along := maxf(hv.dot(dir), 0.0)
			var spd := clampf(maxf(DART_V, along + DART_CARRY), DART_V, DART_CAP)
			v = dir * spd + Vector3.UP * DART_UP
		Kind.SIDE:
			# a sideways spring sheds most of the run
			v = dir * SIDE_V + hv * 0.3 + Vector3.UP * SIDE_UP
		Kind.BACK:
			v = dir * BACK_V + Vector3.UP * BACK_UP
	p.velocity = v
	last_push = v
	state = AIR
	air_t = 0.0
	# the flight is a plain projectile (leap_lock): trace the cat's own capsule along it, like the
	# pounce, so the paws reach for the exact spots they come down on and the landing sticks there
	var tr: Dictionary = p.combat._trace(p.global_position, v)
	air_total = maxf(float(tr.t), 0.1)
	p.land_stick = 0.0
	p.pounce_yaw = p.yaw
	if tr.land:
		land_at = tr.point
		p.pounce_land = tr.point
		p.set_spots(CatRig.pounce_paw_spots(tr.point, p.yaw))
	else:
		land_at = Vector3.INF
		p.pounce_land = Vector3.INF
		p._clear_spots()
	p.stick_armed = true
	iframes = IFRAMES_BACK if kind == Kind.BACK else IFRAMES
	gather = 0.0
	count += 1
	last_kind = kind_name(kind)
	p.leap_lock = true          # committed: no air steering
	p.jumped_this_air = true
	p.pounce_air = false
	p._hopped_now = true
	p.ground_time = 0.0
	p.cam.fov += 5.0
	if kind == Kind.SIDE:
		var side := 1.0 if p.global_transform.basis.x.dot(dir) > 0.0 else -1.0
		p.cam_roll -= side * 0.035
	p._event("%s (%.0f stamina left)" % [last_kind, p.stamina.value])


func on_land() -> void:
	if state == AIR:
		state = IDLE
		recover = RECOVER
		slide_d = 0.0


## climbing / clambering / mantling took over mid dodge
func cancel() -> void:
	if state != IDLE:
		state = IDLE
		gather = 0.0
