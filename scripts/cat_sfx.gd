class_name CatSfx
extends Node3D
## the cat's own sounds, all synthesised once at load (no audio files, same idea as soundscape.gd):
## paw steps per surface (from the gait's real touchdowns, so they match the paws you see),
## hops, landings by drop height, swat whooshes + hits, scratching, climbing claw clicks,
## skids, dodges, catches, getting hurt, a meow key (n by default) and a purr when the cat
## settles down somewhere (or lies in the sunbeam). rats get squeaks for their wind up, bite,
## hurt and death (RatVoice, added by GameMenu's node hook). menus get clicks.
## all on the "SFX" bus (settings -> cat + effects volume).
##   CatSfx.play_at("hit", pos)             a one shot anywhere
##   CatSfx.ui("click")                     flat ui sound
## headless (tests): nothing is baked or played.

const RATE := 22050
const SURF := {
	"wood": "tap", "tile": "tap", "default": "tap", "stone": "tap",
	"carpet": "soft", "rug": "soft",
	"grass": "rustle", "hay": "rustle",
	"dirt": "grit", "sand": "grit", "gravel": "grit",
}
const PURR_AFTER := 5.0        # seconds sat still before the purr starts

static var clips := {}
static var played: Array[String] = []   # last clips played (tests read it)
static var _ui_player: AudioStreamPlayer
static var _pool_world: Array[AudioStreamPlayer3D] = []

var player: CatPlayer
var pool: Array[AudioStreamPlayer3D] = []
var purr: AudioStreamPlayer3D
var scratch_loop: AudioStreamPlayer3D
var enabled := true

var _was_floor := true
var _fall_v := 0.0
var _air_t := 0.0
var _atk_prev := ""
var _phase_prev := 0
var _dash_prev := -1
var _catches := 0
var _still_t := 0.0
var _climb_click := 0.0
var _skid_t := 0.0
var _meow_prev := false
var _meow_cool := 0.0
var _step_cool: Array[float] = [0.0, 0.0, 0.0, 0.0]
var rng := RandomNumberGenerator.new()


static func available() -> bool:
	return DisplayServer.get_name() != "headless"


static func attach(p: CatPlayer) -> CatSfx:
	if not available() or p.has_node("CatSfx"):
		return null
	var s := CatSfx.new()
	s.name = "CatSfx"
	s.player = p
	p.add_child(s)
	return s


func _ready() -> void:
	process_priority = 30     # after the rig: gait touchdowns of this frame are in
	bake()
	for i in 6:
		var a := _player3d(2.0)
		pool.append(a)
	purr = _player3d(1.2)
	purr.stream = clips.purr
	purr.volume_db = -80.0
	scratch_loop = _player3d(1.6)
	scratch_loop.stream = clips.scratch
	if player.health:
		player.health.hurt.connect(func(_a, _f): _one("yowl" if rng.randf() < 0.5 else "hiss", 0.75, rng.randf_range(0.95, 1.08)))


func _player3d(unit: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.unit_size = unit
	a.max_distance = 30.0
	a.bus = "SFX"
	add_child(a)
	return a


func _one(clip: String, vol := 1.0, pitch := 1.0, at = null) -> void:
	if not enabled or not clips.has(clip):
		return
	_log(clip)
	for a in pool:
		if not a.playing:
			a.stream = clips[clip]
			a.volume_db = linear_to_db(clampf(vol, 0.001, 2.0))
			a.pitch_scale = pitch
			a.position = Vector3.ZERO if at == null else to_local(at)
			a.play()
			return


func _variant(base: String) -> String:
	var n := 0
	while clips.has("%s%d" % [base, n]):
		n += 1
	return "%s%d" % [base, rng.randi_range(0, maxi(n - 1, 0))] if n > 0 else base


func _process(dt: float) -> void:
	if player == null or not is_instance_valid(player) or player.rig == null:
		return
	var local := player.bot.is_empty()
	var hv := Vector2(player.velocity.x, player.velocity.z)
	var spd := hv.length()
	var floor := player.is_on_floor()

	# ---- paw steps: one per real touchdown
	var g: CatGait = player.rig.gait
	for i in 4:
		_step_cool[i] = maxf(_step_cool[i] - dt, 0.0)
		if g.touched[i] and _step_cool[i] <= 0.0 and (spd > 0.25 or _air_t > 0.1):
			_step_cool[i] = 0.06
			var kind: String = SURF.get(player.surface, "tap")
			var v := clampf(0.18 + spd * 0.07, 0.15, 0.95) * (1.0 if i < 2 else 0.8)
			if kind == "soft":
				v *= 0.45
			_one(_variant("step_" + kind), v, rng.randf_range(0.9, 1.12))

	# ---- hop / land
	if floor and not _was_floor:
		var drop := _fall_v * _fall_v / 19.6
		if drop > 0.25 or _air_t > 0.25:
			var hard := drop > 1.4
			_one("land_hard" if hard else "land_soft", clampf(0.35 + drop * 0.25, 0.3, 1.2), rng.randf_range(0.92, 1.06))
	elif not floor and _was_floor and player.velocity.y > 1.2:
		_one(_variant("step_" + SURF.get(player.surface, "tap")), 0.6, 0.8)
		_one("jump", 0.45, rng.randf_range(0.95, 1.1))
	if not floor:
		_air_t += dt
		_fall_v = maxf(-player.velocity.y, 0.0)
	else:
		_air_t = 0.0
	_was_floor = floor

	# ---- paws: whoosh on each strike, thud when it connects (combat counts hits)
	var cb = player.combat
	if cb:
		var atk: String = cb.atk
		var ph: int = cb.atk_phase
		if atk in ["swat", "rake", "grab"] and ph == 2 and (_phase_prev != 2 or atk != _atk_prev):
			_one("swish", 0.55 if atk == "rake" else 0.75, rng.randf_range(0.9, 1.15))
		_atk_prev = atk
		_phase_prev = ph
	# ---- dodge
	var ds: int = player.dash.state if player.dash else CatDash.IDLE
	if ds != _dash_prev and _dash_prev == CatDash.IDLE and ds != CatDash.IDLE:
		_one("dash", 0.6, rng.randf_range(0.92, 1.08))
	_dash_prev = ds
	# ---- catches
	if player.catches > _catches:
		_one("squeak", 0.8, rng.randf_range(0.95, 1.15))
	_catches = player.catches
	# ---- scratching (loop) + climbing claws + skids
	var scr := player.scratching
	if scr and not scratch_loop.playing:
		scratch_loop.volume_db = -4.0
		scratch_loop.play()
	elif not scr and scratch_loop.playing:
		scratch_loop.stop()
	if player.climbing:
		_climb_click -= dt * (1.0 + absf(player.velocity.y) * 3.0)
		if _climb_click <= 0.0:
			_climb_click = 0.22
			_one(_variant("claw"), 0.5, rng.randf_range(0.9, 1.2))
	var slip: float = player.rig.slip_claws
	_skid_t -= dt
	if slip > 0.35 and spd > 2.0 and floor and _skid_t <= 0.0:
		_skid_t = 0.12
		_one("skid", clampf(slip, 0.3, 0.9), rng.randf_range(0.9, 1.1))

	# ---- meow (local cat only: key "meow")
	_meow_cool = maxf(_meow_cool - dt, 0.0)
	if local:
		var m: bool = CatKeys.down("meow")
		if m and not _meow_prev and _meow_cool <= 0.0:
			meow()
		_meow_prev = m

	# ---- purr: sat still a while (lying in the sunbeam counts double)
	var resting: bool = floor and spd < 0.15 and not player.climbing and not scr and cb != null and cb.atk == ""
	_still_t = _still_t + dt if resting else 0.0
	var want := 0.0
	if _still_t > PURR_AFTER:
		want = clampf((_still_t - PURR_AFTER) / 2.0, 0.0, 1.0) * 0.5
	var cur := db_to_linear(purr.volume_db) if purr.playing else 0.0
	cur = move_toward(cur, want, dt * (0.4 if want > cur else 1.5))
	if cur > 0.002:
		if not purr.playing:
			purr.play()
		purr.volume_db = linear_to_db(cur)
	elif purr.playing:
		purr.stop()


func meow() -> void:
	_meow_cool = 0.45
	var sv := get_node_or_null("/root/Save")
	if sv:
		sv.add_stat("meows")
	_one(_variant("meow"), 0.9, rng.randf_range(0.94, 1.08))


# ---------------------------------------------------------------- static helpers

static func play_at(clip: String, at: Vector3, vol := 1.0, pitch := 1.0) -> void:
	if not available():
		return
	bake()
	var c := clip
	if not clips.has(c):
		var n := 0
		while clips.has("%s%d" % [clip, n]):
			n += 1
		if n == 0:
			return
		c = "%s%d" % [clip, randi() % n]
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null or ml.current_scene == null:
		return
	_log(c)
	var a := AudioStreamPlayer3D.new()
	a.stream = clips[c]
	a.bus = "SFX"
	a.unit_size = 2.0
	a.max_distance = 30.0
	a.volume_db = linear_to_db(clampf(vol, 0.001, 2.0))
	a.pitch_scale = pitch
	ml.current_scene.add_child(a)
	a.global_position = at
	a.finished.connect(a.queue_free)
	a.play()


static func _log(c: String) -> void:
	played.append(c)
	if played.size() > 300:
		played.remove_at(0)


static func ui(clip: String) -> void:
	if not available():
		return
	bake()
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null:
		return
	if _ui_player == null or not is_instance_valid(_ui_player):
		_ui_player = AudioStreamPlayer.new()
		_ui_player.bus = "SFX"
		_ui_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_ui_player.max_polyphony = 4
		ml.root.add_child.call_deferred(_ui_player)
		return
	if clips.has("ui_" + clip):
		_log("ui_" + clip)
		_ui_player.stream = clips["ui_" + clip]
		_ui_player.volume_db = -8.0 if clip == "hover" else (-2.0 if clip == "unlock" else -4.0)
		_ui_player.play()


# ---------------------------------------------------------------- synthesis

static func bake() -> void:
	if not clips.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	# paw steps: cats are near silent, these are the little sounds a pad + claws make
	for v in 3:
		var b := _buf(0.07)
		_noise(b, r, 0.0, 0.03, 0.5, 0.55, 9.0)            # tap: claw tick + pad
		_tone(b, 0.0, 0.035, 180.0 + v * 20.0, 120.0, 0.25)
		clips["step_tap%d" % v] = _wav(b)
		b = _buf(0.06)
		_noise(b, r, 0.0, 0.05, 0.25, 0.08, 6.0)           # soft: muffled pad on carpet
		clips["step_soft%d" % v] = _wav(b)
		b = _buf(0.11)
		_noise(b, r, 0.0, 0.09, 0.4, 0.7, 4.0)             # rustle: grass / hay
		_noise(b, r, 0.02, 0.07, 0.25, 0.35, 5.0)
		clips["step_rustle%d" % v] = _wav(b)
		b = _buf(0.08)
		for k in 5:                                         # grit: dirt crumbs
			_noise(b, r, k * 0.012 + r.randf() * 0.006, 0.012, 0.45, 0.9, 6.0)
		_noise(b, r, 0.0, 0.06, 0.2, 0.2, 5.0)
		clips["step_grit%d" % v] = _wav(b)
		b = _buf(0.05)
		_noise(b, r, 0.0, 0.012, 0.6, 0.95, 10.0)          # climbing claw click
		_noise(b, r, 0.018, 0.01, 0.35, 0.95, 10.0)
		clips["claw%d" % v] = _wav(b)
	var land := _buf(0.22)
	_tone(land, 0.0, 0.12, 110.0, 55.0, 0.55)
	_noise(land, r, 0.0, 0.08, 0.35, 0.25, 6.0)
	clips["land_soft"] = _wav(land)
	land = _buf(0.35)
	_tone(land, 0.0, 0.2, 95.0, 42.0, 0.85)
	_noise(land, r, 0.0, 0.16, 0.6, 0.3, 5.0)
	_noise(land, r, 0.01, 0.05, 0.4, 0.8, 8.0)
	clips["land_hard"] = _wav(land)
	var jump := _buf(0.1)
	_noise(jump, r, 0.0, 0.08, 0.3, 0.5, 5.0)
	clips["jump"] = _wav(jump)
	clips["swish"] = _wav(_sweep(r, 0.2, 0.05, 0.6, 0.55))
	clips["dash"] = _wav(_sweep(r, 0.3, 0.03, 0.35, 0.6))
	var hit := _buf(0.18)
	_tone(hit, 0.0, 0.09, 160.0, 70.0, 0.7)
	_noise(hit, r, 0.0, 0.05, 0.7, 0.6, 7.0)
	clips["hit"] = _wav(hit)
	# scratching a post / sofa: rasping strokes
	var sc := _buf(0.8)
	for k in 6:
		_noise(sc, r, k * 0.13, 0.1, 0.45, 0.5 + 0.1 * (k % 2), 2.0)
	clips["scratch"] = _wav(sc, true)
	var sk := _buf(0.12)
	for k in 4:
		_noise(sk, r, k * 0.025, 0.012, 0.5, 0.92, 9.0)
	clips["skid"] = _wav(sk)
	# meows: harmonic voice through a moving "mouth" (amplitude of the upper harmonics opens)
	clips["meow0"] = _wav(_voice(r, 0.55, [[0.0, 540.0], [0.25, 760.0], [1.0, 470.0]], 0.9))     # meow
	clips["meow1"] = _wav(_voice(r, 0.22, [[0.0, 620.0], [0.5, 820.0], [1.0, 700.0]], 0.6))      # mew
	clips["meow2"] = _wav(_voice(r, 0.4, [[0.0, 380.0], [0.3, 520.0], [1.0, 600.0]], 0.5, 22.0)) # mrrp (rolled)
	clips["yowl"] = _wav(_voice(r, 0.5, [[0.0, 820.0], [0.35, 980.0], [1.0, 520.0]], 1.0, 7.0))
	var hs := _buf(0.6)
	_noise(hs, r, 0.0, 0.58, 0.55, 0.92, 1.5)
	clips["hiss"] = _wav(hs)
	# purr: ~26 hz throaty pulses, loops
	var pr := _buf(2.0)
	var y := 0.0
	for i in pr.size():
		var t := float(i) / RATE
		y += (r.randf_range(-1.0, 1.0) - y) * 0.06
		var pulse := pow(maxf(sin(TAU * 26.0 * t), 0.0), 3.0)
		var breath := 0.65 + 0.35 * sin(TAU * t * 0.5 - 1.2)   # in / out over the 2 s loop
		pr[i] = (y * 2.2 + sin(TAU * 52.0 * t) * 0.15) * pulse * breath * 0.7
	clips["purr"] = _wav(pr, true)
	# prey + rats
	var sq := _buf(0.18)
	_tone(sq, 0.0, 0.07, 2600.0, 3300.0, 0.35)
	_tone(sq, 0.09, 0.08, 3000.0, 2400.0, 0.3)
	clips["squeak"] = _wav(sq)
	var rw := _buf(0.35)
	_noise(rw, r, 0.0, 0.3, 0.3, 0.85, 2.0)
	_tone(rw, 0.05, 0.25, 1700.0, 2200.0, 0.18, 0.05, 30.0)
	clips["rat_wind"] = _wav(rw)
	var rb := _buf(0.16)
	_tone(rb, 0.0, 0.1, 2400.0, 3000.0, 0.35)
	_noise(rb, r, 0.0, 0.04, 0.35, 0.8, 8.0)
	clips["rat_bite"] = _wav(rb)
	var rh := _buf(0.2)
	_tone(rh, 0.0, 0.16, 3200.0, 2000.0, 0.32, 0.04, 40.0)
	clips["rat_hurt"] = _wav(rh)
	var rd := _buf(0.5)
	_tone(rd, 0.0, 0.45, 2800.0, 900.0, 0.32, 0.06, 18.0)
	clips["rat_die"] = _wav(rd)
	# ui
	var uc := _buf(0.06)
	_tone(uc, 0.0, 0.05, 880.0, 660.0, 0.35)
	clips["ui_click"] = _wav(uc)
	var uh := _buf(0.03)
	_tone(uh, 0.0, 0.025, 1320.0, 1320.0, 0.14)
	clips["ui_hover"] = _wav(uh)
	var un := _buf(0.7)                      # achievement: two note chime
	_tone(un, 0.0, 0.35, 784.0, 784.0, 0.3)
	_tone(un, 0.12, 0.55, 1175.0, 1175.0, 0.28)
	_tone(un, 0.12, 0.55, 2350.0, 2350.0, 0.06)
	clips["ui_unlock"] = _wav(un)


static func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	return b


static func _wav(data: PackedFloat32Array, loop := false) -> AudioStreamWAV:
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


static func _tone(buf: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, amp: float, vib := 0.0, vib_hz := 0.0) -> void:
	var n := int(dur * RATE)
	var start := int(t0 * RATE)
	var ph := 0.0
	for i in n:
		if start + i >= buf.size():
			return
		var k := float(i) / n
		var f := lerpf(f0, f1, k) * (1.0 + vib * sin(TAU * vib_hz * i / RATE))
		ph += TAU * f / RATE
		var env := minf(k * 20.0, 1.0) * pow(1.0 - k, 1.5)
		buf[start + i] += sin(ph) * env * amp


## noise burst. lp = one pole smoothing (low = dull), hp = how much of the smoothed part is taken
## back out (high = thin / bright), decay = exponential fade
static func _noise(buf: PackedFloat32Array, r: RandomNumberGenerator, t0: float, dur: float, amp: float, hp: float, decay: float) -> void:
	var n := int(dur * RATE)
	var start := int(t0 * RATE)
	var lo := 0.0
	var lo2 := 0.0
	for i in n:
		if start + i >= buf.size():
			return
		var k := float(i) / n
		var x := r.randf_range(-1.0, 1.0)
		lo += (x - lo) * 0.35
		lo2 += (lo - lo2) * 0.05
		var s := lo - lo2 * hp * 1.5 if hp < 0.5 else lerpf(lo, x - lo2, hp)
		var env := minf(k * 60.0, 1.0) * exp(-decay * k)
		buf[start + i] += s * env * amp


## air whoosh: noise through a filter that opens then closes
static func _sweep(r: RandomNumberGenerator, dur: float, lp0: float, lp1: float, amp: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var y := 0.0
	for i in b.size():
		var k := float(i) / b.size()
		var lp := lerpf(lp0, lp1, sin(k * PI))
		y += (r.randf_range(-1.0, 1.0) - y) * lp
		b[i] = y * sin(k * PI) * amp * 1.6
	return b


## a cat voice: pitch contour [[t 0..1, hz], ...], the mouth opens in the middle (bright),
## roll > 0 = rolled "r" amplitude flutter in hz
static func _voice(r: RandomNumberGenerator, dur: float, contour: Array, amp: float, roll := 0.0) -> PackedFloat32Array:
	var b := _buf(dur)
	var ph := 0.0
	var y := 0.0
	for i in b.size():
		var k := float(i) / b.size()
		var f := 0.0
		for j in range(contour.size() - 1):
			var a: Array = contour[j]
			var c: Array = contour[j + 1]
			if k >= a[0] and k <= c[0]:
				f = lerpf(a[1], c[1], smoothstep(0.0, 1.0, (k - a[0]) / maxf(c[0] - a[0], 0.001)))
		f *= 1.0 + 0.012 * sin(TAU * 5.5 * i / RATE)
		ph += TAU * f / RATE
		var mouth := sin(clampf(k * 1.15, 0.0, 1.0) * PI)          # m.. eee .. ow
		var s := sin(ph) + mouth * (0.7 * sin(ph * 2.0) + 0.5 * sin(ph * 3.0) + 0.3 * sin(ph * 4.0) + 0.15 * sin(ph * 5.0))
		y += (r.randf_range(-1.0, 1.0) - y) * 0.3
		s += y * 0.08 * mouth                                       # breath
		var env := minf(k * 14.0, 1.0) * minf((1.0 - k) * 5.0, 1.0)
		if roll > 0.0:
			env *= 0.6 + 0.4 * sin(TAU * roll * i / RATE)
		b[i] = s * env * amp * 0.3
	return b


# ---------------------------------------------------------------- rats

class RatVoice extends Node:
	var rat: Node3D
	var _state := -1
	var _hp := -1.0

	func _process(_dt: float) -> void:
		if not is_instance_valid(rat):
			return
		var st: int = rat.get("state")
		if st != _state:
			match st:
				2: CatSfx.play_at("rat_wind", rat.global_position, 0.7, randf_range(0.9, 1.1))     # WINDUP
				3: CatSfx.play_at("rat_bite", rat.global_position, 0.8, randf_range(0.9, 1.1))     # LUNGE
				6: CatSfx.play_at("rat_die", rat.global_position, 0.8, randf_range(0.9, 1.1))      # DEAD
			_state = st
		var hp = rat.get("hp")
		if hp is float:
			if _hp >= 0.0 and hp < _hp - 0.01 and st != 6:
				CatSfx.play_at("hit", rat.global_position, 0.8, randf_range(0.9, 1.1))
				CatSfx.play_at("rat_hurt", rat.global_position, 0.6, randf_range(0.9, 1.15))
			_hp = hp
