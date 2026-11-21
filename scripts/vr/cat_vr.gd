class_name CatVR
extends RefCounted
## vr mode switch (OpenXR: SteamVR, Quest Link / Air Link, WMR, anything with an OpenXR runtime).
##
## OpenXR has to be set up while the engine starts (it hooks the renderer), so vr is a launch
## mode, not a live toggle: the game is started with `--xr-mode on`. the settings toggle
## ("vr mode") saves itself and restarts the game in that mode, a game started normally with the
## setting on restarts itself once into vr, and `-- --vr` / `-- --novr` force it for one run.
## no headset / runtime found: the game stays flat and says so (no restart loop).
##
## once OpenXR is up, start() turns the main viewport over to the headset and hangs a VRBody
## (vr_body.gd) off the root: it lives across scene changes and drives whatever local cat is in
## the scene. flat mode never builds any of it.

static var active := false        # vr is running (or simulated)
static var sim := false           # tests: everything but the headset (poses / buttons come from VRBody.sim_*)
static var failed := ""           # why vr didn't start this run ("" = it did, or it wasn't asked for)
static var body: Node = null      # the VRBody
static var xr: XRInterface = null


## called once at boot (GameMenu._ready)
static func boot(tree: SceneTree) -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless" or tree.get_script() != null:
		return   # (a --script test run never restarts itself)
	var args := OS.get_cmdline_user_args()
	var i := XRServer.find_interface("OpenXR")
	if i != null and i.is_initialized():
		start(tree, i)
		return
	if launched_in_xr():
		# we already asked the engine for OpenXR and it couldn't get a session: stay flat, no loop
		failed = "no vr headset found: is steamvr / quest link running? (playing flat. vr mode can be turned off in settings)"
		push_warning(failed)
		_flat_notice.call_deferred(tree)
		return
	if "--novr" in args:
		return
	if not (GameSettings.g("vr") or "--vr" in args):
		return
	relaunch(tree, true)


## this run is the restart we asked for (the engine eats --xr-mode from the args it hands
## scripts, so the restart marks itself with a game arg)
static func launched_in_xr() -> bool:
	return "--vrboot" in OS.get_cmdline_user_args()


## the args a restart uses: this run's args plus --xr-mode, and a marker after "--" so the new run
## knows it was asked for vr. path: the project folder when running from the editor binary
static func relaunch_args(on: bool, args := OS.get_cmdline_args(), user := OS.get_cmdline_user_args(),
		path := "" if OS.has_feature("template") else ProjectSettings.globalize_path("res://")) -> PackedStringArray:
	var out := PackedStringArray()
	if path != "":
		out.append_array(["--path", path])
	var skip := false
	for a in args:
		if skip:
			skip = false
		elif a == "--xr-mode" or a == "--path":
			skip = true
		else:
			out.append(a)
	out.append_array(["--xr-mode", "on" if on else "off", "--"])
	for u in user:
		if not u in ["--vr", "--novr", "--vrboot"]:
			out.append(u)
	out.append("--vrboot" if on else "--novr")
	return out


## restart the game with vr on / off
static func relaunch(tree: SceneTree, on: bool) -> void:
	GameSettings.save_file()
	var pid := OS.create_process(OS.get_executable_path(), relaunch_args(on))
	if pid <= 0:
		failed = "couldn't restart the game in vr mode"
		push_warning(failed)
		return
	tree.quit()


static func start(tree: SceneTree, iface: XRInterface) -> void:
	xr = iface
	active = true
	tree.root.use_xr = true
	# the headset's compositor paces frames: vsync / fps caps on the desktop window only get in the way
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if iface.has_signal("session_stopping"):
		iface.connect("session_stopping", func(): tree.quit())
	_add_body(tree)
	if iface.has_signal("pose_recentered"):
		iface.connect("pose_recentered", func(): if body: body.recenter())


## tests: the whole vr body with no headset. the root viewport stays flat and VRBody.sim_*
## stand in for the tracked poses and controller buttons
static func start_sim(tree: SceneTree) -> Node:
	sim = true
	active = true
	return _add_body(tree, true)


static func stop_sim() -> void:
	if body and is_instance_valid(body):
		body.shutdown()
		body.queue_free()
	body = null
	active = false
	sim = false


static func _add_body(tree: SceneTree, now := false) -> Node:
	var b: Node = load("res://scripts/vr/vr_body.gd").new()
	b.name = "CatVRBody"
	body = b
	if now:
		tree.root.add_child(b)
	else:
		tree.root.add_child.call_deferred(b)
	return b


static func _flat_notice(tree: SceneTree) -> void:
	var cl := CanvasLayer.new()
	cl.layer = 95
	var l := Label.new()
	l.text = failed
	l.position = Vector2(24, 24)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	cl.add_child(l)
	tree.root.add_child(cl)
	tree.create_timer(9.0).timeout.connect(cl.queue_free)


## the cat's controller input (cat_player._read_input merges it): {} unless vr drives this cat
static func read(p: Node) -> Dictionary:
	if not active or body == null or not is_instance_valid(body) or body.get("player") != p:
		return {}
	return body.read_input()
