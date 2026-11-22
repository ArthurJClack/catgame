class_name CatVision
extends Node3D
## "cat vision": hold q (pad LB) and the world dims a bit while the things worth a look light up
## with a soft glowing rim:
##   gold    unsolved puzzles (Puzzles.sense points, which also get their motes)
##   orange  prey (mice, rats, birds...). you can make them out through walls, faintly
##   blue    other cats (npc, online, bots), also through walls
##   white   loose stuff you can knock off, swat or carry
##   green   things to climb or scratch
## only lights things within RANGE. CatPlayer makes one for itself; it does nothing for bots unless
## their bot dict says "vision". the highlight is a material_overlay on each mesh, put back the way
## it was when the button is let go.

const RANGE := 18.0
const RISE := 0.18              # s to full
const FALL := 0.3
const REFRESH := 0.4            # s between re-picking what to light (prey move, things spawn)
const PROP_MASS := 25.0         # rigid bodies lighter than this count as "loose stuff"
const MAX_MESHES := 48          # per lit thing (a tree with 300 leaf cards gets its first 48)

const C_PUZZLE := Color(1.0, 0.78, 0.3)
const C_PREY := Color(1.0, 0.42, 0.2)
const C_CAT := Color(0.4, 0.72, 1.0)
const C_PROP := Color(0.92, 0.94, 1.0)
const C_CLIMB := Color(0.45, 1.0, 0.5)

var player: CatPlayer
var level := 0.0                # 0..1 how strong it is right now (tests + cat sense read it)
var lit := {}                   # MeshInstance3D -> [old overlay, kind]
var _mats := {}                 # kind -> ShaderMaterial
var _refresh_t := 0.0
var _props: Array = []          # rigid bodies found when the button went down
var _was_on := false
var _screen: CanvasLayer
var _screen_mat: ShaderMaterial

const RIM := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.0;
uniform float base = 0.12;
uniform float rim_k = 1.6;
void vertex() {
	VERTEX += NORMAL * 0.004;   // a hair outside the surface so it never z-fights
}
void fragment() {
	float f = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 4.0);
	ALBEDO = tint.rgb * (base + pow(f, 2.0) * rim_k) * strength * pulse;
}
"""

const XRAY := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.0;
void fragment() {
	float f = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	ALBEDO = tint.rgb * (0.05 + pow(f, 3.0) * 0.5) * strength;
}
"""

const SCREEN := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float amt = 0.0;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 o = mix(c, mix(c, vec3(l), 0.3) * 0.72, amt);
	float v = 1.0 - amt * 0.5 * smoothstep(0.3, 0.8, length(SCREEN_UV - 0.5));
	COLOR = vec4(o * v, 1.0);
}
"""


func _ready() -> void:
	var rim := Shader.new()
	rim.code = RIM
	var xr := Shader.new()
	xr.code = XRAY
	for kind in ["puzzle", "prey", "cat", "prop", "climb"]:
		var m := ShaderMaterial.new()
		m.shader = rim
		m.set_shader_parameter("tint", _color(kind))
		if kind == "climb":
			m.set_shader_parameter("base", 0.04)
			m.set_shader_parameter("rim_k", 0.9)
		if kind in ["puzzle", "prey", "cat"]:
			var x := ShaderMaterial.new()
			x.shader = xr
			x.set_shader_parameter("tint", _color(kind))
			m.next_pass = x
		_mats[kind] = m


static func _color(kind: String) -> Color:
	match kind:
		"puzzle": return C_PUZZLE
		"prey": return C_PREY
		"cat": return C_CAT
		"prop": return C_PROP
	return C_CLIMB


func on() -> bool:
	if not is_instance_valid(player):
		return false
	if not player.bot.is_empty() and not player.bot.get("vision", false):
		return false
	return player.vision_held


func _process(dt: float) -> void:
	var want := on()
	level = clampf(level + (dt / RISE if want else -dt / FALL), 0.0, 1.0)
	if want and not _was_on:
		_props = _find_props()
		_refresh_t = 0.0
	_was_on = want
	if level <= 0.0:
		if not lit.is_empty():
			_clear()
		if _screen:
			_screen.visible = false
		return
	_refresh_t -= dt
	if _refresh_t <= 0.0 and want:
		_refresh_t = REFRESH
		_relight()
	for kind in _mats:
		var m: ShaderMaterial = _mats[kind]
		m.set_shader_parameter("strength", level)
		if m.next_pass:
			(m.next_pass as ShaderMaterial).set_shader_parameter("strength", level)
	_screen_tint()


## what should glow right now: Node3D -> kind
func targets() -> Dictionary:
	var out := {}
	if not is_inside_tree():
		return out
	var me := player.global_position
	var tree := get_tree()
	for n in tree.get_nodes_in_group("climbable") + tree.get_nodes_in_group("scratchable"):
		out[n] = "climb"
	for n in _props:
		if is_instance_valid(n):
			out[n] = "prop"
	for n in tree.get_nodes_in_group("cat"):
		if n != player:
			out[n] = "cat"
	for n in tree.get_nodes_in_group("prey"):
		out[n] = "prey"
	var z := _puzzles()
	if z and z.sense:
		for id in z.sense.open_points():
			var w = z.sense.points[id]
			if w is Node3D and is_instance_valid(w):
				out[w] = "puzzle"
	for n in out.keys():
		if not (n is Node3D) or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
			out.erase(n)
		elif not _near(n, me):
			out.erase(n)
	return out


func _puzzles() -> Node:
	var root := get_tree().current_scene
	return root.get_node_or_null("Puzzles") if root else null


## close enough: the node itself, or (for big things like trees and walls) the nearest point
## of one of its meshes
func _near(n: Node3D, me: Vector3) -> bool:
	if n.global_position.distance_to(me) < RANGE:
		return true
	for m in _meshes(n, 6):
		var bb: AABB = m.global_transform * m.get_aabb()
		var c := me.clamp(bb.position, bb.end)
		if c.distance_to(me) < RANGE:
			return true
	return false


func _meshes(n: Node, cap := MAX_MESHES) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n)
	for c in n.find_children("*", "MeshInstance3D", true, false):
		if out.size() >= cap:
			break
		if (c as MeshInstance3D).mesh and (c as MeshInstance3D).visible:
			out.append(c)
	return out


func _find_props() -> Array:
	var out := []
	var root := get_tree().current_scene
	if root == null:
		return out
	for rb in root.find_children("*", "RigidBody3D", true, false):
		if (rb as RigidBody3D).mass < PROP_MASS and not rb.is_in_group("prey") and not player.is_ancestor_of(rb):
			out.append(rb)
	return out


func _relight() -> void:
	var want := {}       # mesh -> kind
	var t := targets()
	# later kinds win when a node is two things at once (a climbable puzzle spot glows gold)
	for kind in ["climb", "prop", "cat", "prey", "puzzle"]:
		for n in t:
			if t[n] != kind:
				continue
			for m in _meshes(n):
				if not player.is_ancestor_of(m) and not is_ancestor_of(m):
					want[m] = kind
	for m in lit.keys():
		if not want.has(m) or lit[m][1] != want[m]:
			_unlight(m)
	for m in want:
		if lit.has(m):
			continue
		lit[m] = [m.material_overlay, want[m]]
		m.material_overlay = _mats[want[m]]


func _unlight(m) -> void:
	if is_instance_valid(m) and lit.has(m):
		(m as MeshInstance3D).material_overlay = lit[m][0]
	lit.erase(m)


func _clear() -> void:
	for m in lit.keys():
		_unlight(m)
	lit.clear()


## how many meshes of a kind are lit (tests)
func count(kind: String) -> int:
	var n := 0
	for m in lit:
		if lit[m][1] == kind:
			n += 1
	return n


func _screen_tint() -> void:
	if not player.bot.is_empty() or not player.is_inside_tree():
		return
	if _screen == null:
		_screen = CanvasLayer.new()
		_screen.layer = 1        # over the world, under the hud
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = SCREEN
		_screen_mat = ShaderMaterial.new()
		_screen_mat.shader = sh
		r.material = _screen_mat
		_screen.add_child(r)
		add_child(_screen)
	_screen.visible = true
	_screen_mat.set_shader_parameter("amt", level)


func _exit_tree() -> void:
	_clear()
