extends Node3D
## psx night level: "pier 9 pump house". builds env, level, player cat, hud and the psx post filter.
##   keys: 1-7 teleport to test spots, r respawn, f1 psx filter on/off, f2 pixel size,
##         f3 vertex wobble strength, f5 back to the living room
## run with `-- --still x,y,z,tx,ty,tz` to render a single still (used for previews)

var player: CatPlayer
var info := {}
var env: Environment
var hud: CanvasLayer
var hud_label: Label
var event_label: Label
var help_label: Label
var post_rect: ColorRect
var post_mat: ShaderMaterial
var psx_on := true
var lines_opts := [240.0, 180.0, 320.0, 480.0]
var lines_i := 0
var snap_opts := [160.0, 100.0, 240.0, 0.0]
var snap_i := 0
var t := 0.0
var still_cam: Camera3D
var tour := false


func _ready() -> void:
	PSX.setup_globals()
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_scale = 0.5
	_setup_env()
	info = StealthLevel.build(self)
	player = CatPlayer.new()
	player.position = info.spawn
	player.yaw = info.spawn_yaw
	add_child(player)
	Hub.arrive(player)
	# cat sized hole in the west wall bricks, next to the spawn: back to the farm (hub.gd)
	Hub.exit(self, Vector3(-StealthLevel.HALL_X + 0.02, 0.0, 4.4), Vector3(1, 0, 0), "docks", Vector2(0.42, 0.3), "farm")
	_build_hud()
	var args := OS.get_cmdline_user_args()
	var si := args.find("--still")
	if si >= 0:
		var v := args[si + 1].split_floats(",")
		hud.visible = false
		still_cam = Camera3D.new()
		still_cam.fov = 70
		still_cam.near = 0.02
		still_cam.far = 300
		add_child(still_cam)
		still_cam.current = true
		still_cam.global_position = Vector3(v[0], v[1], v[2])
		still_cam.look_at(Vector3(v[3], v[4], v[5]), Vector3.UP)
		player.process_mode = Node.PROCESS_MODE_DISABLED
	elif "--tour" in args:
		tour = true
		hud.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		still_cam = Camera3D.new()
		still_cam.fov = 72
		still_cam.near = 0.02
		still_cam.far = 300
		add_child(still_cam)
		still_cam.current = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.5)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	# psx draw distance fog: everything sinks into murky blue-black
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.1)
	env.fog_light_energy = 1.0
	env.fog_density = 0.045
	env.fog_sky_affect = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.08
	we.environment = env
	add_child(we)

	# cold moonlight through the skylights / over the dock
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.35
	moon.light_specular = 0.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 30.0
	moon.rotation = Vector3(deg_to_rad(-55), deg_to_rad(25), 0)
	add_child(moon)


func _build_hud() -> void:
	# post filter layer sits between the 3d world and the hud
	var post := CanvasLayer.new()
	post.layer = 1
	add_child(post)
	post_rect = ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = PSX.post_material()
	post_rect.material = post_mat
	post.add_child(post_rect)
	_apply_look()

	hud = CanvasLayer.new()
	hud.layer = 2
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
	help_label.offset_top = -132
	help_label.offset_left = 18
	_style(help_label, 15)
	help_label.text = "w/s move · a/d side hop · shift canter (double tap = gallop) · c stalk · space hop / wall kick · alt or mouse4 dodge · q or mmb aimed leap · rmb claws · f scratch · v camera\n1-7 teleport: hall, crate stairs, rack, wall kick shaft, office, containers, crane · r respawn\nf1 psx filter · f2 pixel size · f3 vertex wobble · h hide help\ntry: kick up the shaft by the east wall into the duct, walk the i-beams, climb the crane leg"
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
	l.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)


func _apply_look() -> void:
	post_rect.visible = psx_on
	post_mat.set_shader_parameter("lines", lines_opts[lines_i])
	PSX.snap_lines = snap_opts[snap_i] if psx_on else 0.0
	PSX.affine = 1.0 if psx_on else 0.0
	PSX.apply_globals()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_7:
		var pts: Array = info.points
		var i := k - KEY_1
		if i < pts.size():
			_teleport(pts[i][1], pts[i][2])
			player.toast = pts[i][0]
			player.toast_t = 0.0
	match k:
		KEY_R:
			_teleport(info.spawn, info.spawn_yaw)
		KEY_F1:
			psx_on = not psx_on
			_apply_look()
		KEY_F2:
			lines_i = (lines_i + 1) % lines_opts.size()
			_apply_look()
		KEY_F3:
			snap_i = (snap_i + 1) % snap_opts.size()
			_apply_look()
		KEY_H:
			help_label.visible = not help_label.visible
		KEY_F5:
			Hub.go_home(self, "docks")


func _teleport(p: Vector3, yaw: float) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.yaw = yaw
	player.pitch = 0.0


func _process(dt: float) -> void:
	t += dt
	StealthLevel.animate(t)
	if tour:
		_tour_cam()
	if player and player.global_position.y < -0.9:
		# fell in the harbor
		_teleport(info.spawn, info.spawn_yaw)
		player.toast = "splash. back to the hall"
		player.toast_t = 0.0
	if hud_label == null or not hud.visible:
		return
	var v := player.velocity
	var hs := Vector2(v.x, v.z).length()
	hud_label.text = "%d fps   %s\n%.1f m/s   height %.2f m   kicks %d" % [Engine.get_frames_per_second(), "psx %dp" % int(lines_opts[lines_i]) if psx_on else "psx off", hs, player.global_position.y, player.kicks_left]
	if player.toast_t < 1.2:
		event_label.text = player.toast
		event_label.modulate.a = 1.0 - player.toast_t / 1.2
	else:
		event_label.text = ""


# ------------------------------------------------------------------ flythrough (for preview videos)
const TOUR := [
	# [time, cam pos, look at] (cat eye height shots mixed with overviews)
	[0.0, Vector3(-9.5, 0.25, 4.5), Vector3(-4, 0.6, -4)],
	[4.0, Vector3(-7.4, 0.35, -2.6), Vector3(-7.0, 2.0, -8.0)],
	[8.0, Vector3(-6.6, 2.95, -9.0), Vector3(4, 2.4, -9.3)],
	[12.0, Vector3(-1.0, 4.85, -6.5), Vector3(10, 4.5, -6.5)],
	[16.0, Vector3(9.5, 4.85, -2.0), Vector3(11.6, 1.5, 1.6)],
	[20.0, Vector3(11.6, 0.3, 3.6), Vector3(11.6, 4.0, 0.8)],
	[24.0, Vector3(11.6, 4.27, 0.2), Vector3(11.6, 4.2, -6.0)],
	[28.0, Vector3(8.5, CATWALK_Y + 0.9, -9.6), Vector3(8.5, 3.0, -5.5)],
	[32.0, Vector3(0.0, 0.25, 3.5), Vector3(0.0, 0.3, 12.0)],
	[36.0, Vector3(-1.0, 0.22, 8.5), Vector3(-12, 3.0, 13)],
	[40.0, Vector3(-11.0, 5.5, 16.5), Vector3(10, 6.0, 20)],
	[44.0, Vector3(10.0, 9.6, 17.5), Vector3(-2, 2.0, 8.0)],
	[48.0, Vector3(16.0, 3.0, 22.0), Vector3(0, 2.0, 6.0)],
]
const CATWALK_Y := 2.6


func _tour_cam() -> void:
	var k := TOUR.size() - 1
	for i in TOUR.size() - 1:
		if t < TOUR[i + 1][0]:
			k = i
			break
	if k >= TOUR.size() - 1:
		get_tree().quit()
		return
	var a: Array = TOUR[k]
	var b: Array = TOUR[k + 1]
	var f: float = smoothstep(0.0, 1.0, (t - a[0]) / (b[0] - a[0]))
	var p: Vector3 = (a[1] as Vector3).lerp(b[1], f)
	var l: Vector3 = (a[2] as Vector3).lerp(b[2], f)
	still_cam.global_position = p
	still_cam.look_at(l, Vector3.UP)
