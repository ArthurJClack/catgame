extends Node3D
## Parked cars for the city street: the three Shitbox Rally cars from secret (car_model.gd looks,
## data/city/cars/<id>.json sizes) standing still with box colliders, so the cat can jump on the
## hoods and roofs and hide underneath. No driving here: just big warm metal boxes at cat scale.

const Model := preload("res://scripts/city/car_model.gd")
const IDS := ["wrx_wagon", "crownvic", "civic_ep3"]
const PAINT := [Color(0.85, 0.85, 0.83), Color(0.08, 0.08, 0.09), Color(0.6, 0.62, 0.64), Color(0.32, 0.33, 0.35),
	Color(0.12, 0.17, 0.3), Color(0.45, 0.08, 0.08), Color(0.2, 0.28, 0.22), Color(0.55, 0.5, 0.42),
	Color(0.9, 0.2, 0.55), Color(0.1, 0.75, 0.8)]
const REST_Y := -0.15        # wheel centre below the car origin at rest (car.gd rest_y, roughly)

var defs := {}
var cars: Array[Node3D] = []


func _def(id: String) -> Dictionary:
	if not defs.has(id):
		defs[id] = JSON.parse_string(FileAccess.get_file_as_string("res://data/city/cars/%s.json" % id))
	return defs[id]


## a parked car standing on the ground at xf (xf.origin = the ground under its middle)
func park(id: String, xf: Transform3D, paint: Color) -> Node3D:
	var def := _def(id)
	var r := float(def.get("wheel_radius", 0.31))
	var body := StaticBody3D.new()
	body.name = "Car_" + id
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	body.add_to_group("city_car")
	for b in def.get("collision", []):
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(b["size"][0]), float(b["size"][1]), float(b["size"][2]))
		cs.shape = box
		# lift the box clear of the ground a bit so a cat fits under the sills (ground clearance)
		cs.position = Vector3(float(b["offset"][0]), float(b["offset"][1]) + 0.05, float(b["offset"][2]))
		body.add_child(cs)
	add_child(body)
	body.global_transform = Transform3D(xf.basis, xf.origin + Vector3.UP * (r - REST_Y))
	var wb := float(def["wheelbase"])
	var wheels := []
	var spots := []
	for i in 4:
		var front := i < 2
		var left := i % 2 == 0
		var track := float(def.get("track_front" if front else "track_rear", 1.5))
		wheels.append({"radius": r})
		spots.append([Vector3((-0.5 if left else 0.5) * track, REST_Y, (-0.5 if front else 0.5) * wb), left])
	var m := Model.new()
	body.add_child(m)
	m.build(def, REST_Y, wheels, paint)
	for i in 4:
		m.hubs[i].position = spots[i][0]
		m.hubs[i].rotation.y = PI if spots[i][1] else 0.0
	cars.append(body)
	return body


## park up to n cars on the data's parked spots (deterministic picks + paints)
func fill(spots: Array, n: int, terrain) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var order := range(spots.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	for k in mini(n, order.size()):
		var s: Dictionary = spots[order[k]]
		var x := float(s["x"])
		var z := float(s["z"])
		var y: float = terrain.at(x, z) if terrain != null else 0.0
		var rot := deg_to_rad(float(s.get("rot", 0.0)))
		park(IDS[rng.randi() % IDS.size()], Transform3D(Basis(Vector3.UP, rot), Vector3(x, y, z)), PAINT[rng.randi() % PAINT.size()])
