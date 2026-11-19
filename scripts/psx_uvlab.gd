extends Node3D
## psx texture-near-camera lab: brick floor + hazard wall + crate wall, camera at cat eye height.
## render with `res://psx_uvlab.tscn -- --shot N` (0 floor ahead, 1 wall close, 2 corner, 3 looking down).
## used to check textures keep their size when surfaces get right up to the camera.

const SHOTS := [
	[Vector3(0.0, 0.12, 2.0), Vector3(0.0, 0.02, -3.0)],
	[Vector3(0.6, 0.15, -1.75), Vector3(-0.4, 0.12, -2.0)],
	[Vector3(1.2, 0.2, -1.3), Vector3(2.4, 0.1, -2.2)],
	[Vector3(0.0, 0.08, 0.6), Vector3(0.0, 0.0, 0.2)],
]


func _ready() -> void:
	PSX.setup_globals()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.25, 0.3)
	we.environment = env
	add_child(we)
	_slab(Vector3(12, 0.1, 12), Vector3(0, -0.05, 0), "brick")
	_slab(Vector3(12, 3, 0.2), Vector3(0, 1.5, -2.3), "hazard")
	_slab(Vector3(0.2, 3, 6), Vector3(2.6, 1.5, 0), "crate")
	var cam := Camera3D.new()
	cam.fov = 75
	cam.near = 0.01
	add_child(cam)
	cam.current = true
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	var s: Array = SHOTS[int(args[i + 1]) if i >= 0 else 0]
	cam.position = s[0]
	cam.look_at(s[1], Vector3.UP)
	var ui := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.material = PSX.post_material()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(rect)
	add_child(ui)


func _slab(size: Vector3, pos: Vector3, kind: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = PSX.box_mesh(size, 1.0, 1.2)
	mi.material_override = PSX.mat(kind, Color.WHITE, 0.0, {"unshaded": true})
	mi.position = pos
	add_child(mi)
