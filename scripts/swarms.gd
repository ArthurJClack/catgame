class_name Swarms
extends Node3D
## lots-of-small-things wildlife, each kind is one MultiMesh moved from script (one draw call per swarm):
##   fish     shoals in the pond + stream pools, seen as dark shapes at the surface. they bolt from the cat's
##            shadow and from splashes, and now and then one jumps
##   bees     work the meadow flowers one by one
##   ants     a trail between their hill and a stump. step in it and they scatter, then reform
##   fireflies come out at dusk, blink, drift off when a paw gets close
##   moths    night: flutter round the pale flowers
## `Swarms.spawn_all(parent, atmos)` after the level + foliage exist.

var kind := "fish"
var n := 12
var home := Vector3.ZERO
var atmos: Atmos
var mm: MultiMesh
var pos: PackedVector3Array
var vel: PackedVector3Array
var aux: PackedFloat32Array      # per-instance phase / timer
var aux2: PackedFloat32Array
var tgt: PackedVector3Array
var rng := RandomNumberGenerator.new()
var center := Vector3.ZERO
var center_to := Vector3.ZERO
var t := 0.0
var scare := 0.0
var jump_i := -1
var jump_t := 0.0
var next_jump := 8.0
var stream := false
var path: PackedVector3Array
var _cat: Node3D
var mmi: MultiMeshInstance3D


func _ready() -> void:
	rng.seed = hash(kind) + int(home.x * 31.0 + home.z * 17.0)
	pos.resize(n)
	vel.resize(n)
	aux.resize(n)
	aux2.resize(n)
	tgt.resize(n)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mmi = MultiMeshInstance3D.new()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	match kind:
		"fish":
			mm.mesh = _fish_mesh()
			center = home
			center_to = home
			for i in n:
				pos[i] = home + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
				aux[i] = rng.randf() * TAU
				aux2[i] = rng.randf_range(0.11, 0.2)
			next_jump = rng.randf_range(6.0, 20.0)
			mmi.visibility_range_end = 30.0
		"bees":
			mm.mesh = _bug_mesh(Color(0.95, 0.75, 0.1), Color(0.1, 0.08, 0.05), Color(0.9, 0.95, 1.0))
			for i in n:
				pos[i] = home + Vector3(rng.randf_range(-3, 3), 0.3, rng.randf_range(-3, 3))
				tgt[i] = pos[i]
				aux[i] = rng.randf_range(0.0, 2.0)
			mmi.visibility_range_end = 18.0
		"ants":
			_build_ant_path()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.004, 0.003, 0.009)
			mm.mesh = bm
			for i in n:
				aux[i] = rng.randf()                           # where along the trail
				aux2[i] = 1.0 if i % 2 == 0 else -1.0          # which way it's going
				vel[i] = Vector3.ZERO                          # scatter offset
			mmi.visibility_range_end = 7.0
		"fireflies", "moths":
			var q := BoxMesh.new()
			q.size = Vector3.ONE * (0.04 if kind == "fireflies" else 0.02)
			mm.mesh = q if kind == "fireflies" else _bug_mesh(Color(0.85, 0.82, 0.75), Color(0.6, 0.55, 0.5), Color(0.92, 0.9, 0.85), 2.2)
			if kind == "fireflies":
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.disable_fog = true
			for i in n:
				pos[i] = _fly_spot()
				tgt[i] = _fly_spot()
				aux[i] = rng.randf() * 10.0
				aux2[i] = rng.randf_range(0.7, 1.4)
			mmi.visibility_range_end = 40.0
	mm.instance_count = n
	for i in n:
		mm.set_instance_color(i, _base_col(i))
		mm.set_instance_transform(i, Transform3D(Basis(), pos[i]))
	mmi.multimesh = mm
	mmi.material_override = mat
	# the instances roam: give the multimesh a box that covers wherever they can go
	mmi.custom_aabb = AABB(Vector3(-45, -5, -45), Vector3(90, 30, 90))
	add_child(mmi)


func _base_col(i: int) -> Color:
	match kind:
		"fish":
			return Color(0.95, 0.5, 0.15) if (i * 7 + int(home.x)) % 6 == 0 else Color(0.08, 0.14, 0.14)
		"ants":
			return Color(0.09, 0.06, 0.05)
		"fireflies":
			return Color(0, 0, 0)
	return Color.WHITE


static func _fish_mesh() -> ArrayMesh:
	# top-down fish: a diamond body + tail fin, flat on the water, nose toward -z
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(0, 0, -0.5), Vector3(0.14, 0, -0.15), Vector3(0, 0, 0.3), Vector3(-0.14, 0, -0.15), Vector3(0.12, 0, 0.5), Vector3(-0.12, 0, 0.5)]
	for tri in [[0, 1, 3], [1, 2, 3], [2, 4, 5]]:
		for i in tri:
			st.set_normal(Vector3.UP)
			st.set_color(Color.WHITE)
			st.add_vertex(pts[i])
	return st.commit()


static func _bug_mesh(a: Color, b: Color, wing: Color, wing_scale := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bx := BoxMesh.new()
	var add := func(size: Vector3, off: Vector3, col: Color) -> void:
		bx.size = size
		var arr := bx.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			st.set_normal(norms[i])
			st.set_color(col)
			st.add_vertex(verts[i] + off)
	add.call(Vector3(0.007, 0.007, 0.006), Vector3(0, 0, -0.006), b)
	add.call(Vector3(0.008, 0.008, 0.007), Vector3(0, 0, 0.0), a)
	add.call(Vector3(0.0085, 0.0085, 0.003), Vector3(0, 0, 0.005), b)
	add.call(Vector3(0.007, 0.007, 0.004), Vector3(0, 0, 0.0085), a)
	for s in [-1.0, 1.0]:
		add.call(Vector3(0.01 * wing_scale, 0.0006, 0.006 * wing_scale), Vector3(s * 0.007 * wing_scale, 0.005, -0.001), wing)
	return st.commit()


func _fly_spot() -> Vector3:
	var p := home + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
	p.x = clampf(p.x, -34, 34)
	p.z = clampf(p.z, -34, 34)
	p.y = maxf(ForestLevel.height(p.x, p.z), ForestLevel.WATER_Y) + rng.randf_range(0.12, 1.3)
	return p


func _build_ant_path() -> void:
	# anthill at home, trail wanders to the nearest stump / log (a perch close to the ground)
	var goal := home + Vector3(3.0, 0, 2.0)
	var bd := 1e9
	for p in ForestLevel.perches:
		var up := p.y - ForestLevel.height(p.x, p.z)
		var d := Vector2(p.x - home.x, p.z - home.z).length()
		if up < 1.0 and d > 2.5 and d < bd:
			bd = d
			goal = p
	var steps := int(maxf(Vector2(goal.x - home.x, goal.z - home.z).length() / 0.05, 8.0))
	var side := Vector3(goal.z - home.z, 0, home.x - goal.x).normalized()
	for s in steps + 1:
		var f := float(s) / steps
		var p := home.lerp(goal, f) + side * (sin(f * 9.0) * 0.18 + sin(f * 23.0) * 0.05) * sin(f * PI)
		p.y = ForestLevel.height(p.x, p.z) + 0.003
		path.append(p)
	# the hill itself
	var hill := LowPoly.part(self, LowPoly.cone(7), Color(0.46, 0.36, 0.25), home + Vector3(0, 0.035, 0), Vector3(0.3, 0.1, 0.3))
	hill.visibility_range_end = 30.0
	LowPoly.part(self, LowPoly.box(0.0), Color(0.1, 0.08, 0.06), home + Vector3(0, 0.086, 0), Vector3(0.03, 0.004, 0.03))


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	t += dt
	if _cat == null or not is_instance_valid(_cat):
		_cat = get_tree().get_first_node_in_group("player") as Node3D
	var cp := _cat.global_position if _cat else Vector3(0, -99, 0)
	# nothing to animate when the whole swarm is far away
	var ref := center if kind == "fish" else home
	var cam := get_viewport().get_camera_3d()
	if cam and Vector2(cam.global_position.x - ref.x, cam.global_position.z - ref.z).length() > mmi.visibility_range_end + 16.0:
		return
	match kind:
		"fish":
			_fish(dt, cp)
		"bees":
			_bees(dt, cp)
		"ants":
			_ants(dt, cp)
		"fireflies":
			_fireflies(dt, cp)
		"moths":
			_moths(dt, cp)


func _wet(x: float, z: float) -> bool:
	return ForestLevel.height(x, z) < ForestLevel.WATER_Y - 0.1


func _fish(dt: float, cp: Vector3) -> void:
	scare = maxf(scare - dt, 0.0)
	# the shoal's centre drifts round its pool
	if center.distance_to(center_to) < 0.3 or rng.randf() < dt * 0.08:
		for k in 10:
			var p := home + Vector3(rng.randf_range(-3.2, 3.2), 0, rng.randf_range(-3.2, 3.2))
			if stream:
				p.z = ForestLevel.stream_z(p.x) + rng.randf_range(-0.5, 0.5)
			if _wet(p.x, p.z):
				center_to = p
				break
	center = center.move_toward(center_to, dt * (1.6 if scare > 0.0 else 0.25))
	# the cat at the edge, or wading in: everyone bolts to the far side
	var cd := Vector2(cp.x - center.x, cp.z - center.z).length()
	if cd < 1.7 and cp.y < ForestLevel.WATER_Y + 0.8 and scare <= 0.0:
		scare = 2.5
		var away := Vector3(center.x - cp.x, 0, center.z - cp.z).normalized()
		for k in 8:
			var p := center + away.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6)) * rng.randf_range(2.0, 4.0)
			if stream:
				p.z = ForestLevel.stream_z(p.x)
			if _wet(p.x, p.z):
				center_to = p
				break
		for i in n:
			vel[i] = (away + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))) * rng.randf_range(2.0, 3.5)
		Water.splash(center, 0.35)
	next_jump -= dt
	if next_jump < 0.0 and jump_i < 0 and scare <= 0.0:
		jump_i = rng.randi() % n
		jump_t = 0.0
		next_jump = rng.randf_range(9.0, 26.0)
		Water.splash(pos[jump_i], 0.5)
	var y := ForestLevel.WATER_Y + 0.004
	for i in n:
		aux[i] += dt * (0.5 + 0.25 * sin(i * 1.7))
		# each fish holds a slot that slowly circles the centre
		var slot := center + Vector3(cos(aux[i] + i * 2.4), 0, sin(aux[i] + i * 2.4)) * (0.25 + 0.45 * fposmod(i * 0.618, 1.0))
		var want := (slot - pos[i]) * 1.6
		vel[i] = vel[i].lerp(want.limit_length(0.9 if scare <= 0.0 else 3.5), 1.0 - exp(-(2.0 if scare <= 0.0 else 0.8) * dt))
		var np := pos[i] + vel[i] * dt
		if _wet(np.x, np.z):
			pos[i] = np
		else:
			vel[i] = -vel[i] * 0.4
		var sp := vel[i].length()
		var yaw := atan2(-vel[i].x, -vel[i].z) if sp > 0.02 else aux[i]
		# tail beat: the whole body yaws side to side, faster when it swims harder
		yaw += sin(t * (7.0 + sp * 9.0) + i * 2.1) * 0.22
		var s: float = aux2[i]
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		var p := Vector3(pos[i].x, y + i * 0.0002, pos[i].z)
		if i == jump_i:
			jump_t += dt
			var k := jump_t / 0.55
			p.y = y + sin(k * PI) * 0.22
			# up on its side as it arcs over
			b = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lerpf(0.9, -0.9, k)) * Basis(Vector3.FORWARD, PI * 0.5)
			b = b.scaled(Vector3(s, s, s))
			if k >= 1.0:
				jump_i = -1
				Water.splash(p, 0.7)
				get_tree().call_group("cat_ears", "hear", p, 0.5)
		mm.set_instance_transform(i, Transform3D(b, p))


func _bees(dt: float, cp: Vector3) -> void:
	var day := atmos == null or atmos.daylight() > 0.5
	mmi.visible = day
	if not day:
		return
	for i in n:
		aux[i] -= dt
		var to := tgt[i] - pos[i]
		if to.length() < 0.03:
			# on the flower: crawl about a bit, then pick the next one
			if aux[i] < 0.0:
				if not ForestLevel.flowers.is_empty():
					var best := tgt[i]
					for k in 4:
						var f: Vector3 = ForestLevel.flowers[rng.randi() % ForestLevel.flowers.size()]
						if f.distance_to(home) < 9.0 and f.distance_to(pos[i]) > 0.2:
							best = f + Vector3(0, 0.012, 0)
							break
					tgt[i] = best
				else:
					tgt[i] = home + Vector3(rng.randf_range(-4, 4), rng.randf_range(0.1, 0.5), rng.randf_range(-4, 4))
				aux[i] = rng.randf_range(1.5, 4.0)
			vel[i] = Vector3.ZERO
		else:
			var want := to.normalized() * minf(1.4, to.length() * 3.0 + 0.2)
			# the looping bee line: wobble that fades out as it homes in
			want += Vector3(sin(t * 9.0 + i), sin(t * 7.0 + i * 2.0) * 0.6, cos(t * 8.0 + i * 3.0)) * minf(to.length(), 0.5)
			if to.length() > 0.4:
				want.y += 0.25
			vel[i] = vel[i].lerp(want, 1.0 - exp(-6.0 * dt))
			aux[i] = maxf(aux[i], 0.8)
		var off := pos[i] - cp
		if off.length() < 0.5:
			vel[i] += off.normalized() * 4.0 * dt + Vector3(0, 2.0 * dt, 0)
		pos[i] += vel[i] * dt
		var yaw := atan2(-vel[i].x, -vel[i].z) if vel[i].length() > 0.05 else i * 1.3 + t * 0.7
		var bob := Vector3(0, sin(t * 40.0 + i) * 0.0015, 0)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), pos[i] + bob))


func _ants(dt: float, cp: Vector3) -> void:
	if path.size() < 2:
		return
	var last := path.size() - 1
	var len := last * 0.05
	for i in n:
		aux[i] += aux2[i] * dt * 0.045 / maxf(len, 0.1) * (1.0 + 0.3 * sin(i * 3.1))
		if aux[i] > 1.0:
			aux[i] = 1.0
			aux2[i] = -1.0
		elif aux[i] < 0.0:
			aux[i] = 0.0
			aux2[i] = 1.0
		var f := aux[i] * last
		var k := mini(int(f), last - 1)
		var p := path[k].lerp(path[k + 1], f - k)
		var dir := (path[k + 1] - path[k]).normalized() * aux2[i]
		# two lanes + a little weave
		var side := Vector3(dir.z, 0, -dir.x)
		p += side * (0.008 * aux2[i] + sin(t * 3.0 + i) * 0.004)
		# a paw lands on the trail: scatter, mill about, find the line again
		var off := p + vel[i] - cp
		off.y = 0
		if off.length() < 0.3 and absf(cp.y - p.y) < 0.4:
			vel[i] += (off.normalized() + Vector3(sin(i * 5.0 + t * 9.0), 0, cos(i * 7.0 + t * 8.0))) * dt * 0.5
			vel[i] = vel[i].limit_length(0.25)
		else:
			vel[i] = vel[i].lerp(Vector3.ZERO, 1.0 - exp(-0.7 * dt))
		var yaw := atan2(-dir.x, -dir.z) + (sin(t * 12.0 + i) * 1.2 if vel[i].length() > 0.02 else 0.0)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), p + vel[i]))


func _fireflies(dt: float, cp: Vector3) -> void:
	var dark := 1.0 - (atmos.daylight() if atmos else 1.0)
	var on := clampf((dark - 0.55) / 0.3, 0.0, 1.0)
	mmi.visible = on > 0.0
	if on <= 0.0:
		return
	for i in n:
		var to := tgt[i] - pos[i]
		if to.length() < 0.2:
			tgt[i] = pos[i] + Vector3(rng.randf_range(-2, 2), rng.randf_range(-0.3, 0.3), rng.randf_range(-2, 2))
			tgt[i].y = clampf(tgt[i].y, ForestLevel.height(tgt[i].x, tgt[i].z) + 0.12, ForestLevel.height(tgt[i].x, tgt[i].z) + 1.5)
			if tgt[i].distance_to(home) > 13.0:
				tgt[i] = _fly_spot()
		var want := to.normalized() * 0.35 + Vector3(sin(t * 1.3 + i), sin(t * 1.9 + i * 2.0) * 0.5, cos(t * 1.1 + i * 3.0)) * 0.15
		var off := pos[i] - cp
		if off.length() < 0.6:
			want += off.normalized() * 1.2 + Vector3(0, 0.5, 0)
		vel[i] = vel[i].lerp(want, 1.0 - exp(-2.0 * dt))
		pos[i] += vel[i] * dt
		# the flash: a quick rise, a slow fade, then dark for a few seconds, each on its own clock
		var ph := fposmod(t * aux2[i] + aux[i], 2.6)
		var glow := smoothstep(0.0, 0.15, ph) * (1.0 - smoothstep(0.3, 1.1, ph))
		mm.set_instance_color(i, Color(0.5, 1.0, 0.1) * (0.12 + glow * 1.5) * on)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * (0.45 + glow * 0.9)), pos[i]))


func _moths(dt: float, cp: Vector3) -> void:
	var night := atmos != null and atmos.daylight() < 0.35
	mmi.visible = night
	if not night:
		return
	for i in n:
		var to := tgt[i] - pos[i]
		aux[i] -= dt
		if to.length() < 0.15 or aux[i] < 0.0:
			aux[i] = rng.randf_range(1.0, 4.0)
			if not ForestLevel.flowers.is_empty() and rng.randf() < 0.6:
				tgt[i] = ForestLevel.flowers[rng.randi() % ForestLevel.flowers.size()] + Vector3(0, 0.06, 0)
				if tgt[i].distance_to(home) > 12.0:
					tgt[i] = _fly_spot()
			else:
				tgt[i] = _fly_spot()
		# moths never fly straight
		var want := to.normalized() * 0.8 + Vector3(sin(t * 11.0 + i * 2.0), sin(t * 13.0 + i) * 0.9, cos(t * 9.0 + i * 3.0)) * 0.9
		var off := pos[i] - cp
		if off.length() < 0.6:
			want += off.normalized() * 2.5 + Vector3(0, 1.0, 0)
		vel[i] = vel[i].lerp(want, 1.0 - exp(-4.0 * dt))
		pos[i] += vel[i] * dt
		pos[i].y = maxf(pos[i].y, ForestLevel.height(pos[i].x, pos[i].z) + 0.05)
		var yaw := atan2(-vel[i].x, -vel[i].z)
		var flap := Basis(Vector3.FORWARD, sin(t * 50.0 + i) * 0.5)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw) * flap, pos[i]))


static func spawn_all(parent: Node3D, sky: Atmos = null) -> Array:
	var out := []
	var web := OS.has_feature("web")
	var add := func(k: String, count: int, at: Vector3, on_stream := false) -> Swarms:
		var s := Swarms.new()
		s.kind = k
		s.n = count
		s.home = at
		s.atmos = sky
		s.stream = on_stream
		parent.add_child(s)
		out.append(s)
		return s
	var pond := ForestLevel.POND
	add.call("fish", 12, Vector3(pond.x, ForestLevel.WATER_Y, pond.y))
	add.call("fish", 7, Vector3(pond.x + 1.5, ForestLevel.WATER_Y, pond.y - 1.5))
	for x in [-18.0, 4.0, 14.0]:
		add.call("fish", 6, Vector3(x, ForestLevel.WATER_Y, ForestLevel.stream_z(x)), true)
	var m := ForestLevel.MEADOW
	add.call("bees", 10 if web else 18, Vector3(m.x, ForestLevel.height(m.x, m.y), m.y))
	add.call("ants", 46, ForestLevel.ground(2.6, 26.5))
	add.call("ants", 46, ForestLevel.ground(m.x - 5.0, m.y + 3.0))
	add.call("fireflies", 34 if web else 70, Vector3(m.x, ForestLevel.height(m.x, m.y), m.y))
	add.call("fireflies", 24 if web else 40, ForestLevel.ground(2.0, 22.0))
	add.call("fireflies", 20 if web else 36, ForestLevel.ground(pond.x - 4.0, pond.y + 2.0))
	add.call("moths", 14, Vector3(m.x, ForestLevel.height(m.x, m.y), m.y))
	return out
