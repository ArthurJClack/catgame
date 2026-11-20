class_name ReachShow
extends RefCounted
## before / after reel for attack reach + dodge landings: `res://arena.tscn -- --reachshow`
## (combat_test.gd hands itself over). side camera that follows the cat, half speed / slow mo, captions.

static var _mid: Node3D = null   # look between the cat and this (the rat), if set
static var _side := Vector3(1.0, 0.0, 0.0)


## run the show for `secs` of game time with the camera tracking the cat from the side
static func _hold(t: CombatTest, secs: float, f: Callable = Callable()) -> void:
	var p: CatPlayer = t.p
	var e := 0.0
	while e < secs:
		await t.get_tree().physics_frame
		var dt := t.get_physics_process_delta_time()
		e += dt
		if f.is_valid():
			f.call(e)
		var c := p.global_position + Vector3(0, 0.1, 0)
		if _mid != null and is_instance_valid(_mid):
			c = c.lerp(_mid.global_position + Vector3(0, 0.08, 0), 0.5)
		t._cam_to(c + _side * 1.7 + Vector3(0, 0.38, 0), c, dt, 6.0)


static func _snap(t: CombatTest) -> void:
	var p: CatPlayer = t.p
	var c := p.global_position + Vector3(0, 0.1, 0)
	if _mid != null and is_instance_valid(_mid):
		c = c.lerp(_mid.global_position + Vector3(0, 0.08, 0), 0.5)
	t._cam_pos = c + _side * 1.7 + Vector3(0, 0.38, 0)
	t._cam_look = c
	t.cam.global_position = t._cam_pos
	t.cam.look_at(c, Vector3.UP)


static func run(t: CombatTest) -> void:
	var p: CatPlayer = t.p
	var bot: Dictionary = t.bot
	t._labels()
	t.arena.hud.visible = false
	t.cam = Camera3D.new()
	t.cam.fov = 50
	t.cam.near = 0.02
	t.arena.add_child(t.cam)
	t.cam.current = true
	p.set_third_person(true)
	p.set_style("block")
	await t._ticks(10)
	await t._clear_rats()
	_side = Vector3(1, 0, 0)
	# ---- 1: swats into open air, side on
	t._reset_cat(Vector3(0, 0.02, 1.2))
	t._face(Vector3(0, 0.02, -3))
	_mid = null
	_snap(t)
	t._say("swat into the air  (0.5x)", "how far out the strike goes")
	Engine.time_scale = 0.5
	await _hold(t, 0.4)
	for k in 2:
		t._paws(k == 0, k == 1)
		await t._ticks(3)
		t._paws(false, false)
		await _hold(t, 0.6)
	# ---- 2: a rat about a metre out
	await t._clear_rats()
	t._reset_cat(Vector3(0, 0.02, 1.15))
	var r: SoulsRat = t._dummy_rat(PI, Vector3(0, 0.02, 0.0))
	t._face(r.global_position)
	_mid = r
	_snap(t)
	t._say("rat about 1 m away  (0.5x)", "swat from range")
	await _hold(t, 0.4)
	for k in 2:
		t._face(r.global_position)
		t._paws(k == 0, k == 1)
		await t._ticks(3)
		t._paws(false, false)
		await _hold(t, 0.65)
	await t._clear_rats()
	t._dummy = null
	_mid = null
	# ---- 3: swats on the move
	t._reset_cat(Vector3(0, 0.02, 2.6))
	t._face(Vector3(0, 0.02, -4))
	_snap(t)
	t._say("swats at a trot  (0.5x)", "the strike rides along with the cat")
	bot.move = Vector2(0, 1)
	var fired := [0]
	await _hold(t, 1.9, func(e: float) -> void:
		if (fired[0] == 0 and e > 0.5) or (fired[0] == 1 and e > 1.05):
			t._paws(fired[0] == 0, fired[0] == 1)
			fired[0] += 1
		else:
			t._paws(false, false))
	bot.move = Vector2.ZERO
	await _hold(t, 0.4)
	# ---- 4: dodges, slow mo, then hold still on the landing
	Engine.time_scale = 0.4
	for d in [["dart (w)", Vector2(0, 1), Vector3(1, 0, 0)], ["side leap (d)", Vector2(1, 0), Vector3(0.35, 0, -0.94)], ["backstep (no direction)", Vector2.ZERO, Vector3(1, 0, 0)]]:
		t._reset_cat(Vector3(0, 0.02, 1.0))
		t._face(Vector3(0, 0.02, -3))
		_side = (d[2] as Vector3).normalized()
		await t._ticks(20)
		_snap(t)
		t._say("dodge: " + d[0] + "  (0.4x)", "watch the landing: does it slide on?")
		await _hold(t, 0.25)
		bot.move = d[1]
		bot.dash = true
		await t._ticks(2)
		bot.dash = false
		var st := [false]
		await _hold(t, 1.3, func(_e: float) -> void:
			if p.dash.state == CatDash.AIR:
				st[0] = true
			elif st[0]:
				bot.move = Vector2.ZERO)
		bot.move = Vector2.ZERO
	Engine.time_scale = 1.0
	await t._secs(0.3)
	t.get_tree().quit()
