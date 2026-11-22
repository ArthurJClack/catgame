class_name CatSpar
extends Node
## cat vs cat PLAY FIGHTING (no claws, no damage). lock on (tab) to another player's cat (or the
## practice cat) and it turns into a little 3d fighting game on the buttons you already have:
##
##   swat                 quick bop (HIGH). mash: left, right, then a two paw "bap" (MID) finisher
##   crouch + swat        low sweep at the legs (LOW)
##   forward + swat       lunging bop: long reach, slow, tracks sidesteps (MID, homing)
##   hold swat            rear up -> two paw slam (OVERHEAD: hits ducking cats)
##   grab                 clinch / throw -> wrestle: both roll over, mash swat = bunny kicks,
##                        out kick them and you pin (big points), or they kick free
##   strings              bop bop -> crouch swat = high high low. bop -> grab = clinch.
##                        any bop -> hold = delayed overhead
##   hold back            GUARD: blocks high / mid / overhead, lows get through
##   crouch               DUCK: highs whiff over, blocks lows, overheads and mids still tag you
##   dodge + a / d        sidestep (the normal dodge, so it looks like it): straight bops miss
##   dodge + swat         COUNTER right as a bop lands (same input as the sekiro deflect: uses
##                        player.parry when that's in, else its own short window). they stumble
##   grab as they grab    throw break (tech)
##
## getting tagged while you were winding up your own move = COUNTER HIT (more points, longer
## flinch). no health: every clean tag fills a PLAY meter, fill it and you take the round,
## best of 3, little ready / play! intro, the loser flops onto its back.
##
## online: nobody is in charge of the world (see Net), so the cat that swings checks the reach
## against what it sees and sends the strike, the cat that gets swung at resolves it against its
## own guard / duck / sidestep / counter and sends back what happened. both apply the same points
## from the same results. rounds are refereed by the lower id of the pair. everything rides the
## rig's life_log (["S", to, kind, ...]), so it gets the snapshot stream's repeats + de-dup for free.
## locally (practice cat) the two CatSpars hand each other the same events directly.

enum { R_OFF, R_INTRO, R_FIGHT, R_KO, R_DONE }

const METER := 100.0
const ROUNDS_TO_WIN := 2
const INTRO_T := 1.7
const KO_T := 2.4
const DONE_T := 3.2
const BUFFER := 0.26          # a press waits this long for the next string slot
const HOLD_T := 0.3           # swat held this long = rear up overhead
const COUNTER_T := 0.2        # fallback counter window (no CatParry)
const COUNTER_WHIFF := 0.32   # missed counter: a short recovery you can be tagged in
const TECH_T := 0.28          # grab pressed this soon after their throw lands = break
const WRESTLE_T := 1.8
const WRESTLE_WAIT := 0.6     # thrower waits this long for the other side's kick count
const THROW_EDGE := 4         # the thrower is on top: the other side must out kick it by this
const PAIR_KEEP := 2.6        # no "still locked on you" from the other side this long = not playing
const PAIR_PING := 0.7
const FACE_COS := 0.62        # strike connects only roughly in front (cos of ~52 deg)
const BODY_R := 0.24          # target body half length counted onto reach

## levels: what beats what
##   HIGH: guard blocks, duck whiffs it. MID: guard blocks, duck gets hit. LOW: duck blocks,
##   standing guard gets hit. OVERHEAD: guard blocks, duck gets hit hard. THROW: beats guard,
##   duck whiffs it, a grab at the right moment breaks it
const MOVES := {
	"jab":  {"lvl": "high", "wind": 0.10, "active": 0.06, "recover": 0.18, "chain": [0.03, 0.26], "reach": 0.82,
		"pts": 8.0, "stun": 0.3, "bstun": 0.16, "knock": 0.6, "next": "jab2"},
	"jab2": {"lvl": "high", "wind": 0.10, "active": 0.06, "recover": 0.2, "chain": [0.03, 0.28], "reach": 0.82,
		"pts": 8.0, "stun": 0.32, "bstun": 0.16, "knock": 0.6, "next": "bap"},
	"bap":  {"lvl": "mid", "wind": 0.16, "active": 0.08, "recover": 0.34, "chain": [], "reach": 0.86,
		"pts": 14.0, "stun": 0.5, "bstun": 0.26, "knock": 1.5, "two": true},
	"low":  {"lvl": "low", "wind": 0.14, "active": 0.07, "recover": 0.3, "chain": [0.05, 0.22], "reach": 0.8,
		"pts": 11.0, "stun": 0.42, "bstun": 0.2, "knock": 0.5, "next": "jab"},
	"lunge": {"lvl": "mid", "wind": 0.22, "active": 0.1, "recover": 0.34, "chain": [], "reach": 0.9,
		"pts": 12.0, "stun": 0.45, "bstun": 0.22, "knock": 1.2, "homing": true, "dash": 3.2},
	"over": {"lvl": "over", "wind": 0.3, "active": 0.1, "recover": 0.4, "chain": [], "reach": 0.92,
		"pts": 17.0, "stun": 0.6, "bstun": 0.3, "knock": 1.0, "two": true, "dash": 1.8},
	"throw": {"lvl": "throw", "wind": 0.12, "active": 0.08, "recover": 0.46, "chain": [], "reach": 0.7,
		"pts": 10.0, "stun": 0.0, "bstun": 0.0, "knock": 0.0, "dash": 2.2},
}
const PIN_PTS := 26.0
const ESCAPE_PTS := 8.0
const COUNTER_PTS := 14.0
const TECH_PTS := 3.0
const CHIP := 2.0
const CH_MUL := 1.6

var player: Node3D            # CatPlayer (untyped: no cycle)
var dummy := false            # the practice cat (a bot CatPlayer with its own brain)
var brain: CatSparBrain = null
var forced: Node3D = null     # dummies pick their opponent directly (no lock on)
var hud: CatSparHud = null

# my move
var move := ""
var mt := 0.0                 # time into the move
var phase := 0                # 0 wind, 1 active, 2 recover
var hit_sent := false
var string_n := 0             # how many strikes deep into the current string
var _buf := ""                # "swat" / "grab" waiting for a slot
var _buf_t := 0.0
var _buf_mod := {}            # crouch / fwd held when it was pressed
var _sw_prev := false
var _gr_prev := false
var _sw_hold := 0.0
var _hold_used := false
var _seq := 0

# defense / reactions
var counter_t := 0.0          # fallback counter window open
var counter_rec := 0.0
var stun := 0.0
var stun_max := 0.0
var react := ""               # "high" / "low" / "big" / "block" / "stumble" / "thrown"
var guard := false
var duck := false
var _tech_t := 0.0            # grab pressed recently (throw break)
var _pending_throw := {}      # throw that landed on me, waiting out the tech window
var _kb := Vector3.ZERO       # knockback still to hand to the body

# wrestle
var wrestle := 0.0            # time left (>0 = rolling about)
var wrestle_top := false      # I threw: I'm on top and I judge it
var wrestle_with: Node3D = null
var kicks := 0
var their_kicks := -1
var _wr_wait := 0.0
var pinned := 0.0             # > 0 on my back being pinned (or pinning)
var pin_top := false

# match
var opp: Node3D = null        # who I'm playing with (stays while the match runs)
var they_lock := 0.0          # time since the other side said it's locked on me
var _ping := 0.0
var my_pts := 0.0
var their_pts := 0.0
var my_wins := 0
var their_wins := 0
var round_state := R_OFF
var round_t := 0.0
var round_n := 1
var round_winner := 0         # sid
var banner := ""
var banner_t := 0.0

# counters for tests
var stats := {"hits": 0, "blocked": 0, "whiffs": 0, "evaded": 0, "countered": 0, "thrown": 0,
	"teched": 0, "pins": 0, "escapes": 0, "ch": 0, "got_hit": 0, "sent": 0, "rounds": 0, "matches": 0}
var last_result := ""
var results: Array = []       # [move, result] of my strikes, newest last (tests)
var log_results := false

var _inbox: Array = []        # [from_node, ev] delivered by a local CatSpar
static var dummy_count := 0
var _dummy_sid := 0


func _ready() -> void:
	if dummy:
		dummy_count += 1
		_dummy_sid = -dummy_count
		player.add_to_group("spar_cat")
		player.add_to_group("spar_dummy")
		if brain == null:
			brain = CatSparBrain.new()
		brain.spar = self
	else:
		if brain:
			brain.spar = self
		hud = CatSparHud.new()
		hud.spar = self
		add_child(hud)


# ------------------------------------------------------------------ ids + targets

func my_sid() -> int:
	if dummy:
		return _dummy_sid
	var net := get_node_or_null("/root/Net")
	if net and net.transport:
		return int(net.my_id())
	return 1


static func sid_of(n: Node) -> int:
	if n == null or not is_instance_valid(n):
		return 0
	if n is RemoteCat:
		return (n as RemoteCat).peer.id if (n as RemoteCat).peer else 0
	var s = n.get("spar")
	if s is CatSpar:
		return (s as CatSpar).my_sid()
	return 0


static func spar_of(n: Node) -> CatSpar:
	if n == null or not is_instance_valid(n):
		return null
	var s = n.get("spar")
	return s if s is CatSpar else null


## where another cat's body is (a remote cat's node stays put, its rig moves)
static func pos_of(n: Node3D) -> Vector3:
	if n is RemoteCat and (n as RemoteCat).rig:
		return (n as RemoteCat).rig.global_position
	return n.global_position


func target() -> Node3D:
	if is_instance_valid(forced) and forced.is_inside_tree():
		return forced
	var lt = player.get("lock_target")
	if lt is Node3D and is_instance_valid(lt) and (lt as Node).is_in_group("spar_cat") and lt != player:
		return lt
	return null


## a playmate close enough that tab should lock on to it (outside the rat pit too)
func playmate_near(r := 9.0) -> bool:
	for n in player.get_tree().get_nodes_in_group("spar_cat"):
		if n != player and n is Node3D and pos_of(n).distance_to(player.global_position) < r:
			return true
	return false


func in_match() -> bool:
	return round_state != R_OFF


func fighting() -> bool:
	return round_state == R_FIGHT


func busy() -> bool:
	return move != "" or stun > 0.0 or wrestle > 0.0 or pinned > 0.0 or counter_rec > 0.0


## winding up / swinging right now (getting tagged now = counter hit)
func exposed() -> bool:
	return move != "" and phase <= 1


func meter(mine := true) -> float:
	return clampf((my_pts if mine else their_pts) / METER, 0.0, 1.0)


# ------------------------------------------------------------------ the tick (from the player)

## called first thing in CatPlayer._physics_process with this tick's input. returns the input the
## controller should use (the paws / grab / pounce are eaten while play fighting)
func filter(inp: Dictionary, dt: float) -> Dictionary:
	if brain:
		inp = brain.think(dt)   # practice cat / test bots
	for m in _inbox:
		on_event(m[0], m[1])
	_inbox.clear()
	_timers(dt)
	var tgt := target()
	_pairing(tgt, dt)
	_round_tick(dt)
	var live := tgt != null or busy() or in_match()
	if not live:
		_sw_prev = inp.get("paw_l", false) or inp.get("paw_r", false) or inp.get("swat", false)
		_gr_prev = inp.get("grab", false)
		guard = false
		duck = false
		return inp
	inp = inp.duplicate()
	var sw: bool = inp.get("paw_l", false) or inp.get("paw_r", false) or inp.get("swat", false)
	var gr: bool = inp.get("grab", false)
	var mv: Vector2 = inp.get("move", Vector2.ZERO)
	var sw_press := sw and not _sw_prev
	var gr_press := gr and not _gr_prev
	_sw_prev = sw
	_gr_prev = gr
	_sw_hold = _sw_hold + dt if sw else 0.0
	if not sw:
		_hold_used = false
	if gr_press:
		_tech_t = TECH_T
	for k in ["paw_l", "paw_r", "swat", "grab", "pounce"]:
		inp[k] = false
	if sw_press and wrestle > 0.0:
		kick_press()
	var frozen := round_state in [R_INTRO, R_KO, R_DONE] or stun > 0.0 or wrestle > 0.0 or pinned > 0.0 or _wr_wait > 0.0
	if frozen:
		inp.move = Vector2.ZERO
		if round_state == R_INTRO and tgt and stun <= 0.0 and wrestle <= 0.0 and pinned <= 0.0:
			# squaring up for the round: settle at a bop's distance
			var dd := pos_of(tgt).distance_to(player.global_position)
			if dd < 0.85:
				inp.move = Vector2(0, -0.6)
			elif dd > 1.25:
				inp.move = Vector2(0, 0.6)
		elif (wrestle > 0.0 or _wr_wait > 0.0) and not wrestle_top and is_instance_valid(wrestle_with):
			# tangled up: the one underneath gets pulled in against the thrower
			var to := pos_of(wrestle_with) - player.global_position
			to.y = 0.0
			if to.length() > 0.32:
				var v := to.normalized() * minf(2.0, (to.length() - 0.3) * 8.0)
				player.velocity.x = v.x
				player.velocity.z = v.z
		for k in ["jump", "dash", "crouch", "sprint", "canter", "scratch", "aim"]:
			inp[k] = false
		guard = false
		duck = false
		_buf = ""
		_apply_kb()
		return inp
	var crouch: bool = inp.get("crouch", false)
	var fwd := mv.y > 0.55
	var back := mv.y < -0.3
	# counter: dodge held + swat. the deflect itself is CatParry's when that's in (it eats the
	# swat while the dodge is held), otherwise a short window of our own
	var dodge_held: bool = inp.get("dash", false)
	if sw_press and dodge_held and player.get("parry") == null and move == "" and counter_rec <= 0.0:
		counter_t = COUNTER_T
		counter_rec = COUNTER_T + COUNTER_WHIFF
		sw_press = false
		if player.get("dash"):
			player.dash.cancel()
		inp.dash = false
	if sw_press:
		_buf = "swat"
		_buf_t = BUFFER
		_buf_mod = {"crouch": crouch, "fwd": fwd}
	elif gr_press:
		_buf = "grab"
		_buf_t = BUFFER
		_buf_mod = {"crouch": crouch, "fwd": fwd}
	_step_move(dt, tgt, sw)
	if _buf != "" and counter_rec <= 0.0:
		_try_start(tgt)
	guard = back and not crouch and move == "" and counter_rec <= 0.0 and player.is_on_floor()
	duck = crouch and move == "" and counter_rec <= 0.0
	if guard:
		inp.move = mv * 0.12   # guarding: backing off slowly, not running away
		inp.sprint = false
		inp.canter = false
	if move != "":
		# committed: the feet only creep, no hopping out of it
		inp.move = mv * 0.15
		for k in ["jump", "dash", "sprint", "canter", "scratch"]:
			inp[k] = false
		inp.crouch = move == "low"
	_apply_kb()
	return inp


func _timers(dt: float) -> void:
	_buf_t -= dt
	if _buf_t <= 0.0:
		_buf = ""
	counter_t = maxf(counter_t - dt, 0.0)
	counter_rec = maxf(counter_rec - dt, 0.0)
	_tech_t = maxf(_tech_t - dt, 0.0)
	if stun > 0.0:
		stun = maxf(stun - dt, 0.0)
		if stun <= 0.0:
			react = ""
	banner_t += dt
	they_lock += dt
	if not _pending_throw.is_empty():
		_pending_throw.t -= dt
		if _tech_t > 0.0 and _pending_throw.t < TECH_T:
			_finish_throw(true)
		elif _pending_throw.t <= 0.0:
			_finish_throw(false)
	if wrestle > 0.0:
		wrestle -= dt
		if wrestle <= 0.0:
			_wrestle_over()
	if _wr_wait > 0.0:
		_wr_wait -= dt
		if _wr_wait <= 0.0 or their_kicks >= 0:
			_judge_wrestle()
	if pinned > 0.0:
		pinned = maxf(pinned - dt, 0.0)


func _apply_kb() -> void:
	if _kb != Vector3.ZERO:
		player.velocity += _kb
		_kb = Vector3.ZERO


# ------------------------------------------------------------------ attacking

func _try_start(tgt: Node3D) -> void:
	var pick := ""
	if move == "":
		if _buf == "grab":
			pick = "throw"
		elif _buf_mod.get("crouch", false):
			pick = "low"
		elif _buf_mod.get("fwd", false):
			pick = "lunge"
		else:
			pick = "jab"
		string_n = 0
	else:
		var m: Dictionary = MOVES[move]
		var ch: Array = m.chain
		if phase != 2 or ch.is_empty() or mt - m.wind - m.active < ch[0] or mt - m.wind - m.active > ch[1]:
			return
		if _buf == "grab":
			pick = "throw"
		elif _buf_mod.get("crouch", false):
			pick = "low"
		else:
			pick = m.get("next", "")
		if pick == "":
			return
	_buf = ""
	_start(pick, tgt)


func _start(m: String, _tgt: Node3D) -> void:
	move = m
	mt = 0.0
	phase = 0
	hit_sent = false
	string_n += 1
	if player.get("stamina"):
		player.stamina.spend(2.0)


func _step_move(dt: float, tgt: Node3D, sw_held: bool) -> void:
	# hold swat: rear up into the overhead (from standing, or delayed out of a bop)
	if sw_held and _sw_hold >= HOLD_T and not _hold_used and (move == "" or (move in ["jab", "jab2", "low"] and phase == 2)):
		_hold_used = true
		_start("over", tgt)
		mt = 0.08     # it was already rising while the button was held
	if move == "":
		return
	var m: Dictionary = MOVES[move]
	mt += dt
	var was := phase
	phase = 0 if mt < m.wind else (1 if mt < m.wind + m.active else 2)
	if phase == 1 and was == 0:
		_strike_fx(tgt)
	# lunge: the hind legs push it in, stops short of the other cat
	if m.has("dash") and phase <= 1 and mt > m.wind * 0.35 and tgt:
		var to := pos_of(tgt) - player.global_position
		to.y = 0.0
		var room := to.length() - 0.42
		if room > 0.02:
			var v: Vector3 = to.normalized() * minf(m.dash, room / maxf(dt, 0.001) * 0.5)
			player.velocity.x = v.x
			player.velocity.z = v.z
	if phase == 1 and was == 0 and log_results:
		print("[spar %d] %s out: d %.2f  face %.2f" % [my_sid(), move, (pos_of(tgt) - player.global_position).length() if tgt else -1.0, ((pos_of(tgt) - player.global_position).normalized()).dot(-player.global_transform.basis.z) if tgt else 0.0])
	if phase == 1 and not hit_sent and tgt:
		if _connects(tgt, m):
			hit_sent = true
			_seq += 1
			stats.sent += 1
			_send(tgt, ["atk", _seq, move])
	if mt >= m.wind + m.active + m.recover:
		if not hit_sent and move != "":
			stats.whiffs += 1
		move = ""
		phase = 0
		string_n = 0


func _connects(tgt: Node3D, m: Dictionary) -> bool:
	var to := pos_of(tgt) - player.global_position
	to.y = 0.0
	var d := to.length()
	if d > float(m.reach) + BODY_R:
		return false
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	return d < 0.25 or fwd.normalized().dot(to / d) > FACE_COS


# ------------------------------------------------------------------ getting swung at

## an event from another cat. from = its node (RemoteCat or a local CatPlayer)
func on_event(from: Node3D, ev: Array) -> void:
	if ev.size() < 1:
		return
	match str(ev[0]):
		"atk":
			_defend(from, int(ev[1]), str(ev[2]))
		"res":
			_on_result(from, str(ev[2]), str(ev[3]))
		"lock":
			if bool(ev[1]):
				they_lock = 0.0
				if opp == null or not is_instance_valid(opp):
					opp = from
			else:
				they_lock = PAIR_KEEP
		"kicks":
			their_kicks = int(ev[1])
		"wr":
			_wrestle_result(from, str(ev[1]))
		"round":
			_on_round(from, ev)


func _defend(from: Node3D, seq: int, mname: String) -> void:
	if not MOVES.has(mname):
		return
	var m: Dictionary = MOVES[mname]
	var lvl: String = m.lvl
	var res := "hit"
	var parry = player.get("parry")
	var dashing: bool = player.get("dash") != null and player.dash.busy()
	var dkind: int = int(player.dash.kind) if dashing else -1
	if wrestle > 0.0 or pinned > 0.0:
		res = "whiff"
	elif lvl == "throw":
		if duck:
			res = "whiff"
		elif move == "throw" and phase <= 1:
			res = "tech"           # both grabbed: they bounce off each other
		elif dashing and dkind == CatDash.Kind.SIDE:
			res = "evaded"
		else:
			_pending_throw = {"from": from, "seq": seq, "t": TECH_T}
			if _tech_t > 0.0:
				_finish_throw(true)
			return
	elif (parry != null and parry.has_method("try_deflect") and parry.try_deflect(from, pos_of(from), false)) or counter_t > 0.0:
		res = "countered"
	elif dashing and dkind == CatDash.Kind.SIDE and not m.get("homing", false):
		res = "evaded"
	elif dashing and dkind == CatDash.Kind.BACK and pos_of(from).distance_to(player.global_position) > float(m.reach) * 0.8:
		res = "evaded"
	elif lvl == "high" and duck:
		res = "whiff"
	elif lvl in ["high", "mid", "over"] and guard:
		res = "blocked"
	elif lvl == "low" and duck:
		res = "blocked"
	elif exposed():
		res = "ch"
	_resolve(from, seq, mname, res)


func _finish_throw(teched: bool) -> void:
	var from: Node3D = _pending_throw.get("from")
	var seq: int = _pending_throw.get("seq", 0)
	_pending_throw = {}
	if from == null or not is_instance_valid(from):
		return
	_resolve(from, seq, "throw", "tech" if teched else "thrown")


## I'm the one who got swung at: react, score it, tell the other side
func _resolve(from: Node3D, seq: int, mname: String, res: String) -> void:
	var m: Dictionary = MOVES[mname]
	var away := player.global_position - pos_of(from)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else player.global_transform.basis.z
	match res:
		"hit", "ch":
			var mul := CH_MUL if res == "ch" else 1.0
			_cancel_move()
			stun = float(m.stun) * (1.5 if res == "ch" else 1.0)
			stun_max = stun
			react = "big" if m.lvl in ["mid", "over"] and m.get("two", false) else ("low" if m.lvl == "low" else "high")
			_kb = away * float(m.knock) * mul
			their_pts += float(m.pts) * mul
			stats.got_hit += 1
			_fx_hit(pos_of(from), m.lvl == "low")
		"blocked":
			stun = float(m.bstun)
			stun_max = stun
			react = "block"
			_kb = away * 0.7
			their_pts += CHIP
			_fx_block()
		"countered":
			my_pts += COUNTER_PTS
			stats.countered += 1
			counter_t = 0.0
			counter_rec = 0.0
			_fx_counter(pos_of(from))
		"evaded":
			stats.evaded += 1
		"tech":
			stats.teched += 1
			my_pts += TECH_PTS
			_cancel_move()
			stun = 0.25
			stun_max = stun
			react = "block"
			_kb = away * 1.4
			_fx_block()
		"thrown":
			_cancel_move()
			their_pts += float(m.pts)
			_begin_wrestle(from, false)
	last_result = res
	if log_results:
		print("[spar %d] %s's %s -> %s  (%.0f / %.0f)" % [my_sid(), str(sid_of(from)), mname, res, my_pts, their_pts])
	_send(from, ["res", seq, mname, res])


## the other side told me how my strike went
func _on_result(from: Node3D, mname: String, res: String) -> void:
	if not MOVES.has(mname):
		return
	var m: Dictionary = MOVES[mname]
	var away := player.global_position - pos_of(from)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else player.global_transform.basis.z
	last_result = res
	results.append([mname, res])
	if results.size() > 32:
		results.pop_front()
	match res:
		"hit", "ch":
			var mul := CH_MUL if res == "ch" else 1.0
			my_pts += float(m.pts) * mul
			stats.hits += 1
			if res == "ch":
				stats.ch += 1
			_fx_hit(pos_of(from), m.lvl == "low", true)
		"blocked":
			my_pts += CHIP
			stats.blocked += 1
			_kb = away * 0.5
		"countered":
			their_pts += COUNTER_PTS
			_cancel_move()
			stun = 0.55
			stun_max = stun
			react = "stumble"
			_kb = away * 0.9
		"whiff":
			stats.whiffs += 1
		"evaded":
			stats.evaded += 1
		"tech":
			their_pts += TECH_PTS
			_cancel_move()
			stun = 0.25
			stun_max = stun
			react = "block"
			_kb = away * 1.4
		"thrown":
			my_pts += float(m.pts)
			stats.thrown += 1
			_cancel_move()
			_begin_wrestle(from, true)
	if log_results:
		print("[spar %d] my %s -> %s  (%.0f / %.0f)" % [my_sid(), mname, res, my_pts, their_pts])


func _cancel_move() -> void:
	move = ""
	phase = 0
	string_n = 0
	_buf = ""
	counter_t = 0.0
	counter_rec = 0.0


# ------------------------------------------------------------------ wrestling

func _begin_wrestle(with: Node3D, top: bool) -> void:
	wrestle = WRESTLE_T
	wrestle_top = top
	wrestle_with = with
	kicks = 0
	their_kicks = -1
	stun = 0.0
	react = "thrown"
	if player.get("dash"):
		player.dash.cancel()
	CatSfx.play_at("skid", player.global_position, 0.8, 1.2)


## mash swat while rolling about = bunny kicks
func kick_press() -> void:
	if wrestle > 0.0:
		kicks += 1


func _wrestle_over() -> void:
	if wrestle_top:
		_wr_wait = WRESTLE_WAIT
	else:
		_send(wrestle_with, ["kicks", kicks])
		_wr_wait = WRESTLE_WAIT + 1.0   # held still until the thrower says how it went


func _judge_wrestle() -> void:
	_wr_wait = 0.0
	if not wrestle_top:
		return   # timed out waiting: just get up
	var tk := maxi(their_kicks, 0)
	var res := "pin" if kicks + THROW_EDGE >= tk else "escape"
	_wrestle_result(wrestle_with, res)
	_send(wrestle_with, ["wr", res])


func _wrestle_result(_from: Node3D, res: String) -> void:
	_wr_wait = 0.0
	wrestle = 0.0
	react = ""
	if res == "pin":
		pinned = 1.1
		pin_top = wrestle_top
		if wrestle_top:
			my_pts += PIN_PTS
			stats.pins += 1
		else:
			their_pts += PIN_PTS
		CatSfx.play_at("land_soft", player.global_position, 0.9, 0.8)
	else:
		if wrestle_top:
			their_pts += ESCAPE_PTS
		else:
			my_pts += ESCAPE_PTS
			stats.escapes += 1
		var away := player.global_position - pos_of(wrestle_with) if is_instance_valid(wrestle_with) else Vector3.ZERO
		away.y = 0.0
		if away.length() > 0.01:
			_kb = away.normalized() * 1.6
		stun = 0.2
		stun_max = stun
		react = "block"


# ------------------------------------------------------------------ pairing + rounds

func _pairing(tgt: Node3D, dt: float) -> void:
	_ping -= dt
	if tgt != null:
		if opp != tgt and (opp == null or not is_instance_valid(opp) or not in_match()):
			opp = tgt
		if _ping <= 0.0:
			_ping = PAIR_PING
			_send(tgt, ["lock", true])
	elif is_instance_valid(opp) and _ping <= 0.0 and in_match():
		_ping = PAIR_PING
		_send(opp, ["lock", false])
	var mutual := tgt != null and tgt == opp and they_lock < PAIR_KEEP
	if not mutual and in_match():
		var gone := opp == null or not is_instance_valid(opp) or they_lock > PAIR_KEEP * 1.5 or (tgt == null and they_lock > 0.0 and not busy() and round_state == R_FIGHT and _unlock_t > 1.6)
		_unlock_t += dt
		if gone:
			_end_match("")
	else:
		_unlock_t = 0.0
	if mutual and round_state == R_OFF and is_ref():
		_new_match()

var _unlock_t := 0.0


## the lower id of the pair runs the rounds (dummies have negative ids, so offline the
## practice cat referees)
func is_ref() -> bool:
	var o := sid_of(opp)
	return o == 0 or my_sid() < o


func _new_match() -> void:
	my_wins = 0
	their_wins = 0
	round_n = 1
	stats.matches += 1
	_begin_round()


func _begin_round() -> void:
	my_pts = 0.0
	their_pts = 0.0
	round_state = R_INTRO
	round_t = 0.0
	_set_banner("round %d" % round_n)
	if is_ref():
		_send(opp, ["round", "intro", round_n, my_wins, their_wins])


func _round_tick(dt: float) -> void:
	round_t += dt
	if not is_ref() and round_state in [R_KO, R_DONE] and round_t > KO_T + DONE_T + 2.0:
		# the referee's next word got lost: carry on playing
		round_state = R_FIGHT
		my_pts = 0.0
		their_pts = 0.0
	match round_state:
		R_INTRO:
			if round_t > INTRO_T * 0.55 and banner != "play!":
				_set_banner("play!")
			if round_t >= INTRO_T:
				round_state = R_FIGHT
				round_t = 0.0
		R_FIGHT:
			if is_ref() and (my_pts >= METER or their_pts >= METER) and not busy_wrestling():
				var me_won := my_pts >= their_pts
				_ko(my_sid() if me_won else sid_of(opp))
				_send(opp, ["round", "ko", round_n, my_wins, their_wins, round_winner])
		R_KO:
			if round_t >= KO_T and is_ref():
				if my_wins >= ROUNDS_TO_WIN or their_wins >= ROUNDS_TO_WIN:
					round_state = R_DONE
					round_t = 0.0
					_set_banner("you win!" if my_wins > their_wins else "they win!")
					_send(opp, ["round", "done", round_n, my_wins, their_wins])
				else:
					round_n += 1
					_begin_round()
		R_DONE:
			if round_t >= DONE_T and is_ref():
				_send(opp, ["round", "again", round_n, my_wins, their_wins])
				_new_match()


func busy_wrestling() -> bool:
	return wrestle > 0.0 or _wr_wait > 0.0 or not _pending_throw.is_empty()


func _ko(winner: int) -> void:
	round_winner = winner
	round_state = R_KO
	round_t = 0.0
	stats.rounds += 1
	_cancel_move()
	if winner == my_sid():
		my_wins += 1
		_set_banner("you take round %d" % round_n)
	else:
		their_wins += 1
		_set_banner("round %d to them" % round_n)
	CatSfx.play_at("meow", player.global_position, 0.7, 1.15 if winner == my_sid() else 0.9)


## referee's word (from the other side, so its "my" is my "their")
func _on_round(from: Node3D, ev: Array) -> void:
	if my_sid() < sid_of(from):
		return   # I'm the referee of this pair: ignore stale ones
	opp = from
	var ph := str(ev[1])
	round_n = int(ev[2])
	their_wins = int(ev[3])
	my_wins = int(ev[4])
	match ph:
		"intro":
			my_pts = 0.0
			their_pts = 0.0
			round_state = R_INTRO
			round_t = 0.0
			_set_banner("round %d" % round_n)
		"ko":
			var w := int(ev[5])
			round_winner = w
			round_state = R_KO
			round_t = 0.0
			stats.rounds += 1
			_cancel_move()
			_set_banner("you take round %d" % round_n if w == my_sid() else "round %d to them" % round_n)
		"done":
			round_state = R_DONE
			round_t = 0.0
			_set_banner("you win!" if my_wins > their_wins else "they win!")
		"again":
			my_wins = 0
			their_wins = 0


func _end_match(why: String) -> void:
	round_state = R_OFF
	my_pts = 0.0
	their_pts = 0.0
	my_wins = 0
	their_wins = 0
	opp = null
	_set_banner(why)


func _set_banner(t: String) -> void:
	banner = t
	banner_t = 0.0


## lost the round and it's the flop: on its back for a moment
func flopped() -> bool:
	return round_state == R_KO and round_winner != my_sid() and round_t > 0.25


# ------------------------------------------------------------------ sending

func _send(to: Node3D, ev: Array) -> void:
	if to == null or not is_instance_valid(to):
		return
	var s := spar_of(to)
	if s != null:
		s._inbox.append([player, ev])
		return
	if to is RemoteCat:
		var rig = player.get("rig")
		if rig and rig.net_record and rig.life_log.size() < 64:
			rig.life_log.append(["S", sid_of(to)] + ev)


## a remote cat's life event arrived (RemoteCat calls this for ["S", ...] entries)
static func net_in(from: RemoteCat, ev: Array) -> void:
	if ev.size() < 3 or from == null:
		return
	for p in from.get_tree().get_nodes_in_group("player"):
		var s := spar_of(p)
		if s and not s.dummy and s.my_sid() == int(ev[1]):
			s.on_event(from, ev.slice(2))
			return


# ------------------------------------------------------------------ looks

## per tick, after the player has oriented its rig: fight poses + hit reactions on the real body
## (the rig transform and its dials go over the wire, so other players see all of it)
func orient(rig: Node3D) -> void:
	if rig == null or not (busy() or in_match() or guard or duck or react != ""):
		return
	var b: Basis = rig.global_transform.basis
	var o: Vector3 = rig.global_position
	var right := b.x
	var fwd := -b.z
	var tgt := opp if is_instance_valid(opp) else target()
	var tp: Vector3 = pos_of(tgt) if tgt else o + fwd * 0.6
	var rot := Basis()
	var off := Vector3.ZERO
	if guard:
		rig.crouch = maxf(rig.crouch, 0.35)
		rig.look_pitch = minf(rig.look_pitch, -0.15)
	if move != "":
		var m: Dictionary = MOVES[move]
		var u := mt / maxf(m.wind, 0.001)
		match move:
			"low":
				rig.crouch = maxf(rig.crouch, 0.85)
			"lunge":
				if phase == 0:
					rig.crouch = maxf(rig.crouch, 0.6 * (1.0 - u))
			"over":
				var w := clampf(u, 0.0, 1.0) if phase == 0 else 0.0
				rig.rear = maxf(rig.rear, 0.85 * w)
				if phase >= 1:
					rig.pin = 1.0
					rig.grip = maxf(rig.grip, 1.0 - clampf((mt - m.wind - m.active) / m.recover, 0.0, 1.0))
					rig.claw_target = o.lerp(tp, 0.6) + Vector3.UP * 0.02
			"bap":
				rig.rear = maxf(rig.rear, 0.3 * clampf(u, 0.0, 1.0) if phase == 0 else 0.0)
				if phase >= 1:
					rig.grip = maxf(rig.grip, 1.0 - clampf((mt - m.wind - m.active) / m.recover, 0.0, 1.0))
					rig.claw_target = o.lerp(tp, 0.62) + Vector3.UP * 0.1
			"throw":
				rig.grip = maxf(rig.grip, clampf(u, 0.0, 1.0))
				rig.claw_target = o.lerp(tp, 0.7) + Vector3.UP * 0.12
	if react != "" and stun_max > 0.0:
		var e := stun / stun_max
		var s := sin(PI * minf((1.0 - e) * 1.6, 1.0))
		match react:
			"high":
				rot = Basis(right, 0.32 * s)
				off = -fwd * 0.04 * s
			"low":
				off = Vector3.UP * 0.07 * s
				rot = Basis(right, -0.18 * s)
			"big":
				rot = Basis(right, 0.4 * s) * Basis(fwd, 0.2 * s)
				rig.crouch = maxf(rig.crouch, 0.7 * s)
			"block":
				rig.crouch = maxf(rig.crouch, 0.5 * s)
				off = -fwd * 0.03 * s
			"stumble":
				rot = Basis(Vector3.UP, 0.35 * sin(e * 14.0) * e) * Basis(fwd, 0.25 * s)
	if wrestle > 0.0 or _wr_wait > 0.0 or pinned > 0.0:
		# rolling about: on its side (the thrower the other way round), hind legs bunny kicking
		var side := 1.0 if wrestle_top else -1.0
		var k := clampf((WRESTLE_T - wrestle) * 5.0, 0.0, 1.0) if wrestle > 0.0 else 1.0
		var lie := 1.35 if not (pinned > 0.0 and pin_top) else 0.35
		rot = Basis(fwd, side * lie * k)
		off = Vector3.UP * 0.05 * k
		rig.scramble = maxf(rig.scramble, 1.0 if wrestle > 0.0 else 0.0)
		rig.grip = maxf(rig.grip, 0.6 * k)
		rig.claw_target = o.lerp(tp, 0.5) + Vector3.UP * 0.08
		if pinned > 0.0 and pin_top:
			rig.pin = 1.0
	if flopped():
		var k2 := clampf((round_t - 0.25) * 4.0, 0.0, 1.0)
		rot = Basis(fwd, 1.5 * k2)
		off = Vector3.UP * 0.05 * k2
	elif round_state == R_KO and round_winner == my_sid():
		rig.sit = maxf(rig.sit, clampf(round_t * 2.0, 0.0, 1.0))
	if rot != Basis() or off != Vector3.ZERO:
		rig.global_transform = Transform3D(rot * b, o + off)


func _strike_fx(tgt: Node3D) -> void:
	var p = player
	var fwd: Vector3 = -p.global_transform.basis.z
	var tp: Vector3 = pos_of(tgt) if tgt else p.global_position + fwd * 0.6
	var m: Dictionary = MOVES[move]
	var low := move == "low"
	var paw := (string_n + 1) % 2
	var aim: Vector3 = tp + Vector3.UP * (0.03 if low else 0.17)
	if not m.get("two", false) and move != "throw":
		if p.rig and p.rig.has_method("swat"):
			var sh: Vector3 = p.global_transform * Vector3((-0.04 if paw == 0 else 0.04), 0.17, -0.13)
			p.rig.swat(paw, sh + (aim - sh).limit_length(0.3 if not low else 0.34))
		if p.get("paws") and p.get("paw_anchor"):
			p.paws.swat(paw, p.paw_anchor.to_local(aim))
	if move == "throw":
		CatSfx.play_at("swish", p.global_position, 0.35, 0.8)
		return
	# one soft line, not the three claw scratch: these are harmless play swats
	var right: Vector3 = p.global_transform.basis.x * (-1.0 if paw == 0 else 1.0)
	var c: Vector3 = p.global_position + Vector3.UP * (0.08 if low else 0.2) + fwd * minf(0.5, p.global_position.distance_to(tp) * 0.75)
	var a := c - right * 0.15 + Vector3.UP * (0.02 if low else 0.06)
	var bb := c + right * 0.13 - Vector3.UP * (0.0 if low else 0.04)
	if m.get("two", false):
		a = c + Vector3.UP * 0.2 - fwd * 0.05
		bb = c - Vector3.UP * 0.06 + fwd * 0.08
	SlashFx.streak(p, a, bb, -fwd * 0.04 + Vector3.UP * 0.01, Color(0.85, 0.93, 1.0), p, 1)
	CatSfx.play_at("swish", p.global_position, 0.45, 1.25 if not m.get("two", false) else 1.0)


func _fx_hit(from: Vector3, low: bool, mine := false) -> void:
	var at: Vector3 = (pos_of(opp) if mine and is_instance_valid(opp) else player.global_position) + Vector3.UP * (0.05 if low else 0.16)
	var n := (from - at).normalized() if not mine else (player.global_position - at).normalized()
	SlashFx.sparks(player, at, n, false, 5)
	CatSfx.play_at("land_soft", at, 0.7, 1.7)


func _fx_block() -> void:
	SlashFx.sparks(player, player.global_position + Vector3.UP * 0.15, -player.global_transform.basis.z, false, 3)
	CatSfx.play_at("step_tap", player.global_position, 0.8, 1.3)


func _fx_counter(from: Vector3) -> void:
	SlashFx.sparks(player, player.global_position.lerp(from, 0.5) + Vector3.UP * 0.18, Vector3.UP, false, 8)
	CatSfx.play_at("swish", player.global_position, 0.7, 1.6)
