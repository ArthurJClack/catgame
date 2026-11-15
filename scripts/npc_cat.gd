class_name NpcCat
extends Node3D
## wandering background cat: idles, looks around, walks, trots, zooms, sits.

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


func _ready() -> void:
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


func _process(dt: float) -> void:
	state_t -= dt
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
