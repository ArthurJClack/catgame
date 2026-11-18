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
	if p.test_move(xf, Vector3.UP * STEP_MAX, null, 0.001):
		return false   # no head room
	var up := Transform3D(xf.basis, xf.origin + Vector3.UP * STEP_MAX)
	if p.test_move(up, probe, null, 0.001):
		return false   # still blocked higher up: a real wall / ledge
	var over := Transform3D(xf.basis, up.origin + probe)
	var down := KinematicCollision3D.new()
	if not p.test_move(over, Vector3.DOWN * (STEP_MAX + 0.03), down, 0.001):
		return false   # nothing to stand on past the lip
	if down.get_normal().y < 0.65:
		return false
	var rise := over.origin.y + down.get_travel().y - xf.origin.y
	if rise < 0.004 or rise > STEP_MAX:
		return false
	p.global_position.y += rise + 0.002
	return true
