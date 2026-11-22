class_name ParryTest
extends ArenaTest
## deflect + combo checks (cat_parry.gd, souls_rat.gd COMBOS, parry_cue.gd).
## `res://arena.tscn -- --parrytest` prints each rule and PARRYTEST PASS/FAIL,
## `-- --parryshow` films a deflect fight vs combos + the rat king for --write-movie.

var _auto := false            # the bot deflects / dodges each strike on the cue
var _auto_early := 0.0        # press this long before the hit (0 = on the beat)
var _auto_dodge := true
var _hold := 0
var _dodge_hold := 0
var _dodged_step := []


func _ready() -> void:
	p = arena.player
	bot = p.bot
	if "--parrytest" in OS.get_cmdline_user_args():
		_ptest.call_deferred()
	elif "--dodgeshow" in OS.get_cmdline_user_args():
		_dshow.call_deferred()
	else:
		_pshow.call_deferred()


func _combo_rat(pos: Vector3, yaw: float, pool: Array, size := 1.0) -> SoulsRat:
	var r: SoulsRat = arena.spawn_rat(pos, size)
	r.yaw = yaw
	r.rotation.y = yaw
	r.combos = pool
	r.leaps_on = false
	return r


## the deflect bot: watches the nearest rat's next strike, presses deflect DEFLECT_AT before it
## lands (or dodges a perilous one sideways)
func _physics_process(_dt: float) -> void:
	if not _auto or p == null:
		return
	bot.deflect = _hold > 0
	_hold = maxi(_hold - 1, 0)
	if _dodge_hold > 0:
		_dodge_hold -= 1
		bot.dash = _dodge_hold > 2
		if _dodge_hold == 0:
			bot.move = Vector2.ZERO
	for r in arena.rats:
		if not is_instance_valid(r) or not r.alive():
			continue
		if r.global_position.distance_to(p.global_position) > 1.2:
			continue
		var th: float = r.time_to_hit()
		if th < 0.0:
			continue
		if r.perilous:
			if _auto_dodge and th < 0.2 and _dodge_hold == 0 and _dodged_step != [r, r.combos_done, r.step]:
				_dodged_step = [r, r.combos_done, r.step]
				bot.move = Vector2(1, 0)
				bot.dash = true      # same tick as the stick (a bot side hops on a bare sideways tilt)
				_dodge_hold = 8
		elif th <= 0.045 + _auto_early and th > 0.045 + _auto_early - 0.012 and _hold == 0:
			_hold = 3


func _ptest() -> void:
	var ok := true
	await _ticks(30)
	p.combat_zone = true
	# A: a triple combo comes on its beat, each strike with a cue
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	var r := _combo_rat(Vector3(0, 0.02, 0), PI, ["triple"])
	_face(r.global_position)
	var hits: Array[float] = []
	var t := 0.0
	var b0 := r.bites
	while t < 4.0 and r.combos_done == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if r.bites > b0:
			hits.append(t)
			b0 = r.bites
	var gaps := []
	for i in range(1, hits.size()):
		gaps.append(snappedf(hits[i] - hits[i - 1], 0.01))
	print("A triple combo: %d strikes, gaps %s, cues %d" % [hits.size(), str(gaps), r.cue.cues])
	ok = ok and hits.size() == 3 and r.cue.cues == 3 and gaps.size() == 2 and gaps[0] > 0.3 and gaps[0] < 0.65
	# B: deflect every strike on the cue: no damage, posture goes up
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	var h0 := p.health.hits_taken
	var d0 := p.parry.deflects
	r = _combo_rat(Vector3(0, 0.02, 0), PI, ["triple"])
	_face(r.global_position)
	_auto = true
	_auto_early = 0.0
	var peak := 0.0
	t = 0.0
	while t < 4.0 and r.combos_done == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		peak = maxf(peak, r.posture_v)
	_auto = false
	print("B deflect each hit: %d deflected (%d perfect), %d hits taken, rat posture peak %.1f / %.0f" % [p.parry.deflects - d0, p.parry.perfects, p.health.hits_taken - h0, peak, r.posture_max])
	ok = ok and p.parry.deflects - d0 == 3 and p.health.hits_taken == h0 and peak >= 2.5
	# C: mashing way too early: the window has shut when the bite lands
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	h0 = p.health.hits_taken
	d0 = p.parry.deflects
	r = _combo_rat(Vector3(0, 0.02, 0), PI, ["snap"])
	_face(r.global_position)
	_auto = true
	_auto_early = 0.35
	t = 0.0
	while t < 2.5 and r.combos_done == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_auto = false
	_auto_early = 0.0
	print("C pressed 0.35 s early: %d deflected, %d hits taken" % [p.parry.deflects - d0, p.health.hits_taken - h0])
	ok = ok and p.parry.deflects == d0 and p.health.hits_taken == h0 + 1
	# D: a perilous leap can't be deflected (bot presses deflect anyway, no dodge)
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.75))
	h0 = p.health.hits_taken
	d0 = p.parry.deflects
	r = _combo_rat(Vector3(0, 0.02, 0), PI, ["leap"])
	_face(r.global_position)
	t = 0.0
	var pressed := false
	while t < 2.5 and r.combos_done == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var th := r.time_to_hit()
		if not pressed and th > 0.0 and th < 0.05:
			bot.deflect = true
			pressed = true
		elif pressed:
			bot.deflect = false
	bot.deflect = false
	var leap_hit := p.health.hits_taken - h0
	# ... and dodged it is fine
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.75))
	h0 = p.health.hits_taken
	r = _combo_rat(Vector3(0, 0.02, 0), PI, ["leap"])
	_face(r.global_position)
	_auto = true
	t = 0.0
	var dbg_d := p.dash.count
	while t < 2.5 and r.combos_done == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if OS.has_environment("PARRY_DBG") and (r.state == SoulsRat.LUNGE or bot.get("dash", false)):
			print("  t %.3f th %.3f dash %s state %d ifr %.2f hits %d dodged %d d %.2f" % [t, r.time_to_hit(), str(bot.get("dash")), p.dash.state, p.dash.iframes, p.health.hits_taken, p.health.hits_dodged, p.global_position.distance_to(r.global_position)])
	print("  dodges in D: %d" % (p.dash.count - dbg_d))
	_auto = false
	bot.move = Vector2.ZERO
	bot.dash = false
	print("D perilous leap: deflect -> %d hits (%d deflected), dodge -> %d hits, cue perilous %s" % [leap_hit, p.parry.deflects - d0, p.health.hits_taken - h0, str(r.perilous)])
	ok = ok and leap_hit == 1 and p.parry.deflects == d0 and p.health.hits_taken == h0
	# E: break its posture with deflects, then the finishing swat kills it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	r = _combo_rat(Vector3(0, 0.02, 0), PI, ["triple"])
	_face(r.global_position)
	_auto = true
	t = 0.0
	while t < 8.0 and r.state != SoulsRat.BROKEN:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_face(r.global_position)
	_auto = false
	var broke := r.state == SoulsRat.BROKEN
	var killed := [false]
	r.killed.connect(func(_x): killed[0] = true)
	_face(r.global_position)
	await _ticks(2)
	bot.swat = true
	await _ticks(2)
	bot.swat = false
	await _secs(0.4)
	print("E posture: broken %s after %.1f s, finishing swat killed it %s (deathblows %d)" % [str(broke), t, str(killed[0]), r.deathblows])
	ok = ok and broke and killed[0]
	# F: the chord. dodge then swat 2 ticks later = deflect, no dodge, stamina back.
	#    dodge alone = a dodge (after the chord window)
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	await _ticks(5)
	var dc := p.dash.count
	var pc := p.parry.presses
	var sw := p.combat.swats
	var st0 := p.stamina.value
	bot.dash = true
	await _ticks(2)
	bot.swat = true
	await _ticks(3)
	bot.swat = false
	bot.dash = false
	await _secs(0.3)
	var chord_ok := p.parry.presses == pc + 1 and p.dash.count == dc and p.combat.swats == sw
	var st1 := p.stamina.value
	await _secs(0.4)
	bot.dash = true
	await _ticks(2)
	bot.dash = false
	await _secs(0.5)
	print("F chord: alt + click -> deflects %d dodges %d swats %d stamina %.0f -> %.0f · alt alone -> dodges %d" % [p.parry.presses - pc, 0 if chord_ok else p.dash.count - dc, p.combat.swats - sw, st0, st1, p.dash.count - dc])
	ok = ok and chord_ok and st1 >= st0 - CatParry.STAMINA - 0.5 and p.dash.count == dc + 1
	# G: the rat king vs the deflect bot (deflects the glints, dodges the red ones)
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.9))
	h0 = p.health.hits_taken
	d0 = p.parry.deflects
	r = _combo_rat(Vector3(0, 0.02, 0), PI, [], 2.3)
	r.leaps_on = true
	r.combos = []
	_auto = true
	var breaks := 0
	var was_broken := false
	var perils := 0
	var was_p := false
	t = 0.0
	while t < 14.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _dodge_hold == 0:
			_face(r.global_position)
		var b := r.state == SoulsRat.BROKEN
		if b and not was_broken:
			breaks += 1
		was_broken = b
		var pp := r.perilous and r.state == SoulsRat.WINDUP
		if pp and not was_p:
			perils += 1
		was_p = pp
		p.health.value = CatHealth.MAX
		p.stamina.value = CatStamina.MAX
	_auto = false
	bot.move = Vector2.ZERO
	print("G rat king 14 s: %d combos, %d strikes, %d deflected, %d perilous, %d hits taken, posture breaks %d" % [r.combos_done, r.bites, p.parry.deflects - d0, perils, p.health.hits_taken - h0, breaks])
	ok = ok and r.combos_done >= 2 and p.parry.deflects - d0 >= 4
	print("PARRYTEST %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------- show (video)

func _cam_setup() -> void:
	cam = Camera3D.new()
	cam.fov = 55
	arena.add_child(cam)
	cam.current = true
	var hud := CanvasLayer.new()
	arena.add_child(hud)
	caption = Label.new()
	caption.position = Vector2(30, 24)
	caption.add_theme_font_size_override("font_size", 30)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	caption.add_theme_constant_override("outline_size", 8)
	hud.add_child(caption)
	sub = Label.new()
	sub.position = Vector2(30, 66)
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub.add_theme_constant_override("outline_size", 6)
	hud.add_child(sub)


func _side_cam(r: Node3D, dist := 1.5, h := 0.55) -> void:
	var mid: Vector3 = p.global_position.lerp(r.global_position, 0.5)
	var ab: Vector3 = r.global_position - p.global_position
	ab.y = 0.0
	var side := ab.cross(Vector3.UP).normalized() if ab.length() > 0.01 else Vector3.RIGHT
	var want := mid + side * dist + Vector3.UP * h - ab.normalized() * 0.3
	cam.global_position = cam.global_position.lerp(want, 0.08) if cam.global_position.length() > 0.1 else want
	cam.look_at(mid + Vector3.UP * 0.12, Vector3.UP)


func _film(r: SoulsRat, secs: float, use_cam := true) -> void:
	var t := 0.0
	while t < secs and is_instance_valid(r):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _dodge_hold == 0 and r.alive():
			_face(r.global_position)
		p.health.value = maxf(p.health.value, 40.0)
		p.stamina.value = maxf(p.stamina.value, 50.0)
		if use_cam:
			_side_cam(r)


func _pshow() -> void:
	await _ticks(20)
	p.combat_zone = true
	_cam_setup()
	# 1: the cue up close (slow, no deflect): glint + closing ring, red ! for perilous
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.55))
	var r := _combo_rat(Vector3(0, 0.02, 0), PI, ["triple"])
	caption.text = "rat combos come on a beat"
	sub.text = "each strike: a glint + a ring closing on it. ring meets the star = the hit lands"
	await _film(r, 3.2)
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.55))
	r = _combo_rat(Vector3(0, 0.02, 0), PI, ["triple", "double"])
	caption.text = "alt + click = deflect"
	sub.text = "press as the ring closes. keep alt held and click again for the next hit"
	_auto = true
	_auto_dodge = true
	await _film(r, 5.5)
	caption.text = "deflects fill its posture"
	sub.text = "full bar = broken, the next swat finishes it"
	var t := 0.0
	while t < 6.0 and r.state != SoulsRat.BROKEN and is_instance_valid(r):
		await _film(r, 0.1)
		t += 0.1
	_auto = false
	await _film(r, 0.35)
	bot.swat = true
	await _ticks(2)
	bot.swat = false
	await _film(r, 1.6)
	# 2: perilous: red ! = dodge
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.8))
	r = _combo_rat(Vector3(0, 0.02, 0), PI, ["snap_leap"], 1.6)
	caption.text = "red ! = perilous, can't be deflected"
	sub.text = "dodge it (alt alone)"
	_auto = true
	await _film(r, 4.0)
	# 3: the rat king, first person
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 1.0))
	r = _combo_rat(Vector3(0, 0.02, 0), PI, [], 2.3)
	r.leaps_on = true
	caption.text = "the rat king (wave 5)"
	sub.text = "long combos, delayed bites, perilous tail sweeps"
	await _film(r, 7.0)
	caption.text = "first person"
	sub.text = ""
	cam.current = false
	p.cam.current = true
	await _film(r, 7.0, false)
	_auto = false
	get_tree().quit()


## before / after reel of the dodge: the old per kind poses vs the procedural one
## (`res://arena.tscn -- --dodgeshow`, half speed)
func _dshow() -> void:
	await _ticks(20)
	p.combat_zone = true
	_cam_setup()
	await _clear_rats()
	Engine.time_scale = 0.5
	var moves := [
		["forward (dart)", Vector2(0, 1)],
		["right (side leap)", Vector2(1, 0)],
		["no stick (backstep)", Vector2.ZERO],
		["forward left", Vector2(-0.7, 0.7)],
		["behind (whirl)", Vector2(0, -1)],
		["back right", Vector2(0.7, -0.7)],
	]
	for pass_i in 2:
		CatRig.proc_dodge = pass_i == 1
		for m in moves:
			_reset_cat(Vector3(0, 0.02, 0.0))
			bot.yaw = 0.0
			bot.pitch = 0.0
			p.yaw = 0.0
			p.orb_yaw = 0.0
			caption.text = ("BEFORE: canned pose per kind" if pass_i == 0 else "AFTER: procedural (velocity driven)")
			sub.text = "dodge " + m[0]
			cam.global_position = Vector3(1.25, 0.5, -0.35)
			cam.look_at(Vector3(0, 0.15, -0.35), Vector3.UP)
			await _secs(0.35)
			bot.move = m[1]
			bot.dash = true
			await _ticks(3)
			bot.dash = false
			var t := 0.0
			while t < 1.0:
				await get_tree().physics_frame
				t += get_physics_process_delta_time()
				var want := p.global_position + Vector3(1.25, 0.5, 0.0)
				cam.global_position = cam.global_position.lerp(want, 0.05)
				cam.look_at(p.global_position + Vector3.UP * 0.15, Vector3.UP)
			bot.move = Vector2.ZERO
			await _secs(0.25)
	Engine.time_scale = 1.0
	CatRig.proc_dodge = true
	get_tree().quit()
