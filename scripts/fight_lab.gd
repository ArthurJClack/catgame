extends Node3D
## fight lab: two bare CatRigs square up to each other and run a scripted scrap (calm, standoff
## with hissing, fight crouch, a combo of strikes with rear up batting, back off, calm down).
## a third rig is a remote copy of the left cat, fed through the real wire format (CatNetState
## encode / decode + life_log events), to check the fight looks the same online.
##   godot --path . res://fightlab.tscn -- [--legacy] [--view wide|face|remote] [--fighttest]
## --legacy turns CatFightAnim off (the old look, for before / after films).
## --fighttest runs headless and prints FIGHTTEST PASS / FAIL.

const SCRIPT := [
	# [t, phase, fight, crouch]
	[0.0, "calm", 0.0, 0.0],
	[1.6, "standoff: side on, back up, fur up, hiss", 1.0, 0.0],
	[5.6, "fight crouch: low, tail thrashing, bum wiggle", 1.0, 0.85],
	[7.6, "combo: hook / backhand / bop / chop / scoop, rear up batting", 1.0, 0.0],
	[11.4, "back off, standing its ground", 1.0, 0.0],
	[14.0, "calm again (fur goes down slowly)", 0.0, 0.0],
	[18.0, "", 0.0, 0.0],
]

var a: CatRig     # left cat (owner)
var b: CatRig     # right cat (owner)
var r: CatRig     # remote copy of a
var cam: Camera3D
var caption: Label
var view := "wide"
var testing := false
var t := 0.0
var _swat_n := 0
var _next_swat := 0.0
var _evid := 0
var _done := false
# test measures
var mx := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--legacy" in args:
		CatFightAnim.on = false
	var i := args.find("--view")
	if i >= 0:
		view = args[i + 1]
	testing = "--fighttest" in args
	process_priority = 100   # after the rigs animated this frame
	seed(7)
	_build_world()
	a = _cat(Vector3(-0.44, 0, 0), -PI * 0.5, "block")
	b = _cat(Vector3(0.44, 0, 0), PI * 0.5, "block_black")
	r = _cat(Vector3(-0.44, 0, 1.4), -PI * 0.5, "block")
	r.remote_life = true
	r.auto_listen = false
	r.set("_blink_t", 1e9)
	a.net_record = true
	r.visible = view == "remote" or testing
	for k in ["threat", "bristle", "ear_pin", "rear_add", "lowc", "hiss_mouth", "r_threat", "r_bristle", "r_rear", "start_hackles", "fight_hackles", "fangs", "r_fangs", "nan"]:
		mx[k] = 0.0


func _cat(at: Vector3, yaw: float, st: String) -> CatRig:
	var c := CatRig.new()
	c.style = st
	add_child(c)
	c.position = at
	c.rotation.y = yaw
	c.idle_life = false
	return c


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.65
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	cs.position.y = -0.5
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.33, 0.3)
	mi.material_override = mat
	body.add_child(mi)
	cam = Camera3D.new()
	cam.fov = 45
	add_child(cam)
	var cl := CanvasLayer.new()
	add_child(cl)
	caption = Label.new()
	caption.position = Vector2(24, 18)
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 6)
	cl.add_child(caption)


func _row() -> Array:
	var cur: Array = SCRIPT[0]
	for row in SCRIPT:
		if t >= float(row[0]):
			cur = row
	return cur


func _process(dt: float) -> void:
	if _done:
		return
	t += dt
	var row := _row()
	if str(row[1]) == "":
		_finish()
		return
	_measure()
	_sync_remote(dt)
	var ph := str(row[1])
	caption.text = ("BEFORE  " if not CatFightAnim.on else "") + ph
	for c in [a, b]:
		var cat: CatRig = c
		cat.fight = LowPoly.damp(cat.fight, float(row[2]), 3.0 if float(row[2]) > cat.fight else 0.5, dt)
		cat.crouch = move_toward(cat.crouch, float(row[3]), dt * 4.0)
		cat.drive_velocity = Vector3.ZERO
		cat.on_floor = true
	# the combo: alternating paws, a strike every 0.36 s each, the black cat half a beat behind
	if ph.begins_with("combo"):
		if t >= _next_swat:
			_next_swat = t + 0.18
			var who: CatRig = a if _swat_n % 2 == 0 else b
			var k := _swat_n / 2
			var paw := k % 2
			var hgt: float = [0.13, 0.06, 0.16, 0.03, 0.1][k % 5]
			who.swat(paw, who.to_global(Vector3(0.03 * (1 if paw == 0 else -1), hgt, -0.3)))
			_swat_n += 1
		if not testing:
			caption.text += "   [%s]" % a.fight_anim.style
	if testing and ph.begins_with("combo") and _swat_n > 0:
		pass
	if view == "remote":
		caption.text += "\n(front: the owner's cat   back: its online copy)"
	_camera()


func _camera() -> void:
	match view:
		"face":
			var h := a.head.global_position
			cam.global_position = h + Vector3(0.26, 0.0, 0.2)
			cam.look_at(h + Vector3(0.0, -0.03, 0), Vector3.UP)
		"top":
			cam.global_position = Vector3(0.0, 1.6, 0.25)
			cam.look_at(Vector3(0.0, 0.1, 0), Vector3.UP)
		"quarter":
			cam.global_position = Vector3(0.75, 0.45, 1.05)
			cam.look_at(Vector3(-0.1, 0.13, 0), Vector3.UP)
		"remote":
			cam.global_position = Vector3(-1.9, 0.5, 0.7)
			cam.look_at(Vector3(-0.2, 0.12, 0.7), Vector3.UP)
		_:
			cam.global_position = Vector3(0.15, 0.42, 1.55)
			cam.look_at(Vector3(0.0, 0.14, 0), Vector3.UP)


## the remote copy: the left cat's state through the real wire format, events and all
func _sync_remote(dt: float) -> void:
	var s := CatNetState.from_rig(a, t, null, t)
	for ev in a.life_log:
		_evid += 1
		s.events.append([_evid, t, ev])
	a.life_log.clear()
	var back := CatNetState.decode(s.encode())
	if back == null:
		return
	back.xf.origin += Vector3(0, 0, 1.4)
	back.apply(r, dt)
	for e in back.events:
		r.apply_life(e[2])


func _measure() -> void:
	var fa := a.fight_anim
	mx.threat = maxf(mx.threat, fa.threat)
	mx.bristle = maxf(mx.bristle, fa.bristle)
	mx.ear_pin = maxf(mx.ear_pin, fa.ear_pin)
	mx.rear_add = maxf(mx.rear_add, fa.rear_add)
	mx.lowc = maxf(mx.lowc, fa.lowc)
	mx.hiss_mouth = maxf(mx.hiss_mouth, float(a.soma.get("_mouth")))
	mx.r_threat = maxf(mx.r_threat, r.fight_anim.threat)
	mx.r_bristle = maxf(mx.r_bristle, r.fight_anim.bristle)
	mx.r_rear = maxf(mx.r_rear, r.fight_anim.rear_add)
	var hk_on := a.soma.hackles.size() > 0 and a.soma.hackles[0].visible
	if t < 1.5 and hk_on:
		mx.start_hackles = 1.0
	if t > 4.0 and t < 11.0 and hk_on:
		mx.fight_hackles += 1.0
	if a.soma.fangs.size() > 0 and a.soma.fangs[0].visible:
		mx.fangs = 1.0
	if r.soma.fangs.size() > 0 and r.soma.fangs[0].visible:
		mx.r_fangs = 1.0
	for c in [a, b, r]:
		var p: Vector3 = (c as CatRig).head.global_position
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			mx.nan = 1.0
	if t > 17.9 and not mx.has("end_bristle"):
		mx["end_bristle"] = fa.bristle


func _finish() -> void:
	_done = true
	if not testing:
		get_tree().quit()
		return
	var fails := []
	var thrown: Dictionary = a.fight_anim.styles_thrown
	var rthrown: Dictionary = r.fight_anim.styles_thrown
	print("FIGHT styles a=%s remote=%s" % [thrown, rthrown])
	print("FIGHT hisses a=%d b=%d remote=%d" % [a.soma.hisses, b.soma.hisses, r.soma.hisses])
	print("FIGHT %s" % [mx])
	if thrown.size() < 5:
		fails.append("only %d swat styles" % thrown.size())
	if not thrown.has("bat"):
		fails.append("no rear up bat")
	if thrown != rthrown:
		fails.append("remote styles differ")
	if mx.threat < 0.8 or mx.r_threat < 0.8:
		fails.append("threat pose %.2f / remote %.2f" % [mx.threat, mx.r_threat])
	if mx.bristle < 0.8 or mx.r_bristle < 0.8:
		fails.append("bristle %.2f / remote %.2f" % [mx.bristle, mx.r_bristle])
	if mx.rear_add < 0.3 or mx.r_rear < 0.3:
		fails.append("rear up %.2f / remote %.2f" % [mx.rear_add, mx.r_rear])
	if mx.lowc < 0.6:
		fails.append("fight crouch %.2f" % mx.lowc)
	if mx.ear_pin < 0.9:
		fails.append("ear pin %.2f" % mx.ear_pin)
	if a.soma.hisses < 1 or r.soma.hisses != a.soma.hisses:
		fails.append("hisses a %d remote %d" % [a.soma.hisses, r.soma.hisses])
	if mx.hiss_mouth < 0.8 or mx.fangs < 1.0 or mx.r_fangs < 1.0:
		fails.append("hiss face (mouth %.2f fangs %s remote %s)" % [mx.hiss_mouth, mx.fangs, mx.r_fangs])
	if mx.start_hackles > 0.0:
		fails.append("hackles up while calm")
	if mx.fight_hackles < 30.0:
		fails.append("hackles not up in the fight")
	if float(mx.get("end_bristle", 1.0)) > 0.75 or float(mx.get("end_bristle", 1.0)) >= mx.bristle:
		fails.append("fur never went down")
	if mx.nan > 0.0:
		fails.append("nan")
	print("FIGHTTEST %s %s" % ["PASS" if fails.is_empty() else "FAIL", ", ".join(fails)])
	get_tree().quit(0 if fails.is_empty() else 1)
