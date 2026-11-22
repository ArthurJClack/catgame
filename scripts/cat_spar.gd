class_name CatSpar
extends Node
## play fighting other cats, on the normal combat. press tab on a cat (another player's, or the
## practice tabby) and every attack you have turns into a no claws, no damage play version:
##
##   swat / rake      a soft bop: one rounded line instead of the three line claw scratch, a puff,
##                    the other cat flinches and gets nudged back. no damage, no stamina taken
##   pounce           land on them = bowled over (bigger nudge, a flop for a moment)
##   grab             a hug tackle: they're held for a moment
##   dodge            the normal dodge's iframes slip a bop
##   parry            the normal deflect (player.parry, when that's in) turns a bop back: the
##                    bopper stumbles out of its attack
##   getting tagged   interrupts your own attack (cat_combat.interrupt), same as getting bitten
##
## online: the cat that swings checks its normal hitbox against what it sees and sends a tag,
## the cat that got tagged decides (dodging? parrying?) and reacts, then answers so the swinger
## can stumble when it was deflected. it all rides the rig's life_log (["S", to_sid, kind, ...])
## so it gets the snapshot stream's repeats + de-dup. reactions go on the rig's transform, which
## goes over the wire, so everyone sees the flinch. the practice cat (CatSparBrain) talks to you
## through the same events, handed over directly.

const NUDGE := {"swat": 0.9, "rake": 0.5, "pounce": 2.0, "grab": 0.0}
const STUN := {"swat": 0.32, "rake": 0.2, "pounce": 0.9, "grab": 0.9}
const STUMBLE_T := 0.55
const TAG_R := 0.17           # a cat's body counts this far round its middle for the hitbox
const POUNCE_R := 0.42
const GRAB_R := 0.92

var player: Node3D            # CatPlayer (untyped: no cycle)
var dummy := false            # the practice cat (a bot CatPlayer with its own brain)
var brain: CatSparBrain = null
var forced: Node3D = null     # bots / the practice cat pick their playmate directly (no lock on)

var stun := 0.0
var stun_max := 0.0
var react := ""               # "swat" / "rake" / "pounce" / "grab" / "stumble" / "dodge"
var _kb := Vector3.ZERO
var _done: Array = []         # cats already tagged by the current strike
var _seq := 0
var _inbox: Array = []        # [from_node, ev] delivered by a local CatSpar
var stats := {"tags": 0, "got_tagged": 0, "dodged": 0, "deflected": 0, "deflects": 0, "pounces": 0, "grabs": 0}
var results: Array = []       # [kind, result] of my tags, newest last (tests)
var log_results := false
var parry_override: Object = null   # tests: stands in for player.parry

static var dummy_count := 0
var _dummy_sid := 0


func _ready() -> void:
	if dummy:
		dummy_count += 1
		_dummy_sid = -dummy_count
		player.add_to_group("spar_cat")
		if brain == null:
			brain = CatSparBrain.new()
	if brain:
		brain.spar = self


# ------------------------------------------------------------------ who / where

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
	var s := spar_of(n)
	return s.my_sid() if s else 0


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


## the cat you're playing with: the tab lock target when it's a cat
func playmate() -> Node3D:
	if is_instance_valid(forced) and forced.is_inside_tree():
		return forced
	var lt = player.get("lock_target")
	if lt is Node3D and is_instance_valid(lt) and (lt as Node).is_in_group("spar_cat") and lt != player:
		return lt
	return null


## locked on to a cat: every attack is the safe play version
func play_mode() -> bool:
	return playmate() != null


## a cat close enough that tab should lock on to it (outside the rat pit too)
func playmate_near(r := 9.0) -> bool:
	for n in player.get_tree().get_nodes_in_group("spar_cat"):
		if n != player and n is Node3D and pos_of(n).distance_to(player.global_position) < r:
			return true
	return false


# ------------------------------------------------------------------ per tick (from the player)

## start of CatPlayer._physics_process: practice cat thinks, events land, reactions run
func filter(inp: Dictionary, dt: float) -> Dictionary:
	if brain:
		inp = brain.think(dt)
	for m in _inbox:
		on_event(m[0], m[1])
	_inbox.clear()
	if stun > 0.0:
		stun = maxf(stun - dt, 0.0)
		if stun <= 0.0:
			react = ""
	if _kb != Vector3.ZERO:
		player.velocity += _kb
		_kb = Vector3.ZERO
	if stun > 0.0 and react in ["pounce", "grab", "stumble"]:
		# bowled over / held / stumbling: the feet are busy for a moment
		inp = inp.duplicate()
		inp.move = Vector2.ZERO
		for k in ["jump", "dash", "paw_l", "paw_r", "swat", "grab", "pounce"]:
			inp[k] = false
	return inp


## a new strike started (CatPlayer._do_swat): each cat can be tagged once per strike
func strike_start() -> void:
	_done.clear()


## the normal swat hitbox is out (impact + the live sweep after it). rake = the held paw version
func swat_check(rake: bool) -> bool:
	var c := playmate()
	if c == null or _done.has(c):
		return false
	var q := pos_of(c) + Vector3.UP * 0.12
	if player._swat_box_d(q) > player.SWAT_HIT_R + TAG_R:
		return false
	_done.append(c)
	_tag(c, "rake" if rake else "swat")
	return true


## the pounce came down (CatPlayer._on_land)
func pounce_land() -> void:
	var c := playmate()
	if c == null:
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	var pin_pt: Vector3 = player.global_position + fwd * 0.16
	if pos_of(c).distance_to(pin_pt) < POUNCE_R:
		stats.pounces += 1
		_tag(c, "pounce")


## the grab's reach ended with nothing grabbable in it (cat_combat): a cat in reach = hug tackle
func grab_reach() -> bool:
	var c := playmate()
	if c == null or pos_of(c).distance_to(player.global_position) > GRAB_R:
		return false
	stats.grabs += 1
	_tag(c, "grab")
	return true


func _tag(c: Node3D, kind: String) -> void:
	_seq += 1
	stats.tags += 1
	_send(c, ["tag", _seq, kind])


# ------------------------------------------------------------------ events

func on_event(from: Node3D, ev: Array) -> void:
	if ev.is_empty() or from == null or not is_instance_valid(from):
		return
	match str(ev[0]):
		"tag":
			_tagged(from, int(ev[1]), str(ev[2]))
		"res":
			_on_result(from, str(ev[2]), str(ev[3]))


## another cat tagged me: dodge / deflect / take it (no damage, ever)
func _tagged(from: Node3D, seq: int, kind: String) -> void:
	var res := "hit"
	var parry = parry_override if parry_override else player.get("parry")
	if player.has_method("is_invulnerable") and player.is_invulnerable():
		res = "dodged"
		stats.dodged += 1
	elif kind != "pounce" and parry != null and parry.has_method("try_deflect") and parry.try_deflect(from, pos_of(from), false):
		res = "deflected"
		stats.deflects += 1
	else:
		stats.got_tagged += 1
		_react(kind, pos_of(from))
	_send(from, ["res", seq, kind, res])


func _on_result(from: Node3D, kind: String, res: String) -> void:
	results.append([kind, res])
	if results.size() > 32:
		results.pop_front()
	if log_results:
		print("[spar %d] my %s -> %s" % [my_sid(), kind, res])
	match res:
		"hit":
			_puff(pos_of(from) + Vector3.UP * (0.06 if kind == "pounce" else 0.13))
		"deflected":
			stats.deflected += 1
			_react("stumble", pos_of(from))


func _react(kind: String, from: Vector3) -> void:
	var away: Vector3 = player.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else player.global_transform.basis.z
	react = kind
	stun = STUN.get(kind, STUMBLE_T)
	stun_max = stun
	_kb = away * float(NUDGE.get(kind, 0.8))
	var combat = player.get("combat")
	if combat and combat.has_method("interrupt"):
		combat.interrupt()   # tagged mid wind up: knocked out of it, like any hit
	if kind in ["pounce", "grab", "stumble"] and player.get("dash"):
		player.dash.cancel()
	match kind:
		"swat", "rake":
			_puff(player.global_position + Vector3.UP * 0.14)
		"pounce":
			_puff(player.global_position + Vector3.UP * 0.06)
			CatSfx.play_at("land_soft", player.global_position, 0.9, 0.85)
		"grab":
			CatSfx.play_at("skid", player.global_position, 0.6, 1.3)


func _puff(at: Vector3) -> void:
	SlashFx.sparks(player, at, Vector3.UP, false, 4)
	CatSfx.play_at("land_soft", at, 0.6, 1.7)


func _send(to: Node3D, ev: Array) -> void:
	if to == null or not is_instance_valid(to):
		return
	var s := spar_of(to)
	if s != null:
		s._inbox.append([player, ev])
		return
	if to.has_method("play_tag"):
		# a farm cat (NpcCat): it takes the bop, scampers off, and the answer comes straight back.
		# online the cat's owner runs it (NetWorld.forward), everyone sees it through world sync
		if str(ev[0]) == "tag":
			var kind := str(ev[2])
			if not NetWorld.forward(to, "play_tag", [kind, player.global_position]):
				to.play_tag(kind, player.global_position)
			_inbox.append([to, ["res", ev[1], kind, "hit"]])
		elif str(ev[0]) == "res" and to.has_method("play_result"):
			to.play_result(str(ev[3]))
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

## after the player has oriented its rig: the flinch / bowled over / stumble on the real body
## (the rig transform goes over the wire, so other players see it)
func orient(rig: Node3D) -> void:
	if rig == null or react == "" or stun_max <= 0.0:
		return
	var b: Basis = rig.global_transform.basis
	var o: Vector3 = rig.global_position
	var right := b.x
	var fwd := -b.z
	var e := stun / stun_max
	var s := sin(PI * minf((1.0 - e) * 1.6, 1.0))
	var rot := Basis()
	var off := Vector3.ZERO
	match react:
		"swat", "rake":
			rot = Basis(right, (0.3 if react == "swat" else 0.15) * s)
			off = -fwd * 0.04 * s
		"pounce":
			# bowled onto its side for a moment, then back up
			var k := clampf(minf((1.0 - e) * 6.0, e * 3.0), 0.0, 1.0)
			rot = Basis(fwd, 1.35 * k)
			off = Vector3.UP * 0.05 * k
		"grab":
			rig.crouch = maxf(rig.crouch, 0.6 * s)
			rot = Basis(fwd, 0.25 * sin(e * 18.0) * s)
		"stumble":
			rot = Basis(Vector3.UP, 0.35 * sin(e * 14.0) * e) * Basis(fwd, 0.25 * s)
	rig.global_transform = Transform3D(rot * b, o + off)
