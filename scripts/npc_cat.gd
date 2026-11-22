class_name NpcCat
extends Node3D
## wandering background cat: idles, looks around, walks, trots, zooms, sits.
## and it plays tag with you:
##   - hang about near it and it may crouch, wiggle and come charging at you. reach you = a soft
##     play bop (the same one cat_spar.gd uses: dodge / parry it like any other), then it bolts:
##     you're it
##   - run straight at it and it bolts first
##   - tab on it and it's a play fight like any other cat: a bop makes it flinch and scamper off
##     (play_tag), and once it's got away it often turns round and comes back for you
## online the cat's owner (world sync) runs all of this. a chase reaching YOUR cat is spotted in
## your own game (state "chase" comes over the wire) and the owner hears it by NetWorld.forward

var rig: CatRig
var area := Rect2(-4.5, -1.5, 9.0, 3.5) # x, z, w, d of open floor
var state := "idle"
var state_t := 2.0
var target := Vector3.ZERO
var speed := 0.0
var want_speed := 0.0
var yaw := 0.0
var look_t := 0.0
var look_target := 0.0
var fur := Color(0.2, 0.2, 0.22)
var fur_dark := Color(0.1, 0.1, 0.12)
var pattern := "tux"
var socks := true
var eye := Color(0.95, 0.75, 0.2)
var rng := RandomNumberGenerator.new()
var react := ""          # play fight flinch: "swat" / "rake" / "pounce" / "grab"
var react_t := 0.0
var react_max := 0.0
var tagged := 0          # play bops taken (tests)
var tags_given := 0      # play bops it landed on a cat (tests)

# ---- play tag
const PLAY_R := 4.0          # m: a cat this close can get chased
const SPOOK_R := 2.4         # m: a cat charging at us inside this = bolt
const SPOOK_V := 2.2         # m/s closing speed that counts as charging
const TAG_REACH := 0.34      # m from body to body: got you
const CHASE_T := 4.5         # s: gives up the chase after this
const CHASE_V := 3.8         # m/s
var play := true             # false = the old wander only
var play_chance := 0.22      # per second, while a cat hangs about close: start a stalk
var mate: Node3D = null      # the cat we're chasing / running from
var play_cd := 2.0           # s until it'll start another game
var it_back := false         # got tagged: once away, turn round and come for them
var _tag_cd := 0.0
var _mate_d := -1.0
var _closing := 0.0
var _seq := 0
var _wig := 0.0


func _ready() -> void:
	add_to_group("cat")   # cat vision lights other cats up (cat_vision.gd)
	add_to_group("spar_cat")   # tab locks on to it = play fight, attacks go soft (cat_spar.gd)
	rig = CatRig.new()
	rig.coat_from_style = false
	rig.fur = fur
	rig.fur_dark = fur_dark
	rig.pattern = pattern
	rig.socks = socks
	rig.eye_color = eye
	add_child(rig)
	yaw = rotation.y
	rng.randomize()


func _blocked(to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.15, 0), to + Vector3(0, 0.15, 0))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty()


func _pick() -> void:
	var r := rng.randf()
	if r < 0.25:
		state = "idle"
		state_t = rng.randf_range(1.5, 4.0)
		want_speed = 0.0
	elif r < 0.4:
		state = "sit"
		state_t = rng.randf_range(4.0, 8.0)
		want_speed = 0.0
	else:
		for _i in 12:
			var p := Vector3(rng.randf_range(area.position.x, area.end.x), 0, rng.randf_range(area.position.y, area.end.y))
			if p.distance_to(global_position) > 1.0 and not _blocked(p):
				target = p
				break
		state = "move"
		state_t = 12.0
		var g := rng.randf()
		want_speed = 0.8 if g < 0.5 else (2.6 if g < 0.85 else 7.5)


## a play bop from another cat (cat_spar.gd, or forwarded to us online by NetWorld): flinch,
## then scamper off away from them
func play_tag(kind: String, from: Vector3) -> void:
	tagged += 1
	mate = _nearest_cat(3.0, from)
	it_back = rng.randf() < 0.7    # you got me: once i'm clear, i'm coming for you
	play_cd = 0.0
	react = kind
	react_max = 0.9 if kind in ["pounce", "grab"] else 0.32
	react_t = react_max
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else global_transform.basis.z
	global_position += away * (0.12 if kind == "pounce" else 0.06)
	_flee_from(from, react_max)


## run off somewhere in the area, as far from p as it can find
func _flee_from(p: Vector3, delay := 0.0) -> void:
	var away := global_position - p
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else global_transform.basis.z
	# somewhere ahead of us, away from them (never back past them), the further the better
	var best := global_position
	var best_d := -1.0
	for i in 18:
		var c := Vector3(rng.randf_range(area.position.x, area.end.x), global_position.y, rng.randf_range(area.position.y, area.end.y))
		if i >= 14:   # no luck in the area: a short dash straight off
			c = global_position + away.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7)) * rng.randf_range(0.8, 1.6)
		var to := c - global_position
		to.y = 0.0
		if to.length() < 0.5 or to.normalized().dot(away) < 0.35:
			continue
		var d := c.distance_to(p)
		if d > best_d and not _blocked(c):
			best_d = d
			best = c
	target = best
	state = "flee"
	state_t = 3.0 + delay
	want_speed = 2.6 if rng.randf() < 0.6 else 4.5
	speed = 0.0 if delay > 0.0 else speed


func _process(dt: float) -> void:
	state_t -= dt
	if react_t > 0.0:
		react_t = maxf(react_t - dt, 0.0)
		if react_t <= 0.0:
			react = ""
	_tag_check(dt)
	if play:
		_play_think(dt)
	var vel := Vector3.ZERO
	match state:
		"stalk":
			# low, eyes on them, bum wiggle... then go
			speed = move_toward(speed, 0.0, dt * 10.0)
			if is_instance_valid(mate):
				var to := CatSpar.pos_of(mate) - global_position
				yaw += clampf(wrapf(atan2(-to.x, -to.z) - yaw, -PI, PI), -5.0 * dt, 5.0 * dt)
			if state_t < 0:
				_start_chase()
		"chase":
			if not _mate_ok(PLAY_R + 2.5) or state_t < 0:
				_end_play()
			else:
				var mp := CatSpar.pos_of(mate)
				var to := mp - global_position
				to.y = 0
				var ty := atan2(-to.x, -to.z)
				var diff := wrapf(ty - yaw, -PI, PI)
				yaw += clampf(diff, -6.0 * dt, 6.0 * dt)
				var ws := CHASE_V * clampf(1.0 - absf(diff) / 1.4, 0.15, 1.0)
				if react_t > 0.0:
					ws = 0.0
				speed = move_toward(speed, ws, dt * 9.0)
		"move", "flee":
			var to := target - global_position
			to.y = 0
			var d := to.length()
			if d < 0.15 or state_t < 0:
				if state == "flee":
					_fled()
				else:
					_pick()
			else:
				var ty := atan2(-to.x, -to.z)
				var diff := wrapf(ty - yaw, -PI, PI)
				yaw += clampf(diff, -3.5 * dt, 3.5 * dt)
				var facing := clampf(1.0 - absf(diff) / 1.0, 0.0, 1.0)
				var ws := want_speed * facing
				if d < 0.8:
					ws = minf(ws, maxf(d * 1.6, 0.4))
				if react_t > 0.0:
					ws = 0.0    # flinching first, then off it goes
				speed = move_toward(speed, ws, dt * (8.0 if ws > speed else 10.0))
		_:
			speed = move_toward(speed, 0.0, dt * 10.0)
			if state_t < 0:
				_pick()
	rotation.y = yaw
	vel = -global_transform.basis.z * speed
	global_position += vel * dt
	rig.drive_velocity = vel
	rig.sit = move_toward(rig.sit, 1.0 if (state == "sit" and speed < 0.1) else 0.0, dt * 2.0)
	var low := 0.75 if state == "stalk" else (0.25 if state == "chase" else 0.0)
	rig.crouch = move_toward(rig.crouch, low, dt * 4.0)
	# look around when idle
	look_t -= dt
	if look_t < 0.0:
		look_t = rng.randf_range(0.8, 2.5)
		look_target = rng.randf_range(-0.9, 0.9) if state != "move" else 0.0
	if state == "stalk":
		_wig += dt * 16.0
		look_target = 0.0
		rig.look_yaw = sin(_wig) * 0.06   # head bob while it lines up
	else:
		rig.look_yaw = LowPoly.damp(rig.look_yaw, look_target, 5.0, dt)
	_orient_react()


## the flinch / bowled over on the rig (local to us, so it rides world sync's transform as is)
func _orient_react() -> void:
	if react == "" or react_max <= 0.0:
		if rig.transform != Transform3D.IDENTITY:
			rig.transform = Transform3D.IDENTITY
		return
	var e := react_t / react_max
	var s := sin(PI * minf((1.0 - e) * 1.6, 1.0))
	var rot := Basis()
	var off := Vector3.ZERO
	match react:
		"swat", "rake":
			rot = Basis(Vector3.RIGHT, (0.3 if react == "swat" else 0.15) * s)
			off = Vector3.BACK * 0.04 * s
		"pounce":
			var k := clampf(minf((1.0 - e) * 6.0, e * 3.0), 0.0, 1.0)
			rot = Basis(Vector3.FORWARD, 1.35 * k)
			off = Vector3.UP * 0.05 * k
		"grab":
			rot = Basis(Vector3.FORWARD, 0.25 * sin(e * 18.0) * s)
	rig.transform = Transform3D(rot, off)


# ------------------------------------------------------------------ play tag

## cats we play with: players (local CatPlayer or another player's RemoteCat), not the practice
## bot or other farm cats. near = closest within r of `at` (default: us)
func _nearest_cat(r: float, at = null) -> Node3D:
	var here: Vector3 = at if at is Vector3 else global_position
	var best: Node3D = null
	var best_d := r
	for n in get_tree().get_nodes_in_group("cat"):
		if n == self or n is NpcCat or not n is Node3D:
			continue
		if n is CatPlayer and (n as CatPlayer).spar_dummy:
			continue
		if n is RemoteCat and not ((n as RemoteCat).rig and (n as RemoteCat).rig.visible):
			continue
		var d := CatSpar.pos_of(n).distance_to(here)
		if d < best_d:
			best_d = d
			best = n
	return best


func _mate_ok(r: float) -> bool:
	if not is_instance_valid(mate) or not mate.is_inside_tree():
		return false
	var mp := CatSpar.pos_of(mate)
	if mp.distance_to(global_position) > r:
		return false
	return area.grow(1.5).has_point(Vector2(mp.x, mp.z))


func _play_think(dt: float) -> void:
	play_cd = maxf(play_cd - dt, 0.0)
	if state in ["stalk", "chase"] or react_t > 0.0:
		return
	var near := _nearest_cat(PLAY_R)
	# how fast the nearest cat is coming at us
	if near:
		var d := CatSpar.pos_of(near).distance_to(global_position)
		if near == mate and _mate_d >= 0.0:
			_closing = lerpf(_closing, (_mate_d - d) / maxf(dt, 0.001), clampf(dt * 8.0, 0.0, 1.0))
		else:
			_closing = 0.0
		mate = near
		_mate_d = d
	else:
		_mate_d = -1.0
		_closing = 0.0
		return
	if state == "flee":
		return
	if _mate_d < SPOOK_R and _closing > SPOOK_V and play_cd <= 0.0:
		# they're charging: bolt (and maybe come back at them after)
		_flee_from(CatSpar.pos_of(mate))
		it_back = rng.randf() < 0.5
		play_cd = 1.0
		return
	if play_cd <= 0.0 and state != "sit" and _mate_d > 0.9 and rng.randf() < play_chance * dt:
		_stalk()


func _stalk() -> void:
	state = "stalk"
	state_t = rng.randf_range(0.7, 1.4)
	want_speed = 0.0
	_wig = 0.0
	CatSfx.play_at("meow2", global_position, 0.45, rng.randf_range(1.1, 1.3))   # mrrp


func _start_chase() -> void:
	if not _mate_ok(PLAY_R + 1.5):
		_end_play()
		return
	state = "chase"
	state_t = CHASE_T


## the run's over (got away, or gave up): maybe turn round and come for them
func _fled() -> void:
	if it_back and _mate_ok(PLAY_R + 1.0):
		it_back = false
		_stalk()
		state_t = rng.randf_range(0.4, 0.9)
		return
	it_back = false
	_end_play()


func _end_play() -> void:
	play_cd = rng.randf_range(2.5, 6.0)
	_pick()


## every game: a farm cat in "chase" touching MY cat = I got tagged. (the owner's state comes over
## world sync, so a chase run by someone else's game still lands on my cat here)
func _tag_check(dt: float) -> void:
	_tag_cd = maxf(_tag_cd - dt, 0.0)
	if state != "chase" or _tag_cd > 0.0 or react_t > 0.0:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if not p is CatPlayer or (p as CatPlayer).spar_dummy or not p.is_inside_tree():
			continue
		var pp: Vector3 = (p as Node3D).global_position
		var to := pp - global_position
		to.y *= 0.5
		if to.length() > TAG_REACH + 0.12:
			continue
		_tag_cd = 1.2
		var side := 0 if to.dot(global_transform.basis.x) < 0.0 else 1
		rig.swat(side, pp + Vector3.UP * 0.12, "jab")
		var sp: CatSpar = CatSpar.spar_of(p)
		if sp:
			_seq += 1
			sp._inbox.append([self, ["tag", _seq, "swat"]])
		if not NetWorld.forward(self, "play_got_one", [pp]):
			play_got_one(pp)
		return


## i tagged a cat (here, or in the game whose cat it was): you're it, i'm off
func play_got_one(at: Vector3) -> void:
	tags_given += 1
	_tag_cd = 1.2
	CatSfx.play_at("meow1", global_position, 0.5, rng.randf_range(1.15, 1.35))
	_flee_from(at)
	it_back = false
	play_cd = rng.randf_range(1.5, 3.0)


## the answer to my bop (cat_spar.gd): turned back = i stumble for a moment
func play_result(res: String) -> void:
	if res == "deflected":
		react = "swat"
		react_max = 0.45
		react_t = react_max
