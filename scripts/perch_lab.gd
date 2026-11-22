extends Node3D
## perch lab: drops the cat onto small / narrow tops (posts, rails, a fence board, a branch, a
## box, a bin lid, a ledge on a wall) and lets it stand there and settle, to check (and film)
## that all four paws end up on the top (cat_perch.gd).
## `godot --headless --fixed-fps 60 --path . res://perchlab.tscn -- --perchtest`
##   --perchtest  per perch: share of planted paw frames that aren't on the top, falls off, sits
##   --film       side camera + caption, for clips (xvfb, with --write-movie)
##   --only a,b   just these perches
##   CAT_OFF=perch  the before (paws keep their normal stance, off the edges into the air)
##   PERCH_DBG=1    print paw spots / the box twice a second

const H := 0.9            # perch tops this high off the floor
const SPACE := 3.0
# name, kind, size, spawn offset (along -z), time, bot move, caption
const PERCHES := [
	["post", "box", Vector3(0.09, H, 0.09), 0.0, 7.0, Vector2.ZERO, "fence post 9 cm"],
	["post_drop", "box", Vector3(0.09, H, 0.09), 0.0, 6.0, Vector2.ZERO, "fence post 9 cm, dropping on"],
	["round_post", "cyl", Vector3(0.065, H, 0.0), 0.0, 7.0, Vector2.ZERO, "round post 13 cm"],
	["rail_across", "box", Vector3(1.6, H, 0.05), 0.0, 6.0, Vector2.ZERO, "railing 5 cm, across"],
	["rail_along", "box", Vector3(0.05, H, 1.6), 0.0, 6.0, Vector2.ZERO, "railing 5 cm, along"],
	["fence_top", "box", Vector3(0.09, H, 2.4), 0.6, 6.0, Vector2(0, 0.45), "fence top 9 cm, walking"],
	["branch", "branch", Vector3(0.04, H, 1.8), 0.0, 6.0, Vector2.ZERO, "branch 8 cm"],
	["box", "box", Vector3(0.2, H, 0.2), 0.0, 7.0, Vector2.ZERO, "box 20 cm"],
	["bin", "cyl", Vector3(0.17, H, 0.0), 0.0, 6.0, Vector2.ZERO, "bin lid 34 cm"],
	["ledge", "ledge", Vector3(0.08, H, 1.6), 0.0, 6.0, Vector2.ZERO, "ledge 8 cm on a wall"],
]

var player: CatPlayer
var cam: Camera3D
var label: Label
var film := false
var test := false
var list: Array = []
var cur := -1
var t := 0.0
var tops: Array = []      # the top's body per perch
var res := {}
var _off := 0
var _n := 0
var _fell := false
var _sat := 0.0
var _w := 0.0
var _sq := 0.0
var _nan := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	film = "--film" in args
	test = "--perchtest" in args
	var only := []
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1].split(",")
	for p in PERCHES:
		if only.is_empty() or (p[0] in only):
			list.append(p)
	var fl := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(80, 1, 20)
	fs.shape = bx
	fs.position = Vector3(SPACE * 4, -0.5, 0)
	fl.add_child(fs)
	add_child(fl)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 20)
	fm.mesh = pm
	fm.position = Vector3(SPACE * 4, 0, 0)
	fm.material_override = _mat(Color(0.36, 0.45, 0.3))
	add_child(fm)
	for k in list.size():
		tops.append(_build(list[k], Vector3(k * SPACE, 0, 0)))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.9, 0)
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
	player.global_position = Vector3(0, H + 0.1, 0)
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
	player.set_third_person(true)
	if film:
		cam = Camera3D.new()
		cam.fov = 32.0
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


func _body(shape: Shape3D, mesh: Mesh, at: Vector3, rot := Vector3.ZERO, col := Color(0.55, 0.42, 0.3)) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	b.add_child(mi)
	b.position = at
	b.rotation = rot
	b.set_meta("surface", "wood")
	add_child(b)
	return b


func _build(p: Array, at: Vector3) -> StaticBody3D:
	var s: Vector3 = p[2]
	match p[1]:
		"box":
			var bs := BoxShape3D.new()
			bs.size = s
			var bm := BoxMesh.new()
			bm.size = s
			return _body(bs, bm, at + Vector3(0, s.y * 0.5, 0))
		"cyl":
			var cs := CylinderShape3D.new()
			cs.radius = s.x
			cs.height = s.y
			var cm := CylinderMesh.new()
			cm.top_radius = s.x
			cm.bottom_radius = s.x
			cm.height = s.y
			cm.radial_segments = 16
			return _body(cs, cm, at + Vector3(0, s.y * 0.5, 0), Vector3.ZERO, Color(0.4, 0.45, 0.5) if s.x > 0.1 else Color(0.55, 0.42, 0.3))
		"branch":
			# a log along z, top at H, held up by a post at each end
			var cs2 := CylinderShape3D.new()
			cs2.radius = s.x
			cs2.height = s.z
			var cm2 := CylinderMesh.new()
			cm2.top_radius = s.x
			cm2.bottom_radius = s.x
			cm2.height = s.z
			cm2.radial_segments = 10
			for e in [-1.0, 1.0]:
				var ps := BoxShape3D.new()
				ps.size = Vector3(0.06, H - s.x * 2.0, 0.06)
				var pmh := BoxMesh.new()
				pmh.size = ps.size
				_body(ps, pmh, at + Vector3(0, (H - s.x * 2.0) * 0.5, e * s.z * 0.45), Vector3.ZERO, Color(0.4, 0.3, 0.22))
			return _body(cs2, cm2, at + Vector3(0, H - s.x, 0), Vector3(PI * 0.5, 0, 0), Color(0.42, 0.32, 0.22))
		"ledge":
			# a shelf 8 cm deep sticking out of a wall on the cat's right
			var ws := BoxShape3D.new()
			ws.size = Vector3(0.2, H + 0.7, s.z + 0.4)
			var wm := BoxMesh.new()
			wm.size = ws.size
			_body(ws, wm, at + Vector3(s.x * 0.5 + 0.1, (H + 0.7) * 0.5, 0), Vector3.ZERO, Color(0.75, 0.72, 0.66))
			var ls := BoxShape3D.new()
			ls.size = Vector3(s.x, 0.04, s.z)
			var lm := BoxMesh.new()
			lm.size = ls.size
			return _body(ls, lm, at + Vector3(0, H - 0.02, 0))
	return null


func _next() -> void:
	if cur >= 0:
		_report()
	cur += 1
	if cur >= list.size():
		_done()
		return
	var p: Array = list[cur]
	t = 0.0
	_off = 0
	_n = 0
	_fell = false
	_sat = 0.0
	_w = 0.0
	_sq = 0.0
	player.velocity = Vector3.ZERO
	if player.rig:
		# (each perch starts fresh: standing, not still sitting from the last one)
		player.rig.soma.act("up")
		player.rig._sit_s = 0.0
		player.rig._loaf_s = 0.0
		player.rig._still_t = 0.0
	player.global_position = Vector3(cur * SPACE, H + (0.45 if p[0].ends_with("_drop") else 0.08), float(p[3]))
	player.bot = {"move": Vector2.ZERO, "yaw": 0.0, "pitch": -0.2}


func _physics_process(dt: float) -> void:
	if cur < 0 or cur >= list.size():
		return
	t += dt
	var p: Array = list[cur]
	if t > 1.0:
		# (walking ones stop short of the end of the top)
		var mv: Vector2 = p[5] if player.global_position.z > -float(p[2].z) * 0.5 + 0.45 else Vector2.ZERO
		player.bot = {"move": mv, "yaw": 0.0, "pitch": -0.2}
	if OS.get_environment("PERCH_DBG") != "" and int(t * 60) % 30 == 0:
		var rig: CatRig = player.rig
		var inv := player.global_transform.affine_inverse()
		var s2 := ""
		for i in 4:
			var lp: Vector3 = inv * (rig.gait.pos[i] as Vector3)
			s2 += " %d:(%.3f,%.3f,%.3f)%d" % [i, lp.x, lp.y, lp.z, rig.gait.mode[i]]
		print("dbg t%.1f root %s on %s box x[%.3f %.3f] z[%.3f %.3f] w %.2f %s" % [t, str(player.global_position), rig.perch.on, rig.perch.x0, rig.perch.x1, rig.perch.z0, rig.perch.z1, rig.perch.w, s2])
	if t > float(p[4]):
		_next()


## once per rendered frame, after the rig has posed
func sample(dt: float) -> void:
	if cur < 0 or cur >= list.size() or player.rig == null:
		return
	var p: Array = list[cur]
	var pos := player.global_position
	if cam:
		var c := Vector3(cur * SPACE, H, pos.z)
		var want := c + Vector3(-0.95 if p[1] == "ledge" else 0.95, 0.12, 0.55)
		cam.global_position = want if cam.global_position.distance_to(want) > 1.5 else cam.global_position.lerp(want, 1.0 - exp(-4.0 * dt))
		cam.look_at(Vector3(cur * SPACE, H + 0.12, pos.z))
	var rig: CatRig = player.rig
	if label:
		var bits := "before" if not CatPerch.perch else "after"
		var what := ""
		if rig._sit_s > 0.5:
			what = "  (sits)"
		elif rig._loaf_s > 0.5:
			what = "  (loafs)"
		label.text = "%s  -  %s%s" % [bits, p[6], what]
	if pos.y < H - 0.15:
		_fell = true
	if is_nan(pos.x) or is_nan(rig.pivot.global_position.y):
		_nan = true
	if t < 1.2:
		return   # (dropping on, settling)
	var space := get_world_3d().direct_space_state
	for i in 4:
		if rig.gait.mode[i] != CatGait.PLANTED:
			continue
		var pp: Vector3 = rig.gait.pos[i]
		var q := PhysicsRayQueryParameters3D.create(pp + Vector3(0, 0.03, 0), pp - Vector3(0, 0.03, 0))
		q.exclude = rig.gait.exclude
		var hit := space.intersect_ray(q)
		_n += 1
		if hit.is_empty() or (hit.normal as Vector3).y < 0.3:
			_off += 1
			if OS.get_environment("PERCH_DBG") != "" and _off < 5:
				print("off paw %d at %s hit %s" % [i, str(pp), str(hit)])
	_w = maxf(_w, rig.perch.w)
	_sq = maxf(_sq, rig.perch.squeeze)
	if rig._sit_s > 0.5 or rig._loaf_s > 0.5:
		_sat += dt


func _report() -> void:
	var p: Array = list[cur]
	var off := float(_off) / maxf(_n, 1)
	res[p[0]] = [off, _fell, _sat]
	print("PERCH %-12s paws off %5.1f%%  fell %s  sat %.1fs  perch %.2f  squeeze %.2f" % [p[0], off * 100.0, "YES" if _fell else "no", _sat, _w, _sq])


func _done() -> void:
	if test:
		var fails := []
		for k in res:
			var r: Array = res[k]
			if float(r[0]) > 0.02:
				fails.append("%s paws off %.0f%%" % [k, float(r[0]) * 100.0])
			if r[1]:
				fails.append(k + " fell")
		if _nan:
			fails.append("nan")
		print("PERCHTEST %s %d / %d %s" % ["PASS" if fails.is_empty() else "FAIL", res.size() - fails.size(), res.size(), str(fails)])
	get_tree().quit()


class Tracker extends Node:
	var lab: Node
	func _ready() -> void:
		process_priority = 100
	func _process(dt: float) -> void:
		lab.sample(dt)
