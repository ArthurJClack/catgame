class_name BiomeMain
extends Node3D
## shared scene script for the desert + the mountain (desert_main.gd / mountain_main.gd extend it):
## sky + sun + fog, the psx post filter, the cat, the way back to the farm, hud, keys, wildlife,
## sound and puzzles. a subclass fills in `key`, `build_level()` and `env_cfg()`.
##   r back to the start · t next spot (dev) · h hide help · m mute · f1 psx filter (dev) · f5 / farm sign = back
## preview: `-- --still x,y,z,tx,ty,tz` · `-- --tour` (camera flies the level for the clip, then quits)

var key := ""                 # Hub.DESTS key
var player: CatPlayer
var info := {}                # from build_level(): spawn, spawn_yaw, spots, exit, tour, ...
var puzzles: Puzzles
var sound: BiomeSound
var beasts: Array = []
var hud: CanvasLayer
var event_label: Label
var help_label: Label
var post_rect: ColorRect
var cam: Camera3D
var spot_i := 0
var t := 0.0
var tour := false
var still := false
var _tour_t := 0.0
var _tour_len := 0.0


# --- for the subclass
func build_level() -> Dictionary:
	return {}

func env_cfg() -> Dictionary:
	return {}

func spawn_wildlife() -> void:
	pass

func build_puzzles() -> void:
	pass

func help_text() -> String:
	return ""

func tick(_dt: float) -> void:
	pass


func _ready() -> void:
	process_priority = 10
	PSX.setup_globals()
	var args := OS.get_cmdline_user_args()
	tour = "--tour" in args
	var si := args.find("--still")
	still = si >= 0
	_setup_env()
	info = build_level()
	player = CatPlayer.new()
	var sp: Vector3 = info.spawn
	player.position = sp + Vector3(0, 0.05, 0)
	player.yaw = info.spawn_yaw
	player.orb_yaw = info.spawn_yaw
	add_child(player)
	Hub.arrive(player)
	var ex: Dictionary = info.exit
	Hub.exit(self, ex.pos, ex.normal, key, Vector2.ZERO, "farm")
	_build_hud()
	sound = BiomeSound.new()
	sound.name = "BiomeSound"
	sound.biome = key
	add_child(sound)
	Beast.ground = func(x: float, z: float) -> float: return BiomeKit.y(x, z)
	Beast.sound = sound
	spawn_wildlife()
	if still:
		hud.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.visible = false
		_make_cam()
		var v := args[si + 1].split_floats(",")
		player.souls_hud.visible = false
		# `--rel`: heights are above the ground under each point
		var rel := "--rel" in args
		cam.global_position = Vector3(v[0], v[1] + (BiomeKit.y(v[0], v[2]) if rel else 0.0), v[2])
		cam.look_at(Vector3(v[3], v[4] + (BiomeKit.y(v[3], v[5]) if rel else 0.0), v[5]), Vector3.UP)
	elif tour:
		hud.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.set_third_person(true)
		player.souls_hud.visible = false
		_make_cam()
		for s in info.tour:
			_tour_len += float(s[2])
		_tour_place(0.0)
	elif not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not still:
		build_puzzles()


## online (NetWorld): the authority's mill / drift state goes to everyone in the level.
## props (wedge, tumbleweeds, snowball) and the wildlife sync on their own as rigidbodies / critters
func net_level_pack() -> Dictionary:
	var b = puzzles.get_node_or_null("BiomePuzzles") if puzzles else null
	return b.net_state() if b is BiomePuzzles else {}


func net_level_apply(d: Dictionary) -> void:
	var b = puzzles.get_node_or_null("BiomePuzzles") if puzzles else null
	if b is BiomePuzzles:
		b.net_apply(d)


## static callables would outlive the level (and crash godot at quit): let go of them here
func _exit_tree() -> void:
	Beast.ground = Callable()
	Beast.sound = null
	BiomeKit.hfn = Callable()
	BiomeKit.sfn = Callable()
	BiomeKit.lv = null


func _make_cam() -> void:
	cam = Camera3D.new()
	cam.fov = 66
	cam.near = 0.02
	cam.far = 500
	add_child(cam)
	cam.current = true


func _setup_env() -> void:
	var c := env_cfg()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = c.get("sky_top", Color(0.3, 0.5, 0.8))
	psm.sky_horizon_color = c.get("sky_horizon", Color(0.8, 0.8, 0.8))
	psm.ground_horizon_color = c.get("ground_horizon", Color(0.6, 0.55, 0.5))
	psm.ground_bottom_color = c.get("ground_bottom", Color(0.3, 0.28, 0.25))
	psm.sun_angle_max = 12.0
	psm.sun_curve = 0.08
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = c.get("ambient", Color(0.6, 0.6, 0.6))
	env.ambient_light_energy = c.get("ambient_e", 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = c.get("exposure", 1.0)
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = c.get("fog", Color(0.8, 0.75, 0.7))
	env.fog_density = c.get("fog_density", 0.01)
	env.fog_sky_affect = c.get("fog_sky", 0.3)
	env.adjustment_enabled = true
	env.adjustment_saturation = c.get("sat", 1.0)
	env.adjustment_contrast = c.get("contrast", 1.06)
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = c.get("sun", Color(1, 0.9, 0.75))
	sun.light_energy = c.get("sun_e", 1.6)
	sun.light_specular = 0.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.15
	sun.shadow_normal_bias = 2.5
	var r: Vector3 = c.get("sun_rot", Vector3(-35, -40, 0))
	sun.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
	add_child(sun)


func _build_hud() -> void:
	# psx post filter between the world and the hud (same as pier 9)
	var post := CanvasLayer.new()
	post.layer = 1
	add_child(post)
	post_rect = ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_rect.material = PSX.post_material()
	post.add_child(post_rect)
	hud = CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
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
	help_label.offset_top = -76
	help_label.offset_left = 18
	_style(help_label, 15)
	help_label.text = help_text() + "\nr back to the start · h hide help · f5 back to the farm"
	help_label.visible = false   # h shows it (help text stays hidden by default, see controls diet)
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
	if player == null or tour or still or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	if DevKeys.blocked(k):
		return
	match k:
		KEY_R:
			_place(info.spawn, info.spawn_yaw)
		KEY_T:
			var spots: Array = info.get("spots", [])
			if not spots.is_empty():
				spot_i = (spot_i + 1) % spots.size()
				_place(spots[spot_i][1], spots[spot_i][2])
				player._event(spots[spot_i][0])
		KEY_H:
			help_label.visible = not help_label.visible
		KEY_M:
			if sound:
				sound.set_muted(not sound.muted)
		KEY_F1:
			post_rect.visible = not post_rect.visible
			PSX.snap_lines = 160.0 if post_rect.visible else 0.0
			PSX.affine = 1.0 if post_rect.visible else 0.0
			PSX.apply_globals()
		KEY_F5:
			Hub.go_home(self, key)


func _place(p: Vector3, yaw: float) -> void:
	player.global_position = p + Vector3(0, 0.1, 0)
	player._phys_curr = player.global_position
	player.velocity = Vector3.ZERO
	player.yaw = yaw
	player.orb_yaw = yaw


func _process(dt: float) -> void:
	t += dt
	if tour and cam:
		_tour_t += dt
		_tour_place(_tour_t)
		if _tour_t > _tour_len + 0.2:
			print("TOUR DONE")
			get_tree().quit()
	elif not still and player and player.global_position.y < float(info.get("kill_y", -20.0)):
		_place(info.spawn, info.spawn_yaw)   # fell out of the world somehow
	tick(dt)


## the clip's camera: catmull-rom through the tour keys [pos, look, seconds to the next]
func _tour_place(tt: float) -> void:
	var keys: Array = info.tour
	var acc := 0.0
	var i := 0
	while i < keys.size() - 1 and acc + float(keys[i][2]) < tt:
		acc += float(keys[i][2])
		i += 1
	var u := clampf((tt - acc) / maxf(float(keys[i][2]), 0.01), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65   # a touch of ease without stopping dead
	var g := func(j: int, f: int) -> Vector3: return keys[clampi(j, 0, keys.size() - 1)][f]
	var p := _cr(g.call(i - 1, 0), g.call(i, 0), g.call(i + 1, 0), g.call(i + 2, 0), u)
	var l := _cr(g.call(i - 1, 1), g.call(i, 1), g.call(i + 1, 1), g.call(i + 2, 1), u)
	cam.global_position = p
	if p.distance_to(l) > 0.01:
		cam.look_at(l, Vector3.UP)


static func _cr(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * b) + (-a + c) * u + (2.0 * a - 5.0 * b + 4.0 * c - d) * u2 + (-a + 3.0 * b - 3.0 * c + d) * u3)


## put a wild animal in the level (Beast, beasts.gd). meta = extra settings for that kind
func beast(kind: String, at: Vector3, meta := {}) -> Beast:
	var b := Beast.new()
	b.kind = kind
	b.home = Vector3(at.x, at.y if at.y != 0.0 else BiomeKit.y(at.x, at.z), at.z)
	for k in meta:
		b.set_meta(k, meta[k])
	add_child(b)
	beasts.append(b)
	return b
