class_name BiomeKit
extends RefCounted
## shared builders for the desert + the mountain (desert_level.gd, mountain_level.gd), in the pier 9
## psx look (psx.gd: 32 px textures, wobbly verts, affine uvs, the dithered post filter):
##   begin()    new level root + sample a height function into a 0.5 m grid
##   terrain()  textured, vertex coloured ground tiles + trimesh colliders with a surface per spot
##   slab()     climbable stone block (cliffs, mesas, ledges)        rock()  lumpy boulder w/ hull
##   pbox() / pcyl()  textured boxes + cylinders for buildings and props
## everything is built from fixed seeds, so every player online gets the exact same world.
## the wildlife lists (perches / obstacles / trunks) are ForestLevel's, so Critter + Fauna code
## (wildlife.gd, fauna.gd) works unchanged in these levels too.

const S := 0.5               # terrain grid (m)
const TILE := 16             # cells per tile edge (one mesh + one collider each)

static var lv: Node3D
static var half := 40.0
static var n := 160
static var hs := PackedFloat32Array()
static var hfn: Callable
static var sfn: Callable


static func begin(root: Node3D, name: String, half_size: float, height_fn: Callable) -> Node3D:
	ForestLevel.perches.clear()
	ForestLevel.obstacles.clear()
	ForestLevel.trunks.clear()
	ForestLevel.flowers.clear()
	lv = Node3D.new()
	lv.name = name
	root.add_child(lv)
	ForestLevel.lv = lv
	half = half_size
	n = int(half * 2.0 / S)
	hfn = height_fn
	hs.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			hs[iz * (n + 1) + ix] = float(hfn.call(ix * S - half, iz * S - half))
	return lv


## the height of the drawn + collided triangles (not the smooth function): spawns and props sit
## exactly on what the cat stands on
static func y(x: float, z: float) -> float:
	var fx := clampf((x + half) / S, 0.0, n - 0.001)
	var fz := clampf((z + half) / S, 0.0, n - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - ix
	var v := fz - iz
	var h00 := hs[iz * (n + 1) + ix]
	var h10 := hs[iz * (n + 1) + ix + 1]
	var h01 := hs[(iz + 1) * (n + 1) + ix]
	var h11 := hs[(iz + 1) * (n + 1) + ix + 1]
	# same split as the mesh: (00, 10, 11) and (00, 11, 01)
	if u >= v:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h11 - h01) * u + (h01 - h00) * v


static func at(x: float, z: float, up := 0.0) -> Vector3:
	return Vector3(x, y(x, z) + up, z)


## ground tiles. color_fn(x, z, h, slope) -> Color, surface_fn(x, z) -> footstep surface
static func terrain(color_fn: Callable, surface_fn: Callable, tex := "grain", density := 0.5) -> void:
	sfn = surface_fn
	var mat := PSX.mat(tex)
	for tz in range(0, n, TILE):
		for tx in range(0, n, TILE):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var faces := PackedVector3Array()
			for iz in range(tz, tz + TILE):
				for ix in range(tx, tx + TILE):
					var x0 := ix * S - half
					var z0 := iz * S - half
					var p00 := Vector3(x0, hs[iz * (n + 1) + ix], z0)
					var p10 := Vector3(x0 + S, hs[iz * (n + 1) + ix + 1], z0)
					var p01 := Vector3(x0, hs[(iz + 1) * (n + 1) + ix], z0 + S)
					var p11 := Vector3(x0 + S, hs[(iz + 1) * (n + 1) + ix + 1], z0 + S)
					for tri in [[p00, p10, p11], [p00, p11, p01]]:
						var a: Vector3 = tri[0]
						var b: Vector3 = tri[1]
						var c: Vector3 = tri[2]
						var nrm := (c - a).cross(b - a).normalized()
						var cen := (a + b + c) / 3.0
						var col: Color = color_fn.call(cen.x, cen.z, cen.y, 1.0 - nrm.y)
						for vv in [a, b, c]:
							# smooth (per grid point) normals: gouraud like a psx, and a low sun doesn't
							# turn every little facet black
							st.set_normal(_grid_normal(vv.x, vv.z))
							st.set_color(col)
							st.set_uv(Vector2(vv.x, vv.z) * density)
							st.add_vertex(vv)
							faces.append(vv)
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			# the psx vertex snap runs in the shadow pass too, so ground shadowing itself turns into
			# stripes. the ground only receives (slabs, rocks, props + animals still cast)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "Ground_%d_%d" % [tx, tz]
			lv.add_child(mi)
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(faces)
			cs.shape = sh
			sb.add_child(cs)
			sb.set_meta("surface_at", func(p: Vector3) -> String: return String(BiomeKit.sfn.call(p.x, p.z)))
			sb.name = "GroundBody_%d_%d" % [tx, tz]
			lv.add_child(sb)
	# invisible walls at the edge
	for sg in [-1.0, 1.0]:
		_wall(Vector3(sg * (half - 0.5), 15, 0), Vector3(0.5, 40, half * 2))
		_wall(Vector3(0, 15, sg * (half - 0.5)), Vector3(half * 2, 40, 0.5))


static func _grid_normal(x: float, z: float) -> Vector3:
	var ix := clampi(roundi((x + half) / S), 1, n - 1)
	var iz := clampi(roundi((z + half) / S), 1, n - 1)
	var dx := hs[iz * (n + 1) + ix + 1] - hs[iz * (n + 1) + ix - 1]
	var dz := hs[(iz + 1) * (n + 1) + ix] - hs[(iz - 1) * (n + 1) + ix]
	return Vector3(-dx, 2.0 * S, -dz).normalized()


static func _wall(c: Vector3, s: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	sb.add_child(cs)
	sb.position = c
	lv.add_child(sb)


## flat ring of ground past the walls so the horizon never shows the void
static func apron(col: Color, y0: float, tex := "grain") -> void:
	for sg in [-1.0, 1.0]:
		pbox(Vector3(sg * (half + 150.0 - 0.3), y0 - 0.1, 0), Vector3(300, 0.2, 700), 0.0, tex, col, false)
		pbox(Vector3(0, y0 - 0.1, sg * (half + 150.0 - 0.3)), Vector3(700, 0.2, 300), 0.0, tex, col, false)


# ------------------------------------------------------------------ props

## textured box, optional collider. surface = footstep sound / climb rule (meta "surface")
static func pbox(center: Vector3, size: Vector3, yaw: float, kind: String, tint := Color.WHITE, collide := true, surface := "", parent: Node3D = null, emission := 0.0) -> Node3D:
	var node: Node3D
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		node = sb
		if surface != "":
			sb.set_meta("surface", surface)
	else:
		node = Node3D.new()
	node.position = center
	node.rotation.y = yaw
	(parent if parent else lv).add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = PSX.box_mesh(size, 1.0, 1.2, 0.0 if size.y < 6.0 else -100.0, hash(center))
	mi.material_override = PSX.mat(kind, tint, emission)
	node.add_child(mi)
	return node


static func pcyl(center: Vector3, r: float, h: float, kind: String, tint := Color.WHITE, collide := true, segs := 8, parent: Node3D = null, rot := Vector3.ZERO) -> Node3D:
	var node: Node3D
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = h
		cs.shape = cy
		sb.add_child(cs)
		node = sb
	else:
		node = Node3D.new()
	node.position = center
	node.rotation = rot
	(parent if parent else lv).add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = PSX.cyl_mesh(r, h, segs, 2.0)
	mi.material_override = PSX.mat(kind, tint)
	node.add_child(mi)
	return node


## a block of layered stone standing on `base` (bottom centre). climbable on every face, birds and
## lizards use its top, ground animals walk round it
static func slab(base: Vector3, size: Vector3, yaw: float, tint: Color, climb := true, kind := "rock") -> StaticBody3D:
	var sb := pbox(base + Vector3(0, size.y * 0.5, 0), size, yaw, kind, tint, true, "stone") as StaticBody3D
	sb.name = "Slab"
	if climb:
		sb.add_to_group("climbable")
	ForestLevel.perches.append(base + Vector3(0, size.y, 0))
	ForestLevel.obstacles.append([Vector2(base.x, base.z), maxf(size.x, size.z) * 0.55])
	return sb


## lumpy boulder: a jittered low poly sphere with world scaled uvs and a matching hull collider
static func rock(base: Vector3, size: Vector3, yaw: float, tint: Color, seed_i: int, climb := true, sink := 0.25) -> StaticBody3D:
	var mesh := rock_mesh(size, seed_i)
	var sb := StaticBody3D.new()
	sb.name = "Rock"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_convex_shape(true, true)
	sb.add_child(cs)
	sb.position = base + Vector3(0, size.y * (0.5 - sink), 0)
	sb.rotation.y = yaw
	sb.set_meta("surface", "stone")
	if climb:
		sb.add_to_group("climbable")
	lv.add_child(sb)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = PSX.mat("rock", tint)
	sb.add_child(mi)
	ForestLevel.perches.append(sb.position + Vector3(0, size.y * 0.4, 0))   # rock_mesh flattens the top to 0.4
	ForestLevel.obstacles.append([Vector2(base.x, base.z), maxf(size.x, size.z) * 0.5])
	return sb


static var _rock_cache := {}

static func rock_mesh(size: Vector3, seed_i: int) -> ArrayMesh:
	var key := "%s_%d" % [str(size.snapped(Vector3.ONE * 0.05)), seed_i % 9]
	if _rock_cache.has(key):
		return _rock_cache[key]
	var src := SphereMesh.new()
	src.radius = 0.5
	src.height = 1.0
	src.radial_segments = 7
	src.rings = 4
	var arr := src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed_i % 9
	# jitter per position so seam duplicates move together (no cracks)
	var moved := {}
	for i in verts.size():
		var v := verts[i]
		var k := v.snapped(Vector3.ONE * 0.001)
		if not moved.has(k):
			var j := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.12, 0.12))
			var w := v * Vector3(1, 1, 1) + j
			w.y = maxf(w.y, -0.42)          # flat-ish bottom
			if w.y > 0.3:
				w.y = lerpf(w.y, 0.3, 0.5)   # flat-ish top: something to stand on
			moved[k] = w * size
		verts[i] = moved[k]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var nrm := (c - a).cross(b - a).normalized()
		if nrm.length() < 0.5:
			continue
		var sh := 0.9 + rng.randf() * 0.15
		for v in [a, b, c]:
			st.set_normal(nrm)
			st.set_color(Color(sh, sh, sh))
			# planar uv picked by the face direction: strata stay horizontal
			var uv := Vector2(v.x + v.z, v.y) if absf(nrm.y) < 0.7 else Vector2(v.x, v.z)
			st.set_uv(uv * 1.2)
			st.add_vertex(v)
	var m := st.commit()
	_rock_cache[key] = m
	return m


## a far-off shape (mesa, peak) out past the walls: no collider, fades into the fog
static func far(center: Vector3, size: Vector3, yaw: float, tint: Color, kind := "rock", cone := false) -> void:
	if cone:
		# a peak: a big faceted cone standing on `center` (its base), size = base width x height
		var mi := MeshInstance3D.new()
		mi.mesh = _peak_mesh(hash(center), tint)
		mi.material_override = PSX.mat(kind, Color.WHITE)
		mi.position = center
		mi.rotation.y = yaw
		mi.scale = size
		lv.add_child(mi)
		return
	pbox(center, size, yaw, kind, tint, false)


static func _peak_mesh(seed_i: int, rockc: Color) -> ArrayMesh:
	# 7 sided cone with a jittered ridge line, uvs in "metres" of the unit shape; vertex colour = snow
	# above 70% height (white), rock below
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 7
	var top := Vector3(rng.randf_range(-0.08, 0.08), 1.0, rng.randf_range(-0.08, 0.08))
	var ring := []
	var mid := []
	for i in segs:
		var a := TAU * i / segs + rng.randf_range(-0.2, 0.2)
		var r := 0.5 * rng.randf_range(0.8, 1.15)
		ring.append(Vector3(cos(a) * r, 0, sin(a) * r))
		mid.append(Vector3(cos(a) * r * 0.42, 0.62 + rng.randf_range(-0.08, 0.08), sin(a) * r * 0.42))
	var snow := Color(0.95, 0.96, 1.0)
	var tri := func(p0: Vector3, p1: Vector3, p2: Vector3, c0: Color, c1: Color, c2: Color) -> void:
		var nrm := (p2 - p0).cross(p1 - p0).normalized()
		for pc in [[p0, c0], [p1, c1], [p2, c2]]:
			st.set_normal(nrm)
			st.set_color(pc[1])
			var pp: Vector3 = pc[0]
			st.set_uv(Vector2(pp.x + pp.z, pp.y) * 6.0)
			st.add_vertex(pp)
	for i in segs:
		var j := (i + 1) % segs
		tri.call(ring[i], mid[i], mid[j], rockc, snow.lerp(rockc, 0.5), snow.lerp(rockc, 0.5))
		tri.call(ring[i], mid[j], ring[j], rockc, snow.lerp(rockc, 0.5), rockc)
		tri.call(mid[i], top, mid[j], snow, snow, snow)
	return st.commit()


## a node that keeps a CPUParticles3D cloud around the camera (dust / blowing snow)
static func drift_particles(parent: Node3D, col: Color, amount: int, size: float, vel: Vector3, life := 4.0, box := Vector3(14, 4, 14)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = vel.normalized()
	p.spread = 15.0
	p.initial_velocity_min = vel.length() * 0.7
	p.initial_velocity_max = vel.length() * 1.3
	p.gravity = Vector3(0, -0.05, 0)
	p.local_coords = false
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = col
	qm.material = m
	p.mesh = qm
	parent.add_child(p)
	return p
