class_name CatParry
extends Node
## deflect / parry, sekiro style. the dodge key + swat together:
##
##   press dodge (alt / mouse4 / pad B) and swat within CHORD  -> DEFLECT
##   swat while the dodge key is still held                     -> DEFLECT again (combo hits)
##   dodge alone                                                -> the normal dodge (cat_dash.gd)
##
## no new keys (controls diet). the dodge's gather holds on for the CHORD window so a quick
## alt + click never leaves the ground; if it turns into a deflect the dodge is called off and its
## stamina is handed back. while the dodge key is held the swat button deflects instead of swatting.
##
## a deflect opens a tight WINDOW. a hit that lands inside it (in front of the cat, not a perilous
## one) is batted away: no damage, sparks + a clack, and the attacker takes posture
## (SoulsRat.add_posture). the first PERFECT s of the window is a perfect deflect (more posture,
## brighter sparks). mashing shrinks the window (SPAM_T), so it pays to time it to the glint
## (parry_cue.gd: the ring closes on the star at the moment the hit lands).
##
## perilous hits (red ! cue) can't be deflected: dodge them (i-frames) or get out of the way.
##
## api for anything that hits the cat (rats, cat_spar.gd play fights):
##   parry.active() -> bool
##   parry.try_deflect(attacker, from, perilous := false) -> bool   call at impact, before damage
##   signal deflected(attacker, from, perfect)

signal deflected(attacker: Node3D, from: Vector3, perfect: bool)

const CHORD := 0.09           # dodge pressed, swat within this = deflect (the dodge waits this long)
const WINDOW := 0.16          # deflect window from the press
const PERFECT := 0.07         # first part of it = perfect deflect
const MIN_WINDOW := 0.06      # mashing shrinks it down to this
const SPAM_T := 0.42          # a press sooner than this after the last one shrinks the window
const SPAM_MUL := 0.6
const REPRESS := 0.09         # combo hits come ~0.25-0.3 s apart: you can deflect again this soon
const STAMINA := 4.0          # a deflect costs a little (blocked hits cost nothing else)
const ARC := 1.9              # rad: the hit has to come from within this of where the cat faces
const POSTURE := 1.0          # posture an ordinary deflect deals
const POSTURE_PERFECT := 1.5

var player: Node3D            # CatPlayer
var window := 0.0             # s left in the current deflect window
var cur_window := WINDOW
var since := 9.0              # since the last deflect press
var chord := -1.0             # time since the dodge press while the chord window is open (-1 = shut)
var eat_swat := false         # the swat button belongs to the deflect right now, not the paws
var pose_t := 9.0             # since the last deflect press (rig / paw pose)
var pose_paw := 0
var presses := 0              # tests
var deflects := 0
var perfects := 0
var last_perfect := false
var _dash_prev := false
var _swat_prev := false
var _defl_prev := false


func active() -> bool:
	return window > 0.0


func chord_open() -> bool:
	return chord >= 0.0 and chord <= CHORD


## once per physics tick, before the dodge + paws read their buttons.
## dash_in / swat_in: the raw buttons. defl_in: a bot's direct "deflect" button.
## returns true when the dodge press should go to the dodge (cat_dash.press)
func input(dt: float, dash_in: bool, swat_in: bool, defl_in: bool) -> bool:
	window = maxf(window - dt, 0.0)
	since += dt
	pose_t += dt
	var dash_rise := dash_in and not _dash_prev
	var swat_rise := swat_in and not _swat_prev
	var defl_rise := defl_in and not _defl_prev
	_dash_prev = dash_in
	_swat_prev = swat_in
	_defl_prev = defl_in
	if dash_rise:
		chord = 0.0
	elif chord >= 0.0:
		chord += dt
		if chord > CHORD:
			chord = -1.0
	# a swat press that became a deflect belongs to it until the button comes back up (so the
	# paws don't swat on the same click). a paw already held before the dodge key stays a paw
	if swat_rise and (dash_in or chord_open()):
		eat_swat = true
		_press()
	elif defl_rise:
		_press()
	if not swat_in:
		eat_swat = false
	return dash_rise


func _press() -> void:
	var p = player
	if since < REPRESS:
		return
	if p.climber.active() or p.combat.gripping() or p.health.dead:
		return
	if p.combat.committed() and not p.combat.can_dodge():
		return
	# the dodge it was about to be turns into the deflect: called off, stamina back
	p.dash.abort_for_parry()
	chord = -1.0
	cur_window = maxf(cur_window * SPAM_MUL, MIN_WINDOW) if since < SPAM_T else WINDOW
	window = cur_window
	since = 0.0
	pose_t = 0.0
	pose_paw = 1 - pose_paw
	presses += 1
	# the paw comes up and out to meet it (seen in fp + third person)
	var side := -1.0 if pose_paw == 0 else 1.0
	var pt: Vector3 = p.global_transform * Vector3(side * 0.05, 0.2, -0.3)
	if p.rig.has_method("swat"):
		p.rig.swat(pose_paw, pt)
	p.paws.swat(pose_paw, p.paw_anchor.to_local(pt))
	p._event("deflect")


## a hit is landing on the cat right now. true = it was deflected (no damage)
func try_deflect(attacker: Node3D, from: Vector3, perilous := false) -> bool:
	if window <= 0.0 or perilous:
		return false
	var p = player
	var to: Vector3 = from - p.global_position
	to.y = 0.0
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	if to.length() > 0.01 and absf(fwd.signed_angle_to(to, Vector3.UP)) > ARC * 0.5:
		return false
	var perfect := since <= PERFECT
	last_perfect = perfect
	deflects += 1
	if perfect:
		perfects += 1
	p.stamina.spend(STAMINA * (0.5 if perfect else 1.0))
	# a deflect closes the window: the next hit of the combo needs its own press
	window = 0.0
	cur_window = WINDOW
	# feel: both sides rock back a touch, the camera jolts, sparks between paw and teeth
	var away: Vector3 = -to.normalized() if to.length() > 0.01 else -fwd
	p.velocity += away * (0.5 if perfect else 0.8)
	p.land_dip_v -= 0.15
	p.cam_roll += (0.03 if pose_paw == 1 else -0.03)
	var mid: Vector3 = p.global_position.lerp(from, 0.5) + Vector3.UP * 0.14
	SlashFx.sparks(p, mid, (away + Vector3.UP * 0.4).normalized(), false, 26 if perfect else 14)
	CatSfx.play_at("deflect", mid, 1.0 if perfect else 0.8, randf_range(1.05, 1.15) if perfect else randf_range(0.9, 1.0))
	p._event("perfect deflect!" if perfect else "deflected")
	deflected.emit(attacker, from, perfect)
	return true


## posture this deflect deals to the attacker
func posture_dealt() -> float:
	return POSTURE_PERFECT if last_perfect else POSTURE
