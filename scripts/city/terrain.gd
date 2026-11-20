extends RefCounted
## The ground's height under the city: a grid from the city json's "terrain" (real elevation,
## tools/world/osm_lite_to_city.py), read bilinearly. No terrain in the json = flat at 0.
## Everything that stands on the ground asks at(x, z): the ground mesh and its collision, roads,
## sidewalks, buildings (they sit at the lowest corner of their footprint, the uphill side buried
## like real Seattle buildings), props, the walk / car graphs, spawns.

var x0 := 0.0
var z0 := 0.0
var step := 10.0
var n := 0
var h := PackedFloat32Array()


func setup(d: Dictionary) -> void:
	var t: Dictionary = d.get("terrain", {})
	if t.is_empty():
		return
	x0 = float(t["x0"])
	z0 = float(t["z0"])
	step = float(t["step"])
	n = int(t["n"])
	h = PackedFloat32Array(t["h"])


func at(x: float, z: float) -> float:
	if n == 0:
		return 0.0
	var fx := clampf((x - x0) / step, 0.0, n - 1.001)
	var fz := clampf((z - z0) / step, 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(h[j * n + i], h[j * n + i + 1], tx)
	var b := lerpf(h[(j + 1) * n + i], h[(j + 1) * n + i + 1], tx)
	return lerpf(a, b, tz)


func at_v(p: Vector3, up := 0.0) -> Vector3:
	return Vector3(p.x, at(p.x, p.z) + up, p.z)


## lowest ground under a footprint ring
func lowest(ring: PackedVector2Array) -> float:
	var m := INF
	for p in ring:
		m = minf(m, at(p.x, p.y))
	return m if m < INF else 0.0
