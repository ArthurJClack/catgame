class_name SparTest
extends Node
## `res://spar.tscn -- --spartest`: play fight check. the player is a bot too (a CatSparBrain in
## "script" style, locked on to the practice cat) and every case pins what the practice cat does.
## prints SPARTEST PASS / FAIL. `--sparshow [--sparfp] [--sparsec N]` films two bots playing.

class FakeParry:
	extends RefCounted
	var calls := 0
	func try_deflect(_a, _f, _p := false) -> bool:
		calls += 1
		return true

var main: Node
var show := false
var _fails := 0
var _cam: Camera3D


func _ready() -> void:
	process_priority = 20
	var p: CatPlayer = main.player
	p.bot = {"move": Vector2.ZERO, "stamina": false}
	p.spar.brain = CatSparBrain.new()
	p.spar.brain.spar = p.spar
	p.spar.brain.style = "auto" if show else "script"
	p.spar.brain.rng.seed = 11
	p.spar.forced = main.dummy
	p.spar.log_results = true
	if show:
		main.dummy.spar.brain.style = "auto"
		_film.call_deferred()
	else:
		_run.call_deferred()


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _reset(dstyle: String, plan: Array, dplan := []) -> void:
	var p: CatPlayer = main.player
	var d: CatPlayer = main.dummy
	await _wait(0.6)    # let the last case's moves run out
	p.global_position = main.spawn
	p.velocity = Vector3.ZERO
	p.yaw = 0.0
	d.global_position = Vector3(0, 0.02, main.spawn.z - 0.8)
	d.velocity = Vector3.ZERO
	d.yaw = PI
	for s in [p.spar, d.spar]:
		s.stun = 0.0
		s.react = ""
		s.results.clear()
		for k in s.stats:
			s.stats[k] = 0
		s.brain._queue.clear()
		s.brain._press.clear()
		s.brain._hold.clear()
		s.brain._t = 0.0
		s.brain._read_t = -1.0
	d.spar.brain.style = dstyle
	d.spar.brain.plan = dplan.duplicate(true)
	p.spar.brain.plan = plan.duplicate(true)
	if not p.lock.active():
		p.lock._set_target(d)
	await _wait(0.15)


func _check(name: String, ok: bool, info := "") -> void:
	print("  %s %s  %s" % ["ok  " if ok else "FAIL", name, info])
	if not ok:
		_fails += 1


func _res(s: CatSpar) -> Array:
	return s.results.map(func(r): return r[1])


func _kinds(s: CatSpar) -> Array:
	return s.results.map(func(r): return r[0])


func _run() -> void:
	var p: CatPlayer = main.player
	var d: CatPlayer = main.dummy
	print("SPARTEST start")
	await _wait(0.5)
	p.lock._set_target(d)
	_check("tab on a cat = play mode", p.lock.active() and p.spar.play_mode(), "")

	await _reset("idle", [[0.1, "swat"]])
	var hp0: float = d.health.value if "value" in d.health else 0.0
	var shown := false
	for i in 60:
		await get_tree().physics_frame
		shown = shown or d.spar.react == "swat"
	_check("A a normal swat bops the cat", _res(p.spar) == ["hit"] and shown, str(p.spar.results))
	_check("A   no damage", ("value" not in d.health) or d.health.value == hp0, "")

	await _reset("dodge", [[0.15, "swat"]])
	await _wait(0.8)
	_check("B the normal dodge slips it", d.spar.stats.got_tagged == 0 and d.dash.count > 0, "%s dodges %d" % [str(p.spar.results), d.dash.count])

	await _reset("idle", [[0.1, "rake"]])
	await _wait(1.3)
	_check("C held paw rakes = soft bops too", _kinds(p.spar).count("rake") >= 2 and not _res(p.spar).has("dodged"), str(p.spar.results))

	await _reset("idle", [[0.1, "pounce"]])
	d.global_position = Vector3(0, 0.02, main.spawn.z - 1.4)
	var bowled := false
	for i in 400:
		await get_tree().physics_frame
		bowled = bowled or d.spar.react == "pounce"
	_check("D pounce onto them = bowled over", p.spar.results.has(["pounce", "hit"]) and bowled, str(p.spar.results))

	await _reset("idle", [[0.1, "grab"]])
	await _wait(0.8)
	_check("E grab = hug tackle", p.spar.results.has(["grab", "hit"]), str(p.spar.results))

	await _reset("script", [], [[0.1, "swat"]])
	await _wait(0.8)
	_check("F they bop you back (same events)", p.spar.stats.got_tagged == 1 and d.spar.results.has(["swat", "hit"]), str(d.spar.results))

	var fp := FakeParry.new()
	p.spar.parry_override = fp
	await _reset("script", [], [[0.1, "swat"]])
	var stumbled := false
	for i in 120:
		await get_tree().physics_frame
		stumbled = stumbled or d.spar.react == "stumble"
	p.spar.parry_override = null
	_check("G parry turns it back: they stumble", fp.calls == 1 and d.spar.results.has(["swat", "deflected"]) and stumbled, str(d.spar.results))

	# not locked on: claws again, no play bops
	p.spar.forced = null
	p.lock.release()
	await _reset("idle", [[0.1, "swat"]])
	p.lock.release()
	await _wait(0.6)
	_check("H unlocked = not play mode, no tag", not p.spar.play_mode() and p.spar.results.is_empty(), str(p.spar.results))
	p.spar.forced = d

	# online: tags go out on the rig's life log, answers come back through a RemoteCat
	var peer := NetPeer.new()
	peer.id = 7
	peer.name = "friend"
	var rc := RemoteCat.new()
	rc.peer = peer
	main.add_child(rc)
	await get_tree().process_frame
	_check("R remote cats are play fight targets", rc.is_in_group("spar_cat"))
	p.rig.net_record = true
	p.rig.life_log.clear()
	p.spar._send(rc, ["tag", 42, "swat"])
	var sent: Array = p.rig.life_log.filter(func(e): return str(e[0]) == "S")
	p.rig.net_record = false
	_check("R tag rides the life log to the remote cat", sent.size() == 1 and int(sent[0][1]) == 7 and str(sent[0][2]) == "tag", str(sent))
	var st := CatNetState.from_rig(d.rig, 1.0, null, 1.0)
	st.events = [[1, 1.0, ["S", p.spar.my_sid(), "tag", 5, "swat"]]]
	var back := CatNetState.decode(st.encode())
	var g0: int = p.spar.stats.got_tagged
	if back and not back.events.is_empty():
		CatSpar.net_in(rc, back.events[0][2])
	_check("R   a remote cat's bop lands on me over the wire", back != null and p.spar.stats.got_tagged == g0 + 1, "%d -> %d" % [g0, p.spar.stats.got_tagged])
	rc.queue_free()

	print("SPARTEST %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


# ------------------------------------------------------------------ film

func _film() -> void:
	var p: CatPlayer = main.player
	var fp := "--sparfp" in OS.get_cmdline_user_args()
	p.lock._set_target.call_deferred(main.dummy)
	p.set_third_person(not fp)
	_cam = Camera3D.new()
	_cam.fov = 50
	main.add_child(_cam)
	if not fp:
		_cam.current = true
	var t := 0.0
	var dur := 30.0
	var args := OS.get_cmdline_user_args()
	var di := args.find("--sparsec")
	if di >= 0 and di + 1 < args.size():
		dur = float(args[di + 1])
	while t < dur:
		await get_tree().process_frame
		t += get_process_delta_time()
		var mid: Vector3 = (p.global_position + main.dummy.global_position) * 0.5
		var a := 0.9 + t * 0.12
		var want := mid + Vector3(sin(a) * 1.35, 0.55, cos(a) * 1.35)
		_cam.global_position = _cam.global_position.lerp(want, 0.08) if t > 0.1 else want
		_cam.look_at(mid + Vector3.UP * 0.12)
	print("SPARSHOW done")
	get_tree().quit()
