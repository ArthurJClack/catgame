class_name CombatTest
extends ArenaTest
## paw combat checks (cat_combat.gd). `res://arena.tscn -- --combattest` (headless) prints each
## rule and COMBATTEST PASS/FAIL, `-- --combatshow` plays the moves for a video (--write-movie),
## `-- --pounceshow` the two paw pounce (free arc, soft lock onto a rat / a ledge, stuck landings).


func _ready() -> void:
	p = arena.player
	bot = p.bot
	if "--combattest" in OS.get_cmdline_user_args():
		_ctest.call_deferred()
	elif "--pounceshow" in OS.get_cmdline_user_args():
		_pshow.call_deferred()
	else:
		_cshow.call_deferred()


func _paws(l: bool, r: bool) -> void:
	bot.paw_l = l
	bot.paw_r = r


## waits for the cat to leave the floor and come back down, returns where it touched down
func _land_spot() -> Vector3:
	var t := 0.0
	var left := false
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not p.is_on_floor():
			left = true
		elif left:
			return p.global_position
	return p.global_position


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
	_paws(true, false)               # let go of one (no pounce)
	await _secs(0.2)
	print("F brute held %.2f s then wriggled free (break_t %.2f), cat still gripping %s" % [held_for, r.break_t, str(c.gripping())])
	ok = ok and absf(held_for - r.break_t) < 0.05 and r.held_by == null
	_paws(false, false)
	await _ticks(2)
	# G: grab it from behind: the slam lands double
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.42))
	r = _still_rat(0.0)              # back to the cat
	_face(r.global_position)
	await _secs(0.15)
	r.hp = 99.0
	r.max_hp = 99.0
	_paws(true, true)
	await _secs(0.27)
	var back := r.max_hp - r.hp
	_paws(true, false)               # let go of one: no pounce onto it
	await _secs(0.2)
	_paws(false, false)
	await _ticks(2)
	print("G grab from behind: slam %.1f dmg" % back)
	ok = ok and is_equal_approx(back, 3.0)
	# H: holding runs the bar down, then the grip slips
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.4))
	r = _still_rat(PI)
	r.hp = 99.0
	r.max_hp = 99.0
	r.break_t = 99.0
	_face(r.global_position)
	await _ticks(3)
	p.stamina.value = 20.0
	_paws(true, true)
	t = 0.0
	while t < 4.0 and (c.gripping() or t < 0.1):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		r.break_t = 99.0
	print("H 20 stamina, holding a rat: slips after %.2f s, gripping %s" % [t, str(c.gripping())])
	ok = ok and not c.gripping() and t < 2.8
	_paws(false, false)
	await _ticks(2)
	# I: nothing in reach: rear, drop into the pounce crouch, release both = free projectile pounce
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 2.0))
	_face(Vector3(0, 0.02, -1.0))
	bot.pitch = -0.15
	await _ticks(3)
	_paws(true, true)
	await _secs(0.9)
	var aimed := c.aiming()
	var pred: Vector3 = c.pounce.point
	var pkind: String = c.pounce.kind
	var n0 := c.pounces
	_paws(false, false)
	if OS.has_environment("ARENA_DBG"):
		for k in 6:
			await get_tree().physics_frame
			print("  I fly: pos %s v %s floor %s lock %s" % [p.global_position, p.velocity, p.is_on_floor(), p.leap_lock])
	var land := await _land_spot()
	await _secs(0.4)
	var drift := Vector2(p.global_position.x - land.x, p.global_position.z - land.z).length()
	var miss := Vector2(land.x - pred.x, land.z - pred.z).length()
	print("I free pounce: aiming %s, launched %d, %s arc predicted %.2f m out, landed %.2f m out, miss %.3f m, drift after landing %.3f m" % [str(aimed), c.pounces - n0, pkind, 2.0 - pred.z, 2.0 - land.z, miss, drift])
	ok = ok and aimed and c.pounces - n0 == 1 and pkind == "free" and miss < 0.04 and drift < 0.01 and 2.0 - land.z > 1.0
	# J: soft lock: rat a bit off the aim line, the pounce bends onto it and pins it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 1.8))
	r = _still_rat(PI)
	r.hp = 99.0
	r.max_hp = 99.0
	_face(Vector3(0.35, 0.02, 0.0))   # aiming ~0.35 m to the side of it
	bot.pitch = -0.1
	await _ticks(3)
	_paws(true, true)
	await _secs(0.9)
	pkind = c.pounce.kind
	pred = c.pounce.point
	_paws(false, false)
	land = await _land_spot()
	await _secs(0.3)
	var dmg := r.max_hp - r.hp
	var want := r.global_position.distance_to(Vector3(land.x, r.global_position.y, land.z))
	print("J soft lock on a rat: kind %s, landed %.2f m from it (aim point %.3f m off), pin damage %.1f, drift %.3f m" % [pkind, want, Vector2(land.x - pred.x, land.z - pred.z).length(), dmg, Vector2(p.global_position.x - land.x, p.global_position.z - land.z).length()])
	ok = ok and pkind == "prey" and dmg >= 2.5 and Vector2(land.x - pred.x, land.z - pred.z).length() < 0.06
	# K: ledge: the arc would smack the side of a block, it lands on top instead
	await _clear_rats()
	var box := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.45, 0.6)
	cs.shape = bs
	box.add_child(cs)
	arena.add_child(box)
	box.global_position = Vector3(0, 0.225, -0.2)
	_reset_cat(Vector3(0, 0.02, 1.6))
	_face(Vector3(0, 0.1, 0.1))
	bot.pitch = -0.1
	await _ticks(3)
	_paws(true, true)
	await _secs(0.9)
	pkind = c.pounce.kind
	pred = c.pounce.point
	_paws(false, false)
	land = await _land_spot()
	await _secs(0.3)
	print("K ledge: kind %s, top at %.2f m, landed y %.2f, miss %.3f m" % [pkind, pred.y, land.y, Vector2(land.x - pred.x, land.z - pred.z).length()])
	ok = ok and pkind == "ledge" and land.y > 0.4
	box.queue_free()
	await _ticks(2)
	# L: let go of just one = cancel, no pounce
	_reset_cat(Vector3(0, 0.02, 1.0))
	_face(Vector3(0, 0.02, -1.0))
	await _ticks(3)
	n0 = c.pounces
	_paws(true, true)
	await _secs(0.6)
	_paws(true, false)
	await _secs(0.3)
	_paws(false, false)
	await _secs(0.2)
	print("L let go of one while aiming: pounces %d, aiming %s, cat y %.2f" % [c.pounces - n0, str(c.aiming()), p.global_position.y])
	ok = ok and c.pounces == n0 and not c.aiming() and p.global_position.y < 0.05
	print("COMBATTEST ", "PASS" if ok else "FAIL")
	get_tree().quit()


# ---------------------------------------------------------------- show reel

var _dummy: SoulsRat = null
var _dummy_yaw := 0.0
var _dummy_pos := Vector3.ZERO


func _physics_process(_dt: float) -> void:
	# show reel: the rat is a training dummy, it never attacks (still flinches + struggles)
	if is_instance_valid(_dummy) and _dummy.held_by == null and _dummy.state in [SoulsRat.IDLE, SoulsRat.CHASE, SoulsRat.WINDUP, SoulsRat.LUNGE]:
		_dummy.state = SoulsRat.RECOVER
		_dummy.st_t = -50.0
		_dummy.yaw = _dummy_yaw
		_dummy.hp = 50.0
	if is_instance_valid(_dummy) and _dummy.held_by == null:
		# stays on its mark (swats would knock it out of shot)
		_dummy.global_position = _dummy.global_position.lerp(_dummy_pos, 0.2)
		_dummy.velocity = Vector3.ZERO


func _dummy_rat(yaw: float, pos: Vector3) -> SoulsRat:
	var r: SoulsRat = arena.spawn_rat(pos, 1.0)
	r.yaw = yaw
	r.rotation.y = yaw
	r.hp = 50.0
	r.max_hp = 50.0
	r.state = SoulsRat.RECOVER
	r.st_t = -50.0
	_dummy = r
	_dummy_yaw = yaw
	_dummy_pos = pos
	return r


func _tap(l: bool, r: bool, gap := 0.55) -> void:
	_paws(l, r)
	await _ticks(6)
	_paws(false, false)
	await _secs(gap)


func _cshow() -> void:
	_labels()
	arena.hud.visible = true
	cam = Camera3D.new()
	cam.fov = 46
	cam.near = 0.02
	arena.add_child(cam)
	cam.current = true
	p.set_third_person(true)
	p.set_style("block")
	await _ticks(10)
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	var r := _dummy_rat(PI, Vector3(0, 0.02, 0))
	_face(r.global_position)
	# side on, a little in front of the cat
	cam.global_position = Vector3(1.05, 0.38, 0.12)
	cam.look_at(Vector3(0, 0.13, 0.3))
	_say("left click", "left paw swat")
	await _secs(0.5)
	await _tap(true, false)
	await _tap(true, false)
	_say("right click", "right paw swat")
	await _tap(false, true)
	await _tap(false, true)
	_say("hold one", "that paw keeps raking")
	_paws(true, false)
	await _secs(1.3)
	_paws(false, false)
	await _secs(0.5)
	_say("hold both  (half speed)", "rear up on the hind legs, then pin it with both paws")
	Engine.time_scale = 0.5
	_paws(true, true)
	await _secs(0.9)
	Engine.time_scale = 1.0
	_say("both paws holding", "holding w: can't walk without a free paw")
	bot.move = Vector2(0, 1)
	await _secs(0.9)
	_say("let go of one", "free to walk again")
	_paws(true, false)
	await _secs(0.7)
	_paws(false, false)
	bot.move = Vector2.ZERO
	await _secs(0.3)
	# first person: grab one from behind
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.48))
	r = _dummy_rat(0.0, Vector3(0, 0.02, 0))
	_face(r.global_position)
	p.set_third_person(false)
	p.cam.current = true
	_say("first person", "rake, then grab it from behind (double damage)")
	await _secs(0.5)
	_paws(false, true)
	await _secs(0.9)
	_paws(false, false)
	await _secs(0.3)
	_paws(true, true)
	await _secs(1.8)
	_paws(false, false)
	await _secs(0.6)
	get_tree().quit()


func _block(pos: Vector3, size: Vector3) -> StaticBody3D:
	var box := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	box.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.3, 0.22)
	mi.material_override = mat
	box.add_child(mi)
	arena.add_child(box)
	box.global_position = pos
	return box


## hold both, aim for `wind` s, let go of both, follow the flight with the side camera
func _pounce(wind: float, cam_side := true) -> void:
	_paws(true, true)
	await _secs(wind)
	_paws(false, false)
	var t := 0.0
	while t < 1.3:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if cam_side:
			var mid := p.global_position + Vector3.UP * 0.15
			cam.global_position = cam.global_position.lerp(Vector3(2.3, 0.7, mid.z + 0.4), clampf(dt * 3.0, 0, 1))
			cam.look_at(mid)


func _pshow() -> void:
	_labels()
	arena.hud.visible = true
	cam = Camera3D.new()
	cam.fov = 50
	cam.near = 0.02
	arena.add_child(cam)
	cam.current = true
	p.set_third_person(true)
	p.set_style("block")
	await _ticks(10)
	await _clear_rats()
	# 1: free pounce, no target: the arc goes where you look, sticks the landing
	_reset_cat(Vector3(0, 0.02, 2.2))
	_face(Vector3(0, 0.02, -2.0))
	bot.pitch = 0.0
	cam.global_position = Vector3(2.3, 0.7, 2.0)
	cam.look_at(Vector3(0, 0.15, 1.6))
	_say("hold both", "rears up, then drops into the pounce crouch (the arc shows where it lands)")
	await _pounce(1.1)
	_say("let go of both", "free projectile: no steering, sticks the landing dead still")
	await _secs(0.6)
	# 2: soft lock: aim off to the side of a rat, it bends onto it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 2.2))
	var r := _dummy_rat(PI, Vector3(0.0, 0.02, 0.4))
	_face(Vector3(0.45, 0.02, 0.4))
	bot.pitch = -0.05
	cam.global_position = Vector3(2.3, 0.7, 1.8)
	cam.look_at(Vector3(0, 0.15, 1.3))
	_say("soft lock", "aimed off to the side: locks onto the rat and pins it")
	await _pounce(1.0)
	await _secs(0.5)
	# 3: ledge: the arc would smack the side of the crate, it lands on top instead
	await _clear_rats()
	_dummy = null
	var box := _block(Vector3(0, 0.25, 0.1), Vector3(1.0, 0.5, 0.7))
	_reset_cat(Vector3(0, 0.02, 2.2))
	_face(Vector3(0, 0.1, 0.4))
	bot.pitch = -0.08
	cam.global_position = Vector3(2.3, 0.8, 1.8)
	cam.look_at(Vector3(0, 0.25, 1.2))
	_say("ledges", "would hit the side of the crate: lands on top instead")
	await _pounce(1.0)
	await _secs(0.6)
	box.queue_free()
	# 4: first person
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 2.0))
	r = _dummy_rat(0.0, Vector3(0.15, 0.02, 0.3))
	_face(Vector3(0.0, 0.02, 0.3))
	bot.pitch = -0.08
	p.set_third_person(false)
	p.cam.current = true
	_say("first person", "pounce from behind (double damage)")
	await _secs(0.3)
	await _pounce(0.9, false)
	await _secs(0.8)
	get_tree().quit()
