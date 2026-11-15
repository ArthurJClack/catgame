class_name Fauna
extends Critter
## more forest wildlife, built on the Critter base (same helpers, same prey interface):
##   duck      a pair on the pond with a line of ducklings. dabbles bottoms-up, drifts to the far side when the
##             cat shows up on the bank, takes off across the water if it gets close and circles until it's safe
##   duckling  follows the one in front. when mum flies they scoot into the reeds and sit tight
##   dragonfly hover, dart, hover over the water. huntable (good luck)
##   hedgehog  snuffles about, rolls into a ball when the cat comes close, can be nudged along like one
##   hopper    grasshoppers hidden in the grass that ping away when the cat walks through. huntable
##   hawk      circles over the meadow (its shadow sweeps the grass), now and then stoops at a rabbit:
##             everything in the open scatters. it breaks off if the cat is close
##   woodpecker hitches up trunks and drums (the cat's ears turn to it), flies to another tree if you climb after it
##   crow      struts about, too smart to flush: sidles away keeping its distance. if the cat is up a tree
##             or carrying prey they gather, caw and take turns swooping past its head
##   lizard    basks on a rock, skitters round the back when the cat comes, peeks out again later
##   owl       dozes on a high limb by day and tracks the cat with its head. hunts on silent wings at night
##   bat       dusk + night: flutters in loops over the clearings

const NEW_PREY := ["dragonfly", "hopper", "lizard"]
const FAR := {"duck": 60.0, "duckling": 40.0, "dragonfly": 16.0, "hedgehog": 24.0, "hopper": 9.0, "hawk": 140.0,
	"woodpecker": 32.0, "crow": 46.0, "lizard": 14.0, "owl": 46.0, "bat": 40.0}
const NO_SHADOW := ["dragonfly", "hopper", "lizard", "duckling", "bat"]

var leader: Fauna
var rank := 0
var curl := 0.0
var trunk_a := 0.0
var cling_y := 2.0
var cool := 0.0
var parts := {}
var _air := false
static var atmos: Atmos


func _ready() -> void:
	super._ready()
	# these fly about on their own business all day: only a real scare is passed on (_shout)
	_hushed = true
	if kind in NEW_PREY:
		add_to_group("prey")
	var far: float = FAR.get(kind, 30.0)
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is GeometryInstance3D:
			var g := n as GeometryInstance3D
			g.visibility_range_end = far
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind in NO_SHADOW else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	match kind:
		"duck", "duckling":
			position.y = ForestLevel.WATER_Y
			_set_state("paddle", rng.randf_range(1.0, 4.0))
			target = _pond_point()
		"dragonfly":
			position.y = ForestLevel.WATER_Y + 0.4
			target = position
			_set_state("hover", 1.0)
		"hawk":
			_set_state("soar", rng.randf_range(25.0, 45.0))
		"woodpecker":
			_pick_trunk(false)
			_set_state("scan", 1.0)
		"owl":
			_set_state("doze", 3.0)
		"bat":
			_set_state("roost", 1.0)
			visible = false
		"lizard":
			_set_state("bask", 2.0)
		"hopper":
			_set_state("sit", rng.randf_range(2.0, 10.0))
		"crow":
			_set_state("strut", 2.0)


func _night() -> bool:
	return atmos != null and atmos.is_night()


func _shout() -> void:
	get_tree().call_group("wild", "alarmed", global_position, kind, self)


func _ears(loud: float) -> void:
	get_tree().call_group("cat_ears", "hear", global_position, loud)


# ------------------------------------------------------------------ models
func _build_duck() -> void:
	var drake := rng.randf() < 0.5 if not has_meta("drake") else bool(get_meta("drake"))
	var col := Color(0.62, 0.6, 0.58) if drake else Color(0.5, 0.38, 0.26)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(7, 4), col, Vector3(0, 0.07, 0.02), Vector3(0.2, 0.17, 0.4))
	_p(body, LowPoly.sphere(5, 3), Color(0.36, 0.22, 0.16) if drake else col.lightened(0.15), Vector3(0, 0.07, -0.13), Vector3(0.17, 0.15, 0.16))
	var neck := _pivot(body, Vector3(0, 0.11, -0.15))
	_p(neck, LowPoly.box(), Color(0.1, 0.36, 0.2) if drake else col, Vector3(0, 0.05, 0), Vector3(0.06, 0.12, 0.06))
	if drake:
		_p(neck, LowPoly.box(0.0), Color(0.95, 0.95, 0.92), Vector3(0, 0.005, 0), Vector3(0.065, 0.015, 0.065))
	head = _pivot(neck, Vector3(0, 0.12, 0))
	_p(head, LowPoly.sphere(6, 4), Color(0.1, 0.4, 0.22) if drake else col.darkened(0.08), Vector3(0, 0, -0.01), Vector3(0.085, 0.08, 0.1))
	_p(head, LowPoly.box(), Color(0.92, 0.75, 0.2) if drake else Color(0.8, 0.5, 0.2), Vector3(0, -0.012, -0.075), Vector3(0.045, 0.018, 0.07))
	for s in [-1, 1]:
		_p(head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(s * 0.04, 0.012, -0.03), Vector3.ONE * 0.012)
		var w := _pivot(body, Vector3(s * 0.09, 0.11, 0.0))
		_p(w, LowPoly.box(), col.darkened(0.12), Vector3(s * 0.01, 0, 0.05), Vector3(0.025, 0.09, 0.26))
		_p(w, LowPoly.box(0.0), Color(0.2, 0.3, 0.7), Vector3(s * 0.024, -0.01, 0.1), Vector3(0.006, 0.03, 0.07))
		wings.append(w)
	tail = _pivot(body, Vector3(0, 0.1, 0.2))
	_p(tail, LowPoly.box(), Color(0.95, 0.95, 0.92) if drake else col.lightened(0.2), Vector3(0, 0.02, 0.04), Vector3(0.09, 0.03, 0.1), Vector3(0.5, 0, 0))


func _build_duckling() -> void:
	var col := Color(0.92, 0.8, 0.3)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(6, 4), col, Vector3(0, 0.03, 0.01), Vector3(0.075, 0.07, 0.11))
	_p(body, LowPoly.sphere(5, 3), Color(0.45, 0.36, 0.2), Vector3(0, 0.05, 0.02), Vector3(0.06, 0.04, 0.08))
	head = _pivot(body, Vector3(0, 0.075, -0.04))
	_p(head, LowPoly.sphere(5, 4), col, Vector3.ZERO, Vector3.ONE * 0.055)
	_p(head, LowPoly.box(), Color(0.3, 0.25, 0.2), Vector3(0, -0.008, -0.035), Vector3(0.02, 0.01, 0.025))
	for s in [-1, 1]:
		_p(head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(s * 0.024, 0.008, -0.016), Vector3.ONE * 0.008)


func _build_dragonfly() -> void:
	var col: Color = [Color(0.15, 0.55, 0.9), Color(0.2, 0.75, 0.45), Color(0.85, 0.2, 0.15)][rng.randi() % 3]
	body = _pivot(self, Vector3.ZERO)
	LowPoly.part(body, LowPoly.box(), col, Vector3(0, 0, 0.022), Vector3(0.006, 0.006, 0.055), Vector3.ZERO, 0.4)
	LowPoly.part(body, LowPoly.box(), col.darkened(0.3), Vector3(0, 0.001, -0.012), Vector3(0.011, 0.011, 0.018))
	_p(body, LowPoly.sphere(4, 3), Color(0.1, 0.25, 0.2), Vector3(0, 0.002, -0.026), Vector3(0.013, 0.01, 0.01))
	for k in 4:
		var s := -1.0 if k % 2 == 0 else 1.0
		var w := _pivot(body, Vector3(s * 0.004, 0.005, -0.014 + (0.0 if k < 2 else 0.012)))
		_p(w, LowPoly.box(0.0), Color(0.62, 0.74, 0.82), Vector3(s * 0.022, 0, 0), Vector3(0.042, 0.0008, 0.008))
		wings.append(w)


func _build_hedgehog() -> void:
	var spine := Color(0.36, 0.3, 0.24)
	var face := Color(0.78, 0.68, 0.55)
	body = _pivot(self, Vector3.ZERO)
	parts["ball"] = _p(body, LowPoly.sphere(7, 4), spine, Vector3(0, 0.065, 0.02), Vector3(0.15, 0.12, 0.22))
	var rs := RandomNumberGenerator.new()
	rs.seed = 5
	parts["spines"] = _pivot(body, Vector3(0, 0.065, 0.02))
	for k in 16:
		var a := rs.randf() * TAU
		var up := rs.randf_range(0.15, 1.0)
		var dir := Vector3(cos(a) * sqrt(1.0 - up * up), up, sin(a) * sqrt(1.0 - up * up) * 1.4 + 0.2).normalized()
		var sp := _p(parts["spines"], LowPoly.cone(3), spine.lightened(0.25 if k % 3 == 0 else 0.08), dir * Vector3(0.07, 0.058, 0.1), Vector3(0.02, 0.045, 0.02))
		sp.transform.basis = Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(0.02, 0.045, 0.02))
	head = _pivot(body, Vector3(0, 0.05, -0.09))
	_p(head, LowPoly.cone(5), face, Vector3(0, 0, -0.035), Vector3(0.075, 0.09, 0.065), Vector3(-PI / 2, 0, 0))
	_p(head, LowPoly.box(0.0), Color(0.05, 0.04, 0.04), Vector3(0, 0, -0.082), Vector3.ONE * 0.014)
	for s in [-1, 1]:
		_p(head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(s * 0.024, 0.016, -0.03), Vector3.ONE * 0.009)
		_p(head, LowPoly.sphere(4, 3), face.darkened(0.15), Vector3(s * 0.03, 0.03, -0.005), Vector3(0.02, 0.022, 0.008))
	_leg(body, Vector3(0.045, 0.03, -0.05), 0.03, 0.02, face.darkened(0.2))
	_leg(body, Vector3(-0.045, 0.03, -0.05), 0.03, 0.02, face.darkened(0.2))
	_leg(body, Vector3(0.05, 0.03, 0.07), 0.03, 0.022, face.darkened(0.2))
	_leg(body, Vector3(-0.05, 0.03, 0.07), 0.03, 0.022, face.darkened(0.2))


func _build_hopper() -> void:
	var col := Color(0.45, 0.68, 0.2) if rng.randf() < 0.7 else Color(0.62, 0.52, 0.3)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.box(), col, Vector3(0, 0.008, 0), Vector3(0.007, 0.008, 0.03))
	_p(body, LowPoly.box(), col.darkened(0.15), Vector3(0, 0.011, -0.016), Vector3(0.008, 0.009, 0.008))
	for s in [-1, 1]:
		# the big folded jumping legs
		_p(body, LowPoly.box(0.0), col.lightened(0.1), Vector3(s * 0.007, 0.012, 0.008), Vector3(0.003, 0.004, 0.024), Vector3(0.7, 0, 0))
		var w := _pivot(body, Vector3(s * 0.003, 0.013, 0.0))
		_p(w, LowPoly.box(0.0), Color(1.0, 0.85, 0.4), Vector3(s * 0.014, 0, 0.006), Vector3(0.028, 0.001, 0.018)).visible = false
		wings.append(w)


func _build_hawk() -> void:
	var col := Color(0.42, 0.3, 0.2)
	var pale := Color(0.9, 0.84, 0.72)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(6, 4), col, Vector3(0, 0, 0), Vector3(0.16, 0.13, 0.42))
	_p(body, LowPoly.sphere(5, 3), pale, Vector3(0, -0.025, -0.03), Vector3(0.13, 0.09, 0.3))
	head = _pivot(body, Vector3(0, 0.02, -0.22))
	_p(head, LowPoly.sphere(5, 4), col.lightened(0.1), Vector3.ZERO, Vector3(0.1, 0.09, 0.11))
	_p(head, LowPoly.cone(4), Color(0.9, 0.75, 0.2), Vector3(0, -0.01, -0.06), Vector3(0.03, 0.05, 0.03), Vector3(-PI / 2 - 0.4, 0, 0))
	tail = _pivot(body, Vector3(0, 0, 0.2))
	_p(tail, LowPoly.box(), Color(0.7, 0.36, 0.2), Vector3(0, 0, 0.1), Vector3(0.14, 0.012, 0.22))
	for s in [-1, 1]:
		var w := _pivot(body, Vector3(s * 0.06, 0.02, -0.02))
		_p(w, LowPoly.box(), col, Vector3(s * 0.17, 0, 0.0), Vector3(0.34, 0.016, 0.2))
		var tip := _pivot(w, Vector3(s * 0.34, 0, 0))
		_p(tip, LowPoly.box(), col.darkened(0.15), Vector3(s * 0.15, 0, 0.02), Vector3(0.3, 0.012, 0.16))
		for f in 3:   # splayed primaries
			_p(tip, LowPoly.box(0.0), Color(0.16, 0.12, 0.1), Vector3(s * 0.31, 0, -0.04 + f * 0.05), Vector3(0.1, 0.008, 0.03), Vector3(0, s * (0.25 - f * 0.25), 0))
		wings.append(w)
		parts["tip%d" % wings.size()] = tip


func _build_woodpecker() -> void:
	var black := Color(0.08, 0.08, 0.09)
	var white := Color(0.94, 0.93, 0.9)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(6, 4), black, Vector3(0, 0.05, 0.01), Vector3(0.065, 0.065, 0.14))
	_p(body, LowPoly.sphere(5, 3), white, Vector3(0, 0.038, -0.01), Vector3(0.05, 0.045, 0.1))
	_p(body, LowPoly.box(0.0), white, Vector3(0, 0.08, 0.02), Vector3(0.03, 0.006, 0.07))
	head = _pivot(body, Vector3(0, 0.08, -0.06))
	_p(head, LowPoly.sphere(5, 4), white, Vector3.ZERO, Vector3(0.045, 0.045, 0.05))
	_p(head, LowPoly.box(0.0), Color(0.85, 0.1, 0.1), Vector3(0, 0.02, 0.008), Vector3(0.03, 0.014, 0.04))
	_p(head, LowPoly.box(0.0), black, Vector3(0, 0.0, -0.012), Vector3(0.048, 0.01, 0.03))
	_p(head, LowPoly.cone(4), Color(0.3, 0.3, 0.32), Vector3(0, 0, -0.045), Vector3(0.012, 0.045, 0.012), Vector3(-PI / 2, 0, 0))
	tail = _pivot(body, Vector3(0, 0.04, 0.07))
	_p(tail, LowPoly.box(), black, Vector3(0, -0.01, 0.035), Vector3(0.03, 0.008, 0.07), Vector3(0.5, 0, 0))
	for s in [-1, 1]:
		var w := _pivot(body, Vector3(s * 0.03, 0.065, 0.0))
		_p(w, LowPoly.box(), black, Vector3(s * 0.05, 0, 0.012), Vector3(0.1, 0.006, 0.06))
		_p(w, LowPoly.box(0.0), white, Vector3(s * 0.05, 0.004, 0.012), Vector3(0.06, 0.003, 0.02))
		wings.append(w)


func _build_crow() -> void:
	var black := Color(0.06, 0.06, 0.08)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(7, 4), black, Vector3(0, 0.17, 0.02), Vector3(0.15, 0.15, 0.3))
	head = _pivot(body, Vector3(0, 0.26, -0.12))
	_p(head, LowPoly.sphere(6, 4), black.lightened(0.04), Vector3.ZERO, Vector3(0.1, 0.095, 0.11))
	_p(head, LowPoly.cone(4), Color(0.12, 0.12, 0.13), Vector3(0, -0.008, -0.08), Vector3(0.035, 0.09, 0.035), Vector3(-PI / 2, PI / 4, 0))
	for s in [-1, 1]:
		_p(head, LowPoly.box(0.0), Color(0.5, 0.5, 0.55), Vector3(s * 0.045, 0.012, -0.03), Vector3.ONE * 0.012)
		var w := _pivot(body, Vector3(s * 0.07, 0.2, 0.0))
		_p(w, LowPoly.box(), black.lightened(0.03), Vector3(s * 0.14, 0, 0.03), Vector3(0.28, 0.012, 0.16))
		_p(w, LowPoly.box(0.0), black, Vector3(s * 0.33, 0, 0.04), Vector3(0.14, 0.008, 0.12), Vector3(0, s * -0.2, 0))
		wings.append(w)
	tail = _pivot(body, Vector3(0, 0.17, 0.15))
	_p(tail, LowPoly.box(), black, Vector3(0, 0, 0.07), Vector3(0.09, 0.012, 0.16))
	_leg(body, Vector3(0.035, 0.1, 0.01), 0.1, 0.014, Color(0.1, 0.1, 0.1))
	_leg(body, Vector3(-0.035, 0.1, 0.01), 0.1, 0.014, Color(0.1, 0.1, 0.1))


func _build_lizard() -> void:
	var col := Color(0.4, 0.5, 0.3) if rng.randf() < 0.5 else Color(0.5, 0.42, 0.32)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.box(), col, Vector3(0, 0.012, 0), Vector3(0.022, 0.014, 0.07))
	_p(body, LowPoly.box(0.0), col.lightened(0.2), Vector3(0, 0.02, 0), Vector3(0.008, 0.002, 0.06))
	head = _pivot(body, Vector3(0, 0.014, -0.038))
	_p(head, LowPoly.cone(4), col.lightened(0.05), Vector3(0, 0, -0.014), Vector3(0.022, 0.034, 0.014), Vector3(-PI / 2, PI / 4, 0))
	for s in [-1, 1]:
		_p(head, LowPoly.box(0.0), Color(0.03, 0.03, 0.03), Vector3(s * 0.008, 0.005, -0.008), Vector3.ONE * 0.004)
	# tail in three segments so it can whip
	var prev: Node3D = _pivot(body, Vector3(0, 0.012, 0.034))
	tail = prev
	for k in 3:
		var w := 0.014 - k * 0.004
		_p(prev, LowPoly.box(), col.darkened(0.05 * k), Vector3(0, 0, 0.018), Vector3(w, w * 0.7, 0.038))
		var nxt := _pivot(prev, Vector3(0, 0, 0.036))
		parts["t%d" % k] = prev
		prev = nxt
	for k in 4:
		var s := -1.0 if k % 2 == 0 else 1.0
		var z := -0.022 if k < 2 else 0.024
		var l := _pivot(body, Vector3(s * 0.011, 0.01, z))
		_p(l, LowPoly.box(0.0), col.darkened(0.1), Vector3(s * 0.012, -0.004, 0), Vector3(0.024, 0.005, 0.006))
		legs.append(l)


func _build_owl() -> void:
	var col := Color(0.5, 0.4, 0.28)
	var pale := Color(0.86, 0.8, 0.68)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(7, 4), col, Vector3(0, 0.15, 0), Vector3(0.2, 0.3, 0.19))
	_p(body, LowPoly.sphere(5, 3), pale, Vector3(0, 0.13, -0.03), Vector3(0.16, 0.22, 0.15))
	head = _pivot(body, Vector3(0, 0.31, -0.01))
	_p(head, LowPoly.sphere(7, 4), col.lightened(0.05), Vector3.ZERO, Vector3(0.19, 0.16, 0.17))
	_p(head, LowPoly.cone(4), Color(0.85, 0.7, 0.3), Vector3(0, -0.02, -0.085), Vector3(0.025, 0.04, 0.025), Vector3(-PI / 2 - 0.6, 0, 0))
	for s in [-1, 1]:
		_p(head, LowPoly.cyl(0.5, 0.5, 6), pale, Vector3(s * 0.045, 0.012, -0.075), Vector3(0.07, 0.01, 0.07), Vector3(PI / 2, 0, 0))
		var eye := LowPoly.part(head, LowPoly.cyl(0.5, 0.5, 6), Color(1.0, 0.75, 0.1), Vector3(s * 0.045, 0.012, -0.082), Vector3(0.04, 0.008, 0.04), Vector3(PI / 2, 0, 0), 0.6)
		_p(head, LowPoly.box(0.0), Color(0.02, 0.02, 0.02), Vector3(s * 0.045, 0.012, -0.087), Vector3(0.018, 0.018, 0.004))
		parts["lid%d" % (0 if s < 0 else 1)] = _p(head, LowPoly.box(0.0), col.lightened(0.1), Vector3(s * 0.045, 0.03, -0.089), Vector3(0.05, 0.03, 0.006))
		parts["eye%d" % (0 if s < 0 else 1)] = eye
		_p(head, LowPoly.cone(3), col, Vector3(s * 0.07, 0.09, 0.0), Vector3(0.03, 0.06, 0.02), Vector3(0, 0, -s * 0.3))
		var w := _pivot(body, Vector3(s * 0.09, 0.24, 0.0))
		_p(w, LowPoly.box(), col.darkened(0.1), Vector3(s * 0.2, 0, 0.02), Vector3(0.4, 0.014, 0.2))
		_p(w, LowPoly.box(0.0), col.darkened(0.2), Vector3(s * 0.46, 0, 0.03), Vector3(0.16, 0.01, 0.15))
		wings.append(w)
	tail = _pivot(body, Vector3(0, 0.04, 0.07))
	_p(tail, LowPoly.box(), col.darkened(0.15), Vector3(0, -0.02, 0.03), Vector3(0.1, 0.1, 0.02), Vector3(0.3, 0, 0))


func _build_bat() -> void:
	var col := Color(0.14, 0.11, 0.12)
	body = _pivot(self, Vector3.ZERO)
	_p(body, LowPoly.sphere(5, 3), col.lightened(0.08), Vector3.ZERO, Vector3(0.035, 0.03, 0.06))
	for s in [-1, 1]:
		_p(body, LowPoly.cone(3), col, Vector3(s * 0.012, 0.02, -0.025), Vector3(0.012, 0.022, 0.008))
		var w := _pivot(body, Vector3(s * 0.012, 0.005, 0.0))
		_p(w, LowPoly.box(0.0), col, Vector3(s * 0.06, 0, 0.008), Vector3(0.12, 0.002, 0.07))
		_p(w, LowPoly.box(0.0), col.darkened(0.2), Vector3(s * 0.14, 0, 0.0), Vector3(0.06, 0.002, 0.045), Vector3(0, s * -0.4, 0))
		wings.append(w)


# ------------------------------------------------------------------ shared moves
func _flap(rate: float, amp: float, bias := 0.0) -> void:
	var f := sin(Time.get_ticks_msec() * 0.001 * rate) * amp + bias
	for i in wings.size():
		wings[i].rotation.z = f * (1.0 if i % 2 == 0 else -1.0)
		wings[i].scale.x = 1.0


## wings shut: swung down against the body and drawn in (ducks' wings are already modelled folded)
func _fold(dt: float, ang := -1.0) -> void:
	if ang < 0.0:
		ang = 0.0 if kind == "duck" else 1.4
	var sx := 1.0 if kind == "duck" else 0.5
	for i in wings.size():
		wings[i].rotation.z = LowPoly.damp(wings[i].rotation.z, ang * (1.0 if i % 2 == 0 else -1.0), 12.0, dt)
		wings[i].scale.x = LowPoly.damp(wings[i].scale.x, sx, 12.0, dt)


## straight-ish flight from fly_from to target with an arc. returns true when it arrives
func _fly_step(dt: float, arc: float, rate: float, amp: float) -> bool:
	fly_t += dt / fly_dur
	var k := clampf(fly_t, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var p := fly_from.lerp(target, e)
	p.y += sin(k * PI) * arc
	var d := p - position
	if d.length() > 0.0005:
		yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-10.0 * dt))
		body.rotation.x = LowPoly.damp(body.rotation.x, clampf(d.y / maxf(d.length(), 0.001), -0.6, 0.6), 6.0, dt)
	position = p
	_flap(rate, amp)
	return k >= 1.0


func _launch(to: Vector3, speed_: float, min_t := 0.5) -> void:
	fly_from = position
	target = to
	fly_t = 0.0
	fly_dur = maxf(min_t, fly_from.distance_to(to) / speed_)


func _best_perch(away: Vector3, min_d: float, max_d: float, min_h := 0.0) -> Vector3:
	var best := Vector3.ZERO
	var best_s := -1e9
	for i in 14:
		if ForestLevel.perches.is_empty():
			break
		var p: Vector3 = ForestLevel.perches[rng.randi() % ForestLevel.perches.size()]
		var off := p - position
		var dist := off.length()
		if dist < min_d or dist > max_d or p.y - _ground_y(p.x, p.z) < min_h:
			continue
		var s := Vector3(off.x, 0, off.z).normalized().dot(away) * 3.0 + p.y * 0.3 - dist * 0.06 + rng.randf()
		if s > best_s:
			best_s = s
			best = p
	if best == Vector3.ZERO:
		best = position + away * 6.0 + Vector3(0, 3.0, 0)
	return best


func _pond_point(away_from := Vector3.INF) -> Vector3:
	var c := Vector3(ForestLevel.POND.x, ForestLevel.WATER_Y, ForestLevel.POND.y)
	var r := ForestLevel.POND_R - 1.7
	if away_from != Vector3.INF:
		var d := c - away_from
		d.y = 0
		if d.length() > 0.1:
			return c + d.normalized() * r * rng.randf_range(0.7, 1.0) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	var a := rng.randf() * TAU
	return c + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * r


func _cat_at_pond(th: Array) -> float:
	# how far the cat is from the water's edge of the pond (negative = in it)
	var c := _cat()
	if c == null:
		return 99.0
	return Vector2(c.global_position.x, c.global_position.z).distance_to(ForestLevel.POND) - ForestLevel.POND_R


func _swim(dest: Vector3, spd: float, dt: float) -> float:
	var d := dest - position
	d.y = 0
	var dist := d.length()
	if dist < 0.06:
		speed = LowPoly.damp(speed, 0.0, 4.0, dt)
	else:
		speed = LowPoly.damp(speed, spd, 3.0, dt)
		yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-3.5 * dt))
	position += Vector3(-sin(yaw), 0, -cos(yaw)) * speed * dt
	position.y = ForestLevel.WATER_Y + sin(Time.get_ticks_msec() * 0.002 + home.x) * 0.006
	cool -= dt * (0.3 + speed * 2.0)
	if cool < 0.0 and speed > 0.2:
		cool = 0.5
		Water.splash(position, 0.12 if kind == "duckling" else 0.22)
	return dist


# ---------------- duck
func _think_duck(dt: float, th: Array) -> void:
	var d: float = th[0]
	var edge := _cat_at_pond(th)
	var c := _cat()
	match state:
		"paddle", "dabble", "rest":
			_fold(dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, 1.25 if state == "dabble" else 0.0, 4.0, dt)
			body.position.y = LowPoly.damp(body.position.y, 0.06 if state == "dabble" else 0.0, 4.0, dt)
			head.rotation.y = 0.0 if state != "rest" else sin(Time.get_ticks_msec() * 0.0015 + home.z) * 0.7
			if state == "paddle":
				if _swim(target, 0.35, dt) < 0.15:
					state_t = -1.0
			else:
				_swim(position, 0.0, dt)
				if state == "dabble":
					tail.rotation.x = sin(Time.get_ticks_msec() * 0.02) * 0.3
			if d < 2.2 or (edge < 0.3 and d < 4.0):
				_take_off(th)
			elif edge < 5.0:
				_set_state("wary", rng.randf_range(2.0, 4.0))
				target = _pond_point(c.global_position)
			elif state_t < 0.0:
				var roll := rng.randf()
				if roll < 0.4:
					_set_state("dabble", rng.randf_range(2.0, 4.5))
					Water.splash(position, 0.3)
				elif roll < 0.8:
					target = _pond_point()
					_set_state("paddle", 12.0)
				else:
					_set_state("rest", rng.randf_range(2.0, 5.0))
		"wary":
			# head up, drift to the far side, keep the cat in one eye
			_fold(dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, -0.08, 6.0, dt)
			body.position.y = LowPoly.damp(body.position.y, 0.0, 6.0, dt)
			_swim(target, 0.7, dt)
			if c:
				var to := c.global_position - global_position
				head.rotation.y = clampf(wrapf(atan2(-to.x, -to.z) - yaw, -PI, PI), -1.3, 1.3)
			if d < 2.2 or (edge < 0.2 and d < 4.5):
				_take_off(th)
			elif state_t < 0.0:
				if edge < 5.0:
					target = _pond_point(c.global_position)
					state_t = rng.randf_range(2.0, 4.0)
				else:
					head.rotation.y = 0.0
					_set_state("rest", 2.0)
		"takeoff":
			# pattering run across the water, wings thrashing
			fly_t += dt
			speed = LowPoly.damp(speed, 4.5, 4.0, dt)
			position += Vector3(-sin(yaw), 0, -cos(yaw)) * speed * dt
			position.y = ForestLevel.WATER_Y + fly_t * fly_t * 1.6
			body.rotation.x = -0.3
			_flap(34.0, 1.1)
			cool -= dt
			if cool < 0.0 and fly_t < 0.6:
				cool = 0.12
				Water.splash(position, 0.5)
			if fly_t > 0.9:
				trunk_a = atan2(position.z - ForestLevel.POND.y, position.x - ForestLevel.POND.x)
				_set_state("circle", rng.randf_range(10.0, 14.0))
		"circle":
			trunk_a += dt * 0.55
			var r := 10.0
			var want := Vector3(ForestLevel.POND.x + cos(trunk_a) * r, 7.0 + sin(trunk_a * 2.0), ForestLevel.POND.y + sin(trunk_a) * r)
			var to := want - position
			position += to.limit_length(7.0 * dt)
			if to.length() > 0.01:
				yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 1.0 - exp(-4.0 * dt))
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 3.0, dt)
			_flap(26.0, 0.9)
			if state_t < 0.0 and (edge > 6.0 or state_t < -16.0):
				_launch(_pond_point(c.global_position if c else Vector3.INF), 6.0, 1.5)
				_set_state("land", 99.0)
		"land":
			if _fly_step(dt, 0.4, 24.0, 0.8):
				body.rotation.x = 0.0
				Water.splash(position, 1.0)
				_ears(0.6)
				speed = 1.2
				_set_state("rest", rng.randf_range(2.0, 4.0))


func _take_off(th: Array) -> void:
	var away: Vector3 = th[4]
	yaw = atan2(-away.x, -away.z)
	fly_t = 0.0
	cool = 0.0
	head.rotation.y = 0.0
	_ears(1.0)
	_shout()
	_set_state("takeoff", 99.0)


# ---------------- duckling
func _think_duckling(dt: float, th: Array) -> void:
	var d: float = th[0]
	var mum := leader
	while mum and mum.kind == "duckling" and mum.leader:
		mum = mum.leader
	var mum_gone := mum == null or mum.state in ["takeoff", "circle", "land"]
	head.position.y = 0.075 + sin(Time.get_ticks_msec() * 0.012 + rank) * 0.004
	if mum_gone or d < 1.2:
		if state != "hide":
			# nearest bit of bank that isn't where the cat is
			var c := Vector3(ForestLevel.POND.x, ForestLevel.WATER_Y, ForestLevel.POND.y)
			var out := position - c
			out.y = 0
			var away: Vector3 = th[4]
			out = (out.normalized() + away * 1.5).normalized()
			target = c + out * (ForestLevel.POND_R - 0.9)
			_set_state("hide", 99.0)
		if _swim(target, 1.1, dt) < 0.1:
			speed = 0.0
			body.position.y = -0.015   # tucked low in the reeds
		return
	body.position.y = LowPoly.damp(body.position.y, 0.0, 4.0, dt)
	if state == "hide":
		_set_state("paddle", 1.0)
	if leader:
		var back := Vector3(sin(leader.yaw), 0, cos(leader.yaw))
		var want := leader.position + back * (0.34 if leader.kind == "duck" else 0.2)
		var gap := want.distance_to(position)
		_swim(want, clampf(gap * 2.5, 0.0, 1.3), dt)
		if gap < 0.05:
			yaw = lerp_angle(yaw, leader.yaw, 1.0 - exp(-2.0 * dt))


# ---------------- dragonfly
func _think_dragonfly(dt: float, th: Array) -> void:
	_flap(260.0, 0.5)
	var c := _cat()
	var near := c != null and c.global_position.distance_to(position) < 0.75
	match state:
		"hover":
			# holds dead still in the air, tiny corrections
			position += Vector3(sin(Time.get_ticks_msec() * 0.011 + home.x), sin(Time.get_ticks_msec() * 0.017), cos(Time.get_ticks_msec() * 0.013)) * 0.012 * dt * 10.0
			if state_t < 0.0 or near:
				var p := Vector3.ZERO
				for i in 8:
					p = home + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
					if _ground_y(p.x, p.z) < ForestLevel.WATER_Y + 0.12:
						break
				p.y = maxf(_ground_y(p.x, p.z), ForestLevel.WATER_Y) + rng.randf_range(0.12, 0.7)
				if near:
					p = position + (position - c.global_position).normalized() * 2.0 + Vector3(0, 0.8, 0)
				_launch(p, 5.0 if near else rng.randf_range(2.5, 4.5), 0.15)
				_set_state("dart", 9.0)
		"dart":
			fly_t += dt / fly_dur
			var k := clampf(fly_t, 0.0, 1.0)
			var p := fly_from.lerp(target, 1.0 - (1.0 - k) * (1.0 - k))
			var d := p - position
			if d.length() > 0.001:
				yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-20.0 * dt))
			position = p
			if k >= 1.0:
				_set_state("hover", rng.randf_range(0.4, 2.2))


# ---------------- hedgehog
func _think_hedgehog(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var scared := d < 1.1 or (d < 2.6 and cs > 2.5)
	match state:
		"idle", "snuffle":
			curl = LowPoly.damp(curl, 0.0, 3.0, dt)
			if state == "snuffle":
				var rem := _move_toward(target, 0.28, dt, 3.0)
				head.rotation.y = sin(Time.get_ticks_msec() * 0.006) * 0.5
				head.rotation.x = 0.25 + sin(Time.get_ticks_msec() * 0.02) * 0.08
				if rem < 0.15 or state_t < 0.0:
					_set_state("idle", rng.randf_range(1.0, 3.0))
			else:
				speed = LowPoly.damp(speed, 0.0, 6.0, dt)
				head.rotation.x = LowPoly.damp(head.rotation.x, -0.15, 3.0, dt)
				if state_t < 0.0:
					_pick_wander(5.0)
					_set_state("snuffle", rng.randf_range(5.0, 12.0))
			if scared:
				_set_state("ball", 2.5)
				vel = Vector3.ZERO
		"ball":
			curl = LowPoly.damp(curl, 1.0, 14.0, dt)
			speed = 0.0
			# nudged: it rolls. the cat's nose, basically
			var c := _cat()
			if c and d < 0.3:
				var cv: Vector3 = c.get("velocity") if c.get("velocity") != null else Vector3.ZERO
				var away: Vector3 = th[4]
				vel = away * maxf(Vector3(cv.x, 0, cv.z).length() * 0.8, 0.5)
			# and rolls a little further on slopes
			var gx := _ground_y(position.x + 0.2, position.z) - _ground_y(position.x - 0.2, position.z)
			var gz := _ground_y(position.x, position.z + 0.2) - _ground_y(position.x, position.z - 0.2)
			vel += Vector3(-gx, 0, -gz) * 6.0 * dt
			vel = vel.lerp(Vector3.ZERO, 1.0 - exp(-1.6 * dt))
			position += vel * dt
			position.x = clampf(position.x, -35, 35)
			position.z = clampf(position.z, -35, 35)
			if vel.length() > 0.05:
				yaw = atan2(-vel.x, -vel.z)
				phase += vel.length() * dt / 0.07
			if d < 2.0 or vel.length() > 0.1:
				state_t = maxf(state_t, 2.0)
			if state_t < 0.0:
				# one eye first: uncurl halfway, check, then carry on
				_set_state("peek", 1.4)
		"peek":
			curl = LowPoly.damp(curl, 0.45, 3.0, dt)
			if scared:
				_set_state("ball", 2.5)
			elif state_t < 0.0:
				phase = 0.0
				_set_state("idle", 0.6)
	_snap_ground(dt)
	_walk_anim(dt, 0.07, 0.7)
	# curl pose: body rounds up, face + feet tuck away, spines bristle
	var ball := parts["ball"] as Node3D
	ball.scale = Vector3(0.15, 0.12, 0.22).lerp(Vector3(0.17, 0.165, 0.175), curl)
	ball.position.y = lerpf(0.065, 0.085, curl)
	(parts["spines"] as Node3D).scale = Vector3.ONE.lerp(Vector3(1.15, 1.45, 0.82), curl)
	(parts["spines"] as Node3D).position.y = lerpf(0.065, 0.085, curl)
	head.scale = Vector3.ONE * maxf(1.0 - curl * 1.2, 0.01)
	for l in legs:
		l.scale = Vector3.ONE * maxf(1.0 - curl * 1.5, 0.01)
	body.rotation.x = -phase if state == "ball" else 0.0
	body.position.y = 0.085 * curl * (1.0 - cos(phase)) * 0.0


# ---------------- grasshopper
func _think_hopper(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var c := _cat()
	match state:
		"sit":
			if c and d > 11.0:
				# out of sight: quietly move to the grass ahead of the cat so there's always some about
				var v: Vector3 = c.get("velocity") if c.get("velocity") != null else Vector3.ZERO
				var ahead := Vector3(v.x, 0, v.z).normalized() if Vector2(v.x, v.z).length() > 0.5 else Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU))
				var a := rng.randf_range(-1.0, 1.0)
				var p := c.global_position + ahead.rotated(Vector3.UP, a) * rng.randf_range(4.0, 8.0)
				p.x = clampf(p.x, -34, 34)
				p.z = clampf(p.z, -34, 34)
				var gy := _ground_y(p.x, p.z)
				if gy > ForestLevel.WATER_Y + 0.1 and ForestLevel.path_dist(p.x, p.z) > 0.8:
					position = Vector3(p.x, gy, p.z)
			var spring := (d < 0.6 and cs > 0.3) or d < 0.22
			if spring or state_t < 0.0:
				var dir: Vector3 = th[4] if spring else Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU))
				dir = dir.rotated(Vector3.UP, rng.randf_range(-0.8, 0.8))
				var pw := rng.randf_range(1.1, 1.9) if spring else rng.randf_range(0.4, 0.8)
				vel = dir * pw + Vector3(0, rng.randf_range(1.6, 2.4) * (1.0 if spring else 0.6), 0)
				yaw = atan2(-dir.x, -dir.z)
				for w in wings:
					(w.get_child(0) as Node3D).visible = true
				if spring:
					_ears(0.25)
				_set_state("jump", 3.0)
		"jump":
			vel.y -= 9.8 * dt
			position += vel * dt
			_flap(120.0, 0.7, 0.3)
			body.rotation.x = clampf(vel.y * 0.25, -0.8, 0.8)
			var gy := _ground_y(position.x, position.z)
			if position.y <= gy and vel.y < 0.0:
				position.y = gy
				body.rotation.x = 0.0
				for w in wings:
					(w.get_child(0) as Node3D).visible = false
				_set_state("sit", rng.randf_range(4.0, 14.0))


# ---------------- hawk
func _think_hawk(dt: float, th: Array) -> void:
	var m := ForestLevel.MEADOW
	match state:
		"soar":
			trunk_a += dt * 0.16
			var r := 15.0 + sin(trunk_a * 0.7) * 5.0
			var want := Vector3(m.x + cos(trunk_a) * r, 21.0 + sin(trunk_a * 1.3) * 3.0, m.y + 6.0 + sin(trunk_a) * r)
			var to := want - position
			position += to.limit_length(7.5 * dt)
			if to.length() > 0.01:
				var ny := atan2(-to.x, -to.z)
				body.rotation.z = LowPoly.damp(body.rotation.z, clampf(wrapf(ny - yaw, -PI, PI) * 4.0, -0.5, 0.5), 2.0, dt)
				yaw = lerp_angle(yaw, ny, 1.0 - exp(-2.0 * dt))
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 2.0, dt)
			# long glides, the odd lazy flap
			var fl := sin(Time.get_ticks_msec() * 0.006) * 0.35 if fmod(Time.get_ticks_msec() * 0.001, 9.0) < 1.6 else 0.12
			for i in wings.size():
				wings[i].rotation.z = LowPoly.damp(wings[i].rotation.z, fl * (1.0 if i == 0 else -1.0), 5.0, dt)
				(parts["tip%d" % (i + 1)] as Node3D).rotation.z = wings[i].rotation.z * 0.8
			if state_t < 0.0 and not _night():
				var prey := _pick_quarry()
				if prey:
					perch = prey.global_position
					leader = null
					set_meta("quarry", prey)
					_launch(perch + Vector3(0, 0.6, 0), 15.0, 1.6)
					_ears(1.0)
					_set_state("stoop", 99.0)
				else:
					state_t = rng.randf_range(10.0, 20.0)
		"stoop":
			# wings tucked, falling like a brick at whatever was sitting in the open
			var q: Node3D = get_meta("quarry") if has_meta("quarry") and is_instance_valid(get_meta("quarry")) else null
			if q and fly_t < 0.75:
				target = q.global_position + Vector3(0, 0.5, 0)
			fly_t += dt / fly_dur
			var k := clampf(fly_t, 0.0, 1.0)
			var p := fly_from.lerp(target, k * k)
			var d := p - position
			if d.length() > 0.001:
				yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-6.0 * dt))
				body.rotation.x = LowPoly.damp(body.rotation.x, clampf(d.y / d.length(), -1.2, 0.3), 5.0, dt)
			position = p
			for i in wings.size():
				wings[i].rotation.z = LowPoly.damp(wings[i].rotation.z, (-1.0 if i == 0 else 1.0) * 0.9, 6.0, dt)
			body.rotation.z = LowPoly.damp(body.rotation.z, 0.0, 4.0, dt)
			if fly_t > 0.3 and not has_meta("warned"):
				# everything on the ground sees it coming
				set_meta("warned", true)
				get_tree().call_group("wild", "alarmed", target, "hawk", self)
			var c := _cat()
			if k >= 1.0 or (c and c.global_position.distance_to(target) < 3.5 and k > 0.4):
				remove_meta("warned")
				_ears(0.8)
				_set_state("climb", 7.0)
		"climb":
			var want := Vector3(position.x - sin(yaw) * 4.0, 22.0, position.z - cos(yaw) * 4.0)
			var to := want - position
			position += to.limit_length(8.0 * dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.35, 3.0, dt)
			yaw += dt * 0.5
			_flap(9.0, 0.7)
			for i in wings.size():
				(parts["tip%d" % (i + 1)] as Node3D).rotation.z = wings[i].rotation.z * 0.8
			if state_t < 0.0 or position.y > 19.0:
				trunk_a = atan2(position.z - m.y - 6.0, position.x - m.x)
				_set_state("soar", rng.randf_range(45.0, 80.0))


func _pick_quarry() -> Critter:
	var c := _cat()
	var best: Critter = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("wild"):
		var cr := n as Critter
		if cr == null or cr.kind != "rabbit" or cr.state == "flee":
			continue
		if c and c.global_position.distance_to(cr.global_position) < 6.0:
			continue
		var dd := cr.global_position.distance_to(position)
		if dd < bd:
			bd = dd
			best = cr
	return best


# ---------------- woodpecker
func _pick_trunk(far := true) -> void:
	var best: Array = []
	var bs := -1e9
	for i in 10:
		if ForestLevel.trunks.is_empty():
			return
		var t: Array = ForestLevel.trunks[rng.randi() % ForestLevel.trunks.size()]
		var b: Vector3 = t[0]
		var dd := Vector2(b.x - position.x, b.z - position.z).length()
		if (t[2] as float) < 3.0 or (far and dd < 4.0) or dd > 22.0:
			continue
		var s := (dd if far else -dd) * 0.1 + rng.randf()
		if s > bs:
			bs = s
			best = t
	if best.is_empty():
		best = ForestLevel.trunks[0]
	climb_trunk = best
	trunk_a = rng.randf() * TAU
	cling_y = rng.randf_range(1.8, minf(3.6, (best[2] as float) - 0.3))
	if not far:
		position = _cling_pos()


func _cling_pos() -> Vector3:
	var b: Vector3 = climb_trunk[0]
	var r: float = climb_trunk[1]
	# trunks taper toward the top
	var rr := r * lerpf(1.0, 0.72, clampf(cling_y / maxf(climb_trunk[2], 0.1) * 0.55, 0.0, 1.0)) + 0.035
	return Vector3(b.x + cos(trunk_a) * rr, b.y + cling_y, b.z + sin(trunk_a) * rr)


func _think_woodpecker(dt: float, th: Array) -> void:
	var c := _cat()
	var near := c != null and c.global_position.distance_to(position) < 2.6
	match state:
		"scan", "drum", "hitch":
			_fold(dt)
			var b: Vector3 = climb_trunk[0]
			position = position.lerp(_cling_pos(), 1.0 - exp(-10.0 * dt))
			yaw = atan2(-(b.x - position.x), -(b.z - position.z))
			body.rotation.x = -PI * 0.5 + 0.25   # upright against the bark, propped on its tail
			if state == "drum":
				# a burst of ~18 hits a second, then a pause
				var hit := fmod(state_t, 1.8) < 0.7
				head.rotation.x = (0.45 if fmod(Time.get_ticks_msec() * 0.001, 0.055) < 0.027 else -0.1) if hit else LowPoly.damp(head.rotation.x, -0.2, 6.0, dt)
				cool -= dt
				if hit and cool < 0.0:
					cool = 1.8
					_ears(0.7)
			elif state == "hitch":
				cling_y += dt * 0.5
				trunk_a += dt * 0.6 * (1.0 if int(home.x * 10.0) % 2 == 0 else -1.0)
				body.position.y = absf(sin(Time.get_ticks_msec() * 0.02)) * 0.012
				if cling_y > (climb_trunk[2] as float) - 0.2:
					state_t = -1.0
			else:
				head.rotation.x = -0.2
				head.rotation.y = sin(Time.get_ticks_msec() * 0.004) * 0.9
			if near:
				_wp_fly()
			elif state_t < 0.0:
				head.rotation.y = 0.0
				body.position.y = 0.0
				var roll := rng.randf()
				if cling_y > (climb_trunk[2] as float) - 0.3 or roll < 0.12:
					_wp_fly()
				elif roll < 0.6:
					_set_state("drum", rng.randf_range(3.0, 6.0))
				elif roll < 0.85:
					_set_state("hitch", rng.randf_range(0.6, 1.4))
				else:
					_set_state("scan", rng.randf_range(1.0, 2.5))
		"fly":
			# woodpecker flight: flap, fold, flap, fold = a bouncing line through the trees
			fly_t += dt / fly_dur
			var k := clampf(fly_t, 0.0, 1.0)
			var p := fly_from.lerp(target, k)
			var bounce := sin(k * fly_dur * 7.0)
			p.y += sin(k * PI) * 0.8 + bounce * 0.18 * sin(k * PI)
			var d := p - position
			if d.length() > 0.001:
				yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-10.0 * dt))
			position = p
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 8.0, dt)
			if bounce > 0.0:
				_flap(60.0, 1.0)
			else:
				_fold(dt, 1.2)
			if k >= 1.0:
				_set_state("scan", rng.randf_range(1.0, 2.0))


func _wp_fly() -> void:
	head.rotation = Vector3.ZERO
	body.position.y = 0.0
	_pick_trunk(true)
	_launch(_cling_pos(), 6.5, 0.6)
	_set_state("fly", 99.0)


# ---------------- crow
func _think_crow(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var alt: float = th[3]
	var c := _cat()
	var bait := c != null and (alt > 1.3 or c.get("carried") != null)
	cool -= dt
	match state:
		"strut", "peck", "look":
			_fold(dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 6.0, dt)
			if state == "strut":
				var rem := _move_toward(target, 0.55, dt, 5.0)
				# head bobs back and forth with each step, like every corvid
				head.position.z = -0.12 + sin(phase) * 0.02
				if rem < 0.15:
					state_t = -1.0
			else:
				speed = LowPoly.damp(speed, 0.0, 8.0, dt)
				if state == "peck":
					head.rotation.x = 0.9 if fmod(state_t, 0.7) < 0.15 else 0.1
				elif c:
					var to := c.global_position - global_position
					head.rotation.x = -0.15
					head.rotation.y = clampf(wrapf(atan2(-to.x, -to.z) - yaw, -PI, PI), -1.4, 1.4)
			if d < 1.8 or (d < 4.5 and cs > 3.0):
				_crow_up(th, true)
			elif d < 3.8:
				# not scared, just not stupid: walk off at an angle, watching
				var away: Vector3 = th[4]
				target = position + away.rotated(Vector3.UP, 0.7 if int(home.z) % 2 == 0 else -0.7) * 2.5
				target.y = _ground_y(target.x, target.z)
				_set_state("sidle", 1.5)
			elif bait and d < 22.0 and cool < 0.0:
				_crow_up(th, false)
			elif state_t < 0.0:
				head.rotation = Vector3.ZERO
				var roll := rng.randf()
				if roll < 0.4:
					_pick_wander(4.0)
					_set_state("strut", 6.0)
				elif roll < 0.75:
					_set_state("peck", rng.randf_range(1.4, 3.0))
				else:
					_set_state("look", rng.randf_range(1.0, 2.5))
			_snap_ground(dt)
			_walk_anim(dt, 0.16, 0.5)
		"sidle":
			_fold(dt)
			_move_toward(target, 1.3 if d < 2.6 else 0.8, dt, 8.0)
			# a couple of two-footed hops when it wants to go quicker
			body.position.y = absf(sin(phase * 0.5)) * 0.03 if d < 2.6 else 0.0
			if c:
				var to := c.global_position - global_position
				head.rotation.y = clampf(wrapf(atan2(-to.x, -to.z) - yaw, -PI, PI), -1.5, 1.5)
			_snap_ground(dt)
			_walk_anim(dt, 0.16, 0.6)
			if d < 1.8 or (d < 4.5 and cs > 3.0):
				_crow_up(th, true)
			elif state_t < 0.0:
				body.position.y = 0.0
				_set_state("look", rng.randf_range(0.8, 2.0))
		"fly":
			if _fly_step(dt, maxf(1.0, fly_from.distance_to(target) * 0.15), 16.0, 0.9):
				body.rotation.x = 0.0
				_set_state("perched", rng.randf_range(5.0, 10.0))
				cool = rng.randf_range(2.0, 6.0)
		"perched":
			_fold(dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 6.0, dt)
			if c:
				var to := c.global_position - global_position
				_face(c.global_position, dt, 2.0)
				head.rotation.x = clampf(-to.y * 0.15, -0.3, 0.8)
			if bait and d < 24.0:
				# cawing: lean forward, bill open, tail pumps
				if fmod(Time.get_ticks_msec() * 0.001 + home.x, 2.6) < 0.5:
					body.rotation.x = 0.35
					tail.rotation.x = -0.4
					if cool < 0.0:
						_ears(0.9)
						cool = 0.6
				else:
					tail.rotation.x = 0.0
				state_t = maxf(state_t, 1.0)
				if rng.randf() < dt * 0.14 and c:
					# swoop: a pass just over the cat's head, out the other side to a new perch
					perch = _best_perch((c.global_position - position).normalized(), 5.0, 26.0, 1.5)
					_launch(c.global_position + Vector3(0, 0.55, 0), 9.0, 0.8)
					_set_state("swoop", 99.0)
			elif c and c.global_position.distance_to(position) < 1.6:
				_crow_up(th, true)
			elif state_t < 0.0 and d > 6.0:
				_pick_wander(5.0)
				_launch(target, 5.0, 0.9)
				_set_state("fly_down", 99.0)
		"swoop":
			if c and fly_t < 0.8:
				target = c.global_position + Vector3(0, 0.55, 0)
			if _fly_step(dt, -0.3, 14.0, 0.7):
				_ears(1.0)
				_launch(perch, 8.0, 0.8)
				_set_state("fly", 99.0)
		"fly_down":
			if _fly_step(dt, 0.5, 15.0, 0.8):
				body.rotation.x = 0.0
				_set_state("look", rng.randf_range(1.0, 2.0))


func _crow_up(th: Array, scared: bool) -> void:
	var away: Vector3 = th[4]
	head.rotation = Vector3.ZERO
	body.position.y = 0.0
	var c := _cat()
	# scared: get away. mobbing: get somewhere with a view of the cat
	var p := _best_perch(away if scared else -away, 3.0, 20.0, 1.2)
	if not scared and c:
		var best := 1e9
		for i in 16:
			var q: Vector3 = ForestLevel.perches[rng.randi() % ForestLevel.perches.size()]
			var dq := q.distance_to(c.global_position)
			if dq > 3.0 and dq < best and q.y - _ground_y(q.x, q.z) > 1.2:
				best = dq
				p = q
	_launch(p, 6.5, 0.7)
	if scared:
		_ears(0.8)
		_shout()
	_set_state("fly", 99.0)


# ---------------- lizard
func _think_lizard(dt: float, th: Array) -> void:
	var d: float = th[0]
	var cs: float = th[1]
	var crouched: bool = th[2]
	var spook := 1.2 if (crouched and cs < 0.8) else 2.4
	# the tail trails behind in a lazy s
	for k in 3:
		(parts["t%d" % k] as Node3D).rotation.y = sin(Time.get_ticks_msec() * 0.004 - k * 0.9) * 0.2 + sin(phase - k * 1.2) * 0.35 * clampf(speed, 0.0, 1.0)
	match state:
		"bask":
			speed = 0.0
			position = position.lerp(home, 1.0 - exp(-3.0 * dt))
			# push-ups: what basking lizards do
			body.position.y = maxf(sin(Time.get_ticks_msec() * 0.012), 0.0) * 0.006 if fmod(state_t, 6.0) < 1.2 else 0.0
			head.rotation.x = -0.25
			if d < spook:
				var away: Vector3 = th[4]
				target = home + away * 0.55
				target.y = _ground_y(target.x, target.z)
				_set_state("skitter", 0.25)
			elif state_t < 0.0:
				state_t = rng.randf_range(4.0, 9.0)
		"skitter":
			# bursts with dead stops between, like the real thing
			var burst := fmod(Time.get_ticks_msec() * 0.001 + home.x, 0.5) < 0.32
			var to := target - position
			speed = 2.6 if burst and to.length() > 0.03 else 0.0
			if speed > 0.0:
				yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 1.0 - exp(-25.0 * dt))
				position += to.limit_length(speed * dt)
				phase += dt * 40.0
			for i in legs.size():
				legs[i].rotation.y = sin(phase + (0.0 if i % 3 == 0 else PI)) * 0.6 * clampf(speed, 0.0, 1.0)
			if to.length() < 0.04:
				_set_state("hide", rng.randf_range(4.0, 7.0))
		"hide":
			speed = 0.0
			body.position.y = 0.0
			if d < 0.5:
				# found: one more dash round the rock
				var away: Vector3 = th[4]
				target = home + away.rotated(Vector3.UP, 1.8) * 0.6
				target.y = _ground_y(target.x, target.z)
				_set_state("skitter", 0.2)
			elif state_t < 0.0 and d > 3.5:
				target = home
				_set_state("return", 9.0)
		"return":
			var burst := fmod(Time.get_ticks_msec() * 0.001 + home.z, 0.9) < 0.3
			var to := target - position
			speed = 1.2 if burst else 0.0
			if speed > 0.0:
				yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 1.0 - exp(-20.0 * dt))
				position += to.limit_length(speed * dt)
				phase += dt * 30.0
			if d < spook:
				var away: Vector3 = th[4]
				target = home + away * 0.55
				target.y = _ground_y(target.x, target.z)
				_set_state("skitter", 0.2)
			elif to.length() < 0.03 or state_t < 0.0:
				_set_state("bask", rng.randf_range(4.0, 9.0))


# ---------------- owl
func _think_owl(dt: float, th: Array) -> void:
	var c := _cat()
	var night := _night()
	var open := 0.0
	match state:
		"doze":
			_fold(dt)
			body.rotation.x = LowPoly.damp(body.rotation.x, 0.0, 5.0, dt)
			position = position.lerp(home, 1.0 - exp(-4.0 * dt))
			var close := c != null and c.global_position.distance_to(position) < 7.0
			open = 1.0 if night else (0.55 if close else 0.08)
			if c and (close or night):
				# the head swivels to follow the cat, the body doesn't bother
				var to := c.global_position - global_position
				var want := clampf(wrapf(atan2(-to.x, -to.z) - yaw, -PI, PI), -2.3, 2.3)
				head.rotation.y = LowPoly.damp(head.rotation.y, want, 3.0, dt)
				head.rotation.x = LowPoly.damp(head.rotation.x, clampf(-to.y / maxf(to.length(), 0.1), -0.2, 0.7), 3.0, dt)
			else:
				head.rotation.y = LowPoly.damp(head.rotation.y, 0.0, 1.0, dt)
				head.rotation.x = LowPoly.damp(head.rotation.x, 0.12, 1.0, dt)
			if c and c.global_position.distance_to(position) < 1.5:
				_owl_fly(_best_perch((position - c.global_position).normalized(), 6.0, 26.0, 3.0))
			elif night and state_t < 0.0:
				_owl_fly(_best_perch(Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)), 6.0, 28.0, 2.5))
			elif state_t < 0.0:
				state_t = rng.randf_range(3.0, 8.0)
		"fly":
			open = 1.0
			head.rotation = Vector3.ZERO
			# slow deep wingbeats, low between the trunks, a swoop up to the perch at the end
			if _fly_step(dt, -1.2, 7.0, 0.75):
				body.rotation.x = 0.0
				home = position
				yaw += PI
				_set_state("doze", rng.randf_range(9.0, 20.0) if night else 5.0)
	for i in 2:
		var lid := parts["lid%d" % i] as Node3D
		var blink := 1.0 if fmod(Time.get_ticks_msec() * 0.001 + home.x, 5.3) < 0.12 else 0.0
		var shut := clampf(1.0 - open + blink, 0.0, 1.0)
		lid.scale.y = 0.004 + 0.046 * shut
		lid.position.y = 0.036 - 0.023 * shut


func _owl_fly(to: Vector3) -> void:
	_launch(to, 5.5, 1.0)
	_set_state("fly", 99.0)


# ---------------- bat
func _think_bat(dt: float, th: Array) -> void:
	var dusk := atmos != null and (atmos.hour > 19.0 or atmos.hour < 5.4)
	if not dusk:
		visible = false
		return
	visible = true
	_flap(75.0, 0.9)
	# erratic loops: chase a target that keeps jumping (that's the moth it's after)
	if state_t < 0.0 or position.distance_to(target) < 0.6:
		target = home + Vector3(rng.randf_range(-9, 9), rng.randf_range(2.0, 7.0), rng.randf_range(-9, 9))
		target.y += _ground_y(target.x, target.z)
		state_t = rng.randf_range(0.4, 1.4)
	var to := target - position
	var want := to.normalized() * 6.5 + Vector3(0, sin(Time.get_ticks_msec() * 0.02 + home.x) * 2.0, 0)
	var c := _cat()
	if c and c.global_position.distance_to(position) < 1.5:
		want += (position - c.global_position).normalized() * 8.0
	vel = vel.lerp(want, 1.0 - exp(-3.5 * dt))
	position += vel * dt
	position.y = maxf(position.y, _ground_y(position.x, position.z) + 1.0)
	if vel.length() > 0.1:
		yaw = lerp_angle(yaw, atan2(-vel.x, -vel.z), 1.0 - exp(-8.0 * dt))
		body.rotation.z = clampf(-vel.cross(Vector3.UP).dot(want - vel) * 0.02, -0.7, 0.7)


# ------------------------------------------------------------------ spawning
static func spawn_all(parent: Node3D, sky: Atmos = null) -> Array:
	atmos = sky
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var add := func(k: String, p: Vector3, meta := {}) -> Fauna:
		var c := Fauna.new()
		c.kind = k
		c.home = Vector3(p.x, p.y if p.y != 0.0 else ForestLevel.height(p.x, p.z), p.z)
		for key in meta:
			c.set_meta(key, meta[key])
		parent.add_child(c)
		out.append(c)
		return c
	var pond := ForestLevel.POND
	# the duck family
	var hen: Fauna = add.call("duck", Vector3(pond.x - 1.0, 0, pond.y + 0.5), {"drake": false})
	add.call("duck", Vector3(pond.x + 1.2, 0, pond.y - 1.0), {"drake": true})
	var prev: Fauna = hen
	for k in 5:
		var dl: Fauna = add.call("duckling", Vector3(pond.x - 1.0, 0, pond.y + 0.8 + k * 0.2))
		dl.leader = prev
		dl.rank = k
		prev = dl
	# dragonflies over the pond + along the stream
	for k in 4:
		var a := rng.randf() * TAU
		add.call("dragonfly", Vector3(pond.x + cos(a) * 3.0, 0, pond.y + sin(a) * 3.0))
	for x in [-14.0, -3.0, 6.0]:
		add.call("dragonfly", Vector3(x, 0, ForestLevel.stream_z(x)))
	add.call("hedgehog", Vector3(-3.5, 0, 25.0))
	add.call("hedgehog", Vector3(9.0, 0, -9.0))
	add.call("hedgehog", Vector3(-18.0, 0, 12.0))
	# grasshoppers start near the gate, then keep relocating to wherever the cat is headed
	for k in 14:
		add.call("hopper", Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(22, 32)))
	add.call("hawk", Vector3(ForestLevel.MEADOW.x + 12.0, 21.0, ForestLevel.MEADOW.y))
	add.call("woodpecker", Vector3(-6.0, 0, 16.0))
	add.call("woodpecker", Vector3(10.0, 0, -2.0))
	for p in [Vector2(3.0, 15.0), Vector2(4.5, 14.0), Vector2(2.5, 13.0), Vector2(-9.0, -14.0)]:
		add.call("crow", Vector3(p.x, 0, p.y))
	# lizards on low sunny rocks / stumps / logs
	var spots := 0
	for i in ForestLevel.perches.size():
		var p: Vector3 = ForestLevel.perches[(i * 7 + 3) % ForestLevel.perches.size()]
		var up := p.y - ForestLevel.height(p.x, p.z)
		if up < 0.12 or up > 0.9 or ForestLevel.height(p.x, p.z) < ForestLevel.WATER_Y + 0.1:
			continue
		add.call("lizard", p)
		spots += 1
		if spots >= 7:
			break
	# owls high up, bats over the meadow + the pond
	var owls := 0
	for i in ForestLevel.perches.size():
		var p: Vector3 = ForestLevel.perches[(i * 11 + 5) % ForestLevel.perches.size()]
		if p.y - ForestLevel.height(p.x, p.z) < 3.2 or Vector2(p.x, p.z).length() > 26.0:
			continue
		add.call("owl", p)
		owls += 1
		if owls >= 2:
			break
	for k in 5:
		var c := ForestLevel.MEADOW if k < 3 else pond
		add.call("bat", Vector3(c.x + rng.randf_range(-4, 4), ForestLevel.height(c.x, c.y) + 4.0, c.y + rng.randf_range(-4, 4)))
	return out
