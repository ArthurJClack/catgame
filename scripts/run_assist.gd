class_name RunAssist
extends RefCounted
## running over rough ground, kept out of cat_player.gd so the controller only calls one hook.
##
## step_up(): small stuff in the way (roots, branches, stone lips, up to STEP_MAX) the body glides up
##   over while the planted paws step onto it, like stairs in a shooter. the eye smoothing in
##   CatPlayer._post already turns the pop into a glide. anything up to CatPlayer.STEP_MOUNT (~chest
##   height) the cat steps up onto with its paws (the quick mantle in cat_player.gd). the cat never
##   jumps by itself: logs, big rocks and ditches need the jump key.

const STEP_MAX := 0.11          # glide up this much without leaving the ground
## CatPlayer.smooth_steps: everything up to chest height (CatPlayer.STEP_MOUNT) is taken this way,
## in stride, and the rig carries the body up over it behind its paws (no stop + scripted hop).
## going down the same: off a kerb or down a stair the capsule follows the ground instead of
## falling for a few frames, so the cat walks down instead of doing a little jump per step


static func _lim(_p: CharacterBody3D) -> float:
	return STEP_MAX


# ------------------------------------------------------------------ step up
static func step_up(p: CharacterBody3D, hv: Vector3, dt: float) -> bool:
	var spd := hv.length()
	if spd < 0.15:
		return false
	var dir := hv / spd
	var probe := dir * maxf(spd * dt, 0.025)
	var xf := p.global_transform
	var col := KinematicCollision3D.new()
	if not p.test_move(xf, probe, col, 0.001):
		return false
	if col.get_normal().y > 0.72:
		return false   # just a slope, move_and_slide walks it
	var lim := _lim(p)
	if p.test_move(xf, Vector3.UP * lim, null, 0.001):
		# no head room for the tall version: try the low one (a root under a shelf)
		if lim <= STEP_MAX or p.test_move(xf, Vector3.UP * STEP_MAX, null, 0.001):
			return false
		lim = STEP_MAX
	var up := Transform3D(xf.basis, xf.origin + Vector3.UP * lim)
	if p.test_move(up, probe, null, 0.001):
		return false   # still blocked higher up: a real wall / ledge
	var over := Transform3D(xf.basis, up.origin + probe)
	var down := KinematicCollision3D.new()
	if not p.test_move(over, Vector3.DOWN * (lim + 0.03), down, 0.001):
		return false   # nothing to stand on past the lip
	if down.get_normal().y < 0.65:
		return false
	var rise := over.origin.y + down.get_travel().y - xf.origin.y
	if rise < 0.004 or rise > lim:
		return false
	p.global_position.y += rise + 0.002
	return true


# ------------------------------------------------------------------ step onto
## smooth_steps version of step_up. blocked by something up to chest height with a flat top: put
## the capsule on top of it, just far enough in to stand there, and return how far forward that
## was (world, flat). the caller holds the capsule there while the visible cat walks the gap at
## its own pace (CatPlayer._soft_off), so nothing stops and nothing jumps. ZERO = nothing done
## or handled the old way (round rocks, lumps: step_up)
static func step_onto(p: CharacterBody3D, hv: Vector3, dt: float) -> Vector3:
	var spd := hv.length()
	# (stopped dead against a low rock the speed never builds: pushing at all is enough)
	if spd < 0.04:
		return Vector3.ZERO
	var dir := hv / spd
	var hv_up := dir * maxf(spd, 0.16)
	var probe := dir * maxf(spd * dt, 0.025)
	var xf := p.global_transform
	var col := KinematicCollision3D.new()
	if not p.test_move(xf, probe, col, 0.001):
		return Vector3.ZERO
	if col.get_normal().y > 0.72:
		return Vector3.ZERO
	# loose props (a lantern, a bag, a ball) get pushed or swatted, not climbed onto like a step
	if col.get_collider() is RigidBody3D:
		return Vector3.ZERO
	var lim := CatPlayer.STEP_MOUNT
	if p.test_move(xf, Vector3.UP * lim, null, 0.001):
		step_up(p, hv_up, dt)
		return Vector3.ZERO
	var up := Transform3D(xf.basis, xf.origin + Vector3.UP * lim)
	# the round bottom of the capsule only stands on the top once its middle is past the edge
	var reach := col.get_travel().length() + CatPlayer.RADIUS + 0.012
	var fcol := KinematicCollision3D.new()
	if p.test_move(up, dir * reach, fcol, 0.001):
		reach = fcol.get_travel().length() - 0.004   # something behind the lip: as far in as there's room
		if reach < probe.length():
			step_up(p, hv_up, dt)
			return Vector3.ZERO
	for k in 5:
		var s := lerpf(reach, probe.length(), k / 4.0) if k < 4 else reach
		if k == 4:
			break
		var over := Transform3D(xf.basis, up.origin + dir * s)
		var down := KinematicCollision3D.new()
		if not p.test_move(over, Vector3.DOWN * (lim + 0.03), down, 0.001):
			continue
		var rise := over.origin.y + down.get_travel().y - xf.origin.y
		if down.get_normal().y < 0.93 or rise < 0.004 or rise > lim or down.get_collider() is RigidBody3D:
			continue
		# the nearest spot that still stands flat: try closer ones only while they do
		var best_s := s
		var best_rise := rise
		for j in range(k + 1, 4):
			var s2 := lerpf(reach, probe.length(), j / 4.0)
			var o2 := Transform3D(xf.basis, up.origin + dir * s2)
			var d2 := KinematicCollision3D.new()
			if not p.test_move(o2, Vector3.DOWN * (lim + 0.03), d2, 0.001) or d2.get_normal().y < 0.93:
				break
			var r2 := o2.origin.y + d2.get_travel().y - xf.origin.y
			if absf(r2 - rise) > 0.01:
				break
			best_s = s2
			best_rise = r2
		p.global_position += dir * best_s + Vector3.UP * (best_rise + 0.002)
		return dir * best_s
	# no flat top in reach (a rock, a root, a log): the old glide handles what it can
	step_up(p, hv_up, dt)
	return Vector3.ZERO


# ------------------------------------------------------------------ step down
## call right after move_and_slide. was on the floor, didn't jump, and is now coming off the
## edge of something no higher than a step (a stair, a kerb, the back of a low box): put the
## capsule down on the ground below, clear of the edge, instead of letting it roll off the
## corner and fall for a few frames. returns [done, forward skip (world, flat)]
static func step_down(p: CharacterBody3D, was_grounded: bool, hv: Vector3) -> Array:
	if not CatPlayer.smooth_steps or not was_grounded or p.velocity.y > 0.01:
		return [false, Vector3.ZERO]
	var spd := hv.length()
	var dir := hv / spd if spd > 0.15 else Vector3.ZERO
	if p.is_on_floor():
		# still touching: only when it's tipping forward over a corner
		if dir == Vector3.ZERO or p.get_floor_normal().y > 0.93 or p.get_floor_normal().dot(dir) < 0.2:
			return [false, Vector3.ZERO]
	var xf := p.global_transform
	var lim := CatPlayer.STEP_MOUNT
	for s in [0.0, CatPlayer.RADIUS * 0.5, CatPlayer.RADIUS + 0.015]:
		var sv: Vector3 = dir * float(s)
		if s > 0.0 and (dir == Vector3.ZERO or p.test_move(xf, sv, null, 0.001)):
			break
		var from := Transform3D(xf.basis, xf.origin + sv)
		var col := KinematicCollision3D.new()
		if not p.test_move(from, Vector3.DOWN * (lim + 0.02), col, 0.001):
			continue
		var drop := -col.get_travel().y
		if col.get_normal().y < 0.93:
			continue
		if p.is_on_floor() and drop < 0.04:
			continue
		p.global_position = from.origin + col.get_travel()
		p.velocity.y = 0.0
		p.apply_floor_snap()
		return [true, sv]
	return [false, Vector3.ZERO]
