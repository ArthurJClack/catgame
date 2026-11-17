extends Node3D
## critter lab: films each forest animal side on, running on a treadmill (the animal stays put, the grid
## floor scrolls), so gaits can be compared. works with any version of wildlife.gd that has the same states,
## which is how the before / after clips were made. run (xvfb + opengl3):
##   godot --path . res://critterlab.tscn -- [--only deer,fox] [--label after] [--secs 4] [--report]
## --report skips the camera work and prints stride rate / duty / gait per animal (headless is fine).

const FAUNA := ["hedgehog", "crow", "lizard", "duck", "woodpecker", "owl", "hawk"]
## kind, state, caption, seconds, camera distance, slow motion, look height
const SEGS := [
	["deer", "walk", "deer walk", 4.0, 3.8, 1.0, 0.85],
	["deer", "flee", "deer flat out", 3.0, 4.6, 0.35, 0.85],
	["fox", "trot", "fox trot", 3.0, 1.6, 0.5, 0.3],
	["fox", "retreat", "fox bolting", 2.5, 2.0, 0.3, 0.3],
	["rabbit", "hop", "rabbit hopping about", 3.0, 0.8, 0.5, 0.12],
	["rabbit", "flee", "rabbit fleeing", 2.0, 1.2, 0.25, 0.12],
	["squirrel", "scamper", "squirrel scamper", 2.0, 0.6, 0.3, 0.08],
	["hedgehog", "snuffle", "hedgehog", 3.0, 0.5, 1.0, 0.06],
	["crow", "strut", "crow walking", 3.0, 0.9, 0.6, 0.16],
	["bird", "hop", "songbird hopping", 2.0, 0.35, 0.4, 0.05],
	["lizard", "skitter", "lizard sprint", 2.0, 0.3, 0.12, 0.015],
]

var cam: Camera3D
var floor_mat: ShaderMaterial
var caption: Label
var stats: Label
var chart: Control
var label := ""
var critter: Node3D
var origin := Vector3.ZERO
var travel := 0.0
var seg := -1
var seg_t := 0.0
var segs: Array = []
var report := false
var hist: Array = []
var post: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--label")
	if i >= 0:
		label = args[i + 1]
	var only: PackedStringArray = []
	i = args.find("--only")
	if i >= 0:
		only = args[i + 1].split(",")
	var secs := 0.0
	i = args.find("--secs")
	if i >= 0:
		secs = float(args[i + 1])
	report = "--report" in args
	for s in SEGS:
		if only.is_empty() or (s[0] as String) in only:
			var c: Array = s.duplicate()
			if secs > 0.0:
				c[3] = secs
			segs.append(c)
	process_priority = -100
	post = Node.new()
	post.process_priority = 100
	post.set_script(_post_script())
	post.set("lab", self)
	add_child(post)
	origin = ForestLevel.SPAWN
	origin.y = ForestLevel.height(origin.x, origin.z)
	_world()
	_next()


func _post_script() -> GDScript:
	var g := GDScript.new()
	g.source_code = "extends Node\nvar lab\nfunc _process(dt):\n\tlab.after_critters(dt)\n"
	g.reload()
	return g


func _world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.72, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var pl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	pl.mesh = pm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform float off = 0.0;
uniform float cell = 0.1;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float grid(vec2 p) {
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(1e-4));
	return 1.0 - min(min(g.x, g.y), 1.0);
}
void fragment() {
	vec2 p = vec2(wp.x, wp.z - off);
	float a = grid(p / cell);
	float b = grid(p / (cell * 10.0));
	ALBEDO = mix(vec3(0.36, 0.42, 0.3), vec3(0.88, 0.9, 0.82), max(a * 0.45, b * 0.9));
	ROUGHNESS = 1.0;
}
"""
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = sh
	pl.material_override = floor_mat
	pl.position = origin
	add_child(pl)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	caption = Label.new()
	caption.position = Vector2(28, 20)
	caption.add_theme_font_size_override("font_size", 34)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	ui.add_child(caption)
	stats = Label.new()
	stats.position = Vector2(28, 66)
	stats.add_theme_font_size_override("font_size", 22)
	stats.add_theme_color_override("font_outline_color", Color.BLACK)
	stats.add_theme_constant_override("outline_size", 6)
	ui.add_child(stats)
	chart = Control.new()
	chart.position = Vector2(28, 0)
	chart.draw.connect(_draw_chart)
	ui.add_child(chart)


func _next() -> void:
	if critter:
		critter.queue_free()
		critter = null
	seg += 1
	seg_t = 0.0
	hist.clear()
	if seg >= segs.size():
		Engine.time_scale = 1.0
		get_tree().quit()
		return
	var s: Array = segs[seg]
	var kind: String = s[0]
	var c: Node3D = Fauna.new() if kind in FAUNA else Critter.new()
	c.set("kind", kind)
	c.set("home", origin)
	add_child(c)
	critter = c
	Engine.time_scale = 1.0 if report else float(s[5])
	var d: float = s[4]
	var look_y: float = s[6]
	var h: float = look_y + d * 0.12
	cam.position = origin + Vector3(d, h, 0.0)
	cam.look_at(origin + Vector3(0, look_y, 0))
	floor_mat.set_shader_parameter("cell", 0.5 if d > 3.0 else (0.2 if d > 1.0 else 0.05))
	var slow := "" if float(s[5]) >= 1.0 else "   (%d%% speed)" % roundi(float(s[5]) * 100.0)
	caption.text = ((label.to_upper() + "   ") if label != "" else "") + (s[2] as String) + slow
	_avg = {"n": 0, "f": 0.0, "duty": 0.0, "v": 0.0, "gaits": {}}


var _avg := {}


func _process(dt: float) -> void:
	if critter == null:
		return
	var s: Array = segs[seg]
	critter.set("state", s[1])
	critter.set("state_t", 99.0)
	critter.set("target", critter.position + Vector3(0, 0, -50))


func after_critters(dt: float) -> void:
	if critter == null:
		return
	var s: Array = segs[seg]
	var p := critter.position
	travel += -(p.z - origin.z)
	critter.position = Vector3(origin.x, p.y, origin.z)
	floor_mat.set_shader_parameter("off", fposmod(travel, 100.0))
	var v: float = critter.get("speed")
	var g = critter.get("gait")
	if g != null:
		var gg: CritterGait = g
		stats.text = "%s   %.1f m/s   %.1f strides/s   feet down %d%% of stride" % [gg.gait.replace("_", " "), v, gg.freq, roundi(gg.duty * 100.0)]
		hist.append(gg.contacts.duplicate())
		if hist.size() > 90:
			hist.pop_front()
		if seg_t > 1.0:
			_avg.n += 1
			_avg.f += gg.freq
			_avg.duty += gg.duty
			_avg.v += v
			_avg.gaits[gg.gait] = true
	else:
		stats.text = "%.1f m/s" % v
	chart.queue_redraw()
	seg_t += dt
	if seg_t > float(s[3]):
		if report and _avg.n > 0:
			print("LAB %-10s %-8s v=%.2f m/s  f=%.2f Hz  stride=%.2f m  duty=%.2f  gaits=%s" % [s[0], s[1], _avg.v / _avg.n, _avg.f / _avg.n, _avg.v / maxf(_avg.f, 0.01), _avg.duty / _avg.n, ",".join(_avg.gaits.keys())])
		_next()


## footfall chart (hildebrand style): one row per foot, a bar while it's on the ground, newest on the right
func _draw_chart() -> void:
	if hist.is_empty():
		return
	var g = critter.get("gait") if critter else null
	if g == null:
		return
	var gg: CritterGait = g
	var vp := chart.get_viewport_rect().size
	var rows := gg.info.size()
	var y0 := vp.y - 30.0 - rows * 18.0
	var w := 4.0
	chart.draw_rect(Rect2(-8, y0 - 8, 90 * w + 70, rows * 18.0 + 14), Color(0, 0, 0, 0.45))
	for r in rows:
		var nm: String = gg.info[r]["name"]
		chart.draw_string(ThemeDB.fallback_font, Vector2(0, y0 + r * 18.0 + 13), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
		for k in hist.size():
			var ct: Array = hist[k]
			if r < ct.size() and ct[r]:
				chart.draw_rect(Rect2(40 + k * w, y0 + r * 18.0 + 2, w, 13), Color(1.0, 0.85, 0.3) if (gg.info[r]["fore"] as bool) else Color(0.5, 0.85, 1.0))
