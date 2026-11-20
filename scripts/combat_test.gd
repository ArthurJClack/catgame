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
	elif "--landshow" in OS.get_cmdline_user_args():
		_landshow.call_deferred()
	elif "--commitshow" in OS.get_cmdline_user_args():
		_commitshow.call_deferred()
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


## how far a point is from a polyline
func _dist_to_path(q: Vector3, path: PackedVector3Array) -> float:
	var best := INF
	for k in range(1, path.size()):
		var a := path[k - 1]
		var ab := path[k] - a
		var u := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * u))
	return best


## worst distance (flat) from each planted paw to the circle it was promised
func _paws_off(spots: Array) -> float:
	if spots.size() != 4:
		return 99.0
	var worst := 0.0
	for i in 4:
		var g: Vector3 = p.rig.gait.pos[i]
		var s: Vector3 = spots[i]
		worst = maxf(worst, Vector2(g.x - s.x, g.z - s.z).length())
	return worst


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
	# D: grab button = quick reach (no rearing up), slam down, hold. no walking while both paws hold it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.4))
	r = _still_rat(PI)               # facing the cat
	_face(r.global_position)
	await _ticks(3)
	var sw0 := c.swats
	st0 = p.stamina.value
	bot.grab = true
	await _secs(0.12)
	var rear_mid: float = p.rig.rear
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
	print("D grab: swats %d, rig rear %.2f (none) eye %.2f m, slam %.1f dmg, held %s, moved %.3f m trying to walk + hop, rig grip %.2f, ticks %d, stamina -%.0f" % [c.swats - sw0, rear_mid, eye_mid, slam, str(held), moved, grip_w, c.grip_ticks, st0 - p.stamina.value])
	ok = ok and c.swats == sw0 and rear_mid < 0.05 and held and is_equal_approx(slam, 1.5) and moved < 0.05 and grip_w > 0.9 and c.grip_ticks >= 1
	# E: let go of one paw -> the rat's free and so are you
	bot.jump = false
	bot.grab = false
	await _ticks(2)
	pos0 = p.global_position
	await _secs(0.4)
	moved = p.global_position.distance_to(pos0)
	print("E released grab: rat free %s, gripping %s, cat walks %.2f m in 0.4 s, no stray swat %s" % [str(r.held_by == null), str(c.gripping()), moved, str(c.swats == sw0)])
	ok = ok and r.held_by == null and not c.gripping() and moved > 0.3 and c.swats == sw0
	bot.move = Vector2.ZERO
	bot.grab = false
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
	bot.grab = true
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
	bot.grab = false
	await _secs(0.2)
	print("F brute held %.2f s then wriggled free (break_t %.2f), cat still gripping %s" % [held_for, r.break_t, str(c.gripping())])
	ok = ok and absf(held_for - r.break_t) < 0.05 and r.held_by == null
	bot.grab = false
	await _ticks(2)
	# G: grab it from behind: the slam lands double
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.42))
	r = _still_rat(0.0)              # back to the cat
	_face(r.global_position)
	await _secs(0.15)
	r.hp = 99.0
	r.max_hp = 99.0
	bot.grab = true
	await _secs(0.27)
	var back := r.max_hp - r.hp
	bot.grab = false
	await _secs(0.2)
	bot.grab = false
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
	bot.grab = true
	t = 0.0
	while t < 4.0 and (c.gripping() or t < 0.1):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		r.break_t = 99.0
	print("H 20 stamina, holding a rat: slips after %.2f s, gripping %s" % [t, str(c.gripping())])
	ok = ok and not c.gripping() and t < 2.8
	bot.grab = false
	await _ticks(2)
	# I: hold space: the pounce crouch, release both = free projectile pounce
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 2.0))
	_face(Vector3(0, 0.02, -1.0))
	bot.pitch = -0.15
	await _ticks(3)
	bot.pounce = true
	await _ticks(3)
	var charge0: float = p.charge     # space was already held to get here: full from the start
	await _secs(0.9)
	var aimed := c.aiming()
	var pred: Vector3 = c.pounce.point
	var pkind: String = c.pounce.kind
	var ppath: PackedVector3Array = c.pounce.path
	var pspots: Array = c.pounce.spots
	var n0 := c.pounces
	bot.pounce = false
	# the line: every point the body passes on the way is on the drawn path
	var path_off := 0.0
	var left_floor := false
	var tt := 0.0
	while tt < 3.0:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		if not p.is_on_floor():
			left_floor = true
			path_off = maxf(path_off, _dist_to_path(p.global_position, ppath))
		elif left_floor:
			break
	var land := p.global_position
	await _secs(0.1)
	var settled := p.global_position
	var paws_off := _paws_off(pspots)
	await _secs(0.4)
	var drift := Vector2(p.global_position.x - settled.x, p.global_position.z - settled.z).length()
	var miss := Vector2(settled.x - pred.x, settled.z - pred.z).length()
	print("I free pounce: charge at aim start %.2f, aiming %s, launched %d, %s arc predicted %.2f m out, landed %.2f m out, miss %.4f m, flight off the line %.4f m, paws off their circles %.4f m, drift after landing %.4f m" % [charge0, str(aimed), c.pounces - n0, pkind, 2.0 - pred.z, 2.0 - land.z, miss, path_off, paws_off, drift])
	ok = ok and charge0 > 0.99 and aimed and c.pounces - n0 == 1 and pkind == "free" and miss < 0.005 and path_off < 0.01 and paws_off < 0.01 and drift < 0.002 and 2.0 - land.z > 1.0
	# J: soft lock: rat a bit off the aim line, the pounce bends onto it and pins it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 1.8))
	r = _still_rat(PI)
	r.hp = 99.0
	r.max_hp = 99.0
	_face(Vector3(0.35, 0.02, 0.0))   # aiming ~0.35 m to the side of it
	bot.pitch = -0.1
	await _ticks(3)
	bot.pounce = true
	await _secs(0.9)
	pkind = c.pounce.kind
	pred = c.pounce.point
	bot.pounce = false
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
	bot.pounce = true
	await _secs(0.9)
	pkind = c.pounce.kind
	pred = c.pounce.point
	bot.pounce = false
	pspots = c.pounce.spots
	land = await _land_spot()
	await _secs(0.1)
	paws_off = _paws_off(pspots)
	var hind_y: float = minf((pspots[2] as Vector3).y, (pspots[3] as Vector3).y) if pspots.size() == 4 else 0.0
	await _secs(0.2)
	var kmiss := Vector2(p.global_position.x - pred.x, p.global_position.z - pred.z).length()
	print("K ledge: kind %s, top at %.2f m, landed y %.2f, miss %.4f m, hind paws on top %s, paws off their circles %.4f m" % [pkind, pred.y, land.y, kmiss, str(hind_y > 0.4), paws_off])
	ok = ok and pkind == "ledge" and land.y > 0.4 and kmiss < 0.01 and hind_y > 0.4 and paws_off < 0.015
	box.queue_free()
	await _ticks(2)
	# L: a paw press while aiming = call it off, no pounce
	_reset_cat(Vector3(0, 0.02, 1.0))
	_face(Vector3(0, 0.02, -1.0))
	await _ticks(3)
	n0 = c.pounces
	bot.pounce = true
	await _secs(0.6)
	_paws(true, false)               # a paw instead = call it off
	await _ticks(2)
	_paws(false, false)
	await _secs(0.3)
	bot.pounce = false
	await _secs(0.4)
	print("L paw while aiming: pounces %d, aiming %s, cat y %.2f" % [c.pounces - n0, str(c.aiming()), p.global_position.y])
	ok = ok and c.pounces == n0 and not c.aiming() and p.global_position.y < 0.05
	ok = (await _commit_test()) and ok
	print("COMBATTEST ", "PASS" if ok else "FAIL")
	get_tree().quit()


var _runner: Node3D = null
var _runner_v := Vector3.ZERO


## drives the space filter by hand: held for t, then let go. what came out over the whole press
func _hold_space(t: float, dt: float) -> Dictionary:
	var out := {"jump": false, "pounce": false, "charge": 0.0}
	var e := 0.0
	while e < t:
		var o: Dictionary = p._space_filter(true, true, dt)
		out.pounce = out.pounce or o.pounce
		out.jump = out.jump or o.jump
		e += dt
	var o2: Dictionary = p._space_filter(false, true, dt)
	out.jump = out.jump or o2.jump
	out.charge = o2.hop_charge
	out.mul = o2.hop_mul
	return out


func _hop_height(charge: float, mul := -1.0) -> float:
	_reset_cat(Vector3(0, 0.02, 1.0))
	await _secs(0.3)
	# a big hop's hard landing can still be playing out (ouch knock): settle on the floor first
	var w := 0.0
	while w < 0.25:
		await get_tree().physics_frame
		w = w + get_physics_process_delta_time() if p.is_on_floor() else 0.0
	var y0 := p.global_position.y
	bot.hop_charge = charge
	if mul > 0.0:
		bot.hop_mul = mul
	bot.jump = true
	await _ticks(2)
	bot.jump = false
	var top := y0
	var t := 0.0
	while t < 1.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = maxf(top, p.global_position.y)
		if t > 0.2 and p.is_on_floor():
			break
	bot.erase("hop_charge")
	bot.erase("hop_mul")
	await _secs(0.3)
	return top - y0


## steps physics ticks until cond() or max_t, returns the time it took (max_t if never)
func _until(cond: Callable, max_t := 1.5) -> float:
	var t := 0.0
	while t < max_t:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if cond.call():
			return t
	return max_t


## souls commitment (cat_combat.gd MOVES): phases, movement + turn lock, buffered swats,
## dodge only from the cancel point, stagger out of a wind up, committed grab reach
func _commit_test() -> bool:
	var ok := true
	var c := p.combat
	var sw: Dictionary = CatCombat.MOVES.swat
	# M: trotting in, swat: the feet plant, the body won't swing round, phases run in order
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 2.5))
	_face(Vector3(0, 0.02, -3))
	bot.move = Vector2(0, 1)
	await _secs(0.8)
	var v0 := Vector2(p.velocity.x, p.velocity.z).length()
	var y0: float = p.yaw
	_paws(true, false)
	await _until(func(): return c.atk_phase == CatCombat.A_WIND)
	bot.yaw = y0 + 1.5               # yank the view round mid attack
	p.orb_yaw = bot.yaw
	var phases := []
	var v_act := 99.0
	var t := 0.0
	while t < 0.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if c.atk_phase == CatCombat.A_ACTIVE:
			v_act = minf(v_act, Vector2(p.velocity.x, p.velocity.z).length())
		var ph: String = c.phase_name()
		if phases.is_empty() or phases[-1] != ph:
			phases.append(ph)
		if c.atk_phase == CatCombat.A_RECOVER and phases.size() == 3:
			break
	var turned := absf(wrapf(p.yaw - y0, -PI, PI))
	_paws(false, false)
	bot.move = Vector2.ZERO
	await _secs(0.5)
	print("M swat at a trot: phases %s, speed %.2f -> %.2f m/s while the paw's out, body turned %.2f rad of 1.5 by the recovery" % [str(phases), v0, v_act, turned])
	ok = ok and phases == ["wind", "active", "recover"] and v0 > 2.5 and v_act < 2.0 and turned < 0.45
	bot.yaw = p.yaw
	# N: mash: a second click mid swat is buffered and comes out at the chain point
	_reset_cat(Vector3(0, 0.02, 1.0))
	_face(Vector3(0, 0.02, -1))
	await _ticks(3)
	var s0 := c.swats
	_paws(true, false)
	await _until(func(): return c.swats > s0)
	var f1: float = c.fire_clock
	await _ticks(2)
	_paws(false, true)               # right paw while the left is still winding up
	await _ticks(3)
	_paws(false, false)
	var early := c.swats - s0
	await _until(func(): return c.swats > s0 + 1)
	var gap: float = c.fire_clock - f1
	await _secs(0.5)
	var want: float = sw.wind + sw.active + sw.chain
	print("N mash left, right: right paw buffered (swats right after click %d), came out %.2f s after the left (chain point %.2f), right paw %s" % [early, gap, want, str(p.rig.get("_swat_i") == 1)])
	ok = ok and early == 1 and absf(gap - want) < 0.02 and c.swats - s0 == 2 and p.rig.get("_swat_i") == 1
	# O: dodge pressed in the wind up waits for the cancel point, then rolls out of the recovery
	_reset_cat(Vector3(0, 0.02, 1.0))
	_face(Vector3(0, 0.02, -1))
	await _ticks(3)
	var d0: int = p.dash.count
	_paws(true, false)
	await _until(func(): return c.atk_phase == CatCombat.A_WIND)
	await _ticks(1)
	bot.dash = true
	await _ticks(2)
	bot.dash = false
	await _until(func(): return p.dash.state != CatDash.IDLE)
	var td: float = c.clock - c.fire_clock
	_paws(false, false)
	await _secs(0.7)
	var wcan: float = sw.wind + sw.active + sw.cancel
	print("O dodge pressed in the wind up: rolled %.2f s into the swat (cancel point %.2f), dodges %d, cancels %d" % [td, wcan, p.dash.count - d0, c.dodge_cancels])
	ok = ok and p.dash.count - d0 == 1 and absf(td - wcan) < 0.02 and c.dodge_cancels >= 1
	# P: bitten in the wind up: staggered out, the paw never lands
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.36))
	var r := _still_rat(PI)
	r.hp = 9.0
	r.max_hp = 9.0
	_face(r.global_position)
	await _secs(0.6)
	p.health.grace = 0.0
	var i0: int = c.interrupts
	_paws(true, false)
	await _until(func(): return c.atk_phase == CatCombat.A_WIND)
	await _ticks(2)
	p.health.damage(0.5, r.global_position, 0.5)
	_paws(false, false)
	await _secs(0.4)
	print("P hit mid wind up: interrupted %d, rat took %.1f dmg, still attacking %s" % [c.interrupts - i0, r.max_hp - r.hp, str(c.committed())])
	ok = ok and c.interrupts - i0 == 1 and is_equal_approx(r.hp, r.max_hp) and not c.committed()
	p.health.value = CatHealth.MAX
	# Q: tap grab: the reach still finishes, then a recovery, no pounce
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 1.0))
	_face(Vector3(0, 0.02, -1))
	await _secs(0.3)
	var n0 := c.pounces
	bot.grab = true
	await _secs(0.05)
	bot.grab = false
	await _secs(0.05)
	var still_rearing: bool = c.grip_phase == CatCombat.G_REACH
	var tr := await _until(func(): return c.atk == "grab_out")
	var out_ok: bool = c.atk == "grab_out"
	await _secs(0.4)
	print("Q tap grab: still reaching after letting go %s, grab_out recovery %s, pounces %d" % [str(still_rearing), str(out_ok), c.pounces - n0])
	ok = ok and still_rearing and out_ok and c.pounces == n0 and not c.committed()
	# R: both paws next to a rat = two swats (left, then the right buffered), no grab, no pounce
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.4))
	r = _still_rat(PI)
	r.hp = 99.0
	r.max_hp = 99.0
	_face(r.global_position)
	await _ticks(3)
	var sw0 := c.swats
	_paws(true, true)
	await _secs(0.4)
	var aim_r: bool = c.aiming()
	var held_r: bool = r.held_by == p
	_paws(false, false)
	await _secs(0.3)
	print("R both paws by a rat: swats %d, pounce crouch %s, grabbed %s" % [c.swats - sw0, str(aim_r), str(held_r)])
	ok = ok and c.swats - sw0 == 2 and not aim_r and not held_r
	# S: a rat running across: the pounce leads it and lands where it got to
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 2.2))
	r = _still_rat(-PI * 0.5)
	r.hp = 99.0
	r.max_hp = 99.0
	r.global_position = Vector3(-1.0, 0.02, 0.4)
	_face(Vector3(0, 0.02, 0.4))
	bot.pitch = -0.05
	_runner = r
	_runner_v = Vector3(1.2, 0, 0)
	await _ticks(3)
	bot.pounce = true
	await _secs(0.8)
	var lead_kind: String = c.pounce.kind
	var lead_pt: Vector3 = c.pounce.point
	var rat_then: Vector3 = r.global_position
	bot.pounce = false
	var land_s := await _land_spot()
	var rat_at := r.global_position
	_runner = null
	await _secs(0.3)
	var lead := Vector2(lead_pt.x - rat_then.x, lead_pt.z - rat_then.z).length()
	var off := Vector2(rat_at.x - land_s.x, rat_at.z - land_s.z).length()
	print("S rat running 1.2 m/s across: kind %s, aimed %.2f m ahead of it, landed %.2f m from where it got to, pin dmg %.1f" % [lead_kind, lead, off, r.max_hp - r.hp])
	ok = ok and lead_kind in ["prey", "lock"] and lead > 0.3 and off < 0.45 and r.max_hp - r.hp >= 2.5
	# T: space: tap = hop, hold = higher hop, hold long = pounce mode (the human input filter)
	_reset_cat(Vector3(0, 0.02, 1.0))
	await _ticks(3)
	var dt := 1.0 / 144.0
	var f_tap := _hold_space(0.06, dt)
	var f_mid := _hold_space(0.3, dt)
	var f_long := _hold_space(0.6, dt)
	var f_air: Dictionary = p._space_filter(true, false, dt)
	p._space_filter(false, false, dt)
	print("T space filter: tap %s, 0.3 s %s, 0.6 s %s, air press jumps at once %s" % [str(f_tap), str(f_mid), str(f_long), str(f_air.jump)])
	ok = ok and f_tap.jump and f_tap.charge == 0.0 and f_tap.mul < 0.2 and f_mid.mul > f_tap.mul * 3.0 and f_mid.jump and f_mid.charge > 0.3 and f_mid.charge < 0.8 and not f_mid.pounce and f_long.pounce and not f_long.jump and f_air.jump
	# U: a charged hop goes higher than a tapped one
	var h_tap := await _hop_height(0.0)
	var h_big := await _hop_height(1.0)
	var h_tiny := await _hop_height(0.0, CatPlayer.HOP_TAP_MUL)
	var h_full := await _hop_height(1.0, CatPlayer.HOP_CHARGE_MUL)
	print("U hop %.2f m tapped, %.2f m fully charged (bot) / player space: tap %.2f m, held %.2f m" % [h_tap, h_big, h_tiny, h_full])
	ok = ok and h_big > h_tap * 1.4 and h_tiny < 0.2 and h_full > h_tiny * 6.0
	# V: every swat lunges a bit: into open air the full step, at a rat it stops just short + hits
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 1.5))
	_face(Vector3(0, 0.02, -2))
	await _secs(0.3)
	var z0 := p.global_position.z
	_paws(true, false)
	await _ticks(3)
	_paws(false, false)
	await _secs(0.5)
	var open_d := z0 - p.global_position.z
	r = _still_rat(PI)
	r.hp = 9.0
	r.max_hp = 9.0
	_reset_cat(Vector3(0, 0.02, 0.56))
	_face(r.global_position)
	await _secs(0.3)
	var gap0 := p.global_position.distance_to(r.global_position)
	_paws(false, true)
	await _ticks(3)
	_paws(false, false)
	await _secs(0.5)
	var gap1 := Vector2(p.global_position.x - r.global_position.x, p.global_position.z - r.global_position.z).length()
	var near_side := gap1 - 0.16 * r.s
	print("V lunge: open air %.2f m, at a rat %.2f -> %.2f m (near side %.2f m off), rat took %.1f, rig gather peak test %s" % [open_d, gap0, gap1, near_side, r.max_hp - r.hp, str(CatCombat.MOVES.swat.has("lunge"))])
	ok = ok and open_d > 0.12 and open_d < 0.4 and gap1 < gap0 - 0.05 and near_side > CatCombat.LUNGE_STOP - 0.05 and r.max_hp - r.hp >= 1.0
	return ok


# ---------------------------------------------------------------- show reel

var _dummy: SoulsRat = null
var _dummy_yaw := 0.0
var _dummy_pos := Vector3.ZERO


func _physics_process(_dt: float) -> void:
	if is_instance_valid(_runner) and _runner.get("held_by") == null and not (_runner.has_method("pinned") and _runner.pinned()):
		_runner.global_position += _runner_v * _dt     # test S: moved by position only (no velocity to read)
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
	_say("g = grab  (half speed)", "quick reach, both paws pin it (no rearing up)")
	Engine.time_scale = 0.5
	bot.grab = true
	await _secs(0.9)
	Engine.time_scale = 1.0
	_say("holding", "holding w: can't walk without a free paw")
	bot.move = Vector2(0, 1)
	await _secs(0.9)
	_say("let go of g", "free to walk again")
	bot.grab = false
	await _secs(0.7)
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
	bot.grab = true
	await _secs(1.8)
	bot.grab = false
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
	bot.pounce = true
	await _secs(wind)
	bot.pounce = false
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
	_say("hold space", "past the hop: pounce crouch, the line shows exactly where it lands")
	await _pounce(1.1)
	_say("let go", "low forward arc, no steering, sticks the landing dead still")
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


# ---------------------------------------------------------------- exact landing reel (--landshow)

## copies of the aim's paw circles + landing ring left in the world (video only), so you can watch
## the paws come down in them after the real ones vanish at launch
func _ghost_marks() -> Array:
	var out := []
	var src: Array = [p._aim_ring]
	src.append_array(p._paw_rings)
	for r in src:
		if not (r as MeshInstance3D).is_visible_in_tree():
			continue
		var g := MeshInstance3D.new()
		g.mesh = r.mesh
		var m: StandardMaterial3D = (r.material_override as StandardMaterial3D).duplicate()
		m.albedo_color.a *= 0.7
		g.material_override = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arena.add_child(g)
		g.global_transform = r.global_transform
		out.append(g)
	return out


func _slow_pounce(aim_t: float, slow := 0.3) -> void:
	bot.pounce = true
	await _secs(aim_t)
	var ghosts := _ghost_marks()
	Engine.time_scale = slow
	bot.pounce = false
	var left := false
	var t := 0.0
	while t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not p.is_on_floor():
			left = true
		elif left:
			break
	await _secs(0.35)
	Engine.time_scale = 1.0
	await _secs(1.1)
	for g in ghosts:
		g.queue_free()


func _landshow() -> void:
	_labels()
	arena.hud.visible = true
	cam = Camera3D.new()
	cam.fov = 45
	cam.near = 0.02
	arena.add_child(cam)
	cam.current = true
	p.set_third_person(true)
	await _ticks(10)
	await _clear_rats()
	_dummy = null
	# 1: tap vs hold
	_reset_cat(Vector3(0, 0.02, 1.0))
	_face(Vector3(0, 0.02, -2))
	cam.global_position = Vector3(2.4, 0.6, 0.9)
	cam.look_at(Vector3(0, 0.45, 0.9))
	_say("tap space", "tiny hop")
	await _secs(0.6)
	bot.hop_charge = 0.0
	bot.hop_mul = CatPlayer.HOP_TAP_MUL
	bot.jump = true
	await _ticks(2)
	bot.jump = false
	await _secs(1.2)
	_say("hold space a bit", "the hop builds up the longer you hold")
	bot.hop_charge = 1.0
	bot.hop_mul = CatPlayer.HOP_CHARGE_MUL
	bot.jump = true
	await _ticks(2)
	bot.jump = false
	await _secs(1.6)
	bot.erase("hop_charge")
	bot.erase("hop_mul")
	# 2: free pounce from above: line + four paw circles, slow mo landing into them
	_reset_cat(Vector3(0, 0.02, 2.2))
	_face(Vector3(0, 0.02, -2.0))
	bot.pitch = -0.12
	cam.global_position = Vector3(1.1, 1.15, 2.6)
	cam.look_at(Vector3(0, 0.0, 1.2))
	_say("hold space: pounce mode", "full power straight away, line = the exact flight, a circle for each paw")
	await _slow_pounce(1.4)
	_say("lands on the spot", "no slide, no bounce, every paw in its circle")
	await _secs(0.8)
	# 3: close up on the paws
	_reset_cat(Vector3(0, 0.02, 2.0))
	_face(Vector3(0.3, 0.02, -2.0))
	bot.pitch = -0.2
	cam.global_position = Vector3(0.55, 0.55, 1.15)
	cam.look_at(Vector3(0.12, 0.0, 0.85))
	_say("close up", "paw circles")
	await _slow_pounce(1.2, 0.25)
	# 4: crate: the old ray-only line could clip the edge, now the cat's own body is traced
	var box := _block(Vector3(0, 0.25, 0.1), Vector3(1.0, 0.5, 0.7))
	_reset_cat(Vector3(0, 0.02, 2.2))
	_face(Vector3(0, 0.1, 0.4))
	bot.pitch = -0.08
	cam.global_position = Vector3(1.6, 1.1, 2.3)
	cam.look_at(Vector3(0, 0.3, 1.0))
	_say("onto a crate", "snaps on top, far enough in for the back paws too")
	await _slow_pounce(1.2)
	box.queue_free()
	# 5: rat: soft lock
	_reset_cat(Vector3(0, 0.02, 2.2))
	_dummy_rat(PI, Vector3(0.0, 0.02, 0.4))
	_face(Vector3(0.4, 0.02, 0.4))
	bot.pitch = -0.05
	cam.global_position = Vector3(1.5, 1.0, 2.4)
	cam.look_at(Vector3(0, 0.1, 1.2))
	_say("onto a rat", "flies onto it, not into it: no shove off the spot")
	await _slow_pounce(1.2)
	await _secs(0.5)
	get_tree().quit()


# ---------------------------------------------------------------- commitment reel (--commitshow)

## waits t seconds, the subtitle shows the attack phase live (wind up / paw out / recovery)
func _watch(t: float, title: String, extra := "") -> void:
	var c := p.combat
	var e := 0.0
	while e < t:
		await get_tree().physics_frame
		e += get_physics_process_delta_time()
		var ph: String = {"wind": "WIND UP", "active": "PAW OUT", "recover": "RECOVERY"}.get(c.phase_name(), "")
		if c.buf_paw >= 0:
			ph += "   + buffered " + ("left" if c.buf_paw == 0 else "right")
		if c.dodge_buf > 0.0:
			ph += "   + dodge waiting"
		_say(title, (ph + "   " + extra) if ph != "" else extra)


func _commitshow() -> void:
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
	cam.global_position = Vector3(1.05, 0.38, 0.12)
	cam.look_at(Vector3(0, 0.13, 0.3))
	# 1: one swat, half speed, phases called out
	Engine.time_scale = 0.4
	_say("souls style commitment", "every swat: wind up + lunge, paw out, scratch, recovery")
	await _secs(0.4)
	_paws(true, false)
	await _ticks(4)
	_paws(false, false)
	await _watch(0.6, "lunge + scratch  (0.4x)", "steps in, claws drag down and back")
	# 2: mash: clicks are buffered and come out on the beat
	_paws(false, true)
	await _ticks(3)
	_paws(false, false)
	await _ticks(10)
	_paws(true, false)
	await _ticks(3)
	_paws(false, false)
	await _watch(0.25, "mashing  (0.4x)", "extra clicks wait their turn")
	_paws(false, true)
	await _ticks(3)
	_paws(false, false)
	await _watch(0.6, "mashing  (0.4x)", "extra clicks wait their turn")
	# 3: dodge pressed in the wind up rolls out of the recovery
	_paws(true, false)
	await _ticks(4)
	_paws(false, false)
	await _ticks(6)
	bot.move = Vector2(1, 0)
	bot.dash = true
	await _ticks(3)
	bot.dash = false
	await _watch(0.7, "dodge mid swat  (0.4x)", "comes out at the cancel point")
	bot.move = Vector2.ZERO
	Engine.time_scale = 1.0
	await _secs(0.5)
	# 4: trotting in: the feet plant
	await _clear_rats()
	_dummy = null
	_reset_cat(Vector3(0, 0.02, 2.4))
	_face(Vector3(0, 0.02, -3))
	cam.global_position = Vector3(1.6, 0.45, 1.2)
	cam.look_at(Vector3(0, 0.12, 1.0))
	bot.move = Vector2(0, 1)
	_say("swat at a trot", "the feet plant, the body won't swing round")
	await _secs(0.55)
	_paws(true, false)
	await _ticks(4)
	_paws(false, false)
	await _watch(0.6, "swat at a trot", "the feet plant, the body won't swing round")
	bot.move = Vector2.ZERO
	await _secs(0.4)
	# 5: grab on its own button, no rearing up
	_reset_cat(Vector3(0, 0.02, 0.5))
	r = _dummy_rat(PI, Vector3(0, 0.02, 0))
	_face(r.global_position)
	cam.global_position = Vector3(1.05, 0.38, 0.12)
	cam.look_at(Vector3(0, 0.13, 0.3))
	_say("g = grab", "quick reach, both paws pin it, no rearing up")
	await _secs(0.3)
	bot.grab = true
	await _secs(1.2)
	bot.grab = false
	await _secs(0.5)
	# 6: space: tap hop, held hop, hold = pounce mode with the line
	await _clear_rats()
	_dummy = null
	_reset_cat(Vector3(0, 0.02, 1.0))
	_face(Vector3(0, 0.02, -2))
	cam.global_position = Vector3(2.2, 0.55, 0.6)
	cam.look_at(Vector3(0, 0.4, 0.8))
	_say("space: tap", "hop")
	await _secs(0.3)
	bot.jump = true
	await _ticks(2)
	bot.jump = false
	await _secs(0.9)
	_say("space: hold a bit", "higher hop")
	bot.hop_charge = 1.0
	bot.jump = true
	await _ticks(2)
	bot.jump = false
	await _secs(1.1)
	bot.erase("hop_charge")
	# 7: pounce onto a running rat: the lock leads it
	_reset_cat(Vector3(0, 0.02, 2.2))
	r = _still_rat(-PI * 0.5)
	r.hp = 50.0
	r.max_hp = 50.0
	r.global_position = Vector3(-1.3, 0.02, 0.4)
	_face(Vector3(0, 0.02, 0.4))
	bot.pitch = -0.05
	cam.global_position = Vector3(2.3, 0.75, 2.0)
	cam.look_at(Vector3(-0.2, 0.1, 1.2))
	_runner = r
	_runner_v = Vector3(1.0, 0, 0)
	_say("space: hold long", "pounce mode: the line shows the exact path, it leads the running rat")
	await _pounce(1.0, false)
	_runner = null
	_say("lands on it", "dead still, no slide, pinned")
	await _secs(0.8)
	# 8: ledge snap
	await _clear_rats()
	var box := _block(Vector3(0, 0.25, 0.1), Vector3(1.0, 0.5, 0.7))
	_reset_cat(Vector3(0, 0.02, 2.2))
	_face(Vector3(0, 0.1, 0.4))
	bot.pitch = -0.08
	cam.global_position = Vector3(2.3, 0.8, 1.8)
	cam.look_at(Vector3(0, 0.25, 1.2))
	_say("still snaps to ledges", "and the tab lock target, and prey")
	await _pounce(1.0)
	await _secs(0.6)
	box.queue_free()
	# 9: first person: the fp paws lunge + scratch too
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.6))
	var r2 := _dummy_rat(PI, Vector3(0, 0.02, 0))
	_face(r2.global_position)
	p.set_third_person(false)
	p.cam.current = true
	Engine.time_scale = 0.5
	_say("first person  (0.5x)", "lunge in, scratch, left right left")
	await _secs(0.3)
	for k in 3:
		_paws(k % 2 == 0, k % 2 == 1)
		await _ticks(3)
		_paws(false, false)
		await _secs(0.32)
	await _secs(0.4)
	Engine.time_scale = 1.0
	get_tree().quit()
