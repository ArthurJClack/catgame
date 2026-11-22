extends Node3D
## stops lab: runs the cat up to walk / trot / canter / gallop speed on a long flat strip and lets
## go of the stick, over and over, to check (and film) how it comes to a stop (cat_stop.gd).
## `godot --path . res://stoplab.tscn --fixed-fps 60 -- --stoptest` (xvfb: the head cam needs the rig)
##   --stoptest   checks: lots of different stops, never the same one twice running, the fast
##                ones skid, a stop cut short by moving off doesn't pop, no camera / body jolts
##   --film       side camera + caption, for clips (with --write-movie)
##   --fp         film in first person (looking down at the paws)
##   --plain      let plain stops (no animation) happen like in the game
##   --legs=n     how many run ups (default 16 test, 12 film)
##   CAT_OFF=stops  the before (the one stop it always did)

const TIERS := [
	["walk", {"move": Vector2(0, 0.5)}, 2.2],
	["trot", {"move": Vector2(0, 1.0)}, 2.0],
	["canter", {"move": Vector2(0, 1.0), "canter": true}, 2.2],
	["gallop", {"move": Vector2(0, 1.0), "sprint": true}, 2.4],
]
const HOLD := 3.4

var player: CatPlayer
var cam: Camera3D
var label: Label
var film := false
var fp := false
var test := false
var legs := 16
var leg := -1
var phase := 0          # 0 run up, 1 stopped, 2 cut short (moves off again right away)
var t := 0.0
var seen: Array[String] = []
var brakes := 0
var fast_legs := 0
var stop_kind := ""
var cut_leg := 5
var cut_pops := 0.0
var jolt_cam := 0.0
var jolt_body := 0.0
var brake_cam := 0.0
var leg_cam := 0.0
var leg_body := 0.0
var brake_body := 0.0
var nan := false
var _cy := PackedFloat32Array()
var _by := PackedVector3Array()
var _stopped := false
var _braked := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	film = "--film" in args
	fp = "--fp" in args
	test = "--stoptest" in args
	CatStop.plain_stops = "--plain" in args   # the lab wants to see a stop every time
	legs = 12 if film else 16
	for a in args:
		if a.begins_with("--legs="):
			legs = int(a.substr(7))
	var floor_b := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40, 1, 600)
	fs.shape = bx
	fs.position = Vector3(0, -0.5, -280)
	floor_b.add_child(fs)
	floor_b.set_meta("surface", "wood")
	add_child(floor_b)
	# boards across the strip (something to judge speed and slide against)
	for k in (300 if film else 0):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(40, 0.02, 1.0)
		mi.mesh = bm
		mi.material_override = _mat(Color(0.56, 0.42, 0.28) if k % 2 == 0 else Color(0.5, 0.37, 0.24))
		mi.position = Vector3(0, -0.01, 15.0 - k * 1.0 - 0.5)
		add_child(mi)
	for k in (120 if film else 0):
		var z := 15.0 - k * 5.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.5, 0.06)
		mi.mesh = bm
		mi.material_override = _mat(Color(0.92, 0.92, 0.94))
		mi.position = Vector3(-1.4, 0.25, z)
		add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	player = CatPlayer.new()
	add_child(player)
	player.global_position = Vector3(0, 0.02, 10.0)
	if film:
		var cl := CanvasLayer.new()
		label = Label.new()
		label.position = Vector2(24, 18)
		label.add_theme_font_size_override("font_size", 34)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 8)
		cl.add_child(label)
		add_child(cl)
	await get_tree().process_frame
	player.set_third_person(not (fp or test))
	if film and not fp:
		cam = Camera3D.new()
		cam.fov = 40.0
		add_child(cam)
		cam.current = true
	var tr := Tracker.new()
	tr.lab = self
	add_child(tr)
	_next()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _bot(move: Vector2, extra := {}) -> void:
	var b := {"move": move, "yaw": 0.0, "pitch": player.bot.get("pitch", -0.5) if fp else -0.12}
	for k in extra:
		if k != "move":
			b[k] = extra[k]
	player.bot = b


func _next() -> void:
	if leg >= 0:
		print("[stop]        leg %2d %s: worst once stopped cam %.1f body %.1f" % [leg, stop_kind, leg_cam * 1000.0, leg_body * 1000.0])
	leg_cam = 0.0
	leg_body = 0.0
	leg += 1
	if leg >= legs:
		_done()
		return
	var tier: Array = TIERS[leg % TIERS.size()]
	_bot(tier[1]["move"], tier[1])
	phase = 0
	t = 0.0
	_stopped = false
	_braked = false
	stop_kind = ""
	if test:
		# test both views: odd legs in third person
		player.set_third_person(leg % 2 == 1)


func _physics_process(dt: float) -> void:
	if leg < 0 or leg >= legs:
		return
	t += dt
	var tier: Array = TIERS[leg % TIERS.size()]
	var st: CatStop = player.rig.soma.stop if player.rig else null
	if fp and not player.bot.is_empty():
		# first person film: look ahead on the run up, down at the paws once it is stopping
		player.bot.pitch = move_toward(float(player.bot.get("pitch", -0.5)), -1.2 if phase >= 1 else -0.45, dt * 1.8)
	if phase == 0:
		if t > float(tier[2]):
			_bot(Vector2.ZERO)
			phase = 1
			t = 0.0
			if tier[0] in ["canter", "gallop"]:
				fast_legs += 1
	elif phase == 1:
		if st:
			if st.brake > 0.3 and not _braked:
				_braked = true
				brakes += 1
			if st.kind != "" and stop_kind == "":
				stop_kind = st.kind
				seen.append(st.kind)
				print("[stop] leg %2d %-6s %s  -> %s%s" % [leg, tier[0], "tp" if player.third_person else "fp", st.kind, "  (skid)" if _braked else ""])
		if test and leg == cut_leg and t > 1.0 and stop_kind != "-":
			# moves off again right away: whatever the stop was doing has to give way smoothly
			# (same moment with stops off, for the before number)
			phase = 2
			t = 0.0
			_bot(Vector2(0, 1.0))
		elif t > HOLD:
			if stop_kind == "":
				print("[stop] leg %2d %-6s no stop picked" % [leg, tier[0]])
				seen.append("")
			_next()
	elif phase == 2:
		if t > 1.2:
			_bot(Vector2.ZERO)
			phase = 1
			t = 0.0
			stop_kind = "-"


## once per rendered frame, after the head cam
func sample(dt: float) -> void:
	if leg < 0 or leg >= legs or player.rig == null:
		return
	var p := player.global_position
	if cam:
		var want := p + Vector3(1.75, 0.4, -0.2)
		cam.global_position = want if cam.global_position.distance_to(want) > 3.0 else cam.global_position.lerp(want, 1.0 - exp(-6.0 * dt))
		cam.look_at(p + Vector3(0, 0.18, -0.25))
	if label:
		var tier: Array = TIERS[leg % TIERS.size()]
		var st: CatStop = player.rig.soma.stop
		var before := not CatStop.stops
		var what := ""
		if phase == 0:
			what = tier[0]
		elif before:
			what = "stop (always the same)"
		elif st.brake > 0.2:
			what = "stop: skid"
		elif st.kind != "":
			what = "stop: " + st.kind
		elif stop_kind != "":
			what = "stop: " + stop_kind
		else:
			what = "stopping"
		label.text = ("before" if before else "after") + "  -  " + what
	# jolts: second difference of the camera height and of the body, per rendered frame
	var cy := player.cam.global_position.y
	var bp: Vector3 = player.rig.pivot.global_position - p
	if is_nan(cy) or is_nan(bp.x) or is_nan(bp.y):
		nan = true
	if phase >= 1:
		_cy.append(cy)
		_by.append(bp)
		if _cy.size() >= 3:
			var n := _cy.size()
			var d2 := absf(_cy[n - 1] - 2.0 * _cy[n - 2] + _cy[n - 3])
			var b2 := (_by[n - 1] - 2.0 * _by[n - 2] + _by[n - 3]).length()
			if player.rig.speed_s < 0.4:
				if not player.third_person:
					jolt_cam = maxf(jolt_cam, d2)
				jolt_body = maxf(jolt_body, b2)
				if not player.third_person:
					leg_cam = maxf(leg_cam, d2)
				leg_body = maxf(leg_body, b2)
			else:
				if not player.third_person:
					brake_cam = maxf(brake_cam, d2)
				brake_body = maxf(brake_body, b2)
			if phase == 2 and t < 0.5:
				cut_pops = maxf(cut_pops, b2)
	else:
		_cy.clear()
		_by.clear()


func _done() -> void:
	var kinds := {}
	var repeats := 0
	var none := 0
	for i in seen.size():
		if seen[i] == "":
			none += 1
			continue
		kinds[seen[i]] = true
		if i > 0 and seen[i] == seen[i - 1]:
			repeats += 1
	print("[stop] kinds %d %s, repeats %d, no stop %d, skids %d / %d fast" % [kinds.size(), str(kinds.keys()), repeats, none, brakes, fast_legs])
	print("[stop] worst jolt once stopped: fp camera %.2f mm/frame^2, body %.2f, cut short %.2f" % [jolt_cam * 1000.0, jolt_body * 1000.0, cut_pops * 1000.0])
	print("[stop] worst jolt slowing down: fp camera %.2f mm/frame^2, body %.2f" % [brake_cam * 1000.0, brake_body * 1000.0])
	if test:
		var fails := []
		if CatStop.stops:
			if kinds.size() < 6:
				fails.append("only %d kinds of stop" % kinds.size())
			if repeats > 0:
				fails.append("same stop twice running")
			if none > 1:
				fails.append("%d stops picked nothing" % none)
			if brakes < 1:
				fails.append("no skid on a fast stop")
		if nan:
			fails.append("nan")
		# bars sit ~1.4x over what the old single stop already measures here (CAT_OFF=stops:
		# fp cam ~28, body ~12, moving off ~22 mm/frame^2: that's the gait's own settle steps)
		if jolt_cam > 0.04:
			fails.append("fp camera jolt")
		if jolt_body > 0.02:
			fails.append("body jolt")
		if cut_pops > 0.03:
			fails.append("cut short stop popped")
		print("STOPTEST %s %s" % ["PASS" if fails.is_empty() else "FAIL", str(fails)])
	get_tree().quit()


class Tracker extends Node:
	var lab: Node
	func _ready() -> void:
		process_priority = 100   # after HeadFollow (20)
	func _process(dt: float) -> void:
		lab.sample(dt)
