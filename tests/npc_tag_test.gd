extends SceneTree
## farm cats play tag (npc_cat.gd): one stalks you, charges, bops you (a real play bop on your
## cat) and bolts; run straight at one and it bolts; bop one and it runs off, then comes back for you.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/npc_tag_test.gd [-- out/dir for a few stills]

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


func _shot(nm: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots + "/" + nm + ".png")


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			shots = a
	GameSettings.path = "user://npc_tag_test_settings.cfg"
	GameSettings.reset_defaults()
	CatKeys.reset()
	Tutorial.force = false
	GameSettings.s("hints", false)
	Engine.set_meta("title_done", true)
	change_scene_to_file("res://main.tscn")
	await _wait(20.0, func(): return current_scene != null and current_scene.get("player") != null)
	var main = current_scene
	var p: CatPlayer = main.player
	await _wait(1.5)
	p.set_view(2)
	var tux: NpcCat = main.npcs[0]
	var tab: NpcCat = main.npcs[1]
	for n in main.npcs:
		n.play_chance = 0.0    # only what the test starts
	if main.practice_cat:
		main.practice_cat.global_position = Vector3(4, 0.05, -1)

	# ---- 1. it charges you and tags you
	p.global_position = tux.global_position + Vector3(1.8, 0.05, 0)
	p.velocity = Vector3.ZERO
	await _wait(0.4)
	tux.play_cd = 0.0
	tux.mate = p
	tux._stalk()
	_ok(tux.state == "stalk", "tux crouches to stalk you")
	await _shot("1_stalk")
	var g0: int = p.spar.stats.got_tagged
	var chased := await _wait(15.0, func(): return tux.state == "chase" or tux.tags_given > 0)
	_ok(chased, "then charges")
	await _shot("2_chase")
	var got := await _wait(8.0, func(): return p.spar.stats.got_tagged > g0)
	_ok(got, "it reaches you and bops you (play bop, got_tagged %d -> %d)" % [g0, p.spar.stats.got_tagged])
	_ok(tux.tags_given == 1, "tux counts the tag (%d)" % tux.tags_given)
	await _wait(0.2)
	_ok(tux.state == "flee", "and bolts: you're it (%s)" % tux.state)
	_ok(p.health == null or p.health.value >= CatHealth.MAX - 0.001, "no damage")
	await _shot("3_bolt")
	var d0 := tux.global_position.distance_to(p.global_position)
	await _wait(10.0, func(): return tux.global_position.distance_to(p.global_position) > d0 + 0.5)
	_ok(tux.global_position.distance_to(p.global_position) > d0 + 0.3, "runs away from you (%.2f -> %.2f m)" % [d0, tux.global_position.distance_to(p.global_position)])

	# ---- 2. run straight at it: it bolts
	await _wait(1.0)
	tab.play_cd = 0.0
	tab.state = "idle"
	tab.state_t = 30.0
	var start := tab.global_position + Vector3(2.2, 0, 0.3)
	p.global_position = Vector3(start.x, p.global_position.y, start.z)
	await _wait(0.3)
	var bolted := false
	for i in 400:
		var to := tab.global_position - p.global_position
		to.y = 0
		if to.length() < 0.6:
			break
		await process_frame
		var dt: float = clampf(current_scene.get_process_delta_time(), 0.005, 0.1)   # game time
		p.global_position += to.normalized() * minf(3.5 * dt, to.length() - 0.5)
		p.velocity = Vector3.ZERO
		if tab.state == "flee":
			bolted = true
			break
	_ok(bolted, "run at the tabby and it bolts (%s)" % tab.state)

	# ---- 3. bop one: off it goes, then it comes back for you
	await _wait(3.5, func(): return tab.state != "flee")
	tab.state = "idle"
	tab.state_t = 30.0
	p.global_position = tab.global_position + Vector3(0.9, 0.05, 0)
	p.velocity = Vector3.ZERO
	await _wait(0.3)
	tab.play_tag("swat", p.global_position)
	tab.it_back = true
	_ok(tab.state == "flee" and tab.react == "swat", "bopped: flinch then off (%s)" % tab.state)
	var back := await _wait(25.0, func(): return tab.state in ["stalk", "chase"])
	_ok(back, "once it's clear it turns round and comes for you (%s)" % tab.state)
	await _shot("4_back")
	print("NPCTAGTEST %s (%d bad)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
