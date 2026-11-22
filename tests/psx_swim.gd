extends Node
## psx texture swim check: loads a level, then glides a camera at cat eye height so you can see
## textures warp (or not) as surfaces pass close to the lens. render it as a movie:
##   xvfb-run godot --path . --write-movie out/f.png --fixed-fps 30 --quit-after 90 res://tests/psx_swim.tscn -- \
##     --scene res://city.tscn --from x,y,z --to x,y,z --look x,y,z
## the camera slides from --from to --to over the clip, always looking --look relative (a direction).

var cam: Camera3D
var a := Vector3.ZERO
var b := Vector3.ZERO
var look := Vector3(0, 0, -1)
var t := 0.0
var dur := 3.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := _arg(args, "--scene", "res://psx_uvlab.tscn")
	a = _vec(_arg(args, "--from", "0,0.2,2"))
	b = _vec(_arg(args, "--to", "0,0.2,-1"))
	look = _vec(_arg(args, "--look", "0,0,-1"))
	dur = float(_arg(args, "--dur", "3"))
	var lvl: Node = load(scene).instantiate()
	add_child(lvl)
	# levels on terrain (city): --from / --to heights are above the ground there
	if lvl.has_method("_ground"):
		a = lvl._ground(Vector3(a.x, 0, a.z), a.y)
		b = lvl._ground(Vector3(b.x, 0, b.z), b.y)
	cam = Camera3D.new()
	cam.fov = 75
	cam.near = 0.02
	cam.far = 300
	add_child(cam)
	cam.current = true
	for c in get_tree().get_nodes_in_group("player_like"):
		c.process_mode = Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
	# levels make their own cameras (player, still cams): keep ours on top
	if not cam.current:
		cam.current = true
	var k := clampf(t / dur, 0.0, 1.0)
	var p := a.lerp(b, k)
	cam.global_position = p
	cam.look_at(p + look, Vector3.UP)
	t += delta
	_hide_hud(self)


## hide hud text/bars, keep full screen post effect rects (shader materials)
func _hide_hud(n: Node) -> void:
	for c in n.get_children():
		if c is Control and not (c.material is ShaderMaterial):
			c.visible = false
		elif c is CanvasLayer and c.layer >= 100:
			c.visible = false
		else:
			_hide_hud(c)


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


func _vec(s: String) -> Vector3:
	var v := s.split_floats(",")
	return Vector3(v[0], v[1], v[2])
