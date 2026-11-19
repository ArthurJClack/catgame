extends SceneTree
## clip of the "herd the chicks" puzzle (puzzle_herd.gd) from a camera up over the yard. the cat
## is driven like a player would: gallop at them once (scatter), then walk round behind each chick
## and ease it toward the gap. writes PNG stills too when given `-- out/dir`.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --write-movie out/herd.avi --fixed-fps 30 --script res://tests/herd_show.gd

var p: CatPlayer
var bot := {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0}
var cam: Camera3D


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


## steer the cat at walking pace toward a spot (true when it's there)
func _walk_to(want: Vector3, look: Vector3, fast := false) -> bool:
	var d := want - p.global_position
	d.y = 0
	if d.length() < 0.12:
		bot.move = Vector2.ZERO
		var l := look - p.global_position
		bot.yaw = atan2(-l.x, -l.z)
		return true
	bot.yaw = atan2(-d.x, -d.z)
	bot.move = Vector2(0, 1.0 if fast else clampf(d.length() * 0.8, 0.25, 0.5))
	return false


func _run() -> void:
	change_scene_to_file("res://main.tscn")
	for i in 30:
		await process_frame
	p = current_scene.player
	p.bot = bot
	var z: Puzzles = current_scene.get_node("Puzzles")
	var h: HerdChicks = z.herd
	cam = Camera3D.new()
	current_scene.add_child(cam)
	cam.fov = 58
	cam.current = true
	cam.global_position = Vector3(15.2, 3.4, 12.6)
	cam.look_at(Vector3(20.2, 0, 11.4))
	var hl = current_scene.get("help_label")
	if hl is Control:
		(hl as Control).visible = false
	p.global_position = Vector3(13.8, 0.02, 9.4)
	p.velocity = Vector3.ZERO
	await _ticks(60)
	await _shot("herd_0_loose")
	# gallop straight through them: they scatter
	bot.yaw = atan2(-(17.4 - 13.8), -(9.4 - 9.4))
	bot.move = Vector2(0, 1)
	bot.sprint = true
	await _ticks(25)
	await _shot("herd_1_scatter")
	await _ticks(25)
	bot.sprint = false
	bot.move = Vector2.ZERO
	await _ticks(70)
	var gap := Vector3(HerdChicks.PEN.position.x - 0.9, 0, (HerdChicks.GAP_Z.x + HerdChicks.GAP_Z.y) * 0.5)
	var t := 0
	var shot_mid := false
	while not h.done and t < 30 * 300:
		var best: CharacterBody3D = null
		var bd := 1e9
		for c in h.chicks:
			if not h.in_pen(c.global_position):
				var dd := c.global_position.distance_to(gap)
				if dd < bd:
					bd = dd
					best = c
		if best == null:
			bot.move = Vector2.ZERO
			await _ticks(1)
			t += 1
			continue
		var cp := best.global_position
		cp.y = 0
		var aligned := absf(cp.z - gap.z) < 0.35 and cp.x > gap.x - 0.6 and cp.x < HerdChicks.PEN.position.x + 0.3
		var target: Vector3 = h.grain if aligned else gap
		var back := cp - target
		back.y = 0
		back = back.normalized()
		var flat := Vector3(p.global_position.x, 0, p.global_position.z)
		var rel := flat - cp
		var want: Vector3
		if rel.length() < 2.0 and rel.normalized().dot(back) < 0.6:
			var tang := Vector3(-rel.z, 0, rel.x).normalized()
			if tang.dot(back) < 0.0:
				tang = -tang
			want = cp + (rel.normalized() * 2.0 + tang * 0.9).normalized() * 2.0
		else:
			want = cp + back * 1.15
		_walk_to(want, cp)
		await _ticks(1)
		t += 1
		if not shot_mid and h.inside() >= 3:
			shot_mid = true
			await _shot("herd_2_three_in")
	bot.move = Vector2.ZERO
	print("herd_show: done %s after %.0f s, %d in" % [str(h.done), t / 30.0, h.inside()])
	await _ticks(50)
	await _shot("herd_3_gate_shut")
	await _ticks(60)
	quit()
