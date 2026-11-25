extends Node3D
## edge sense lab (cat_player.gd `edge_sense`, cat_climb.gd `let_down`): the cat walking up to
## drops. a real cat never walks off a ledge by accident: it slows to the lip, steps down small
## drops, stops and peers over big ones, and pushed on turns round and lowers itself off.
##   headless check: godot --headless --fixed-fps 60 --path . res://edgelab.tscn -- --edgetest
##   film (xvfb):    ... res://edgelab.tscn --write-movie out.avi --fixed-fps 30 -- --film
##   before:         CAT_OFF=edge_sense (same command)

var player: CatPlayer
var cam: Camera3D
var cap: Label
var film := false
var scen := []
var si := -1
var t := 0.0
var lg := {}
var bad := 0
var _y0 := 0.0

# lanes along x, each a run up (z from 0 toward -z) onto a platform edge at z = -4
const LEDGE_H := 1.2


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	film = args.has("--film")
	_box(Vector3(0, -0.5, -10), Vector3(40, 1, 40), "dirt")
	if film:
		_box(Vector3(-40, -0.5, -10), Vector3(40, 1, 40), "wood")   # flat wood for the film lanes
	# lane 0: 1.2 m ledge (trot at it and keep pushing)
	_box(Vector3(0, LEDGE_H * 0.5, 0), Vector3(2.0, LEDGE_H, 8.0), "wood")
	# lane 1: 0.3 m kerb (walk off it)
	_box(Vector3(6, 0.15, 0), Vector3(2.0, 0.3, 8.0), "stone")
	# lane 2: 1.2 m ledge at a gallop (on purpose: runs off)
	_box(Vector3(12, LEDGE_H * 0.5, 2.0), Vector3(2.0, LEDGE_H, 12.0), "wood")
	# lane 4: a 0.7 m bed (look, then hop down)
	_box(Vector3(-6, 0.35, 0), Vector3(2.0, 0.7, 8.0), "carpet")
	# lane 3: a 20 deg ramp down off a deck (a slope is not a drop)
	_box(Vector3(18, 0.6, 1.5), Vector3(2.0, 1.2, 5.0), "wood")
	var a := deg_to_rad(20.0)
	var rl := 1.2 / sin(a)
	var ramp := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.0, 0.1, rl)
	cs.shape = bx
	ramp.add_child(cs)
	ramp.position = Vector3(18, 0.6 - 0.05 / cos(a), -1.0 - cos(a) * rl * 0.5)
	ramp.rotation = Vector3(-a, 0, 0)
	ramp.set_meta("surface", "wood")
	add_child(ramp)
	if film:
		_mesh(ramp, bx.size, Color(0.55, 0.42, 0.3))
	scen = [
		{"name": "ledge_trot", "x": 0.0, "y": LEDGE_H, "z": 1.0, "dur": 5.0, "bot": {"move": Vector2(0, 1), "edge_sense": true}, "text": "trot at a 1.2 m ledge, keep holding w"},
		{"name": "kerb_walk", "x": 6.0, "y": 0.3, "z": -1.0, "dur": 4.0, "bot": {"move": Vector2(0, 1), "stroll": true, "edge_sense": true}, "text": "walk off a 30 cm kerb"},
		{"name": "ledge_gallop", "x": 12.0, "y": LEDGE_H, "z": 7.5, "dur": 4.0, "bot": {"move": Vector2(0, 1), "canter": true, "edge_sense": true}, "text": "gallop at the same ledge (on purpose)"},
		{"name": "bed_trot", "x": -6.0, "y": 0.7, "z": 1.0, "dur": 4.0, "bot": {"move": Vector2(0, 1), "edge_sense": true}, "text": "trot off a 70 cm bed"},
		{"name": "ramp_down", "x": 18.0, "y": 1.2, "z": 3.5, "dur": 3.0, "bot": {"move": Vector2(0, 1), "edge_sense": true}, "text": "trot down a 20 deg ramp (a slope is not a drop)"},
	]
	if film or args.has("--all"):
		# film lanes (the rest of the "real cat" pass): a steep tile slope, a standing start
		# flat out, a slow turn round
		var sa := deg_to_rad(35.0)
		var sl := StaticBody3D.new()
		var scs := CollisionShape3D.new()
		var sbx := BoxShape3D.new()
		sbx.size = Vector3(2.0, 0.2, 7.0)
		scs.shape = sbx
		sl.add_child(scs)
		sl.position = Vector3(-30, 2.0, -2.0)
		sl.rotation = Vector3(-sa, 0, 0)
		sl.set_meta("surface", "tile")
		add_child(sl)
		if film:
			_mesh(sl, sbx.size, Color(0.75, 0.78, 0.8))
		var top: Vector3 = sl.position + Vector3(0, cos(sa), -sin(sa)) * 0.11 + Vector3(0, sin(sa), cos(sa)) * 1.5
		scen.append({"name": "steep", "x": top.x, "y": top.y, "z": top.z, "dur": 3.0, "bot": {"move": Vector2.ZERO}, "text": "standing on 35 deg tile (paws hold 24 deg)"})
		scen.append({"name": "start", "x": -36.0, "y": 0.0, "z": 2.0, "dur": 2.6, "bot": {"move": Vector2(0, 1), "canter": true}, "text": "flat out from a stand: a bound start"})
		scen.append({"name": "pivot", "x": -42.0, "y": 0.0, "z": -2.0, "dur": 3.4, "t2": 1.0, "bot": {"move": Vector2(0, 1), "stroll": true}, "bot2": {"move": Vector2(0, -1), "stroll": true}, "text": "walk, then turn round: the forepaws pivot"})
		if film and not args.has("--all"):
			scen = scen.filter(func(x): return x.name in ["ledge_trot", "bed_trot", "kerb_walk", "steep", "start", "pivot"])
	player = CatPlayer.new()
	add_child(player)
	if film:
		player.set_third_person(true)
		cam = Camera3D.new()
		cam.fov = 45.0
		add_child(cam)
		cam.make_current()
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-1.0, 0.7, 0.0)
		sun.shadow_enabled = true
		add_child(sun)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.5, 0.58, 0.68)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.7, 0.72, 0.78)
		env.ambient_light_energy = 0.7
		we.environment = env
		add_child(we)
		var cl := CanvasLayer.new()
		add_child(cl)
		cap = Label.new()
		cap.position = Vector2(20, 14)
		cap.add_theme_font_size_override("font_size", 30)
		cap.add_theme_color_override("font_outline_color", Color.BLACK)
		cap.add_theme_constant_override("outline_size", 8)
		cl.add_child(cap)
	_next.call_deferred()


func _box(pos: Vector3, size: Vector3, surface: String) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	b.add_child(cs)
	b.position = pos
	b.set_meta("surface", surface)
	add_child(b)
	if film:
		_mesh(b, size, Color(0.42, 0.36, 0.28) if surface == "dirt" else (Color(0.55, 0.42, 0.3) if surface == "wood" else Color(0.6, 0.6, 0.62)))


func _mesh(b: Node3D, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, col)
	img.set_pixel(1, 1, col)
	img.set_pixel(1, 0, col.darkened(0.25))
	img.set_pixel(0, 1, col.darkened(0.25))
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	mi.material_override = m
	b.add_child(mi)


func _next() -> void:
	if si >= 0:
		_judge(scen[si])
	si += 1
	if si >= scen.size():
		_done()
		return
	var s: Dictionary = scen[si]
	var at := Vector3(float(s.x), float(s.y) + 0.02, float(s.z))
	player.global_position = at
	player._phys_curr = at
	player._phys_prev = at
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.rotation.y = 0.0
	player.orb_yaw = 0.0
	player.climber.reset()
	player.last_event = ""
	player.last_impact = 0.0
	player.rig.idle_life = false
	player.bot = {"move": Vector2.ZERO, "pitch": -0.25}
	_y0 = at.y
	t = -0.5
	lg = {"min_v_lip": INF, "fell_t": -1.0, "events": [], "max_v": 0.0, "impact": 0.0, "hang": false, "lip_v": -1.0, "stopped_at": INF}
	if film:
		cap.text = s.text + ("\nbefore" if not CatPlayer.edge_sense else "\nafter")


func _physics_process(dt: float) -> void:
	if si < 0 or si >= scen.size():
		return
	var s: Dictionary = scen[si]
	t += dt
	if t >= 0.0:
		player.bot = ((s.bot2 if s.has("t2") and t > float(s.t2) else s.bot) as Dictionary).duplicate()
		player.bot["pitch"] = -0.25
		var hv := Vector2(player.velocity.x, player.velocity.z).length()
		lg.max_v = maxf(lg.max_v, hv)
		if player.last_event != "" and (lg.events.is_empty() or lg.events[-1] != player.last_event):
			lg.events.append(player.last_event)
		if player.climber.mode == CatClimb.HANG:
			lg.hang = true
		var z := player.global_position.z
		# the platforms end at z = -4 (lane 2: z = -4 too)
		if z > -4.0 and z < -3.6 and player.is_on_floor():
			lg.min_v_lip = minf(lg.min_v_lip, hv)
		if lg.lip_v < 0.0 and z < -4.0 + player.RADIUS and float(s.y) <= 0.31:
			lg.lip_v = hv
		if lg.fell_t < 0.0 and player.global_position.y < float(s.y) - 0.15 and not player.climber.active():
			lg.fell_t = t
		if player.is_on_floor() and player.last_impact > lg.impact and player.global_position.y < 0.3:
			lg.impact = player.last_impact
	if film:
		var p := player.global_position
		cam.global_position = Vector3(p.x + 3.2, maxf(p.y, 0.4) + 0.6, p.z - 0.6)
		cam.look_at(Vector3(p.x, maxf(p.y, 0.3) + 0.1, p.z - 0.4))
	if t > float(s.dur):
		_next()


func _ok(cond: bool, what: String) -> void:
	print(("EDGE ok   " if cond else "EDGE FAIL ") + what)
	if not cond:
		bad += 1


func _judge(s: Dictionary) -> void:
	print("EDGE %s: events %s, max %.2f m/s, slowest at the lip %.2f, fell at %.2f s, hung %s, landed %.1f m/s" % [s.name, str(lg.events), lg.max_v, lg.min_v_lip, lg.fell_t, lg.hang, lg.impact])
	if film or not CatPlayer.edge_sense:
		return
	match s.name:
		"ledge_trot":
			_ok(lg.min_v_lip < 0.3, "trot at a ledge: it stops at the lip (%.2f m/s)" % lg.min_v_lip)
			_ok("let down" in lg.events and lg.hang, "kept pushing: it lowers itself off and hangs")
			_ok(lg.fell_t > 0.8, "it doesn't just walk off (left the top at %.2f s)" % lg.fell_t)
			_ok(lg.impact > 0.0 and lg.impact < 4.4, "dropped from the hang: a free landing (%.1f m/s)" % lg.impact)
		"kerb_walk":
			_ok(lg.fell_t > 0.0, "a kerb: it steps down off it")
			_ok(lg.lip_v >= 0.0 and lg.lip_v < CatPlayer.EDGE_STEP_V + 0.4, "and at a walk (%.2f m/s)" % lg.lip_v)
		"ledge_gallop":
			_ok(lg.fell_t > 0.0 and lg.min_v_lip > 3.0 and not lg.hang, "galloping at a ledge on purpose: no brake, it goes off (%.1f m/s at the lip)" % lg.min_v_lip)
		"bed_trot":
			_ok("hop down" in lg.events and lg.min_v_lip < 0.3, "a bed: it stops, looks, hops down")
			_ok(lg.impact < 4.4, "soft landing off the bed (%.1f m/s)" % lg.impact)
		"ramp_down":
			_ok(lg.max_v > 2.0, "a ramp down isn't braked like a drop (%.2f m/s)" % lg.max_v)


func _done() -> void:
	if not film:
		print("EDGETEST %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad else 0)
