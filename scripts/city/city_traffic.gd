class_name CityTraffic
extends Node3D
## city traffic: cars (the three shitbox rally models), buses and bikes on main st + cross st,
## traffic lights, walk signals with countdowns. step in front of something moving and you get
## bonked back onto the curb (playful: a yowl, a toss, back on the sidewalk you came from).
## wait for WALK, or go over: awnings, the sign bridge, the footbridge, under parked cars.
##
## online: there's nothing to send. the whole thing is a pure function of the shared clock
## (unix time): the lights run on `fposmod(t, CYCLE)`, and the cars come from a fixed spawn
## schedule (an integer hash of lane + slot) stepped at a fixed 30 hz. every machine starts its
## sim WARM seconds in the past, by then the lanes have emptied out whatever was there before,
## so everyone ends up with exactly the same cars in the same places.

const Model := preload("res://scripts/city/car_model.gd")
const IDS := ["wrx_wagon", "crownvic", "civic_ep3"]
const PAINT := [Color(0.85, 0.85, 0.83), Color(0.08, 0.08, 0.09), Color(0.6, 0.62, 0.64), Color(0.32, 0.33, 0.35),
	Color(0.12, 0.17, 0.3), Color(0.45, 0.08, 0.08), Color(0.2, 0.28, 0.22), Color(0.55, 0.5, 0.42),
	Color(0.9, 0.2, 0.55), Color(0.1, 0.75, 0.8), Color(0.95, 0.75, 0.1)]
const REST_Y := -0.15
const CYCLE := 34.0          # main green 0-14, yellow -17, all red -18, cross green -30, yellow -33, all red -34
const DT := 1.0 / 30.0
const WARM := 90.0
const LANE_LEN := 116.0
const DEC := 4.5             # planned braking (m/s2)
const BRAKE := 9.0           # the most a driver will brake
const VIS_LAYER := 2         # vehicles render on layer 2: the explore map's top down shot skips them

var player: CatPlayer
var clock_offset := 0.0      # tests: shift the shared clock
var lanes: Array = []
var vehicles: Array = []
var sim_t := 0.0
var bonks := 0
var spawned := 0
var heads: Array = []        # [{road, lenses: [r, y, g]}]
var walks: Array = []        # [{crossing, lens, label}]
var _defs := {}
var _mats := {}
var _bonk_t := 0.0
var _respawn := Vector3.ZERO
var _last_safe := Vector3.ZERO
var _honk: AudioStreamWAV
var _chirp: AudioStreamWAV
var _honk_cool := 0.0
var _walk_was := {}
var _warm := true


func _ready() -> void:
	lanes = [
		{"o": Vector3(-58, 0, 1.75), "d": Vector3(1, 0, 0), "road": "main", "every": 3.0, "bus": 58.0 - 13.4},
		{"o": Vector3(58, 0, -1.75), "d": Vector3(-1, 0, 0), "road": "main", "every": 3.0, "bus": -1.0},
		{"o": Vector3(-1.75, 0, -58), "d": Vector3(0, 0, 1), "road": "cross", "every": 4.0, "bus": -1.0},
		{"o": Vector3(1.75, 0, 58), "d": Vector3(0, 0, -1), "road": "cross", "every": 4.0, "bus": -1.0},
	]
	for l in lanes:
		l["stop"] = 58.0 - 9.5
		l["right"] = (l.d as Vector3).cross(Vector3.UP)
	_sounds()
	_build_signals()
	# warm up: run the sim from WARM seconds ago with no nodes, then make nodes for what's left
	var now := clock()
	sim_t = floorf((now - WARM) / DT) * DT
	_warm = true
	while sim_t + DT <= now:
		_step(DT)
	_warm = false
	for v in vehicles:
		_make_node(v)


func clock() -> float:
	return Time.get_unix_time_from_system() + clock_offset


# ---------------------------------------------------------------- signals

## "g" / "y" / "r" for a road at shared time t
static func light(road: String, t: float) -> String:
	var c := fposmod(t, CYCLE)
	if road == "main":
		return "g" if c < 14.0 else ("y" if c < 17.0 else "r")
	return "r" if c < 18.0 else ("g" if c < 30.0 else ("y" if c < 33.0 else "r"))


## walk signal for crossing a road (crossing main st = walking north-south): [state, secs left]
## state: "walk", "flash" (finish crossing, don't start), "wait"
static func walk(crossing: String, t: float) -> Array:
	var c := fposmod(t, CYCLE)
	var w0 := 18.0 if crossing == "main" else 0.0
	var k := fposmod(c - w0, CYCLE)
	if k < 10.0:
		return ["walk", 15.0 - k]
	if k < 15.0:
		return ["flash", 15.0 - k]
	return ["wait", CYCLE - k]


func _build_signals() -> void:
	var col := Color(0.12, 0.13, 0.14)
	for l in lanes:
		var d: Vector3 = l.d
		var r: Vector3 = l.right
		var stop_p: Vector3 = (l.o as Vector3) + d * float(l.stop)
		var pole := stop_p + r * 4.1 + d * 0.3
		pole.y = CityBlock.CURB
		_part(pole + Vector3(0, 2.8, 0), Vector3(0.14, 5.6, 0.14), col)
		# mast arm out over the lane + the head facing oncoming traffic, and a low one for cats
		var arm_mid := (pole + stop_p + d * 0.3) * 0.5
		arm_mid.y = 5.4
		var arm_len := pole.distance_to(Vector3(stop_p.x, pole.y, stop_p.z) + d * 0.3)
		_part(arm_mid, Vector3(arm_len, 0.1, 0.1) if absf(r.x) > 0.5 else Vector3(0.1, 0.1, arm_len), col)
		for hp in [stop_p + d * 0.3 + Vector3(0, 4.9, 0), pole + Vector3(0, 2.3, 0) - d * 0.12]:
			var h: Vector3 = hp
			_part(h, Vector3(0.36, 1.0, 0.36), col)
			var lenses := []
			for k in 3:
				var lp := h + Vector3(0, 0.3 - k * 0.3, 0) - d * 0.19
				lenses.append(_lens(lp, 0.12))
			heads.append({"road": l.road, "lenses": lenses})
	# walk signals at both ends of the four crosswalks, facing across
	for s in [-1.0, 1.0]:
		for e in [-1.0, 1.0]:
			# crossing main st (zebra at x = s * 7), ends at z = e * 5.6
			_walk_head(Vector3(s * 8.9, CityBlock.CURB, e * 5.7), Vector3(0, 0, -e), "main")
			# crossing cross st (zebra at z = s * 7), ends at x = e * 5.6
			_walk_head(Vector3(e * 5.7, CityBlock.CURB, s * 8.9), Vector3(-e, 0, 0), "cross")


func _walk_head(p: Vector3, face: Vector3, crossing: String) -> void:
	var col := Color(0.12, 0.13, 0.14)
	_part(p + Vector3(0, 1.3, 0), Vector3(0.09, 2.6, 0.09), col)
	var h := p + Vector3(0, 2.4, 0) + face * 0.12
	_part(h, Vector3(0.42, 0.42, 0.42), col)
	var lens := _lens(h + face * 0.22, 0.17, true)
	var lab := Label3D.new()
	lab.font_size = 48
	lab.pixel_size = 0.004
	lab.outline_size = 8
	lab.shaded = false
	lab.double_sided = false
	lab.position = h + face * 0.24 + Vector3(0, -0.32, 0)
	add_child(lab)
	lab.look_at(lab.position - face, Vector3.UP)
	# push button box at cat height
	_part(p + Vector3(0, 1.0, 0) + face * 0.07, Vector3(0.12, 0.18, 0.06), Color(0.8, 0.7, 0.1))
	walks.append({"crossing": crossing, "lens": lens, "label": lab, "pos": h})


func _part(c: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat("body", col, 0.0)
	mi.position = c
	add_child(mi)
	var sb := StaticBody3D.new()
	sb.set_meta("surface", "metal")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = c
	add_child(sb)


func _lens(p: Vector3, r: float, square := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if square:
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 2.0, r * 2.0, r * 2.0)
		mi.mesh = bm
	else:
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 10
		sm.rings = 5
		mi.mesh = sm
	mi.position = p
	mi.material_override = _mat("off", Color(0.08, 0.08, 0.08), 0.0)
	add_child(mi)
	return mi


func _mat(key: String, col: Color, energy: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.5
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


func _update_signals(t: float) -> void:
	var on := {"r": _mat("r", Color(1.0, 0.12, 0.08), 4.0), "y": _mat("y", Color(1.0, 0.65, 0.05), 4.0), "g": _mat("g", Color(0.15, 1.0, 0.45), 4.0)}
	var off := _mat("off", Color(0.08, 0.08, 0.08), 0.0)
	for h in heads:
		var st := light(str(h.road), t)
		var ls: Array = h.lenses
		(ls[0] as MeshInstance3D).material_override = on.r if st == "r" else off
		(ls[1] as MeshInstance3D).material_override = on.y if st == "y" else off
		(ls[2] as MeshInstance3D).material_override = on.g if st == "g" else off
	var blink := fmod(t, 1.0) < 0.55
	for wi in walks.size():
		var w: Dictionary = walks[wi]
		var ws := walk(str(w.crossing), t)
		var lab: Label3D = w.label
		var lens: MeshInstance3D = w.lens
		match ws[0]:
			"walk":
				lens.material_override = _mat("walk", Color(0.9, 0.95, 1.0), 3.5)
				lab.text = "WALK %d" % ceili(ws[1])
				lab.modulate = Color(1.6, 1.7, 1.8)
			"flash":
				lens.material_override = _mat("wait", Color(1.0, 0.45, 0.08), 3.5) if blink else off
				lab.text = "%d" % ceili(ws[1])
				lab.modulate = Color(2.0, 0.9, 0.2)
			_:
				lens.material_override = _mat("wait", Color(1.0, 0.45, 0.08), 3.5)
				lab.text = "WAIT"
				lab.modulate = Color(2.0, 0.9, 0.2)
		var was = _walk_was.get(wi, "")
		if ws[0] == "walk" and was != "walk" and not _warm and player and player.global_position.distance_to(w.pos) < 14.0:
			_play(_chirp, w.pos, 0.5)
		_walk_was[wi] = ws[0]


# ---------------------------------------------------------------- the sim

static func _hash(a: int, b: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ 83492791
	h = (h * 2654435761) & 0xffffffff
	h ^= h >> 13
	h = (h * 1274126177) & 0xffffffff
	return h ^ (h >> 16)


func _step(dt: float) -> void:
	var t0 := sim_t
	sim_t += dt
	# spawns: one slot per lane every `every` seconds
	for li in lanes.size():
		var l: Dictionary = lanes[li]
		var every: float = l.every
		var s0 := floori(t0 / every)
		var s1 := floori(sim_t / every)
		if s1 == s0:
			continue
		var h := _hash(li + 1, s1)
		if h % 100 >= 72:
			continue
		var roll := (h >> 8) % 100
		var kind := "car"
		if roll < 9 and l.road == "main":
			kind = "bus"
		elif roll < 27:
			kind = "bike"
		var last = null
		for v in vehicles:
			if v.lane == li and (last == null or v.s < last.s):
				last = v
		if last != null and last.s - last.len * 0.5 < 7.0:
			continue
		var v := {"lane": li, "s": 0.0, "ps": 0.0, "v": 6.0, "kind": kind, "id": s1 * 8 + li,
			"model": IDS[(h >> 16) % IDS.size()], "paint": PAINT[(h >> 20) % PAINT.size()], "served": false, "wait": 0.0, "brake": false, "node": null}
		match kind:
			"bus":
				v.len = 10.6; v.w = 2.5; v.v0 = 7.5; v.acc = 1.3
			"bike":
				v.len = 1.8; v.w = 0.7; v.v0 = 5.5 + float((h >> 12) % 10) * 0.1; v.acc = 1.6; v.v = 4.0
			_:
				v.len = 4.4; v.w = 1.8; v.v0 = 8.5 + float((h >> 12) % 10) * 0.15; v.acc = 2.6
		v.s = -v.len * 0.5
		v.ps = v.s
		vehicles.append(v)
		spawned += 1
		if not _warm:
			_make_node(v)
	# move: front to back per lane
	for li in lanes.size():
		var l: Dictionary = lanes[li]
		var st := light(str(l.road), sim_t)
		var lane_v := vehicles.filter(func(x): return x.lane == li)
		lane_v.sort_custom(func(a, b): return a.s > b.s)
		var lead = null
		for v in lane_v:
			var front: float = v.s + v.len * 0.5
			var limit: float = v.v0
			if lead != null:
				var gap: float = (lead.s - lead.len * 0.5) - front - 2.2
				limit = minf(limit, sqrt(maxf(0.0, 2.0 * DEC * gap)))
			var d_stop: float = float(l.stop) - front
			if st != "g" and d_stop > -0.3:
				var need: float = v.v * v.v / (2.0 * BRAKE) + 0.4
				if st == "r" or d_stop > need:
					limit = minf(limit, sqrt(maxf(0.0, 2.0 * DEC * (d_stop - 0.1))))
			if v.kind == "bus" and not v.served and float(l.bus) > 0.0:
				var d_bs: float = float(l.bus) - front
				if d_bs > -0.5:
					limit = minf(limit, sqrt(maxf(0.0, 2.0 * DEC * maxf(d_bs, 0.0))))
					if d_bs < 0.8 and v.v < 0.3:
						v.wait += dt
						limit = 0.0
						if v.wait > 4.0:
							v.served = true
			var was: float = v.v
			if v.v < limit:
				v.v = minf(limit, v.v + v.acc * dt)
			else:
				v.v = maxf(limit, v.v - BRAKE * dt)
			v.brake = v.v < was - 0.01 or v.v < 0.1
			v.ps = v.s
			v.s += v.v * dt
			lead = v
	# off the far end into the tunnel
	for i in range(vehicles.size() - 1, -1, -1):
		var v: Dictionary = vehicles[i]
		if v.s - v.len * 0.5 > LANE_LEN:
			if v.node != null and is_instance_valid(v.node):
				v.node.queue_free()
			vehicles.remove_at(i)


func _physics_process(dt: float) -> void:
	var now := clock()
	if now - sim_t > 3.0 or now < sim_t - 1.0:
		# fell way behind (paused, alt tabbed): jump the clock, the schedule keeps it in sync
		for v in vehicles:
			if v.node != null and is_instance_valid(v.node):
				v.node.queue_free()
		vehicles.clear()
		sim_t = floorf((now - WARM) / DT) * DT
		_warm = true
		while sim_t + DT <= now:
			_step(DT)
		_warm = false
		for v in vehicles:
			_make_node(v)
	var n := 0
	while sim_t + DT <= now and n < 12:
		_step(DT)
		n += 1
	var a := clampf((now - sim_t) / DT + 1.0, 0.0, 1.0)
	for v in vehicles:
		_place(v, a, dt)
	_update_signals(now)
	_cat_check(dt)


func pos_of(v: Dictionary, a := 1.0) -> Vector3:
	var l: Dictionary = lanes[v.lane]
	return (l.o as Vector3) + (l.d as Vector3) * lerpf(v.ps, v.s, a)


func _place(v: Dictionary, a: float, dt: float) -> void:
	var node: Node3D = v.node
	if node == null or not is_instance_valid(node):
		return
	var l: Dictionary = lanes[v.lane]
	var p := pos_of(v, a)
	node.global_transform = Transform3D(Basis.looking_at(l.d, Vector3.UP), p)
	if node.has_meta("model"):
		var m = node.get_meta("model")
		for s in m.spins:
			(s as Node3D).rotation.x -= v.v * dt / 0.31
		for tm in m._tail_mats:
			(tm as ShaderMaterial).set_shader_parameter("emission", 2.4 if v.brake else 0.6)
	var wheels: Array = node.get_meta("wheels", [])
	for w in wheels:
		(w as Node3D).rotation.x -= v.v * dt / 0.34
	if node.has_meta("crank"):
		var c: Node3D = node.get_meta("crank")
		c.rotation.x -= v.v * dt / 0.9
		var legs: Array = node.get_meta("legs")
		for k in 2:
			var leg: Node3D = legs[k]
			leg.rotation.x = sin(c.rotation.x + k * PI) * 0.55


# ---------------------------------------------------------------- vehicle nodes

func _def(id: String) -> Dictionary:
	if not _defs.has(id):
		_defs[id] = JSON.parse_string(FileAccess.get_file_as_string("res://data/city/cars/%s.json" % id))
	return _defs[id]


func _make_node(v: Dictionary) -> void:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	body.add_to_group("city_traffic")
	body.name = "%s_%d" % [v.kind, v.id]
	add_child(body)
	match str(v.kind):
		"car": _car(body, v)
		"bus": _bus(body, v)
		_: _bike(body, v)
	_layers(body)
	v.node = body
	_place(v, 1.0, 0.0)


func _box_shape(body: Node3D, size: Vector3, off: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = off
	body.add_child(cs)


func _car(body: Node3D, v: Dictionary) -> void:
	var def := _def(str(v.model))
	var r := float(def.get("wheel_radius", 0.31))
	var root := Node3D.new()
	root.position.y = r - REST_Y
	body.add_child(root)
	for b in def.get("collision", []):
		_box_shape(body, Vector3(float(b["size"][0]), float(b["size"][1]), float(b["size"][2])), Vector3(float(b["offset"][0]), float(b["offset"][1]) + 0.05 + r - REST_Y, float(b["offset"][2])))
	var wb := float(def["wheelbase"])
	var wheels := []
	var spots := []
	for i in 4:
		var front := i < 2
		var left := i % 2 == 0
		var track := float(def.get("track_front" if front else "track_rear", 1.5))
		wheels.append({"radius": r})
		spots.append([Vector3((-0.5 if left else 0.5) * track, REST_Y, (-0.5 if front else 0.5) * wb), left])
	var m := Model.new()
	root.add_child(m)
	m.build(def, REST_Y, wheels, v.paint)
	for i in 4:
		m.hubs[i].position = spots[i][0]
		m.hubs[i].rotation.y = PI if spots[i][1] else 0.0
	body.set_meta("model", m)
	v.len = float(def["dimensions"][2])
	v.w = float(def["dimensions"][0])
	# headlights: two little glow cards up front (no real lights, too many cars)
	for s in [-0.55, 0.55]:
		var hl := MeshInstance3D.new()
		var q := BoxMesh.new()
		q.size = Vector3(0.22, 0.1, 0.02)
		hl.mesh = q
		hl.material_override = _mat("headlight", Color(1.0, 0.95, 0.8), 3.0)
		hl.position = Vector3(s * v.w * 0.8, 0.72, -v.len * 0.5 - 0.01)
		body.add_child(hl)


func _vpart(parent: Node3D, c: Vector3, size: Vector3, col: Color, energy := 0.0, key := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(key if key != "" else "v_%s_%.2f" % [col.to_html(), energy], col, energy)
	mi.position = c
	parent.add_child(mi)
	return mi


func _wheel(parent: Node3D, c: Vector3, r: float, w: float) -> Node3D:
	var hub := Node3D.new()
	hub.position = c
	parent.add_child(hub)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = w
	cm.radial_segments = 10
	mi.mesh = cm
	mi.rotation.z = PI * 0.5
	mi.material_override = _mat("tyre", Color(0.05, 0.05, 0.05), 0.0)
	hub.add_child(mi)
	_vpart(hub, Vector3(0, r * 0.6, 0), Vector3(w + 0.02, r * 0.3, 0.06), Color(0.5, 0.5, 0.5))
	return hub


func _bus(body: Node3D, v: Dictionary) -> void:
	var L: float = v.len
	var col := Color(0.15, 0.55, 0.6) if int(v.id) % 2 == 0 else Color(0.85, 0.5, 0.12)
	_box_shape(body, Vector3(2.5, 2.8, L), Vector3(0, 1.75, 0))
	_vpart(body, Vector3(0, 1.75, 0), Vector3(2.5, 2.8, L), col)
	_vpart(body, Vector3(0, 0.45, 0), Vector3(2.4, 0.3, L - 0.4), Color(0.12, 0.12, 0.13))
	# window band (lit inside), windshield, destination sign
	for s in [-1.0, 1.0]:
		_vpart(body, Vector3(s * 1.26, 2.2, 0.3), Vector3(0.02, 1.0, L - 2.2), Color(0.55, 0.5, 0.4), 0.5, "buswin")
		for k in 6:
			_vpart(body, Vector3(s * 1.27, 2.2, -L * 0.5 + 1.6 + k * 1.6), Vector3(0.03, 1.0, 0.1), col.darkened(0.3))
	_vpart(body, Vector3(0, 2.0, -L * 0.5 - 0.01), Vector3(2.3, 1.4, 0.02), Color(0.2, 0.3, 0.4), 0.0, "buswind")
	_vpart(body, Vector3(0, 2.95, -L * 0.5 - 0.02), Vector3(1.8, 0.3, 0.02), Color(1.0, 0.6, 0.1), 3.0, "busdest")
	var lab := Label3D.new()
	lab.text = "42 PURR AVE"
	lab.font_size = 40
	lab.pixel_size = 0.005
	lab.modulate = Color(0.1, 0.05, 0.0)
	lab.position = Vector3(0, 2.95, -L * 0.5 - 0.04)
	lab.rotation.y = PI
	lab.shaded = false
	body.add_child(lab)
	for s in [-0.85, 0.85]:
		_vpart(body, Vector3(s, 0.85, -L * 0.5 - 0.01), Vector3(0.3, 0.15, 0.02), Color(1, 0.95, 0.8), 3.0, "headlight")
		_vpart(body, Vector3(s, 0.85, L * 0.5 + 0.01), Vector3(0.3, 0.15, 0.02), Color(1, 0.1, 0.05), 2.0, "taillight")
	var wheels := []
	for z in [-L * 0.5 + 2.0, L * 0.5 - 2.2]:
		for s in [-1.1, 1.1]:
			wheels.append(_wheel(body, Vector3(s, 0.48, z), 0.48, 0.3))
	body.set_meta("wheels", wheels)


func _bike(body: Node3D, v: Dictionary) -> void:
	var frame := Color(0.8, 0.15, 0.2) if int(v.id) % 3 == 0 else (Color(0.1, 0.5, 0.8) if int(v.id) % 3 == 1 else Color(0.2, 0.2, 0.2))
	_box_shape(body, Vector3(0.5, 1.6, 1.7), Vector3(0, 0.95, 0))
	var wheels := []
	for z in [-0.55, 0.55]:
		wheels.append(_wheel(body, Vector3(0, 0.34, z), 0.34, 0.05))
	body.set_meta("wheels", wheels)
	_vpart(body, Vector3(0, 0.62, 0), Vector3(0.05, 0.05, 1.0), frame)
	_vpart(body, Vector3(0, 0.75, -0.42), Vector3(0.05, 0.5, 0.05), frame)
	_vpart(body, Vector3(0, 1.0, -0.45), Vector3(0.5, 0.04, 0.04), Color(0.1, 0.1, 0.1))
	_vpart(body, Vector3(0, 0.82, 0.25), Vector3(0.18, 0.05, 0.25), Color(0.1, 0.1, 0.1))
	_vpart(body, Vector3(0, 0.62, 0.28), Vector3(0.05, 0.4, 0.05), frame)
	_vpart(body, Vector3(0, 0.9, -0.62), Vector3(0.12, 0.08, 0.04), Color(1, 1, 0.9), 3.0, "headlight")
	# rider: blocky, leaning forward, pedalling
	var jacket: Color = [Color(0.9, 0.85, 0.2), Color(0.2, 0.6, 0.3), Color(0.6, 0.2, 0.6), Color(0.15, 0.15, 0.2)][int(v.id) % 4]
	_vpart(body, Vector3(0, 1.3, 0.05), Vector3(0.4, 0.62, 0.25), jacket).rotation.x = -0.5
	_vpart(body, Vector3(0, 1.68, -0.18), Vector3(0.22, 0.24, 0.22), Color(0.85, 0.65, 0.5))
	_vpart(body, Vector3(0, 1.8, -0.18), Vector3(0.26, 0.12, 0.3), Color(0.15, 0.15, 0.15))
	for s in [-0.18, 0.18]:
		_vpart(body, Vector3(s, 1.2, -0.25), Vector3(0.08, 0.08, 0.45), jacket).rotation.x = 0.6
	var crank := Node3D.new()
	crank.position = Vector3(0, 0.45, 0.05)
	body.add_child(crank)
	var legs := []
	for k in 2:
		var hip := Node3D.new()
		hip.position = Vector3((k - 0.5) * 0.2, 0.95, 0.22)
		body.add_child(hip)
		_vpart(hip, Vector3(0, -0.28, 0), Vector3(0.12, 0.56, 0.12), Color(0.15, 0.15, 0.25))
		legs.append(hip)
	body.set_meta("crank", crank)
	body.set_meta("legs", legs)


func _layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1 << (VIS_LAYER - 1)
	for c in n.get_children():
		_layers(c)


# ---------------------------------------------------------------- the cat vs traffic

func _cat_check(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_honk_cool -= dt
	var p := player.global_position
	if _bonk_t > 0.0:
		_bonk_t -= dt
		if _bonk_t <= 0.9 and _respawn != Vector3.ZERO:
			player.global_position = _respawn
			player.velocity = Vector3.ZERO
			_respawn = Vector3.ZERO
		return
	if player.is_on_floor() and not CityBlock.on_road(p):
		_last_safe = p
	if not CityBlock.on_road(p) or p.y > 0.6:
		return
	for v in vehicles:
		var node: Node3D = v.node
		if node == null or not is_instance_valid(node):
			continue
		var lp := node.global_transform.affine_inverse() * p
		if lp.length_squared() > 196.0:
			continue
		var hw: float = v.w * 0.5 + 0.18
		var hl: float = v.len * 0.5 + 0.25
		if absf(lp.x) < hw and absf(lp.z) < hl and v.v > 0.7:
			_bonk(v)
			return
		# honk at a cat standing in the lane ahead
		if absf(lp.x) < hw + 0.4 and lp.z < -hl and lp.z > -hl - 9.0 and v.v > 2.0 and _honk_cool <= 0.0:
			_honk_cool = 2.5
			_play(_honk, node.global_position, 0.9, 1.0 if v.kind != "bus" else 0.7)


func _bonk(v: Dictionary) -> void:
	bonks += 1
	_bonk_t = 1.6
	var l: Dictionary = lanes[v.lane]
	var d: Vector3 = l.d
	player.velocity = d * (float(v.v) * 0.45 + 1.2) + Vector3.UP * 3.4
	_respawn = CityBlock.nearest_curb(player.global_position, _last_safe if _last_safe != Vector3.ZERO else player.global_position)
	player.toast = "bonk! wait for the walk light (or go over)"
	player.toast_t = 0.0
	player._event("bonk")
	CatSfx.play_at("yowl", player.global_position, 0.9, 1.15)
	CatSfx.play_at("hit", player.global_position, 0.8, 1.3)
	_play(_honk, (v.node as Node3D).global_position, 1.0, 1.0)
	var sv = get_node_or_null("/root/Save")
	if sv and sv.enabled:
		sv.add_stat("bonks")


# ---------------------------------------------------------------- sounds

func _sounds() -> void:
	var rate := 22050
	var hb := PackedFloat32Array()
	hb.resize(int(rate * 0.38))
	for i in hb.size():
		var t := float(i) / rate
		var env := minf(1.0, t / 0.01) * minf(1.0, (0.38 - t) / 0.05)
		var a := signf(sin(TAU * 415.0 * t)) * 0.5 + signf(sin(TAU * 522.0 * t)) * 0.5
		hb[i] = a * env * 0.22
	_honk = _wav(hb, rate)
	var cb := PackedFloat32Array()
	cb.resize(int(rate * 0.5))
	for i in cb.size():
		var t := float(i) / rate
		var k := fmod(t, 0.12)
		cb[i] = sin(TAU * (2600.0 - k * 9000.0) * t) * exp(-k * 60.0) * 0.3
	_chirp = _wav(cb, rate)


func _wav(buf: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func _play(stream: AudioStream, at: Vector3, vol := 1.0, pitch := 1.0) -> void:
	if not CatSfx.available():
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.bus = "SFX"
	a.unit_size = 4.0
	a.max_distance = 40.0
	a.volume_db = linear_to_db(vol)
	a.pitch_scale = pitch
	add_child(a)
	a.global_position = at
	a.finished.connect(a.queue_free)
	a.play()
