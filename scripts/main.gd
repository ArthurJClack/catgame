extends Node3D
## builds the whole prototype procedurally: lighting, level, player cat, npc cats, hud.
## run with `-- --preview` to play the scripted showcase instead (used to render the video).

var player: CatPlayer
var hud_label: Label
var event_label: Label
var help_label: Label
var crosshair: Control
var hud: CanvasLayer
var info := {}
var npcs: Array[NpcCat] = []
var env: Environment
var preview_mode := false


func _ready() -> void:
	if Net.server:
		# dedicated server (--server): no level, Net swaps in server.tscn next frame
		set_process(false)
		set_process_unhandled_input(false)
		return
	_setup_env()
	info = Level.build(self)

	player = CatPlayer.new()
	player.position = info.spawn
	player.yaw = -0.6
	# coming back from another level: start at the hub gate that leads there (hub.gd)
	var back: String = Engine.get_meta("cat_spawn", "")
	if info.hub_spawns.has(back):
		player.position = info.hub_spawns[back][0]
		player.yaw = info.hub_spawns[back][1]
	Engine.set_meta("cat_spawn", "")
	add_child(player)
	if Engine.get_meta("cat_style", "") != "":
		player.set_style.call_deferred(Engine.get_meta("cat_style"))

	var looks := [
		{"fur": Color(0.16, 0.16, 0.18), "dark": Color(0.08, 0.08, 0.1), "pattern": "tux", "socks": true, "eye": Color(0.95, 0.78, 0.2), "pos": Vector3(0.5, 0, 2.2)},
		{"fur": Color(0.58, 0.6, 0.64), "dark": Color(0.36, 0.38, 0.42), "pattern": "tabby", "socks": false, "eye": Color(0.35, 0.75, 0.9), "pos": Vector3(-3.0, 0, -0.6)},
	]
	for l in looks:
		var n := NpcCat.new()
		n.fur = l.fur
		n.fur_dark = l.dark
		n.pattern = l.pattern
		n.socks = l.socks
		n.eye = l.eye
		n.position = l.pos
		add_child(n)
		npcs.append(n)

	_build_hud()
	Puzzles.farm(self, player)   # knock it off, sunbeam perch, doormat gifts (puzzles.gd)
	preview_mode = "--preview" in OS.get_cmdline_user_args()
	if not preview_mode and Tutorial.should_run():
		Tutorial.start(self, player)        # first time: control hint cards (tutorial.gd)
	if not preview_mode and TitleScreen.should_show():
		TitleScreen.show_on(self, player)   # boot: title over the live farm (title_screen.gd)
		return
	if preview_mode:
		var p := Preview.new()
		p.main = self
		add_child(p)
	elif not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.55, 0.85)
	psm.sky_horizon_color = Color(0.75, 0.82, 0.9)
	psm.ground_horizon_color = Color(0.6, 0.65, 0.6)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.8)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.35
	env.ssao_intensity = 2.2
	env.ssao_detail = 0.8
	env.ssil_enabled = true
	env.ssil_radius = 2.0
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	# dusty sunbeams through the window
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(1.0, 0.95, 0.88)
	env.volumetric_fog_length = 16.0
	env.volumetric_fog_ambient_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 3.2
	sun.light_volumetric_fog_energy = 2.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 25.0
	sun.shadow_blur = 1.2
	sun.rotation = Vector3(deg_to_rad(-34), deg_to_rad(-105), 0)
	# soft bluish skylight bouncing in from the window
	var skyfill := OmniLight3D.new()
	skyfill.position = Vector3(-4.2, 1.6, 0)
	skyfill.light_color = Color(0.7, 0.8, 1.0)
	skyfill.light_energy = 0.9
	skyfill.omni_range = 6.0
	skyfill.light_volumetric_fog_energy = 0.0
	add_child(skyfill)
	add_child(sun)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.3, 0)
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 0.7
	lamp.light_volumetric_fog_energy = 0.0
	lamp.omni_range = 8.0
	lamp.shadow_enabled = false
	add_child(lamp)
	var lamp2 := OmniLight3D.new()
	lamp2.position = Vector3(3.0, 2.2, -2.0)
	lamp2.light_color = Color(1.0, 0.88, 0.7)
	lamp2.light_energy = 0.5
	lamp2.light_volumetric_fog_energy = 0.0
	lamp2.omni_range = 6.0
	add_child(lamp2)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	hud_label = Label.new()
	hud_label.position = Vector2(18, 58)   # under the health + stamina bars (souls_hud.gd)
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hud_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(hud_label)
	event_label = Label.new()
	event_label.anchor_left = 0.5
	event_label.anchor_right = 0.5
	event_label.anchor_top = 0.62
	event_label.offset_left = -300
	event_label.offset_right = 300
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.add_theme_font_size_override("font_size", 22)
	event_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	event_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(event_label)
	help_label = Label.new()
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_top = -130
	help_label.offset_left = 18
	help_label.add_theme_font_size_override("font_size", 15)
	help_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help_label.add_theme_constant_override("outline_size", 5)
	help_label.text = "wasd move (relative to your view, the cat turns to run that way) · hold shift canter · double tap shift gallop · ctrl/c stalk · space hop (hold = higher, hold long = pounce + aim line) / wall kick (1 per jump) · alt or mouse4 dodge (wasd picks the way, none = backstep) · arrows also look\ntab = lock on (rats first, then prey / wildlife): camera holds it, wasd circles it, flick the mouse = next target, tab again = unlock\nhold q or mouse3 + look + release = aimed leap (yellow ring = grab the edge + haul up)\njump at trees / posts / fences / hay / curtains holding w = climb (then wasd any way, round trunks + corners, space + direction = lunge) · hold f at a wall = scratch\nstalk (c) up to prey, hold space to pounce · mouse1 / mouse2 = left / right paw swat (hold = rake, or claws: hook stuff) · g / mouse5 = grab + pin it · e drop\nattacks are committed (souls style): dodge comes out of the recovery, extra clicks are buffered\n1-9 swap cat · v first / third / orbit cam (scroll zooms) · walk out the yard gates to travel: west = forest, east = pier 9, north = trail, back fence behind the house = the city, cellar by the barn = rat pit (f6 / f7 / f8 / f10 / f4 shortcuts) · n meow · h hide help · esc = menu (settings, rebind keys)"
	if OS.has_feature("web"):
		help_label.text = "click the game to grab the mouse (in a browser use c to crouch, ctrl+w closes the tab!)\n" + help_label.text.replace("ctrl/c", "c")
		help_label.offset_top = -152
	hud.add_child(help_label)
	crosshair = ColorRect.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the captured cursor parks on it: STOP would eat every mouse move
	crosshair.color = Color(1, 1, 1, 0.7)
	crosshair.size = Vector2(4, 4)
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.offset_left = -2
	crosshair.offset_top = -2
	hud.add_child(crosshair)




func _unhandled_input(event: InputEvent) -> void:
	if preview_mode or player == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			player.set_style(CatRig.STYLE_ORDER[k - KEY_1])
		elif k == KEY_H:
			help_label.visible = not help_label.visible
		elif k == KEY_F6:
			go_scene("res://forest.tscn")
		elif k == KEY_F7:
			go_scene("res://stealth.tscn")
		elif k == KEY_F8:
			go_scene("res://trail.tscn")
		elif k == KEY_F10:
			go_scene("res://arena.tscn")
		elif k == KEY_F4:
			go_scene("res://city.tscn")


## level hop (debug keys, lobby "go to them", server map). keeps the cat style via Engine
## meta "cat_style"; the in-world gates go through Hub.travel too.
func go_scene(path: String) -> void:
	if not ResourceLoader.exists(path):
		_flash("that level isn't in this build yet")
		return
	Hub.travel(get_tree(), path, "", player.style)


func _flash(t: String) -> void:
	player._event(t)


func _process(_dt: float) -> void:
	if hud_label == null or player == null:
		return
	var v := player.velocity
	var hs := Vector2(v.x, v.z).length()
	var mode := "gallop" if player.rig.gait_w.z > 0.5 else ("trot" if player.rig.gait_w.y > 0.5 else "walk")
	if hs < 0.1:
		mode = "idle"
	if player.crouch_amt > 0.5:
		mode = "stalk"
	if not player.is_on_floor():
		mode = "air"
	var fps_line := "" if preview_mode else "%d fps\n" % Engine.get_frames_per_second()
	hud_label.text = fps_line + "%.1f m/s  (%.0f km/h)  %s\nheight %.2f m   kicks %d   caught %d   grip: %s%s" % [hs, hs * 3.6, mode, player.global_position.y, player.kicks_left, player.catches, player.surface, "  SLIPPING" if player.slip > 0.3 else ""]
	if player.hunt_info != "":
		hud_label.text += "\nstalking: " + player.hunt_info
	if player.toast_t < 0.9:
		event_label.text = player.toast
		event_label.modulate.a = 1.0 - player.toast_t / 0.9
	else:
		event_label.text = ""
