class_name NetSteamServer
extends Node
## puts a dedicated server on steam's server list (the steam game server api: SteamGameServer).
## the cats themselves still travel over enet on the game port (NetEnetTransport); steam is the
## phone book: name, map, players, and the address players connect to. players find it in the m
## menu's server list, or in steam's own server browser (View > Game Servers), which launches the
## game with +connect ip:port.
##
## needs the GodotSteam *Server* GDExtension (addons/godotsteam_server, a separate download from the
## normal GodotSteam: the release workflow fetches it for the server builds). it shows up as the
## "SteamServer" singleton. no steam client is needed on the server box, but on linux steam's
## steamclient.so has to be in ~/.steam/sdk64/ (steamcmd: `app_update 1007`, see the readme).
##
## every call goes through _call() and checks the method exists first: GodotSteam renamed and
## reordered a few of these between versions, and a missing one should cost a feature, not the server.

signal status(text: String)

const GAME_DIR := "catgame"     # what the server browser filters on (shared app 480, see NetSteamTransport)
# EServerMode: 1 = no auth and NOT listed, 2 = authenticate + listed (no VAC), 3 = + VAC
const SERVER_MODE_LISTED := 2

var api: Object = null
var ready_ok := false
var logged_on := false
var why := ""
var game_port := 24680
var query_port := 27016
var server_name := "cat server"
var map_name := "the house"
var max_cats := 16
var token := ""                  # game server login token (steamcommunity.com/dev/managegameservers) keeps the same server id
var version := "0.1.0"
var proto := 1
var _users := {}                 # client id -> steam id of the fake "unauthenticated" user on the server list


func start() -> bool:
	if not Engine.has_singleton("SteamServer"):
		why = "GodotSteam Server isn't in this build: running without the steam server list (direct ip still works)"
		return false
	api = Engine.get_singleton("SteamServer")
	OS.set_environment("SteamAppId", str(NetSteamTransport.STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(NetSteamTransport.STEAM_APP_ID))
	var init_name := "serverInitEx" if api.has_method("serverInitEx") else "serverInit"
	var r = _call(init_name, _init_args(init_name))
	var ok := false
	if r is Dictionary:
		ok = int(r.get("status", 1)) == 0
		if not ok:
			why = "steam game server didn't start: %s" % str(r.get("verbal", r))
	elif r is bool:
		ok = r
		if not ok:
			why = "steam game server didn't start (port %d / query %d taken? on linux: is steamclient.so in ~/.steam/sdk64?)" % [game_port, query_port]
	elif r == null:
		why = "this GodotSteam Server has no serverInit/serverInitEx"
	if not ok:
		return false
	ready_ok = true
	_hook("server_connected", _on_connected)
	_hook("server_connect_failure", _on_connect_failure)
	_hook("server_disconnected", _on_disconnected)
	_call("setModDir", [GAME_DIR])
	_call("setProduct", [GAME_DIR])
	_call("setGameDescription", ["Cat Game"])
	_call("setDedicatedServer", [true])
	_call("setMaxPlayerCount", [max_cats])
	_call("setPasswordProtected", [false])
	_call("setServerName", [server_name])
	_call("setMapName", [map_name])
	_call("setGameTags", ["%s,proto%d,port%d" % [GAME_DIR, proto, game_port]])
	_call("setKeyValue", ["proto", str(proto)])
	_call("setKeyValue", ["port", str(game_port)])
	if token != "":
		_call("logOn", [token])
	else:
		_call("logOnAnonymous", [])
	status.emit("logging on to steam as a game server...")
	return true


## serverInitEx(ip, game_port, query_port, server_mode, version_string) in GodotSteam 4.x. read the
## argument names instead of trusting the order, and give ints / strings to whatever wants them
func _init_args(method: String) -> Array:
	for m in api.get_method_list():
		if m.name != method:
			continue
		var out := []
		for a in m.args:
			var n := str(a.name).to_lower()
			var is_str := int(a.type) == TYPE_STRING
			if n.contains("query"):
				out.append(query_port)
			elif n.contains("port"):
				out.append(game_port)
			elif n.contains("ip"):
				out.append("0.0.0.0" if is_str else 0)
			elif n.contains("mode"):
				out.append(SERVER_MODE_LISTED)
			elif n.contains("version"):
				out.append(version if is_str else 1)
			else:
				out.append("" if is_str else 0)
		return out
	return []


func poll() -> void:
	if not ready_ok:
		return
	if api.has_method("run_callbacks"):
		api.run_callbacks()
	elif api.has_method("runCallbacks"):
		api.runCallbacks()


func _on_connected(_a = null) -> void:
	logged_on = true
	# newer sdk: setAdvertiseServerActive, older: enableHeartbeats
	if api.has_method("setAdvertiseServerActive"):
		_call("setAdvertiseServerActive", [true])
	else:
		_call("enableHeartbeats", [true])
	var sid = _call("getSteamID", [])
	status.emit("on the steam server list as \"%s\" (server id %s, %s)" % [server_name, str(sid), _ip_text()])


func _on_connect_failure(result = null, retrying = null) -> void:
	status.emit("couldn't log on to steam (result %s)%s" % [str(result), ", retrying" if retrying else ""])


func _on_disconnected(result = null) -> void:
	logged_on = false
	status.emit("lost steam (result %s), it'll keep trying" % str(result))


func _ip_text() -> String:
	var ip = _call("getPublicIP", [])
	if ip is Dictionary:
		ip = ip.get("ipv4", ip.get("ip", ip))
	if ip is int and ip != 0:
		return "public ip %d.%d.%d.%d:%d" % [(ip >> 24) & 255, (ip >> 16) & 255, (ip >> 8) & 255, ip & 255, game_port]
	return "game port %d, query port %d" % [game_port, query_port]


# ------------------------------------------------------------------ what the server list shows

func set_map(label: String) -> void:
	map_name = label
	_call("setMapName", [label])


## the player count on the server list comes from users the server told steam about. we don't do
## steam auth (players connect over enet), so each one gets an "unauthenticated" placeholder user
func player_joined(id: int, nm: String) -> void:
	if not ready_ok or _users.has(id):
		return
	var sid = _call("createUnauthenticatedUserConnection", [])
	if sid == null or int(sid) == 0:
		return
	_users[id] = int(sid)
	player_named(id, nm)


func player_named(id: int, nm: String) -> void:
	if _users.has(id):
		_call("updateUserData", [_users[id], nm, 0])


func player_left(id: int) -> void:
	if not _users.has(id):
		return
	var sid: int = _users[id]
	_users.erase(id)
	for m in ["sendUserDisconnect_DEPRECATED", "sendUserDisconnect", "endAuthSession"]:
		if api.has_method(m):
			_call(m, [sid])
			break


func close() -> void:
	if not ready_ok:
		return
	if api.has_method("setAdvertiseServerActive"):
		_call("setAdvertiseServerActive", [false])
	else:
		_call("enableHeartbeats", [false])
	_call("logOff", [])
	for m in ["serverShutdown", "shutdown"]:
		if api.has_method(m):
			_call(m, [])
			break
	ready_ok = false


func _call(method: String, args: Array):
	if api == null or not api.has_method(method):
		return null
	return api.callv(method, args)


func _hook(sig: String, fn: Callable) -> void:
	if api.has_signal(sig) and not api.is_connected(sig, fn):
		api.connect(sig, fn)
