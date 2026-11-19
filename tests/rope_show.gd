extends SceneTree
## clip of the "pull the string" puzzle from a fixed side camera (puzzle_rope.gd):
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --write-movie out/rope.avi --fixed-fps 30 --script res://tests/rope_show.gd

var p: CatPlayer
var bot := {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0}


func _initialize() -> void:
	_run.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _put(pos: Vector3, look: Vector3) -> void:
	p.velocity = Vector3.ZERO
	p.global_position = pos
	var d := look - (pos + Vector3.UP * 0.25)
	bot.yaw = atan2(-d.x, -d.z)
	bot.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.yaw = bot.yaw
	p.orb_yaw = bot.yaw


func _run() -> void:
	change_scene_to_file("res://main.tscn")
	for i in 30:
		await process_frame
	p = current_scene.player
	p.bot = bot
	var z: Puzzles = current_scene.get_node("Puzzles")
	var r: PullString = z.rope
	var tl := r.rest_tail()
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	cam.global_position = Vector3(tl.x + 2.3, 1.2, tl.z - 1.1)
	cam.look_at(Vector3(tl.x, 1.1, tl.z - 0.2))
	cam.fov = 62
	cam.current = true
	var stand := Vector3(tl.x, 0.02, tl.z - 0.32)
	_put(stand, tl + Vector3(0, 0.12, 0))
	await _ticks(90)
	bot.paw_l = true          # bat it first: it only swings
	await _ticks(3)
	bot.paw_l = false
	await _ticks(200)
	for tries in 4:
		if r.falling:
			break
		_put(stand, tl + Vector3(0, 0.12, 0))
		await _ticks(20)
		p.call("_claw_start", 0)
		for k in 24:
			_put(stand + Vector3(0, 0, -0.016 * k), tl + Vector3(0, 0.05, 0))
			await _ticks(3)
		p.call("_claw_release")
		await _ticks(120)
	await _ticks(500)
	quit()
