extends SceneTree
## top down map of the hub farm with each gate labelled. render one frame:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --write-movie out/map.png --fixed-fps 30 --quit-after 10 --script res://tests/hub_map.gd

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	_setup.call_deferred()


func _setup() -> void:
	while current_scene == null or current_scene.get("player") == null:
		await process_frame
	var main := current_scene
	main.hud.visible = false
	var sh = main.player.get("souls_hud")
	if sh is CanvasItem or sh is CanvasLayer:
		sh.visible = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 56.0
	cam.far = 200.0
	main.add_child(cam)
	cam.global_position = Vector3(5.0, 60.0, 11.0)
	cam.rotation = Vector3(-PI / 2.0, 0, 0)
	cam.current = true
	var tags := {
		"FOREST\ngate": Vector3(Hub.FENCE_X0 + 3.6, 3, 12.25),
		"PIER 9\ngate": Vector3(Hub.FENCE_X1 - 3.6, 3, 3.25),
		"TRAIL gate": Vector3(-3.0, 3, Hub.FENCE_Z1 - 2.4),
		"RAT PIT\n(cellar)": Hub.PIT_HATCH + Vector3(-3.4, 3, 0.0),
		"you start\n(house)": Vector3(-1.0, 6, 1.0),
		"signpost": Vector3(3.9, 6, 7.2),
	}
	for t in tags:
		var l := Label3D.new()
		l.text = t
		l.font_size = 100
		l.pixel_size = 0.012
		l.outline_size = 24
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.modulate = Color(1, 0.95, 0.4) if t.begins_with("you") or t == "signpost" else Color(1, 1, 1)
		l.position = tags[t]
		main.add_child(l)
	# ring each gate
	for k in Hub.DESTS:
		var tr: Node3D = null
		for n in get_nodes_in_group("hub_trigger"):
			if n.get_meta("hub_to", "") == Hub.DESTS[k].scene:
				tr = n
		if tr:
			var m := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 1.3
			tm.outer_radius = 1.7
			m.mesh = tm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.45, 0.1)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.position = tr.global_position + Vector3(0, 2.0, 0)
			main.add_child(m)
