extends CanvasLayer
## play online (m, or "play online" on the title screen). three pages:
##   home:   host a game (steam friends / steam public / lan + direct ip) or join one (steam
##           lobbies, dedicated servers off steam's list, or type an address)
##   room:   the lobby. everyone in it with their coat + ready tick. you pick your coat and tick
##           ready, the host picks the level and presses start, every game loads it (Net.start_match).
##           mid match it shows who's where, "go to them", and the host can move everyone on.
##   server: on a dedicated server (always on, no room): who's here, leave.
## works with mouse, keyboard (tab / arrows) and pads (d-pad + A, B closes).

signal closed

const W := 640
const GOLD := Color(0.95, 0.78, 0.2)
const DIM := Color(0.62, 0.63, 0.67)
const GOOD := Color(0.55, 0.9, 0.5)

var page := ""
var _root: Control
var _body: VBoxContainer
var _title: Label
var status: Label
var _lobbies: Array = []
var _servers: Array = []
var _addr_text := ""
var _start_armed := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _dirty := false


func _ready() -> void:
	layer = 95       # over the title screen (85) and the pause menu (90)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	Net.changed.connect(func(): _dirty = true)
	if Net.steam:
		Net.steam.lobbies_listed.connect(func(l): _lobbies = l; _dirty = true)
	if Net.browser:
		Net.browser.servers_listed.connect(func(l): _servers = l; _dirty = true)


func _process(_dt: float) -> void:
	if _dirty and visible:
		_dirty = false
		_rebuild()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # clicks off the panel don't reach the game
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.085, 0.1, 0.96)
	sb.border_color = Color(GOLD, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 20
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(W, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = W
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	v.add_child(status)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	v.add_child(_body)


# ---------------------------------------------------------------- open / close

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	var esc := k != null and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE
	var pad_b: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B
	if esc or pad_b:
		# esc while typing an address just leaves the box
		var f := get_viewport().gui_get_focus_owner()
		if esc and f is LineEdit:
			f.release_focus()
		else:
			close()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_M:
		var gm := get_node_or_null("/root/GameMenu")
		if gm and gm.is_open:
			return       # one menu at a time
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	visible = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	CatKeys.blocked = true
	_start_armed = false
	if not Net.in_room() and not Net.on_server():
		_refresh_lists()
	_rebuild()


func close() -> void:
	if not visible:
		return
	visible = false
	var titled := not get_tree().get_nodes_in_group("title_screen").is_empty()
	CatKeys.blocked = titled
	if not OS.has_feature("web") and not titled:
		Input.mouse_mode = _mouse_before if _mouse_before != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _refresh_lists() -> void:
	if Net.steam and Net.steam.ready_ok:
		Net.steam.refresh()
	if Net.browser and Net.browser.available():
		Net.browser.refresh()


# ---------------------------------------------------------------- widgets

func _btn(parent: Node, text: String, fn: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 40)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(fn)
	if w <= 0.0:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


func _hbox(parent: Node = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	(parent if parent else _body).add_child(h)
	return h


func _label(parent: Node, text: String, size := 16, col := Color(0.92, 0.92, 0.94), expand := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
	parent.add_child(l)
	return l


func _section(text: String) -> void:
	_label(_body, text, 15, Color(GOLD, 0.85))


func _note(text: String) -> Label:
	var l := _label(_body, text, 13, DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = W
	return l


func _list(max_h := 230.0) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(W, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	_body.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	# grow with the list up to max_h, then scroll
	v.resized.connect(func(): sc.custom_minimum_size.y = minf(v.size.y, max_h))
	return v


func _row_panel(parent: Node, lit := false) -> HBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.17, 0.08, 0.55) if lit else Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	pc.add_child(h)
	return h


static func coat_name(st: String) -> String:
	return str(GameMenu.COAT_NAMES.get(st, st))


# ---------------------------------------------------------------- pages

func _rebuild() -> void:
	if not visible:
		return
	# keep pad / keyboard focus on the same button across rebuilds (Net.changed fires a lot)
	var f := get_viewport().gui_get_focus_owner()
	var keep := ""
	if f is Button and _body.is_ancestor_of(f):
		keep = (f as Button).text
	var typing := f is LineEdit and _body.is_ancestor_of(f)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	status.text = Net.status_text
	if Net.on_dedicated():
		page = "server"
		_page_server()
	elif Net.in_room():
		page = "room"
		_page_room()
	else:
		page = "home"
		_page_home()
	_refocus.call_deferred(keep, typing)


func _refocus(keep: String, typing: bool) -> void:
	if not visible:
		return
	var first: Control = null
	var match_b: Control = null
	var le: Control = null
	var stack: Array = [_body]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is LineEdit and le == null:
			le = n
		if n is Button and (n as Button).visible and not (n as Button).disabled:
			if first == null:
				first = n
			if keep != "" and (n as Button).text == keep and match_b == null:
				match_b = n
		stack.append_array(n.get_children())
	if typing and le:
		le.grab_focus()
	elif match_b:
		match_b.grab_focus()
	elif first and keep == "":
		first.grab_focus()
	elif first and not _body.is_ancestor_of(get_viewport().gui_get_focus_owner() if get_viewport().gui_get_focus_owner() else _body):
		first.grab_focus()


func _page_home() -> void:
	_title.text = "play online"
	var st: NetSteamTransport = Net.steam
	var steam_ok := st != null and st.ready_ok
	_section("host a game")
	var h := _hbox()
	if steam_ok:
		_btn(h, "host for friends", func(): st.host(false))
		_btn(h, "host public", func(): st.host(true))
	_btn(h, "host on lan / ip", func(): Net.host_lan())
	if not steam_ok:
		_note("steam isn't running, so it's lan / direct ip for now: host here and friends type your ip (udp port %d)." % NetEnetTransport.PORT)

	_section("join a game")
	if steam_ok:
		var bar := _hbox()
		_btn(bar, "refresh", _refresh_lists)
		if Net.browser and Net.browser.available():
			_btn(bar, "lan servers", func(): Net.browser.refresh(true))
		var list := _list()
		if _lobbies.is_empty() and _servers.is_empty():
			_label(list, "nothing yet. host one, or refresh", 15, DIM)
		for l in _lobbies:
			var r := _row_panel(list)
			var nm: String = l.name if l.name != "" else "cats"
			_label(r, nm, 16, Color.WHITE, true)
			_label(r, "lobby · %d / %d" % [l.cats, l.max], 14, DIM)
			var lid: int = l.id
			_btn(r, "join", func(): st.join_lobby(lid), 90)
		for sv in _servers.slice(0, 20):
			var r := _row_panel(list)
			_label(r, sv.name, 16, Color.WHITE, true)
			var where: String = (" · %s" % sv.map) if sv.map != "" else ""
			_label(r, "server · %d / %d%s · %d ms" % [sv.cats, sv.max, where, sv.ping], 14, DIM)
			var a: String = sv.addr
			var p: int = sv.port
			if a != "":
				_btn(r, "join", func(): Net.join_server(a, p), 90)
	# anyone can type an address: a friend's lan game, a server steam doesn't list
	var direct := _hbox()
	var le := LineEdit.new()
	le.placeholder_text = "friend's ip or server  (ip or ip:port)"
	le.text = _addr_text
	le.custom_minimum_size.y = 40
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(t): _addr_text = t)
	le.text_submitted.connect(func(t): Net.join_server(t))
	direct.add_child(le)
	_btn(direct, "join", func(): Net.join_server(_addr_text), 90)
	var bottom := _hbox()
	_btn(bottom, "back", close)
	if steam_ok:
		_note("testing on steam's shared test app (480), so steam may call the game \"Spacewar\". friends get invites in the steam overlay (shift+tab).")


func _page_room() -> void:
	var st: NetSteamTransport = Net.steam
	var tr = Net.transport
	var host := Net.is_host()
	var hp := Net.host_peer()
	if tr == st:
		_title.text = st.lobby_name() if st.lobby_name() != "" else "lobby"
	elif Net.hosting_lan():
		_title.text = "your lan game"
	else:
		_title.text = "%s's game" % hp.name if hp and hp.hello_seen else "lan game"
	var connecting: bool = tr is NetEnetTransport and not host and not (tr as NetEnetTransport).connected()
	if connecting:
		_note("connecting to %s..." % Net.server_addr)
	if Net.hosting_lan():
		_note("friends join with your ip: %s  (udp port %d, open it on your router for people outside your wifi)" % [_my_ips(), (tr as NetEnetTransport).port])

	# who's here
	var count := 1
	var ready_n := 1 if Net.me_ready else 0
	var list := _list(260)
	var in_match := _in_match()
	_player_row(list, "%s (you)" % Net.my_name, Net.my_style(), Net.me_ready, host, Net._scene_path() if in_match else "")
	for id in (tr.members() if tr else []):
		var p: NetPeer = Net.peers.get(id)
		count += 1
		if p and p.ready:
			ready_n += 1
		var nm: String = p.name if p else tr.display_name(id)
		var is_h: bool = id == Net.host_id()
		if p == null or not (p.hello_seen or p.lobby_seen):
			var r := _row_panel(list)
			_label(r, nm, 16, Color.WHITE, true)
			_label(r, "joining...", 14, DIM)
			continue
		var where := p.scene if (in_match or (p.playing and is_h)) else ""
		var r2 := _player_row(list, nm, p.style, p.ready, is_h, where)
		if in_match and p.scene != "" and p.scene != Net._scene_path() and ResourceLoader.exists(p.scene):
			_btn(r2, "go to them", func(): Net.go_to(id); close(), 120)

	# your cat
	var me := _hbox()
	_label(me, "your coat", 16, Color.WHITE)
	var coats: Array = CatRig.STYLE_ORDER
	var ci := maxi(coats.find(Net.my_style()), 0)
	_btn(me, "<", func(): Net.set_style(coats[(ci - 1 + coats.size()) % coats.size()]), 44)
	var cl := _label(me, coat_name(coats[ci]), 17, GOLD)
	cl.custom_minimum_size.x = 130
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn(me, ">", func(): Net.set_style(coats[(ci + 1) % coats.size()]), 44)
	if not in_match:
		var rb := _btn(me, "ready!" if not Net.me_ready else "not ready", func(): Net.set_ready(not Net.me_ready))
		if Net.me_ready:
			rb.add_theme_color_override("font_color", GOOD)

	# the level + start
	if host:
		var lv := _hbox()
		_label(lv, "level", 16, Color.WHITE)
		var levels: Array = Net.LEVELS
		var li := maxi(levels.find(Net.level), 0)
		_btn(lv, "<", func(): Net.set_level(levels[(li - 1 + levels.size()) % levels.size()]), 44)
		var ll := _label(lv, Net.scene_label(levels[li]), 17, GOLD)
		ll.custom_minimum_size.x = 130
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_btn(lv, ">", func(): Net.set_level(levels[(li + 1) % levels.size()]), 44)
		var all_in := Net.everyone_ready()
		if in_match and Net.level == Net._scene_path():
			_note("everyone's here. pick another level to take the whole lobby there.")
			all_in = false
		var word := "take everyone to %s" % Net.scene_label(Net.level) if in_match else "start"
		var txt := word
		if not all_in and not in_match:
			txt = "not everyone's ready. start anyway?" if _start_armed else "%s  (%d / %d ready)" % [word, ready_n, count]
		var sb: Button = null
		if not (in_match and Net.level == Net._scene_path()):
			sb = _btn(_body, txt, _on_start)
			sb.custom_minimum_size.y = 48
			sb.add_theme_font_size_override("font_size", 20)
			if all_in or in_match:
				sb.add_theme_color_override("font_color", GOOD)
	elif hp and hp.playing and not in_match:
		var jb := _btn(_body, "jump in (%s is playing %s)" % [hp.name, Net.scene_label(hp.level)], func(): Net.jump_in(); close())
		jb.custom_minimum_size.y = 48
	elif not in_match:
		var lvl := Net.scene_label(hp.level) if hp and hp.level != "" else "..."
		_note("waiting for %s to start · level: %s" % [hp.name if hp else "the host", lvl])

	var bottom := _hbox()
	if tr == st and st:
		_btn(bottom, "invite friends", st.invite_friends)
	_btn(bottom, "leave", func(): Net.leave(); _start_armed = false)
	_btn(bottom, "close", close)


func _player_row(list: Node, nm: String, style: String, is_ready: bool, host: bool, where: String) -> HBoxContainer:
	var r := _row_panel(list, host)
	_label(r, nm, 16, Color.WHITE, true)
	if host:
		_label(r, "host", 13, GOLD)
	_label(r, coat_name(style), 14, DIM)
	if where != "":
		_label(r, Net.scene_label(where), 14, DIM)
	else:
		var l := _label(r, "ready" if is_ready else "not ready", 14, GOOD if is_ready else DIM)
		l.custom_minimum_size.x = 76
	return r


func _in_match() -> bool:
	# a match is on and we're in it (the room page turns into "who's where")
	if Net.is_host():
		return Net.playing
	var hp := Net.host_peer()
	return hp != null and hp.playing and hp.scene == Net._scene_path() and get_tree().get_nodes_in_group("title_screen").is_empty()


func _on_start() -> void:
	if not Net.everyone_ready() and not _in_match() and not _start_armed:
		_start_armed = true      # two presses when someone isn't ready yet
		_rebuild()
		return
	_start_armed = false
	Net.start_match()
	close()


func _page_server() -> void:
	_title.text = str(Net.server_info.get("name", "server"))
	_note("dedicated server · %s · always on: you're dropped into its level, wander off through the gates if you like." % Net.scene_label(str(Net.server_info.get("map", ""))))
	var list := _list(300)
	_player_row(list, "%s (you)" % Net.my_name, Net.my_style(), false, false, Net._scene_path())
	var tr = Net.transport
	for id in (tr.members() if tr else []):
		var p: NetPeer = Net.peers.get(id)
		var nm: String = p.name if p else tr.display_name(id)
		if p == null or not p.hello_seen:
			var r := _row_panel(list)
			_label(r, nm, 16, Color.WHITE, true)
			_label(r, "joining...", 14, DIM)
			continue
		var r2 := _player_row(list, nm, p.style, false, false, p.scene)
		if p.scene != "" and p.scene != Net._scene_path():
			_btn(r2, "go to them", func(): Net.go_to(id); close(), 120)
	var bottom := _hbox()
	_btn(bottom, "leave server", Net.leave)
	_btn(bottom, "close", close)


static func _my_ips() -> String:
	var out := []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and int(a.get_slice(".", 1)) >= 16 and int(a.get_slice(".", 1)) < 32):
			out.append(a)
	return " / ".join(out) if out.size() > 0 else "(ipconfig shows it)"
