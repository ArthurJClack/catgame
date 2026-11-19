extends SceneTree
## preview clip of the hub: a bot cat canters from the patio out of each farm gate, through the
## level's way back, and on to the next gate. render:
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --write-movie out/hub.avi --fixed-fps 30 --script res://tests/hub_show.gd

# [scene the leg runs in, waypoints before the trigger, trigger it heads into]
const LEGS := [
	["res://main.tscn", [Vector3(8, 0, 4.5)], "res://stealth.tscn"],
	["res://stealth.tscn", [], "res://main.tscn"],
	["res://main.tscn", [Vector3(21, 0, 10), Vector3(4, 0, 13), Vector3(3.6, 0, 21.6)], "res://arena.tscn"],
	["res://arena.tscn", [Vector3(0, 0, 5.2)], "res://main.tscn"],
	["res://main.tscn", [Vector3(-3, 0, 27)], "res://trail.tscn"],
	["res://trail.tscn", [], "res://main.tscn"],
	["res://main.tscn", [Vector3(-8, 0, 20), Vector3(-13.5, 0, 12.25)], "res://forest.tscn"],
]

var leg := 0
var wp := 0
var frames := 0
var settle := 0
var _seen: Node = null


func _initialize() -> void:
	Hub.allow_bots = true
	change_scene_to_file("res://main.tscn")


func _player() -> CatPlayer:
	if current_scene == null:
		return null
	var p = current_scene.get("player")
	return p if p is CatPlayer and p.is_inside_tree() else null


func _trigger(to: String) -> Node3D:
	for n in get_nodes_in_group("hub_trigger"):
		if current_scene and current_scene.is_ancestor_of(n) and n.get_meta("hub_to", "") == to:
			return n
	return null


func _process(_dt: float) -> bool:
	frames += 1
	if frames > 30 * 120:
		return true
	var p := _player()
	if p == null or root.has_node("HubFade") and current_scene != _seen:
		return false
	if current_scene != _seen:
		# new level: camera behind the cat, a beat to look around
		_seen = current_scene
		settle = 25
		wp = 0
		p.bot = {"move": Vector2.ZERO, "yaw": p.yaw, "pitch": -0.15}
		p.set_third_person(true)
		if current_scene.get("hud"):
			current_scene.hud.visible = false
		if leg == 0:
			# start on the patio, next to the fingerpost
			p.global_position = Vector3(2.6, 0.05, 6.2)
			p.yaw = -PI / 2.0
			p.orb_yaw = p.yaw
			p.bot.yaw = p.yaw
			settle = 45
		if leg >= LEGS.size():
			settle = 75
	if settle > 0:
		settle -= 1
		if settle == 0 and leg >= LEGS.size():
			return true
		return false
	if leg >= LEGS.size():
		return false
	var L: Array = LEGS[leg]
	if current_scene.scene_file_path != L[0]:
		return false
	var pts: Array = L[1]
	var target: Vector3
	if wp < pts.size():
		target = pts[wp]
	else:
		var t := _trigger(L[2])
		if t == null:
			print("hub show: no trigger to ", L[2])
			return true
		target = t.global_position
	var to := target - p.global_position
	to.y = 0
	if wp < pts.size() and to.length() < 0.6:
		wp += 1
	var want := atan2(-to.x, -to.z)
	var y := lerp_angle(float(p.bot.get("yaw", p.yaw)), want, 0.12)
	p.bot = {"move": Vector2(0, 1), "yaw": y, "pitch": -0.15, "canter": true}
	if wp >= pts.size() and root.has_node("HubFade"):
		leg += 1
		p.bot = {"move": Vector2(0, 0.6), "yaw": y, "pitch": -0.15}
	return false
