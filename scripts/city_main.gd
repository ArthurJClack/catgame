extends Node3D
## the city street (res://city.tscn, f4 from the farm, gate in the back fence): secret's Pioneer
## Square, Seattle (real OpenStreetMap streets + elevation, psx look, Shitbox Rally cars parked on
## the curbs) at night, dressed up cyberpunk (city/city_neon.gd): neon, rain, steam, wet street.
## You're a cat, so the whole city is enormous: curbs are steps, parked cars are climbing frames,
## alley dumpsters + crates are the way up.
##   r back to the start · t next spot · 1-9 swap cat · v camera · h hide help · f5 / farm sign = back
## preview: `-- --still x,y,z,tx,ty,tz`, `-- --tour` (bot run + camera director for the clip),
## `-- --citytest` (builds, cat lands on the street, cars + neon + exit exist, prints one line)

const Builder := preload("res://scripts/city/city_builder.gd")
const Cars := preload("res://scripts/city/city_cars.gd")
const Neon := preload("res://scripts/city/city_neon.gd")
const DATA := "res://data/city/pioneer_square.json"
# S Main St between 1st Ave S and Occidental (where secret starts you), your three cars at the curb
const START := Vector3(-46, 0, 42.4)
const START_YAW := -PI * 0.5
const START_CARS := [["wrx_wagon", Vector3(-30, 0, 45.4)], ["crownvic", Vector3(-46, 0, 45.4)], ["civic_ep3", Vector3(-62, 0, 45.4)]]
# t cycles these: [name, pos, yaw]
const SPOTS := [
	["s main st", Vector3(-46, 0, 42.4), -PI * 0.5],
	["occidental square", Vector3(-10, 0, 0), PI],
	["1st ave s", Vector3(-89, 0, 100), PI],
	["the alley", Vector3(-40, 0, -90), 0.0],
	["s jackson st", Vector3(40, 0, 139), -PI * 0.5],
]
static var n_parked := 90

var player: CatPlayer
var builder
var cars
var neon
var data: Dictionary
var hud: CanvasLayer
var hud_label: Label
var event_label: Label
var help_label: Label
var cam: Camera3D
var rain: CPUParticles3D
var spot_i := 0
var t := 0.0
var tour := false
var test := false
var _mode := ""
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_init := false
var _stuck_t := 0.0
var _route_i := 0
# the tour bot's route: east along the S Main St sidewalk, then up Occidental Ave S (checked clear of buildings)
const ROUTE := [Vector2(-46, 42.4), Vector2(-20, 42.6), Vector2(4, 42.8), Vector2(11, 36.0), Vector2(11, 0.0), Vector2(11, -40.0), Vector2(11, -80.0), Vector2(11, -110.0)]


func _ready() -> void:
	process_priority = 10
	var args := OS.get_cmdline_user_args()
	tour = "--tour" in args
	test = "--citytest" in args
	_setup_env()
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	builder = Builder.new()
	add_child(builder)
	builder.build(data)
	_tag_ground()
	cars = Cars.new()
	add_child(cars)
	for sc in START_CARS:
		var p: Vector3 = sc[1]
		cars.park(sc[0], Transform3D(Basis(Vector3.UP, -PI * 0.5), _ground(p)), Color(0.72, 0.74, 0.76) if sc[0] == "wrx_wagon" else (Color(0.08, 0.08, 0.09) if sc[0] == "crownvic" else Color(0.45, 0.08, 0.08)))
	cars.fill(_free_spots(), n_parked, builder.terrain)
	neon = Neon.new()
	add_child(neon)
	neon.build(data, builder.terrain)
	player = CatPlayer.new()
	player.position = _ground(START, 0.25)
	player.yaw = START_YAW
	player.orb_yaw = START_YAW
	add_child(player)
	Hub.arrive(player)
	_build_hud()
	_build_farm_exit()
	_build_rain()
	var si := args.find("--still")
	if si >= 0:
		hud.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		_make_cam()
		var v := args[si + 1].split_floats(",")
		# heights are above the street (the ground climbs ~40 m across the map)
		cam.global_position = _ground(Vector3(v[0], 0, v[2]), v[1])
		cam.look_at(_ground(Vector3(v[3], 0, v[5]), v[4]), Vector3.UP)
		player.souls_hud.visible = false
	elif tour or test:
		help_label.visible = false
		player.bot = {"move": Vector2(0, 1), "yaw": START_YAW, "pitch": -0.1}
		var vs := args.find("--style")
		player.set_style.call_deferred(args[vs + 1] if vs >= 0 else "block")
		_make_cam()
	elif not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ground(p: Vector3, up := 0.0) -> Vector3:
	return builder.terrain.at_v(p, up)


## footsteps: the city's one big trimesh is street / sidewalk / stone
func _tag_ground() -> void:
	for c in builder.get_children():
		if c is StaticBody3D:
			c.set_meta("surface", "stone")


## parked spots not right on top of your three cars or the spawn
func _free_spots() -> Array:
	var out := []
	for s in data.get("parked", []):
		var p := Vector2(float(s["x"]), float(s["z"]))
		var near := p.distance_to(Vector2(START.x, START.z)) < 26.0
		if not near:
			out.append(s)
	return out


func _make_cam() -> void:
	cam = Camera3D.new()
	cam.fov = 64
	cam.near = 0.02
	cam.far = 600
	add_child(cam)
	cam.current = true


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	# smoggy night sky: the city glow lights the clouds from below (magenta at the horizon)
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.03, 0.02, 0.07)
	psm.sky_horizon_color = Color(0.38, 0.12, 0.42)
	psm.sky_curve = 0.12
	psm.ground_bottom_color = Color(0.05, 0.03, 0.08)
	psm.ground_horizon_color = Color(0.38, 0.12, 0.42)
	psm.sun_angle_max = 0.0
	psm.sky_energy_multiplier = 1.0
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.36, 0.62)
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.12, 0.38)
	env.fog_density = 0.008
	env.fog_sky_affect = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.08
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, 40, 0)
	moon.light_color = Color(0.55, 0.6, 0.9)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 30.0
	add_child(moon)


func _build_rain() -> void:
	rain = CPUParticles3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.8, 1.0, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := BoxMesh.new()
	q.size = Vector3(0.008, 0.35, 0.008)
	q.material = m
	rain.mesh = q
	rain.amount = 900
	rain.lifetime = 1.2
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(9, 0.5, 9)
	rain.direction = Vector3(0.1, -1, 0.05)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -4, 0)
	rain.initial_velocity_min = 9.0
	rain.initial_velocity_max = 11.0
	rain.preprocess = 1.2
	rain.visibility_aabb = AABB(Vector3(-12, -16, -12), Vector3(24, 18, 24))
	add_child(rain)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	hud_label = Label.new()
	hud_label.position = Vector2(18, 58)
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
	help_label.text = "the city: pioneer square at night (real osm map from secret, cars from shitbox rally). you're a cat: curbs are steps, cars are climbing frames\nhop onto hoods + roofs, alley dumpsters and crates go higher, hide under cars from the rain\nr back to the start · h hide help · f5 or the farm sign = back to the farm\nmap data (c) openstreetmap contributors, odbl"
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


## farm gate on the sidewalk just behind the start, a chain-link panel with a neon sign
func _build_farm_exit() -> void:
	var c := _ground(START + Vector3(-5.0, 0, -2.6), 0.15)
	var dir := Vector3(1, 0, 0)      # sign faces down the street toward the start
	for s in [-1.0, 1.0]:
		Level.box(self, c + Vector3(0, 0.75, s * 0.6), Vector3(0.08, 1.5, 0.08), Color(0.35, 0.36, 0.4)).name = "FarmGatePost"
	Level.box(self, c + Vector3(0, 1.52, 0), Vector3(0.08, 0.06, 1.28), Color(0.35, 0.36, 0.4), false)
	Hub.exit(self, c, dir, "city", Vector2.ZERO, "farm")


func _unhandled_input(event: InputEvent) -> void:
	if player == null or tour or test or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	if DevKeys.blocked(k):
		return
	if k >= KEY_1 and k <= KEY_9:
		var order: Array = CatRig.STYLE_ORDER
		if k - KEY_1 < order.size():
			player.set_style(order[k - KEY_1])
	match k:
		KEY_R:
			spot_i = 0
			_place(SPOTS[0])
		KEY_T:
			spot_i = (spot_i + 1) % SPOTS.size()
			_place(SPOTS[spot_i])
			player._event(SPOTS[spot_i][0])
		KEY_H:
			help_label.visible = not help_label.visible
		KEY_F5:
			Hub.go_home(self, "city")


func _place(s: Array) -> void:
	player.global_position = _ground(s[1], 0.3)
	player.velocity = Vector3.ZERO
	player.yaw = s[2]
	player.orb_yaw = s[2]


func _physics_process(dt: float) -> void:
	if player == null:
		return
	var p := player.global_position
	if p.y < builder.terrain.at(p.x, p.z) - 3.0:
		_place(SPOTS[spot_i])
	if tour or test:
		_bot(dt)


func _bot(dt: float) -> void:
	var p := player.global_position
	var tgt: Vector2 = ROUTE[mini(_route_i, ROUTE.size() - 1)]
	var to := Vector2(tgt.x - p.x, tgt.y - p.z)
	if to.length() < 1.5 and _route_i < ROUTE.size() - 1:
		_route_i += 1
	var want := atan2(-to.x, -to.y)
	var cur: float = player.bot.get("yaw", player.yaw)
	player.bot.yaw = cur + clampf(wrapf(want - cur, -PI, PI), -4.0 * dt, 4.0 * dt)
	player.bot.canter = true
	player.bot.sprint = t > 3.0 and t < 14.0
	player.bot.move = Vector2(0, 1) if _route_i < ROUTE.size() - 1 or to.length() > 1.0 else Vector2.ZERO
	var hs := Vector2(player.velocity.x, player.velocity.z).length()
	_stuck_t = _stuck_t + dt if hs < 0.5 else 0.0
	player.bot.jump = _stuck_t > 0.4 and _stuck_t < 0.5
	if test and t > 6.0:
		_report()


func _report() -> void:
	var p := player.global_position
	var gy: float = builder.terrain.at(p.x, p.z)
	var moved := Vector2(p.x - START.x, p.z - START.z).length()
	var exits := get_tree().get_nodes_in_group("hub_trigger").filter(func(n: Node) -> bool: return is_ancestor_of(n)).size()
	var ok: bool = player.is_on_floor() and p.y > gy - 0.5 and p.y < gy + 3.0 and moved > 4.0 and cars.cars.size() > 40 and neon.lights > 10 and exits >= 1
	print("[city] %s: on floor %s, y %.2f ground %.2f, ran %.1f m, %d cars, %d neon lights, %d puddles, %d vents, %d exits, %d fps" % [
		"ok" if ok else "FAIL", player.is_on_floor(), p.y, gy, moved, cars.cars.size(), neon.lights, neon.puddles.size(), neon.vents.size(), exits, Engine.get_frames_per_second()])
	get_tree().quit(0 if ok else 1)


func _process(dt: float) -> void:
	t += dt
	if player == null:
		return
	var follow := player.global_position
	if cam != null and cam.current:
		follow = cam.global_position
	if rain:
		rain.global_position = follow + Vector3(0, 7, 0)
	if tour:
		_director(dt)
	if hud_label == null:
		return
	var v := player.velocity
	var hs := Vector2(v.x, v.z).length()
	hud_label.text = "%d fps\n%.1f m/s   %s" % [Engine.get_frames_per_second(), hs, player.surface]
	if player.toast_t < 0.9:
		event_label.text = player.toast
		event_label.modulate.a = 1.0 - player.toast_t / 0.9
	else:
		event_label.text = ""


## clip shots: high crane over the street, chase behind the cat, low side dolly, first person
func _director(dt: float) -> void:
	hud.visible = false
	var mode := "crane"
	if t > 4.0:
		mode = "chase"
	if t > 10.0:
		mode = "low"
	if t > 15.0:
		mode = "fp"
	if t > 21.0:
		get_tree().quit()
		return
	var p := player.rig.global_position
	var fwd := -player.global_transform.basis.z
	var left := Vector3(fwd.z, 0, -fwd.x)
	if mode != _mode:
		_mode = mode
		_cam_init = false
	if player.third_person != (mode != "fp"):
		player.set_third_person(mode != "fp")
	if mode == "fp":
		player.cam.current = true
		player.bot.pitch = 0.05
		return
	cam.current = true
	var want_pos := p
	var want_look := p
	match mode:
		"crane":
			var u := clampf(t / 4.0, 0.0, 1.0)
			want_pos = p + Vector3(0, lerpf(14.0, 1.2, u * u), 0) - fwd * lerpf(8.0, 1.6, u) + left * 1.5
			want_look = p + fwd * 2.0 + Vector3(0, lerpf(2.0, 0.3, u), 0)
		"chase":
			want_pos = p - fwd * 1.3 + left * 0.25 + Vector3(0, 0.45, 0)
			want_look = p + fwd * 1.0 + Vector3(0, 0.45, 0)
		"low":
			want_pos = p + left * 1.1 + fwd * 0.4 + Vector3(0, 0.15, 0)
			want_look = p + fwd * 0.3 + Vector3(0, 0.35, 0)
	var off := want_pos - p
	var loff := want_look - p
	if not _cam_init or mode == "crane":
		_cam_pos = off
		_cam_look = loff
		_cam_init = true
	_cam_pos = LowPoly.damp3(_cam_pos, off, 4.0, dt)
	_cam_look = LowPoly.damp3(_cam_look, loff, 6.0, dt)
	cam.global_position = p + _cam_pos
	cam.look_at(p + _cam_look, Vector3.UP)
