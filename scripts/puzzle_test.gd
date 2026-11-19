class_name PuzzleTest
extends Node
## checks the first puzzle milestone with the real controller (puzzles.gd).
##   godot --headless --path . res://main.tscn -- --puzzletest    (knock it off, sunbeam, gift, treats)
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
	print("   solved: %s" % str(Puzzles.solved))
	return ok


const SUN_WAIT := 2.2


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
