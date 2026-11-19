class_name Hub
extends RefCounted
## the farm is the hub world: gates / openings around the yard lead to the other levels,
## and every level has a way back that drops the cat at the matching gate.
##
## farm side:  Hub.gate_on_fence() picks the fence panels that become gates (world.gd),
##             Hub.build_farm() adds the portals, signs + the patio fingerpost.
## level side: Hub.exit() puts a "back to the farm" trigger in a level,
##             Hub.go_home(node, key) for keys like f5.
## travel:     Hub.travel(tree, scene, spawn_key) fades out, keeps the cat style, fades in.
## multiplayer: every player travels on their own (you see cats in the same level as you);
##             the signs show how many cats are behind each gate, net.gd flashes who went where.

## destinations reached from the farm. "spawn" = Engine meta "cat_spawn" set when coming back,
## main.gd looks it up in spawns() to put the cat at that gate.
const DESTS := {
	"forest": {"scene": "res://forest.tscn", "label": "the forest", "sign": "forest", "spawn": "forest_gate"},
	"docks": {"scene": "res://stealth.tscn", "label": "pier 9", "sign": "pier 9", "spawn": "dock_gate"},
	"trail": {"scene": "res://trail.tscn", "label": "the trail", "sign": "running trail", "spawn": "trail_gate"},
	"pit": {"scene": "res://arena.tscn", "label": "the rat pit", "sign": "rat pit", "spawn": "pit_hatch"},
}

## fence gates: which side of the yard + where along it (world.gd fence runs x -16..26, z -9..31)
const FENCE_GATES := {
	"forest": {"side": "west", "at": 12.25},
	"docks": {"side": "east", "at": 3.25},
	"trail": {"side": "north", "at": -3.0},
}
## the rat pit is under the barn: a cellar hatch against its west wall
const PIT_HATCH := Vector3(5.0, 0.0, 23.6)

const FENCE_X0 := -16.0
const FENCE_X1 := 26.0
const FENCE_Z0 := -9.0
const FENCE_Z1 := 31.0

const C_POST := Color(0.5, 0.42, 0.31)
const FADE := 0.35

## lets preview bots walk through portals (normally only the local human player travels)
static var allow_bots := false


# ------------------------------------------------------------------ travel

## where a cat coming back from each level starts on the farm: key -> [pos, yaw]
static func spawns() -> Dictionary:
	var out := {
		"forest_gate": [Vector3(FENCE_X0 + 1.0, 0.02, 12.25), -PI / 2.0],
		"dock_gate": [Vector3(FENCE_X1 - 1.2, 0.02, 3.25), PI / 2.0],
		"trail_gate": [Vector3(-3.0, 0.02, FENCE_Z1 - 1.2), 0.0],
		"pit_hatch": [PIT_HATCH + Vector3(-1.4, 0.02, -1.2), 0.6],
	}
	return out


## change level with a quick fade. spawn_key (optional) is where the next scene puts the cat.
static func travel(tree: SceneTree, scene: String, spawn_key := "", style := "") -> bool:
	if not ResourceLoader.exists(scene):
		return false
	if tree.root.has_node("HubFade"):
		return false       # already on the way
	if spawn_key != "":
		Engine.set_meta("cat_spawn", spawn_key)
	if style != "":
		Engine.set_meta("cat_style", style)
	var label := ""
	for k in DESTS:
		if DESTS[k].scene == scene:
			label = DESTS[k].label
	if scene == "res://main.tscn":
		label = "the farm"
	var f := HubFade.new()
	f.name = "HubFade"
	f.scene = scene
	f.label = label
	tree.root.add_child(f)
	return true


## "the forest", "the farm"... for a scene path (title screen, save slots)
static func scene_name(scene: String) -> String:
	for k in DESTS:
		if DESTS[k].scene == scene:
			return DESTS[k].label
	return "the farm" if scene == "res://main.tscn" or scene == "" else scene.get_file().get_basename()


## back to the farm from any level, at the gate that leads to it
static func go_home(node: Node, from_key: String) -> void:
	var st := ""
	var p := _local_player(node)
	if p:
		st = p.style
	var spawn: String = DESTS[from_key].spawn if DESTS.has(from_key) else ""
	travel(node.get_tree(), "res://main.tscn", spawn, st)


static func _local_player(node: Node) -> CatPlayer:
	var root := node.get_tree().current_scene
	if root == null:
		return null
	var p = root.get("player")
	return p if p is CatPlayer else null


## true for the cat this game instance controls (not preview bots, not remote cats)
static func is_traveller(b: Node) -> bool:
	return b is CatPlayer and ((b as CatPlayer).bot.is_empty() or allow_bots)


## call from a level's _ready: carry the cat style over (the trail / pit / forest already do)
static func arrive(player: CatPlayer) -> void:
	if Engine.get_meta("cat_style", "") != "":
		player.set_style.call_deferred(Engine.get_meta("cat_style"))


## trigger box: the local cat touching it travels
static func trigger(parent: Node3D, pos: Vector3, size: Vector3, rot_y: float, go: Callable, to := "") -> Area3D:
	var area := Area3D.new()
	area.name = "HubTrigger"
	area.add_to_group("hub_trigger")
	area.set_meta("hub_to", to)   # scene it leads to (tests, debug)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	area.add_child(cs)
	area.position = pos
	area.rotation.y = rot_y
	area.monitorable = false
	parent.add_child(area)
	area.body_entered.connect(func(b: Node3D) -> void:
		if is_traveller(b):
			go.call())
	return area


## floating sign; with a scene it also shows how many online cats are in there
static func label(parent: Node3D, pos: Vector3, rot_y: float, text: String, scene := "", size := 48, col := Color(1, 0.97, 0.9)) -> Label3D:
	var s := HubSign.new()
	s.base = text
	s.scene = scene
	s.text = text
	s.font_size = size
	s.pixel_size = 0.0055
	s.outline_size = 10
	s.modulate = col
	s.position = pos
	s.rotation.y = rot_y
	parent.add_child(s)
	return s


## a "back to the farm" way out in another level: a dark opening (if the level has a wall
## there) + sign + trigger. normal = direction the opening faces (into the level).
static func exit(parent: Node3D, pos: Vector3, normal: Vector3, from_key: String, hole := Vector2.ZERO, text := "farm") -> Area3D:
	var n := Vector3(normal.x, 0, normal.z).normalized()
	var ry := atan2(n.x, n.z)
	if hole != Vector2.ZERO:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(hole.x, hole.y, 0.02)
		mi.mesh = bm
		# daylight from the farm side shows through, so it reads as a way out even in the dark
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.75, 0.85, 0.6)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = pos + Vector3(0, hole.y * 0.5, 0) + n * 0.012
		mi.rotation.y = ry
		parent.add_child(mi)
		# broken rim around it
		var along := Vector3(n.z, 0, -n.x)
		var rim := Color(0.25, 0.22, 0.2)
		for s in [-1.0, 1.0]:
			Level.rbox(parent, pos + along * s * (hole.x * 0.5 + 0.03) + Vector3(0, hole.y * 0.5, 0) + n * 0.02, Vector3(0.06, hole.y + 0.06, 0.04), Vector3(0, ry, 0), rim, false)
		Level.rbox(parent, pos + Vector3(0, hole.y + 0.03, 0) + n * 0.02, Vector3(hole.x + 0.12, 0.06, 0.04), Vector3(0, ry, 0), rim, false)
		var glow := OmniLight3D.new()
		glow.position = pos + Vector3(0, hole.y * 0.5, 0) + n * 0.3
		glow.light_color = Color(0.8, 0.9, 0.7)
		glow.light_energy = 0.6
		glow.omni_range = 1.4
		parent.add_child(glow)
	label(parent, pos + Vector3(0, maxf(hole.y, 0.6) + 0.35, 0) + n * 0.05, ry, "%s" % text, "res://main.tscn", 40)
	var w := maxf(hole.x, 1.0) + 0.2
	return trigger(parent, pos + Vector3(0, 0.4, 0) + n * 0.15, Vector3(w, 0.8, 0.4), ry, func() -> void:
		go_home(parent, from_key), "res://main.tscn")


# ------------------------------------------------------------------ farm

## world.gd asks for every fence panel: the key of the gate on it, or ""
static func gate_on_fence(horiz: bool, mid: Vector2, panel_len: float) -> String:
	for k in FENCE_GATES:
		var g: Dictionary = FENCE_GATES[k]
		var on_side := false
		var along := 0.0
		match g.side:
			"west":
				on_side = not horiz and absf(mid.x - FENCE_X0) < 0.1
				along = mid.y
			"east":
				on_side = not horiz and absf(mid.x - FENCE_X1) < 0.1
				along = mid.y
			"north":
				on_side = horiz and absf(mid.y - FENCE_Z1) < 0.1
				along = mid.x
			"south":
				on_side = horiz and absf(mid.y - FENCE_Z0) < 0.1
				along = mid.x
		if on_side and absf(along - float(g.at)) < panel_len * 0.5:
			return k
	return ""


## builds the gate for key in the fence gap at c (gap width w). out = direction off the farm.
static func fence_gate(lv: Node3D, key: String, c: Vector3, w: float) -> void:
	var out := _out_dir(FENCE_GATES[key].side)
	var along := Vector3(-out.z, 0, out.x)
	var ry := atan2(out.x, out.z)
	match key:
		"forest": _gate_forest(lv, c, w, out, along, ry)
		"docks": _gate_docks(lv, c, w, out, along, ry)
		"trail": _gate_trail(lv, c, w, out, along, ry)
	var d: Dictionary = DESTS[key]
	# signs both ways: outside readers rarely matter, but from inside the yard it's the whole point
	label(lv, c + Vector3(0, 1.78, 0) - out * 0.08, ry + PI, d.sign, d.scene)
	trigger(lv, c + out * 0.6 + Vector3(0, 0.6, 0), Vector3(w, 1.2, 0.6), ry, func() -> void:
		var p := _local_player(lv)
		travel(lv.get_tree(), d.scene, "", p.style if p else ""), d.scene)


static func _out_dir(side: String) -> Vector3:
	match side:
		"west": return Vector3(-1, 0, 0)
		"east": return Vector3(1, 0, 0)
		"north": return Vector3(0, 0, 1)
	return Vector3(0, 0, -1)


static func _posts(lv: Node3D, c: Vector3, w: float, along: Vector3, col: Color, h := 1.5) -> void:
	for s in [-1.0, 1.0]:
		Level.box(lv, c + along * s * w * 0.5 + Vector3(0, h * 0.5, 0), Vector3(0.12, h, 0.12), col)
	# lintel sized along the gap (rbox so it lines up whichever way the fence runs)
	Level.rbox(lv, c + Vector3(0, h + 0.05, 0), Vector3(w + 0.12, 0.1, 0.12), Vector3(0, atan2(-along.z, along.x), 0), col, false)


static func _path(lv: Node3D, c: Vector3, out: Vector3, along: Vector3, n: int, col: Color, wobble := 0.2) -> void:
	for k in n:
		var p := c + out * (0.6 + k * 0.7) + along * sin(k * 1.3) * wobble
		Level.rbox(lv, p + Vector3(0, -0.005, 0), Vector3(0.45, 0.02, 0.4), Vector3(0, k * 0.4, 0), col.lightened(0.05 * (k % 3)), false)


static func _gate_forest(lv: Node3D, c: Vector3, w: float, out: Vector3, along: Vector3, ry: float) -> void:
	_posts(lv, c, w, along, C_POST)
	# the gate leaf swung open outward
	Level.rbox(lv, c + out * 0.55 + Vector3(0, 0.6, 0) - along * (w * 0.5 - 0.1), Vector3(0.04, 1.1, 1.1), Vector3(0, ry + 0.35, 0), Color(0.7, 0.6, 0.45))
	_path(lv, c, out, along, 6, Color(0.6, 0.58, 0.54))
	# a couple of ferns + saplings outside, the forest starts here
	for k in 4:
		var p := c + out * (2.0 + k * 1.1) + along * (1.6 if k % 2 == 0 else -1.8)
		Level.box(lv, p + Vector3(0, 0.6, 0), Vector3(0.12, 1.2, 0.12), Color(0.4, 0.3, 0.22), false)
		Level.box(lv, p + Vector3(0, 1.5, 0), Vector3(0.9, 0.9, 0.9), Color(0.25, 0.45, 0.22), false)


static func _gate_docks(lv: Node3D, c: Vector3, w: float, out: Vector3, along: Vector3, ry: float) -> void:
	# steel farm gate standing open + a tarmac lane down to the harbour
	_posts(lv, c, w, along, Color(0.45, 0.47, 0.5))
	for k in 4:
		Level.rbox(lv, c + out * 0.7 - along * (w * 0.5 - 0.1) + Vector3(0, 0.25 + k * 0.28, 0), Vector3(0.03, 0.04, 1.3), Vector3(0, ry + 1.2, 0), Color(0.6, 0.62, 0.64), false)
	for k in 10:
		Level.box(lv, c + out * (0.8 + k * 1.0) + Vector3(0, -0.01, 0), Vector3(1.0, 0.025, 1.0) if absf(out.x) > 0.5 else Vector3(1.0, 0.025, 1.0), Color(0.24, 0.25, 0.27), false)
		if k % 2 == 0:
			Level.box(lv, c + out * (0.8 + k * 1.0) + Vector3(0, 0.005, 0), Vector3(0.4, 0.01, 0.06) if absf(out.x) > 0.5 else Vector3(0.06, 0.01, 0.4), Color(0.9, 0.8, 0.3), false)
	# street lamp: the harbour is at night, the lamp is already on
	var lp := c + out * 2.2 + along * 1.1
	Level.box(lv, lp + Vector3(0, 1.6, 0), Vector3(0.08, 3.2, 0.08), Color(0.3, 0.32, 0.35))
	Level.box(lv, lp + Vector3(0, 3.2, 0) - along * 0.3, Vector3(0.6, 0.06, 0.06) if absf(along.x) > 0.5 else Vector3(0.06, 0.06, 0.6), Color(0.3, 0.32, 0.35), false)
	Level.box(lv, lp + Vector3(0, 3.12, 0) - along * 0.55, Vector3(0.18, 0.08, 0.18), Color(1.0, 0.8, 0.5), false, 3.0)
	var light := OmniLight3D.new()
	light.position = lp + Vector3(0, 3.0, 0) - along * 0.55
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.light_volumetric_fog_energy = 0.0
	lv.add_child(light)
	# a crate + coiled rope waiting by the gate
	Level.box(lv, c + out * 1.2 - along * 1.3 + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), Color(0.55, 0.42, 0.28))
	Level.box(lv, c + out * 1.2 - along * 1.3 + Vector3(0, 0.55, 0), Vector3(0.3, 0.1, 0.3), Color(0.75, 0.68, 0.5), false)


static func _gate_trail(lv: Node3D, c: Vector3, w: float, out: Vector3, along: Vector3, ry: float) -> void:
	# timber arch with orange trail blazes, dirt track heading off
	_posts(lv, c, w, along, Color(0.42, 0.32, 0.22), 2.2)
	for s in [-1.0, 1.0]:
		Level.box(lv, c + along * s * w * 0.5 + Vector3(0, 1.7, 0) - out * 0.07, Vector3(0.14, 0.2, 0.02) if absf(out.z) > 0.5 else Vector3(0.02, 0.2, 0.14), Color(1.0, 0.5, 0.1), false, 0.5)
	for k in 12:
		var p := c + out * (0.6 + k * 0.6) + along * sin(k * 0.6) * 0.3
		Level.rbox(lv, p + Vector3(0, -0.008, 0), Vector3(0.9, 0.02, 0.65), Vector3(0, ry + sin(k * 0.6) * 0.3, 0), Color(0.5, 0.4, 0.28), false)
	# km marker post
	var mp := c + out * 1.4 + along * 1.0
	Level.box(lv, mp + Vector3(0, 0.45, 0), Vector3(0.12, 0.9, 0.12), Color(0.85, 0.82, 0.75))
	Level.box(lv, mp + Vector3(0, 0.82, 0), Vector3(0.13, 0.08, 0.13), Color(1.0, 0.5, 0.1), false, 0.5)
	label(lv, mp + Vector3(0, 1.05, 0), ry + PI, "loop 137 m", "", 28, Color(1.0, 0.75, 0.45))


## cellar hatch against the barn: two doors flung open over a dark stairwell
static func _pit_hatch(lv: Node3D) -> void:
	var c := PIT_HATCH
	var col := Color(0.42, 0.3, 0.2)
	# concrete curb around the opening (low: the cat steps over it)
	Level.box(lv, c + Vector3(0, 0.04, -0.75), Vector3(1.3, 0.08, 0.1), Color(0.6, 0.6, 0.58))
	Level.box(lv, c + Vector3(0, 0.04, 0.75), Vector3(1.3, 0.08, 0.1), Color(0.6, 0.6, 0.58))
	Level.box(lv, c + Vector3(-0.6, 0.04, 0), Vector3(0.1, 0.08, 1.5), Color(0.6, 0.6, 0.58))
	# the dark well + a few steps going down (visual, the ground collider stays)
	Level.box(lv, c + Vector3(0, 0.003, 0), Vector3(1.1, 0.006, 1.4), Color(0.02, 0.02, 0.02), false)
	for k in 3:
		Level.box(lv, c + Vector3(-0.35 + k * 0.25, 0.006, 0), Vector3(0.18, 0.004, 1.3), Color(0.12, 0.1, 0.09), false)
	# open doors lying back on the grass to either side
	Level.rbox(lv, c + Vector3(0, 0.03, -1.45), Vector3(1.2, 0.05, 0.7), Vector3(0.2, 0, 0), col)
	Level.rbox(lv, c + Vector3(0, 0.03, 1.45), Vector3(1.2, 0.05, 0.7), Vector3(-0.2, 0, 0), col)
	label(lv, c + Vector3(-0.7, 1.0, 0), -PI / 2.0, "rat pit v", DESTS.pit.scene, 44, Color(1.0, 0.7, 0.6))
	# scratch marks on the barn wall above it
	for k in 4:
		Level.rbox(lv, c + Vector3(0.75, 0.5 + k * 0.05, -0.2 + k * 0.1), Vector3(0.01, 0.35, 0.02), Vector3(0.0, 0, 0.3), Color(0.3, 0.1, 0.08), false)
	trigger(lv, c + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 1.2), 0.0, func() -> void:
		var p := _local_player(lv)
		travel(lv.get_tree(), DESTS.pit.scene, "", p.style if p else ""), DESTS.pit.scene)


## fingerpost on the patio: one arm per destination, pointing at its gate
static func _fingerpost(lv: Node3D, base: Vector3) -> void:
	Level.box(lv, base + Vector3(0, 0.85, 0), Vector3(0.1, 1.7, 0.1), Color(0.45, 0.35, 0.25))
	var targets := {
		"forest": Vector3(FENCE_X0, 0, 12.25),
		"docks": Vector3(FENCE_X1, 0, 3.25),
		"trail": Vector3(-3.0, 0, FENCE_Z1),
		"pit": PIT_HATCH,
	}
	var k := 0
	for key in targets:
		var to: Vector3 = targets[key] - base
		to.y = 0
		var dir := to.normalized()
		var y := 1.5 - k * 0.24
		var mid := base + dir * 0.5 + Vector3(0, y, 0)
		var ang := atan2(-dir.z, dir.x)
		Level.rbox(lv, mid, Vector3(0.95, 0.16, 0.03), Vector3(0, ang, 0), Color(0.88, 0.84, 0.74), false)
		# one label per face of the arm (a double sided label would hide inside the board)
		var nz := Vector3(sin(ang), 0, cos(ang))
		for side in [1.0, -1.0]:
			var s := label(lv, mid + nz * side * 0.02, ang if side > 0.0 else ang + PI, DESTS[key].sign, DESTS[key].scene, 26, Color(0.2, 0.15, 0.1))
			s.outline_size = 0
			s.double_sided = false
		k += 1


## everything hub-specific on the farm except the fence gaps themselves (world.gd)
static func build_farm(lv: Node3D) -> void:
	_pit_hatch(lv)
	_fingerpost(lv, Vector3(3.9, 0, 5.4))


# ------------------------------------------------------------------ helpers (nodes)

## sign text + live "· 2 cats" when friends are in that level
class HubSign extends Label3D:
	var base := ""
	var scene := ""
	var _t := 0.0

	func _process(dt: float) -> void:
		_t -= dt
		if _t > 0.0 or scene == "":
			return
		_t = 0.5
		var n := Hub.cats_in(scene)
		text = base if n == 0 else "%s\n%d cat%s there" % [base, n, "" if n == 1 else "s"]


## online cats (other players) in a level
static func cats_in(scene: String) -> int:
	var ml := Engine.get_main_loop() as SceneTree
	var net: Node = ml.root.get_node_or_null("Net") if ml else null
	if net == null:
		return 0
	var n := 0
	var peers: Dictionary = net.get("peers")
	for id in peers:
		var p: NetPeer = peers[id]
		if p.hello_seen and p.scene == scene:
			n += 1
	return n


## black fade that survives the scene change (lives on the root window), then fades back in
class HubFade extends CanvasLayer:
	var scene := ""
	var label := ""
	var _rect: ColorRect
	var _title: Label
	var _t := 0.0
	var _switched := false

	func _ready() -> void:
		layer = 100
		process_mode = Node.PROCESS_MODE_ALWAYS
		_rect = ColorRect.new()
		_rect.color = Color(0, 0, 0, 0)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_rect)
		_title = Label.new()
		_title.text = label
		_title.set_anchors_preset(Control.PRESET_CENTER)
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title.offset_left = -300
		_title.offset_right = 300
		_title.add_theme_font_size_override("font_size", 40)
		_title.modulate.a = 0.0
		add_child(_title)

	func _process(dt: float) -> void:
		_t += minf(dt, 0.05)
		if not _switched:
			_rect.color.a = clampf(_t / Hub.FADE, 0.0, 1.0)
			_title.modulate.a = _rect.color.a
			if _t >= Hub.FADE:
				_switched = true
				_t = 0.0
				get_tree().change_scene_to_file(scene)
			return
		# hold black a beat while the level builds, then fade the title + black away
		var a := 1.0 - clampf((_t - 0.25) / (Hub.FADE * 2.0), 0.0, 1.0)
		_rect.color.a = a
		_title.modulate.a = 1.0 - clampf((_t - 0.6) / 0.6, 0.0, 1.0)
		if a <= 0.0 and _title.modulate.a <= 0.0:
			queue_free()
