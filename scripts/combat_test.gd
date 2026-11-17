class_name CombatTest
extends ArenaTest
## paw combat checks (cat_combat.gd). `res://arena.tscn -- --combattest` (headless) prints each
## rule and COMBATTEST PASS/FAIL, `-- --combatshow` plays the moves for a video (--write-movie).


func _ready() -> void:
	p = arena.player
	bot = p.bot
	if "--combattest" in OS.get_cmdline_user_args():
		_ctest.call_deferred()
	else:
		_cshow.call_deferred()


func _paws(l: bool, r: bool) -> void:
	bot.paw_l = l
	bot.paw_r = r


func _still_rat(yaw: float, size := 1.0) -> SoulsRat:
	var r := _rat(yaw, size)
	r.state = SoulsRat.RECOVER       # stands still for the test
	r.st_t = -50.0
	return r


func _ctest() -> void:
	var ok := true
	var c := p.combat
	p.log_events = OS.has_environment("ARENA_DBG")
	await _ticks(30)
	# A: left click = left paw, right click = right paw
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	_face(Vector3(0, 0.02, -1))
	_paws(true, false)
	await _ticks(3)
	_paws(false, false)
	await _secs(0.05)
	var li: int = p.rig.get("_swat_i")
	await _secs(0.4)
	_paws(false, true)
	await _ticks(3)
	_paws(false, false)
	await _secs(0.05)
	var ri: int = p.rig.get("_swat_i")
	print("A tap left -> paw %d, tap right -> paw %d  (swats %d)" % [li, ri, c.swats])
	ok = ok and li == 0 and ri == 1 and c.swats == 2
	await _secs(0.4)
	# B: hold one paw on a rat = rakes. half damage + half poise each
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.36))
	var r := _still_rat(PI)
	_face(r.global_position)
	await _ticks(3)
	var rk0 := c.rakes
	var st0 := p.stamina.value
	_paws(false, true)
	await _secs(1.0)
	_paws(false, false)
	await _secs(0.2)
	var n := c.rakes - rk0
	print("B hold right on a rat 1 s: 1 swat + %d rakes, rat took %.1f dmg, stamina -%.0f, rat hp %.1f" % [n, r.max_hp - r.hp, st0 - p.stamina.value, r.hp])
	ok = ok and n >= 3 and n <= 4 and is_equal_approx(r.max_hp - r.hp, 1.0 + 0.5 * n) and p.rig.get("_swat_i") == 1
	# C: hold one paw with nothing in front = the old claw hook
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	_face(Vector3(0, 0.02, -1))
	_paws(true, false)
	await _secs(0.4)
	var hooked := p.clawing and p.paws.claw_i == 0
	_paws(false, false)
	await _ticks(2)
	print("C hold left at nothing: claw hold with the left paw %s, released %s" % [str(hooked), str(not p.clawing)])
	ok = ok and hooked and not p.clawing
	# D: both = rear up, slam down, hold. no walking while both paws hold it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.4))
	r = _still_rat(PI)               # facing the cat
	_face(r.global_position)
	await _ticks(3)
	var sw0 := c.swats
	st0 = p.stamina.value
	_paws(true, false)
	await _ticks(2)                  # second button a few ms later: still a chord
	_paws(true, true)
	await _secs(0.12)
	var rear_mid: float = c.rear_w
	var eye_mid: float = p.eye_local.y
	await _secs(0.2)
	var held := r.held_by == p
	var slam := r.max_hp - r.hp
	var pos0 := p.global_position
	bot.move = Vector2(0, 1)
	bot.jump = true
	await _secs(0.5)
	var moved := p.global_position.distance_to(pos0)
	var grip_w: float = p.rig.get("grip")
	print("D both paws: swats %d, rear %.2f eye %.2f m, slam %.1f dmg, held %s, moved %.3f m trying to walk + hop, rig grip %.2f, ticks %d, stamina -%.0f" % [c.swats - sw0, rear_mid, eye_mid, slam, str(held), moved, grip_w, c.grip_ticks, st0 - p.stamina.value])
	ok = ok and c.swats == sw0 and rear_mid > 0.5 and held and is_equal_approx(slam, 1.5) and moved < 0.05 and grip_w > 0.9 and c.grip_ticks >= 1
	# E: let go of one paw -> the rat's free and so are you
	bot.jump = false
	_paws(true, false)
	await _ticks(2)
	pos0 = p.global_position
	await _secs(0.4)
	moved = p.global_position.distance_to(pos0)
	print("E released right: rat free %s, gripping %s, cat walks %.2f m in 0.4 s, no stray swat %s" % [str(r.held_by == null), str(c.gripping()), moved, str(c.swats == sw0)])
	ok = ok and r.held_by == null and not c.gripping() and moved > 0.3 and c.swats == sw0
	bot.move = Vector2.ZERO
	_paws(false, false)
	await _ticks(2)
	# F: hold on and it wriggles out after break_t (the brute sooner)
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	r = _still_rat(PI, 1.6)
	r.hp = 99.0
	r.max_hp = 99.0
	_face(r.global_position)
	await _ticks(3)
	if OS.has_environment("ARENA_DBG"):
		print("  F pre: y %.3f floor %s climb %s clamber %s mantle %s scratch %s charge %s dash %s" % [p.global_position.y, p.is_on_floor(), p.climbing, p.clambering, p.mantling, p.scratching, p.charging, p.dash.busy()])
	_paws(true, true)
	var t := 0.0
	var held_for := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if r.held_by == p:
			held_for += dt
		elif held_for > 0.0:
			break
	print("F brute held %.2f s then wriggled free (break_t %.2f), cat still gripping %s" % [held_for, r.break_t, str(c.gripping())])
	ok = ok and absf(held_for - r.break_t) < 0.05 and r.held_by == null
	_paws(false, false)
	await _ticks(2)
	# G: grab it from behind: the slam lands double
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.42))
	r = _still_rat(0.0)              # back to the cat
	_face(r.global_position)
	await _ticks(3)
	_paws(true, true)
	await _secs(0.3)
	var back := r.max_hp - r.hp
	_paws(false, false)
	await _ticks(2)
	print("G grab from behind: slam %.1f dmg" % back)
	ok = ok and is_equal_approx(back, 3.0)
	# H: holding runs the bar down, then the grip slips
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	_face(Vector3(0, 0.02, -1))
	p.stamina.value = 20.0
	_paws(true, true)
	t = 0.0
	while t < 4.0 and (c.gripping() or t < 0.1):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("H 20 stamina, gripping air: slips after %.2f s, gripping %s" % [t, str(c.gripping())])
	ok = ok and not c.gripping() and t < 2.5
	_paws(false, false)
	print("COMBATTEST ", "PASS" if ok else "FAIL")
	get_tree().quit()


# ---------------------------------------------------------------- show reel

func _cshow() -> void:
	_labels()
	await _ticks(20)
	cam = Camera3D.new()
	cam.fov = 62
	arena.add_child(cam)
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	var r := _still_rat(PI)
	_face(r.global_position)
	r.hp = 50.0
	r.max_hp = 50.0
	var side := Vector3(0.75, 0.32, 0.55)
	cam.global_position = side
	cam.look_at(Vector3(0, 0.12, 0.25))
	cam.current = true
	_say("left click", "left paw swat")
	await _secs(0.6)
	for k in 2:
		_paws(true, false)
		await _ticks(4)
		_paws(false, false)
		await _secs(0.55)
	_say("right click", "right paw swat")
	for k in 2:
		_paws(false, true)
		await _ticks(4)
		_paws(false, false)
		await _secs(0.55)
	_say("hold", "raking with one paw")
	_paws(true, false)
	await _secs(1.4)
	_paws(false, false)
	await _secs(0.4)
	_paws(false, true)
	await _secs(1.4)
	_paws(false, false)
	await _secs(0.6)
	r.hp = 50.0
	_say("hold both", "rear up on the hind legs, then pin it with both paws")
	_paws(true, true)
	bot.move = Vector2(0, 1)
	await _secs(1.5)
	_say("both paws busy", "can't walk until one lets go")
	await _secs(0.9)
	_say("let go of one", "walk again")
	_paws(true, false)
	await _secs(0.25)
	_paws(false, false)
	await _secs(0.8)
	bot.move = Vector2.ZERO
	# first person view of the grip
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	r = _still_rat(0.0)
	r.hp = 50.0
	r.max_hp = 50.0
	_face(r.global_position)
	bot.pitch = -0.55
	p.cam.current = true
	_say("first person", "grab from behind = double damage")
	await _secs(0.8)
	_paws(true, false)
	await _ticks(4)
	_paws(false, false)
	await _secs(0.6)
	_paws(true, true)
	await _secs(1.6)
	_paws(false, false)
	await _secs(0.8)
	get_tree().quit()
