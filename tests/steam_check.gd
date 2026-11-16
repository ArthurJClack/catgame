extends SceneTree
## ci check (linux, no steam client): the GodotSteam extension loads, and every Steam call the
## multiplayer code makes exists in this version. prints the signatures so a mismatch is easy to
## read in the log. exit 1 = something's missing.
##   godot --headless --path . --script res://tests/steam_check.gd

const METHODS := [
	"steamInitEx", "run_callbacks", "getSteamID", "getPersonaName", "getFriendPersonaName", "isSteamRunning",
	"initRelayNetworkAccess", "createLobby", "joinLobby", "leaveLobby", "setLobbyJoinable", "setLobbyData",
	"getLobbyData", "getNumLobbyMembers", "getLobbyMemberByIndex", "getLobbyOwner", "getLobbyMemberLimit",
	"addRequestLobbyListStringFilter", "addRequestLobbyListDistanceFilter", "addRequestLobbyListResultCountFilter",
	"requestLobbyList", "activateGameOverlayInviteDialog", "sendMessageToUser", "receiveMessagesOnChannel",
	"acceptSessionWithUser", "closeSessionWithUser",
]
const SIGNALS := [
	"lobby_created", "lobby_joined", "lobby_match_list", "lobby_chat_update", "join_requested",
	"network_messages_session_request", "network_messages_session_failed", "persona_state_change",
]


func _initialize() -> void:
	if not Engine.has_singleton("Steam"):
		print("FAIL: Steam singleton missing (GodotSteam extension didn't load)")
		quit(1)
		return
	var s := Engine.get_singleton("Steam")
	var bad := 0
	var by_name := {}
	for m in s.get_method_list():
		by_name[m.name] = m
	for n in METHODS:
		if not by_name.has(n):
			print("MISSING method ", n)
			bad += 1
			continue
		var m: Dictionary = by_name[n]
		var args := []
		for a in m.args:
			args.append("%s:%s" % [a.name, type_string(a.type)])
		print("ok  %s(%s)" % [n, ", ".join(args)])
	var sigs := {}
	for g in s.get_signal_list():
		sigs[g.name] = g
	for n in SIGNALS:
		if not sigs.has(n):
			print("MISSING signal ", n)
			bad += 1
			continue
		var args := []
		for a in sigs[n].args:
			args.append("%s:%s" % [a.name, type_string(a.type)])
		print("ok  signal %s(%s)" % [n, ", ".join(args)])
	# the transport also has to compile against it
	var t = load("res://scripts/net/steam_transport.gd")
	if t == null:
		print("FAIL: steam_transport.gd doesn't load")
		bad += 1
	print("steam check: %s" % ("PASS" if bad == 0 else "%d problems" % bad))
	quit(0 if bad == 0 else 1)
