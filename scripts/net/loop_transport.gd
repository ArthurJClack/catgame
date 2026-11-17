class_name NetLoopTransport
extends Node
## test transport: everything you send comes back to you as if from another player (id 2),
## after a fake network delay with jitter and packet loss. used by `-- --nettest` to check that a
## remote copy of your cat animates the same as your own.

signal packet(from_id: int, data: PackedByteArray)
signal peer_joined(id: int)
signal peer_left(id: int)

const ECHO_ID := 2

var my_id := 1
var latency := 0.06
var jitter := 0.02
var loss := 0.02
var _q: Array = []   # [deliver_at, data]
var _rng := RandomNumberGenerator.new()


func start() -> bool:
	_rng.seed = 5
	peer_joined.emit.call_deferred(ECHO_ID)
	return true


func kind() -> String:
	return "loopback"


func members() -> Array:
	return [ECHO_ID]


func display_name(_id: int) -> String:
	return "echo"


func send(_to: int, data: PackedByteArray, reliable: bool) -> void:
	if not reliable and _rng.randf() < loss:
		return
	var at := NetPeer.now() + latency + _rng.randf_range(0.0, jitter)
	if reliable:
		at = maxf(at, _q[-1][0] if not _q.is_empty() else 0.0)
	_q.append([at, data])
	_q.sort_custom(func(a, b): return a[0] < b[0])


func poll() -> void:
	var t := NetPeer.now()
	while not _q.is_empty() and _q[0][0] <= t:
		packet.emit(ECHO_ID, _q.pop_front()[1])


func close() -> void:
	_q.clear()
