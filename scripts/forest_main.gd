extends Node3D
## forest level: builds sky/light, ForestLevel, wildlife, the player cat and a hud.
##   walk back out through the gate behind you (or press f5) to return to the yard.
##   t: teleport to the next landmark · 1-8 swap cat · h hide help
## `-- --still x,y,z,tx,ty,tz` renders a still, `-- --tour` a flythrough (preview video)

var player: CatPlayer
var info := {}
var env: Environment
var hud: CanvasLayer
var hud_label: Label
var event_label: Label
var help_label: Label
var critters: Array = []
var tp_i := 0
var t := 0.0
var cam: Camera3D
var tour := false
var leaving := false


func _ready() -> void:
	_setup_env()
	info = ForestLevel.build(self)
	critters = Critter.spawn_all(self)
	_spawn_mice()
	player = CatPlayer.new()
	player.position = info.spawn
	player.yaw = info.spawn_yaw
	add_child(player)
	if Engine.has_meta("cat_style"):
		player.set_style.call_deferred(Engine.get_meta("cat_style"))
	_build_gate_trigger()
	_build_hud()
	var args := OS.get_cmdline_user_args()
	var si := args.find("--still")
	if si >= 0 or "--tour" in args:
		hud.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		cam = Camera3D.new()
		cam.fov = 70
		cam.near = 0.02
		cam.far = 400
		add_child(cam)
		cam.current = true
		if si >= 0:
			var v := args[si + 1].split_floats(",")
			cam.global_position = Vector3(v[0], v[1], v[2])
			cam.look_at(Vector3(v[3], v[4], v[5]), Vector3.UP)
		else:
			tour = true
	elif not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_mice() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for p in [Vector2(-3.0, 24.0), Vector2(1.5, 21.0), Vector2(-12.0, -5.0), Vector2(5.0, -2.0), Vector2(-2.0, -10.0), Vector2(8.0, 14.0)]:
		var m := FieldMouse.new()
		m.position = ForestLevel.ground(p.x, p.y) + Vector3(0, 0.05, 0)
		add_child(m)


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.32, 0.5, 0.78)
	psm.sky_horizon_color = Color(0.78, 0.8, 0.72)
	psm.ground_horizon_color = Color(0.45, 0.55, 0.4)
	psm.ground_bottom_color = Color(0.2, 0.28, 0.18)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.72, 0.62)
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.8
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.2
	# hazy green depth, the far trees melt into it
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.75)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.95, 0.95, 0.85)
	env.volumetric_fog_length = 40.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.7
	sun.light_volumetric_fog_energy = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_blur = 1.5
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-140), 0)
	add_child(sun)


func _build_gate_trigger() -> void:
	var a := Area3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 3.0, 1.0)
	cs.shape = bs
	a.add_child(cs)
	a.position = ForestLevel.ground(0.0, 38.1) + Vector3(0, 1.0, 0)
	a.body_entered.connect(func(b: Node) -> void:
		if b == player:
			_go_home())
	add_child(a)


func _go_home() -> void:
	if leaving:
		return
	leaving = true
	Engine.set_meta("cat_spawn", "forest_gate")
	if player and player.get("style") != null:
		Engine.set_meta("cat_style", player.style)
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	hud_label = Label.new()
	hud_label.position = Vector2(18, 14)
	_style(hud_label, 18)
	hud.add_child(hud_label)
	event_label = Label.new()
	event_label.anchor_left = 0.5
	event_label.anchor_right = 0.5
	event_label.anchor_top = 0.62
	event_label.offset_left = -300
	event_label.offset_right = 300
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(event_label, 22)
	hud.add_child(event_label)
	help_label = Label.new()
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_top = -112
	help_label.offset_left = 18
	_style(help_label, 15)
	help_label.text = "the forest: deer + rabbits in the meadow, squirrels up the trees, birds, foxes, frogs by the stream, field mice to hunt\nstalk (c) to sneak up on things, rushing spooks them · trees, logs, stumps and the deer stand ladder are climbable\nt teleport to next landmark · 1-8 swap cat · v camera · h hide help · walk out the gate behind you (or f5) = back to the yard"
	hud.add_child(help_label)
	var ch := ColorRect.new()
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.color = Color(1, 1, 1, 0.7)
	ch.size = Vector2(4, 4)
	ch.anchor_left = 0.5
	ch.anchor_top = 0.5
	ch.offset_left = -2
	ch.offset_top = -2
	hud.add_child(ch)


func _style(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_8 and player.has_method("set_style"):
		var order: Array = CatRig.STYLE_ORDER
		if k - KEY_1 < order.size():
			player.set_style(order[k - KEY_1])
	match k:
		KEY_T:
			var pts: Array = info.points
			tp_i = (tp_i + 1) % pts.size()
			player.global_position = pts[tp_i][1]
			player.velocity = Vector3.ZERO
			player.yaw = pts[tp_i][2]
			player.last_event = pts[tp_i][0]
			player.last_event_t = 0.0
		KEY_H:
			help_label.visible = not help_label.visible
		KEY_F5, KEY_TAB:
			_go_home()


func _process(dt: float) -> void:
	t += dt
	if tour:
		_tour_cam()
		return
	if player == null or hud_label == null:
		return
	if player.global_position.y < -3.0:
		player.global_position = info.spawn
		player.velocity = Vector3.ZERO
	var v := player.velocity
	var hs := Vector2(v.x, v.z).length()
	var near := ""
	var best := 6.0
	for c in critters:
		var cr := c as Critter
		if cr.kind == "butterfly":
			continue
		var dd := cr.global_position.distance_to(player.global_position)
		if dd < best:
			best = dd
			near = "%s nearby (%s)" % [cr.kind, cr.state]
	hud_label.text = "%d fps\n%.1f m/s   height %.2f m   kicks %d\n%s" % [Engine.get_frames_per_second(), hs, player.global_position.y - ForestLevel.height(player.global_position.x, player.global_position.z), player.kicks_left, near]
	if player.last_event_t < 1.2:
		event_label.text = player.last_event
		event_label.modulate.a = 1.0 - player.last_event_t / 1.2
	else:
		event_label.text = ""


# ------------------------------------------------------------------ flythrough
func _tour_cam() -> void:
	var g := func(x: float, z: float, up: float) -> Vector3:
		return ForestLevel.ground(x, z) + Vector3(0, up, 0)
	var keys := [
		[0.0, g.call(0.0, 34.5, 0.28), g.call(0.0, 20.0, 1.0)],
		[5.0, g.call(0.5, 24.0, 0.3), g.call(-1.0, 12.0, 0.6)],
		[10.0, g.call(-0.5, ForestLevel.stream_z(0.0) + 3.0, 0.3), g.call(0.0, ForestLevel.stream_z(0.0) - 3.0, 0.2)],
		[15.0, g.call(0.0, -3.0, 0.35), g.call(0.0, -14.0, 0.8)],
		[21.0, g.call(-6.0, -9.0, 0.3), g.call(1.5, -16.0, 1.0)],
		[27.0, g.call(-8.5, -2.5, 1.0), g.call(-14.0, -9.5, 1.8)],
		[32.0, g.call(5.0, -2.0, 4.5), g.call(0.0, -14.0, 0.5)],
		[38.0, g.call(12.0, -11.0, 3.3), g.call(0.0, -14.0, 0.5)],
		[43.0, g.call(9.0, ForestLevel.stream_z(9.0) + 3.4, 0.6), g.call(9.0, ForestLevel.stream_z(9.0) - 3.0, 0.3)],
		[48.0, g.call(14.0, 11.5, 0.3), g.call(19.0, 7.0, -0.3)],
		[53.0, g.call(0.0, 10.0, 14.0), g.call(0.0, -10.0, 0.0)],
	]
	var k := keys.size() - 1
	for i in keys.size() - 1:
		if t < keys[i + 1][0]:
			k = i
			break
	if k >= keys.size() - 1:
		get_tree().quit()
		return
	var a: Array = keys[k]
	var b: Array = keys[k + 1]
	var f: float = smoothstep(0.0, 1.0, (t - a[0]) / (b[0] - a[0]))
	cam.global_position = (a[1] as Vector3).lerp(b[1], f)
	cam.look_at((a[2] as Vector3).lerp(b[2], f), Vector3.UP)
