class_name RemoteCat
extends Node3D
## another player's cat. the same CatRig the local player has, driven by that player's
## snapshots instead of a controller, so the spine, paws, tail, ears, sits and landings come
## out of the same solver with the same inputs. remote_life is on: it never rolls its own
## dice for glances / blinks / ear flicks / tail twitches, it replays the owner's.

var peer: NetPeer
var rig: CatRig
var style := ""
var tag: Label3D
var _carry_key := ""
var _carry_node: Node3D
var _started := false


func _ready() -> void:
	add_to_group("spar_cat")   # lock on to it and it's a play fight (cat_spar.gd)
	tag = Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.0011
	tag.font_size = 36
	tag.outline_size = 10
	tag.modulate = Color(1, 1, 1, 0.92)
	tag.no_depth_test = false
	tag.fixed_size = false
	add_child(tag)
	_build_rig()


func _build_rig() -> void:
	if rig:
		rig.queue_free()
	style = peer.style if peer else "block_black"
	rig = CatRig.new()
	if CatRig.STYLES.has(style):
		rig.style = style
	rig.remote_life = true
	rig.auto_listen = false
	rig.set("_blink_t", 1e9)
	add_child(rig)
	# paws must never land on the local player's capsule (it isn't there for the owner)
	for p in get_tree().get_nodes_in_group("player"):
		if p is CollisionObject3D:
			rig.gait.exclude.append((p as CollisionObject3D).get_rid())
	_started = false


func _process(dt: float) -> void:
	# runs before the rig's own _process (parents first), so the rig animates this frame's inputs
	if peer == null:
		return
	if peer.style != style:
		_build_rig()
	var rt := peer.render_time()
	var s := peer.sample(rt)
	if s == null:
		rig.visible = false
		tag.visible = false
		return
	rig.visible = true
	_started = true
	global_position = s.xf.origin   # the node follows the cat (lock on / pounce aim duck type it)
	s.apply(rig, dt)
	for ev in peer.due_events(rt):
		if str(ev[0]) == "S":
			CatSpar.net_in(self, ev)   # play fight strike / result / round, meant for one cat
		else:
			rig.apply_life(ev)
	# name tag floats over the head, fades out with distance
	tag.text = peer.name
	tag.global_position = rig.global_position + Vector3.UP * 0.42
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(tag.global_position) if cam else 0.0
	tag.visible = d < 18.0
	tag.modulate.a = clampf((18.0 - d) / 6.0, 0.0, 0.92)
	_update_carry(s.carry)


## prey in the mouth: a look-alike of the same kind of critter, with its brain switched off
func _update_carry(key: String) -> void:
	if key != _carry_key:
		_carry_key = key
		if is_instance_valid(_carry_node):
			_carry_node.get_parent().queue_free()
		_carry_node = null
		if key != "":
			_carry_node = _make_prop(key)
	if is_instance_valid(_carry_node) and rig.head:
		var hx := rig.head.global_transform
		_carry_node.global_transform = Transform3D(hx.basis.orthonormalized() * Basis(Vector3.UP, PI * 0.5), hx * Vector3(0, -0.035, -0.07))


func _make_prop(key: String) -> Node3D:
	var parts := key.split("|")
	var path := parts[0]
	if not path.begins_with("res://") or not ResourceLoader.exists(path):
		return null
	var scr = load(path)
	if not (scr is GDScript):
		return null
	var n = (scr as GDScript).new()
	if not (n is Node3D):
		if n is Node:
			n.free()
		return null
	if parts.size() > 1 and parts[1] != "" and "kind" in n:
		n.set("kind", parts[1])
	var holder := Node3D.new()
	holder.process_mode = Node.PROCESS_MODE_DISABLED   # no ai, no physics
	add_child(holder)
	holder.add_child(n)
	# it's only a picture of prey: nothing may hunt it, bump into it or hear it
	for g in n.get_groups():
		n.remove_from_group(g)
	if n is CollisionObject3D:
		(n as CollisionObject3D).collision_layer = 0
		(n as CollisionObject3D).collision_mask = 0
	if n is RigidBody3D:
		(n as RigidBody3D).freeze = true
	if "caught" in n:
		n.set("caught", true)
	n.top_level = true
	return n
