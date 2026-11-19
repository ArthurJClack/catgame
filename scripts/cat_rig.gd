class_name CatRig
extends Node3D
## procedural low poly cat with an ik driven gait system.
## the rig root sits on the ground between the feet and faces -Z.
## whoever owns the rig (player, npc, preview) just feeds it a velocity +
## a few state values every frame, and the rig figures out the rest:
## gait selection (walk/trot/gallop), planted feet, spine flex, air poses,
## crouch/stalk, sit, butt wiggle before a pounce, tail physics, blinking.
##
## real domestic cat proportions (meters): body ~0.46 long, shoulder ~0.25,
## tail ~0.29, legs ~0.2

# ---------------- look ----------------
var fur := Color(0.86, 0.52, 0.24)
var fur_dark := Color(0.58, 0.30, 0.12)
var belly := Color(0.96, 0.90, 0.80)
var eye_color := Color(0.62, 0.86, 0.22)
var nose_color := Color(0.88, 0.50, 0.55)
var pad_color := Color(0.93, 0.55, 0.6)      # toe beans (first person paws read this)
var whisker_color := Color(0.95, 0.95, 0.92)
var coat_flat := false   # solid coat with no lighter muzzle / underside (the black cat)
var pattern := "tabby" # "tabby", "solid", "tux"
var socks := false

# ---------------- driver inputs ----------------
var drive_velocity := Vector3.ZERO # world space
var on_floor := true
var crouch := 0.0   # 0..1 stalking low
var sit := 0.0      # 0..1
var charge := 0.0   # 0..1 winding up a pounce
var scramble := 0.0 # 0..1 front paws clawing up a wall
var look_yaw := 0.0
var look_pitch := 0.0
## 0..1 looking down at its own paws: the neck curls, the chin pulls back toward the chest
## and the head drops over the forelegs (the first person head camera rides along)
var head_tuck := 0.0
# behaviours + parkour (all 0..1 blends set by the owner)
var rear := 0.0          # up on the hind legs (scratching, peeking)
var kick_paws := [Vector3.ZERO, Vector3.ZERO] # wall kick: where the hind paws press on the wall (world)
var kick_paw_w := 0.0    # 0..1 hind paws held there (legs extend as the body leaves the wall)
var kick_w := 0.0        # 0..1 in the wall kick pose (tail tucked down the spine line, off the wall)
var scratch := 0.0       # raking claws down a vertical surface in front
var scratch_dist := 0.16 # distance from the rig root (-z) to the scratched surface
var climb := 0.0         # claws in, going up a vertical surface. owner rotates the rig onto the wall
var clamber := 0.0       # hanging off a ledge by the forepaws
var clamber_pull := 0.0  # 0..1 progress of hauling up over it
var ledge_world := Vector3.ZERO # top of the ledge edge (world)
var stretch := 0.0       # big front stretch, butt up
var groom := 0.0         # sitting, licking a paw + face wipes
var loaf := 0.0          # legs tucked under, eyes half shut
var pin := 0.0           # forepaws slammed down together (pounce landing), decays by itself
var claws_out := 0.0     # read only
var slip_claws := 0.0    # 0..1 paws slipping on the floor: claws come out, paws stay down

# ---------------- state (readable by others) ----------------
var phase := 0.0
var speed_s := 0.0
var gait_w := Vector3(1, 0, 0) # walk, trot, gallop
var freq := 1.0

var _dir := Vector3(0, 0, -1)
var _air_w := 0.0
var _air_timer := 0.0
var _vy := 0.0
var _vy_prev := 0.0
var _yaw_prev := 0.0
var _yaw_rate := 0.0
var _t := 0.0
var _blink_t := 2.0
var _land := 0.0
var _land_v := 0.0
var _prev_floor := true
var _tail_lag := 0.0
var _tail_lag_v := 0.0
var _tail_p := PackedFloat32Array([0.9, -0.06, 0.12, 1.2, 0.0])
var _built := false
var _land_f := 0.0
var _land_fv := 0.0
var _acc := Vector3.ZERO
var _vel_prev := Vector3.ZERO
var _tp := PackedFloat32Array()
var _tpv := PackedFloat32Array()
var _ty := PackedFloat32Array()
var _tyv := PackedFloat32Array()
var _twitch_t := 1.5
var _groom_t := 0.0
var _gw := [1.0, 0.0, 0.0, 0.0]
var pelvis_z := 0.095
var leg_claws: Array[Node3D] = []
var _ear_t := 3.0
var _ear_flick := [0.0, 0.0]

# ---------------- footfall solver (see cat_gait.gd) ----------------
## paws are planted in the world and the body is solved from them. turn this off
## to get the cheap phase driven legs back (far away npc cats)
var use_planting := true
var gait := CatGait.new()
## front paw offsets from their rest spots (rig space) + lift, for the first person paws
var fp_foot := [Vector3.ZERO, Vector3.ZERO]
var fp_down := [true, true]
var yaw_off := 0.0 # body yaw behind the root (the spine follows the head into a turn)
var _byaw := 0.0
var _byaw_init := false
var _chest_dy := 0.0
var _pelvis_dy := 0.0
var _fgy := 0.0
var _hgy := 0.0
# rough ground: last root height (girdle heights are damped in world space, so the body doesn't
# hop when the capsule rides over a bump) and how far each girdle tilts with the ground across it
var _root_y_prev := NAN
var _groll := [0.0, 0.0]
var _prev_floor_g := false
var _cx := 0.0
var _chest_f := Vector3.ZERO
var _chest_f_init := false
var _prot_s := [0.0, 0.0, 0.0, 0.0]
var _heel_s := [0.0, 0.0, 0.0, 0.0]
var _scap := [0.0, 0.0]
var _roll_c := 0.0
var _roll_p := 0.0
var _yaw_c := 0.0
var _yaw_p := 0.0
var _tyaw := 0.0
var _air_vy_max := 0.0
var _hop_w := 0.0
## claw hold: fore paw claw_i (0 left, 1 right) reaches out and stays hooked on claw_target (world)
var claw_on := false
var claw_i := 1
var claw_target := Vector3.ZERO
var _claw_w := [0.0, 0.0]
## two paw grip (both mouse buttons): both fore paws clamp down on claw_target (world) and hold.
## grip_squeeze() pulses them (claws dig in) on every bite / squeeze
var grip := 0.0
var _squeeze_t := -1.0
var _swat_t := -1.0
var _swat_i := 1
var _swat_target := Vector3.ZERO
var _gait_setup := false

# ---------------- spine, weight, head, jumps, life ----------------
## owner options
var gravity := 9.8        # what the owner integrates falls with (for the landing prediction)
var balance := 0.0        # 0..1 on something narrow: paws in line, tail out as a balance pole (also auto detected)
var idle_life := true     # weight shifts, glances and ear swivels when standing around
var auto_listen := true   # ears turn to prey moving nearby by themselves (see hear())
## readable
var land_known := false   # airborne and the arc meets ground soon
var land_point := Vector3.ZERO
var land_t := 0.0         # seconds until it does
var head_bob := 0.0       # what is left of the head's vertical bob after the neck took its share (m)
var _flex_s := 0.0
var _iner := Vector3.ZERO     # body offset thrown by its own momentum (rig space)
var _iner_v := Vector3.ZERO
var _ipitch := 0.0
var _ipitch_v := 0.0
var _head_f := Vector3.ZERO
var _head_f_init := false
var _head_slow := 0.0
var _neck_rest := Vector3.ZERO
var _sit_s := 0.0
var _loaf_s := 0.0
var _sit_h := 0.0
var _abs_fv := 0.0
var _abs_hv := 0.0
var _abs_delay := -1.0
var _abs_imp := 0.0
var _launch := 0.0
var _tum_c := 0.0
var _tum_p := 0.0
var _climb_prev := 0.0
# climbing (see _climb_paws): splayed, clawed in, and hanging off the grips under gravity.
# each paw holds a world spot on the wall (_cg) until its turn to reach for a new one
const CL_OFFS := [0.62, 0.70, 0.20, 0.24]   # LF RF LH RH: hinds push + swing up, then the fronts reach
const CL_SW := [0.3, 0.3, 0.28, 0.28]       # share of the cycle each paw is off the wall
var climb_splay := 1.0                      # how wide the limbs spread on a wall (0 = old narrow pose)
var _cg := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _cg_from := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _cg_sw := [-1.0, -1.0, -1.0, -1.0]      # -1 gripping, else reach progress 0..1
var _cg_init := false
var _cg_phase := 0.0
var _cg_idle_t := 0.0
var _cg_foot := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _cg_prot := [0.0, 0.0, 0.0, 0.0]
var _cg_hold := [1.0, 1.0, 1.0, 1.0]        # 0..1 how much weight each grip is taking
var _paw_yaw := [0.0, 0.0, 0.0, 0.0]
var _hang_c := Vector3.ZERO                 # chest / hips swinging off the grips (rig space, m)
var _hang_cv := Vector3.ZERO
var _hang_p := Vector3.ZERO
var _hang_pv := Vector3.ZERO
var _hang_roll := 0.0
var _still_t := 0.0
var _glance := Vector2.ZERO
var _glance_to := Vector2.ZERO
var _glance_t := 3.0
var _glance_on := false
var _hear_pos := Vector3.ZERO
var _hear_w := 0.0
var _hear_t := 0.0
var _ear_turn := [0.0, 0.0]
var _listen_t := 0.0
var _listen_seen := {}
var _bal_t := 0.0
var _bal_auto := 0.0
var _bal_s := 0.0
var _load_s := [0.6, 0.6, 0.6, 0.6]
var _lean := 0.0
var _hear_age := 9.0
## the living layer: breathing, loose skin, whiskers, ears, pupils, idle acts, startle (cat_soma.gd)
var soma := CatSoma.new()
var chin: MeshInstance3D
var whiskers := []   # [node, rest transform, root point, side] per whisker

# ---- multiplayer (see scripts/net/). everything random the rig does by itself (glances, ear
# flicks, blinks, tail twitches) and everything it is told once (swats, sounds) is written to
# life_log while net_record is on, so other players' copies of this cat can replay it exactly.
# a copy with remote_life on never rolls its own dice: it only does what the log says
var net_record := false
var remote_life := false
var life_log: Array = []
var net_phase := -1.0   # remote copy: the owner's gait phase for this frame (-1 = run free)
var net_paws := PackedVector3Array()   # remote copy: where the owner's paws are (world)
var net_pmode := -1                    # remote copy: owner's gait modes, 2 bits per paw
var _net_paws_init := false
var _net_apply := false


func _log(ev: Array) -> void:
	if net_record and life_log.size() < 64:
		life_log.append(ev)


## replay one entry of another player's life_log on this (remote) copy
func apply_life(ev: Array) -> void:
	_net_apply = true
	match str(ev[0]):
		"g":
			_glance_on = bool(ev[1])
			_glance_to = Vector2(ev[2], ev[3])
		"e":
			_ear_flick[clampi(int(ev[1]), 0, 1)] = 1.0
		"b":
			_blink_t = -0.0001
		"t":
			_twitch(float(ev[1]))
		"s":
			swat(int(ev[1]), ev[2])
		"q":
			grip_squeeze()
		"h":
			hear(ev[1], float(ev[2]))
		"L":
			gait.queue_lift(int(ev[1]), float(ev[2]), float(ev[3]))
		"a":
			soma.act(str(ev[1]), float(ev[2]))
	_net_apply = false

# ---------------- model style ----------------
## every style is a different take on the blocky low poly cat: its own
## proportions, cross sections and low poly fur trick. the animation rig is shared.
const STYLES := {
	# block base: flat painted facets
	# all black, lanky: long legs + body, slim, small head, big ears, long whip tail.
	# "flat" = no lighter muzzle / underside, nose + pads + inner ears black too
	"block_black":     {"label": "block black cat", "base": "block", "sides": 4, "head": 0.96, "leg": 1.1, "girth": 0.87, "len": 1.09, "ear": 1.18, "tail_r": 0.85, "tail_len": 1.24, "muzzle": 1.08, "fur": "painted",
		"coat": {"fur": Color(0.06, 0.06, 0.068), "dark": Color(0.035, 0.035, 0.042), "belly": Color(0.06, 0.06, 0.068), "eye": Color(1.0, 0.8, 0.06), "pattern": "solid", "socks": false,
			"flat": true, "nose": Color(0.045, 0.04, 0.045), "pad": Color(0.05, 0.045, 0.05), "whisker": Color(0.32, 0.32, 0.34)}},
	"block":           {"label": "block tabby", "base": "block", "sides": 4, "head": 1.0, "leg": 1.0, "girth": 1.0, "len": 1.0, "ear": 1.0, "tail_r": 1.0, "tail_len": 1.0, "muzzle": 1.0, "fur": "painted",
		"coat": {"fur": Color(0.86, 0.52, 0.24), "dark": Color(0.58, 0.30, 0.12), "belly": Color(0.96, 0.90, 0.80), "eye": Color(0.62, 0.86, 0.22), "pattern": "tabby", "socks": false}},
	"block_tux":       {"label": "block tuxedo", "base": "block", "sides": 4, "head": 1.02, "leg": 1.0, "girth": 0.98, "len": 1.0, "ear": 1.05, "tail_r": 1.0, "tail_len": 1.05, "muzzle": 1.0, "fur": "painted",
		"coat": {"fur": Color(0.13, 0.13, 0.15), "dark": Color(0.07, 0.07, 0.08), "belly": Color(0.96, 0.95, 0.92), "eye": Color(0.95, 0.78, 0.2), "pattern": "tux", "socks": true}},
	"block_lean":      {"label": "block lean (blue)", "base": "block", "sides": 4, "head": 0.93, "leg": 1.13, "girth": 0.86, "len": 1.07, "ear": 1.32, "tail_r": 0.85, "tail_len": 1.18, "muzzle": 1.15, "fur": "painted",
		"coat": {"fur": Color(0.47, 0.5, 0.56), "dark": Color(0.36, 0.38, 0.44), "belly": Color(0.6, 0.62, 0.68), "eye": Color(0.45, 0.85, 0.4), "pattern": "solid", "socks": false}},
	"block_bob":       {"label": "block bobtail", "base": "block", "sides": 4, "head": 1.06, "leg": 0.94, "girth": 1.1, "len": 0.94, "ear": 0.95, "tail_r": 1.25, "tail_len": 0.32, "muzzle": 0.95, "fur": "painted",
		"coat": {"fur": Color(0.55, 0.42, 0.3), "dark": Color(0.25, 0.18, 0.12), "belly": Color(0.9, 0.85, 0.75), "eye": Color(0.85, 0.65, 0.2), "pattern": "tabby", "socks": true}},
	# stepped base: chunky shell clumps
	"stepped":         {"label": "stepped fluff", "base": "stepped", "sides": 4, "head": 1.06, "leg": 0.88, "girth": 1.14, "len": 1.0, "ear": 0.95, "tail_r": 1.45, "tail_len": 0.95, "muzzle": 1.0, "fur": "shells",
		"coat": {"fur": Color(0.86, 0.52, 0.24), "dark": Color(0.58, 0.30, 0.12), "belly": Color(0.96, 0.90, 0.80), "eye": Color(0.62, 0.86, 0.22), "pattern": "tabby", "socks": false}},
	"stepped_coon":    {"label": "stepped maine coon", "base": "stepped", "sides": 4, "head": 1.1, "leg": 1.04, "girth": 1.14, "len": 1.12, "ear": 1.25, "tail_r": 1.65, "tail_len": 1.15, "muzzle": 1.1, "fur": "shells", "ear_tufts": true,
		"coat": {"fur": Color(0.5, 0.38, 0.26), "dark": Color(0.2, 0.14, 0.1), "belly": Color(0.88, 0.82, 0.7), "eye": Color(0.8, 0.7, 0.25), "pattern": "tabby", "socks": false}},
	"stepped_persian": {"label": "stepped persian", "base": "stepped", "sides": 4, "head": 1.14, "leg": 0.78, "girth": 1.2, "len": 0.95, "ear": 0.75, "tail_r": 1.55, "tail_len": 0.85, "muzzle": 0.45, "fur": "shells",
		"coat": {"fur": Color(0.95, 0.94, 0.9), "dark": Color(0.85, 0.83, 0.78), "belly": Color(0.98, 0.97, 0.94), "eye": Color(0.95, 0.55, 0.15), "pattern": "solid", "socks": false}},
	"stepped_smoke":   {"label": "stepped smoke", "base": "stepped", "sides": 4, "head": 1.04, "leg": 0.92, "girth": 1.1, "len": 1.02, "ear": 1.0, "tail_r": 1.5, "tail_len": 1.0, "muzzle": 1.0, "fur": "shells",
		"coat": {"fur": Color(0.12, 0.12, 0.14), "dark": Color(0.22, 0.22, 0.26), "belly": Color(0.2, 0.2, 0.23), "eye": Color(0.95, 0.75, 0.15), "pattern": "solid", "socks": false}},
}
const STYLE_ORDER := ["block_black", "block", "block_tux", "block_lean", "block_bob", "stepped", "stepped_coon", "stepped_persian", "stepped_smoke"]
## when true (default) the variant's own coat colors replace fur/fur_dark/belly/eye/pattern/socks
var coat_from_style := true
var style := "block"
var S_: Dictionary = {}

# ---------------- dimensions (set from the style in build) ----------------
var BODY_H := 0.215
var FRONT_SHOULDER := Vector3(0.040, -0.030, -0.030) # in chest space (x mirrored)
var HIND_HIP := Vector3(0.040, -0.012, 0.050)       # in pelvis space
var F_UP := 0.105
var F_LO := 0.084
var F_PA := 0.030 # pastern: wrist down to the knuckles (cats stand on their toes)
var H_TH := 0.100
var H_SH := 0.108
var H_MT := 0.072
var HOME := [Vector3(-0.044, 0, -0.130), Vector3(0.044, 0, -0.130), Vector3(-0.048, 0, 0.122), Vector3(0.048, 0, 0.122)]
const TAIL_N := 10
var TAIL_SEG := 0.029
var MAX_STANCE := 0.36

# gait tables: per leg phase offsets in order LF, RF, LH, RH
const OFFS := [
	[0.25, 0.75, 0.0, 0.5],   # walk: lateral sequence (LH, LF, RH, RF)
	[0.0, 0.5, 0.5, 0.0],     # trot: diagonal pairs
	[0.62, 0.52, 0.0, 0.10],  # rotary gallop: hinds then fronts
	[0.5, 0.56, 0.0, 0.06],   # half bound (climbing): hinds together, fronts together
]
const DUTY := [0.64, 0.5, 0.38, 0.45]

# ---------------- nodes ----------------
var pivot: Node3D
var chest: Node3D
var pelvis: Node3D
var neck: Node3D
var head: Node3D
var tail_base: Node3D
var ears: Array[Node3D] = []
var eyes: Array[Node3D] = []
var legs := [] # per leg dictionary of mesh instances
var tail_segs: Array[MeshInstance3D] = []
var tail_joints: Array[MeshInstance3D] = []
var spine: Array[MeshInstance3D] = [] # loin blocks between the rib cage and the pelvis


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	S_ = STYLES.get(style, STYLES["block"])
	if coat_from_style and S_.has("coat"):
		var ct: Dictionary = S_.coat
		fur = ct.fur
		fur_dark = ct.dark
		belly = ct.belly
		eye_color = ct.eye
		pattern = ct.pattern
		socks = ct.socks
		coat_flat = ct.get("flat", false)
		nose_color = ct.get("nose", nose_color)
		pad_color = ct.get("pad", pad_color)
		whisker_color = ct.get("whisker", whisker_color)
	var L: float = S_.len
	var Lg: float = S_.leg
	var Gi: float = S_.girth
	BODY_H = 0.215 * (0.3 + 0.7 * Lg)
	F_UP = 0.105 * Lg
	F_LO = 0.084 * Lg
	F_PA = 0.030 * Lg
	H_TH = 0.100 * Lg
	H_SH = 0.108 * Lg
	H_MT = 0.072 * Lg
	MAX_STANCE = 0.36 * Lg
	FRONT_SHOULDER = Vector3(0.040 * Gi, -0.030, -0.030 * L)
	HIND_HIP = Vector3(0.040 * Gi, -0.012, 0.050 * L)
	HOME = [Vector3(-0.044 * Gi, 0, -0.130 * L), Vector3(0.044 * Gi, 0, -0.130 * L), Vector3(-0.048 * Gi, 0, 0.122 * L), Vector3(0.048 * Gi, 0, 0.122 * L)]
	TAIL_SEG = 0.029 * S_.tail_len

	pivot = Node3D.new()
	pivot.position = Vector3(0, BODY_H, 0)
	add_child(pivot)

	# torso: chest, belly and pelvis blocks that flex against each other.
	# fur pattern is painted per face (see _fur_color) so stripes flow across parts
	chest = Node3D.new()
	chest.position = Vector3(0, 0.012, -0.095 * L)
	pivot.add_child(chest)
	_body_part(chest, "torso", Vector3(0, 0, -0.005), Vector3(0.1 * Gi, 0.122 * Gi, 0.17 * L), Vector3.ZERO, -0.095, "chest")
	# the loin: three short blocks strung along the spine between the rib cage and the pelvis
	# (placed every frame by _solve_spine). with the chest and pelvis that is a five piece back
	for k in 3:
		var sw: float = [0.096, 0.09, 0.094][k] * Gi
		var sh_: float = [0.114, 0.106, 0.11][k] * Gi
		var sp := _body_part(pivot, "torso", Vector3(0, -0.002, (k - 1) * 0.045 * L), Vector3(sw, sh_, 0.086 * L), Vector3.ZERO, (k - 1) * 0.045, "mid")
		sp.set_meta("s", sp.scale)
		spine.append(sp)
	pelvis = Node3D.new()
	pelvis.position = Vector3(0, 0.0, 0.095 * L)
	pelvis_z = 0.095 * L
	_tp.resize(TAIL_N); _tp.fill(0.0)
	_tpv.resize(TAIL_N); _tpv.fill(0.0)
	_ty.resize(TAIL_N); _ty.fill(0.0)
	_tyv.resize(TAIL_N); _tyv.fill(0.0)
	pivot.add_child(pelvis)
	_body_part(pelvis, "torso", Vector3(0, 0.004, 0.012), Vector3(0.1 * Gi, 0.114 * Gi, 0.15 * L), Vector3.ZERO, 0.095, "pelvis")
	# chest plate (bib)
	_body_part(chest, "bib", Vector3(0, -0.03, -0.07 * L), Vector3(0.07 * Gi, 0.08 * Gi, 0.05), Vector3(0.35, 0, 0), -0.17, "bib")
	# haunches: big square thighs read as "cat" from the side
	for side in [-1, 1]:
		_body_part(pelvis, "torso", Vector3(side * 0.03 * Gi, -0.014, 0.03 * L), Vector3(0.05 * Gi, 0.088, 0.095), Vector3(0.2, 0, 0), 0.125, "haunch")

	# neck + head
	neck = Node3D.new()
	neck.position = Vector3(0, 0.045 * Gi, -0.088 * L)
	chest.add_child(neck)
	_body_part(neck, "neck", Vector3(0, 0.004, -0.012), Vector3(0.068 * Gi, 0.078 * Gi, 0.08), Vector3(-0.5, 0, 0), -0.2, "neck")
	head = Node3D.new()
	head.position = Vector3(0, 0.038, -0.045)
	head.scale = Vector3.ONE * float(S_.head)
	neck.add_child(head)
	_build_head()

	# tail
	tail_base = Node3D.new()
	tail_base.position = Vector3(0, 0.035, 0.084 * L)
	pelvis.add_child(tail_base)
	var tr: float = S_.tail_r
	for i in TAIL_N:
		var f0 := float(i) / TAIL_N
		var f1 := float(i + 1) / TAIL_N
		var r0 := lerpf(0.017, 0.009, f0) * tr
		var r1 := lerpf(0.017, 0.009, f1) * tr
		var col := fur
		if pattern == "tabby" and i % 2 == 1:
			col = fur_dark
		if i == TAIL_N - 1:
			col = fur_dark if pattern != "tux" else belly
		var seg := LowPoly.part(self, LowPoly.cyl(r0, r1, S_.sides), col)
		_style_mat(seg)
		tail_segs.append(seg)
		var j := LowPoly.part(self, _joint_mesh(), col, Vector3.ZERO, Vector3.ONE * r1 * 1.6)
		_style_mat(j)
		tail_joints.append(j)
		if S_.fur == "shells":
			for k in 2:
				var sh := MeshInstance3D.new()
				sh.mesh = seg.mesh
				sh.scale = Vector3(1.35 + k * 0.35, 1.0, 1.35 + k * 0.35)
				sh.material_override = LowPoly.fur_mat(0.0, 0.6 - k * 0.2, 6.0, 1.04 + k * 0.04, col)
				seg.add_child(sh)
		elif (S_.fur == "tufts" or S_.fur == "sawtooth") and i >= TAIL_N - 3:
			# bushy tip: a few spikes off the end segments
			for k in 4:
				var a := k * TAU / 4.0 + i
				var tuft := LowPoly.part(j, LowPoly.cone(3), col, Vector3(cos(a) * 0.4, 0.2, sin(a) * 0.4), Vector3(0.5, 1.4, 0.5) if S_.fur == "tufts" else Vector3(0.7, 1.2, 0.12))
				tuft.rotation = Vector3(sin(a) * 1.2, 0, -cos(a) * 1.2)

	# legs
	for i in 4:
		var front := i < 2
		var leg := {}
		if front:
			leg.upper = _leg_part("fu", 0.03, 0.021, false)
			leg.lower = _leg_part("fl", 0.02, 0.017, true)
			leg.pastern = _leg_part("fp", 0.0165, 0.0155, true)
			leg.wrist = _joint(0.02)
			leg.joint = _joint(0.03)
			leg.shoulder = _body_part(self, "torso", Vector3.ZERO, Vector3(0.045 * Gi, 0.07, 0.06), Vector3.ZERO, -0.12, "shoulder")
		else:
			leg.upper = _leg_part("hu", 0.04, 0.025, false)
			leg.lower = _leg_part("hl", 0.022, 0.017, false)
			leg.meta = _leg_part("hm", 0.017, 0.014, true)
			leg.joint = _joint(0.032)
			leg.joint2 = _joint(0.022)
			leg.shoulder = _body_part(self, "torso", Vector3.ZERO, Vector3(0.055 * Gi, 0.088, 0.088), Vector3.ZERO, 0.15, "hip")
		leg.paw = Node3D.new()
		add_child(leg.paw)
		var pawc := belly if socks else fur
		var pm := LowPoly.part(leg.paw, LowPoly.box(), pawc, Vector3(0, -0.002, 0.002), Vector3(0.032, 0.018, 0.036))
		_style_mat(pm)
		leg.pad = pm
		# toes (kept so they can spread under load and curl in the air)
		leg.toes = []
		for k in 3:
			var tm := LowPoly.part(leg.paw, LowPoly.box(), pawc, Vector3((k - 1) * 0.0105, -0.001, -0.018), Vector3(0.0095, 0.014, 0.013))
			_style_mat(tm)
			leg.toes.append(tm)
		# claws: hidden until scratching / climbing / pouncing (scaled out along y)
		var cl := Node3D.new()
		cl.position = Vector3(0, -0.002, -0.024)
		leg.paw.add_child(cl)
		for k in 3:
			var cm := LowPoly.part(cl, LowPoly.cone(4), Color(0.96, 0.94, 0.88), Vector3((k - 1) * 0.0105, -0.004, -0.004), Vector3(0.0035, 0.012, 0.0035), Vector3(-PI / 2 - 0.5, 0, 0))
			cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cl.visible = false
		leg_claws.append(cl)
		leg.shoulder.set_meta("s", leg.shoulder.scale)
		legs.append(leg)

	# low poly fur extras
	match S_.fur:
		"tufts":
			_add_tufts(false)
		"sawtooth":
			_add_tufts(true)


## the cross section mesh for big parts, in unit size, long axis = Z
func _part_src() -> Array:
	var xf := Transform3D.IDENTITY
	var src: PrimitiveMesh
	match style:
		"chamfer":
			src = LowPoly.cyl_src(0.5, 0.5, 8, 1)
			xf = Transform3D(Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.UP, PI / 8), Vector3.ZERO)
		"facet":
			src = LowPoly.cyl_src(0.4, 0.5, 6, 1)
			xf = Transform3D(Basis(Vector3.RIGHT, -PI / 2) * Basis(Vector3.UP, PI / 6), Vector3.ZERO)
		"wedge":
			src = LowPoly.cyl_src(0.47, 0.707, 4, 1)
			xf = Transform3D(Basis(Vector3.RIGHT, -PI / 2) * Basis(Vector3.UP, PI / 4), Vector3.ZERO)
		_:
			var b := BoxMesh.new()
			b.size = Vector3.ONE
			b.subdivide_width = 1
			b.subdivide_height = 1
			b.subdivide_depth = 2
			src = b
	return [src, xf]


## swap in the fleck shader for the hex facet style. parts colored by material
## (not vertex paint) pass their color through as the shader's base color
func _style_mat(mi: MeshInstance3D) -> void:
	if S_.fur == "flecks":
		var base := Color.WHITE
		if mi.material_override is StandardMaterial3D:
			base = (mi.material_override as StandardMaterial3D).albedo_color
		mi.material_override = LowPoly.fur_mat(0.55, 1.0, 10.0, 1.0, base)


func _joint_mesh() -> Mesh:
	return LowPoly.box()


func _joint(sz: float) -> MeshInstance3D:
	var j := LowPoly.part(self, _joint_mesh(), fur, Vector3.ZERO, Vector3.ONE * sz)
	_style_mat(j)
	return j


## a fur covered block. body_z = where the part sits along the body (for stripe continuity)
func _body_part(parent: Node3D, region: String, pos: Vector3, scl: Vector3, rot: Vector3, body_z: float, tag: String) -> MeshInstance3D:
	var key := "body_%s_%s_%s_%s_%s_%s_%s_%s" % [style, pattern, fur.to_html(), fur_dark.to_html(), belly.to_html(), region, scl, body_z]
	var me := self
	var painter := func(c: Vector3, n: Vector3) -> Color:
		return me._fur_color(region, c, n, scl, body_z)
	var sx: Array = _part_src()
	var mesh := LowPoly.painted(sx[0], painter, key, 0.035, sx[1])
	var mi := LowPoly.part(parent, mesh, Color.WHITE, pos, scl, rot)
	mi.set_meta("tag", tag)
	_style_mat(mi)
	if S_.fur == "shells" and tag != "shoulder" and tag != "hip" and tag != "bib":
		# two chunky cutout layers = clumpy stepped fluff
		for k in 2:
			var sh := MeshInstance3D.new()
			sh.mesh = mesh
			var g := 1.1 + k * 0.1
			sh.scale = Vector3(g, g, 1.0 + (g - 1.0) * 0.5)
			sh.material_override = LowPoly.fur_mat(0.0, 0.62 - k * 0.2, 5.0 + k * 1.5, 1.03 + k * 0.04)
			mi.add_child(sh)
	return mi


func _leg_part(region: String, top_r: float, bot_r: float, low: bool) -> MeshInstance3D:
	var key := "leg_%s_%s_%s_%s_%s_%s" % [style, pattern, fur.to_html(), fur_dark.to_html(), socks, region]
	var me := self
	var painter := func(c: Vector3, _n: Vector3) -> Color:
		var col: Color = me.fur
		if me.pattern == "tabby" and sin(c.y * TAU * 2.5) > 0.35:
			col = me.fur_dark.lerp(me.fur, 0.25)
		if low and me.socks and c.y < 0.1:
			col = me.belly
		return col
	var sides: int = S_.sides
	var mesh := LowPoly.painted(LowPoly.cyl_src(top_r, bot_r, sides, 3), painter, key)
	var mi := LowPoly.part(self, mesh, Color.WHITE)
	_style_mat(mi)
	if S_.fur == "shells" and region in ["hu", "fu"]:
		var sh := MeshInstance3D.new()
		sh.mesh = mesh
		sh.scale = Vector3(1.4, 0.95, 1.4)
		sh.material_override = LowPoly.fur_mat(0.0, 0.45, 8.0, 1.05)
		mi.add_child(sh)
	return mi


## jagged fur silhouettes. tufts = little 3 sided spikes in clumps,
## sawtooth = rows of flat triangle cards (zig zag edges)
func _add_tufts(saw: bool) -> void:
	var spike := LowPoly.cone(3)
	var lo := fur.lightened(0.06)
	var rows := [
		# parent, start, end, direction(rot), count, size, color
		[head, Vector3(-0.042, -0.03, 0.0), Vector3(-0.042, -0.005, 0.02), Vector3(0.0, 0, 1.9), 3, 0.022, lo],
		[head, Vector3(0.042, -0.03, 0.0), Vector3(0.042, -0.005, 0.02), Vector3(0.0, 0, -1.9), 3, 0.022, lo],
		[chest, Vector3(-0.03, -0.075, -0.07), Vector3(0.03, -0.075, -0.07), Vector3(PI - 0.4, 0, 0), 4, 0.026, belly],
		[pivot, Vector3(-0.025, -0.06, -0.06), Vector3(0.025, -0.06, 0.06), Vector3(PI, 0, 0), 5, 0.02, belly],
		[pelvis, Vector3(-0.045, -0.02, 0.07), Vector3(-0.045, -0.06, 0.06), Vector3(2.2, 0, 0), 2, 0.024, fur],
		[pelvis, Vector3(0.045, -0.02, 0.07), Vector3(0.045, -0.06, 0.06), Vector3(2.2, 0, 0), 2, 0.024, fur],
		[neck, Vector3(-0.02, 0.04, 0.02), Vector3(0.02, 0.04, 0.02), Vector3(-0.5, 0, 0), 3, 0.02, fur],
	]
	for r in rows:
		var parent: Node3D = r[0]
		var n: int = r[4]
		for k in n:
			var t := 0.5 if n == 1 else float(k) / (n - 1)
			var p: Vector3 = (r[1] as Vector3).lerp(r[2], t)
			var sz: float = r[5] * (0.85 + 0.3 * fmod(k * 0.618, 1.0))
			var scl := Vector3(sz * 0.7, sz * 1.6, sz * 0.7) if not saw else Vector3(sz * 1.2, sz * 1.4, sz * 0.12)
			var mi := LowPoly.part(parent, spike, r[6], p, scl, r[3] + Vector3(0, 0, (t - 0.5) * 0.4))
			_style_mat(mi)
	# ear tufts
	for e in ears:
		LowPoly.part(e, spike, Color(0.97, 0.95, 0.9), Vector3(0, 0.03, -0.006), Vector3(0.008, 0.03, 0.004) if saw else Vector3(0.01, 0.026, 0.01), Vector3(-0.3, 0, 0))


## the fur painter. c = face centroid in unit space (-0.5..0.5)
func _fur_color(region: String, c: Vector3, n: Vector3, scl: Vector3, body_z: float) -> Color:
	var col := fur
	var bz := body_z + c.z * scl.z
	var lower := c.y < -0.28
	match pattern:
		"tabby":
			if region == "torso" or region == "neck":
				# mackerel stripes run down the flanks from the spine
				var band := sin(bz * TAU / 0.085 + absf(c.y) * 1.6)
				if band > 0.35 and c.y > -0.18:
					col = fur_dark.lerp(fur, 0.15)
				if absf(c.x) < 0.13 and c.y > 0.3:
					col = fur_dark.lerp(fur, 0.15)
				if lower:
					col = belly
			elif region == "bib":
				col = belly if c.z < 0.05 else fur
			elif region == "head":
				col = fur
				if c.y > 0.12 and c.z < 0.15 and absf(c.x) < 0.28 and sin(c.x * 34.0) > 0.25:
					col = fur_dark
				if absf(c.x) > 0.3 and c.y > -0.12 and c.y < 0.12 and sin(c.y * 42.0) > 0.3:
					col = fur_dark
				if c.y < -0.3 and c.z < 0.0:
					col = belly
		"tux":
			col = fur
			if region == "bib" and c.z < 0.1:
				col = belly
			elif region == "torso" and lower and c.y < -0.33:
				col = belly
			elif region == "head" and c.y < -0.25 and c.z < -0.1:
				col = belly
		_:
			if lower and not coat_flat:
				col = fur.lightened(0.12)
	# flat faces get a small light/dark tint by which way they face, keeps blocks readable
	col = col.lightened(clampf(n.y * 0.06, 0.0, 0.06)).darkened(clampf(-n.y * 0.12, 0.0, 0.12))
	return col


func _build_head() -> void:
	var pink := nose_color
	var E: float = S_.ear
	var Ssrc: Array = _part_src()
	# skull (blocky), square jaw/cheeks, muzzle block, chin
	_body_part(head, "head", Vector3(0, 0.002, 0.0), Vector3(0.078, 0.066, 0.07), Vector3.ZERO, -0.3, "skull")
	for side in [-1, 1]:
		_body_part(head, "head", Vector3(side * 0.024, -0.016, -0.012), Vector3(0.042, 0.04, 0.05), Vector3(0, side * 0.15, 0), -0.31, "cheek")
	var muzzle_col := belly if pattern != "solid" else (fur if coat_flat else fur.lightened(0.1))
	var mzs: float = S_.get("muzzle", 1.0)
	var mz := LowPoly.part(head, LowPoly.box(), muzzle_col, Vector3(0, -0.019, -0.027 - 0.013 * mzs), Vector3(0.036, 0.024, 0.026 * mzs))
	_style_mat(mz)
	var ch := LowPoly.part(head, LowPoly.box(), muzzle_col, Vector3(0, -0.031, -0.032), Vector3(0.022, 0.012, 0.02))
	_style_mat(ch)
	chin = ch
	LowPoly.part(head, LowPoly.box(), pink, Vector3(0, -0.009, -0.04 - 0.013 * mzs), Vector3(0.012, 0.008, 0.006))
	# ears
	var ear_mesh := LowPoly.cone(4)
	for side in [-1, 1]:
		var ear := Node3D.new()
		ear.position = Vector3(side * 0.025, 0.028, 0.004)
		ear.rotation = Vector3(-0.15, 0, side * -0.32)
		ear.scale = Vector3.ONE * E
		head.add_child(ear)
		var eo := LowPoly.part(ear, ear_mesh, fur_dark.lerp(fur, 0.5) if pattern == "tabby" else fur, Vector3(0, 0.023, 0), Vector3(0.04, 0.048, 0.022), Vector3(0, PI / 4 if ear_mesh == LowPoly.cone(4) else 0.0, 0))
		_style_mat(eo)
		LowPoly.part(ear, LowPoly.cone(3), pink.lerp(fur, 0.2), Vector3(0, 0.019, -0.008), Vector3(0.024, 0.033, 0.006))
		if S_.get("ear_tufts", false):
			# lynx tips
			LowPoly.part(ear, LowPoly.cone(3), fur_dark, Vector3(0, 0.054, 0.002), Vector3(0.009, 0.026, 0.009))
		ears.append(ear)
		# eyes: flat blocks with a slit pupil and a square glint
		var eye := Node3D.new()
		eye.position = Vector3(side * 0.02, 0.006, -0.036)
		eye.rotation = Vector3(0, side * -0.3, side * 0.12)
		head.add_child(eye)
		LowPoly.part(eye, LowPoly.box(), eye_color, Vector3.ZERO, Vector3(0.017, 0.012, 0.004), Vector3.ZERO, 0.25)
		LowPoly.part(eye, LowPoly.box(), Color(0.03, 0.03, 0.03), Vector3(0, 0, -0.0022), Vector3(0.0042, 0.011, 0.002))
		LowPoly.part(eye, LowPoly.box(), Color(1, 1, 1), Vector3(side * 0.004, 0.003, -0.0028), Vector3(0.003, 0.003, 0.001), Vector3.ZERO, 0.6)
		eyes.append(eye)
		# whiskers
		for k in 3:
			var w := LowPoly.part(head, LowPoly.box(0.0), whisker_color, Vector3.ZERO, Vector3.ONE)
			var a := Vector3(side * 0.018, -0.018 + k * 0.004, -0.045)
			var b := a + Vector3(side * 0.06, -0.012 + k * 0.01, 0.012 + k * 0.004)
			w.transform = Transform3D(LowPoly.seg_xform(b, a).basis * Basis().scaled(Vector3(0.0012, 1, 0.0012)), (a + b) * 0.5)
			whiskers.append([w, w.transform, a, float(side)])


## hide the visible model but keep its shadow (first person body)
func set_shadow_only(v: bool) -> void:
	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if v else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not v and _head_hidden:
		set_head_hidden(true)


var _head_hidden := false
var _head_kids := 0

## head camera: the camera sits in the skull, so the head, neck + bib only cast their shadow and
## everything else (chest, shoulders, forelegs, the rest of the body) is drawn as normal
func set_head_hidden(v: bool) -> void:
	_head_hidden = v
	_head_kids = head.get_child_count()
	for c in head_parts():
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if v else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## head, neck and the bib under the chin: what a camera in the skull hides
func head_parts() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in neck.find_children("*", "MeshInstance3D", true, false):
		out.append(c)
	for c in chest.find_children("*", "MeshInstance3D", true, false):
		if c.get_meta("tag", "") == "bib" or (c.get_parent() is MeshInstance3D and c.get_parent().get_meta("tag", "") == "bib"):
			out.append(c)
	return out


## where a camera mounted in the head goes (world): between the eyes, a touch inside the skull
func head_cam_world() -> Vector3:
	return head.to_global(Vector3(0, 0.006, -0.03))


func _process(dt: float) -> void:
	if not _built or dt <= 0.0:
		return
	animate(minf(dt, 0.05))
	if _head_hidden and head.get_child_count() != _head_kids:
		set_head_hidden(true)   # something was hung on the head later (soma's mouth): hide it too


## one quick swat with a fore paw (0 = left, 1 = right) at a world space point within reach:
## winds out to its own side (0.07 s), whips across to the target (hits at about 0.12 s,
## there by 0.15 s), back on the ground by 0.32 s. the other three paws keep standing
func swat(side: int, target: Vector3) -> void:
	if climb > 0.5 or clamber > 0.5:
		return
	if remote_life and not _net_apply:
		return
	_log(["s", side, target])
	_swat_i = clampi(side, 0, 1)
	_swat_target = target
	_swat_t = 0.0


func is_swatting() -> bool:
	return _swat_t >= 0.0


## grip: both clamped fore paws dig in for a moment
func grip_squeeze() -> void:
	if remote_life and not _net_apply:
		return
	_log(["q"])
	_squeeze_t = 0.0


func _setup_gait() -> void:
	_gait_setup = true
	_sit_s = sit
	_loaf_s = loaf
	add_to_group("cat_ears")
	gait.rig = self
	soma.setup(self)
	gait.max_stance = MAX_STANCE * 0.74
	gait.max_stance_gallop = MAX_STANCE * 0.78
	# don't let the paws stand on whatever body carries the rig (the player capsule)
	var n: Node = get_parent()
	while n:
		if n is CollisionObject3D:
			gait.exclude.append((n as CollisionObject3D).get_rid())
		n = n.get_parent()


func animate(dt: float) -> void:
	_t += dt
	if not _gait_setup:
		_setup_gait()
	# what the cat does by itself when left alone (sits down, grooms, stretches) goes in on top
	# of what the owner asked for, for this frame only
	var in_pose := [sit, loaf, groom, stretch]
	sit = maxf(sit, soma.auto_sit)
	loaf = maxf(loaf, soma.auto_loaf)
	groom = maxf(groom, soma.auto_groom)
	stretch = maxf(stretch, soma.auto_stretch)
	var gx := global_transform
	var gb := gx.basis.orthonormalized()
	var inv := gb.inverse()
	var lv := inv * drive_velocity
	var hv := Vector3(lv.x, 0, lv.z)
	var spd := hv.length()
	# local acceleration drives body inertia + the tail chain
	var acc := (lv - _vel_prev) / dt
	_vel_prev = lv
	_acc = _acc.lerp(acc.limit_length(40.0), 1.0 - exp(-10.0 * dt))
	_vy_prev = _vy
	_vy = lerpf(drive_velocity.y, lv.y, climb)
	speed_s = LowPoly.damp(speed_s, spd, 10.0, dt)
	if spd > 0.05:
		var nd := _dir.lerp(hv / spd, 1.0 - exp(-12.0 * dt))
		if nd.length_squared() > 1e-4:
			_dir = nd.normalized()
	var yaw := global_rotation.y
	var yaw_step := wrapf(yaw - _yaw_prev, -PI, PI)
	_yaw_rate = LowPoly.damp(_yaw_rate, yaw_step / dt, 8.0, dt)
	_yaw_prev = yaw
	pin = move_toward(pin, 0.0, dt * 0.9)
	var nc := 1.0 - climb
	if _swat_t >= 0.0:
		_swat_t += dt
		if _swat_t > 0.32:
			_swat_t = -1.0

	# sitting and lying down go in stages, never as one blend: the hind end goes down first,
	# then the front paws walk back / fold under. getting up runs the other way
	_sit_s = move_toward(_sit_s, sit, dt * (1.8 if sit >= _sit_s else soma.rise_rate))
	_loaf_s = move_toward(_loaf_s, loaf, dt * (1.5 if loaf >= _loaf_s else maxf(1.5, soma.rise_rate)))
	var sit_h := smoothstep(0.0, 0.62, _sit_s)
	var sit_f := smoothstep(0.38, 1.0, _sit_s)
	var loaf_h := smoothstep(0.0, 0.55, _loaf_s)
	var loaf_f := smoothstep(0.4, 1.0, _loaf_s)
	_sit_h = sit_h

	# the body does not snap round with the root: head first, chest after, hips last.
	# yaw_off is how far the body is still behind (paws re-step as it comes round)
	if not _byaw_init:
		_byaw_init = true
		_byaw = yaw
	var lagw := nc * (1.0 - clamber) * (1.0 - maxf(rear, scratch)) * (1.0 if use_planting else 0.0)
	var yd := wrapf(yaw - _byaw, -PI, PI)
	var ystep := yd * (1.0 - exp(-lerpf(6.5, 15.0, clampf(speed_s / 2.0, 0.0, 1.0)) * dt))
	var ymax := lerpf(5.0, 14.0, clampf(speed_s / 2.0, 0.0, 1.0)) * dt
	yd = clampf(yd - clampf(ystep, -ymax, ymax), -1.2, 1.2)
	_byaw = yaw - yd
	# cats don't strafe. when the travel direction has a sideways part the body turns toward it
	# (nose first going forward, tail first backing up) and the head stays on the root's heading
	if on_floor:
		var ty := 0.0
		if spd > 0.05:
			var fwdness := clampf((-lv.z + 0.5 * absf(lv.x)) / maxf(0.35 * spd, 0.02), -1.0, 1.0)
			ty = clampf(atan2(-lv.x, absf(lv.z)), -1.0, 1.0) * fwdness * smoothstep(0.15, 0.6, spd)
		_tyaw = LowPoly.damp(_tyaw, ty, 5.0, dt)
	yaw_off = (-yd + _tyaw) * lagw

	# airborne blend + landing. cats land front first: the forelegs take the hit and fold,
	# the hind end comes down a beat later, and the back rounds between them
	if on_floor:
		if not _prev_floor:
			_abs_imp = clampf(-_vy_prev, 0.0, 8.0)
			_land_fv += _abs_imp * 0.5
			_abs_delay = 0.07
			for j in TAIL_N:
				_tpv[j] -= _abs_imp * 0.9 * float(j) / TAIL_N
		_air_timer = 0.0
	else:
		if _prev_floor:
			_air_vy_max = 0.0
			if drive_velocity.y > 0.8:
				gait.takeoff()
				_launch = 1.0
			elif _climb_prev > 0.5 and drive_velocity.y < 0.3:
				tumble(0.5)   # came off a wall back first
		_air_vy_max = maxf(_air_vy_max, absf(_vy))
		_air_timer += dt
	_prev_floor = on_floor
	_climb_prev = climb
	if _abs_delay >= 0.0:
		_abs_delay -= dt
		if _abs_delay < 0.0:
			_land_v += _abs_imp * 0.42
	_launch = move_toward(_launch, 0.0, dt * 5.5)
	var air_target := 1.0 if _air_timer > 0.03 else 0.0
	_air_w = move_toward(_air_w, air_target, dt * (9.0 if air_target > _air_w else 14.0))
	# _land_f / _land: how far (m) the chest / hips have sunk into the landing
	_land_v += (-_land * 190.0 - _land_v * 19.0) * dt
	_land += _land_v * dt
	_land_fv += (-_land_f * 210.0 - _land_fv * 21.0) * dt
	_land_f += _land_fv * dt
	if not on_floor and nc > 0.5 and clamber < 0.5:
		_predict_landing(gx.origin)
	else:
		land_known = false
	# righting reflex: the front half comes round first, the hind half follows it
	if _tum_c != 0.0 or _tum_p != 0.0:
		var trate := 30.0 if on_floor else 13.0
		_tum_c = move_toward(_tum_c, 0.0, trate * dt)
		if on_floor or absf(_tum_p) - absf(_tum_c) > 1.2 or _tum_c == 0.0:
			_tum_p = move_toward(_tum_p, 0.0, trate * dt)
	var rise := clampf(_vy / 3.5, -1.0, 1.0)

	# weight: the body is a mass on springs over the paws. it hangs back and squats when the
	# cat takes off, pitches onto the forelegs and dips when it brakes, and rocks once as it settles
	var gacc := Vector3(_acc.x, 0.0, _acc.z) * (1.0 - _air_w) * nc
	var it := Vector3(clampf(-gacc.x * 0.0022, -0.02, 0.02), -clampf(gacc.length() * 0.0011, 0.0, 0.016), clampf(-gacc.z * 0.003, -0.03, 0.03))
	_iner_v += ((it - _iner) * 150.0 - _iner_v * 13.0) * dt
	_iner += _iner_v * dt
	_ipitch_v += ((clampf(-gacc.z * 0.011, -0.16, 0.16) - _ipitch) * 150.0 - _ipitch_v * 13.0) * dt
	_ipitch += _ipitch_v * dt
	_listen(dt)
	_check_narrow(dt, gx.origin, gb)

	# ---------- gait timing (real cat numbers, see cat_gait.gd) ----------
	gait.plan(speed_s, dt)
	var ww: float = gait.w_walk * nc
	var wt: float = gait.w_trot * nc
	var wg: float = gait.gallop * nc
	var wb := climb
	gait_w = Vector3(ww, wt, wg)
	_gw = [ww, wt, wg, wb]
	freq = lerpf(gait.freq, 1.5 + 1.4 * speed_s, climb)
	var move_amt := clampf(speed_s / 0.12, 0.0, 1.0)
	var still := (1.0 - move_amt) * (1.0 - _air_w)
	_still_t = _still_t + dt if (still > 0.95 and on_floor) else 0.0
	soma.pre(dt)

	# ---------- groom cycle (lick the paw, then wipe the face) ----------
	if groom > 0.01:
		_groom_t += dt
	else:
		_groom_t = 0.0
	var gcyc := fposmod(_groom_t, 3.4)
	var g_lick := groom * (1.0 - smoothstep(1.7, 1.95, gcyc)) * smoothstep(0.0, 0.35, _groom_t)
	var g_wipe := groom * smoothstep(1.7, 1.95, gcyc) * (1.0 - smoothstep(3.2, 3.4, gcyc))

	# ---------- paws: planted in the world ----------
	var lift_amt := clampf(0.022 + 0.012 * speed_s, 0.022, 0.095) * lerpf(1.0, 0.7, crouch)
	# cats walk "single track": paws land close to the midline, wider when running / climbing
	var track := 1.0 - move_amt * (0.68 * ww + 0.4 * wt + 0.15 * wg)
	track *= 1.0 + climb * 0.4 + loaf_f * 0.1 - pin * 0.5
	track *= 1.0 - 0.7 * _bal_s
	var yb := Basis(Vector3.UP, yaw_off)
	var homes := []
	for i in 4:
		var home: Vector3 = HOME[i]
		home.x *= track
		if i < 2:
			home.z = lerpf(home.z, -0.115 * pelvis_z / 0.095, sit_f)
			home.z -= stretch * 0.15
			home.z = lerpf(home.z, -0.085 * pelvis_z / 0.095, loaf_f)
		else:
			home.z = lerpf(home.z, 0.035, sit_h)
			home.z += crouch * 0.02
			home.z = lerpf(home.z, 0.07 * pelvis_z / 0.095, loaf_h)
			home.z += rear * 0.02
		homes.append(yb * home)
	var all_free := (not on_floor) or climb > 0.02 or clamber > 0.02 or not use_planting
	var want_free := [all_free, all_free, all_free, all_free]
	var gxf := Transform3D(gb, gx.origin)
	if net_phase >= 0.0:
		# remote copy: start this frame's step from where the owner's gait clock was, so the
		# same paw lifts on the same beat (update() and the climb line below add this frame's bit)
		var gv := drive_velocity * nc
		var gh := gv - gb.y * gv.dot(gb.y)
		var inc := gh.length() * dt / maxf(gait.stride, 0.05)
		if climb > 0.0:
			inc += climb * (1.5 + 1.4 * speed_s) * move_amt * dt
		gait.phase = fposmod(net_phase - inc, 1.0)
		net_phase = -1.0
	gait.remote = remote_life
	gait.owner_modes = net_pmode if remote_life else -1
	gait.update(dt, gxf, drive_velocity * nc, _yaw_rate, homes, want_free, lift_amt, on_floor)
	if net_pmode >= 0 and net_paws.size() == 4:
		# remote copy: a paw both copies have on the ground goes where the owner's is. it lands
		# right on the owner's print, and one that's off (joined mid stride) creeps over unseen
		for i in 4:
			var om := (net_pmode >> (i * 2)) & 3
			if om == CatGait.PLANTED and gait.mode[i] == CatGait.PLANTED:
				if gait.touched[i] or not _net_paws_init:
					gait.pos[i] = net_paws[i]
				else:
					gait.pos[i] = gait.pos[i].move_toward(net_paws[i], 0.06 * dt)
		_net_paws_init = true
		net_pmode = -1
	if climb > 0.0:
		gait.phase = fposmod(gait.phase + climb * (1.5 + 1.4 * speed_s) * move_amt * dt, 1.0)
	phase = gait.phase
	if climb > 0.0:
		_climb_paws(dt, gxf, move_amt)
	else:
		_cg_init = false
		_hang_c = Vector3.ZERO
		_hang_p = Vector3.ZERO
		_hang_cv = Vector3.ZERO
		_hang_pv = Vector3.ZERO
		_hang_roll = 0.0
	var p2 := phase * TAU
	var fl := []
	for i in 4:
		fl.append(gxf.affine_inverse() * (gait.pos[i] as Vector3))

	# ---------- body, solved from the paws ----------
	# walking a leg is a strut: the shoulder / hip vaults over the planted paw, highest at
	# mid stance. running it is a spring: lowest at mid stance. front and back halves each
	# follow their own legs, so the back rocks instead of bouncing as one block
	var runw := smoothstep(0.9, 1.5, speed_s)
	var Lp := BODY_H * 0.95
	var dy := [0.0, 0.0]
	var gy := [_fgy, _hgy]
	var cx_sum := 0.0
	var cx_w := 0.0
	var rough := CatGait.rough and use_planting
	if rough:
		# the capsule hopped up / down a bump: the planted paws didn't, so neither does the body
		var ry := gx.origin.y
		if not is_nan(_root_y_prev) and on_floor and _prev_floor_g and nc > 0.5 and absf(ry - _root_y_prev) < 0.3:
			_fgy -= ry - _root_y_prev
			_hgy -= ry - _root_y_prev
		_root_y_prev = ry
		_prev_floor_g = on_floor
	var groll_t := [0.0, 0.0]
	var groll_ok := [false, false]
	for h in 2:
		var wsum := 0.0
		var drop := 0.0
		var spring := 0.0
		var gsum := 0.0
		var gn := 0
		for k in 2:
			var i := h * 2 + k
			if gait.mode[i] != CatGait.PLANTED:
				continue
			var d: Vector3 = (fl[i] as Vector3) - (homes[i] as Vector3)
			var d2 := minf(d.x * d.x + d.z * d.z, Lp * Lp * 0.6)
			var sld := sin(PI * float(gait.st_s[i]))
			var w := 0.15 + sld
			wsum += w
			drop += w * (Lp - sqrt(Lp * Lp - d2))
			spring += sld
			gsum += (fl[i] as Vector3).y
			gn += 1
			cx_sum += (fl[i] as Vector3).x * float(gait.load[i])
			cx_w += float(gait.load[i])
		var walk_dy := -drop / maxf(wsum, 0.001) * 0.35 if wsum > 0.0 else 0.0
		var run_dy := -minf(spring, 1.3) * lerpf(0.007, 0.016, gait.gallop)
		dy[h] = lerpf(walk_dy, run_dy, runw) * move_amt * (1.0 - _air_w)
		if gn > 0:
			gy[h] = gsum / gn
		if rough:
			# the ground under both paws of the girdle (the swinging one: where it's landing).
			# the girdle sits nearer the lower paw (the high leg folds, the low one isn't
			# stretched off its paw: a cat crouches over a dip rather than reaching down into it) and tilts part way with the ground across it
			var yl := gait.ground_y(h * 2) - gx.origin.y
			var yr := gait.ground_y(h * 2 + 1) - gx.origin.y
			var wl := 1.0 if gait.mode[h * 2] == CatGait.PLANTED else (0.5 if gait.mode[h * 2] == CatGait.SWING else 0.0)
			var wr := 1.0 if gait.mode[h * 2 + 1] == CatGait.PLANTED else (0.5 if gait.mode[h * 2 + 1] == CatGait.SWING else 0.0)
			if wl + wr > 0.0:
				var mean := (yl * wl + yr * wr) / (wl + wr)
				var lo := minf(yl, yr) if wl > 0.0 and wr > 0.0 else mean
				gy[h] = lerpf(mean, lo, 0.75)
			if wl > 0.0 and wr > 0.0:
				var dx := maxf((fl[h * 2 + 1] as Vector3).x - (fl[h * 2] as Vector3).x, 0.07)
				groll_t[h] = clampf(atan2(yr - yl, dx) * 0.4, -0.22, 0.22)
				groll_ok[h] = true
	_chest_dy = LowPoly.damp(_chest_dy, dy[0], 28.0, dt)
	_pelvis_dy = LowPoly.damp(_pelvis_dy, dy[1], 28.0, dt)
	var plantw := (1.0 - _air_w) * nc * (1.0 - clamber)
	var glo := -0.2 if rough else -0.12
	var ghi := 0.2 if rough else 0.14
	_fgy = LowPoly.damp(_fgy, clampf(gy[0], glo, ghi) * plantw, 12.0, dt)
	_hgy = LowPoly.damp(_hgy, clampf(gy[1], glo, ghi) * plantw, 12.0, dt)
	for h in 2:
		if groll_ok[h] or not rough:
			_groll[h] = LowPoly.damp(_groll[h], float(groll_t[h]) * plantw, 10.0, dt)
	# lean over the paws that are carrying the weight
	_cx = LowPoly.damp(_cx, (cx_sum / cx_w if cx_w > 0.01 else 0.0) * 0.45 * plantw, 9.0, dt)
	_bal_s = LowPoly.damp(_bal_s, maxf(balance, _bal_auto) * plantw, 4.0, dt)
	# standing around: the weight wanders from side to side
	var still_w := smoothstep(1.0, 3.0, _still_t) * (1.0 if idle_life else 0.0) * (1.0 - _sit_s) * (1.0 - _loaf_s)
	var idle_x := still_w * (sin(_t * 0.41) * 0.005 + sin(_t * 0.97 + 1.3) * 0.002)
	var span := absf((HOME[0] as Vector3).z) + absf((HOME[2] as Vector3).z)
	var cdy := _chest_dy - clampf(_land_f, -0.02, 0.08)
	var pdy := _pelvis_dy - clampf(_land, -0.02, 0.08)
	var gait_pitch := atan2((cdy + _fgy) - (pdy + _hgy), span)

	var air_pitch := clampf(_vy * 0.065, -0.42, 0.42)
	if land_known and _vy < 0.0:
		# a long drop: nose down toward the landing, levelling out just before the paws hit
		var fall := clampf((gx.origin.y - land_point.y) / 0.6, 0.0, 1.0) * (1.0 - clampf(spd / 2.5, 0.0, 1.0))
		air_pitch -= 0.32 * fall * smoothstep(0.03, 0.22, land_t)
	air_pitch *= _air_w * nc
	# the back folds and opens with the paws: hind paws coming up under the body round it,
	# fore paws reaching out ahead of the hind ones stretch it (that is the whole gallop)
	var ext := 0.0
	if use_planting:
		ext = ((((fl[2] as Vector3).z + (fl[3] as Vector3).z) - ((fl[0] as Vector3).z + (fl[1] as Vector3).z)) - (((homes[2] as Vector3).z + (homes[3] as Vector3).z) - ((homes[0] as Vector3).z + (homes[1] as Vector3).z))) * 0.5 / span
	_flex_s = LowPoly.damp(_flex_s, clampf(ext * 1.15, -0.42, 0.3) * (0.25 + 0.75 * gait.gallop) * move_amt * plantw, 24.0, dt)
	var flex := _flex_s + wb * 0.32 * sin(p2 + 1.2) * (1.0 - _air_w) * move_amt
	var gal_bob := wg * 0.012 * sin(p2 + 0.7) * move_amt + wb * 0.012 * sin(p2) * move_amt
	# in the air: stretched right out off the push, gathered on the way down
	var air_flex := (0.26 * _launch - 0.2 * (1.0 - smoothstep(-0.5, 0.3, rise)) * (1.0 - _launch)) * _air_w * nc
	# landing rounds the back
	var arch := clampf((_land_f + _land) * 2.2, 0.0, 0.3)
	# rearing up rotates the spine about the hips (scratching, hanging off a ledge)
	var pull_e := smoothstep(0.3, 1.0, clamber_pull)
	var ra := rear * 1.02 + clamber * lerpf(1.3, 0.0, pull_e)
	var hz := pelvis_z
	var base_y := BODY_H - crouch * 0.085 - charge * 0.03 - sit_h * 0.075 + gal_bob * (1.0 - _air_w) - stretch * 0.02 - climb * lerpf(0.07, 0.145, climb_splay)
	base_y += (cdy + pdy) * 0.5 + (_fgy + _hgy) * 0.5 + _iner.y + soma.dip
	base_y = lerpf(base_y, BODY_H * 0.4 + (_fgy + _hgy) * 0.5, (loaf_h + loaf_f) * 0.5)
	pivot.position.y = base_y + hz * sin(ra)
	pivot.position.z = -sit_h * 0.035 + hz * (1.0 - cos(ra)) - clamber * (1.0 - pull_e) * 0.15 + stretch * 0.03 + _iner.z
	pivot.rotation.x = air_pitch + sit_h * 0.62 - charge * 0.05 + gait_pitch * (1.0 - sit_h) - stretch * 0.36 - pin * 0.24 + ra + _ipitch + (loaf_h - loaf_f) * 0.22
	pivot.position.x = _cx + _iner.x + idle_x
	pivot.rotation.y = yaw_off
	# lean into turns at speed
	_lean = LowPoly.damp(_lean, clampf(_yaw_rate * speed_s * 0.02, -0.28, 0.28) * (1.0 - _air_w) * nc, 6.0, dt)
	pivot.rotation.z = _lean + _tum_p
	chest.rotation.x = flex + air_flex - arch * 0.5 - sit_h * 0.14
	chest.position.y = 0.012 - stretch * 0.03
	pelvis.rotation.x = -flex - air_flex + arch * 0.5 + sit_h * 0.25 + stretch * 0.1
	# a rounded back is a shorter back: the hips slide up toward the chest
	pelvis.position.z = pelvis_z + clampf(_flex_s + air_flex - arch, -0.45, 0.3) * 0.035
	# girdles follow their paws: the hip / shoulder on the reaching side goes forward with it,
	# and the swing side drops a little
	var sw := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		if gait.mode[i] == CatGait.SWING:
			sw[i] = sin(PI * clampf(float(gait.sw_t[i]), 0.0, 1.0)) * float(gait.sw_amp[i])
	var gw_ := plantw * (1.0 - sit) * (1.0 - loaf)
	var yc := clampf(((fl[0] as Vector3).z - (homes[0] as Vector3).z - (fl[1] as Vector3).z + (homes[1] as Vector3).z) * 0.22, -0.09, 0.09) * gw_
	var yp := clampf(((fl[2] as Vector3).z - (homes[2] as Vector3).z - (fl[3] as Vector3).z + (homes[3] as Vector3).z) * 0.3, -0.12, 0.12) * gw_
	_yaw_c = LowPoly.damp(_yaw_c, yc, 14.0, dt)
	_yaw_p = LowPoly.damp(_yaw_p, yp, 14.0, dt)
	_roll_c = LowPoly.damp(_roll_c, (float(sw[0]) - float(sw[1])) * 0.022 * gw_, 14.0, dt)
	_roll_p = LowPoly.damp(_roll_p, (float(sw[2]) - float(sw[3])) * 0.034 * gw_, 14.0, dt)
	# the spine bends along the turn: the tighter the circle the more the chest leads the hips
	var twist := clampf(_yaw_rate * 0.17 / maxf(speed_s, 0.7), -0.42, 0.42) * nc * (1.0 - _air_w)
	chest.rotation.y = -yaw_off * 0.35 + twist * 0.5 + _yaw_c
	chest.rotation.z = _roll_c + (_tum_c - _tum_p) + soma.roll_c + float(_groll[0])
	# butt wiggle before a pounce
	pelvis.rotation.z = sin(_t * 19.0) * 0.14 * charge + _roll_p + soma.roll_p + float(_groll[1])
	pelvis.rotation.y = sin(_t * 19.0) * 0.06 * charge + yaw_off * 0.2 - twist * 0.5 + _yaw_p + still_w * sin(_t * 0.41) * 0.035
	# breathing (slower + deeper when loafing)
	var br := 1.0 + sin(_t * lerpf(2.4, 1.5, loaf)) * lerpf(0.012, 0.02, loaf) * (1.0 - move_amt * 0.5)
	chest.scale = Vector3(br, br, 1.0)
	# on a wall the body hangs off its grips: chest and hips swing as two pendulums under
	# whichever paws are holding, the hind end sags whenever the hind paws let go
	pivot.position += _hang_c * climb
	pelvis.position.x = (_hang_p.x - _hang_c.x) * climb
	pelvis.position.y = (_hang_p.y - _hang_c.y) * climb
	pelvis.position.z += (_hang_p.z - _hang_c.z) * climb
	chest.rotation.z += (float(_cg_hold[0]) - float(_cg_hold[1])) * 0.14 * climb * climb_splay + _hang_roll * climb
	pelvis.rotation.z += (float(_cg_hold[2]) - float(_cg_hold[3])) * 0.18 * climb * climb_splay - _hang_roll * 0.6 * climb

	_solve_spine()

	# ---------- head: held still in space while the body works under it ----------
	# the head has its own target. first the neck is posed as if it just rode on the chest,
	# then the gap between where that leaves the head and where the head has been is taken
	# out by the neck (it pitches / turns, and slides a little on the shoulders)
	var body_pitch := pivot.rotation.x + chest.rotation.x
	var body_yaw := pivot.rotation.y + chest.rotation.y
	var turn_lead := clampf(_yaw_rate * 0.06, -0.35, 0.35) * nc
	var lick_bob := sin(_t * 21.0) * 0.07 * g_lick
	var rinv := gxf.affine_inverse()
	# life: glances at nothing in particular, and toward sounds
	_glance_t -= dt
	if _glance_t < 0.0 and not remote_life:
		_glance_on = not _glance_on
		if _glance_on:
			_glance_to = Vector2(randf_range(0.25, 0.75) * (1.0 if randf() < 0.5 else -1.0), randf_range(-0.1, 0.18))
			_glance_t = randf_range(0.9, 2.4)
		else:
			_glance_to = Vector2.ZERO
			_glance_t = randf_range(2.5, 7.0)
		_log(["g", _glance_on, _glance_to.x, _glance_to.y])
	_hear_t = maxf(_hear_t - dt, 0.0)
	_hear_age += dt
	var hw := _hear_w * smoothstep(0.0, 0.35, _hear_t)
	var hear_yaw := 0.0
	if hw > 0.001:
		var hd := gb.inverse() * (_hear_pos - head.global_position)
		hear_yaw = atan2(-hd.x, -hd.z)
	var gl_t := Vector2.ZERO
	if hw > 0.001 and _hear_w >= 0.55:
		gl_t = Vector2(clampf(hear_yaw - look_yaw, -1.0, 1.0), 0.0) * smoothstep(0.1, 0.25, _hear_age) * smoothstep(0.0, 0.35, _hear_t)
	elif idle_life and _still_t > 1.2 and groom < 0.05:
		gl_t = _glance_to
	_glance = _glance.lerp(gl_t, 1.0 - exp(-8.0 * dt))
	var lk_yaw := look_yaw + _glance.x
	var lk_pitch := look_pitch + _glance.y
	if not _head_f_init:
		_neck_rest = neck.position
	var tk := smoothstep(0.0, 1.0, head_tuck) * (1.0 - _air_w) * (1.0 - climb) * (1.0 - clamber)
	var tuck_off := Vector3(0, -0.04, 0.04) * tk
	neck.position = _neck_rest + tuck_off
	neck.rotation.x = -body_pitch * 0.55 + lk_pitch * 0.35 - crouch * 0.34 - wg * 0.25 + stretch * 0.3 - pin * 0.35 + scratch * 0.15 - g_lick * 0.42 - g_wipe * 0.15 - loaf * 0.15 + climb * lerpf(0.1, -0.22, climb_splay)
	head.rotation.x = -body_pitch * 0.45 + lk_pitch * 0.65 + crouch * 0.2 + wg * 0.12 + stretch * 0.25 - g_lick * 0.38 + lick_bob - g_wipe * 0.2
	neck.rotation.y = -body_yaw * 0.5 + lk_yaw * 0.4 + turn_lead + g_lick * 0.25
	head.rotation.y = -body_yaw * 0.5 + lk_yaw * 0.6 + turn_lead * 0.6 + g_lick * 0.3
	head.rotation.z = clampf(-(pivot.rotation.z + chest.rotation.z) * 0.9, -1.0, 1.0) + g_lick * 0.25 + g_wipe * 0.4
	var hn := rinv * head.global_position
	if not _head_f_init:
		_head_f_init = true
		_head_f = hn
		_head_slow = hn.y
	var hold := (1.0 - _air_w) * nc * (1.0 - clamber) * (1.0 - maxf(rear, scratch))
	_head_f.x = clampf(LowPoly.damp(_head_f.x, hn.x, lerpf(5.0, 2.5, crouch), dt), hn.x - 0.02, hn.x + 0.02)
	_head_f.y = clampf(LowPoly.damp(_head_f.y, hn.y, lerpf(3.0, 1.5, crouch), dt), hn.y - 0.024, hn.y + 0.024)
	_head_f.z = hn.z
	_head_f = hn.lerp(_head_f, hold)
	var cbq := (gb.inverse() * chest.global_transform.basis).orthonormalized()
	var ec := cbq.inverse() * (_head_f - hn)
	var stab_p := clampf(ec.y / 0.075, -0.32, 0.32)
	var stab_y := clampf(-ec.x / 0.075, -0.3, 0.3)
	neck.rotation.x += stab_p
	head.rotation.x -= stab_p
	neck.rotation.y += stab_y
	head.rotation.y -= stab_y
	var h2 := rinv * head.global_position
	var hr := cbq.inverse() * (_head_f - h2)
	hr = Vector3(clampf(hr.x, -0.012, 0.012), clampf(hr.y, -0.016, 0.016), 0.0)
	neck.position = _neck_rest + tuck_off + hr
	var head_y := h2.y + (cbq * hr).y
	_head_slow = LowPoly.damp(_head_slow, head_y, 1.2, dt)
	head_bob = clampf(head_y - _head_slow, -0.02, 0.02) * hold
	# ears: forward + up when hunting, flattened back at speed or hanging on, follow the gaze
	_ear_t -= dt
	if _ear_t < 0.0 and not remote_life:
		_ear_t = randf_range(2.0, 6.0)
		var fi := randi() % 2
		_ear_flick[fi] = 1.0
		_log(["e", fi])
	var ear_fwd := maxf(crouch, charge) * 0.35 + scratch * 0.1 + hw * 0.2
	var ear_back := wg * 0.55 + clamber * 0.45 + climb * 0.25 + g_lick * 0.3
	for i in ears.size():
		var side := -1.0 if i == 0 else 1.0
		_ear_flick[i] = move_toward(_ear_flick[i], 0.0, dt * 6.0)
		var fk := sin(_ear_flick[i] * PI) * 0.5
		ears[i].rotation.x = -0.15 - ear_fwd + ear_back * 0.6 - fk * 0.6
		ears[i].rotation.z = side * (-0.32 - ear_back * 0.55 + ear_fwd * 0.2 - fk)
		# a sound: the ear on that side swings to it first and furthest
		var et := 0.0
		var near := true
		if hw > 0.001:
			var rel_y := wrapf(hear_yaw - lk_yaw, -PI, PI)
			near = rel_y * side < 0.0
			et = clampf(rel_y, -1.3, 1.3) * hw * (1.0 if near else 0.55)
		_ear_turn[i] = LowPoly.damp(_ear_turn[i], et, 20.0 if near else 9.0, dt)
		ears[i].rotation.y = side * fk * 0.6 + look_yaw * 0.35 + _ear_turn[i] + still_w * sin(_t * 0.7 + i * 2.1) * 0.22
	# blink, half closed eyes when loafing / grooming
	_blink_t -= dt
	var eye_y := 1.0 - loaf * 0.6 - groom * 0.45
	if _blink_t < 0.0:
		eye_y = 0.1
		if _blink_t > -dt - 1e-4:
			_log(["b"])
		if _blink_t < -0.11:
			_blink_t = 1e9 if remote_life else randf_range(1.5, 5.0)
	for e in eyes:
		e.scale.y = LowPoly.damp(e.scale.y, eye_y, 40.0, dt)

	# ---------- legs ----------
	# short sideways hop (low, mostly lateral): no chest tuck, the paws on the leading side
	# reach for the landing, the far hind leg pushes off last, the body leans into it
	var lat := clampf(lv.x / 1.4, -1.0, 1.0)
	var hopw := clampf(absf(lat) * 1.6 - absf(lv.z) / maxf(absf(lv.x), 0.05) * 0.8, 0.0, 1.0) * (1.0 - smoothstep(1.7, 3.0, _air_vy_max))
	_hop_w = LowPoly.damp(_hop_w, hopw if _air_w > 0.0 else 0.0, 20.0, dt)
	pivot.rotation.z -= lat * 0.11 * _hop_w * _air_w
	var hs := clampf(spd / 2.5, 0.0, 1.0)
	var lp := to_local(ledge_world) if clamber > 0.0 else Vector3.ZERO
	var claws := maxf(maxf(maxf(scramble, slip_claws), scratch), maxf(climb, clamber))
	claws = maxf(claws, maxf(pin, _air_w * hs * clampf(rise + 0.8, 0.0, 1.0)))
	claws_out = LowPoly.damp(claws_out, claws, 14.0, dt)
	var land_l := rinv * land_point
	if (_swat_t >= 0.0 and _swat_t < 0.26) or claw_on or grip > 0.3:
		claws_out = maxf(claws_out, 1.0)
	if _squeeze_t >= 0.0:
		_squeeze_t += dt
		if _squeeze_t > 0.25:
			_squeeze_t = -1.0
	for i in 4:
		var front := i < 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var home: Vector3 = homes[i]
		var fw: float = gait.free_w[i]
		var pp := _paw_pose(i)
		# toes turned out on the wall (fore paws up and out, hind feet more sideways)
		_paw_yaw[i] = -side * (0.38 if front else 0.6) * climb * climb_splay
		_prot_s[i] = LowPoly.damp(_prot_s[i], pp[0], 38.0, dt)
		_heel_s[i] = LowPoly.damp(_heel_s[i], pp[1], 38.0, dt)
		var foot: Vector3 = fl[i]
		var prot: float = _prot_s[i]
		var heel: float = _heel_s[i]
		_load_s[i] = LowPoly.damp(_load_s[i], pp[2], 30.0, dt)
		var load: float = _load_s[i]
		if fw > 0.0:
			# posed by the rig: standing under the hips, or the bound up a wall
			var ff := home
			var fprot := 0.0
			var fheel := 0.0
			if climb > 0.0:
				# clawed into the wall, limbs spread wide (see _climb_paws)
				ff = home.lerp(_cg_foot[i], climb)
				fprot = float(_cg_prot[i]) * climb
				fheel = (0.0 if front else 0.22 * float(_cg_hold[i])) * climb * climb_splay
			foot = foot.lerp(ff, fw)
			prot = lerpf(prot, fprot, fw)
			heel = lerpf(heel, fheel, fw)

		# pounce wind up: the hind feet tread (paddle) under the hips
		if not front and charge > 0.0:
			var tr := maxf(0.0, sin(_t * 13.0 + side * PI * 0.5))
			foot.y += tr * 0.012 * charge
			heel += tr * 0.25 * charge

		# air poses
		var aw := _air_w * nc * fw
		if aw > 0.0:
			var af: Vector3
			var arot: float
			if front:
				# going up: paws folded to the chest. coming down: reaching for the ground.
				# long leaps / pounces: arms thrown forward, claws out
				var tuck := Vector3(side * 0.035, 0.115, -0.15)
				var reach_down := Vector3(side * 0.045, -0.035, -0.2)
				var reach_fwd := Vector3(side * 0.032, 0.06, -0.33)
				var u := clampf(rise * 0.8 + 0.35, 0.0, 1.0)
				af = reach_down.lerp(tuck, u)
				arot = lerpf(0.15, -1.25, u)
				var fwd := hs * clampf(rise + 0.7, 0.0, 1.0)
				af = af.lerp(reach_fwd, fwd)
				arot = lerpf(arot, 0.35, fwd)
				if land_known:
					# the ground is coming: each paw goes for the exact spot it will land on,
					# as far as the leg reaches, so it is already there at touch down
					var lw := 1.0 - smoothstep(0.1, 0.34, land_t)
					var sh0 := yb * Vector3(side * 0.04, pivot.position.y - 0.02, (HOME[i] as Vector3).z)
					var rv := land_l + home + yb * Vector3(0, 0, -0.035) - sh0
					af = af.lerp(yb.inverse() * (sh0 + rv.limit_length(F_UP + F_LO + F_PA * 0.7)), lw)
					arot = lerpf(arot, 0.25, lw)
			else:
				var push_pose := Vector3(side * 0.05, 0.05, 0.3 + hs * 0.05)
				var tuck_pose := Vector3(side * 0.05, 0.03, 0.08)
				af = tuck_pose.lerp(push_pose, clampf(rise, 0.0, 1.0))
				arot = lerpf(-0.2, -1.1, clampf(rise, 0.0, 1.0))
				if land_known:
					# hind paws swing through under the body for their own landing spots
					var lw := (1.0 - smoothstep(0.05, 0.2, land_t)) * 0.85
					var hp0 := yb * Vector3(side * 0.04, pivot.position.y - 0.01, pelvis_z + 0.05)
					var rv := land_l + home + yb * Vector3(0, 0, -0.02) - hp0
					af = af.lerp(yb.inverse() * (hp0 + rv.limit_length(H_TH + H_SH + H_MT * 0.5)), lw)
					arot = lerpf(arot, 0.0, lw)
			if _hop_w > 0.0:
				var lead := side * lat > 0.0
				var up_k := clampf(rise * 1.6 + 0.5, 0.0, 1.0)
				var hx := side * (0.045 if front else 0.05) + lat * (0.075 if lead else 0.02)
				var hy := lerpf(-0.012 if lead else 0.0, 0.04 if lead else 0.022, up_k)
				if not front and not lead:
					# the pushing hind leg trails toward where it left the ground
					hx -= lat * 0.07 * up_k
					hy = lerpf(0.0, 0.012, up_k)
				var hp := Vector3(hx, hy, (HOME[i] as Vector3).z + (-0.015 if front else 0.0))
				af = af.lerp(hp, _hop_w)
				arot = lerpf(arot, lerpf(0.12, -0.45, up_k) if front else lerpf(0.0, -0.5, up_k), _hop_w)
			var afw := yb * af
			var troll := _tum_c if front else _tum_p
			if troll != 0.0:
				# mid righting twist the legs go round with their half of the body
				var pc := Vector3(pivot.position.x, pivot.position.y, afw.z)
				afw = pc + Basis(Vector3(0, 0, 1), troll) * (afw - pc)
			foot = foot.lerp(afw, aw)
			prot = lerpf(prot, arot, aw)
		if not front and kick_paw_w > 0.0:
			# wall kick: hind paws flat on the wall behind, toes down, until the legs straighten off it
			foot = foot.lerp(to_local(kick_paws[0 if side < 0.0 else 1]), kick_paw_w)
			prot = lerpf(prot, -1.25, kick_paw_w)
		if front and scramble > 0.0:
			var claw := Vector3(side * 0.05, 0.2 + 0.05 * sin(_t * 15.0 + side * 1.6), -0.21)
			foot = foot.lerp(claw, scramble)
			prot = lerpf(prot, 1.2, scramble)
		# airborne / climbing paws are the rig's: remember where they are so they can plant from there
		if gait.mode[i] == CatGait.FREE and fw > 0.9:
			gait.pos[i] = gxf * foot

		# behaviours
		if front:
			if stretch > 0.0:
				prot = lerpf(prot, 0.25, stretch)
			if loaf > 0.0:
				# paws folded under the chest ("hands" tucked in)
				foot = foot.lerp(Vector3(side * 0.028, 0.004, home.z + 0.02), loaf_f)
				prot = lerpf(prot, -1.9, loaf_f)
			if pin > 0.0:
				var pt := Vector3(side * 0.02, 0.0, home.z - 0.1)
				foot = foot.lerp(pt, pin)
				prot = lerpf(prot, 0.05, pin)
			if rear > 0.0 and scratch < 1.0:
				# up on the hind legs with nothing to hold: forepaws dangle, wrists bent
				var dang := Vector3(side * 0.035, BODY_H * 1.35, home.z * 0.15)
				foot = foot.lerp(dang, rear * (1.0 - scratch))
				prot = lerpf(prot, -1.3, rear * (1.0 - scratch))
			if scratch > 0.0:
				# alternate rakes: press in and drag down slowly, lift off and reach back up fast
				var sp := fposmod(_t * 1.75 + (0.0 if side < 0.0 else 0.5), 1.0)
				var top := BODY_H * 2.05
				var bot := BODY_H * 1.3
				var wz := -scratch_dist
				var st: Vector3
				if sp < 0.62:
					var u := sp / 0.62
					st = Vector3(side * 0.03, lerpf(top, bot, u * u * (3.0 - 2.0 * u)), wz + 0.004)
				else:
					var u := (sp - 0.62) / 0.38
					var e := u * u * (3.0 - 2.0 * u)
					st = Vector3(side * 0.034, lerpf(bot, top, e), wz + 0.04 * sin(PI * u))
				foot = foot.lerp(st, scratch)
				prot = lerpf(prot, 1.45, scratch)
			if g_lick + g_wipe > 0.0 and i == 1:
				# right forepaw comes up to the mouth, then wipes back over the cheek + ear
				var mouth := to_local(head.to_global(Vector3(0.006, -0.05, -0.05)))
				var wu := 0.5 - 0.5 * cos(_t * 6.5)
				var wipe := to_local(head.to_global(Vector3(0.03, lerpf(-0.03, 0.05, wu), lerpf(-0.06, -0.005, wu))))
				var gp := mouth.lerp(wipe, g_wipe / maxf(g_lick + g_wipe, 0.001))
				var gw := clampf(g_lick + g_wipe, 0.0, 1.0)
				foot = foot.lerp(gp, gw)
				prot = lerpf(prot, -1.5, gw)
			if clamber > 0.0:
				# forepaws hooked over the ledge, they stay planted while the body hauls up
				var ft := lp + Vector3(side * 0.04, 0.0, -0.045)
				var cw := clamber * (1.0 - smoothstep(0.8, 1.0, clamber_pull))
				foot = foot.lerp(ft, cw)
				prot = lerpf(prot, 0.0, cw)
			# claw hold: this paw reaches out and stays hooked on a point
			_claw_w[i] = LowPoly.damp(_claw_w[i], 1.0 if (claw_on and claw_i == i and _swat_t < 0.0 and climb < 0.5 and clamber < 0.5) else 0.0, 26.0, dt)
			if _claw_w[i] > 0.001:
				foot = foot.lerp(to_local(claw_target), _claw_w[i])
				prot = lerpf(prot, 0.5, _claw_w[i])
			# two paw grip: both paws clamped either side of the target's spine, digging in
			if grip > 0.001:
				var gp := to_local(claw_target) + Vector3(side * 0.032, 0.0, 0.0)
				if _squeeze_t >= 0.0:
					var k := sin(clampf(_squeeze_t / 0.25, 0.0, 1.0) * PI)
					gp += Vector3(-side * 0.012, -0.012, 0.018) * k
				foot = foot.lerp(gp, grip)
				prot = lerpf(prot, 0.65, grip)
			# swat: wind out to the side, whip across, recover
			if _swat_t >= 0.0 and _swat_i == i:
				var wind := Vector3(side * 0.105, BODY_H * 0.62, home.z - 0.07)
				var strike := to_local(_swat_target)
				var sw_p: Vector3
				var sw_r: float
				if _swat_t < 0.07:
					var u := _swat_t / 0.07
					sw_p = foot.lerp(wind, u * (2.0 - u))
					sw_r = lerpf(prot, -0.9, u)
				elif _swat_t < 0.15:
					var u := (_swat_t - 0.07) / 0.08
					sw_p = wind.lerp(strike, u * u)
					sw_r = lerpf(-0.9, 0.55, u)
				elif _swat_t < 0.24:
					# the scratch: claws hooked in, the paw drags down and back toward the chest
					var u := smoothstep(0.0, 1.0, (_swat_t - 0.15) / 0.09)
					sw_p = strike.lerp(strike + Vector3(-side * 0.015, -0.05, 0.075), u)
					sw_r = lerpf(0.55, 0.95, u)
				else:
					var rk := strike + Vector3(-side * 0.015, -0.05, 0.075)
					var u := smoothstep(0.0, 1.0, (_swat_t - 0.24) / 0.08)
					sw_p = rk.lerp(foot, u)
					sw_p.y += sin(PI * u) * 0.015
					sw_r = lerpf(0.95, prot, u)
				foot = sw_p
				prot = sw_r
			fp_foot[i] = foot - Vector3((HOME[i] as Vector3).x * track, 0.0, (HOME[i] as Vector3).z)
			fp_down[i] = gait.mode[i] == CatGait.PLANTED
		else:
			if loaf > 0.0:
				heel = lerpf(heel, -0.95, loaf_h)
			if stretch > 0.0:
				heel += stretch * 0.25
			if clamber > 0.0:
				# hind paws scrabble on the wall face, then step up onto the top
				var hip_l := to_local(pelvis.to_global(Vector3(HIND_HIP.x * side, HIND_HIP.y, HIND_HIP.z)))
				var scr := sin(_t * 17.0 + side * 1.7) * (1.0 - clamber_pull)
				var wt_p := Vector3(side * 0.05, hip_l.y - H_TH * 0.95 + 0.035 * scr, lp.z + 0.012 + 0.014 * maxf(scr, 0.0))
				var hcw := clamber * (1.0 - smoothstep(0.55, 0.95, clamber_pull))
				foot = foot.lerp(wt_p, hcw)
				heel = lerpf(heel, 0.35, hcw)
				prot = lerpf(prot, 1.35, hcw)
		foot += soma.paw_off[i]
		_solve_leg(i, foot, side, prot, heel, load)
		# toes spread under weight and curl when the paw is folded back in the air
		var spl := load * (1.0 - fw)
		var curl := clampf(-prot / 1.2, 0.0, 1.0)
		var toes: Array = legs[i].toes
		for k in 3:
			var tm: MeshInstance3D = toes[k]
			tm.position = Vector3((k - 1) * 0.0105 * (1.0 + 0.42 * spl - 0.2 * curl), -0.001 - 0.005 * curl, -0.018 - 0.0015 * spl + 0.003 * curl)
			tm.rotation.x = -0.7 * curl
		(legs[i].pad as MeshInstance3D).scale = Vector3(0.032 * (1.0 + 0.16 * spl), 0.018 * (1.0 - 0.14 * spl), 0.036)
		if leg_claws.size() > i:
			var cl: Node3D = leg_claws[i]
			var cs := clampf(claws_out * (1.0 if front else climb + clamber), 0.0, 1.0)
			cl.visible = cs > 0.05
			cl.scale = Vector3(1, 1, maxf(cs, 0.05))

	# ---------- tail ----------
	_update_tail(dt, ww, wt, wg, move_amt)
	soma.post(dt)
	sit = in_pose[0]
	loaf = in_pose[1]
	groom = in_pose[2]
	stretch = in_pose[3]


## strings the loin blocks along a curve from the back of the rib cage to the front of the
## pelvis. whatever the two ends do (gallop fold, turning, sitting, twisting) the back then
## bends through five pieces instead of hinging in the middle
func _solve_spine() -> void:
	if spine.is_empty():
		return
	var ct := chest.transform
	var pt := pelvis.transform
	var ls := pelvis_z / 0.095
	var a := ct * Vector3(0, -0.014, 0.05 * ls)
	var b := pt * Vector3(0, -0.002, -0.045 * ls)
	var m := (b - a).length()
	var ta := ct.basis.z.normalized() * m
	var tb := pt.basis.z.normalized() * m
	var qa := ct.basis.orthonormalized().get_rotation_quaternion()
	var qb := pt.basis.orthonormalized().get_rotation_quaternion()
	for k in spine.size():
		var t: float = [0.06, 0.5, 0.94][k]
		var t2 := t * t
		var t3 := t2 * t
		var p := a * (2.0 * t3 - 3.0 * t2 + 1.0) + ta * (t3 - 2.0 * t2 + t) + b * (-2.0 * t3 + 3.0 * t2) + tb * (t3 - t2)
		var d := a * (6.0 * t2 - 6.0 * t) + ta * (3.0 * t2 - 4.0 * t + 1.0) + b * (-6.0 * t2 + 6.0 * t) + tb * (3.0 * t2 - 2.0 * t)
		var z := d.normalized()
		var up := qa.slerp(qb, t) * Vector3.UP
		var x := up.cross(z).normalized()
		var y := z.cross(x)
		var sc: Vector3 = spine[k].get_meta("s")
		spine[k].transform = Transform3D(Basis(x, y, z) * Basis.from_scale(sc), p)


## where the current jump / fall comes down: marches the ballistic arc against the static world
func _predict_landing(from: Vector3) -> void:
	land_known = false
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var p := from + Vector3(0, 0.03, 0)
	var v := drive_velocity
	var h := 0.05
	for k in 16:
		var v2 := v + Vector3.DOWN * gravity * h
		var p2 := p + (v + v2) * 0.5 * h
		var q := PhysicsRayQueryParameters3D.create(p, p2 - Vector3(0, 0.03, 0))
		q.exclude = gait.exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.5 and (hit.collider is StaticBody3D or hit.collider is CSGShape3D or hit.collider is GridMap):
			land_point = hit.position
			land_t = (k + (land_point - p).length() / maxf((p2 - p).length(), 0.001)) * h
			land_known = true
			return
		p = p2
		v = v2


## righting reflex: start a fall rolled over by this many turns (0.5 = on its back) and the
## cat twists itself upright on the way down, front half first. happens by itself when the
## cat comes off a climb backwards
func _twitch(imp: float) -> void:
	if _tyv.size() < TAIL_N:
		return
	for j in range(TAIL_N - 3, TAIL_N):
		_tyv[j] += imp * (j - TAIL_N + 4) / 3.0
		_tpv[j] += absf(imp) * 0.4


func tumble(turns := 0.5) -> void:
	_tum_c = turns * TAU
	_tum_p = turns * TAU


## something made a noise at a world position. the ears swing to it (the near ear first and
## furthest), and from about 0.55 loudness the head follows. anything can call this, or reach
## every cat with get_tree().call_group("cat_ears", "hear", pos, loudness)
func hear(pos: Vector3, loud := 1.0) -> void:
	if remote_life and not _net_apply:
		return   # a remote copy only hears what its owner heard
	if loud < _hear_w * smoothstep(0.0, 0.35, _hear_t):
		return
	_log(["h", pos, loud])
	_hear_pos = pos
	_hear_w = clampf(loud, 0.0, 1.0)
	_hear_t = 1.1 + _hear_w * 0.8
	_hear_age = 0.0
	soma.heard(pos, loud)


## where the eyes are (world). steady: the neck has already taken the body's bob out
func eye_world() -> Vector3:
	return head.to_global(Vector3(0, 0.006, -0.036))


## prey rustling about nearby is heard without anyone calling hear() (ears only, never the head)
func _listen(dt: float) -> void:
	_listen_t -= dt
	if _listen_t > 0.0 or not auto_listen or remote_life or not is_inside_tree():
		return
	_listen_t = 0.3
	var seen := {}
	var best_s := 0.0
	var best := Vector3.ZERO
	var me := global_position
	for n in get_tree().get_nodes_in_group("prey"):
		if not (n is Node3D):
			continue
		var p: Vector3 = (n as Node3D).global_position
		var id := n.get_instance_id()
		seen[id] = p
		var d := p.distance_to(me)
		if d > 6.0 or d < 0.05 or not _listen_seen.has(id):
			continue
		var s := clampf((p - (_listen_seen[id] as Vector3)).length() / 0.3 / 1.5, 0.0, 1.0) * (1.0 - d / 6.0)
		if s > best_s:
			best_s = s
			best = p
	_listen_seen = seen
	if best_s > 0.12:
		hear(best, clampf(0.2 + best_s * 0.4, 0.0, 0.5))


## standing on something narrow (fence top, beam, branch): nothing to stand on either side
func _check_narrow(dt: float, origin: Vector3, gb: Basis) -> void:
	_bal_t -= dt
	if _bal_t > 0.0 or not is_inside_tree():
		return
	_bal_t = 0.25
	_bal_auto = 0.0
	if not on_floor or climb > 0.1 or not use_planting:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	for s in [-1.0, 1.0]:
		var from: Vector3 = origin + gb.x * (s * 0.11) + Vector3(0, 0.08, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 0.26, 0))
		q.exclude = gait.exclude
		if not space.intersect_ray(q).is_empty():
			return
	_bal_auto = 1.0


## wrist flick / heel lift / load for a paw from where it is in its step.
## returns [paw pitch, extra hock angle, load 0..1]
func _paw_pose(i: int) -> Array:
	var front := i < 2
	var prot := 0.0
	var heel := 0.0
	if gait.mode[i] == CatGait.SWING:
		var s := clampf(float(gait.sw_t[i]), 0.0, 1.0)
		var a: float = gait.sw_amp[i]
		if front:
			# wrist flick: paw folds back hard right after lift off, then unfolds toes first
			prot = (-1.35 * sin(PI * clampf(s / 0.62, 0.0, 1.0)) + 0.22 * smoothstep(0.6, 0.85, s) * (1.0 - smoothstep(0.88, 1.0, s))) * a
		else:
			prot = -0.75 * sin(PI * clampf(s / 0.7, 0.0, 1.0)) * a
			heel = 0.45 * (1.0 - smoothstep(0.0, 0.5, s)) * a
		return [prot, heel, 0.0]
	if gait.mode[i] == CatGait.FREE:
		return [0.0, 0.0, 0.0]
	var mv: float = gait.moving
	var s: float = gait.st_s[i]
	if front:
		# end of stance: the paw peels off heel first, wrist breaks over
		prot = -smoothstep(0.7, 1.0, s) * 0.55 * mv
	else:
		# E2 yield: right after touch down the ankle gives (hock sinks) as the leg takes the
		# weight, peaking ~25% into stance (~10 deg walking, ~18 trotting), then the hock rises and
		# the weight rolls onto the toes for the E3 push off
		var yld := (0.17 + 0.14 * gait.w_trot) * sin(PI * clampf(s / 0.55, 0.0, 1.0))
		heel = (smoothstep(0.5, 1.0, s) * 0.45 - yld) * mv
		prot = -smoothstep(0.75, 1.0, s) * 0.4 * mv
	return [prot, heel, lerpf(0.6, sin(PI * s), mv)]


## where each paw grips on a wall, rig space: spread well wider than the shoulders / hips,
## fore paws reaching up past the chest
func _climb_home(i: int) -> Vector3:
	var h: Vector3 = HOME[i]
	var sp := lerpf(1.4, 1.6 if i < 2 else 1.95, climb_splay)
	return Vector3(h.x * sp, 0.0, h.z + (-0.1 if i < 2 else 0.015) * climb_splay)


## climbing paws: each holds its own spot on the wall (claws in) and only lets go to reach
## for the next. hind paws push and swing up together, then the fore paws reach one after
## the other. the body hangs off whatever is holding: chest and hips are two damped
## pendulums pulled down the wall by gravity, swinging under the paws that grip
func _climb_paws(dt: float, gxf: Transform3D, move_amt: float) -> void:
	var inv := gxf.affine_inverse()
	if not _cg_init:
		_cg_init = true
		for i in 4:
			_cg[i] = gxf * _climb_home(i)
			_cg_sw[i] = -1.0
			_cg_hold[i] = 1.0
		_cg_phase = phase
	var fr := maxf(freq, 2.2)
	# land ahead of home so the grip passes under it halfway through the hold
	var reach_len := clampf(speed_s * 0.7 / fr * 0.5, 0.0, 0.07)
	var dir_l := Vector3(_dir.x, 0.0, _dir.z)
	var swinging := 0
	for i in 4:
		if float(_cg_sw[i]) >= 0.0:
			swinging += 1
	for i in 4:
		var front := i < 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var home := _climb_home(i)
		var grip_l: Vector3 = inv * (_cg[i] as Vector3)
		if float(_cg_sw[i]) < 0.0:
			var q0 := fposmod(_cg_phase - float(CL_OFFS[i]), 1.0)
			var q1 := fposmod(phase - float(CL_OFFS[i]), 1.0)
			var err := Vector2(grip_l.x - home.x, grip_l.z - home.z).length()
			var start := move_amt > 0.3 and q1 < q0 and q1 < 0.25   # its turn in the cycle
			start = start or err > 0.15                              # out of reach: has to let go
			if move_amt <= 0.3 and swinging == 0 and _cg_idle_t <= 0.0 and err > 0.035:
				start = true                                         # hanging still: re-grip one at a time
			if start:
				_cg_sw[i] = 0.0
				_cg_from[i] = _cg[i]
				swinging += 1
				_cg_idle_t = 0.22
		var target := home + dir_l * reach_len * move_amt
		if float(_cg_sw[i]) >= 0.0:
			_cg_sw[i] = minf(float(_cg_sw[i]) + dt * fr / float(CL_SW[i]), 1.0)
			var s: float = _cg_sw[i]
			var e := s * s * (3.0 - 2.0 * s)
			var f: Vector3 = (inv * (_cg_from[i] as Vector3)).lerp(target, e)
			var arc := sin(PI * s)
			f.y += arc * (0.05 if front else 0.034)
			f.x += side * arc * 0.014
			_cg_foot[i] = f
			if front:
				# paw curled on the way up, then opened with the claws out to strike the bark
				_cg_prot[i] = -1.1 * sin(PI * minf(s / 0.7, 1.0)) + 0.4 * smoothstep(0.6, 1.0, s)
			else:
				_cg_prot[i] = -0.7 * arc
			_cg_hold[i] = 1.0 - smoothstep(0.0, 0.12, s) * (1.0 - smoothstep(0.88, 1.0, s))
			if s >= 1.0:
				_cg_sw[i] = -1.0
				_cg[i] = gxf * Vector3(target.x, 0.0, target.z)
		else:
			_cg_foot[i] = grip_l
			_cg_prot[i] = 0.2 if front else 0.05
			_cg_hold[i] = 1.0
	_cg_phase = phase
	_cg_idle_t -= dt

	# ---- the hang. gravity in rig space, flattened onto the wall (mostly +z: down the wall)
	var g_l := gxf.basis.orthonormalized().inverse() * Vector3.DOWN
	var gp := Vector3(g_l.x, 0.0, g_l.z)
	var fh := (float(_cg_hold[0]) + float(_cg_hold[1])) * 0.5
	var hh := (float(_cg_hold[2]) + float(_cg_hold[3])) * 0.5
	var fx := 0.0
	var hx := 0.0
	for k in 2:
		fx += (_cg_foot[k] as Vector3).x * float(_cg_hold[k])
		hx += (_cg_foot[k + 2] as Vector3).x * float(_cg_hold[k + 2])
	fx = fx / (fh * 2.0) if fh > 0.05 else 0.0
	hx = hx / (hh * 2.0) if hh > 0.05 else 0.0
	# the burst up the wall leaves the hips behind (they lag, then catch up)
	var up_acc := clampf(-_acc.dot(gp), -6.0, 10.0)
	var sp := climb_splay
	var c_t := gp * (0.006 + 0.024 * (1.0 - fh)) + Vector3(fx * 0.5, 0.024 * (1.0 - fh), 0.0)
	var p_t := gp * (0.014 + 0.036 * (1.0 - hh) + up_acc * 0.0018) + Vector3(0.0, 0.032 * (1.0 - hh), 0.0)
	p_t.x = lerpf(c_t.x, hx * 0.5, hh)
	c_t *= sp
	p_t *= sp
	_hang_cv += ((c_t - _hang_c) * 120.0 - _hang_cv * 8.0) * dt
	_hang_c += _hang_cv * dt
	_hang_pv += ((p_t - _hang_p) * 75.0 - _hang_pv * 5.5) * dt
	_hang_p += _hang_pv * dt
	# a sideways swing of the hips twists the body a touch
	_hang_roll = LowPoly.damp(_hang_roll, clampf(_hang_pv.x * 1.2, -0.15, 0.15), 10.0, dt)


## phase driven foot path in rig space (only the climbing bound still uses this).
## returns [foot position, paw pitch, extra hock angle, load 0..1]
func _gait_foot(g: int, i: int, home: Vector3, lift: float) -> Array:
	var duty: float = DUTY[g]
	var max_st := MAX_STANCE if g < 2 else MAX_STANCE * 1.22
	var stance_len := speed_s * duty / maxf(freq, 0.01)
	if stance_len > max_st:
		duty = max_st * freq / maxf(speed_s, 0.001)
		stance_len = max_st
	var q := fposmod(phase - OFFS[g][i], 1.0)
	var front := i < 2
	var along: float
	var y := 0.0
	var prot := 0.0
	var heel := 0.0
	var load := 0.0
	if q < duty:
		var s := q / duty
		along = stance_len * (0.5 - s)
		load = sin(PI * s)
		if front:
			prot = -smoothstep(0.7, 1.0, s) * 0.55
		else:
			heel = smoothstep(0.5, 1.0, s) * 0.45
			prot = -smoothstep(0.75, 1.0, s) * 0.4
	else:
		var s := (q - duty) / (1.0 - duty)
		var e := s * s * (3.0 - 2.0 * s)
		along = stance_len * (-0.5 + e)
		y = lift * sin(PI * pow(s, 0.65)) * (1.0 if front else 0.85)
		along += sin(PI * s) * stance_len * (0.12 if g < 2 else 0.3)
		if front:
			prot = -1.35 * sin(PI * clampf(s / 0.62, 0.0, 1.0)) + 0.22 * smoothstep(0.6, 0.85, s) * (1.0 - smoothstep(0.88, 1.0, s))
		else:
			prot = -0.75 * sin(PI * clampf(s / 0.7, 0.0, 1.0))
			heel = 0.45 * (1.0 - smoothstep(0.0, 0.5, s))
	return [home + _dir * along + Vector3(0, y, 0), prot, heel, load]


func _solve_leg(i: int, foot: Vector3, side: float, prot: float, heel: float, load: float) -> void:
	var leg: Dictionary = legs[i]
	var rel := global_transform.basis.orthonormalized().inverse()
	# a planted paw lies flat on whatever it stands on (slopes, step edges)
	var n_l := rel * (gait.nrm[i] as Vector3)
	var tw := float(gait.load[i]) * (1.0 - float(gait.free_w[i])) * (1.0 - climb)
	var ax := Vector3.UP.cross(n_l)
	var R := Basis(Vector3.UP, float(_paw_yaw[i])) * Basis(Vector3.RIGHT, prot)
	if tw > 0.01 and ax.length_squared() > 1e-6:
		R = Basis(ax.normalized(), acos(clampf(n_l.y, -1.0, 1.0)) * tw) * R
	if i < 2:
		# shoulder blade: hangs off the top of the chest and swings with the leg, so the
		# shoulder joint travels forward and back with the paw (a longer working leg).
		# under load the chest sinks between the blades and they poke up above the back
		var cb := rel * chest.global_transform.basis.orthonormalized()
		var top_c := Vector3(FRONT_SHOULDER.x * side * 0.8, 0.042, FRONT_SHOULDER.z + 0.04)
		var rest := Vector3(FRONT_SHOULDER.x * side, FRONT_SHOULDER.y, FRONT_SHOULDER.z) - top_c
		var top := to_local(chest.to_global(top_c))
		# pastern: the wrist stands over the toes on a short sloping bone that gives under load
		var pa := 0.2 + load * 0.3
		var knuckle := foot + R * Vector3(0, 0.013, 0.004)
		var wrist_t := knuckle + R * Vector3(0, F_PA * cos(pa), F_PA * sin(pa))
		var reach := (cb.inverse() * (wrist_t - top))
		var limb_a := atan2(-reach.z, maxf(-reach.y, 0.02))
		_scap[i] = clampf(limb_a * 0.6, -0.5, 0.55)
		var sb := Basis(Vector3.RIGHT, _scap[i])
		# stalking low the blades work like pistons: the one over the loaded paw pokes right up
		var rise := load * (0.012 + 0.02 * crouch) + crouch * 0.008
		top += cb * Vector3(0, rise, 0)
		var sh := top + cb * (sb * rest)
		var hint := Vector3(0, -0.2 - rear * 0.9 - clamber * 0.6, 1.0)
		# climbing: elbows stick out sideways and off the wall
		hint += Vector3(side * 1.5, 0.7, -0.5) * climb * climb_splay
		var d := (wrist_t - sh).length()
		gait.stretch[i] = d / (F_UP + F_LO)
		# nothing bony ties the blade to the ribs: when the leg runs out of reach the whole
		# shoulder slides toward the paw instead of the paw leaving the ground
		var over := d - (F_UP + F_LO - 0.004)
		if over > 0.0:
			var slip := (wrist_t - sh) / d * minf(over, 0.03)
			sh += slip
			top += slip * 0.6
		var r := LowPoly.ik2(sh, wrist_t, F_UP, F_LO, hint)
		var elbow: Vector3 = r[0]
		var wrist: Vector3 = r[1]
		leg.upper.transform = LowPoly.seg_xform(sh, elbow)
		leg.lower.transform = LowPoly.seg_xform(elbow, wrist)
		leg.joint.position = elbow
		var sc: Vector3 = leg.shoulder.get_meta("s")
		leg.shoulder.transform = Transform3D(cb * Basis(Vector3.RIGHT, _scap[i] * 0.8 + 0.12) * Basis.from_scale(sc), sh.lerp(top, 0.42) + cb * Vector3(0, 0.004, 0.0))
		var miss := wrist - wrist_t
		leg.pastern.transform = LowPoly.seg_xform(wrist, knuckle + miss)
		leg.wrist.position = wrist
		leg.paw.position = foot + miss + R * Vector3(0, 0.010, -0.006)
		leg.paw.basis = R
	else:
		var hip := to_local(pelvis.to_global(Vector3(HIND_HIP.x * side, HIND_HIP.y, HIND_HIP.z)))
		var theta := lerpf(1.1, 0.7, crouch)
		theta = lerpf(theta, 0.12, _sit_h)
		theta = lerpf(theta, 1.3, rear)
		theta += heel - load * 0.1 * (1.0 - _sit_h)
		if _air_w > 0.0:
			theta = lerpf(theta, lerpf(0.9, 0.3, clampf(_vy / 3.5, 0.0, 1.0)), _air_w * (1.0 - climb))
		theta = clampf(theta, 0.05, 1.65)
		var hock_t := foot + Basis(Vector3.UP, float(_paw_yaw[i]) * 0.5) * Vector3(0, H_MT * sin(theta), H_MT * cos(theta))
		var hd := (hock_t - hip).length()
		gait.stretch[i] = hd / (H_TH + H_SH)
		var hover := hd - (H_TH + H_SH - 0.004)
		if hover > 0.0:
			hip += (hock_t - hip) / hd * minf(hover, 0.02)
		# climbing: knees out to the side, frog legged
		var r := LowPoly.ik2(hip, hock_t, H_TH, H_SH, Vector3(0, 0.1, -1.0) + Vector3(side * 1.6, 0.5, 0.4) * climb * climb_splay)
		var knee: Vector3 = r[0]
		var hock: Vector3 = r[1]
		var foot_a := hock - (hock_t - foot)
		leg.upper.transform = LowPoly.seg_xform(hip, knee)
		leg.lower.transform = LowPoly.seg_xform(knee, hock)
		leg.meta.transform = LowPoly.seg_xform(hock, foot_a + R * Vector3(0, 0.012, 0))
		leg.joint.position = knee
		leg.joint2.position = hock
		var pb := rel * pelvis.global_transform.basis.orthonormalized()
		var sc: Vector3 = leg.shoulder.get_meta("s")
		leg.shoulder.transform = Transform3D(pb * Basis.from_scale(sc), hip + pb * Vector3(0, 0.02, -0.01))
		leg.paw.position = foot_a + R * Vector3(0, 0.008, -0.014)
		leg.paw.basis = R


func _update_tail(dt: float, ww: float, wt: float, wg: float, move_amt: float) -> void:
	# shape params: base pitch, curve per seg, sway amp, sway freq, yaw curl per seg
	var idle := PackedFloat32Array([0.95, -0.07, 0.10, 0.9, 0.0])
	var walk := PackedFloat32Array([1.45, -0.05, 0.06, 1.8, 0.0])
	var trot := PackedFloat32Array([0.85, -0.07, 0.06, 2.4, 0.0])
	var gal := PackedFloat32Array([0.18, -0.005, 0.05, 3.0, 0.0])
	var stalk := PackedFloat32Array([-0.12, 0.035, 0.32, 2.8, 0.0])
	var sitp := PackedFloat32Array([-1.1, 0.16, 0.05, 1.0, 0.22])
	var loafp := PackedFloat32Array([-0.5, 0.05, 0.03, 0.8, 0.27])
	# climbing: hangs down the wall off the rump, curving back in toward it, swinging slowly
	var climbp := PackedFloat32Array([0.32, -0.06, 0.07, 0.9, 0.0])
	var rearp := PackedFloat32Array([-0.95, 0.05, 0.08, 1.2, 0.0])
	# wall kick: reared up with the rump against the wall, the tail hangs down the spine line, off the wall
	var kickp := PackedFloat32Array([-0.42, 0.03, 0.04, 1.2, 0.0])
	var hangp := PackedFloat32Array([-1.05, 0.02, 0.22, 1.7, 0.0])
	var strp := PackedFloat32Array([0.75, -0.02, 0.04, 1.0, 0.0])
	var balp := PackedFloat32Array([0.28, -0.012, 0.03, 1.1, 0.0])
	var target := PackedFloat32Array([0, 0, 0, 0, 0])
	var nc := 1.0 - climb
	for k in 5:
		var moving := (ww * walk[k] + wt * trot[k] + wg * gal[k]) / maxf(nc, 0.001)
		var v := lerpf(idle[k], moving, move_amt)
		v = lerpf(v, stalk[k], maxf(crouch, charge))
		if _air_w > 0.0:
			var airv: float = [0.45 + clampf(-_vy * 0.12, -0.3, 0.5), 0.0, 0.03, 2.0, 0.0][k]
			v = lerpf(v, airv, _air_w)
		v = lerpf(v, sitp[k], sit)
		v = lerpf(v, loafp[k], loaf)
		v = lerpf(v, strp[k], stretch)
		v = lerpf(v, rearp[k], rear)
		v = lerpf(v, kickp[k], kick_w)
		v = lerpf(v, climbp[k], climb)
		v = lerpf(v, hangp[k], clamber * (1.0 - clamber_pull))
		v = lerpf(v, balp[k], _bal_s * (1.0 - maxf(sit, loaf)))
		target[k] = v
	for k in 5:
		_tail_p[k] = LowPoly.damp(_tail_p[k], target[k], 5.0, dt)
		# wall kick: the body turns its back to the wall in a couple of frames and the tail
		# goes with it right away (a lagging tail would sweep through the wall)
		_tail_p[k] = lerpf(_tail_p[k], target[k], kick_w)

	# inertia: accelerating forward / up makes the tail trail back and droop,
	# lateral accel + turning swing it out. the chain springs follow their parent
	# with a lag so motion rolls down the tail as a whip, with a floppy tip.
	var f_pitch := clampf(_acc.z * 0.02 - _acc.y * 0.03, -0.7, 0.7)
	var f_yaw := clampf(-_acc.x * 0.025 - _yaw_rate * 0.14 * (1.0 + wg * 0.8), -1.0, 1.0)
	# balance: the tail goes the other way from wherever the body is being thrown, whirls
	# against a righting twist, and on a narrow perch works side to side as a balance pole
	f_yaw += clampf(-_iner_v.x * 1.6, -0.35, 0.35) - clampf((_tum_c + _tum_p) * 0.5, -1.0, 1.0)
	f_yaw += _bal_s * (clampf(-_cx * 22.0, -0.4, 0.4) + 0.22 * sin(_t * 5.3) * sin(_t * 1.7))
	# on a wall it's the counterweight: swings out against the hips as they sway off the grips
	f_yaw += clampf(-_hang_p.x * 28.0 - _hang_pv.x * 1.5, -0.6, 0.6) * climb
	f_yaw = clampf(f_yaw, -1.2, 1.2)
	# the kick's jolt doesn't throw the tail about (it would whip through the wall)
	f_yaw *= 1.0 - kick_w
	f_pitch *= 1.0 - kick_w
	if kick_w > 0.0:
		for i in TAIL_N:
			_tp[i] *= 1.0 - kick_w
			_ty[i] *= 1.0 - kick_w
			_tpv[i] *= 1.0 - kick_w
			_tyv[i] *= 1.0 - kick_w
	_twitch_t -= dt * (1.0 + maxf(crouch, charge) * 3.0)
	if _twitch_t < 0.0 and not remote_life:
		_twitch_t = randf_range(1.2, 4.0)
		var imp := randf_range(-7.0, 7.0)
		_twitch(imp)
		_log(["t", imp])
	var sub := 2
	var h := dt / sub
	for _s in sub:
		var pp := 0.0
		var py := 0.0
		for i in TAIL_N:
			var fi := float(i) / (TAIL_N - 1)
			var k := lerpf(300.0, 75.0, fi)
			var c := lerpf(28.0, 8.0, fi)
			var tp_t := f_pitch * (0.25 + fi * 0.5) + pp * 0.88
			var ty_t := f_yaw * (0.25 + fi * 0.5) + py * 0.88
			_tpv[i] += ((tp_t - _tp[i]) * k - _tpv[i] * c) * h
			_tyv[i] += ((ty_t - _ty[i]) * k - _tyv[i] * c) * h
			_tp[i] = clampf(_tp[i] + _tpv[i] * h, -1.3, 1.3)
			_ty[i] = clampf(_ty[i] + _tyv[i] * h, -1.3, 1.3)
			pp = _tp[i]
			py = _ty[i]

	# question mark tip: a relaxed walking cat hooks the end of its tail forward
	var qm := move_amt * ww / maxf(ww + wt + wg, 0.001) * (1.0 - maxf(crouch, charge)) * (1.0 - _air_w) * nc
	var p := to_local(tail_base.global_position)
	var pb := global_transform.basis.orthonormalized().inverse() * tail_base.global_transform.basis.orthonormalized()
	var lash := 1.0 + charge * 2.5
	var tail_floor := on_floor and climb < 0.1 and clamber < 0.1 and _air_w < 0.1
	var floor_y := _hgy + 0.011 * float(S_.tail_r)
	var curl := 0.0
	for i in TAIL_N:
		var fi := float(i) / TAIL_N
		if i >= TAIL_N - 4:
			curl += 0.42 * qm
		var a := _tail_p[0] + _tail_p[1] * i + curl + _tp[i]
		var y := _tail_p[4] * i + sin(_t * _tail_p[3] * TAU - i * 0.55) * _tail_p[2] * lash * (0.3 + fi) + _ty[i]
		var dir := pb * Vector3(sin(y) * cos(a), sin(a), cos(y) * cos(a))
		var np := p + dir * TAIL_SEG
		# the tail lies on the floor, it does not go through it
		if tail_floor and np.y < floor_y:
			np.y = floor_y
			np = p + (np - p).normalized() * TAIL_SEG
		elif climb > 0.5 and np.y < 0.014:
			# nor through the wall it's climbing (rig y = 0 is the wall face)
			np.y = 0.014
			np = p + (np - p).normalized() * TAIL_SEG
		tail_segs[i].transform = LowPoly.seg_xform(p, np)
		tail_joints[i].position = np
		p = np
