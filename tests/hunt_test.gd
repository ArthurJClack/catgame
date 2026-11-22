extends SceneTree
## forest hunting (hunt_prey.gd + net/prey_sync.gd): mice and rats forage round their dens,
## a crouched cat that keeps still isn't noticed, a cat that charges in is (they bolt for a hole and
## vanish down it, then peek and come back out), a stalk + pounce catches, the catch goes in the
## mouth and runs off when dropped, and the online sync mirrors an authority's prey onto puppets.
##   godot --headless --path . --script res://tests/hunt_test.gd

var bad := 0
var p: CatPlayer
var bot := {}


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _secs(t: float) -> void:
	var e := 0.0
	while e < t:
		await physics_frame
		e += 1.0 / float(Engine.physics_ticks_per_second)


func _prey() -> Array:
	return HuntPrey.all.duplicate()


func _place(pos: Vector3, look_at: Vector3) -> void:
	p.climbing = false
	p.mantling = false
	p.clambering = false
	p.leap_lock = false
	p.combat.cancel()
	p.pounce_air = false
	p.stick_armed = false
	pos.y = ForestLevel.height(pos.x, pos.z) + 0.03
	p.global_position = pos
	p._phys_prev = pos
	p._phys_curr = pos
	p.velocity = Vector3.ZERO
	var d := look_at + Vector3.UP * 0.03 - (pos + Vector3.UP * 0.25)
	bot.yaw = atan2(-d.x, -d.z)
	bot.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.yaw = bot.yaw
	p.orb_yaw = bot.yaw
	bot.move = Vector2.ZERO
	bot.crouch = false
	bot.canter = false
	bot.sprint = false
	bot.pounce = false
	bot.jump = false


## everyone calm, out of their holes, eating at home (so each check starts the same)
func _calm_all() -> void:
	for q in _prey():
		var h: HuntPrey = q
		h.caught = false
		h.aware = 0.0
		h.threat = Vector3.INF
		h._react = -1.0
		h.global_position = h._on_ground(h.home)
		h._go(HuntPrey.FORAGE, 3.0)
		h._nibble = true


func _far_away() -> void:
	_place(Vector3(30.0, 0, 30.0), Vector3(30.0, 0, 29.0))


func _run() -> void:
	Engine.set_meta("title_done", true)
	GameSettings.s("hints", false)
	change_scene_to_file("res://forest.tscn")
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.get("player") == null) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	p = current_scene.get("player")
	p.bot = bot
	await _secs(0.5)
	var all := _prey()
	var mice := all.filter(func(h): return h.kind == "mouse")
	var rats := all.filter(func(h): return h.kind == "rat")
	_ok(mice.size() == 8 and rats.size() == 5, "forest has 8 mice + 5 rats (%d + %d)" % [mice.size(), rats.size()])
	var grounded := true
	for h in all:
		grounded = grounded and absf(h.global_position.y - ForestLevel.height(h.global_position.x, h.global_position.z)) < 0.02 and h.is_in_group("prey") and h.hides.size() >= 2
	_ok(grounded, "all on the ground, huntable, with at least 2 holes each")
	_ok(PreySync.me != null and PreySync.me.is_inside_tree(), "prey sync node made")

	# A: left alone they forage: move about, stay near home
	_far_away()
	var start := all.map(func(h): return h.global_position)
	await _secs(6.0)
	var moved := 0
	var near_home := true
	for i in all.size():
		var h: HuntPrey = all[i]
		if h.global_position.distance_to(start[i]) > 0.15:
			moved += 1
		near_home = near_home and Vector2(h.global_position.x - h.home.x, h.global_position.z - h.home.z).length() < float(h._sp.range) + 1.0
	_ok(moved >= 8 and near_home, "A forage: %d / %d moved, all near home %s" % [moved, all.size(), str(near_home)])

	# B: a crouched cat that keeps still 2 m off isn't noticed
	_calm_all()
	var m: HuntPrey = mice[0]
	var at := m.global_position + Vector3(2.0, 0, 0.6)
	_place(at, m.global_position)
	bot.crouch = true
	await _secs(4.0)
	print("  B still crouched cat: mouse state %s aware %.2f heard %.2f seen %.2f" % [HuntPrey.STATE_NAMES[m.state], m.aware, m.heard, m.seen])
	_ok(m.state in [HuntPrey.FORAGE, HuntPrey.ALERT] and m.aware < HuntPrey.FLEE_AT, "B still crouched cat 2 m off: mouse keeps eating (%s, aware %.2f)" % [HuntPrey.STATE_NAMES[m.state], m.aware])

	# C: cantering at it: it bolts for a hole and goes down it, out of the prey group
	_far_away()
	_calm_all()
	await _secs(0.3)
	m = mice[1]
	_place(m.global_position + Vector3(0, 0, 5.0), m.global_position)
	bot.move = Vector2(0, 1)
	bot.canter = true
	var fled := false
	var hid := false
	var tt := 0.0
	while tt < 5.0:
		await physics_frame
		tt += 1.0 / 60.0
		var d := Vector2(p.global_position.x - m.global_position.x, p.global_position.z - m.global_position.z).length()
		if d < 0.5:
			bot.move = Vector2.ZERO
		fled = fled or m.state == HuntPrey.FLEE
		if m.state == HuntPrey.HIDDEN:
			hid = true
			break
	bot.move = Vector2.ZERO
	bot.canter = false
	_ok(fled and hid and not m.is_in_group("prey") and not m.visible, "C cantering cat: mouse bolts (%s) and dives down a hole (%s) after %.1f s" % [str(fled), str(hid), tt])
	# ... then later peeks out and comes back out once the coast is clear
	_far_away()
	m.state_t = 0.1
	var peeked := false
	tt = 0.0
	while tt < 6.0:
		await physics_frame
		tt += 1.0 / 60.0
		peeked = peeked or m.state == HuntPrey.PEEK
		if m.state == HuntPrey.FORAGE:
			break
	_ok(peeked and m.state == HuntPrey.FORAGE and m.is_in_group("prey"), "C2 peeks out of the hole, then comes out to forage")

	# D: stalk + pounce: crouched 1.4 m off a feeding mouse / rat, hold space, let go -> caught
	var caught := 0
	var tries := 0
	for h in [mice[2], mice[3], rats[2], mice[5], rats[3]]:
		tries += 1
		_far_away()
		await _secs(0.1)
		_calm_all()
		if is_instance_valid(p.carried):
			p._drop_carried()
		await _secs(0.2)
		var q: HuntPrey = h
		q._nibble = true
		q.state_t = 6.0
		# like a player would: creep round to a side with a clear line, crosshair on it
		var lined := false
		for dir in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			_place(q.global_position + dir.normalized() * 1.4, q.global_position)
			bot.crouch = true
			q.global_position = q._on_ground(q.home)
			q._go(HuntPrey.FORAGE, 6.0)
			q._nibble = true
			q.aware = 0.0
			await _secs(0.5)
			for k in 4:
				var dd := q.global_position + Vector3.UP * 0.02 - p._aim_pos()
				var want := atan2(dd.y, Vector2(dd.x, dd.z).length())
				var lk := p._look_dir()
				var have := asin(clampf(lk.y, -1.0, 1.0))
				bot.pitch += want - have
				await _secs(0.08)
			if p.combat._solve(1.0).get("kind", "") == "prey":
				lined = true
				break
		if not lined:
			print("  D no clear pounce line onto the %s" % q.kind)
		var a0 := q.aware
		bot.pounce = true
		await _secs(0.7)
		var qp := q.global_position
		print("    at launch: %s aware %.2f -> %.2f heard %.2f seen %.2f charge %.2f kind %s aim %.2f m off it" % [HuntPrey.STATE_NAMES[q.state], a0, q.aware, q.heard, q.seen, p.charge, p.combat.pounce.get("kind", "?"), Vector2(p.combat.pounce.point.x - qp.x, p.combat.pounce.point.z - qp.z).length() if p.combat.pounce.has("point") else -1.0])
		bot.pounce = false
		await _secs(1.2)
		var got := p.carried == q
		print("  D pounce on %s: %s (state %s, cat %.2f m from it)" % [q.kind, "caught" if got else "missed", HuntPrey.STATE_NAMES[q.state], p.global_position.distance_to(q.global_position)])
		if got:
			caught += 1
		bot.crouch = false
	_ok(caught >= 3, "D stalk + pounce catches %d / %d" % [caught, tries])

	# E: in the mouth it wriggles and stays put; dropped, it runs for a hole
	_far_away()
	_calm_all()
	m = mice[4]
	p._catch(m)
	await _secs(0.5)
	_ok(m.caught and m.state == HuntPrey.CAUGHT and p.carried == m, "E caught mouse goes in the mouth")
	p._drop_carried()
	await _secs(0.3)
	_ok(not m.caught and m.state in [HuntPrey.FLEE, HuntPrey.HIDDEN], "E dropped: it bolts (%s)" % HuntPrey.STATE_NAMES[m.state])

	# F: a bolting rat squeals and its neighbours hear it
	_far_away()
	_calm_all()
	await _secs(0.2)
	var r0: HuntPrey = rats[0]
	var r1: HuntPrey = rats[1]
	r0.threat = r0.global_position + Vector3(1, 0, 0)
	r0._bolt(true)
	await _secs(0.1)
	_ok(r1.aware >= HuntPrey.ALERT_AT, "F rat squeal alerts the colony (neighbour aware %.2f)" % r1.aware)

	# G: online: authority snapshot -> puppets glide to it; a puppet catch sends a claim the
	# authority turns into "taken" for everyone
	_far_away()
	_calm_all()
	var ps: PreySync = PreySync.me
	ps.forced = true
	ps.authority = true
	var sent: Array = []
	ps.out = func(b: PackedByteArray) -> void: sent.append(b)
	await _secs(0.3)
	_ok(sent.size() >= 2, "G authority sends snapshots (%d in 0.3 s)" % sent.size())
	var snap: PackedByteArray = ps.snapshot()
	var truth := all.map(func(h): return h.global_position)
	ps.authority = false
	await _secs(0.05)
	for h in all:
		h.global_position += Vector3(0.6, 0, -0.4)   # puppets drifted
	ps.receive(snap)
	await _secs(0.5)
	var err := 0.0
	var puppets := true
	for i in all.size():
		var h: HuntPrey = all[i]
		puppets = puppets and h.puppet
		err = maxf(err, Vector2(h.global_position.x - truth[i].x, h.global_position.z - truth[i].z).length())
	_ok(puppets and err < 0.05, "G puppets glide onto the authority's prey (worst %.3f m)" % err)
	sent.clear()
	var pm: HuntPrey = mice[6]
	pm.pinned()
	_ok(sent.size() == 1 and pm.state == HuntPrey.CAUGHT, "G puppet catch: in my mouth now + one claim sent")
	var claim: PackedByteArray = sent[0]
	pm.caught = false
	pm._go(HuntPrey.FORAGE, 1.0)
	ps.authority = true
	ps.receive(claim)
	_ok(pm.state == HuntPrey.TAKEN and not pm.is_in_group("prey"), "G authority hears the claim: taken for everyone")
	var snap2 := ps.snapshot()
	ps.authority = false
	pm._go(HuntPrey.FORAGE, 1.0)
	pm.add_to_group("prey")
	ps._hold.clear()
	ps.receive(snap2)
	_ok(pm.state == HuntPrey.TAKEN, "G others see it gone (in that cat's mouth)")
	ps.forced = false
	ps.out = Callable()

	print("HUNTTEST %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad > 0 else 0)
