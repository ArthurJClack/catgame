extends Node3D
## low side camera on the cat's paws for before/after renders of paws vs drawn ground.
## xvfb-run godot --path . res://tests/float_show.tscn --write-movie out/x.png --fixed-fps 30 -- --map forest|farm
var player: CatPlayer
var cam: Camera3D
var t := 0.0
var map := "forest"
var still := false
var yaw0 := 0.3
var dist := 0.9

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if "--map" in a:
		map = a[a.find("--map") + 1]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	player = CatPlayer.new()
	player.style = "block"
	var at := Vector2(-24, 20)
	if "--at" in a:
		var q: PackedStringArray = a[a.find("--at") + 1].split(",")
		at = Vector2(float(q[0]), float(q[1]))
	if "--still" in a:
		still = true
	if "--dist" in a:
		dist = float(a[a.find("--dist") + 1])
	if "--yaw" in a:
		yaw0 = float(a[a.find("--yaw") + 1])
	if map == "forest":
		ForestLevel.build(self)
		add_child(player)
		player.global_position = Vector3(at.x, ForestLevel.height(at.x, at.y) + 0.3, at.y)
	else:
		Level.build(self)
		add_child(player)
		player.global_position = Vector3(12, 0.02, 9)
	cam = Camera3D.new()
	cam.fov = 40
	cam.near = 0.02
	add_child(cam)
	cam.current = true

func _process(dt: float) -> void:
	t += dt
	var walk := t > 1.0 and t < 7.0 and not still
	player.bot = {"move": Vector2(0, 0.45 if walk else 0.0), "yaw": yaw0}
	var b := player.global_transform.basis
	var right := b.x
	var fwd := -b.z
	var c := player.global_position + Vector3(0, 0.1, 0)
	cam.global_position = c + right * dist + fwd * 0.05 + Vector3(0, -0.07 if dist < 0.6 else 0.0, 0)
	cam.look_at(c + Vector3(0, -0.04 if dist >= 0.6 else -0.09, 0))
	if t > (3.0 if still else 8.0):
		get_tree().quit()
