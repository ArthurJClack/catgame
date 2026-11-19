extends SceneTree
## screenshots of the pause menu pages for the pr / readme:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/menu_shots.gd -- out/menu

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "out/menu"
	DirAccess.make_dir_recursive_absolute(dir)
	GameSettings.path = "user://settings_shots.cfg"
	GameSettings.load_file()
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://main.tscn")
	await _frames(240)
	var menu = root.get_node("GameMenu")
	menu.open_menu()
	for pg in ["main", "settings", "controls"]:
		menu.show_page(pg)
		await _frames(20)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/menu_%s.png" % [dir, pg])
	menu.close_menu()
	quit()
