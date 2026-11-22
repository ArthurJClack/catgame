class_name NetWorld
extends Node
## online: everyone in the same level sees the same world (Net.world, a child of Net).
##
## the levels are built from fixed seeds, so the static stuff already matches. what drifts apart
## is everything that moves: props you knock over, prey, rats, wildlife, the village cats, the
## puzzle animals, the time of day. each of those gets ONE owner who simulates it and streams
## its state (T_WORLD, ~15 Hz, only what moved); everyone else shows a puppet of it.
##
## who owns what:
##   - props (rigid bodies): whoever touched it last (a swat, a bump, claws, a carry) claims it.
##     untouched ones belong to the level's authority (Net.authority_here)
##   - anything alive (rats, mice, wildlife, npc cats, puzzle animals): the player whose cat is
##     nearest, so its brain reacts to a real cat with no lag. a catch / grab claims it for as long
##     as it's held. a rat's hp, stagger and bites go with it when it changes hands
##   - hits on a rat you don't own are sent to its owner (forward), who applies them
##   - level state (rat pit wave, time of day) comes from the authority. a solved puzzle counts for
##     everyone in the level
##
## entities are matched across games by a key that comes out the same in every game: its kind +
## its order in the scene tree (levels build in the same order), or an explicit "net_key" meta
## (the pit's rats: wave + slot). test: tests/world_sync_test.gd (two games over lan)

const T_WORLD := 15
const SUB_STATE := 0
const SUB_CLAIM := 1
const SUB_HIT := 2
const SUB_SOLVED := 3
const SUB_LEVEL := 4
const SUB_OWNERS := 5

const SEND_HZ := 15.0
const FULL_EVERY := 2.0        # s: unchanged entities still go out this often (late joiners, loss)
const MAX_PACKET := 1100
const NEAR_HYST := 1.5         # m: another cat has to be this much nearer to take over a critter
const LEASE := 2.5             # s a claim holds before "nearest cat" can move a critter on
const SMOOTH := 14.0           # 1/s: puppets ease toward the latest state

var entities := {}             # key hash -> Ent
var _scene: Node = null
var _scan_t := 0.0
var _send_acc := 0.0
var _full_acc := 0.0
var _atmos: Array = []
var _owners_acc := 0.0
var active := false
var sent_states := 0           # tests
var got_states := 0
var forwarded := 0


class Ent:
	var key := ""
	var h := 0
	var node: Node3D
	var kind := ""             # rb, mouse, rat, critter, npc, custom
	var owner := 0             # peer id simulating it (0 = nobody decided yet)
	var lease_t := 0.0         # claim time left
	var puppet := false
	var saved_freeze := false
	var last_sent := Transform3D()
	var last_sent_x := ""      # extra state, as text, to spot changes
	var tgt := Transform3D()
	var tgt_v := Vector3.ZERO
	var has_tgt := false
	var x := {}                # latest extra state from the owner
	var heard := 0.0           # local clock when the owner last sent


func _ready() -> void:
	process_priority = 100     # after the critters / npc cats think: puppets get the owner's pose


## kind of a node we keep in step, or ""
static func kind_of(n: Node) -> String:
	if n is SoulsRat:
		return "rat"
	if n is FieldMouse or n is ToyMouse:
		return "mouse"
	if n is Critter:
		return "critter"
	if n is NpcCat:
		return "npc"
	if n.has_method("net_pack") and n.has_method("net_apply") and n is Node3D:
		return "custom"
	if n is RigidBody3D:
		return "rb"
	return ""


# ---------------------------------------------------------------- static hooks (no-ops offline)

static func _w() -> NetWorld:
	var ml := Engine.get_main_loop() as SceneTree
	var net = ml.root.get_node_or_null("Net") if ml else null
	var w = net.get("world") if net else null
	return w if w is NetWorld and (w as NetWorld).active else null


## my cat touched this (swat, bump, claws, carry): I simulate it from now on.
## rats aren't taken by a swat (hits go to their owner, forward()), only by holding them (hold())
static func touch(n: Object) -> void:
	var w := _w()
	if w and n is Node3D and not n is SoulsRat:
		w._claim(n)


## pinned under my paws: mine while I hold it, whatever it is
static func hold(n: Object) -> void:
	var w := _w()
	if w and n is Node3D:
		w._claim(n)


## a hit on something someone else simulates: send it to them. true = sent (skip it locally)
static func forward(n: Object, method: String, args: Array) -> bool:
	var w := _w()
	return w != null and n is Node and w._forward(n, method, args)


## somebody solved a puzzle: tell the level (they get the credit too)
static func solved(id: String) -> void:
	var w := _w()
	if w:
		w._send_solved(id)


## level scripts (the pit) ask this before running their own wave clock
static func level_puppet() -> bool:
	var w := _w()
	return w != null and not w._is_authority()


# ---------------------------------------------------------------- tick

func _net() -> Node:
	return get_parent()


func _here_ids() -> Array:
	# me + everyone whose cat is in this level
	var out := [_net().my_id()]
	for id in _net().peers:
		var p: NetPeer = _net().peers[id]
		if p.hello_seen and p.scene == _net()._scene_path():
			out.append(id)
	return out


func _is_authority() -> bool:
	return _net().authority_here() == _net().my_id()


func _process(dt: float) -> void:
	var net := _net()
	var cs := get_tree().current_scene
	var others := net.transport != null and _here_ids().size() > 1 and net.server == null
	if cs != _scene:
		_scene = cs
		_reset()
	if not others:
		if active:
			_go_offline()
		return
	if not active:
		active = true
		_scan()
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 1.0
		_scan()
	_decide_owners(dt)
	_ease(dt)
	_send_acc += dt
	_full_acc += dt
	if _send_acc >= 1.0 / SEND_HZ:
		_send_acc = 0.0
		var full := _full_acc >= FULL_EVERY
		if full:
			_full_acc = 0.0
		_send_states(full)


func _reset() -> void:
	entities.clear()
	_atmos.clear()
	active = false


## the last other cat left: everything goes back to running locally
func _go_offline() -> void:
	for h in entities:
		var e: Ent = entities[h]
		if is_instance_valid(e.node) and e.puppet:
			_unpuppet(e)
	entities.clear()
	active = false


func _scan() -> void:
	if _scene == null:
		return
	var seen := {}
	var counts := {}
	var stack: Array = [_scene]
	_atmos.clear()
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is CatPlayer or n is RemoteCat:
			continue           # cats sync themselves (and a remote cat's mouthful is only a picture)
		if n is Atmos:
			_atmos.append(n)
		var k := kind_of(n)
		if k != "":
			var key := ""
			if n.has_meta("net_key"):
				key = "%s:%s" % [k, n.get_meta("net_key")]
			else:
				var c := int(counts.get(k, 0))
				counts[k] = c + 1
				key = "%s#%d" % [k, c]
			var h := hash(key)
			seen[h] = true
			var e: Ent = entities.get(h)
			if e == null or not is_instance_valid(e.node) or e.node != n:
				e = Ent.new()
				e.key = key
				e.h = h
				e.node = n
				e.kind = k
				e.owner = 0
				entities[h] = e
		if k == "" or k == "custom":
			stack.append_array(n.get_children())
	for h in entities.keys():
		if not seen.has(h):
			entities.erase(h)


# ---------------------------------------------------------------- ownership

func _cat_pos(id: int) -> Variant:
	var net := _net()
	if id == net.my_id():
		var p = net.get("_player")
		return (p as Node3D).global_position if is_instance_valid(p) and p.is_inside_tree() else null
	var pr: NetPeer = net.peers.get(id)
	if pr and is_instance_valid(pr.cat) and pr.cat.rig and (pr.cat as RemoteCat).rig.visible:
		return (pr.cat as RemoteCat).rig.global_position
	return null


func _decide_owners(dt: float) -> void:
	var ids := _here_ids()
	var auth: int = _net().authority_here()
	var me: int = _net().my_id()
	var am_auth := auth == me
	var pos := {}
	for id in ids:
		var p = _cat_pos(id)
		if p != null:
			pos[id] = p
	for h in entities:
		var e: Ent = entities[h]
		if not is_instance_valid(e.node):
			continue
		var want := e.owner
		if not want in ids:
			want = 0
		if e.lease_t > 0.0:
			e.lease_t -= dt
		var held := _held(e)
		if held and e.owner == me:
			e.lease_t = LEASE
		if not am_auth:
			# only the authority hands things out (SUB_OWNERS). until it says, a thing whose owner
			# left goes to the authority
			if want == 0:
				_set_owner(e, auth)
			continue
		if e.kind == "rb":
			if want == 0:
				want = auth
		elif want == 0 or (e.lease_t <= 0.0 and pos.has(want)):
			# alive things: nearest cat, with some stickiness so it doesn't flip every frame. a
			# near tie goes to the lower id so every game picks the same one. (an owner whose cat
			# we can't see this frame keeps it)
			var at: Vector3 = e.node.global_position
			var best := want
			var best_d: float = at.distance_to(pos[want]) - NEAR_HYST if pos.has(want) else INF
			for id in pos:
				var d: float = at.distance_to(pos[id])
				if d < best_d - 0.3 or (absf(d - best_d) <= 0.3 and (best == 0 or id < best)):
					best_d = d
					best = id
			want = best if best != 0 else auth
		_set_owner(e, want)
	if am_auth:
		_owners_acc += dt
		if _owners_acc >= 0.4:
			_owners_acc = 0.0
			_send_owners()


## authority -> everyone: who runs what (a claim in flight on the other end wins until it lands)
func _send_owners() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(T_WORLD)
	b.put_u8(SUB_OWNERS)
	var n := 0
	var body := StreamPeerBuffer.new()
	for h in entities:
		var e: Ent = entities[h]
		body.put_u32(e.h)
		body.put_u32(e.owner)
		n += 1
	b.put_u32(n)
	b.put_data(body.data_array)
	_send_all(b.data_array, false)


func _held(e: Ent) -> bool:
	var n := e.node
	if "caught" in n and n.get("caught"):
		return true
	if e.kind == "rat" and n.get("held_by") != null:
		return true
	return false


func _set_owner(e: Ent, id: int) -> void:
	if id == e.owner and e.puppet == (id != _net().my_id()):
		return
	e.owner = id
	if id == _net().my_id():
		if e.puppet:
			_unpuppet(e)
	elif not e.puppet:
		_puppetize(e)


func _claim(n: Node3D) -> void:
	for h in entities:
		var e: Ent = entities[h]
		if e.node == n:
			e.lease_t = LEASE
			if e.owner != _net().my_id():
				_set_owner(e, _net().my_id())
				var b := StreamPeerBuffer.new()
				b.put_u8(T_WORLD)
				b.put_u8(SUB_CLAIM)
				b.put_u32(e.h)
				_send_all(b.data_array, true)
			return


func _puppetize(e: Ent) -> void:
	e.puppet = true
	e.has_tgt = false
	var n := e.node
	match e.kind:
		"rb", "mouse":
			var rb := n as RigidBody3D
			e.saved_freeze = rb.freeze
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			rb.freeze = true
		"rat":
			n.set_physics_process(false)


func _unpuppet(e: Ent) -> void:
	e.puppet = false
	var n := e.node
	match e.kind:
		"rb", "mouse":
			var rb := n as RigidBody3D
			var caught: bool = n.get("caught") == true
			rb.freeze = e.saved_freeze or caught
			if not rb.freeze:
				rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				rb.linear_velocity = e.tgt_v
				rb.sleeping = false
		"rat":
			n.set_physics_process(true)
			if "velocity" in n:
				n.set("velocity", e.tgt_v)


# ---------------------------------------------------------------- puppets

func _ease(dt: float) -> void:
	var k := 1.0 - exp(-SMOOTH * dt)
	for h in entities:
		var e: Ent = entities[h]
		if not e.puppet or not e.has_tgt or not is_instance_valid(e.node):
			continue
		var n := e.node
		# coast along the last velocity a little (packets are ~70 ms apart)
		var age := minf(NetPeer.now() - e.heard, 0.25)
		var to := e.tgt.origin + e.tgt_v * age
		var gx := n.global_transform
		var far := gx.origin.distance_to(to) > 2.5
		var nb: Basis = gx.basis.orthonormalized().slerp(e.tgt.basis.orthonormalized(), 1.0 if far else k)
		var np := to if far else gx.origin.lerp(to, k)
		match e.kind:
			"rb", "mouse":
				n.global_transform = Transform3D(nb, np)
			"rat":
				n.global_position = np
				n.set("yaw", lerp_angle(float(n.get("yaw")), float(e.x.get("yaw", 0.0)), 1.0 if far else k))
				n.rotation.y = float(n.get("yaw"))
				_apply_x(e)
			"critter", "npc":
				n.global_position = np
				n.set("yaw", lerp_angle(float(n.get("yaw")), float(e.x.get("yaw", 0.0)), 1.0 if far else k))
				n.rotation.y = float(n.get("yaw"))
				_apply_x(e)
				if e.kind == "critter" and n.get("solid"):
					var so: Node3D = n.get("solid")
					so.global_transform = Transform3D(Basis(Vector3.UP, float(n.get("yaw"))), n.global_position)
			"custom":
				n.call("net_apply", e.x)


const X_KEYS := {
	"rat": ["state", "st_t", "hp", "_speed", "_yaw_rate", "_poise", "yaw"],
	"critter": ["state", "state_t", "speed", "caught", "yaw"],
	"npc": ["state", "state_t", "speed", "yaw"],
	"mouse": ["caught"],
}


func _apply_x(e: Ent) -> void:
	var n := e.node
	for k in e.x:
		if k == "yaw" or not k in n:
			continue
		if e.kind == "rat" and k == "state" and int(e.x[k]) == SoulsRat.DEAD and n.get("state") != SoulsRat.DEAD:
			n.call("_die")   # the owner killed it: same death here (counts for the pit)
			continue
		n.set(k, e.x[k])


func _pack_x(e: Ent) -> Dictionary:
	var n := e.node
	if e.kind == "custom":
		return n.call("net_pack")
	var d := {}
	for k in X_KEYS.get(e.kind, []):
		if k in n:
			var v = n.get(k)
			d[k] = snappedf(v, 0.01) if v is float else v
	return d


# ---------------------------------------------------------------- send

func _send_states(full: bool) -> void:
	var me: int = _net().my_id()
	var hdr := StreamPeerBuffer.new()
	hdr.put_u8(T_WORLD)
	hdr.put_u8(SUB_STATE)
	var level := {}
	if _is_authority():
		for a in _atmos:
			if is_instance_valid(a) and "hour" in a:
				level["hour"] = snappedf(float(a.get("hour")), 0.001)
				break
		if _scene and _scene.has_method("net_level_pack"):
			level.merge(_scene.call("net_level_pack"))
	hdr.put_var(level)
	var chunk := StreamPeerBuffer.new()
	var n := 0
	for h in entities:
		var e: Ent = entities[h]
		if e.owner != me or not is_instance_valid(e.node):
			continue
		var gx := e.node.global_transform
		var xd := _pack_x(e)
		var xs := var_to_str(xd)
		var moved := gx.origin.distance_squared_to(e.last_sent.origin) > 0.0001 or not gx.basis.is_equal_approx(e.last_sent.basis)
		if not (full or moved or xs != e.last_sent_x):
			continue
		e.last_sent = gx
		e.last_sent_x = xs
		var v := Vector3.ZERO
		if e.node is RigidBody3D:
			v = (e.node as RigidBody3D).linear_velocity
		elif "velocity" in e.node and e.node.get("velocity") is Vector3:
			v = e.node.get("velocity")
		chunk.put_u32(e.h)
		_put_v3(chunk, gx.origin)
		var q := gx.basis.orthonormalized().get_rotation_quaternion()
		chunk.put_float(q.x)
		chunk.put_float(q.y)
		chunk.put_float(q.z)
		chunk.put_float(q.w)
		_put_v3(chunk, v)
		chunk.put_var(xd)
		n += 1
		if chunk.get_size() > MAX_PACKET:
			_flush(hdr, chunk, n)
			chunk = StreamPeerBuffer.new()
			n = 0
			hdr = _hdr_only()
	if n > 0 or not level.is_empty():
		_flush(hdr, chunk, n)


func _hdr_only() -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.put_u8(T_WORLD)
	b.put_u8(SUB_STATE)
	b.put_var({})
	return b


func _flush(hdr: StreamPeerBuffer, chunk: StreamPeerBuffer, n: int) -> void:
	var b := StreamPeerBuffer.new()
	b.put_data(hdr.data_array)
	b.put_u16(n)
	b.put_data(chunk.data_array)
	sent_states += n
	_send_all(b.data_array, false)


func _send_all(bytes: PackedByteArray, reliable: bool) -> void:
	var net := _net()
	for id in _here_ids():
		if id != net.my_id():
			net.transport.send(id, bytes, reliable)


static func _put_v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _get_v3(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_float(), b.get_float(), b.get_float())


func _forward(n: Node, method: String, args: Array) -> bool:
	for h in entities:
		var e: Ent = entities[h]
		if e.node == n:
			if not e.puppet or e.owner == 0:
				return false
			var b := StreamPeerBuffer.new()
			b.put_u8(T_WORLD)
			b.put_u8(SUB_HIT)
			b.put_u32(e.h)
			b.put_utf8_string(method)
			b.put_var(args)
			_net().transport.send(e.owner, b.data_array, true)
			forwarded += 1
			return true
	return false


func _send_solved(id: String) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(T_WORLD)
	b.put_u8(SUB_SOLVED)
	b.put_utf8_string(id)
	b.put_utf8_string(_net().my_name)
	_send_all(b.data_array, true)


# ---------------------------------------------------------------- receive

const HIT_OK := ["take_hit", "stun", "pin_hit"]


func on_packet(from: int, data: PackedByteArray) -> void:
	if not active or data.size() < 2:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	b.seek(2)
	match data[1]:
		SUB_STATE:
			var level = b.get_var()
			if level is Dictionary and not level.is_empty() and from == _net().authority_here():
				_apply_level(level)
			var n := b.get_u16()
			for i in n:
				var h := b.get_u32()
				var o := _get_v3(b)
				var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
				var v := _get_v3(b)
				var xd = b.get_var()
				var e: Ent = entities.get(h)
				if e == null or not is_instance_valid(e.node):
					continue
				if e.owner != from:
					continue     # stale: the owners list will sort it out
				got_states += 1
				e.tgt = Transform3D(Basis(q.normalized()), o)
				e.tgt_v = v
				e.x = xd if xd is Dictionary else {}
				e.heard = NetPeer.now()
				if not e.has_tgt:
					e.has_tgt = true
					e.node.global_transform = Transform3D(e.node.global_transform.basis, o)
		SUB_CLAIM:
			var e: Ent = entities.get(b.get_u32())
			if e:
				if e.owner == _net().my_id() and e.lease_t > 0.0 and _held(e):
					return   # it's in my paws / mouth: mine (the owners list tells them)
				e.lease_t = LEASE
				_set_owner(e, from)
		SUB_OWNERS:
			if from != _net().authority_here():
				return
			var n := b.get_u32()
			var me: int = _net().my_id()
			for i in n:
				var e: Ent = entities.get(b.get_u32())
				var o := b.get_u32()
				if e == null or not is_instance_valid(e.node):
					continue
				if e.owner == me and e.lease_t > 0.0 and o != me:
					continue     # my claim hasn't reached them yet
				_set_owner(e, o)
		SUB_HIT:
			var e: Ent = entities.get(b.get_u32())
			var method := b.get_utf8_string()
			var args = b.get_var()
			if e and is_instance_valid(e.node) and not e.puppet and method in HIT_OK and args is Array and e.node.has_method(method):
				e.node.callv(method, args)
		SUB_SOLVED:
			var id := b.get_utf8_string()
			var who := b.get_utf8_string()
			if int(Puzzles.solved.get(id, 0)) > 0:
				return     # had it already
			Puzzles.solved[id] = 1
			var p = _net().get("_player")
			if is_instance_valid(p) and p.has_method("_event"):
				p.call("_event", "%s solved a puzzle (it counts for you too)" % who)


func _apply_level(d: Dictionary) -> void:
	if d.has("hour"):
		for a in _atmos:
			if is_instance_valid(a) and "hour" in a:
				var cur := float(a.get("hour"))
				var want := float(d.hour)
				# small drift: ease it, big gap (just joined): jump
				var diff := fposmod(want - cur + 12.0, 24.0) - 12.0
				a.set("hour", want if absf(diff) > 0.25 else fposmod(cur + diff * 0.2, 24.0))
	if _scene and _scene.has_method("net_level_apply"):
		_scene.call("net_level_apply", d)
