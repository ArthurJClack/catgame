class_name PuzzleTest
extends Node
## checks the first puzzle milestone with the real controller (puzzles.gd).
##   godot --headless --path . res://main.tscn -- --puzzletest    (knock it off, sunbeam, gift, treats, rope, chicks)
##   godot --headless --path . res://arena.tscn -- --puzzletest   (lanterns: swat off a pillar, smash a rat)
## prints each check and PUZZLETEST PASS / FAIL, then quits.

var z: Puzzles
var p: CatPlayer
var bot := {}


func _ready() -> void:
	p = z.player
	bot = {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0}
	p.bot = bot
	if "--puzzleshow" in OS.get_cmdline_user_args():
		p.set_view.call_deferred(1)
	_run.call_deferred()


func _run() -> void:
	await _ticks(20)
	var ok: bool
	if z.arena:
		ok = await _pit()
	elif z.dog:
		ok = await _docks()
	else:
		ok = await _farm()
	print("PUZZLETEST " + ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(s: float) -> void:
	var e := 0.0
	while e < s:
		await get_tree().physics_frame
		e += get_physics_process_delta_time()


func _put(pos: Vector3, look_at: Vector3) -> void:
	p.velocity = Vector3.ZERO
	p.global_position = pos
	var d := look_at - (pos + Vector3.UP * 0.25)
	bot.yaw = atan2(-d.x, -d.z)
	bot.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.yaw = bot.yaw
	p.orb_yaw = bot.yaw


func _swat(right := false) -> void:
	var k := "paw_r" if right else "paw_l"
	bot[k] = true
	await _ticks(3)
	bot[k] = false


func _farm() -> bool:
	var ok := true
	# A: knock it off. stand on the cabinet top beside the bag, swat it toward the room
	var b := z.bag
	var bp := b.global_position
	var tries := 0
	while not z.bag_burst and tries < 4:
		_put(Vector3(bp.x + 0.22, 2.21, -3.97), b.global_position)
		await _ticks(30)
		await _swat(tries % 2 == 1)
		await _secs(2.0)
		tries += 1
		bp = b.global_position
	print("A knock it off: bag burst %s after %d swat(s), peak %.2f, treats on floor %d" % [str(z.bag_burst), tries, z.bag_peak, z.treats.size()])
	ok = ok and z.bag_burst and z.treats.size() >= 5
	# B: eat the spilled treats by walking over them
	var n0 := Puzzles.treats_eaten
	for f in z.treats.duplicate():
		if is_instance_valid(f):
			_put(Vector3(f.global_position.x, 0.02, f.global_position.z), f.global_position + Vector3(0, 0, -1))
			await _ticks(4)
	var ate := Puzzles.treats_eaten - n0
	print("B treats: ate %d, left %d" % [ate, z.treats.size()])
	ok = ok and ate >= 5 and z.treats.is_empty()
	# C: sunbeam: sit on the beam spot, nothing for a moving cat
	_put(z.sun_spot + Vector3(0, 0.02, 0), z.sun_spot + Vector3(-1, 0, 0))
	await _secs(SUN_WAIT)
	print("C sunbeam: solved %s after %.1f s (sun_t %.2f, cat at %s)" % [str(z.sun_done), SUN_WAIT, z.sun_t, str(p.global_position)])
	ok = ok and z.sun_done
	# D: gift: catch a toy mouse, carry it to the doormat, drop it (e)
	var mouse: Node3D = null
	for m in get_tree().get_nodes_in_group("prey"):
		if m is ToyMouse:
			mouse = m
			break
	if mouse == null:
		print("D gift: no toy mouse in the level")
		return false
	p.call("_catch", mouse)
	_put(z.mat_pos + Vector3(0, 0.03, -0.15), z.mat_pos + Vector3(0, 0, 1.0))
	await _ticks(10)
	_put(z.mat_pos + Vector3(0, 0.03, -0.15), z.mat_pos + Vector3(0, 0, 1.0))
	bot.drop = true
	await _ticks(3)
	bot.drop = false
	await _ticks(5)
	var g1 := z.gifts
	var bowl := z.treats.size()
	# same mouse again doesn't count twice
	p.call("_catch", mouse)
	await _ticks(5)
	_put(z.mat_pos + Vector3(0, 0.03, -0.15), z.mat_pos + Vector3(0, 0, 1.0))
	p.call("_drop_carried")
	await _ticks(5)
	print("D gift: gifts %d (then %d after re-gifting the same mouse), treats in bowl %d" % [g1, z.gifts, bowl])
	ok = ok and g1 == 1 and z.gifts == 1 and bowl >= 3
	# E: pull the string: batting it only swings it, hooking + dragging it back drops the bale
	var r: PullString = z.rope
	var tl: Vector3 = r.rest_tail()
	var stand: Vector3 = Vector3(tl.x, 0.02, tl.z - 0.32)
	_put(stand, tl + Vector3(0, 0.12, 0))
	await _ticks(20)
	await _swat()
	await _secs(1.0)
	var swung: int = r.tugs
	tries = 0
	while not r.falling and tries < 5:
		_put(stand, tl + Vector3(0, 0.12, 0))
		await _ticks(10)
		p.call("_claw_start", 0)
		var got: bool = r.hooked()
		for k in 24:
			_put(stand + Vector3(0, 0, -0.016 * k), tl + Vector3(0, 0.05, 0))
			await _ticks(3)
		print("E pull: try %d hooked %s tugs %d tail off %.2f" % [tries, str(got), r.tugs, r.tail().distance_to(tl)])
		p.call("_claw_release")
		await _secs(1.0)
		tries += 1
	await _secs(3.5)
	print("E pull string: tugs %d (batting alone gave %d), bale fell %s, solved %s, bale at %s, treats on floor %d" % [r.tugs, swung, str(r.falling), str(r.done), str(r.bale.global_position.snapped(Vector3.ONE * 0.01)), z.treats.size()])
	ok = ok and swung == 0 and r.done and r.bale.global_position.y < 0.5 and z.treats.size() >= 5
	ok = (await _herd()) and ok
	print("   solved: %s" % str(Puzzles.solved))
	return ok


## F: herd the chicks. first gallop at them (they should scatter), then walk them in one by one
## the way a person would play it: get behind a chick, on the side away from where it should go,
## and close in slowly. only ever walking pace (the cat is moved, never faster than 1.1 m/s)
func _herd() -> bool:
	var h: HerdChicks = z.herd
	var c0: Vector3 = h.chicks[1].global_position
	_put(c0 + Vector3(-4.5, 0.02, 0), c0)
	await _ticks(10)
	bot.move = Vector2(0, 1)
	bot.sprint = true
	await _secs(1.6)
	bot.move = Vector2.ZERO
	bot.sprint = false
	await _secs(1.0)
	var scattered: int = h.panics
	print("F herd: galloping at them made %d chick(s) bolt" % scattered)
	var gap := Vector3(HerdChicks.PEN.position.x - 0.9, 0, (HerdChicks.GAP_Z.x + HerdChicks.GAP_Z.y) * 0.5)
	var cat := p.global_position
	cat.y = 0.02
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t := 0.0
	while not h.done and t < 240.0:
		# the loose chick closest to the gap
		var best: CharacterBody3D = null
		var bd := 1e9
		for c in h.chicks:
			if not h.in_pen(c.global_position):
				var d := c.global_position.distance_to(gap)
				if d < bd:
					bd = d
					best = c
		if best == null:
			await _ticks(1)
			t += dt
			continue
		var cp := best.global_position
		cp.y = 0
		# lined up with the gap: push it straight in, else push it to the spot in front of the gap
		var aligned := absf(cp.z - gap.z) < 0.35 and cp.x > gap.x - 0.6 and cp.x < HerdChicks.PEN.position.x + 0.3
		var target: Vector3 = h.grain if aligned else gap
		var back := (cp - target)
		back.y = 0
		back = back.normalized()
		var spot := cp + back * 1.15
		var flat := Vector3(cat.x, 0, cat.z)
		var rel := flat - cp
		var want: Vector3
		if rel.length() < 2.0 and rel.normalized().dot(back) < 0.6:
			# wrong side of it: circle round outside its flight zone
			var tang := Vector3(-rel.z, 0, rel.x).normalized()
			if tang.dot(back) < 0.0:
				tang = -tang
			want = cp + (rel.normalized() * 2.0 + tang * 0.9).normalized() * 2.0
		else:
			want = spot
		var step := (want - flat)
		step.y = 0
		var sp := 1.1 * dt
		if step.length() > sp:
			step = step.normalized() * sp
		cat += step
		_put(cat, Vector3(cp.x, 0.1, cp.z))
		await _ticks(1)
		t += dt
		if int(t / dt) % 600 == 0:
			print("   t %.0f s: %d/5 in the pen, cat %s chick %s" % [t, h.inside(), str(cat.snapped(Vector3.ONE * 0.1)), str(cp.snapped(Vector3.ONE * 0.1))])
	var n_in: int = h.inside()
	var treats_before := z.treats.size()
	await _secs(2.0)
	var gate_shut: bool = absf(h.gate.rotation.y) < 0.05
	print("F herd the chicks: %d/5 in after %.0f s walking them, solved %s, gate shut %s, treats out %d" % [n_in, t, str(h.done), str(gate_shut), treats_before])
	return scattered >= 2 and h.done and gate_shut and treats_before >= 5


const SUN_WAIT := 2.2


func _drive(yaw: float, secs: float, keys := {}) -> void:
	bot.yaw = yaw
	bot.move = Vector2(0, 1)
	for k in keys:
		bot[k] = keys[k]
	await _secs(secs)
	bot.move = Vector2.ZERO
	for k in keys:
		bot[k] = false


## G: quiet paws (pier 9). gallop past the sleeping dog: it wakes, barks, comes for you. get well
## away and it lies back down. then stalk in, eat from its bowl, stalk out: it sleeps through it
func _docks() -> bool:
	var q: QuietPaws = z.dog
	var ok := true
	await _secs(1.0)
	_put(Vector3(3.0, 0.02, 13.6), Vector3(10, 0.2, 13.6))
	await _ticks(10)
	await _drive(-PI / 2, 1.6, {"sprint": true})
	var woke := q.awake
	print("G loud: galloping past it: awake %s (max alert %.2f, noise %.2f)" % [str(woke), q.max_alert, q.noise])
	ok = ok and woke
	# run off and wait it out
	_put(Vector3(-2.0, 0.02, 18.0), Vector3(-3, 0.2, 18))
	var tt := 0.0
	while q.awake and tt < 20.0:
		await _secs(0.5)
		tt += 0.5
	await _secs(3.5)
	print("G settles: back asleep %s after %.1f s, alert %.2f, dog at %s" % [str(not q.awake), tt, q.alert, str(q.dog.position.snapped(Vector3.ONE * 0.01))])
	ok = ok and not q.awake
	# trot (no crouch) straight to the bowl the same way: that's enough to wake it
	_put(Vector3(5.0, 0.02, 11.95), q.bowl)
	await _ticks(10)
	var w1 := q.wakes
	tt = 0.0
	bot.move = Vector2(0, 1)
	while q.wakes == w1 and tt < 3.0:
		var dd := q.bowl - p.global_position
		bot.yaw = atan2(-dd.x, -dd.z)
		bot.move = Vector2(0, 1) if Vector2(dd.x, dd.z).length() > 0.25 else Vector2.ZERO
		await _ticks(2)
		tt += 2.0 / Engine.physics_ticks_per_second
	bot.move = Vector2.ZERO
	print("G trot: trotting up to the bowl woke it %s (%.1f s in)" % [str(q.wakes > w1), tt])
	ok = ok and q.wakes > w1
	_put(Vector3(-2.0, 0.02, 18.0), Vector3(-3, 0.2, 18))
	tt = 0.0
	while q.awake and tt < 20.0:
		await _secs(0.5)
		tt += 0.5
	await _secs(3.5)
	# sneak: stalk in along the hut wall from the west, eat, stalk back out
	var w0 := q.wakes
	_put(Vector3(5.6, 0.02, 11.95), q.bowl)
	await _ticks(10)
	q.reset_max()
	bot.crouch = true
	await _secs(0.6)
	bot.yaw = -PI / 2
	bot.move = Vector2(0, 1)
	tt = 0.0
	while Vector2(p.global_position.x - q.bowl.x, p.global_position.z - q.bowl.z).length() > 0.2 and tt < 8.0:
		await _ticks(2)
		tt += 2.0 / Engine.physics_ticks_per_second
		var d := q.bowl - p.global_position
		bot.yaw = atan2(-d.x, -d.z)
	bot.move = Vector2.ZERO
	print("   stalked to the bowl in %.1f s, crouch %.2f, alert %.2f" % [tt, p.crouch_amt, q.alert])
	await _secs(QuietPaws.EAT_T + 0.8)
	var ate := q.done
	await _drive(PI / 2, 2.5, {"crouch": true})
	bot.crouch = false
	print("G quiet paws: ate the lot %s, woke it %d time(s) sneaking (max alert %.2f), solved %s" % [str(ate), q.wakes - w0, q.max_alert, str(Puzzles.solved.has("quiet_paws"))])
	ok = ok and ate and q.wakes == w0 and q.max_alert < QuietPaws.WAKE
	return ok


func _pit() -> bool:
	var ok := true
	var arena := z.arena
	p.stamina.infinite = true
	p.health.grace = 99.0
	# pillars got climbable
	var climb := 0
	for c in arena.get_children():
		if c is StaticBody3D and c.is_in_group("climbable"):
			climb += 1
	print("E pillars climbable: %d" % climb)
	ok = ok and climb >= 4
	# F: lantern on the 1.3 m pillar. a rat stands below, the cat swats the lantern off onto it
	await _ticks(10)
	var lan: RigidBody3D = null
	for l in z.lanterns:
		if absf(l.global_position.y - 1.4) < 0.1:
			lan = l
	if lan == null:
		print("F no lantern on the low pillar")
		return false
	var top := lan.global_position - Vector3(0, 0.1, 0)
	var out := Vector3(top.x, 0, top.z).normalized()    # pillar centre -> outwards
	var pc := top + out * 0.12                          # pillar centre top
	var rats: Array = arena.get("rats")
	var rat: SoulsRat = null
	for r in rats:
		if is_instance_valid(r):
			rat = r
	if rat == null:
		rat = arena.call("spawn_rat", Vector3.ZERO)
	var side := out.cross(Vector3.UP).normalized()
	var hp0 := rat.hp
	var smashed := false
	var tries := 0
	while not smashed and tries < 4:
		# cat on the pillar top, behind the lantern, looking over it into the pit
		_put(pc + out * 0.05 + side * 0.18 + Vector3(0, 0.02, 0), lan.global_position)
		await _ticks(30)
		var land := lan.global_position - out * 0.9 - side * 0.4
		land.y = 0.02
		rat.global_position = land
		rat.velocity = Vector3.ZERO
		rat.state = SoulsRat.RECOVER
		rat.st_t = -50.0
		await _swat(tries % 2 == 1)
		var e := 0.0
		while e < 2.0 and is_instance_valid(lan):
			await get_tree().physics_frame
			e += get_physics_process_delta_time()
			if is_instance_valid(rat) and is_instance_valid(lan) and not lan.freeze:
				# keep the rat under the falling lantern (it'd chase the cat otherwise)
				rat.global_position = Vector3(lan.global_position.x, rat.global_position.y, lan.global_position.z) + out * 0.3
		smashed = not is_instance_valid(lan)
		tries += 1
	await _ticks(5)
	var hp1 := rat.hp if is_instance_valid(rat) else -99.0
	print("F lantern: smashed %s after %d swat(s), rat hp %.1f -> %.1f, fires %d" % [str(smashed), tries, hp0, hp1, z.fires.size()])
	ok = ok and smashed and hp1 < hp0 and z.fires.size() == 1
	# G: fire burns out, lanterns come back next wave
	await _secs(Puzzles.FIRE_T + 0.3)
	var n_before := z.lanterns.size()
	arena.set("wave", int(arena.get("wave")) + 1)
	await _ticks(3)
	print("G fire out %s, lanterns %d -> %d after a new wave" % [str(z.fires.is_empty()), n_before, z.lanterns.size()])
	ok = ok and z.fires.is_empty() and z.lanterns.size() == 3
	return ok
