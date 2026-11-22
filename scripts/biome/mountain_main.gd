extends BiomeMain
## the mountain (res://mountain.tscn, the gate in the farm's north fence behind the barn): see
## mountain_level.gd for the map, beasts.gd for the animals, biome_puzzles.gd for the three cat
## puzzles (snowball, marmot, summit).

var snow: CPUParticles3D


func _init() -> void:
	key = "mountain"


func build_level() -> Dictionary:
	var i := MountainLevel.build(self)
	return i


func env_cfg() -> Dictionary:
	# a cold clear morning: deep blue overhead, pale at the horizon, sun low in the east
	return {
		"sky_top": Color(0.18, 0.36, 0.72), "sky_horizon": Color(0.78, 0.86, 0.95),
		"ground_horizon": Color(0.62, 0.68, 0.76), "ground_bottom": Color(0.3, 0.34, 0.4),
		"ambient": Color(0.62, 0.7, 0.86), "ambient_e": 0.7, "exposure": 1.0,
		"fog": Color(0.78, 0.84, 0.94), "fog_density": 0.0038, "fog_sky": 0.2,
		"sun": Color(1.0, 0.93, 0.82), "sun_e": 1.9, "sun_rot": Vector3(-28, 62, 0),
		"sat": 1.05, "contrast": 1.08,
	}


func help_text() -> String:
	return "the mountain: two cliff bands to climb (or the talus gullies the long way round), a hut, marmots, goats, and a cairn on top"


func spawn_wildlife() -> void:
	sound.stream_line = MountainLevel.stream_pts
	# goats: two on the band 2 ledges, two on the bench
	var r: Array = MountainLevel.goat_routes
	beast("goat", r[0][0], {"route": r[0]})
	var r0b: Array = r[0].duplicate()
	r0b.reverse()
	beast("goat", r0b[0], {"route": r0b})
	beast("goat", r[1][0], {"route": r[1]})
	var r1b: Array = r[1].slice(3) + r[1].slice(0, 3)
	beast("goat", r1b[0], {"route": r1b})
	# marmots: the sentry on its lookout rock, three grazing by their burrows below the gully
	var sr := BiomeKit.at(MountainLevel.SENTRY.x, MountainLevel.SENTRY.y)
	var top := sr.y + 0.9 * (0.5 - 0.2) + 0.9 * 0.4   # rock(..., sink 0.2): centre + flattened top
	var burrows := [Vector2(20.0, 12.0), Vector2(23.5, 13.0), Vector2(19.0, 9.0), Vector2(24.5, 9.5)]
	beast("marmot", Vector3(sr.x, top, sr.z), {"sentry": true, "burrow": BiomeKit.at(burrows[0].x, burrows[0].y), "face": PI})
	for k in range(1, 4):
		var b := BiomeKit.at(burrows[k].x, burrows[k].y)
		beast("marmot", b + Vector3(0.6, 0, 0.4), {"burrow": b})
		_burrow_mound(b)
	_burrow_mound(BiomeKit.at(burrows[0].x, burrows[0].y))
	# pikas up the talus gully
	var pk := 0
	for p in ForestLevel.perches:
		var pp: Vector3 = p
		if pp.x > 18.0 and pp.x < 26.0 and pp.z < MountainLevel.z1(pp.x) + 3.0 and pp.z > MountainLevel.z1(pp.x) - 4.0:
			beast("pika", pp)
			pk += 1
			if pk >= 4:
				break
	# golden eagle over the meadow, snow finches about the bench
	beast("eagle", Vector3(0, 24, 10), {"circle": Vector3(4, 24, 12), "radius": 18.0})
	for k in 5:
		beast("bird", BiomeKit.at(-6.0 + k * 0.7, -7.0 + (k % 2) * 0.6))
	# blowing snow near the cat when it's up high
	snow = BiomeKit.drift_particles(self, Color(1, 1, 1, 0.7), 140, 0.03, Vector3(2.5, -0.2, 0.8), 3.0, Vector3(8, 3, 8))
	snow.emitting = false


func _burrow_mound(b: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = BiomeKit.rock_mesh(Vector3(0.7, 0.18, 0.6), 2)
	m.material_override = PSX.mat("grain", MountainLevel.C_DIRT)
	m.position = b + Vector3(0, 0.03, 0)
	BiomeKit.lv.add_child(m)
	BiomeKit.pbox(b + Vector3(0, 0.07, 0.24), Vector3(0.18, 0.12, 0.02), 0.0, "rubber", Color(0.2, 0.2, 0.2), false)


func tick(dt: float) -> void:
	var c := get_viewport().get_camera_3d()
	if snow and c:
		snow.global_position = c.global_position + Vector3(-3, 1, 0)
		snow.emitting = c.global_position.y > MountainLevel.B1 - 0.5
	# the summit flag snaps in the wind, the low clouds drift
	for f in get_tree().get_nodes_in_group("biome_flag"):
		(f as Node3D).rotation.y = sin(t * 7.0) * 0.35 + sin(t * 13.0) * 0.1


func build_puzzles() -> void:
	puzzles = BiomePuzzles.mountain(self, player)
