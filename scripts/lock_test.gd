class_name LockTest
extends ArenaTest
## tab lock on checks (cat_lock_on.gd). `res://arena.tscn -- --locktest` (headless) prints each rule
## and LOCKTEST PASS/FAIL, `-- --lockshow` films it (third person + first person) for --write-movie.


func _ready() -> void:
	p = arena.player
	bot = p.bot
	if "--locktest" in OS.get_cmdline_user_args():
		_ltest.call_deferred()
	else:
		_lshow.call_deferred()


func _still(pos: Vector3, size := 1.0) -> SoulsRat:
	var r: SoulsRat = arena.spawn_rat(pos, size)
	r.state = SoulsRat.RECOVER
	r.st_t = -50.0
	return r


## look straight at a point the way a player would (no bot yaw: the lock has to own the heading)
func _look(pt: Vector3) -> void:
	bot.erase("yaw")
	bot.erase("pitch")
	var d := pt - (p.global_position + Vector3.UP * 0.25)
	p.yaw = atan2(-d.x, -d.z)
	p.rotation.y = p.yaw
	p.orb_yaw = p.yaw
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _tab() -> void:
	bot.lock_on = true
	await _ticks(2)
	bot.lock_on = false
	await _ticks(1)


## angle between where the camera looks and the target
func _cam_err() -> float:
	var c := p.cam.global_transform
	return (-c.basis.z).angle_to(p.lock_point() - c.origin)


func _face_err() -> float:
	return absf(wrapf(p.lock.yaw_to() - p.yaw, -PI, PI))


func _ltest() -> void:
	var ok := true
	var L := p.lock
	p.log_events = OS.has_environment("ARENA_DBG")
	await _ticks(30)
	await _clear_rats()
	# A: picks the rat nearest the crosshair, not the nearer one off to the side; camera swings on
	_reset_cat(Vector3(0, 0.02, 3.0))
	var ra := _still(Vector3(0.3, 0.02, 0.0))
	var rb := _still(Vector3(-1.6, 0.02, 1.9))
	_look(Vector3(0.0, 0.1, 0.0))
	await _ticks(3)
	await _tab()
	await _secs(0.5)
	var a_err := _cam_err()
	print("A tab: locked %s (want the one under the crosshair), camera off target %.2f rad, lock_target api %s" % [str(L.target == ra), a_err, str(p.lock_target == ra)])
	ok = ok and L.target == ra and a_err < 0.12 and p.lock_target == ra
	# B: tab again = unlock, lock_target goes null
	await _tab()
	print("B tab again: unlocked %s" % str(not L.active() and p.lock_target == null))
	ok = ok and not L.active() and p.lock_target == null
	# C: nothing in view = no lock (rats behind the cat)
	_look(Vector3(0, 0.1, 8.0))
	await _ticks(3)
	await _tab()
	print("C rats behind you: no lock %s" % str(not L.active()))
	ok = ok and not L.active()
	# D: strafe. locked + holding d: circles the rat, body stays on it, no side hops
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 1.2))
	ra = _still(Vector3(0, 0.02, 0))
	_look(ra.lock_point())
	await _ticks(3)
	await _tab()
	var a0 := atan2(p.global_position.x, p.global_position.z)
	var d0 := Vector2(p.global_position.x, p.global_position.z).length()
	var hops := 0
	bot.move = Vector2(1, 0)
	var worst_face := 0.0
	for i in 90:
		await get_tree().physics_frame
		if p.last_event == "side hop" or p.velocity.y > 0.8:
			hops += 1
		if i > 20:
			worst_face = maxf(worst_face, _face_err())
	bot.move = Vector2.ZERO
	var a1 := atan2(p.global_position.x, p.global_position.z)
	var d1 := Vector2(p.global_position.x, p.global_position.z).length()
	var swept := absf(wrapf(a1 - a0, -PI, PI))
	print("D hold d 1.5 s: swept %.2f rad round the rat, radius %.2f -> %.2f m, worst facing error %.2f rad, hops %d, camera err %.2f" % [swept, d0, d1, worst_face, hops, _cam_err()])
	ok = ok and swept > 1.0 and absf(d1 - d0) < 0.12 and worst_face < 0.35 and hops == 0 and _cam_err() < 0.2
	# E: dodge relative to the target. s = backstep away, a = side leap, both keep facing it
	await _secs(0.3)
	var dist0 := (p.global_position - ra.global_position).length()
	bot.move = Vector2(0, -1)
	bot.dash = true
	await _ticks(2)
	bot.dash = false
	bot.move = Vector2.ZERO
	await _secs(0.8)
	var k1: String = p.dash.last_kind
	var dist1 := (p.global_position - ra.global_position).length()
	var f1 := _face_err()
	bot.move = Vector2(-1, 0)
	bot.dash = true
	await _ticks(2)
	bot.dash = false
	bot.move = Vector2.ZERO
	await _secs(0.8)
	var k2: String = p.dash.last_kind
	var f2 := _face_err()
	print("E dodge s -> %s (%.2f -> %.2f m from the rat, facing err %.2f), dodge a -> %s (facing err %.2f)" % [k1, dist0, dist1, f1, k2, f2])
	ok = ok and k1 == "backstep" and dist1 > dist0 + 0.4 and f1 < 0.4 and k2 == "side leap" and f2 < 0.4
	# F: mouse flick right hops to the rat on the right, left goes back
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 3.0))
	var mid := _still(Vector3(0, 0.02, 0))
	var right := _still(Vector3(1.8, 0.02, 0.3))    # +x = right when looking down -z
	var left := _still(Vector3(-1.8, 0.02, 0.3))
	_look(mid.lock_point())
	await _ticks(3)
	await _tab()
	var f_mid := L.target == mid
	L.mouse(30.0)                                   # slow drag: no switch
	await _secs(0.3)
	var f_drag := L.target == mid
	L.mouse(140.0)
	await _ticks(2)
	var f_r := L.target == right
	await _secs(0.5)
	L.mouse(-140.0)
	await _ticks(2)
	var f_back := L.target == mid
	await _secs(0.4)
	L.mouse(-140.0)
	await _ticks(2)
	var f_l := L.target == left
	print("F lock mid %s, slow drag stays %s, flick right -> right rat %s, flick left -> mid %s -> left %s" % [str(f_mid), str(f_drag), str(f_r), str(f_back), str(f_l)])
	ok = ok and f_mid and f_drag and f_r and f_back and f_l
	# G: killing the target hands the lock to the next rat close by; killing the last one unlocks
	left._die()
	await _ticks(3)
	var g1 := L.active() and L.target != left
	(L.target as SoulsRat)._die()
	await _ticks(3)
	var g2 := L.active()
	(L.target as SoulsRat)._die()
	await _ticks(3)
	print("G kill target -> next rat %s, again -> last rat %s, kill last -> unlocked %s" % [str(g1), str(g2), str(not L.active())])
	ok = ok and g1 and g2 and not L.active()
	# H: every camera view holds the target in the middle of the screen
	await _clear_rats()
	var errs := []
	for vm in [0, 1, 2]:
		_reset_cat(Vector3(0, 0.02, 2.0))
		p.set_view(vm)
		ra = _still(Vector3(0.4, 0.02, 0))
		_look(ra.lock_point())
		await _ticks(3)
		await _tab()
		bot.move = Vector2(1, 0)
		await _secs(1.0)
		bot.move = Vector2.ZERO
		await _secs(0.3)
		errs.append(_cam_err())
		await _tab()
		await _clear_rats()
	p.set_view(0)
	print("H camera on target after circling: first person %.2f, third %.2f, orbit %.2f rad" % errs)
	ok = ok and errs[0] < 0.15 and errs[1] < 0.3 and errs[2] < 0.35
	# I: walking out of range breaks it
	_reset_cat(Vector3(0, 0.02, 2.0))
	ra = _still(Vector3(0, 0.02, 0))
	_look(ra.lock_point())
	await _ticks(3)
	await _tab()
	p.global_position = Vector3(0, 0.02, CatLockOn.KEEP + 1.0)
	p._phys_prev = p.global_position
	await _ticks(3)
	print("I out of range: unlocked %s" % str(not L.active()))
	ok = ok and not L.active()
	print("LOCKTEST PASS" if ok else "LOCKTEST FAIL")
	get_tree().quit()


# ---------------------------------------------------------------- video

func _lshow() -> void:
	_labels()
	arena.hud.visible = false
	p.set_style("block")
	await _ticks(10)
	await _clear_rats()
	var L := p.lock
	# 1: third person. lock, circle, dodge, flick through the pack
	p.set_view(1)
	_reset_cat(Vector3(0, 0.02, 1.7))
	var r1 := _still(Vector3(0, 0.02, 0))
	var r2 := _still(Vector3(1.3, 0.02, 0.2), 1.6)
	var r3 := _still(Vector3(-1.3, 0.02, 0.3))
	_look(Vector3(0, 0.3, 4.0) * -1.0)
	_say("tab = lock on", "picks the rat nearest your crosshair, dot marks it")
	await _secs(1.0)
	await _tab()
	await _secs(1.0)
	_say("wasd circles it", "the body stays square to the rat, the camera holds it")
	bot.move = Vector2(1, 0)
	await _secs(2.2)
	bot.move = Vector2(0, 0)
	await _secs(0.3)
	bot.move = Vector2(-1, 0)
	await _secs(1.4)
	bot.move = Vector2.ZERO
	_say("dodges go relative to it", "s = backstep away, a / d = side leap round it")
	await _secs(0.4)
	for mv in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		bot.move = mv
		bot.dash = true
		await _ticks(2)
		bot.dash = false
		bot.move = Vector2.ZERO
		await _secs(0.9)
	_say("flick the mouse = next target", "flick right, flick right, flick left")
	await _secs(0.6)
	for f in [140.0, 140.0, -140.0, -140.0]:
		L.mouse(f)
		await _secs(1.1)
	# 2: first person
	_say("works in first person too", "")
	p.set_view(0)
	await _secs(0.4)
	bot.move = Vector2(-1, 0)
	await _secs(2.0)
	bot.move = Vector2.ZERO
	bot.move = Vector2(0, -1)
	bot.dash = true
	await _ticks(2)
	bot.dash = false
	bot.move = Vector2.ZERO
	await _secs(0.9)
	L.mouse(140.0)
	await _secs(1.2)
	_say("tab again = unlock", "")
	await _tab()
	await _secs(1.2)
	get_tree().quit()
