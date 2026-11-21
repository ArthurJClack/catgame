extends SceneTree
## vr mode without a headset (vr/cat_vr.gd, vr/vr_body.gd): CatVR.start_sim() builds the real vr
## body and the test plays the headset + controllers through VRBody.sim_head / sim_hands / sim_in.
## checks flat mode is untouched, the eye rides the cat's head, head look drives the cat, leaning
## is limited, the origin only yaws, stick moves / snap + smooth turns, raised hands lift the
## paws, a swing / trigger swats with a buzz, 2d layers land on the vr panel, the laser clicks
## real menu buttons, and shutting vr down gives the window its 2d back. needs a display:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --fixed-fps 60 --script res://tests/vr_test.gd [-- outdir]
## with an outdir it also saves what the (mono) headset sees: vr_hud.png, vr_menu.png, vr_paw.png

const TEST_PATH := "user://settings_vr_test.cfg"
var bad := 0
var out_dir := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	_run.call_deferred()


## waits game time (run with --fixed-fps 60: xvfb renders a couple of real fps)
func _wait(sec: float, until: Callable = func(): return false) -> bool:
	var t := 0.0
	var wall := Time.get_ticks_msec() + int(maxf(sec, 1.0) * 60000.0)
	while t < sec and Time.get_ticks_msec() < wall:
		await process_frame
		t += root.get_process_delta_time()
		if until.call():
			return true
	return until.call()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		bad += 1


func _player() -> CatPlayer:
	var p = current_scene.get("player") if current_scene else null
	return p if p is CatPlayer and p.is_inside_tree() else null


func _yawb(y: float, pitch := 0.0) -> Basis:
	return Basis(Vector3.UP, y) * Basis(Vector3.RIGHT, pitch)


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null


func _shot(name: String) -> void:
	if out_dir == "":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png(out_dir.path_join(name))
	print("saved ", out_dir.path_join(name))


## aim the sim hand k (tracking space) so its laser hits viewport pixel px on the panel
func _point_at(b: VRBody, k: int, px: Vector2) -> void:
	var vs := Vector2(b.hud_vp.size)
	var sz: Vector2 = b._panel_size()
	var uv := px / vs
	var target := b.hud_panel.to_global(Vector3((uv.x - 0.5) * sz.x, (0.5 - uv.y) * sz.y, 0.0))
	var hl := Vector3(0.12 if k == 1 else -0.12, b.sim_head.origin.y - 0.25, b.sim_head.origin.z - 0.2)
	var hw := b.origin.global_transform * (hl * b.world_scale)
	var wb := Basis.looking_at((target - hw).normalized(), Vector3.UP)
	b.sim_hands[k] = Transform3D(b.origin.global_basis.inverse() * wb, hl)


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	GameSettings.path = TEST_PATH
	GameSettings.load_file()
	GameSettings.s("hints", false)
	Engine.set_meta("title_done", true)

	# --- launch args
	var none := PackedStringArray()
	_ok(CatVR.relaunch_args(true, none, none, "") == PackedStringArray(["--xr-mode", "on", "--", "--vrboot"]), "relaunch (exported game) = --xr-mode on + marker")
	_ok(CatVR.relaunch_args(true, PackedStringArray(["main.tscn"]), PackedStringArray(["--vr", "--debug"]), "/p") == PackedStringArray(["--path", "/p", "main.tscn", "--xr-mode", "on", "--", "--debug", "--vrboot"]), "relaunch from the editor keeps the project + game args")
	_ok(CatVR.relaunch_args(false, none, PackedStringArray(["--vrboot"]), "") == PackedStringArray(["--xr-mode", "off", "--", "--novr"]), "relaunch can turn it off")
	_ok(not CatVR.launched_in_xr(), "this run wasn't launched in xr")

	change_scene_to_file("res://main.tscn")
	_ok(await _wait(25.0, func(): return _player() != null), "farm loads")
	await _wait(1.5)
	var p := _player()

	# --- flat mode untouched
	_ok(not CatVR.active and root.get_node_or_null("CatVRBody") == null, "flat: no vr body")
	_ok(CatVR.read(p).is_empty(), "flat: no vr input")
	_ok(p.cam.current and not root.use_xr, "flat: the cat's own camera renders")

	# --- vr (simulated headset)
	var b: VRBody = CatVR.start_sim(self)
	await _frames(4)
	_ok(b.player == p, "vr body found the local cat")
	_ok(b.xr_cam.current, "the xr camera renders")
	var gm := root.get_node("GameMenu")
	_ok(gm.custom_viewport == b.hud_vp and p.souls_hud.custom_viewport == b.hud_vp, "2d layers (pause menu, hud) draw on the vr panel")
	var ch = current_scene.get("crosshair")
	_ok(ch is CanvasItem and not ch.visible, "flat crosshair hidden (reticle instead)")

	# eye on the head bone
	b.sim_head = Transform3D(_yawb(0.0), Vector3(0, 1.2, 0))
	b.recenter()
	await _frames(3)
	var d0 := b.xr_cam.global_position.distance_to(p.cam_pivot.global_position)
	_ok(d0 < 0.004, "headset sits on the cat's head cam spot (off by %.4f m)" % d0)
	_ok(p.view_mode == 0 and p.head_cam and p.calm_cam, "first person head cam, calm (no bob / roll)")
	p.set_view(1)
	await _frames(2)
	_ok(p.view_mode == 0, "third person can't be switched on in vr")

	# head look drives the cat
	var y0 := p.orb_yaw
	b.sim_head = Transform3D(_yawb(0.8, -0.4), Vector3(0, 1.2, 0))
	await _frames(2)
	_ok(absf(wrapf(p.orb_yaw - y0 - 0.8, -PI, PI)) < 0.02, "turning your head turns the cat's look (%.3f)" % wrapf(p.orb_yaw - y0, -PI, PI))
	_ok(absf(p.pitch + 0.4) < 0.02, "looking down = cat looks down (%.3f)" % p.pitch)
	var look := -p.cam.global_basis.z
	var xr_look := -b.xr_cam.global_basis.z
	_ok(look.dot(xr_look) > 0.995, "the aim direction is the headset's")
	b.sim_head = Transform3D(_yawb(0.0), Vector3(0, 1.2, 0))
	await _frames(2)

	# leaning: a little, never through the head
	b.sim_head = Transform3D(_yawb(0.0), Vector3(0.4, 1.2, 0))
	await _frames(3)
	var lean := Vector2(b.lean.x, b.lean.z).length()
	_ok(lean > 0.03 and lean <= VRBody.LEAN_MAX + 0.001, "a 40 cm lean moves the eye %.3f m (max %.2f)" % [lean, VRBody.LEAN_MAX])
	b.sim_head = Transform3D(_yawb(0.0), Vector3(0, 1.2, 0))
	await _frames(2)
	_ok(b.origin.global_basis.y.dot(Vector3.UP) > 0.9999, "the origin only yaws")

	# move with the left stick: head relative
	var pos := p.global_position
	var fwd := -b.xr_cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	b.sim_in[0] = {"primary": Vector2(0, 1)}
	await _wait(1.4)
	b.sim_in[0] = {}
	var mvd := p.global_position - pos
	mvd.y = 0.0
	_ok(mvd.length() > 0.8, "left stick moves the cat (%.2f m)" % mvd.length())
	_ok(mvd.normalized().dot(fwd) > 0.85, "...the way you're looking (dot %.2f)" % mvd.normalized().dot(fwd))
	var vmax := b.vignette_strength()
	_ok(b.origin.global_basis.y.dot(Vector3.UP) > 0.9999, "origin still only yaws on the move")
	await _wait(1.2)

	# snap turn
	GameSettings.s("vr_turn", 0)
	var vy := b.vr_yaw
	b.sim_in[1] = {"primary": Vector2(1, 0)}
	await _wait(0.4)
	_ok(absf(wrapf(vy - b.vr_yaw, -PI, PI) - deg_to_rad(30.0)) < 0.01, "snap turn right = 30° once while held (%.1f°)" % rad_to_deg(wrapf(vy - b.vr_yaw, -PI, PI)))
	b.sim_in[1] = {}
	await _frames(2)
	b.sim_in[1] = {"primary": Vector2(-1, 0)}
	await _frames(2)
	b.sim_in[1] = {}
	await _frames(1)
	_ok(absf(wrapf(b.vr_yaw - vy, -PI, PI)) < 0.01, "snap back left")
	# smooth turn + vignette
	GameSettings.s("vr_turn", 1)
	vy = b.vr_yaw
	b.sim_in[1] = {"primary": Vector2(1, 0)}
	await _wait(0.5)
	var turned := rad_to_deg(wrapf(vy - b.vr_yaw, -PI, PI))
	var vig := b.vignette_strength()
	b.sim_in[1] = {}
	_ok(turned > 35.0 and turned < 75.0, "smooth turn ~120°/s (%.0f° in 0.5 s)" % turned)
	_ok(vig > 0.15 or vmax > 0.15, "comfort vignette closes in while turning / running (%.2f / %.2f)" % [vig, vmax])
	GameSettings.s("vr_turn", 0)
	await _wait(0.8)
	_ok(b.vignette_strength() < 0.05, "vignette opens again when still (%.3f)" % b.vignette_strength())

	# raise a hand: that paw follows it
	b.sim_hands[0] = Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.45, -0.15))
	b.sim_hands[1] = Transform3D(Basis.IDENTITY, Vector3(0.12, 1.0, -0.4))
	await _wait(0.5)
	var paw: Node3D = p.rig.legs[1].paw
	var pd := paw.global_position.distance_to(b.paw_target[1])
	_ok(b.paw_w[1] > 0.8 and b.paw_w[0] < 0.1, "raised right hand lifts the right paw only (%.2f / %.2f)" % [b.paw_w[1], b.paw_w[0]])
	_ok(pd < 0.035, "right forepaw follows the hand (%.3f m off)" % pd)
	print("  paw local %s  target local %s  head local %s" % [p.rig.to_local(paw.global_position), p.rig.to_local(b.paw_target[1]), p.rig.to_local(p.cam_pivot.global_position)])
	_ok(paw.global_position.y > p.global_position.y + 0.06, "...up off the ground (%.3f m)" % (paw.global_position.y - p.global_position.y))
	await _shot("vr_paw.png")
	# swing it = swat
	var sw := b.swings
	var cs0 := p.combat.swats
	b.haptics.clear()
	for i in 6:
		b.sim_hands[1] = Transform3D(Basis.IDENTITY, Vector3(0.12 - i * 0.05, 1.0 - i * 0.02, -0.4 - i * 0.02))
		await process_frame
	_ok(b.swings > sw, "a fast swing of a raised hand throws a swat")
	await _wait(0.2, func(): return p.combat.swats > cs0)
	_ok(p.combat.swats > cs0, "...the cat swats with it (%d swats)" % (p.combat.swats - cs0))
	_ok(not b.haptics.is_empty(), "...and the controller buzzes")
	b.sim_hands[1] = Transform3D(Basis.IDENTITY, Vector3(0.2, 0.45, -0.15))
	await _wait(0.6)
	_ok(b.paw_w[1] < 0.15, "hand down = paw back down")
	# trigger swat
	await _wait(0.4)
	cs0 = p.combat.swats
	b.sim_in[0] = {"trigger": 1.0}
	await _frames(3)
	b.sim_in[0] = {}
	await _wait(0.3, func(): return p.combat.swats > cs0)
	_ok(p.combat.swats > cs0, "left trigger swats too")
	await _wait(0.6)

	# buttons map to the cat's input
	b.sim_in[1] = {"ax_button": true, "grip": 1.0}
	var inp := b.read_input()
	_ok(inp.jump and inp.grab, "A = hop / leap, grip = grab")
	b.sim_in[1] = {}
	b.sim_in[0] = {"ax_button": true}
	_ok(b.read_input().interact, "X = interact (scratch / drop)")
	b.sim_in[0] = {"by_button": true}
	var mw := b.meows
	await _frames(2)
	b.sim_in[0] = {}
	await _frames(1)
	_ok(b.meows == mw + 1 and not gm.is_open, "tap Y = meow")
	await _wait(0.3)

	await _shot("vr_hud.png")

	# menu: menu button opens it, laser clicks, B backs out
	b.sim_in[0] = {"menu_button": true}
	await _frames(2)
	b.sim_in[0] = {}
	await _frames(2)
	_ok(gm.is_open and b.menu_mode, "menu button opens the pause menu")
	_ok(b.read_input().is_empty(), "the cat gets no input while it's open")
	await _frames(3)
	var img := b.hud_vp.get_texture().get_image()
	var lit := 0
	for y in range(0, img.get_height(), 16):
		for x in range(0, img.get_width(), 16):
			if img.get_pixel(x, y).a > 0.5:
				lit += 1
	_ok(lit > 50, "the menu is drawn on the vr panel (%d samples)" % lit)
	var sb := _find_button(gm, "settings")
	_ok(sb != null, "menu has a settings button")
	if sb:
		var c := sb.get_global_rect().get_center()
		_point_at(b, 1, c)
		await _frames(3)
		_ok(b.pointer_px.distance_to(c) < 6.0, "laser lands on the settings button (%s vs %s)" % [str(b.pointer_px), str(c)])
		await _shot("vr_menu.png")
		b.sim_in[1] = {"trigger": 1.0}
		await _frames(2)
		b.sim_in[1] = {}
		await _frames(3)
		_ok(gm.page == "settings", "trigger clicks it: settings page (%s)" % gm.page)
		_ok(_find_button(gm, "turn vr off (restarts)") != null, "settings has the vr section")
		var turn_b := _find_button(gm, "snap")
		_ok(turn_b != null, "vr turning option is a click to cycle button (no popup)")
		if turn_b:
			turn_b.pressed.emit()
			_ok(int(GameSettings.g("vr_turn")) == 1 and turn_b.text == "smooth", "...cycles to smooth")
			turn_b.pressed.emit()
	b.sim_in[1] = {"by_button": true}
	await _frames(2)
	b.sim_in[1] = {}
	await _frames(2)
	_ok(gm.is_open and gm.page == "main", "B goes back a page")
	b.sim_in[0] = {"menu_button": true}
	await _frames(2)
	b.sim_in[0] = {}
	await _frames(3)
	_ok(not gm.is_open and not b.menu_mode, "menu button closes it")

	# world scale setting
	GameSettings.s("vr_scale", 0.75)
	b.apply_settings()
	_ok(is_equal_approx(b.origin.world_scale, 0.75), "cat size setting sets the world scale")
	GameSettings.s("vr_scale", 0.5)
	b.apply_settings()

	# back to flat
	CatVR.stop_sim()
	await _frames(3)
	_ok(gm.custom_viewport == null and p.souls_hud.custom_viewport == null, "vr off: 2d layers back on the window")
	p.cam.make_current()
	_ok(not CatVR.active, "vr off")

	print("VRTEST %s (%d failed)" % ["PASS" if bad == 0 else "FAIL", bad])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	quit(0 if bad == 0 else 1)
