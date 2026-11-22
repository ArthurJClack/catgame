extends Node
## multiplayer (autoload "Net").
##
## other players show up as full procedural cats: the same CatRig as yours, fed the exact inputs
## your rig gets (position, velocity, floor contact, pose dials) plus everything it does at random
## (glances, blinks, ear flicks, tail twitches, swats, sounds it heard). see CatNetState.
##
## nobody is in charge of the world: each game sends its own cat to everyone else in the lobby
## (about 30 snapshots a second, ~6 kB/s per player) and plays theirs back ~0.1 s in the past.
## the levels, props and prey are still each player's own.
##
## how people find each other:
##   - steam (default): press M. host a lobby, invite friends through the steam overlay, or
##     browse public lobbies. needs steam running. see NetSteamTransport for the app id story.
##   - dedicated servers: the m menu's server list (steam server browser) or direct join by ip.
##     run one with `--headless -- --server` (NetDedicatedServer, steam listing: NetSteamServer)
##   - lan / direct ip: `-- --net-host` and `-- --net-join <ip>` (NetEnetTransport)
##   - `-- --nettest`: loopback test, your own cat echoed back through a fake laggy network

signal changed

const PROTO := 1
var SEND_HZ := 30.0
const EVENT_REPEATS := 4      # each life event rides along in this many snapshots (packet loss)
const PEER_TIMEOUT := 8.0

var steam: NetSteamTransport
var browser: NetServerBrowser   # dedicated server list (steam)
var server: NetDedicatedServer  # set when this game IS a dedicated server
var server_info := {}           # set while connected to a dedicated server: name, map, motd, max
var server_addr := ""
var transport: Node = null     # whichever transport is live
var peers := {}                # id -> NetPeer
var my_name := "cat"
var status_text := ""
var ui: Node = null

var _sim_t := 0.0
var _disp_t := 0.0
var _send_acc := 0.0
var _last: CatNetState
var _last_sent := false
var _event_id := 0
var _pending: Array = []       # [[id, t, ev, sends_left]]
var _hello_key := ""
var _player: Node = null
var _was_floor := true
var _was_claw := false
var _join_t := 0.0
var _map_done := false
var handlers := {}             # packet type byte -> func(from, data) for other systems (PreySync: 14)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	my_name = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else OS.get_environment("USER")
	if my_name == "":
		my_name = "cat"
	var args := OS.get_cmdline_user_args()
	if NetDedicatedServer.wanted(args):
		_start_server(args)
		return
	if "--nettest" in args:
		var lt := NetLoopTransport.new()
		# knobs for the test: --net-hz 30 --net-lag 60 (ms) --net-jitter 20 (ms) --net-loss 0.02
		var get_arg := func(flag: String, dflt: float) -> float:
			var i := args.find(flag)
			return float(args[i + 1]) if i >= 0 and i + 1 < args.size() else dflt
		SEND_HZ = get_arg.call("--net-hz", SEND_HZ)
		lt.latency = get_arg.call("--net-lag", 60.0) / 1000.0
		lt.jitter = get_arg.call("--net-jitter", 20.0) / 1000.0
		lt.loss = get_arg.call("--net-loss", 0.02)
		_use(lt)
	elif "--net-host" in args or "--net-join" in args:
		var et := NetEnetTransport.new()
		et.hosting = "--net-host" in args
		var ji := args.find("--net-join")
		if ji >= 0 and ji + 1 < args.size():
			et.address = args[ji + 1]
		var pi := args.find("--net-port")
		if pi >= 0 and pi + 1 < args.size():
			et.port = int(args[pi + 1])
		if args.find("--net-name") >= 0 and args.find("--net-name") + 1 < args.size():
			my_name = args[args.find("--net-name") + 1]
		if et.hosting:
			_use(et)
		else:
			join_server.call_deferred(et.address, et.port)   # a host or a dedicated server
			et.free()
	elif not _quiet_run(args):
		steam = NetSteamTransport.new()
		steam.name = "Steam"
		steam.proto = PROTO
		add_child(steam)
		if steam.start():
			my_name = steam.my_name
			steam.status.connect(_set_status)
			steam.lobby_changed.connect(func():
				# took a steam invite while on a server: the lobby wins
				if steam.in_lobby() and on_server():
					leave_server()
				changed.emit())
			_use(steam, false)
			_set_status("steam ready as %s. host a lobby or join one" % my_name)
			browser = NetServerBrowser.new()
			browser.name = "ServerBrowser"
			add_child(browser)
			browser.setup(steam.steam)
			browser.status.connect(_set_status)
		else:
			_set_status(steam.why)
		# steam's server browser (or a shortcut) started us with +connect ip:port
		var all := OS.get_cmdline_args()
		var ci := all.find("+connect")
		if ci >= 0 and ci + 1 < all.size():
			var hp := all[ci + 1].split(":")
			join_server.call_deferred(hp[0], int(hp[1]) if hp.size() > 1 else NetEnetTransport.PORT)
	if DisplayServer.get_name() != "headless" and not _quiet_run(args):
		ui = preload("res://scripts/net/lobby_ui.gd").new()
		add_child(ui)


func _start_server(args: PackedStringArray) -> void:
	# a dedicated server: no window, no cat. swap whatever level loaded for an empty scene
	Engine.max_fps = 120                       # forwarding latency <= ~8 ms without spinning a core
	Engine.physics_ticks_per_second = 30
	server = NetDedicatedServer.new()
	server.name = "Server"
	server.proto = PROTO
	server.configure(args)
	add_child(server)
	if not server.start():
		get_tree().quit(1)
		return
	var cs := get_tree().current_scene
	if cs == null or cs.scene_file_path != "res://server.tscn":
		get_tree().change_scene_to_file.call_deferred("res://server.tscn")


## join a dedicated server (or anyone running --net-host) by address
func join_server(addr: String, port: int = NetEnetTransport.PORT) -> void:
	addr = addr.strip_edges()
	if addr == "":
		return
	if ":" in addr and addr.count(":") == 1:
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	leave_server()
	if steam and steam.in_lobby():
		steam.leave_lobby()
	var et := NetEnetTransport.new()
	et.address = addr
	et.port = port
	_switch_to(et)
	if transport != et:
		return
	server_addr = "%s:%d" % [addr, port]
	_join_t = 0.0
	_map_done = false
	et.lost.connect(_on_server_lost)
	_set_status("connecting to %s..." % server_addr)


func leave_server() -> void:
	if not (transport is NetEnetTransport):
		return
	var t: NetEnetTransport = transport
	for id in t.members():
		t.send(id, PackedByteArray([CatNetState.T_BYE]), true)
	t.poll()
	_switch_to(steam if steam and steam.ready_ok else null)
	t.close()
	t.queue_free()
	var was: String = str(server_info.get("name", server_addr))
	server_info = {}
	server_addr = ""
	if was != "":
		_set_status("left %s" % was)


func on_server() -> bool:
	return transport is NetEnetTransport and server_addr != ""


func _on_server_lost() -> void:
	var nm: String = server_info.get("name", server_addr)
	var ever := not server_info.is_empty()
	leave_server()
	_set_status("lost the connection to %s" % nm if ever else "couldn't reach %s (wrong address, or its udp port isn't open)" % nm)


## swap the live transport: everyone from the old one leaves
func _switch_to(t: Node) -> void:
	if transport and is_instance_valid(transport):
		for id in peers.keys():
			_on_peer_left(id)
		for pair in [["packet", _on_packet], ["peer_joined", _on_peer_joined], ["peer_left", _on_peer_left]]:
			if transport.is_connected(pair[0], pair[1]):
				transport.disconnect(pair[0], pair[1])
	transport = null
	_hello_key = ""
	if t == null:
		changed.emit()
		return
	if t == steam:
		transport = steam
		steam.packet.connect(_on_packet)
		steam.peer_joined.connect(_on_peer_joined)
		steam.peer_left.connect(_on_peer_left)
		for m in steam.members():
			_on_peer_joined(m)
		changed.emit()
		return
	_use(t)
	changed.emit()


func _quiet_run(args: PackedStringArray) -> bool:
	# preview renders / test runs / headless (ci, scripts): never touch steam
	if DisplayServer.get_name() == "headless":
		return true
	for f in ["--preview", "--tour", "--showcase", "--posetest", "--parkour", "--report"]:
		if f in args:
			return true
	return false


func _use(t: Node, add := true) -> void:
	transport = t
	if add:
		t.name = "Transport"
		add_child(t)
	t.packet.connect(_on_packet)
	t.peer_joined.connect(_on_peer_joined)
	t.peer_left.connect(_on_peer_left)
	if add and not t.start():
		_set_status("couldn't start %s" % t.kind())
		transport = null
		return
	if add:
		_set_status("%s mode" % t.kind())


func _set_status(t: String) -> void:
	status_text = t
	print("net: ", t)
	changed.emit()


func online() -> bool:
	return transport != null and not transport.members().is_empty()


func my_id() -> int:
	return int(transport.my_id) if transport else 0


## who runs the shared world bits (prey) in my level: the lobby host when they're here, else the
## lowest player id in the level. a dedicated server only relays and never loads a level, so it
## is never it. offline = me.
func authority_here() -> int:
	var me := my_id()
	if transport == null:
		return me
	var here := _scene_path()
	if has_method("host_id"):
		var h := int(call("host_id"))
		if h == me:
			return me
		if peers.has(h) and (peers[h] as NetPeer).hello_seen and (peers[h] as NetPeer).scene == here:
			return h
	var best := me
	for id in peers:
		var p: NetPeer = peers[id]
		if p.hello_seen and p.scene == here and int(id) < best:
			best = int(id)
	return best


# ------------------------------------------------------------------ sending

## called by CatPlayer at the end of every physics tick, after it has set up its rig
func capture(player: Node, dt: float) -> void:
	_sim_t += dt
	_player = player
	var rig: CatRig = player.rig
	if rig == null:
		return
	if transport == null or transport.members().is_empty():
		rig.net_record = false
		rig.life_log.clear()
		return
	rig.net_record = true
	# whatever the rig did at random since the last tick (it animates in _process, so these
	# happened at the last displayed frame's time)
	for ev in rig.life_log:
		_event_id += 1
		_pending.append([_event_id, _disp_t, ev, EVENT_REPEATS])
	rig.life_log.clear()
	var prev := _last
	var prev_sent := _last_sent
	_last = CatNetState.from_rig(rig, _sim_t, player.get("carried"), _disp_t)
	_last_sent = false
	_send_acc += dt
	# something snapped this tick (take off, landing, claws, a pose dial jumping like the
	# pounce charge letting go). linear playback would smear it over a whole send interval,
	# so the tick before goes out too and the copy gets both sides of the jump
	var urgent := _last.on_floor != _was_floor or _last.claw_on != _was_claw
	if prev and not urgent:
		# a paw letting go of / coming back to the ground (FREE is mode 2 in both bits)
		var fr_now := _last.pmode & 0xAA
		var fr_prev := prev.pmode & 0xAA
		urgent = fr_now != fr_prev
	if prev and not urgent:
		for i in mini(prev.dials.size(), _last.dials.size()):
			if absf(_last.dials[i] - prev.dials[i]) > 0.2:
				urgent = true
				break
	if _last.on_floor != _was_floor:
		# exact moment of take off / landing, repeated like the life events so a lost packet
		# can't make the copy land late (the landing squash and paw plant hang off it)
		_event_id += 1
		_pending.append([_event_id, _sim_t, ["F", _last.on_floor], EVENT_REPEATS])
	_was_floor = _last.on_floor
	_was_claw = _last.claw_on
	if urgent and prev and not prev_sent:
		_send_state(prev)
	if _send_acc >= 1.0 / SEND_HZ or urgent or (not _pending.is_empty() and _pending[-1][3] == EVENT_REPEATS):
		_send_acc = 0.0
		_send_snapshot()
	_check_hello()


func _send_state(st: CatNetState) -> void:
	st.events = []
	var bytes := st.encode()
	for id in transport.members():
		transport.send(id, bytes, false)


func _send_snapshot() -> void:
	_last_sent = true
	_last.events = []
	for p in _pending:
		_last.events.append([p[0], p[1], p[2]])
		p[3] -= 1
	_pending = _pending.filter(func(p): return p[3] > 0)
	var bytes := _last.encode()
	for id in transport.members():
		transport.send(id, bytes, false)


func _scene_path() -> String:
	var cs := get_tree().current_scene
	return cs.scene_file_path if cs else ""


func _hello_bytes() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(CatNetState.T_HELLO)
	b.put_u8(PROTO)
	b.put_utf8_string(my_name)
	b.put_utf8_string(str(_player.get("style")) if _player else "block_black")
	b.put_utf8_string(_scene_path())
	return b.data_array


func _check_hello() -> void:
	var key := "%s|%s" % [_player.get("style"), _scene_path()]
	if key != _hello_key:
		_hello_key = key
		_send_hello_to(transport.members())
		if not server_info.is_empty():
			transport.send(1, _hello_bytes(), true)


func _send_hello_to(ids: Array) -> void:
	if transport == null:
		return
	var bytes := _hello_bytes()
	for id in ids:
		transport.send(id, bytes, true)


# ------------------------------------------------------------------ receiving

func _peer(id: int) -> NetPeer:
	if not peers.has(id):
		var p := NetPeer.new()
		p.id = id
		p.name = transport.display_name(id) if transport else "cat"
		peers[id] = p
	return peers[id]


func _on_peer_joined(id: int) -> void:
	var p := _peer(id)
	p.last_heard = NetPeer.now()
	_send_hello_to([id])
	_flash("%s joined" % p.name)
	changed.emit()


func _on_peer_left(id: int) -> void:
	if peers.has(id):
		var p: NetPeer = peers[id]
		_flash("%s left" % p.name)
		if is_instance_valid(p.cat):
			p.cat.queue_free()
		peers.erase(id)
	changed.emit()


func _on_packet(from: int, data: PackedByteArray) -> void:
	if data.is_empty():
		return
	match data[0]:
		CatNetState.T_SNAP:
			var s := CatNetState.decode(data)
			if s:
				_peer(from).push(s, 1.0 / SEND_HZ)
		CatNetState.T_HELLO:
			var b := StreamPeerBuffer.new()
			b.data_array = data
			b.seek(1)
			var proto := b.get_u8()
			var p := _peer(from)
			var first := not p.hello_seen
			p.hello_seen = true
			p.last_heard = NetPeer.now()
			var nm := b.get_utf8_string().strip_edges().left(32)
			if nm != "" and not transport is NetSteamTransport:
				p.name = nm     # steam names come from steam, never from the packet
			p.style = b.get_utf8_string()
			var was := p.scene
			p.scene = b.get_utf8_string()
			# hub travel: say when a friend walks off to another level (or comes to ours)
			if not first and was != "" and was != p.scene:
				if p.scene == _scene_path():
					_flash("%s came over to %s" % [p.name, scene_label(p.scene)])
				else:
					_flash("%s went to %s" % [p.name, scene_label(p.scene)])
			if proto != PROTO:
				_flash("%s has a different game version" % p.name)
			if first:
				_send_hello_to([from])   # make sure they have ours too
			changed.emit()
		CatNetState.T_BYE:
			_on_peer_left(from)
		CatNetState.T_INFO:
			if from == 1 and transport is NetEnetTransport:
				_on_server_info(NetDedicatedServer.read_info(data))
		_:
			var h: Callable = handlers.get(data[0], Callable())
			if h.is_valid():
				h.call(from, data)


func _on_server_info(info: Dictionary) -> void:
	server_info = info
	_set_status("on %s" % info.name)
	if info.proto != PROTO:
		_flash("%s runs a different game version, update both" % info.name)
	elif info.motd != "":
		_flash(info.motd)
	# the server knows us by our hello (name on the server list, who's where)
	if transport:
		transport.send(1, _hello_bytes(), true)
	# everyone starts in the server's level (you can still wander off, you'll only see cats
	# in the same level as you)
	var map: String = info.map
	if not _map_done and map != "" and map != _scene_path() and ResourceLoader.exists(map):
		_map_done = true
		print("net: heading to %s, where the server is" % scene_label(map))
		var root := get_tree().current_scene
		if is_instance_valid(_player):
			Engine.set_meta("cat_style", _player.get("style"))
		if root and root.has_method("go_scene"):
			root.call("go_scene", map)
		else:
			get_tree().change_scene_to_file.call_deferred(map)
	_map_done = true


# ------------------------------------------------------------------ per frame

func _process(dt: float) -> void:
	NetPeer.clock += dt
	# time of the frame about to be drawn, in sim clock (the player draws between ticks)
	_disp_t = _sim_t - (1.0 - Engine.get_physics_interpolation_fraction()) / float(Engine.physics_ticks_per_second)
	if transport:
		transport.poll()
	if steam and transport != steam:
		steam.poll()
	if on_server() and server_info.is_empty():
		_join_t += dt
		if _join_t > 10.0:
			_on_server_lost()
	var here := _scene_path()
	var root := get_tree().current_scene
	var t := NetPeer.now()
	for id in peers.keys():
		var p: NetPeer = peers[id]
		if t - p.last_heard > PEER_TIMEOUT and p.last_heard > 0.0:
			_on_peer_left(id)
			continue
		var want := root != null and p.hello_seen and p.scene == here and _player_in(root)
		if want and not (is_instance_valid(p.cat) and p.cat.get_parent() == root):
			var rc := RemoteCat.new()
			rc.peer = p
			rc.name = "RemoteCat_%d" % (id % 100000)
			root.add_child(rc)
			p.cat = rc
			print("net: %s's cat is here" % p.name)
		elif not want and is_instance_valid(p.cat):
			p.cat.queue_free()
			p.cat = null


func _player_in(root: Node) -> bool:
	return is_instance_valid(_player) and root.is_ancestor_of(_player)


func _flash(t: String) -> void:
	print("net: ", t)
	if is_instance_valid(_player) and _player.has_method("_event"):
		_player.call("_event", t)


## send everyone to another player's level (lobby menu "go to them")
func go_to(id: int) -> void:
	if not peers.has(id):
		return
	var path: String = peers[id].scene
	if path == "" or path == _scene_path() or not ResourceLoader.exists(path):
		return
	var root := get_tree().current_scene
	if is_instance_valid(_player):
		Engine.set_meta("cat_style", _player.get("style"))
	if root and root.has_method("go_scene"):
		root.call("go_scene", path)
	else:
		get_tree().change_scene_to_file.call_deferred(path)


static func scene_label(path: String) -> String:
	match path:
		"res://main.tscn": return "the farm"
		"res://forest.tscn": return "the forest"
		"res://stealth.tscn": return "the docks"
		"res://trail.tscn": return "the trail"
		"res://arena.tscn": return "the arena"
	return path.get_file().get_basename()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if server and is_instance_valid(server):
			server.close()
		if transport and is_instance_valid(transport):
			var b := PackedByteArray([CatNetState.T_BYE])
			for id in transport.members():
				transport.send(id, b, true)
			if transport is NetSteamTransport:
				transport.close()
