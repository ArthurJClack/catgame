extends CanvasLayer
## autoload `ExploreMap`: a map of the level you're in that fills in as you explore it (fog of
## war per level). opens on the "map" key (CatKeys, j by default), the pad's back button, or
## the pause menu. shows where the cat is, the place names you've found, puzzles you've found
## (gold paw = solved) and the ways out.
##
## works in every level: a level can say how big it is with `map_info() -> {rect: Rect2 (x, z),
## cell: float, labels: [[text, Vector3]], top: float}` on its root node (the city does), else
## the map frames every mesh in the scene. the picture is one top down orthographic shot of the
## live level (taken the first time you open it), the fog is a byte per cell on top.
##
## saved state (also what online world sync should carry): Save.data.explore[scene_path] =
## {"v": 1, "rect": [x, z, w, h], "cell": c, "w": cols, "h": rows, "fog": base64 bytes}
## one byte per cell, row major from the rect's min corner, 0 = never seen .. 255 = seen.
## merging two maps = max per cell: `merge(scene_path, entry)`. `revealed` fires as it fills.

signal revealed(scene_path: String)
signal opened
signal closed

const VERSION := 1
const MAX_CELLS := 180
const REVEAL_R := 8.0
const SAVE_EVERY := 2.0

var is_open := false
var scene_path := ""
var rect := Rect2()
var cell := 1.0
var gw := 0
var gh := 0
var fog := PackedByteArray()
var labels: Array = []
var top := 30.0
var no_pause := false            # tests / screenshots: keep the game running under the map
static var mem := {}            # state when Save is off (tests)

var _scene: Node = null
var _acc := 0.0
var _save_acc := 0.0
var _dirty := false
var _fog_img: Image
var _fog_tex: ImageTexture
var _map_tex: Texture2D = null
var _shooting := false
var _paused_tree := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _root: Control
var _frame: Control
var _map_rect: TextureRect
var _marks: Control
var _title: Label
var _sub: Label
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


# ---------------------------------------------------------------- state

func _store() -> Dictionary:
	var sv = get_node_or_null("/root/Save")
	if sv and sv.enabled and sv.data is Dictionary:
		if not sv.data.has("explore") or not sv.data.explore is Dictionary:
			sv.data["explore"] = {}
		return sv.data.explore
	return mem


func entry(path := "") -> Dictionary:
	if path == "" or path == scene_path:
		_write()
		path = scene_path
	return _store().get(path, {})


func _write() -> void:
	if scene_path == "" or gw == 0:
		return
	_store()[scene_path] = {"v": VERSION, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "cell": cell,
		"w": gw, "h": gh, "fog": Marshalls.raw_to_base64(fog)}
	_dirty = false


## fold another copy of a level's map in (online sync, another save): max per cell
func merge(path: String, e: Dictionary) -> void:
	if e.is_empty():
		return
	if path == scene_path and gw > 0:
		_fold(e, rect, cell, gw, gh, fog)
		_dirty = true
		_upload()
		revealed.emit(path)
		return
	var cur: Dictionary = _store().get(path, {})
	if cur.is_empty():
		_store()[path] = e.duplicate(true)
		return
	var r := _rect_of(cur)
	var buf := Marshalls.base64_to_raw(str(cur.get("fog", "")))
	var w := int(cur.get("w", 0))
	var h := int(cur.get("h", 0))
	if buf.size() != w * h:
		_store()[path] = e.duplicate(true)
		return
	_fold(e, r, float(cur.get("cell", 1.0)), w, h, buf)
	cur["fog"] = Marshalls.raw_to_base64(buf)


static func _rect_of(e: Dictionary) -> Rect2:
	var a: Array = e.get("rect", [0, 0, 1, 1])
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


## resample entry e into the grid (r, c, w, h, buf) taking the max per cell
static func _fold(e: Dictionary, r: Rect2, c: float, w: int, h: int, buf: PackedByteArray) -> void:
	var er := _rect_of(e)
	var ec := float(e.get("cell", 1.0))
	var ew := int(e.get("w", 0))
	var eh := int(e.get("h", 0))
	var eb := Marshalls.base64_to_raw(str(e.get("fog", "")))
	if eb.size() != ew * eh or ew == 0:
		return
	for j in h:
		var z := r.position.y + (j + 0.5) * c
		var ej := int((z - er.position.y) / ec)
		if ej < 0 or ej >= eh:
			continue
		for i in w:
			var x := r.position.x + (i + 0.5) * c
			var ei := int((x - er.position.x) / ec)
			if ei < 0 or ei >= ew:
				continue
			var v := eb[ej * ew + ei]
			if v > buf[j * w + i]:
				buf[j * w + i] = v


## share of the level seen (0..1)
func explored() -> float:
	if fog.is_empty():
		return 0.0
	var n := 0
	for b in fog:
		if b > 127:
			n += 1
	return float(n) / fog.size()


# ---------------------------------------------------------------- level tracking

func _cat() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if p is CatPlayer and p.is_inside_tree():
			return p
	return null


func _process(dt: float) -> void:
	var sc := get_tree().current_scene
	if sc != _scene:
		_switch(sc)
	if _scene == null or gw == 0:
		return
	_acc += dt
	if _acc >= 0.15 and not get_tree().paused:
		_acc = 0.0
		var c := _cat()
		if c and not _shooting:
			reveal_at(c.global_position)
	_save_acc += dt
	if _dirty and _save_acc > SAVE_EVERY:
		_save_acc = 0.0
		_write()
	if is_open:
		_marks.queue_redraw()


func _switch(sc: Node) -> void:
	if is_open:
		close_map()
	_write()
	_scene = sc
	_map_tex = null
	gw = 0
	fog = PackedByteArray()
	labels = []
	scene_path = ""
	if sc == null or sc.scene_file_path == "" or not sc.is_inside_tree():
		return
	if not get_tree().get_nodes_in_group("title_screen").is_empty():
		_scene = null     # wait: the title screen sits over the farm
		return
	scene_path = sc.scene_file_path
	# the level's size: its own map_info() or frame the meshes (deferred: the level builds in _ready)
	_setup.call_deferred(sc)


func _setup(sc: Node) -> void:
	if sc != _scene or not is_instance_valid(sc):
		return
	var info: Dictionary = sc.call("map_info") if sc.has_method("map_info") else {}
	if info.has("rect"):
		rect = info.rect
		cell = float(info.get("cell", 1.0))
		labels = info.get("labels", [])
		top = float(info.get("top", 30.0))
	else:
		var box := _frame_meshes(sc)
		rect = Rect2(box.position.x - 2.0, box.position.z - 2.0, box.size.x + 4.0, box.size.z + 4.0)
		top = box.end.y + 4.0
		cell = maxf(0.75, maxf(rect.size.x, rect.size.y) / 160.0)
	cell = maxf(cell, maxf(rect.size.x, rect.size.y) / MAX_CELLS)
	gw = maxi(1, ceili(rect.size.x / cell))
	gh = maxi(1, ceili(rect.size.y / cell))
	fog = PackedByteArray()
	fog.resize(gw * gh)
	var old: Dictionary = _store().get(scene_path, {})
	if not old.is_empty():
		_fold(old, rect, cell, gw, gh, fog)
	_fog_img = Image.create_from_data(gw, gh, false, Image.FORMAT_L8, fog)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_mat.set_shader_parameter("fog_tex", _fog_tex)


func _frame_meshes(sc: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [sc]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree() and not (n is CPUParticles3D or n is GPUParticles3D):
			var gi := n as GeometryInstance3D
			var bb: AABB = gi.global_transform * gi.get_aabb()
			if bb.size.x > 400.0 or bb.size.z > 400.0 or bb.size.length() < 0.01:
				continue
			if first:
				out = bb
				first = false
			else:
				out = out.merge(bb)
	if first:
		out = AABB(Vector3(-20, 0, -20), Vector3(40, 10, 40))
	# keep it sane (a far off backdrop shouldn't shrink the level to a dot)
	var c := out.get_center()
	var sx := minf(out.size.x, 320.0)
	var sz := minf(out.size.z, 320.0)
	return AABB(Vector3(c.x - sx * 0.5, out.position.y, c.z - sz * 0.5), Vector3(sx, out.size.y, sz))


## mark what a cat at p can see (radius grows when it's up high)
func reveal_at(p: Vector3) -> void:
	if gw == 0:
		return
	var up := clampf(p.y - 0.3, 0.0, 14.0)
	var r := REVEAL_R + up * 0.7
	var ci := (p.x - rect.position.x) / cell
	var cj := (p.z - rect.position.y) / cell
	var rc := r / cell
	var changed := false
	for j in range(maxi(0, floori(cj - rc)), mini(gh, ceili(cj + rc) + 1)):
		for i in range(maxi(0, floori(ci - rc)), mini(gw, ceili(ci + rc) + 1)):
			var d := Vector2(i + 0.5 - ci, j + 0.5 - cj).length() / rc
			if d > 1.0:
				continue
			var v := int(255.0 * clampf((1.0 - d) * 2.6, 0.0, 1.0))
			var k := j * gw + i
			if v > fog[k]:
				fog[k] = v
				changed = true
	if changed:
		_dirty = true
		if is_open:
			_upload()
		revealed.emit(scene_path)


func _upload() -> void:
	if gw == 0:
		return
	_fog_img.set_data(gw, gh, false, Image.FORMAT_L8, fog)
	_fog_tex.update(_fog_img)


func fog_at(p: Vector3) -> int:
	var i := int((p.x - rect.position.x) / cell)
	var j := int((p.z - rect.position.y) / cell)
	if i < 0 or j < 0 or i >= gw or j >= gh:
		return 0
	return fog[j * gw + i]


# ---------------------------------------------------------------- the top down picture

func _shoot() -> void:
	if _scene == null or gw == 0 or _shooting:
		return
	_shooting = true
	var aspect := rect.size.x / rect.size.y
	var px := 1024
	var sv := SubViewport.new()
	sv.size = Vector2i(px, int(px / aspect)) if aspect >= 1.0 else Vector2i(int(px * aspect), px)
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.msaa_3d = Viewport.MSAA_4X
	add_child(sv)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = rect.size.y
	cam.near = 0.1
	cam.far = top + 80.0
	cam.cull_mask = 0xFFFFF & ~(1 << 1)     # skip layer 2: cars, rain
	cam.position = Vector3(rect.get_center().x, top, rect.get_center().y)
	cam.rotation = Vector3(-PI * 0.5, 0, 0)
	cam.environment = _map_env()
	sv.add_child(cam)
	cam.current = true
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	sv.queue_free()
	if img != null and not img.is_empty():
		_map_tex = ImageTexture.create_from_image(img)
	_shooting = false
	if is_open:
		_map_rect.texture = _map_tex


func _map_env() -> Environment:
	var env: Environment = null
	var stack: Array[Node] = [_scene]
	while not stack.is_empty() and env == null:
		var n: Node = stack.pop_back()
		if n is WorldEnvironment and (n as WorldEnvironment).environment:
			env = ((n as WorldEnvironment).environment).duplicate()
		for ch in n.get_children():
			stack.append(ch)
	if env == null:
		env = Environment.new()
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = maxf(env.ambient_light_energy, 1.2)
	env.glow_enabled = false
	env.ssao_enabled = false
	return env


# ---------------------------------------------------------------- ui

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.position.y = 18
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.2))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_title)
	_sub = Label.new()
	_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.position.y = -40
	_sub.add_theme_font_size_override("font_size", 15)
	_sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_sub)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)
	var border := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07)
	sb.border_color = Color(0.95, 0.78, 0.2, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_expand_margin_all(6)
	border.add_theme_stylebox_override("panel", sb)
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(border)
	_map_rect = TextureRect.new()
	_map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _fog_shader()
	_map_rect.material = _mat
	_frame.add_child(_map_rect)
	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	_frame.add_child(_marks)


func _fog_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float time = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	// a map, not a photo: lift the night shot, cool it a little, grid lines every ~5 m
	vec3 m = pow(clamp(c, 0.0, 1.0), vec3(0.75)) * 1.05;
	m = mix(m, vec3(dot(m, vec3(0.3, 0.55, 0.15))) * vec3(0.95, 1.0, 1.08), 0.25);
	vec2 g = fract(UV * vec2(textureSize(fog_tex, 0)) / 5.0);
	m *= 1.0 - 0.08 * (step(g.x, 0.04) + step(g.y, 0.04));
	float f = texture(fog_tex, UV).r;
	float n = noise(UV * 60.0) * 0.25 + noise(UV * 14.0 + time * 0.03) * 0.35;
	float seen = smoothstep(0.35, 0.65, f + (n - 0.3) * 0.45);
	vec3 fogc = vec3(0.06, 0.06, 0.09) + vec3(0.04, 0.035, 0.06) * noise(UV * 9.0 + time * 0.02);
	// a soft lit edge where the fog ends
	float edge = smoothstep(0.0, 0.5, seen) * smoothstep(1.0, 0.5, seen);
	COLOR = vec4(mix(fogc, m, seen) + vec3(0.9, 0.7, 0.3) * edge * 0.25, 1.0);
}
"""
	return s


func _layout() -> void:
	var vs := _root.get_viewport_rect().size
	var avail := Vector2(vs.x - 120.0, vs.y - 150.0)
	var aspect := rect.size.x / maxf(rect.size.y, 0.01)
	var sz := Vector2(avail.y * aspect, avail.y)
	if sz.x > avail.x:
		sz = Vector2(avail.x, avail.x / aspect)
	_frame.position = Vector2((vs.x - sz.x) * 0.5, 70.0 + (avail.y - sz.y) * 0.5)
	_frame.size = sz


func _to_map(p: Vector3) -> Vector2:
	var u := (p.x - rect.position.x) / rect.size.x
	var v := (p.z - rect.position.y) / rect.size.y
	return Vector2(u, v) * _frame.size


func _draw_marks() -> void:
	if gw == 0:
		return
	_mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
	var font := ThemeDB.fallback_font
	# place names you've seen
	for l in labels:
		var p: Vector3 = l[1]
		if fog_at(p) < 140:
			continue
		var at := _to_map(p)
		var txt := str(l[0])
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_marks.draw_string_outline(font, at - Vector2(w * 0.5, -4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		_marks.draw_string(font, at - Vector2(w * 0.5, -4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.9, 0.85))
	# ways out
	for n in get_tree().get_nodes_in_group("hub_trigger"):
		if not (n is Node3D) or not _scene.is_ancestor_of(n):
			continue
		var p := (n as Node3D).global_position
		if fog_at(p) < 140:
			continue
		var at := _to_map(p)
		_marks.draw_rect(Rect2(at - Vector2(6, 8), Vector2(12, 16)), Color(0.35, 0.85, 0.5))
		_marks.draw_rect(Rect2(at - Vector2(6, 8), Vector2(12, 16)), Color(0, 0, 0), false, 2.0)
		var to := str(n.get_meta("hub_to", ""))
		var nm := "way out" if to == "" else "to " + Net.scene_label(to)
		_marks.draw_string_outline(font, at + Vector2(10, 5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.85))
		_marks.draw_string(font, at + Vector2(10, 5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 1.0, 0.7))
	# puzzles you've found (the cat sense points), gold = solved
	var pz := _scene.get_node_or_null("Puzzles")
	if pz != null and pz.get("sense") != null and pz.sense != null:
		for id in pz.sense.points:
			var p: Vector3 = pz.sense.point_pos(id)
			if fog_at(p) < 140:
				continue
			var solved := int(Puzzles.solved.get(id, 0)) > 0
			var at := _to_map(p)
			var col := Color(1.0, 0.8, 0.2) if solved else Color(0.85, 0.85, 1.0)
			_marks.draw_circle(at, 9.0, Color(0, 0, 0, 0.7))
			_marks.draw_circle(at, 7.0, col)
			var g := "✓" if solved else "?"
			_marks.draw_string(font, at + Vector2(-4, 5), g if font.has_char(g.unicode_at(0)) else ("*" if solved else "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.08, 0.05))
			var nm: String = Puzzles.LIST[id][0] if solved and Puzzles.LIST.has(id) else "something odd here"
			_marks.draw_string_outline(font, at + Vector2(12, 5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.85))
			_marks.draw_string(font, at + Vector2(12, 5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# the cat: an arrow pointing where it faces, pulsing
	var c := _cat()
	if c:
		var at := _to_map(c.global_position)
		var yaw: float = c.get("yaw") if c.get("yaw") != null else c.global_rotation.y
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(-fwd.y, fwd.x)
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.008)
		var s := 11.0 * pulse
		var pts := PackedVector2Array([at + fwd * s, at - fwd * s * 0.6 + side * s * 0.65, at - fwd * s * 0.25, at - fwd * s * 0.6 - side * s * 0.65])
		_marks.draw_circle(at, s * 1.5, Color(1.0, 0.8, 0.2, 0.18))
		_marks.draw_colored_polygon(pts, Color(1.0, 0.82, 0.25))
		pts.append(pts[0])
		_marks.draw_polyline(pts, Color(0, 0, 0), 2.0)


func open_map() -> void:
	if is_open or gw == 0 or _scene == null:
		return
	var gm = get_node_or_null("/root/GameMenu")
	if gm and gm.is_open:
		gm.close_menu()
	is_open = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	CatKeys.blocked = true
	_paused_tree = Net.peers.is_empty() and not Net.on_server() and not no_pause
	_upload()
	_layout()
	_title.text = Net.scene_label(scene_path)
	_sub.text = "%d%% explored  ·  %s / esc close" % [roundi(explored() * 100.0), CatKeys.describe("map")]
	_map_rect.texture = _map_tex
	_root.visible = true
	if _map_tex == null:
		await _shoot()
	if _paused_tree and is_open:
		get_tree().paused = true
	opened.emit()


func close_map() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	CatKeys.blocked = false
	if _paused_tree:
		get_tree().paused = false
	_paused_tree = false
	if not OS.has_feature("web"):
		Input.mouse_mode = _mouse_before if _mouse_before != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED
	closed.emit()


func toggle() -> void:
	if is_open:
		close_map()
	else:
		open_map()


func _input(event: InputEvent) -> void:
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	var hit := false
	if key or (event is InputEventMouseButton and event.pressed):
		var b := CatKeys.from_event(event)
		for mb in CatKeys.binds("map"):
			if CatKeys.same(mb, b):
				hit = true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		hit = true
	if is_open and key and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		hit = true
	if is_open and event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START]:
		hit = true
	if not hit:
		return
	if is_open:
		close_map()
		get_viewport().set_input_as_handled()
		return
	var gm = get_node_or_null("/root/GameMenu")
	if (gm and gm.is_open) or not _can_open():
		return
	open_map()
	get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if DisplayServer.get_name() == "headless" or gw == 0:
		return false
	if Net.ui and Net.ui is CanvasItem and (Net.ui as CanvasItem).visible:
		return false
	if get_tree().root.has_node("HubFade") or not get_tree().get_nodes_in_group("title_screen").is_empty():
		return false
	for p in get_tree().get_nodes_in_group("player"):
		if p is CatPlayer and (p as CatPlayer).bot.is_empty():
			return true
	return false
