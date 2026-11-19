extends Node3D
## slide lab: the real CatPlayer (bot driven) slides down things it can't climb: a smooth tile
## wall (steering into it), the same wall let go of halfway (drops off), a wooden ramp too
## steep to stand on going down head first and facing up it. checks the slide happens, the
## speed it settles at, front paws ahead of the shoulders + hind feet behind the hips, fore
## claws on the surface while they drag, re-catches, and that it stops once it's on the floor.
##   godot --path . res://slidelab.tscn -- --slidetest [--only wall,ramp_down]     (xvfb)
##   godot --path . res://slidelab.tscn -- --show --write-movie out/f.png --fixed-fps 30   (xvfb)

const WALL_Z := -1.0          # wall face (wall runs along x, faces +z)
const RAMP_X := 4.0
const RAMP_ANG := deg_to_rad(64.0)   # from flat: normal.y = cos 64 = 0.44, too steep to stand on
const RUNS := {
	"wall": {"pos": Vector3(0, 3.6, WALL_Z + 0.09), "yaw": 0.0, "move": Vector2(0, 1), "t": 3.0},
	"letgo": {"pos": Vector3(1.4, 2.6, WALL_Z + 0.09), "yaw": 0.0, "move": Vector2(0, 1), "t": 2.0, "release": 0.5},
	"ramp_down": {"ramp": true, "head_up": false, "t": 3.0},
	"ramp_up": {"ramp": true, "head_up": true, "move": Vector2(0, 1), "t": 3.0},
	"wall_fp": {"pos": Vector3(-1.0, 3.6, WALL_Z + 0.09), "yaw": 0.0, "move": Vector2(0, 1), "t": 3.0, "fp": true, "show_only": true},
}
const LEG := ["LF", "RF", "LH", "RH"]

var player: CatPlayer
var cam: Camera3D
var show := false
var runs: Array = []
var ri := -1
var t := 0.0
var m := {}
var results := {}
var fails: Array[String] = []
var caption: Label
var ramp_n := Vector3.ZERO
var ramp_top := Vector3.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	show = "--show" in args
	process_priority = 100
	var only := []
	var k := args.find("--only")
	if k >= 0:
		only = Array(args[k + 1].split(","))
	for r in RUNS:
		if RUNS[r].get("show_only", false) and not show and not (r in only):
			continue
		if only.is_empty() or r in only:
			runs.append(r)
	_build()
	player = CatPlayer.new()
	if show:
		player.style = "block"    # the default black cat is hard to read against the shadows
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
	_next()


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
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 14.0
	add_child(sun)
	_box(Vector3(0, -0.1, 0), Vector3(16, 0.2, 12), Vector3.ZERO, Color(0.42, 0.4, 0.36), "wood")
	# smooth tiled wall, 4.5 m tall (too tall to grab the top from where the cat starts)
	_box(Vector3(0.5, 2.25, WALL_Z - 0.1), Vector3(5, 4.5, 0.2), Vector3.ZERO, Color(0.78, 0.8, 0.82), "tile")
	for i in 15:
		_box(Vector3(0.5, 0.3 * i + 0.15, WALL_Z - 0.003), Vector3(5, 0.006, 0.01), Vector3.ZERO, Color(0.6, 0.62, 0.64), "tile", false)
	# steep plank ramp: rises toward -z, top face tilted RAMP_ANG from flat
	var L := 3.2
	var b := Basis(Vector3.RIGHT, RAMP_ANG)
	var c := Vector3(RAMP_X, L * 0.5 * sin(RAMP_ANG), WALL_Z + 2.4 - L * 0.5 * cos(RAMP_ANG))
	_box(c - b.y * 0.06, Vector3(1.4, 0.12, L), Vector3(RAMP_ANG, 0, 0), Color(0.55, 0.4, 0.26), "wood")
	ramp_n = b.y
	ramp_top = c + b.z * (-L * 0.5 + 0.35)


func _box(pos: Vector3, size: Vector3, rot: Vector3, col: Color, surf: String, solid := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	mi.material_override = mat
	if not solid:
		mi.position = pos
		mi.rotation = rot
		add_child(mi)
		return
	var body := StaticBody3D.new()
	body.set_meta("surface", surf)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.add_child(mi)
	body.position = pos
	body.rotation = rot
	add_child(body)


func _next() -> void:
	if ri >= 0:
		_report(runs[ri])
	ri += 1
	if ri >= runs.size():
		_summary()
		get_tree().quit(1 if not fails.is_empty() else 0)
		return
	var r: String = runs[ri]
	var cfg: Dictionary = RUNS[r]
	var yaw: float = cfg.get("yaw", 0.0)
	var pos: Vector3 = cfg.get("pos", Vector3.ZERO)
	if cfg.get("ramp", false):
		# ramp rises toward -z. head up = facing -z (yaw 0), head first = facing +z (yaw PI)
		yaw = 0.0 if cfg.head_up else PI
		pos = ramp_top + ramp_n * 0.1
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.yaw = yaw
	player.orb_yaw = yaw
	player.rotation.y = yaw
	player._end_slide()
	if show:
		player.set_third_person(not cfg.get("fp", false))
		if cfg.get("fp", false):
			player.cam.make_current()
		else:
			cam.make_current()
	player.bot = {"move": cfg.get("move", Vector2.ZERO), "yaw": yaw, "pitch": -0.1}
	t = 0.0
	m = {"n": 0, "slide_n": 0, "vy": [], "fore_ahead": 0, "hind_behind": 0, "fore_on": 0, "fore_planted": 0,
		"catch0": player.rig.slide_fx.catches, "head_up": [], "landed_still": false, "slid_t": 0.0, "max_w": 0.0}
	if caption:
		caption.text = {"wall": "smooth tile wall: steering into it", "letgo": "let go halfway: drops off",
			"ramp_down": "too steep ramp: going down head first", "ramp_up": "too steep ramp: facing up it",
			"wall_fp": "first person: sliding down the tile wall"}[r]


func _physics_process(dt: float) -> void:
	if ri < 0 or ri >= runs.size():
		return
	t += dt
	var cfg: Dictionary = RUNS[runs[ri]]
	if cfg.has("release") and t > float(cfg.release):
		player.bot.move = Vector2.ZERO
	if t > float(cfg.t):
		_next()


func _process(_dt: float) -> void:
	if ri < 0 or ri >= runs.size() or player == null:
		return
	var r: String = runs[ri]
	if cam:
		var p := player.global_position
		if RUNS[r].get("ramp", false):
			cam.global_position = p + Vector3(1.5, 0.3, 0.25)
		else:
			cam.global_position = p + Vector3(0.95, 0.05, 0.75)
		cam.look_at(p + Vector3(0, 0.05, 0))
	if OS.get_cmdline_user_args().has("--dbg") and Engine.get_process_frames() % 6 == 0:
		print("t %.2f p %s v %s floor %s slide %s seen %.2f wall_t %.2f n %s ev %s mant %s clamb %s scr %.2f" % [t, player.global_position, player.velocity, player.is_on_floor(), player.sliding, player._slide_seen, player.wall_time, player.slide_n, player.last_event, player.mantling, player.clambering, player.scramble_t])
	if t < 0.15:
		return
	m.n += 1
	m.max_w = maxf(m.max_w, player.w_slide)
	if not player.sliding or player.w_slide < 0.8:
		if player.is_on_floor() and t > 1.5 and not player.sliding:
			m.landed_still = true
		return
	m.slide_n += 1
	m.slid_t += _dt
	m.vy.append(player.velocity.y)
	m.head_up.append(player.slide_head_up)
	var rig := player.rig
	var xf := rig.global_transform
	var inv := xf.affine_inverse()
	var n := player.slide_n
	var plane_d := n.dot(xf.origin)   # the rig sits on the surface (rig y 0 = the face)
	var sh: Vector3 = (inv * rig.legs[0].paw.global_position + inv * rig.legs[1].paw.global_position) * 0.5
	var hp: Vector3 = (inv * rig.legs[2].paw.global_position + inv * rig.legs[3].paw.global_position) * 0.5
	# fore paws out ahead of the shoulders (rig -z), hind feet back behind the hips
	if sh.z < (rig.HOME[0] as Vector3).z - 0.03:
		m.fore_ahead += 1
	if hp.z > (rig.HOME[2] as Vector3).z + 0.02:
		m.hind_behind += 1
	for i in 2:
		if rig.slide_fx.planted[i]:
			m.fore_planted += 1
			var cp: Vector3 = rig.legs[i].paw.global_transform * Vector3(0, -0.010, 0.006)
			if OS.get_cmdline_user_args().has("--dbg") and Engine.get_process_frames() % 10 == 0:
				print("paw %d off %.3f target %s actual %s  pivot %s" % [i, n.dot(cp) - plane_d, rig.slide_fx.foot[i], inv * cp, rig.pivot.position])
			if absf(n.dot(cp) - plane_d) < 0.03:
				m.fore_on += 1


func _report(r: String) -> void:
	var vy: Array = m.vy
	var tail := vy.slice(int(vy.size() * 0.6)) if vy.size() > 4 else vy
	var vavg := 0.0
	for v in tail:
		vavg += float(v)
	vavg = vavg / maxf(tail.size(), 1)
	var hu := 0
	for h in m.head_up:
		if h:
			hu += 1
	var sn := maxi(m.slide_n, 1)
	var res := {
		"slid_s": snappedf(m.slid_t, 0.01),
		"vy_settled": snappedf(vavg, 0.01),
		"fore_ahead": snappedf(float(m.fore_ahead) / sn, 0.01),
		"hind_behind": snappedf(float(m.hind_behind) / sn, 0.01),
		"fore_on_surface": snappedf(float(m.fore_on) / maxf(m.fore_planted, 1), 0.01),
		"catches": player.rig.slide_fx.catches - int(m.catch0),
		"head_up": snappedf(float(hu) / sn, 0.01),
		"landed_still": m.landed_still,
	}
	results[r] = res
	print("SLIDE %s %s" % [r, JSON.stringify(res)])
	var cfg: Dictionary = RUNS[r]
	if r == "wall_fp":
		return
	if r == "letgo":
		_check(r, m.slid_t > 0.1 and m.slid_t < 0.75, "slid then let go (slid %.2f s)" % m.slid_t)
		_check(r, m.landed_still, "on the floor, not sliding")
		return
	_check(r, m.slid_t > 0.4, "slid (%.2f s)" % m.slid_t)
	_check(r, res.fore_ahead > 0.85, "fore paws ahead of the shoulders %.2f" % res.fore_ahead)
	_check(r, res.hind_behind > 0.85, "hind feet behind the hips %.2f" % res.hind_behind)
	_check(r, res.fore_on_surface > 0.8, "dragging fore claws on the surface %.2f" % res.fore_on_surface)
	_check(r, res.catches >= 2, "fore paws re-catch (%d)" % res.catches)
	_check(r, res.landed_still, "stops sliding on the floor")
	var want_up: bool = cfg.get("head_up", true)
	_check(r, (res.head_up > 0.9) == want_up, "head %s" % ("up" if want_up else "first"))
	if r == "wall":
		_check(r, vavg < -1.6 and vavg > -2.6, "settles near the tile slide speed (%.2f m/s)" % vavg)


func _check(r: String, ok: bool, what: String) -> void:
	if not ok:
		fails.append("%s: %s" % [r, what])
		print("  FAIL %s: %s" % [r, what])


func _summary() -> void:
	if fails.is_empty():
		print("SLIDETEST PASS")
	else:
		print("SLIDETEST FAIL (%d)" % fails.size())
