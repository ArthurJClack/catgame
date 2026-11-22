extends Node3D
## the city (res://city.tscn, f4 from the farm, gate in the back fence): one dense crossroads at
## cat scale (city/city_block.gd), at night in the rain, cyberpunk neon. traffic you have to wait
## for (city/city_traffic.gd: lights, walk signals, bonk back to the curb), pigeons on the
## pavements and sparrows in the park (wildlife.gd birds), rats in the alleys (hunt_prey.gd, if
## the hunting update is in), the warm vent puzzle on the s main st sidewalk.
##   r back to the start · t next spot · 1-9 swap cat · h hide help · f5 / farm sign = back
## preview: `-- --still x,y,z,tx,ty,tz`, `-- --tour` (camera flythrough for the clip),
## `-- --citytest` (builds, runs the bot, checks traffic + a bonk, prints one line),
## `-- --mapshot <png>` (explores a route, opens the explore map, saves a screenshot)

const Cars := preload("res://scripts/city/city_cars.gd")
const CAR_IDS := ["wrx_wagon", "crownvic", "civic_ep3"]

var player: CatPlayer
var block: CityBlock
var traffic: CityTraffic
var cars
var birds: Array = []
var rats: Array = []
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
var mapshot := ""
var _phase := 0
var _phase_t := 0.0
var _bonk_car = null
var _test_log := []


func _ready() -> void:
	process_priority = 10
	var args := OS.get_cmdline_user_args()
	tour = "--tour" in args
	test = "--citytest" in args
	var mi := args.find("--mapshot")
	if mi >= 0:
		mapshot = args[mi + 1] if mi + 1 < args.size() else "user://mapshot.png"
	_setup_env()
	block = CityBlock.new()
	block.name = "CityBlock"
	add_child(block)
	block.build()
	cars = Cars.new()
	cars.name = "ParkedCars"
	add_child(cars)
	for k in block.parked.size():
		var pk: Array = block.parked[k]
		cars.park(CAR_IDS[(k * 7 + 3) % 3], Transform3D(Basis(Vector3.UP, pk[1]), pk[0]), Cars.PAINT[(k * 5 + 1) % Cars.PAINT.size()])
	player = CatPlayer.new()
	player.position = block.start + Vector3(0, 0.1, 0)
	player.yaw = block.start_yaw
	player.orb_yaw = block.start_yaw
	add_child(player)
	Hub.arrive(player)
	traffic = CityTraffic.new()
	traffic.name = "Traffic"
	traffic.player = player
	if test:
		# start the test in a main st green so the bonk check has moving cars to step in front of
		var now := Time.get_unix_time_from_system()
		traffic.clock_offset = CityTraffic.CYCLE - fposmod(now, CityTraffic.CYCLE) + 2.0
	add_child(traffic)
	_spawn_wildlife()
	_build_hud()
	_build_farm_exit()
	_build_rain()
	var si := args.find("--still")
	if si >= 0:
		hud.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		_make_cam()
		var v := args[si + 1].split_floats(",")
		cam.global_position = Vector3(v[0], v[1], v[2])
		cam.look_at(Vector3(v[3], v[4], v[5]), Vector3.UP)
		player.souls_hud.visible = false
	elif tour or test or mapshot != "":
		help_label.visible = false
		player.bot = {"move": Vector2.ZERO, "yaw": block.start_yaw, "pitch": -0.1}
		var vs := args.find("--style")
		player.set_style.call_deferred(args[vs + 1] if vs >= 0 else "block")
		if tour:
			_make_cam()
			player.visible = false
			player.process_mode = Node.PROCESS_MODE_DISABLED
			player.global_position = Vector3(-44.0, CityBlock.CURB + 0.1, 8.4)
	elif not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if si < 0 and not (tour or test):
		Puzzles.city(self, player, block.vent_at)   # the warm vent (puzzle_more.gd)


## the explore map (explore_map.gd) asks the level for its extent + place names
func map_info() -> Dictionary:
	return {"rect": Rect2(-CityBlock.HALF, -CityBlock.HALF, CityBlock.HALF * 2.0, CityBlock.HALF * 2.0), "cell": 1.0, "labels": block.labels, "top": 26.0}


func _spawn_wildlife() -> void:
	var gy := func(x: float, z: float) -> float: return CityBlock.ground_y(x, z) + (0.02 if x > CityBlock.WALK and z > CityBlock.WALK else 0.0)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var add := func(p: Vector3, pigeon: bool) -> void:
		var c := Critter.new()
		c.kind = "bird"
		c.pigeon = pigeon
		c.ground_cb = gy
		c.perch_list = block.perches
		c.home = Vector3(p.x, gy.call(p.x, p.z), p.z)
		add_child(c)
		birds.append(c)
	for s in block.pigeon_spots:
		for k in r.randi_range(4, 6):
			add.call(s + Vector3(r.randf_range(-1.5, 1.5), 0, r.randf_range(-1.5, 1.5)), true)
	for s in block.sparrow_spots:
		for k in r.randi_range(3, 5):
			add.call(s + Vector3(r.randf_range(-1.2, 1.2), 0, r.randf_range(-1.2, 1.2)), false)
	# rats: the hunting update's prey (same ones in the same order on every machine)
	if ResourceLoader.exists("res://scripts/hunt_prey.gd"):
		var hp = load("res://scripts/hunt_prey.gd")
		if hp != null and hp.has_method("spawn"):
			for di in block.rat_dens.size():
				if di % 2 == 1 or rats.size() >= 12:
					continue
				var den: Array = block.rat_dens[di]
				var hides: Array[Vector3] = []
				hides.assign(den[1])
				rats.append(hp.spawn(self, "rat", den[0], hides, Callable(), block.blockers))


func _make_cam() -> void:
	cam = Camera3D.new()
	cam.fov = 64
	cam.near = 0.02
	cam.far = 300
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
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.4, 0.62)
	env.ambient_light_energy = 1.4
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.12, 0.38)
	env.fog_density = 0.0085
	env.fog_sky_affect = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.08
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, 40, 0)
	moon.light_color = Color(0.55, 0.6, 0.9)
	moon.light_energy = 0.4
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
	rain.layers = 1 << (CityTraffic.VIS_LAYER - 1)
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
	event_label.offset_left = -320
	event_label.offset_right = 320
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(event_label, 22)
	hud.add_child(event_label)
	help_label = Label.new()
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_top = -92
	help_label.offset_left = 18
	_style(help_label, 15)
	help_label.text = "the city: one crossroads, packed. sills, ac units, awnings, pipes, fire escapes, rooftops, a park\ncars don't stop for cats: cross on WALK, or go over (awnings, the sign bridge, the footbridge)\n%s map · r back to the start · t next spot · h hide help · f5 or the farm sign = back to the farm" % CatKeys.describe("map")
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


## farm gate at the west end of the s main st sidewalk, a chain-link panel with a neon sign
func _build_farm_exit() -> void:
	var c := block.exit_at
	for s in [-1.0, 1.0]:
		Level.box(self, c + Vector3(0, 0.75, s * 0.6), Vector3(0.08, 1.5, 0.08), Color(0.35, 0.36, 0.4)).name = "FarmGatePost"
	Level.box(self, c + Vector3(0, 1.52, 0), Vector3(0.08, 0.06, 1.28), Color(0.35, 0.36, 0.4), false)
	Hub.exit(self, c, Vector3(1, 0, 0), "city", Vector2.ZERO, "farm")


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
			_place(block.spots[0])
		KEY_T:
			spot_i = (spot_i + 1) % block.spots.size()
			_place(block.spots[spot_i])
			player.toast = block.spots[spot_i][0]
			player.toast_t = 0.0
		KEY_H:
			help_label.visible = not help_label.visible
		KEY_F5:
			Hub.go_home(self, "city")


func _place(s: Array) -> void:
	player.global_position = s[1] + Vector3(0, 0.15, 0)
	player.velocity = Vector3.ZERO
	player.yaw = s[2]
	player.orb_yaw = s[2]


func _physics_process(dt: float) -> void:
	if player == null:
		return
	if player.global_position.y < -3.0:
		_place(block.spots[spot_i])
	if test:
		_test(dt)
	elif mapshot != "":
		_mapshot(dt)


# ---------------------------------------------------------------- citytest

func _test(dt: float) -> void:
	_phase_t += dt
	var p := player.global_position
	match _phase:
		0:
			# walk east along the s main st sidewalk for a few seconds
			player.bot.move = Vector2(0, 1)
			player.bot.canter = true
			if _phase_t > 5.0:
				_test_log.append("walk ran %.1f m, on floor %s, y %.2f" % [p.distance_to(block.start), player.is_on_floor(), p.y])
				_test_log.append(player.is_on_floor() and p.distance_to(block.start) > 3.0 and absf(p.y - CityBlock.CURB) < 0.3)
				player.bot.move = Vector2.ZERO
				_phase = 1
				_phase_t = 0.0
		1:
			# step in front of a moving car: should get bonked back onto the curb
			if _bonk_car == null:
				for v in traffic.vehicles:
					if v.v > 4.0 and v.kind == "car" and v.s > 8.0 and v.s < 40.0:
						_bonk_car = v
						break
				if _bonk_car == null:
					if _phase_t > 25.0:
						_test_log.append("no moving car found")
						_test_log.append(false)
						_phase = 2
					return
				var l: Dictionary = traffic.lanes[_bonk_car.lane]
				var at: Vector3 = traffic.pos_of(_bonk_car) + (l.d as Vector3) * 7.0
				player.global_position = Vector3(at.x, 0.05, at.z)
				player.velocity = Vector3.ZERO
				_phase_t = 0.0
			elif _phase_t > 3.5:
				var ok: bool = traffic.bonks > 0 and not CityBlock.on_road(player.global_position)
				_test_log.append("bonks %d, cat at %s (on road %s)" % [traffic.bonks, player.global_position.snapped(Vector3.ONE * 0.1), CityBlock.on_road(player.global_position)])
				_test_log.append(ok)
				_phase = 2
		2:
			_report()
			_phase = 3


func _report() -> void:
	var em = get_node_or_null("/root/ExploreMap")
	var explored: float = em.explored() if em else -1.0
	var oks := _test_log.filter(func(x): return x is bool)
	var ok: bool = oks.all(func(x): return x) and traffic.spawned > 4 and traffic.heads.size() >= 8 and traffic.walks.size() == 8 \
		and block.n_boxes > 3000 and block.perches.size() > 40 and birds.size() > 15 and block.rat_dens.size() >= 6 and explored > 0.0
	var exits := get_tree().get_nodes_in_group("hub_trigger").filter(func(n: Node) -> bool: return is_ancestor_of(n)).size()
	ok = ok and exits >= 1
	print("[city] %s: %s | %d boxes, %d shapes, %d lights, %d perches, %d birds, %d rat dens (%d rats), %d vehicles now (%d spawned), %d signal heads, %d walk signs, explored %.1f%%, %d exits, %d fps" % [
		"ok" if ok else "FAIL", " · ".join(_test_log.filter(func(x): return x is String)), block.n_boxes, block.n_shapes, block.n_lights, block.perches.size(), birds.size(),
		block.rat_dens.size(), rats.size(), traffic.vehicles.size(), traffic.spawned, traffic.heads.size(), traffic.walks.size(), explored * 100.0, exits, Engine.get_frames_per_second()])
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------- map screenshot

const MAP_ROUTE := [Vector3(-38, 0.2, 7), Vector3(-25, 0.2, 7), Vector3(-34.5, 0.2, 7), Vector3(-34.5, 0.2, -8), Vector3(-34.5, 0.2, -28),
	Vector3(-34.5, 7.0, -36), Vector3(-27, 14, -15), Vector3(-15, 10.5, -15), Vector3(0, 10.8, -15), Vector3(15, 10.5, -15),
	Vector3(7, 0.2, -7), Vector3(7, 0.2, 7), Vector3(14, 0.2, 14), Vector3(26, 0.2, 24), Vector3(33, 0.2, 28), Vector3(19, 0.2, 34)]


func _mapshot(dt: float) -> void:
	_phase_t += dt
	var em = get_node_or_null("/root/ExploreMap")
	if em == null:
		return
	match _phase:
		0:
			hud.visible = false
			player.souls_hud.visible = false
			if _phase_t > 1.0:
				# walk the route: reveal along it, leave the cat at the end
				for i in MAP_ROUTE.size() - 1:
					var a: Vector3 = MAP_ROUTE[i]
					var b: Vector3 = MAP_ROUTE[i + 1]
					var n := int(a.distance_to(b) / 1.5) + 1
					for k in n + 1:
						em.reveal_at(a.lerp(b, float(k) / n))
				player.global_position = MAP_ROUTE[MAP_ROUTE.size() - 1]
				player.yaw = PI * 0.75
				Puzzles.solved["warm_vent"] = 1
				_phase = 1
				_phase_t = 0.0
		1:
			if _phase_t > 0.5:
				em.no_pause = true
				em.open_map()
				_phase = 2
				_phase_t = 0.0
		2:
			if _phase_t > 2.0:
				var img := get_viewport().get_texture().get_image()
				img.save_png(mapshot)
				print("[city] map screenshot -> %s (explored %.1f%%)" % [mapshot, em.explored() * 100.0])
				get_tree().quit()


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
	if player.toast_t < 1.6:
		event_label.text = player.toast
		event_label.modulate.a = 1.0 - player.toast_t / 1.6
	else:
		event_label.text = ""


# ---------------------------------------------------------------- flythrough (--tour)

## camera keys [time, pos, look]: low down the sidewalk, into the alley, up the fire escape,
## over the roofs + the sign bridge, down to the crossing (traffic), the park, the pond, the
## playground, the construction site, the footbridge, up and out for the whole block
const KEYS := [
	[0.0, Vector3(-41.0, 0.45, 7.6), Vector3(-30.0, 0.6, 6.0)],
	[4.0, Vector3(-34.5, 0.6, 5.0), Vector3(-34.5, 1.0, -6.0)],
	[8.0, Vector3(-34.6, 1.2, -10.0), Vector3(-34.5, 1.5, -26.0)],
	[12.0, Vector3(-34.3, 2.2, -26.0), Vector3(-36.0, 6.0, -36.0)],
	[16.0, Vector3(-33.0, 8.0, -33.0), Vector3(-36.0, 9.0, -40.0)],
	[20.0, Vector3(-30.0, 15.5, -26.0), Vector3(-15.0, 11.0, -15.0)],
	[24.0, Vector3(-17.0, 11.6, -16.0), Vector3(0.0, 11.2, -15.0)],
	[28.0, Vector3(-3.0, 11.4, -15.4), Vector3(12.0, 10.5, -15.0)],
	[31.0, Vector3(6.5, 7.0, -7.5), Vector3(0.0, 0.5, 2.0)],
	[35.0, Vector3(9.5, 1.2, 9.5), Vector3(-4.0, 0.6, -2.0)],
	[39.0, Vector3(13.0, 0.8, 16.5), Vector3(28.0, 0.8, 30.0)],
	[43.0, Vector3(27.5, 1.1, 27.0), Vector3(34.0, 0.9, 33.0)],
	[47.0, Vector3(25.0, 1.6, 36.0), Vector3(17.0, 1.0, 35.0)],
	[51.0, Vector3(20.5, 4.5, 31.5), Vector3(40.0, 1.0, 17.5)],
	[55.0, Vector3(33.0, 7.0, 9.0), Vector3(27.0, 5.3, 0.0)],
	[59.0, Vector3(27.1, 5.9, -5.0), Vector3(27.1, 5.6, 8.0)],
	[63.0, Vector3(-7.0, 3.0, 13.0), Vector3(-15.0, 1.0, 28.0)],
	[66.0, Vector3(-8.0, 3.5, 25.0), Vector3(-20.0, 2.0, 30.0)],
	[70.0, Vector3(-24.0, 5.0, 27.0), Vector3(-36.0, 4.0, 36.0)],
	[74.0, Vector3(-30.0, 9.0, 31.0), Vector3(-40.0, 6.0, 40.0)],
	[78.0, Vector3(-20.0, 30.0, 40.0), Vector3(0.0, 0.0, 0.0)],
	[83.0, Vector3(30.0, 48.0, 50.0), Vector3(0.0, 0.0, -2.0)],
]


func _director(_dt: float) -> void:
	hud.visible = false
	player.souls_hud.visible = false
	var last: Array = KEYS[KEYS.size() - 1]
	if t > float(last[0]) + 0.5:
		get_tree().quit()
		return
	var i := 0
	while i < KEYS.size() - 2 and t > float(KEYS[i + 1][0]):
		i += 1
	var k0: Array = KEYS[maxi(i - 1, 0)]
	var k1: Array = KEYS[i]
	var k2: Array = KEYS[i + 1]
	var k3: Array = KEYS[mini(i + 2, KEYS.size() - 1)]
	var u := clampf((t - float(k1[0])) / (float(k2[0]) - float(k1[0])), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65
	var pos := _cr(k0[1], k1[1], k2[1], k3[1], u)
	var look := _cr(k0[2], k1[2], k2[2], k3[2], u)
	cam.global_position = pos
	if pos.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)
