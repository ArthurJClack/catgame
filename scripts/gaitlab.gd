extends Node3D
## gait lab: drives a bare CatRig through scripted moves on a gridded floor and
## scores the animation (paw slide, duty, stride rate, head steadiness, track width,
## direct register). standalone scene, run with:
##   godot --path . res://gaitlab.tscn -- [--only walk,trot] [--style block] [--view side|top|front|quarter] [--report path.json] [--slow 0.33]

const G := 9.8
const LEG_NAMES := ["LF", "RF", "LH", "RH"]

var cat: CatRig
var cam: Camera3D
var chart: Control
var caption: Label
var view := "side"
var slow := 1.0
var style := "block"
var only: PackedStringArray = []
var report_path := ""
var dbg := false

var vel := Vector3.ZERO
var yaw := 0.0
var airborne := false
var cam_dist := 1.0

# metrics
var rest_h := [0.0, 0.0, 0.0, 0.0]
var m := {}
var results := {}
var hist := [] # contact history for the chart


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0:
		view = args[i + 1]
	i = args.find("--slow")
	if i >= 0:
		slow = float(args[i + 1])
	i = args.find("--style")
	if i >= 0:
		style = args[i + 1]
	i = args.find("--only")
	if i >= 0:
		only = args[i + 1].split(",")
	i = args.find("--report")
	if i >= 0:
		report_path = args[i + 1]
	dbg = "--dbg" in args
	_build_world()
	_run()


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.6, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12.0
	add_child(sun)
	# floor: one big static box, checker tiles 10 cm so sliding paws are obvious
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	cs.position.y = -0.5
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = floor(wp.xz * 10.0);
	float k = mod(c.x + c.y, 2.0);
	vec2 m = floor(wp.xz);
	float k2 = mod(m.x + m.y, 2.0);
	vec3 a = mix(vec3(0.33, 0.35, 0.38), vec3(0.4, 0.42, 0.45), k);
	ALBEDO = a * mix(0.85, 1.0, k2);
	ROUGHNESS = 0.95;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	mi.material_override = sm
	add_child(mi)
	# a little staircase + a cushion to test ground contact (far from the flat lanes)
	for k in 4:
		_block(Vector3(20.0, 0.03 + k * 0.03, -1.0 - k * 0.22), Vector3(0.8, 0.06 + k * 0.06, 0.22), Color(0.55, 0.42, 0.3))
	_block(Vector3(20.0, 0.12, -2.4), Vector3(0.8, 0.24, 1.0), Color(0.55, 0.42, 0.3))
	cam = Camera3D.new()
	cam.fov = 40
	cam.near = 0.02
	add_child(cam)
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(30, 24)
	caption.add_theme_font_size_override("font_size", 30)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(caption)
	chart = Control.new()
	chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	chart.draw.connect(_draw_chart)
	layer.add_child(chart)


func _block(center: Vector3, size: Vector3, col: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mi.material_override = mat
	body.add_child(mi)


## footfall chart (hildebrand style): one row per paw, filled while it is down
func _draw_chart() -> void:
	var vp := chart.get_viewport_rect().size
	var w := 420.0
	var x0 := vp.x - w - 30.0
	var y0 := 30.0
	chart.draw_rect(Rect2(x0 - 46, y0 - 8, w + 56, 4 * 22 + 12), Color(0, 0, 0, 0.45))
	var font := ThemeDB.fallback_font
	for l in 4:
		chart.draw_string(font, Vector2(x0 - 40, y0 + l * 22 + 15), LEG_NAMES[l], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var n := hist.size()
	var span := 240
	for k in mini(n, span):
		var h: int = hist[n - 1 - k]
		var x := x0 + w - (k + 1) * w / span
		for l in 4:
			if h & (1 << l):
				chart.draw_rect(Rect2(x, y0 + l * 22 + 2, w / span + 0.5, 16), Color(0.95, 0.75, 0.3))


func _spawn(at: Vector3) -> void:
	if cat:
		cat.queue_free()
	cat = CatRig.new()
	cat.style = style
	add_child(cat)
	cat.position = at
	cat.rotation.y = 0.0
	yaw = 0.0
	vel = Vector3.ZERO
	airborne = false
	hist.clear()


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.4, 0), p + Vector3(0, -1.0, 0))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else 0.0


## the point of the paw that touches the ground (the rig pivots the paw about it)
func _contact(i: int) -> Vector3:
	var paw: Node3D = cat.legs[i].paw
	return paw.global_transform * (Vector3(0, -0.010, 0.006) if i < 2 else Vector3(0, -0.008, 0.014))


func _down(i: int) -> bool:
	var gp := _contact(i)
	return gp.y - _ground_y(gp) < rest_h[i] + 0.004


func _begin(name: String) -> void:
	m = {"name": name, "t": 0.0, "down": [false, false, false, false], "plant": [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
		"last": [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO], "path": [0.0, 0.0, 0.0, 0.0],
		"slides": [], "down_t": [0.0, 0.0, 0.0, 0.0], "td": [0, 0, 0, 0], "td_time": [[], [], [], []], "gap": [],
		"head_y": [], "chest_y": [], "head_x": [], "lat": [], "reg": [], "order": [], "front_td": [null, null], "miss": [], "frames": 0, "dist": 0.0}


func _sample(dt: float) -> void:
	m.t += dt
	m.frames += 1
	var mask := 0
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var g = cat.get("gait")
	for i in 4:
		var gp := _contact(i)
		var d := _down(i)
		if g != null and g.mode[i] == 0:
			m.miss.append((gp - (g.pos[i] as Vector3)).length())
			if dbg and (gp - (g.pos[i] as Vector3)).length() > 0.02:
				print("MISS t=%.2f leg=%s miss=%.0fmm stretch=%.2f spd=%.2f air=%s local=%s" % [m.t, LEG_NAMES[i], (gp - (g.pos[i] as Vector3)).length() * 1000.0, g.stretch[i], vel.length(), airborne, cat.to_local(g.pos[i])])
		if d:
			mask |= 1 << i
			m.down_t[i] += dt
			m.gap.append(absf(gp.y - _ground_y(gp) - rest_h[i]))
		if d and not m.down[i]:
			m.plant[i] = gp
			m.path[i] = 0.0
			m.td[i] += 1
			m.td_time[i].append(m.t)
			m.order.append(i)
			m.lat.append((gp - cat.global_position).dot(right))
			if i < 2:
				m.front_td[i] = gp
			elif m.front_td[i - 2] != null:
				var fp: Vector3 = m.front_td[i - 2]
				m.reg.append(Vector2(gp.x - fp.x, gp.z - fp.z).length())
		elif d and m.down[i]:
			var dl: Vector3 = gp - m.last[i]
			m.path[i] += Vector2(dl.x, dl.z).length()
		elif not d and m.down[i]:
			m.slides.append(m.path[i])
		m.down[i] = d
		m.last[i] = gp
	hist.append(mask)
	m.head_y.append(cat.head.global_position.y)
	m.chest_y.append(cat.chest.global_position.y)
	m.head_x.append((cat.head.global_position - cat.global_position).dot(right))
	chart.queue_redraw()


static func _std(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var mean := 0.0
	for v in a:
		mean += v
	mean /= a.size()
	var s := 0.0
	for v in a:
		s += (v - mean) * (v - mean)
	return sqrt(s / a.size())


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _max(a: Array) -> float:
	var s := 0.0
	for v in a:
		s = maxf(s, v)
	return s


func _end() -> void:
	var duty := []
	var freq := []
	for i in 4:
		duty.append(snappedf(m.down_t[i] / maxf(m.t, 0.001), 0.01))
		var tt: Array = m.td_time[i]
		freq.append(snappedf((tt.size() - 1) / maxf(tt[-1] - tt[0], 0.001), 0.01) if tt.size() > 1 else 0.0)
	var seq := ""
	for k in mini(m.order.size(), 12):
		seq += LEG_NAMES[m.order[k]] + " "
	var r := {
		"slide_mean_mm": snappedf(_mean(m.slides) * 1000.0, 0.1), "slide_max_mm": snappedf(_max(m.slides) * 1000.0, 0.1),
		"ik_miss_max_mm": snappedf(_max(m.miss) * 1000.0, 0.1), "ik_miss_mean_mm": snappedf(_mean(m.miss) * 1000.0, 0.1),
		"gap_max_mm": snappedf(_max(m.gap) * 1000.0, 0.1),
		"duty": duty, "stride_hz": freq,
		"head_y_std_mm": snappedf(_std(m.head_y) * 1000.0, 0.01), "chest_y_std_mm": snappedf(_std(m.chest_y) * 1000.0, 0.01),
		"head_x_std_mm": snappedf(_std(m.head_x) * 1000.0, 0.01),
		"track_width_mm": snappedf(_std(m.lat) * 2000.0, 0.1), "register_mm": snappedf(_mean(m.reg) * 1000.0, 0.1),
		"order": seq.strip_edges(), "steps": m.slides.size(),
	}
	results[m.name] = r
	print("LAB ", m.name, " ", JSON.stringify(r))


func _camera() -> void:
	var p := cat.global_position
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	match view:
		"top":
			cam.global_position = p + Vector3(0, 1.6 * cam_dist, 0.001)
			cam.look_at(p, Vector3(1, 0, 0))
		"front":
			cam.global_position = p + Vector3(0, 0.16, -1.1 * cam_dist)
			cam.look_at(p + Vector3(0, 0.13, 0), Vector3.UP)
		"quarter":
			cam.global_position = p + Vector3(0.75, 0.42, -0.75) * cam_dist
			cam.look_at(p + Vector3(0, 0.12, 0), Vector3.UP)
		"fixed":
			pass
		_:
			cam.global_position = Vector3(p.x + 1.15 * cam_dist, 0.2 + p.y * 0.6, p.z)
			cam.look_at(Vector3(p.x, 0.13 + p.y * 0.8, p.z), Vector3.UP)


## advance one frame: integrate the cat, feed the rig, sample metrics
func _step(want_speed: float, yaw_rate := 0.0, accel := 12.0, measure := true, local_dir := Vector3(0, 0, -1)) -> float:
	await get_tree().process_frame
	var dt := get_process_delta_time()
	# the rig animated last frame against the transform we gave it then: sample that before moving on
	if measure and m.has("t"):
		_sample(dt)
	yaw += yaw_rate * dt
	var b := Basis(Vector3.UP, yaw)
	var hv := Vector3(vel.x, 0, vel.z).move_toward(b * local_dir * want_speed, accel * dt)
	vel.x = hv.x
	vel.z = hv.z
	var p := cat.position
	var gy := _ground_y(p)
	if airborne:
		vel.y -= G * dt
		p += vel * dt
		if p.y <= gy and vel.y <= 0.0:
			p.y = gy
			vel.y = 0.0
			airborne = false
	else:
		p += Vector3(vel.x, 0, vel.z) * dt
		p.y = move_toward(p.y, _ground_y(p), 1.5 * dt)
		vel.y = 0.0
	cat.position = p
	cat.rotation.y = yaw
	cat.drive_velocity = vel
	cat.on_floor = not airborne
	_camera()
	return dt


func _settle(dur: float) -> void:
	var t := 0.0
	while t < dur:
		t += await _step(0.0, 0.0, 12.0, false)
	for i in 4:
		var gp: Vector3 = _contact(i)
		rest_h[i] = gp.y - _ground_y(gp)


func _want(name: String) -> bool:
	return only.is_empty() or name in only


func _straight(name: String, speed: float, dur: float, crouch := 0.0) -> void:
	if not _want(name):
		return
	_spawn(Vector3(0, 0, 0))
	cat.crouch = crouch
	cam_dist = 1.0 if speed < 4.0 else 1.5
	Engine.time_scale = 1.0
	await _settle(0.5)
	caption.text = "%s  %.1f m/s" % [name, speed]
	# run up, then measure at steady speed
	var t := 0.0
	while t < 0.8 + speed * 0.1:
		t += await _step(speed, 0.0, 12.0, false)
	Engine.time_scale = slow
	_begin(name)
	t = 0.0
	while t < dur * slow:
		t += await _step(speed)
	Engine.time_scale = 1.0
	_end()


func _run() -> void:
	await get_tree().process_frame
	await _straight("stalk", 0.25, 5.0, 1.0)
	await _straight("walk", 0.6, 4.0)
	await _straight("fastwalk", 0.9, 3.0)
	await _straight("trot", 1.8, 2.5)
	await _straight("run", 3.2, 2.5)
	await _straight("gallop", 6.0, 2.0)
	await _straight("sprint", 11.0, 2.0)

	if _want("circle"):
		_spawn(Vector3(8, 0, 0))
		cam_dist = 1.3
		await _settle(0.5)
		caption.text = "circle, 0.6 m/s, radius 0.5 m"
		var t := 0.0
		while t < 1.0:
			t += await _step(0.6, 1.2, 12.0, false)
		Engine.time_scale = slow
		_begin("circle")
		t = 0.0
		while t < 5.0 * slow:
			t += await _step(0.6, 1.2)
		Engine.time_scale = 1.0
		_end()

	if _want("turn"):
		_spawn(Vector3(12, 0, 0))
		cam_dist = 1.0
		await _settle(0.6)
		caption.text = "turn in place"
		Engine.time_scale = slow
		_begin("turn")
		var t := 0.0
		while t < 6.0 * slow:
			var ph := t / slow
			var yr := 0.0
			if ph > 0.3 and ph < 1.0:
				yr = 2.4
			elif ph > 2.2 and ph < 2.5:
				yr = -9.0
			elif ph > 4.0 and ph < 4.9:
				yr = 3.5
			t += await _step(0.0, yr)
		Engine.time_scale = 1.0
		_end()

	if _want("startstop"):
		_spawn(Vector3(16, 0, 0))
		cam_dist = 1.2
		await _settle(0.6)
		caption.text = "start, stop, strafe, back up"
		Engine.time_scale = slow
		_begin("startstop")
		var t := 0.0
		while t < 9.0 * slow:
			var ph := t / slow
			var sp := 0.0
			var dir := Vector3(0, 0, -1)
			if ph > 0.3 and ph < 1.6:
				sp = 3.2
			elif ph > 2.6 and ph < 3.6:
				sp = 0.7
			elif ph > 4.4 and ph < 5.6:
				sp = 0.6
				dir = Vector3(1, 0, 0)
			elif ph > 6.4 and ph < 7.6:
				sp = 0.5
				dir = Vector3(0, 0, 1)
			t += await _step(sp, 0.0, 16.0, true, dir)
		Engine.time_scale = 1.0
		_end()

	if _want("strafe"):
		_spawn(Vector3(28, 0, 0))
		cam_dist = 1.2
		await _settle(0.6)
		caption.text = "sideways, diagonal, backing up"
		Engine.time_scale = slow
		_begin("strafe")
		var t := 0.0
		while t < 9.0 * slow:
			var ph := t / slow
			var sp := 0.0
			var dir := Vector3(0, 0, -1)
			if ph > 0.3 and ph < 2.0:
				sp = 0.9
				dir = Vector3(1, 0, 0)
			elif ph > 2.6 and ph < 4.4:
				sp = 2.2
				dir = Vector3(-0.707, 0, -0.707)
			elif ph > 5.0 and ph < 6.4:
				sp = 0.9
				dir = Vector3(-1, 0, 0)
			elif ph > 7.0 and ph < 8.4:
				sp = 0.6
				dir = Vector3(0.6, 0, 0.8)
			t += await _step(sp, 0.0, 16.0, true, dir)
		Engine.time_scale = 1.0
		_end()

	if _want("sidehop"):
		_spawn(Vector3(32, 0, 0))
		cam_dist = 1.0
		await _settle(0.6)
		caption.text = "side hops"
		Engine.time_scale = slow
		_begin("sidehop")
		var t := 0.0
		var hops := 0
		var times := [0.5, 1.5, 2.5, 3.3]
		var dirs := [1.0, -1.0, -1.0, 1.0]
		while t < 4.5 * slow:
			var ph := t / slow
			if hops < 4 and ph > times[hops]:
				vel = Basis(Vector3.UP, yaw) * Vector3(dirs[hops] * 1.8, 1.15, 0)
				airborne = true
				hops += 1
			t += await _step(0.0, 0.0, 0.0 if airborne else 30.0)
		Engine.time_scale = 1.0
		_end()

	if _want("swat"):
		_spawn(Vector3(36, 0, 0))
		cam_dist = 0.8
		await _settle(0.6)
		caption.text = "swat right, swat left, claw hold"
		Engine.time_scale = slow
		_begin("swat")
		var t := 0.0
		var n := 0
		while t < 4.0 * slow:
			var ph := t / slow
			if n == 0 and ph > 0.4:
				n = 1
				cat.swat(1, cat.to_global(Vector3(-0.04, 0.12, -0.33)))
			if n == 1 and ph > 1.3:
				n = 2
				cat.swat(0, cat.to_global(Vector3(0.05, 0.05, -0.3)))
			cat.claw_on = ph > 2.2 and ph < 3.4
			cat.claw_i = 1
			cat.claw_target = cat.to_global(Vector3(0.03 + 0.03 * sin(ph * 5.0), 0.16, -0.31))
			t += await _step(0.0)
		Engine.time_scale = 1.0
		_end()

	if _want("stairs"):
		_spawn(Vector3(20, 0, 0))
		cam_dist = 1.2
		await _settle(0.6)
		caption.text = "steps, 0.5 m/s"
		Engine.time_scale = slow
		_begin("stairs")
		var t := 0.0
		while t < 6.5 * slow:
			t += await _step(0.5)
		Engine.time_scale = 1.0
		_end()

	if _want("jump"):
		_spawn(Vector3(24, 0, 0))
		cam_dist = 1.5
		await _settle(0.6)
		caption.text = "hop + landing"
		Engine.time_scale = slow
		_begin("jump")
		var t := 0.0
		var jumped := 0
		while t < 4.5 * slow:
			var ph := t / slow
			cat.charge = smoothstep(0.2, 0.5, ph) * (1.0 - smoothstep(0.78, 0.8, ph)) if ph < 1.0 else 0.0
			if (ph > 0.8 and jumped == 0) or (ph > 2.6 and jumped == 1):
				jumped += 1
				vel.y = 4.2
				airborne = true
			t += await _step(1.6 if ph > 0.8 else 0.0)
		Engine.time_scale = 1.0
		_end()

	if _want("sit"):
		_spawn(Vector3(40, 0, 0))
		cam_dist = 0.9
		await _settle(0.6)
		caption.text = "sit down, lie down, get up (in stages)"
		Engine.time_scale = slow
		_begin("sit")
		var t := 0.0
		while t < 9.0 * slow:
			var ph := t / slow
			cat.sit = 1.0 if (ph > 0.5 and ph < 6.6) else 0.0
			cat.loaf = 1.0 if (ph > 3.2 and ph < 5.6) else 0.0
			t += await _step(0.0)
		Engine.time_scale = 1.0
		_end()

	if _want("fall"):
		_spawn(Vector3(44, 0, 0))
		cam_dist = 1.7
		await _settle(0.4)
		caption.text = "falls: on its back (righting twist), then a long drop"
		Engine.time_scale = slow
		_begin("fall")
		var t := 0.0
		var n := 0
		while t < 5.0 * slow:
			var ph := t / slow
			if (n == 0 and ph > 0.3) or (n == 1 and ph > 2.6):
				cat.position.y = 1.9 if n == 0 else 1.5
				vel = Vector3(0, 0, -0.9) if n == 1 else Vector3.ZERO
				airborne = true
				cat.drive_velocity = vel
				cat.on_floor = false
				if n == 0:
					cat.tumble(0.5)
				n += 1
			t += await _step(0.9 if (n == 2 and airborne) else 0.0, 0.0, 0.0 if airborne else 12.0)
		Engine.time_scale = 1.0
		_end()

	if _want("hear"):
		_spawn(Vector3(48, 0, 0))
		cam_dist = 0.8
		await _settle(0.6)
		caption.text = "a quiet noise on the left (ears), a loud one behind right (head too)"
		Engine.time_scale = slow
		_begin("hear")
		var t := 0.0
		var n := 0
		while t < 5.0 * slow:
			var ph := t / slow
			if n == 0 and ph > 0.6:
				n = 1
				cat.hear(cat.to_global(Vector3(-2.0, 0.1, -0.5)), 0.4)
			if n == 1 and ph > 2.4:
				n = 2
				cat.hear(cat.to_global(Vector3(1.5, 0.1, 1.2)), 0.95)
			t += await _step(0.0)
		Engine.time_scale = 1.0
		_end()

	if _want("beam"):
		_block(Vector3(52, 0.15, -1.5), Vector3(0.09, 0.3, 5.0), Color(0.5, 0.4, 0.3))
		_spawn(Vector3(52, 0.3, 0.6))
		cam_dist = 1.1
		await _settle(0.8)
		caption.text = "narrow beam, 0.5 m/s: paws in line, tail out"
		Engine.time_scale = slow
		_begin("beam")
		var t := 0.0
		while t < 5.0 * slow:
			t += await _step(0.5)
		Engine.time_scale = 1.0
		_end()

	if report_path != "":
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	get_tree().quit()
