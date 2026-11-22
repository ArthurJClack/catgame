class_name BiomeSound
extends Node3D
## desert + mountain sound, synthesised at load like the forest's soundscape.gd (no audio files):
##   desert    hot breathy wind, cicada buzz from the scrub, quail calling, the odd far off screech
##   mountain  big gusty wind, the meltwater stream (follows the bank near you), marmot whistles
##             echoing off the cliffs, an eagle now and then
## one-shots the animals + puzzles use: rattle, hiss, whistle, eep, screech, bleat, clatter, scuttle,
## creak (windmill), pour (water), thump (snow), quail.   `sound.play(name, pos, vol, pitch)`
## m mutes this level's sound (biome_main.gd)

const RATE := 16000
var biome := "desert"
var clips := {}
static var _cache := {}   # biome -> baked clips, so going back in doesn't re-synthesise
var pool: Array[AudioStreamPlayer3D] = []
var wind: AudioStreamPlayer
var bed: AudioStreamPlayer3D        # cicadas (desert) / stream (mountain), parked near the listener
var stream_line: Array = []         # mountain: points along the stream for `bed`
var muted := false
var rng := RandomNumberGenerator.new()
var _call_t := 3.0
var _far_t := 12.0
var _gust := 0.0


func _ready() -> void:
	rng.seed = hash(biome)
	if DisplayServer.get_name() == "headless":
		return   # tests: no audio device, skip the baking
	if _cache.has(biome):
		clips = _cache[biome]
	else:
		_bake()
		_cache[biome] = clips
	wind = AudioStreamPlayer.new()
	wind.stream = clips["wind"]
	wind.volume_db = -16.0 if biome == "mountain" else -20.0
	add_child(wind)
	wind.play()
	bed = AudioStreamPlayer3D.new()
	bed.stream = clips["bed"]
	bed.unit_size = 3.0
	bed.max_distance = 26.0
	bed.volume_db = -10.0
	add_child(bed)
	bed.play()
	for k in 10:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 60.0
		add_child(p)
		pool.append(p)


func play(clip: String, at: Vector3, vol := 1.0, pitch := 1.0) -> void:
	if muted or not clips.has(clip):
		return
	for p in pool:
		if not p.playing:
			p.stream = clips[clip]
			p.global_position = at
			p.volume_db = linear_to_db(clampf(vol, 0.01, 1.5)) - 6.0
			p.pitch_scale = pitch
			p.play()
			return


func set_muted(m: bool) -> void:
	muted = m
	if wind:
		wind.stream_paused = m
		bed.stream_paused = m


# ------------------------------------------------------------------ synthesis
func _wav(data: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	return w


func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	return b


func _tone(buf: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, amp: float, vib := 0.0, vib_hz := 0.0, harm := 0.0) -> void:
	var n := int(dur * RATE)
	var start := int(t0 * RATE)
	var ph := 0.0
	for i in n:
		if start + i >= buf.size():
			return
		var k := float(i) / n
		var f := lerpf(f0, f1, k) * (1.0 + vib * sin(TAU * vib_hz * i / RATE))
		ph += TAU * f / RATE
		var env := minf(k * 14.0, 1.0) * minf((1.0 - k) * 5.0, 1.0)
		var s := sin(ph)
		if harm > 0.0:
			s += harm * sin(ph * 2.0) + harm * 0.6 * sin(ph * 3.0) + harm * 0.3 * sin(ph * 4.0)
		buf[start + i] += s * env * amp


func _noise(buf: PackedFloat32Array, t0: float, dur: float, amp: float, lp: float, decay := 0.0, hp := false) -> void:
	var n := int(dur * RATE)
	var start := int(t0 * RATE)
	var y := 0.0
	for i in n:
		if start + i >= buf.size():
			return
		var k := float(i) / n
		var r := rng.randf_range(-1.0, 1.0)
		y += (r - y) * lp
		var v := (r - y) if hp else y
		var env := minf(k * 40.0, 1.0) * (exp(-decay * k) if decay > 0.0 else minf((1.0 - k) * 8.0, 1.0))
		buf[start + i] += v * env * amp


func _seam(buf: PackedFloat32Array, sec: float) -> void:
	var n := int(sec * RATE)
	var last := buf.size() - n
	for i in n:
		var k := float(i) / n
		buf[i] = buf[i] * k + buf[last + i] * (1.0 - k)
	buf.resize(last)


func _bake() -> void:
	# wind: low noise breathing in slow swells (stronger + gustier up the mountain)
	var w := _buf(8.0)
	var y := 0.0
	var y2 := 0.0
	var gusty := biome == "mountain"
	for i in w.size():
		var s := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * (0.04 if gusty else 0.025)
		y2 += (y - y2) * 0.3
		var swell := 0.55 + 0.45 * sin(s * TAU / 8.0 * 2.0) * sin(s * TAU / 8.0 * 3.0 + 1.0)
		w[i] = y2 * (2.6 if gusty else 1.8) * swell
	_seam(w, 0.5)
	clips["wind"] = _wav(w, true)
	if biome == "desert":
		# cicadas: a buzz pulsing ~ 60 Hz, swelling in and out
		var c := _buf(5.0)
		var ph := 0.0
		for i in c.size():
			var s := float(i) / RATE
			ph += TAU * (4200.0 + 120.0 * sin(s * 3.0)) / RATE
			var pulse := 0.5 + 0.5 * sin(TAU * 62.0 * s)
			var swell := clampf(0.4 + 0.6 * sin(s * TAU / 5.0), 0.0, 1.0)
			c[i] = sin(ph) * pulse * pulse * swell * 0.18 + rng.randf_range(-1, 1) * 0.02 * swell
		_seam(c, 0.4)
		clips["bed"] = _wav(c, true)
	else:
		# stream: bright burbling noise with little bubble tones
		var st := _buf(5.0)
		var yy := 0.0
		for i in st.size():
			yy += (rng.randf_range(-1.0, 1.0) - yy) * 0.35
			st[i] = yy * 0.35
		for k in 40:
			_tone(st, rng.randf_range(0.0, 4.9), 0.04, rng.randf_range(500, 1200), rng.randf_range(900, 1800), 0.06)
		_seam(st, 0.3)
		clips["bed"] = _wav(st, true)
	# rattle: fast clicks of keratin, ~ 50 a second
	var r := _buf(1.0)
	for k in 50:
		_noise(r, k * 0.02, 0.012, 0.7, 0.8, 6.0, true)
	clips["rattle"] = _wav(r)
	var h := _buf(0.6)
	_noise(h, 0.0, 0.6, 0.6, 0.9, 3.0, true)
	clips["hiss"] = _wav(h)
	# marmot whistle: one sharp rising note
	var wh := _buf(0.4)
	_tone(wh, 0.0, 0.35, 2400.0, 2900.0, 0.55, 0.01, 30.0, 0.15)
	clips["whistle"] = _wav(wh)
	var e := _buf(0.3)
	_tone(e, 0.0, 0.08, 3200.0, 2800.0, 0.4)
	_tone(e, 0.13, 0.08, 3300.0, 2900.0, 0.35)
	clips["eep"] = _wav(e)
	# raptor scream: a falling, rough cry
	var sc := _buf(1.0)
	_tone(sc, 0.0, 0.9, 2300.0, 1500.0, 0.35, 0.03, 38.0, 0.5)
	_noise(sc, 0.0, 0.9, 0.08, 0.6, 2.0, true)
	clips["screech"] = _wav(sc)
	# goat bleat: nasal, wobbling
	var bl := _buf(0.8)
	_tone(bl, 0.0, 0.7, 380.0, 330.0, 0.35, 0.06, 7.0, 0.8)
	clips["bleat"] = _wav(bl)
	var cl := _buf(0.4)
	for k in 4:
		_noise(cl, k * 0.07 + rng.randf() * 0.02, 0.03, 0.6, 0.7, 10.0, true)
	clips["clatter"] = _wav(cl)
	var su := _buf(0.3)
	for k in 10:
		_noise(su, k * 0.025, 0.008, 0.25, 0.9, 8.0, true)
	clips["scuttle"] = _wav(su)
	# windmill: a slow wooden creak + the iron whine of the vane
	var cr := _buf(1.4)
	_tone(cr, 0.0, 1.2, 140.0, 110.0, 0.3, 0.12, 13.0, 0.9)
	_tone(cr, 0.2, 0.9, 620.0, 700.0, 0.06, 0.02, 5.0)
	clips["creak"] = _wav(cr)
	var po := _buf(2.0)
	_noise(po, 0.0, 2.0, 0.5, 0.45)
	for k in 30:
		_tone(po, rng.randf_range(0.0, 1.9), 0.05, rng.randf_range(400, 900), rng.randf_range(700, 1400), 0.08)
	clips["pour"] = _wav(po)
	var th := _buf(0.6)
	_noise(th, 0.0, 0.5, 0.9, 0.08, 6.0)
	clips["thump"] = _wav(th)
	# gambel's quail style "chi-CA-go-go"
	var q := _buf(0.9)
	_tone(q, 0.0, 0.1, 1300.0, 1500.0, 0.3, 0.0, 0.0, 0.3)
	_tone(q, 0.16, 0.18, 1700.0, 1900.0, 0.4, 0.0, 0.0, 0.3)
	_tone(q, 0.42, 0.12, 1400.0, 1300.0, 0.3, 0.0, 0.0, 0.3)
	_tone(q, 0.62, 0.12, 1400.0, 1300.0, 0.25, 0.0, 0.0, 0.3)
	clips["quail"] = _wav(q)


# ------------------------------------------------------------------ ambience
func _process(dt: float) -> void:
	if muted or wind == null:
		return
	var cam := get_viewport().get_camera_3d()
	var ear := cam.global_position if cam else Vector3.ZERO
	# gusts: the wind swells harder the higher you climb
	_gust = LowPoly.damp(_gust, 0.0, 0.3, dt)
	if rng.randf() < dt * 0.08:
		_gust = rng.randf_range(2.0, 6.0)
	var alt := clampf(ear.y / 14.0, 0.0, 1.0) if biome == "mountain" else 0.0
	wind.volume_db = (-20.0 if biome == "desert" else -17.0) + _gust + alt * 6.0
	if biome == "mountain" and not stream_line.is_empty():
		var best: Vector3 = stream_line[0]
		for p in stream_line:
			if (p as Vector3).distance_to(ear) < best.distance_to(ear):
				best = p
		bed.global_position = best
	elif biome == "desert":
		# cicadas sit in the scrub a few metres off, moved along when you get close or wander away
		if bed.global_position.distance_to(ear) > 18.0 or bed.global_position.distance_to(ear) < 2.5:
			var a := rng.randf() * TAU
			bed.global_position = ear + Vector3(cos(a), 0, sin(a)) * rng.randf_range(5.0, 10.0)
	_call_t -= dt
	if _call_t < 0.0:
		_call_t = rng.randf_range(4.0, 11.0)
		var a := rng.randf() * TAU
		var p := ear + Vector3(cos(a), 0.5, sin(a)) * rng.randf_range(10.0, 24.0)
		if biome == "desert":
			play("quail", p, rng.randf_range(0.3, 0.6), rng.randf_range(0.95, 1.08))
		else:
			play("whistle", p + Vector3(0, 4, 0), rng.randf_range(0.15, 0.35), rng.randf_range(0.9, 1.05))
	_far_t -= dt
	if _far_t < 0.0:
		_far_t = rng.randf_range(18.0, 40.0)
		var a := rng.randf() * TAU
		play("screech", ear + Vector3(cos(a) * 30.0, 18.0, sin(a) * 30.0), 0.35, rng.randf_range(0.9, 1.05))
