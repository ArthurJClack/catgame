extends Node3D
## the play mat (res://spar.tscn): a sunny room with a rug and a practice cat to play fight with.
## tab locks on to it and the rounds start (cat_spar.gd). r = new match, f5 = back to the farm.
## `-- --spartest` runs the rules check (spar_test.gd), `-- --sparshow` films a bot vs bot bout,
## `-- --sparstyle guard|duck|counter|idle|auto` pins what the practice cat does.

var player: CatPlayer
var dummy: CatPlayer
var test_mode := false
var show_mode := false
var spawn := Vector3(0, 0.02, 1.0)
var dummy_spawn := Vector3(0, 0.02, -0.2)


func _ready() -> void:
	process_priority = 10
	var args := OS.get_cmdline_user_args()
	test_mode = "--spartest" in args
	show_mode = "--sparshow" in args
	_setup_env()
	_build_room()
	player = CatPlayer.new()
	player.position = spawn
	add_child(player)
	if Engine.has_meta("cat_style"):
		player.set_style.call_deferred(Engine.get_meta("cat_style"))
	dummy = make_dummy(self, dummy_spawn, player, "block")
	var si := args.find("--sparstyle")
	if si >= 0 and si + 1 < args.size():
		dummy.spar.brain.style = args[si + 1]
	if test_mode or show_mode:
		var t := SparTest.new()
		t.main = self
		t.show = show_mode
		add_child(t)


## a practice cat (bot CatPlayer + CatSparBrain) that plays with `opp`. usable from any level
static func make_dummy(host: Node, at: Vector3, opp: CatPlayer, style := "block") -> CatPlayer:
	var d := CatPlayer.new()
	d.spar_dummy = true
	d.bot = {"move": Vector2.ZERO, "stamina": false}
	d.position = at
	d.yaw = PI
	d.name = "PracticeCat"
	host.add_child(d)
	d.set_style.call_deferred(style)
	d.spar.forced = opp
	# a bot's camera must never take over the screen
	d.cam.current = false
	if opp and opp.cam:
		opp.cam.current = true
	return d


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				player.global_position = spawn
				dummy.global_position = dummy_spawn
				player.spar._end_match("")
				dummy.spar._end_match("")
			KEY_F5:
				if has_method("go_scene"):
					call("go_scene", "res://main.tscn")
				else:
					get_tree().change_scene_to_file("res://main.tscn")


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.8, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.88, 0.78)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 5.0
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(35), 0)
	add_child(sun)


func _build_room() -> void:
	# wooden floor, a round-ish rug, low walls, a few cushions and a box to bounce off
	_box(Vector3(0, -0.05, 0), Vector3(9, 0.1, 9), Color(0.4, 0.28, 0.19), 0.0, true, "wood")
	_box(Vector3(0, 0.004, 0.4), Vector3(3.4, 0.008, 2.6), Color(0.5, 0.22, 0.2), 0.0, false)
	_box(Vector3(0, 0.006, 0.4), Vector3(2.8, 0.008, 2.0), Color(0.62, 0.55, 0.38), 0.0, false)
	for w in [[Vector3(0, 0.6, -4.5), Vector3(9, 1.2, 0.1)], [Vector3(0, 0.6, 4.5), Vector3(9, 1.2, 0.1)],
			[Vector3(-4.5, 0.6, 0), Vector3(0.1, 1.2, 9)], [Vector3(4.5, 0.6, 0), Vector3(0.1, 1.2, 9)]]:
		_box(w[0], w[1], Color(0.7, 0.66, 0.6))
	_box(Vector3(-2.4, 0.08, -1.6), Vector3(0.7, 0.16, 0.7), Color(0.35, 0.5, 0.7), 0.3)
	_box(Vector3(2.5, 0.08, 1.9), Vector3(0.7, 0.16, 0.7), Color(0.55, 0.65, 0.4), -0.4)
	_box(Vector3(2.6, 0.2, -2.2), Vector3(0.6, 0.4, 0.5), Color(0.7, 0.58, 0.4), 0.2)


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
