extends SceneTree
## paws must touch the ground you SEE: loads each level and checks, at a few thousand random
## spots, that the walkable collision never sits above everything drawn there (a cat standing on
## it would hover). catches heightmap / mesh triangulation mismatches, grass tiles drawn under the
## collider top, round colliders on faceted low poly logs, ...
## `xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/ground_flush_test.gd [-- res://forest.tscn ...]`
## (needs a renderer: headless can't build the level meshes)

const SCENES := ["res://main.tscn", "res://forest.tscn", "res://trail.tscn", "res://stealth.tscn"]
const TOL := 0.004          # m of collision above the drawn surface that still counts as touching
const MAX_BAD := 0.5        # % of spots allowed over TOL (odd lumpy rock hull corners etc.)
const SPOTS := 4000

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scenes: Array = Array(OS.get_cmdline_user_args()).filter(func(s): return s.begins_with("res://"))
	if scenes.is_empty():
		scenes = SCENES
	for s in scenes:
		await _check(s)
	print("GROUND FLUSH %s" % ("PASS" if fails == 0 else "FAIL (%d levels)" % fails))
	quit(1 if fails else 0)


func _check(path: String) -> void:
	var root: Node = load(path).instantiate()
	get_root().add_child(root)
	for _k in 30:
		await physics_frame
	var player = get_first_node_in_group("player")
	var center: Vector3 = player.global_position if player else Vector3.ZERO
	# a second physics world holding a trimesh of every visible static mesh
	var w := World3D.new()
	var bodies: Array[RID] = []
	var shapes: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null or _moving(mi):
			continue
		var f: PackedVector3Array = mi.mesh.get_faces()
		if f.is_empty():
			continue
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(f)
		var b := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(b, sh.get_rid())
		PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, mi.global_transform)
		PhysicsServer3D.body_set_space(b, w.space)
		bodies.append(b)
		shapes.append(sh)
	for _k in 3:
		await physics_frame
	var ps: PhysicsDirectSpaceState3D = root.get_viewport().world_3d.direct_space_state
	var vd := PhysicsServer3D.space_get_direct_state(w.space)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := 0
	var bad := 0
	var worst := 0.0
	var worst_at := Vector3.ZERO
	for _k in SPOTS:
		var x := center.x + rng.randf_range(-30, 30)
		var z := center.z + rng.randf_range(-30, 30)
		var rq := PhysicsRayQueryParameters3D.create(Vector3(x, center.y + 30, z), Vector3(x, center.y - 30, z))
		if player:
			rq.exclude = [player.get_rid()]
		var h := ps.intersect_ray(rq)
		# walkable static ground near the cat's height (skips tree tops, invisible edge walls)
		if h.is_empty() or not (h.collider is StaticBody3D) or (h.normal as Vector3).y < 0.7 or h.position.y > center.y + 2.5:
			continue
		var hy: float = h.position.y
		var v := vd.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, hy + 0.3, z), Vector3(x, hy - 0.5, z)))
		var gap: float = hy - (v.position.y if v else hy - 0.5)
		n += 1
		if gap > TOL:
			bad += 1
			if gap > worst:
				worst = gap
				worst_at = Vector3(x, hy, z)
	for b in bodies:
		PhysicsServer3D.free_rid(b)
	var pct := 100.0 * bad / maxf(n, 1)
	var ok := n > 200 and pct <= MAX_BAD
	if not ok:
		fails += 1
	print("[ground] %-20s %4d spots  collision above drawn ground: %.2f%%  worst %.0f mm at %s  %s" % [path, n, pct, worst * 1000.0, str(worst_at.snapped(Vector3.ONE * 0.1)), "ok" if ok else "FAIL"])
	root.queue_free()
	await process_frame
	await process_frame


func _moving(n: Node) -> bool:
	while n:
		if n is CatRig or n is CharacterBody3D or n is RigidBody3D:
			return true
		n = n.get_parent()
	return false
