extends BiomeMain
## the desert (res://desert.tscn, the gate in the farm's west fence): see desert_level.gd for the map,
## beasts.gd for the animals, biome_puzzles.gd for the three cat puzzles (windmill, tumbleweed, box).


func _init() -> void:
	key = "desert"


func build_level() -> Dictionary:
	return DesertLevel.build(self)


func env_cfg() -> Dictionary:
	# late afternoon: low hot sun from the west, washed out blue going to dusty peach at the horizon
	return {
		"sky_top": Color(0.32, 0.5, 0.78), "sky_horizon": Color(0.96, 0.78, 0.58),
		"ground_horizon": Color(0.86, 0.66, 0.46), "ground_bottom": Color(0.5, 0.36, 0.26),
		"ambient": Color(0.82, 0.7, 0.6), "ambient_e": 0.62, "exposure": 1.05,
		"fog": Color(0.95, 0.8, 0.62), "fog_density": 0.0055, "fog_sky": 0.15,
		"sun": Color(1.0, 0.84, 0.62), "sun_e": 2.0, "sun_rot": Vector3(-26, -78, 0),
		"sat": 1.08, "contrast": 1.08,
	}


func help_text() -> String:
	return "the desert: a dry wash, a ranch ruin, a windmill, dunes and a mesa to climb. mind the rattlesnakes"


func spawn_wildlife() -> void:
	# lizards basking on the low rocks
	var n := 0
	for i in ForestLevel.perches.size():
		var p: Vector3 = ForestLevel.perches[(i * 7 + 3) % ForestLevel.perches.size()]
		var up := p.y - BiomeKit.y(p.x, p.z)
		if up < 0.15 or up > 1.0:
			continue
		beast("lizard", p)
		n += 1
		if n >= 7:
			break
	# rattlesnakes: in the pickup's shade + at the foot of the mesa
	beast("snake", BiomeKit.at(DesertLevel.TRUCK.x + 1.4, DesertLevel.TRUCK.y + 1.2))
	beast("snake", BiomeKit.at(DesertLevel.MESA.x + 5.0, DesertLevel.MESA.y + 5.5))
	# scorpions at rock edges
	var sc := 0
	for i in ForestLevel.perches.size():
		var p: Vector3 = ForestLevel.perches[(i * 13 + 5) % ForestLevel.perches.size()]
		var up := p.y - BiomeKit.y(p.x, p.z)
		if up < 0.3 or up > 1.4 or Vector2(p.x, p.z).distance_to(Vector2(0, 33)) < 6.0:
			continue
		beast("scorpion", BiomeKit.at(p.x + 0.45, p.z + 0.3))
		sc += 1
		if sc >= 3:
			break
	# vultures on the thermals, one sometimes drops into the dead tree
	beast("vulture", Vector3(0, 22, 0), {"circle": Vector3(2, 22, 6), "radius": 16.0, "roost": DesertLevel.roost()})
	beast("vulture", Vector3(-10, 26, -6), {"circle": Vector3(-12, 27, -8), "radius": 11.0})
	# jackrabbits on the flats, a covey of quail by the gate
	for p in [Vector2(-18, 28), Vector2(12, 8), Vector2(-26, 2)]:
		beast("rabbit", BiomeKit.at(p.x, p.y))
	for k in 6:
		beast("bird", BiomeKit.at(7.0 + (k % 3) * 0.5, 29.0 + (k / 3) * 0.6))


func build_puzzles() -> void:
	puzzles = BiomePuzzles.desert(self, player)
