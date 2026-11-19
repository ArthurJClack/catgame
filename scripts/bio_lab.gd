extends Node3D
## biomechanics lab: the real CatPlayer (bot driven) is put through every movement state on a
## small course and every frame the body is checked for the things that read as glitches:
##   slide  planted paws moving over the ground (mm per frame)
##   gap    planted paws hovering over / sunk into what they stand on
##   miss   the leg not reaching where the gait put the paw
##   over   legs stretched past their length
##   pop    body parts or paws jumping (speed change between two frames no muscle could do)
##   clip   chest / hips / head under the floor or inside a wall
##   snap   the whole cat teleporting (capsule moved further than its velocity)
##
##   godot --headless --fixed-fps 60 --path . res://biolab.tscn -- --biotest [--only walk,stairs_up] [--json out.json] [--dbg pop]
##   godot --path . res://biolab.tscn -- --show [--only ...] --write-movie out/bio.avi --fixed-fps 60   (xvfb)
##   --real 0 turns CatPlayer.real_move off where the build has it (before / after)

const LEG := ["LF", "RF", "LH", "RH"]
const PARTS := ["chest", "pelvis", "head"]

var player: CatPlayer
var cam: Camera3D
var caption: Label
var show := false
var dbg := ""
var json_path := ""
var names: Array = []
var scen := {}
var si := -1
var t := 0.0
var m := {}
var results := {}
var rest_gap := [0.0, 0.0, 0.0, 0.0]
var _prev := {}
var _phys_prev_pos := Vector3.ZERO
var _phys_ok := false
var _tick := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	show = "--show" in args
	process_priority = 100
	var k := args.find("--dbg")
	if k >= 0:
		dbg = args[k + 1]
	k = args.find("--json")
	if k >= 0:
		json_path = args[k + 1]
	k = args.find("--real")
	var ps: Script = load("res://scripts/cat_player.gd")
	if k >= 0 and ps.get("real_move") != null:
		ps.set("real_move", args[k + 1] != "0")
	if "--legacy" in args:
		# every switch this overhaul added, off: the cat as it was before (before / after runs)
		for sw in [["cat_gait.gd", "reach_lift"], ["cat_rig.gd", "paw_free"], ["cat_rig.gd", "reach_sag"], ["cat_rig.gd", "follow_fast"], ["cat_rig.gd", "smooth_ref"], ["cat_gait.gd", "solid_rays"], ["cat_player.gd", "smooth_steps"], ["cat_player.gd", "real_move"], ["cat_rig.gd", "phys"], ["cat_rig.gd", "leg_limits"], ["cat_gait.gd", "pendulum"], ["cat_rig.gd", "load_shift"], ["cat_gait.gd", "support_rule"], ["cat_player.gd", "paw_drive"]]:
			var sc: Script = load("res://scripts/" + sw[0])
			if sc.get(sw[1]) != null:
				sc.set(sw[1], false)
	# --off a,b: single switches off (name of the static var, looked up in the three scripts)
	k = args.find("--off")
	if k >= 0:
		for nm in args[k + 1].split(","):
			for fn in ["cat_gait.gd", "cat_rig.gd", "cat_player.gd"]:
				var sc2: Script = load("res://scripts/" + fn)
				if sc2.get(nm) != null:
					sc2.set(nm, false)
	_build()
	_scenarios()
	var only := []
	k = args.find("--only")
	if k >= 0:
		only = Array(args[k + 1].split(","))
	for n in scen:
		if only.is_empty() or n in only:
			names.append(n)
	player = CatPlayer.new()
	add_child(player)
	if show:
		player.set_third_person(true)
		cam = Camera3D.new()
		cam.fov = 38.0
		cam.near = 0.02
		add_child(cam)
		cam.make_current()
		var cl := CanvasLayer.new()
		add_child(cl)
		caption = Label.new()
		caption.position = Vector2(24, 18)
		caption.add_theme_font_size_override("font_size", 30)
		caption.add_theme_color_override("font_outline_color", Color.BLACK)
		caption.add_theme_constant_override("outline_size", 8)
		cl.add_child(caption)
	_next.call_deferred()


# ---------------------------------------------------------------- course

func _box(pos: Vector3, size: Vector3, col: Color, surface := "", group := "", rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	mi.material_override = mat
	b.add_child(mi)
	b.position = pos
	b.rotation = rot
	if surface != "":
		b.set_meta("surface", surface)
	if group != "":
		b.add_to_group(group)
	add_child(b)
	return b


static func rough_h(x: float, z: float) -> float:
	var w := smoothstep(-2.0, -3.0, z) * (1.0 - smoothstep(-11.0, -12.0, z))
	return w * (0.03 * sin(x * 7.1 + z * 3.3) + 0.022 * sin(x * -4.3 + z * 8.9 + 1.7) + 0.016 * sin(x * 13.0 - z * 11.0 + 0.4) + 0.03 * sin(z * 5.2) * sin(x * 3.0 + 0.6))


func _build() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.85, 0.6, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 14.0
	add_child(sun)
	# lane A (x 0): 70 m of wood floor. the whole course stands on one slab, lanes 4 m apart
	_box(Vector3(18, -0.5, -30), Vector3(80, 1, 90), Color(0.62, 0.5, 0.36), "wood")
	# lane B (x 6): stairs up (6 x 10 cm), a landing, stairs down
	for i in 6:
		var h := 0.1 * (i + 1)
		_box(Vector3(6, h * 0.5, -3.0 - 0.25 * i - 0.125), Vector3(1.6, h, 0.25), Color(0.5, 0.42, 0.34), "wood")
		_box(Vector3(6, h * 0.5, -8.0 + 0.25 * i + 0.125), Vector3(1.6, h, 0.25), Color(0.5, 0.42, 0.34), "wood")
	_box(Vector3(6, 0.3, -5.5), Vector3(1.6, 0.6, 2.0), Color(0.5, 0.42, 0.34), "wood")
	# lane C (x 10): a chest high step (20 cm) to mount, walk across and step off
	_box(Vector3(10, 0.1, -4.0), Vector3(1.6, 0.2, 2.0), Color(0.45, 0.45, 0.5), "tile")
	# lane D (x 14): rough dirt
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.07
	for iz in int(11.0 / step):
		for ix in int(2.0 / step):
			var x0 := 13.0 + ix * step
			var z0 := -1.5 - iz * step
			var a := Vector3(x0, rough_h(x0, z0), z0)
			var b := Vector3(x0 + step, rough_h(x0 + step, z0), z0)
			var c := Vector3(x0, rough_h(x0, z0 - step), z0 - step)
			var d := Vector3(x0 + step, rough_h(x0 + step, z0 - step), z0 - step)
			for v in [a, c, b, b, c, d]:
				st.add_vertex(v + Vector3(0, 0.004, 0))
	st.generate_normals()
	var mesh := st.commit()
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.42, 0.33, 0.24)
	dm.roughness = 1.0
	mesh.surface_set_material(0, dm)
	var rb := StaticBody3D.new()
	rb.set_meta("surface", "dirt")
	var rcs := CollisionShape3D.new()
	rcs.shape = mesh.create_trimesh_shape()
	rb.add_child(rcs)
	var rmi := MeshInstance3D.new()
	rmi.mesh = mesh
	rb.add_child(rmi)
	add_child(rb)
	# lane E (x 18): 20 deg ramp up to a 1.4 m deck with an open far end (the drop)
	var rl := 1.4 / sin(deg_to_rad(20.0))
	_box(Vector3(18, 0.7 - 0.05 * cos(deg_to_rad(20.0)), -2.0 - 0.5 * rl * cos(deg_to_rad(20.0)) - 0.05 * sin(deg_to_rad(20.0))), Vector3(1.6, 0.1, rl), Color(0.4, 0.5, 0.4), "grass", "", Vector3(deg_to_rad(20.0), 0, 0))
	_box(Vector3(18, 0.7, -2.0 - rl * cos(deg_to_rad(20.0)) - 1.5), Vector3(1.6, 1.4, 3.0), Color(0.4, 0.5, 0.4), "grass")
	# lane F (x 22): a smooth wall (kick / slide)
	_box(Vector3(22, 1.5, -4.0), Vector3(3.0, 3.0, 0.4), Color(0.7, 0.7, 0.72), "tile")
	# lane G (x 26): a climbable wall with a top to haul onto
	_box(Vector3(26, 0.8, -4.5), Vector3(2.0, 1.6, 1.4), Color(0.4, 0.3, 0.2), "bark", "climbable")
	# lane H (x 30): a 60 cm ledge (grab + haul up)
	_box(Vector3(30, 0.3, -4.5), Vector3(2.0, 0.6, 1.6), Color(0.5, 0.5, 0.45), "wood")
	# lane I (x 34): tile floor (2 mm proud of the wood so the ray reads tile)
	_box(Vector3(44, 0.001, -30.0), Vector3(24, 0.002, 86.0), Color(0.8, 0.82, 0.85), "tile")


# ---------------------------------------------------------------- scenarios
# each: lane x, start z, seconds, f(t) -> bot dict. keys the lab reads itself: "orb" (camera
# heading the cat steers by, rad), "body" (old body relative controls: this yaw, strafing allowed),
# "sit" / "crouch"

func _fwd(extra := {}) -> Dictionary:
	var d := {"move": Vector2(0, 1), "pitch": -0.1}
	d.merge(extra, true)
	return d


func _scenarios() -> void:
	var idle := {"move": Vector2.ZERO, "pitch": -0.1}
	scen = {
		"stand": [0, 0, 3.0, func(_t): return idle],
		"sit": [0, 0, 5.0, func(tt): return {"move": Vector2.ZERO, "pitch": -0.1, "sit": 1.0 if tt > 0.5 and tt < 3.5 else 0.0}],
		"turn_place": [0, 0, 4.0, func(tt): return {"move": Vector2.ZERO, "pitch": -0.1, "orb": tt * 1.6}],
		"walk": [0, 0, 6.0, func(_t): return {"move": Vector2(0, 0.5), "pitch": -0.1}],
		"trot": [0, 0, 5.0, func(_t): return _fwd()],
		"canter": [0, 0, 5.0, func(_t): return _fwd({"canter": true})],
		"gallop": [0, 2, 5.0, func(_t): return _fwd({"sprint": true})],
		"back_up": [0, -3, 4.0, func(_t): return {"move": Vector2(0, -1), "pitch": -0.1, "body": 0.0}],
		"stalk": [0, 0, 5.0, func(_t): return _fwd({"crouch": true})],
		"gaits_up_down": [0, 2, 9.0, func(tt): return {"move": Vector2(0, 0.5 if (tt < 1.5 or tt > 7.5) else 1.0), "pitch": -0.1, "canter": tt > 3.0 and tt < 4.5, "sprint": tt >= 4.5 and tt < 6.0}],
		"trot_stop": [0, 0, 4.0, func(tt): return _fwd() if tt < 2.0 else idle],
		"gallop_stop": [0, 2, 6.0, func(tt): return _fwd({"sprint": true}) if tt < 3.0 else idle],
		"trot_circle": [0, -10, 6.0, func(tt): return _fwd({"orb": tt * 1.3})],
		"canter_circle": [0, -14, 6.0, func(tt): return _fwd({"canter": true, "orb": tt * 0.8})],
		"trot_reverse": [0, 0, 5.0, func(tt): return _fwd({"orb": PI if tt > 2.0 else 0.0})],
		"gallop_reverse": [0, 2, 7.0, func(tt): return _fwd({"sprint": true, "orb": PI if tt > 3.0 else 0.0})],
		"trot_zigzag": [0, 0, 6.0, func(tt): return _fwd({"orb": 0.9 * signf(sin(tt * 2.6))})],
		"side_hop": [0, 0, 4.0, func(tt): return {"move": Vector2(1.0 if fmod(tt, 1.0) < 0.2 else 0.0, 0), "pitch": -0.1, "body": 0.0}],
		"dodge": [0, 0, 4.0, func(tt): return {"move": Vector2(0, 1), "pitch": -0.1, "dash": fmod(tt, 1.5) > 1.0 and fmod(tt, 1.5) < 1.1}],
		"swat_stand": [0, 0, 4.0, func(tt): return {"move": Vector2.ZERO, "pitch": -0.1, "paw_l": fmod(tt, 1.0) > 0.5 and fmod(tt, 1.0) < 0.58, "paw_r": fmod(tt, 1.0) < 0.08 and tt > 0.9}],
		"swat_walk": [0, 0, 4.0, func(tt): return {"move": Vector2(0, 0.5), "pitch": -0.1, "paw_l": fmod(tt, 1.0) > 0.5 and fmod(tt, 1.0) < 0.58}],
		"hop_stand": [0, 0, 3.0, func(tt): return {"move": Vector2.ZERO, "pitch": -0.1, "jump": tt > 0.8 and tt < 0.9}],
		"hop_trot": [0, 0, 4.0, func(tt): return _fwd({"jump": fmod(tt, 1.5) > 1.2 and fmod(tt, 1.5) < 1.3})],
		"hop_gallop": [0, 2, 5.0, func(tt): return _fwd({"sprint": true, "jump": tt > 3.0 and tt < 3.1})],
		"hop_charged": [0, 0, 3.0, func(tt): return {"move": Vector2.ZERO, "pitch": -0.1, "jump": tt > 0.8 and tt < 0.9, "hop_charge": 1.0}],
		"stairs_up_walk": [6, -1.5, 9.0, func(_t): return {"move": Vector2(0, 0.5), "pitch": -0.1}],
		"stairs_up_trot": [6, -1.0, 4.0, func(_t): return _fwd()],
		"stairs_canter": [6, 1.0, 3.5, func(_t): return _fwd({"canter": true})],
		"step_mount_walk": [10, -1.8, 7.0, func(_t): return {"move": Vector2(0, 0.5), "pitch": -0.1}],
		"step_mount_trot": [10, -1.0, 3.5, func(_t): return _fwd()],
		"rough_walk": [14, -1.0, 12.0, func(_t): return {"move": Vector2(0, 0.5), "pitch": -0.1}],
		"rough_trot": [14, -1.0, 4.5, func(_t): return _fwd()],
		"ramp_up_trot": [18, -0.5, 3.0, func(_t): return _fwd()],
		"ramp_walk_drop": [18, -0.5, 12.0, func(_t): return {"move": Vector2(0, 0.5), "pitch": -0.1}],
		"ramp_run_drop": [18, 1.0, 4.0, func(_t): return _fwd({"canter": true})],
		"wall_run_in": [22, -1.0, 3.0, func(_t): return _fwd()],
		"wall_kick": [22, -1.5, 3.5, func(tt): return _fwd({"jump": (tt > 0.55 and tt < 0.65) or (tt > 0.88 and tt < 0.96)})],
		"wall_slide": [22, -2.6, 3.0, func(tt): return _fwd({"jump": tt > 0.2 and tt < 0.3, "hop_charge": 1.0})],
		"climb_top": [26, -2.6, 5.0, func(tt): return _fwd({"jump": tt > 0.25 and tt < 0.35})],
		"climb_let_go": [26, -2.6, 3.5, func(tt): return _fwd({"jump": tt > 0.25 and tt < 0.35, "crouch": tt > 1.2 and tt < 1.4})],
		"clamber": [30, -2.6, 3.5, func(tt): return _fwd({"jump": tt > 0.25 and tt < 0.35})],
		"tile_trot_circle": [44, -10, 6.0, func(tt): return _fwd({"orb": tt * 1.3})],
		"tile_gallop_reverse": [44, 0, 7.0, func(tt): return _fwd({"sprint": true, "orb": PI if tt > 2.2 else 0.0})],
	}


func _floor_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 0.5, z), Vector3(x, -1.0, z))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else 0.0


func _next() -> void:
	if si >= 0:
		_report(names[si])
	si += 1
	if si >= names.size():
		_summary()
		get_tree().quit()
		return
	var s: Array = scen[names[si]]
	var p := Vector3(float(s[0]), 0.0, float(s[1]))
	p.y = _floor_y(p.x, p.z) + 0.02
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.orb_yaw = 0.0
	player.rotation.y = 0.0
	for k in ["climbing", "clambering", "mantling", "scratching", "charging", "wall_sliding"]:
		player.set(k, false)
	player.kick_plant_t = 0.0
	player.wall_time = 10.0
	player.wall_collider = null
	player.climb_cool = 0.0
	player.crouch_amt = 0.0
	player.rig.sit = 0.0
	player.rig.idle_life = false     # no self started sits / stretches mid measurement
	player.rig.gait._ready_done = false
	player.bot = {"move": Vector2.ZERO, "pitch": -0.1}
	t = -0.5    # half a second to settle before the script starts
	m = {"frames": 0, "planted": 0, "slide": [], "gap": [], "hover": 0, "sink": 0, "miss": [], "over": 0, "stretch_max": 0.0,
		"fold": 0, "frames_leg": 0, "hang_min": 9.0, "pop": 0, "pop_max": 0.0, "pop_what": "", "pop_t": 0.0, "clip": 0, "clip_max": 0.0, "clip_what": "", "snap": 0, "snap_max": 0.0, "nan": 0, "ev": [], "dist": 0.0, "vmax": 0.0, "air": 0.0, "ymax": -9.0}
	_prev = {}
	_phys_ok = false
	if caption:
		caption.text = names[si].replace("_", " ")


func _physics_process(dt: float) -> void:
	if si < 0 or si >= names.size():
		return
	t += dt
	var s: Array = scen[names[si]]
	if t >= 0.0:
		var b: Dictionary = (s[3] as Callable).call(t)
		if b.has("orb"):
			player.orb_yaw = float(b.orb)
			b.erase("orb")
		if b.has("body"):
			b["yaw"] = float(b.body)
			b.erase("body")
		player.rig.sit = float(b.get("sit", 0.0))
		b.erase("sit")
		player.bot = b
	# whole cat teleports: the capsule went further than its speed says (0.5 cm of slack + step glide)
	var pp := player.global_position
	if player.get("_soft_off") != null:
		pp += player.get("_soft_off")    # the visible cat's spot (the capsule may hop onto a step under it)
	if _phys_ok and t > 0.0:
		var moved := (pp - _phys_prev_pos).length()
		var exp_d := maxf(player.velocity.length(), _tick.get("v", 0.0)) * dt
		var mv3 := pp - _phys_prev_pos
		if player.is_on_floor():
			mv3.y = 0.0     # on the ground the rig takes the height out itself (the body is solved from the paws)
		var extra := mv3.length() - exp_d
		var lim := 0.02 if not (player.mantling or player.clambering) else 0.05
		if extra > lim:
			m.snap += 1
			if extra > m.snap_max:
				m.snap_max = extra
			if dbg == "snap":
				print("  snap %.0f mm t=%.2f %s" % [extra * 1000.0, t, player.last_event])
		m.dist += moved
	if dbg == "trace" and t > 0.0:
		print("  t=%.3f pos %.3f %.3f %.3f v %.2f %.2f floor %s mant %s clip_off %.3f ev %s" % [t, pp.x, pp.y, pp.z, Vector2(player.velocity.x, player.velocity.z).length(), player.velocity.y, player.is_on_floor(), player.mantling, player._clip_off, player.last_event])
	_tick = {"v": player.velocity.length()}
	_phys_prev_pos = pp
	_phys_ok = true
	m.vmax = maxf(m.vmax, Vector2(player.velocity.x, player.velocity.z).length())
	m.ymax = maxf(m.ymax, pp.y)
	if not player.is_on_floor() and not (player.climbing or player.clambering or player.mantling):
		m.air += dt
	if player.last_event_t <= dt * 1.5 and player.last_event != "" and (m.ev.is_empty() or m.ev[-1] != player.last_event):
		m.ev.append(player.last_event)
	if t > float(s[2]):
		_next()


func _contact(i: int) -> Vector3:
	var paw: Node3D = player.rig.legs[i].paw
	return paw.global_transform * (Vector3(0, -0.010, 0.006) if i < 2 else Vector3(0, -0.008, 0.014))


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 0.25, p.z), Vector3(p.x, p.y - 0.6, p.z))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else p.y - 1.0


## is p inside something solid (convex colliders: boxes, the course's walls and steps)
func _inside(p: Vector3) -> float:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.exclude = [player.get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_point(q, 4):
		if hit.collider is StaticBody3D:
			return 0.03
	return 0.0


func _process(dt: float) -> void:
	if si < 0 or si >= names.size() or dt <= 0.0:
		return
	if show:
		_camera(dt)
	if t < 0.0:
		_prev = {}
		return
	var rig := player.rig
	var g: CatGait = rig.gait
	var on_wall := rig.climb > 0.3 or rig.clamber > 0.3
	var cur := {}
	m.frames += 1
	var root := player.global_transform
	var rinv := root.affine_inverse()
	var spd := player.velocity.length()
	for i in 4:
		var c := _contact(i)
		if not (is_finite(c.x) and is_finite(c.y) and is_finite(c.z)):
			m.nan += 1
			continue
		cur["c%d" % i] = c
		cur["l%d" % i] = c
		cur["m%d" % i] = g.mode[i]
		# fold: a leg tucked up into / over the body. the paw has to hang well under its hip /
		# shoulder (a cat's leg can't fold shorter than about a third of its length), and
		# the knee / elbow stays under the back line
		if not on_wall and player.is_on_floor() and rig.sit < 0.03 and rig.loaf < 0.03 and rig.rear < 0.2 and float(g.free_w[i]) < 0.3:
			var sd := -1.0 if i % 2 == 0 else 1.0
			var girdle: Node3D = rig.chest if i < 2 else rig.pelvis
			var jl: Vector3 = Vector3(rig.FRONT_SHOULDER.x * sd, rig.FRONT_SHOULDER.y, rig.FRONT_SHOULDER.z) if i < 2 else Vector3(rig.HIND_HIP.x * sd, rig.HIND_HIP.y, rig.HIND_HIP.z)
			var jw: Vector3 = girdle.to_global(jl)
			var full: float = (rig.F_UP + rig.F_LO + rig.F_PA) if i < 2 else (rig.H_TH + rig.H_SH + rig.H_MT)
			var hang: float = (jw.y - c.y) / full
			var kn: Vector3 = (rig.legs[i].joint as Node3D).global_position
			var over_back: float = kn.y - (girdle.global_position.y + 0.03)
			m.frames_leg += 1
			m.hang_min = minf(m.hang_min, hang)
			if hang < 0.25 or over_back > 0.0:
				m.fold += 1
				if dbg == "fold":
					print("  fold %s hang %.2f knee over back %.0f mm mode %s t=%.2f fgy %.3f hgy %.3f sup %s paw_rel_y %.3f sw %.2f" % [LEG[i], hang, over_back * 1000.0, "PSF"[g.mode[i]], t, rig._fgy, rig._hgy, str(rig._sup), c.y - rig.global_position.y, g.sw_t[i]])
		cur["g%d" % i] = g.pos[i]
		if g.mode[i] == CatGait.PLANTED and g.load[i] > 0.5:
			m.stretch_max = maxf(m.stretch_max, float(g.stretch[i]))
			if g.stretch[i] > 1.005:
				m.over += 1
				if dbg == "stretch":
					print("  stretch %s %.2f t=%.2f st_s %.2f load %.2f v=%.1f" % [LEG[i], g.stretch[i], t, g.st_s[i], g.load[i], spd])
		if g.mode[i] == CatGait.PLANTED and g.load[i] > 0.5 and not on_wall and player.is_on_floor():
			m.planted += 1
			var gap: float = c.y - _ground(c) - float(rest_gap[i])
			m.gap.append(absf(gap))
			if gap > 0.012:
				m.hover += 1
			if gap < -0.012:
				m.sink += 1
			m.miss.append((c - (g.pos[i] as Vector3) - Vector3(0, float(rest_gap[i]), 0)).length())
			if _prev.has("c%d" % i) and int(_prev["m%d" % i]) == CatGait.PLANTED and not g.touched[i]:
				var sl: float = ((c - (_prev["c%d" % i] as Vector3)) * Vector3(1, 0, 1)).length()
				sl = maxf(sl - 0.1 * Vector2(player.velocity.x, player.velocity.z).length() * dt, 0.0)
				m.slide.append(sl)
				if dbg == "slide" and sl > 0.006:
					print("  slide %s %.1f mm t=%.2f v=%.1f st_s %.2f load %.2f stretch %.2f gpos moved %.1f mm" % [LEG[i], sl * 1000.0, t, spd, g.st_s[i], g.load[i], g.stretch[i], ((g.pos[i] as Vector3) - (_prev["g%d" % i] as Vector3)).length() * 1000.0])
	for pn in PARTS:
		var n: Node3D = rig.get(pn)
		var p := n.global_position
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			m.nan += 1
			continue
		cur[pn] = p
		# under the floor / in a wall
		var depth := 0.0
		if not on_wall:
			depth = maxf(depth, _ground(p) + 0.03 - p.y)
		depth = maxf(depth, _inside(p))
		if depth > 0.01:
			m.clip += 1
			if depth > m.clip_max:
				m.clip_max = depth
				m.clip_what = "%s @%.2fs" % [pn, t]
	for i in 4:
		if cur.has("c%d" % i):
			# 2.5 cm in from the pad (toward the body): a paw resting on a face is not in it
			var cp: Vector3 = cur["c%d" % i]
			var d := _inside(cp + Vector3.UP * 0.02 + (player.global_position + Vector3.UP * 0.1 - cp).normalized() * 0.02) if not on_wall else 0.0
			if d > 0.01:
				m.clip += 1
				if d > m.clip_max:
					m.clip_max = d
					m.clip_what = "%s paw @%.2fs" % [LEG[i], t]
	# pops: the change of a part's speed (world space) between two frames
	if not _prev.is_empty() and _prev.has("dt"):
		for key in cur.keys():
			if not (cur[key] is Vector3) or key.begins_with("v") or ((key.begins_with("c") or key.begins_with("g")) and key.length() == 2):
				continue
			if not _prev.has(key):
				continue
			var v: Vector3 = ((cur[key] as Vector3) - (_prev[key] as Vector3)) / dt
			cur["v" + key] = v
			if _prev.has("v" + key):
				var dv: float = (v - (_prev["v" + key] as Vector3)).length()
				var is_paw: bool = key.begins_with("l")
				# paws: a step meets the ground at ground speed, so up to ~1.5x the run speed + a flick
				var lim: float = (3.5 + 1.6 * spd) if is_paw else (1.6 + 0.12 * spd)
				if is_paw and int(key.substr(1)) < 2 and (rig.is_swatting() or player.combat.busy()):
					lim = 14.0   # a swat is a whip: 4 m/s paw tip, there and back in a few frames
				if dv > lim:
					m.pop += 1
					if dv / lim > m.pop_max:
						m.pop_max = dv / lim
						m.pop_what = "%s %.1f m/s @%.2fs" % [key if not is_paw else LEG[int(key.substr(1))], dv, t]
					if dbg == "pop":
						print("  pop %s dv=%.1f lim=%.1f t=%.2f ev=%s floor=%s" % [key, dv, lim, t, player.last_event, player.is_on_floor()])
	if dbg == "paws":
		var rg2 := rig.global_position
		var ln := "  t=%.3f root y %.3f z %.3f fgy %.3f hgy %.3f |" % [t, rg2.y, rg2.z, rig._fgy, rig._hgy]
		for i in 4:
			ln += " %s %s y%+.3f z%+.3f gy%+.3f |" % [LEG[i], "PSF"[g.mode[i]], (g.pos[i] as Vector3).y - rg2.y, (g.pos[i] as Vector3).z - rg2.z, g.ground_y(i) - rg2.y]
		print(ln)
	if dbg == "phys":
		var ln2 := "  t=%.3f v %.2f fgy %+.3f hgy %+.3f gv %+.2f %+.2f sup %.2f %.2f str %.2f du %.2f st_t %.3f gap %.3f |" % [t, player.velocity.length(), rig._fgy, rig._hgy, rig._gv[0], rig._gv[1], rig._sup[0], rig._sup[1], g.stride, g.duty, g.st_time, g.gap_time]
		for i in 4:
			ln2 += " %s %s ld %.1f st %.2f |" % [LEG[i], "PSF"[g.mode[i]], g.load[i], g.stretch[i]]
		print(ln2)
	if dbg == "head":
		var rg := rig.global_position
		print("  t=%.3f root %.3f %.3f | head rel %.3f %.3f %.3f | chest rel y %.3f | fgy %.3f hgy %.3f | soft %.3f | air %.2f floor %s" % [t, rg.y, rg.z, rig.head.global_position.x - rg.x, rig.head.global_position.y - rg.y, rig.head.global_position.z - rg.z, rig.chest.global_position.y - rg.y, rig._fgy, rig._hgy, player._soft_off.length(), rig._air_w, rig.on_floor])
	cur["dt"] = dt
	_prev = cur


static func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(p * (b.size() - 1)), 0, b.size() - 1)]


func _report(n: String) -> void:
	if n == "stand":
		# how high each paw's contact point sits over the floor when just standing = the zero
		pass
	var r := {
		"slide_p95_mm": snappedf(_pct(m.slide, 0.95) * 1000.0, 0.1), "slide_max_mm": snappedf(_pct(m.slide, 1.0) * 1000.0, 0.1),
		"gap_p95_mm": snappedf(_pct(m.gap, 0.95) * 1000.0, 0.1), "off_ground_pct": snappedf(100.0 * (m.hover + m.sink) / maxf(m.planted, 1), 0.1),
		"miss_p95_mm": snappedf(_pct(m.miss, 0.95) * 1000.0, 0.1), "miss_max_mm": snappedf(_pct(m.miss, 1.0) * 1000.0, 0.1), "over_pct": snappedf(100.0 * m.over / maxf(m.frames * 4, 1), 0.1),
		"stretch_max": snappedf(m.stretch_max, 0.001), "pops": m.pop, "pop_worst": snappedf(m.pop_max, 0.01), "pop_what": m.pop_what,
		"clip_frames": m.clip, "clip_max_mm": snappedf(m.clip_max * 1000.0, 0.1), "clip_what": m.clip_what,
		"fold_pct": snappedf(100.0 * m.fold / maxf(m.frames_leg, 1), 0.1), "hang_min": snappedf(m.hang_min, 0.01), "snaps": m.snap, "snap_max_mm": snappedf(m.snap_max * 1000.0, 0.1), "nan": m.nan,
		"planted_pct": snappedf(100.0 * m.planted / maxf(m.frames * 4, 1), 0.1), "dist_m": snappedf(m.dist, 0.01), "vmax": snappedf(m.vmax, 0.01), "air_s": snappedf(m.air, 0.01), "ymax": snappedf(m.ymax, 0.001), "events": m.ev,
	}
	results[n] = r
	if dbg == "count":
		print("  frames %d planted %d slide n %d  dist %.2f vmax %.2f gap0 %s miss0 %s c0 %s pos0 %s" % [m.frames, m.planted, m.slide.size(), m.dist, m.vmax, str(m.gap.slice(0, 3)), str(m.miss.slice(0, 3)), str(_contact(0)), str(player.rig.gait.pos[0])])
	print("BIO %-20s slide p95 %4.1f max %5.1f mm | off ground %4.1f%% gap p95 %4.1f | miss %4.1f max %5.1f | over %4.1f%% (%.2f) | pops %3d (x%.1f %s) | clip %3d (%.0f mm %s) | snaps %d (%.0f mm) | fold %.1f%% (min hang %.2f) | %s" % [
		n, r.slide_p95_mm, r.slide_max_mm, r.off_ground_pct, r.gap_p95_mm, r.miss_p95_mm, r.miss_max_mm, r.over_pct, r.stretch_max, r.pops, r.pop_worst, r.pop_what, r.clip_frames, r.clip_max_mm, r.clip_what, r.snaps, r.snap_max_mm, r.fold_pct, r.hang_min, ",".join(PackedStringArray(m.ev))])


## what counts as glitch free for one scenario
func _bad(r: Dictionary) -> Array:
	var why := []
	if r.nan > 0: why.append("nan")
	if r.pops > 0: why.append("pops %d" % r.pops)
	if r.clip_max_mm > 25.0: why.append("clip %.0f mm" % r.clip_max_mm)
	if r.off_ground_pct > 8.0: why.append("paws off ground %.0f%%" % r.off_ground_pct)
	if r.slide_p95_mm > 4.0: why.append("slide %.1f mm" % r.slide_p95_mm)
	# at a gallop the body covers 18 cm a frame: a paw may be that frame's 15% off its print
	if r.miss_max_mm > 15.0 + 2.5 * r.vmax: why.append("paw off its spot %.0f mm" % r.miss_max_mm)
	if r.snap_max_mm > 60.0: why.append("snap %.0f mm" % r.snap_max_mm)
	if r.fold_pct > 0.5: why.append("legs folded into the body %.1f%%" % r.fold_pct)
	return why


func _summary() -> void:
	var fails := 0
	for n in results:
		var why := _bad(results[n])
		if not why.is_empty():
			fails += 1
			print("BIO FAIL %-20s %s" % [n, ", ".join(PackedStringArray(why))])
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "  "))
	print("BIOTEST %s  %d / %d scenarios clean" % ["PASS" if fails == 0 else "FAIL", results.size() - fails, results.size()])


func _camera(dt: float) -> void:
	var p := player.global_position
	var want := p + Vector3(1.05, 0.22, 0.25)
	if cam.global_position.distance_to(want) > 3.0:
		cam.global_position = want
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-5.0 * dt))
	cam.look_at(p + Vector3(0, 0.1, -0.05), Vector3.UP)
