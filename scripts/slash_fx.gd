class_name SlashFx
extends RefCounted
## claw slash effects for paw attacks (cat_combat.gd / cat_player._swat_impact). all world space,
## so the same streak reads in first person (it whips across in front of the camera) and in third
## person / orbit (it's where the paw went):
##   streak()  three parallel claw trails along the swipe, white hot core, fade in ~0.18 s
##   sparks()  a little burst where the claws connect (pale on stuff, red bits on a rat)
##   wound()   three short scratch lines stuck on whatever got hit, fade over ~1.4 s
## headless (tests) does nothing: the dummy renderer can't build meshes.

const STREAK_T := 0.24
const WOUND_T := 1.4


static func _ok(n: Node) -> bool:
	return n != null and n.is_inside_tree() and DisplayServer.get_name() != "headless"


static func _mat(col: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	m.no_depth_test = false
	return m


## a swipe from a to b, bowed toward `bow` (world offset at the middle). side = the across
## direction the three claws are spread along. follow: the streak rides along with that node
## (the cat: a strike thrown on the move stays out in front of it instead of hanging in the air behind)
## lines: 3 = the claw scratch, 1 = a single soft stroke (harmless play swats, cat_spar.gd)
static func streak(host: Node, a: Vector3, b: Vector3, bow: Vector3, col := Color(1.0, 0.95, 0.85), follow: Node3D = null, lines := 3) -> void:
	if not _ok(host):
		return
	var cam := host.get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else a + Vector3.UP
	var root := MeshInstance3D.new()
	root.top_level = true
	root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := (b - a)
	var mid := (a + b) * 0.5
	var to_cam := (eye - mid).normalized()
	var spread := along.cross(to_cam).normalized()      # claws side by side, across the swipe
	if spread.length() < 0.5:
		spread = Vector3.UP
	var n := 10
	var soft := lines == 1
	for k in lines:
		var ck := float(k) - float(lines - 1) * 0.5
		var off := spread * ck * 0.016
		var lag := absf(ck) * 0.06          # outer claws trail the middle one a touch
		var pts: Array[Vector3] = []
		for i in n + 1:
			var u := lerpf(lag, 1.0, float(i) / n)
			var p := a.lerp(b, u) + bow * (4.0 * u * (1.0 - u)) + off
			pts.append(p)
		for i in n:
			var u0 := float(i) / n
			var u1 := float(i + 1) / n
			# thin at the start, fat then sharp at the tip, like a claw tearing through
			var w0 := 0.0065 * sin(PI * pow(u0, 0.7))
			var w1 := 0.0065 * sin(PI * pow(u1, 0.7))
			if soft:
				# one rounder, fatter stroke with blunt ends: a paw pad, not claws
				w0 = 0.011 * sin(PI * u0)
				w1 = 0.011 * sin(PI * u1)
			var t := (pts[i + 1] - pts[i]).normalized()
			var side0 := t.cross((eye - pts[i]).normalized()).normalized()
			var side1 := t.cross((eye - pts[i + 1]).normalized()).normalized()
			var c0 := Color(col.r, col.g, col.b, u0 * 0.9 + 0.1)
			var c1 := Color(col.r, col.g, col.b, u1 * 0.9 + 0.1)
			var v := [pts[i] - side0 * w0, pts[i] + side0 * w0, pts[i + 1] + side1 * w1, pts[i + 1] - side1 * w1]
			var cs := [c0, c0, c1, c1]
			for q in [0, 1, 2, 0, 2, 3]:
				st.set_color(cs[q])
				st.add_vertex(v[q])
	root.mesh = st.commit()
	var mat := _mat(Color(1, 1, 1, 1))
	root.material_override = mat
	if follow != null and follow.is_inside_tree():
		root.top_level = false
		follow.add_child(root)
		root.transform = follow.global_transform.affine_inverse()
	else:
		host.get_tree().current_scene.add_child(root)
		root.global_transform = Transform3D.IDENTITY
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, STREAK_T).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


## burst where the claws connect. flesh = red bits + fur tufts, else pale sparks / splinters
static func sparks(host: Node, pos: Vector3, normal: Vector3, flesh := false, amount := 10) -> void:
	if not _ok(host):
		return
	var p := CPUParticles3D.new()
	p.top_level = true
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.32
	p.explosiveness = 1.0
	p.direction = normal if normal.length() > 0.1 else Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -7.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var bm := BoxMesh.new()
	bm.size = Vector3(0.007, 0.007, 0.007)
	p.mesh = bm
	var col := Color(0.75, 0.08, 0.06) if flesh else Color(1.0, 0.92, 0.7)
	var m := _mat(Color(1, 1, 1, 1), not flesh)
	m.vertex_color_use_as_albedo = true
	bm.material = m
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 1.0))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = grad
	host.get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(0.7)
	tw.tween_callback(p.queue_free)


## three short scratch lines stuck to `on` (they ride along as it moves), facing `normal`
static func wound(on: Node3D, pos: Vector3, normal: Vector3, sweep: Vector3, col := Color(0.55, 0.05, 0.05)) -> void:
	if not _ok(on):
		return
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nrm := normal.normalized() if normal.length() > 0.1 else Vector3.UP
	var along := (sweep - nrm * sweep.dot(nrm)).normalized()
	if along.length() < 0.5:
		along = nrm.cross(Vector3.UP).normalized()
	var across := nrm.cross(along).normalized()
	for k in 3:
		var c := pos + nrm * 0.004 + across * (float(k) - 1.0) * 0.013
		var half := along * (0.03 - absf(float(k) - 1.0) * 0.006)
		var w := across * 0.0025
		var v := [c - half - w, c - half + w, c + half + w, c + half - w]
		for q in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(1, 1, 1, 1))
			st.add_vertex(on.to_local(v[q]))
	mi.mesh = st.commit()
	var mat := _mat(col, false)
	mi.material_override = mat
	on.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_interval(WOUND_T * 0.6)
	tw.tween_property(mat, "albedo_color:a", 0.0, WOUND_T * 0.4)
	tw.tween_callback(mi.queue_free)
