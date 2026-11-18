class_name CatLockOn
extends CanvasLayer
## souls style lock on. tab picks the best thing in view (rat pit rats first, then prey, then any
## other wildlife), puts a dot on it and holds the camera on it in every view. while locked:
##
##   - the body squares up to the target and wasd strafes / circles round it (shift still runs,
##     and running turns the body to where it's going like normal, the camera stays on the target)
##   - dodges read wasd relative to the target (s = backstep, a/d = side leap), see CatDash.try_start
##   - flick the mouse left / right to hop the lock to the next target on that side
##   - tab again unlocks. so does the target dying / being caught, going out of range or staying
##     out of sight for a moment. a killed enemy hands the lock to the next enemy close by (ds3 style)
##
## the camera is steered in _process (render rate), not physics, so it doesn't judder.
## the marker is a canvas dot projected from the target's body centre. every Control ignores the
## mouse (the captured cursor parks at screen centre and a STOP control eats mouse look).

const RANGE := 11.0          # m: how far a fresh lock reaches
const KEEP := 16.0           # m: past this the lock breaks
const RETARGET := 7.0        # m: a dead enemy hands the lock to another enemy this close
const LOS_GRACE := 1.4       # s: out of sight this long and the lock breaks
const VIEW_CONE := 0.85      # rad off the look direction counted as "in view" when there's no frustum
const FLICK_PX := 75.0       # px of fast mouse x travel that counts as a flick
const FLICK_DECAY := 520.0   # px/s the flick meter drains (slow drags never get there)
const FLICK_COOL := 0.28
const TURN_K := 14.0         # camera catch up rate (1/s)
const TIER := {"enemy": 0, "prey": 1, "wild": 2}

var player: Node3D           # CatPlayer (untyped: no cycle)
var target: Node3D = null
var tier := 0
var switches := 0            # for tests
var _lost_t := 0.0
var _flick := 0.0
var _flick_cool := 0.0
var _pop := 0.0
var _h_cache := {}
var _mark: Control


func _ready() -> void:
	layer = 5
	_mark = Control.new()
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.anchor_right = 1.0
	_mark.anchor_bottom = 1.0
	_mark.draw.connect(_draw_mark)
	add_child(_mark)


func active() -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree()


func toggle() -> void:
	if active():
		release("unlocked")
	else:
		acquire()


func acquire() -> bool:
	var best: Node3D = null
	var best_s := 1e9
	var look: Vector3 = player._look_dir()
	var eye := _eye()
	for c in _candidates(RANGE):
		var to: Vector3 = point_of(c) - eye
		if not _in_view(point_of(c), look, eye):
			continue
		if not _sees(c):
			continue
		# enemies always win over prey, prey over the rest. then nearest the crosshair, then nearest
		var s: float = TIER[_tier_of(c)] * 3.0 + look.angle_to(to) + to.length() * 0.05
		if s < best_s:
			best_s = s
			best = c
	if best == null:
		player._event("nothing to lock on to")
		return false
	_set_target(best)
	return true


func release(why := "") -> void:
	target = null
	_lost_t = 0.0
	_flick = 0.0
	_mark.queue_redraw()
	if why != "":
		player._event(why)


## world point the camera / marker aims at: the body's middle, not its feet
func point() -> Vector3:
	return point_of(target) if active() else Vector3.ZERO


func point_of(n: Node3D) -> Vector3:
	if n.has_method("lock_point"):
		return n.lock_point()
	return n.global_position + Vector3.UP * _height(n)


## yaw (player convention: atan2(-x, -z)) from the cat to the target
func yaw_to() -> float:
	var d := point() - player.global_position
	return atan2(-d.x, -d.z)


## mouse x while locked: fills the flick meter instead of turning the camera
func mouse(rel_x: float) -> void:
	if signf(rel_x) != signf(_flick):
		_flick = 0.0
	_flick += rel_x


## per physics tick: keep the lock honest, read flicks
func physics_tick(dt: float) -> void:
	_flick_cool = maxf(_flick_cool - dt, 0.0)
	_flick = move_toward(_flick, 0.0, FLICK_DECAY * dt)
	_pop = move_toward(_pop, 0.0, dt * 5.0)
	if target == null:
		return
	if not _valid(target):
		var was_enemy := tier == 0
		target = null
		if was_enemy and _retarget():
			return
		release("lock lost")
		return
	var d: float = (point() - _eye()).length()
	if d > KEEP:
		release("target out of range")
		return
	_lost_t = 0.0 if _sees(target) else _lost_t + dt
	if _lost_t > LOS_GRACE:
		release("lost sight of it")
		return
	if absf(_flick) > FLICK_PX and _flick_cool <= 0.0:
		switch_side(1 if _flick > 0.0 else -1)
		_flick = 0.0
		_flick_cool = FLICK_COOL


## side +1 = the next one to the right on screen, -1 = left
func switch_side(side: int) -> bool:
	if not active():
		return false
	var eye := _eye()
	var cur := _yaw_from(eye, point())
	var best: Node3D = null
	var best_s := 1e9
	for c in _candidates(KEEP):
		if c == target:
			continue
		var dy := wrapf(_yaw_from(eye, point_of(c)) - cur, -PI, PI)
		# yaw grows to the left, so "right" is a negative step
		if (dy < -0.02 and side > 0) or (dy > 0.02 and side < 0):
			if absf(dy) > 2.2 or not _sees(c):
				continue
			var s: float = absf(dy) + TIER[_tier_of(c)] * 0.35 + (point_of(c) - eye).length() * 0.02
			if s < best_s:
				best_s = s
				best = c
	if best == null:
		return false
	_set_target(best)
	switches += 1
	return true


## render rate: swing the camera onto the target
func frame_steer(dt: float) -> void:
	_mark.queue_redraw()
	if not active():
		return
	var p = player
	var k := 1.0 - exp(-TURN_K * dt)
	var piv: Vector3 = p.global_position + Vector3.UP * 0.25
	if p.view_mode == 0 and p.cam:
		piv = p.cam.global_position   # first person: aim from the camera (it rides the head)
	var to := point() - piv
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.05:
		return
	var want_yaw := atan2(-to.x, -to.z)
	p.orb_yaw = p.orb_yaw + wrapf(want_yaw - p.orb_yaw, -PI, PI) * k
	var want_pitch := atan2(to.y, flat)
	if p.view_mode == 0:
		p.pitch = lerpf(p.pitch, clampf(want_pitch, -1.2, 1.0), k)
	elif p.view_mode == 1:
		# camera sits up and behind: tip it down a touch more so the cat and the target both fit
		p.pitch = lerpf(p.pitch, clampf(want_pitch - 0.22, -1.2, 0.6), k)
	else:
		p.orb_pitch = lerpf(p.orb_pitch, clampf(want_pitch - 0.3, -1.3, 0.4), k)


# ------------------------------------------------------------------ picking

func _set_target(n: Node3D) -> void:
	target = n
	tier = TIER[_tier_of(n)]
	_lost_t = 0.0
	_pop = 1.0
	_mark.queue_redraw()
	player._event("locked on: %s" % player._prey_name(n))


func _retarget() -> bool:
	var eye := _eye()
	var best: Node3D = null
	var best_d := RETARGET
	for c in _candidates(RETARGET):
		if _tier_of(c) != "enemy" or not _sees(c):
			continue
		var d := (point_of(c) - eye).length()
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		return false
	_set_target(best)
	return true


func _candidates(rng: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var seen := {}
	var eye := _eye()
	for g in ["enemy", "prey", "wild"]:
		for n in player.get_tree().get_nodes_in_group(g):
			if not n is Node3D or seen.has(n) or not _valid(n):
				continue
			seen[n] = true
			if (point_of(n) - eye).length() <= rng:
				out.append(n)
	return out


func _valid(n: Object) -> bool:
	if n == null or not is_instance_valid(n) or not (n as Node).is_inside_tree():
		return false
	if not (n.is_in_group("enemy") or n.is_in_group("prey") or n.is_in_group("wild")):
		return false
	if n == player.get("carried"):
		return false
	if n.get("caught") == true:
		return false
	if n.has_method("alive") and not n.alive():
		return false
	if n is Node3D and not (n as Node3D).is_visible_in_tree():
		return false
	return true


func _tier_of(n: Node) -> String:
	if n.is_in_group("enemy"):
		return "enemy"
	if n.is_in_group("prey"):
		return "prey"
	return "wild"


func _eye() -> Vector3:
	return player.global_transform * Vector3(0, player.EYE_STAND, 0)


func _yaw_from(eye: Vector3, p: Vector3) -> float:
	var d := p - eye
	return atan2(-d.x, -d.z)


func _in_view(p: Vector3, look: Vector3, eye: Vector3) -> bool:
	var cam: Camera3D = player.cam
	if cam and cam.is_inside_tree() and cam.current:
		return cam.is_position_in_frustum(p)
	return look.angle_to(p - eye) < VIEW_CONE


func _sees(n: Node3D) -> bool:
	var eye := _eye()
	var p := point_of(n)
	var q := PhysicsRayQueryParameters3D.create(eye, p)
	var ex: Array[RID] = [player.get_rid()]
	if n is CollisionObject3D:
		ex.append((n as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	# hit something belonging to the target (a child body) or right at it
	var col: Object = hit.collider
	if col is Node and (n.is_ancestor_of(col) or col == n):
		return true
	return (hit.position - p).length() < 0.08


## body centre height above the node's origin, from its meshes (cached per node)
func _height(n: Node3D) -> float:
	var id := n.get_instance_id()
	if _h_cache.has(id):
		return _h_cache[id]
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var any := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.append(k)
		if c is VisualInstance3D and not c is Light3D:
			var vi := c as VisualInstance3D
			var b := (inv * vi.global_transform) * vi.get_aabb()
			box = b if not any else box.merge(b)
			any = true
	var h := 0.06
	if any:
		h = clampf(box.get_center().y, 0.02, 1.2)
	_h_cache[id] = h
	return h


# ------------------------------------------------------------------ marker

func _draw_mark() -> void:
	if not active():
		return
	var cam: Camera3D = player.cam
	if cam == null or not cam.current:
		return
	var p := point()
	if cam.is_position_behind(p):
		return
	var s := cam.unproject_position(p)
	var glow := Color(1.0, 0.35, 0.25, 0.5) if tier == 0 else Color(1.0, 0.85, 0.45, 0.45)
	var r := 5.0 + _pop * 9.0
	_mark.draw_circle(s, r + 6.0, Color(glow, glow.a * 0.35))
	_mark.draw_circle(s, r + 3.0, glow)
	_mark.draw_circle(s, r, Color(1, 0.97, 0.9, 0.95))
	_mark.draw_arc(s, r + 0.5, 0.0, TAU, 24, Color(0, 0, 0, 0.55), 1.2, true)
