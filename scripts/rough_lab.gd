extends Node3D
## rough ground lab: the real CatPlayer (bot driven) walks / trots / canters down a strip of
## uneven ground (bumps, roots, scattered rocks, a cross slope, low stone steps) and every
## frame the planted paws are checked against the actual ground under them.
##   godot --headless --path . res://roughlab.tscn -- --roughtest [--legacy] [--only walk,trot]
##   godot --path . res://roughlab.tscn -- --show [--legacy] --write-movie out/f.png --fixed-fps 30   (xvfb)
## --legacy turns the rough ground footwork off (CatGait.rough = false) for before / after.

const RUNS := {"walk": {"move": 0.5}, "trot": {}, "canter": {"canter": true}}
const Z0 := 1.0
const Z_END := -30.0
const SECTIONS := [["flat", 1.0, -4.0], ["bumps", -4.0, -9.0], ["roots", -9.0, -14.0], ["rocks", -14.0, -19.0], ["slope", -19.0, -24.0], ["steps", -24.0, -28.5], ["flat2", -28.5, -31.0]]
const LEG := ["LF", "RF", "LH", "RH"]

var player: CatPlayer
var cam: Camera3D
var show := false
var runs: Array = []
var ri := -1
var t := 0.0
var m := {}
var results := {}
var rest := [0.0, 0.0, 0.0, 0.0]
var rest_n := [0, 0, 0, 0]
var _rng := RandomNumberGenerator.new()
var _bodies: Array[RID] = []
var caption: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	show = "--show" in args
	process_priority = 100
	CatGait.rough = not ("--legacy" in args)
	var only := []
	var k := args.find("--only")
	if k >= 0:
		only = Array(args[k + 1].split(","))
	for r in RUNS:
		if only.is_empty() or r in only:
			runs.append(r)
	if show and only.is_empty():
		runs = ["walk", "trot"]
	_build()
	player = CatPlayer.new()
	add_child(player)
	if show:
		player.set_third_person(true)
		cam = Camera3D.new()
		cam.fov = 40.0
		cam.near = 0.02
		add_child(cam)
		cam.make_current()
		var cl := CanvasLayer.new()
		add_child(cl)
		caption = Label.new()
		caption.position = Vector2(24, 18)
		caption.add_theme_font_size_override("font_size", 30)
		caption.add_theme_color_override("font_outline_color", Color.BLACK)
		caption.add_theme_constant_override("outline_size", 8)
		cl.add_child(caption)
	_next()


# ---------------------------------------------------------------- ground

func _noise(x: float, z: float) -> float:
	return 0.018 * sin(x * 7.1 + z * 3.3) + 0.014 * sin(x * -4.3 + z * 8.9 + 1.7) + 0.01 * sin(x * 13.0 - z * 11.0 + 0.4)


func height(x: float, z: float) -> float:
	var h := 0.0
	var bw := smoothstep(-3.6, -4.4, z) * (1.0 - smoothstep(-8.6, -9.4, z))
	h += bw * (_noise(x, z) * 1.6 + 0.02 * sin(z * 5.2) * sin(x * 3.0 + 0.6))
	h += 0.4 * _noise(x * 1.3, z * 1.1) * smoothstep(-8.6, -9.4, z) * (1.0 - smoothstep(-23.6, -24.4, z))
	# cross slope ~15 deg
	var sw := smoothstep(-18.6, -19.6, z) * (1.0 - smoothstep(-23.4, -24.2, z))
	h += sw * 0.27 * x
	return h


func _build() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.85, 0.6, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12.0
	add_child(sun)
	_rng.seed = 7
	# heightmap strip
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.07
	var nx := int(3.0 / step)
	var nz := int((Z0 - Z_END) / step)
	for iz in nz:
		for ix in nx:
			var x0 := -1.5 + ix * step
			var z0 := Z0 - iz * step
			var a := Vector3(x0, height(x0, z0), z0)
			var b := Vector3(x0 + step, height(x0 + step, z0), z0)
			var c := Vector3(x0, height(x0, z0 - step), z0 - step)
			var d := Vector3(x0 + step, height(x0 + step, z0 - step), z0 - step)
			for v in [a, c, b, b, c, d]:
				st.set_color(_dirt(v))
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var body := StaticBody3D.new()
	body.set_meta("surface", "dirt")
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	body.add_child(mi)
	add_child(body)
	# roots: thin half buried cylinders across the path
	var z := -9.4
	while z > -13.8:
		var r := _rng.randf_range(0.018, 0.04)
		var ang := _rng.randf_range(-0.45, 0.45)
		_prop("cyl", Vector3(_rng.randf_range(-0.2, 0.2), height(0, z) + r * 0.25, z), Vector3(r, 2.4, r), Vector3(0, ang, PI * 0.5), Color(0.33, 0.24, 0.16))
		z -= _rng.randf_range(0.45, 0.8)
	# rocks: rotated boxes poking 3-9 cm out of the ground
	z = -14.3
	while z > -18.8:
		var s := Vector3(_rng.randf_range(0.07, 0.2), 0.0, _rng.randf_range(0.07, 0.18))
		var top := _rng.randf_range(0.03, 0.09)
		s.y = top + 0.1
		var x := _rng.randf_range(-0.28, 0.28)
		_prop("box", Vector3(x, height(x, z) + top - s.y * 0.5, z), s, Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(0, TAU), _rng.randf_range(-0.2, 0.2)), Color(0.5, 0.5, 0.48).lerp(Color(0.62, 0.6, 0.55), _rng.randf()))
		z -= _rng.randf_range(0.22, 0.5)
	# low stone steps: up three, down three
	var y := height(0, -24.3)
	var sz := -24.3
	for k in 6:
		var rise := 0.07 if k < 3 else -0.07
		y += rise if k < 3 else 0.0
		_prop("box", Vector3(0, y - 0.2, sz - 0.22), Vector3(2.4, 0.4, 0.44), Vector3.ZERO, Color(0.4, 0.39, 0.36) if k % 2 == 0 else Color(0.45, 0.43, 0.39))
		if k >= 3:
			y += rise
		sz -= 0.44
		if k == 2:
			sz -= 0.0


func _dirt(v: Vector3) -> Color:
	var g := 0.5 + 0.5 * sin(v.x * 9.0 + v.z * 5.0) * sin(v.z * 3.0)
	var c := Color(0.42, 0.33, 0.22).lerp(Color(0.36, 0.42, 0.22), g * 0.6)
	return c.lightened(clampf(v.y * 2.0, -0.2, 0.2))


func _prop(kind: String, pos: Vector3, size: Vector3, rot: Vector3, col: Color) -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", "wood" if kind == "cyl" else "tile")
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	if kind == "cyl":
		var c := CylinderShape3D.new()
		c.radius = size.x
		c.height = size.y
		cs.shape = c
		var cm := CylinderMesh.new()
		cm.top_radius = size.x
		cm.bottom_radius = size.x
		cm.height = size.y
		cm.radial_segments = 8
		mi.mesh = cm
	else:
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	mi.material_override = mat
	body.add_child(cs)
	body.add_child(mi)
	body.position = pos
	body.rotation = rot
	add_child(body)


# ---------------------------------------------------------------- runs

func _next() -> void:
	if ri >= 0:
		_report(runs[ri])
	ri += 1
	if ri >= runs.size():
		_summary()
		get_tree().quit()
		return
	var r: String = runs[ri]
	# the walk is slow: the video starts it at the roots
	var z0 := -8.4 if show and r == "walk" else Z0 - 0.3
	player.global_position = Vector3(0, height(0, z0) + 0.03, z0)
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.orb_yaw = 0.0
	var b := {"move": Vector2(0, RUNS[r].get("move", 1.0)), "yaw": 0.0, "pitch": -0.1}
	for k in RUNS[r]:
		if k != "move":
			b[k] = RUNS[r][k]
	player.bot = b
	t = 0.0
	m = {"sec": {}, "n": 0}
	if caption:
		# the trot goes by in slow motion so the footwork can be seen
		Engine.time_scale = 0.5 if r == "trot" else 1.0
		caption.text = ("before" if not CatGait.rough else "after") + "  -  " + r + ("  (half speed)" if r == "trot" else "")


func _sec(z: float) -> String:
	for s in SECTIONS:
		if z <= s[1] and z > s[2]:
			return s[0]
	return "flat2"


func _ground(p: Vector3) -> Array:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 0.3, p.z), Vector3(p.x, p.y - 0.6, p.z))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return [p.y - 1.0, Vector3.UP]
	return [(hit.position as Vector3).y, hit.normal]


func _contact(i: int) -> Vector3:
	var paw: Node3D = player.rig.legs[i].paw
	return paw.global_transform * (Vector3(0, -0.010, 0.006) if i < 2 else Vector3(0, -0.008, 0.014))


func _physics_process(dt: float) -> void:
	if ri < 0 or ri >= runs.size():
		return
	t += dt
	if player.global_position.z < Z_END + 1.5 or t > 40.0:
		_next()


# sampled after the rig has animated this frame (process_priority), against the transform
# it animated with: in physics the rig has already been moved on by the next tick
func _process(dt: float) -> void:
	if ri < 0 or ri >= runs.size():
		return
	if show:
		_camera(dt)
	if t > 0.6 and player.is_on_floor():
		_sample(player.global_position.z)


func _sample(pz: float) -> void:
	var g: CatGait = player.rig.gait
	var sec := _sec(pz)
	if not m.sec.has(sec):
		m.sec[sec] = {"gap": [], "hover": 0, "sink": 0, "planted": 0, "swing_clip": [], "miss": [], "over": 0, "frames": 0, "pitch_err": [], "roll_err": []}
	var s: Dictionary = m.sec[sec]
	s.frames += 1
	for i in 4:
		var c := _contact(i)
		var gr := _ground(c)
		var gap: float = c.y - float(gr[0])
		if g.mode[i] == CatGait.PLANTED and g.load[i] > 0.5:
			if sec == "flat" and t > 1.0:
				rest[i] += gap
				rest_n[i] += 1
			var r0: float = rest[i] / maxf(rest_n[i], 1)
			var e := gap - r0
			s.gap.append(absf(e))
			s.planted += 1
			if e > 0.012:
				s.hover += 1
			if e < -0.012:
				s.sink += 1
			s.miss.append((c - (g.pos[i] as Vector3)).length())
			if OS.get_environment("RL_DBG") == sec and absf(e) > 0.012:
				var gp: Vector3 = g.pos[i]
				print("DBG t=%.2f leg %s e=%.0fmm  gpos.y-ground=%.0fmm  contact-gpos=%s  stretch %.2f root %.3f" % [t, LEG[i], e * 1000, (gp.y - float(_ground(gp)[0])) * 1000, str((c - gp) * 1000).replace(" ", ""), g.stretch[i], player.global_position.y])
			if g.stretch[i] > 0.995:
				s.over += 1
		elif g.mode[i] == CatGait.SWING:
			# the toes (front of the paw) dragging through the ground
			var toe: Vector3 = player.rig.legs[i].paw.global_transform * Vector3(0, -0.01, -0.02)
			s.swing_clip.append(maxf(0.0, float(_ground(toe)[0]) - toe.y))
	# how well the body lines up with the ground under it: the line from the hip paws to
	# the shoulder paws vs the line through the chest and pelvis
	var ch: Vector3 = player.rig.chest.global_position
	var pe: Vector3 = player.rig.pelvis.global_position
	var gf: float = _ground(ch)[0]
	var gh: float = _ground(pe)[0]
	var span := Vector2(ch.x - pe.x, ch.z - pe.z).length()
	if span > 0.05:
		s.pitch_err.append(absf(((ch.y - gf) - (pe.y - gh)) / span))


static func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)


static func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(p * (b.size() - 1)), 0, b.size() - 1)]


func _report(run: String) -> void:
	var tot := {"planted": 0, "hover": 0, "sink": 0}
	var out := {}
	for sec in m.sec:
		var s: Dictionary = m.sec[sec]
		tot.planted += s.planted
		tot.hover += s.hover
		tot.sink += s.sink
		out[sec] = {
			"gap_mean_mm": snappedf(_mean(s.gap) * 1000.0, 0.1), "gap_p95_mm": snappedf(_pct(s.gap, 0.95) * 1000.0, 0.1),
			"hover_pct": snappedf(100.0 * s.hover / maxf(s.planted, 1), 0.1), "sink_pct": snappedf(100.0 * s.sink / maxf(s.planted, 1), 0.1),
			"swing_clip_max_mm": snappedf(_pct(s.swing_clip, 1.0) * 1000.0, 0.1), "swing_clip_p95_mm": snappedf(_pct(s.swing_clip, 0.95) * 1000.0, 0.1),
			"miss_p95_mm": snappedf(_pct(s.miss, 0.95) * 1000.0, 0.1), "over_pct": snappedf(100.0 * s.over / maxf(s.planted, 1), 0.1),
			"body_pitch_err": snappedf(_mean(s.pitch_err), 0.001),
		}
		print("ROUGH %s %-6s %s" % [run, sec, JSON.stringify(out[sec])])
	var bad: float = 100.0 * (tot.hover + tot.sink) / maxf(tot.planted, 1)
	results[run] = {"bad_pct": bad, "secs": out}
	print("ROUGH %s total: planted paw off the ground (>12 mm hover or sunk) %.1f%% of paw frames, %.1f s" % [run, bad, t])


func _summary() -> void:
	var fail := 0
	for r in results:
		var b: float = results[r].bad_pct
		var clip := 0.0
		for sec in results[r].secs:
			clip = maxf(clip, results[r].secs[sec].swing_clip_p95_mm)
		print("ROUGH %s: bad %.1f%%  worst swing clip p95 %.1f mm" % [r, b, clip])
		if CatGait.rough and (b > 8.0 or clip > 15.0):
			fail += 1
	print("ROUGHTEST ", "PASS" if fail == 0 else "FAIL (%d)" % fail, " (", "rough" if CatGait.rough else "legacy", ")")


func _camera(dt: float) -> void:
	var p := player.global_position
	var tgt := p + Vector3(0, 0.07, -0.1)
	var want := p + Vector3(0.85, 0.15, -0.3)
	# never under the ground (the cross slope rises toward the camera side)
	want.y = maxf(want.y, height(want.x, want.z) + 0.1)
	if cam.global_position.distance_to(want) > 2.0:
		cam.global_position = want
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-4.0 * dt))
	cam.look_at(tgt, Vector3.UP)
