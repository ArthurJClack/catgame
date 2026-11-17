class_name CritterGait
extends RefCounted
## footfall solver for the forest animals (the cat has its own, cat_gait.gd). one per animal.
##
## every number comes from published locomotion data instead of being eyeballed:
##  - footfall order: hildebrand's gait diagrams (lateral sequence walk, trot, transverse gallop for deer,
##    rotary gallop for foxes, half bound for rabbits / squirrels / mice, hops vs walks for birds)
##  - stride length at walk + trot: alexander's dynamic similarity, stride = 2.3 * hip height * froude^0.3
##    (alexander & jayes 1983), froude = v^2 / (g * hip height)
##  - stride rate once galloping: heglund & taylor 1988, f = 4.48 * mass^-0.14 Hz at the trot-gallop
##    switch (which happens at 1.53 * mass^0.24 m/s) and barely rises after that
##  - duty factor (how much of a stride a foot is down) falls with froude, fit to alexander & jayes:
##    0.5 * froude^-0.2 (0.7+ at a stroll, ~0.5 at a trot, ~0.3 flat out)
##  - walk -> trot at froude 0.5 (alexander 1989)
##  - feet are planted: a stance foot moves back at exactly body speed, so nothing skates
##  - body bob + pitch are not keyframed: the vertical leg forces (a half sine per foot contact, fore legs
##    carrying ~60% of the weight) are integrated over the stride, so a trot bounces twice per stride,
##    a gallop rocks nose up / nose down and gets a flight phase, a hop launches the whole bird

const G := 9.8

## touchdown time of each foot within a stride (left hind = 0), from hildebrand's gait diagrams
const PATTERN := {
	"walk": {"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75},         # lateral sequence singlefoot
	"trot": {"LH": 0.0, "RF": 0.0, "RH": 0.5, "LF": 0.5},           # diagonal pairs
	"transverse": {"LH": 0.0, "RH": 0.12, "LF": 0.5, "RF": 0.62},   # deer / horse gallop (right lead)
	"rotary": {"LH": 0.0, "RH": 0.1, "RF": 0.48, "LF": 0.6},        # fox / dog / cat gallop
	"half_bound": {"LH": 0.0, "RH": 0.04, "LF": 0.5, "RF": 0.62},   # rabbit, squirrel, mouse
	"bound": {"LH": 0.0, "RH": 0.0, "LF": 0.5, "RF": 0.5},          # squirrel flat out, climbing
	"sprawl": {"LH": 0.0, "RF": 0.0, "RH": 0.5, "LF": 0.5},         # lizards trot, sprawled
	"biped_walk": {"L": 0.0, "R": 0.5},
	"biped_hop": {"L": 0.0, "R": 0.0},
}

## m = body mass (kg), h = hip height (m) the real animal uses for froude, gaits = slow to fast,
## fore = share of weight on the forelegs, lift = how much a swinging leg folds (fraction of its length),
## freq = [Hz, at m/s] for animals the scaling laws don't cover (lizards), duty = [min, max] clamp
const SPECIES := {
	"deer": {"m": 60.0, "h": 0.87, "gaits": ["walk", "trot", "transverse"], "fore": 0.58, "lift": 0.3},
	"fox": {"m": 6.0, "h": 0.30, "gaits": ["walk", "trot", "rotary"], "fore": 0.6, "lift": 0.32},
	"rabbit": {"m": 2.0, "h": 0.15, "gaits": ["half_bound"], "fore": 0.45, "lift": 0.35},
	"squirrel": {"m": 0.5, "h": 0.08, "gaits": ["half_bound", "bound"], "fore": 0.5, "lift": 0.4},
	"hedgehog": {"m": 0.8, "h": 0.05, "gaits": ["walk", "trot"], "fore": 0.55, "lift": 0.35},
	"field mouse": {"m": 0.02, "h": 0.025, "gaits": ["half_bound"], "fore": 0.5, "lift": 0.4},
	"crow": {"m": 0.5, "h": 0.12, "gaits": ["biped_walk", "biped_hop"], "fore": 0.5, "lift": 0.3},
	"bird": {"m": 0.03, "h": 0.04, "gaits": ["biped_hop"], "fore": 0.5, "lift": 0.3},
	# small lacertid lizards: ~14 strides a second at a 2.6 m/s sprint, feet down about half the stride
	"lizard": {"m": 0.01, "h": 0.03, "gaits": ["sprawl"], "fore": 0.5, "lift": 0.5, "freq": [14.0, 2.6], "duty": [0.45, 0.7]},
}

var spec: Dictionary
var legs: Array[Node3D] = []
var info: Array = []      # per leg: {len, z, side (+1 right), fore, name, w}
var gait := ""
var duty := 0.6
var freq := 0.0
var stride := 0.0
var phase := 0.0
var contacts: Array[bool] = []
var off: Array[float] = []
var m := 0.0              # 0 standing .. 1 moving: blends the whole thing in and out
# outputs for the body / head (added on top of whatever pose the animal's own code set)
var dy := 0.0
var pitch := 0.0
var head_pitch := 0.0
var head_z := 0.0
var yaw_wave := 0.0

var _v_tg := 1.0
var _f_tg := 1.0
var _z_c := 0.0
var _body_len := 0.3
var _tab_key := Vector4(-1, -1, -1, -1)
var _tab_y := PackedFloat32Array()
var _tab_p := PackedFloat32Array()
const N := 48


func _init(kind: String, leg_nodes: Array[Node3D], lens: Array[float]) -> void:
	spec = SPECIES.get(kind, SPECIES["fox"])
	legs = leg_nodes
	var mass: float = spec["m"]
	_v_tg = 1.53 * pow(mass, 0.24)
	_f_tg = 4.48 * pow(mass, -0.14)
	gait = spec["gaits"][0]
	var zs := 0.0
	for p in legs:
		zs += p.position.z
	zs /= maxf(legs.size(), 1)
	var zmin := 1e9
	var zmax := -1e9
	var two := legs.size() == 2
	for i in legs.size():
		var p := legs[i]
		var fore := p.position.z < zs
		var right := p.position.x > 0.0
		var nm := ("R" if right else "L") + ("" if two else ("F" if fore else "H"))
		var share: float = 0.5 if two else ((spec["fore"] as float) if fore else 1.0 - (spec["fore"] as float)) * 0.5
		info.append({"len": lens[i] if i < lens.size() else 0.1, "z": p.position.z, "side": 1.0 if right else -1.0, "fore": fore, "name": nm, "w": share})
		zmin = minf(zmin, p.position.z)
		zmax = maxf(zmax, p.position.z)
		contacts.append(true)
		off.append(_pattern_off(nm))
	_z_c = 0.0
	for d in info:
		_z_c += (d["w"] as float) * (d["z"] as float)
	_body_len = maxf((zmax - zmin) * 1.3, 0.02)


func _pattern_off(nm: String) -> float:
	var pat: Dictionary = PATTERN[gait]
	return pat.get(nm, 0.0)


func froude(v: float) -> float:
	return v * v / (G * (spec["h"] as float))


## choose the gait the way the animal would: froude for walk -> trot, the mass scaled speed for trot -> gallop.
## 15% hysteresis so it doesn't flicker between two at the boundary
func _pick_gait(v: float) -> String:
	var list: Array = spec["gaits"]
	var cur := list.find(gait)
	var want := 0
	for i in list.size() - 1:
		var x := froude(v)
		var thr := 0.5
		match list[i]:
			"biped_walk":
				thr = 0.6
			"trot":
				x = v
				thr = _v_tg            # trot -> gallop at heglund's transition speed
			"half_bound":
				x = v
				thr = _v_tg * 2.2      # squirrels go to a full bound well above it
		thr *= 0.85 if cur > i else 1.15
		if x <= thr:
			break
		want = i + 1
	return list[want]


func _rate(v: float) -> float:
	if spec.has("freq"):
		var fq: Array = spec["freq"]
		return (fq[0] as float) * pow(clampf(v / (fq[1] as float), 0.02, 2.0), 0.4)
	var h: float = spec["h"]
	var fr := froude(v)
	var lam := 2.3 * h * pow(maxf(fr, 1e-4), 0.3)
	var f_alex := v / maxf(lam, 1e-4)
	var f_heg := _f_tg * pow(maxf(v / _v_tg, 1.0), 0.15)
	return lerpf(f_alex, f_heg, smoothstep(0.85 * _v_tg, 1.25 * _v_tg, v))


func _duty(v: float) -> float:
	var b := 0.5 * pow(maxf(froude(v), 0.01), -0.2)
	var lim: Array = spec.get("duty", [0.22, 0.75])
	b = clampf(b, lim[0], lim[1])
	if gait in ["walk", "biped_walk"]:
		b = maxf(b, 0.56)   # a walk always has a foot down on each side (duty > 0.5 by definition)
	elif gait == "trot":
		b = clampf(b, 0.36, 0.55)
	return b


## advance one frame. `force` picks a gait by name instead of the automatic choice
func step(dt: float, v: float, force := "") -> void:
	v = absf(v)
	var h: float = spec["h"]
	var fade := 0.12 * sqrt(G * h)
	m = LowPoly.damp(m, smoothstep(0.0, fade, v), 10.0, dt)
	var want := force if force != "" else _pick_gait(v)
	if want != gait and PATTERN.has(want):
		gait = want
	if v > 0.001:
		freq = _rate(v)
		duty = LowPoly.damp(duty, _duty(v), 8.0, dt)
		stride = v / maxf(freq, 0.01)
		phase = fposmod(phase + freq * dt, 1.0)
	# ease each foot's timing to the new pattern so gait changes don't pop
	var k := 1.0 - exp(-7.0 * dt)
	for i in off.size():
		var tgt := _pattern_off(info[i]["name"])
		off[i] = fposmod(off[i] + wrapf(tgt - off[i], -0.5, 0.5) * k, 1.0)
	_body_tables()
	var s := phase * N
	var j := int(s) % N
	var fr := s - floorf(s)
	dy = lerpf(_tab_y[j], _tab_y[(j + 1) % N], fr) * m
	pitch = lerpf(_tab_p[j], _tab_p[(j + 1) % N], fr) * m
	head_pitch = -pitch * 0.8   # gaze stabilisation: the head keeps level while the body rocks
	head_z = 0.0
	yaw_wave = 0.0
	if gait == "biped_walk":
		# head bobbing birds: the head holds still in space for most of each step, then thrusts forward
		var u2 := fposmod(phase * 2.0, 1.0)
		var a := minf(stride * 0.3, h * 0.25)
		head_z = (a * (u2 / 0.7) if u2 < 0.7 else a * (1.0 - (u2 - 0.7) / 0.3)) - a * 0.5
		head_z *= m
	elif gait == "sprawl":
		# lizards bend side to side as they trot (a standing wave down the trunk)
		yaw_wave = sin(phase * TAU) * 0.28 * m
	_legs()


func _foot(i: int) -> Vector3:
	## x = foot ahead of the hip (m), y = lift 0..1, z = load shape (half sine over the stance)
	var u := fposmod(phase - off[i], 1.0)
	var reach: float = (info[i]["len"] as float) * 0.62
	var sweep := minf(duty * stride, reach * 2.0)
	if u < duty:
		var s := u / duty
		return Vector3(sweep * (0.5 - s), 0.0, sin(PI * s))
	var s2 := (u - duty) / maxf(1.0 - duty, 0.01)
	var e := s2 * s2 * (3.0 - 2.0 * s2)
	return Vector3(sweep * (-0.5 + e), sin(PI * s2), 0.0)


func _legs() -> void:
	var lift_amt: float = spec["lift"]
	for i in legs.size():
		var lg := legs[i]
		var L: float = info[i]["len"]
		var f := _foot(i)
		contacts[i] = f.y == 0.0
		var th := asin(clampf(f.x / L, -0.95, 0.95))
		if gait == "sprawl":
			var sd: float = info[i]["side"]
			lg.rotation.y = sd * th * 1.6 * m
			lg.rotation.z = sd * f.y * 0.6 * m
			continue
		# the hip moves with the body (bob + pitch); a planted foot stays on the ground,
		# so the leg stretches / compresses to reach it, and folds to clear it on the swing
		var hip := L + dy - ((info[i]["z"] as float) - _z_c) * sin(pitch)
		var need := hip / maxf(cos(th), 0.3) / L
		if f.y > 0.0:
			need *= 1.0 - f.y * lift_amt
		var kk := lerpf(1.0, clampf(need, 0.5, 1.3), m)
		lg.rotation.x = th * m
		lg.scale.y = lg.scale.x * kk


## integrate the vertical and pitching leg forces over one stride -> periodic bob + pitch tables
func _body_tables() -> void:
	var osum := 0.0
	for o in off:
		osum += o
	var key := Vector4(duty, freq, osum, float(PATTERN.keys().find(gait)))
	if _tab_y.size() == N and absf(key.x - _tab_key.x) < 0.01 and absf(key.y - _tab_key.y) < maxf(_tab_key.y * 0.03, 0.01) and absf(key.z - _tab_key.z) < 0.01 and key.w == _tab_key.w:
		return
	_tab_key = key
	_tab_y.resize(N)
	_tab_p.resize(N)
	var T := 1.0 / maxf(freq, 0.2)
	var dt := T / N
	var norm := duty * 2.0 / PI    # mean of a half sine contact over a stride
	var inertia := _body_len * _body_len / 12.0
	var a := PackedFloat32Array()
	var al := PackedFloat32Array()
	a.resize(N)
	al.resize(N)
	var ma := 0.0
	var mal := 0.0
	var save := phase
	for j in N:
		phase = float(j) / N
		var fv := 0.0
		var tq := 0.0
		for i in info.size():
			var w: float = info[i]["w"]
			var ld := _foot(i).z * w / norm
			fv += ld
			tq += ld * -((info[i]["z"] as float) - _z_c)
		a[j] = G * (fv - 1.0)
		al[j] = G * tq / inertia
		ma += a[j]
		mal += al[j]
	phase = save
	ma /= N
	mal /= N
	var sq := 0.35 if gait == "sprawl" else 1.0   # a lizard's belly hangs low: it barely vaults
	_integrate(a, ma, dt, _tab_y, sq, (spec["h"] as float) * 0.25)
	_integrate(al, mal, dt, _tab_p, 1.0 if info.size() > 2 else 0.0, 0.3)


static func _integrate(acc: PackedFloat32Array, mean: float, dt: float, out: PackedFloat32Array, scale: float, lim: float) -> void:
	var n := acc.size()
	var vel := PackedFloat32Array()
	vel.resize(n)
	var v := 0.0
	var mv := 0.0
	for j in n:
		v += (acc[j] - mean) * dt
		vel[j] = v
		mv += v
	mv /= n
	var y := 0.0
	var my := 0.0
	for j in n:
		y += (vel[j] - mv) * dt
		out[j] = y
		my += y
	my /= n
	for j in n:
		out[j] = clampf((out[j] - my) * scale, -lim, lim)
