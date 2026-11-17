extends SceneTree
## ci only: does this GodotSteam Server build survive serverInit and log on to steam?
## (some builds parse the ip with a steam networking call that crashes before init.)
##   CATGAME_STEAM_TRACE=1 godot --headless --path . --script res://tests/steam_server_init.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var srv := NetSteamServer.new()
	srv.game_port = 24794
	srv.query_port = 27017
	srv.server_name = "catgame ci init test"
	root.add_child(srv)
	srv.status.connect(func(t): print("status: ", t))
	if not srv.start():
		print("init FAILED: ", srv.why)
		quit(1)
		return
	print("init ok, waiting for steam logon")
	for i in 400:
		srv.poll()
		await process_frame
		OS.delay_msec(50)
		if srv.logged_on:
			break
	print("logged on: ", srv.logged_on)
	srv.close()
	quit(0 if srv.logged_on else 2)
