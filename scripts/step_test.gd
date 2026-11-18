extends Node3D
## headless check that the cat never jumps by itself and steps up onto low stuff on its own.
## `godot --headless --path . res://steptest.tscn`: runs the cat (walk / trot / canter / gallop) into
## boxes, a round rock and a lying log of different heights, prints what happened to each.

const SPEEDS := {"walk": {"move": 0.5}, "trot": {}, "canter": {"canter": true}, "gallop": {"sprint": true}}
var cases := []
var ci := -1
var player: CatPlayer
var t := 0.0
var obst: Node3D
var peak_vy := 0.0
var air_t := 0.0
var max_air := 0.0
var got_on := false
var mounts := 0
var h := 0.0
var results := []


func _ready() -> void:
	var floor_b := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40, 1, 40)
	fs.shape = bx
	fs.position.y = -0.5
	floor_b.add_child(fs)
	add_child(floor_b)
	for sp in SPEEDS:
		for hh in [0.06, 0.1, 0.15, 0.2, 0.22, 0.26, 0.35]:
			cases.append(["box", hh, sp])
		for hh in [0.15, 0.2, 0.3]:
			cases.append(["rock", hh, sp])
		for hh in [0.12, 0.2]:
			cases.append(["log", hh, sp])
	player = CatPlayer.new()
	add_child(player)
	_next()


func _next() -> void:
	if ci >= 0:
		var c: Array = cases[ci]
		var r := "%-6s %-5s h=%.2f  on top: %-5s  step ups %d  peak vy %.2f  max air %.2fs" % [c[2], c[0], c[1], str(got_on), mounts, peak_vy, max_air]
		print("[step] ", r)
		results.append([c, got_on, peak_vy, max_air])
	ci += 1
	if ci >= cases.size():
		_summary()
		get_tree().quit()
		return
	if obst:
		obst.queue_free()
	var c: Array = cases[ci]
	h = c[1]
	obst = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	match c[0]:
		"box":
			var b := BoxShape3D.new()
			b.size = Vector3(3, h, 1.5)
			cs.shape = b
			cs.position = Vector3(0, h * 0.5, -2.75)
		"rock":
			var s := SphereShape3D.new()
			s.radius = 0.5
			cs.shape = s
			cs.position = Vector3(0, h - 0.5, -2.6)
		"log":
			var cy := CylinderShape3D.new()
			cy.radius = h * 0.5
			cy.height = 3.0
			cs.shape = cy
			cs.rotation.z = PI * 0.5
			cs.position = Vector3(0, h * 0.5, -2.4)
	obst.add_child(cs)
	add_child(obst)
	player.global_position = Vector3(0, 0.02, 2.0)
	player.velocity = Vector3.ZERO
	player.wall_collider = null
	player.yaw = 0.0
	player.orb_yaw = 0.0
	var b2 := {"move": Vector2(0, SPEEDS[c[2]].get("move", 1.0)), "yaw": 0.0, "pitch": -0.1}
	for k in SPEEDS[c[2]]:
		if k != "move":
			b2[k] = SPEEDS[c[2]][k]
	player.bot = b2
	t = 0.0
	peak_vy = 0.0
	air_t = 0.0
	max_air = 0.0
	got_on = false
	mounts = 0
	_was_m = false


var _was_m := false

func _physics_process(dt: float) -> void:
	t += dt
	if t < 0.05:
		return
	peak_vy = maxf(peak_vy, player.velocity.y)
	if player.mantling and not _was_m:
		mounts += 1
	_was_m = player.mantling
	if OS.get_environment("STEP_DBG") == str(ci) and t < 1.6:
		print("  t=%.3f y=%.3f z=%.3f vy=%.2f floor %s mant %s %s" % [t, player.global_position.y, player.global_position.z, player.velocity.y, player.is_on_floor(), player.mantling, player.last_event])
	if not player.is_on_floor() and not player.mantling:
		air_t += dt
		max_air = maxf(max_air, air_t)
	else:
		air_t = 0.0
	if player.global_position.y > h * 0.6 and player.is_on_floor():
		got_on = true
	# a walk is ~1 m/s now (momentum: half tilt = walk), so it gets longer to reach the obstacle
	var limit := 5.5 if player.bot.get("move", Vector2.ONE).y < 0.6 else 3.0
	if t > limit or player.global_position.z < -4.0:
		_next()


func _summary() -> void:
	var bad := 0
	for r in results:
		var c: Array = r[0]
		# never a leap: no launch faster than a tiny settle, never really airborne going up
		if r[2] > 1.0:
			bad += 1
			print("[step] FAIL leapt: ", c)
		var should: bool = c[1] <= 0.22
		if c[0] == "box" and should != r[1]:
			bad += 1
			print("[step] FAIL box %.2f on top %s (expected %s)" % [c[1], r[1], should])
	print("[step] done, %d problems" % bad)
