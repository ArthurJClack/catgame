class_name NetServerBrowser
extends Node
## the m menu's server list: asks steam's matchmaking servers api for dedicated servers running
## this game (internet + lan), see NetDedicatedServer / NetSteamServer for the other side.
## uses the normal GodotSteam "Steam" singleton the lobbies use. GodotSteam's names for this api
## moved around between versions, so arguments are matched by name and the details dictionary is
## read defensively. tests/steam_check.gd prints what this build actually has.

signal servers_listed(list: Array)   # [{name, map, cats, max, ping, addr, port}]
signal status(text: String)

var steam: Object = null
var _req = null
var _lan := false
var busy := false


func setup(api: Object) -> void:
	steam = api
	for s in ["refresh_complete", "server_list_refresh_complete"]:
		if steam.has_signal(s) and not steam.is_connected(s, _on_done):
			steam.connect(s, _on_done)


func available() -> bool:
	return steam != null and steam.has_method("requestInternetServerList") and steam.has_method("getServerDetails")


func refresh(lan := false) -> void:
	if not available():
		status.emit("this steam build can't list servers, use direct join")
		return
	_release()
	_lan = lan
	busy = true
	status.emit("looking for %s servers..." % ("lan" if lan else "steam"))
	var method := "requestLANServerList" if lan else "requestInternetServerList"
	_req = steam.callv(method, _args(method, {}))
	# some versions never fire refresh_complete for an empty list
	get_tree().create_timer(6.0).timeout.connect(func(): if busy: _on_done())


func _filters(type: int):
	if type == TYPE_DICTIONARY:
		return {"gamedir": NetSteamServer.GAME_DIR}
	return [["gamedir", NetSteamServer.GAME_DIR]]


func _args(method: String, extra: Dictionary) -> Array:
	for m in steam.get_method_list():
		if m.name != method:
			continue
		var out := []
		for a in m.args:
			var n := str(a.name).to_lower()
			if n.contains("app"):
				out.append(NetSteamTransport.STEAM_APP_ID)
			elif n.contains("filter"):
				out.append(_filters(int(a.type)))
			elif n.contains("request") or n.contains("handle"):
				out.append(_req if _req != null else 0)
			elif n.contains("server") or n.contains("index"):
				out.append(extra.get("index", 0))
			else:
				out.append(0)
		return out
	return []


func _on_done(_a = null, _b = null) -> void:
	if not busy:
		return
	busy = false
	var n := 0
	if steam.has_method("getServerCount"):
		var c = steam.callv("getServerCount", _args("getServerCount", {}))
		n = int(c) if c != null else 0
	var out := []
	for i in n:
		var d = steam.callv("getServerDetails", _args("getServerDetails", {"index": i}))
		if d is Dictionary:
			var s := parse(d)
			if not s.is_empty():
				out.append(s)
	out.sort_custom(func(a, b): return a.ping < b.ping)
	status.emit("%d server%s found" % [out.size(), "" if out.size() == 1 else "s"])
	servers_listed.emit(out)


## pulls what we need out of GodotSteam's server details. {} if it isn't one of ours
static func parse(d: Dictionary) -> Dictionary:
	var gd := str(d.get("game_dir", d.get("gamedir", NetSteamServer.GAME_DIR)))
	if gd != NetSteamServer.GAME_DIR:
		return {}
	var s := {
		"name": str(_first(d, ["name", "server_name"], "cat server")),
		"map": str(_first(d, ["map", "map_name"], "")),
		"cats": int(_first(d, ["players", "player_count"], 0)),
		"max": int(_first(d, ["max_players", "max_player_count"], 0)),
		"ping": int(_first(d, ["ping"], 999)),
		"addr": "", "port": NetEnetTransport.PORT,
	}
	var tags := str(_first(d, ["tags", "game_tags"], ""))
	for t in tags.split(","):
		if t.begins_with("port") and t.substr(4).is_valid_int():
			s.port = int(t.substr(4))
	var a = _first(d, ["connection_address", "address", "ip", "ip_address", "public_ip"], null)
	if a is int and a != 0:
		s.addr = "%d.%d.%d.%d" % [(a >> 24) & 255, (a >> 16) & 255, (a >> 8) & 255, a & 255]
	elif a is String and a != "":
		var parts := (a as String).split(":")
		s.addr = parts[0]
		# the connection address's port is the game port unless the tags said otherwise
		if parts.size() > 1 and parts[1].is_valid_int() and not tags.contains("port"):
			s.port = int(parts[1])
	var p = _first(d, ["connection_port", "game_port"], null)
	if p != null and int(p) > 0 and not tags.contains("port"):
		s.port = int(p)
	return s


static func _first(d: Dictionary, keys: Array, dflt):
	for k in keys:
		if d.has(k):
			return d[k]
	return dflt


func _release() -> void:
	if _req != null and steam.has_method("releaseRequest"):
		steam.callv("releaseRequest", _args("releaseRequest", {}))
	_req = null
