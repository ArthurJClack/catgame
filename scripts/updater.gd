extends Node
## Auto updater (autoload "Updater").
##
## On launch of an installed Windows build it asks GitHub for the latest release of
## ArthurJClack/catgame. If that release is newer than this build's
## application/config/version, it downloads CatGame-Setup.exe in the background while
## you play. Once it's ready:
##   - F9 restarts into the new version right away, or
##   - quitting the game installs it silently, and the next launch is the new version.
##
## It does nothing in the editor, on the web build, in non-Windows builds, or when the
## game was started with --no-update (preview renders etc). Every failure (offline, rate
## limited, bad download) is silent: the game just keeps running the version it has.

const REPO := "ArthurJClack/catgame"
const API_LATEST := "https://api.github.com/repos/%s/releases/latest" % REPO
const ASSET_NAME := "CatGame-Setup.exe"
const UA := "CatGame-Updater"

enum State { IDLE, CHECKING, DOWNLOADING, READY, FAILED, UP_TO_DATE }

var state := State.IDLE
var current_version := ""
var latest_version := ""
var _asset_url := ""
var _asset_size := 0
var _setup_path := ""
var _http: HTTPRequest
var _installing := false

var _layer: CanvasLayer
var _label: Label


func _ready() -> void:
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if not _should_run():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_path = OS.get_user_data_dir().path_join("update").path_join(ASSET_NAME)
	_cleanup_old_download()
	_build_banner()
	_check()


static func _should_run() -> bool:
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return false
	if OS.get_name() != "Windows":
		return false
	if DisplayServer.get_name() == "headless":
		return false
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for flag in ["--no-update", "--preview", "--tour", "--showcase", "--posetest"]:
		if flag in args:
			return false
	return true


# ---------------------------------------------------------------- version check

func _check() -> void:
	state = State.CHECKING
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_release_info)
	var err := _http.request(API_LATEST, ["User-Agent: " + UA, "Accept: application/vnd.github+json"])
	if err != OK:
		_fail("request failed (%d)" % err)


func _on_release_info(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.request_completed.disconnect(_on_release_info)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("release check failed (result %d, http %d)" % [result, code])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_fail("bad release json")
		return
	latest_version = str(data.get("tag_name", "")).trim_prefix("v")
	if compare_versions(latest_version, current_version) <= 0:
		state = State.UP_TO_DATE
		print("[updater] up to date (%s)" % current_version)
		return
	for a in data.get("assets", []):
		if typeof(a) == TYPE_DICTIONARY and a.get("name", "") == ASSET_NAME:
			_asset_url = str(a.get("browser_download_url", ""))
			_asset_size = int(a.get("size", 0))
	if _asset_url == "":
		_fail("release %s has no %s" % [latest_version, ASSET_NAME])
		return
	_download()


## Returns 1 if a > b, -1 if a < b, 0 if equal. "1.2.10" > "1.2.9".
static func compare_versions(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


# ---------------------------------------------------------------- download

func _download() -> void:
	state = State.DOWNLOADING
	DirAccess.make_dir_recursive_absolute(_setup_path.get_base_dir())
	var part := _setup_path + ".part"
	if FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	_http.timeout = 0.0  # big file, slow connections are fine
	_http.download_file = part
	_http.request_completed.connect(_on_downloaded)
	var err := _http.request(_asset_url, ["User-Agent: " + UA])
	if err != OK:
		_fail("download request failed (%d)" % err)
		return
	_show("downloading update v%s..." % latest_version)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var part := _setup_path + ".part"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("download failed (result %d, http %d)" % [result, code])
		return
	var f := FileAccess.open(part, FileAccess.READ)
	var size := f.get_length() if f else -1
	f = null
	if size <= 0 or (_asset_size > 0 and size != _asset_size):
		_fail("download size mismatch (%d vs %d)" % [size, _asset_size])
		return
	if FileAccess.file_exists(_setup_path):
		DirAccess.remove_absolute(_setup_path)
	DirAccess.rename_absolute(part, _setup_path)
	state = State.READY
	print("[updater] v%s downloaded to %s" % [latest_version, _setup_path])
	_show("update v%s ready: F9 to restart now, or it installs when you quit" % latest_version, 0.0)


func _process(_delta: float) -> void:
	if state == State.DOWNLOADING and _http and _asset_size > 0:
		var pct := int(100.0 * _http.get_downloaded_bytes() / _asset_size)
		_label.text = "downloading update v%s... %d%%" % [latest_version, clampi(pct, 0, 100)]


func _cleanup_old_download() -> void:
	# a setup exe left over from an update we already installed (or an older one)
	for p in [_setup_path, _setup_path + ".part"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _fail(why: String) -> void:
	state = State.FAILED
	print("[updater] " + why)
	if _layer:
		_layer.visible = false


# ---------------------------------------------------------------- install

func _unhandled_input(event: InputEvent) -> void:
	if state == State.READY and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F9:
		get_viewport().set_input_as_handled()
		install(true)


## Runs the downloaded installer silently. relaunch = start the game again after.
func install(relaunch: bool) -> void:
	if state != State.READY or _installing:
		return
	_installing = true
	var args := PackedStringArray(["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-",
			"/CLOSEAPPLICATIONS", "/UPDATE"])
	if relaunch:
		args.append("/RELAUNCH")
	var pid := OS.create_process(_setup_path, args)
	print("[updater] started installer pid %d %s" % [pid, args])
	if relaunch:
		get_tree().quit()


func _exit_tree() -> void:
	# window closed or game quit with an update waiting: install it on the way out
	if state == State.READY and not _installing:
		install(false)


# ---------------------------------------------------------------- banner

func _build_banner() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.visible = false
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -16.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	panel.add_child(_label)


func _show(text: String, hide_after := 0.0) -> void:
	_label.text = text
	_layer.visible = true
	if hide_after > 0.0:
		get_tree().create_timer(hide_after).timeout.connect(func(): _layer.visible = false)
