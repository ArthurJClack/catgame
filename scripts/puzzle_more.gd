class_name MorePuzzles
extends RefCounted
## one cat puzzle for each level that had none (simplify pass item 10, 2026-11-21). all three
## use verbs the cat already has and the world answers with a chime + treats, no words:
##   forest  the crow's shiny   a crow left a bottle cap on the deer stand platform (3 m). climb
##                              the ladder, swat it off: it rings off a rock below.
##   trail   the boulder        a treat bag on top of a tall rough boulder by the rock garden.
##                              climb or leap up, knock it off.
##   city    the warm vent      a steaming grate on the s main st sidewalk. sit still on it in
##                              the rain and warm up.
## knock offs share one tick (a prop that fell far enough and settled); the vent is a sit spot
## like the barn sunbeam. Puzzles.forest / trail / city build them and add cat sense points.

var z                          # the Puzzles node (untyped: Puzzles <-> MorePuzzles would cycle)
var knocks := []               # [{rb, id, peak, done, spill}]
var sits := []                 # [{pos, id, t, done, r}]

const SIT_T := 2.0
const DROP := 1.2              # a knock off counts once it fell this far and stopped


static func make(zz) -> MorePuzzles:
	var m := MorePuzzles.new()
	m.z = zz
	return m


func knock(rb: RigidBody3D, id: String, spill := 5) -> void:
	knocks.append({"rb": rb, "id": id, "peak": rb.global_position.y, "done": false, "spill": spill})


func sit(pos: Vector3, id: String, r := 0.35) -> void:
	sits.append({"pos": pos, "id": id, "t": 0.0, "done": false, "r": r})


func tick(dt: float) -> void:
	var player: CatPlayer = z.player
	for k in knocks:
		if k.done or not is_instance_valid(k.rb):
			continue
		var rb: RigidBody3D = k.rb
		var y := rb.global_position.y
		k.peak = maxf(k.peak, y)
		if k.peak - y > DROP and rb.linear_velocity.length() < 0.4:
			k.done = true
			var at := rb.global_position
			z._play("crash", at, 0.8, 1.6)
			z._spill(at, k.spill, 0.4)
			z._solve(k.id, at)
	for s in sits:
		if s.done:
			continue
		var d: Vector3 = player.global_position - s.pos
		var on: bool = Vector2(d.x, d.z).length() < s.r and absf(d.y) < 0.35
		var still := Vector2(player.velocity.x, player.velocity.z).length() < 0.3 and player.is_on_floor()
		s.t = s.t + dt if (on and still) else maxf(s.t - dt * 2.0, 0.0)
		if s.t >= SIT_T:
			s.done = true
			z._spill(s.pos + Vector3(0.4, 0, 0), 3, 0.12)
			z._solve(s.id, s.pos)


# ---------------------------------------------------------------- props

## a small shiny thing (bottle cap) a cat can swat off a ledge
func shiny(pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "Shiny"
	rb.mass = 0.05
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.03
	cy.height = 0.012
	cs.shape = cy
	rb.add_child(cs)
	rb.position = pos + Vector3(0, 0.01, 0)
	z.add_child(rb)
	LowPoly.part(rb, LowPoly.cyl(0.5, 0.5, 8), Color(0.85, 0.82, 0.7), Vector3.ZERO, Vector3(0.06, 0.012, 0.06), Vector3.ZERO, 0.9)
	rb.set_meta("loud", true)
	return rb


## tall rough stone the cat can climb, standing on the ground at `base`
func boulder(base: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "Boulder"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = base + Vector3(0, size.y * 0.5, 0)
	sb.set_meta("surface", "stone")
	sb.add_to_group("climbable")
	z.add_child(sb)
	# looks: two faceted lumps of weathered stone (the collider stays a simple box) with a
	# mossy cap, so it reads as a rock and not a fridge
	LowPoly.part(sb, LowPoly.sphere(7, 5), Color(0.44, 0.43, 0.4), Vector3(0, -size.y * 0.18, 0), Vector3(size.x * 1.25, size.y * 0.75, size.z * 1.25), Vector3(0, 0.4, 0))
	LowPoly.part(sb, LowPoly.sphere(6, 4), Color(0.5, 0.49, 0.45), Vector3(0.04, size.y * 0.22, -0.03), Vector3(size.x * 1.05, size.y * 0.62, size.z * 1.0), Vector3(0, 1.1, 0))
	LowPoly.part(sb, LowPoly.sphere(6, 3), Color(0.36, 0.45, 0.28), Vector3(0.03, size.y * 0.47, 0), Vector3(size.x * 0.8, 0.1, size.z * 0.75))
	return sb


## a steaming grate set in the pavement
func vent(at: Vector3) -> void:
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.62, 0.012, 0.62)
	g.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.12, 0.13)
	m.metallic = 0.6
	m.roughness = 0.5
	g.material_override = m
	g.position = at + Vector3(0, 0.006, 0)
	z.add_child(g)
	for i in 5:
		var bar := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(0.6, 0.016, 0.03)
		bar.mesh = b2
		bar.material_override = m
		bar.position = at + Vector3(0, 0.012, -0.24 + i * 0.12)
		z.add_child(bar)
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.28, 0.01, 0.28)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0, 0.05, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	qm.material = sm
	p.mesh = qm
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.9, 0.92, 0.28))
	grad.set_color(1, Color(0.9, 0.9, 0.92, 0.0))
	p.color_ramp = grad
	p.position = at + Vector3(0, 0.02, 0)
	z.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.35)
	l.light_energy = 0.5
	l.omni_range = 1.0
	l.position = at + Vector3(0, 0.1, 0)
	z.add_child(l)
