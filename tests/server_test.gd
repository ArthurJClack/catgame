extends SceneTree
## dedicated server check, all in one process, no steam: a NetDedicatedServer + two enet clients on
## localhost. checks the server isn't a "cat" in anyone's roster, clients get the server info, the
## server learns names from hellos, cat packets get relayed client to client, and leaving shows up.
##   godot --headless --path . --script res://tests/server_test.gd

const PORT := 24777

var srv: NetDedicatedServer
var a: NetEnetTransport
var b: NetEnetTransport
var got := {"a_info": {}, "b_info": {}, "b_from_a": 0, "a_left": false, "b_joined_a": false}
var bad := 0


func _initialize() -> void:
	_run.call_deferred()


func _client(tag: String) -> NetEnetTransport:
	var c := NetEnetTransport.new()
	c.address = "127.0.0.1"
	c.port = PORT
	root.add_child(c)
	c.packet.connect(func(from: int, data: PackedByteArray):
		if data.is_empty():
			return
		if data[0] == CatNetState.T_INFO and from == 1:
			got[tag + "_info"] = NetDedicatedServer.read_info(data)
		elif tag == "b" and data[0] == CatNetState.T_SNAP:
			got.b_from_a += 1)
	return c


func _pump(sec: float, until: Callable = func(): return false) -> void:
	var t := 0.0
	while t < sec and not until.call():
		srv.enet.poll()
		a.poll()
		if b:
			b.poll()
		await process_frame
		OS.delay_msec(5)
		t += 0.005 + 1.0 / 60.0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		bad += 1


func _run() -> void:
	srv = NetDedicatedServer.new()
	srv.configure(PackedStringArray(["--server", "--no-steam", "--port", str(PORT), "--name", "test cats", "--map", "forest", "--motd", "hi"]))
	root.add_child(srv)
	srv.set_process(false)   # we pump it ourselves
	_check(srv.start(), "server starts on udp %d" % PORT)
	a = _client("a")
	_check(a.start(), "client a starts")
	await _pump(3.0, func(): return not got.a_info.is_empty())
	_check(got.a_info.get("name") == "test cats" and got.a_info.get("map") == "res://forest.tscn" and got.a_info.get("motd") == "hi", "a got server info %s" % str(got.a_info))
	_check(a.members().is_empty(), "server isn't a member for a (%s)" % str(a.members()))
	b = _client("b")
	b.peer_joined.connect(func(id): if id == a.my_id: got.b_joined_a = true)
	b.peer_left.connect(func(id): if id == a.my_id: got.a_left = true)
	b.start()
	await _pump(3.0, func(): return got.b_joined_a and not got.b_info.is_empty())
	_check(got.b_joined_a, "b sees a join")
	_check(a.members() == [b.my_id], "a sees only b (%s)" % str(a.members()))
	_check(srv.players.size() == 2, "server counts 2 players")
	# hello to the server: name shows up on its side
	var h := StreamPeerBuffer.new()
	h.put_u8(CatNetState.T_HELLO)
	h.put_u8(srv.proto)
	h.put_utf8_string("mittens")
	h.put_utf8_string("block_black")
	h.put_utf8_string("res://forest.tscn")
	a.send(1, h.data_array, true)
	# a cat snapshot from a to b gets relayed
	for i in 10:
		a.send(b.my_id, PackedByteArray([CatNetState.T_SNAP, 1, 2, 3]), false)
	await _pump(2.0, func(): return got.b_from_a >= 5 and srv.players.get(a.my_id, {}).get("name") == "mittens")
	_check(srv.players.get(a.my_id, {}).get("name") == "mittens", "server learned a's name")
	_check(got.b_from_a >= 5, "b got a's snapshots through the server (%d/10)" % got.b_from_a)
	a.close()
	await _pump(4.0, func(): return got.a_left)
	_check(got.a_left, "b sees a leave")
	_check(srv.players.size() == 1, "server back to 1 player")
	print("server test: %s" % ("PASS" if bad == 0 else "%d problems" % bad))
	quit(0 if bad == 0 else 1)
