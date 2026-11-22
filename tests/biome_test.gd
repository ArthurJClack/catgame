extends SceneTree
## desert + mountain (scripts/biome/): each level builds, the cat lands on the ground, the way back to
## the farm + wildlife + cat sense points exist, the gullies are walkable without climbing, and all
## six puzzles can be solved (props shoved / the cat placed the way a player would get there).
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/biome_test.gd
## prints ok / FAIL lines, BIOMETEST PASS or FAIL at the end, exit code 0 / 1

var bad := 0


func _initialize() -> void:
	Engine.set_meta("title_done", true)
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		await physics_frame


## waits game seconds (physics ticks), not wall clock: xvfb renders slowly, the sim doesn't skip
func _wait(sec: float, until: Callable) -> bool:
	var n := int(sec * Engine.physics_ticks_per_second)
	for i in n:
		await physics_frame
		if until.call():
			return true
	return until.call()


func _player() -> CatPlayer:
	var p = current_scene.get("player") if current_scene else null
	return p if p is CatPlayer and p.is_inside_tree() else null


func _load(path: String) -> BiomePuzzles:
	change_scene_to_file(path)
	await _wait(600.0, func(): return _player() != null and current_scene.get_node_or_null("Puzzles/BiomePuzzles") != null)
	await _frames(20)
	return current_scene.get_node_or_null("Puzzles/BiomePuzzles") if current_scene else null


func _put(p: CatPlayer, at: Vector3, yaw := 0.0) -> void:
	p.global_position = at
	p._phys_curr = at
	p.velocity = Vector3.ZERO
	p.yaw = yaw
	p.orb_yaw = yaw


func _solved(id: String) -> bool:
	return int(Puzzles.solved.get(id, 0)) > 0


func _common(b: BiomePuzzles, key: String, ids: Array, kinds: Array) -> void:
	var p := _player()
	_ok(b != null, "%s: builds with its puzzles" % key)
	if b == null:
		return
	await _wait(6.0, func(): return p.is_on_floor())
	var gy := BiomeKit.y(p.global_position.x, p.global_position.z)
	_ok(p.is_on_floor() and absf(p.global_position.y - gy) < 0.12, "%s: the cat stands on the ground at the start (%.2f vs %.2f)" % [key, p.global_position.y, gy])
	var exits := 0
	for n in get_nodes_in_group("hub_trigger"):
		if current_scene.is_ancestor_of(n) and n.get_meta("hub_to", "") == "res://main.tscn":
			exits += 1
	_ok(exits == 1, "%s: one way back to the farm" % key)
	for id in ids:
		_ok(Puzzles.LIST.has(id), "%s: %s is in the pause menu list" % [key, id])
		_ok(b.z.sense.points.has(id), "%s: %s has a cat sense point" % [key, id])
	var seen := {}
	for n in get_nodes_in_group("wild"):
		if n is Beast:
			seen[(n as Beast).kind] = int(seen.get((n as Beast).kind, 0)) + 1
	for k in kinds:
		_ok(int(seen.get(k, 0)) > 0, "%s: has %s (%d)" % [key, k, int(seen.get(k, 0))])
	_ok(Hub.DESTS.has(key) and Hub.FENCE_GATES.has(key) and Hub.spawns().has(Hub.DESTS[key].spawn), "%s: farm gate + spawn back" % key)


## bot walks straight `dist` m along yaw from `from`: returns how high it got
func _walk(p: CatPlayer, from: Vector3, yaw: float, sec: float) -> float:
	_put(p, from + Vector3(0, 0.1, 0), yaw)
	p.bot = {"move": Vector2(0, 1), "yaw": yaw, "pitch": -0.1, "canter": true}
	var y0 := p.global_position.y
	var best := y0
	for i in int(sec * Engine.physics_ticks_per_second):
		await physics_frame
		best = maxf(best, p.global_position.y)
	p.bot = {"move": Vector2.ZERO, "yaw": yaw, "pitch": 0.0}
	return best - y0


func _run() -> void:
	# ------------------------------------------------ desert
	var b := await _load("res://desert.tscn")
	await _common(b, "desert", ["windmill", "tumbleweed", "box"], ["snake", "scorpion", "vulture", "lizard", "rabbit", "bird"])
	if b:
		var p := _player()
		p.bot = {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0}
		# windmill: the wedge sits still till shoved off the platform, then the trough fills
		var w0 := b.wedge.global_position
		await _frames(30)
		_ok(b.wedge.global_position.distance_to(w0) < 0.05 and b.stage.windmill == 0, "windmill: wedge sits jammed on the platform")
		b.wedge.sleeping = false
		b.wedge.linear_velocity = Vector3(0.4, 0.5, -2.2)
		_ok(await _wait(12.0, func(): return b.stage.windmill >= 1), "windmill: knocked off -> the wheel turns")
		_ok(await _wait(10.0, func(): return b.pour_t >= 4.0), "windmill: the trough fills")
		var tc: Vector3 = b.mill.trough
		_put(p, tc + Vector3(-0.55, 0.05, 0.0), -PI * 0.5)
		_ok(await _wait(12.0, func(): return _solved("windmill")), "windmill: a drink at the trough = solved")
		# box: in through the window. the cat on the sill walking in drops inside the shack
		var sill: Vector3 = b.shack.sill
		_put(p, sill + Vector3(0.12, 0.08, 0), PI * 0.5)
		p.bot = {"move": Vector2(0, 0.6), "yaw": PI * 0.5, "pitch": 0.0}
		await _wait(2.5, func(): return false)
		p.bot = {"move": Vector2.ZERO, "yaw": PI * 0.5, "pitch": 0.0}
		_ok(p.global_position.x < sill.x - 0.15 and p.global_position.y < sill.y - 0.5, "box: through the window into the shack (%.2f, %.2f)" % [p.global_position.x - sill.x, p.global_position.y - sill.y])
		var bx: Vector3 = b.shack.box
		_put(p, bx + Vector3(0, 0.08, 0), 0.0)
		_ok(await _wait(12.0, func(): return _solved("box")), "box: if it fits, i sits = solved")
		# tumbleweed: they roll down the wash on the wind; the cat drops onto a rolling one
		var moving := await _wait(15.0, func():
			for wd in b.weeds:
				if wd.linear_velocity.length() > 0.8:
					return true
			return false)
		_ok(moving, "tumbleweed: the wind rolls them down the wash")
		var caught := false
		for tries in 30:
			for wd in b.weeds:
				if wd.linear_velocity.length() > 0.8 and not wd.freeze:
					_put(p, wd.global_position + wd.linear_velocity * 0.08 + Vector3(0, 0.35, 0), 0.0)
					break
			if await _wait(0.6, func(): return _solved("tumbleweed")):
				caught = true
				break
		_ok(caught, "tumbleweed: pounced on one rolling = solved")
		_ok(b.net_state().get("mill", false), "desert: net_state reports the running mill")
	# ------------------------------------------------ mountain
	b = await _load("res://mountain.tscn")
	await _common(b, "mountain", ["snowball", "marmot", "summit"], ["goat", "marmot", "pika", "eagle", "bird"])
	if b:
		var p := _player()
		p.bot = {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0}
		# snowball: sits on the cliff lip, shoved off it lands in the drift, the flap opens
		var s0 := b.ball.global_position
		await _frames(30)
		_ok(b.ball.global_position.distance_to(s0) < 0.05, "snowball: sits still on the lip (%.3f)" % b.ball.global_position.distance_to(s0))
		b.ball.sleeping = false
		b.ball.linear_velocity = Vector3(0, 0.6, 2.6)
		_ok(await _wait(15.0, func(): return _solved("snowball")), "snowball: knocked off -> drift bursts = solved")
		var flap := b.hut.flap as Node3D
		_ok(flap != null and (flap.get_child(0) as CollisionShape3D).disabled, "snowball: the cat flap is open")
		# marmot: walk up openly in front of it -> it whistles and dives
		var m := b.sentry
		_ok(m != null and m.state == "sentry", "marmot: the sentry is up on its rock")
		if m:
			_put(p, m.home + Vector3(0, -0.6, 3.5), PI)
			p.bot = {"move": Vector2(0, 1), "yaw": PI, "pitch": 0.0}
			await _wait(3.0, func(): return m.state != "sentry")
			p.bot = {"move": Vector2.ZERO, "yaw": PI, "pitch": 0.0}
			_ok(m.state != "sentry" and not m.startled and not _solved("marmot"), "marmot: seen coming -> whistles + dives (%s)" % m.state)
			_put(p, m.home + Vector3(-8.0, 0, 6.0), 0.0)   # back off: it only peeks out once you're away
			p.global_position.y = BiomeKit.y(p.global_position.x, p.global_position.z) + 0.05
			await _wait(25.0, func(): return m.state == "sentry")
			_ok(m.state == "sentry", "marmot: comes back up when the coast is clear")
			# now sneak in from behind it, crouched and slow
			var back := Vector3(sin(m.scan_base), 0, cos(m.scan_base))   # opposite its facing
			var start := m.home + back * 2.2
			start.y = BiomeKit.y(start.x, start.z) + 0.05
			var yaw_in := atan2(back.x, back.z)
			_put(p, start, yaw_in)
			p.bot = {"move": Vector2(0, 0.35), "yaw": yaw_in, "pitch": 0.0, "crouch": true}
			await _wait(14.0, func(): return _solved("marmot") or (m.state != "sentry" and not m.startled))
			await _wait(1.0, func(): return _solved("marmot"))
			p.bot = {"move": Vector2.ZERO, "yaw": yaw_in, "pitch": 0.0}
			_ok(_solved("marmot"), "marmot: sneaking up from behind = solved (state %s)" % m.state)
		# the long way round: both talus gullies walk up without climbing
		var up1 := await _walk(p, BiomeKit.at(22.0, MountainLevel.z1(22.0) + 6.5), 0.0, 12.0)
		_ok(up1 > 3.0, "gully 1 walks up to the bench (+%.1f m)" % up1)
		var up2 := await _walk(p, BiomeKit.at(-25.5, MountainLevel.z2(-25.5) + 6.5), 0.0, 12.0)
		_ok(up2 > 3.5, "gully 2 walks up to the summit plateau (+%.1f m)" % up2)
		# summit: sit by the cairn
		_put(p, MountainLevel.summit_spot + Vector3(0, 0.1, 0), 0.0)
		_ok(await _wait(12.0, func(): return _solved("summit")), "summit: a sit by the cairn = solved")
		_ok(b.net_state().get("drift", false), "mountain: net_state reports the drift gone")
	print("BIOMETEST %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(0 if bad == 0 else 1)
