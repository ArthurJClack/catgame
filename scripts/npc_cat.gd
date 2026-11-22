class_name NpcCat
extends Node3D
## wandering background cat: idles, looks around, walks, trots, zooms, sits.
## tab on it and it's a play fight like any other cat (cat_spar.gd): a bop makes it flinch and
## scamper off (play_tag)

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
	state = "move"
	state_t = 3.0 + delay
	want_speed = 2.6 if rng.randf() < 0.6 else 4.5
	speed = 0.0 if delay > 0.0 else speed


func _process(dt: float) -> void:
	state_t -= dt
	if react_t > 0.0:
		react_t = maxf(react_t - dt, 0.0)
		if react_t <= 0.0:
			react = ""
	var vel := Vector3.ZERO
	match state:
		"move":
			var to := target - global_position
			to.y = 0
			var d := to.length()
			if d < 0.15 or state_t < 0:
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
	# look around when idle
	look_t -= dt
	if look_t < 0.0:
		look_t = rng.randf_range(0.8, 2.5)
		look_target = rng.randf_range(-0.9, 0.9) if state != "move" else 0.0
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
