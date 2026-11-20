class_name FreeClimb
extends RefCounted
## free climbing: once the claws are in, the cat goes any way along the surface, not just up.
## w/s = up / down the wall, a/d = sideways, diagonals work. it follows curved things (tree
## trunks, posts, rope) by re-reading the surface normal every tick, swings round outside
## corners (box trunks, fence posts, crates wrapped in fabric) and turns into inside corners
## (two walls meeting) without letting go. reaching the top still mantles / clambers.
##
## space while climbing:
##   holding a direction  = climb lunge: a quick hop along the wall that way (costs stamina)
##   nothing / s / looking away from the wall = kick off backwards (old leap off)
## run the bar dry and the claws give out (hands over to the claw drag slide when it exists).
##
## all the state lives on the player (climb_n, climb_face, climb_head, climb_lunge_*), this is
## just the step so cat_player.gd stays readable. the rig side (splayed grips, hanging body) is
## unchanged: the player turns the rig toward the climb heading and the grips re-plant.

const SIDE_SPEED := 0.85     # m/s sideways (real cats are slower across than up: ~0.7x)
const DOWN_SPEED := 0.6      # backing down, tail first
const REACH := 0.2           # how far past the body the "is there still wall" ray looks
const CORNER_IN := 0.72      # a side hit whose normal is this far off ours is a new face
const LUNGE_V := 2.3         # peak speed of a climb lunge
const LUNGE_T := 0.3
const LUNGE_COST := 14.0
const HEAD_MAX := 1.05       # rad the body turns toward sideways travel (~60 deg)
const CHEST := 0.12
const WRAP_PAUSE := 0.28     # s at an edge after swinging round one (paws re-plant on the new face)          # ray height above the feet

static var off := false      # tests / before-after: true = the old up-only climb


static func start(p, n: Vector3) -> void:
	p.climb_n = n
	p.climb_face = n
	p.climb_head = 0.0
	p.climb_lunge_t = 0.0
	p.climb_side = 0.0
	p.climb_wrap_t = 0.0


static func _flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length() > 0.01 else Vector3.ZERO


## the surface at height CHEST in front of the feet, {} if nothing grippable
static func _probe(p, feet: Vector3, n: Vector3) -> Dictionary:
	var c := feet + Vector3.UP * CHEST
	var hit: Dictionary = p._ray(c, c - n * (p.RADIUS + REACH))
	if hit.is_empty() or not p._is_climbable(hit.collider):
		return {}
	var hn := _flat(hit.normal)
	if hn == Vector3.ZERO:
		return {}
	hit.normal = hn
	return hit


static func _let_go(p, cool: float, ev: String) -> void:
	p.climbing = false
	p.climb_cool = cool
	p._event(ev)


static func step(p, dt: float, mv: Vector2, wish_dir: Vector3, jump_pressed: bool, want_crouch: bool) -> void:
	var n0: Vector3 = p.climb_n
	_step(p, dt, mv, wish_dir, jump_pressed, want_crouch)
	if not p.climbing:
		return
	# going round something: body faces the new face, and the view comes round with it by the
	# same angle (you keep looking at the trunk instead of the field behind it)
	var n1: Vector3 = p.climb_n
	var d := atan2(n0.cross(n1).y, n0.dot(n1))
	p.orb_yaw += d
	p.yaw = atan2(n1.x, n1.z)
	p.rotation.y = p.yaw


static func _step(p, dt: float, mv: Vector2, wish_dir: Vector3, jump_pressed: bool, want_crouch: bool) -> void:
	var n: Vector3 = p.climb_n
	var into := -n
	var feet: Vector3 = p.global_position
	var hit := _probe(p, feet, n)
	if hit.is_empty():
		# the surface went away under us (moved, or we came in at its very top)
		var up_ok: bool = p._try_ledge(into)
		p.climbing = false
		p.climb_cool = 0.3
		if not up_ok:
			p.velocity = Vector3.UP * 1.6 + into * 0.8
		return
	n = hit.normal
	p.climb_n = n
	into = -n

	if not p.stamina.infinite and p.stamina.is_empty():
		_let_go(p, 0.5, "claws give out")
		p.velocity = n * 0.4
		if p.has_method("start_wall_slide"):
			p.start_wall_slide(n)
		return

	var dir := mv
	if dir.length() > 1.0:
		dir = dir.normalized()
	var moving := dir.length() > 0.15
	var right := into.cross(Vector3.UP).normalized()

	if jump_pressed:
		var look_away := false
		if p.cam:
			look_away = _flat(-p.cam.global_transform.basis.z).dot(n) > 0.35
		if moving and dir.y > -0.3 and not look_away and p.stamina.spend(LUNGE_COST):
			# lunge along the wall: hinds bunch and fire, fore paws strike higher up / across
			p.climb_lunge_t = LUNGE_T
			p.climb_lunge_dir = (Vector3.UP * dir.y + right * dir.x).normalized()
			p._event("climb lunge")
		else:
			p.climbing = false
			p.climb_cool = 0.35
			p.velocity = n * p.KICK_OUT + Vector3.UP * p.KICK_UP * 0.8 + wish_dir * 0.8
			p.jumped_this_air = true
			p.kicks_left = maxi(p.kicks_left - 1, 0)
			p._event("leap off")
			return
	if want_crouch:
		_let_go(p, 0.4, "let go")
		p.velocity = n * 0.6
		return

	# speeds: up in bursts (the bound), across steadier, down slow
	var burst := 0.55 + 0.45 * maxf(0.0, sin(p.rig.phase * TAU + 0.6))
	var vy: float = (p.CLIMB_SPEED * burst if dir.y > 0.0 else DOWN_SPEED) * dir.y
	var vx := SIDE_SPEED * (0.75 + 0.25 * burst) * dir.x
	var v := Vector3.UP * vy + right * vx
	if p.climb_lunge_t > 0.0:
		var k: float = p.climb_lunge_t / LUNGE_T
		v += p.climb_lunge_dir * LUNGE_V * k * k
		p.climb_lunge_t = maxf(p.climb_lunge_t - dt, 0.0)
	p.climb_wrap_t = maxf(p.climb_wrap_t - dt, 0.0)
	var side := signf(v.dot(right)) if absf(v.dot(right)) > 0.05 else 0.0
	p.climb_side = side

	# inside corner: another grippable face right beside us in the travel direction -> turn onto it
	if side != 0.0:
		var c := feet + Vector3.UP * CHEST
		var sh: Dictionary = p._ray(c, c + right * side * (p.RADIUS + 0.07))
		if not sh.is_empty() and p._is_climbable(sh.collider):
			var sn := _flat(sh.normal)
			if sn != Vector3.ZERO and sn.dot(n) < CORNER_IN and sn.dot(right * side) < -0.3:
				p.climb_n = sn
				p._event("round the inside corner")
				# this tick just turns; next tick a/d means the same way round along the new face
				v = Vector3.UP * vy
				n = sn
				into = -n
				hit = sh

	# hug the surface, then move
	var dist: float = Vector2(hit.position.x - feet.x, hit.position.z - feet.z).dot(Vector2(into.x, into.z))
	v += into * clampf((dist - (p.RADIUS + 0.01)) * 12.0, -1.0, 1.0)
	p.velocity = v
	p.move_and_slide()

	# still on it? follow the curve (trunks, posts) or swing round the edge
	var feet2: Vector3 = p.global_position
	var h2 := _probe(p, feet2, n)
	if not h2.is_empty():
		p.climb_n = h2.normal
	elif side != 0.0 and p.climb_wrap_t <= 0.0 and _wrap_outside(p, feet2, n, right * side):
		p.climb_wrap_t = WRAP_PAUSE
		p._event("round the corner")
	elif vy > 0.05 and absf(vy) >= absf(vx):
		# ran out of wall going up: haul over the top if there is one
		p.global_position = feet2
		if p._try_ledge(into):
			p.climbing = false
			p.climb_cool = 0.3
			return
		p.global_position = feet
	else:
		# edge we can't get round (bottom of a branch, end of a thin board): stop at it
		p.global_position = feet

	if p.is_on_floor() and dir.y < 0.0:
		_let_go(p, 0.4, "down")
	elif p.is_on_ceiling() and dir.y > 0.0:
		# bumped into an overhang (a perch / platform): reach around the lip and haul up
		if p._try_lip(into):
			p.climbing = false

	# body turns toward where it's going across the wall (head first), back to head up idle
	var head := 0.0
	if moving and dir.y > -0.3:
		head = clampf(atan2(dir.x, maxf(dir.y, 0.2)), -HEAD_MAX, HEAD_MAX)
	p.climb_head = LowPoly.damp(p.climb_head, head, 5.0, dt)


## the face ended beside us. look back round the edge for the next face: from a point just
## past the old face plane, cast back against the travel direction. thin posts, box trunks,
## crate corners all wrap like this
static func _wrap_outside(p, feet: Vector3, n: Vector3, travel: Vector3) -> bool:
	var c := feet + Vector3.UP * CHEST
	for depth in [0.05, 0.12]:
		var o: Vector3 = c - n * (p.RADIUS + depth) + travel * 0.04
		var h: Dictionary = p._ray(o, o - travel * (p.RADIUS + 0.35))
		if h.is_empty() or not p._is_climbable(h.collider):
			continue
		var hn := _flat(h.normal)
		if hn == Vector3.ZERO or hn.dot(travel) < 0.3:
			continue
		var to: Vector3 = Vector3(h.position.x, feet.y, h.position.z) + hn * (p.RADIUS + 0.012)
		if not p._fits(to):
			continue
		p.global_position = to
		p.climb_n = hn
		return true
	return false
