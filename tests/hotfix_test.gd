extends SceneTree
## headless cat + tab on farm cats: on the farm, every cat's head is drawn (yours in third person,
## the practice tabby, the farm cats), and tab locks on to the practice cat and the farm cats.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/hotfix_test.gd [-- out/dir]

var bad := 0
var shots := ""


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float, until: Callable = func(): return false) -> bool:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		if until.call():
			return true
	return until.call()


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _drawn_head(rig: CatRig) -> bool:
	var parts := rig.head_parts()
	if parts.is_empty():
		return false
	var shown := 0
	for m in parts:
		if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and m.is_visible_in_tree():
			shown += 1
		elif OS.get_cmdline_user_args().has("--why"):
			print("     hidden: %s shadow=%d vis=%s self=%s" % [rig.get_path_to(m), m.cast_shadow, m.is_visible_in_tree(), m.visible])
	return shown * 10 >= parts.size() * 8


func _shot(name: String) -> void:
	if shots == "":
		return
	await _wait(0.6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots + "/" + name + ".png")


func _face(p: CatPlayer, at: Vector3) -> void:
	var d := at - p.global_position
	p.yaw = atan2(-d.x, -d.z)
	p.orb_yaw = p.yaw
	p.pitch = -0.1


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			shots = a
	GameSettings.path = "user://hotfix_test_settings.cfg"
	GameSettings.reset_defaults()
	CatKeys.reset()
	Tutorial.force = false
	GameSettings.s("hints", false)
	Engine.set_meta("title_done", true)
	change_scene_to_file("res://main.tscn")
	await _wait(20.0, func(): return current_scene != null and current_scene.get("player") != null)
	var main = current_scene
	var p: CatPlayer = main.player
	await _wait(2.0)

	# --- heads
	_ok(p.view_mode == 0 and not _drawn_head(p.rig), "first person: your own head is hidden (camera's in it)")
	p.set_view(1)
	await _wait(0.5)
	_ok(_drawn_head(p.rig), "third person: your head is drawn")
	var pc: CatPlayer = main.practice_cat
	_ok(pc != null and _drawn_head(pc.rig), "practice cat has a head")
	for n in main.npcs:
		_ok(_drawn_head(n.rig), "farm cat %s has a head" % n.pattern)
		n.name = "Farm" + n.pattern.capitalize()
	if pc:
		_face(p, pc.global_position)
		await _shot("3p_practice")

	# --- tab lock on each cat
	p.set_view(0)
	var cats: Array = [pc] + Array(main.npcs)
	for n in main.npcs:
		n.play_chance = 0.0   # no surprise games of tag (npc_tag_test.gd covers those)
	for c in cats:
		if c == null:
			continue
		p.lock.release("")
		var cp: Vector3 = c.global_position
		var dir := (p.global_position - cp)
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
		p.global_position = cp + dir * 1.6
		p.velocity = Vector3.ZERO
		_face(p, cp)
		for i in 8:
			await process_frame
			await physics_frame
			_face(p, c.global_position)
		var eye: Vector3 = p.lock._eye()
		var pt: Vector3 = p.lock.point_of(c)
		print("     %s: d %.2f view %s sees %s valid %s" % [c.name, (pt - eye).length(), p.lock._in_view(pt, p._look_dir(), eye), p.lock._sees(c), p.lock._valid(c)])
		var picked := p.lock.acquire()
		_ok(picked and p.lock.target == c, "tab locks on to %s (got %s)" % [c.name, p.lock.target])
		_ok(p.spar.play_mode(), "locked on %s = play fight mode" % c.name)
		await _shot("lock_" + str(c.name))
		if c is NpcCat:
			var t0: int = c.tagged
			p.spar._send(c, ["tag", 99, "swat"])
			await _wait(0.2)
			_ok(c.tagged == t0 + 1 and c.react == "swat", "a play bop lands on %s" % c.name)
			_ok(p.spar.results.has(["swat", "hit"]), "and the answer comes back")
			var at: Vector3 = c.global_position
			print("     flee to %s from %s state %s" % [c.target, at, c.state])
			c.it_back = false
			var d0 := at.distance_to(p.global_position)
			await _wait(12.0, func(): return c.global_position.distance_to(p.global_position) > d0 + 0.15)
			_ok(c.global_position.distance_to(p.global_position) > at.distance_to(p.global_position) + 0.15, "%s scampers off (%.2f -> %.2f m)" % [c.name, at.distance_to(p.global_position), c.global_position.distance_to(p.global_position)])
	print("HOTFIXTEST %s (%d bad)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
