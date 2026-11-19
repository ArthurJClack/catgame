extends SceneTree
## clip of the "quiet paws" puzzle on pier 9 (puzzle_dog.gd) from a fixed camera by the guard hut:
## stalk in along the hut wall, eat the dog's dinner, stalk away. then come back at a gallop: it
## wakes, barks and lunges on its chain. `-- out/dir` also saves stills.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --write-movie out/dog.avi --fixed-fps 30 --script res://tests/dog_show.gd

var p: CatPlayer
var HZ := float(Engine.physics_ticks_per_second)
var bot := {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0}


func _initialize() -> void:
	_run.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String) -> void:
	var a := OS.get_cmdline_user_args()
	if a.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(a[0])
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [a[0], name])


func _go_to(to: Vector3, max_ticks: int) -> void:
	for i in max_ticks:
		var d := to - p.global_position
		d.y = 0
		if d.length() < 0.28:
			break
		bot.yaw = atan2(-d.x, -d.z)
		bot.move = Vector2(0, 1)
		await _ticks(1)
	bot.move = Vector2.ZERO


func _run() -> void:
	change_scene_to_file("res://stealth.tscn")
	for i in 30:
		await process_frame
	p = current_scene.player
	p.bot = bot
	for k in ["help_label", "hud"]:
		var n = current_scene.get(k)
		if n is CanvasItem or n is CanvasLayer:
			n.visible = false
	var z: Puzzles = current_scene.get_node("Puzzles")
	var q: QuietPaws = z.dog
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	cam.fov = 60
	cam.near = 0.02
	cam.current = true
	cam.global_position = Vector3(6.3, 1.25, 14.4)
	cam.look_at(Vector3(7.9, 0.15, 12.0))
	p.global_position = Vector3(4.4, 0.02, 11.8)
	p.velocity = Vector3.ZERO
	await _ticks(int(HZ * 1.5))
	await _shot("dog_0_asleep")
	bot.crouch = true
	await _ticks(20)
	await _go_to(q.bowl, int(HZ * 8))
	await _ticks(int(HZ * (QuietPaws.EAT_T * 0.5)))
	await _shot("dog_1_eating")
	await _ticks(int(HZ * (QuietPaws.EAT_T * 0.5 + 0.6)))
	await _go_to(Vector3(4.4, 0.02, 11.8), int(HZ * 6))
	bot.crouch = false
	await _ticks(int(HZ))
	# now back, loud: a gallop along the front of the hut
	p.global_position = Vector3(2.6, 0.02, 13.6)
	p.velocity = Vector3.ZERO
	bot.yaw = -PI / 2
	await _ticks(10)
	bot.sprint = true
	bot.move = Vector2(0, 1)
	await _ticks(int(HZ * 1.6))
	bot.sprint = false
	bot.move = Vector2.ZERO
	await _ticks(12)
	await _shot("dog_2_awake")
	bot.canter = true
	await _go_to(Vector3(4.0, 0.02, 15.5), int(HZ * 3))
	bot.canter = false
	await _ticks(int(HZ * 3))
	print("dog_show: ate %s, woke %d, shoves %d" % [str(q.done), q.wakes, q.shoves])
	quit()
