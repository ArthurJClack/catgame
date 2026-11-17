extends SceneTree
## ci check for the dedicated server builds (linux, no steam client): GodotSteam Server loads and has
## what NetSteamServer calls. prints every signature so a renamed call is easy to spot in the log.
## only the calls the server can't list itself without are fatal; the rest just cost a feature
## (NetSteamServer checks each one before calling it).
##   godot --headless --path . --script res://tests/steam_server_check.gd

const REQUIRED := ["run_callbacks", "logOnAnonymous", "setModDir", "setServerName", "setMaxPlayerCount"]
const ONE_OF := [["serverInitEx", "serverInit"], ["setAdvertiseServerActive", "enableHeartbeats"]]
const OPTIONAL := [
	"setProduct", "setGameDescription", "setDedicatedServer", "setPasswordProtected", "setMapName",
	"setGameTags", "setKeyValue", "logOn", "logOff", "getSteamID", "getPublicIP",
	"createUnauthenticatedUserConnection", "updateUserData", "sendUserDisconnect_DEPRECATED",
	"sendUserDisconnect", "endAuthSession", "serverShutdown", "shutdown",
]
const SIGNALS := ["server_connected", "server_connect_failure", "server_disconnected"]


func _initialize() -> void:
	if not Engine.has_singleton("SteamServer"):
		print("FAIL: SteamServer singleton missing (GodotSteam Server extension didn't load)")
		quit(1)
		return
	var s := Engine.get_singleton("SteamServer")
	var by_name := {}
	for m in s.get_method_list():
		by_name[m.name] = m
	var bad := 0
	for n in REQUIRED:
		if not _show(by_name, n):
			print("MISSING method ", n)
			bad += 1
	for group in ONE_OF:
		var any := false
		for n in group:
			any = _show(by_name, n) or any
		if not any:
			print("MISSING all of ", group)
			bad += 1
	for n in OPTIONAL:
		if not _show(by_name, n):
			print("(missing, optional) ", n)
	var sigs := {}
	for g in s.get_signal_list():
		sigs[g.name] = g
	for n in SIGNALS:
		if not sigs.has(n):
			print("(missing, optional) signal ", n)
			continue
		var args := []
		for a in sigs[n].args:
			args.append("%s:%s" % [a.name, type_string(a.type)])
		print("ok  signal %s(%s)" % [n, ", ".join(args)])
	if load("res://scripts/net/steam_server.gd") == null:
		print("FAIL: steam_server.gd doesn't load")
		bad += 1
	print("steam server check: %s" % ("PASS" if bad == 0 else "%d problems" % bad))
	quit(0 if bad == 0 else 1)


func _show(by_name: Dictionary, n: String) -> bool:
	if not by_name.has(n):
		return false
	var args := []
	for a in by_name[n].args:
		args.append("%s:%s" % [a.name, type_string(a.type)])
	print("ok  %s(%s)" % [n, ", ".join(args)])
	return true
