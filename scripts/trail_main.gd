extends Node3D
## the running trail (res://trail.tscn): a loop of rough singletrack to run. the cat glides over roots
## and branches and steps up onto low stones and steps by itself (run_assist.gd + the step up in
## cat_player.gd). logs, big rocks and the creek need a jump (space).
##   r restart at the trailhead · t jump to the next section · b auto step on/off · 1-8 swap cat
##   v camera · h hide help · f5 back to the house · tab lock on
## preview: `-- --still x,y,z,tx,ty,tz`, `-- --run` (a bot runs the loop with a camera director, for
## the preview video), `-- --runtest` (bot lap, prints every step up + jump and where it got stuck)

var player: CatPlayer
var info := {}
var hud: CanvasLayer
var hud_label: Label
var event_label: Label
var help_label: Label
var sec_i := 0
var t := 0.0
var cam: Camera3D
var run_bot := false
var run_test := false
var lap_s := 0.0          # distance run along the trail this session
var _last_s := 0.0
var jumps := 0
var steps := 0
var _was_floor := true
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_init := false
var _mode := ""
var _slow := 1.0
var _bot_log: Array = []
var _stuck_t := 0.0
var _land_ok := 0
var _was_mantle := false


func _ready() -> void:
	process_priority = 10   # after the player, so the camera director sees this frame's cat
	_setup_env()
	info = TrailLevel.build(self)
	player = CatPlayer.new()
	player.position = info.spawn
	player.yaw = info.spawn_yaw
	player.orb_yaw = info.spawn_yaw
	add_child(player)
	if Engine.has_meta("cat_style"):
		player.set_style.call_deferred(Engine.get_meta("cat_style"))
	_build_hud()
	_build_farm_exit()
	var args := OS.get_cmdline_user_args()
	var si := args.find("--still")
	run_bot = "--run" in args or "--runtest" in args
	run_test = "--runtest" in args
	if si >= 0:
		hud.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		_make_cam()
		var v := args[si + 1].split_floats(",")
		cam.global_position = Vector3(v[0], v[1], v[2])
		cam.look_at(Vector3(v[3], v[4], v[5]), Vector3.UP)
	elif run_bot:
		player.bot = {"move": Vector2(0, 1), "yaw": info.spawn_yaw, "pitch": -0.12}
		player.log_events = run_test
		help_label.visible = false
		# the preview uses the orange tabby: a black cat disappears in the forest shade
		var vs := args.find("--style")
		player.set_style.call_deferred(args[vs + 1] if vs >= 0 else "block")
		_make_cam()
	elif not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_last_s = TrailLevel.nearest(player.global_position.x, player.global_position.z)[1]


func _make_cam() -> void:
	cam = Camera3D.new()
	cam.fov = 62
	cam.near = 0.02
	cam.far = 300
	add_child(cam)
	cam.current = true


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.52, 0.78)
	psm.sky_horizon_color = Color(0.86, 0.78, 0.62)
	psm.ground_horizon_color = Color(0.5, 0.48, 0.36)
	psm.ground_bottom_color = Color(0.2, 0.22, 0.15)
	psm.sun_angle_max = 20.0
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.7, 0.6)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.4
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_hdr_threshold = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.74, 0.62)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(1.0, 0.92, 0.78)
	env.volumetric_fog_length = 36.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	# late afternoon: low warm sun raking across the trail so every lump and root throws a shadow
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.84, 0.62)
	sun.light_energy = 1.9
	sun.light_volumetric_fog_energy = 2.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.2
	sun.shadow_blur = 1.2
	sun.rotation = Vector3(deg_to_rad(-24), deg_to_rad(-62), 0)
	add_child(sun)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	hud_label = Label.new()
	hud_label.position = Vector2(18, 58)   # under the health + stamina bars (souls_hud.gd)
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
	help_label.offset_top = -92
	help_label.offset_left = 18
	_style(help_label, 15)
	help_label.text = "the trail: roots, logs, a rock garden, stone steps, drop offs, a creek. run it (shift canter, double tap shift gallop)\nthe cat glides over roots + branches and steps up onto low stuff by itself. space to jump logs, rocks and the creek\nr restart · t next section · b auto step on/off · 1-8 swap cat · v camera · h hide help · f5 back to the house"
	hud.add_child(help_label)
	var ch := ColorRect.new()
	ch.color = Color(1, 1, 1, 0.7)
	ch.size = Vector2(4, 4)
	ch.anchor_left = 0.5
	ch.anchor_top = 0.5
	ch.offset_left = -2
	ch.offset_top = -2
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ch)


func _style(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if player == null or run_bot or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_8:
		var order: Array = CatRig.STYLE_ORDER
		if k - KEY_1 < order.size():
			player.set_style(order[k - KEY_1])
	match k:
		KEY_R:
			_place(0.3)
		KEY_T:
			sec_i = (sec_i + 1) % TrailLevel.markers.size()
			_place(TrailLevel.markers[sec_i][1] + 0.3)
			player._event(TrailLevel.markers[sec_i][0])
		KEY_B:
			player.auto_step = not player.auto_step
			player._event("auto step " + ("on" if player.auto_step else "off"))
		KEY_H:
			help_label.visible = not help_label.visible
		KEY_F5:
			_go_home()


func _place(s: float) -> void:
	var f := TrailLevel.frame(s)
	var fwd: Vector3 = f[1]
	player.global_position = (f[0] as Vector3) + Vector3(0, 0.06, 0)
	player.velocity = Vector3.ZERO
	player.yaw = atan2(-fwd.x, -fwd.z)
	player.orb_yaw = player.yaw
	_last_s = s


func _go_home() -> void:
	Hub.go_home(self, "trail")


## farm gate just off the start line (hub.gd): two posts + sign, walk between them to go back
func _build_farm_exit() -> void:
	var f := TrailLevel.frame(0.3, 2.6)
	var left: Vector3 = f[2]
	var fwd: Vector3 = f[1]
	var c: Vector3 = f[0]
	for s in [-1.0, 1.0]:
		var post := Level.box(self, c + fwd * s * 0.55 + Vector3(0, 0.75, 0), Vector3(0.12, 1.5, 0.12), Hub.C_POST)
		post.name = "FarmGatePost"
	Level.rbox(self, c + Vector3(0, 1.55, 0), Vector3(1.22, 0.1, 0.12), Vector3(0, atan2(-fwd.z, fwd.x), 0), Hub.C_POST, false)
	Hub.exit(self, c - left * 0.1, -left, "trail", Vector2.ZERO, "farm")


func _physics_process(dt: float) -> void:
	if player == null:
		return
	var p := player.global_position
	var nr := TrailLevel.nearest(p.x, p.z)
	var s: float = nr[1]
	var ds := wrapf(s - _last_s, -TrailLevel.trail_len * 0.5, TrailLevel.trail_len * 0.5)
	if absf(ds) < 2.0:
		lap_s += ds
	_last_s = s
	var fl := player.is_on_floor()
	if player.mantling and not _was_mantle:
		steps += 1
		if run_test:
			print("[trail] step up #%d %s at s=%.1f (%s)" % [steps, player.last_event, s, TrailLevel.section(s)])
	_was_mantle = player.mantling
	if not fl and _was_floor and player.velocity.y > 0.5 and not player.mantling:
		jumps += 1
		if run_test:
			print("[trail] jump #%d at s=%.1f (%s) vy %.2f" % [jumps, s, TrailLevel.section(s), player.velocity.y])
	_was_floor = fl
	if p.y < TrailLevel.surface_y(p.x, p.z) - 1.5:
		_place(s)
	if run_bot:
		_bot(dt, s)


# ------------------------------------------------------------------ bot + camera director
const BOT_PACE := {"start": "trot", "roots": "trot", "logs": "canter", "rocks": "canter", "ledges": "canter", "drops": "trot", "creek": "canter", "debris": "gallop"}


func _bot(dt: float, s: float) -> void:
	var lap := int(floor(lap_s / TrailLevel.trail_len))
	var sec := TrailLevel.section(s)
	var pace: String = BOT_PACE.get(sec, "canter")
	if lap >= 1 and not run_test:
		pace = "canter" if pace != "trot" else "trot"
	var look := 1.4 + (1.2 if pace == "gallop" else 0.0)
	var tgt: Vector2 = TrailLevel.at(s + look)[0]
	var p := player.global_position
	var to := Vector2(tgt.x - p.x, tgt.y - p.z)
	var want := atan2(-to.x, -to.y)
	var cur: float = player.bot.get("yaw", player.yaw)
	player.bot.yaw = cur + clampf(wrapf(want - cur, -PI, PI), -5.0 * dt, 5.0 * dt)
	player.bot.canter = pace == "canter"
	player.bot.sprint = pace == "gallop"
	player.bot.move = Vector2(0, 1)
	# stuck (ran into something too tall to step up onto): jump, like a player would
	var hs := Vector2(player.velocity.x, player.velocity.z).length()
	_stuck_t = _stuck_t + dt if hs < 0.6 else 0.0
	player.bot.jump = _stuck_t > 0.5 and _stuck_t < 0.6
	if run_test:
		if lap_s > TrailLevel.trail_len + 2.0 or t > 120.0:
			print("[trail] lap done: %.1f m in %.1f s, %d step ups, %d jumps, stuck at %s" % [lap_s, t, steps, jumps, str(_bot_log)])
			get_tree().quit()
		if _stuck_t > 0.5 and (_bot_log.is_empty() or absf(_bot_log[-1] - s) > 1.0):
			_bot_log.append(snappedf(s, 0.1))
			print("[trail] stuck at s=%.1f (%s) pos %s" % [s, sec, str(p.snapped(Vector3.ONE * 0.01))])


func _process(dt: float) -> void:
	t += dt
	if player == null or hud_label == null:
		return
	if run_bot and not run_test:
		_director(dt)
	var v := player.velocity
	var hs := Vector2(v.x, v.z).length()
	var sec := TrailLevel.section(_last_s)
	hud_label.text = "%d fps\n%.1f m/s (%.0f km/h)   %s\nsection: %s   step ups %d   jumps %d   auto step %s" % [Engine.get_frames_per_second(), hs, hs * 3.6, player.surface, sec, steps, jumps, "on" if player.auto_step else "off"]
	if player.last_event_t < 0.9:
		event_label.text = player.last_event
		event_label.modulate.a = 1.0 - player.last_event_t / 0.9
	else:
		event_label.text = ""


## shot list for the preview: chase / side dolly / low front / first person, slow-mo on jumps in side shots
func _director(dt: float) -> void:
	hud.visible = false
	var rdt := dt / maxf(Engine.time_scale, 0.05)
	var lap := int(floor(lap_s / TrailLevel.trail_len))
	var sec := TrailLevel.section(_last_s)
	var mode := "chase"
	if lap == 0:
		mode = {"start": "chase", "roots": "low", "logs": "side", "rocks": "chase", "ledges": "side", "drops": "front", "creek": "side", "debris": "chase"}.get(sec, "chase")
	else:
		mode = "fp"
		if lap_s > TrailLevel.trail_len + 62.0:
			get_tree().quit()
	# the rig is interpolated to the frame (the body only moves on physics ticks)
	var p := player.rig.global_position
	var fwd := -player.global_transform.basis.z
	var left := Vector3(fwd.z, 0, -fwd.x)
	var a := TrailLevel.at(_last_s)
	var td: Vector2 = a[1]
	var tf := Vector3(td.x, 0, td.y)
	var tl := Vector3(td.y, 0, -td.x)
	if mode != _mode:
		_mode = mode
		_cam_init = false
	# the whole cat only renders in third person (in first person the body is shadow only)
	if player.third_person != (mode != "fp"):
		player.set_third_person(mode != "fp")
	if mode == "fp":
		player.cam.current = true
		player.bot.pitch = -0.22
		Engine.time_scale = 1.0
		return
	cam.current = true
	var want_pos := p
	var want_look := p + Vector3(0, 0.18, 0)
	var slow := 1.0
	match mode:
		"chase":
			want_pos = p - tf * 0.95 + tl * 0.18 + Vector3(0, 0.36, 0)
			want_look = p + tf * 0.6 + Vector3(0, 0.12, 0)
		"low":
			want_pos = p - tf * 0.7 + tl * 0.28 + Vector3(0, 0.14, 0)
			want_look = p + tf * 0.5 + Vector3(0, 0.12, 0)
		"side":
			want_pos = p + tl * 1.0 + tf * 0.2 + Vector3(0, 0.26, 0)
			want_look = p + tf * 0.25 + Vector3(0, 0.15, 0)
			if not player.is_on_floor():
				slow = 0.35
		"front":
			want_pos = p + tf * 1.2 + tl * 0.25 + Vector3(0, 0.24, 0)
			want_look = p + Vector3(0, 0.15, 0)
	# never let a rock or trunk block the shot: pull in toward the cat
	var eye := p + Vector3(0, 0.18, 0)
	var q := PhysicsRayQueryParameters3D.create(eye, want_pos)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want_pos = eye.lerp(hit.position, 0.85)
	# keep the camera above the ground and out of rocks
	var gy := TrailLevel.surface_y(want_pos.x, want_pos.z) + 0.1
	want_pos.y = maxf(want_pos.y, gy)
	# smooth the offset from the cat, not the world position, or the camera trails a metre behind at a run
	var off := want_pos - p
	var loff := want_look - p
	if not _cam_init:
		_cam_pos = off
		_cam_look = loff
		_cam_init = true
	_cam_pos = LowPoly.damp3(_cam_pos, off, 4.0, rdt)
	_cam_look = LowPoly.damp3(_cam_look, loff, 6.0, rdt)
	cam.global_position = p + _cam_pos
	cam.look_at(p + _cam_look, Vector3.UP)
	_slow = LowPoly.damp(_slow, slow, 10.0 if slow < _slow else 4.0, rdt)
	Engine.time_scale = _slow
