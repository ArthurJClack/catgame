class_name ArenaTest
extends Node
## arena checks + the preview fight. `-- --arenatest` (headless) prints each rule and PASS/FAIL,
## `-- --arenashow` plays a bot fight with a camera director (render with --write-movie).

var arena: Node3D
var p: CatPlayer
var bot: Dictionary
var cam: Camera3D
var caption: Label
var sub: Label


func _ready() -> void:
	p = arena.player
	bot = p.bot
	if "--arenatest" in OS.get_cmdline_user_args():
		_test.call_deferred()
	else:
		_show.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(t: float) -> void:
	var e := 0.0
	while e < t:
		await get_tree().physics_frame
		e += get_physics_process_delta_time()


func _face(pt: Vector3) -> void:
	var d := pt + Vector3.UP * 0.04 - (p.global_position + Vector3.UP * 0.25)
	bot.yaw = atan2(-d.x, -d.z)
	bot.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.yaw = bot.yaw
	p.orb_yaw = bot.yaw


func _clear_rats() -> void:
	for r in arena.rats:
		if is_instance_valid(r):
			r.queue_free()
	arena.rats.clear()
	await _ticks(2)


func _reset_cat(pos: Vector3) -> void:
	p.mantling = false
	p.clambering = false
	p.climbing = false
	p.dash.cancel()
	p.dash.recover = 0.0
	p.leap_lock = false
	if "stick_armed" in p:
		p.pounce_air = false
		p.stick_armed = false
		p.combat.cancel()
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p._phys_prev = pos
	p.health.heal_full()
	p.health.grace = 0.0
	p.stamina.value = CatStamina.MAX
	p.stamina.winded = false
	bot.move = Vector2.ZERO
	bot.dash = false
	bot.swat = false
	bot.jump = false
	bot.crouch = false


## rat at the origin facing +z (toward the cat in front cases)
func _rat(yaw: float, size := 1.0) -> SoulsRat:
	var r: SoulsRat = arena.spawn_rat(Vector3(0, 0.02, 0), size)
	r.yaw = yaw
	r.rotation.y = yaw
	return r


func _test() -> void:
	var ok := true
	await _ticks(30)
	# A: right in front -> it winds up and bites
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	var r := _rat(PI)     # yaw PI faces +z
	_face(r.global_position)
	var t := 0.0
	var first := -1.0
	while t < 2.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if first < 0.0 and p.health.hits_taken > 0:
			first = t
	print("A in front: hit after %.2f s, health %.0f" % [first, p.health.value])
	ok = ok and first > 0.4 and first < 1.0
	# B: sitting right behind it: it has to turn round first
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.38))
	var h0 := p.health.hits_taken
	r = _rat(0.0)          # facing -z, cat behind at +z
	t = 0.0
	first = -1.0
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if first < 0.0 and p.health.hits_taken > h0:
			first = t
	print("B behind (cat sits still): first hit after %.2f s (it turns round first)" % first)
	ok = ok and (first < 0.0 or first > 1.2)
	# C: circling it at a trot: it never gets its face on you
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.6))
	h0 = p.health.hits_taken
	r = _rat(PI)
	var ang := 0.0
	var winds := 0
	var was := false
	t = 0.0
	while t < 5.0:
		var dt := get_physics_process_delta_time()
		ang += 3.2 / 0.6 * dt
		var pos := Vector3(sin(ang) * 0.6, 0.02, cos(ang) * 0.6)
		p.velocity = (pos - p.global_position) / maxf(dt, 0.001)
		p.velocity.y = 0.0
		p.global_position = pos
		await get_tree().physics_frame
		t += dt
		if r.state == SoulsRat.WINDUP and not was:
			winds += 1
		was = r.state == SoulsRat.WINDUP
	print("C circling at a trot for 5 s: %d hits, %d wind ups" % [p.health.hits_taken - h0, winds])
	ok = ok and p.health.hits_taken - h0 == 0
	# D: dodge the bite (backstep just before the lunge): i-frames eat it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.45))
	h0 = p.health.hits_taken
	var d0 := p.health.hits_dodged
	r = _rat(PI)
	_face(r.global_position)
	t = 0.0
	var dodged := false
	while t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not dodged and r.state == SoulsRat.WINDUP and r.st_t > r.windup_t - 0.1:
			bot.move = Vector2(0, 1)     # dart straight into its face: only the i-frames save you
			bot.dash = true
			dodged = true
		else:
			bot.dash = false
		if r.state == SoulsRat.RECOVER:
			break
	bot.move = Vector2.ZERO
	print("D dart into the bite: %d hits, %d went through i-frames, dist at bite %.2f m" % [p.health.hits_taken - h0, p.health.hits_dodged - d0, p.global_position.distance_to(r.global_position)])
	ok = ok and p.health.hits_taken - h0 == 0
	# E: swat from the front vs from behind
	p.log_events = OS.has_environment("ARENA_DBG")
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.36))
	r = _rat(PI)
	r.state = SoulsRat.RECOVER       # hold still for the swat
	r.st_t = -5.0
	_face(r.global_position)
	await _ticks(3)
	if OS.has_environment("ARENA_DBG"):
		print("  E1 pre: cat %s target %s  prey %s  eye %s  look %s  rat %s  bot %s" % [p.global_position, str(p._paw_target(CatPlayer.SWAT_RANGE, 0.5)), str(r.is_in_group("prey")), p._eye_pos(), p._look_dir(), r.global_position, str(bot)])
	bot.swat = true
	await _ticks(2)
	bot.swat = false
	await _secs(0.3)
	var front_dmg := r.max_hp - r.hp
	print("E1 swat from the front: %.0f damage, state %d" % [front_dmg, r.state])
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.36))
	r = _rat(0.0)                    # back to the cat
	r.state = SoulsRat.RECOVER
	r.st_t = -5.0
	_face(r.global_position)
	await _ticks(3)
	if OS.has_environment("ARENA_DBG"):
		print("  E2 pre: cat %s target %s  rat %s st %d" % [p.global_position, str(p._paw_target(CatPlayer.SWAT_RANGE, 0.5)), r.global_position, r.state])
	bot.swat = true
	await _ticks(2)
	bot.swat = false
	await _secs(0.25)
	var back_dmg := r.max_hp - r.hp
	print("E2 swat from behind: %.0f damage, staggered %s" % [back_dmg, str(r.state == SoulsRat.STAGGER)])
	ok = ok and front_dmg == 1.0 and back_dmg == 2.0 and r.state == SoulsRat.STAGGER
	# F: kill it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.36))
	r = _rat(0.0)
	var killed := [false]
	r.killed.connect(func(_x): killed[0] = true)
	for k in 3:
		r.state = SoulsRat.RECOVER
		r.st_t = -5.0
		r.yaw = 0.0
		_face(r.global_position)
		bot.swat = true
		await _ticks(2)
		bot.swat = false
		await _secs(0.45)
	print("F three backstabs: killed %s (hp %.0f)" % [str(killed[0]), r.hp])
	ok = ok and killed[0]
	# G: the big one hits harder
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.62))
	r = _rat(PI, 1.6)
	_face(r.global_position)
	var hv0 := p.health.value
	await _secs(2.0)
	print("G brute bite: %.0f damage (wind up %.2f s)" % [hv0 - p.health.value, r.windup_t])
	# H: losing all health takes a life
	p.health.lives = 9
	p.health.value = 10.0
	p.health.grace = 0.0
	var died := [false]
	p.health.died.connect(func(_l): died[0] = true)
	await _secs(0.6)
	p.health.damage(20.0, Vector3.ZERO)
	print("H out of health: died %s, lives %d" % [str(died[0]), p.health.lives])
	ok = ok and died[0] and p.health.lives == 8
	print("ARENATEST ", "PASS" if ok else "FAIL")
	get_tree().quit()


# ---------------------------------------------------------------- preview fight

func _say(a: String, b := "") -> void:
	caption.text = a
	sub.text = b


func _labels() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	caption = Label.new()
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_left = 36
	caption.offset_top = -120
	caption.add_theme_font_size_override("font_size", 34)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(caption)
	sub = Label.new()
	sub.anchor_top = 1.0
	sub.anchor_bottom = 1.0
	sub.offset_left = 38
	sub.offset_top = -72
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	layer.add_child(sub)


var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO


func _cam_to(pos: Vector3, look: Vector3, dt: float, rate := 4.0) -> void:
	_cam_pos = _cam_pos.lerp(pos, 1.0 - exp(-rate * dt))
	_cam_look = _cam_look.lerp(look, 1.0 - exp(-rate * 1.5 * dt))
	cam.global_position = _cam_pos
	cam.look_at(_cam_look, Vector3.UP)


func _show() -> void:
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
	# 1: the pit
	_reset_cat(arena.spawn)
	_say("the rat pit", "f10 from the house")
	var t := 0.0
	_cam_pos = Vector3(1.5, 3.2, 5.0)
	_cam_look = Vector3.ZERO
	while t < 3.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var a := 0.3 + t * 0.15
		_cam_to(Vector3(sin(a) * 5.2, 3.2 - t * 0.35, cos(a) * 5.2), Vector3(0, 0.2, 0), dt, 10.0)
	# 2: rat gait, side on, slow-mo
	await _clear_rats()
	_reset_cat(Vector3(-2.5, 0.02, 3.5))
	var r: SoulsRat = arena.spawn_rat(Vector3(2.5, 0.02, -2.0), 1.0)
	_say("rat trot, slow-mo", "diagonal pairs, hunched back, knees forward, long flat hind feet, tail low")
	Engine.time_scale = 0.35
	t = 0.0
	_cam_pos = r.global_position + Vector3(0.8, 0.25, 0.5)
	while t < 2.2:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var rp := r.global_position
		var side := Vector3(cos(r.yaw), 0, -sin(r.yaw))
		_cam_to(rp + side * 0.85 + Vector3(0, 0.18, 0), rp + Vector3(0, 0.08, 0), dt, 14.0)
	Engine.time_scale = 1.0
	# 3: the tell + the bite, taken on the chin
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	r = _rat(PI)
	_face(r.global_position)
	_say("it can only bite what's in front", "rears back, jaw open (the tell), then the lunge. take it and you lose a chunk")
	Engine.time_scale = 0.5
	t = 0.0
	_cam_pos = Vector3(1.0, 0.4, 0.25)
	while t < 1.6:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		_cam_to(Vector3(0.9, 0.35, 0.3), Vector3(0, 0.1, 0.25), dt, 8.0)
	Engine.time_scale = 1.0
	# 4: dodge through it
	await _clear_rats()
	_reset_cat(Vector3(0, 0.02, 0.5))
	r = _rat(PI)
	_face(r.global_position)
	_say("dodge through the bite", "i-frames from the push off: the snap goes right through")
	Engine.time_scale = 0.5
	t = 0.0
	var dodged := false
	while t < 1.7:
		if not dodged and r.state == SoulsRat.WINDUP and r.st_t > r.windup_t - 0.09:
			bot.move = Vector2(1, 0)
			bot.dash = true
			dodged = true
		else:
			bot.dash = false
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if dodged and p.dash.state == CatDash.IDLE:
			bot.move = Vector2.ZERO
		_cam_to(Vector3(0.9, 0.38, 0.3), Vector3(0.1, 0.1, 0.25), dt, 8.0)
	Engine.time_scale = 1.0
	# 5: a real fight: wave 2
	await _clear_rats()
	_reset_cat(arena.spawn)
	arena._start_wave(1)
	_say("circle, bait, punish from behind", "backstabs do double damage and stagger it")
	await _fight(26.0)
	Engine.time_scale = 1.0
	get_tree().quit()


## a simple bot that plays the rats the way you're meant to
func _fight(dur: float) -> void:
	var t := 0.0
	var swat_cd := 0.0
	var dodge_side := 1.0
	_cam_pos = p.global_position + Vector3(0, 2.2, 2.4)
	var shown_sub := 0.0
	while t < dur:
		var dt := get_physics_process_delta_time()
		t += dt
		swat_cd -= dt
		shown_sub += dt
		if shown_sub > 6.0:
			_say("")
		bot.dash = false
		bot.swat = false
		# nearest live rat
		var r: SoulsRat = null
		var best := 99.0
		for x in arena.rats:
			if is_instance_valid(x) and x.alive():
				var d: float = x.global_position.distance_to(p.global_position)
				if d < best:
					best = d
					r = x
		if r == null:
			_say("wave cleared")
			bot.move = Vector2.ZERO
		else:
			var rp := r.global_position
			var rf := Vector3(-sin(r.yaw), 0, -cos(r.yaw))
			var to_cat := p.global_position - rp
			to_cat.y = 0.0
			var in_front := to_cat.normalized().dot(rf) > 0.55
			var biting := false
			for x in arena.rats:
				if is_instance_valid(x) and x.alive() and x.state == SoulsRat.WINDUP and x.st_t > x.windup_t - 0.12 and x.global_position.distance_to(p.global_position) < 0.9:
					var xf: Vector3 = Vector3(-sin(x.yaw), 0, -cos(x.yaw))
					var tc: Vector3 = p.global_position - x.global_position
					tc.y = 0.0
					if tc.normalized().dot(xf) > 0.5:
						biting = true
			if biting and p.dash.state == CatDash.IDLE and p.dash.recover <= 0.0:
				_face(rp)
				bot.move = Vector2(dodge_side, 0)
				bot.dash = true
				dodge_side = -dodge_side
			elif p.dash.busy():
				pass
			elif not in_front and best < 0.5:
				# behind or beside it: turn on it and swat
				_face(rp)
				bot.move = Vector2.ZERO
				if swat_cd <= 0.0 and p.stamina.value > 10.0:
					bot.swat = true
					swat_cd = 0.32
			else:
				# run round to its back: aim for a point behind it, curving round its side
				var back := rp - rf * 0.38
				var side := Vector3(rf.z, 0, -rf.x)
				if side.dot(to_cat) < 0.0:
					side = -side
				var goal := back + side * (0.5 if in_front else 0.15)
				var d := goal - p.global_position
				d.y = 0.0
				bot.yaw = atan2(-d.x, -d.z)
				bot.pitch = -0.2
				p.orb_yaw = bot.yaw
				bot.move = Vector2(0, 1) if d.length() > 0.08 else Vector2.ZERO
		await get_tree().physics_frame
		# camera: behind and above the cat, framing the rat
		var focus := p.global_position
		if r:
			focus = focus.lerp(r.global_position, 0.4)
		var bk := Vector3(sin(p.orb_yaw), 0, cos(p.orb_yaw))
		_cam_to(focus + bk * 1.5 + Vector3(0.6, 1.1, 0), focus + Vector3(0, 0.08, 0), dt, 2.5)
