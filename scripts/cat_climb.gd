class_name CatClimb
extends RefCounted
## everything the cat does on the side of things, in one place: free climbing (any direction
## along a grippable surface, round trunks, round outside corners, into inside corners), hanging
## off a ledge, and every move that takes it from one place to another over an edge (grab, haul
## up, top out, low ledge hop, curb step up, round an overhanging lip, push off a wall).
##
## the rules that keep it from looking janky:
##   1. the capsule never teleports. every move over an edge is a planned path (cubic hermite
##      keys: position + velocity) that starts at where the cat is, moving the way it's moving,
##      and ends moving the way the next thing expects. no speed jumps at either end.
##   2. a path is swept with the real capsule (test_move, a few cm at a time) before it starts.
##      if any part of it hits something, it's not taken: no clipping through edges, shelves,
##      ceilings. a few variants are tried (higher over the edge, shallower / deeper landing).
##   3. while it runs, the path moves the capsule with move_and_collide. something in the way
##      (a moving prop) = let go and fall with the path's speed, never stuck in a pose.
##   4. outside corners are swung round on an arc about the corner edge (eased in and out), not
##      jumped across. inside corners turn the facing over a few tenths of a second.
##   5. the body's turn on the wall (toward sideways travel) is a spring, and it's held back by
##      how much room there is that way, so the head never goes into a wall it's climbing toward.
##      upward, the head's reach is checked too (an overhang stops the climb before the head
##      goes into it, then the lip move takes over).
##
## the player keeps its old flags (climbing / clambering / mantling) as read only views of this,
## so the rig, paws, sounds and tests didn't change. setting one false resets the climb.

enum { NONE, CLING, HANG, MOVE }

# free climb
const SIDE_SPEED := 0.85     # m/s sideways (real cats are slower across than up: ~0.7x)
const DOWN_SPEED := 0.6      # backing down, tail first
const REACH := 0.2           # how far past the body the "is there still wall" ray looks
const CORNER_IN := 0.72      # a side hit whose normal is this far off ours is a new face
const LUNGE_V := 2.3         # peak speed of a climb lunge
const LUNGE_T := 0.3
const LUNGE_COST := 14.0
const HEAD_MAX := 1.05       # rad the body turns toward sideways travel (~60 deg)
const HEAD_W := 9.0          # turn spring (rad/s, critically damped)
const CHEST := 0.12          # probe height above the feet
const HEAD_UP := 0.42        # how far above the feet the head reaches on a wall (climbing up)
const BODY_SIDE := 0.3       # room needed sideways for the body to turn full toward travel
const WRAP_MIN_T := 0.32     # s, shortest swing round an outside corner
const WRAP_PAUSE := 0.2      # s at an edge after swinging round one (thin posts don't spin)
const TURN_IN_T := 0.42       # s to turn into an inside corner
const CLIMB_ACC := 9.0       # m/s2 the climbing speed can change by (starts, stops, reversing)
const ABSORB := 9.0         # 1/s: speed it hits the wall with bleeds off as the claws sink in
const FLOOR_LET_GO := 0.11   # climbing down: let go this far above the floor (rump would touch)
const GAP := 0.012           # capsule skin off the face
# moves over edges
const HAUL_UP := 1.1         # m/s average rise hauling up off a hang
const MANTLE_UP := 1.7       # low ledge hop
const PUSH_T := 0.16         # s the hind legs push when kicking off a wall
const LIP_MAX := 0.45        # deepest overhang it reaches round

var p: CatPlayer
var mode := NONE
var kind := ""               # MOVE: grab, haul, mantle, step, lip, push
var hang_t := 0.0
var from_climb := false      # this move / hang started on a climb (w = up, whatever the camera)
var wrap_t := 0.0            # pause after a wrap
var corner := {}             # active swing round an outside corner / turn into an inside one
var _keys: Array = []        # [{p, v, t}]
var _pt := 0.0
var _then := NONE
var _haul: Array = []        # pre planned haul from the hang (validated when it grabbed on)
var _head_v := 0.0
var _absorb := Vector3.ZERO
var _cv := Vector2.ZERO      # climbing speed along the face (x across, y up): eases toward what's asked
var _edge := Vector3.ZERO    # ledge edge point / normal for the move in progress
var _edge_n := Vector3.ZERO

static var dbg := false


func _init(player: CatPlayer) -> void:
	p = player


func active() -> bool:
	return mode != NONE


func reset() -> void:
	mode = NONE
	kind = ""
	corner = {}
	_keys = []
	_haul = []


## progress 0..1 of the current move (the rig's haul pose reads it)
func progress() -> float:
	if mode != MOVE or _keys.size() < 2:
		return 0.0
	return clampf(_pt / float(_keys[-1].t), 0.0, 1.0)


func is_climbing() -> bool:
	return mode == CLING


func _over_kind() -> bool:
	return kind == "haul" or kind == "lip" or kind == "mantle"


## hanging / hauling up off a hang (the rig's rear up + pull pose)
func is_clambering() -> bool:
	return (mode == HANG or (mode == MOVE and (kind == "grab" or kind == "haul" or kind == "lip"))) and not from_climb


## a quick hop up (low ledge, curb), or a top out straight off a climb (the body tips over
## the edge from the climb pose instead of rearing up: see climb_pose)
func is_mantling() -> bool:
	return mode == MOVE and (kind == "mantle" or kind == "step" or (from_climb and _over_kind()))


## does the rig stand on its paws: on a wall / hanging yes, flying up toward an edge no (the
## paws reach for the top and land on it part way through the move)
func rig_grounded() -> bool:
	match mode:
		CLING, HANG:
			return true
		MOVE:
			if kind == "step":
				return true
			if _over_kind():
				return progress() > 0.55 or (from_climb and climb_pose() > 0.5)
	return false


## how far onto the wall the body is (the player's w_climb target): 1 climbing, 0 off, and
## during a top out off a climb it follows the haul (flat on the wall -> standing on top)
func climb_pose() -> float:
	if mode == CLING:
		return 1.0
	if mode == MOVE and from_climb and _over_kind():
		var u := progress()
		var e := clampf((u - 0.1) / 0.75, 0.0, 1.0)
		return 1.0 - e * e * e * (e * (e * 6.0 - 15.0) + 10.0)
	return 0.0


# ================================================================== entry points

## claws into a grippable surface with normal n
func cling(n: Vector3) -> void:
	var fn := _flat(n)
	if fn == Vector3.ZERO:
		return
	mode = CLING
	kind = ""
	corner = {}
	wrap_t = 0.0
	p.climb_n = fn
	p.climb_face = fn
	p.climb_head = 0.0
	_head_v = 0.0
	p.climb_lunge_t = 0.0
	p.climb_side = 0.0
	p.climb_wrap_t = 0.0
	# whatever speed it hit the wall with, along the wall, bleeds off (claws sink in, it slides
	# a few cm) instead of stopping dead in one tick
	var v: Vector3 = p.velocity
	_absorb = (v - fn * v.dot(fn)).limit_length(3.5)
	_cv = Vector2.ZERO
	p.velocity = Vector3.ZERO
	p.leap_lock = false
	p.pounce_air = false
	p.charging = false
	p._event("claws in, climbing")


## the wall in front (into = direction into it) has a top in reach: hop / haul onto it.
## step = walking into something low (keeps the pace it came in at). returns true if a move started
func try_ledge(into: Vector3, step := false) -> bool:
	if p.climb_cool > 0.0 and not step:
		return false
	var feet: Vector3 = p.global_position
	var li: Dictionary = p._ledge_info(into, feet, p.STEP_MOUNT if step else p.CLAMBER_MAX)
	if li.is_empty():
		return false
	var h: float = li.h
	var edge: Vector3 = li.edge
	var top_y: float = (li.top as Vector3).y
	var n := -into
	var climb := mode == CLING
	var v0: Vector3 = p.velocity
	if step:
		var spd := maxf(1.5, Vector2(v0.x, v0.z).length())
		return _go_over("step", edge, n, top_y, v0, into * spd)
	if h <= p.MANTLE_MAX:
		return _go_over("mantle", edge, n, top_y, v0, into * (0.25 if climb else maxf(1.2, Vector2(v0.x, v0.z).length())))
	# higher: catch the edge with the forepaws. hauls straight up if you're pushing for it,
	# else hangs there till you do (or drop)
	var keys := _plan_over("haul", edge, n, top_y, v0, into * 0.25, feet)
	if keys.is_empty():
		return false
	from_climb = climb
	_edge = edge
	_edge_n = n
	var hang := _hang_pos(edge, n, feet)
	if climb or feet.y > hang.y - 0.02:
		# already up at the edge (came off a climb / jumped high): no hang, just haul
		_start("haul", keys, NONE)
		p.stamina.spend(CatStamina.CLAMBER)
		p._event("haul up (%.2fm)" % h)
		return true
	var g := [_key(feet, _calm(v0, n), 0.0)]
	var dist := feet.distance_to(hang)
	var tg := clampf(2.0 * dist / maxf(v0.length(), 0.5), 0.12, 0.26)
	g.append(_key(hang, Vector3.ZERO, tg))
	if not _valid(g):
		g = [_key(feet, Vector3.ZERO, 0.0), _key(hang, Vector3.ZERO, maxf(tg, 0.2))]
		if not _valid(g):
			return false
	_haul = _plan_over("haul", edge, n, top_y, Vector3.ZERO, into * 0.25, hang)
	if _haul.is_empty():
		return false
	_start("grab", g, HANG)
	hang_t = 0.0
	p.stamina.spend(CatStamina.CLAMBER)
	p._event("grab (%.2fm)" % h)
	return true


# ================================================================== tick

func step(dt: float, mv: Vector2, wish_dir: Vector3, jump_pressed: bool, want_crouch: bool) -> void:
	match mode:
		CLING:
			var n0: Vector3 = p.climb_n
			_cling(dt, mv, wish_dir, jump_pressed, want_crouch)
			if mode == CLING or (mode == MOVE and from_climb):
				# going round something: the view comes round with the body by the same angle
				# (you keep looking at the trunk instead of the field behind it)
				var n1: Vector3 = p.climb_n
				var d := atan2(n0.cross(n1).y, n0.dot(n1))
				p.orb_yaw += d
				p.yaw = atan2(n1.x, n1.z)
				p.rotation.y = p.yaw
		HANG:
			_hang(dt, wish_dir, jump_pressed, want_crouch)
		MOVE:
			_run(dt)
	if mode == NONE:
		kind = ""


# ------------------------------------------------------------------ paths

func _key(pos: Vector3, vel: Vector3, t: float) -> Dictionary:
	return {"p": pos, "v": vel, "t": t}


## start speed for a path off a wall: never into the wall, and not silly fast
func _calm(v: Vector3, n: Vector3) -> Vector3:
	var into := v.dot(-n)
	if into > 0.0:
		v += n * into
	return v.limit_length(3.0)


func _sample(keys: Array, t: float) -> Array:
	var i := 0
	while i < keys.size() - 2 and t > float(keys[i + 1].t):
		i += 1
	var k0: Dictionary = keys[i]
	var k1: Dictionary = keys[i + 1]
	var T: float = maxf(float(k1.t) - float(k0.t), 1e-4)
	var s := clampf((t - float(k0.t)) / T, 0.0, 1.0)
	var s2 := s * s
	var s3 := s2 * s
	var p0: Vector3 = k0.p
	var p1: Vector3 = k1.p
	var v0: Vector3 = k0.v * T
	var v1: Vector3 = k1.v * T
	var pos := p0 * (2 * s3 - 3 * s2 + 1) + v0 * (s3 - 2 * s2 + s) + p1 * (-2 * s3 + 3 * s2) + v1 * (s3 - s2)
	var vel := (p0 * (6 * s2 - 6 * s) + v0 * (3 * s2 - 4 * s + 1) + p1 * (-6 * s2 + 6 * s) + v1 * (3 * s2 - 2 * s)) / T
	return [pos, vel]


## sweeps the real capsule along the path, a few cm at a time
func _valid(keys: Array) -> bool:
	var end: float = keys[-1].t
	var steps := maxi(int(ceil(end / 0.012)), 4)
	var a: Vector3 = keys[0].p
	var basis: Basis = p.global_transform.basis
	for i in range(1, steps + 1):
		var b: Vector3 = _sample(keys, end * float(i) / steps)[0]
		if p.test_move(Transform3D(basis, a), b - a, null, 0.001):
			if dbg:
				print("[climb] path blocked at %.2f / %.2f s, %s" % [end * float(i) / steps, end, str(b)])
			return false
		a = b
	return true


func _start(k: String, keys: Array, then: int) -> void:
	if k != "push":
		p.ledge_point = _edge
		p.ledge_n = _edge_n
	mode = MOVE
	kind = k
	_keys = keys
	_pt = 0.0
	_then = then
	corner = {}
	p.velocity = keys[0].v
	p.leap_lock = false
	p.pounce_air = false
	p.charging = false


func _run(dt: float) -> void:
	_pt += dt
	if from_climb:
		_head_tick(dt, Vector2.ZERO, false, BODY_SIDE + p.RADIUS)
	var end: float = _keys[-1].t
	var sv := _sample(_keys, minf(_pt, end))
	var to: Vector3 = sv[0]
	var motion: Vector3 = to - p.global_position
	var col = p.move_and_collide(motion, false, 0.001)
	if col != null and (col as KinematicCollision3D).get_remainder().length() > 0.012:
		# something moved into the way: let go and fall, carrying on the way it was going
		p.velocity = (sv[1] as Vector3) * 0.5
		p.climb_cool = 0.35
		mode = NONE
		p._event("lost the edge")
		return
	p.velocity = sv[1]
	if _pt >= end:
		p.velocity = _keys[-1].v
		match _then:
			HANG:
				mode = HANG
				hang_t = 0.0
				p.velocity = Vector3.ZERO
				p.land_dip_v -= 0.35
			_:
				mode = NONE
				p.climb_cool = 0.3
				if kind != "push":
					# settle onto the top through the body's own floor check, so the very next
					# tick knows it's standing (not in the air touching the wall: no slide)
					var ev: Vector3 = p.velocity
					p.velocity = Vector3.DOWN * 0.4
					p.move_and_slide()
					p.velocity = ev
				if kind != "push":
					p._event("up")


# ------------------------------------------------------------------ over an edge

## hang spot under an edge, at the lateral position of `at`
func _hang_pos(edge: Vector3, n: Vector3, at: Vector3) -> Vector3:
	var lat := at - n * (at - edge).dot(n)
	return Vector3(lat.x, edge.y - p.HANG, lat.z) + n * (p.RADIUS + GAP)


## the path from `from` (moving at v0) up the face and over the edge onto the top. a few
## variants: rise a bit higher over the edge, land shallower / deeper. [] if none is clear
func _plan_over(k: String, edge: Vector3, n: Vector3, top_y: float, v0: Vector3, exit_v: Vector3, from: Vector3) -> Array:
	var into := -n
	var lat := from - n * (from - edge).dot(n)        # straight up the face from here
	var wall := Vector3(lat.x, 0, lat.z) + n * (p.RADIUS + GAP + 0.003)
	var up_rate: float = HAUL_UP if k == "haul" else MANTLE_UP
	var spd := Vector2(exit_v.x, exit_v.z).length()
	if k == "step":
		up_rate = clampf(spd * 0.75, 1.6, 3.0)
	var v_start := _calm(v0, n)
	# off a climb the body is still flat on the wall when the feet crest the edge, hips lowest:
	# come up higher so the hips clear the edge as it tips over onto the top
	var lifts := [0.1, 0.14, 0.06] if mode == CLING else [0.035, 0.07]
	for lift in lifts:
		# (deep first: the rump and hind paws end up on the top too, not hanging off the edge.
		# last: perched right over a thin top, a fence or a wall)
		for deep in [p.RUMP_REACH + 0.06, 0.14, 0.07, 0.03, 0.05 - p.RADIUS]:
			var a := Vector3(wall.x, top_y + float(lift), wall.z)
			var b: Vector3 = Vector3(lat.x, top_y + 0.004, lat.z) + into * (p.RADIUS + float(deep))
			var rise := a.y - from.y
			var t1 := clampf(rise / up_rate, 0.06 if k == "step" else 0.1, 0.6)
			var over := a.distance_to(b)
			var t2 := clampf(over / maxf(spd, 0.9), 0.05, 0.2) if k == "step" else maxf(0.17 if k == "haul" else 0.12, over / (1.3 if k == "haul" else 1.8))
			var va := Vector3.UP * (rise / t1) * 0.35 + into * (over / t2) * 0.7
			var keys := [_key(from, v_start, 0.0), _key(a, va, t1), _key(b, exit_v, t1 + t2)]
			if not p._fits(b) or not _stands(b) or not _body_fits(b, into) or not _valid(keys):
				continue
			return keys
	return []


## something to stand on right under the feet (a thin wall top: don't land past it in the air)
func _stands(feet: Vector3) -> bool:
	var h: Dictionary = p._ray(feet + Vector3.UP * 0.04, feet + Vector3.DOWN * 0.05)
	return not h.is_empty() and h.normal.y > 0.7


## room for the whole body lying along `fwd` at feet (the capsule is only as long as it is wide:
## the head and rump stick out front and back)
func _body_fits(feet: Vector3, fwd: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.05
	cap.height = p.NOSE_REACH + p.RUMP_REACH
	q.shape = cap
	var x := Vector3.UP.cross(fwd).normalized()
	var c := feet + Vector3.UP * 0.11 + fwd * (p.NOSE_REACH - p.RUMP_REACH) * 0.5
	q.transform = Transform3D(Basis(x, fwd, x.cross(fwd)), c)   # capsule axis (y) along fwd
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _go_over(k: String, edge: Vector3, n: Vector3, top_y: float, v0: Vector3, exit_v: Vector3) -> bool:
	var keys := _plan_over(k, edge, n, top_y, v0, exit_v, p.global_position)
	if keys.is_empty():
		return false
	from_climb = mode == CLING
	_edge = edge
	_edge_n = n
	_start(k, keys, NONE)
	p.mantle_quick = Vector2(exit_v.x, exit_v.z).length() if k == "step" else 0.0
	p.paws.mantle()
	p._event("%s %.2fm" % ["step up" if k == "step" else "mantle", top_y - (keys[0].p as Vector3).y])
	return true


## climbing into the underside of something that sticks out (a shelf, a perch, a platform):
## swing out under it, reach round the lip and haul up onto it
func _try_lip(n: Vector3, ceil_y: float) -> bool:
	var feet: Vector3 = p.global_position
	var into := -n
	# outer face of the overhang: look back in toward the wall from out past it
	var y := ceil_y + 0.012
	var o: Dictionary = p._ray(Vector3(feet.x, y, feet.z) + n * (LIP_MAX + 0.2), Vector3(feet.x, y, feet.z) - n * 0.02)
	if o.is_empty() or _flat(o.normal).dot(n) < 0.7:
		return false
	var lip: Vector3 = o.position
	var depth := (lip - feet).dot(n) - p.RADIUS
	if depth > LIP_MAX:
		return false
	var th: Dictionary = p._ray(lip - n * 0.03 + Vector3.UP * 0.5, lip - n * 0.03 + Vector3.DOWN * 0.02)
	if th.is_empty() or th.normal.y < 0.7:
		return false
	var top_y: float = (th.position as Vector3).y
	var edge := Vector3(lip.x, top_y, lip.z)
	var out_pt := Vector3(lip.x, minf(feet.y, ceil_y - p.STAND_H - 0.02), lip.z) + n * (p.RADIUS + 0.03)
	var d := out_pt.distance_to(feet)
	var t1 := clampf(d / 0.9, 0.15, 0.4)
	var keys := [_key(feet, Vector3.ZERO, 0.0), _key(out_pt, n * 0.5 + Vector3.UP * 0.3, t1)]
	var over := _plan_over("haul", edge, n, top_y, n * 0.5 + Vector3.UP * 0.3, into * 0.25, out_pt)
	if over.is_empty():
		return false
	for i in range(1, over.size()):
		keys.append(_key(over[i].p, over[i].v, t1 + float(over[i].t)))
	if not _valid(keys):
		return false
	from_climb = true
	_edge = edge
	_edge_n = n
	_start("lip", keys, NONE)
	p.paws.mantle()
	p._event("round the lip")
	return true


# ------------------------------------------------------------------ hanging off an edge

func _hang(dt: float, wish_dir: Vector3, jump_pressed: bool, want_crouch: bool) -> void:
	hang_t += dt
	p.velocity = Vector3.ZERO
	var n := _edge_n
	var into := -n
	if from_climb:
		# came off a climb: the camera can be anywhere round a trunk, w / s mean up / down
		wish_dir = into * p.climb_mv.y
	if want_crouch or wish_dir.dot(n) > 0.5:
		mode = NONE
		p.velocity = n * 0.8 + Vector3.DOWN * 0.3
		p.climb_cool = 0.4
		p._event("let go")
		return
	if hang_t > 0.1 and (wish_dir.dot(into) > 0.3 or jump_pressed):
		# re-check: something may have moved onto the top since it grabbed on
		if _haul.is_empty() or not _valid(_haul):
			_haul = _plan_over("haul", _edge, n, _edge.y, Vector3.ZERO, into * 0.25, p.global_position)
		if not _haul.is_empty():
			_start("haul", _haul, NONE)
			p.paws.mantle()
			p._event("haul up")


# ------------------------------------------------------------------ free climbing

static func _flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length() > 0.01 else Vector3.ZERO


## the surface at height CHEST in front of the feet, {} if nothing grippable
func _probe(feet: Vector3, n: Vector3, h := CHEST) -> Dictionary:
	var c := feet + Vector3.UP * h
	var hit: Dictionary = p._ray(c, c - n * (p.RADIUS + REACH))
	if hit.is_empty() or not p._is_climbable(hit.collider):
		return {}
	var hn := _flat(hit.normal)
	if hn == Vector3.ZERO:
		return {}
	hit.normal = hn
	return hit


func _let_go(cool: float, ev: String, vel: Vector3) -> void:
	mode = NONE
	p.climb_cool = cool
	p.velocity = vel
	p._event(ev)


func _cling(dt: float, mv: Vector2, wish_dir: Vector3, jump_pressed: bool, want_crouch: bool) -> void:
	var n: Vector3 = p.climb_n
	var feet: Vector3 = p.global_position
	var dir := mv.limit_length(1.0)
	var moving := dir.length() > 0.15
	wrap_t = maxf(wrap_t - dt, 0.0)
	p.climb_wrap_t = wrap_t

	if not p.stamina.infinite and p.stamina.is_empty():
		_let_go(0.5, "claws give out", n * 0.4)
		if p.has_method("start_wall_slide"):
			p.start_wall_slide(n)
		return

	if not corner.is_empty():
		_corner_tick(dt, dir)
		return

	var hit := _probe(feet, n)
	if hit.is_empty():
		# the surface went away under us (moved, or came in at its very top)
		if try_ledge(-n):
			return
		_let_go(0.3, "lost grip", n * 0.4 + Vector3.UP * 0.6)
		return
	n = hit.normal
	p.climb_n = n
	var into := -n
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
			_push_off(n * p.KICK_OUT + Vector3.UP * p.KICK_UP * 0.8 + wish_dir * 0.8)
			return
	if want_crouch:
		_let_go(0.4, "let go", n * 0.6)
		return

	# speeds: up in bursts (the bound), across steadier, down slow
	var burst := 0.55 + 0.45 * maxf(0.0, sin(p.rig.phase * TAU + 0.6))
	var vy: float = (p.CLIMB_SPEED * burst if dir.y > 0.0 else DOWN_SPEED) * dir.y
	var vx := SIDE_SPEED * (0.75 + 0.25 * burst) * dir.x
	if p.climb_lunge_t > 0.0:
		# speed swells in as the hinds fire, then fades (no jump to full speed)
		var u: float = 1.0 - p.climb_lunge_t / LUNGE_T
		var f := smoothstep(0.0, 0.25, u) * pow(1.0 - smoothstep(0.25, 1.0, u), 1.5)
		var lv: Vector3 = p.climb_lunge_dir * LUNGE_V * f
		vy += lv.y
		vx += lv.dot(right)
		p.climb_lunge_t = maxf(p.climb_lunge_t - dt, 0.0)
	var side := signf(vx) if absf(vx) > 0.05 else 0.0
	p.climb_side = side
	var chest := feet + Vector3.UP * CHEST

	# room sideways (the body turns that way and is longer than the capsule is wide)
	var room := BODY_SIDE + p.RADIUS
	if side != 0.0:
		var sh: Dictionary = p._ray(chest, chest + right * side * (BODY_SIDE + p.RADIUS))
		if not sh.is_empty():
			room = (sh.position - chest).dot(right * side)
			var sn := _flat(sh.normal)
			if p._is_climbable(sh.collider) and sn != Vector3.ZERO and sn.dot(n) < CORNER_IN and sn.dot(right * side) < -0.3:
				if room < p.RADIUS + 0.05:
					# inside corner: turn onto the other face
					corner = {"in": true, "n0": n, "n1": sn, "t": 0.0, "dur": TURN_IN_T}
					p._event("round the inside corner")
					_corner_tick(dt, dir)
					return
			elif room < p.RADIUS + 0.025:
				vx = 0.0   # something we can't climb onto: stop beside it
		_absorb.x *= 0.0 if room < p.RADIUS + 0.03 else 1.0

	# head room upward: the head reaches well past the top of the capsule on a wall
	if vy > 0.0:
		var hc := feet + n * 0.05 + Vector3.UP * 0.12
		var uh: Dictionary = p._ray(hc, hc + Vector3.UP * (HEAD_UP - 0.12 + 0.02))
		if not uh.is_empty() and uh.normal.y < -0.5:
			if _try_lip(n, (uh.position as Vector3).y):
				return
			vy = 0.0   # an overhang it can't get round: stop under it

	# going up: is there wall at the chest after this tick? no = top: over it if there's room
	if vy > 0.05:
		var nxt := feet + Vector3.UP * (vy * dt + 0.002)
		if _probe(nxt, n).is_empty():
			if try_ledge(into):
				return
			vy = 0.0   # no way over (no headroom, nothing to stand on): stay at the top
	# going down: let go a little above the floor, before the rump reaches it
	if vy < -0.05:
		var fh: Dictionary = p._ray(feet + Vector3.UP * 0.02, feet + Vector3.DOWN * FLOOR_LET_GO)
		if not fh.is_empty() and fh.normal.y > 0.6:
			_let_go(0.4, "down", n * 0.3 + Vector3.DOWN * 0.3)
			return

	# the limbs can only change the speed so fast: ease toward it (the bursts stay in)
	var want := Vector2(vx, vy)
	_cv = _cv.move_toward(want, (CLIMB_ACC if p.climb_lunge_t <= 0.0 else 25.0) * dt)
	if vx == 0.0:
		_cv.x = 0.0   # (stopped against something beside it)
	if vy == 0.0 and want.y == 0.0 and (dir.y > 0.0):
		_cv.y = minf(_cv.y, 0.0)   # (stopped at the top / under an overhang)
	vx = _cv.x
	vy = _cv.y
	var v := Vector3.UP * vy + right * vx
	_absorb = _absorb.lerp(Vector3.ZERO, clampf(dt * ABSORB, 0.0, 1.0))
	v += _absorb

	# hug the surface, then move
	var dist: float = Vector2(hit.position.x - feet.x, hit.position.z - feet.z).dot(Vector2(into.x, into.z))
	v += into * clampf((dist - (p.RADIUS + 0.01)) * 12.0, -1.0, 1.0)
	p.velocity = v
	p.move_and_slide()

	# still on it? follow the curve (trunks, posts) or swing round the edge
	var feet2: Vector3 = p.global_position
	var h2 := _probe(feet2, n)
	if not h2.is_empty():
		p.climb_n = h2.normal
	elif side != 0.0 and wrap_t <= 0.0 and _wrap_outside(feet2, n, right * side):
		_corner_tick(dt, dir)
		return
	elif not _probe(feet, n).is_empty():
		# would leave the wall (edge we can't get round: bottom of a branch, end of a board):
		# step back onto it, the way it came (move_and_collide, no snap)
		p.move_and_collide(feet - feet2, false, 0.001)

	if p.is_on_floor() and dir.y < 0.0:
		_let_go(0.4, "down", Vector3.ZERO)
		return

	_head_tick(dt, dir, moving, room)


## body turns toward where it's going across the wall (head first), back to head up idle.
## a spring, held back by the room there is that way
func _head_tick(dt: float, dir: Vector2, moving: bool, room: float) -> void:
	var head := 0.0
	if moving and dir.y > -0.3:
		head = clampf(atan2(dir.x, maxf(dir.y, 0.2)), -HEAD_MAX, HEAD_MAX)
	var room_k := clampf((room - p.RADIUS - 0.1) / (BODY_SIDE - 0.1), 0.0, 1.0)
	head *= room_k
	var w := HEAD_W * (1.6 if room_k < 0.5 else 1.0)
	_head_v += (w * w * (head - p.climb_head) - 2.0 * w * _head_v) * dt
	p.climb_head += _head_v * dt


func _push_off(vel: Vector3) -> void:
	# the hind legs push for a few hundredths of a second: speed builds instead of appearing
	var feet: Vector3 = p.global_position
	# (mid key placed so the push starts with no kick: speed swells, then builds to full)
	var keys := [_key(feet, Vector3.ZERO, 0.0), _key(feet + vel * PUSH_T / 12.0, vel * 0.5, PUSH_T * 0.5), _key(feet + vel * PUSH_T * 0.5, vel, PUSH_T)]
	p.jumped_this_air = true
	p.kicks_left = maxi(p.kicks_left - 1, 0)
	p.climb_cool = 0.35
	p._event("leap off")
	if _valid(keys):
		_start("push", keys, NONE)
	else:
		mode = NONE
		p.velocity = vel


## the face ended beside us. look back round the edge for the next face: from a point just
## past the old face plane, cast back against the travel direction. thin posts, box trunks,
## crate corners all wrap like this. sets up the swing (no teleport)
func _wrap_outside(feet: Vector3, n: Vector3, travel: Vector3) -> bool:
	var c := feet + Vector3.UP * CHEST
	for depth in [0.05, 0.12]:
		var o: Vector3 = c - n * (p.RADIUS + depth) + travel * 0.04
		var h: Dictionary = p._ray(o, o - travel * (p.RADIUS + 0.35))
		if h.is_empty() or not p._is_climbable(h.collider):
			continue
		var hn := _flat(h.normal)
		if hn == Vector3.ZERO or hn.dot(travel) < 0.3:
			continue
		# corner edge = where the two face planes meet (2d line intersection)
		var f0 := feet - n * (p.RADIUS + GAP)
		var f1: Vector3 = h.position
		var det := n.x * hn.z - n.z * hn.x
		if absf(det) < 0.2:
			continue
		var c0 := n.x * f0.x + n.z * f0.z
		var c1 := hn.x * f1.x + hn.z * f1.z
		var ex := (c0 * hn.z - c1 * n.z) / det
		var ez := (n.x * c1 - hn.x * c0) / det
		var e := Vector3(ex, 0.0, ez)
		var r: float = p.RADIUS + GAP
		var a1 := atan2(n.cross(hn).y, n.dot(hn))
		var to: Vector3 = e + hn * r
		to.y = feet.y
		if Vector2(feet.x - e.x, feet.z - e.z).length() > r + 0.12 or not p._fits(to):
			continue
		# angle over time: a cubic that starts at the speed it was going across the face and
		# ends at the speed it'll go across the next one (no stop, no lurch)
		var w0 := clampf(p.velocity.dot(travel), 0.0, 2.0) / r * signf(a1)
		var w1 := SIDE_SPEED * 0.85 / r * signf(a1)
		var dur := clampf(absf(a1) / maxf((absf(w0) + absf(w1)) * 0.5, 0.1), 0.12, 0.45)
		corner = {"in": false, "e": e, "r": r, "n0": n, "n1": hn, "a1": a1, "t": 0.0, "dur": dur, "w0": w0, "w1": w1}
		p._event("round the corner")
		return true
	return false


## one tick of a swing round an outside corner (arc about the edge) or a turn into an
## inside corner. eased in and out; vertical input still moves it up / down meanwhile
func _corner_tick(dt: float, dir: Vector2) -> void:
	corner.t += dt
	var u := clampf(float(corner.t) / float(corner.dur), 0.0, 1.0)
	var e := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
	if not corner["in"]:
		# hermite in angle: a(0) 0, a(1) a1, a'(0) w0, a'(1) w1 (all scaled to u)
		var dur: float = corner.dur
		var a1: float = corner.a1
		var u2 := u * u
		var u3 := u2 * u
		var aa: float = (u3 - 2 * u2 + u) * float(corner.w0) * dur + (-2 * u3 + 3 * u2) * a1 + (u3 - u2) * float(corner.w1) * dur
		e = aa / a1
	var n0: Vector3 = corner.n0
	var n1: Vector3 = corner.n1
	var vy := DOWN_SPEED * dir.y * 0.5 if dir.y < 0.0 else p.CLIMB_SPEED * 0.5 * dir.y
	var feet: Vector3 = p.global_position
	if corner["in"]:
		var nn := n0.slerp(n1, e).normalized()
		p.climb_n = nn
		var into := -nn
		var v := Vector3.UP * vy
		var hit := _probe(feet, nn)
		if not hit.is_empty():
			var dist: float = Vector2(hit.position.x - feet.x, hit.position.z - feet.z).dot(Vector2(into.x, into.z))
			v += into * clampf((dist - (p.RADIUS + 0.01)) * 12.0, -1.0, 1.0)
		p.velocity = v
		p.move_and_slide()
	else:
		var a := float(corner.a1) * e
		var nn := n0.rotated(Vector3.UP, a).normalized()
		var r: float = corner.r
		var c: Vector3 = corner.e
		var to := c + nn * r
		to.y = feet.y + vy * dt
		var motion := to - feet
		var col = p.move_and_collide(motion, false, 0.001)
		if col != null and (col as KinematicCollision3D).get_remainder().length() > 0.01:
			# something in the way round the corner: back onto the face it came from
			corner = {}
			wrap_t = WRAP_PAUSE
			return
		p.velocity = motion / dt
		p.climb_n = nn
	# (turning into an inside corner the way it was going is straight into the new wall: head up)
	_head_tick(dt, dir, dir.length() > 0.15, p.RADIUS if corner["in"] else BODY_SIDE + p.RADIUS)
	if u >= 1.0:
		p.climb_n = n1
		corner = {}
		wrap_t = WRAP_PAUSE
		p.climb_wrap_t = wrap_t
