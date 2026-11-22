extends SceneTree
## online world sync (net/world_sync.gd) with two real games on this machine over lan.
## both games write what they see to a shared folder, the friend compares:
##   1. rat pit: the same rats (keys, owners, positions) in both games
##   2. the friend swats a rat the host runs: the host's rat loses the hp
##   3. the friend kills the wave: both games move on to the same next wave
##   4. the farm: the host knocks a prop flying, it lands in the same spot for the friend,
##      then the friend knocks one and the host sees it
## run the host first, the friend ~20 s later:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/world_sync_test.gd -- host /tmp/ws
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/world_sync_test.gd -- join /tmp/ws

const PORT := 24713
var bad := 0
var role := "host"
var dir := "/tmp/ws"
var net: Node
var _write_t := 0.0


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


func _flag(nm: String) -> void:
	FileAccess.open("%s/%s" % [dir, nm], FileAccess.WRITE).store_string("1")


func _has_flag(nm: String) -> bool:
	return FileAccess.file_exists("%s/%s" % [dir, nm])


## what this game sees: entity key -> [pos, owner, extra]
func _state() -> Dictionary:
	var w: NetWorld = net.world
	var out := {}
	for h in w.entities:
		var e = w.entities[h]
		if not is_instance_valid(e.node):
			continue
		var x := {}
		if e.kind == "rat":
			x = {"hp": e.node.hp, "state": e.node.state}
		out[e.key] = {"p": var_to_str(e.node.global_position), "o": e.owner, "x": x}
	return out


func _dump() -> void:
	if net == null or net.world == null:
		return
	var now := Time.get_ticks_msec()
	if now - _write_t < 150:
		return
	_write_t = now
	var d := {"t": Time.get_unix_time_from_system(), "scene": current_scene.scene_file_path if current_scene else "",
		"me": net.my_id(), "e": _state(), "wave": current_scene.get("wave") if current_scene else -1}
	var f := FileAccess.open("%s/%s_state.json.tmp" % [dir, role], FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	DirAccess.rename_absolute("%s/%s_state.json.tmp" % [dir, role], "%s/%s_state.json" % [dir, role])


func _theirs() -> Dictionary:
	var other := "host" if role == "join" else "join"
	var s := FileAccess.get_file_as_string("%s/%s_state.json" % [dir, other])
	var d = JSON.parse_string(s) if s != "" else null
	return d if d is Dictionary else {}


func _in(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path and not root.has_node("HubFade") and current_scene.get("player") != null


func _rats() -> Array:
	var out := []
	for c in current_scene.get_children():
		if c is SoulsRat:
			out.append(c)
	return out


## positions of the same keys in both games (theirs is up to ~0.2 s old, so moving rats get slack)
func _compare(kind: String, tol: float) -> Array:
	var th := _theirs()
	var mine := _state()
	var n := 0
	var worst := 0.0
	var owners_agree := true
	for k in mine:
		if not k.begins_with(kind) or not th.get("e", {}).has(k):
			continue
		var a: Vector3 = str_to_var(mine[k].p)
		var b: Vector3 = str_to_var(th.e[k].p)
		worst = maxf(worst, a.distance_to(b))
		if int(mine[k].o) != int(th.e[k].o):
			owners_agree = false
		n += 1
	return [n, worst, owners_agree]


func _ent(key: String):
	for h in net.world.entities:
		if net.world.entities[h].key == key:
			return net.world.entities[h]
	return null


func _key_of(n: Node) -> String:
	for h in net.world.entities:
		if net.world.entities[h].node == n:
			return net.world.entities[h].key
	return ""


## the n-th loose prop (not a puzzle's frozen one, not prey) in tree order: the same one in both games
func _free_prop(n: int) -> RigidBody3D:
	var keys := []
	for h in net.world.entities:
		var e = net.world.entities[h]
		if e.kind == "rb" and not e.node.is_in_group("prey") and not e.saved_freeze and (e.node as RigidBody3D).mass < 3.0:
			keys.append(e.key)
	keys.sort()
	return _ent(keys[n % keys.size()]).node


func _knock(rb: RigidBody3D) -> void:
	NetWorld.touch(rb)
	rb.freeze = false
	rb.sleeping = false
	rb.apply_central_impulse(Vector3(0.6, 1.2, 0.3) * rb.mass)


func _key_dist(key: String) -> float:
	var th := _theirs()
	var e = _ent(key)
	if e == null or not th.get("e", {}).has(key):
		return INF
	return e.node.global_position.distance_to(str_to_var(th.e[key].p))


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
		net.start_match("res://arena.tscn")
	else:
		net.join_server("127.0.0.1:%d" % PORT)
	# ---- 1. the pit: same rats
	var there := await _wait(120, func(): return _in("res://arena.tscn"))
	_ok(there, "in the rat pit")
	var both := await _wait(60, func(): return net.world.active and _theirs().get("scene", "") == "res://arena.tscn")
	_ok(both, "world sync on in both games")
	if role == "host":
		# walk over to the rat side: the rat is nearest the host's cat, so the host runs it and
		# it comes at the host (a moving rat to compare)
		var pl: CatPlayer = current_scene.player
		pl.global_position = Vector3(0, 0.05, -1.5)
		pl.velocity = Vector3.ZERO
	await _sleep(6)
	if role == "host":
		await _wait(400, func(): return _has_flag("pit_done"))
		net.start_match("res://main.tscn")
		await _wait(120, func(): return _in("res://main.tscn") and net.world.active)
		await _wait(240, func(): return _has_flag("farm_ready"))
		await _sleep(3)
		var rb := _free_prop(0)
		var kf := FileAccess.open("%s/host_knocked" % dir, FileAccess.WRITE)
		kf.store_string(_key_of(rb))
		kf.close()
		print("knocked ", _key_of(rb))
		_knock(rb)
		await _wait(400, func(): return _has_flag("join_done"))
		_flag("host_done")
		await _sleep(2)
		print("world sync test [host]: %s" % ("PASS" if bad == 0 else "%d FAILED" % bad))
		net.leave()
		quit(1 if bad else 0)
		return
	var c := _compare("rat", 0.45)
	_ok(c[0] >= 1, "same rats in both games (%d matched)" % c[0])
	_ok(c[1] < 0.45, "rat positions match (worst %.2f m)" % c[1])
	_ok(c[2], "both games agree who runs each rat")
	_ok(int(_theirs().get("wave", -1)) == int(current_scene.wave), "same wave")
	# ---- 2. swat a rat the host runs: hp drops in the host's game
	var w: NetWorld = net.world
	var victim: SoulsRat = null
	for r in _rats():
		for h in w.entities:
			var e = w.entities[h]
			if e.node == r and e.owner != net.my_id() and r.alive():
				victim = r
	_ok(victim != null, "the host runs the rat next to its cat")
	if victim == null:
		victim = _rats()[0]
	var key := ""
	for h in w.entities:
		if w.entities[h].node == victim:
			key = w.entities[h].key
	var hp0: float = float(_theirs().e[key].x.hp)
	var fwd0 := w.forwarded
	victim.take_hit(1.0, victim.global_position + Vector3(0, 0, 0.3))
	_ok(w.forwarded == fwd0 + 1, "hit on the host's rat was sent to the host")
	var dropped := await _wait(5, func(): return float(_theirs().e.get(key, {"x": {"hp": hp0}}).x.hp) < hp0)
	_ok(dropped, "host's rat lost hp (%.1f -> %.1f)" % [hp0, float(_theirs().e.get(key, {"x": {"hp": hp0}}).x.hp)])
	var mirrored := await _wait(3, func(): return victim.hp < hp0)
	_ok(mirrored, "the friend's copy shows it too (%.1f)" % victim.hp)
	# ---- 3. kill the wave from here: both games move on to the next one
	var w0 := int(current_scene.wave)
	for i in 40:
		for r in _rats():
			if r.alive():
				r.take_hit(3.0, r.global_position + Vector3(0, 0, 0.3), true)
		await _sleep(0.3)
		if int(current_scene.wave) > w0:
			break
	var next := await _wait(15, func(): return int(current_scene.wave) > w0 and int(_theirs().get("wave", -1)) == int(current_scene.wave))
	_ok(next, "next wave in both games (%d / %d)" % [int(current_scene.wave), int(_theirs().get("wave", -1))])
	# a slow test box can run the game well behind the wall clock, so wait for the match instead of a fixed time.
	# charging rats (2.2 m/s): their file can be ~0.15 s old and a puppet runs ~1 packet behind,
	# so the slack is what a rat covers in that time
	var got := [0, 0.0, 0.0]    # matched, worst, slack (a lambda can't assign outer locals)
	var same := await _wait(15, func():
		var age := absf(Time.get_unix_time_from_system() - float(_theirs().get("t", 0.0)))
		var cc: Array = _compare("rat", 0.45)
		got[0] = cc[0]
		got[1] = cc[1]
		got[2] = 0.25 + 2.2 * (age + 0.07)
		return cc[0] >= 2 and cc[1] < got[2])
	_ok(same, "new wave's rats match too (%d, worst %.2f m, slack %.2f m)" % [got[0], got[1], got[2]])
	_flag("pit_done")
	# ---- 4. the farm: knocked props land in the same place
	var farm := await _wait(120, func(): return _in("res://main.tscn") and net.world.active and _theirs().get("scene", "") == "res://main.tscn")
	_ok(farm, "both on the farm")
	await _sleep(2)
	_flag("farm_ready")
	await _wait(240, func(): return FileAccess.get_file_as_string("%s/host_knocked" % dir) != "")
	var hk := FileAccess.get_file_as_string("%s/host_knocked" % dir).strip_edges()
	print("host knocked: '%s' at %d ms" % [hk, Time.get_ticks_msec()])
	await _sleep(6)
	var d1 := _key_dist(hk)
	_ok(d1 < 0.15, "prop the host knocked landed in the same spot here (%s, %.3f m apart)" % [hk, d1])
	var mine := _free_prop(1)
	var mk := _key_of(mine)
	var p0 := mine.global_position
	_knock(mine)
	await _sleep(7)
	var d2 := _key_dist(mk)
	_ok(mine.global_position.distance_to(p0) > 0.1, "my knock moved it (%.2f m)" % mine.global_position.distance_to(p0))
	_ok(d2 < 0.15, "prop I knocked landed in the same spot for the host (%s, %.3f m apart)" % [mk, d2])
	var npc := _compare("npc", 1.0)
	_ok(npc[0] >= 1 and npc[1] < 0.6, "farm cats walk the same (%d, worst %.2f m)" % [npc[0], npc[1]])
	_flag("join_done")
	await _wait(30, func(): return _has_flag("host_done"))
	print("world sync test [join]: %s" % ("PASS" if bad == 0 else "%d FAILED" % bad))
	net.leave()
	quit(1 if bad else 0)
