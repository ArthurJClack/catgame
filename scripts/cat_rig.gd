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
# behaviours + parkour (all 0..1 blends set by the owner)
var rear := 0.0          # up on the hind legs (scratching, peeking)
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
var _swat_t := -1.0
var _swat_i := 1
var _swat_target := Vector3.ZERO
var _gait_setup := false

# ---------------- model style ----------------
## every style is a different take on the blocky low poly cat: its own
## proportions, cross sections and low poly fur trick. the animation rig is shared.
const STYLES := {
	# block base: flat painted facets
	"block_black":     {"label": "block black cat", "base": "block", "sides": 4, "head": 1.02, "leg": 1.02, "girth": 0.96, "len": 1.02, "ear": 1.1, "tail_r": 0.95, "tail_len": 1.12, "muzzle": 1.0, "fur": "painted",
		"coat": {"fur": Color(0.075, 0.075, 0.085), "dark": Color(0.04, 0.04, 0.05), "belly": Color(0.1, 0.1, 0.115), "eye": Color(1.0, 0.86, 0.12), "pattern": "solid", "socks": false}},
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
var F_LO := 0.098
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
	var L: float = S_.len
	var Lg: float = S_.leg
	var Gi: float = S_.girth
	BODY_H = 0.215 * (0.3 + 0.7 * Lg)
	F_UP = 0.105 * Lg
	F_LO = 0.098 * Lg
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
	_body_part(pivot, "torso", Vector3(0, -0.002, 0.0), Vector3(0.092 * Gi, 0.11 * Gi, 0.16 * L), Vector3.ZERO, 0.0, "mid")
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
		# toes
		for k in 3:
			var tm := LowPoly.part(leg.paw, LowPoly.box(), pawc, Vector3((k - 1) * 0.0105, -0.001, -0.018), Vector3(0.0095, 0.014, 0.013))
			_style_mat(tm)
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
			if lower:
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
	var muzzle_col := belly if pattern != "solid" else fur.lightened(0.1)
	var mzs: float = S_.get("muzzle", 1.0)
	var mz := LowPoly.part(head, LowPoly.box(), muzzle_col, Vector3(0, -0.019, -0.027 - 0.013 * mzs), Vector3(0.036, 0.024, 0.026 * mzs))
	_style_mat(mz)
	var ch := LowPoly.part(head, LowPoly.box(), muzzle_col, Vector3(0, -0.031, -0.032), Vector3(0.022, 0.012, 0.02))
	_style_mat(ch)
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
			var w := LowPoly.part(head, LowPoly.box(0.0), Color(0.95, 0.95, 0.92), Vector3.ZERO, Vector3.ONE)
			var a := Vector3(side * 0.018, -0.018 + k * 0.004, -0.045)
			var b := a + Vector3(side * 0.06, -0.012 + k * 0.01, 0.012 + k * 0.004)
			w.transform = Transform3D(LowPoly.seg_xform(b, a).basis * Basis().scaled(Vector3(0.0012, 1, 0.0012)), (a + b) * 0.5)


## hide the visible model but keep its shadow (first person body)
func set_shadow_only(v: bool) -> void:
	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if v else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _process(dt: float) -> void:
	if not _built or dt <= 0.0:
		return
	animate(minf(dt, 0.05))


## one quick swat with a fore paw (0 = left, 1 = right) at a world space point within reach:
## winds out to its own side (0.07 s), whips across to the target (hits at about 0.12 s,
## there by 0.15 s), back on the ground by 0.32 s. the other three paws keep standing
func swat(side: int, target: Vector3) -> void:
	if climb > 0.5 or clamber > 0.5:
		return
	_swat_i = clampi(side, 0, 1)
	_swat_target = target
	_swat_t = 0.0


func is_swatting() -> bool:
	return _swat_t >= 0.0


func _setup_gait() -> void:
	_gait_setup = true
	gait.rig = self
	gait.max_stance = MAX_STANCE * 0.64
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

	# airborne blend + landing springs. cats land front first: the forelegs
	# take the hit, the chest dips nose down, then the hinds come down after
	if on_floor:
		if not _prev_floor:
			var imp := clampf(-_vy_prev, 0.0, 8.0)
			_land_v -= imp * 0.22
			_land_fv -= imp * 0.34
		_air_timer = 0.0
	else:
		if _prev_floor:
			_air_vy_max = 0.0
			if drive_velocity.y > 0.8:
				gait.takeoff()
		_air_vy_max = maxf(_air_vy_max, absf(_vy))
		_air_timer += dt
	_prev_floor = on_floor
	var air_target := 1.0 if _air_timer > 0.03 else 0.0
	_air_w = move_toward(_air_w, air_target, dt * (9.0 if air_target > _air_w else 14.0))
	_land_v += (-_land * 190.0 - _land_v * 17.0) * dt
	_land += _land_v * dt
	_land_fv += (-_land_f * 330.0 - _land_fv * 21.0) * dt
	_land_f += _land_fv * dt

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
	track *= 1.0 + climb * 0.4 + loaf * 0.1 - pin * 0.5
	var yb := Basis(Vector3.UP, yaw_off)
	var homes := []
	for i in 4:
		var home: Vector3 = HOME[i]
		home.x *= track
		if i < 2:
			home.z = lerpf(home.z, -0.115 * pelvis_z / 0.095, sit)
			home.z -= stretch * 0.15
			home.z = lerpf(home.z, -0.085 * pelvis_z / 0.095, loaf)
		else:
			home.z = lerpf(home.z, 0.035, sit)
			home.z += crouch * 0.02
			home.z = lerpf(home.z, 0.07 * pelvis_z / 0.095, loaf)
			home.z += rear * 0.02
		homes.append(yb * home)
	var all_free := (not on_floor) or climb > 0.02 or clamber > 0.02 or not use_planting
	var want_free := [all_free, all_free, all_free, all_free]
	var gxf := Transform3D(gb, gx.origin)
	gait.update(dt, gxf, drive_velocity * nc, _yaw_rate, homes, want_free, lift_amt, on_floor)
	if climb > 0.0:
		gait.phase = fposmod(gait.phase + climb * (1.5 + 1.4 * speed_s) * move_amt * dt, 1.0)
	phase = gait.phase
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
	_chest_dy = LowPoly.damp(_chest_dy, dy[0], 28.0, dt)
	_pelvis_dy = LowPoly.damp(_pelvis_dy, dy[1], 28.0, dt)
	var plantw := (1.0 - _air_w) * nc * (1.0 - clamber)
	_fgy = LowPoly.damp(_fgy, clampf(gy[0], -0.12, 0.14) * plantw, 12.0, dt)
	_hgy = LowPoly.damp(_hgy, clampf(gy[1], -0.12, 0.14) * plantw, 12.0, dt)
	# lean over the paws that are carrying the weight
	_cx = LowPoly.damp(_cx, (cx_sum / cx_w if cx_w > 0.01 else 0.0) * 0.45 * plantw, 9.0, dt)
	var span := absf((HOME[0] as Vector3).z) + absf((HOME[2] as Vector3).z)
	var gait_pitch := atan2((_chest_dy + _fgy) - (_pelvis_dy + _hgy), span)

	var air_pitch := clampf(_vy * 0.065, -0.42, 0.42) * _air_w * nc
	var flex := (wg * 0.3 * sin(p2 + 0.3) + wb * 0.32 * sin(p2 + 1.2)) * (1.0 - _air_w) * move_amt
	var gal_bob := wg * 0.012 * sin(p2 + 0.7) * move_amt + wb * 0.012 * sin(p2) * move_amt
	# stretched in air when rising, curled when coming down
	var air_flex := clampf(_vy * 0.04, -0.15, 0.15) * _air_w
	# rearing up rotates the spine about the hips (scratching, hanging off a ledge)
	var pull_e := smoothstep(0.3, 1.0, clamber_pull)
	var ra := rear * 1.02 + clamber * lerpf(1.3, 0.0, pull_e)
	var hz := pelvis_z
	var base_y := BODY_H - crouch * 0.085 - charge * 0.03 - sit * 0.075 + gal_bob * (1.0 - _air_w) - _land * 0.035 - _land_f * 0.012 - stretch * 0.02 - climb * 0.07
	base_y += (_chest_dy + _pelvis_dy) * 0.5 + (_fgy + _hgy) * 0.5
	base_y = lerpf(base_y, BODY_H * 0.4 + (_fgy + _hgy) * 0.5, loaf)
	pivot.position.y = base_y + hz * sin(ra)
	pivot.position.z = -sit * 0.035 + hz * (1.0 - cos(ra)) - clamber * (1.0 - pull_e) * 0.15 + stretch * 0.03
	pivot.rotation.x = air_pitch + sit * 0.62 - charge * 0.05 + gait_pitch * (1.0 - sit) - stretch * 0.36 - _land_f * 0.32 - pin * 0.24 + ra
	pivot.position.x = _cx
	pivot.rotation.y = yaw_off
	# lean into turns at speed
	pivot.rotation.z = LowPoly.damp(pivot.rotation.z, clampf(_yaw_rate * speed_s * 0.02, -0.28, 0.28) * (1.0 - _air_w) * nc, 6.0, dt)
	chest.rotation.x = flex - air_flex + _land_f * 0.1
	chest.position.y = 0.012 - _land_f * 0.022 - stretch * 0.03
	pelvis.rotation.x = -flex + air_flex + sit * 0.25 + stretch * 0.1
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
	# spine curls into turns: chest leads, hips follow
	var twist := clampf(_yaw_rate * 0.05, -0.3, 0.3) * nc
	chest.rotation.y = -yaw_off * 0.35 + twist * 0.5 + _yaw_c
	chest.rotation.z = _roll_c
	# butt wiggle before a pounce
	pelvis.rotation.z = sin(_t * 19.0) * 0.14 * charge + _roll_p
	pelvis.rotation.y = sin(_t * 19.0) * 0.06 * charge + yaw_off * 0.2 - twist * 0.5 + _yaw_p
	# breathing (slower + deeper when loafing)
	var br := 1.0 + sin(_t * lerpf(2.4, 1.5, loaf)) * lerpf(0.012, 0.02, loaf) * (1.0 - move_amt * 0.5)
	chest.scale = Vector3(br, br, 1.0)

	# ---------- head: held still in space while the body works under it ----------
	# whatever the chest does quickly (bob, sway, twist) the neck takes out, so only slow
	# moves reach the head. in a stalk it is almost frozen
	var cpos := gxf.affine_inverse() * chest.global_position
	if not _chest_f_init:
		_chest_f_init = true
		_chest_f = cpos
	_chest_f = LowPoly.damp3(_chest_f, cpos, lerpf(5.0, 2.5, crouch), dt)
	var dev := (cpos - _chest_f) * (1.0 - _air_w) * nc
	var nl := 0.085
	var stab_p := clampf(dev.y / nl, -0.3, 0.3)
	var stab_y := clampf(dev.x / nl, -0.3, 0.3)
	var body_pitch := pivot.rotation.x + chest.rotation.x
	var body_yaw := pivot.rotation.y + chest.rotation.y
	var turn_lead := clampf(_yaw_rate * 0.06, -0.35, 0.35) * nc
	var lick_bob := sin(_t * 21.0) * 0.07 * g_lick
	neck.rotation.x = -body_pitch * 0.55 - stab_p + look_pitch * 0.35 - crouch * 0.34 - wg * 0.25 + stretch * 0.3 - pin * 0.35 + scratch * 0.15 - g_lick * 0.42 - g_wipe * 0.15 - loaf * 0.15 + climb * 0.1
	head.rotation.x = -body_pitch * 0.45 + stab_p + look_pitch * 0.65 + crouch * 0.2 + wg * 0.12 + stretch * 0.25 - g_lick * 0.38 + lick_bob - g_wipe * 0.2
	neck.rotation.y = -body_yaw * 0.5 + stab_y + look_yaw * 0.4 + turn_lead + g_lick * 0.25
	head.rotation.y = -body_yaw * 0.5 - stab_y + look_yaw * 0.6 + turn_lead * 0.6 + g_lick * 0.3
	head.rotation.z = -(pivot.rotation.z + chest.rotation.z) * 0.9 + g_lick * 0.25 + g_wipe * 0.4
	# ears: forward + up when hunting, flattened back at speed or hanging on, follow the gaze
	_ear_t -= dt
	if _ear_t < 0.0:
		_ear_t = randf_range(2.0, 6.0)
		_ear_flick[randi() % 2] = 1.0
	var ear_fwd := maxf(crouch, charge) * 0.35 + scratch * 0.1
	var ear_back := wg * 0.55 + clamber * 0.45 + climb * 0.25 + g_lick * 0.3
	for i in ears.size():
		var side := -1.0 if i == 0 else 1.0
		_ear_flick[i] = move_toward(_ear_flick[i], 0.0, dt * 6.0)
		var fk := sin(_ear_flick[i] * PI) * 0.5
		ears[i].rotation.x = -0.15 - ear_fwd + ear_back * 0.6 - fk * 0.6
		ears[i].rotation.z = side * (-0.32 - ear_back * 0.55 + ear_fwd * 0.2 - fk)
		ears[i].rotation.y = side * fk * 0.6 + look_yaw * 0.35
	# blink, half closed eyes when loafing / grooming
	_blink_t -= dt
	var eye_y := 1.0 - loaf * 0.6 - groom * 0.45
	if _blink_t < 0.0:
		eye_y = 0.1
		if _blink_t < -0.11:
			_blink_t = randf_range(1.5, 5.0)
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
	var rise := clampf(_vy / 3.5, -1.0, 1.0)
	var lp := to_local(ledge_world) if clamber > 0.0 else Vector3.ZERO
	var claws := maxf(maxf(maxf(scramble, slip_claws), scratch), maxf(climb, clamber))
	claws = maxf(claws, maxf(pin, _air_w * hs * clampf(rise + 0.8, 0.0, 1.0)))
	claws_out = LowPoly.damp(claws_out, claws, 14.0, dt)
	if (_swat_t >= 0.0 and _swat_t < 0.26) or claw_on:
		claws_out = maxf(claws_out, 1.0)
	for i in 4:
		var front := i < 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var home: Vector3 = homes[i]
		var fw: float = gait.free_w[i]
		var pp := _paw_pose(i)
		_prot_s[i] = LowPoly.damp(_prot_s[i], pp[0], 38.0, dt)
		_heel_s[i] = LowPoly.damp(_heel_s[i], pp[1], 38.0, dt)
		var foot: Vector3 = fl[i]
		var prot: float = _prot_s[i]
		var heel: float = _heel_s[i]
		var load: float = pp[2]
		if fw > 0.0:
			# posed by the rig: standing under the hips, or the bound up a wall
			var ff := home
			var fprot := 0.0
			var fheel := 0.0
			if climb > 0.0:
				var r := _gait_foot(3, i, home, lift_amt * move_amt)
				ff = home.lerp(r[0], climb)
				fprot = float(r[1]) * climb * move_amt
				fheel = float(r[2]) * climb * move_amt
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
			else:
				var push_pose := Vector3(side * 0.05, 0.05, 0.3 + hs * 0.05)
				var tuck_pose := Vector3(side * 0.05, 0.03, 0.08)
				af = tuck_pose.lerp(push_pose, clampf(rise, 0.0, 1.0))
				arot = lerpf(-0.2, -1.1, clampf(rise, 0.0, 1.0))
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
			foot = foot.lerp(yb * af, aw)
			prot = lerpf(prot, arot, aw)
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
				foot = foot.lerp(Vector3(side * 0.028, 0.004, home.z + 0.02), loaf)
				prot = lerpf(prot, -1.9, loaf)
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
				else:
					var u := smoothstep(0.0, 1.0, (_swat_t - 0.15) / 0.17)
					sw_p = strike.lerp(foot, u)
					sw_p.y += sin(PI * u) * 0.02
					sw_r = lerpf(0.55, prot, u)
				foot = sw_p
				prot = sw_r
			fp_foot[i] = foot - Vector3((HOME[i] as Vector3).x * track, 0.0, (HOME[i] as Vector3).z)
			fp_down[i] = gait.mode[i] == CatGait.PLANTED
		else:
			if loaf > 0.0:
				heel = lerpf(heel, -0.95, loaf)
			if stretch > 0.0:
				heel += stretch * 0.25
			if clamber > 0.0:
				# hind paws scrabble on the wall face, then step up onto the top
				var hip_l := to_local(pelvis.to_global(Vector3(HIND_HIP.x * side, HIND_HIP.y, HIND_HIP.z)))
				var scr := sin(_t * 17.0 + side * 1.7) * (1.0 - clamber_pull)
				var wt_p := Vector3(side * 0.05, hip_l.y - H_TH * 0.95 + 0.035 * scr, lp.z + 0.012 + 0.014 * maxf(scr, 0.0))
				var hw := clamber * (1.0 - smoothstep(0.55, 0.95, clamber_pull))
				foot = foot.lerp(wt_p, hw)
				heel = lerpf(heel, 0.35, hw)
				prot = lerpf(prot, 1.35, hw)
		_solve_leg(i, foot, side, prot, heel, load)
		if leg_claws.size() > i:
			var cl: Node3D = leg_claws[i]
			var cs := clampf(claws_out * (1.0 if front else climb + clamber), 0.0, 1.0)
			cl.visible = cs > 0.05
			cl.scale = Vector3(1, 1, maxf(cs, 0.05))

	# ---------- tail ----------
	_update_tail(dt, ww, wt, wg, move_amt)


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
		# hock rises and the weight rolls onto the toes before push off
		heel = smoothstep(0.5, 1.0, s) * 0.45 * mv
		prot = -smoothstep(0.75, 1.0, s) * 0.4 * mv
	return [prot, heel, lerpf(0.6, sin(PI * s), mv)]


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
	var R := Basis(Vector3.RIGHT, prot)
	var rel := global_transform.basis.orthonormalized().inverse()
	if i < 2:
		# shoulder blade: hangs off the top of the chest and swings with the leg, so the
		# shoulder joint travels forward and back with the paw (a longer working leg).
		# under load the chest sinks between the blades and they poke up above the back
		var cb := rel * chest.global_transform.basis.orthonormalized()
		var top_c := Vector3(FRONT_SHOULDER.x * side * 0.8, 0.042, FRONT_SHOULDER.z + 0.04)
		var rest := Vector3(FRONT_SHOULDER.x * side, FRONT_SHOULDER.y, FRONT_SHOULDER.z) - top_c
		var top := to_local(chest.to_global(top_c))
		var wrist_t := foot + R * Vector3(0, 0.022, 0.006)
		var reach := (cb.inverse() * (wrist_t - top))
		var limb_a := atan2(-reach.z, maxf(-reach.y, 0.02))
		_scap[i] = clampf(limb_a * 0.6, -0.5, 0.55)
		var sb := Basis(Vector3.RIGHT, _scap[i])
		var rise := load * 0.012 + crouch * 0.016
		top += cb * Vector3(0, rise, 0)
		var sh := top + cb * (sb * rest)
		var hint := Vector3(0, -0.2 - rear * 0.9 - clamber * 0.6, 1.0)
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
		leg.paw.position = wrist + R * Vector3(0, -0.012, -0.012)
		leg.paw.basis = R
	else:
		var hip := to_local(pelvis.to_global(Vector3(HIND_HIP.x * side, HIND_HIP.y, HIND_HIP.z)))
		var theta := lerpf(1.1, 0.7, crouch)
		theta = lerpf(theta, 0.12, sit)
		theta = lerpf(theta, 1.3, rear)
		theta += heel
		if _air_w > 0.0:
			theta = lerpf(theta, lerpf(0.9, 0.3, clampf(_vy / 3.5, 0.0, 1.0)), _air_w * (1.0 - climb))
		theta = clampf(theta, 0.05, 1.65)
		var hock_t := foot + Vector3(0, H_MT * sin(theta), H_MT * cos(theta))
		var hd := (hock_t - hip).length()
		gait.stretch[i] = hd / (H_TH + H_SH)
		var hover := hd - (H_TH + H_SH - 0.004)
		if hover > 0.0:
			hip += (hock_t - hip) / hd * minf(hover, 0.02)
		var r := LowPoly.ik2(hip, hock_t, H_TH, H_SH, Vector3(0, 0.1, -1.0))
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
	var climbp := PackedFloat32Array([0.1, 0.0, 0.08, 1.4, 0.0])
	var rearp := PackedFloat32Array([-0.95, 0.05, 0.08, 1.2, 0.0])
	var hangp := PackedFloat32Array([-1.05, 0.02, 0.22, 1.7, 0.0])
	var strp := PackedFloat32Array([0.75, -0.02, 0.04, 1.0, 0.0])
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
		v = lerpf(v, climbp[k], climb)
		v = lerpf(v, hangp[k], clamber * (1.0 - clamber_pull))
		target[k] = v
	for k in 5:
		_tail_p[k] = LowPoly.damp(_tail_p[k], target[k], 5.0, dt)

	# inertia: accelerating forward / up makes the tail trail back and droop,
	# lateral accel + turning swing it out. the chain springs follow their parent
	# with a lag so motion rolls down the tail as a whip, with a floppy tip.
	var f_pitch := clampf(_acc.z * 0.02 - _acc.y * 0.03, -0.7, 0.7)
	var f_yaw := clampf(-_acc.x * 0.025 - _yaw_rate * 0.14, -1.0, 1.0)
	_twitch_t -= dt * (1.0 + maxf(crouch, charge) * 3.0)
	if _twitch_t < 0.0:
		_twitch_t = randf_range(1.2, 4.0)
		var imp := randf_range(-7.0, 7.0)
		for j in range(TAIL_N - 3, TAIL_N):
			_tyv[j] += imp * (j - TAIL_N + 4) / 3.0
			_tpv[j] += absf(imp) * 0.4
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
	var curl := 0.0
	for i in TAIL_N:
		var fi := float(i) / TAIL_N
		if i >= TAIL_N - 4:
			curl += 0.42 * qm
		var a := _tail_p[0] + _tail_p[1] * i + curl + _tp[i]
		var y := _tail_p[4] * i + sin(_t * _tail_p[3] * TAU - i * 0.55) * _tail_p[2] * lash * (0.3 + fi) + _ty[i]
		var dir := pb * Vector3(sin(y) * cos(a), sin(a), cos(y) * cos(a))
		var np := p + dir * TAIL_SEG
		tail_segs[i].transform = LowPoly.seg_xform(p, np)
		tail_joints[i].position = np
		p = np
