class_name Soundscape
extends Node3D
## forest sound, all synthesised at load into short clips (no audio files in the project):
## wind in the trees, the stream (follows the nearest bit of bank), birdsong by day, crickets + frogs + an owl
## at night, and one-shots the animals trigger themselves (quack, caw, drumming, splash, hawk cry...).
##   Soundscape.play("splash", world_pos, 0.8)     from anywhere, does nothing if there is no soundscape
## m mutes (forest_main).

const RATE := 16000
static var inst: Soundscape
var clips := {}
var atmos: Atmos
var pool: Array[AudioStreamPlayer3D] = []
var wind: AudioStreamPlayer
var stream: AudioStreamPlayer3D
var crickets: Array[AudioStreamPlayer3D] = []
var rng := RandomNumberGenerator.new()
var _bird_t := 2.0
var _frog_t := 5.0
var _owl_t := 12.0
var muted := false
var _cat: Node3D


func _ready() -> void:
	inst = self
	rng.seed = 77
	_bake()
	wind = AudioStreamPlayer.new()
	wind.stream = clips["wind"]
	wind.volume_db = -22.0
	add_child(wind)
	wind.play()
	stream = AudioStreamPlayer3D.new()
	stream.stream = clips["stream"]
	stream.unit_size = 3.0
	stream.max_distance = 22.0
	stream.volume_db = -9.0
	add_child(stream)
	stream.play()
	for k in 3:
		var c := AudioStreamPlayer3D.new()
		c.stream = clips["cricket"]
		c.unit_size = 2.5
		c.max_distance = 26.0
		c.volume_db = -60.0
		c.pitch_scale = 0.94 + k * 0.05
		add_child(c)
		c.play(k * 0.37)
		crickets.append(c)
	for k in 8:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 45.0
		add_child(p)
		pool.append(p)


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func play(clip: String, at: Vector3, vol := 1.0, pitch := 1.0) -> void:
	if inst == null or inst.muted or not inst.clips.has(clip):
		return
	for p in inst.pool:
		if not p.playing:
			p.stream = inst.clips[clip]
			p.global_position = at
			p.volume_db = linear_to_db(clampf(vol, 0.01, 1.5)) - 6.0
			p.pitch_scale = pitch
			p.play()
			return


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


# ------------------------------------------------------------------ synthesis
func _wav(data: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w


func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	return b


## a sine that glides f0 -> f1 with a smooth attack/decay, added into buf at t0
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
		var env := sin(k * PI)
		env = env * env if dur < 0.08 else minf(k * 12.0, 1.0) * minf((1.0 - k) * 6.0, 1.0)
		var s := sin(ph)
		if harm > 0.0:
			s += harm * sin(ph * 2.0) + harm * 0.6 * sin(ph * 3.0)
		buf[start + i] += s * env * amp


func _noise(buf: PackedFloat32Array, t0: float, dur: float, amp: float, lp: float, decay := 0.0) -> void:
	var n := int(dur * RATE)
	var start := int(t0 * RATE)
	var y := 0.0
	for i in n:
		if start + i >= buf.size():
			return
		var k := float(i) / n
		y += (rng.randf_range(-1.0, 1.0) - y) * lp
		var env := minf(k * 40.0, 1.0) * (exp(-decay * k) if decay > 0.0 else minf((1.0 - k) * 8.0, 1.0))
		buf[start + i] += y * env * amp


func _bake() -> void:
	# wind: slow-breathing low noise. the loop end is crossfaded into the start so it doesn't click
	var w := _buf(6.0)
	var y := 0.0
	var y2 := 0.0
	for i in w.size():
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.035
		y2 += (y - y2) * 0.2
		var tt := float(i) / w.size()
		w[i] = y2 * 2.6 * (0.55 + 0.3 * sin(TAU * tt) + 0.15 * sin(TAU * tt * 3.0 + 1.0))
	_seam(w, 0.4)
	clips["wind"] = _wav(w, true)
	# stream: hiss of moving water + lots of little bubble blips
	var s := _buf(4.0)
	var a := 0.0
	var b := 0.0
	for i in s.size():
		var r := rng.randf_range(-1.0, 1.0)
		a += (r - a) * 0.35
		b += (a - b) * 0.06
		s[i] = (a - b) * 0.22
	for k in 150:
		var f := rng.randf_range(500.0, 2400.0)
		_tone(s, rng.randf() * 3.9, rng.randf_range(0.02, 0.06), f, f * rng.randf_range(1.1, 1.6), rng.randf_range(0.03, 0.1))
	_seam(s, 0.25)
	clips["stream"] = _wav(s, true)
	# crickets: a trill of short 4.3 kHz pulses, pause, repeat
	var c := _buf(1.5)
	for burst in 3:
		for p in 7:
			_tone(c, burst * 0.5 + p * 0.035, 0.022, 4300.0, 4300.0, 0.22)
	clips["cricket"] = _wav(c, true)
	# three bird songs: rising pair, a trill, a two-note call
	var b1 := _buf(0.7)
	_tone(b1, 0.0, 0.12, 2600.0, 3600.0, 0.3)
	_tone(b1, 0.16, 0.12, 2800.0, 3900.0, 0.3)
	_tone(b1, 0.34, 0.2, 3400.0, 2700.0, 0.25, 0.04, 30.0)
	clips["bird1"] = _wav(b1)
	var b2 := _buf(0.8)
	for p in 9:
		_tone(b2, p * 0.075, 0.05, 4200.0 - p * 60.0, 3600.0 - p * 60.0, 0.24)
	clips["bird2"] = _wav(b2)
	var b3 := _buf(0.9)
	_tone(b3, 0.0, 0.22, 3100.0, 3000.0, 0.28)
	_tone(b3, 0.3, 0.35, 2400.0, 2300.0, 0.28, 0.02, 12.0)
	clips["bird3"] = _wav(b3)
	# owl: hoo, hoo-hoo
	var o := _buf(1.9)
	_tone(o, 0.0, 0.4, 360.0, 340.0, 0.5, 0.01, 6.0, 0.15)
	_tone(o, 0.75, 0.22, 365.0, 350.0, 0.45, 0.0, 0.0, 0.15)
	_tone(o, 1.05, 0.5, 360.0, 330.0, 0.5, 0.01, 6.0, 0.15)
	clips["owl"] = _wav(o)
	# frog: a rattly croak (low tone chopped at ~50 hz)
	var fr := _buf(0.5)
	_tone(fr, 0.0, 0.42, 480.0, 420.0, 0.5, 0.0, 0.0, 0.5)
	for i in fr.size():
		fr[i] *= 0.5 + 0.5 * signf(sin(TAU * 48.0 * i / RATE))
	clips["frog"] = _wav(fr)
	# duck: nasal quacks = buzzy tone with a falling pitch
	var q := _buf(0.9)
	for p in 3:
		_tone(q, p * 0.27, 0.2, 620.0 - p * 30.0, 480.0, 0.4, 0.0, 0.0, 0.9)
	for i in q.size():
		q[i] *= 0.6 + 0.4 * sin(TAU * 110.0 * i / RATE)
	clips["quack"] = _wav(q)
	# crow: harsh caw = noisy buzz
	var cw := _buf(0.5)
	_tone(cw, 0.0, 0.38, 900.0, 700.0, 0.35, 0.0, 0.0, 0.9)
	_noise(cw, 0.0, 0.38, 0.5, 0.5)
	for i in cw.size():
		cw[i] *= 0.5 + 0.5 * sin(TAU * 140.0 * i / RATE)
	clips["caw"] = _wav(cw)
	# hawk: long falling whistle
	var hk := _buf(1.1)
	_tone(hk, 0.0, 1.0, 3300.0, 2100.0, 0.35, 0.015, 9.0, 0.2)
	clips["hawk"] = _wav(hk)
	# woodpecker drum: a roll of knocks, slowing a touch
	var dr := _buf(0.9)
	var tt2 := 0.0
	for p in 14:
		_noise(dr, tt2, 0.03, 0.9, 0.5, 9.0)
		_tone(dr, tt2, 0.03, 900.0, 600.0, 0.35)
		tt2 += 0.05 + p * 0.0016
	clips["drum"] = _wav(dr)
	var sp := _buf(0.6)
	_noise(sp, 0.0, 0.55, 0.9, 0.3, 6.0)
	_tone(sp, 0.02, 0.12, 300.0, 140.0, 0.4)
	clips["splash"] = _wav(sp)
	var pl := _buf(0.25)
	_tone(pl, 0.0, 0.09, 500.0, 1300.0, 0.5)
	_noise(pl, 0.03, 0.18, 0.25, 0.3, 8.0)
	clips["plop"] = _wav(pl)
	var fl := _buf(0.5)
	for p in 5:
		_noise(fl, p * 0.09, 0.07, 0.5, 0.18, 3.0)
	clips["flap"] = _wav(fl)
	var tk := _buf(0.12)
	_noise(tk, 0.0, 0.03, 0.5, 0.7, 6.0)
	_noise(tk, 0.05, 0.03, 0.4, 0.7, 6.0)
	clips["tick"] = _wav(tk)
	var sq := _buf(0.35)
	for p in 3:
		_tone(sq, p * 0.1, 0.07, 2000.0, 1500.0, 0.3, 0.0, 0.0, 0.5)
	clips["chatter"] = _wav(sq)
	var sn := _buf(0.3)
	_noise(sn, 0.0, 0.1, 0.3, 0.25, 4.0)
	_noise(sn, 0.16, 0.1, 0.3, 0.25, 4.0)
	clips["sniff"] = _wav(sn)


func _seam(buf: PackedFloat32Array, sec: float) -> void:
	var n := int(sec * RATE)
	var last := buf.size() - n
	for i in n:
		var k := float(i) / n
		buf[i] = buf[i] * k + buf[last + i] * (1.0 - k)
	buf.resize(last)


# ------------------------------------------------------------------ ambience
func _process(dt: float) -> void:
	if muted:
		return
	if _cat == null or not is_instance_valid(_cat):
		_cat = get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	var ear := cam.global_position if cam else Vector3.ZERO
	var day := atmos.daylight() if atmos else 1.0
	# the stream sound sits on the nearest bit of water to the listener
	var sx := clampf(ear.x, -36.0, 36.0)
	stream.global_position = Vector3(sx, ForestLevel.WATER_Y, ForestLevel.stream_z(sx))
	var night_db := lerpf(-13.0, -60.0, clampf(day * 2.5, 0.0, 1.0))
	for k in crickets.size():
		var c := crickets[k]
		c.volume_db = LowPoly.damp(c.volume_db, night_db, 1.0, dt)
		# crickets are always "over there": parked in the grass a few metres out, moved when you get close
		if c.global_position.distance_to(ear) > 24.0 or c.global_position.distance_to(ear) < 2.0:
			var a := rng.randf() * TAU
			var p := ear + Vector3(cos(a), 0, sin(a)) * rng.randf_range(6.0, 12.0)
			c.global_position = Vector3(p.x, ForestLevel.height(clampf(p.x, -38, 38), clampf(p.z, -38, 38)) + 0.05, p.z)
	_bird_t -= dt
	if _bird_t < 0.0:
		_bird_t = rng.randf_range(1.2, 5.0) if day > 0.5 else rng.randf_range(6.0, 12.0)
		if day > 0.35 and not ForestLevel.perches.is_empty():
			# sung from a real perch somewhere within earshot
			for tries in 6:
				var p: Vector3 = ForestLevel.perches[rng.randi() % ForestLevel.perches.size()]
				if p.distance_to(ear) < 30.0 and p.y - ForestLevel.height(p.x, p.z) > 1.0:
					play("bird%d" % rng.randi_range(1, 3), p, rng.randf_range(0.35, 0.7) * day, rng.randf_range(0.9, 1.15))
					break
	_frog_t -= dt
	if _frog_t < 0.0:
		_frog_t = rng.randf_range(2.0, 6.0) if day < 0.4 else rng.randf_range(9.0, 20.0)
		var a := rng.randf() * TAU
		play("frog", Vector3(ForestLevel.POND.x + cos(a) * 5.0, ForestLevel.WATER_Y, ForestLevel.POND.y + sin(a) * 5.0), 0.5, rng.randf_range(0.85, 1.2))
	_owl_t -= dt
	if _owl_t < 0.0:
		_owl_t = rng.randf_range(14.0, 30.0)
		if day < 0.2:
			for n in get_tree().get_nodes_in_group("wild"):
				if (n as Critter).kind == "owl":
					play("owl", (n as Node3D).global_position, 0.9)
					break
