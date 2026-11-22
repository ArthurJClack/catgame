extends SceneTree
## screenshots of every menu / hud screen at one window size, for ui checks + pr images:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/ui_shots.gd -- out/ui 1600x900

var dir := "out/ui"


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(nm: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, nm])
	print("shot ", nm)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else dir
	var sz := Vector2i(1600, 900)
	if args.size() > 1:
		var p: PackedStringArray = args[1].split("x")
		sz = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(dir)
	GameSettings.path = "user://settings_uishots.cfg"
	GameSettings.load_file()
	root.size = sz
	DisplayServer.window_set_size(sz)
	TitleScreen.force = true
	Tutorial.force = true
	change_scene_to_file("res://main.tscn")
	await _frames(200)
	await _shot("01_title")
	var t = get_nodes_in_group("title_screen")[0]
	t.show_page("slots")
	await _shot("02_title_slots")
	t.show_page("main")
	t._close("play")
	await _frames(30)
	await _shot("03_hud_tutorial")
	var menu = root.get_node("GameMenu")
	menu.open_menu()
	for pg in ["main", "settings", "controls", "puzzles", "achievements"]:
		menu.show_page(pg)
		await _shot("04_menu_" + pg)
	menu.close_menu()
	var net = root.get_node("Net")
	if net.ui:
		net.ui.toggle()
		await _shot("05_online")
		if net.ui.has_method("show_page"):
			for pg in ["host", "join"]:
				net.ui.show_page(pg)
				await _shot("05_online_" + pg)
		net.ui.toggle()
	if args.size() > 2:
		# extra scenes' hud: arena (health + stamina + lock on), forest
		for sc in args.slice(2):
			change_scene_to_file(sc)
			await _frames(160)
			await _shot("06_" + sc.get_file().get_basename())
	quit()
