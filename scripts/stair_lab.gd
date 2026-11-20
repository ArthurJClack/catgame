extends Node3D
## stairs camera check: runs the cat up and down staircases (glide steps, mount steps, a smooth
## ramp like the house stairs) at trot / canter / gallop and measures how much the camera's height
## jerks from one rendered frame to the next, in first person (head cam) and third person.
## `godot --path . res://stairlab.tscn --fixed-fps 60 -- --stairtest` (xvfb: the head cam needs the rig)
##   --old       step camera smoothing off (the before)
##   --film      one fp run up + down the big steps for a clip (with --write-movie)
##   --tp        film in third person

const SPEEDS := {"walk": {"move": 0.5}, "trot": {}, "canter": {"canter": true}, "gallop": {"sprint": true}}
const STAIRS := {"glide": [0.09, 0.30, 8], "mount": [0.17, 0.30, 8], "tall": [0.21, 0.32, 6], "ramp": [0.19, 0.27, 10]}
var cases := []
var ci := -1
var player: CatPlayer
var course: Node3D
var t := 0.0
var ys := PackedFloat32Array()
var results := []
var film := false
var end_z := 0.0
var label: Label
var dbg := OS.get_environment("STAIR_DBG") != ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	film = "--film" in args
	var floor_b := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	fs.shape = bx
	fs.position.y = -0.5
	floor_b.add_child(fs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fm.mesh = pm
	fm.material_override = _mat(Color(0.35, 0.42, 0.3))
	floor_b.add_child(fm)
	add_child(floor_b)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var only := ""
	for a in args:
		if a.begins_with("--case="):
			only = a.substr(7)
	if only != "":
		var o := only.split(",")
		cases.append([o[0], o[1], int(o[2])])
	elif film:
		cases.append(["mount", "trot", 0])
		cases.append(["glide", "canter", 0])
	else:
		var kind := ""
		for a in args:
			if a.begins_with("--kind="):
				kind = a.substr(7)
		for st in STAIRS:
			if kind != "" and st != kind:
				continue
			for sp in ["walk", "trot", "canter", "gallop"]:
				for vm in [0, 1]:
					cases.append([st, sp, vm])
	player = CatPlayer.new()
	add_child(player)
	if film:
		var cl := CanvasLayer.new()
		label = Label.new()
		label.position = Vector2(24, 18)
		label.add_theme_font_size_override("font_size", 34)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 8)
		label.text = "before: camera rides every step" if "--old" in args else "after: smooth stair camera"
		cl.add_child(label)
		add_child(cl)
	var tracker := Tracker.new()
	tracker.lab = self
	add_child(tracker)
	await get_tree().process_frame
	if "--old" in args:
		player.step_cam = false
	_next()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _box(pos: Vector3, size: Vector3, col: Color, solid := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = pos
	course.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
		sb.add_child(cs)
		sb.position = pos
		sb.set_meta("surface", "wood")
		course.add_child(sb)


## n steps up, a landing, n steps down, all along -z from z = 0
func _build(kind: String) -> void:
	if course:
		course.queue_free()
	course = Node3D.new()
	add_child(course)
	var s: Array = STAIRS[kind]
	var r: float = s[0]
	var tr: float = s[1]
	var n: int = s[2]
	var z := 0.0
	var ramp := kind == "ramp"
	for k in n:
		var h := r * (k + 1)
		_box(Vector3(0, h * 0.5, z - tr * 0.5), Vector3(1.2, h, tr), Color(0.55, 0.38, 0.22) if k % 2 == 0 else Color(0.62, 0.44, 0.27), not ramp)
		z -= tr
	var top := r * n
	_box(Vector3(0, top * 0.5, z - 0.75), Vector3(1.2, top, 1.5), Color(0.5, 0.5, 0.52))
	var land0 := z
	z -= 1.5
	var land1 := z
	for k in n:
		var h := r * (n - k)
		_box(Vector3(0, h * 0.5, z - tr * 0.5), Vector3(1.2, h, tr), Color(0.55, 0.38, 0.22) if k % 2 == 0 else Color(0.62, 0.44, 0.27), not ramp)
		z -= tr
	if ramp:
		# like the house stairs: one smooth ramp through the tread middles
		for side in [0, 1]:
			var z0 := (-tr * 0.5) if side == 0 else land1 - tr * 0.5
			var z1 := land0 + tr * 0.5 if side == 0 else z + tr * 0.5
			var y0 := 0.0 if side == 0 else top
			var y1 := top if side == 0 else 0.0
			var a := Vector3(0, y0, z0)
			var b := Vector3(0, y1, z1)
			var len := a.distance_to(b) + 0.1
			var ang := atan2(y1 - y0, z0 - z1)
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.2, 0.1, len)
			cs.shape = bs
			sb.add_child(cs)
			sb.transform = Transform3D(Basis(Vector3.RIGHT, ang), (a + b) * 0.5 + Basis(Vector3.RIGHT, ang) * Vector3(0, -0.05, 0))
			course.add_child(sb)
	end_z = z - 0.6
	if film:
		# things to judge the camera against: posts along both sides, a striped wall far ahead
		var zz := 1.5
		while zz > end_z - 2.0:
			for x in [-0.9, 0.9]:
				_box(Vector3(x, 0.6, zz), Vector3(0.05, 1.2, 0.05), Color(0.9, 0.9, 0.92), false)
			zz -= 0.6
		for k in 28:
			_box(Vector3(0, 0.25 + k * 0.25, end_z - 4.0), Vector3(14, 0.25, 0.2), Color(0.85, 0.3, 0.25) if k % 2 == 0 else Color(0.95, 0.92, 0.85), false)


func _next() -> void:
	if ci >= 0:
		results.append([cases[ci], _score()])
		var c: Array = cases[ci]
		var sc: Dictionary = results[-1][1]
		print("[stair] %-6s %-6s %s  max frame jolt %5.1f mm  rms %4.2f mm  max step %5.1f mm  top %s" % [c[0], c[1], "fp" if c[2] == 0 else "tp", sc.jolt, sc.rms, sc.step, str(sc.top)])
	ci += 1
	if ci >= cases.size():
		_summary()
		get_tree().quit()
		return
	var c: Array = cases[ci]
	_build(c[0])
	player.set_third_person(c[2] == 1 or (film and "--tp" in OS.get_cmdline_user_args()))
	player.global_position = Vector3(0, 0.02, 1.6)
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.orb_yaw = 0.0
	player.rotation.y = 0.0
	var pt := 0.08 if film else -0.12
	player.pitch = pt
	var b2 := {"move": Vector2(0, SPEEDS[c[1]].get("move", 1.0)), "yaw": 0.0, "pitch": pt}
	for k in SPEEDS[c[1]]:
		if k != "move":
			b2[k] = SPEEDS[c[1]][k]
	player.bot = b2
	t = 0.0
	ys = PackedFloat32Array()
	_top = false


var _top := false

func _physics_process(dt: float) -> void:
	if ci < 0 or ci >= cases.size():
		return
	t += dt
	var c: Array = cases[ci]
	var n: int = STAIRS[c[0]][2]
	if player.global_position.y > STAIRS[c[0]][0] * n - 0.03 and player.is_on_floor():
		_top = true
	var limit := 16.0 if c[1] == "walk" else 9.0
	if player.global_position.z < end_z or t > limit:
		_next()


## per rendered frame, after the head cam has moved
func sample() -> void:
	if ci < 0 or ci >= cases.size() or t < 0.3:
		return
	if player.global_position.z > 0.6 or player.global_position.z < end_z + 0.3:
		return
	ys.append(player.cam.global_position.y)
	if dbg:
		print("  t=%.3f z=%.3f body=%.3f cam=%.3f off=%.3f fl=%s m=%s blk=%s tp=%.3f ev=%s" % [t, player.global_position.z, player.global_position.y, player.cam.global_position.y, player.step_cam_off, player.is_on_floor(), player.mantling, player.head_cam_blocked, player._tp_dist, player.last_event])


func _score() -> Dictionary:
	var jolt := 0.0
	var sq := 0.0
	var step := 0.0
	for i in range(1, ys.size() - 1):
		var d2 := absf(ys[i + 1] - 2.0 * ys[i] + ys[i - 1])
		jolt = maxf(jolt, d2)
		sq += d2 * d2
		step = maxf(step, absf(ys[i + 1] - ys[i]))
	var rms := sqrt(sq / maxf(1.0, ys.size() - 2))
	return {"jolt": jolt * 1000.0, "rms": rms * 1000.0, "step": step * 1000.0, "top": _top}


func _summary() -> void:
	var worst := {}
	var bad := 0
	for r in results:
		var c: Array = r[0]
		var k := "%s %s" % [c[0], "fp" if c[2] == 0 else "tp"]
		worst[k] = maxf(worst.get(k, 0.0), r[1].jolt)
		if not r[1].top:
			print("[stair] FAIL never got up the stairs: ", c)
			bad += 1
	for k in worst:
		print("[stair] worst jolt %-10s %5.1f mm/frame^2" % [k, worst[k]])
	print("[stair] done, %d problems" % bad)


class Tracker extends Node:
	var lab: Node
	func _ready() -> void:
		process_priority = 100   # after HeadFollow (20)
	func _process(_dt: float) -> void:
		lab.sample()
