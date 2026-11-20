extends Node3D
## Builds a city scene from a city JSON (data/city/<id>.json: the approximate Pioneer Square
## blocks from tools/world/approx_pioneer_square.py, or a real OSM bake from tools/world/bake_city.py).
## PLACEHOLDER look: generated textures, extruded footprints, storefront + window bands, curbed
## sidewalks, lane paint, crosswalks. Props (lamps, trees...) come from city_props.gd.
## Real elevation (terrain.gd): ground, roads, curbs and paint follow the ground; buildings sit at
## the lowest corner of their footprint. All static collision is one trimesh on layer 1.

const Psx := preload("res://scripts/city/psx_mat.gd")
const Kit := preload("res://scripts/city/mesh_kit.gd")
const Props := preload("res://scripts/city/city_props.gd")
const Terrain := preload("res://scripts/city/terrain.gd")
const CURB := 0.15
const FLOOR := 4.0
const TINTS := [Color(0.55, 0.3, 0.24), Color(0.62, 0.52, 0.38), Color(0.38, 0.27, 0.22), Color(0.5, 0.5, 0.52)]
const NEON := [Color(1, 0.3, 0.55), Color(0.3, 0.9, 1), Color(1, 0.75, 0.3), Color(0.6, 1, 0.4), Color(0.75, 0.5, 1)]

var data: Dictionary
var parked: Array[Transform3D] = []   # parked car spots (the scene spawns real cars there)
var lamps: Array[Vector3] = []
var signs := {}                        # building id -> Label3D
var _roads: Array = []                 # [a, b, half width, street index] of every car street
var terrain = Terrain.new()


func build(d: Dictionary) -> void:
	data = d
	terrain.setup(d)
	var k := Kit.new()
	k.terrain = terrain
	k.drape = true
	var b: Array = d["bounds"]
	var x0: float = b[0]
	var z0: float = b[1]
	var x1: float = b[2]
	var z1: float = b[3]
	k.flat("asphalt", x0, z0, x1, z1, 0.0, true)   # the ground, with its collision
	for si in d["streets"].size():
		var st: Dictionary = d["streets"][si]
		if st.get("cars", true):
			var sp: Array = st["pts"]
			for i in range(1, sp.size()):
				_roads.append([Vector2(sp[i - 1][0], sp[i - 1][1]), Vector2(sp[i][0], sp[i][1]), float(st["width"]) * 0.5, si])
	for m in d.get("medians", []):
		_roads.append([Vector2(m["pts"][0][0], m["pts"][0][1]), Vector2(m["pts"][1][0], m["pts"][1][1]), float(m["width"]) * 0.5, -2])
	_streets(k)
	# divided avenues: a curbed median with bark mulch (the trees are props)
	for m in d.get("medians", []):
		var ma := Vector2(m["pts"][0][0], m["pts"][0][1])
		var mb := Vector2(m["pts"][1][0], m["pts"][1][1])
		var n := (mb - ma).normalized().orthogonal()
		_strip(k, ma, mb, n, -float(m["width"]) * 0.5, float(m["width"]) * 0.5, "bark")
	for p in d.get("plazas", []):
		# squares (Occidental Square): red brick pavers; other plazas: tile
		_slab(k, "pavers" if p.get("kind", "") == "square" else "tile", _ring(p["pts"]), CURB)
	for p in d.get("parks", []):
		_slab(k, "grass", _ring(p["pts"]), CURB + 0.01)
	k.drape = false
	for bl in d.get("buildings", []):
		_building(k, bl)
	k.commit(self, _materials())
	k.collider(self)
	# outskirts (coarse, no collision) + skyline + water (west: Elliott Bay)
	var far := Kit.new()
	far.step = 20.0
	far.chunk = 200.0
	far.terrain = terrain
	far.drape = true
	far.flat("asphalt", x0 - 240, z0 - 240, x1 + 240, z0, -0.02)
	far.flat("asphalt", x0 - 240, z1, x1 + 240, z1 + 240, -0.02)
	if d.get("water", []).is_empty():
		far.flat("asphalt", x0 - 240, z0, x0, z1, -0.02)
	far.flat("asphalt", x1, z0, x1 + 240, z1, -0.02)
	far.drape = false
	for s in d.get("skyline", []):
		var r := _ring(s["pts"])
		far.lift = terrain.lowest(r) - 0.5
		far.walls("sky", r, 0.0, float(s["height"]) + 0.5)
		far.floor_poly("roof", r, float(s["height"]) + 0.5)
	far.lift = 0.0
	for w in d.get("water", []):
		far.floor_poly("water", _ring(w["pts"]), 1.5)
	far.commit(self, _materials())
	if terrain.n == 0:
		_ground_box(x0 - 240, z0 - 240, x1 + 240, z1 + 240)
	var props := Props.new()
	props.terrain = terrain
	add_child(props)
	props.build(d.get("props", []))
	parked = props.parked
	lamps = props.lamps
	if d.has("play"):
		_walls(d["play"])


## the edge of the play area: invisible walls on their own layer (16), which only the player and
## the player's car collide with, so traffic still drives in and out
func _walls(p: Array) -> void:
	var a := Vector2(float(p[0]), float(p[1]))
	var b := Vector2(float(p[2]), float(p[3]))
	var c := (a + b) * 0.5
	var size := b - a
	# (tall: the ground climbs ~40 m across the area)
	for side in [[Vector3(c.x, 40, a.y), Vector3(size.x + 2, 120, 1)], [Vector3(c.x, 40, b.y), Vector3(size.x + 2, 120, 1)],
			[Vector3(a.x, 40, c.y), Vector3(1, 120, size.y + 2)], [Vector3(b.x, 40, c.y), Vector3(1, 120, size.y + 2)]]:
		var body := StaticBody3D.new()
		body.collision_layer = 16
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		cs.shape = box
		body.add_child(cs)
		add_child(body)
		body.position = side[0]


func _materials() -> Dictionary:
	var m := {
		"asphalt": Psx.mat(Color(0.5, 0.48, 0.58), "asphalt", 0.5, 0.06),   # cat game: lighter + a faint purple sheen (wet, neon)
		"concrete": Psx.mat(Color(0.62, 0.62, 0.6), "concrete", 0.5),
		"tile": Psx.mat(Color(0.6, 0.52, 0.45), "tile", 0.5),
		"grass": Psx.mat(Color(0.24, 0.4, 0.2), "grass", 0.6),
		"bark": Psx.mat(Color(0.38, 0.26, 0.17), "grass", 0.8),
		"pavers": Psx.mat(Color(0.55, 0.36, 0.3), "brick", 0.5),
		"paint": Psx.mat(Color(0.85, 0.85, 0.8), "plain", 1.0, 0.25),
		"yellow": Psx.mat(Color(0.85, 0.7, 0.2), "plain", 1.0, 0.25),
		"trim": Psx.mat(Color(0.45, 0.42, 0.4), "concrete", 0.5),
		"roof": Psx.mat(Color(0.2, 0.2, 0.22), "concrete", 0.25),
		"door": Psx.mat(Color(0.08, 0.07, 0.07), "plain"),
		"sky": Psx.mat(Color(0.3, 0.33, 0.42), "windows", 0.125, 0.3),
		"water": Psx.mat(Color(0.06, 0.12, 0.18), "plain", 1.0, 0.1),
	}
	# one storefront + one window material for every building: the tint is per vertex
	m["store"] = Psx.mat(Color.WHITE, "storefront", 0.125, 0.35)
	m["win"] = Psx.mat(Color.WHITE, "windows", 0.125, 0.3)
	for k in ["store", "win"]:
		(m[k] as ShaderMaterial).set_shader_parameter("vcol", true)
	return m


func _ring(pts: Array) -> PackedVector2Array:
	var r := PackedVector2Array()
	for p in pts:
		r.append(Vector2(float(p[0]), float(p[1])))
	if r.size() > 2 and r[0].distance_to(r[r.size() - 1]) < 0.01:
		r.remove_at(r.size() - 1)
	return r


func _slab(k, key: String, r: PackedVector2Array, h: float) -> void:
	k.floor_poly(key, r, h, true)
	k.walls("concrete", r, 0.0, h, true)


# --- streets: sidewalks with curbs, lane paint, crosswalks ------------------

func _streets(k) -> void:
	var sw: float = data.get("sidewalk", 3.5)
	var streets: Array = data["streets"]
	for si in streets.size():
		var s: Dictionary = streets[si]
		var w: float = s["width"]
		var pts: Array = s["pts"]
		var cars: bool = s.get("cars", true)
		for i in range(1, pts.size()):
			var a := Vector2(pts[i - 1][0], pts[i - 1][1])
			var bb := Vector2(pts[i][0], pts[i][1])
			var dir := (bb - a).normalized()
			var n := dir.orthogonal()
			for cut in _cuts(si, a, bb):
				var ca: Vector2 = cut[0]
				var cb: Vector2 = cut[1]
				var ja: int = cut[2]
				var jb: int = cut[3]
				# the lower-numbered street owns each corner square; the other stops short of it
				var sa: Vector2 = ca + dir * (sw if ja >= 0 and ja < si else 0.0)
				var sb: Vector2 = cb - dir * (sw if jb >= 0 and jb < si else 0.0)
				if not cars:
					_strip(k, sa, sb, n, -w * 0.5 - sw, w * 0.5 + sw, "concrete")
					continue
				for side in [[w * 0.5, w * 0.5 + sw], [-w * 0.5 - sw, -w * 0.5]]:
					var mid: Vector2 = (sa + sb) * 0.5 + n * (float(side[0]) + float(side[1])) * 0.5
					if not _on_other_road(mid, si):   # divided roads: no sidewalk down the median
						_strip(k, sa, sb, n, side[0], side[1], "concrete")
				_paint_line(k, ca + dir * sw, cb - dir * sw, n, w, bool(s.get("oneway", false)))
				if ja >= 0:
					_crosswalk(k, ca + dir * sw * 0.5, n, w)
				if jb >= 0:
					_crosswalk(k, cb - dir * sw * 0.5, n, w)


## the parts of segment a-b between cross streets: [[from, to, street at from, street at to]]
## (-1 = no cross street there, just the end of the street)
func _cuts(si: int, a: Vector2, b: Vector2) -> Array:
	var dir := (b - a).normalized()
	var total := a.distance_to(b)
	var stops := [[0.0, 0.0, -1], [total, 0.0, -1]]   # [t, half width of the cross street, its index]
	var streets: Array = data["streets"]
	for sj in streets.size():
		if sj == si:
			continue
		var o: Dictionary = streets[sj]
		var op: Array = o["pts"]
		for j in range(1, op.size()):
			var p = Geometry2D.segment_intersects_segment(a, b, Vector2(op[j - 1][0], op[j - 1][1]), Vector2(op[j][0], op[j][1]))
			if p == null:
				continue
			var t := a.distance_to(p)
			var half := float(o["width"]) * 0.5
			if t <= 0.5:
				stops[0] = [0.0, half, sj]       # starts on a cross street
			elif t >= total - 0.5:
				stops[1] = [total, half, sj]     # ends on one (Occidental at Yesler)
			else:
				stops.append([t, half, sj])
	stops.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out := []
	for i in range(1, stops.size()):
		var t0: float = stops[i - 1][0] + stops[i - 1][1]
		var t1: float = stops[i][0] - stops[i][1]
		if t1 - t0 > 0.5:
			out.append([a + dir * t0, a + dir * t1, stops[i - 1][2], stops[i][2]])
	return out


## a raised strip beside the road, from lateral offset o0 to o1
func _strip(k, a: Vector2, b: Vector2, n: Vector2, o0: float, o1: float, key: String) -> void:
	if key == "concrete" and _on_median((a + b) * 0.5 + n * (o0 + o1) * 0.5):
		return   # (a sidewalk strip that would land in a median)
	var p := [a + n * o0, b + n * o0, b + n * o1, a + n * o1]
	var r := PackedVector2Array(p)
	_slab(k, key, r, CURB)


func _on_median(p: Vector2) -> bool:
	for r in _roads:
		if int(r[3]) == -2 and Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p) < float(r[2]) + 1.0:
			return true
	return false


func _on_other_road(p: Vector2, self_i: int) -> bool:
	for r in _roads:
		if int(r[3]) != self_i and Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p) < float(r[2]) + 0.5:
			return true
	return false


func _paint_line(k, a: Vector2, b: Vector2, n: Vector2, w: float, oneway := false) -> void:
	var dir := (b - a).normalized()
	var ln := a.distance_to(b)
	var t := 2.0
	while t + 3.0 < ln - 2.0 and (not oneway or w >= 8.0):
		var c := a + dir * t
		_flat_rect(k, "paint" if oneway else "yellow", c, c + dir * 3.0, n, 0.08)
		t += 7.0
	if w >= 18.0:   # wide streets get lane edge lines
		for side in [-1.0, 1.0]:
			_flat_rect(k, "paint", a + n * side * (w * 0.5 - 1.2), b + n * side * (w * 0.5 - 1.2), n, 0.06)


func _crosswalk(k, c: Vector2, n: Vector2, w: float) -> void:
	var dir := n.orthogonal()
	var o := -w * 0.5 + 0.6
	while o < w * 0.5 - 0.6:
		var p := c + n * o
		_flat_rect(k, "paint", p - dir * 1.4, p + dir * 1.4, dir.orthogonal(), 0.25)
		o += 1.2


func _flat_rect(k, key: String, a: Vector2, b: Vector2, n: Vector2, half: float) -> void:
	var y := 0.02
	k.quad(key, Vector3(a.x + n.x * half, y, a.y + n.y * half), Vector3(b.x + n.x * half, y, b.y + n.y * half),
		Vector3(b.x - n.x * half, y, b.y - n.y * half), Vector3(a.x - n.x * half, y, a.y - n.y * half), Vector3.UP)


# --- buildings ---------------------------------------------------------------

func _building(k, bl: Dictionary) -> void:
	var r := _ring(bl["pts"])
	var levels: int = bl.get("levels", 3)
	var h := FLOOR * maxf(1.0, float(levels))
	var ti: int = absi(hash(bl["id"])) % TINTS.size()
	k.lift = terrain.lowest(r) - 0.3   # sits at its lowest corner; uphill the ground covers the base
	k.color = TINTS[ti]
	k.walls("store", r, 0.0, FLOOR, true)
	k.walls("win", r, FLOOR, h, true)
	k.color = Color.WHITE
	var lip := Geometry2D.offset_polygon(r, 0.35)
	if lip.size() > 0:
		k.walls("trim", lip[0], h - 0.7, h)
		k.floor_poly("roof", lip[0], h)
		k.walls("trim", lip[0], FLOOR - 0.1, FLOOR + 0.35)
	else:
		k.floor_poly("roof", r, h)
	for door in bl["doors"]:
		var f := deg_to_rad(float(door[2]))
		var dir := Vector2(sin(f), cos(f))
		var p := Vector2(float(door[0]), float(door[1])) - dir * 0.15
		var side := dir.orthogonal()
		var n := Vector3(dir.x, 0, dir.y)
		var a := p - side * 0.9
		var c := p + side * 0.9
		var gy := terrain.at(p.x, p.y)   # doors open onto the street where it is, uphill or down
		k.lift = gy
		k.quad("door", Vector3(a.x, 0.15, a.y), Vector3(c.x, 0.15, c.y), Vector3(c.x, 2.7, c.y), Vector3(a.x, 2.7, a.y), n)
		# AI PLACEHOLDER: the business names are made up (data has "ai_text": true)
		var sign := Label3D.new()
		sign.text = str(bl.get("name", ""))
		sign.font_size = 28
		sign.pixel_size = 0.02
		sign.outline_size = 6
		sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sign.visibility_range_end = 90.0
		sign.modulate = NEON[absi(hash(bl["id"])) % NEON.size()]
		sign.position = Vector3(p.x + dir.x * 0.3, gy + 3.3, p.y + dir.y * 0.3)
		sign.rotation.y = f
		add_child(sign)
		signs[bl["id"]] = sign
	k.lift = 0.0


func _ground_box(x0: float, z0: float, x1: float, z1: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(x1 - x0, 1.0, z1 - z0)
	cs.shape = box
	cs.position = Vector3((x0 + x1) * 0.5, -0.5, (z0 + z1) * 0.5)
	body.add_child(cs)
	add_child(body)
