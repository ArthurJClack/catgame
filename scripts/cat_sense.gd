class_name CatSense
extends Node3D
## "cat sense": crouch and keep still for a moment and the cat notices things. every unsolved
## puzzle nearby gets a few warm motes drifting round it, brighter the closer it is. no words,
## no new key (crouch already means "stalk and pay attention"), and nothing shows while you run
## around, so the world stays clean. Puzzles adds one of these and fills `points` (id -> Node3D
## or Vector3). a point stops showing once Puzzles.solved has its id.

const STILL_SPEED := 0.4      # m/s: slower than this counts as keeping still
const WAIT := 0.5             # s crouched + still before the sense starts
const RISE := 0.7             # s to full
const FALL := 0.35
const RANGE := 14.0           # m: points further than this don't show
const MOTES := 6
const C_MOTE := Color(1.0, 0.82, 0.42)

var player: CatPlayer
var points := {}              # id -> Node3D or Vector3
var level := 0.0              # 0..1 how strong the sense is right now (tests read it)
var _still_t := 0.0
var _t := 0.0
var _vis := {}                # id -> Array[MeshInstance3D]
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.no_depth_test = false
	_mat.albedo_color = Color(C_MOTE, 0.0)
	_mat.emission_enabled = true
	_mat.emission = C_MOTE
	_mat.emission_energy_multiplier = 2.0


func add_point(id: String, where) -> void:
	points[id] = where


func point_pos(id: String) -> Vector3:
	var w = points.get(id)
	if w is Node3D:
		return (w as Node3D).global_position if is_instance_valid(w) else Vector3.INF
	if w is Vector3:
		return w
	return Vector3.INF


## the ids the cat can sense from here (unsolved, in range)
func open_points() -> Array:
	var out := []
	if not is_instance_valid(player):
		return out
	for id in points:
		if int(Puzzles.solved.get(id, 0)) > 0:
			continue
		var p := point_pos(id)
		if p != Vector3.INF and p.distance_to(player.global_position) < RANGE:
			out.append(id)
	return out


func sensing() -> bool:
	if not is_instance_valid(player) or not player.bot.is_empty() and not player.bot.get("sense", false):
		return false
	var spd := Vector2(player.velocity.x, player.velocity.z).length()
	return player.crouch_amt > 0.7 and spd < STILL_SPEED and player.is_on_floor()


func _physics_process(dt: float) -> void:
	_t += dt
	if sensing():
		_still_t += dt
	else:
		_still_t = 0.0
	if _still_t >= WAIT:
		level = minf(level + dt / RISE, 1.0)
	else:
		level = maxf(level - dt / FALL, 0.0)


func _process(_dt: float) -> void:
	var open := open_points() if level > 0.0 else []
	for id in _vis.keys():
		if not id in open:
			for m in _vis[id]:
				m.queue_free()
			_vis.erase(id)
	for id in open:
		if not _vis.has(id):
			_vis[id] = _make_motes()
		var c := point_pos(id)
		var near := 1.0 - clampf(c.distance_to(player.global_position) / RANGE, 0.0, 1.0)
		var a := level * lerpf(0.35, 0.95, near)
		var arr: Array = _vis[id]
		for i in arr.size():
			var m: MeshInstance3D = arr[i]
			var ph := _t * (0.6 + i * 0.09) + i * TAU / MOTES
			m.global_position = c + Vector3(cos(ph) * 0.32, 0.12 + fmod(_t * 0.18 + i * 0.17, 0.5), sin(ph) * 0.32)
			var mm := m.material_override as StandardMaterial3D
			mm.albedo_color.a = a * (0.55 + 0.45 * sin(_t * 3.0 + i))


func _make_motes() -> Array:
	var arr := []
	for i in MOTES:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.026, 0.026)
		m.mesh = q
		m.material_override = _mat.duplicate()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		arr.append(m)
	return arr
