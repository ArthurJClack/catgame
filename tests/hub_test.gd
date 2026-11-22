extends SceneTree
## hub world round trip: from the farm walk (teleport) into every gate, check the level loads,
## walk into that level's farm exit, check we're back on the farm at the matching gate and
## don't bounce straight back out. needs a renderer for the meshes:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/hub_test.gd

var bad := 0


func _initialize() -> void:
	_run.call_deferred()


## waits `sec` of wall clock AND sec * 60 frames, whichever is longer: software gl under xvfb can
## drop the heavier levels to ~1 fps, and the fade counts frames (dt is capped)
func _wait(sec: float, until: Callable = func(): return false) -> bool:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	var frames := int(sec * 60.0)
	while Time.get_ticks_msec() < end or frames > 0:
		await process_frame
		frames -= 1
		if until.call():
			return true
	return until.call()


func _scene() -> String:
	return current_scene.scene_file_path if current_scene else ""


func _player() -> CatPlayer:
	if current_scene == null:
		return null
	var p = current_scene.get("player")
	return p if p is CatPlayer and p.is_inside_tree() else null


func _triggers(to: String) -> Array:
	var out := []
	for n in get_nodes_in_group("hub_trigger"):
		if current_scene and current_scene.is_ancestor_of(n) and n.get_meta("hub_to", "") == to:
			out.append(n)
	return out


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _arrived(path: String) -> bool:
	return _scene() == path and _player() != null and not root.has_node("HubFade")


func _step_into(a: Area3D) -> void:
	var p := _player()
	p.velocity = Vector3.ZERO
	p.global_position = a.global_position + Vector3(0, -0.3, 0)


func _run() -> void:
	change_scene_to_file("res://main.tscn")
	_ok(await _wait(20.0, func(): return _arrived("res://main.tscn")), "farm loads")
	var spawns := Hub.spawns()
	for key in Hub.DESTS:
		var d: Dictionary = Hub.DESTS[key]
		if _scene() != "res://main.tscn":
			# an earlier step failed: start this one from the farm again
			change_scene_to_file("res://main.tscn")
			await _wait(20.0, func(): return _arrived("res://main.tscn"))
		var gates := _triggers(d.scene)
		_ok(gates.size() == 1, "%s: one gate on the farm (%d)" % [key, gates.size()])
		if gates.is_empty():
			continue
		_player().set_style("stepped_coon")
		_step_into(gates[0])
		_ok(await _wait(30.0, func(): return _arrived(d.scene)), "%s: gate takes you to %s" % [key, d.scene])
		if _scene() != d.scene:
			continue
		await _wait(0.5)
		_ok(_player().style == "stepped_coon", "%s: cat style carried over (%s)" % [key, _player().style])
		var exits := _triggers("res://main.tscn")
		_ok(exits.size() >= 1, "%s: level has a way back to the farm" % key)
		if exits.is_empty():
			continue
		# not standing in the exit right after arriving
		_ok(_scene() == d.scene, "%s: still there after arriving" % key)
		_step_into(exits[0])
		_ok(await _wait(30.0, func(): return _arrived("res://main.tscn")), "%s: exit leads back to the farm" % key)
		await _wait(0.3)
		var want: Vector3 = spawns[d.spawn][0]
		var at := _player().global_position
		_ok(Vector2(at.x - want.x, at.z - want.z).length() < 0.6, "%s: back at its gate (%.1f, %.1f) want (%.1f, %.1f)" % [key, at.x, at.z, want.x, want.z])
		await _wait(1.5)
		_ok(_scene() == "res://main.tscn", "%s: no bounce back out" % key)
	print("hub test: %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad > 0 else 0)
