extends SceneTree
## the forest / trail / city puzzles (puzzle_more.gd): each level builds its Puzzles node with a
## cat sense point, knocking the prop off its ledge solves it (crow's shiny, boulder bag) and
## sitting still on the city vent solves that one. `-- out/dir` saves a still of each prop.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/more_puzzles_test.gd

var bad := 0
var shots := ""


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _player() -> CatPlayer:
	var p = current_scene.get("player") if current_scene else null
	return p if p is CatPlayer and p.is_inside_tree() else null


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		await physics_frame


func _load(path: String) -> Puzzles:
	change_scene_to_file(path)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		if _player() != null and current_scene.get_node_or_null("Puzzles") != null:
			break
	await _frames(10)
	return current_scene.get_node_or_null("Puzzles") if current_scene else null


## the cat stands `back` m from `at`, looking at it (first person) and a still is saved
func _look(p: CatPlayer, at: Vector3, from: Vector3, name: String) -> void:
	if shots == "":
		return
	p.global_position = from
	p._phys_curr = from
	p.velocity = Vector3.ZERO
	var d := at - from
	p.orb_yaw = atan2(-d.x, -d.z)
	p.yaw = p.orb_yaw
	p.pitch = atan2(d.y - 0.25, Vector2(d.x, d.z).length())
	await _frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots + "/" + name + ".png")


func _knock(z: Puzzles, id: String, label: String) -> void:
	var k: Dictionary = {}
	for kk in z.more.knocks:
		if kk.id == id:
			k = kk
	_ok(not k.is_empty(), "%s: %s is built" % [label, id])
	if k.is_empty():
		return
	_ok(z.sense.points.has(id), "%s: cat sense point" % label)
	var rb: RigidBody3D = k.rb
	var start := rb.global_position
	await _frames(30)
	_ok(rb.global_position.distance_to(start) < 0.05, "%s: it sits still on its ledge (%.3f m)" % [label, rb.global_position.distance_to(start)])
	_ok(int(Puzzles.solved.get(id, 0)) == 0, "%s: not solved yet" % label)
	await _look(z.player, start, Vector3(start.x + 2.2, start.y - (2.9 if id == "crow_shiny" else 1.8), start.z + 2.2), id)
	# a swat's worth of shove off the edge
	rb.sleeping = false
	rb.linear_velocity = Vector3(1, 0.3, 0.6).normalized() * 3.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and int(Puzzles.solved.get(id, 0)) == 0:
		await _frames(1)
	_ok(int(Puzzles.solved.get(id, 0)) == 1, "%s: knocked off = solved (fell %.1f m)" % [label, start.y - rb.global_position.y])
	_ok(z.treats.size() > 0, "%s: treats spill" % label)


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		shots = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(shots)
	Engine.set_meta("title_done", true)
	GameSettings.s("hints", false)
	Puzzles.solved = {}
	_ok(Puzzles.LIST.size() == 10, "10 puzzles in the list")

	var z := await _load("res://forest.tscn")
	_ok(z != null, "forest: puzzles node")
	if z:
		await _knock(z, "crow_shiny", "forest")

	z = await _load("res://trail.tscn")
	_ok(z != null, "trail: puzzles node")
	if z:
		await _knock(z, "trail_boulder", "trail")

	z = await _load("res://city.tscn")
	_ok(z != null, "city: puzzles node")
	if z:
		var s: Dictionary = z.more.sits[0]
		_ok(s.id == "warm_vent" and z.sense.points.has("warm_vent"), "city: vent + sense point")
		var p := z.player
		await _look(p, s.pos, s.pos + Vector3(1.6, 0.05, 1.2), "warm_vent")
		var on: Vector3 = s.pos + Vector3(0, 0.08, 0)
		p.global_position = on
		p._phys_curr = on
		p.velocity = Vector3.ZERO
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 20000 and int(Puzzles.solved.get("warm_vent", 0)) == 0:
			await _frames(1)
		_ok(int(Puzzles.solved.get("warm_vent", 0)) == 1, "city: sitting still on the vent = solved (cat at %s, vent %s)" % [p.global_position, s.pos])
	Puzzles.solved = {}
	print("more_puzzles_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
