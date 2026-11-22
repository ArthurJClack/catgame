class_name NetDedicatedServer
extends Node
## a dedicated server: no window, no cat of its own, just keeps a place where players meet.
##   linux:   ./CatGameServer.x86_64 --headless -- --server --name "my cats" --map forest
##   windows: CatGame.exe --headless -- --server            (any normal build works too)
##
## players connect over enet (udp, --port, default 24680) and the server passes every cat's
## snapshots on to everyone else (the same star the lan host uses, NetEnetTransport). each player's
## game still runs its own world, the server only relays, so it's cheap: a few % of one core and
## ~6 kB/s per player each way.
##
## with the GodotSteam Server extension it also lists itself on steam's server list
## (NetSteamServer), so people find it in the m menu or steam's server browser. without it (or with
## --no-steam) it's a direct-ip / lan server.
##
## flags (after the `--`):
##   --name <text>      server name on the list            --map <house|forest|docks|trail|arena|city|desert|mountain|res://..>
##   --port <udp>       game port (24680)                  --query-port <udp>  steam query port (27016)
##   --max <n>          max cats (16)                      --motd <text>       shown to players when they join
##   --token <gslt>     steam game server login token (keeps the same server id across restarts)
##   --no-steam         don't touch steam at all

const MAPS := {
	"house": "res://main.tscn", "forest": "res://forest.tscn", "docks": "res://stealth.tscn",
	"trail": "res://trail.tscn", "arena": "res://arena.tscn", "city": "res://city.tscn",
	"desert": "res://desert.tscn", "mountain": "res://mountain.tscn",
}

var server_name := "cat server"
var map := "res://main.tscn"
var motd := ""
var port := NetEnetTransport.PORT
var query_port := 27016
var max_cats := 16
var token := ""
var use_steam := true
var proto := 1

var enet: NetEnetTransport
var steam: NetSteamServer
var players := {}          # id -> {name, style, scene, since}
var _report_t := 0.0
var _started := 0.0


static func label(path: String) -> String:
	for k in MAPS:
		if MAPS[k] == path:
			return "the " + k
	return path.get_file().get_basename()


static func wanted(args: PackedStringArray) -> bool:
	return "--server" in args or "--dedicated" in args or OS.has_feature("dedicated_server")


func configure(args: PackedStringArray) -> void:
	var get_arg := func(flag: String, dflt: String) -> String:
		var i := args.find(flag)
		return args[i + 1] if i >= 0 and i + 1 < args.size() else dflt
	server_name = get_arg.call("--name", server_name).left(63)
	motd = get_arg.call("--motd", motd).left(200)
	port = int(get_arg.call("--port", str(port)))
	query_port = int(get_arg.call("--query-port", str(query_port)))
	max_cats = clampi(int(get_arg.call("--max", str(max_cats))), 1, 64)
	token = get_arg.call("--token", OS.get_environment("CATGAME_GSLT"))
	use_steam = not "--no-steam" in args
	var m: String = get_arg.call("--map", "house")
	map = MAPS.get(m, m if m.begins_with("res://") else "res://main.tscn")
	if not ResourceLoader.exists(map):
		push_warning("server: no map %s, using the house" % m)
		map = "res://main.tscn"


func start() -> bool:
	_started = Time.get_ticks_msec() / 1000.0
	enet = NetEnetTransport.new()
	enet.name = "Enet"
	enet.hosting = true
	enet.dedicated = true
	enet.port = port
	enet.max_clients = max_cats
	add_child(enet)
	if not enet.start():
		_log("couldn't open udp port %d (already in use?)" % port)
		return false
	enet.packet.connect(_on_packet)
	enet.peer_joined.connect(_on_joined)
	enet.peer_left.connect(_on_left)
	_log("\"%s\" up on udp %d, map %s, up to %d cats" % [server_name, port, NetDedicatedServer.label(map), max_cats])
	if use_steam:
		steam = NetSteamServer.new()
		steam.name = "SteamServer"
		steam.game_port = port
		steam.query_port = query_port
		steam.server_name = server_name
		steam.map_name = NetDedicatedServer.label(map)
		steam.max_cats = max_cats
		steam.token = token
		steam.proto = proto
		steam.version = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
		add_child(steam)
		steam.status.connect(_log)
		if not steam.start():
			_log(steam.why)
			steam.queue_free()
			steam = null
	else:
		_log("--no-steam: direct ip / lan only")
	return true


func _process(dt: float) -> void:
	if enet:
		enet.poll()
	if steam:
		steam.poll()
	_report_t += dt
	if _report_t > 300.0:
		_report_t = 0.0
		_log("%d cat%s online" % [players.size(), "" if players.size() == 1 else "s"])


func _info_bytes() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(CatNetState.T_INFO)
	b.put_u8(proto)
	b.put_utf8_string(server_name)
	b.put_utf8_string(map)
	b.put_utf8_string(motd)
	b.put_u16(max_cats)
	return b.data_array


static func read_info(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	b.seek(1)
	var out := {"proto": b.get_u8(), "name": b.get_utf8_string(), "map": b.get_utf8_string(), "motd": b.get_utf8_string()}
	out["max"] = b.get_u16()
	return out


func _on_joined(id: int) -> void:
	players[id] = {"name": "cat %d" % (id % 1000), "style": "", "scene": "", "since": Time.get_ticks_msec()}
	enet.send(id, _info_bytes(), true)
	if steam:
		steam.player_joined(id, players[id].name)
	_log("someone connected (%d online)" % players.size())


func _on_left(id: int) -> void:
	var p = players.get(id)
	players.erase(id)
	if steam:
		steam.player_left(id)
	_log("%s left (%d online)" % [p.name if p else "someone", players.size()])


func _on_packet(from: int, data: PackedByteArray) -> void:
	# only messages addressed to the server land here; cats' snapshots just get forwarded
	if data.is_empty() or not players.has(from):
		return
	if data[0] == CatNetState.T_HELLO:
		var b := StreamPeerBuffer.new()
		b.data_array = data
		b.seek(1)
		var their_proto := b.get_u8()
		var p: Dictionary = players[from]
		var first: bool = p.style == ""
		var nm := b.get_utf8_string().strip_edges().left(32)
		if nm != "":
			p.name = nm
		p.style = b.get_utf8_string()
		p.scene = b.get_utf8_string()
		if steam:
			steam.player_named(from, p.name)
		if first:
			_log("%s joined%s" % [p.name, "" if their_proto == proto else " (different game version!)"])


func close() -> void:
	if enet:
		var bye := PackedByteArray([CatNetState.T_BYE])
		for id in enet.members():
			enet.send(id, bye, true)
		enet.poll()
		enet.close()
	if steam:
		steam.close()


func _log(t: String) -> void:
	print("[server %s] %s" % [Time.get_time_string_from_system(), t])
