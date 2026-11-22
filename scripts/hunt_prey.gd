class_name HuntPrey
extends Node3D
## huntable mice and rats. they forage round a home den, keep an ear and an eye out for cats,
## freeze and sit up when something seems off, and bolt for the nearest hole when it's real.
## the hunt is the cat's: creep up low while it eats, freeze when it looks up, pounce from 1-2 m.
##
## real numbers: wood mouse ~25 g, 9 cm body, bursts ~3 m/s, flinches at ~1.5 m from a walking
## predator; brown rat ~300 g, 22 cm body, runs ~3.5 m/s, bolder (forages in the open, lets you
## closer, but squeals and the whole colony hears it). rodents hear way better than they see
## (ultrasonic, but also footfalls), and their eyes are on the sides: ~300 deg of view, poor detail,
## so a cat that keeps still is near invisible and a cat that moves is not.
##
## spawn: `HuntPrey.spawn(parent, "mouse" | "rat", home, hides, ground_y, blockers)`.
##   hides: hole / den mouths it runs to and vanishes into (comes back out after a while, peeks first)
##   ground_y: func(x, z) -> float. empty = ray down onto whatever's there
##   blockers: [Vector2 center, radius] it steers round
## prey duck type for the cat: group "prey", pinned() / stun(t) / released() / caught / kind / s.
## online: HuntPrey.all is the spawn order list PreySync (scripts/net/prey_sync.gd) mirrors from the
## level's prey authority, so everyone hunts the same mice. `puppet` = driven by the network.

enum { FORAGE, ALERT, FLEE, HIDDEN, PEEK, STUN, CAUGHT, TAKEN }
const STATE_NAMES := ["forage", "alert", "flee", "hidden", "peek", "stun", "caught", "taken"]

## per species. len = body length (m), run/walk m/s, hear/see = range (m) at full loudness /
## daylight, panic = bolts no matter what inside this, bold < 1 = slower to get nervous,
## react = startle delay (s), hide = seconds in the hole
const SPEC := {
	"mouse": {"len": 0.085, "w": 0.034, "h": 0.03, "run": 3.0, "walk": 0.32, "hear": 9.0, "see": 6.0,
		"panic": 0.65, "bold": 1.0, "react": 0.16, "hide": Vector2(5.0, 12.0), "zig": 0.75, "range": 3.5,
		"fur": Color(0.52, 0.4, 0.28), "belly": Color(0.86, 0.8, 0.7), "tail": Color(0.72, 0.56, 0.5), "tail_len": 0.08, "s": 0.32},
	"rat": {"len": 0.22, "w": 0.075, "h": 0.07, "run": 3.4, "walk": 0.42, "hear": 7.5, "see": 6.5,
		"panic": 0.9, "bold": 0.6, "react": 0.22, "hide": Vector2(7.0, 15.0), "zig": 0.3, "range": 5.0,
		"fur": Color(0.36, 0.31, 0.26), "belly": Color(0.6, 0.55, 0.48), "tail": Color(0.75, 0.6, 0.58), "tail_len": 0.19, "s": 0.62},
}

const ALERT_AT := 0.3
const FLEE_AT := 1.0
const SQUEAK_R := 6.0         # fleeing prey within this hear the alarm
const CLOSE_RUSH := 1.6       # m/s a cat closing in at this speed (inside 3.5 m) is an attack
const STARTLE := 0.22         # s the flinch / jump on the spot takes when caught unawares

static var all: Array = []    # live prey in spawn order (net ids)
static var vision := -1.0     # >= 0: someone else (cat vision) drives the highlight 0..1
static var _threat_frame := -1
static var _threats: Array = []
static var _remote_prev := {}  # instance id -> last position (remote cats have no velocity)
static var _land_prev := {}    # instance id -> [was on floor, last vertical speed]

var kind := "mouse"
var caught := false
var s := 0.32                 # size for the cat's hitbox / fx (0.16 * s m radius)
var home := Vector3.ZERO
var hides: Array[Vector3] = []
var ground_y := Callable()
var blockers: Array = []
var state := FORAGE
var state_t := 1.0
var aware := 0.0
var vel := Vector3.ZERO       # horizontal m/s
var yaw := 0.0
var target := Vector3.ZERO
var hide_at := Vector3.INF
var threat := Vector3.INF     # where the scary thing was last noticed
var net_id := -1
var puppet := false           # positions come from the network authority
var live := false             # spawned for real (remote_cat's mouth props are not)
var heard := 0.0              # last frame's hearing / sight inputs (tests, debug)
var seen := 0.0
var _react := -1.0            # counting down to a bolt
var _startle := 0.0           # flinch hop timer
var _nibble := false
var _sit := 0.0               # 0..1 sat up on the haunches
var _head_down := 0.0
var _look := 0.0              # head yaw toward the threat
var _t := 0.0
var _stun := 0.0
var _rng := RandomNumberGenerator.new()
var _sp: Dictionary
var _hip: Node3D
var _body: Node3D
var _head: Node3D
var _tail: Array[Node3D] = []
var _gait: CritterGait
var _glow: MeshInstance3D
var _sense := 0.0
var _still_t := 0.0
var _net_pos := Vector3.INF
var _net_yaw := 0.0
var _peek_y := 0.0


static func spawn(parent: Node, k: String, at: Vector3, hide_spots: Array, gy := Callable(), block := []) -> HuntPrey:
	var p := HuntPrey.new()
	p.kind = k if SPEC.has(k) else "mouse"
	p.home = at
	for h in hide_spots:
		p.hides.append(h)
	p.ground_y = gy
	p.blockers = block
	p.live = true
	p.position = at
	parent.add_child(p)
	PreySync.ensure(parent)
	return p


## a little den mouth (dark hole in a ring of dug out earth) for a hide spot
static func make_burrow(parent: Node, at: Vector3, r := 0.035) -> Node3D:
	var n := Node3D.new()
	n.position = at
	parent.add_child(n)
	LowPoly.part(n, LowPoly.cyl(0.5, 0.5, 7), Color(0.42, 0.33, 0.24), Vector3(0, 0.006, 0), Vector3(r * 4.2, 0.016, r * 4.2))
	LowPoly.part(n, LowPoly.cyl(0.5, 0.5, 7), Color(0.05, 0.04, 0.03), Vector3(0, 0.0145, 0), Vector3(r * 2.0, 0.002, r * 2.0))
	return n


func _ready() -> void:
	_sp = SPEC.get(kind, SPEC["mouse"])
	s = _sp.s
	_rng.seed = hash("%s|%.2f|%.2f" % [kind, home.x, home.z])
	yaw = _rng.randf() * TAU
	_build()
	if not live:
		return
	net_id = all.size()
	all.append(self)
	add_to_group("prey")
	add_to_group("wild")
	position = _on_ground(home)
	_pick_food()
	state_t = _rng.randf_range(0.3, 2.0)


func _exit_tree() -> void:
	if live:
		all.erase(self)


# ------------------------------------------------------------------ model (meters, -z forward)
func _build() -> void:
	var L: float = _sp.len
	var W: float = _sp.w
	var H: float = _sp.h
	var fur: Color = _sp.fur
	_hip = Node3D.new()
	_hip.position = Vector3(0, 0, L * 0.35)
	add_child(_hip)
	_body = Node3D.new()
	_body.position = Vector3(0, 0, -L * 0.35)
	_hip.add_child(_body)
	LowPoly.part(_body, LowPoly.sphere(6, 4), fur, Vector3(0, H * 0.55, 0.0), Vector3(W, H, L * 0.8))
	LowPoly.part(_body, LowPoly.sphere(5, 3), _sp.belly, Vector3(0, H * 0.38, -L * 0.04), Vector3(W * 0.78, H * 0.6, L * 0.6))
	# haunches: rodents are pear shaped, wide at the back
	LowPoly.part(_body, LowPoly.sphere(5, 3), fur, Vector3(0, H * 0.55, L * 0.22), Vector3(W * 1.08, H * 0.92, L * 0.42))
	_head = Node3D.new()
	_head.position = Vector3(0, H * 0.62, -L * 0.36)
	_body.add_child(_head)
	LowPoly.part(_head, LowPoly.cone(5), fur, Vector3(0, 0, -L * 0.1), Vector3(W * 0.78, L * 0.32, H * 0.86), Vector3(-PI / 2, 0, 0))
	LowPoly.part(_head, LowPoly.box(0.0), Color(0.9, 0.6, 0.62), Vector3(0, -H * 0.04, -L * 0.27), Vector3.ONE * W * 0.17)
	var ear := Color(0.78, 0.58, 0.55) if kind == "mouse" else Color(0.62, 0.5, 0.48)
	var ear_s := 0.5 if kind == "mouse" else 0.32   # mice are all ears
	for sd in [-1, 1]:
		LowPoly.part(_head, LowPoly.sphere(5, 3), ear, Vector3(sd * W * 0.36, H * 0.42, -L * 0.02), Vector3(W * ear_s, W * ear_s, W * 0.1))
		LowPoly.part(_head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(sd * W * 0.27, H * 0.16, -L * 0.13), Vector3.ONE * W * 0.15)
		# whiskers
		for k in 2:
			LowPoly.part(_head, LowPoly.box(0.0), Color(0.85, 0.85, 0.82), Vector3(sd * W * 0.32, -H * 0.02 + k * H * 0.08, -L * 0.24), Vector3(W * 0.7, 0.0008, 0.0008), Vector3(0, sd * (0.25 + k * 0.2), 0))
	# tail: three links that whip and curl
	var link: Node3D = _body
	var tl: float = _sp.tail_len / 3.0
	var at := Vector3(0, H * 0.4, L * 0.42)
	for k in 3:
		var n := Node3D.new()
		n.position = at
		link.add_child(n)
		var th := W * (0.13 - k * 0.03)
		LowPoly.part(n, LowPoly.box(0.0), _sp.tail, Vector3(0, 0, tl * 0.5), Vector3(th, th, tl))
		_tail.append(n)
		link = n
		at = Vector3(0, 0, tl)
	var legs: Array[Node3D] = []
	var lens: Array[float] = []
	for z in [-L * 0.24, L * 0.26]:
		for sd in [-1, 1]:
			var lg := Node3D.new()
			lg.position = Vector3(sd * W * 0.36, H * 0.4, z)
			_body.add_child(lg)
			var hind: bool = z > 0
			LowPoly.part(lg, LowPoly.box(0.0), Color(0.82, 0.64, 0.6), Vector3(0, -H * 0.2, -0.002 if hind else 0.0), Vector3(W * 0.18, H * 0.4, W * (0.3 if hind else 0.17)))
			legs.append(lg)
			lens.append(H * 0.4)
	_gait = CritterGait.new("field mouse", legs, lens)
	# the faint shimmer cat sense puts on it (crouch + keep still)
	_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(L * 2.2, L * 2.2)
	_glow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glow_tex()
	m.albedo_color = Color(1.0, 0.86, 0.5, 0.0)
	m.no_depth_test = true
	m.render_priority = 2
	_glow.material_override = m
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position = Vector3(0, H * 0.6, 0)
	_glow.visible = false
	add_child(_glow)


static var _gtex: ImageTexture
static func _glow_tex() -> ImageTexture:
	if _gtex:
		return _gtex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_gtex = ImageTexture.create_from_image(img)
	return _gtex


# ------------------------------------------------------------------ prey duck type
func alive() -> bool:
	return state != TAKEN


func pinned() -> void:
	if caught:
		return
	caught = true
	_go(CAUGHT, 0.0)
	vel = Vector3.ZERO
	PreySync.claim(self, PreySync.A_CATCH)


func stun(t: float) -> void:
	if caught or state in [HIDDEN, TAKEN]:
		return
	_stun = maxf(_stun, t)
	_go(STUN, t)
	CatSfx.play_at("rat_hurt" if kind == "rat" else "squeak", global_position, 0.6, 1.4 if kind == "mouse" else 1.0)
	PreySync.claim(self, PreySync.A_STUN)


## dropped out of the cat's mouth: shakes it off and bolts for a hole
func released() -> void:
	caught = false
	position = _on_ground(global_position)
	rotation = Vector3(0, yaw, 0)
	aware = FLEE_AT + 0.5
	threat = global_position + Vector3(sin(yaw), 0, cos(yaw)) * 0.3
	_bolt(true)
	PreySync.claim(self, PreySync.A_RELEASE)


## a bolting rabbit, a squealing rat: other wildlife's alarm (wildlife.gd call_group "wild")
func alarmed(from: Vector3, _by: String, src: Node) -> void:
	if src == self or caught or puppet or state in [HIDDEN, STUN, TAKEN, FLEE]:
		return
	if from.distance_to(global_position) > SQUEAK_R:
		return
	aware = maxf(aware, ALERT_AT + 0.35)
	if threat == Vector3.INF:
		threat = from
	if state == FORAGE:
		_go(ALERT, _rng.randf_range(1.0, 2.2))


# ------------------------------------------------------------------ brain
func _go(st: int, t: float) -> void:
	state = st
	state_t = t
	visible = st not in [HIDDEN, TAKEN]
	var in_group := st not in [HIDDEN, TAKEN]
	if live and in_group != is_in_group("prey"):
		if in_group:
			add_to_group("prey")
		else:
			remove_from_group("prey")


func _physics_process(dt: float) -> void:
	if not live:
		return
	_t += dt
	if state == CAUGHT:
		_wriggle(dt)
		return
	if state == TAKEN:
		visible = false
		return
	if puppet:
		_puppet_step(dt)
		_sense_glow(dt)
		return
	state_t -= dt
	if state == STUN:
		_stun -= dt
		_pose_stun()
		if _stun <= 0.0:
			aware = FLEE_AT + 0.2
			_bolt(false)
		return
	if state == HIDDEN:
		visible = false
		if state_t <= 0.0:
			_peek()
		return
	_notice(dt)
	match state:
		FORAGE:
			_forage(dt)
		ALERT:
			_alert(dt)
		FLEE:
			_flee(dt)
		PEEK:
			_peek_step(dt)
	_move(dt)
	_animate(dt)
	_sense_glow(dt)


## hearing + sight of every cat in the level -> awareness. footfalls carry; a crouched cat that
## creeps is near silent, a cat that keeps still is near invisible, a pounce in the air is not
func _notice(dt: float) -> void:
	heard = 0.0
	seen = 0.0
	var day := _daylight()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var nearest := 1e9
	var rush := false
	for th in _threats_now(get_tree()):
		var off: Vector3 = th.pos - global_position
		off.y *= 0.5
		var d := off.length()
		var spd: float = th.spd
		var crouched: bool = th.crouch > 0.5
		# noise: paw falls, louder the faster, landings thump
		var loud := clampf((spd - 0.25) / 3.0, 0.0, 1.3) * (0.28 if crouched else 1.0)
		if th.landed:
			loud = maxf(loud, 1.0)
		var hr: float = _sp.hear * loud
		if d < hr:
			heard = maxf(heard, 1.0 - d / hr)
		# sight: wide field, motion is what shows; eating = head down = half blind
		var vis := clampf(spd / 1.4, 0.06, 1.0) * (0.45 if crouched else 1.0)
		if th.air:
			vis = 1.0
		var sr: float = _sp.see * lerpf(0.45, 1.0, day) * (0.4 if _nibble else 1.0)
		var cosang := fwd.dot(Vector3(off.x, 0, off.z).normalized()) if d > 0.01 else 1.0
		if d < sr and cosang > -0.7:
			seen = maxf(seen, vis * (1.0 - d / sr))
		# smelled / felt at point blank
		if d < 0.45:
			seen = maxf(seen, 0.6)
		var closing: float = -th.vel.dot(off.normalized()) if d > 0.01 else 0.0
		if d < 3.5 and closing > CLOSE_RUSH and (th.air or not crouched or closing > 2.4):
			rush = true
		if d < nearest:
			nearest = d
			if heard > 0.05 or seen > 0.05 or rush:
				threat = th.pos
	var rate := (heard * 1.4 + seen * 2.0) * float(_sp.bold)
	if state == ALERT:
		rate *= 1.6   # looking right at you now
	aware = clampf(aware + rate * dt - (0.12 * dt if rate < 0.05 else 0.0), 0.0, 1.6)
	if state in [FLEE, PEEK]:
		return
	if _react >= 0.0:
		_react -= dt
		if _react < 0.0:
			_bolt(true)
		return
	if aware >= FLEE_AT or nearest < float(_sp.panic) or rush:
		# startle: a split second to react. caught unawares (head down in the food, or just
		# pottering about) it's a flinch, a jump on the spot, THEN the run; already on edge it goes
		_react = float(_sp.react) * _rng.randf_range(0.85, 1.2)
		if state == FORAGE:
			_react += STARTLE * (1.3 if _nibble else 1.0)
			_startle = STARTLE
		if rush or nearest < float(_sp.panic):
			aware = FLEE_AT
	elif state == FORAGE and aware >= ALERT_AT:
		_go(ALERT, _rng.randf_range(1.2, 2.6))


func _forage(_dt: float) -> void:
	if _nibble:
		vel = Vector3.ZERO
		if state_t <= 0.0:
			_nibble = false
			_pick_food()
		return
	var to := target - global_position
	to.y = 0
	if to.length() < 0.05 or state_t <= 0.0:
		_nibble = true
		state_t = _rng.randf_range(1.4, 4.0)
		vel = Vector3.ZERO
		return
	# stop-go scurry: little dashes with pauses, the classic rodent creep along cover
	var go := fmod(_t * (1.6 if kind == "mouse" else 1.1) + float(net_id) * 0.37, 1.0) < 0.6
	_steer(to.normalized(), float(_sp.walk) * (2.2 if go else 0.0))


func _alert(_dt: float) -> void:
	vel = vel.move_toward(Vector3.ZERO, 6.0 * _dt)
	_nibble = false
	if threat != Vector3.INF:
		var to := threat - global_position
		_turn_to(atan2(-to.x, -to.z), _dt, 2.0)
	if aware < ALERT_AT * 0.5 and state_t <= 0.0:
		_go(FORAGE, _rng.randf_range(0.5, 1.5))
		_nibble = true


func _bolt(squeal: bool) -> void:
	_react = -1.0
	_startle = 0.0
	_nibble = false
	_go(FLEE, 9.0)
	hide_at = _best_hide()
	if hide_at == Vector3.INF:
		var away := global_position - (threat if threat != Vector3.INF else global_position + Vector3.FORWARD)
		away.y = 0
		target = global_position + away.normalized() * _rng.randf_range(5.0, 8.0)
	else:
		target = hide_at
	if squeal:
		CatSfx.play_at("squeak", global_position, 0.5 if kind == "mouse" else 0.8, 1.5 if kind == "mouse" else 0.8)
		# the colony hears it
		get_tree().call_group("wild", "alarmed", global_position, kind, self)


## the nearest hole that isn't past the cat
func _best_hide() -> Vector3:
	var best := Vector3.INF
	var bs := 1e9
	var me := global_position
	var tdir := Vector3.ZERO
	if threat != Vector3.INF:
		tdir = Vector3(threat.x - me.x, 0, threat.z - me.z)
	for h in hides:
		var to := Vector3(h.x - me.x, 0, h.z - me.z)
		var d := to.length()
		if d > 14.0:
			continue
		var score := d
		if tdir.length() > 0.01 and d > 0.01:
			var c := to.normalized().dot(tdir.normalized())
			# running past the cat: only if the hole is right here and the cat isn't
			if c > 0.5 and tdir.length() < d + 0.5:
				score += 8.0 + c * 6.0
			else:
				score += maxf(c, 0.0) * 2.0
		if score < bs:
			bs = score
			best = h
	return best


func _flee(dt: float) -> void:
	var to := target - global_position
	to.y = 0
	var d := to.length()
	if hide_at != Vector3.INF and d < 0.06 + float(_sp.len) * 0.3:
		_go(HIDDEN, _rng.randf_range(_sp.hide.x, _sp.hide.y))
		position = _on_ground(hide_at)
		vel = Vector3.ZERO
		aware = 0.35
		return
	if hide_at == Vector3.INF and d < 0.3 or state_t <= 0.0:
		_go(ALERT, _rng.randf_range(1.5, 3.0))
		return
	var dir := to / maxf(d, 0.001)
	# mice jink: zig zags that throw off a pounce, straightening up near the hole
	var zig: float = _sp.zig * clampf(d / 2.0, 0.0, 1.0)
	var side := Vector3(-dir.z, 0, dir.x) * sin(_t * 9.0 + float(net_id)) * zig
	_steer((dir + side).normalized(), float(_sp.run))
	if dt > 0.0 and state_t > 8.6:
		vel *= 0.6 + (9.0 - state_t) * 0.8   # push off: a few strides to top speed


func _peek() -> void:
	_go(PEEK, _rng.randf_range(1.4, 3.0))
	visible = true
	aware = minf(aware, 0.4)
	_peek_y = 0.0


func _peek_step(dt: float) -> void:
	vel = Vector3.ZERO
	_peek_y = minf(_peek_y + dt * 1.5, 1.0)
	if threat != Vector3.INF:
		var to := threat - global_position
		_turn_to(atan2(-to.x, -to.z), dt, 3.0)
	if aware > ALERT_AT + 0.1 or _react >= 0.0:
		# nope: back down the hole
		_react = -1.0
		_go(HIDDEN, _rng.randf_range(_sp.hide.x, _sp.hide.y) * 0.6)
		return
	if state_t <= 0.0:
		_go(FORAGE, 0.5)
		_nibble = false
		aware = 0.2
		_pick_food()


func _pick_food() -> void:
	for k in 6:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * float(_sp.range)
		var p := home + Vector3(cos(a) * r, 0, sin(a) * r)
		if not _blocked(Vector2(p.x, p.z), 0.08):
			target = p
			state_t = 6.0
			return
	target = home
	state_t = 6.0


func _blocked(p: Vector2, pad: float) -> bool:
	for b in blockers:
		if p.distance_to(b[0]) < float(b[1]) + pad:
			return true
	return false


## steer toward `dir` at `spd`, sliding round blockers
func _steer(dir: Vector3, spd: float) -> void:
	var p := Vector2(global_position.x, global_position.z)
	var d2 := Vector2(dir.x, dir.z)
	var goal := Vector2(target.x, target.z)
	for b in blockers:
		var c: Vector2 = b[0]
		var r: float = float(b[1]) + 0.1
		if goal.distance_to(c) < r + 0.3:
			continue   # the hole is at its foot: run right up to it
		var off := p - c
		var dist := off.length()
		if dist < r + 0.4 and dist > 0.001:
			var n := off / dist
			if d2.dot(n) < 0.0:
				# heading in: run along the edge instead (whichever way is closer to the goal)
				var t := Vector2(-n.y, n.x)
				if t.dot(d2) < 0.0:
					t = -t
				var k := clampf((r + 0.4 - dist) / 0.4, 0.0, 1.0)
				d2 = (d2 * (1.0 - k) + t * k + n * k * 0.3).normalized()
	var want := Vector3(d2.x, 0, d2.y) * spd
	vel = vel.move_toward(want, (18.0 if spd > 1.0 else 8.0) * get_physics_process_delta_time())


func _turn_to(a: float, dt: float, rate: float) -> void:
	yaw = lerp_angle(yaw, a, minf(dt * rate * 4.0, 1.0))


func _move(dt: float) -> void:
	if vel.length() > 0.05:
		_turn_to(atan2(-vel.x, -vel.z), dt, 3.5)
	var np := global_position + vel * dt
	np = _on_ground(np)
	global_position = np
	rotation = Vector3(0, yaw, 0)


func _on_ground(p: Vector3) -> Vector3:
	if ground_y.is_valid():
		return Vector3(p.x, float(ground_y.call(p.x, p.z)), p.z)
	if not is_inside_tree():
		return p
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.35, p + Vector3.DOWN * 1.2)
	var ex: Array[RID] = []
	for c in get_tree().get_nodes_in_group("player"):
		if c is CollisionObject3D:
			ex.append((c as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return p
	return Vector3(p.x, hit.position.y, p.z)


func _daylight() -> float:
	var cs := get_tree().current_scene
	var at = cs.get("atmos") if cs else null
	if at != null and is_instance_valid(at) and at.has_method("daylight"):
		return float(at.daylight())
	return 1.0


# ------------------------------------------------------------------ threats (every cat in the level)
static func _threats_now(tree: SceneTree) -> Array:
	var f := Engine.get_physics_frames()
	if f == _threat_frame:
		return _threats
	_threat_frame = f
	_threats = []
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for p in tree.get_nodes_in_group("player"):
		if not p is CharacterBody3D or not (p as Node3D).is_inside_tree():
			continue
		var cb := p as CharacterBody3D
		var v := cb.velocity
		var fl := cb.is_on_floor()
		var id := cb.get_instance_id()
		# a real thump (dropped from more than ~8 cm), not stepping off a root
		var lp: Array = _land_prev.get(id, [true, 0.0])
		var landed: bool = fl and not bool(lp[0]) and float(lp[1]) < -1.25
		_land_prev[id] = [fl, v.y]
		_threats.append({"pos": cb.global_position, "vel": Vector3(v.x, 0, v.z), "spd": Vector2(v.x, v.z).length(),
			"crouch": float(cb.get("crouch_amt")) if "crouch_amt" in cb else 0.0, "air": not fl and Vector2(v.x, v.z).length() > 1.5, "landed": landed})
	var cs := tree.current_scene
	if cs:
		for c in cs.get_children():
			if not c is RemoteCat:
				continue
			var rc := c as RemoteCat
			var q := rc.global_position
			if rc.rig:
				q = rc.rig.global_position
			var id := rc.get_instance_id()
			var prev: Vector3 = _remote_prev.get(id, q)
			_remote_prev[id] = q
			var v := (q - prev) / dt
			var cr := float(rc.rig.get("crouch")) if rc.rig else 0.0
			_threats.append({"pos": q, "vel": Vector3(v.x, 0, v.z), "spd": Vector2(v.x, v.z).length(), "crouch": cr,
				"air": absf(v.y) > 1.0 and Vector2(v.x, v.z).length() > 1.5, "landed": v.y < -1.5})
	return _threats


# ------------------------------------------------------------------ animation
func _animate(dt: float) -> void:
	var spd := vel.length()
	var sit_want := 0.0
	var head_down := 0.0
	if state == FORAGE and _nibble:
		# eats sat up, food in the forepaws, or nose down in the litter
		sit_want = 0.55 if fmod(float(net_id) * 0.7 + floor(_t / 3.0) * 0.43, 1.0) < 0.5 else 0.0
		head_down = 0.0 if sit_want > 0.0 else 0.6
	elif state == ALERT:
		# sits right up, nose in the air, ears and whiskers on you
		sit_want = 0.95 if kind == "mouse" else 0.75
	elif state == PEEK:
		sit_want = 0.0
	_sit = move_toward(_sit, sit_want, dt * 5.0)
	_head_down = move_toward(_head_down, head_down, dt * 4.0)
	_gait.step(dt, spd, "half_bound")
	_hip.rotation.x = _sit * 1.05
	_body.position.y = _gait.dy
	_body.rotation.x = _gait.pitch
	_hip.position.y = 0.0
	# head: chewing bob, sniffing twitch, looking at the threat
	var chew := sin(_t * 22.0) * 0.06 if _nibble else 0.0
	var sniff := sin(_t * 31.0) * 0.03
	var look_a := 0.0
	if state in [ALERT, PEEK] and threat != Vector3.INF:
		var to := threat - global_position
		look_a = wrapf(atan2(-to.x, -to.z) - yaw, -PI, PI)
	_look = lerpf(_look, clampf(look_a, -1.2, 1.2), minf(dt * 8.0, 1.0))
	_head.rotation = Vector3(-_sit * 0.7 + _head_down * 0.6 + chew + sniff, _look, 0)
	# tail: drags and swings when running, flicks when nervous
	var flick := aware * 0.6
	for i in _tail.size():
		var ph := _t * (6.0 + flick * 10.0) - i * 0.9
		_tail[i].rotation = Vector3(-0.15 + _sit * 0.25 * float(i == 0), sin(ph) * (0.18 + flick * 0.3 + spd * 0.05), 0)
	# the flinch: a straight up jump on the spot (mice spring several body lengths)
	if _startle > 0.0:
		_startle = maxf(_startle - dt, 0.0)
		var k := 1.0 - _startle / STARTLE
		_hip.position.y = sin(k * PI) * float(_sp.len) * (1.1 if kind == "mouse" else 0.5)
		_hip.rotation.x = 0.4 * sin(k * PI)
	# peeking: only the head and shoulders come up out of the hole
	if state == PEEK:
		_hip.position.y = -float(_sp.h) * 1.1 * (1.0 - _peek_y * 0.55)
		_hip.rotation.x = 0.5


func _pose_stun() -> void:
	vel = Vector3.ZERO
	_hip.rotation = Vector3(0, 0, 1.4)
	_head.rotation = Vector3(0.2, 0, 0)
	for i in _tail.size():
		_tail[i].rotation = Vector3(0, sin(_t * 18.0 + i) * 0.15, 0)


func _wriggle(_dt: float) -> void:
	_hip.rotation = Vector3(0, 0, sin(_t * (14.0 if kind == "rat" else 20.0)) * 0.25)
	_head.rotation = Vector3(0.3, sin(_t * 11.0) * 0.4, 0)
	for i in _tail.size():
		_tail[i].rotation = Vector3(0.3, sin(_t * 12.0 - i * 1.2) * 0.5, 0)


## crouch + keep still (cat sense) and nearby prey shimmer through the grass; the hunt can be
## played by eye without it, it's a nudge, not a radar
func _sense_glow(dt: float) -> void:
	var lvl := 0.0
	if vision >= 0.0:
		lvl = vision
	else:
		var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
		if p and "crouch_amt" in p:
			var still := Vector2(p.velocity.x, p.velocity.z).length() < CatSense.STILL_SPEED and float(p.get("crouch_amt")) > 0.7
			_still_t = _still_t + dt if still else 0.0
			lvl = 1.0 if _still_t > CatSense.WAIT else 0.0
			var d := p.global_position.distance_to(global_position)
			lvl *= clampf((CatSense.RANGE - d) / 4.0, 0.0, 1.0)
	_sense = move_toward(_sense, lvl, dt / (CatSense.RISE if lvl > _sense else CatSense.FALL))
	_glow.visible = _sense > 0.01 and visible
	if _glow.visible:
		var m := _glow.material_override as StandardMaterial3D
		m.albedo_color.a = _sense * (0.32 + 0.12 * sin(_t * 4.0 + float(net_id)))


# ------------------------------------------------------------------ network (PreySync)
## what goes on the wire for this one: state, position, yaw, awareness
func net_pack() -> Array:
	return [state, global_position.x, global_position.z, yaw, aware]


func net_apply(st: int, x: float, z: float, y: float, aw: float) -> void:
	if caught:
		return   # it's in my own mouth: mine until I drop it (the authority hears my claim)
	if st == CAUGHT:
		st = TAKEN   # someone else's mouth
	if st != state:
		_go(st, 1.0)
		if st == PEEK:
			_peek_y = 0.0
	_net_pos = Vector3(x, global_position.y, z)
	_net_yaw = y
	aware = aw


func _puppet_step(dt: float) -> void:
	if state == HIDDEN:
		visible = false
		return
	if _net_pos != Vector3.INF:
		var before := global_position
		var np := global_position.lerp(Vector3(_net_pos.x, global_position.y, _net_pos.z), minf(dt * 14.0, 1.0))
		if before.distance_to(_net_pos) > 2.0:
			np = _net_pos   # teleport (hid and came out elsewhere)
		np = _on_ground(np)
		global_position = np
		vel = (np - before) / maxf(dt, 0.001)
		vel.y = 0.0
		yaw = lerp_angle(yaw, _net_yaw, minf(dt * 12.0, 1.0))
		rotation = Vector3(0, yaw, 0)
	_nibble = state == FORAGE and vel.length() < 0.05
	if state == STUN:
		_pose_stun()
	elif state == PEEK:
		_peek_y = minf(_peek_y + dt * 1.5, 1.0)
		_animate(dt)
	else:
		_animate(dt)
