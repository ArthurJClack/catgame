extends Node3D
## movement scoreboard: the real CatPlayer (bot driven) does set maneuvers on each surface and the
## numbers that come out are put next to what a real house cat does (the table in the movement
## plan). biolab checks that the cat doesn't glitch, this checks that it moves like a cat.
##
## it is a scoreboard, not a gate: rows outside the band print "off" and the run still exits 0.
## each phase of the movement plan should move its rows into the band without knocking others out.
##
##   godot --headless --fixed-fps 60 --path . res://movelab.tscn -- --realtest [--only sprint_tile,hop_tap] [--csv out.csv]
##   --real 0 turns CatPlayer.real_move off where the build has it (before / after)
##
## rows (unit, band):
##   start_g_<surface>   mean push off a stand up to 3 m/s, in g. band = what the surface holds (mu), capped by the legs
##   to10_<surface>      seconds from a stand to 10 m/s
##   brake_g_<surface>   mean braking from a gallop (stick let go + crouch = paws dug in), in g. band = mu
##   brake_m_<surface>   metres that stop takes
##   turn_g_<gait>_<surface>  sideways g held in the tightest turn. band = mu
##   turn_r_<gait>_<surface>  radius of that turn (info: follows from the g row)
##   hop_tap_m / hop_full_m   apex of a tapped / fully held standing hop
##   takeoff_tap_s / takeoff_full_s   press to paws leaving the floor
##   run_jump_m          apex of a full hop out of a gallop (fast run = long and low)
##   air_turn_deg        how far the flight path bends when steering 90 deg in the air
##   air_gain_ms         speed gained in the air by steering
##   drop15_keep / drop4_keep   share of run speed left 0.25 s after landing a 1.5 / 4 m drop
##   drop8_hurt          health lost landing an 8 m drop
##   hill_ratio          speed 10 m into a sprint up a 20 deg hill / the same on the flat
##   steep_slide_m       metres slid in 2.5 s standing on 35 deg tile (real paws can't hold it)

const MU := {"wood": 0.55, "tile": 0.45, "dirt": 0.85, "grass": 1.0, "carpet": 1.2}
const LANE := {"wood": 0.0, "tile": 70.0, "dirt": 140.0, "grass": 210.0, "carpet": 280.0}
const LEG_G := 0.92          # the hardest the legs shove off a stand whatever the footing (PUSH_ACCEL / g)
const HILL := 20.0
const STEEP := 35.0

var player: CatPlayer
var names: Array = []
var scen := {}
var si := -1
var t := 0.0
var csv_path := ""
var tr := {}                 # trace of the running scenario
var rows: Array = []         # [name, value, unit, lo, hi]
var keep := {}               # values other rows need (flat sprint for the hill ratio)
var _orb := 0.0
var _hp0 := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--csv")
	if k >= 0:
		csv_path = args[k + 1]
	k = args.find("--real")
	var ps: Script = load("res://scripts/cat_player.gd")
	if k >= 0 and ps.get("real_move") != null:
		ps.set("real_move", args[k + 1] != "0")
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
	_next.call_deferred()


# ---------------------------------------------------------------- course

func _box(pos: Vector3, size: Vector3, surface: String, rot := Vector3.ZERO) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	b.add_child(cs)
	b.position = pos
	b.rotation = rot
	b.set_meta("surface", surface)
	add_child(b)


## a ramp rising toward -z from (x, 0, z0): top face starts at the floor
func _ramp(x: float, z0: float, deg: float, length: float, surface: String) -> void:
	var a := deg_to_rad(deg)
	_box(Vector3(x, 0.5 * length * sin(a) - 0.1 * cos(a), z0 - 0.5 * length * cos(a) - 0.1 * sin(a)), Vector3(4.0, 0.2, length), surface, Vector3(a, 0, 0))


func _build() -> void:
	# one 64 x 110 m slab per surface, 70 m apart: room for a gallop and a wide turn on each
	for s in LANE:
		_box(Vector3(LANE[s], -0.5, -45.0), Vector3(64, 1, 110), s)
	# drop towers on the wood slab: trot off the -z end
	for d in [[-10.0, 1.5], [-18.0, 4.0], [-26.0, 8.0]]:
		_box(Vector3(d[0], d[1] * 0.5, -2.0), Vector3(2.0, d[1], 4.0), "wood")
	_ramp(LANE.grass + 24.0, 0.0, HILL, 16.0, "grass")
	_ramp(LANE.tile + 24.0, 0.0, STEEP, 6.0, "tile")


# ---------------------------------------------------------------- scenarios
# each: [x, y, z, seconds, f(t) -> bot dict, f() -> rows]. the bot dict key "steer" is handled
# here: radians the cat steers off its current path (0 = hold the heading it started with)

func _go(extra := {}) -> Dictionary:
	var d := {"move": Vector2(0, 1), "pitch": -0.1}
	d.merge(extra, true)
	return d


func _scenarios() -> void:
	var idle := {"move": Vector2.ZERO, "pitch": -0.1}
	for s in LANE:
		var x: float = LANE[s]
		scen["sprint_" + s] = [x, 0.0, 8.0, 9.0,
			func(tt): return _go({"sprint": true}) if tt < 5.0 else {"move": Vector2.ZERO, "pitch": -0.1, "crouch": true},
			_m_sprint.bind(s)]
		for g in [["trot", {}, 1.5], ["gallop", {"sprint": true}, 4.0]]:
			var t0: float = g[2]
			var ex: Dictionary = g[1]
			scen["turn_%s_%s" % [g[0], s]] = [x - 14.0, 0.0, 8.0, t0 + 3.0,
				func(tt): return _go(ex.merged({"steer": 0.5 if tt > t0 else 0.0})),
				_m_turn.bind("%s_%s" % [g[0], s], t0, MU[s])]
	scen["hop_tap"] = [0.0, 0.0, 0.0, 2.5, func(tt): return idle.merged({"jump": tt > 0.5 and tt < 0.6, "hop_mul": CatPlayer.HOP_TAP_MUL}), _m_hop.bind("tap", 0.5, 0.10, 0.50, 0.03, 0.08)]
	scen["hop_full"] = [0.0, 0.0, 0.0, 3.0, func(tt): return idle.merged({"jump": tt > 0.5 and tt < 0.6, "hop_charge": 1.0}), _m_hop.bind("full", 0.5, 1.30, 1.60, 0.12, 0.30)]
	scen["run_jump"] = [0.0, 0.0, 8.0, 5.5, func(tt): return _go({"sprint": true, "jump": tt > 3.5 and tt < 3.6, "hop_charge": 1.0}), _m_run_jump]
	scen["air_steer"] = [0.0, 0.0, 0.0, 3.5, func(tt): return _go({"jump": tt > 1.5 and tt < 1.6, "hop_charge": 1.0, "air_steer": 1.5708}), _m_air]
	scen["drop15"] = [-10.0, 1.5, -0.4, 4.0, func(_t): return _go(), _m_drop.bind("drop15_keep", 0.55, 1.0)]
	scen["drop4"] = [-18.0, 4.0, -0.4, 4.5, func(_t): return _go(), _m_drop.bind("drop4_keep", 0.0, 0.35)]
	scen["drop8"] = [-26.0, 8.0, -0.4, 5.0, func(_t): return _go(), _m_hurt]
	scen["hill"] = [LANE.grass + 24.0, 0.0, 1.0, 4.0, func(_t): return _go({"sprint": true}), _m_hill]
	var a := deg_to_rad(STEEP)
	scen["steep"] = [LANE.tile + 24.0, 3.0 * sin(a) + 0.03, -3.0 * cos(a), 3.0, func(_t): return idle, _m_steep]


func _next() -> void:
	if si >= 0:
		(scen[names[si]][5] as Callable).call()
	si += 1
	if si >= names.size():
		_summary()
		get_tree().quit()
		return
	var s: Array = scen[names[si]]
	player.global_position = Vector3(float(s[0]), float(s[1]) + 0.02, float(s[2]))
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.orb_yaw = 0.0
	player.rotation.y = 0.0
	for k in ["climbing", "clambering", "mantling", "scratching", "charging", "wall_sliding"]:
		player.set(k, false)
	player.kick_plant_t = 0.0
	player.wall_time = 10.0
	player.wall_collider = null
	player.crouch_amt = 0.0
	player.rig.sit = 0.0
	player.rig.idle_life = false
	player.rig.gait._ready_done = false
	player.health.heal_full()
	player.health.grace = 0.0
	player.bot = {"move": Vector2.ZERO, "pitch": -0.1}
	_orb = 0.0
	_hp0 = player.health.value
	t = -0.6
	tr = {"t": [], "p": [], "v": [], "vy": [], "fl": [], "hp": [], "jump": []}


func _heading(v: Vector2) -> float:
	return atan2(-v.x, -v.y)


func _physics_process(dt: float) -> void:
	if si < 0 or si >= names.size():
		return
	t += dt
	var s: Array = scen[names[si]]
	var hv := Vector2(player.velocity.x, player.velocity.z)
	if t >= 0.0:
		var b: Dictionary = (s[4] as Callable).call(t)
		if b.has("steer"):
			if float(b.steer) != 0.0 and hv.length() > 0.3:
				_orb = _heading(hv) + float(b.steer)
			b.erase("steer")
		if b.has("air_steer"):
			_orb = float(b.air_steer) if (not player.is_on_floor() and t > 1.5) else (_orb if t > 1.6 else 0.0)
			b.erase("air_steer")
		player.orb_yaw = _orb
		player.bot = b
		tr.t.append(t)
		tr.p.append(player.global_position)
		tr.v.append(hv)
		tr.vy.append(player.velocity.y)
		tr.fl.append(player.is_on_floor())
		tr.hp.append(player.health.value)
		tr.jump.append(bool(b.get("jump", false)))
	if t > float(s[3]):
		_next()


# ---------------------------------------------------------------- measuring

func _row(name: String, value: float, unit: String, lo: float, hi: float) -> void:
	rows.append([name, value, unit, lo, hi])


func _idx(time: float) -> int:
	var i: int = tr.t.bsearch(time)
	return clampi(i, 0, tr.t.size() - 1)


func _speed(i: int) -> float:
	return (tr.v[i] as Vector2).length()


func _path(i0: int, i1: int) -> float:
	var d := 0.0
	for i in range(i0 + 1, i1 + 1):
		var a: Vector3 = tr.p[i - 1]
		var b: Vector3 = tr.p[i]
		d += Vector2(b.x - a.x, b.z - a.z).length()
	return d


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	a.sort()
	return a[a.size() / 2]


func _m_sprint(surf: String) -> void:
	var mu: float = MU[surf]
	var n: int = tr.t.size()
	# push off a stand: mean over the first 3 m/s (single strides pulse, so no peak picking)
	var peak := 0.0
	for i in n:
		if _speed(i) >= 3.0:
			peak = 3.0 / maxf(tr.t[i], 0.01)
			break
	var cap := minf(mu, LEG_G)
	_row("start_g_" + surf, peak / 9.8, "g", cap * 0.75, cap * 1.08)
	var t10 := -1.0
	var i10 := -1
	for i in n:
		if _speed(i) >= 10.0:
			t10 = tr.t[i]
			i10 = i
			break
	# no quicker than the footing allows (10 m/s at mu g the whole way) or than the legs manage on
	# good ground (~1.6 s), and not a lot slower than that either
	var fast := maxf(1.6, 10.0 / (mu * 9.8))
	_row("to10_" + surf, t10, "s", fast, fast * 2.2)
	if i10 >= 0:
		keep["sprint10_" + surf] = _path(0, i10)
		keep["tr_" + surf] = [tr.t.duplicate(), tr.p.duplicate(), tr.v.duplicate()]
	var i0 := _idx(5.0)
	var v0 := _speed(i0)
	var i1 := i0
	while i1 < n - 1 and _speed(i1) > 1.0:
		i1 += 1
	if i1 > i0 and i1 < n - 1:
		_row("brake_g_" + surf, (v0 - _speed(i1)) / (tr.t[i1] - tr.t[i0]) / 9.8, "g", mu * 0.75, mu * 1.08)
		_row("brake_m_" + surf, _path(i0, i1), "m", v0 * v0 / (2.0 * 9.8 * mu * 1.08), v0 * v0 / (2.0 * 9.8 * mu * 0.75))
	else:
		_row("brake_g_" + surf, -1.0, "g", mu * 0.75, mu * 1.08)


func _m_turn(tag: String, t0: float, mu: float) -> void:
	var lat := []
	var rad := []
	for i in range(_idx(t0 + 0.8), tr.t.size()):
		var a: Vector2 = tr.v[i - 1]
		var b: Vector2 = tr.v[i]
		if a.length() < 0.5 or b.length() < 0.5:
			continue
		var w: float = absf(wrapf(_heading(b) - _heading(a), -PI, PI)) / float(tr.t[i] - tr.t[i - 1])
		lat.append(b.length() * w / 9.8)
		if w > 0.001:
			rad.append(b.length() / w)
	_row("turn_g_" + tag, _median(lat), "g", mu * 0.75, mu * 1.08)
	_row("turn_r_" + tag, _median(rad), "m", 0.0, 0.0)


func _air_span() -> Array:
	var i0 := -1
	var i1 := -1
	for i in range(1, tr.t.size()):
		if i0 < 0 and tr.fl[i - 1] and not tr.fl[i]:
			i0 = i
		elif i0 >= 0 and tr.fl[i] and tr.t[i] - tr.t[i0] > 0.05:
			i1 = i
			break
	return [i0, i1]


func _press() -> int:
	for i in tr.t.size():
		if tr.jump[i]:
			return i
	return -1


func _apex(i0: int) -> float:
	var top := -1e9
	for i in range(i0, tr.t.size()):
		top = maxf(top, (tr.p[i] as Vector3).y)
	return top - (tr.p[maxi(i0 - 1, 0)] as Vector3).y


func _m_hop(tag: String, _tp: float, lo: float, hi: float, dlo: float, dhi: float) -> void:
	var sp := _air_span()
	var pr := _press()
	if sp[0] < 0 or pr < 0:
		_row("hop_%s_m" % tag, -1.0, "m", lo, hi)
		return
	_row("hop_%s_m" % tag, _apex(sp[0]), "m", lo, hi)
	_row("takeoff_%s_s" % tag, tr.t[sp[0]] - tr.t[pr], "s", dlo, dhi)


func _m_run_jump() -> void:
	var sp := _air_span()
	if sp[0] < 0:
		_row("run_jump_m", -1.0, "m", 0.2, 0.5)
		return
	_row("run_jump_m", _apex(sp[0]), "m", 0.2, 0.5)


func _m_air() -> void:
	var sp := _air_span()
	if sp[0] < 0 or sp[1] < 0:
		_row("air_turn_deg", -1.0, "deg", 0.0, 12.0)
		return
	var a: Vector2 = tr.v[sp[0]]
	var b: Vector2 = tr.v[sp[1] - 1]
	_row("air_turn_deg", absf(rad_to_deg(wrapf(_heading(b) - _heading(a), -PI, PI))), "deg", 0.0, 12.0)
	_row("air_gain_ms", b.length() - a.length(), "m/s", -1.0, 0.3)


func _m_drop(name: String, lo: float, hi: float) -> void:
	var sp := _air_span()
	if sp[0] < 0 or sp[1] < 0:
		_row(name, -1.0, "x", lo, hi)
		return
	var before := _speed(sp[0] - 1)
	var after := _speed(_idx(tr.t[sp[1]] + 0.25))
	_row(name, after / maxf(before, 0.1), "x", lo, hi)
	if name == "drop15_keep":
		_row("drop15_hurt", _hp0 - float(tr.hp[-1]), "hp", 0.0, 0.0)


func _m_hurt() -> void:
	_row("drop8_hurt", _hp0 - float(tr.hp[-1]), "hp", 5.0, 60.0)


func _m_hill() -> void:
	# speed after 10 m of path (1 m of flat, then the hill) against the flat grass sprint at the same distance
	var up := -1.0
	for i in tr.t.size():
		if _path(0, i) >= 10.0:
			up = _speed(i)
			break
	keep["hill10"] = up


func _m_steep() -> void:
	_row("steep_slide_m", ((tr.p[-1] as Vector3) - (tr.p[_idx(0.5)] as Vector3)).length(), "m", 0.5, 20.0)


func _summary() -> void:
	if keep.has("hill10") and keep.has("tr_grass"):
		var g: Array = keep.tr_grass
		var d := 0.0
		var flat := -1.0
		for i in range(1, g[0].size()):
			var a: Vector3 = g[1][i - 1]
			var b: Vector3 = g[1][i]
			d += Vector2(b.x - a.x, b.z - a.z).length()
			if d >= 10.0:
				flat = (g[2][i] as Vector2).length()
				break
		if flat > 0.0 and keep.hill10 > 0.0:
			_row("hill_ratio", keep.hill10 / flat, "x", 0.6, 0.88)
	var ok := 0
	var scored := 0
	var csv := "row,value,unit,lo,hi,verdict\n"
	for r in rows:
		var info: bool = r[3] == 0.0 and r[4] == 0.0 and not String(r[0]).ends_with("_hurt")
		var good: bool = r[1] >= r[3] - 1e-6 and r[1] <= r[4] + 1e-6
		var verdict := "info" if info else ("ok" if good else "off")
		if not info:
			scored += 1
			ok += 1 if good else 0
		print("REAL %-22s %8.2f %-4s  cat %5.2f .. %5.2f  %s" % [r[0], r[1], r[2], r[3], r[4], verdict])
		csv += "%s,%.3f,%s,%.3f,%.3f,%s\n" % [r[0], r[1], r[2], r[3], r[4], verdict]
	print("REALTEST %d / %d rows in the real cat band" % [ok, scored])
	if csv_path != "":
		var f := FileAccess.open(csv_path, FileAccess.WRITE)
		if f:
			f.store_string(csv)
