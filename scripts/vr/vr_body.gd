class_name VRBody
extends Node3D
## you, in vr, as the cat (cat_vr.gd builds this once OpenXR is running; flat mode never does).
##
## - the headset rides the cat's head bone (the same spot the flat first person camera uses,
##   cat_player._place_head_cam): XROrigin3D is moved every frame so the headset lands there.
##   the origin only ever yaws: the body's pitch / roll on slopes, walls and climbs, head bob and
##   head roll never reach your eyes. leaning moves the view a few cm off the head (soft limit).
## - where you look is where the cat looks: orb_yaw / pitch come from the headset, so moving,
##   swats, leap aim and lock on all work off your head like they work off the mouse.
## - XRServer world scale (setting "vr_scale", default 0.5) shrinks your eyes to a cat's: the world
##   reads twice as big, a real metre of hand movement is half a game metre.
## - controllers: left stick moves (head relative, tilt = speed like a pad), click it = run
##   (again at full tilt = gallop). right stick turns (snap or smooth), pull it back = crouch.
##   triggers = left / right paw, grips = aim (left) / grab (right), A jump (hold = pounce),
##   B dodge, X scratch, Y drop (hold Y or press menu = pause menu), right stick click = lock on.
## - your hands are the forepaws: raise a hand to chest height and that paw leaves the ground
##   and follows it (cat_rig.vr_paw); a fast swing of a raised hand is a swat on that side.
## - every 2d screen (hud, menus, title, tutorial cards...) is redirected into a SubViewport shown
##   on a panel floating in front of you. when a menu is up a laser comes out of your pointer hand
##   (setting "vr_hand"), trigger clicks, the stick scrolls.
## - comfort: tunnel vignette while moving fast / turning (setting "vr_vignette"), a blink on snap
##   turns, the flat crosshair is swapped for a reticle in the world.
##
## tests use CatVR.start_sim(): no headset, sim_head / sim_hands / sim_in stand in for the tracked
## poses and the controller inputs (tests/vr_test.gd).

const LEAN_MAX := 0.06        # game m the eye may lean off the head bone sideways / forward
const LEAN_UP := 0.035        #   and up / down
const DRIFT_RECENTER := 0.45  # real m walked off the centre spot (held DRIFT_T s) = recentre there
const DRIFT_T := 1.2
const PANEL_REAL_DIST := 1.1  # how far away the 2d panel looks (real m)
const PANEL_FOV := 54.0       # degrees wide
const PANEL_FOLLOW := 0.55    # rad the head can turn off the panel before it swings round
const SWING_SPEED := 1.8      # real m/s: a raised hand moving this fast = a swat
const SWING_PULSE := 0.1      # s the paw button is held for a swing
const SWING_COOL := 0.3
const RAISE_LO := -0.62       # hand this far (real m) under the eyes = paw on the ground
const RAISE_HI := -0.38       #   this far = paw fully on the hand
const PAW_K := 0.3            # hand offset from the eyes (real m) -> paw offset from the head (game m)
const PAW_DROP := -0.04      # paws sit a little under where the hands point (chin / chest, not the eyes)
const STICK_DZ := 0.15
const HAND_NAMES := ["left_hand", "right_hand"]

var origin: XROrigin3D
var xr_cam: XRCamera3D
var hands: Array[XRController3D] = []
var player: CatPlayer
var vr_yaw := 0.0                 # the origin's turn (snap / smooth turning moves this)
var head_local := Transform3D.IDENTITY     # headset pose in tracking space (real m)
var hand_local: Array = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var hand_ok := [false, false]
var center := Vector3.ZERO        # tracking space spot that maps onto the cat's head
var centered := false
var lean := Vector3.ZERO          # game m the eye sits off the head bone (after the soft limit)
var world_scale := 0.5
var menu_mode := false            # a menu / title / lobby is up: laser on, the cat gets no input
var paw_w := [0.0, 0.0]
var paw_target := [Vector3.INF, Vector3.INF]
var hand_speed := [0.0, 0.0]
var swings := 0                   # swats thrown by swinging (tests)
var haptics: Array = []           # [hand, amp, dur] (sim only: tests read it)
var pointer_px := Vector2(-1, -1) # where the laser is on the 2d screen (viewport px), -1 = off it
var hud_vp: SubViewport
var hud_panel: MeshInstance3D
var panel_yaw := 0.0

# tests
var sim_head := Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
var sim_hands: Array = [Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.45, -0.15)), Transform3D(Basis.IDENTITY, Vector3(0.2, 0.45, -0.15))]
var sim_in: Array = [{}, {}]      # per hand: {"trigger": 1.0, "primary": Vector2(...), "ax_button": true, ...}

var _swing_t := [0.0, 0.0]
var _swing_cool := [0.0, 0.0]
var _prev_hand := [Vector3.INF, Vector3.INF]
var _snap_armed := true
var _turn_rate := 0.0
var _run := 0
var _l3_prev := false
var _trig := [false, false]
var _y_t := -1.0
var _y_menu_done := false
var _drop_t := 0.0
var _menu_prev := false
var _b_prev := false
var _click_prev := false
var _scroll_t := 0.0
var _drift_t := 0.0
var _last_event_t := 99.0
var _head_pt := Vector3.ZERO
var _laser: MeshInstance3D
var _dot: MeshInstance3D
var _reticle: MeshInstance3D
var _vignette: MeshInstance3D
var _vig_mat: ShaderMaterial
var _vig := 0.0
var _flash := 0.0
var _hand_marks: Array[MeshInstance3D] = []
var _panel_chase := false
var _swats_seen := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # menus pause the tree: the laser still has to work
	process_priority = -20                      # before the cat's _process reads orb_yaw / pitch
	origin = XROrigin3D.new()
	origin.name = "Origin"
	add_child(origin)
	xr_cam = XRCamera3D.new()
	xr_cam.near = 0.005
	xr_cam.far = 300.0
	origin.add_child(xr_cam)
	for k in 2:
		var c := XRController3D.new()
		c.name = HAND_NAMES[k]
		c.tracker = HAND_NAMES[k]
		c.pose = "aim_pose"
		origin.add_child(c)
		hands.append(c)
		var m := MeshInstance3D.new()   # a small bead where your hand is (the paw follows it when raised)
		var s := SphereMesh.new()
		s.radius = 0.006
		s.height = 0.012
		s.radial_segments = 8
		s.rings = 4
		m.mesh = s
		m.material_override = _flat_mat(Color(1, 1, 1, 0.35), 105)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(m)
		_hand_marks.append(m)
	_build_hud()
	_build_pointer()
	_build_vignette()
	var late := Late.new()
	late.body = self
	add_child(late)
	apply_settings()
	get_tree().node_added.connect(_on_node_added)
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		_redirect(cl)
	_read_poses(0.0)


## put every 2d layer back on the window (tests / sim shutdown)
func shutdown() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if (cl as CanvasLayer).custom_viewport == hud_vp:
			(cl as CanvasLayer).custom_viewport = null
	if player and is_instance_valid(player):
		player.rig.vr_paw_w = [0.0, 0.0]


func apply_settings() -> void:
	world_scale = float(GameSettings.g("vr_scale"))
	origin.world_scale = world_scale


## the runtime's recentre (or the menu button): your current spot + facing = the cat's head + facing
func recenter() -> void:
	centered = false
	var f := head_local.basis * Vector3.FORWARD
	var head_yaw := atan2(-f.x, -f.z)
	var want := player.orb_yaw if player and is_instance_valid(player) else vr_yaw + head_yaw
	vr_yaw = wrapf(want - head_yaw, -PI, PI)


# ---------------------------------------------------------------- per frame (early)

func _process(dt: float) -> void:
	_find_player()
	_read_poses(dt)
	menu_mode = _menu_wanted()
	_buttons(dt)
	if not menu_mode:
		_turn(dt)
	else:
		_turn_rate = 0.0
	if player:
		# the cat looks where you look (moving, swats, leap aim, lock on all read these)
		var f := Basis(Vector3.UP, vr_yaw) * head_local.basis * Vector3.FORWARD
		player.orb_yaw = atan2(-f.x, -f.z)
		player.pitch = clampf(asin(clampf(f.y, -1.0, 1.0)), -1.45, 1.45)
		# vr is always first person on the head, and the head never bobs / rolls your eyes
		if player.view_mode != 0:
			player.set_view(0)
		if not player.head_cam:
			player.set_head_cam(true)
		player.calm_cam = true
		_paws(dt)
		_event_haptics()
		var cs := get_tree().current_scene
		if cs:
			var ch = cs.get("crosshair")
			if ch is CanvasItem:
				(ch as CanvasItem).visible = false   # swapped for the reticle in the world
	if not xr_cam.current:
		xr_cam.make_current()   # a new level's flat camera grabs current in its _ready


func _find_player() -> void:
	if player and is_instance_valid(player) and player.is_inside_tree():
		return
	player = null
	for p in get_tree().get_nodes_in_group("player"):
		if p is CatPlayer and (p as CatPlayer).bot.is_empty() and p.is_inside_tree():
			player = p
			recenter()
			return


func _read_poses(dt: float) -> void:
	for k in 2:
		_hand_marks[k].visible = false
	if CatVR.sim:
		head_local = sim_head
		xr_cam.transform = Transform3D(sim_head.basis, sim_head.origin * world_scale)
		for k in 2:
			hand_local[k] = sim_hands[k]
			hand_ok[k] = true
			hands[k].transform = Transform3D(hand_local[k].basis, hand_local[k].origin * world_scale)
	else:
		var ws := maxf(world_scale, 0.01)
		head_local = Transform3D(xr_cam.transform.basis, xr_cam.transform.origin / ws)
		for k in 2:
			hand_ok[k] = hands[k].get_has_tracking_data()
			hand_local[k] = Transform3D(hands[k].transform.basis, hands[k].transform.origin / ws)
	for k in 2:
		var p: Vector3 = hand_local[k].origin
		if dt > 0.0 and hand_ok[k] and _prev_hand[k] != Vector3.INF:
			hand_speed[k] = LowPoly.damp(hand_speed[k], p.distance_to(_prev_hand[k]) / dt, 40.0, dt)
		else:
			hand_speed[k] = 0.0
		_prev_hand[k] = p if hand_ok[k] else Vector3.INF
		_hand_marks[k].visible = hand_ok[k]


func _menu_wanted() -> bool:
	var gm := get_node_or_null("/root/GameMenu")
	if gm and gm.get("is_open"):
		return true
	if not get_tree().get_nodes_in_group("title_screen").is_empty():
		return true
	var net := get_node_or_null("/root/Net")
	if net and net.get("ui") is CanvasItem and (net.get("ui") as CanvasItem).visible:
		return true
	return player == null


# ---------------------------------------------------------------- controllers

func _axis(h: int, name: String) -> float:
	if CatVR.sim:
		return float(sim_in[h].get(name, 0.0))
	return hands[h].get_float(name) if hand_ok[h] else 0.0


func _btn(h: int, name: String) -> bool:
	if CatVR.sim:
		return bool(sim_in[h].get(name, false))
	return hands[h].is_button_pressed(name) if hand_ok[h] else false


func _stick(h: int) -> Vector2:
	var v: Vector2 = sim_in[h].get("primary", Vector2.ZERO) if CatVR.sim else (hands[h].get_vector2("primary") if hand_ok[h] else Vector2.ZERO)
	var l := v.length()
	if l < STICK_DZ:
		return Vector2.ZERO
	return v / l * minf((l - STICK_DZ) / (1.0 - STICK_DZ), 1.0)


## the cat's input from the controllers, same keys as the keyboard / pad dicts (cat_player._read_input
## merges it in with CatPad.merge). stick y up = forward, like a pad
func read_input() -> Dictionary:
	if menu_mode:
		return {}
	var mv := _stick(0)
	var l3 := _btn(0, "primary_click")
	if l3 and not _l3_prev:
		_run = mini(_run + 1, 2) if mv.length() > 0.5 else 1
	_l3_prev = l3
	if mv.length() < 0.5:
		_run = 0
	for k in 2:
		_trig[k] = _axis(k, "trigger") > (0.35 if _trig[k] else 0.6)
	var rs := _stick(1)
	return {
		"move": mv,
		"canter": _run == 1,
		"sprint": _run == 2,
		"crouch": rs.y < -0.65 and absf(rs.x) < 0.5,
		"jump": _btn(1, "ax_button"),
		"dash": _btn(1, "by_button"),
		"scratch": _btn(0, "ax_button"),
		"drop": _drop_t > 0.0,
		"paw_l": _trig[0] or _swing_t[0] > 0.0,
		"paw_r": _trig[1] or _swing_t[1] > 0.0,
		"aim": _axis(0, "grip") > 0.6,
		"grab": _axis(1, "grip") > 0.6,
		"lock_on": _btn(1, "primary_click"),
	}


func _buttons(dt: float) -> void:
	# Y: tap = drop what's in your mouth, hold = pause menu (not every controller has a menu button)
	var y := _btn(0, "by_button")
	if y:
		_y_t = 0.0 if _y_t < 0.0 else _y_t + dt
		if _y_t >= 0.7 and not _y_menu_done:
			_y_menu_done = true
			_esc()
	else:
		if _y_t >= 0.0 and _y_t < 0.7 and not menu_mode:
			_drop_t = 0.15
		_y_t = -1.0
		_y_menu_done = false
	_drop_t = maxf(_drop_t - dt, 0.0)
	var m := _btn(0, "menu_button")
	if m and not _menu_prev:
		_esc()
	_menu_prev = m
	# in a menu B goes back a page / closes it, like a pad's B
	var b := _btn(1, "by_button")
	if menu_mode and b and not _b_prev:
		_esc()
	_b_prev = b


## the pause menu listens for esc (game_menu.gd): open / back / close it the same way
func _esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	var r := e.duplicate() as InputEventKey
	r.pressed = false
	Input.parse_input_event(r)


func _turn(dt: float) -> void:
	var x := _stick(1).x
	_turn_rate = 0.0
	if int(GameSettings.g("vr_turn")) == 0:
		if absf(x) > 0.7 and _snap_armed:
			vr_yaw = wrapf(vr_yaw - signf(x) * deg_to_rad(float(GameSettings.g("vr_snap"))), -PI, PI)
			_snap_armed = false
			_flash = 1.0
		elif absf(x) < 0.35:
			_snap_armed = true
	elif x != 0.0:
		_turn_rate = x * deg_to_rad(float(GameSettings.g("vr_turn_speed")))
		vr_yaw = wrapf(vr_yaw - _turn_rate * dt, -PI, PI)


## raised hands carry the forepaws, swung hands swat
func _paws(dt: float) -> void:
	var on: bool = GameSettings.g("vr_paws") and not menu_mode
	var R := Basis(Vector3.UP, vr_yaw)
	var head_w := player.cam_pivot.global_position
	for k in 2:
		var rel: Vector3 = hand_local[k].origin - head_local.origin
		var up := smoothstep(RAISE_LO, RAISE_HI, rel.y) if on and hand_ok[k] else 0.0
		paw_w[k] = LowPoly.damp(paw_w[k], up, 14.0, dt)
		paw_target[k] = head_w + R * (rel * PAW_K) + Vector3(0, PAW_DROP, 0)
		_swing_t[k] = maxf(_swing_t[k] - dt, 0.0)
		_swing_cool[k] = maxf(_swing_cool[k] - dt, 0.0)
		if on and up > 0.5 and hand_speed[k] > SWING_SPEED and _swing_cool[k] <= 0.0:
			_swing_t[k] = SWING_PULSE
			_swing_cool[k] = SWING_COOL
			swings += 1
	player.rig.vr_paw = paw_target.duplicate()
	player.rig.vr_paw_w = paw_w.duplicate()


const _BUZZ := {"swat": 0.5, "swatted": 0.8, "grab!": 0.6, "got a grip": 0.7, "hooked": 0.5, "claws in": 0.4,
		"caught": 1.0, "pounce!": 0.5, "paws down": 0.6, "wall kick": 0.4, "scratch": 0.3}


## a buzz in the hands for things the paws do / feel
func _event_haptics() -> void:
	var t := player.last_event_t
	if t < _last_event_t:
		var ev := player.last_event
		for key in _BUZZ:
			if ev.begins_with(key):
				var amp: float = _BUZZ[key]
				var side := -1
				if key.begins_with("swat"):
					side = 0 if _swing_t[0] > 0.0 or _trig[0] else (1 if _swing_t[1] > 0.0 or _trig[1] else -1)
				for k in 2:
					if side == -1 or side == k:
						pulse(k, amp, 0.06 + amp * 0.06)
				break
	_last_event_t = t
	# every swat / rake thrown: a tick in the hand that threw it (a hit buzzes harder, above)
	var n: int = player.combat.swats + player.combat.rakes
	if n > _swats_seen and _swats_seen >= 0:
		var hit := false
		for k in 2:
			if _swing_t[k] > 0.0 or _trig[k]:
				pulse(k, 0.25, 0.04)
				hit = true
		if not hit:
			for k in 2:
				pulse(k, 0.15, 0.03)
	_swats_seen = n


func pulse(h: int, amp: float, dur: float) -> void:
	if CatVR.sim:
		haptics.append([h, amp, dur])
		return
	if hand_ok[h]:
		hands[h].trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)


# ---------------------------------------------------------------- per frame (late: after the head cam)

## runs after HeadFollow (priority 20) put the cat's eye on the head bone this frame
class Late extends Node:
	var body: Node
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 30
	func _process(dt: float) -> void:
		body._place(dt)


func _place(dt: float) -> void:
	if player and is_instance_valid(player) and player.is_inside_tree():
		_head_pt = player.cam_pivot.global_position
	var hl := head_local.origin
	if not centered:
		center = hl
		centered = true
	var raw := hl - center
	# walked off round the room: that becomes the new centre (a lean is never this big)
	if Vector2(raw.x, raw.z).length() > DRIFT_RECENTER:
		_drift_t += dt
		if _drift_t > DRIFT_T:
			center = hl
			raw = Vector3.ZERO
			_drift_t = 0.0
	else:
		_drift_t = 0.0
	var l := raw * world_scale
	var h := Vector2(l.x, l.z)
	var hlen := h.length()
	if hlen > 0.0001:
		h = h / hlen * LEAN_MAX * tanh(hlen / LEAN_MAX)    # soft limit: the eye stays near the head
	lean = Vector3(h.x, LEAN_UP * tanh(l.y / LEAN_UP), h.y)
	var R := Basis(Vector3.UP, vr_yaw)
	var want := _head_pt + R * lean
	if player and lean.length() > 0.002:
		# don't lean through a wall
		var f: float = player._sweep(_head_pt, want, 0.02)
		want = _head_pt.lerp(want, f)
	origin.global_transform = Transform3D(R, want - R * (hl * world_scale))
	_place_panel(dt)
	_place_pointer()
	_vignette_tick(dt)


# ---------------------------------------------------------------- the 2d panel

func _build_hud() -> void:
	hud_vp = SubViewport.new()
	hud_vp.name = "Hud"
	hud_vp.transparent_bg = true
	hud_vp.disable_3d = true
	hud_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hud_vp.size = Vector2i(1600, 900)
	add_child(hud_vp)
	hud_panel = MeshInstance3D.new()
	hud_panel.name = "HudPanel"
	hud_panel.mesh = QuadMesh.new()
	var m := _flat_mat(Color.WHITE, 100)
	m.albedo_texture = hud_vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hud_panel.material_override = m
	hud_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hud_panel)


func _on_node_added(n: Node) -> void:
	if n is CanvasLayer:
		_redirect.call_deferred(n)


## a 2d layer draws into the panel instead of the window. a full screen post filter (it reads the
## screen) can't work on a panel, so it's switched off
func _redirect(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree() or not n is CanvasLayer:
		return
	var cl := n as CanvasLayer
	if hud_vp.is_ancestor_of(cl) or cl.custom_viewport != null:
		return
	if _reads_screen(cl):
		cl.visible = false
		return
	cl.custom_viewport = hud_vp
	# a post material can arrive a frame later (stealth_main adds the rect after the layer)
	if not cl.child_entered_tree.is_connected(_recheck):
		cl.child_entered_tree.connect(_recheck.bind(cl))


func _recheck(_c: Node, cl: CanvasLayer) -> void:
	(func():
		if is_instance_valid(cl) and _reads_screen(cl):
			cl.custom_viewport = null
			cl.visible = false).call_deferred()


func _reads_screen(cl: CanvasLayer) -> bool:
	for c in cl.find_children("*", "CanvasItem", true, false):
		var mat := (c as CanvasItem).material
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader and "hint_screen_texture" in (mat as ShaderMaterial).shader.code:
			return true
	return false


func _panel_size() -> Vector2:
	var d := PANEL_REAL_DIST * world_scale
	var w := 2.0 * d * tan(deg_to_rad(PANEL_FOV) * 0.5)
	var vs := Vector2(hud_vp.size)
	return Vector2(w, w * vs.y / maxf(vs.x, 1.0))


func _place_panel(dt: float) -> void:
	var vs := get_tree().root.get_visible_rect().size
	if Vector2i(vs) != hud_vp.size and vs.x > 0 and vs.y > 0:
		hud_vp.size = Vector2i(vs)
	var eye := xr_cam.global_position
	var f := -xr_cam.global_basis.z
	var yaw := atan2(-f.x, -f.z)
	var off := wrapf(yaw - panel_yaw, -PI, PI)
	# lazy follow: the panel stays put while you look round a bit, then swings back in front
	var lim := PANEL_FOLLOW * (1.6 if menu_mode else 1.0)
	if not hud_panel.has_meta("placed"):
		panel_yaw = yaw
		hud_panel.set_meta("placed", true)
	if absf(off) > lim:
		_panel_chase = true
	if _panel_chase:
		panel_yaw = wrapf(panel_yaw + off * (1.0 - exp(-6.0 * dt)), -PI, PI)
		if absf(off) < 0.05:
			_panel_chase = false
	var d := PANEL_REAL_DIST * world_scale
	var sz := _panel_size()
	(hud_panel.mesh as QuadMesh).size = sz
	var b := Basis(Vector3.UP, panel_yaw)
	hud_panel.global_transform = Transform3D(b, eye + b * Vector3(0, -0.08 * d, -d))


# ---------------------------------------------------------------- laser + reticle

func _build_pointer() -> void:
	_laser = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.0015, 0.0015, 1.0)
	_laser.mesh = bm
	_laser.material_override = _flat_mat(Color(0.55, 0.9, 1.0, 0.7), 110)
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_laser)
	_dot = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.004
	s.height = 0.008
	s.radial_segments = 8
	s.rings = 4
	_dot.mesh = s
	_dot.material_override = _flat_mat(Color(0.7, 0.95, 1.0, 0.95), 111)
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dot)
	_reticle = MeshInstance3D.new()
	_reticle.mesh = s
	_reticle.material_override = _flat_mat(Color(1, 1, 1, 0.6), 104)
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_reticle)


func pointer_hand() -> int:
	return int(GameSettings.g("vr_hand"))


func _place_pointer() -> void:
	_laser.visible = false
	_dot.visible = false
	pointer_px = Vector2(-1, -1)
	# reticle: a dot where the cat is looking (the flat crosshair is hidden)
	_reticle.visible = not menu_mode and player != null
	if _reticle.visible:
		var from: Vector3 = player._aim_pos()
		var dir: Vector3 = player._look_dir()
		var hit: Dictionary = player._ray(from, from + dir * 3.0)
		var p: Vector3 = hit.position if not hit.is_empty() else from + dir * 1.5
		var dist := xr_cam.global_position.distance_to(p)
		_reticle.global_position = p
		_reticle.scale = Vector3.ONE * clampf(dist * 0.6, 0.05, 2.0)
	if not menu_mode:
		_click_prev = false
		return
	var k := pointer_hand()
	if not hand_ok[k]:
		return
	var hx := hands[k].global_transform
	var from := hx.origin
	var dir := -hx.basis.z.normalized()
	var n := hud_panel.global_basis.z.normalized()
	var hit = Plane(n, hud_panel.global_position).intersects_ray(from, dir)
	if hit == null:
		return
	var local := hud_panel.to_local(hit)
	var sz := _panel_size()
	var uv := Vector2(local.x / sz.x + 0.5, 0.5 - local.y / sz.y)
	var len := from.distance_to(hit)
	_laser.visible = true
	_laser.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK), from + dir * len * 0.5)
	_laser.scale = Vector3(1, 1, len)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		_click_prev = false
		return
	_dot.visible = true
	_dot.global_position = hit
	_dot.scale = Vector3.ONE * world_scale * 2.0
	var vs := Vector2(hud_vp.size)
	var px := uv * vs
	var root := get_tree().root
	var mm := InputEventMouseMotion.new()
	mm.position = px
	mm.global_position = px
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _click_prev else 0
	root.push_input(mm, true)
	pointer_px = px
	var click := _axis(k, "trigger") > (0.35 if _click_prev else 0.6)
	if click != _click_prev:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = click
		mb.position = px
		mb.global_position = px
		root.push_input(mb, true)
	_click_prev = click
	# the pointer hand's stick scrolls lists
	var sy := _stick(k).y
	_scroll_t -= get_process_delta_time()
	if absf(sy) > 0.5 and _scroll_t <= 0.0:
		_scroll_t = 0.09
		for pressed in [true, false]:
			var wb := InputEventMouseButton.new()
			wb.button_index = MOUSE_BUTTON_WHEEL_UP if sy > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
			wb.pressed = pressed
			wb.factor = 1.0
			wb.position = px
			wb.global_position = px
			root.push_input(wb, true)


# ---------------------------------------------------------------- comfort vignette

const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);   // a full screen quad in each eye
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float inner = mix(1.25, 0.45, strength);
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(inner, inner + 0.4, d) * clamp(strength * 3.0, 0.0, 1.0);
}
"""


func _build_vignette() -> void:
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = sh
	_vig_mat.render_priority = 90
	_vignette = MeshInstance3D.new()
	_vignette.name = "Vignette"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_vignette.mesh = q
	_vignette.material_override = _vig_mat
	_vignette.extra_cull_margin = 16384.0
	_vignette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vignette.position = Vector3(0, 0, -0.05)
	xr_cam.add_child(_vignette)


## how much tunnel: moving fast, turning smoothly, a blink on snap turns
func vignette_target() -> float:
	var s := 0.0
	if player and not menu_mode:
		var hv := Vector2(player.velocity.x, player.velocity.z).length()
		s = smoothstep(1.2, 8.0, hv)
		s = maxf(s, clampf(absf(_turn_rate) / 2.5, 0.0, 1.0))
	return clampf(s * float(GameSettings.g("vr_vignette")), 0.0, 1.0)


func _vignette_tick(dt: float) -> void:
	_vig = LowPoly.damp(_vig, vignette_target(), 5.0, dt)
	_flash = maxf(_flash - dt * 8.0, 0.0)
	var flash := _flash * (1.0 if float(GameSettings.g("vr_vignette")) > 0.0 else 0.0)
	var s := maxf(_vig, flash)
	_vig_mat.set_shader_parameter("strength", s)
	_vignette.visible = s > 0.005


func vignette_strength() -> float:
	return float(_vig_mat.get_shader_parameter("strength"))


func _flat_mat(c: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.render_priority = prio
	return m
