extends SceneTree
## Headless check of the updater logic (runs on any OS, skips the Windows-only gate):
##   godot --headless --path . -s tests/updater_test.gd
## Checks version compare, then fakes a "newer release" reply pointing at a real GitHub
## release asset (redirects included) and makes sure the download lands as READY.

const U := preload("res://scripts/updater.gd")

func _initialize() -> void:
	var ok := true
	var cases := [["0.1.10", "0.1.9", 1], ["v0.2.0", "0.2.0", 0], ["0.1.0", "0.1.1", -1],
			["1.0", "0.9.99", 1], ["0.1", "0.1.0", 0]]
	for c in cases:
		var got: int = U.compare_versions(c[0], c[1])
		if got != c[2]:
			ok = false
			print("FAIL compare %s %s -> %d (want %d)" % [c[0], c[1], got, c[2]])
	print("compare_versions ", "ok" if ok else "FAILED")
	_run_download.call_deferred(ok)

func _run_download(ok: bool) -> void:
	var u: Node = U.new()
	root.add_child(u)  # _ready bails out (not a windows template build)
	u.current_version = "0.1.0"
	u._setup_path = OS.get_user_data_dir().path_join("update_test").path_join("CatGame-Setup.exe")
	u._build_banner()
	u._http = HTTPRequest.new()
	u.add_child(u._http)
	var fake := {"tag_name": "v0.1.5", "assets": [{"name": "CatGame-Setup.exe",
		"browser_download_url": "https://github.com/godotengine/godot/releases/download/4.3-stable/SHA512-SUMS.txt",
		"size": 0}]}
	u._http.request_completed.connect(u._on_release_info)
	u._on_release_info(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(fake).to_utf8_buffer())
	var t := 0.0
	while u.state == U.State.DOWNLOADING and t < 60.0:
		await process_frame
		t += 1.0 / 60.0
		await create_timer(0.05).timeout
	var ready: bool = u.state == U.State.READY and FileAccess.file_exists(u._setup_path)
	print("download -> state %d, file %s" % [u.state, FileAccess.file_exists(u._setup_path)])
	# an older/equal release must not trigger anything
	var u2: Node = U.new()
	root.add_child(u2)
	u2.current_version = "0.1.5"
	u2._http = HTTPRequest.new()
	u2.add_child(u2._http)
	u2._http.request_completed.connect(u2._on_release_info)
	u2._on_release_info(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(fake).to_utf8_buffer())
	var same_ok: bool = u2.state == U.State.UP_TO_DATE
	print("same version -> up to date: ", same_ok)
	u.state = U.State.IDLE  # don't try to "install" a txt file on exit
	DirAccess.remove_absolute(u._setup_path)
	var all := ok and ready and same_ok
	print("ALL ", "PASS" if all else "FAIL")
	quit(0 if all else 1)
