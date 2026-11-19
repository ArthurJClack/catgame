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
var atmos: Atmos
var water: Water
var swarms: Array = []
var _shift_t := 0.0
var sound: Soundscape
var _perf := false
var _perf_n := 0
var _perf_sum := 0.0
var _load_ms := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_perf = "--perf" in OS.get_cmdline_user_args()
	_setup_env()
	info = ForestLevel.build(self)
	_dress()
	critters = Critter.spawn_all(self)
	critters.append_array(Fauna.spawn_all(self, atmos))
	swarms = Swarms.spawn_all(self, atmos)
	sound = Soundscape.new()
	sound.atmos = atmos
	add_child(sound)
	_spawn_mice()
	player = CatPlayer.new()
	player.position = info.spawn
	player.yaw = info.spawn_yaw
	add_child(player)
	if Engine.has_meta("cat_style"):
		player.set_style.call_deferred(Engine.get_meta("cat_style"))
	_build_gate_trigger()
	_build_hud()
	_load_ms = Time.get_ticks_msec() - t0
	var args := OS.get_cmdline_user_args()
	var si := args.find("--still")
	if si >= 0 or "--tour" in args or "--watch" in args:
		hud.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		cam = Camera3D.new()
		cam.fov = 70
		cam.near = 0.02
		cam.far = 400
		add_child(cam)
		cam.current = true
		if "--zoo" in args:
			_zoo()
		var wi := args.find("--watch")
		if wi >= 0:
			_watch_setup(args, wi)
		elif si >= 0:
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
	atmos = Atmos.new()
	add_child(atmos)
	env = atmos.env
	var hi := OS.get_cmdline_user_args().find("--hour")
	if hi >= 0:
		atmos.hour = float(OS.get_cmdline_user_args()[hi + 1])
		atmos.apply_time()
		var ds := OS.get_cmdline_user_args().find("--dayspeed")
		if ds >= 0:
			atmos.day_speed = float(OS.get_cmdline_user_args()[ds + 1])
	else:
		# a full day takes about half an hour of play
		atmos.day_speed = 0.012


## grass, flowers, reeds, the water surface: everything that dresses the bare level
func _dress() -> void:
	var w := ForestLevel.lv.get_node_or_null("Water") as MeshInstance3D
	if w:
		water = Water.apply(w)
	add_child(Foliage.new())
	# deepen the ground: the bare terrain colours are pale next to real grass
	var tm := LowPoly.mat(Color(0.66, 0.84, 0.54), 0.95)
	for c in ForestLevel.lv.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Terrain_"):
			(c as MeshInstance3D).material_override = tm


func _build_gate_trigger() -> void:
	var a := Area3D.new()
	a.add_to_group("hub_trigger")
	a.set_meta("hub_to", "res://main.tscn")
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
	Hub.go_home(self, "forest")


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
	help_label.offset_top = -112
	help_label.offset_left = 18
	_style(help_label, 15)
	help_label.text = "the forest: deer + rabbits in the meadow, ducks + fish on the pond, crows, a hawk overhead, hedgehogs, lizards on the rocks, grasshoppers + mice to hunt\nstalk (c) to sneak up on things, rushing spooks them · trees, logs, stumps and the deer stand ladder are climbable\nt teleport to next landmark · n skip time (sunset, night, morning) · m mute · 1-8 swap cat · v camera · h hide help · walk out the gate behind you (or f5) = back to the yard"
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
			player.toast = pts[tp_i][0]
			player.toast_t = 0.0
		KEY_H:
			help_label.visible = not help_label.visible
		KEY_M:
			sound.set_muted(not sound.muted)
			player.toast = "sound off" if sound.muted else "sound on"
			player.toast_t = 0.0
		KEY_N:
			# skip ahead: afternoon -> sunset -> night -> morning
			atmos.skip = 3.0
			player.toast = "time passes..."
			player.toast_t = 0.0
		KEY_F5:
			_go_home()


# ------------------------------------------------------------------ wildlife camera (previews + checks)
## `-- --watch duck` films the first animal of that kind (`duck:2` = the third). add `--poke 4` to have a
## stand-in cat walk up to it after 4 s (`--rush` = at a run, `--crouch` = stalking), `--dist 1.5` camera range,
## `--log` prints every state change, `--hour 21` sets the time of day
var _watch: Node3D
var _watch_dist := 1.6
var _poke_t := -1.0
var _poke_speed := 1.5
var _poke_from := Vector3.ZERO
var _log_states := {}


## `-- --zoo --still ...`: one of every new animal lined up (frozen) to check the models
func _zoo() -> void:
	var x := -2.0
	for k in ["duck", "duck", "duckling", "crow", "owl", "hawk", "woodpecker", "hedgehog", "lizard", "dragonfly", "hopper", "bat"]:
		var c := Fauna.new()
		c.kind = k
		var big: bool = k in ["duck", "crow", "owl", "hawk"]
		c.home = ForestLevel.ground(x, -14.0 if big or k in ["duckling", "woodpecker", "hedgehog"] else -12.6) + Vector3(0, 0.02, 0)
		if k == "duck":
			c.set_meta("drake", x > -1.9)
		add_child(c)
		c.position = c.home
		c.rotation.y = -0.7
		c.visible = true
		c.set_process(false)
		x += 0.75 if big else 0.4
		if k == "hedgehog":
			x = -1.0


func _watch_setup(args: PackedStringArray, wi: int) -> void:
	var spec := args[wi + 1].split(":")
	var idx := int(spec[1]) if spec.size() > 1 else 0
	var found := 0
	for c in critters:
		if (c as Critter).kind == spec[0]:
			if found == idx:
				_watch = c
				break
			found += 1
	if _watch == null:
		for sw in swarms:
			if (sw as Swarms).kind == spec[0]:
				if found == idx:
					_watch = sw
					break
				found += 1
	var di := args.find("--dist")
	if di >= 0:
		_watch_dist = float(args[di + 1])
	var pi := args.find("--poke")
	if pi >= 0:
		_poke_t = float(args[pi + 1])
	if "--rush" in args:
		_poke_speed = 6.0
	if "--crouch" in args:
		_poke_speed = 0.6
		player.crouch_amt = 1.0
	if _watch is Fauna and (_watch as Fauna).kind == "hawk":
		(_watch as Fauna).state_t = 3.0
	# park the stand-in cat far away until it's time
	player.global_position = Vector3(30, 20, 30)
	player.visible = true


func _watch_pos() -> Vector3:
	if _watch is Swarms:
		var sw := _watch as Swarms
		return sw.center if sw.kind == "fish" else (sw.pos[0] if sw.kind != "ants" else sw.path[sw.path.size() / 3])
	return _watch.global_position


func _watch_cam(dt: float) -> void:
	if _watch == null:
		return
	var p := _watch_pos()
	var a := 0.6 + t * 0.05
	var want := p + Vector3(cos(a), 0.45, sin(a)) * _watch_dist
	want.y = maxf(want.y, ForestLevel.height(want.x, want.z) + 0.12)
	cam.global_position = want if t < 0.1 else cam.global_position.lerp(want, 1.0 - exp(-3.0 * dt))
	cam.look_at(p + Vector3(0, 0.05, 0), Vector3.UP)
	if _poke_t >= 0.0 and t > _poke_t:
		# the stand-in cat: slides in from 7 m out, straight at the animal, then stops beside it
		if _poke_from == Vector3.ZERO:
			_poke_from = p + Vector3(cos(a + 2.2), 0, sin(a + 2.2)) * 7.0
			player.global_position = _poke_from
		var cp := player.global_position
		var to := p - cp
		to.y = 0
		var step := to.normalized() * _poke_speed if to.length() > 0.35 else Vector3.ZERO
		player.velocity = step
		cp += step * dt
		cp.y = maxf(ForestLevel.height(cp.x, cp.z), ForestLevel.WATER_Y - 0.1) + 0.02
		player.global_position = cp
		player.yaw = atan2(-to.x, -to.z)
	if "--log" in OS.get_cmdline_user_args():
		for c in critters:
			var cr := c as Critter
			if _log_states.get(cr) != cr.state:
				_log_states[cr] = cr.state
				if t > 0.2:
					print("%.1f %s -> %s" % [t, cr.kind, cr.state])


func _process(dt: float) -> void:
	t += dt
	if _perf:
		# `-- --perf`: script cost per frame (process + physics), printed after 6 s
		_perf_n += 1
		_perf_sum += Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * Engine.physics_ticks_per_second / maxf(Engine.get_frames_per_second(), 1.0)
		if t > 6.0:
			print("perf: %.3f ms process, %.3f ms per physics tick, load %d ms" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, _load_ms])
			get_tree().quit()
	_shift_t -= dt
	if _shift_t < 0.0:
		_shift_t = 2.0
		Fauna.night_shift(critters)
		if water and atmos:
			water.set_sky(atmos.sky_mat.get_shader_parameter("horizon"))
	if _watch != null:
		_watch_cam(dt)
		return
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
		if cr.kind in ["butterfly", "hopper", "bat", "hawk"]:
			continue
		var dd := cr.global_position.distance_to(player.global_position)
		if dd < best:
			best = dd
			near = "%s nearby (%s)" % [cr.kind, cr.state]
	hud_label.text = "%d fps   %02d:%02d\n%.1f m/s   height %.2f m   kicks %d\n%s" % [Engine.get_frames_per_second(), int(atmos.hour), int(fmod(atmos.hour, 1.0) * 60.0), hs, player.global_position.y - ForestLevel.height(player.global_position.x, player.global_position.z), player.kicks_left, near]
	if player.toast_t < 1.2:
		event_label.text = player.toast
		event_label.modulate.a = 1.0 - player.toast_t / 1.2
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
