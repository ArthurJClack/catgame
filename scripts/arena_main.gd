extends Node3D
## the rat pit (res://arena.tscn, f10 from the house): a torch lit stone pit, waves of souls style
## rats (souls_rat.gd) that can only bite what's in front of them. circle them, bait the bite,
## dodge through it (alt / mouse4) and swat them from behind. health + stamina top left,
## nine lives under them. clearing a wave patches you back up.
##   r restart the pit · h hide help · 1-8 swap cat · v camera · f5 back to the house · tab lock on
## preview: `-- --arenatest` (headless rules check), `-- --arenashow` (bot fight for the video),
## `-- --combattest` / `-- --combatshow` (paw combat: swats, rakes, two paw grip; combat_test.gd)
## `-- --locktest` / `-- --lockshow` (tab lock on: pick, strafe, dodges, flick switch; lock_test.gd)

const R := 6.0                # pit radius
const WAVES := [
	[1.0],
	[1.0, 1.0],
	[1.0, 1.0, 1.0],
	[1.6, 1.0],
]

var player: CatPlayer
var hud: CanvasLayer
var event_label: Label
var help_label: Label
var wave_label: Label
var fade: ColorRect
var wave := 0
var rats: Array[SoulsRat] = []
var _between := 0.0
var _respawn := 0.0
var _fade_a := 0.0
var _torches: Array[OmniLight3D] = []
var _t := 0.0
var cam: Camera3D
var test_mode := false
var show_mode := false
var spawn := Vector3(0, 0.02, 4.4)


func _ready() -> void:
	process_priority = 10
	var args := OS.get_cmdline_user_args()
	test_mode = "--arenatest" in args or "--combattest" in args or "--locktest" in args
	show_mode = "--arenashow" in args or "--combatshow" in args or "--pounceshow" in args or "--lockshow" in args
	_setup_env()
	_build_pit()
	player = CatPlayer.new()
	player.position = spawn
	add_child(player)
	if Engine.has_meta("cat_style"):
		player.set_style.call_deferred(Engine.get_meta("cat_style"))
	player.health.died.connect(_on_died)
	player.souls_hud.show_lives = true
	_build_hud()
	if not (test_mode or show_mode) or "--puzzletest" in args:
		Puzzles.pit(self, player)   # lanterns on the pillars (puzzles.gd)
	if test_mode or show_mode:
		help_label.visible = false
		player.bot = {"move": Vector2.ZERO, "stamina": true}
		var t: ArenaTest = CombatTest.new() if ("--combattest" in args or "--combatshow" in args or "--pounceshow" in args) else ArenaTest.new()
		if "--locktest" in args or "--lockshow" in args:
			t = LockTest.new()
		t.arena = self
		add_child(t)
		return
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_start_wave(0)


# ---------------------------------------------------------------- waves

func _start_wave(i: int) -> void:
	wave = i
	for r in rats:
		if is_instance_valid(r):
			r.queue_free()
	rats.clear()
	var sizes: Array = WAVES[i] if i < WAVES.size() else _endless(i)
	var n := sizes.size()
	for k in n:
		# out of the gate at the far side, fanned out
		var a := PI + (float(k) - (n - 1) * 0.5) * 0.5
		spawn_rat(Vector3(sin(a) * (R - 1.2), 0.02, cos(a) * (R - 1.2)), sizes[k])
	wave_label.text = "wave %d" % (i + 1)
	player._event("wave %d · %d rat%s" % [i + 1, n, "" if n == 1 else "s"])


func _endless(i: int) -> Array:
	var a := [1.6]
	for k in mini(i - 2, 5):
		a.append(1.0)
	return a


func spawn_rat(pos: Vector3, size := 1.0) -> SoulsRat:
	var r := SoulsRat.new()
	r.s = size
	r.position = pos
	r.yaw = atan2(pos.x, pos.z)   # facing the middle
	r.target = player
	add_child(r)
	rats.append(r)
	r.killed.connect(_on_killed)
	return r


func alive_rats() -> int:
	var n := 0
	for r in rats:
		if is_instance_valid(r) and r.alive():
			n += 1
	return n


func _on_killed(_r: SoulsRat) -> void:
	var left := alive_rats()
	if left > 0:
		player._event("rat down · %d left" % left)
	elif not test_mode:
		player._event("wave %d cleared!" % (wave + 1))
		_between = 3.0


func _on_died(lives_left: int) -> void:
	if test_mode:
		return
	_respawn = 2.2
	if lives_left <= 0:
		player._event("out of lives. the pit wins this time")


func restart() -> void:
	player.health.lives = 9
	_put_back()
	_start_wave(0)


func _put_back() -> void:
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.orb_yaw = 0.0
	player.health.heal_full()
	player.stamina.value = CatStamina.MAX
	player.stamina.winded = false


func _physics_process(dt: float) -> void:
	_t += dt
	for i in _torches.size():
		_torches[i].light_energy = 1.6 + 0.25 * sin(_t * 9.0 + i * 1.7) + 0.15 * sin(_t * 23.0 + i)
	if test_mode or show_mode:
		return
	if _between > 0.0:
		_between -= dt
		if _between <= 0.0:
			player.health.heal_full()
			_start_wave(wave + 1)
	if _respawn > 0.0:
		_respawn -= dt
		_fade_a = minf(_fade_a + dt * 1.5, 1.0)
		if _respawn <= 0.0:
			if player.health.lives <= 0:
				restart()
			else:
				_put_back()
				_start_wave(wave)
	else:
		_fade_a = maxf(_fade_a - dt * 1.2, 0.0)
	fade.color.a = _fade_a
	if player.global_position.y < -3.0:
		_put_back()


func _process(_dt: float) -> void:
	if event_label and player:
		event_label.text = player.last_event if player.last_event_t < 2.2 else ""


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.bot.is_empty() or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_8:
		var order: Array = CatRig.STYLE_ORDER
		if k - KEY_1 < order.size():
			player.set_style(order[k - KEY_1])
	match k:
		KEY_R:
			restart()
		KEY_H:
			help_label.visible = not help_label.visible
		KEY_F5:
			Engine.set_meta("cat_style", player.style)
			get_tree().change_scene_to_file.call_deferred("res://main.tscn")


# ---------------------------------------------------------------- the pit

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.45)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 5.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.07, 0.08)
	env.fog_density = 0.04
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.0
	we.environment = env
	add_child(we)
	# cold moonlight from above so the pit floor reads, torches do the rest
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.85)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.rotation = Vector3(deg_to_rad(-62), deg_to_rad(30), 0)
	add_child(moon)


func _box(pos: Vector3, size: Vector3, c: Color, rot_y := 0.0, solid := true, surface := "") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = pos
	b.rotation.y = rot_y
	if solid:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		b.add_child(cs)
	if surface != "":
		b.set_meta("surface", surface)
	LowPoly.part(b, LowPoly.box(0.02), c, Vector3.ZERO, size)
	add_child(b)
	return b


func _build_pit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	# floor: one collider, flagstones on top for the look
	var fl := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(R * 2.4, 1.0, R * 2.4)
	fcs.shape = fbs
	fcs.position.y = -0.5
	fl.add_child(fcs)
	fl.set_meta("surface", "tile")
	add_child(fl)
	LowPoly.part(fl, LowPoly.box(0.0), Color(0.16, 0.15, 0.14), Vector3(0, -0.5, 0), Vector3(R * 2.4, 1.0, R * 2.4))
	# flagstones: one multimesh (one draw call), colour per stone
	var tile := 0.55
	var n := int(R * 2.0 / tile) + 1
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for ix in n:
		for iz in n:
			var x := -R + ix * tile + tile * 0.5
			var z := -R + iz * tile + tile * 0.5
			if Vector2(x, z).length() > R - 0.1:
				continue
			var g := rng.randf_range(0.27, 0.38)
			var c := Color(g, g * 0.96, g * 0.9)
			if rng.randf() < 0.12:
				c = c.lerp(Color(0.22, 0.26, 0.16), 0.5)   # moss
			var b := Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)).scaled(Vector3(tile - 0.035, 0.012, tile - 0.035))
			xfs.append(Transform3D(b, Vector3(x, 0.004 + rng.randf() * 0.004, z)))
			cols.append(c)
	_multi(fl, LowPoly.box(0.06), xfs, cols)
	# wall ring: too tall to hop out of, smooth stone (wall kicks work)
	var segs := 28
	for i in segs:
		var a := TAU * i / segs
		var p := Vector3(sin(a), 0, cos(a)) * (R + 0.25)
		var g := rng.randf_range(0.2, 0.27)
		_box(p + Vector3(0, 0.9, 0), Vector3(TAU * (R + 0.25) / segs + 0.05, 1.8, 0.5), Color(g, g * 0.95, g * 0.92), a)
		if i % 2 == 0:
			_box(p * 0.985 + Vector3(0, 1.85, 0), Vector3(0.5, 0.12, 0.6), Color(g * 0.8, g * 0.8, g * 0.78), a, false)
	# invisible lid on the wall so a double wall kick doesn't leave the pit
	for i in segs:
		var a := TAU * i / segs
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(TAU * (R + 0.25) / segs + 0.05, 3.0, 0.5)
		cs.shape = bs
		b.add_child(cs)
		b.position = Vector3(sin(a), 0, cos(a)) * (R + 0.25) + Vector3(0, 3.3, 0)
		b.rotation.y = a
		add_child(b)
	# the rat gate (far side): a dark arch in the wall
	_box(Vector3(0, 0.45, -(R + 0.02)), Vector3(0.9, 0.9, 0.08), Color(0.02, 0.02, 0.02), 0.0, false)
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * 0.5, 0.55, -(R - 0.05)), Vector3(0.12, 1.1, 0.16), Color(0.3, 0.27, 0.22), 0.0)
	_box(Vector3(0, 1.1, -(R - 0.05)), Vector3(1.12, 0.12, 0.16), Color(0.3, 0.27, 0.22), 0.0)
	# four broken pillars: cover, and something to wall kick off
	for i in 4:
		var a := TAU * i / 4 + PI / 4
		var h: float = [2.2, 1.3, 2.2, 0.7][i]
		var p := Vector3(sin(a), 0, cos(a)) * 3.3
		_box(p + Vector3(0, h * 0.5, 0), Vector3(0.5, h, 0.5), Color(0.34, 0.32, 0.3), a)
		_box(p + Vector3(0, 0.08, 0), Vector3(0.7, 0.16, 0.7), Color(0.28, 0.26, 0.24), a)
		if i == 3:
			_box(p + Vector3(0.6, 0.12, 0.3), Vector3(0.5, 0.24, 0.3), Color(0.33, 0.31, 0.29), a + 0.6)
	# bones + rubble
	var bxf: Array[Transform3D] = []
	var bcol: Array[Color] = []
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.0, R - 0.4)
		var p := Vector3(sin(a) * d, 0.012, cos(a) * d)
		if i % 3 == 0:
			_box(p + Vector3(0, 0.03, 0), Vector3(0.09, 0.06, 0.08) * rng.randf_range(0.7, 1.4), Color(0.25, 0.24, 0.22), rng.randf() * TAU, false)
		else:
			bxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.012, 0.01, rng.randf_range(0.05, 0.12))), p))
			bcol.append(Color(0.78, 0.74, 0.62))
	_multi(self, LowPoly.box(), bxf, bcol)
	# torches round the rim
	for i in 6:
		var a := TAU * i / 6 + PI / 6
		var p := Vector3(sin(a), 0, cos(a)) * (R - 0.05) + Vector3(0, 1.45, 0)
		_box(p, Vector3(0.06, 0.3, 0.06), Color(0.25, 0.17, 0.1), a, false)
		LowPoly.part(self, LowPoly.box(), Color(1.0, 0.55, 0.15), p + Vector3(0, 0.2, 0), Vector3(0.07, 0.1, 0.07), Vector3.ZERO, 4.0)
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, 0.3, 0) - Vector3(sin(a), 0, cos(a)) * 0.2
		l.light_color = Color(1.0, 0.6, 0.28)
		l.omni_range = 5.5
		l.light_energy = 1.6
		# omni shadows are very slow on the compatibility renderer (web): only on forward+
		l.shadow_enabled = i % 2 == 0 and not _compat()
		add_child(l)
		_torches.append(l)


func _compat() -> bool:
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "gl_compatibility" or OS.has_feature("web") or "gl_compatibility" in OS.get_cmdline_args()


func _multi(parent: Node, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = LowPoly.mat(Color.WHITE)
	parent.add_child(mi)


func _build_hud() -> void:
	hud = CanvasLayer.new()
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
	wave_label = Label.new()
	wave_label.anchor_left = 1.0
	wave_label.anchor_right = 1.0
	wave_label.offset_left = -200
	wave_label.offset_right = -22
	wave_label.offset_top = 16
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(wave_label, 22)
	hud.add_child(wave_label)
	help_label = Label.new()
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_top = -92
	help_label.offset_left = 18
	_style(help_label, 15)
	help_label.text = "the rat pit: rats can only bite what's in front of them. circle round, bait the bite, swat them from behind (double damage)\nalt / mouse4 dodge (i-frames) · mouse1 / mouse2 left / right paw (hold = rake) · both = rear up + pin it (can't walk while holding), release both = pounce · hold space + release / q leap = pounce (heavy hit) · watch your stamina\ntab lock on (wasd circles, flick mouse = switch rat, dodges go relative to it) · r restart · 1-8 swap cat · v camera · h hide help · f5 back to the house"
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
	fade = ColorRect.new()
	fade.anchor_right = 1.0
	fade.anchor_bottom = 1.0
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fade)


func _style(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
