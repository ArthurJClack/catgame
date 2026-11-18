class_name NetEnetTransport
extends Node
## direct / lan play without steam: `CatGame.exe -- --net-host` on one pc and
## `CatGame.exe -- --net-join 192.168.1.20` on the others (udp port 24680, or --net-port).
## star shaped: the host forwards everyone's packets to everyone else, so clients only ever
## talk to the host. every packet is [u32 sender id] + payload.
##
## the same thing runs the dedicated server (NetDedicatedServer): `dedicated` = the host has no cat
## of its own, so it isn't in the roster and nobody sees a "cat 1" join. it only forwards and
## sends its own messages (server info) to clients.

signal packet(from_id: int, data: PackedByteArray)
signal peer_joined(id: int)
signal peer_left(id: int)
signal lost   # client: the connection to the host failed or dropped

const PORT := 24680
const MAX_CLIENTS := 7

var my_id := 0
var hosting := false
var dedicated := false
var max_clients := MAX_CLIENTS
var address := ""
var port := PORT
var _peer: MultiplayerPeer
var _roster: Array = []   # everyone connected, me included
var _names := {}
var _was_connected := false


func start() -> bool:
	var e = ClassDB.instantiate("ENetMultiplayerPeer")
	if e == null:
		return false
	var err: int
	if hosting:
		err = e.create_server(port, max_clients)
	else:
		err = e.create_client(address, port)
	if err != OK:
		push_warning("net: enet %s failed (%d)" % ["host" if hosting else "join", err])
		return false
	_peer = e
	_peer.peer_connected.connect(func(i): _links[i] = true)
	_peer.peer_disconnected.connect(func(i): _links.erase(i))
	if hosting:
		my_id = 1
		_roster = [] if dedicated else [1]
	return true


func kind() -> String:
	return "lan host" if hosting else "lan"


func members() -> Array:
	return _roster.filter(func(i): return i != my_id)


func display_name(id: int) -> String:
	return _names.get(id, "cat %d" % (id % 1000))


func send(to: int, data: PackedByteArray, reliable: bool) -> void:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var b := StreamPeerBuffer.new()
	b.put_u32(my_id)
	b.put_u32(to)
	b.put_data(data)
	# clients can only reach the host. the host passes it on
	_put(1 if not hosting else to, b.data_array, reliable)


func _put(target: int, bytes: PackedByteArray, reliable: bool) -> void:
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	_peer.transfer_channel = 0 if reliable else 1
	_peer.set_target_peer(target)
	_peer.put_packet(bytes)


func poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	if not hosting:
		var st := _peer.get_connection_status()
		if st == MultiplayerPeer.CONNECTION_CONNECTED and not _was_connected:
			_was_connected = true
			my_id = _peer.get_unique_id()
		elif st == MultiplayerPeer.CONNECTION_DISCONNECTED:
			if _was_connected:
				_was_connected = false
				for i in members():
					peer_left.emit(i)
				_roster = []
			_peer = null
			lost.emit()
			return
	while _peer.get_available_packet_count() > 0:
		var from_link := _peer.get_packet_peer()
		var mode := _peer.get_packet_mode()
		var raw := _peer.get_packet()
		if raw.size() < 9:
			continue
		var b := StreamPeerBuffer.new()
		b.data_array = raw
		var origin := b.get_u32()
		var to := b.get_u32()
		var body := raw.slice(8)
		if hosting:
			origin = from_link   # never trust the claimed sender
			if to != 1:
				var fw := StreamPeerBuffer.new()
				fw.put_u32(origin)
				fw.put_u32(to)
				fw.put_data(body)
				if to in _roster:
					_put(to, fw.data_array, mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE)
				continue
		elif origin == 1 and body.size() > 0 and body[0] == CatNetState.T_ROSTER:
			_read_roster(body)
			continue
		packet.emit(origin, body)
	if hosting:
		_host_roster()


var _roster_sent: Array = []
var _links := {}   # host: ids of connected clients


func _host_roster() -> void:
	# who's here: ENet tells the host about joins/leaves through peer ids it has seen
	var now_ids: Array = [] if dedicated else [1]
	for i in _links:
		now_ids.append(i)
	now_ids.sort()
	if now_ids == _roster_sent:
		return
	var old := _roster.duplicate()
	_roster = now_ids
	_roster_sent = now_ids.duplicate()
	for i in _roster:
		if not i in old:
			peer_joined.emit(i)
	for i in old:
		if not i in _roster:
			peer_left.emit(i)
	var b := StreamPeerBuffer.new()
	b.put_u8(CatNetState.T_ROSTER)
	b.put_var(_roster)
	for i in members():
		var w := StreamPeerBuffer.new()
		w.put_u32(1)
		w.put_u32(i)
		w.put_data(b.data_array)
		_put(i, w.data_array, true)


func _read_roster(body: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = body
	b.seek(1)
	var r = b.get_var(false)
	if not (r is Array):
		return
	var old := _roster.duplicate()
	_roster = r
	for i in _roster:
		if i != my_id and not i in old:
			peer_joined.emit(i)
	for i in old:
		if i != my_id and not i in _roster:
			peer_left.emit(i)


func connected() -> bool:
	return _peer != null and (hosting or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)


func close() -> void:
	if _peer:
		_peer.close()
	_peer = null
	_roster = []
