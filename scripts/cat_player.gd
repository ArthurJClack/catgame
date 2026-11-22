class_name CatPlayer
extends CharacterBody3D
## first person cat controller. movement shooter feel, real cat numbers:
##   stalk 0.7 m/s, trot 3.2 m/s, canter 6 m/s (hold shift), gallop up to 11 m/s (double tap shift) (~40 km/h, real cats top out ~48)
##   hop 1.0 m, charged pounce up to 1.8 m (real cats clear ~1.5-1.8 m, ~5x their height)
##   gravity 9.8, 1 wall kick per airtime, wall scramble. real_move: grip per surface, jumps take a push, no air steering
## parkour (the easy part): hold right mouse, look at where you want to be, let go.
##   the cat crouches, wiggles and leaps on a real ballistic arc that lands exactly there.
##   look at the side of something and it finds the top. too high to land on? it leaps
##   to grab the edge and hauls itself up (clamber). low ledges are hopped up automatically.
##   jump into anything rough (cat tree post, scratching post, curtains) holding W to climb it.
## scratch: hold F facing a wall / couch / post. pounce (the only one): hold space past a hop
##   (_space_filter) to crouch + aim, let go to launch; forepaws slam down and pin what's under them.
## controls: wasd move, shift canter (double tap = gallop), ctrl/c stalk, space jump/kick, q / mouse3 aim leap,
## f scratch, mouse1 / mouse2 left / right paw (tap swat, hold rake / claw hook),
## g / mouse5 grab (pin it with both paws, hold), alt / mouse4 dodge (cat_combat.gd: attacks are committed),
## v third person, esc mouse, x / caps lock walk
## momentum: speed builds with power-limited accel and coasts off (consts under "momentum"), turn rate drops with speed
## gamepad: cat_pad.gd, merged in _read_input. stick tilt -> speed_for_tilt() (creep / walk / trot)

const G := 9.8
const STALK_SPEED := 0.7
const TROT_SPEED := 3.2
const SPRINT_SPEED := 11.0
const CANTER_SPEED := 6.0
const DOUBLE_TAP := 0.3
const FRICTION := 5.0
# ---- momentum: the cat has weight. speed builds and bleeds instead of snapping ----
const WALK_SPEED := 1.0       # real cats walk ~0.7-1.0 m/s
const CREEP_SPEED := 0.25     # the slowest the stick (just past the deadzone) asks for
const WALK_TILT := 0.45       # keyboard walk (hold x / caps lock) = this much stick
const PUSH_ACCEL := 9.0       # m/s2 the legs can shove the body from a stand
const PUSH_POWER := 24.0      # push fades as speed climbs (accel ~ power / v): trot in ~0.4 s, gallop ~2.5 s
const COAST_DECEL := 3.0      # let go of everything: the body rolls on and the legs soak it up
const COAST_DRAG := 0.45      #   + this per m/s (gallop to stand ~1.5 s / ~6 m, walk ~0.25 s)
const GAIT_DOWN_DECEL := 6.5  # still going but asking for a slower gait: stride shortens over ~1 s
const GAIT_DOWN_DRAG := 0.3
const BRAKE_DECEL := 11.0     # pushing the other way / dropping to a crouch: paws dig in (grip caps it, so it skids)
const TURN_RATE_SLOW := 10.0  # body turn rad/s at a stand
const TURN_RATE_FAST := 2.4   #   and at full gallop: a running cat carves wide arcs
const TURN_ASK := 48.0   # sideways accel the cat asks for when carving a turn (grip caps it)
const AIR_ACCEL := 60.0
const AIR_WISH_CAP := 0.9
const HOP_HEIGHT := 1.0
# space (human input, _space_filter): tap = hop, hold longer = higher hop, hold long enough =
# pounce mode (the aim line shows; let go to pounce, cat_combat.gd)
const HOP_TAP := 0.12          # let go before this = plain hop
const POUNCE_HOLD := 0.45      # held this long on the ground = pounce mode
const HOP_CHARGE_MUL := 1.6    # a hop let go just before pounce mode goes this much higher (1.6 m)
const HOP_TAP_MUL := 0.14      # a plain tap of space (no hold) is a tiny hop (~14 cm), holding builds it up
var _sp_state := 0             # 0 up, 1 held on the ground, 2 held in the air, 3 pounce mode
var _sp_t := 0.0
var _hop_charge := 0.0
var _hop_mul := 1.0
const POUNCE_MIN := 0.6
const POUNCE_MAX := 1.8
const CHARGE_TIME := 0.45
const KICK_UP := 4.4
const KICK_OUT := 3.0
const MAX_KICKS := 1           # one wall kick per jump (touch the floor to get it back)
const KICK_PLANT := 0.085     # paws on the wall before the push (real cats: ~0.08-0.15 s of wall contact)
const NOSE_REACH := 0.29      # nose ahead of the capsule centre (x style length), for the clip guard
const RUMP_REACH := 0.2       # rump behind it (the tail is allowed to brush things)
const RADIUS := 0.085
const STAND_H := 0.27
const CROUCH_H := 0.17
const EYE_STAND := 0.25
const EYE_CROUCH := 0.14
const LEAP_RANGE := 3.2       # horizontal reach of an aimed leap
const MANTLE_MAX := 0.3       # ledges up to this are just hopped onto
const STEP_MOUNT := 0.23      # walking into something up to this high (~chest, 22 cm + slack) steps up onto it by itself
const CLAMBER_MAX := 0.85     # up to this above the feet: grab with the forepaws + haul up
const HANG := 0.40            # ledge height above the feet while hanging
const CLIMB_SPEED := 1.25
const SCRATCH_DIST := 0.115

var fur := Color(0.86, 0.52, 0.24)
var fur_dark := Color(0.58, 0.30, 0.12)
var pattern := "tabby"
var style := "block_black"
var yaw := 0.0
var pitch := 0.0
var mouse_sens := 0.0022
var invert_y := false        # settings (game_settings.gd)
var calm_cam := false        # settings: head bob off, the fp camera glides instead of riding every step
var _calm_y := 0.0
## stairs / step ups / curbs: the body pops up (step_up glide, floor snap) or hops up (quick mantle)
## a step at a time, the camera's height glides along a spring instead (every view). false = old
var step_cam := true
const STEP_CAM_W := 18.0       # spring rate (rad/s): a 17 cm step settles in ~0.2 s
const STEP_CAM_SOFT := 0.09    # lag (m) past which the spring stiffens up
const STEP_CAM_V_TAU := 0.09   # climb rate low pass (s): averages a flight of steps into one slope
var step_cam_off := 0.0        # camera height minus body height (m), this physics tick
var _sc_off_prev := 0.0
var _sc_y := 0.0
var _sc_v := 0.0
var _sc_tv := 0.0
var _sc_body_y := 0.0
var _sc_ok := false
var _sc_stairs := false
var _hs := Vector4.ZERO   # head cam stair spring: y, v, target v, last raw y
var _hs_ok := false
var _hs_floor := -INF
var _hs_hv := Vector3.ZERO
var _hs_last := Vector3.INF
var _sc_air := 0.0
var _sc_jumped := false
var _sc_act := 0.0
var _sc_ground_t := 0.0
var _sc_last := Vector3.ZERO
var third_person := false
var view_mode := 0            # 0 first person, 1 third person (behind), 2 orbit
var orbit_in_cycle := false   # v only flips first / third person unless the photo cam setting is on
var orb_yaw := 0.0            # where you're looking (all views). the body (yaw) turns to run where you steer
var orb_pitch := -0.35        # orbit view pitch (first/third person use pitch)
var orb_dist := 1.4
var _orb_d := 1.4
# side hops (a/d): cats don't strafe, they hop sideways
const SIDE_HOP_V := 1.8       # lateral m/s
const SIDE_HOP_UP := 1.15     # vertical m/s: ~0.23 s up, lands ~0.42 m over
const SIDE_HOP_COOL := 0.38
const BACKUP_SPEED := 0.8     # backing up is slow and careful
var _hop_cool := 0.0
var _prev_side := 0.0
var _hopped_now := false
var auto_step := true         # glide up roots / lips underfoot (run_assist.gd). the cat never jumps by itself
## steps, kerbs and stairs up to chest height are walked up and down in stride and the rig's body
## rides over them behind its paws (run_assist.gd). false = the old stop + scripted hop / little falls
static var smooth_steps := true
## speed changes and turns are pushed through the paws that are down (see the ground accel)
static var paw_drive := true
const DRIVE_MAX := 7.0
var _drive := 1.0
var _drive_avg := 2.0
## where the visible cat (rig + camera) is relative to the capsule, world space. the capsule
## still moves in jumps where it has to (onto a step); the cat seen on screen walks across
var _soft_off := Vector3.ZERO
## the body has mass: a jump's shove and a landing's stop reach the visible cat through its
## legs over a few hundredths of a second, not in one tick. `_lift` is how far the visible
## cat is above (+) or below (-) the capsule while that happens, `_lift_v` its own speed
static var soft_air := true
## going up stairs / a slope costs speed
static var climb_cost := true
const CLIMB_RATE := 1.8
var _grade_y := 0.0
var _grade_v := 0.0
## slow down for a wall dead ahead instead of running into it
static var wall_brake := true
## movement plan phase 1: one traction budget. everything the cat does to its own motion on the
## ground (push, brake, turn) has to come out of what the paws can hold on this surface: mu x g.
## the body can't swing round faster than that lets the run follow, a cat that knows its footing
## asks for just under it (and carves), and a flat out start, a thrown brake or a yanked turn
## asks for more and slides. false = the old per surface accel table (1.4 to 3 g)
static var real_move := true
const MU := {"tile": 0.45, "metal": 0.45, "wood": 0.55, "stone": 0.7, "default": 0.7, "dirt": 0.85, "hay": 0.9, "grass": 1.0, "carpet": 1.2, "rug": 1.2, "bark": 1.2}
const GRIP_REAL := 1.0        # feel dial on top of the real numbers (1.3 = a third more grip everywhere)
const SKID := 0.85            # sliding paws hold less than planted ones
## movement plan phase 3 (also behind real_move): a jump is a push, and a push takes time and
## footing. the legs load, then extend (GATHER_MIN..MAX s for a tap..full spring) before the paws
## leave the floor. the faster the run, the less time the paws are down to push up with, so a
## running jump goes long and low. and nothing in the air can change where the cat is going,
## bar a small correction (AIR_NUDGE, AIR_BUDGET m/s in all per jump, sideways only)
const GATHER_MIN := 0.04
const GATHER_MAX := 0.18
const RUN_HOP := 0.3          # share of the hop height left at a full gallop
const STAND_PUSH := 1.2       # a standing hop with the stick held goes toward it (m/s)
const AIR_NUDGE := 1.5
const AIR_BUDGET := 0.5
## movement plan phase 4 (real_move): coming down costs what the fall was worth. a cat lands on
## its forelegs and folds: up to LAND_FREE m/s (a ~1 m drop) is nothing, up to LAND_SOFT (~2.5 m)
## the legs give for a moment and it keeps most of its run, up to LAND_HARD (~6 m) it lands in a
## deep crouch and needs LAND_REC_MAX s before it can spring or sprint again, and past that it
## is hurt, more the faster it was falling (FALL_DMG_MIN at LAND_HARD .. FALL_DMG_MAX at terminal).
## pounces and stuck dodges are landings the cat set up for: no extra cost under LAND_HARD
const LAND_FREE := 4.4
const LAND_SOFT := 7.0
const LAND_HARD := 10.8
const LAND_KEEP_SOFT := 0.7
const LAND_KEEP_HARD := 0.2
const LAND_REC_SOFT := 0.15
const LAND_REC_MAX := 0.4
const FALL_TERMINAL := 27.0
const FALL_DMG_MIN := 8.0
const FALL_DMG_MAX := 60.0
var land_rec := 0.0           # legs busy soaking up a landing: no jump, no run
var last_impact := 0.0        # m/s the last landing came down at (tests, sfx)
var _gather_t := 0.0
var _gather_vy := 0.0
var _air_left := AIR_BUDGET
var _launch_hv := Vector3.ZERO   # the way the push sent it (a face it brushed on the way up doesn't cancel that)
var _hard_ask := false        # this tick the cat asked for more than the footing holds on purpose
const WALL_BRAKE := 9.0
const LIFT_UP_ACC := 60.0     # hardest the legs shove the body up / stop it, m/s^2 (~6 g)
const LIFT_DN_ACC := 40.0
const LIFT_REACH := 0.09      # legs reach down this far to meet the ground before a landing
const LIFT_SQUAT := 0.08      # and give this far under it
var _lift := 0.0
var _lift_v := 0.0
var _lift_base := NAN
var _lift_vc := 0.0
var _lift_on_prev := true
## the same sideways: a dodge's or a wall kick's shove gets the body up to speed over a few
## hundredths of a second (the visible cat trails the capsule by `_lag` meanwhile)
const LAG_ACC := 65.0
const LAG_MAX := 0.22
var _lag := Vector3.ZERO
var _lag_v := Vector3.ZERO
var _lag_vc := Vector3.ZERO
var _lag_base := Vector3.INF
var _climb_age := 0.0
var _pounce_hold := 0.0
var _vis_prev := Vector3.ZERO
var _vis_curr := Vector3.ZERO

## when set, input is read from here instead of the keyboard (used by the preview bot)
var bot := {}

var rig: CatRig
var cam: Camera3D
var cam_pivot: Node3D
var paws: PawView
var shape: CollisionShape3D
var capsule: CapsuleShape3D

var crouch_amt := 0.0
var charging := false
var charge_src := ""
var charge := 0.0
var kicks_left := MAX_KICKS
var air_time := 0.0
var ground_time := 0.0
var jump_buffer := 0.0
var jumped_this_air := false
var scramble_avail := true
var scramble_t := 0.0
var wall_normal := Vector3.ZERO
var wall_collider: Object
var wall_time := 10.0
var last_kick_normal := Vector3.ZERO
var mantle_quick := 0.0     # >0: quick step up (curb, low box), exits at this speed
var land_dip := 0.0
var _eye_bob := 0.0
var land_dip_v := 0.0
var cam_roll := 0.0
var prev_vy := 0.0
var prev_jump := false
var prev_swat := false
var prev_v := false
var fov_base := 82.0
var max_height := 0.0
var wall_sliding := false       # = sliding (kept for old tests / scripts)
# sliding down something it can't grip (smooth wall, slope too steep to stand on): fore claws drag
# out ahead, body + hind legs trail (rig side: cat_slide.gd). steering into a wall or just lying
# on a too steep slope keeps it going
var sliding := false
var slide_n := Vector3.ZERO     # surface normal (full 3d: walls and steep slopes)
var slide_head_up := true       # facing the surface / up the slope (false = going down head first)
var w_slide := 0.0
var _slide_col: Object
var _slide_seen := 10.0         # time since last touching a too steep surface
var _slide_marks: Array[Node3D] = []
var _slide_mark_last := [Vector3.INF, Vector3.INF]
var _slide_mat: StandardMaterial3D
# steady slide speed (m/s down a vertical face) by surface: slick tile goes fastest, claws
# bite into soft stuff more
const SLIDE_SPEED := {"tile": 2.1, "wood": 1.6, "dirt": 1.3, "grass": 1.2, "hay": 1.0, "carpet": 0.8, "rug": 0.8, "default": 1.5}
const SLIDE_STEEP_Y := 0.64     # normals below this are too steep to stand on (floor_max_angle 50 deg)
var last_event := ""            # what the cat last did (logs / tests only: nothing on screen)
var last_event_t := 0.0
var toast := ""                 # the only on screen text: level / system messages set by the mains
var toast_t := 99.0

# parkour state
var aim_valid := false
var aim_kind := ""            # "land" or "grab"
var aim_point := Vector3.ZERO
var aim_vel := Vector3.ZERO
var _aim_ok_age := 99.0   # time since the aim was last valid (forgives a jittery last frame)
var _aim_ok_vel := Vector3.ZERO
var _aim_ok_point := Vector3.ZERO
var _aim_ok_kind := ""
var leap_lock := false        # aimed leap in flight: no air steering, it's already on target
var stick_armed := false      # paw pounce in flight: stick the landing (no slide, no steps)
var land_stick := 0.0         # planted after a stuck landing
var pounce_air := false       # launched as a pounce/leap: pin on landing
var pounce_land := Vector3.INF # where the pounce's capsule trace says the feet come down
var _dodge_land_t := 9.0      # time since a dodge touched down (rig landing pose)
var pounce_yaw := 0.0          # the body faces the flight the whole way (paw spots are laid out on it)
var pounce_prey: Node = null   # what it's pouncing on: no collision with it till the paws are down
var _spots_t := 0.0            # paw spots stay put this long after touch down (pin pose + gait)
# everything on the side of things (free climb, hanging off an edge, grab / haul / top out /
# low ledge hop / curb step up / round a lip / push off) is cat_climb.gd. these flags are
# read only views of it (the rig, paws, sounds, tests read them); setting one false resets it
var climber: CatClimb
var climbing: bool:
	get: return climber != null and climber.is_climbing()
	set(v):
		if climber == null:
			return
		if v and not climber.is_climbing():
			climber.cling(climb_n if climb_n != Vector3.ZERO else global_transform.basis.z)
		elif not v and climber.is_climbing():
			climber.reset()
var clambering: bool:
	get: return climber != null and climber.is_clambering()
	set(v):
		if not v and climber != null and climber.is_clambering():
			climber.reset()
var mantling: bool:
	get: return climber != null and climber.is_mantling()
	set(v):
		if not v and climber != null and climber.is_mantling():
			climber.reset()
var clamber_phase: int:       # 0 grab, 1 hang, 2 pull
	get:
		if climber == null or climber.mode == CatClimb.HANG:
			return 1
		return 0 if climber.kind == "grab" else 2
var clamber_t: float:         # hang: time hanging. pull: 0..0.55 progress of the haul
	get:
		if climber == null:
			return 0.0
		return climber.hang_t if climber.mode == CatClimb.HANG else climber.progress() * 0.55
var clamber_climb: bool:      # this clamber started from a climb: w hauls up, not camera fwd
	get: return climber != null and climber.from_climb
var ledge_point := Vector3.ZERO
var ledge_n := Vector3.ZERO
var climb_n := Vector3.ZERO
var climb_cool := 0.0
var climb_face := Vector3.FORWARD   # smoothed climb_n the rig turns with (corners don't pop)
var climb_head := 0.0               # rad the body is turned on the wall toward sideways travel
var climb_side := 0.0               # -1 / 0 / 1: going left / not across / right (tests, rig)
var climb_lunge_t := 0.0
var climb_lunge_dir := Vector3.UP
var climb_wrap_t := 0.0             # pause after swinging round an edge (thin posts don't spin)
var climb_mv := Vector2.ZERO        # raw move input while on a wall (up = up, whatever the camera)
var scratching := false
var scratch_n := Vector3.ZERO
var scratch_t := 0.0
var _rake_prev := [0.0, 0.0]
var face_n := Vector3.FORWARD
var w_face := 0.0
var w_climb := 0.0
var _w_climb_v := 0.0
var _w_clamber_v := 0.0
var _w_climb_m := 0.0     # (the blends go through a smoothing stage first, then the spring: the
var _w_clamber_m := 0.0   #  body starts turning onto / off a wall without a kick)
var _w_slide_v := 0.0
var _w_slide_m := 0.0
var w_clamber := 0.0
var w_scratch := 0.0
# wall kick: plant (all four paws on the wall, body flat against it) then push + twist away
var kick_plant_t := 0.0
var kick_n := Vector3.ZERO
var w_kick := 0.0
var _kick_hv := Vector3.ZERO
var _kick_same := false
var _kick_turn_t := 0.0
var kick_dir := Vector3.ZERO      # where the push goes: the camera / steering direction, kept off the wall
var _kick_aim := Vector3.FORWARD  # camera relative steering (or the look direction) this tick
var _kick_wall_pt := Vector3.ZERO
var _kick_paws_set := 0
const KICK_LEAN := 0.32           # body tipped back toward the wall so the hind paws reach it (rad)
# clip guard: the capsule is only as wide as the cat, so its head and rump stick out
# front and back. the visible body slides back along its spine when either end would go into something
var _clip_off := 0.0
var _clip_v := 0.0

# swat / claw: left mouse = left paw, right mouse = right paw (tap swat, hold rake / claw hook,
# both = two swats), g = grab (two paw grip), space hold = pounce. the button logic lives in cat_combat.gd
const PAW_MASS := 0.25          # effective mass behind a swatting forepaw (kg)
const PAW_SPEED := 4.0          # paw tip speed at impact (m/s)
const CLAW_FORCE := 6.0         # max pull one hooked forepaw manages (N)
const SWAT_RANGE := 1.15        # how far out (from the eye) a paw strike looks for something to hit
const SWAT_HIT_NEAR := 0.18     # the strike's hitbox: a capsule along the look line from this far out...
const SWAT_HIT_FWD := 0.62      # ...to this far ahead of the eye...
const SWAT_HIT_R := 0.2         # ...this thick. it rides with the cat through the lunge (re-placed every tick)
const SWAT_LIVE := 0.08         # the hitbox stays out this long after the paw lands (catches what the lunge runs into)
var _swat_hit_t := -1.0
var _swat_live := 0.0           # > 0: the strike's hitbox is still out (see _swat_sweep)
var _swat_done: Array = []      # what this strike already hit (one hit per strike)
var _swat_rb: RigidBody3D
var _swat_side := 1.0
var prev_claw := false
var combat: CatCombat
var clawing := false
var claw_rb: RigidBody3D
var claw_local := Vector3.ZERO    # hook point in the body's local space
var claw_dist := 0.3
var claw_static := false
var claw_pt := Vector3.ZERO       # hook point on a static surface (world)
var claw_n := Vector3.UP
var claw_col: Object
var _claw_last_mark := Vector3.ZERO
var _claw_fluff := 0.0
# camera robustness
var _smooth_y := 0.0
var _tp_dist := 1.25
# render-rate camera: physics runs at a fixed tick (72 Hz on web, 144 desktop) that never
# lines up with the monitor, so the camera + visible body are interpolated between the
# last two physics positions every rendered frame, and mouse look is applied per frame
var eye_local := Vector3(0, EYE_STAND, 0)
var _phys_prev := Vector3.ZERO
var _phys_curr := Vector3.ZERO
var _rig_base := Transform3D.IDENTITY
var _interp_ok := false
var paw_anchor: Node3D
## first person = a real camera in the cat's head: it rides the rig's head bone (gait, crouch,
## rearing, climbing, pounces all move it) and you see the cat's actual chest, shoulders and
## forelegs below you. false = the old floating viewmodel paws (paw_view.gd)
var head_cam := true
var head_roll := 0.0           # roll picked up from the head bone this frame (rad)
var head_cam_blocked := false  # the head is pushed into something: the camera is held short of it
var _head_follow: Node
# hunting
var carried: Node3D = null      # prey held in the mouth
var catches := 0
var leaps := 0                   # aimed leaps taken (tutorial / stats)
var hunt_info := ""             # hud line: nearest prey while stalking
var _swat_prey: Node3D = null
var _auto_t := 0.0
var _auto_last: Object = null
var _auto_last_t := 0.0
var prev_drop := false
# grip: how hard the paws can push on what's underfoot (m/s^2 before they slip)
const GRIP := {"wood": 16.0, "tile": 14.0, "carpet": 30.0, "rug": 30.0, "grass": 24.0, "dirt": 19.0, "hay": 20.0, "default": 18.0}
var surface := "default"
var slip := 0.0
var _tear_last := Vector3.ZERO
var _tears: Array[Node3D] = []
var dust: PawDust              # dirt / dust right under a paw, only on hard pushes (paw_dust.gd)
var stamina: CatStamina        # souls style stamina bar (cat_stamina.gd)
var health: CatHealth          # hits from enemies (souls_rat.gd), nine lives (cat_health.gd)
var souls_hud: SoulsHud        # health + stamina bars, top left
var dash: CatDash              # souls style dodge: dart / side leap / whirl / backstep (cat_dash.gd)
var prev_dash := false
var lock: CatLockOn            # souls style tab lock on (cat_lock_on.gd)
var spar: CatSpar              # cat vs cat play fighting (cat_spar.gd): on while locked on to another cat
var spar_dummy := false        # set before adding: this bot is the practice cat (CatSparBrain drives it)
var prev_lock := false
var _lock_r := -1.0             # radius being circled while strafing a lock (-1 = not circling)
const LOCK_STRAFE := 0.8       # x trot: circling / strafing a locked target
const LOCK_ACCEL := 16.0       # squared up to a lock target the cat takes quick short steps, no run up
const LOCK_BACK := 0.6         # x trot: backing off a locked target (normal back up is a slow 0.25)
## the lock on target (Node3D) or null. other systems duck type this ("lock_target" in player)
var lock_target: Node3D:
	get:
		return lock.target if lock and lock.active() else null

var _aim_root: Node3D
var _aim_ring: MeshInstance3D
var _aim_dots: Array[MeshInstance3D] = []
var _paw_rings: Array[MeshInstance3D] = []   # pounce aim: where each paw comes down (LF RF LH RH)
var _marks: Array[Node3D] = []


func _ready() -> void:
	climber = CatClimb.new(self)
	# debugging: CAT_OFF=soft_air,wall_brake turns named biomechanics switches off in any scene / test
	if OS.has_environment("CAT_OFF"):
		for nm in OS.get_environment("CAT_OFF").split(","):
			for f in ["cat_player.gd", "cat_rig.gd", "cat_gait.gd", "cat_stop.gd"]:
				var sc: Script = load("res://scripts/" + f)
				if sc.get(nm) != null:
					sc.set(nm, false)
	if not spar_dummy:
		add_to_group("player")   # (the practice cat isn't "the player": wildlife etc look that up)
	GameSettings.apply_player.call_deferred(self)   # sens / fov / invert / head bob (no-op for bots)
	(func(): if bot.is_empty() or Engine.get_write_movie_path() != "": CatSfx.attach(self)).call_deferred()   # the cat's own sounds (cat_sfx.gd)
	floor_snap_length = 0.06
	floor_max_angle = deg_to_rad(50)
	safe_margin = 0.002
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = STAND_H
	shape = CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = STAND_H * 0.5
	add_child(shape)

	rig = CatRig.new()
	rig.fur = fur
	rig.fur_dark = fur_dark
	rig.pattern = pattern
	rig.style = style
	add_child(rig)
	_apply_rig_view()
	dust = PawDust.new()
	dust.player = self
	add_child(dust)
	stamina = CatStamina.new()
	stamina.player = self
	add_child(stamina)
	dash = CatDash.new()
	dash.player = self
	add_child(dash)
	combat = CatCombat.new()
	combat.player = self
	add_child(combat)
	health = CatHealth.new()
	health.player = self
	add_child(health)
	souls_hud = SoulsHud.new()
	souls_hud.player = self
	add_child(souls_hud)
	lock = CatLockOn.new()
	lock.player = self
	add_child(lock)
	spar = CatSpar.new()
	spar.player = self
	spar.dummy = spar_dummy
	add_child(spar)

	cam_pivot = Node3D.new()
	cam_pivot.position.y = EYE_STAND
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam.near = 0.01
	cam.far = 300.0
	cam.fov = fov_base
	cam_pivot.add_child(cam)
	paws = PawView.new()
	paws.fur = rig.fur
	paws.fur_dark = rig.fur_dark
	paws.pattern = rig.pattern
	paws.socks = rig.socks
	paws.sock_col = rig.belly
	paws.pad = rig.pad_color
	paws.rig = rig
	# the paws hang off a yaw-only anchor at the eye, not the camera: look up and they
	# drop out of view like real paws would, look down and you see more of them
	paw_anchor = Node3D.new()
	cam_pivot.add_child(paw_anchor)
	paw_anchor.add_child(paws)
	cam.current = true
	# runs after the rig has posed this frame, so the camera is where the head really is
	_head_follow = HeadFollow.new()
	_head_follow.player = self
	add_child(_head_follow)
	_apply_rig_view()
	_build_aim_marker()


func _build_aim_marker() -> void:
	_aim_root = Node3D.new()
	_aim_root.top_level = true
	add_child(_aim_root)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.75)
	m.no_depth_test = false
	_aim_ring = MeshInstance3D.new()
	_aim_ring.mesh = LowPoly.cyl(0.5, 0.5, 12)
	_aim_ring.material_override = m.duplicate()
	_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_root.add_child(_aim_ring)
	for k in 48:     # dense enough to read as a line: the exact path the pounce / leap flies
		var d := MeshInstance3D.new()
		d.mesh = LowPoly.box(0.0)
		d.material_override = m
		d.scale = Vector3.ONE * 0.011
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aim_root.add_child(d)
		_aim_dots.append(d)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.017
	tor.outer_radius = 0.026
	tor.rings = 16
	tor.ring_segments = 4
	for k in 4:
		var r := MeshInstance3D.new()
		r.mesh = tor
		r.material_override = m.duplicate()
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.visible = false
		_aim_root.add_child(r)
		_paw_rings.append(r)
	_aim_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not bot.is_empty():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		# browsers' pointer lock sometimes reports a bogus huge jump for one event: drop it
		if OS.has_feature("web") and rel.length() > 250.0:
			return
		if lock.active():
			lock.mouse(rel.x)    # locked: the camera stays on the target, a flick switches targets
			return
		orb_yaw -= rel.x * mouse_sens
		if invert_y:
			rel.y = -rel.y
		if view_mode == 2:
			orb_pitch = clampf(orb_pitch - rel.y * mouse_sens, -1.4, 0.6)
		else:
			pitch = clampf(pitch - rel.y * mouse_sens, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed and view_mode == 2 and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		orb_dist = clampf(orb_dist * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14), 0.45, 4.5)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


var _shift_prev := false
var _shift_last_tap := -10.0
var _galloping := false
var _swat_prev := false
var _swat_paw := 1             # the swat button alternates paws: this is the one it used last
var _int_prev := false
var _int_drop := false         # e pressed while carrying: dropped, so this hold isn't a scratch
## the rat pit (arena_main) turns this on: lock on, rakes and the health bar only exist there
## (stamina is everywhere). everywhere else the cat just moves, swats and explores. bots always get
## the full set (tests + preview films drive those systems directly)
var combat_zone := false


func combat_on() -> bool:
	return combat_zone or not bot.is_empty()
var _brake_ask := false
var _backing := false
var _turn_factor := 1.0


func _read_input() -> Dictionary:
	if not bot.is_empty():
		return bot
	# hold shift = canter. double tap shift (and keep holding) = full gallop
	var shift := CatKeys.down("run")
	var now := Time.get_ticks_msec() / 1000.0
	if shift and not _shift_prev:
		_galloping = now - _shift_last_tap < DOUBLE_TAP
		_shift_last_tap = now
	if not shift:
		_galloping = false
	_shift_prev = shift
	var mv := Vector2.ZERO
	if CatKeys.down("forward"): mv.y += 1
	if CatKeys.down("back"): mv.y -= 1
	if CatKeys.down("left"): mv.x -= 1
	if CatKeys.down("right"): mv.x += 1
	mv = mv.limit_length(1.0)
	# no walk keys any more (simplify pass): crouch is the slow, quiet sneak, a pad stick still
	# walks with a half tilt
	if mv != Vector2.ZERO:
		CatPad.last_used_pad = false
	var kb := {
		"move": mv,
		"canter": shift and not _galloping,
		"sprint": shift and _galloping,
		"crouch": CatKeys.down("crouch"),
		"jump": CatKeys.down("jump"),
		"swat": CatKeys.down("swat"),
		"grab": CatKeys.down("grab"),
		"interact": CatKeys.down("interact"),
		"toggle_view": CatKeys.down("toggle_view"),
		"dash": CatKeys.down("dash"),
		"lock_on": CatKeys.down("lock_on"),   # press = lock / unlock (cat_lock_on.gd)
	}
	# gamepad (cat_pad.gd): every action has a button, the left stick's tilt picks the speed
	var pad := CatPad.read()
	var d := CatPad.merge(kb, pad)
	# vr controllers (vr/vr_body.gd): empty in flat mode
	var vrd := CatVR.read(self)
	if not vrd.is_empty():
		d = CatPad.merge(d, vrd)
	_human_buttons(d)
	if CatKeys.blocked:
		# pause menu open (online the game keeps running): the cat stands still
		for k in d:
			d[k] = Vector2.ZERO if d[k] is Vector2 else (0.0 if d[k] is float else false)
	var sp := _space_filter(d.get("jump", false), is_on_floor(), get_physics_process_delta_time())
	d.jump = sp.jump
	d.pounce = sp.pounce
	d.hop_charge = sp.hop_charge
	d.hop_mul = sp.hop_mul
	return d


## the few human buttons -> the actions the controller (and the bots) speak:
##   swat     one button, alternates paws each press (held = that paw keeps hooking / raking)
##   interact drop what's in your mouth, otherwise scratch (held) whatever's in front
##   lock on  only in the rat pit
func _human_buttons(d: Dictionary) -> void:
	var sw: bool = d.get("swat", false)
	d.erase("swat")
	if sw and not _swat_prev:
		_swat_paw = 1 - _swat_paw
	_swat_prev = sw
	# vr: each hand's trigger / swing is that side's own paw (vr/vr_body.gd)
	d.paw_l = (sw and _swat_paw == 0) or d.get("vr_paw_l", false)
	d.paw_r = (sw and _swat_paw == 1) or d.get("vr_paw_r", false)
	d.erase("vr_paw_l")
	d.erase("vr_paw_r")
	var it: bool = d.get("interact", false)
	d.erase("interact")
	if it and not _int_prev:
		_int_drop = carried != null
	if not it:
		_int_drop = false
	_int_prev = it
	d.drop = it and _int_drop
	d.scratch = it and not _int_drop
	if not combat_on() and not (spar and spar.playmate_near()):
		d.lock_on = false   # lock on is for the rat pit, and for play fighting other cats


## space / A on the ground: hop when it's let go (higher the longer it was held), or held past
## POUNCE_HOLD = pounce mode. off the ground a press is a jump right away (wall kicks, climbing
## leap offs, scramble holds), and walking off an edge mid hold hops right then (coyote)
func _space_filter(held: bool, on_ground: bool, dt: float) -> Dictionary:
	var out := {"jump": false, "pounce": false, "hop_charge": 0.0, "hop_mul": HOP_TAP_MUL}
	match _sp_state:
		0:
			if held:
				if on_ground:
					_sp_state = 1
					_sp_t = 0.0
				else:
					_sp_state = 2
					out.jump = true
		1:
			if not on_ground:
				_sp_state = 2 if held else 0
				out.jump = true
				out.hop_charge = clampf((_sp_t - HOP_TAP) / (POUNCE_HOLD - HOP_TAP), 0.0, 1.0)
				out.hop_mul = lerpf(HOP_TAP_MUL, HOP_CHARGE_MUL, out.hop_charge)
			elif held:
				_sp_t += dt
				if _sp_t >= POUNCE_HOLD:
					_sp_state = 3
					out.pounce = true
			else:
				_sp_state = 0
				out.jump = true
				out.hop_charge = clampf((_sp_t - HOP_TAP) / (POUNCE_HOLD - HOP_TAP), 0.0, 1.0)
				out.hop_mul = lerpf(HOP_TAP_MUL, HOP_CHARGE_MUL, out.hop_charge)
		2:
			if held:
				out.jump = true
			else:
				_sp_state = 0
		3:
			if held:
				out.pounce = true
			else:
				_sp_state = 0
	return out


## 0..1 how far a held space is toward pounce mode (hud / rig gather)
func space_charge() -> float:
	return clampf(_sp_t / POUNCE_HOLD, 0.0, 1.0) if _sp_state == 1 else 0.0


var log_events := false


func _event(name: String) -> void:
	last_event = name
	last_event_t = 0.0
	if log_events:
		print("[cat] %s  pos=%s  v=%s" % [name, global_position.snapped(Vector3.ONE * 0.01), velocity.snapped(Vector3.ONE * 0.01)])


func _physics_process(dt: float) -> void:
	_phys_prev = global_position
	_sc_off_prev = step_cam_off
	_vis_prev = global_position + _vis_off()
	var inp := _read_input()
	inp = spar.filter(inp, dt)     # play fighting another cat eats the paws / grab (cat_spar.gd)
	if combat.locks_move():
		# both fore paws are holding something: a cat can't walk, hop or dodge on its hind legs alone
		inp = inp.duplicate()
		for k in ["jump", "aim", "dash", "scratch", "sprint", "canter", "crouch"]:
			inp[k] = false
		inp["move"] = Vector2.ZERO
	# the dodge reads the real stick even mid attack (a roll out of a recovery goes where you hold)
	var dodge_mv: Vector2 = inp.get("move", Vector2.ZERO)
	if combat.committed():
		# souls commitment (cat_combat.gd MOVES): mid attack the feet only creep, no jumping,
		# leaping, running or scratching until the move is over
		inp = inp.duplicate()
		for k in ["jump", "aim", "scratch", "sprint", "canter"]:
			inp[k] = false
		inp["move"] = dodge_mv * combat.move_scale()
	var prev_yaw := yaw
	var prev_pitch := pitch
	var lock_in: bool = inp.get("lock_on", false)
	if lock_in and not prev_lock:
		lock.toggle()
	prev_lock = lock_in
	lock.physics_tick(dt)
	# locked on and not running: square up to the target and strafe round it
	var lock_face: bool = lock.active() and not (inp.get("sprint", false) or inp.get("canter", false))
	if inp.has("yaw"):
		yaw = inp.yaw
	if inp.has("pitch"):
		pitch = inp.pitch
	if bot.is_empty():
		var kl := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_LEFT): kl.x += 1
		if Input.is_physical_key_pressed(KEY_RIGHT): kl.x -= 1
		if Input.is_physical_key_pressed(KEY_UP): kl.y += 1
		if Input.is_physical_key_pressed(KEY_DOWN): kl.y -= 1
		orb_yaw += kl.x * 2.4 * dt
		if view_mode == 2:
			orb_pitch = clampf(orb_pitch + kl.y * 1.6 * dt, -1.4, 0.6)
		else:
			pitch = clampf(pitch + kl.y * 1.6 * dt, -1.45, 1.45)
	var mv: Vector2 = inp.get("move", Vector2.ZERO)
	# the way a wall kick goes: where you steer relative to the camera, or where you look
	var aim_yaw: float = yaw if inp.has("yaw") else orb_yaw
	_kick_aim = Basis(Vector3.UP, aim_yaw) * (Vector3(mv.x, 0, -mv.y).normalized() if mv.length() > 0.05 else Vector3.FORWARD)
	if inp.has("yaw") and not lock.active():
		orb_yaw = yaw    # scripted bot: camera and body share one heading, old body-relative controls
		_turn_factor = 1.0
		_brake_ask = false
	else:
		# every view: wasd is relative to where you look, the cat turns to face where it's going
		# and runs forward (no strafing). standing still, the head looks around first and the
		# body only comes round once the look goes past what a neck can do
		if view_mode == 2:
			pitch = lerpf(pitch, orb_pitch * 0.5, clampf(dt * 6.0, 0, 1))
		var busy := climbing or clambering or scratching or mantling or dash.busy() or kick_plant_t > 0.0 or _kick_turn_t > 0.0 or combat.locks_move()
		var face_look: bool = charging or clawing or combat.any_down() or inp.get("scratch", false) or inp.get("aim", false)
		_turn_factor = 1.0
		_brake_ask = false
		if lock_face:
			# souls lock: the body keeps its face on the target, wasd (camera relative) becomes
			# body relative strafing. the rig angles the body into the travel and keeps the head on it
			if not busy:
				yaw += clampf(wrapf(lock.yaw_to() - yaw, -PI, PI), -12.0 * dt, 12.0 * dt)
			if mv.length() > 0.05:
				var lw := Basis(Vector3.UP, yaw).inverse() * (Basis(Vector3.UP, orb_yaw) * Vector3(mv.x, 0, -mv.y))
				mv = Vector2(lw.x, -lw.z)
			# pure a / d: hold the radius you started circling at (stepping sideways off a
			# point you keep turning to face spirals outward otherwise)
			var tr := lock.point() - global_position
			var rr := Vector2(tr.x, tr.z).length()
			if absf(mv.y) < 0.25 and absf(mv.x) > 0.3:
				if _lock_r < 0.0:
					_lock_r = rr
				mv.y += clampf((rr - _lock_r) * 2.5, -0.6, 0.6)
			else:
				_lock_r = -1.0
		elif mv.length() > 0.05 and not busy:
			var wd := Basis(Vector3.UP, orb_yaw) * Vector3(mv.x, 0, -mv.y)
			var ty := atan2(-wd.x, -wd.z)
			var diff := wrapf(ty - yaw, -PI, PI)
			# momentum: the faster it's going, the slower the body can swing round
			var spd := Vector2(velocity.x, velocity.z).length()
			var tr := lerpf(TURN_RATE_SLOW, TURN_RATE_FAST, smoothstep(0.8, SPRINT_SPEED, spd)) if is_on_floor() else TURN_RATE_SLOW
			if real_move and is_on_floor():
				# the body swings only a bit ahead of what the paws can bend the run by (v x turn rate = mu g)
				tr = minf(TURN_RATE_SLOW, 1.15 * grip_now() / maxf(spd, 0.5))
			yaw += clampf(diff, -tr * dt, tr * dt)
			# asking to go back the way it came at speed: plant the paws and brake before turning round
			_brake_ask = absf(diff) > 1.7 and spd > 1.2
			# mid turn the cat eases off (a little at speed, where it carves instead of pivoting).
			# the tilt itself stays, so the gait you asked for comes back as soon as it's lined up
			_turn_factor = clampf(1.25 - absf(diff) * lerpf(1.0, 0.5, smoothstep(2.0, SPRINT_SPEED, spd)), 0.15, 1.0)
			mv = Vector2(0, mv.length())
		elif not busy:
			var ld := wrapf(orb_yaw - yaw, -PI, PI)
			if face_look:
				yaw += clampf(ld, -12.0 * dt, 12.0 * dt)
			elif absf(ld) > 1.1:
				yaw += clampf(ld - signf(ld) * 1.1, -6.0 * dt, 6.0 * dt)
	if combat.committed():
		# committed: the body tracks a little in the wind up and is frozen while the paw's out
		var cap := combat.turn_cap() * dt
		yaw = prev_yaw + clampf(wrapf(yaw - prev_yaw, -PI, PI), -cap, cap)
	_kick_turn_t = maxf(_kick_turn_t - dt, 0.0)
	if _kick_turn_t > 0.0 and Vector2(velocity.x, velocity.z).length() > 0.5:
		# coming off a wall kick the body twists round to where it's flying, however the keys are held
		var ky := atan2(-velocity.x, -velocity.z)
		yaw += clampf(wrapf(ky - yaw, -PI, PI), -16.0 * dt, 16.0 * dt)
	if pounce_air and leap_lock and not is_on_floor():
		# a pounce flies straight: the body squares to the flight (fast) and stays on it
		yaw += clampf(wrapf(pounce_yaw - yaw, -PI, PI), -18.0 * dt, 18.0 * dt)
	rotation.y = yaw
	last_event_t += dt
	toast_t += dt
	# stamina / dodge bookkeeping. bots run with a bottomless bar unless they ask for the real one
	# stamina is everywhere again (user 2026-11-21: "put stamina back in"): only bots that
	# don't ask for the real bar run bottomless
	stamina.infinite = not bot.is_empty() and not bot.get("stamina", false)
	dash.tick(dt)
	var dash_in: bool = inp.get("dash", false)
	if dash_in and not prev_dash and combat.dodge_pressed():
		dash.press()      # mid attack it waits for the move's cancel point (combat._atk_step)
	prev_dash = dash_in
	var raw_mv: Vector2 = dodge_mv
	var dash_wish := Vector3.ZERO
	if raw_mv.length() > 0.3:
		dash_wish = Basis(Vector3.UP, orb_yaw) * Vector3(raw_mv.x, 0, -raw_mv.y)
	climb_cool = maxf(climb_cool - dt, 0.0)
	paws.look_vel = paws.look_vel.lerp(Vector2(wrapf(yaw - prev_yaw, -PI, PI), pitch - prev_pitch) / dt, clampf(dt * 20.0, 0, 1))

	var sprint: bool = inp.get("sprint", false)
	var canter: bool = inp.get("canter", false)
	# running only happens straight ahead
	if mv.y < 0.5 or absf(mv.x) > 0.3:
		sprint = false
		canter = false
	# winded (ran the bar dry): trot only until it's back up
	if not stamina.can_run():
		sprint = false
		canter = false
	var want_crouch: bool = inp.get("crouch", false)
	var jump_held: bool = inp.get("jump", false)
	var aim_in: bool = inp.get("aim", false)
	var scratch_in: bool = inp.get("scratch", false)
	var jump_pressed := jump_held and not prev_jump
	var jump_released := (not jump_held) and prev_jump
	prev_jump = jump_held
	# paws: left mouse = left paw, right mouse = right paw ("swat" = left paw for old bot scripts)
	var paw_l: bool = inp.get("paw_l", false) or inp.get("swat", false)
	var paw_r: bool = inp.get("paw_r", false)
	combat.tick(dt, paw_l, paw_r, inp.get("grab", false), inp.get("pounce", false))
	if _swat_hit_t >= 0.0:
		_swat_hit_t -= dt
		if _swat_hit_t < 0.0:
			_swat_impact()
	elif _swat_live > 0.0:
		_swat_live -= dt
		_swat_sweep()
	if clawing:
		_claw_step(dt)
	var drop_in: bool = inp.get("drop", false)
	if drop_in and not prev_drop and carried:
		_drop_carried()
	prev_drop = drop_in
	# auto swat: anything loose (or prey) right under the crosshair and in paw reach gets swatted
	_auto_t -= dt
	_auto_last_t += dt
	if bot.is_empty() and _auto_t <= 0.0 and not clawing and not combat.any_down() and not combat.busy() and _swat_hit_t < 0.0 and not (climbing or clambering or mantling or scratching or charging):
		_auto_t = 0.1
		var at := _paw_target(SWAT_RANGE * 0.85, 0.17)
		if not at.is_empty():
			var who: Object = at.get("prey") if at.get("prey") else at.get("rb")
			if who != carried and (who != _auto_last or _auto_last_t > 1.4):
				_auto_last = who
				_auto_last_t = 0.0
				_auto_t = 0.55
				combat.auto_swat()
	_update_surface()
	var tv: bool = inp.get("toggle_view", false)
	if tv and not prev_v:
		set_view((view_mode + 1) % (3 if orbit_in_cycle else 2))
	prev_v = tv

	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	# a/d on the ground = a short sideways hop (stalking: a slow sidestep). in the air
	# the full input still steers a touch. climbing etc read mv themselves
	var side := signf(mv.x) if absf(mv.x) > 0.3 else 0.0
	_hop_cool = maxf(_hop_cool - dt, 0.0)
	var ground_mv := Vector2(0.0, mv.y)
	if lock_face:
		# locked on: a/d walk round the target instead of hopping
		ground_mv = Vector2(mv.x * LOCK_STRAFE, mv.y * (LOCK_STRAFE if mv.y > 0.0 else LOCK_BACK))
	if is_on_floor() and not (mantling or clambering or climbing or scratching or charging):
		if lock_face:
			pass
		elif want_crouch_peek(inp):
			ground_mv.x = mv.x * 0.45
		elif side != 0.0 and not bot.is_empty() and not combat.committed() and _hop_cool <= 0.0 and (side != _prev_side or ground_time > 0.12) and not dash.busy() and dash.buffer <= 0.0 and stamina.spend(CatStamina.SIDE_HOP):
			_side_hop(side, fwd, right)
	_prev_side = side
	if is_on_floor():
		mv = ground_mv
		_backing = mv.y < 0.0 and not lock_face
	var wish := (fwd * mv.y + right * mv.x)
	wish.y = 0
	var wish_len := minf(wish.length(), 1.0)
	var wish_dir := wish.normalized() if wish.length() > 0.01 else Vector3.ZERO

	if climber.active() or scratching:
		dash.cancel()
	if climbing and wish_dir.length() > 0.0:
		stamina.drain(CatStamina.CLIMB, dt)
	if climber.active():
		climb_mv = mv
		climber.step(dt, mv, wish_dir, jump_pressed, want_crouch)
		_post(dt, inp)
		return
	if scratching:
		_scratch_step(dt, scratch_in, mv)
		_post(dt, inp)
		return
	if kick_plant_t > 0.0:
		_kick_plant_step(dt, wish_dir)
		_post(dt, inp)
		return

	var grounded := is_on_floor() and not _hopped_now
	_hopped_now = false
	if grounded:
		if air_time > 0.05:
			_on_land()
		air_time = 0.0
		ground_time += dt
		kicks_left = MAX_KICKS
		_air_left = AIR_BUDGET
		_launch_hv = Vector3.ZERO
		jumped_this_air = false
		scramble_avail = true
		last_kick_normal = Vector3.ZERO
		leap_lock = false
	else:
		air_time += dt
		ground_time = 0.0

	# ---------------- dodge (souls style, cat_dash.gd) ----------------
	if dash.buffer > 0.0 and charging and grounded:
		charging = false     # a dodge cancels a wind up
		charge = 0.0
		_aim_root.visible = false
	if dash.winding() or dash.try_start(dash_wish, grounded):
		dash.wind_step(dt)
		if dash.winding():
			velocity.y = minf(velocity.y, 0.0)
		move_and_slide()
		_track_walls()
		_post(dt, inp)
		return
	land_rec = maxf(land_rec - dt, 0.0)
	if land_rec > 0.0 and real_move:
		# legs folded under a landing: nothing springs or runs until they are back under it
		jump_pressed = false
		jump_held = false
		aim_in = false
		wish_len *= 0.3
	if dash.recover > 0.0:
		# landing out of a dodge: the legs are busy soaking it up
		jump_pressed = false
		jump_held = false
		aim_in = false
		wish_len *= 0.3

	# scratch: stand up against whatever is in front of you
	if scratch_in and grounded and not charging and Vector2(velocity.x, velocity.z).length() < 1.5:
		if _try_scratch():
			_post(dt, inp)
			return

	# crouch / stand (only stand if there's room)
	var crouch_target := 1.0 if (want_crouch or charging or _gather_t > 0.0 or (land_rec > LAND_REC_SOFT and real_move)) else 0.0
	crouch_target = maxf(crouch_target, space_charge() * 0.5)   # gathering for a bigger hop
	if crouch_target < crouch_amt and not _can_stand():
		crouch_target = crouch_amt
	crouch_amt = move_toward(crouch_amt, crouch_target, dt * 7.0)
	var h := lerpf(STAND_H, CROUCH_H, crouch_amt)
	capsule.height = h
	shape.position.y = h * 0.5

	var hv := Vector3(velocity.x, 0, velocity.z)

	# ---------------- jumping ----------------
	jump_buffer = maxf(jump_buffer - dt, 0.0)
	if jump_pressed:
		jump_buffer = 0.12
		_hop_charge = inp.get("hop_charge", 0.0)
		# humans: the space filter says how big (a tap is tiny). bots: plain hop scaled by charge
		_hop_mul = inp.get("hop_mul", lerpf(1.0, HOP_CHARGE_MUL, _hop_charge))
	var can_ground_jump := grounded or (air_time < 0.09 and not jumped_this_air)
	if _gather_t > 0.0:
		# legs loaded: the push ends, the paws leave the floor
		_gather_t -= dt
		if _gather_t <= 0.0:
			_gather_t = 0.0
			if can_ground_jump:
				velocity.y = _gather_vy
				if Vector2(velocity.x, velocity.z).length() < 1.0 and wish_len > 0.3:
					velocity += wish_dir * STAND_PUSH * wish_len
				jumped_this_air = true
				grounded = false
				_launch_hv = Vector3(velocity.x, 0, velocity.z)
				_event("hop")

	# hold q / mouse3 = aimed leap (movement). the one pounce lives on both paws (cat_combat.gd)
	if not charging and can_ground_jump and aim_in:
		charging = true
		_aim_ok_age = 99.0
		charge_src = "aim"
		charge = 0.0
		jump_buffer = 0.0
	if charging and not can_ground_jump:
		charging = false
		charge = 0.0
	if charging:
		charge = minf(charge + dt / CHARGE_TIME, 1.0)
		_update_aim()
		var release := false
		if charge_src == "aim":
			release = (not aim_in) or jump_pressed
		else:
			release = jump_released or not want_crouch
		if release:
			if aim_valid or _aim_ok_age < 0.2:
				_leap()
			charging = false
			jumped_this_air = true
			grounded = false
			charge = 0.0
	elif jump_buffer > 0.0 and can_ground_jump and _gather_t <= 0.0:
		# a cat always gets off the ground, but spent it's a lower hop
		var hh := HOP_HEIGHT * _hop_mul
		if not stamina.spend(CatStamina.HOP * (1.0 + _hop_charge)):
			hh = HOP_HEIGHT * 0.55
		if real_move:
			hh *= lerpf(1.0, RUN_HOP, smoothstep(TROT_SPEED + 0.3, SPRINT_SPEED, hv.length()))
			_gather_vy = sqrt(2.0 * G * hh)
			_gather_t = lerpf(GATHER_MIN, GATHER_MAX, clampf((hh - 0.14) / 1.36, 0.0, 1.0))
			if inp.has("hop_mul") and _hop_charge > 0.0:
				_gather_t = GATHER_MIN + 0.02   # a held space bar already was the crouch
			_hop_charge = 0.0
			jump_buffer = 0.0
		else:
			_hop_charge = 0.0
			velocity.y = sqrt(2.0 * G * hh)
			jumped_this_air = true
			jump_buffer = 0.0
			grounded = false
			_event("hop")
	elif jump_pressed and not grounded:
		_try_wall_kick(wish_dir)
	if not charging and not combat.aiming():
		_aim_root.visible = false

	hv = Vector3(velocity.x, 0, velocity.z)
	var hv_before := hv

	# ---------------- horizontal movement ----------------
	# how hard the stick (or keys) push picks the gait: nudge = creep, half = walk, full = trot.
	# run buttons on top of that need a near full push
	var target_speed := speed_for_tilt(wish_len)
	if want_crouch:
		target_speed = minf(target_speed, STALK_SPEED * clampf(wish_len / 0.7, 0.35, 1.0))
	elif sprint and wish_len > 0.8:
		target_speed = SPRINT_SPEED
	elif canter and wish_len > 0.8:
		target_speed = CANTER_SPEED
	if _backing:
		target_speed = minf(target_speed, BACKUP_SPEED)
	if charging:
		target_speed = 0.0
	if grounded:
		target_speed *= _turn_factor
		if climb_cost:
			# running uphill is work: a cat climbs at most about 1.8 m/s straight up, so stairs
			# and steep ramps are taken at a fast trot, not a flat out run
			var by := global_position.y + _soft_off.y
			var gv := (by - _grade_y) / dt if absf(by - _grade_y) < 0.3 else 0.0
			_grade_v = lerpf(_grade_v, gv, 1.0 - exp(-4.0 * dt))
			var grade := _grade_v / maxf(hv.length(), 1.0)
			if grade > 0.15:
				target_speed = minf(target_speed, maxf(CLIMB_RATE / grade, TROT_SPEED * 0.8))
			_grade_y = by
	else:
		_grade_y = global_position.y + _soft_off.y
		_grade_v = 0.0
		target_speed *= wish_len   # air steering keeps the old feel

	if grounded:
		var target := wish_dir * target_speed
		var cur := hv.length()
		# momentum: what the legs can do depends on what's asked and how fast the body already goes
		var accel: float
		var speeding := false
		if wish_len <= 0.01 and not want_crouch:
			accel = COAST_DECEL + COAST_DRAG * cur
		elif _brake_ask or (want_crouch and cur > STALK_SPEED + 0.3) or charging:
			accel = BRAKE_DECEL
		elif target_speed < cur - 0.05:
			accel = GAIT_DOWN_DECEL + GAIT_DOWN_DRAG * cur
		else:
			accel = minf(PUSH_ACCEL, PUSH_POWER / maxf(cur, 0.5))
			speeding = true
		if wall_brake and cur > 0.6 and not charging:
			# a cat doesn't run its face into a wall: it sees it coming and digs in so the nose
			# gets there at a walk. (only real walls, head on: not steps, ledges to hop onto,
			# animals or things that can be pushed)
			var cap := _wall_cap(hv / cur, cur)
			if cap < target_speed:
				target_speed = cap
				target = wish_dir * target_speed
				if cap < cur - 0.05:
					accel = maxf(accel, BRAKE_DECEL)
					speeding = false
		var lat_ask := TURN_ASK
		var g_now := grip_now()
		if real_move:
			# the cat knows its footing: easing off, a normal start and a steady turn ask for just
			# under what the paws hold. a flat out start, a thrown brake (stick back / crouch / a wall
			# coming) and a yanked turn ask for more than that, and slide
			var hard := accel >= BRAKE_DECEL - 0.01 or (speeding and target_speed > CANTER_SPEED + 0.5 and cur < 2.0)
			if not hard:
				accel = minf(accel, 0.95 * g_now)
			var off := wish_dir.angle_to(hv / cur) if (cur > 0.5 and wish_len > 0.01) else 0.0
			lat_ask = g_now * lerpf(0.95, 1.8, smoothstep(0.6, 1.3, off))
			_hard_ask = hard or off > 0.6
		if paw_drive and not lock_face and rig and rig.gait:
			# the body only speeds up, slows down or turns through paws that are on the ground:
			# with one paw down it gets half the shove of two, with none it just coasts. and
			# a cat's legs start it at about 0.65 g, not 0.9
			var down := 0.0
			for pi in 4:
				down += rig.gait.push(pi)
			# (measured against how many paws this gait has down on average: a gallop is in the
			# air most of the time and makes its speed in the moments it isn't, so over a
			# stride the cat gets about the same push, in surges. it never drops under 0.6: the
			# test course and the game's tuned run ups assume the old average)
			_drive_avg = lerpf(_drive_avg, down, 1.0 - exp(-2.5 * dt))
			_drive = lerpf(_drive, 0.6 + 0.4 * clampf(down / maxf(_drive_avg, 0.15), 0.0, 2.2), 1.0 - exp(-30.0 * dt))
			# slowing down keeps its tuned rates and only pulses a little with the paws
			if speeding:
				accel = minf(accel, DRIVE_MAX) * _drive
			else:
				accel *= lerpf(1.0, _drive, 0.35)
			if not real_move:
				lat_ask *= _drive   # (real_move: the turn is already held to what the paws grip)
		if lock_face and wish_len > 0.01:
			# (real_move: quick short steps, but placed ones: as hard as the floor holds, no skid)
			accel = maxf(accel, minf(LOCK_ACCEL, 0.95 * g_now) if real_move else LOCK_ACCEL)
		if cur > target_speed + 0.1 and ground_time < 0.1 and not real_move:
			# bhop window: keep momentum if you jump again quickly
			pass
		elif cur > SPRINT_SPEED + 0.3 and wish_len > 0.01 and not _brake_ask:
			# over speed (faster than any gait, landed from a fast jump): bleed it with friction but keep steering
			var newspeed := maxf(cur - FRICTION * cur * dt, maxf(target_speed, SPRINT_SPEED))
			hv = hv.lerp(wish_dir * cur, clampf(8.0 * dt, 0, 1)).normalized() * newspeed
		else:
			# the cat wants to carve hard: sideways (turning) the ask is way stronger than
			# the push along the run. grip below decides how much of it the paws can deliver
			var dv := target - hv
			var rundir := hv.normalized() if cur > 0.3 else Vector3.ZERO
			var lon := rundir * dv.dot(rundir)
			var lat := dv - lon
			if rundir == Vector3.ZERO:
				lon = dv
				lat = Vector3.ZERO
			hv += lon.limit_length(accel * dt) + lat.limit_length(lat_ask * (1.0 if real_move else lerpf(0.4, 1.0, clampf(cur / SPRINT_SPEED * 1.6, 0.0, 1.0))) * dt)
	elif not leap_lock and real_move:
		# in the air there is nothing to push on: the path is set. a twist of the body buys a
		# small sideways correction, once, and never any speed
		if wish_len > 0.01 and _air_left > 0.0:
			var sp := hv.length()
			var add := wish_dir * AIR_NUDGE * dt
			if sp > 0.3:
				add -= hv / sp * add.dot(hv / sp)
			add = add.limit_length(_air_left)
			_air_left -= add.length()
			hv += add
			if sp > 0.3:
				hv = hv.limit_length(sp)
		# hopping up at something right in front: the capsule catches its face on the way up and
		# loses the forward half of the push. once clear it carries on the way it was sent
		var ll := _launch_hv.length()
		if ll > 0.3 and wish_len > 0.3 and wish_dir.dot(_launch_hv / ll) > 0.5:
			var lack := ll - hv.dot(_launch_hv / ll)
			if lack > 0.05:
				hv += _launch_hv / ll * minf(lack, 10.0 * dt)
	elif not leap_lock:
		# quake/cpm style air accel: tiny wish cap so strafing + turning builds speed
		if wish_len > 0.01:
			var wishspeed := minf(target_speed, AIR_WISH_CAP)
			var cur_along := hv.dot(wish_dir)
			var add := wishspeed - cur_along
			if add > 0.0:
				hv += wish_dir * minf(add, AIR_ACCEL * dt * wishspeed)
		hv *= 1.0 - 0.02 * dt

	# ---------------- grip ----------------
	# the paws can only push so hard on what's underfoot. ask for more (hard starts, stops,
	# tight turns at speed) and they slip: the cat drifts, scrabbles, and tears up soft ground
	if grounded:
		# grip fades a little at speed (paws spend less time planted per stride)
		var g: float = GRIP.get(surface, GRIP.default) * lerpf(1.0, 0.75, clampf(hv_before.length() / SPRINT_SPEED, 0.0, 1.0))
		if real_move:
			g = grip_now()
		var need := (hv - hv_before) / dt
		var nl := need.length()
		if real_move and not _hard_ask and nl > 0.97 * g:
			# pushing and turning at once: a cat that isn't forcing it shares out what the paws hold
			need *= 0.97 * g / nl
			nl = 0.97 * g
			hv = hv_before + need * dt
		if nl > g:
			hv = hv_before + need / nl * g * SKID * dt
			slip = LowPoly.damp(slip, clampf((nl - g) / g, 0.0, 1.0), 20.0, dt)
		else:
			slip = LowPoly.damp(slip, 0.0, 10.0, dt)
		if slip > 0.2:
			_slip_fx(dt, hv)
	else:
		slip = LowPoly.damp(slip, 0.0, 10.0, dt)

	# ---------------- wall scramble ----------------
	scramble_t = maxf(scramble_t - dt, 0.0)
	if not grounded and wall_time < 0.05 and jump_held and scramble_avail and velocity.y > -1.5:
		if wish_dir.dot(-wall_normal) > 0.6 and not _is_climbable(wall_collider) and stamina.spend(CatStamina.SCRAMBLE):
			scramble_avail = false
			scramble_t = 0.32
			_event("scramble")
	if scramble_t > 0.0:
		if wall_time < 0.06:
			velocity.y = maxf(velocity.y, 2.5)
		else:
			scramble_t = 0.0

	# gravity
	if grounded:
		# landing out of a wall slide used to leave this stuck on, so the paws stayed in the scramble pose
		wall_sliding = false
	if not grounded:
		velocity.y -= G * dt
		if real_move:
			velocity.y = maxf(velocity.y, -FALL_TERMINAL)   # a spread out cat tops out at ~27 m/s
		# claws out: steering into a wall it can't climb (or lying on a slope too steep to stand
		# on) it slides down it, fore claws dragging. see _slide_step
		_slide_step(dt, wish_dir)
	else:
		_end_slide()
	velocity.x = hv.x
	velocity.z = hv.z
	if _spots_t > 0.0:
		_spots_t -= dt
		if _spots_t <= 0.0 or not grounded:
			_clear_spots()
	if land_stick > 0.0:
		# stuck the pounce landing: all four paws planted where it came down
		land_stick -= dt
		if grounded:
			velocity.x = 0.0
			velocity.z = 0.0
	prev_vy = velocity.y
	if grounded and wish_len > 0.3 and hv.length() > TROT_SPEED + 0.3:
		if sprint:
			stamina.drain(CatStamina.GALLOP, dt)
		elif canter:
			stamina.drain(CatStamina.CANTER, dt)

	if grounded and auto_step:
		if smooth_steps:
			_soft_off -= RunAssist.step_onto(self, hv, dt)   # steps, kerbs, stairs: taken in stride
		else:
			RunAssist.step_up(self, hv, dt)   # roots, branches, stone lips: glide up, paws step
	# just put on top of a step, ahead of where the visible cat is: wait there while it walks up
	var step_wait := grounded and _soft_off.length_squared() > 4e-6
	if step_wait:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	if step_wait:
		velocity.x = hv.x
		velocity.z = hv.z
	_soft_off = _soft_off.move_toward(Vector3.ZERO, maxf(hv.length(), _soft_off.length() * 6.0 + 0.3) * dt)
	var sd := RunAssist.step_down(self, grounded and not step_wait, hv)
	if sd[0]:
		air_time = 0.0
		_soft_off -= sd[1]
	_track_walls()
	_slide_contact()
	_push_props()

	if wall_time < 0.03:
		var into := -wall_normal
		var pushing := wish_dir.dot(into) > 0.4 or (leap_lock and Vector3(velocity.x, 0, velocity.z).dot(into) > -0.2)
		if pushing and not is_on_floor():
			leap_lock = false
			# rough surface: sink the claws in and climb. otherwise go for the ledge
			if _is_climbable(wall_collider) and climb_cool <= 0.0 and stamina.can_run() and wish_dir.dot(into) > 0.4 and not is_on_floor():
				climber.cling(wall_normal)
			else:
				climber.try_ledge(into)
		elif pushing and is_on_floor() and _is_climbable(wall_collider) and jump_pressed and climb_cool <= 0.0 and stamina.can_run():
			climber.cling(wall_normal)

	# small stuff up to chest height (curbs, steps, rocks, logs): walking into it the cat just steps
	# up onto it, forepaws first then the hind legs, no leap. anything taller needs a jump
	if is_on_floor() and not (mantling or clambering or climbing or want_crouch or charging):
		var bump := _bump_dir()
		if bump != Vector3.ZERO and wish_dir.dot(bump) > 0.4:
			var v_keep := velocity
			velocity = Vector3(hv.x, 0.0, hv.z).normalized() * maxf(hv.length(), wish_len * TROT_SPEED) if hv.length() > 0.05 else bump * wish_len * TROT_SPEED
			if not climber.try_ledge(bump, true):
				velocity = v_keep   # what the slide left, not the speed from before it hit the bump

	# fell out of the world somehow: respawn
	if global_position.y < -5.0:
		global_position = Vector3(-1.0, 0.05, 1.2)
		velocity = Vector3.ZERO

	_post(dt, inp)


func _post(dt: float, _inp: Dictionary) -> void:
	# camera + rig + paws
	var hspd := Vector2(velocity.x, velocity.z).length()
	land_dip_v += (-land_dip * 180.0 - land_dip_v * 18.0) * dt
	land_dip += land_dip_v * dt
	var bob := 0.0
	if is_on_floor():
		# a cat's head is stabilised: only a whisper of bob, mostly at the gallop
		# gait hooks: the camera rides on the rig's head, which the neck already holds steady.
		# head_bob is what little vertical movement is left after that
		bob = rig.head_bob

	# blend weights for the special states
	if soft_air:
		# (the body turns onto / off the wall like a mass: it starts turning from rest and
		# stops without a jerk, where a plain ease starts at full speed)
		# (a top out from a climb tells it how far round the body is: it tips over the edge
		# with the haul, see CatClimb.climb_pose)
		var cp := climber.climb_pose()
		_w_climb_m = LowPoly.damp(_w_climb_m, cp, 22.0, dt)
		# dropping off the wall into the air (claws gave out, let go): the body swings round
		# slower, it's falling, not hauling itself over. 17 here jolted the hips (climblab stamina)
		var wf := 10.0 if (not climbing and cp <= 0.0 and not is_on_floor()) else 17.0
		_w_climb_v += (wf * wf * (_w_climb_m - w_climb) - 2.0 * wf * _w_climb_v) * dt
		w_climb = clampf(w_climb + _w_climb_v * dt, 0.0, 1.0)
		_w_clamber_m = LowPoly.damp(_w_clamber_m, 1.0 if clambering else 0.0, 26.0, dt)
		_w_clamber_v += (22.0 * 22.0 * (_w_clamber_m - w_clamber) - 44.0 * _w_clamber_v) * dt
		w_clamber = clampf(w_clamber + _w_clamber_v * dt, 0.0, 1.0)
	else:
		w_climb = LowPoly.damp(w_climb, 1.0 if climbing else 0.0, 12.0, dt)
		w_clamber = LowPoly.damp(w_clamber, 1.0 if clambering else 0.0, 16.0, dt)
	w_scratch = LowPoly.damp(w_scratch, 1.0 if scratching else 0.0, 8.0, dt)
	if climbing:
		climb_face = climb_face.slerp(climb_n, clampf(dt * 14.0, 0.0, 1.0)).normalized() if climb_face.dot(climb_n) > -0.9 else climb_n
		face_n = climb_face
	elif clambering:
		face_n = ledge_n
	elif scratching:
		face_n = scratch_n
	# wall kick: snaps flat onto the wall for the plant, then peels off it during the push
	# wall kick: turns its back to the wall and rears up on the hind legs during the plant,
	# then stays reared while the hind legs push it off
	w_kick = LowPoly.damp(w_kick, 1.0 if kick_plant_t > 0.0 else 0.0, 90.0 if kick_plant_t > 0.0 else 7.0, dt)
	w_face = maxf(w_climb, maxf(w_clamber, w_scratch))

	# eye: stands up when scratching, peeks over the edge when hanging
	_eye_bob = bob
	var eye := Vector3(0, lerpf(EYE_STAND, EYE_CROUCH, crouch_amt) + land_dip + bob - charge * 0.03, 0)
	var inv := global_transform.basis.inverse()
	eye = eye.lerp(Vector3(0, 0.41, 0) + inv * (-face_n * 0.05), w_scratch)
	# two paw grab: the head dips down over the target (no rearing up)
	eye.y -= combat.grip_w * 0.05
	if clambering:
		var pull := clampf(clamber_t / 0.55, 0.0, 1.0) if clamber_phase == 2 else 0.0
		var hang_eye := Vector3(0, HANG + 0.07, 0) + inv * (-ledge_n * 0.07)
		eye = eye.lerp(hang_eye.lerp(Vector3(0, EYE_STAND, 0), smoothstep(0.2, 0.9, pull)), w_clamber)
	eye = eye.lerp(Vector3(0, 0.27, 0) + inv * (face_n * 0.03), w_climb)
	# step smoothing: floor snapping pops the body up/down small steps; the eye glides instead
	var ty := global_position.y
	if step_cam:
		_step_cam(dt)
		eye.y += step_cam_off
	else:
		if is_on_floor() and not (mantling or clambering or climbing) and absf(_smooth_y - ty) < (0.3 if smooth_steps else 0.2):
			_smooth_y = LowPoly.damp(_smooth_y + velocity.y * dt, ty, 18.0, dt)
		else:
			_smooth_y = ty
		eye.y += _smooth_y - ty
	eye_local = _safe_eye(eye)
	var strafe := global_transform.basis.x.dot(velocity)
	cam_roll = LowPoly.damp(cam_roll, clampf(-strafe * 0.004, -0.02, 0.02), 6.0, dt)
	cam.rotation.z = cam_roll
	cam.fov = LowPoly.damp(cam.fov, fov_base + clampf((hspd - 3.0) * 1.4, 0.0, 14.0), 5.0, dt)

	rig.drive_velocity = velocity
	rig.on_floor = (is_on_floor() and not climber.active()) or climber.rig_grounded() or scratching
	var crouch_t := maxf(maxf(crouch_amt * (1.0 - charge), dash.gather * 0.85), combat.gather_w())
	# (legs open out of a gather over a few hundredths of a second, they don't switch)
	# dodge: the rig's own air pose per kind (stretched dart, arched side spring, rearing backstep)
	# and a deep four paw squat soaking up the landing
	_dodge_land_t += dt
	var dland := smoothstep(0.0, 0.05, _dodge_land_t) * (1.0 - smoothstep(0.08, 0.3, _dodge_land_t))
	crouch_t = maxf(crouch_t, 0.6 * dland)
	rig.dodge = move_toward(rig.dodge, 1.0 if dash.state == CatDash.AIR else 0.0, (16.0 if dash.state == CatDash.AIR else 7.0) * dt)
	if dash.state == CatDash.AIR:
		rig.dodge_kind = dash.kind
		rig.dodge_u = clampf(dash.air_t / dash.air_total, 0.0, 1.0)
		var ld := global_transform.basis.inverse() * dash.dir
		rig.dodge_lat = clampf(ld.x * 1.4, -1.0, 1.0)
	rig.dodge_land = dland
	rig.crouch = move_toward(rig.crouch, crouch_t, (16.0 if dland > 0.0 else 10.0) * dt) if soft_air else crouch_t
	rig.charge = charge
	rig.look_pitch = pitch * 0.6 * (1.0 - maxf(w_face, w_slide))
	# head camera: looking down past ~15 deg the cat curls its neck to look at its own paws
	var tuck := smoothstep(-0.25, -1.25, pitch) if (head_cam and view_mode == 0) else 0.0
	rig.head_tuck = LowPoly.damp(rig.head_tuck, tuck, 8.0, dt)
	# the head turns a little toward where you're looking
	var lyaw := clampf(wrapf(orb_yaw - yaw, -PI, PI), -1.2, 1.2) * 0.7 * (1.0 - maxf(w_face, w_slide))
	rig.look_yaw = LowPoly.damp(rig.look_yaw, lyaw, 10.0, dt)
	# wall scramble pose only. ground slip used to feed this too, which threw the front paws up into
	# the wall-claw pose whenever grip ran out on the floor (hard starts / turns on wood or tile).
	# slipping now just shows the claws and the paws stay on the ground.
	rig.scramble = LowPoly.damp(rig.scramble, 1.0 if scramble_t > 0.0 else 0.0, 14.0, dt)
	if soft_air:
		# a body can't snap onto the wall or off it: sprung. and as the floor comes up under a
		# slide the cat peels off the wall to land on its feet instead of lying on it into the ground
		var st := 1.0 if sliding else 0.0
		if sliding:
			var fh := _ray(global_position + Vector3.UP * 0.05, global_position + Vector3.DOWN * 0.45)
			if not fh.is_empty() and fh.normal.y > 0.7:
				st = smoothstep(0.03, 0.4, global_position.y - fh.position.y)
		_w_slide_m = LowPoly.damp(_w_slide_m, st, 24.0, dt)
		_w_slide_v += (16.0 * 16.0 * (_w_slide_m - w_slide) - 32.0 * _w_slide_v) * dt
		w_slide = clampf(w_slide + _w_slide_v * dt, 0.0, 1.0)
		if (w_slide <= 0.0 and _w_slide_v < 0.0) or (w_slide >= 1.0 and _w_slide_v > 0.0):
			_w_slide_v = 0.0
	else:
		w_slide = LowPoly.damp(w_slide, 1.0 if sliding else 0.0, 14.0 if sliding else 9.0, dt)
	rig.slide = w_slide * (1.0 - w_face)
	rig.slide_out = soft_air and not sliding
	if sliding:
		rig.on_floor = true    # paws are on the surface, not in an air pose
		_slide_fx()
	rig.slip_claws = minf(slip * 1.3, 1.0) if is_on_floor() else 0.0
	if stamina and stamina.winded:
		rig.soma.exertion = maxf(rig.soma.exertion, 0.9)   # ran the bar dry: the cat is visibly blown
	rig.climb = w_climb
	rig.carried = 1.0 if climber.active() else move_toward(rig.carried, 0.0, dt * 2.0)
	rig.on_wall = climber.active() and climber.kind != "step"
	rig.kick_paw_w = clampf(w_kick * 1.6 - 0.25, 0.0, 1.0)
	rig.kick_w = w_kick
	rig.clamber = w_clamber
	rig.clamber_pull = clampf(clamber_t / 0.55, 0.0, 1.0) if (clambering and clamber_phase == 2) else (1.0 if not clambering else 0.0)
	rig.ledge_world = ledge_point
	rig.rear = maxf(w_scratch, w_kick * 0.85)
	rig.scratch = w_scratch
	if "grip" in rig:
		rig.grip = combat.grip_w
		if combat.grip_w > 0.001 and not clawing:
			rig.claw_target = combat.grip_point
	rig.scratch_dist = SCRATCH_DIST
	_lift_tick(dt)
	rig.inertia_y = _lift
	rig.inertia_on = soft_air
	_orient_rig()

	paws.phase = rig.phase
	paws.speed = hspd
	paws.gait_w = rig.gait_w
	paws.on_floor = rig.on_floor
	paws.vy = velocity.y
	paws.crouch = crouch_amt
	paws.charge = charge
	paws.scramble = maxf(rig.scramble, rig.slide * 0.6)
	paws.climb = w_climb
	paws.hang = w_clamber
	paws.hang_pull = rig.clamber_pull if clambering else 0.0
	paws.scratch = w_scratch
	paws.claws_out = rig.claws_out
	if view_mode == 2:
		_orbit_cam(dt)
	elif third_person:
		_third_person_cam(dt)
	_hunt_scan()
	dust.physics_tick(dt)
	health.physics_tick(dt)
	stamina.physics_tick(dt, hspd < 0.2 and is_on_floor() and not (climbing or clambering or scratching))
	_phys_curr = global_position
	_vis_curr = global_position + _vis_off()
	_rig_base = rig.transform
	_interp_ok = true
	max_height = maxf(max_height, global_position.y)
	# gait hooks: first person paws follow the rig's planted front paws
	paws.foot = rig.fp_foot
	paws.use_feet = rig.use_planting and w_face < 0.02
	rig.gravity = G
	# multiplayer: hand this tick's rig inputs to the network (no-op when nobody else is here)
	var net := get_node_or_null("/root/Net")
	if net and not spar_dummy:
		net.capture(self, dt)


func _process(_dt: float) -> void:
	if bot.is_empty() and not CatKeys.blocked:
		# right stick look lands every frame like the mouse
		var ld := CatPad.look_delta(_dt)
		if invert_y:
			ld.y = -ld.y
		if ld != Vector2.ZERO:
			orb_yaw += ld.x
			if view_mode == 2:
				orb_pitch = clampf(orb_pitch + ld.y, -1.4, 0.6)
			else:
				pitch = clampf(pitch + ld.y, -1.45, 1.45)
	if not _interp_ok:
		return
	# (the visible cat's spot is what gets smoothed between ticks: the capsule itself may hop onto a step)
	var voff := _vis_off()
	var vis := global_position + voff
	if _phys_prev.distance_to(_vis_prev - voff) > 0.3 or _phys_curr.distance_to(global_position) > 0.001:
		# a test / respawn moved the cat by hand between ticks
		_vis_prev = _phys_prev + voff
		_vis_curr = _phys_curr + voff
	var p := _vis_prev.lerp(_vis_curr, Engine.get_physics_interpolation_fraction())
	if p.distance_to(vis) > 0.6:
		p = vis   # teleport / respawn: don't smear
	var off := global_transform.basis.inverse() * (p - vis)
	if not _head_cam_on():
		# eye_local carries this tick's stair glide; swap it for the glide in between ticks, like the body
		var sc := Vector3(0, step_cam_frame() - step_cam_off, 0) if step_cam else Vector3.ZERO
		cam_pivot.position = eye_local + off + global_transform.basis.inverse() * voff + sc
	# (head cam: the pivot keeps last frame's head spot until _place_head_cam moves it, so the
	# lock aims from where the camera really is)
	lock.frame_steer(_dt)
	# mouse look lands every frame, not every physics tick
	cam_pivot.rotation = Vector3(orb_pitch if view_mode == 2 else pitch, wrapf(orb_yaw - rotation.y, -PI, PI), 0)
	paw_anchor.rotation.x = -cam_pivot.rotation.x
	_carry_follow()
	rig.transform = Transform3D(_rig_base.basis, _rig_base.origin + off)


## fastest the cat may be going so that braking at WALL_BRAKE it reaches a wall dead ahead at
## a slow walk (INF when there's no wall in the way)
## what the paws can hold on what's underfoot right now (m/s2)
func grip_now() -> float:
	return float(MU.get(surface, MU.default)) * G * GRIP_REAL


func _wall_cap(dir: Vector3, cur: float) -> float:
	var wb := minf(WALL_BRAKE, SKID * 0.9 * grip_now()) if real_move else WALL_BRAKE
	var L: float = rig.S_.get("len", 1.0) if rig.S_ is Dictionary else 1.0
	var nose := NOSE_REACH * L
	var look := nose + 0.05 + cur * cur / (2.0 * wb) + cur * 0.05
	var gap := INF
	for h in [0.14, 0.6]:
		var c: Vector3 = global_position + Vector3.UP * h
		var hit := _ray(c, c + dir * look)
		if hit.is_empty() or not (hit.collider is StaticBody3D or hit.collider is CSGShape3D or hit.collider is GridMap):
			return INF
		var n: Vector3 = hit.normal
		if absf(n.y) > 0.5 or n.dot(dir) > -0.75:
			return INF   # a slope, or a glancing angle: the cat runs along it
		gap = minf(gap, (hit.position - c).dot(dir) - nose)
	return sqrt(2.0 * wb * maxf(gap - 0.03, 0.0)) + 0.5


func _vis_off() -> Vector3:
	return _soft_off + Vector3(_lag.x, _lift, _lag.z)


## vertical inertia of the visible cat (see `_lift`). the capsule's speed changes in one tick
## at a take off and at a landing; the body's can't
func _lift_tick(dt: float) -> void:
	var on := is_on_floor()
	# (grabbing a wall: the forelegs take the hit, the body carries on a few cm before it has
	# stopped. after that the climb moves it directly)
	_climb_age = _climb_age + dt if climbing else 0.0
	var grab: bool = climbing and _climb_age < 0.22
	var busy: bool = not soft_air or (climbing and not grab) or clambering or wall_sliding or sliding
	# sideways
	var hb := global_position + _soft_off
	hb.y = 0.0
	# (a pounce promises where each paw comes down: the body flies and lands exactly with the capsule)
	_pounce_hold = 0.3 if (pounce_air or dash.state == CatDash.AIR) else maxf(_pounce_hold - dt, 0.0)
	var h_off: bool = busy or _pounce_hold > 0.0 or not _lag_base.is_finite() or hb.distance_to(_lag_base) > 0.25
	var hvc := Vector3.ZERO if h_off else (hb - _lag_base) / dt
	_lag_base = hb
	if h_off:
		_lag = _lag.move_toward(Vector3.ZERO, (6.0 if _pounce_hold > 0.0 else 1.5) * dt)
		_lag_v = hvc
	else:
		var hrel := _lag_v - _lag_vc
		var dvh := hvc + hrel + (-196.0 * _lag - 28.0 * hrel) * dt - _lag_v
		# (a crash into something stops the body with the capsule: it can't carry on into a wall)
		var lmax := 0.08 if grab else LAG_MAX
		if grab:
			dvh = dvh.limit_length(maxf(LAG_ACC, hrel.length_squared() / (2.0 * maxf(lmax - _lag.length() - 0.01, 0.01))) * dt)
		elif hvc.length() > _lag_vc.length() - 1.0:
			dvh = dvh.limit_length(LAG_ACC * dt)
		_lag_v += dvh
		_lag += (_lag_v - hvc) * dt
		if _lag.length() > lmax:
			_lag = _lag.limit_length(lmax)
			_lag_v = hvc
	_lag_vc = hvc
	# up and down
	var base := global_position.y + _soft_off.y
	var off_now: bool = busy or is_nan(_lift_base) or absf(base - _lift_base) > 0.15
	var vc := 0.0 if off_now else (base - _lift_base) / dt
	_lift_base = base
	if off_now:
		_lift = move_toward(_lift, 0.0, 1.5 * dt)
		_lift_v = vc
		_lift_vc = vc
		return
	if on and _lift_on_prev and absf(_lift) < 0.002 and absf(_lift_v - _lift_vc) < 0.25:
		# standing on the ground and settled: the body just rides the capsule (steps, stairs
		# and slopes are the soft root's and the legs' job)
		_lift = 0.0
		_lift_v = vc
		_lift_vc = vc
		return
	_lift_on_prev = on
	# falling: the legs reach for the ground (the body is still that far up when the paws touch)
	var want := LIFT_REACH * smoothstep(-0.5, -2.5, vc) if not on else 0.0
	var rel := _lift_v - _lift_vc
	var vt := vc + rel + (196.0 * (want - _lift) - 28.0 * rel) * dt
	var lo := -LIFT_SQUAT if on else -0.22
	var up := LIFT_UP_ACC
	if on and _lift_v < 0.0:
		# a hard landing: the legs stop the body in the room they have, however hard that is
		up = maxf(up, _lift_v * _lift_v / (2.0 * maxf(_lift - lo - 0.01, 0.01)))
	var dv := clampf(vt - _lift_v, -LIFT_DN_ACC * dt, up * dt)
	if on and _lift_v < 0.0 and up > LIFT_UP_ACC:
		dv = minf(up * dt, -_lift_v)   # no room to stop any gentler
	_lift_v += dv
	_lift += (_lift_v - vc) * dt
	if _lift < lo:
		_lift = move_toward(_lift, lo, 2.0 * dt) if _lift < lo - 0.02 else lo
		_lift_v = maxf(_lift_v, vc)
	elif _lift > 0.12:
		_lift = 0.12
		_lift_v = minf(_lift_v, vc)
	_lift_vc = vc


## world point the lock on aims at (target body centre), or Vector3.ZERO when not locked
func lock_point() -> Vector3:
	return lock.point() if lock else Vector3.ZERO


## the rig normally just follows the body. on walls it turns to face the surface,
## and when climbing it rotates 90 degrees so its feet are on the wall
func _orient_rig() -> void:
	_orient_rig_base()
	var voff := _vis_off()
	if voff != Vector3.ZERO:
		rig.global_position += voff
	if spar:
		spar.orient(rig)   # play fight poses + hit reactions (goes over the wire with the rig)


func _orient_rig_base() -> void:
	_clip_guard()
	if w_slide > 0.002 and w_face < 0.002 and w_kick < 0.002:
		_orient_slide()
		return
	if w_kick > 0.002 and w_face < 0.002:
		_orient_kick()
		return
	if w_face < 0.002:
		rig.transform = Transform3D(Basis(), Vector3(0, 0, _clip_off))
		return
	var n := face_n
	var up := Vector3.UP
	var face := Basis(up.cross(n).normalized(), up, n)
	var climb_b := Basis(n.cross(Vector3.DOWN).normalized(), n, Vector3.DOWN)
	if absf(climb_head) > 0.001:
		climb_b = Basis(n, -climb_head) * climb_b   # free climb: body turned toward sideways travel
	var q := global_transform.basis.get_rotation_quaternion()
	q = q.slerp(face.get_rotation_quaternion(), clampf(w_face, 0.0, 1.0))
	var wc := w_climb
	q = q.slerp(climb_b.get_rotation_quaternion(), clampf(wc, 0.0, 1.0))
	var pos := global_position.lerp(global_position + up * 0.05 - n * (RADIUS + 0.012), wc)
	pos += global_transform.basis.z * _clip_off * (1.0 - clampf(w_face, 0.0, 1.0))
	rig.global_transform = Transform3D(Basis(q), pos)


## sliding: the rig lies on the surface (rig y = its normal), head up it, or down it going head first
func _orient_slide() -> void:
	var n := slide_n
	var down := (Vector3.DOWN - n * Vector3.DOWN.dot(n))
	if down.length() < 0.05:
		down = -global_transform.basis.z
	down = down.normalized()
	var z := down if slide_head_up else -down
	var sb := Basis(n.cross(z).normalized(), n, z)
	var w := clampf(w_slide, 0.0, 1.0)
	var q := global_transform.basis.get_rotation_quaternion().slerp(sb.get_rotation_quaternion(), w)
	var pos := global_position.lerp(global_position - n * (RADIUS + 0.008), w)
	pos += global_transform.basis.z * _clip_off * (1.0 - w)
	rig.global_transform = Transform3D(Basis(q), pos)


## wall kick pose: back to the wall, facing the kick direction, reared up on the hind legs
## (spine ~75 deg) with the whole body tipped back so the hind paws sit flat on the wall
func _orient_kick() -> void:
	var w := clampf(w_kick, 0.0, 1.0)
	var d := kick_dir if kick_dir != Vector3.ZERO else kick_n
	var fwd_b := Basis(Vector3.UP, atan2(-d.x, -d.z))
	var kb := fwd_b * Basis(Vector3.RIGHT, KICK_LEAN)
	var q := global_transform.basis.get_rotation_quaternion().slerp(kb.get_rotation_quaternion(), w)
	var b := Basis(q)
	var pos := global_position + global_transform.basis.z * _clip_off * (1.0 - w)
	# keep the hips just off the wall: the hind paws reach back to it, the rump never goes in
	var hip: Vector3 = b * Vector3(0, 0.1, 0.17)
	var depth := -(pos + hip - _kick_wall_pt).dot(kick_n)
	if depth > -0.03:
		pos += kick_n * (depth + 0.03) * w
	rig.global_transform = Transform3D(b, pos)
	# hind paws pressed on the wall under the hips
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		var p: Vector3 = pos + b * Vector3(side * 0.05, 0.0, 0.13)
		p -= kick_n * (p - _kick_wall_pt).dot(kick_n) - kick_n * 0.045   # paw centre, so the toes rest on the face
		if _kick_paws_set < 2:
			rig.kick_paws[k] = p
	_kick_paws_set = mini(_kick_paws_set + 1, 2) if kick_plant_t > 0.0 and w > 0.8 else _kick_paws_set


## the capsule (r 8.5 cm) keeps the middle of the cat out of walls, but the head and the rump
## stick out ~29 / 20 cm front and back (forepaws ~37 cm ahead in the air). ray along the spine at chest and head height and slide
## the visible body back (or forward) so neither end sinks into a wall, door or shelf.
## pops in instantly, eases back out
func _clip_guard() -> void:
	var L: float = rig.S_.get("len", 1.0) if rig.S_ is Dictionary else 1.0
	var fwd := -global_transform.basis.z
	# in the air the forelegs reach out ahead of the nose for the landing
	var nose := (NOSE_REACH + (0.0 if is_on_floor() else 0.08)) * L
	var rump := RUMP_REACH * L
	var front := nose
	var back := rump
	for h in [0.03, 0.12, 0.22]:
		var c: Vector3 = global_position + _vis_off() + Vector3.UP * h
		var hf := _ray(c, c + fwd * nose)
		if not hf.is_empty() and not hf.collider is RigidBody3D and not _steppable(hf):
			front = minf(front, (hf.position - c).dot(fwd))
		var hb := _ray(c, c - fwd * rump)
		if not hb.is_empty() and not hb.collider is RigidBody3D and not _steppable(hb):
			back = minf(back, (c - hb.position).dot(fwd))
	# +z is backwards in body space
	var want := maxf(nose - front, 0.0)
	# nothing behind: the body can slide as far back as it needs (it's only the visible cat)
	var room := maxf(back - 0.01, 0.0) if back < rump else want
	want = minf(want, room) if want > 0.0 else -minf(maxf(rump - back, 0.0), maxf(front - 0.01, 0.0))
	var cdt := get_physics_process_delta_time()
	if soft_air:
		# the body is eased back off a wall (quickly, but not in one tick: a 30 cm shove in a
		# single frame is a worse glitch than a nose in a wall for a moment). walking up to a
		# wall the cat brakes, so this only has work to do in the odd case
		var w := 26.0 if absf(want) > absf(_clip_off) else 10.0
		_clip_v += (w * w * (want - _clip_off) - 2.0 * w * _clip_v) * cdt
		_clip_off += _clip_v * cdt
	elif absf(want) > absf(_clip_off):
		_clip_off = want
	else:
		_clip_off = LowPoly.damp(_clip_off, want, 10.0, cdt)


## is what this ray hit something the cat just walks up onto / down off (a step, a kerb, a
## stair riser: flat top no higher than chest height above the feet)? those are not walls: the
## body goes over them, front end first, instead of being held back off them
func _steppable(hit: Dictionary) -> bool:
	if not smooth_steps:
		return false
	var n: Vector3 = hit.normal
	var p: Vector3 = hit.position - Vector3(n.x, 0, n.z).normalized() * 0.03
	var top := _ray(Vector3(p.x, global_position.y + STEP_MOUNT + 0.05, p.z), Vector3(p.x, global_position.y - 0.02, p.z))
	# (a down ray that starts inside a tall wall passes out of it and finds the floor under
	# the wall: a top at floor level is not the top of a step)
	return not top.is_empty() and top.normal.y > 0.7 and top.position.y <= global_position.y + STEP_MOUNT + 0.01 and top.position.y > global_position.y + 0.012


## swap the cat model (block, chamfer, facet, wedge, stepped) on the fly
func set_style(st: String) -> void:
	style = st
	var old := rig
	rig = CatRig.new()
	rig.fur = fur
	rig.fur_dark = fur_dark
	rig.pattern = pattern
	rig.style = st
	add_child(rig)
	_apply_rig_view()
	old.queue_free()
	# fp paws get the new coat too
	var op := paws
	paws = PawView.new()
	paws.fur = rig.fur
	paws.fur_dark = rig.fur_dark
	paws.pattern = rig.pattern
	paws.socks = rig.socks
	paws.sock_col = rig.belly
	paws.pad = rig.pad_color
	paws.visible = op.visible
	_apply_rig_view()
	paws.rig = rig
	op.get_parent().add_child(paws)
	op.queue_free()
	_event("cat: " + CatRig.STYLES[st].label)


## stick tilt (0..1) -> ground speed. analog all the way: creep, walk, then up to a trot
static func speed_for_tilt(m: float) -> float:
	if m <= 0.01:
		return 0.0
	if m <= 0.5:
		return lerpf(CREEP_SPEED, WALK_SPEED, m / 0.5)
	return lerpf(WALK_SPEED, TROT_SPEED, smoothstep(0.5, 0.92, m))


func want_crouch_peek(inp: Dictionary) -> bool:
	return inp.get("crouch", false)


func _side_hop(side: float, fwd: Vector3, right: Vector3) -> void:
	var keep := fwd * fwd.dot(velocity)
	velocity = keep + right * side * SIDE_HOP_V
	velocity.y = SIDE_HOP_UP
	_hop_cool = SIDE_HOP_COOL
	_hopped_now = true
	ground_time = 0.0
	_event("side hop " + ("right" if side > 0.0 else "left"))


## inside a dodge's i-frame window (cat_dash.gd). anything that hurts the cat should check this
func is_invulnerable() -> bool:
	return dash.iframes > 0.0


## where paw reach is measured from: the body's eye point (above the shoulders), even when
## the camera is behind it or out in the head (the head bob / neck curl doesn't change reach)
func _eye_pos() -> Vector3:
	if view_mode == 0:
		return global_transform * eye_local
	return global_transform * Vector3(0, EYE_STAND, 0)


## where crosshair rays start: the camera itself in first person (it rides the head, so a ray
## from the body would land off the crosshair when looking down), the body's eye otherwise
func _aim_pos() -> Vector3:
	if view_mode == 0:
		return cam.global_position
	return _eye_pos()


func _look_dir() -> Vector3:
	return -cam.global_transform.basis.z


func set_view(m: int) -> void:
	view_mode = m
	if m == 2:
		orb_pitch = clampf(pitch - 0.35, -1.4, 0.6)
		_orb_d = 0.4
	set_third_person(m != 0)
	_event(["first person", "third person", "orbit cam (scroll = zoom)"][m])


## first person with head_cam: the whole body is drawn except the head + neck (the camera is
## inside them), no viewmodel. old style (head_cam off): the body only casts a shadow and the
## paws you see are the viewmodel (tracks the real planted paws, sits in body space, see paw_anchor)
func _apply_rig_view() -> void:
	var real := third_person or head_cam
	rig.set_shadow_only(not real)
	rig.set_head_hidden(not third_person and head_cam)
	if paws:
		paws.visible = not real


func set_head_cam(v: bool) -> void:
	head_cam = v
	_apply_rig_view()
	if not v:
		head_roll = 0.0
		cam.rotation.z = cam_roll


## first person head camera, once per rendered frame after the rig has animated: the pivot
## (which carries mouse look) moves to the head bone's eye point, kept out of walls by a
## sweep from the middle of the body. look direction stays on the mouse (no lag), only a bit
## of the head's roll comes through so turns and side hops feel like they're on a body
func _head_cam_on() -> bool:
	return view_mode == 0 and not third_person and head_cam and rig != null and rig.head != null and _interp_ok


func _place_head_cam(dt: float) -> void:
	if not _head_cam_on():
		return
	var to: Vector3 = rig.head_cam_world()
	var from := rig.global_transform * Vector3(0, minf(capsule.height * 0.5, 0.12), 0)
	var f := _sweep(from, to, 0.03)
	head_cam_blocked = f < 1.0
	if head_cam_blocked:
		to = from.lerp(to, f)   # head in a wall / under a shelf: the eye stays on this side of it
	if step_cam:
		# stairs: the head glides up/down the steps, not pop by pop. the glide only goes as far as
		# open space allows (lagging low it would sink into the next riser), and then gives way
		var glide := Vector3(to.x, _head_step_y(to.y, dt), to.z)
		if dt > 0.0 and _hs_last != Vector3.INF and _hs_last.distance_to(to) < 0.5:
			_hs_hv = _hs_hv.lerp(Vector3(to.x - _hs_last.x, 0.0, to.z - _hs_last.z) / dt, 1.0 - exp(-dt / 0.05))
		_hs_last = to
		if glide.y < to.y - 0.005:
			# gliding up behind the head: look at the steps just ahead of the eye and lift the
			# glide before it reaches a riser, so it eases over the nosing instead of bumping it
			var hv := _hs_hv   # how the eye is really moving (velocity is zero during a quick mantle)
			var fl := _cam_floor(to, to.y)
			for ahead in [0.08, 0.16, 0.24]:
				fl = maxf(fl, _cam_floor(to + hv * ahead, to.y))
			fl = minf(fl + 0.035, to.y)
			if _hs_floor == -INF:
				_hs_floor = minf(fl, glide.y)   # starts under the glide, then eases up
			_hs_floor = fl if fl < _hs_floor else LowPoly.damp(_hs_floor, fl, 50.0, dt)
			if glide.y < _hs_floor:
				glide.y = _hs_floor
				_hs.x = glide.y
				_hs.y = maxf(_hs.y, _hs.z)
		else:
			_hs_floor = -INF
		var g := _sweep(to, glide, 0.03) if absf(glide.y - to.y) > 0.001 else 1.0
		if g < 1.0:
			glide = to.lerp(glide, maxf(g - 0.05, 0.0))
			_hs.x = glide.y
			_hs.y = _hs.z
		to = glide
	if calm_cam:
		# comfort setting: the eye glides over the head's step bob and never rolls
		_calm_y = LowPoly.damp(_calm_y, to.y, 7.0, dt) if absf(_calm_y - to.y) < 0.25 else to.y
		to.y = _calm_y
	cam_pivot.global_position = to
	var hx: Vector3 = rig.head.global_transform.basis.x.normalized()
	var r := clampf(asin(clampf(hx.y, -1.0, 1.0)), -0.12, 0.12)   # head's right side up = +roll
	head_roll = LowPoly.damp(head_roll, 0.0 if calm_cam else r * 0.5, 12.0, dt)
	cam.rotation.z = (0.0 if calm_cam else cam_roll) + head_roll


class HeadFollow extends Node:
	var player: Node
	func _ready() -> void:
		process_priority = 20   # after the rig (0) and the paw copies (10)
	func _process(dt: float) -> void:
		player._place_head_cam(dt)


func set_third_person(v: bool) -> void:
	if not v:
		view_mode = 0
	elif view_mode == 0:
		view_mode = 1
	third_person = v
	_apply_rig_view()
	if not v:
		cam.position = Vector3.ZERO
		eye_local = Vector3(0, EYE_STAND, 0)
	else:
		_tp_dist = 0.3


func _can_stand() -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS * 0.95
	cap.height = STAND_H
	params.shape = cap
	params.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_H * 0.5 + 0.01, 0))
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _track_walls() -> void:
	wall_time += get_physics_process_delta_time()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) < 0.4:
			wall_normal = Vector3(n.x, 0, n.z).normalized()
			wall_collider = c.get_collider()
			wall_time = 0.0


## what the cat walked into this tick: direction into a wall or a steep lump (too steep to walk up), or ZERO
func _bump_dir() -> Vector3:
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y < 0.72 and n.y > -0.4 and Vector2(n.x, n.z).length() > 0.1:
			return -Vector3(n.x, 0, n.z).normalized()
	return Vector3.ZERO


## surfaces claws sink into even when the level didn't tag them "climbable" (free climbing)
const CLIMB_SURFACES := ["bark", "fabric", "carpet", "rug", "hay", "sisal", "rope"]


## any contact this tick with something too steep to stand on (a wall, or a slope past 50 deg)
func _slide_contact() -> void:
	_slide_seen += get_physics_process_delta_time()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if n.y < SLIDE_STEEP_Y and n.y > -0.15:
			slide_n = n
			_slide_col = c.get_collider()
			_slide_seen = 0.0


## falling against something it can't climb: claws out, slide down it. on a vertical face it needs
## steering into it (let go = drop off); a too steep slope keeps it sliding just by lying on it
func _slide_step(dt: float, wish_dir: Vector3) -> void:
	var nh := Vector3(slide_n.x, 0.0, slide_n.z)
	nh = nh.normalized() if nh.length() > 0.01 else -global_transform.basis.z
	var into := wish_dir.dot(-nh)
	var slope := slide_n.y > 0.2
	var ok := _slide_seen < 0.1 and not _is_climbable(_slide_col) and scramble_t <= 0.0
	ok = ok and not (climbing or clambering or mantling or scratching) and velocity.y < 0.3
	ok = ok and (slope or into > (0.25 if sliding else 0.5))
	if not ok:
		_end_slide()
		return
	if not sliding:
		start_wall_slide(slide_n)
	# claws drag it down to a steady speed (slower on a gentler slope, faster on slick stuff)
	var steep := sqrt(maxf(1.0 - slide_n.y * slide_n.y, 0.0))
	var v_t := float(SLIDE_SPEED.get(_slide_surface(), SLIDE_SPEED.default)) * steep * steep
	if velocity.y < -v_t:
		velocity.y = move_toward(velocity.y, -v_t, 30.0 * dt)


## starts the claw drag slide on a surface with normal n (also called when climbing loses its grip)
func start_wall_slide(n: Vector3) -> void:
	if is_on_floor():
		return
	if n.y >= SLIDE_STEEP_Y or n.y <= -0.15:
		n = Vector3(n.x, 0.0, n.z).normalized()
	if n == Vector3.ZERO:
		return
	slide_n = n
	_slide_seen = 0.0
	if sliding:
		return
	sliding = true
	wall_sliding = true
	# which way round: facing into it / up it = head up, facing down the slope = head first
	var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	var fwd := -global_transform.basis.z
	fwd = fwd - n * fwd.dot(n)
	slide_head_up = down.length() < 0.05 or fwd.length() < 0.05 or fwd.normalized().dot(down.normalized()) < 0.3
	_slide_mark_last = [Vector3.INF, Vector3.INF]
	_event("sliding down, claws dragging")


func _end_slide() -> void:
	sliding = false
	wall_sliding = false


func _slide_surface() -> String:
	if _slide_col is Node:
		var nd := _slide_col as Node
		if nd.has_meta("surface"):
			return nd.get_meta("surface")
	return "default"


## claw marks: three thin scrapes behind each fore claw while it drags
func _slide_fx() -> void:
	var sf: CatSlide = rig.slide_fx
	if w_slide < 0.5 or get_tree().current_scene == null:
		return
	for i in 2:
		var c: Vector3 = sf.contact[i]
		if not sf.planted[i]:
			_slide_mark_last[i] = Vector3.INF
			continue
		var last: Vector3 = _slide_mark_last[i]
		if last == Vector3.INF:
			_slide_mark_last[i] = c
			continue
		var d := c - last
		if d.length() < 0.025:
			continue
		_slide_mark_last[i] = c
		var along := d.normalized()
		var side := along.cross(slide_n).normalized()
		var tint := Color(0.92, 0.88, 0.8, 0.6) if _slide_surface() == "wood" else Color(0.22, 0.2, 0.18, 0.5)
		if _slide_mat == null or _slide_mat.albedo_color != tint:
			_slide_mat = StandardMaterial3D.new()
			_slide_mat.albedo_color = tint
			_slide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_slide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for k in 3:
			var m := MeshInstance3D.new()
			m.mesh = LowPoly.box(0.0)
			m.material_override = _slide_mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			get_tree().current_scene.add_child(m)
			var mid := (c + last) * 0.5 + side * (k - 1) * 0.006 + slide_n * 0.0015
			m.global_transform = Transform3D(Basis(side * 0.0016, slide_n * 0.001, along * (d.length() + 0.004)), mid)
			_slide_marks.append(m)
		while _slide_marks.size() > 360:
			var old: Node3D = _slide_marks.pop_front()
			if is_instance_valid(old):
				old.queue_free()


func _is_climbable(o: Object) -> bool:
	if o == null or not is_instance_valid(o) or not (o is Node):
		return false
	var nd := o as Node
	if nd.is_in_group("climbable"):
		return true
	return nd.has_meta("surface") and CLIMB_SURFACES.has(str(nd.get_meta("surface")))


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _find_wall() -> Vector3:
	# recently touched wall counts (a little coyote time for kicks)
	if wall_time < 0.12:
		return wall_normal
	var best := Vector3.ZERO
	var best_d := 1e9
	var center := global_position + Vector3(0, capsule.height * 0.5, 0)
	for k in 8:
		var a := k * TAU / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var hit := _ray(center, center + d * (RADIUS + 0.14))
		if not hit.is_empty() and absf(hit.normal.y) < 0.4:
			var dist: float = (hit.position - center).length()
			if dist < best_d:
				best_d = dist
				best = Vector3(hit.normal.x, 0, hit.normal.z).normalized()
	return best


func _try_wall_kick(wish_dir: Vector3) -> void:
	if kicks_left <= 0:
		return
	var n := _find_wall()
	if n == Vector3.ZERO:
		return
	if not stamina.spend(CatStamina.WALL_KICK):
		return
	var same_wall := last_kick_normal != Vector3.ZERO and n.dot(last_kick_normal) > 0.9
	var hv := Vector3(velocity.x, 0, velocity.z)
	var into := hv.dot(n)
	if into < 0.0:
		hv -= n * into
	# a cat can't push off a wall it isn't touching: it plants all four paws on it first
	# (the run up is soaked into flexed legs) and the push comes out of that crouch.
	# the plant is short enough that the kick still answers the key straight away
	_kick_hv = hv
	_kick_same = same_wall
	kick_n = n
	kick_plant_t = KICK_PLANT
	_snug_to_wall(n)
	_kick_wall_pt = global_position - n * RADIUS
	_kick_paws_set = 0
	kick_dir = _kick_heading(n)
	# the turn to put its back to the wall happens on the way in: by the time the paws
	# touch it's done (blending it would sweep the rump and tail through the wall)
	w_kick = 1.0
	velocity = hv * 0.25 - n * 0.4 + Vector3.UP * clampf(velocity.y * 0.3, -0.4, 0.6)
	kicks_left -= 1
	last_kick_normal = n
	scramble_t = 0.0
	leap_lock = false
	var side := 1.0 if global_transform.basis.x.dot(-n) > 0.0 else -1.0
	paws.kick(side)
	cam_roll += side * 0.025
	_event("wall kick (%d left)" % kicks_left)


## kick found its wall by the coyote ray: close the gap so the paws actually meet it
func _snug_to_wall(n: Vector3) -> void:
	var c := global_position + Vector3.UP * minf(capsule.height * 0.5, 0.12)
	var hit := _ray(c, c - n * (RADIUS + 0.2))
	if hit.is_empty():
		return
	var gap: float = (c - hit.position).dot(n) - RADIUS - 0.004
	if gap > 0.0:
		move_and_collide(-n * gap)


## paws planted on the wall: stick to it, legs loading up, then the push
func _kick_plant_step(dt: float, wish_dir: Vector3) -> void:
	kick_plant_t -= dt
	kick_dir = _kick_heading(kick_n)   # still aimable during the plant
	# along the wall the run up bleeds off into the legs, falling stops, a slight press keeps contact
	var along := Vector3(velocity.x, 0, velocity.z)
	along -= kick_n * along.dot(kick_n)
	velocity = along * maxf(1.0 - 18.0 * dt, 0.0) - kick_n * 0.4 + Vector3.UP * move_toward(velocity.y, 0.0, 12.0 * dt)
	move_and_slide()
	_track_walls()
	if kick_plant_t <= 0.0 or wall_time > 0.06:
		_kick_release(wish_dir)


func _kick_release(_wish_dir: Vector3) -> void:
	kick_plant_t = 0.0
	kick_dir = _kick_heading(kick_n)
	# the hind legs drive the body out along the kick direction; a bit of the run up along
	# the wall survives in the same direction
	var carry := maxf(_kick_hv.dot(kick_dir), 0.0) * 0.4
	var hv := kick_dir * (KICK_OUT + 0.6 + carry)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = KICK_UP * (0.75 if _kick_same else 1.0)
	# the body already faces the kick (it turned during the plant)
	yaw = atan2(-kick_dir.x, -kick_dir.z)
	rotation.y = yaw
	_kick_turn_t = 0.15
	jumped_this_air = true
	cam.fov += 6.0


## kick direction: camera / steering heading, bent away from the wall (at least ~17 deg off it)
func _kick_heading(n: Vector3) -> Vector3:
	var d := Vector3(_kick_aim.x, 0, _kick_aim.z)
	var dn := d.dot(n)
	if dn < 0.3:
		var t := d - n * dn
		d = t + n * 0.3 if t.length() > 0.2 else n
	return d.normalized()


# ------------------------------------------------------------------ ledges

## finds the top of whatever wall is in front of the feet. returns {} or
## {"top": point on the top surface, "edge": point on the edge, "h": height above feet}
func _ledge_info(into: Vector3, feet: Vector3, max_h: float) -> Dictionary:
	var from := feet + Vector3.UP * (max_h + 0.1) + into * (RADIUS + 0.1)
	var hit := _ray(from, from + Vector3.DOWN * (max_h + 0.1))
	if hit.is_empty() or hit.normal.y < 0.7:
		return {}
	var ledge: float = hit.position.y - feet.y
	if ledge < 0.04 or ledge > max_h:
		return {}
	# the ledge has to be reachable from where the cat is (no mantling through ceilings)
	var head := feet + Vector3.UP * (capsule.height * 0.9)
	var over := Vector3(feet.x, from.y, feet.z)
	if not _ray(head, over).is_empty() or not _ray(over, from).is_empty():
		return {}
	if _point_blocked(from):
		return {}
	# where exactly is the face of the wall
	var c := feet + Vector3.UP * (ledge - 0.04)
	var face := _ray(c - into * 0.05, c + into * (RADIUS + 0.35))
	var edge: Vector3 = hit.position
	if not face.is_empty():
		edge = Vector3(face.position.x, hit.position.y, face.position.z)
	return {"top": hit.position, "edge": edge, "h": ledge}


func _point_blocked(p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_point(q, 1).is_empty()


func _fits(feet: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS * 0.9
	cap.height = STAND_H * 0.9
	params.shape = cap
	params.transform = Transform3D(Basis(), feet + Vector3(0, STAND_H * 0.5 + 0.01, 0))
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


# ------------------------------------------------------------------ climbing

## claws into a grippable surface with normal n (see cat_climb.gd)
func _start_climb(n: Vector3) -> void:
	climber.cling(n)


# ------------------------------------------------------------------ scratching

func _try_scratch() -> bool:
	var fwd := -global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var hit := {}
	for hh in [0.15, 0.3]:
		var c: Vector3 = global_position + Vector3.UP * hh
		hit = _ray(c, c + fwd * 0.38)
		if not hit.is_empty() and absf(hit.normal.y) < 0.35:
			break
	if hit.is_empty() or absf(hit.normal.y) > 0.35:
		return false
	scratching = true
	scratch_n = Vector3(hit.normal.x, 0, hit.normal.z).normalized()
	scratch_t = 0.0
	velocity = Vector3.ZERO
	charging = false
	_aim_root.visible = false
	_event("scratch scratch")
	return true


func _scratch_step(dt: float, held: bool, mv: Vector2) -> void:
	scratch_t += dt
	var c := global_position + Vector3.UP * 0.15
	var hit := _ray(c, c - scratch_n * 0.45)
	if hit.is_empty():
		c = global_position + Vector3.UP * 0.3
		hit = _ray(c, c - scratch_n * 0.45)
	if not held or hit.is_empty() or mv.y < -0.5:
		scratching = false
		return
	scratch_n = Vector3(hit.normal.x, 0, hit.normal.z).normalized()
	# shuffle to the right distance from the surface
	var dist: float = Vector2(hit.position.x - c.x, hit.position.z - c.z).length()
	velocity = -scratch_n * clampf((dist - SCRATCH_DIST) * 8.0, -0.6, 0.6)
	velocity.y = -1.0
	move_and_slide()
	velocity = Vector3.ZERO
	# a fresh set of claw marks every time a paw starts its pull down
	if w_scratch > 0.8:
		for i in 2:
			var sp := fposmod(rig._t * 1.75 + (0.0 if i == 0 else 0.5), 1.0)
			if sp < _rake_prev[i]:
				var paw: Node3D = rig.legs[i].paw
				_add_marks(hit.collider, paw.global_position, hit.position, scratch_n)
			_rake_prev[i] = sp


func _add_marks(col: Object, paw_pos: Vector3, wall_pt: Vector3, n: Vector3) -> void:
	var along := Vector3.UP.cross(n).normalized()
	var base := wall_pt + along * along.dot(paw_pos - wall_pt)
	base.y = paw_pos.y
	var soft := col is Node and ((col as Node).is_in_group("scratchable") or (col as Node).is_in_group("climbable"))
	var colr := Color(0.12, 0.08, 0.06, 0.55) if not soft else Color(0.93, 0.88, 0.75)
	for k in 3:
		var m := MeshInstance3D.new()
		m.mesh = LowPoly.box(0.0)
		m.material_override = LowPoly.mat(colr, 1.0)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(m)
		var len := randf_range(0.07, 0.1)
		m.global_transform = Transform3D(Basis(along * 0.0035, Vector3.UP * len, n * 0.002), base + along * (k - 1) * 0.0095 + Vector3.DOWN * len * 0.5 + n * 0.001)
		_marks.append(m)
	if soft:
		# fluff + sisal bits fly off
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 10
		p.lifetime = 0.9
		p.explosiveness = 0.85
		p.direction = n
		p.spread = 50
		p.initial_velocity_min = 0.3
		p.initial_velocity_max = 0.8
		p.gravity = Vector3(0, -2.0, 0)
		p.scale_amount_min = 0.004
		p.scale_amount_max = 0.008
		var pm := BoxMesh.new()
		pm.size = Vector3.ONE
		pm.material = LowPoly.mat(Color(0.92, 0.86, 0.7), 1.0)
		p.mesh = pm
		get_tree().current_scene.add_child(p)
		p.global_position = base + n * 0.01
		p.emitting = true
		get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	while _marks.size() > 120:
		var old: Node3D = _marks.pop_front()
		old.queue_free()


# ------------------------------------------------------------------ aimed leap

## figures out where the crosshair is pointing and how to get there. shows a ring
## + the arc so you can see exactly where the cat will land before you let go
func _update_aim() -> void:
	aim_valid = false
	_aim_ok_age += get_physics_process_delta_time()
	var from := _aim_pos()
	var dir := _look_dir()
	var hit := _ray(from, from + dir * (LEAP_RANGE + 1.2))
	if hit.is_empty():
		_aim_root.visible = false
		return
	var feet := global_position
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var kind := "land"
	var nh := Vector3.ZERO
	if n.y < 0.7:
		if absf(n.y) > 0.4:
			_aim_root.visible = false
			return
		# looking at the side of something: find its top
		nh = Vector3(n.x, 0, n.z).normalized()
		var found := false
		for up in [1.0, 0.6, 0.35, 0.15]:
			var s: Vector3 = p - nh * 0.07 + Vector3.UP * up
			if _point_blocked(s) or not _ray(p + nh * 0.06, s + nh * 0.13).is_empty():
				continue
			var th := _ray(s, Vector3(s.x, p.y - 0.05, s.z))
			if not th.is_empty() and th.normal.y > 0.7:
				p = th.position
				found = true
				break
		if not found:
			_aim_root.visible = false
			return
		var face := _ray(Vector3(p.x, p.y - 0.04, p.z) + nh * 0.3, Vector3(p.x, p.y - 0.04, p.z) - nh * 0.1)
		var edge := p + nh * 0.07
		if not face.is_empty():
			edge = Vector3(face.position.x, p.y, face.position.z)
		p = edge - nh * (RADIUS + 0.14)
		ledge_point = edge
		ledge_n = nh
	# hunting aim assist: prey is tiny, so anything the crosshair passes close to counts
	var prey: Node3D = null
	if hit.collider is Node and (hit.collider as Node).is_in_group("prey"):
		prey = hit.collider
	else:
		for pr in get_tree().get_nodes_in_group("prey"):
			var pp: Vector3 = (pr as Node3D).global_position
			var along := (pp - from).dot(dir)
			if along > 0.2 and along < LEAP_RANGE + 1.0 and dir.angle_to(pp - from) < 0.2:
				prey = pr
				break
	if prey:
		# land so the forepaws come down right on top of it
		var q: Vector3 = prey.global_position
		var to := Vector3(q.x - feet.x, 0, q.z - feet.z)
		p = Vector3(q.x, q.y, q.z) - to.normalized() * 0.15
		n = Vector3.UP
	var dh := p.y - feet.y
	var flat := Vector3(p.x - feet.x, 0, p.z - feet.z)
	var d := flat.length()
	var ok := d <= LEAP_RANGE and not (d < 0.2 and dh < 0.15)
	var target := p
	if dh > POUNCE_MAX - 0.05:
		# too high to land on: leap to grab the edge and haul up
		if nh == Vector3.ZERO or dh > POUNCE_MAX - 0.05 + CLAMBER_MAX - HANG:
			ok = false
		else:
			kind = "grab"
			target = Vector3(ledge_point.x, ledge_point.y - HANG, ledge_point.z) + nh * (RADIUS + 0.03)
			dh = target.y - feet.y
			flat = Vector3(target.x - feet.x, 0, target.z - feet.z)
			d = flat.length()
	elif not _fits(p + Vector3.UP * 0.02):
		ok = false
	# ballistic arc: apex a bit above the target, more for longer leaps
	var apex := maxf(dh, 0.0) + (0.2 + 0.07 * d if kind == "land" else 0.06)
	apex = minf(apex, POUNCE_MAX + 0.05)
	if apex < dh + 0.02:
		ok = false
	var vy := sqrt(2.0 * G * maxf(apex, 0.05))
	var t_total := vy / G + sqrt(2.0 * maxf(apex - dh, 0.0) / G)
	var vh := d / maxf(t_total, 0.05)
	if vh > 7.5:
		ok = false
	var hdir := flat / d if d > 0.001 else Vector3.ZERO
	aim_vel = hdir * vh + Vector3.UP * vy
	aim_point = target
	aim_kind = kind
	aim_valid = ok
	if ok:
		_aim_ok_age = 0.0
		_aim_ok_vel = aim_vel
		_aim_ok_point = aim_point
		_aim_ok_kind = kind
	# marker
	_aim_root.visible = true
	_aim_root.global_transform = Transform3D.IDENTITY
	var col := Color(0.45, 1.0, 0.55, 0.8) if kind == "land" else Color(1.0, 0.85, 0.3, 0.85)
	if not ok:
		col = Color(1.0, 0.35, 0.3, 0.6)
	(_aim_ring.material_override as StandardMaterial3D).albedo_color = col
	var ring_at := p if kind == "land" else ledge_point - ledge_n * 0.04
	_aim_ring.global_transform = Transform3D(Basis().scaled(Vector3(0.16, 0.004, 0.16)), ring_at + Vector3.UP * 0.006)
	for r in _paw_rings:
		r.visible = false
	var start := feet + Vector3.UP * 0.12
	for k in _aim_dots.size():
		var tt := t_total * float(k + 1) / (_aim_dots.size() + 1)
		var dp := start + hdir * vh * tt + Vector3.UP * (vy * tt - 0.5 * G * tt * tt)
		_aim_dots[k].global_position = dp
		_aim_dots[k].visible = ok


func _leap() -> void:
	if not aim_valid:
		aim_vel = _aim_ok_vel
		aim_point = _aim_ok_point
		aim_kind = _aim_ok_kind
	_aim_ok_age = 99.0
	leaps += 1
	stamina.spend(CatStamina.LEAP)
	velocity = aim_vel
	leap_lock = true
	_aim_root.visible = false
	_event("leap (%s %.1fm)" % [aim_kind, aim_point.y - global_position.y])


## falls only cost health where health matters (the rat pit sets fall_damage) and for bots
## (labs + tests measure it). everywhere else a fall past LAND_HARD is a stumble
var fall_damage := false


func fall_hurts() -> bool:
	return fall_damage or combat_on()


func _on_land() -> void:
	var dodge_land := dash.state == CatDash.AIR
	dash.on_land()
	var impact := -prev_vy
	land_dip_v -= clampf(impact * 0.12, 0.0, 0.9)
	paws.land(impact)
	last_impact = impact
	if real_move and impact > LAND_FREE:
		var set_up := stick_armed and (pounce_air or dodge_land)
		var over := clampf((impact - LAND_HARD) / (FALL_TERMINAL - LAND_HARD), 0.0, 1.0)
		if impact > LAND_HARD and fall_hurts():
			health.fall(lerpf(FALL_DMG_MIN, FALL_DMG_MAX, over))
		if not set_up or impact > LAND_HARD:
			var hard := clampf((impact - LAND_SOFT) / (LAND_HARD - LAND_SOFT), 0.0, 1.0)
			var keep_v := LAND_KEEP_SOFT if impact <= LAND_SOFT else lerpf(LAND_KEEP_SOFT, LAND_KEEP_HARD, hard)
			velocity.x *= keep_v
			velocity.z *= keep_v
			land_rec = LAND_REC_SOFT if impact <= LAND_SOFT else lerpf(LAND_REC_SOFT, LAND_REC_MAX, hard)
			_event("landed hard (%.1f m/s)" % impact if impact > LAND_SOFT else "soft landing")
			if impact > LAND_HARD and not fall_hurts():
				# outside the rat pit a big fall costs time, not health: the cat stumbles, sits low
				# a beat longer and has to start its run again (simplify pass 2026-11-21)
				velocity.x *= 0.4
				velocity.z *= 0.4
				land_rec = LAND_REC_MAX + lerpf(0.25, 0.6, over)
				land_dip_v -= 0.4
				_event("stumbled (%.1f m/s)" % impact)
	if stick_armed and (pounce_air or dodge_land):
		# stuck it: four paws down and the body stops right there, no skid, no steps after
		land_stick = 0.3 if pounce_air else CatDash.STICK
		velocity.x = 0.0
		velocity.z = 0.0
		if pounce_air:
			combat.land_recover()
		else:
			_dodge_land_t = 0.0
		var off := Vector2(global_position.x - pounce_land.x, global_position.z - pounce_land.z).length() if pounce_land != Vector3.INF else 99.0
		if off < 0.12 and absf(global_position.y - pounce_land.y) < 0.1:
			# right where the circle said: settle onto the exact spot (the last physics step can
			# slide a couple of cm along the floor) and plant the paws on their circles
			var tp := Vector3(pounce_land.x, global_position.y, pounce_land.z)
			if _fits(tp):
				global_position = tp
				_phys_curr = tp
			if pounce_air:
				yaw = pounce_yaw
				rotation.y = yaw
			_spots_t = 1.4 if pounce_air else 0.8
		else:
			_clear_spots()   # it hit something else on the way: the paws find their own footing
	elif _spots_t <= 0.0:
		_clear_spots()
	_end_pounce_prey()
	stick_armed = false
	if pounce_air:
		pounce_air = false
		rig.pin = 1.0
		paws.pin()
		_pin_check()


## the four spots a pounce's paws come down on (the same ones the aim circles show)
func set_spots(spots: Array) -> void:
	rig.pounce_spots = spots
	rig.gait.land_spots = spots
	_spots_t = 0.0


func _clear_spots() -> void:
	rig.pounce_spots = []
	rig.gait.land_spots = []
	_spots_t = 0.0


func _end_pounce_prey() -> void:
	if pounce_prey != null and is_instance_valid(pounce_prey) and pounce_prey is PhysicsBody3D:
		remove_collision_exception_with(pounce_prey)
	pounce_prey = null


## forepaws come down together: anything small under them gets pinned
func _pin_check() -> void:
	var fwd := -global_transform.basis.z
	var pin_pt := global_position + fwd * 0.16 + Vector3.UP * 0.05
	var params := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.16
	params.shape = sph
	params.transform = Transform3D(Basis(), pin_pt)
	params.exclude = [get_rid()]
	for r in get_world_3d().direct_space_state.intersect_shape(params, 8):
		var col: Object = r.collider
		if col == carried:
			continue
		if col is Node and (col as Node).is_in_group("prey"):
			_catch(col)
			return
		elif col is RigidBody3D:
			(col as RigidBody3D).apply_central_impulse(Vector3.DOWN * 0.3 + fwd * 0.2)
	for n in get_tree().get_nodes_in_group("prey"):
		if n is Node3D and n != carried:
			var d: Vector3 = (n as Node3D).global_position - pin_pt
			if Vector2(d.x, d.z).length() < 0.24 and absf(d.y) < 0.3:
				_catch(n)
				return

# ------------------------------------------------------------------ hunting

func _prey_name(n: Object) -> String:
	if n is ToyMouse:
		return "toy mouse"
	if "kind" in n:
		return str(n.get("kind"))
	if n is Node and String((n as Node).get_class()) != "":
		var cn := String((n as Object).get_script().get_global_name()) if (n as Object).get_script() else ""
		if cn == "FieldMouse":
			return "field mouse"
	return "mouse"


## caught something: it stops struggling and goes in the mouth
func _catch(n: Object) -> void:
	if n.has_method("pin_hit"):
		n.call("pin_hit", self)   # too big to carry (arena rats): the pounce lands as a heavy hit
		if n is Node3D:
			combat._slam_fx(n)
		return
	if carried:
		_drop_carried()
	if n.has_method("pinned"):
		n.call("pinned")
	carried = n as Node3D
	if carried is PhysicsBody3D:
		add_collision_exception_with(carried)
		if carried is RigidBody3D:
			(carried as RigidBody3D).freeze = true
	catches += 1
	rig.pin = 1.0
	paws.pin()
	_event("caught a %s! (%d caught · e to drop)" % [_prey_name(n), catches])


func _drop_carried() -> void:
	if not is_instance_valid(carried):
		carried = null
		return
	var n := carried
	carried = null
	var fwd := -global_transform.basis.z
	n.global_position = global_position + fwd * 0.2 + Vector3.UP * 0.03
	if n is PhysicsBody3D:
		remove_collision_exception_with(n)
	# catch and release: it shakes itself off and runs again
	if n.has_method("released"):
		n.call("released")
	else:
		if "caught" in n:
			n.set("caught", false)
		if n is RigidBody3D:
			(n as RigidBody3D).freeze = false
	_event("dropped the " + _prey_name(n))


func _carry_follow() -> void:
	if carried == null:
		return
	if not is_instance_valid(carried):
		carried = null
		return
	var hx: Transform3D = rig.head.global_transform if rig.head else global_transform
	carried.global_transform = Transform3D(hx.basis.orthonormalized() * Basis(Vector3.UP, PI * 0.5), hx * Vector3(0, -0.035, -0.07))


## stalking: tells you about the nearest prey in front of you
func _hunt_scan() -> void:
	hunt_info = ""
	if crouch_amt < 0.5 and not charging:
		return
	var best: Node3D = null
	var bd := 6.0
	var fwd := _look_dir()
	for n in get_tree().get_nodes_in_group("prey"):
		if not n is Node3D or n == carried or ("caught" in n and n.get("caught")):
			continue
		var d: Vector3 = (n as Node3D).global_position - global_position
		if d.length() < bd and fwd.angle_to(d) < 0.7:
			bd = d.length()
			best = n
	if best:
		hunt_info = "%s %.1f m%s" % [_prey_name(best), bd, " · pounce range!" if bd < POUNCE_MAX + 0.3 else ""]


# ------------------------------------------------------------------ grip

func _update_surface() -> void:
	if not is_on_floor():
		return
	var hit := _ray(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 0.08)
	if hit.is_empty():
		return
	var c: Object = hit.collider
	var sf := "default"
	if c is Node:
		var nd := c as Node
		if nd.has_meta("surface_at"):
			sf = (nd.get_meta("surface_at") as Callable).call(hit.position)
		elif nd.has_meta("surface"):
			sf = nd.get_meta("surface")
		elif nd.is_in_group("climbable") or nd.is_in_group("scratchable"):
			sf = "carpet"
	surface = sf


func _slip_fx(_dt: float, hv: Vector3) -> void:
	var soft := surface in ["grass", "dirt", "hay"]
	var feet := global_position + Vector3.UP * 0.01
	if soft and feet.distance_to(_tear_last) > 0.09:
		_tear_last = feet
		# torn up turf: a dark scuff lying along the slide
		var m := MeshInstance3D.new()
		m.mesh = LowPoly.box(0.1)
		m.material_override = LowPoly.mat(Color(0.32, 0.24, 0.15) if surface != "hay" else Color(0.6, 0.5, 0.28), 1.0)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(m)
		var along := hv.normalized() if hv.length() > 0.1 else -global_transform.basis.z
		var side := along.cross(Vector3.UP).normalized()
		var w := 0.045 + slip * 0.04
		m.global_transform = Transform3D(Basis(side * w, Vector3.UP * 0.006, along * (0.09 + slip * 0.08)), feet + side * randf_range(-0.04, 0.04) + Vector3.UP * 0.004)
		_tears.append(m)
		while _tears.size() > 220:
			var old: Node3D = _tears.pop_front()
			old.queue_free()
	# the dust itself comes from the paws that are digging in (paw_dust.gd)


# ------------------------------------------------------------------ camera

## sweeps a small sphere from a to b, returns how far (0..1) it gets before touching something
func _sweep(a: Vector3, b: Vector3, r: float) -> float:
	var params := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = r
	params.shape = sph
	params.transform = Transform3D(Basis(), a)
	params.motion = b - a
	params.exclude = [get_rid()]
	var res := get_world_3d().direct_space_state.cast_motion(params)
	if res.is_empty():
		return 1.0
	return res[0]


## stair camera: the camera's height (_sc_y) chases the body's height on a critically damped
## spring whose target speed is the body's climb rate low passed over a few steps. a flight of
## steps (each one a pop or a quick hop) becomes one even slope, a single curb a soft glide,
## a ramp is tracked with no lag. in the air, climbing, clambering or rearing the spring lets go
## fast (no lag on jumps), and big moves (teleport, respawn) snap.
func _step_cam(dt: float) -> void:
	# (the visible cat's height: with the soft root the capsule hops onto a step and the cat seen
	# on screen walks up after it, so the spring follows the walk, not the hop)
	var vis := global_position + _soft_off
	var ty := vis.y
	var moved := vis.distance_to(_sc_last)
	_sc_last = vis
	if not _sc_ok or absf(ty - _sc_y) > 0.6 or dt <= 0.0 or moved > 0.4:
		_hs_ok = false   # teleport / respawn / lab reset: the head cam snaps too
		_sc_act = 0.0
		_sc_ok = true
		_sc_y = ty
		_sc_v = 0.0
		_sc_tv = 0.0
		_sc_body_y = ty
		step_cam_off = 0.0
		return
	var v := (ty - _sc_body_y) / dt
	var prev_off := _sc_y - _sc_body_y
	_sc_body_y = ty
	# running down steps the cat drops off each one (a short fall, not a jump): keep gliding through that
	if is_on_floor() or mantling:
		_sc_air = 0.0
		_sc_jumped = false
	else:
		if _sc_air == 0.0 and velocity.y > 0.6:
			_sc_jumped = true
		_sc_air += dt
	var drop := _sc_air > 0.0 and _sc_air < 0.4 and not _sc_jumped
	# only while the ground under the paws is actually going up or down (steps, curbs, ramps): on
	# flat ground the camera rides the head exactly like before (pounce crouch, swats, dodges, kicks)
	var grounded := is_on_floor() or (mantling and mantle_quick > 0.0)
	# (moving up or down more than its own velocity explains: a step pop, a floor snap, a quick
	# mantle, a ramp. a jump or a hop moves it by its velocity and doesn't count)
	# (a landing doesn't count either: it has to have been on the ground a moment already, so the
	# floor snap settling a pounce landing isn't taken for a step)
	if grounded and _sc_ground_t > 0.06 and absf(v - velocity.y) > 0.25:
		_sc_act = 0.6
	else:
		_sc_act = maxf(0.0, _sc_act - dt)
	_sc_ground_t = _sc_ground_t + dt if grounded else 0.0
	var stairs := _sc_act > 0.0 and (grounded or drop) and not (clambering or climbing or scratching) and w_kick < 0.05
	_sc_stairs = stairs
	if stairs:
		_sc_tv = lerpf(_sc_tv, clampf(v, -6.0, 6.0), 1.0 - exp(-dt / _sc_tau()))
		var r := _stair_spring(_sc_y, _sc_v, _sc_tv, ty, dt, Vector2(velocity.x, velocity.z).length())
		_sc_y = r.x
		_sc_v = r.y
	else:
		# off the stairs: hand the camera straight back to the body, just without a snap
		_sc_tv = 0.0   # (a landing hands over with no climb rate)
		_sc_y = ty + prev_off * exp(-14.0 * dt)   # the offset fades, the camera moves with the body
		_sc_v = clampf(v, -3.0, 3.0)
	# never sink the eye through the step it's on or float far over it
	_sc_y = clampf(_sc_y, ty - 0.3, ty + 0.2)
	step_cam_off = _sc_y - ty


## climb rate low pass time, shorter on a faster run (same stretch of stairs)
func _sc_tau() -> float:
	return STEP_CAM_V_TAU / maxf(1.0, Vector2(velocity.x, velocity.z).length() / 3.2)


## height of whatever the eye would sit over at p (sphere cast down from a bit above `top`),
## -INF when there's nothing within reach
func _cam_floor(p: Vector3, top: float) -> float:
	var a := Vector3(p.x, top + 0.12, p.z)
	var f := _sweep(a, a + Vector3.DOWN * 0.5, 0.03)
	if f >= 1.0:
		return -INF
	if f <= 0.0:
		return a.y   # starts inside something: it's at least that high there
	return a.y - 0.5 * f - 0.03


## one exact critically damped spring step (no overshoot, stable at any tick rate) of a camera
## height y (speed yv) toward a target now at `to` moving at tv. falling far behind (a gallop up
## tall steps) stiffens it smoothly instead of hitting a hard limit. returns (y, yv)
## faster runs (hspd m/s) tighten it too, so it smooths over about the same stretch of stairs
static func _stair_spring(y: float, yv: float, tv: float, to: float, dt: float, hspd: float) -> Vector2:
	var x := y - (to - tv * dt)   # the target moved along at tv during this step
	var w := STEP_CAM_W * maxf(1.0, hspd / 3.2) * maxf(1.0, absf(x) / STEP_CAM_SOFT)
	var u := yv - tv
	var e := exp(-w * dt)
	var j := u + w * x
	return Vector2(to + (x + j * dt) * e, tv + (u - w * j * dt) * e)


## head cam version of the stair spring, per rendered frame on the head's world height. it rides
## out the body's step pops and the rig's own step-up pose (the head ducks and rises on every quick
## mantle) in one go. same rules as _step_cam: off the stairs it hands straight back to the head
func _head_step_y(raw: float, dt: float) -> float:
	if not _hs_ok or absf(raw - _hs.x) > 0.6 or dt <= 0.0:
		_hs_ok = true
		_hs = Vector4(raw, 0.0, 0.0, raw)
		return raw
	var v := (raw - _hs.w) / dt
	var y := _hs.x
	var yv := _hs.y
	var tv := _hs.z
	if _sc_stairs:
		tv = lerpf(tv, clampf(v, -6.0, 6.0), 1.0 - exp(-dt / _sc_tau()))
		var r := _stair_spring(y, yv, tv, raw, dt, Vector2(velocity.x, velocity.z).length())
		y = r.x
		yv = r.y
	else:
		tv = 0.0
		y = raw + (_hs.x - _hs.w) * exp(-14.0 * dt)   # the offset fades, the camera moves with the head
		yv = clampf(v, -3.0, 3.0)
	y = clampf(y, raw - 0.3, raw + 0.2)
	_hs = Vector4(y, yv, tv, raw)
	return y


## render rate step camera offset (between the last two physics ticks, like the body)
func step_cam_frame() -> float:
	if not step_cam:
		return 0.0
	return lerpf(_sc_off_prev, step_cam_off, Engine.get_physics_interpolation_fraction())


## keeps the first person eye inside open space: swept from the middle of the body
## so it never pokes through a wall, ceiling, shelf underside or the climbed surface
func _safe_eye(eye_local: Vector3) -> Vector3:
	var from := global_position + Vector3.UP * minf(capsule.height * 0.5, 0.12)
	var to := global_transform * eye_local
	var f := _sweep(from, to, 0.03)
	if f >= 1.0:
		return eye_local
	return global_transform.affine_inverse() * from.lerp(to, f)


## orbit camera: pivot above the cat, boom pulled in instantly on contact, eased back out
func _third_person_cam(dt: float) -> void:
	var piv := _safe_eye(Vector3(0, 0.45 + (step_cam_off if step_cam else 0.0), 0))
	eye_local = piv
	var a := global_transform * piv
	var want := 1.25
	var b := a + Basis(Vector3.UP, orb_yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, want)
	var d := want * _sweep(a, b, 0.07) - 0.02
	d = maxf(d, 0.05)
	_tp_dist = d if d < _tp_dist else LowPoly.damp(_tp_dist, d, 4.0, dt)
	cam.position = Vector3(0, 0, _tp_dist)


## free orbit around the cat: mouse orbits, scroll zooms, boom pulls in on contact
func _orbit_cam(dt: float) -> void:
	var piv := _safe_eye(Vector3(0, 0.2 + (step_cam_off if step_cam else 0.0), 0))
	eye_local = piv
	var a := global_transform * piv
	var b := a + Basis(Vector3.UP, orb_yaw) * Basis(Vector3.RIGHT, orb_pitch) * Vector3(0, 0, orb_dist)
	var d := maxf(orb_dist * _sweep(a, b, 0.07) - 0.02, 0.05)
	_orb_d = d if d < _orb_d else LowPoly.damp(_orb_d, d, 4.0, dt)
	cam.position = Vector3(0, 0, _orb_d)


# ------------------------------------------------------------------ swat + claws

## the loose object nearest the crosshair that a forepaw can reach (aim assist for paws)
func _paw_target(reach: float, cone: float) -> Dictionary:
	# (from where the eye rests: the head's own bob, a couple of cm up or down as the body
	# settles, must not decide whether a paw finds what's in front of it)
	var eye := _eye_pos() - global_transform.basis.y * _eye_bob
	var dir := _look_dir()
	var params := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = reach
	params.shape = sph
	params.transform = Transform3D(Basis(), eye)
	params.exclude = [get_rid()]
	var best := {}
	var best_s := 1e9
	for r in get_world_3d().direct_space_state.intersect_shape(params, 32):
		if not r.collider is RigidBody3D or r.collider == carried:
			continue
		var rb: RigidBody3D = r.collider
		if rb.freeze and not rb.is_in_group("prey"):
			continue
		var c := rb.global_position
		var to_c := c - eye
		var ang := dir.angle_to(to_c)
		if ang > cone:
			continue
		# what the paw actually touches: ray from the eye at the body
		var q := PhysicsRayQueryParameters3D.create(eye, c + to_c.normalized() * 0.05)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or hit.collider != rb:
			continue   # something in the way
		var dist: float = (hit.position - eye).length()
		if dist > reach:
			continue
		var score := ang + dist * 0.6
		if score < best_s:
			best_s = score
			best = {"rb": rb, "point": hit.position, "normal": hit.normal, "prey": rb if rb.is_in_group("prey") else null}
	# prey that isn't a physics body (forest critters): distance + line of sight
	for n in get_tree().get_nodes_in_group("prey"):
		if n is RigidBody3D or not n is Node3D or n == carried:
			continue
		var c: Vector3 = (n as Node3D).global_position + Vector3.UP * 0.03
		var to_c := c - eye
		var dist := to_c.length()
		if dist > reach:
			continue
		var ang := dir.angle_to(to_c)
		if ang > cone:
			continue
		var hit := _ray(eye, c)
		if not hit.is_empty() and hit.collider != n and (hit.position - eye).length() < dist - 0.06:
			continue   # something in the way (prey with its own collider doesn't block itself)
		var score := ang + dist * 0.6
		if score < best_s:
			best_s = score
			best = {"rb": null, "point": c, "normal": -to_c.normalized(), "prey": n}
	return best

var _swat_rake := false
var _swat_pt := Vector3.ZERO      # world point the paw strikes (for the slash fx)

## paw 0 = left, 1 = right, -1 = random (auto swat). rake = one of a held paw's repeated rakes
func _do_swat(paw := -1, rake := false) -> void:
	if paw < 0:
		paw = randi() % 2
	_swat_rake = rake
	_swat_side = -1.0 if paw == 0 else 1.0
	var t := _paw_target(SWAT_RANGE, 0.5)
	var wt: Vector3
	if not t.is_empty():
		_swat_rb = t.rb
		_swat_prey = t.get("prey")
		wt = t.point
		paws.swat(paw, paw_anchor.to_local(t.point))
	else:
		_swat_rb = null
		_swat_prey = null
		var dir := _look_dir()
		var hit := _ray(_eye_pos(), _eye_pos() + dir * 0.4)
		wt = hit.position if not hit.is_empty() else swat_box()
		paws.swat(paw, paw_anchor.to_local(hit.position) if not hit.is_empty() else null)
	# the real foreleg swats too (seen in third person / orbit, and in the shadow)
	if rig.has_method("swat"):
		var sh := global_transform * Vector3((-0.04 if paw == 0 else 0.04), 0.17, -0.13)
		rig.swat(paw, sh + (wt - sh).limit_length(0.27))
	_swat_pt = wt
	if clawing and paw == paws.claw_i:
		_claw_release()
	_swat_hit_t = 0.12   # paw lands at the end of the strike, not on the click

## where the strike's hitbox is right now: out in front of the eye, carried along with the cat
## (the far end of it: that's where the claws are going)
func swat_box() -> Vector3:
	return _eye_pos() + _look_dir() * SWAT_HIT_FWD


## distance from a point to the strike's hitbox core (the segment along the look line)
func _swat_box_d(q: Vector3) -> float:
	var a := _eye_pos() + _look_dir() * SWAT_HIT_NEAR
	var b := swat_box()
	var ab := b - a
	var u := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return q.distance_to(a + ab * u)


func _swat_impact() -> void:
	var dir := _look_dir()
	var sweep := -cam.global_transform.basis.x * _swat_side   # paw whips across from its own side
	_swat_done = []
	_swat_live = SWAT_LIVE
	var hits: Array[RigidBody3D] = []
	if is_instance_valid(_swat_rb) and _swat_rb.global_position.distance_to(_eye_pos()) < SWAT_RANGE + 0.15:
		hits.append(_swat_rb)
	for rb in _box_bodies():
		if not hits.has(rb):
			hits.append(rb)
	# prey gets knocked silly (a stunned mouse is an easy pounce)
	var prey_hit := is_instance_valid(_swat_prey) and _swat_prey.global_position.distance_to(_eye_pos()) < SWAT_RANGE + 0.15
	if not prey_hit:
		# nothing locked at the click: whatever the lunge carried the hitbox onto
		var np := _box_prey()
		if np != null:
			_swat_prey = np
			prey_hit = true
	_slash_fx(dir, sweep, _swat_prey if prey_hit else null, hits)
	if prey_hit:
		_hit_prey(_swat_prey)
	_hit_bodies(hits, dir, sweep)


## the hitbox is still out: anything the lunge carries it onto gets hit too (once per strike)
func _swat_sweep() -> void:
	var dir := _look_dir()
	var sweep := -cam.global_transform.basis.x * _swat_side
	var np := _box_prey()
	if np != null:
		_swat_prey = np
		_hit_prey(np)
		SlashFx.sparks(self, np.global_position + Vector3.UP * 0.04, (_eye_pos() - np.global_position).normalized(), np.is_in_group("enemy"), 8)
	var hits: Array[RigidBody3D] = []
	for rb in _box_bodies():
		hits.append(rb)
	_hit_bodies(hits, dir, sweep)


## rigid bodies inside the strike's hitbox (not hit yet this strike)
func _box_bodies() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = SWAT_HIT_R
	cap.height = SWAT_HIT_FWD - SWAT_HIT_NEAR + SWAT_HIT_R * 2.0
	params.shape = cap
	var dir := _look_dir()
	var mid := _eye_pos() + dir * (SWAT_HIT_NEAR + SWAT_HIT_FWD) * 0.5
	# capsules stand along y: turn y onto the look line
	var ax := Vector3.UP.cross(dir)
	var bas := Basis(ax.normalized(), Vector3.UP.angle_to(dir)) if ax.length() > 0.001 else Basis()
	params.transform = Transform3D(bas, mid)
	params.exclude = [get_rid()]
	for r in get_world_3d().direct_space_state.intersect_shape(params, 8):
		if r.collider is RigidBody3D and not _swat_done.has(r.collider) and r.collider != carried:
			out.append(r.collider)
	return out


## prey / enemies whose body is inside the strike's hitbox (not hit yet this strike)
func _box_prey() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("prey"):
		if not n is Node3D or n == carried or _swat_done.has(n):
			continue
		var rad: float = 0.16 * float(n.get("s")) if "s" in n else 0.06
		var q: Vector3 = (n as Node3D).global_position + Vector3.UP * 0.04
		var d := _swat_box_d(q) - rad
		if d < SWAT_HIT_R and d < best_d:
			best_d = d
			best = n
	return best


func _hit_prey(n: Node3D) -> void:
	if _swat_done.has(n):
		return
	_swat_done.append(n)
	if _swat_rake and n.has_method("take_hit"):
		n.call("take_hit", CatCombat.RAKE_DMG, global_position, false, CatCombat.RAKE_POISE)
	elif n.has_method("stun"):
		n.call("stun", 1.6)
	_event("swatted the " + _prey_name(n) + "!")


func _hit_bodies(hits: Array[RigidBody3D], dir: Vector3, sweep: Vector3) -> void:
	var any := false
	for rb in hits:
		if rb == carried or _swat_done.has(rb):
			continue
		_swat_done.append(rb)
		if rb.freeze:
			if rb.is_in_group("prey"):
				continue
			rb.freeze = false
		# paw (effective mass PAW_MASS at PAW_SPEED) hits a body: J = (1+e) * mu * v
		var mu := PAW_MASS * rb.mass / (PAW_MASS + rb.mass)
		var push := (sweep * 0.7 + dir * 0.6 + Vector3.UP * 0.35).normalized()
		var j := push * (1.0 + 0.4) * mu * PAW_SPEED
		# off-centre contact (paw comes from the side, a bit high) gives a spin
		var off := -sweep * 0.025 + Vector3.UP * 0.015
		rb.sleeping = false
		rb.apply_impulse(j, off)
		any = true
	if any:
		_event("swat!")


## claw streak along the swipe + sparks / scratch lines where it connects (slash_fx.gd)
func _slash_fx(dir: Vector3, sweep: Vector3, prey: Node3D, hits: Array[RigidBody3D]) -> void:
	var eye := _eye_pos()
	# out where the strike's hitbox is now (the lunge carried it), or on what got locked at the click
	var c := swat_box()
	if is_instance_valid(_swat_rb) and hits.has(_swat_rb):
		c = _swat_pt
	if prey != null:
		var q := prey.global_position + Vector3.UP * 0.06 * float(prey.get("s") if "s" in prey else 0.5)
		c = q + (eye - q).normalized() * 0.04
	var a := c - sweep * 0.17 + Vector3.UP * 0.07
	var b := c + sweep * 0.14 - Vector3.UP * 0.05
	SlashFx.streak(self, a, b, -dir * 0.05 + Vector3.UP * 0.015, Color(1.0, 0.82, 0.78) if prey != null else Color(1.0, 0.95, 0.85), self)
	var n := (eye - c).normalized()
	if prey != null:
		var flesh := prey.is_in_group("enemy")
		SlashFx.sparks(self, c, n + sweep * 0.6, flesh, 12 if flesh else 6)
		if flesh:
			SlashFx.wound(prey, c, n, sweep)
	elif not hits.is_empty():
		SlashFx.sparks(self, c, n + sweep * 0.6, false, 6)
	else:
		var hit := _ray(eye, eye + (c - eye).normalized() * ((c - eye).length() + 0.12))
		if not hit.is_empty():
			SlashFx.sparks(self, hit.position, hit.normal, false, 5)


func _claw_start(paw := -1) -> void:
	clawing = true
	paws.claw_i = paw if paw >= 0 else randi() % 2
	paws.claw_on = true
	if "claw_on" in rig:
		rig.claw_on = true
		rig.claw_i = paws.claw_i
		rig.claw_target = _eye_pos() + _look_dir() * 0.25
	claw_rb = null
	claw_static = false
	var t := _paw_target(0.6, 0.45)
	if not t.is_empty() and t.get("prey") and t.prey != carried:
		_catch(t.prey)
		_claw_release()
		return
	if not t.is_empty() and t.rb:
		claw_rb = t.rb
		if claw_rb.freeze and not claw_rb.is_in_group("prey"):
			claw_rb = null
		else:
			claw_rb.freeze = false
			claw_local = claw_rb.to_local(t.point)
			claw_dist = clampf((t.point - _eye_pos()).length(), 0.2, 0.4)
			_event("hooked")
			return
	var dir := _look_dir()
	var hit := _ray(_eye_pos(), _eye_pos() + dir * 0.45)
	if not hit.is_empty() and not hit.collider is RigidBody3D:
		claw_static = true
		claw_pt = hit.position
		claw_n = hit.normal
		claw_col = hit.collider
		_claw_last_mark = claw_pt
		_event("claws in")


func _claw_release() -> void:
	clawing = false
	paws.claw_on = false
	if "claw_on" in rig:
		rig.claw_on = false
	if is_instance_valid(claw_rb):
		if claw_rb.is_in_group("prey") and claw_rb.get("caught"):
			claw_rb.freeze = true
		_event("let go")
	claw_rb = null
	claw_static = false


func _claw_step(dt: float) -> void:
	var eye := _eye_pos()
	var dir := _look_dir()
	if is_instance_valid(claw_rb):
		stamina.drain(CatStamina.CLAW_DRAG, dt)
		# hooked body: spring-damper pulls the hook point toward where you look,
		# limited to what one forepaw can pull. heavy things drag, light things lift
		var g := claw_rb.to_global(claw_local)
		var hold := eye + dir * claw_dist
		if (g - eye).length() > 0.8:
			_claw_release()
			return
		var m := claw_rb.mass
		var w := 14.0
		var v_g := claw_rb.linear_velocity + claw_rb.angular_velocity.cross(g - claw_rb.global_position)
		var f := m * (w * w * (hold - g) - 2.0 * 0.8 * w * (v_g - velocity))
		f += Vector3.UP * m * 9.8 * clampf(0.5 / maxf(m, 0.01), 0.0, 1.0) * 0.9   # lift what's light enough
		f = f.limit_length(CLAW_FORCE)
		claw_rb.sleeping = false
		claw_rb.apply_force(f, g - claw_rb.global_position)
		paws.claw_target = paw_anchor.to_local(g)
		_rig_claw(g)
		return
	if claw_static:
		if not is_instance_valid(claw_col):
			_claw_release()
			return
		# the hooked claws stay put and get dragged along the surface toward the crosshair
		var den := dir.dot(claw_n)
		var want := claw_pt
		if absf(den) > 0.05:
			var tt := (claw_pt - eye).dot(claw_n) / den
			if tt > 0.0:
				want = eye + dir * tt
		want = claw_pt + (want - claw_pt).limit_length(0.6 * dt)   # claws drag, they don't glide
		# keep it on the surface + within reach
		var hit := _ray(want + claw_n * 0.05, want - claw_n * 0.05)
		if not hit.is_empty() and not hit.collider is RigidBody3D and hit.normal.dot(claw_n) > 0.7:
			claw_pt = hit.position
			claw_n = hit.normal
			claw_col = hit.collider
		if (claw_pt - eye).length() > 0.48:
			_claw_release()
			return
		if claw_pt.distance_to(_claw_last_mark) > 0.04:
			_claw_stroke(claw_col, _claw_last_mark, claw_pt, claw_n, dt)
			_claw_last_mark = claw_pt
		paws.claw_target = paw_anchor.to_local(claw_pt + claw_n * 0.01)
		_rig_claw(claw_pt + claw_n * 0.01)
		return
	# nothing to hook: paw just reaches out at the crosshair
	paws.claw_target = Vector3(0, -0.06, -0.3)
	_rig_claw(_eye_pos() + _look_dir() * 0.25)


func _rig_claw(world: Vector3) -> void:
	if "claw_target" in rig:
		var sh := global_transform * Vector3((-0.04 if paws.claw_i == 0 else 0.04), 0.17, -0.13)
		rig.claw_target = sh + (world - sh).limit_length(0.24)


## three parallel scratch lines from a to b on a surface
func _claw_stroke(col: Object, a: Vector3, b: Vector3, n: Vector3, _dt: float) -> void:
	var along := (b - a)
	var len := along.length()
	if len < 0.001:
		return
	along /= len
	var side := n.cross(along).normalized()
	var soft := col is Node and ((col as Node).is_in_group("scratchable") or (col as Node).is_in_group("climbable"))
	var colr := Color(0.12, 0.08, 0.06, 0.55) if not soft else Color(0.93, 0.88, 0.75)
	var mid := (a + b) * 0.5
	for k in 3:
		var mk := MeshInstance3D.new()
		mk.mesh = LowPoly.box(0.0)
		mk.material_override = LowPoly.mat(colr, 1.0)
		mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(mk)
		mk.global_transform = Transform3D(Basis(side * 0.0035, along * (len + 0.004), n * 0.002), mid + side * (k - 1) * 0.0095 + n * 0.001)
		_marks.append(mk)
	_claw_fluff += len
	if soft and _claw_fluff > 0.15:
		_claw_fluff = 0.0
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 6
		p.lifetime = 0.8
		p.explosiveness = 0.9
		p.direction = n
		p.spread = 50
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.6
		p.gravity = Vector3(0, -2.0, 0)
		p.scale_amount_min = 0.004
		p.scale_amount_max = 0.008
		var pm := BoxMesh.new()
		pm.size = Vector3.ONE
		pm.material = LowPoly.mat(Color(0.92, 0.86, 0.7), 1.0)
		p.mesh = pm
		get_tree().current_scene.add_child(p)
		p.global_position = b + n * 0.01
		p.emitting = true
		get_tree().create_timer(1.3).timeout.connect(p.queue_free)
	while _marks.size() > 160:
		var old: Node3D = _marks.pop_front()
		old.queue_free()


func _push_props() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if col is RigidBody3D:
			var rb: RigidBody3D = col
			rb.apply_central_impulse(-c.get_normal() * 0.02 * Vector2(velocity.x, velocity.z).length())
