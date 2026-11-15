class_name NetSteamTransport
extends Node
## steam lobbies + steam networking messages (p2p, relayed through valve's network so nobody has
## to open ports). needs the GodotSteam GDExtension (addons/godotsteam, ci downloads it) and the
## steam client running. everything goes through Engine.get_singleton("Steam") so this script
## still loads when the extension isn't there (editor without the addon, web build): it just
## reports that steam isn't available.
##
## app id: STEAM_APP_ID = 480 is valve's public test app ("Spacewar"). it's fine for testing
## with friends, but every dev on earth shares it, so lobbies are tagged with LOBBY_TAG and the
## browser only lists those. for a real release: steamworks partner account + the $100 app fee
## gets you your own app id, put it here and drop steam_appid.txt from the build.

signal packet(from_id: int, data: PackedByteArray)
signal peer_joined(id: int)
signal peer_left(id: int)
signal lobbies_listed(list: Array)   # [{id, name, cats, max, host}]
signal lobby_changed                  # joined / left / members changed
signal status(text: String)

const STEAM_APP_ID := 480
const LOBBY_TAG := "catgame"
const MAX_CATS := 8
const CH_RELIABLE := 0
const CH_FAST := 1
# k_nSteamNetworkingSend_*: unreliable 0, no nagle 1, reliable 8, auto restart broken session 32
const SEND_UNRELIABLE := 1 | 32
const SEND_RELIABLE := 8 | 32
# ELobbyType / ELobbyComparison / ELobbyDistanceFilter / EChatMemberStateChange
const LOBBY_FRIENDS := 1
const LOBBY_PUBLIC := 2
const CMP_EQUAL := 0
const DIST_WORLDWIDE := 3
const CHAT_ENTERED := 1

var steam: Object = null
var proto := 1          # Net.PROTO, set by Net (kept off the autoload so tests can load this alone)
var ready_ok := false
var why := "steam isn't set up in this build"
var my_id := 0
var my_name := ""
var lobby_id := 0
var lobby_owner := 0
var _members: Array = []
var _id_style := ""     # how this GodotSteam version names a peer in messages: "int" / "identity"


func start() -> bool:
	if not Engine.has_singleton("Steam"):
		why = "steam isn't in this build (GodotSteam addon missing)"
		return false
	steam = Engine.get_singleton("Steam")
	# no steam_appid.txt next to the game (or running from the editor): tell the api which app
	OS.set_environment("SteamAppId", str(STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(STEAM_APP_ID))
	var r = _call("steamInitEx", [])
	var ok := false
	if r is Dictionary:
		ok = int(r.get("status", 1)) == 0
		if not ok:
			why = "steam didn't start: %s" % str(r.get("verbal", r))
	elif r is bool:
		ok = r
	if not ok and steam.has_method("isSteamRunning") and not steam.isSteamRunning():
		why = "open steam (and log in) first, then restart the game"
	if not ok:
		return false
	ready_ok = true
	my_id = int(steam.getSteamID())
	my_name = str(steam.getPersonaName())
	_call("initRelayNetworkAccess", [])
	_hook("lobby_created", _on_lobby_created)
	_hook("lobby_joined", _on_lobby_joined)
	_hook("lobby_match_list", _on_lobby_match_list)
	_hook("lobby_chat_update", _on_lobby_chat_update)
	_hook("join_requested", _on_join_requested)
	_hook("network_messages_session_request", _on_session_request)
	_hook("network_messages_session_failed", _on_session_failed)
	_hook("persona_state_change", _on_persona)
	_id_style = _detect_id_style()
	# started from an invite while the game was closed: steam passes +connect_lobby <id>
	var args := OS.get_cmdline_args()
	var ci := args.find("+connect_lobby")
	if ci >= 0 and ci + 1 < args.size() and args[ci + 1].is_valid_int():
		join_lobby.call_deferred(int(args[ci + 1]))
	return true


func kind() -> String:
	return "steam"


func members() -> Array:
	return _members.filter(func(i): return i != my_id)


func display_name(id: int) -> String:
	if not ready_ok:
		return "cat"
	return str(steam.getFriendPersonaName(id))


func in_lobby() -> bool:
	return lobby_id != 0


# ------------------------------------------------------------------ lobbies

func host(public := false) -> void:
	if not ready_ok:
		return
	if lobby_id != 0:
		leave_lobby()
	status.emit("making a lobby...")
	_call("createLobby", [LOBBY_PUBLIC if public else LOBBY_FRIENDS, MAX_CATS])


func refresh() -> void:
	if not ready_ok:
		return
	status.emit("looking for lobbies...")
	_call("addRequestLobbyListStringFilter", ["game", LOBBY_TAG, CMP_EQUAL])
	_call("addRequestLobbyListDistanceFilter", [DIST_WORLDWIDE])
	_call("addRequestLobbyListResultCountFilter", [50])
	_call("requestLobbyList", [])


func join_lobby(id: int) -> void:
	if not ready_ok or id == 0 or id == lobby_id:
		return
	if lobby_id != 0:
		leave_lobby()
	status.emit("joining...")
	_call("joinLobby", [id])


func leave_lobby() -> void:
	if lobby_id == 0:
		return
	for m in members():
		peer_left.emit(m)
		_call("closeSessionWithUser", [_peer_arg(m)])
	_call("leaveLobby", [lobby_id])
	lobby_id = 0
	lobby_owner = 0
	_members = []
	lobby_changed.emit()
	status.emit("left the lobby")


func invite_friends() -> void:
	if lobby_id != 0:
		_call("activateGameOverlayInviteDialog", [lobby_id])


func lobby_name() -> String:
	return str(_call("getLobbyData", [lobby_id, "name"])) if lobby_id != 0 else ""


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:   # k_EResultOK
		status.emit("couldn't make a lobby (steam error %d)" % result)
		return
	lobby_id = id
	_call("setLobbyJoinable", [id, true])
	_call("setLobbyData", [id, "game", LOBBY_TAG])
	_call("setLobbyData", [id, "name", "%s's cats" % my_name])
	_call("setLobbyData", [id, "proto", str(proto)])
	status.emit("lobby up. invite friends or let them find it")
	# lobby_joined fires for the creator too, which fills in the members


func _on_lobby_joined(id: int, _perm: int = 0, _locked: bool = false, response: int = 1) -> void:
	if response != 1:   # k_EChatRoomEnterResponseSuccess
		status.emit("couldn't join that lobby (%s)" % _join_error(response))
		return
	lobby_id = id
	_refresh_members()
	status.emit("in %s" % lobby_name())
	var theirs := str(_call("getLobbyData", [id, "proto"]))
	if theirs != "" and theirs != str(proto):
		status.emit("heads up: that lobby runs a different game version, update both games")


func _on_lobby_match_list(lobbies: Array) -> void:
	var out := []
	for l in lobbies:
		var id := int(l)
		out.append({
			"id": id,
			"name": str(_call("getLobbyData", [id, "name"])),
			"cats": int(_call("getNumLobbyMembers", [id])),
			"max": int(_call("getLobbyMemberLimit", [id])),
		})
	status.emit("%d lobb%s found" % [out.size(), "y" if out.size() == 1 else "ies"])
	lobbies_listed.emit(out)


func _on_lobby_chat_update(id: int, _changed: int = 0, _by: int = 0, _state: int = 0) -> void:
	if id == lobby_id:
		_refresh_members()


func _on_join_requested(id: int, _friend: int = 0) -> void:
	# accepted an invite (or "join game" on a friend) while already playing
	join_lobby(id)


func _refresh_members() -> void:
	var old := _members.duplicate()
	_members = []
	var n := int(_call("getNumLobbyMembers", [lobby_id]))
	for i in n:
		_members.append(int(_call("getLobbyMemberByIndex", [lobby_id, i])))
	lobby_owner = int(_call("getLobbyOwner", [lobby_id]))
	for m in _members:
		if m != my_id and not m in old:
			peer_joined.emit(m)
	for m in old:
		if m != my_id and not m in _members:
			peer_left.emit(m)
			_call("closeSessionWithUser", [_peer_arg(m)])
	lobby_changed.emit()


func _join_error(r: int) -> String:
	match r:
		2: return "it doesn't exist any more"
		3: return "not allowed"
		4: return "it's full"
		5: return "error"
		6: return "banned"
		7: return "limited account"
		9: return "blocked"
	return "code %d" % r


# ------------------------------------------------------------------ packets

func send(to: int, data: PackedByteArray, reliable: bool) -> void:
	if not ready_ok or not to in _members:
		return
	_call("sendMessageToUser", [_peer_arg(to), data, SEND_RELIABLE if reliable else SEND_UNRELIABLE, CH_RELIABLE if reliable else CH_FAST])


func poll() -> void:
	if not ready_ok:
		return
	steam.run_callbacks()
	for ch in [CH_RELIABLE, CH_FAST]:
		var msgs = _call("receiveMessagesOnChannel", [ch, 64])
		if not (msgs is Array):
			continue
		for m in msgs:
			if not (m is Dictionary):
				continue
			var from := _sender_of(m)
			var data = m.get("payload", PackedByteArray())
			if data is String:
				data = (data as String).to_utf8_buffer()
			if from != 0 and from in _members and data is PackedByteArray:
				packet.emit(from, data)


func _on_session_request(who) -> void:
	var id := _as_id(who)
	# only people in our lobby get a session
	if id in _members:
		_call("acceptSessionWithUser", [_peer_arg(id)])


func _on_persona(_a = null, _b = null) -> void:
	lobby_changed.emit()   # a name came in


func _on_session_failed(a = null, _b = null, _c = null, _d = null) -> void:
	push_warning("net: steam session failed %s" % str(a))


func close() -> void:
	leave_lobby()


# ------------------------------------------------------------------ GodotSteam version glue
# the networking messages api took steam ids as ints in newer GodotSteam and "identity" strings
# in older ones. look at what this build wants instead of guessing

func _detect_id_style() -> String:
	for m in steam.get_method_list():
		if m.name == "sendMessageToUser" and m.args.size() > 0:
			return "identity" if int(m.args[0].type) == TYPE_STRING else "int"
	return "int"


func _peer_arg(id: int):
	if _id_style == "identity":
		var key := "steam_%d" % id
		if steam.has_method("addIdentity"):
			steam.addIdentity(key)
			if steam.has_method("setIdentitySteamID64"):
				steam.setIdentitySteamID64(key, id)
		return key
	return id


func _as_id(v) -> int:
	if v is int:
		return v
	var s := str(v)
	var digits := ""
	for ch in s:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits.length() >= 15:
			break
		else:
			digits = ""
	return int(digits) if digits.length() >= 15 else 0


func _sender_of(m: Dictionary) -> int:
	for k in ["remote_steam_id", "steam_id", "identity", "sender"]:
		if m.has(k):
			var id := _as_id(m[k])
			if id != 0:
				return id
	return 0


func _call(method: String, args: Array):
	if steam == null or not steam.has_method(method):
		return null
	return steam.callv(method, args)


func _hook(sig: String, fn: Callable) -> void:
	if steam.has_signal(sig) and not steam.is_connected(sig, fn):
		steam.connect(sig, fn)
