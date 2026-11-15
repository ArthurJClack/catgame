class_name LowPoly
extends RefCounted
## helpers for building flat shaded low poly meshes + simple ik math

static var _mesh_cache := {}
static var _mat_cache := {}


## turns any primitive mesh into a flat shaded (faceted) ArrayMesh with a tiny
## per-face brightness jitter, which is what sells the low poly look
static func flat(src: PrimitiveMesh, jitter: float = 0.05, rng_seed: int = 7) -> ArrayMesh:
	var arrays := src.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var use_idx := idx.size() > 0
	var count := idx.size() if use_idx else verts.size()
	for t in range(0, count - 2, 3):
		var i0 := idx[t] if use_idx else t
		var i1 := idx[t + 1] if use_idx else t + 1
		var i2 := idx[t + 2] if use_idx else t + 2
		var a := verts[i0]
		var b := verts[i1]
		var c := verts[i2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-16:
			continue
		n = n.normalized()
		var avg := norms[i0] + norms[i1] + norms[i2]
		if n.dot(avg) < 0.0:
			n = -n
		var s := 1.0 + rng.randf_range(-jitter, jitter)
		var col := Color(s, s, s)
		out_v.append(a); out_v.append(b); out_v.append(c)
		out_n.append(n); out_n.append(n); out_n.append(n)
		out_c.append(col); out_c.append(col); out_c.append(col)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out_v
	arr[Mesh.ARRAY_NORMAL] = out_n
	arr[Mesh.ARRAY_COLOR] = out_c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## like flat(), but every face gets its color from painter.call(centroid, normal) -> Color.
## used to paint fur patterns (tabby stripes, white bellies, socks) straight into the mesh
static func painted(src: PrimitiveMesh, painter: Callable, key: String, jitter: float = 0.035, xf := Transform3D.IDENTITY) -> ArrayMesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var base := flat(src, 0.0)
	var arrays := base.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if xf != Transform3D.IDENTITY:
		for i in verts.size():
			verts[i] = xf * verts[i]
			norms[i] = (xf.basis * norms[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for t in range(0, verts.size(), 3):
		var c := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
		var col: Color = painter.call(c, norms[t])
		var s := 1.0 + rng.randf_range(-jitter, jitter)
		col = Color(col.r * s, col.g * s, col.b * s)
		cols[t] = col; cols[t + 1] = col; cols[t + 2] = col
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = m
	return m


static func sphere_src(segs: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func cyl_src(top_r: float, bot_r: float, segs: int, rings: int = 1) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = 1.0
	c.radial_segments = segs
	c.rings = rings
	return c


## unit diameter sphere (scale it to get an ellipsoid of that size)
static func sphere(segs: int = 8, rings: int = 5) -> ArrayMesh:
	var key := "s%d_%d" % [segs, rings]
	if not _mesh_cache.has(key):
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = segs
		s.rings = rings
		_mesh_cache[key] = flat(s, 0.06, segs * 31 + rings)
	return _mesh_cache[key]


## unit height cylinder along +Y, centered. top_r is the radius at +Y
static func cyl(top_r: float, bot_r: float, segs: int = 7) -> ArrayMesh:
	var key := "c%.4f_%.4f_%d" % [top_r, bot_r, segs]
	if not _mesh_cache.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top_r
		c.bottom_radius = bot_r
		c.height = 1.0
		c.radial_segments = segs
		c.rings = 1
		_mesh_cache[key] = flat(c, 0.05, segs)
	return _mesh_cache[key]


static func cone(segs: int = 4) -> ArrayMesh:
	return cyl(0.0, 0.5, segs)


static func box(jitter: float = 0.04) -> ArrayMesh:
	var key := "b%.3f" % jitter
	if not _mesh_cache.has(key):
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		_mesh_cache[key] = flat(b, jitter, 3)
	return _mesh_cache[key]


static func mat(c: Color, rough: float = 0.85, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [c.to_html(), rough, emission]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.vertex_color_use_as_albedo = true
		m.roughness = rough
		if emission > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emission
		_mat_cache[key] = m
	return _mat_cache[key]


static func part(parent: Node, mesh: Mesh, color: Color, pos := Vector3.ZERO, scl := Vector3.ONE, rot := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, 0.85, emission)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


## transform that maps a unit +Y cylinder so it spans from b (bottom) to a (top)
static func seg_xform(a: Vector3, b: Vector3) -> Transform3D:
	var d := a - b
	var l := d.length()
	if l < 1e-5:
		return Transform3D(Basis().scaled(Vector3(1, 1e-4, 1)), a)
	var y := d / l
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


## two bone ik. returns [mid_joint, end_effector]. hint = which way the joint bends
static func ik2(root: Vector3, target: Vector3, la: float, lb: float, hint: Vector3) -> Array:
	var d := target - root
	var dist := d.length()
	var dir := d / dist if dist > 1e-5 else Vector3.DOWN
	dist = clampf(dist, absf(la - lb) + 0.002, la + lb - 0.0008)
	var cos_a := clampf((la * la + dist * dist - lb * lb) / (2.0 * la * dist), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var perp := hint - dir * hint.dot(dir)
	if perp.length_squared() < 1e-8:
		perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var mid := root + dir * (la * cos_a) + perp * (la * sin_a)
	return [mid, root + dir * dist]


static func damp(a: float, b: float, rate: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-rate * dt))


static func damp3(a: Vector3, b: Vector3, rate: float, dt: float) -> Vector3:
	return a.lerp(b, 1.0 - exp(-rate * dt))


static var _fur_shaders := {}


## fur shader: vertex colors + optional hashed "fleck" streaks, optional
## shell cutout (blocky clumps). everything in object space so it sticks to the animated parts
static func fur_mat(fleck: float, keep: float = 1.0, density: float = 10.0, tint: float = 1.0, base := Color.WHITE) -> ShaderMaterial:
	var key := "%.2f_%.2f_%.1f_%.2f_%s" % [fleck, keep, density, tint, base.to_html()]
	if _fur_shaders.has(key):
		return _fur_shaders[key]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform float fleck = 0.0;
uniform float keep = 1.0;
uniform float density = 10.0;
uniform float tint = 1.0;
uniform vec3 base = vec3(1.0);
varying vec3 op;
float h3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
void vertex() { op = VERTEX; }
void fragment() {
	if (keep < 1.0) {
		vec3 cell = floor(op * density + 0.5);
		if (h3(cell) > keep) discard;
	}
	vec3 c = COLOR.rgb * base * tint;
	if (fleck > 0.0) {
		// short streaks of lighter/darker hair, blocky like an old console texture
		float s = h3(floor(op * vec3(46.0, 46.0, 14.0)));
		float s2 = h3(floor(op * vec3(14.0, 46.0, 46.0)) + 7.0);
		float f = mix(s, s2, 0.5);
		c *= 1.0 - fleck * 0.5 + fleck * f;
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("fleck", fleck)
	m.set_shader_parameter("keep", keep)
	m.set_shader_parameter("density", density)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("base", Vector3(base.r, base.g, base.b))
	_fur_shaders[key] = m
	return m
