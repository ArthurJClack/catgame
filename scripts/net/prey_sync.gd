class_name PreySync
extends Node
## online hunting: everyone in a level sees the same mice and rats.
##
## one game in the level is the prey authority (Net.authority_here(): the lobby host if they're
## here, else the lowest player id in the level). it runs the real prey brains and sends
## everyone a snapshot ~10 times a second; everybody else's prey are puppets that glide to it.
## a puppet the local cat catches / drops / swats goes into its mouth (or runs) right away, and a
## claim goes to the authority, which makes it official for everyone else (others see it vanish
## into that cat's mouth, the RemoteCat already shows a copy there).
##
## packet (Net type T_PREY = 14): [u8 14][u8 sub][scene path] then
##   SUB_SNAP:  [u16 n] n x [u8 state][f32 x][f32 z][u8 yaw][u8 aware]
##   SUB_CLAIM: [u16 id][u8 action][f32 x][f32 z]
## prey are matched by spawn order (HuntPrey.all), so levels must spawn them deterministically.

const T_PREY := 14
const SUB_SNAP := 0
const SUB_CLAIM := 1
const A_CATCH := 0
const A_RELEASE := 1
const A_STUN := 2
const SEND_HZ := 10.0
const HOLD := 0.6             # s a prey I just claimed ignores snapshots (until the authority heard)

static var me: PreySync

var authority := true         # tests can force this (and `forced`)
var forced := false
var sent := 0                 # snapshots sent (tests)
var applied := 0              # snapshots applied
var out: Callable             # tests: catch outgoing packets instead of the network
var _acc := 0.0
var _hold := {}               # net id -> seconds left


## one per level, made by the first prey that spawns
static func ensure(parent: Node) -> PreySync:
	if is_instance_valid(me) and me.is_inside_tree():
		return me
	me = PreySync.new()
	me.name = "PreySync"
	parent.add_child.call_deferred(me)
	return me


func _ready() -> void:
	var net := _net()
	if net and "handlers" in net:
		net.handlers[T_PREY] = _on_packet


func _exit_tree() -> void:
	var net := _net()
	if net and "handlers" in net and net.handlers.get(T_PREY) == _on_packet:
		net.handlers.erase(T_PREY)
	if me == self:
		me = null


func _net() -> Node:
	return get_node_or_null("/root/Net") if is_inside_tree() else null


func online() -> bool:
	if forced:
		return true
	var net := _net()
	return net != null and net.has_method("online") and net.online()


func _physics_process(dt: float) -> void:
	for k in _hold.keys():
		_hold[k] -= dt
		if _hold[k] <= 0.0:
			_hold.erase(k)
	if not forced:
		var net := _net()
		authority = true
		if online() and net.has_method("authority_here"):
			authority = int(net.authority_here()) == int(net.my_id())
	var puppets := online() and not authority
	for p in HuntPrey.all:
		if is_instance_valid(p):
			p.puppet = puppets
	if online() and authority:
		_acc += dt
		if _acc >= 1.0 / SEND_HZ:
			_acc = 0.0
			_send(snapshot())


func _scene() -> String:
	var cs := get_tree().current_scene if is_inside_tree() else null
	return cs.scene_file_path if cs else ""


func snapshot() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(T_PREY)
	b.put_u8(SUB_SNAP)
	b.put_utf8_string(_scene())
	b.put_u16(HuntPrey.all.size())
	for p in HuntPrey.all:
		var a: Array = p.net_pack()
		b.put_u8(int(a[0]))
		b.put_float(float(a[1]))
		b.put_float(float(a[2]))
		b.put_u8(int(round(wrapf(float(a[3]), 0.0, TAU) / TAU * 255.0)) % 256)
		b.put_u8(int(clampf(float(a[4]) / 1.6, 0.0, 1.0) * 255.0))
	sent += 1
	return b.data_array


func _send(bytes: PackedByteArray) -> void:
	if out.is_valid():
		out.call(bytes)
		return
	var net := _net()
	if net == null or net.transport == null:
		return
	for id in net.transport.members():
		net.transport.send(id, bytes, false)


## the local cat did something to a prey: tell the authority (no-op when we are it / offline)
static func claim(p: HuntPrey, action: int) -> void:
	if not is_instance_valid(me) or not me.online() or me.authority or p.net_id < 0:
		return
	me._hold[p.net_id] = HOLD
	var b := StreamPeerBuffer.new()
	b.put_u8(T_PREY)
	b.put_u8(SUB_CLAIM)
	b.put_utf8_string(me._scene())
	b.put_u16(p.net_id)
	b.put_u8(action)
	b.put_float(p.global_position.x)
	b.put_float(p.global_position.z)
	me._send(b.data_array)


func _on_packet(_from: int, data: PackedByteArray) -> void:
	receive(data)


func receive(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if b.get_u8() != T_PREY:
		return
	var sub := b.get_u8()
	if b.get_utf8_string() != _scene():
		return   # about another level's prey
	if sub == SUB_SNAP:
		if authority:
			return   # two authorities for a moment (someone joined): ours wins until it settles
		var n := b.get_u16()
		for i in n:
			var st := b.get_u8()
			var x := b.get_float()
			var z := b.get_float()
			var y := b.get_u8() / 255.0 * TAU
			var aw := b.get_u8() / 255.0 * 1.6
			if i < HuntPrey.all.size() and not _hold.has(i):
				(HuntPrey.all[i] as HuntPrey).net_apply(st, x, z, y, aw)
		applied += 1
	elif sub == SUB_CLAIM and authority:
		var id := b.get_u16()
		var act := b.get_u8()
		var x := b.get_float()
		var z := b.get_float()
		if id >= HuntPrey.all.size():
			return
		var p: HuntPrey = HuntPrey.all[id]
		if p.caught:
			return   # my own cat got there first
		match act:
			A_CATCH:
				p._go(HuntPrey.TAKEN, 0.0)
			A_RELEASE:
				p.global_position = p._on_ground(Vector3(x, p.global_position.y, z))
				p.aware = HuntPrey.FLEE_AT + 0.5
				p._bolt(true)
			A_STUN:
				if p.state != HuntPrey.TAKEN:
					p.stun(1.6)
