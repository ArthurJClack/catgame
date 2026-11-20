class_name Level
extends RefCounted
## procedural "living room parkour gym" at real household scale (meters),
## plus a gait reference studio off to the side.

const WALL_H := 2.6
const C_FLOOR := Color(0.62, 0.43, 0.28)
const C_WALL := Color(0.86, 0.82, 0.74)
const C_WALL2 := Color(0.55, 0.66, 0.68)
const C_WOOD := Color(0.48, 0.32, 0.2)
const C_WOOD_L := Color(0.72, 0.56, 0.38)
const C_COUCH := Color(0.32, 0.42, 0.55)
const C_CUSHION := Color(0.38, 0.5, 0.64)
const C_COUNTER := Color(0.92, 0.92, 0.9)
const C_CAB := Color(0.42, 0.55, 0.47)
const C_FRIDGE := Color(0.88, 0.9, 0.92)
const C_CARDBOARD := Color(0.74, 0.57, 0.36)
const C_RUG := Color(0.7, 0.32, 0.28)


# static geometry is merged into a few big meshes (one draw call per 12 m cell)
# instead of thousands of little MeshInstances. matters a lot for the web build
static var _batch_root: Node3D
static var _batch := {}


static func _emit_box(xf: Transform3D, color: Color) -> void:
	var cell := Vector2i(floori(xf.origin.x / 12.0), floori(xf.origin.z / 12.0))
	if not _batch.has(cell):
		_batch[cell] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
	var b: Array = _batch[cell]
	var src: Array = LowPoly.box().surface_get_arrays(0)
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var sc: PackedColorArray = src[Mesh.ARRAY_COLOR]
	var nb := xf.basis.inverse().transposed()
	var vv: PackedVector3Array = b[0]
	var nn: PackedVector3Array = b[1]
	var cc: PackedColorArray = b[2]
	for i in sv.size():
		vv.append(xf * sv[i])
		nn.append((nb * sn[i]).normalized())
		var j: float = sc[i].r
		cc.append(Color(color.r * j, color.g * j, color.b * j))
	b[0] = vv
	b[1] = nn
	b[2] = cc


static func _flush() -> void:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	for cell in _batch:
		var b: Array = _batch[cell]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b[0]
		arr[Mesh.ARRAY_NORMAL] = b[1]
		arr[Mesh.ARRAY_COLOR] = b[2]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = m
		mi.name = "Batch_%d_%d" % [cell.x, cell.y]
		_batch_root.add_child(mi)
	_batch.clear()
	_batch_root = null


static func box(parent: Node, center: Vector3, size: Vector3, color: Color, collide := true, emission := 0.0, show := true) -> Node3D:
	var node: Node3D
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		node = sb
	else:
		node = Node3D.new()
	node.position = center
	parent.add_child(node)
	if not show:
		return node
	if parent == _batch_root and emission == 0.0:
		_emit_box(Transform3D(Basis.from_scale(size), center), color)
	else:
		LowPoly.part(node, LowPoly.box(), color, Vector3.ZERO, size, Vector3.ZERO, emission)
	return node


## rotated box (roofs, leaning boards). rot in radians, euler xyz
static func rbox(parent: Node, center: Vector3, size: Vector3, rot: Vector3, color: Color, collide := true) -> Node3D:
	var b := Basis.from_euler(rot)
	var node: Node3D
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		node = sb
	else:
		node = Node3D.new()
	node.transform = Transform3D(b, center)
	parent.add_child(node)
	if parent == _batch_root:
		_emit_box(Transform3D(b * Basis.from_scale(size), center), color)
	else:
		LowPoly.part(node, LowPoly.box(), color, Vector3.ZERO, size)
	return node


## box given by min corner + size (easier for furniture)
static func bx(parent: Node, minc: Vector3, size: Vector3, color: Color, collide := true) -> Node3D:
	return box(parent, minc + size * 0.5, size, color, collide)


static func table(parent: Node, center_xz: Vector2, size: Vector3, top_col: Color, leg_col: Color) -> void:
	var t := 0.04
	box(parent, Vector3(center_xz.x, size.y - t * 0.5, center_xz.y), Vector3(size.x, t, size.z), top_col)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var p := Vector3(center_xz.x + sx * (size.x * 0.5 - 0.05), (size.y - t) * 0.5, center_xz.y + sz * (size.z * 0.5 - 0.05))
			box(parent, p, Vector3(0.045, size.y - t, 0.045), leg_col)


static func sisal_post(parent: Node, pos: Vector3, h: float) -> void:
	box(parent, pos + Vector3(0, 0.02, 0), Vector3(0.42, 0.04, 0.42), Color(0.82, 0.78, 0.72))
	var post := box(parent, pos + Vector3(0, 0.04 + h * 0.5, 0), Vector3(0.1, h, 0.1), Color(0.78, 0.66, 0.46))
	post.add_to_group("climbable")
	post.add_to_group("scratchable")
	# rope wraps: alternating bands so it reads as sisal
	var n := int(h / 0.035)
	for k in n:
		var y := 0.06 + k * 0.035
		LowPoly.part(post, LowPoly.box(0.02), Color(0.86, 0.74, 0.52) if k % 2 == 0 else Color(0.72, 0.6, 0.4), Vector3(0, y - h * 0.5 - 0.02, 0), Vector3(0.106, 0.018, 0.106))
	box(parent, pos + Vector3(0, 0.04 + h + 0.02, 0), Vector3(0.26, 0.04, 0.26), Color(0.82, 0.78, 0.72))
	box(parent, pos + Vector3(0, 0.04 + h + 0.05, 0), Vector3(0.22, 0.02, 0.22), Color(0.55, 0.62, 0.75), false)


static func mug(parent: Node, pos: Vector3, color: Color) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = 0.3
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.04
	cy.height = 0.1
	cs.shape = cy
	rb.add_child(cs)
	rb.position = pos + Vector3(0, 0.05, 0)
	parent.add_child(rb)
	LowPoly.part(rb, LowPoly.cyl(0.04, 0.036, 8), color, Vector3.ZERO, Vector3(1, 0.1, 1))
	LowPoly.part(rb, LowPoly.cyl(0.033, 0.033, 8), Color(0.25, 0.15, 0.08), Vector3(0, 0.047, 0), Vector3(1, 0.008, 1))
	var handle := LowPoly.part(rb, LowPoly.box(), color, Vector3(0.048, 0, 0), Vector3(0.012, 0.06, 0.012))
	handle.rotation.z = 0.0
	return rb


static func build(root: Node3D) -> Dictionary:
	var lv := Node3D.new()
	lv.name = "Level"
	root.add_child(lv)
	_batch_root = lv
	_batch.clear()

	# ---- room shell: 10 x 8 m, 2.6 m ceiling ----
	box(lv, Vector3(0, -0.0485, 0), Vector3(10.4, 0.1, 8.4), C_FLOOR, true, 0.0, false).set_meta("surface", "wood") # collision only, planks are the visuals
	_planks(lv)
	box(lv, Vector3(0, WALL_H + 0.05, 0), Vector3(10.4, 0.1, 8.4), Color(0.95, 0.94, 0.9))
	box(lv, Vector3(0, WALL_H * 0.5, -4.1), Vector3(10.4, WALL_H, 0.2), C_WALL)
	# south wall has an open patio door out to the yard (x 1.8..2.8)
	bx(lv, Vector3(-5.2, 0, 4.0), Vector3(7.0, WALL_H, 0.2), C_WALL)
	bx(lv, Vector3(2.8, 0, 4.0), Vector3(2.4, WALL_H, 0.2), C_WALL)
	bx(lv, Vector3(1.8, 2.1, 4.0), Vector3(1.0, WALL_H - 2.1, 0.2), C_WALL)
	bx(lv, Vector3(1.8, 0, 4.0), Vector3(1.0, 0.03, 0.22), Color(0.95, 0.95, 0.93))  # threshold
	# east wall has a doorway into the bedroom wing (z -0.6..0.4)
	bx(lv, Vector3(5.0, 0, -4.2), Vector3(0.2, WALL_H, 3.6), C_WALL2)
	bx(lv, Vector3(5.0, 0, 0.4), Vector3(0.2, WALL_H, 3.8), C_WALL2)
	bx(lv, Vector3(5.0, 2.1, -0.6), Vector3(0.2, WALL_H - 2.1, 1.0), C_WALL2)
	# left wall has a big window (sunlight streams in)
	var wz0 := -1.3
	var wz1 := 1.3
	var wy0 := 0.9
	var wy1 := 2.15
	box(lv, Vector3(-5.1, WALL_H * 0.5, (-4.2 + wz0) * 0.5), Vector3(0.2, WALL_H, wz0 + 4.2), C_WALL2)
	box(lv, Vector3(-5.1, WALL_H * 0.5, (4.2 + wz1) * 0.5), Vector3(0.2, WALL_H, 4.2 - wz1), C_WALL2)
	box(lv, Vector3(-5.1, wy0 * 0.5, 0), Vector3(0.2, wy0, wz1 - wz0), C_WALL2)
	box(lv, Vector3(-5.1, (wy1 + WALL_H) * 0.5, 0), Vector3(0.2, WALL_H - wy1, wz1 - wz0), C_WALL2)
	# window sill (a classic cat spot)
	box(lv, Vector3(-4.9, wy0 - 0.02, 0), Vector3(0.32, 0.04, wz1 - wz0 + 0.2), Color(0.95, 0.95, 0.93))
	# baseboards
	box(lv, Vector3(0, 0.04, -3.99), Vector3(10, 0.08, 0.02), Color(0.96, 0.96, 0.95), false)
	box(lv, Vector3(-1.6, 0.04, 3.89), Vector3(6.8, 0.08, 0.02), Color(0.96, 0.96, 0.95), false)
	box(lv, Vector3(3.9, 0.04, 3.89), Vector3(2.2, 0.08, 0.02), Color(0.96, 0.96, 0.95), false)

	# rug (its own thin collider so the paws grip on it)
	box(lv, Vector3(-2.6, 0.004, 0.9), Vector3(3.0, 0.008, 2.2), C_RUG, false)
	box(lv, Vector3(-2.6, 0.0045, 0.9), Vector3(3.0, 0.009, 2.2), C_RUG, true, 0.0, false).set_meta("surface", "rug")

	# ---- couch (gap underneath: crouch to crawl under it, like a real cat) ----
	var cx := -2.6
	var cz := 2.9
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(lv, Vector3(cx + sx * 0.92, 0.1, cz + sz * 0.35), Vector3(0.06, 0.2, 0.06), C_WOOD)
	bx(lv, Vector3(cx - 1.0, 0.2, cz - 0.45), Vector3(2.0, 0.2, 0.9), C_COUCH)          # base, top 0.40
	bx(lv, Vector3(cx - 0.85, 0.4, cz - 0.45), Vector3(0.84, 0.08, 0.66), C_CUSHION)     # seat cushions, top 0.48
	bx(lv, Vector3(cx + 0.01, 0.4, cz - 0.45), Vector3(0.84, 0.08, 0.66), C_CUSHION)
	bx(lv, Vector3(cx - 1.0, 0.4, cz + 0.21), Vector3(2.0, 0.48, 0.24), C_COUCH)          # back, top 0.88
	bx(lv, Vector3(cx - 1.0, 0.4, cz - 0.45), Vector3(0.15, 0.22, 0.66), C_COUCH)         # arms, top 0.62
	bx(lv, Vector3(cx + 0.85, 0.4, cz - 0.45), Vector3(0.15, 0.22, 0.66), C_COUCH)

	# coffee table 0.42 m
	table(lv, Vector2(-2.6, 1.0), Vector3(1.1, 0.42, 0.6), C_WOOD_L, C_WOOD)

	# ---- dining table 0.75 m + chairs 0.46 m ----
	table(lv, Vector2(1.6, 0.6), Vector3(1.6, 0.75, 0.9), C_WOOD_L, C_WOOD)
	for p in [Vector2(1.1, -0.2), Vector2(2.1, -0.2), Vector2(1.1, 1.4), Vector2(2.1, 1.4)]:
		var back_z := -0.2 if p.y < 0.6 else 0.2
		table(lv, p, Vector3(0.42, 0.46, 0.42), C_WOOD, C_WOOD)
		box(lv, Vector3(p.x, 0.46 + 0.25, p.y + back_z), Vector3(0.42, 0.5, 0.03), C_WOOD)

	# ---- kitchen: counter 0.92 m, upper cabinets 1.5-2.2 m, fridge 1.85 m ----
	bx(lv, Vector3(0.4, 0, -4.0), Vector3(3.6, 0.88, 0.6), C_CAB)
	bx(lv, Vector3(0.38, 0.88, -4.02), Vector3(3.64, 0.04, 0.64), C_COUNTER)              # top 0.92
	bx(lv, Vector3(0.4, 1.5, -4.0), Vector3(3.6, 0.7, 0.35), C_CAB)                        # upper cabs top 2.2
	bx(lv, Vector3(4.05, 0, -4.0), Vector3(0.8, 1.85, 0.7), C_FRIDGE)                     # fridge
	# fridge -> cabinet top gap is a jump

	# ---- bookshelf with open shelves (cats love these) ----
	var bxp := -4.95
	bx(lv, Vector3(bxp, 0, -3.3), Vector3(0.36, 2.0, 0.04), C_WOOD)
	bx(lv, Vector3(bxp, 0, -2.04), Vector3(0.36, 2.0, 0.04), C_WOOD)
	for y in [0.0, 0.45, 0.9, 1.35, 1.8]:
		bx(lv, Vector3(bxp, y, -3.26), Vector3(0.36, 0.04, 1.22), C_WOOD_L)
	bx(lv, Vector3(bxp, 1.96, -3.3), Vector3(0.36, 0.04, 1.3), C_WOOD)

	# ---- cat tree ----
	var tx := -0.6
	var tz := -2.6
	box(lv, Vector3(tx, 0.03, tz), Vector3(0.6, 0.06, 0.6), Color(0.8, 0.76, 0.7))
	var tpost := box(lv, Vector3(tx, 0.8, tz), Vector3(0.11, 1.6, 0.11), Color(0.82, 0.72, 0.56))
	tpost.add_to_group("climbable")
	tpost.add_to_group("scratchable")
	box(lv, Vector3(tx + 0.18, 0.52, tz), Vector3(0.42, 0.05, 0.42), Color(0.8, 0.76, 0.7))
	box(lv, Vector3(tx - 0.16, 1.05, tz + 0.05), Vector3(0.4, 0.05, 0.4), Color(0.8, 0.76, 0.7))
	box(lv, Vector3(tx + 0.1, 1.6, tz - 0.05), Vector3(0.46, 0.05, 0.46), Color(0.8, 0.76, 0.7))

	# ---- tall sisal scratching post with a perch (climb it, scratch it) ----
	sisal_post(lv, Vector3(0.35, 0, 2.7), 1.15)
	# ---- couch is scratchable (obviously) ----
	for c in lv.get_children():
		if c is StaticBody3D and (c as Node3D).position.distance_to(Vector3(cx, 0.4, cz)) < 1.3:
			c.add_to_group("scratchable")

	# ---- wall kick chimney + high shelf reward ----
	# two panels 0.55 m apart sticking out of the right wall. kick between them.
	var ch_z0 := 1.6
	var ch_gap := 0.55
	box(lv, Vector3(4.65, 1.1, ch_z0 - 0.03), Vector3(0.7, 2.2, 0.06), C_WOOD)
	box(lv, Vector3(4.65, 1.1, ch_z0 + ch_gap + 0.03), Vector3(0.7, 2.2, 0.06), C_WOOD)
	bx(lv, Vector3(4.6, 2.16, ch_z0 + ch_gap + 0.06), Vector3(0.4, 0.04, 1.6), C_WOOD_L)  # high shelf, top 2.2
	# glowing fish treat on the high shelf (future puzzle goal)
	var fish := Node3D.new()
	fish.position = Vector3(4.8, 2.27, 3.2)
	lv.add_child(fish)
	LowPoly.part(fish, LowPoly.sphere(6, 4), Color(1.0, 0.65, 0.25), Vector3.ZERO, Vector3(0.05, 0.04, 0.11), Vector3.ZERO, 0.8)
	LowPoly.part(fish, LowPoly.cone(3), Color(1.0, 0.65, 0.25), Vector3(0, 0, 0.07), Vector3(0.05, 0.04, 0.03), Vector3(PI / 2, 0, 0), 0.8)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.7, 0.35)
	glow.light_energy = 0.6
	glow.omni_range = 0.8
	fish.add_child(glow)

	# ---- cardboard boxes by the door (stairs for cats) ----
	bx(lv, Vector3(3.2, 0, 3.3), Vector3(0.5, 0.4, 0.5), C_CARDBOARD)
	bx(lv, Vector3(3.75, 0, 3.4), Vector3(0.45, 0.75, 0.45), C_CARDBOARD.darkened(0.08))
	bx(lv, Vector3(3.3, 0.4, 3.35), Vector3(0.36, 0.3, 0.36), C_CARDBOARD.lightened(0.06))

	# ---- props you can swat off things ----
	mug(lv, Vector3(1.3, 0.75, 0.5), Color(0.9, 0.3, 0.25))
	mug(lv, Vector3(1.9, 0.75, 0.75), Color(0.25, 0.55, 0.85))
	mug(lv, Vector3(-3.0, 0.42, 1.12), Color(0.95, 0.85, 0.3))
	mug(lv, Vector3(1.0, 0.92, -3.75), Color(0.3, 0.75, 0.45))
	mug(lv, Vector3(2.2, 0.92, -3.8), Color(0.95, 0.95, 0.95))
	mug(lv, Vector3(-4.9, 0.9, 0.5), Color(0.6, 0.4, 0.8))

	# a wind up toy mouse to hunt
	var tm := ToyMouse.new()
	tm.position = Vector3(-1.6, 0.02, 0.2)
	lv.add_child(tm)

	# curtains you can climb (invisible colliders around the cloth strips)
	for z in [-1.62, 1.62]:
		var cc := box(lv, Vector3(-4.88, 1.2, z), Vector3(0.12, 2.3, 0.38), Color.WHITE, true, 0.0, false)
		cc.add_to_group("climbable")
		cc.add_to_group("scratchable")

	_dress(lv)
	World.build(lv)
	_flush()
	_build_studio(root)

	return {
		"spawn": Vector3(-1.0, 0.02, 1.2),
		"forest_gate": Vector3(-15.2, 0.02, 12.25),
		"hub_spawns": Hub.spawns(),
		"studio_x": 40.0,
	}


## muybridge style gait reference studio: long runway + black backdrop with a white grid
static func _build_studio(root: Node3D) -> void:
	var st := Node3D.new()
	st.name = "Studio"
	root.add_child(st)
	box(st, Vector3(40, -0.05, 0), Vector3(4, 0.1, 120), Color(0.46, 0.45, 0.43))
	var wall := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 3)
	pm.orientation = PlaneMesh.FACE_X
	wall.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = vec2(wp.z, wp.y) / 0.05;
	vec2 f = abs(fract(g) - 0.5);
	float minor = step(0.44, max(f.x, f.y));
	vec2 g2 = vec2(wp.z, wp.y) / 0.25;
	vec2 f2 = abs(fract(g2) - 0.5);
	float major = step(0.47, max(f2.x, f2.y));
	vec3 c = vec3(0.07, 0.07, 0.08);
	c = mix(c, vec3(0.32), minor * 0.6);
	c = mix(c, vec3(0.9), major);
	ALBEDO = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	wall.material_override = m
	wall.position = Vector3(38.6, 1.5, 0)
	st.add_child(wall)


## wooden floor: staggered planks with slightly different tones
static func _planks(lv: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var w := 0.16
	var z := -4.2
	while z < 4.2:
		var x := -5.2 - rng.randf_range(0.0, 1.2)
		while x < 5.2:
			var l := rng.randf_range(0.9, 2.0)
			var x0 := maxf(x, -5.2)
			var x1 := minf(x + l, 5.2)
			if x1 - x0 > 0.05:
				var tone := rng.randf_range(-0.07, 0.07)
				var c := Color(C_FLOOR.r + tone, C_FLOOR.g + tone * 0.8, C_FLOOR.b + tone * 0.6)
				box(lv, Vector3((x0 + x1) * 0.5, -0.0025, z + w * 0.5), Vector3(x1 - x0 - 0.006, 0.008, w - 0.006), c, false)
			x += l
		z += w
	# dark gaps between planks
	box(lv, Vector3(0, -0.0075, 0), Vector3(10.4, 0.004, 8.4), C_FLOOR.darkened(0.45), false)


static func plant(parent: Node3D, pos: Vector3, h: float) -> void:
	box(parent, pos + Vector3(0, 0.12, 0), Vector3(0.24, 0.24, 0.24), Color(0.75, 0.42, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 100 + pos.z * 10)
	for i in 7:
		var a := i * TAU / 7.0 + rng.randf() * 0.4
		var leaf := LowPoly.part(parent, LowPoly.cone(4), Color(0.25, 0.5, 0.25).lightened(rng.randf() * 0.2), pos + Vector3(cos(a) * 0.07, 0.24 + h * 0.4, sin(a) * 0.07), Vector3(0.09, h, 0.03))
		leaf.rotation = Vector3(sin(a) * 0.5, -a, -cos(a) * 0.5)


static func frame(parent: Node3D, center: Vector3, size: Vector2, art: Color, normal_x := 0.0) -> void:
	var depth := Vector3(0.03, size.y, size.x) if normal_x != 0.0 else Vector3(size.x, size.y, 0.03)
	box(parent, center, depth, Color(0.2, 0.16, 0.12), false)
	var inner := depth - Vector3(0, 0.06, 0.06) if normal_x != 0.0 else depth - Vector3(0.06, 0.06, 0)
	var off := Vector3(normal_x * 0.008, 0, 0) if normal_x != 0.0 else Vector3(0, 0, 0.008)
	box(parent, center + off, inner, art, false)
	# a little abstract "painting"
	var blob := inner * Vector3(1, 0.35, 0.5) if normal_x != 0.0 else inner * Vector3(0.5, 0.35, 1)
	box(parent, center + off * 1.6 + Vector3(0, -inner.y * 0.15, 0), blob, art.darkened(0.35).lerp(Color(0.9, 0.7, 0.3), 0.3), false)


## set dressing: makes the room read as a lived in home at cat scale
static func _dress(lv: Node3D) -> void:
	# rug border
	box(lv, Vector3(-2.6, 0.005, 0.9), Vector3(2.7, 0.009, 1.9), Color(0.85, 0.75, 0.55), false)
	box(lv, Vector3(-2.6, 0.006, 0.9), Vector3(2.5, 0.009, 1.7), C_RUG.darkened(0.1), false)
	# window frame + mullions + curtains
	var wx := -4.98
	box(lv, Vector3(wx, 1.525, 0), Vector3(0.06, 0.04, 2.6), Color(0.95, 0.95, 0.93), false)
	box(lv, Vector3(wx, 1.525, 0), Vector3(0.06, 1.25, 0.04), Color(0.95, 0.95, 0.93), false)
	for z in [-1.3, 1.3]:
		box(lv, Vector3(wx, 1.525, z), Vector3(0.08, 1.33, 0.06), Color(0.95, 0.95, 0.93), false)
	for z in [-1.62, 1.62]:
		for k in 4:
			box(lv, Vector3(-4.9, 1.2, z + (k - 1.5) * 0.09), Vector3(0.05 + (k % 2) * 0.03, 2.3, 0.09), Color(0.85, 0.55, 0.35).darkened(k % 2 * 0.1), false)
	box(lv, Vector3(-4.88, 2.38, 0), Vector3(0.03, 0.03, 4.0), Color(0.3, 0.25, 0.2), false)
	# books on the shelves
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in [0.04, 0.49, 0.94, 1.39]:
		var z := -3.24
		while z < -2.1:
			var t := rng.randf_range(0.025, 0.05)
			var h := rng.randf_range(0.2, 0.34)
			if rng.randf() < 0.82:
				var c := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.6), rng.randf_range(0.4, 0.8))
				box(lv, Vector3(-4.86, y + h * 0.5, z + t * 0.5), Vector3(0.22, h, t), c, false)
			z += t + 0.003
			if rng.randf() < 0.08:
				z += 0.2
	# pictures
	frame(lv, Vector3(-2.6, 1.55, 3.98), Vector2(1.0, 0.7), Color(0.55, 0.7, 0.8))
	frame(lv, Vector3(1.0, 1.6, 3.98), Vector2(0.5, 0.65), Color(0.8, 0.6, 0.5))
	frame(lv, Vector3(4.98, 1.5, -1.2), Vector2(0.8, 0.6), Color(0.6, 0.75, 0.55), -1.0)
	# plants
	plant(lv, Vector3(-4.6, 0, 3.6), 0.5)
	plant(lv, Vector3(4.5, 0, -2.6), 0.6)
	plant(lv, Vector3(-4.85, 0.92, -0.9), 0.25)
	# floor lamp by the couch
	box(lv, Vector3(-4.0, 0.02, 3.5), Vector3(0.3, 0.04, 0.3), Color(0.15, 0.15, 0.15))
	box(lv, Vector3(-4.0, 0.8, 3.5), Vector3(0.03, 1.56, 0.03), Color(0.15, 0.15, 0.15))
	LowPoly.part(lv, LowPoly.cyl(0.12, 0.2, 8), Color(0.98, 0.92, 0.78), Vector3(-4.0, 1.62, 3.5), Vector3(1, 0.25, 1), Vector3.ZERO, 0.5)
	var ll := OmniLight3D.new()
	ll.position = Vector3(-4.0, 1.55, 3.5)
	ll.light_color = Color(1.0, 0.78, 0.5)
	ll.light_energy = 1.2
	ll.omni_range = 3.0
	lv.add_child(ll)
	# ceiling light fixture
	LowPoly.part(lv, LowPoly.sphere(10, 6), Color(1.0, 0.95, 0.85), Vector3(0, 2.52, 0), Vector3(0.4, 0.14, 0.4), Vector3.ZERO, 1.2)
	# cat bed + food bowls
	LowPoly.part(lv, LowPoly.cyl(0.3, 0.27, 12), Color(0.55, 0.35, 0.5), Vector3(-0.2, 0.06, 3.5), Vector3(1, 0.12, 1))
	LowPoly.part(lv, LowPoly.cyl(0.24, 0.24, 12), Color(0.9, 0.85, 0.8), Vector3(-0.2, 0.1, 3.5), Vector3(1, 0.06, 1))
	for i in 2:
		LowPoly.part(lv, LowPoly.cyl(0.07, 0.055, 10), Color(0.3, 0.6, 0.75) if i == 0 else Color(0.85, 0.4, 0.35), Vector3(2.0 + i * 0.2, 0.025, -3.4), Vector3(1, 0.05, 1))
	# fruit bowl on the dining table
	LowPoly.part(lv, LowPoly.cyl(0.13, 0.08, 10), Color(0.92, 0.92, 0.9), Vector3(1.6, 0.79, 0.65), Vector3(1, 0.08, 1))
	for k in 4:
		var a := k * TAU / 4.0
		LowPoly.part(lv, LowPoly.sphere(6, 4), [Color(0.9, 0.3, 0.2), Color(0.95, 0.75, 0.2), Color(0.5, 0.75, 0.25), Color(0.95, 0.5, 0.15)][k], Vector3(1.6 + cos(a) * 0.05, 0.85, 0.65 + sin(a) * 0.05), Vector3.ONE * 0.075)
	# kitchen details: backsplash, sink, kettle
	box(lv, Vector3(2.2, 1.2, -3.99), Vector3(3.6, 0.55, 0.02), Color(0.82, 0.88, 0.88), false)
	box(lv, Vector3(1.4, 0.925, -3.75), Vector3(0.5, 0.012, 0.35), Color(0.7, 0.72, 0.75), false)
	LowPoly.part(lv, LowPoly.cyl(0.06, 0.075, 8), Color(0.2, 0.2, 0.22), Vector3(3.2, 1.0, -3.75), Vector3(1, 0.16, 1))
