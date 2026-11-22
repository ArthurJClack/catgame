extends SceneTree
## online lobby round trip with two real games on this machine (lan / enet on 127.0.0.1):
##   host:   title -> play online -> host on lan -> waits for the friend to tick ready -> start
##   friend: joins by ip -> sees the room -> picks a coat + ticks ready -> gets loaded into the level
## run both (the friend a moment later), each prints ok / FAIL lines and exits 0 / 1:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/lobby_test.gd -- host [shots_dir]
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/lobby_test.gd -- join [shots_dir]

const PORT := 24711
const LEVEL := "res://trail.tscn"
var bad := 0
var role := "host"
var shots := ""


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + "[%s] %s" % [role, what])
	if not cond:
		bad += 1


func _wait(sec: float, until: Callable) -> bool:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		if until.call():
			return true
	return until.call()


func _shot(nm: String) -> void:
	if shots == "":
		return
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [shots, role, nm])


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var b := _find_button(c, prefix)
		if b:
			return b
	return null


func _press(n: Node, prefix: String) -> bool:
	var b := _find_button(n, prefix)
	if b:
		b.pressed.emit()
	return b != null


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	shots = args[1] if args.size() > 1 else ""
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	root.size = Vector2i(1600, 900)
	GameSettings.path = "user://settings_lobbytest_%s.cfg" % role
	var net = root.get_node("Net")
	net.my_name = "host cat" if role == "host" else "friend cat"
	if role == "host":
		TitleScreen.force = true
	Engine.remove_meta("title_done")
	change_scene_to_file("res://main.tscn")
	await _wait(60, func(): return current_scene != null and current_scene.get("player") != null)
	await _wait(3, func(): return false)
	var ui = net.ui
	_ok(ui != null, "lobby ui exists")
	if role == "host":
		var title = get_nodes_in_group("title_screen")
		_ok(title.size() == 1, "title screen up")
		_ok(_press(title[0], "play online"), "play online button")
		await _wait(5, func(): return ui.visible)
		_ok(ui.visible and ui.page == "home", "lobby home opens over the title")
		await _wait(1, func(): return false)
		_ok(not title[0]._root.visible, "title menu hides under the lobby")
		await _shot("1_home")
		net.host_lan(PORT)
		await _wait(5, func(): return ui.page == "room")
		_ok(net.in_room() and net.is_host(), "hosting a lan room")
		net.set_level(LEVEL)
		# friend joins + ticks ready
		var joined := await _wait(90, func(): return net.transport.members().size() == 1)
		_ok(joined, "friend joined")
		var ready := await _wait(60, func(): return net.everyone_ready() == false and net.peers.size() == 1 and net.peers.values()[0].ready)
		_ok(ready, "friend shows ready")
		var fp = net.peers.values()[0] if net.peers.size() > 0 else null
		_ok(fp != null and fp.style == "stepped_coon", "friend's coat shows (%s)" % (fp.style if fp else "-"))
		await _wait(1, func(): return false)
		await _shot("2_room_friend_ready")
		var sb := _find_button(ui, "start")
		_ok(sb != null and "1 / 2" in sb.text, "start shows 1 / 2 ready (%s)" % (sb.text if sb else "-"))
		_ok(_press(ui, "ready!"), "host ticks ready")
		await _wait(5, func(): return net.everyone_ready())
		await _wait(1, func(): return false)
		await _shot("3_room_all_ready")
		_ok(_press(ui, "start"), "press start")
	else:
		await _wait(3, func(): return false)
		net.join_server("127.0.0.1:%d" % PORT)
		ui.open()
		var inroom := await _wait(60, func(): return net.in_room() and net.transport.connected() and net.host_peer() != null and net.host_peer().hello_seen)
		_ok(inroom, "joined the host's room")
		# past the old 10 s "couldn't reach" timeout
		await _wait(12, func(): return false)
		_ok(net.in_room(), "still connected after 12 s")
		var hp = net.host_peer()
		_ok(hp != null and hp.level == LEVEL, "sees the host's level pick")
		await _shot("1_room")
		net.set_style("stepped_coon")
		_ok(_press(ui, "ready!"), "tick ready")
	var loaded := await _wait(120, func(): return current_scene != null and current_scene.scene_file_path == LEVEL and not root.has_node("HubFade"))
	_ok(loaded, "loaded into %s" % LEVEL)
	_ok(get_nodes_in_group("title_screen").is_empty(), "title gone")
	_ok(not ui.visible, "lobby closed for the match")
	var other := await _wait(60, func():
		for c in current_scene.get_children():
			if c is RemoteCat:
				return true
		return false)
	_ok(other, "the other cat is in the level")
	await _wait(3, func(): return false)
	await _shot("4_in_level")
	ui.open()
	await _wait(1, func(): return false)
	_ok(ui.page == "room", "m mid match shows the room (%s)" % ui.page)
	await _shot("5_mid_match")
	ui.close()
	await _wait(4, func(): return false)
	print("lobby test [%s]: %s" % [role, "PASS" if bad == 0 else "%d FAILED" % bad])
	net.leave()
	quit(1 if bad else 0)
