extends SceneTree
## play fighting online with two real games on this machine over lan: the friend tabs on to the
## host's cat (a RemoteCat), it's play mode, a bop lands on the host's cat and the answer comes
## back; then the friend tabs on to a farm cat and bops it (the host runs farm cats it's nearest,
## so that bop gets forwarded to the host).
## run the host first, the friend ~20 s later:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/spar_net_test.gd -- host /tmp/sn
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/spar_net_test.gd -- join /tmp/sn

const PORT := 24717
var bad := 0
var role := "host"
var dir := "/tmp/sn"
var net: Node


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
		_dump()
		if until.call():
			return true
	return until.call()


func _sleep(sec: float) -> void:
	await _wait(sec, func(): return false)


func _in(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path and not root.has_node("HubFade") and current_scene.get("player") != null


var _dump_t := 0
func _dump() -> void:
	if role != "host" or not _in("res://main.tscn"):
		return
	if Time.get_ticks_msec() - _dump_t < 200:
		return
	_dump_t = Time.get_ticks_msec()
	var npc := 0
	for n in current_scene.npcs:
		npc += n.tagged
	var d := {"got": current_scene.player.spar.stats.got_tagged, "npc": npc}
	var f := FileAccess.open(dir + "/host.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _host_state() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(dir + "/host.json"))
	return d if d is Dictionary else {}


func _face(p: CatPlayer, at: Vector3) -> void:
	var d := at - p.global_position
	p.yaw = atan2(-d.x, -d.z)
	p.orb_yaw = p.yaw
	p.pitch = -0.1


func _stand_by(p: CatPlayer, at: Vector3, from: Vector3) -> void:
	var dir3 := from - at
	dir3.y = 0
	dir3 = dir3.normalized() if dir3.length() > 0.1 else Vector3.BACK
	for i in 10:
		p.global_position = Vector3(at.x, p.global_position.y, at.z) + dir3 * 1.3
		p.velocity = Vector3.ZERO
		_face(p, at)
		await process_frame
		await physics_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	dir = args[1] if args.size() > 1 else dir
	DirAccess.make_dir_recursive_absolute(dir)
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.my_name = role + " cat"
	Engine.set_meta("title_done", true)
	change_scene_to_file("res://main.tscn")
	await _wait(60, func(): return _in("res://main.tscn"))
	if role == "host":
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute("%s/%s" % [dir, f])
		net.host_lan(PORT)
		await _wait(120, func(): return net.transport.members().size() == 1 and net.peers.values()[0].hello_seen)
		_ok(net.peers.size() == 1, "friend joined")
		await _sleep(2)
		net.start_match("res://main.tscn")
		await _sleep(4)
		await _wait(60, func(): return _in("res://main.tscn"))
		var pl: CatPlayer = current_scene.player
		pl.global_position = Vector3(0.0, 0.05, 0.6)
		pl.velocity = Vector3.ZERO
		# park the farm cats next to the host's cat: the host runs them
		for n in current_scene.npcs:
			n.area = Rect2(-1.0, 0.0, 2.0, 1.4)
		await _wait(400, func(): return FileAccess.file_exists(dir + "/join_done"))
		print("spar net test [host]: %s" % ("PASS" if bad == 0 else "%d FAILED" % bad))
		net.leave()
		quit(1 if bad else 0)
		return
	await _sleep(1)
	net.join_server("127.0.0.1:%d" % PORT)
	await _sleep(8)
	await _wait(120, func(): return _in("res://main.tscn") and net.world != null and net.world.active)
	var p: CatPlayer = current_scene.player
	var found := []    # (lambdas copy locals: hand the result back in an array)
	await _wait(60, func():
		for n in current_scene.get_tree().get_nodes_in_group("spar_cat"):
			if n is RemoteCat and n.rig and n.rig.visible:
				found.append(n)
		return not found.is_empty())
	var rc: RemoteCat = found[0] if not found.is_empty() else null
	_ok(rc != null, "the host's cat shows up")
	if rc == null:
		_finish()
		return
	await _sleep(3)
	# ---- tab on the host's cat
	await _stand_by(p, rc.rig.global_position, p.global_position)
	var inp := {"lock_on": true}
	p._human_buttons(inp)
	_ok(inp.lock_on, "tab isn't swallowed next to another player's cat")
	var got := p.lock.acquire()
	_ok(got and p.lock.target == rc, "tab locks on to the host's cat (%s)" % p.lock.target)
	_ok(p.spar.play_mode(), "= play fight mode")
	var g0 := int(_host_state().get("got", 0))
	p.spar.strike_start()
	p.spar._tag(rc, "swat")
	var landed := await _wait(20, func(): return int(_host_state().get("got", 0)) > g0)
	_ok(landed, "the bop lands on the host's cat (%d -> %d)" % [g0, int(_host_state().get("got", 0))])
	var back := await _wait(20, func(): return p.spar.results.size() > 0)
	_ok(back, "the host's answer comes back (%s)" % str(p.spar.results))
	# ---- tab on a farm cat the host runs
	p.lock.release("")
	var npc: NpcCat = current_scene.npcs[0]
	await _stand_by(p, npc.global_position, npc.global_position + Vector3(0, 0, 2))
	await _stand_by(p, npc.global_position, p.global_position)
	got = p.lock.acquire()
	_ok(got and p.lock.target is NpcCat, "tab locks on to a farm cat online (%s)" % p.lock.target)
	var n0 := int(_host_state().get("npc", 0))
	var l0 := 0
	for n in current_scene.npcs:
		l0 += n.tagged
	if p.lock.target is NpcCat:
		p.spar._tag(p.lock.target, "swat")
	var npc_hit := await _wait(20, func():
		var l := 0
		for n in current_scene.npcs:
			l += n.tagged
		return int(_host_state().get("npc", 0)) > n0 or l > l0)
	_ok(npc_hit, "the farm cat takes the bop (host %d -> %d)" % [n0, int(_host_state().get("npc", 0))])
	_finish()


func _finish() -> void:
	FileAccess.open(dir + "/join_done", FileAccess.WRITE).store_string("1")
	print("spar net test [join]: %s" % ("PASS" if bad == 0 else "%d FAILED" % bad))
	net.leave()
	quit(1 if bad else 0)
