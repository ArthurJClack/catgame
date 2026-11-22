class_name SparTest
extends Node
## `res://spar.tscn -- --spartest`: play fight rules check. the player is a bot too (a
## CatSparBrain in "script" style) and every case pins what the practice cat does, then checks
## what came back. prints SPARTEST PASS / FAIL. `--sparshow` instead films two bots sparring.

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
	main.dummy.spar.log_results = false
	if show:
		_film.call_deferred()
	else:
		_run.call_deferred()


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _reset(dstyle: String, script: Array) -> void:
	var p: CatPlayer = main.player
	var d: CatPlayer = main.dummy
	p.global_position = main.spawn
	p.velocity = Vector3.ZERO
	p.yaw = 0.0
	d.global_position = Vector3(0, 0.02, main.spawn.z - 0.82)
	d.velocity = Vector3.ZERO
	d.yaw = PI
	for s in [p.spar, d.spar]:
		s.my_pts = 0.0
		s.their_pts = 0.0
		s._cancel_move()
		s.stun = 0.0
		s.react = ""
		s.wrestle = 0.0
		s._wr_wait = 0.0
		s.pinned = 0.0
		s._pending_throw = {}
		s.results.clear()
		s.last_result = ""
	d.spar.brain.style = dstyle
	d.spar.brain._queue.clear()
	d.spar.brain._press.clear()
	d.spar.brain._hold.clear()
	d.spar.brain._guard_t = 0.0
	d.spar.brain._duck_t = 0.0
	p.spar.brain.plan = script.duplicate(true)
	p.spar.brain._t = 0.0
	p.spar.brain._queue.clear()


func _check(name: String, ok: bool, info := "") -> void:
	print("  %s %s  %s" % ["ok  " if ok else "FAIL", name, info])
	if not ok:
		_fails += 1


func _res() -> Array:
	return main.player.spar.results.map(func(r): return r[1])


func _run() -> void:
	var p: CatPlayer = main.player
	var d: CatPlayer = main.dummy
	print("SPARTEST start")
	# the match only starts once both cats are on each other: wait for the first "play!"
	var t := 0.0
	while p.spar.round_state != CatSpar.R_FIGHT and t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("match starts (mutual lock, practice cat referees)", p.spar.round_state == CatSpar.R_FIGHT and d.spar.is_ref(), "state %d" % p.spar.round_state)

	_reset("idle", [[0.1, "swat"]])
	await _wait(0.7)
	_check("A bop tags a standing cat", _res() == ["hit"] and d.spar.react != "" or _res() == ["hit"], str(_res()))
	_check("A   points: mine > 0, theirs in step", p.spar.my_pts > 0.0 and is_equal_approx(p.spar.my_pts, d.spar.their_pts), "%.1f / %.1f" % [p.spar.my_pts, d.spar.their_pts])

	_reset("guard", [[0.3, "swat"]])
	await _wait(0.9)
	_check("B guard blocks a high", _res() == ["blocked"], str(_res()))

	_reset("duck", [[0.3, "swat"]])
	await _wait(0.9)
	_check("C duck makes a high whiff", _res() == ["whiff"], str(_res()))

	_reset("guard", [[0.3, "low"]])
	await _wait(0.9)
	_check("D low gets under a standing guard", _res() == ["hit"], str(_res()))

	_reset("duck", [[0.3, "low"]])
	await _wait(0.9)
	_check("E duck blocks a low", _res() == ["blocked"], str(_res()))

	_reset("duck", [[0.3, "hold"]])
	await _wait(1.4)
	_check("F overhead tags a ducking cat", not p.spar.results.is_empty() and p.spar.results[-1] == ["over", "hit"], str(p.spar.results))

	_reset("guard", [[0.3, "hold"]])
	await _wait(1.4)
	_check("G guard blocks the overhead", not p.spar.results.is_empty() and p.spar.results[-1] == ["over", "blocked"], str(p.spar.results))

	_reset("idle", [[0.1, "swat"], [0.32, "swat"], [0.62, "swat"]])
	await _wait(1.6)
	var mv: Array = p.spar.results.map(func(r): return r[0])
	_check("H bop bop bap string", _res() == ["hit", "hit", "hit"] and mv == ["jab", "jab2", "bap"], str(p.spar.results))

	_reset("idle", [[0.1, "swat"], [0.32, "swat"], [0.62, "low"]])
	await _wait(1.6)
	mv = p.spar.results.map(func(r): return r[0])
	_check("I high high low branch", mv == ["jab", "jab2", "low"], str(p.spar.results))

	_reset("guard", [[0.3, "grab"]])
	await _wait(0.8)
	_check("J throw beats guard -> wrestle", _res() == ["thrown"] and p.spar.wrestle > 0.0 and d.spar.wrestle > 0.0, str(_res()))
	await _wait(3.2)
	_check("J   idle cat gets pinned", p.spar.stats.pins >= 1 and d.spar.pinned >= 0.0, "pins %d  pts %.0f/%.0f" % [p.spar.stats.pins, p.spar.my_pts, d.spar.their_pts])

	_reset("duck", [[0.3, "grab"]])
	await _wait(0.9)
	_check("K duck beats a throw", _res() == ["whiff"], str(_res()))

	_reset("counter", [[0.3, "swat"]])
	await _wait(1.0)
	_check("L counter: they stumble the bopper", _res() == ["countered"] and d.spar.stats.countered == 1, str(_res()))

	_reset("script", [[0.32, "swat"]])
	d.spar.brain.plan = [[0.25, "side_l"]]
	d.spar.brain._t = 0.0
	await _wait(1.1)
	var miss: bool = _res() == ["evaded"] or (_res().is_empty() and p.spar.stats.whiffs > 0)
	_check("M sidestep slips a straight bop", miss, str(_res()))

	_reset("script", [[0.3, "lunge"]])
	d.spar.brain.plan = [[0.3, "side_l"]]
	d.spar.brain._t = 0.0
	await _wait(1.2)
	_check("N lunge tracks the sidestep", _res() == ["hit"], str(_res()))

	_reset("script", [[0.2, "swat"]])
	d.spar.brain.plan = [[0.26, "swat"]]
	d.spar.brain._t = 0.0
	await _wait(1.0)
	_check("O tagged mid wind up = counter hit", _res().has("ch"), str(_res()))

	_reset("script", [[0.3, "grab"]])
	d.spar.brain.plan = [[0.36, "grab"]]
	d.spar.brain._t = 0.0
	await _wait(1.0)
	_check("P grab as they grab = throw break", _res() == ["tech"] or _res() == ["tech", "tech"], str(_res()))

	# rounds: the referee (practice cat) calls it when the meter's full
	_reset("idle", [[0.2, "swat"]])
	p.spar.my_pts = 95.0
	d.spar.their_pts = 95.0
	await _wait(0.8)
	_check("Q full meter = round to me", p.spar.my_wins == 1 and p.spar.round_state == CatSpar.R_KO, "wins %d state %d" % [p.spar.my_wins, p.spar.round_state])
	await _wait(CatSpar.KO_T + 0.4)
	_check("Q   round 2 starts", p.spar.round_n == 2 and p.spar.round_state in [CatSpar.R_INTRO, CatSpar.R_FIGHT] and p.spar.my_pts == 0.0, "round %d state %d" % [p.spar.round_n, p.spar.round_state])

	# online: strikes go out on the rig's life log, results come back through a RemoteCat
	var peer := NetPeer.new()
	peer.id = 7
	peer.name = "friend"
	var rc := RemoteCat.new()
	rc.peer = peer
	main.add_child(rc)
	await get_tree().process_frame
	p.rig.net_record = true
	p.rig.life_log.clear()
	p.spar._send(rc, ["atk", 42, "jab"])
	var sent: Array = p.rig.life_log.filter(func(e): return str(e[0]) == "S")
	p.rig.net_record = false
	_check("R strike rides the life log to the remote cat", sent.size() == 1 and int(sent[0][1]) == 7 and str(sent[0][2]) == "atk", str(sent))
	var st := CatNetState.from_rig(d.rig, 1.0, null, 1.0)
	st.events = [[1, 1.0, ["S", p.spar.my_sid(), "res", 42, "jab", "hit"]]]
	var back := CatNetState.decode(st.encode())
	var hits0: int = p.spar.stats.hits
	if back and not back.events.is_empty():
		CatSpar.net_in(rc, back.events[0][2])
	_check("R   their answer comes back over the wire", back != null and p.spar.stats.hits == hits0 + 1, "hits %d -> %d" % [hits0, p.spar.stats.hits])
	var lockev := CatNetState.decode(CatNetState.from_rig(d.rig, 2.0, null, 2.0).encode())
	_check("R   plain snapshots still decode", lockev != null)
	rc.queue_free()

	print("SPARTEST %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


# ------------------------------------------------------------------ film

func _film() -> void:
	var p: CatPlayer = main.player
	p.set_third_person(true)
	main.dummy.spar.brain.style = "auto"
	main.dummy.spar.brain.skill = 0.5
	p.spar.brain.skill = 0.5
	var fp := "--sparfp" in OS.get_cmdline_user_args()
	_cam = Camera3D.new()
	_cam.fov = 50
	main.add_child(_cam)
	if fp:
		p.set_third_person(false)   # through the player cat's own eyes (the game's view)
	else:
		_cam.current = true
	var t := 0.0
	var dur := 40.0
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
		# the hud belongs to the player's camera; keep it on screen anyway
	print("SPARSHOW done")
	get_tree().quit()
