class_name PawView
extends Node3D
## first person front legs. when `rig` is set these are copies of the full body cat's own
## forelegs (same meshes, same pose every frame: gait, swats, pounces, dodges, wall kicks,
## climbing...), lifted from where they really are (below and behind the eye, out of view)
## into view by one fixed shift. so what you see in first person is exactly what the body does.
## without a rig it falls back to its own procedural ik (the old viewmodel).

var fur := Color(0.86, 0.52, 0.24)
var pad := Color(0.93, 0.55, 0.6)
var fur_dark := Color(0.58, 0.30, 0.12)
var pattern := "tabby"
var socks := false
## mouse look velocity (rad/s) from the player, for viewmodel sway
var look_vel := Vector2.ZERO
var _sway := Vector3.ZERO
var sock_col := Color(0.96, 0.9, 0.8)

# driven by the player every frame
var phase := 0.0
var speed := 0.0
var gait_w := Vector3(1, 0, 0)
var on_floor := true
var vy := 0.0
var crouch := 0.0
var charge := 0.0
## front paw offsets from their rest spots, from the rig's footfall solver (CatRig.fp_foot)
var foot := [Vector3.ZERO, Vector3.ZERO]
var use_feet := false

var _t := 0.0
var _swat_t := -1.0
var _swat_i := 1                      # which paw swats (0 left, 1 right)
var _swat_target := Vector3(-0.07, -0.08, -0.29) # camera space strike point
var claw_on := false                  # right mouse: paw out with claws, hooked on something
var claw_i := 1
var claw_target := Vector3(0.0, -0.1, -0.3)  # camera space
var _kick_t := -1.0
var _kick_side := 1.0
var _mantle_t := -1.0
var scramble := 0.0
var climb := 0.0
var hang := 0.0
var hang_pull := 0.0
var scratch := 0.0
var claws_out := 0.0
var _pin_t := -1.0
var _land := 0.0

const SHOULDER := Vector3(0.062, -0.14, 0.03)
const LA := 0.125
const LB := 0.12

var _legs := []

## the full body cat whose forelegs you see (CatRig). null = old standalone viewmodel
var rig: Node3D
var mirror := true
## how the rig's real forelegs are moved into view. a cat's eyes sit ahead of and above its
## shoulders, so its own forelegs are mostly below / behind what it can see. one rigid
## transform fixes that without touching the animation: the legs are taken relative to the
## shoulders' rest spot (in the yaw-only eye frame, so camera dips and crouches still show),
## tipped forward by view_tilt, hung at view_origin, and scaled toward the eye by view_scale
## (scaling toward the eye doesn't change the picture, it only pulls them closer so they
## poke into walls less). every angle, timing and contact of the rig is kept
var view_tilt := 1.25
var view_origin := Vector3(0.0, -0.17, -0.05)
var view_scale := 0.6
## extra sideways gap per leg (each leg is moved as a whole, so it keeps its own exact pose).
## cats put their forepaws nearly on one line, which from the eye stacks both up on the crosshair
var view_spread := 0.03
## a raised paw is seen from behind rather than from above (see _leg_xform)
var raise_tilt := 0.35
var raise_push := Vector3(0.0, 0.0, -0.08)
var _raise := [0.0, 0.0]
var eye_height := 0.25      # player eye above the rig root at rest
## the body can face away from the camera (head turns first, s runs toward you): the legs
## follow the body's heading only this far (rad) so they stay on screen
var yaw_limit := 0.4
var _rest := Vector3.ZERO   # rest shoulder midpoint, eye frame
var _mir: Array = []        # [src, dup] pairs, every node under the copied leg parts
var _mir_rig: Node3D = null
var mirror_xform := Transform3D.IDENTITY  # rig local -> this node's local, last frame (tests)
var _targets := [Vector3(-0.055, -0.22, -0.15), Vector3(0.055, -0.22, -0.15)]


func _ready() -> void:
	# run after the rig has animated this frame (both live under the player)
	process_priority = 10
	var S := LowPoly.sphere(8, 6)
	var S_lo := LowPoly.sphere(6, 4)
	for i in 2:
		var leg := {}
		var low_col := sock_col if socks else fur
		leg.upper = LowPoly.part(self, _striped(0.031, 0.023, false), Color.WHITE)
		leg.lower = LowPoly.part(self, _striped(0.022, 0.018, true), Color.WHITE)
		leg.joint = LowPoly.part(self, LowPoly.box(), fur, Vector3.ZERO, Vector3.ONE * 0.036)
		var paw := Node3D.new()
		add_child(paw)
		LowPoly.part(paw, LowPoly.box(), low_col, Vector3(0, 0, -0.012), Vector3(0.046, 0.026, 0.05))
		# toes
		for k in 4:
			var x := (k - 1.5) * 0.011
			LowPoly.part(paw, LowPoly.box(), low_col, Vector3(x, -0.002, -0.04 + absf(k - 1.5) * 0.004), Vector3(0.0105, 0.016, 0.016))
		# toe beans + main pad (on the underside)
		for k in 4:
			var x := (k - 1.5) * 0.011
			LowPoly.part(paw, LowPoly.box(), pad, Vector3(x, -0.011, -0.038 + absf(k - 1.5) * 0.004), Vector3(0.007, 0.004, 0.007))
		LowPoly.part(paw, LowPoly.box(), pad, Vector3(0, -0.014, -0.012), Vector3(0.022, 0.004, 0.016))
		# claws (only out when swatting / scrambling)
		var claws := Node3D.new()
		paw.add_child(claws)
		for k in 4:
			var x := (k - 1.5) * 0.011
			LowPoly.part(claws, LowPoly.cone(4), Color(0.97, 0.95, 0.9), Vector3(x, -0.004, -0.05 + absf(k - 1.5) * 0.004), Vector3(0.004, 0.014, 0.004), Vector3(-PI / 2 - 0.4, 0, 0))
		claws.visible = false
		leg.paw = paw
		leg.claws = claws
		_legs.append(leg)
	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _striped(top_r: float, bot_r: float, low: bool) -> ArrayMesh:
	var key := "vm_%s_%s_%s_%s_%.3f_%.3f_%s" % [pattern, fur.to_html(), fur_dark.to_html(), socks, top_r, bot_r, low]
	var me := self
	var painter := func(c: Vector3, n: Vector3) -> Color:
		var col: Color = me.fur
		# stripes wrap the outside of the leg, inside stays plain
		if me.pattern == "tabby" and sin(c.y * TAU * 3.0 + n.x * 0.8) > 0.3 and n.z > -0.4:
			col = me.fur_dark.lerp(me.fur, 0.2)
		if low and me.socks and c.y < 0.0:
			col = me.sock_col
		return col.darkened(clampf(-n.y * 0.1, 0.0, 0.1))
	return LowPoly.painted(LowPoly.cyl_src(top_r, bot_r, 4, 6), painter, key)


## side: 0 left paw, 1 right paw. target: camera space point to hit (null = straight ahead)
func swat(paw := 1, target = null) -> void:
	if _swat_t < 0.0 or _swat_t > 0.22:
		_swat_t = 0.0
		_swat_i = paw
		var sd := -1.0 if paw == 0 else 1.0
		var tp: Vector3 = target if target != null else Vector3(-sd * 0.07, -0.08, -0.29)
		# a forepaw can only reach so far from its shoulder
		var sh := Vector3(SHOULDER.x * sd, SHOULDER.y, SHOULDER.z)
		_swat_target = sh + (tp - sh).limit_length(LA + LB - 0.02)


func is_swatting() -> bool:
	return _swat_t >= 0.0 and _swat_t < 0.3


func kick(side: float) -> void:
	_kick_t = 0.0
	_kick_side = side


func mantle() -> void:
	_mantle_t = 0.0


func pin() -> void:
	_pin_t = 0.0


func land(impact: float) -> void:
	_land = clampf(impact * 0.012, 0.0, 0.06)


func _mirror_on() -> bool:
	if not mirror or rig == null or not is_instance_valid(rig) or not rig.get("_built"):
		return false
	if _mir_rig != rig:
		_build_mirror()
	return true


func _build_mirror() -> void:
	for pr in _mir:
		if pr[1].get_parent() == self:
			pr[1].queue_free()
	_mir.clear()
	_mir_rig = rig
	var st: Dictionary = rig.get("S_")
	_rest = Vector3(0.0, float(rig.get("BODY_H")) - 0.018 - eye_height, -0.125 * float(st.get("len", 1.0)))
	var legs: Array = rig.get("legs")
	for i in 2:
		var leg: Dictionary = legs[i]
		for key in ["upper", "lower", "pastern", "wrist", "joint", "paw"]:
			if not leg.has(key):
				continue
			var src: Node3D = leg[key]
			var dup: Node3D = src.duplicate()
			dup.set_meta("leg", i)
			add_child(dup)
			_pair(src, dup)
	for c in find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for leg in _legs:
		for key in ["upper", "lower", "joint", "paw"]:
			(leg[key] as Node3D).visible = false


func _pair(src: Node, dup: Node) -> void:
	if src is Node3D:
		_mir.append([src, dup])
	for k in mini(src.get_child_count(), dup.get_child_count()):
		_pair(src.get_child(k), dup.get_child(k))


## rig local space -> the eye frame, body yaw clamped (the shared part of both legs' transforms)
func _body_xform() -> Transform3D:
	var anchor := get_parent() as Node3D
	var local := anchor.global_transform.affine_inverse() * rig.global_transform
	# yaw of the body (player), not the rig root: the rig tips onto walls when climbing
	var body := rig.get_parent() as Node3D
	var bz := anchor.global_transform.basis.inverse() * body.global_transform.basis.z
	if Vector2(bz.x, bz.z).length() > 0.3:
		var rel := atan2(bz.x, bz.z)
		var excess := rel - clampf(rel, -yaw_limit, yaw_limit)
		local = Transform3D(Basis(Vector3.UP, -excess), Vector3.ZERO) * local
	return Transform3D(Basis.IDENTITY, -_rest) * local


## one leg's view transform. a paw on the ground is seen from high up (view_tilt), a paw
## raised up off the ground (swat, reaching up a wall, rearing) gets seen from behind instead
## (raise_tilt), otherwise the tip would swing a raised paw straight into your face.
## the whole leg moves as one piece, so its pose is still exactly the rig's
func _leg_xform(body: Transform3D, i: int, raise: float) -> Transform3D:
	var tilt := lerpf(view_tilt, raise_tilt, raise)
	var org := view_origin + raise_push * raise
	org.x += view_spread * (-1.0 if i == 0 else 1.0)
	var v := Transform3D(Basis(Vector3.RIGHT, tilt).scaled(Vector3.ONE * view_scale), org * view_scale)
	return v * body


func _mirror_step() -> void:
	var body := _body_xform()
	var legs: Array = rig.get("legs")
	var xf: Array[Transform3D] = []
	for i in 2:
		var paw: Node3D = legs[i].paw
		var h := paw.position.y - 0.012
		_raise[i] = smoothstep(0.03, 0.15, h)
		xf.append(_leg_xform(body, i, _raise[i]))
	mirror_xform = xf[1]
	for pr in _mir:
		var src: Node3D = pr[0]
		var dup: Node3D = pr[1]
		dup.visible = src.visible
		if dup.get_parent() == self:
			dup.transform = xf[int(dup.get_meta("leg"))] * src.transform
		else:
			dup.transform = src.transform


func _process(dt: float) -> void:
	_t += dt
	if _swat_t >= 0.0:
		_swat_t += dt
		if _swat_t > 0.32:
			_swat_t = -1.0
	if _kick_t >= 0.0:
		_kick_t += dt
		if _kick_t > 0.28:
			_kick_t = -1.0
	if _mantle_t >= 0.0:
		_mantle_t += dt
		if _mantle_t > 0.35:
			_mantle_t = -1.0
	_land = LowPoly.damp(_land, 0.0, 6.0, dt)
	if _pin_t >= 0.0:
		_pin_t += dt
		if _pin_t > 0.9:
			_pin_t = -1.0
	if _mirror_on():
		var sway_m := Vector3(clampf(-look_vel.x * 0.0025, -0.015, 0.015), clampf(look_vel.y * 0.002, -0.01, 0.01), 0)
		_sway = LowPoly.damp3(_sway, sway_m, 10.0, dt)
		position = _sway
		rotation.z = _sway.x * 1.0
		_mirror_step()
		return

	# sway: paws lag behind mouse movement a touch
	var sway_t := Vector3(clampf(-look_vel.x * 0.0025, -0.015, 0.015), clampf(look_vel.y * 0.002, -0.01, 0.01), 0)
	_sway = LowPoly.damp3(_sway, sway_t, 10.0, dt)
	position = _sway
	rotation.z = _sway.x * 1.0
	var move := clampf(speed / 2.5, 0.0, 1.0)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# --- ground: the paws follow the rig's real front paws (cat_gait.gd), so a planted
		# paw stays put on the floor while you travel over it, then peels off and swings ahead.
		# positions are squeezed a little so they stay in view and match the floor's speed on screen
		var base := Vector3(side * 0.066, -0.168 - crouch * 0.01 - _land, -0.21)
		var tgt := base
		if use_feet:
			var f: Vector3 = foot[i]
			tgt.x += clampf(f.x, -0.05, 0.05) * 0.6
			tgt.z += clampf(f.z * 0.76, -0.11, 0.1)
			tgt.y += clampf(f.y, -0.02, 0.1) * 1.3
		else:
			var off := 0.0 if i == 0 else lerpf(0.5, 0.1, gait_w.z)
			var q := fposmod(phase - off, 1.0)
			var duty := lerpf(0.55, 0.38, gait_w.z)
			var reach := lerpf(0.06, 0.11, gait_w.z) * move
			var lift := lerpf(0.05, 0.095, gait_w.z) * move
			if q < duty:
				var s := q / duty
				tgt.z += lerpf(-reach, reach * 0.9, s)
				tgt.y -= sin(PI * s) * 0.01 * move
			else:
				var s := (q - duty) / (1.0 - duty)
				var e := s * s * (3.0 - 2.0 * s)
				tgt.z += lerpf(reach * 0.9, -reach * 1.25, e)
				tgt.y += sin(PI * s) * lift
		# idle breathing + stalking creep
		tgt.y += sin(_t * 2.4 + side) * 0.002
		tgt.y += crouch * 0.015
		# pounce wind-up: paws tense, pulled back
		tgt = tgt.lerp(Vector3(side * 0.07, -0.21, -0.12), charge * 0.7)

		# --- air ---
		if not on_floor:
			var rise := clampf(vy / 3.5 * 0.5 + 0.5, 0.0, 1.0)
			var up_pose := Vector3(side * 0.05, -0.1, -0.24)
			var down_pose := Vector3(side * 0.07, -0.17, -0.25)
			var air := down_pose.lerp(up_pose, rise)
			tgt = air
		# --- scramble up a wall ---
		if scramble > 0.0:
			var claw := Vector3(side * 0.06, -0.05 + 0.05 * sin(_t * 16.0 + side * 1.5), -0.2)
			tgt = tgt.lerp(claw, scramble)
		# --- wall kick: one paw slaps the wall ---
		if _kick_t >= 0.0 and side == _kick_side:
			var k := sin(clampf(_kick_t / 0.28, 0.0, 1.0) * PI)
			tgt = tgt.lerp(Vector3(side * 0.13, -0.06, -0.19), k)
		# --- mantle: both paws hook the ledge and pull ---
		if _mantle_t >= 0.0:
			var m := _mantle_t / 0.35
			var grab := Vector3(side * 0.07, -0.03, -0.24)
			var pull := Vector3(side * 0.07, -0.2, -0.13)
			var mt := grab.lerp(pull, clampf((m - 0.25) / 0.75, 0.0, 1.0))
			tgt = tgt.lerp(mt, sin(clampf(m, 0.0, 1.0) * PI * 0.5 + 0.3))
		# --- climbing: both paws reach up the surface together (half bound) ---
		if climb > 0.0:
			var cq := sin(phase * TAU + (0.0 if i == 0 else 0.35))
			var ct := Vector3(side * 0.075, -0.07 + 0.075 * cq, -0.17 + 0.02 * cq)
			tgt = tgt.lerp(ct, climb)
		# --- hanging off a ledge: paws hooked over the top, then pull down past you ---
		if hang > 0.0:
			var hg := Vector3(side * 0.08, -0.12, -0.2)
			var hp := Vector3(side * 0.075, -0.22, -0.1)
			var ht := hg.lerp(hp, smoothstep(0.1, 0.8, hang_pull))
			ht.y += sin(_t * 9.0 + side) * 0.004 * (1.0 - hang_pull)
			tgt = tgt.lerp(ht, hang)
		# --- scratching: alternate rakes down the surface ---
		if scratch > 0.0:
			var sp := fposmod(_t * 1.75 + (0.0 if i == 0 else 0.5), 1.0)
			var st: Vector3
			if sp < 0.62:
				var u := sp / 0.62
				st = Vector3(side * 0.06, lerpf(0.0, -0.17, u * u * (3.0 - 2.0 * u)), -0.15)
			else:
				var u := (sp - 0.62) / 0.38
				st = Vector3(side * 0.065, lerpf(-0.17, 0.0, u * u * (3.0 - 2.0 * u)), -0.12)
			tgt = tgt.lerp(st, scratch)
		# --- pounce landing: both paws slam down together in front of your face ---
		if _pin_t >= 0.0:
			var k := smoothstep(0.0, 0.08, _pin_t) * (1.0 - smoothstep(0.55, 0.9, _pin_t))
			tgt = tgt.lerp(Vector3(side * 0.035, -0.2, -0.26), k)
		# --- swat: one paw winds out to its own side, then whips across at the target ---
		var swatting := i == _swat_i and _swat_t >= 0.0
		if swatting:
			var s := _swat_t
			var wind := Vector3(side * 0.11, -0.07, -0.11)
			var strike := _swat_target
			var swt: Vector3
			if s < 0.07:
				swt = tgt.lerp(wind, s / 0.07)
			elif s < 0.15:
				var u := (s - 0.07) / 0.08
				swt = wind.lerp(strike, u * u)
			else:
				swt = strike.lerp(tgt, (s - 0.15) / 0.17)
			tgt = swt
		# --- claw hold (right mouse): paw reaches out and stays hooked on the target ---
		var clawing := claw_on and i == claw_i and not swatting
		if clawing:
			var sh := Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
			tgt = sh + (claw_target - sh).limit_length(LA + LB - 0.015)
		if swatting:
			_targets[i] = tgt
		else:
			_targets[i] = LowPoly.damp3(_targets[i], tgt, 30.0 if clawing else 16.0, dt)
		_solve(i, _targets[i], side)
		_legs[i].claws.visible = (swatting and _swat_t < 0.26) or clawing or scramble > 0.3 or claws_out > 0.4 or _pin_t >= 0.0


func _solve(i: int, target: Vector3, side: float) -> void:
	var leg: Dictionary = _legs[i]
	var sh := Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
	# the shoulder reaches forward with the paw (shoulder blade), so a long step stays attached
	sh.z -= clampf(-target.z - 0.2, 0.0, 0.08)
	var r := LowPoly.ik2(sh, target, LA, LB, Vector3(side * 0.3, -0.6, 1.0))
	var elbow: Vector3 = r[0]
	var wrist: Vector3 = r[1]
	leg.upper.transform = LowPoly.seg_xform(sh, elbow)
	leg.lower.transform = LowPoly.seg_xform(elbow, wrist)
	leg.joint.position = elbow
	# paw points roughly along the forearm but flattens out toward the ground
	var fwd := (wrist - elbow).normalized()
	var flat_fwd := Vector3(fwd.x, minf(fwd.y, 0.0) * 0.4, fwd.z)
	if flat_fwd.length_squared() < 1e-4:
		flat_fwd = Vector3(0, 0, -1)
	flat_fwd = flat_fwd.normalized()
	var paw: Node3D = leg.paw
	paw.position = wrist
	paw.basis = Basis.looking_at(flat_fwd, Vector3.UP)
	paw.rotate_object_local(Vector3.RIGHT, clampf((target.y + 0.2) * 4.0, -0.3, 0.9))
