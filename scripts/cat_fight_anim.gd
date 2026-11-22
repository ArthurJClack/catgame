class_name CatFightAnim
extends RefCounted
## how a cat looks when it fights (rig.fight_anim). all of it is animation: nothing in here
## changes a hitbox, a timing or a rule, so the combat code is untouched by it.
##
##   swat styles: every strike is still 0.32 s with the paw landing at ~0.12-0.15 s, but it isn't
##     one canned swing any more. a string of strikes runs through a combo (hook, backhand, double
##     bop jab, overhead chop, low scoop, long rake), low targets get chopped down on, and in a
##     real fight every few chained strikes the cat rears up on its hind legs and bats down
##     from above (rear_add). the owner picks the style and it goes out with the swat event, so
##     online copies throw the very same strike
##   threat pose ("halloween cat"): standing its ground in a fight the cat turns side on (side_yaw),
##     humps its back up high (arch), goes up on straight legs (lift) and puts its tail up in a
##     hooked bottle brush. the head stays on the threat
##   fight crouch: crouched in a fight it gets low and tight, tail thrashing along the ground,
##     with bursts of bum wiggle
##   bristle: piloerection. the hackles along the spine stand up (soma builds the fur shards) and
##     the tail puffs out, from the fight level + a scare. it goes down slowly, like real fur
##   ear_pin: ears pinned flat back on the head when it means it (attacking, hissing, arched,
##     crouched to spring). the rest of the fight they swivel and flick at the threat
##
## the owner sets rig.fight (0..1: is there a fight on, synced as a dial). everything here is
## worked out from that and from the rig's own synced inputs, so remote copies match.

## false = the old look (fight lab --legacy, for before / after): one swat, no fight body language
static var on := true

var rig: CatRig

# ---- outputs, read by the rig (pre) and soma (post)
var threat := 0.0      # side on arched threat pose weight
var lowc := 0.0        # fight crouch weight
var arch := 0.0        # rad: chest pitches down / hips up by this much (a humped back)
var lift := 0.0        # m: body up on straight legs
var side_yaw := 0.0    # rad: body turned side on to the threat (the head stays on it)
var rear_add := 0.0    # rearing up to bat down from above
var wiggle := 0.0      # bum wiggle weight
var bristle := 0.0     # 0..1 fur standing up
var ear_pin := 0.0     # 0..1 ears pinned flat back
var swivel := 0.0      # 0..1 ears working (quick turns / flicks at the threat)

# ---- swats
const STYLES := ["hook", "back", "jab", "chop", "scoop", "rake", "bat"]
const COMBO_GAP := 0.75   # a strike within this of the last one carries the combo on
const BAT_T := 0.62       # how long one rear up lasts (each chained bat extends it)
var style := "hook"
var combo := 0
var styles_thrown := {}   # tests: style -> count
var _last_swat := -9.0
var _last_style := ""
var _bat_t := -1.0
var _bat_n := 0
var _bag: Array = []           # bats in this rear up
var _side := 1.0
var _was_threat := false
var _rng := RandomNumberGenerator.new()


func setup(r: CatRig) -> void:
	rig = r
	_rng.randomize()


## the owner's pick for the next strike. target_local = where it hits, in rig space.
## rake = one of a held paw's repeated rakes
func pick(target_local: Vector3, rake: bool) -> String:
	var now: float = rig._t
	combo = combo + 1 if now - _last_swat < COMBO_GAP else 0
	_last_swat = now
	var f: float = rig.fight
	var s := "hook"
	if not on:
		return s
	if rake:
		s = "rake"
	elif f > 0.3 and combo % 4 == 3 and rig.on_floor and rig.climb < 0.1:
		s = "bat"      # every fourth chained strike in a real fight: up on the hind legs
	elif _bat_t >= 0.0 and _bat_t < BAT_T - 0.12 and _bat_n < 2:
		s = "bat"      # still up there: one more bat down, then back on all fours
	elif target_local.y < 0.045 and combo == 0:
		s = "chop"     # something on the ground: slam down on it
	elif combo == 0:
		s = "hook" if _rng.randf() < 0.6 else "jab"
	else:
		# a combo: deals from a shuffled bag, so every kind of strike comes up before any repeats
		if _bag.is_empty():
			_bag = ["hook", "back", "jab", "chop", "scoop"]
			_bag.shuffle()
			if _bag[0] == _last_style:
				_bag.push_back(_bag.pop_front())
		s = _bag.pop_front()
		if s == "scoop" and target_local.y < 0.045:
			s = "chop"     # (can't come up from under something lying on the ground)
	return s


## the rig starts a strike of this style (owner or replayed from the net)
func begin(s: String) -> void:
	style = s if s in STYLES else "hook"
	_last_style = style
	styles_thrown[style] = int(styles_thrown.get(style, 0)) + 1
	if style == "bat":
		if _bat_t < 0.0:
			_bat_t = 0.0
			_bat_n = 1
		else:
			_bat_t = minf(_bat_t, 0.14)
			_bat_n += 1


# ------------------------------------------------------------------ before the body is solved

func pre(dt: float) -> void:
	if not on:
		return
	var r := rig
	var f: float = r.fight
	var swatting: bool = r.is_swatting()
	var grounded: bool = r.on_floor and r.climb < 0.1 and r.clamber < 0.1 and r.carried < 0.05 and r.slide < 0.1
	# rear up batting
	if _bat_t >= 0.0:
		_bat_t += dt
		if _bat_t > BAT_T or not grounded:
			_bat_t = -1.0
	var bw := 0.0
	if _bat_t >= 0.0:
		bw = smoothstep(0.0, 0.12, _bat_t) * (1.0 - smoothstep(BAT_T - 0.2, BAT_T, _bat_t))
	rear_add = 0.42 * bw
	# standing its ground: side on, back up, tail up
	var still: bool = r.speed_s < 0.45 and not swatting and _bat_t < 0.0
	var free_body: bool = r.crouch < 0.25 and r.charge < 0.05 and r.sit < 0.3 and r.loaf < 0.3 and r.grip < 0.1 and r.dodge < 0.1 and r.scratch < 0.1 and r.pin < 0.1
	var want_t := smoothstep(0.25, 0.7, f) if (grounded and still and free_body) else 0.0
	threat = LowPoly.damp(threat, want_t, 4.5 if want_t > threat else 7.0, dt)
	if threat > 0.02 and not _was_threat:
		# turn the side that's already nearer (the body is a little turned already)
		_side = 1.0 if float(r._tyaw) >= 0.0 else -1.0
	_was_threat = threat > 0.02
	arch = 0.5 * threat
	lift = 0.028 * threat
	side_yaw = _side * 0.78 * threat
	# crouched in a fight: low, tight, tail thrashing, bum wiggling in bursts
	var want_l := smoothstep(0.2, 0.6, f) * smoothstep(0.25, 0.6, maxf(r.crouch, r.charge)) * (1.0 if grounded else 0.0)
	lowc = LowPoly.damp(lowc, want_l, 6.0, dt)
	var burst := smoothstep(0.35, 0.75, sin(float(r._t) * 2.7) * 0.5 + 0.5)
	wiggle = lowc * burst * (1.0 - r.charge)   # (the pounce wind up has its own wiggle)
	# fur: up fast, down slow
	var scare: float = r.soma._puff
	var want_b := maxf(smoothstep(0.15, 0.6, f) * (0.55 + 0.45 * maxf(threat, lowc)), scare)
	if swatting and f > 0.2:
		want_b = maxf(want_b, 0.85)
	bristle = LowPoly.damp(bristle, clampf(want_b, 0.0, 1.0), 5.0 if want_b > bristle else 0.7, dt)
	# ears
	var hiss: float = r.soma.hiss_w()
	var want_e := maxf(maxf(threat * 0.75, lowc), hiss)
	if f > 0.2 and (swatting or _bat_t >= 0.0):
		want_e = 1.0
	ear_pin = LowPoly.damp(ear_pin, want_e, 14.0 if want_e > ear_pin else 4.0, dt)
	swivel = smoothstep(0.1, 0.5, f) * (1.0 - ear_pin)


# ------------------------------------------------------------------ the strike

static func _ease(u: float, k: int) -> float:
	u = clampf(u, 0.0, 1.0)
	match k:
		1: return u * u               # accelerating into the hit
		2: return u * (2.0 - u)       # decelerating out to a wind up
	return smoothstep(0.0, 1.0, u)


## keys: [[t, pos, rot, ease], ...] starting at t 0. returns [pos, rot] at time t
static func _keys(t: float, keys: Array) -> Array:
	for k in range(1, keys.size()):
		var b: Array = keys[k]
		if t <= float(b[0]) or k == keys.size() - 1:
			var a: Array = keys[k - 1]
			var u := _ease((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), int(b[3]))
			return [(a[1] as Vector3).lerp(b[1], u), lerpf(float(a[2]), float(b[2]), u)]
	return [keys[0][1], keys[0][2]]


## where the swatting fore paw is (rig space) at strike time t (0..0.32) and its wrist roll.
## foot / prot = where the paw would be without the strike, home = its rest spot, strike = the
## point it hits (rig space), h = body height. "hook" is the original swat, untouched
func pose(t: float, side: float, foot: Vector3, prot: float, home: Vector3, strike: Vector3, h: float) -> Array:
	match style:
		"back":
			# backhand: cocked in across the chest, flung out through the target to its own side
			return _keys(t, [
				[0.0, foot, prot, 0],
				[0.07, Vector3(-side * 0.025, h * 0.5, home.z - 0.04), 0.5, 2],
				[0.14, strike, -0.5, 1],
				[0.22, strike + Vector3(side * 0.07, 0.02, 0.03), -0.85, 2],
				[0.32, foot, prot, 0]])
		"jab":
			# double bop: short straight taps, tap tap
			var bop := strike + Vector3(0, 0.025, 0.05)
			return _keys(t, [
				[0.0, foot, prot, 0],
				[0.06, Vector3(side * 0.035, h * 0.45, home.z + 0.015), -0.4, 2],
				[0.12, strike + Vector3(0, 0.004, -0.012), 0.3, 1],
				[0.16, strike, 0.2, 0],
				[0.205, bop, -0.25, 2],
				[0.25, strike, 0.3, 1],
				[0.32, foot, prot, 0]])
		"chop":
			# overhead: up high, then slammed straight down and held there, claws in
			return _keys(t, [
				[0.0, foot, prot, 0],
				[0.08, Vector3(side * 0.05, h * 1.0, home.z - 0.02), -1.2, 2],
				[0.14, strike + Vector3(0, -0.02, 0), 0.6, 1],
				[0.23, strike + Vector3(0, -0.028, 0.012), 0.75, 0],
				[0.32, foot, prot, 0]])
		"scoop":
			# low uppercut: down by the ground, then hooked up through the target
			return _keys(t, [
				[0.0, foot, prot, 0],
				[0.07, Vector3(side * 0.06, 0.015, strike.z + 0.05), 0.9, 2],
				[0.15, strike + Vector3(0, 0.045, -0.015), -0.6, 1],
				[0.23, strike + Vector3(side * 0.02, 0.075, 0.03), -0.95, 2],
				[0.32, foot, prot, 0]])
		"rake":
			# a long claw drag down and back
			return _keys(t, [
				[0.0, foot, prot, 0],
				[0.07, Vector3(side * 0.04, h * 0.85, home.z - 0.06), -1.0, 2],
				[0.13, strike + Vector3(0, 0.02, 0), 0.5, 1],
				[0.26, strike + Vector3(-side * 0.012, -0.07, 0.1), 1.0, 0],
				[0.32, foot, prot, 0]])
		"bat":
			# reared up: bats down from above, bounces off, back up to hover for the next one
			return _keys(t, [
				[0.0, foot, prot, 0],
				[0.09, Vector3(side * 0.06, h * 1.35, home.z - 0.05), -1.3, 2],
				[0.15, strike, 0.6, 1],
				[0.22, strike + Vector3(0, 0.035, 0.02), 0.2, 2],
				[0.32, foot, prot, 0]])
	# hook (the original swat): wind out to the side, whip across, claws drag down + back, recover
	var wind := Vector3(side * 0.105, h * 0.62, home.z - 0.07)
	if t < 0.07:
		var u := t / 0.07
		return [foot.lerp(wind, u * (2.0 - u)), lerpf(prot, -0.9, u)]
	elif t < 0.15:
		var u := (t - 0.07) / 0.08
		return [wind.lerp(strike, u * u), lerpf(-0.9, 0.55, u)]
	elif t < 0.24:
		var u := smoothstep(0.0, 1.0, (t - 0.15) / 0.09)
		return [strike.lerp(strike + Vector3(-side * 0.015, -0.05, 0.075), u), lerpf(0.55, 0.95, u)]
	var rk := strike + Vector3(-side * 0.015, -0.05, 0.075)
	var u2 := smoothstep(0.0, 1.0, (t - 0.24) / 0.08)
	var p := rk.lerp(foot, u2)
	p.y += sin(PI * u2) * 0.015
	return [p, lerpf(0.95, prot, u2)]


# ------------------------------------------------------------------ the owner's fight level

const FIGHT_R := 3.2   # an enemy this close is a fight

## how much of a fight the player is in (0..1), eased from cur. a locked on enemy, an enemy
## close by, or just having been hurt
static func level(p: Node, cur: float, dt: float) -> float:
	var want := 0.0
	var lt = p.get("lock_target")
	if lt is Node and is_instance_valid(lt) and (lt as Node).is_in_group("enemy") and _alive(lt):
		want = 1.0
	if want < 1.0 and p is Node3D and p.is_inside_tree():
		var me: Vector3 = (p as Node3D).global_position
		for n in p.get_tree().get_nodes_in_group("enemy"):
			if n is Node3D and _alive(n):
				var d: float = me.distance_to((n as Node3D).global_position)
				want = maxf(want, 1.0 - smoothstep(FIGHT_R * 0.6, FIGHT_R, d))
	# a cat vs cat play fight (cat_spar.gd, duck typed): fur up and ears back, a bit less than a real one
	var sp = p.get("spar")
	if sp is Object and is_instance_valid(sp) and (sp as Object).has_method("in_match") and sp.in_match():
		want = maxf(want, 0.75)
	var h = p.get("health")
	if h != null and is_instance_valid(h) and float(h.get("flash")) > 0.05:
		want = maxf(want, 0.8)
	return LowPoly.damp(cur, want, 3.0 if want > cur else 0.5, dt)


static func _alive(n: Node) -> bool:
	if "hp" in n and float(n.get("hp")) <= 0.0:
		return false
	if n.get("caught") == true:
		return false
	return true
