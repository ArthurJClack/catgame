extends SceneTree
## big falls (movement plan phase 4 + simplify pass): on the farm a fall past LAND_HARD is a
## stumble (no health lost, long recovery, run speed mostly gone). with fall_damage on (the rat
## pit) the same fall hurts.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/fall_test.gd

var bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _player() -> CatPlayer:
	var p = current_scene.get("player") if current_scene else null
	return p if p is CatPlayer and p.is_inside_tree() else null


func _drop(p: CatPlayer, h: float) -> Dictionary:
	# open yard grass, well away from the house
	var at := Vector3(6.0, h, 10.0)
	p.global_position = at
	p.velocity = Vector3(0, 0, -3.0)
	p._phys_curr = at
	var hp0: float = p.health.value
	var rec := 0.0
	var landed := false
	for i in 900:
		await physics_frame
		if p.is_on_floor() and p.air_time == 0.0 and p.last_impact > 1.0:
			landed = true
			rec = maxf(rec, p.land_rec)
			if i % 10 == 0:
				break
	return {"landed": landed, "lost": hp0 - p.health.value, "rec": rec, "impact": p.last_impact}


func _run() -> void:
	Engine.set_meta("title_done", true)
	GameSettings.s("hints", false)
	change_scene_to_file("res://main.tscn")
	var t0 := Time.get_ticks_msec()
	while _player() == null and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	var p := _player()
	_ok(p != null, "farm loads")
	for i in 30:
		await physics_frame
	if not CatPlayer.real_move:
		print("real_move is off, nothing to test")
		quit(0)
		return
	var r := await _drop(p, 9.0)
	_ok(r.landed and r.impact > CatPlayer.LAND_HARD, "9 m drop lands past LAND_HARD (%.1f m/s)" % r.impact)
	_ok(r.lost == 0.0, "farm: no health lost (%.1f)" % r.lost)
	_ok(r.rec > CatPlayer.LAND_REC_MAX, "farm: a stumble, long recovery (%.2f s)" % r.rec)
	for i in 120:
		await physics_frame
	p.fall_damage = true
	p.health.heal_full()
	r = await _drop(p, 9.0)
	_ok(r.lost > 0.0, "fall_damage on (rat pit): the same drop hurts (%.1f)" % r.lost)
	print("fall_test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad else 0)
