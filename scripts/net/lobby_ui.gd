extends CanvasLayer
## M: the multiplayer menu. host a lobby (friends only or public), invite friends through the
## steam overlay, browse lobbies, see who's here and which level they're in, leave.

var panel: PanelContainer
var box: VBoxContainer
var status: Label
var lobby_list: VBoxContainer
var member_list: VBoxContainer
var actions: HBoxContainer
var hint: Label
var _lobbies: Array = []
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: get_viewport().set_input_as_handled())
	add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.position = Vector2(-280, -230)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.11, 0.94)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	dim.add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "cats online"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 520
	status.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	box.add_child(status)
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	member_list = VBoxContainer.new()
	box.add_child(member_list)
	lobby_list = VBoxContainer.new()
	box.add_child(lobby_list)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 520
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	hint.text = "m closes · friends get your invite in steam (shift+tab overlay too) · testing on steam's shared test app (480), so steam may call the game \"Spacewar\""
	box.add_child(hint)
	visible = false
	Net.changed.connect(_rebuild)
	if Net.steam:
		Net.steam.lobbies_listed.connect(func(l): _lobbies = l; _rebuild())


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_M:
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and k and k.pressed and k.physical_keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	if visible:
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if Net.steam and Net.steam.ready_ok and not Net.steam.in_lobby():
			Net.steam.refresh()
		_rebuild()
	elif not OS.has_feature("web"):
		Input.mouse_mode = _mouse_before if _mouse_before != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED


func _btn(parent: Node, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


func _row(parent: Node, text: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	parent.add_child(r)
	return r


func _rebuild() -> void:
	if not visible:
		return
	status.text = Net.status_text
	_clear(actions)
	_clear(member_list)
	_clear(lobby_list)
	var st: NetSteamTransport = Net.steam
	var tr = Net.transport
	if st and st.ready_ok:
		if st.in_lobby():
			_btn(actions, "invite friends", st.invite_friends)
			_btn(actions, "leave", st.leave_lobby)
		else:
			_btn(actions, "host (friends)", func(): st.host(false))
			_btn(actions, "host (public)", func(): st.host(true))
			_btn(actions, "refresh", st.refresh)
	# who's here
	if tr and (not (tr is NetSteamTransport) or st.in_lobby()):
		var hdr := Label.new()
		hdr.text = st.lobby_name() if tr is NetSteamTransport else "%s (%s)" % ["playing together", tr.kind()]
		hdr.add_theme_font_size_override("font_size", 18)
		member_list.add_child(hdr)
		_row(member_list, "you (%s)" % Net.my_name)
		for id in tr.members():
			var p: NetPeer = Net.peers.get(id)
			var nm: String = p.name if p else tr.display_name(id)
			var where := ""
			if p and p.hello_seen:
				where = " · " + Net.scene_label(p.scene)
				if st and tr is NetSteamTransport and id == st.lobby_owner:
					where += " · host"
			else:
				where = " · connecting..."
			var r := _row(member_list, nm + where)
			if p and p.hello_seen and p.scene != Net._scene_path() and p.scene != "":
				_btn(r, "go to them", func(): Net.go_to(id); toggle())
	elif st and st.ready_ok:
		var hdr := Label.new()
		hdr.text = "lobbies" if not _lobbies.is_empty() else "no lobbies yet, host one"
		hdr.add_theme_font_size_override("font_size", 18)
		lobby_list.add_child(hdr)
		for l in _lobbies:
			var nm: String = l.name if l.name != "" else "cats"
			var r := _row(lobby_list, "%s  (%d/%d)" % [nm, l.cats, l.max])
			var lid: int = l.id
			_btn(r, "join", func(): st.join_lobby(lid))
	elif tr == null:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 520
		l.text = "no steam: you can still play over lan / direct ip.\nhost: start the game with  -- --net-host\nfriend: start with  -- --net-join <host's ip>   (udp port 24680)"
		member_list.add_child(l)
