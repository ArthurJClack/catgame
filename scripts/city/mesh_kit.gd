extends RefCounted
## Collects city geometry as subdivided quads (PSX vertex lighting and affine textures need small
## polygons) and turns it into meshes: one MeshInstance per material per 40 m chunk, so each piece
## only sees the street lamps near it. Also gathers collision faces.
##   var k := Kit.new()
##   k.quad("brick", a, b, c, d, normal)   # a->b = u, a->d = v
##   k.commit(parent, {"brick": material})

var chunk := 40.0               # meters; one MeshInstance per chunk (a surface per material)
var color := Color.WHITE         # vertex color for what's added next (materials with vcol on use it)

var step := 4.0
var terrain = null               # terrain.gd: when `drape` is on, vertex heights are added to it
var drape := false
var lift := 0.0                  # added to every y (buildings sit at their footprint's base)
var _collide := false
var _tris := {}            # "key|cx|cz" -> PackedVector3Array (3 per triangle)
var _nrms := {}
var _cols := {}
var collision := PackedVector3Array()


func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, collide := false) -> void:
	_collide = collide
	var nu := maxi(1, ceili(a.distance_to(b) / step))
	var nv := maxi(1, ceili(a.distance_to(d) / step))
	for i in nu:
		for j in nv:
			var p00 := _bil(a, b, c, d, float(i) / nu, float(j) / nv)
			var p10 := _bil(a, b, c, d, float(i + 1) / nu, float(j) / nv)
			var p11 := _bil(a, b, c, d, float(i + 1) / nu, float(j + 1) / nv)
			var p01 := _bil(a, b, c, d, float(i) / nu, float(j + 1) / nv)
			tri(key, p00, p10, p11, n)
			tri(key, p00, p11, p01, n)
	_collide = false


func _y(p: Vector3) -> Vector3:
	if drape and terrain != null:
		return Vector3(p.x, p.y + terrain.at(p.x, p.z) + lift, p.z)
	return Vector3(p.x, p.y + lift, p.z)


func _bil(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float, v: float) -> Vector3:
	return a.lerp(b, u).lerp(d.lerp(c, u), v)


## Godot front faces wind clockwise seen from outside
func _wind(p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3) -> Array:
	if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
		return [p0, p2, p1]
	return [p0, p1, p2]


func tri(key: String, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3) -> void:
	p0 = _y(p0)
	p1 = _y(p1)
	p2 = _y(p2)
	if drape and n.y > 0.9:   # slopes tilt the floor's normal
		n = (p1 - p0).cross(p2 - p0).normalized()
		if n.y < 0.0:
			n = -n
	if _collide:
		for p in _wind(p0, p1, p2, n):
			collision.append(p)
	var mid := (p0 + p1 + p2) / 3.0
	var k := "%s|%d|%d" % [key, floori(mid.x / chunk), floori(mid.z / chunk)]
	if not _tris.has(k):
		_tris[k] = PackedVector3Array()
		_nrms[k] = PackedVector3Array()
		_cols[k] = PackedColorArray()
	for p in _wind(p0, p1, p2, n):
		_tris[k].append(p)
		_nrms[k].append(n)
		_cols[k].append(color)


## a flat horizontal polygon (roofs, parks), triangulated
func floor_poly(key: String, pts: PackedVector2Array, y: float, collide := false) -> void:
	_collide = collide
	var idx := Geometry2D.triangulate_polygon(pts)
	for t in range(0, idx.size(), 3):
		var a := Vector3(pts[idx[t]].x, y, pts[idx[t]].y)
		var b := Vector3(pts[idx[t + 1]].x, y, pts[idx[t + 1]].y)
		var c := Vector3(pts[idx[t + 2]].x, y, pts[idx[t + 2]].y)
		if drape:   # big draped polygons: split them so they follow the ground
			_split_tri(key, a, b, c, 0)
		else:
			tri(key, a, b, c, Vector3.UP)
	_collide = false


func _split_tri(key: String, a: Vector3, b: Vector3, c: Vector3, depth: int) -> void:
	var lab := a.distance_to(b)
	var lbc := b.distance_to(c)
	var lca := c.distance_to(a)
	var m := maxf(lab, maxf(lbc, lca))
	if m <= step * 1.5 or depth > 8:
		tri(key, a, b, c, Vector3.UP)
		return
	if m == lab:
		var p := (a + b) * 0.5
		_split_tri(key, a, p, c, depth + 1)
		_split_tri(key, p, b, c, depth + 1)
	elif m == lbc:
		var p := (b + c) * 0.5
		_split_tri(key, a, b, p, depth + 1)
		_split_tri(key, a, p, c, depth + 1)
	else:
		var p := (c + a) * 0.5
		_split_tri(key, a, b, p, depth + 1)
		_split_tri(key, p, b, c, depth + 1)


## a horizontal rectangle, subdivided (ground, sidewalks, streets)
func flat(key: String, x0: float, z0: float, x1: float, z1: float, y: float, collide := false) -> void:
	quad(key, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, collide)


## vertical walls around a footprint ring from y0 to y1, facing out
func walls(key: String, ring: PackedVector2Array, y0: float, y1: float, collide := false) -> void:
	var cw := _signed_area(ring) > 0.0
	for i in ring.size():
		var a2 := ring[i]
		var b2 := ring[(i + 1) % ring.size()]
		var e := (b2 - a2).normalized()
		var out2 := Vector2(e.y, -e.x) if cw else Vector2(-e.y, e.x)
		var n := Vector3(out2.x, 0, out2.y)
		quad(key, Vector3(a2.x, y0, a2.y), Vector3(b2.x, y0, b2.y), Vector3(b2.x, y1, b2.y), Vector3(a2.x, y1, a2.y), n, collide)


func _signed_area(r: PackedVector2Array) -> float:
	var s := 0.0
	for i in r.size():
		var a := r[i]
		var b := r[(i + 1) % r.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func commit(parent: Node3D, mats: Dictionary) -> void:
	var chunks := {}        # "cx|cz" -> ArrayMesh with a surface per material
	for k in _tris:
		var key: String = (k as String).get_slice("|", 0)
		var ck: String = (k as String).substr(key.length() + 1)
		if not chunks.has(ck):
			chunks[ck] = ArrayMesh.new()
		var m: ArrayMesh = chunks[ck]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = _tris[k]
		arr[Mesh.ARRAY_NORMAL] = _nrms[k]
		arr[Mesh.ARRAY_COLOR] = _cols[k]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, mats[key])
	for ck in chunks:
		var mi := MeshInstance3D.new()
		mi.mesh = chunks[ck]
		parent.add_child(mi)
	_tris.clear()
	_nrms.clear()
	_cols.clear()


func collider(parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body
