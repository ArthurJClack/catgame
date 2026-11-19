class_name PSX
extends RefCounted
## psx style rendering kit:
##  - tiny procedural textures (32x32, nearest filtered, limited palette)
##  - spatial shader with vertex snapping (wobbly verts) + affine texture mapping
##  - box / cylinder builders with world scaled uvs and subdivided faces
##  - full screen post: low res pixels, 15 bit color, 4x4 bayer dither

const TEX := 32
static var _tex := {}
static var _mats := {}
static var _shader: Shader
static var _rng := RandomNumberGenerator.new()

## global look knobs (stealth_main exposes them on f-keys)
static var snap_lines := 160.0
static var affine := 1.0


# ------------------------------------------------------------------ shader
const SPATIAL := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float emission = 0.0;
uniform bool cutout = false;
uniform bool unshaded = false;
uniform float wave = 0.0;
uniform vec2 scroll = vec2(0.0);
global uniform float psx_snap;
global uniform float psx_affine;
// affine warp only for verts at least this far (m) from the camera. closer verts lean back to
// perspective correct uvs. real psx games subdivided near polys for the same reason: a vert
// right next to (or behind) the lens makes screen space uvs collapse, so textures shrink and smear
uniform float affine_near = 1.5;
varying vec3 aff;

void vertex() {
	if (wave > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		VERTEX.y += (sin(w.x * 0.7 + TIME * 1.3) + cos(w.z * 0.9 + TIME * 1.1)) * wave;
	}
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (clip.w > 0.05 && psx_snap > 0.0) {
		vec2 grid = vec2(psx_snap * VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, psx_snap) * 0.5;
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * grid + 0.5) / grid;
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
	vec2 uv = UV + scroll * TIME;
	// weight W / w per vert: W = w gives pure affine, W = const gives perspective correct
	float W = max(clip.w, affine_near);
	aff = vec3(uv * W, W);
}

void fragment() {
	vec2 persp = aff.xy / aff.z;
	vec2 uv = mix(UV, persp, psx_affine);
	if (psx_affine < 0.5) { uv = UV; }
	vec4 t = texture(tex, uv);
	if (cutout && t.a < 0.5) { discard; }
	vec3 c = t.rgb * tint.rgb * COLOR.rgb;
	if (unshaded) {
		ALBEDO = vec3(0.0);
		EMISSION = c * max(emission, 1.0);
	} else {
		ALBEDO = c;
		EMISSION = c * emission;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

const POST := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float lines = 240.0;
uniform float levels = 32.0;
uniform float dither_amt = 1.0;
const float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 ss = 1.0 / SCREEN_PIXEL_SIZE;
	float px = max(1.0, floor(ss.y / lines + 0.5));
	vec2 cell = floor(FRAGCOORD.xy / px);
	vec2 uv = (cell * px + px * 0.5) * SCREEN_PIXEL_SIZE;
	vec3 c = textureLod(screen, uv, 0.0).rgb;
	int bx = int(mod(cell.x, 4.0));
	int by = int(mod(cell.y, 4.0));
	float b = (bayer[by * 4 + bx] + 0.5) / 16.0 - 0.5;
	c = c + b * dither_amt / (levels - 1.0);
	c = floor(c * (levels - 1.0) + 0.5) / (levels - 1.0);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""


static func setup_globals() -> void:
	# global shader uniforms so every psx material follows the same knobs
	if not ProjectSettings.has_setting("shader_globals/psx_snap"):
		RenderingServer.global_shader_parameter_add("psx_snap", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, snap_lines)
		RenderingServer.global_shader_parameter_add("psx_affine", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, affine)
	apply_globals()


static func apply_globals() -> void:
	RenderingServer.global_shader_parameter_set("psx_snap", snap_lines)
	RenderingServer.global_shader_parameter_set("psx_affine", affine)


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SPATIAL
	return _shader


static func post_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = POST
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func mat(kind: String, tint := Color.WHITE, emission := 0.0, extra := {}) -> ShaderMaterial:
	var key := "%s_%s_%.2f_%s" % [kind, tint.to_html(), emission, str(extra)]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("tex", texture(kind))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("emission", emission)
	for k in extra:
		m.set_shader_parameter(k, extra[k])
	_mats[key] = m
	return m


# ------------------------------------------------------------------ textures
static func texture(kind: String) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	_rng.seed = hash(kind)
	for y in TEX:
		for x in TEX:
			img.set_pixel(x, y, _texel(kind, x, y))
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


static func _n() -> float:
	return _rng.randf()


## 15 bit color, like the real thing
static func _q(c: Color) -> Color:
	return Color(floorf(c.r * 31.0 + 0.5) / 31.0, floorf(c.g * 31.0 + 0.5) / 31.0, floorf(c.b * 31.0 + 0.5) / 31.0, c.a)


static func _h(x: int, y: int, s: int) -> float:
	var v := sin(float(x * 127 + y * 311 + s * 74.7)) * 43758.5453
	return v - floorf(v)


static func _texel(kind: String, x: int, y: int) -> Color:
	var n := _n()
	var c := Color.WHITE
	match kind:
		"concrete":
			var g := 0.5 + n * 0.12 + _h(x / 4, y / 4, 1) * 0.1
			c = Color(g, g * 0.98, g * 0.95)
			if (x + y * 3) % 29 == 0 or (x == 9 and y > 12 and y < 22) or (y == 20 + (x / 6) and x > 14):
				c = c.darkened(0.35) # cracks
			if _h(x / 8, y / 8, 9) > 0.8:
				c = c.darkened(0.15) # oil stains
		"concrete_slab":
			var g := 0.52 + n * 0.1
			c = Color(g, g, g * 0.96)
			if x == 0 or y == 0:
				c = c.darkened(0.25) # expansion joints
		"metal":
			var g := 0.42 + n * 0.08
			c = Color(g * 0.95, g, g * 1.05)
			if x % 16 == 0 or y % 16 == 0:
				c = c.darkened(0.3)
			if (x % 16 == 2 or x % 16 == 13) and (y % 16 == 2 or y % 16 == 13):
				c = c.lightened(0.35) # rivets
		"tread":
			var g := 0.45 + n * 0.06
			c = Color(g, g, g * 1.04)
			var cx := x % 8
			var cy := y % 8
			var d := (cx - 3) if (x / 8 + y / 8) % 2 == 0 else (3 - cx)
			if absi(cy - 3 - d) <= 0 and cx > 0 and cx < 7:
				c = c.lightened(0.4) # diamond plate ridges
		"grate":
			var g := 0.32 + n * 0.08
			c = Color(g, g * 0.97, g * 0.92)
			if x % 4 != 0 and y % 8 != 0:
				c.a = 0.0
		"rust":
			var r := 0.45 + n * 0.25
			c = Color(r, r * 0.5, r * 0.28)
			if _h(x / 3, y / 3, 4) > 0.6:
				c = Color(0.38, 0.38, 0.4).lerp(c, 0.3)
		"corrugated":
			var ridge := 0.75 + 0.25 * sin(float(x) / TEX * TAU * 4.0)
			var g := (0.5 + n * 0.06) * ridge
			c = Color(g, g, g)
			if _h(x, y / 5, 3) > 0.92:
				c = Color(0.5, 0.3, 0.18) # rust streaks
		"crate":
			var plank := y % 8
			var g := 0.62 + n * 0.1 + _h(0, y / 8, 5) * 0.08
			c = Color(g, g * 0.74, g * 0.48)
			if plank == 0:
				c = c.darkened(0.55)
			if x == 0 or x == TEX - 1 or (x == 2 and plank > 0) or (x == TEX - 3 and plank > 0):
				c = c.darkened(0.35) # frame boards
			if plank > 1 and plank < 7 and (x + y) % 11 == 0:
				c = c.darkened(0.15) # grain
		"cardboard":
			var g := 0.7 + n * 0.06
			c = Color(g * 0.95, g * 0.72, g * 0.46)
			if y == 15 or y == 16:
				c = Color(0.78, 0.74, 0.6) # tape
			if x > 20 and x < 28 and y > 22 and y < 27 and _h(x, y, 2) > 0.4:
				c = c.darkened(0.5) # stencil
		"hazard":
			var s := ((x + y) / 6) % 2
			c = Color(0.92, 0.72, 0.1) if s == 0 else Color(0.08, 0.08, 0.08)
			c = c.darkened(n * 0.15)
		"container":
			var ridge := 0.7 + 0.3 * absf(sin(float(x) / TEX * PI * 6.0))
			var g := (0.85 + n * 0.1) * ridge
			c = Color(g, g, g)
			if _h(x / 2, y / 6, 8) > 0.9:
				c = Color(0.45, 0.26, 0.15)
		"brick":
			var row := y / 4
			var off := 4 if row % 2 == 0 else 0
			var g := 0.55 + n * 0.12
			c = Color(g, g * 0.5, g * 0.38)
			if y % 4 == 0 or (x + off) % 8 == 0:
				c = Color(0.4, 0.38, 0.36)
		"wood":
			var g := 0.5 + n * 0.08 + 0.06 * sin(float(y) * 0.9 + _h(x / 8, 0, 2) * 6.0)
			c = Color(g, g * 0.7, g * 0.45)
			if x % 8 == 0:
				c = c.darkened(0.4)
		"water":
			var g := 0.25 + n * 0.08 + 0.08 * sin(float(x + y) * 0.6)
			c = Color(g * 0.5, g * 0.8, g)
		"screen":
			c = Color(0.1, 0.9, 0.4) * (0.6 + 0.4 * float(y % 2)) if (x > 2 and x < 29 and y > 3 and y < 28 and _h(x / 3, y / 2, 6) > 0.35) else Color(0.03, 0.12, 0.06)
		"light":
			c = Color(1, 1, 1) if (x > 1 and x < 30 and y > 1 and y < 30) else Color(0.3, 0.3, 0.3)
		"fabric":
			var g := 0.6 + n * 0.1 + (0.1 if (x + y) % 4 < 2 else 0.0)
			c = Color(g, g, g)
		"chainlink":
			var a := (x + y) % 8
			var b := (x - y + 64) % 8
			c = Color(0.62, 0.64, 0.66) * (0.8 + n * 0.3)
			if a != 0 and b != 0:
				c.a = 0.0
		"rubber":
			var g := 0.12 + n * 0.05
			c = Color(g, g, g)
		"paint":
			var g := 0.85 + n * 0.12
			c = Color(g, g, g)
			if _h(x / 2, y / 2, 11) > 0.97:
				c = Color(0.62, 0.6, 0.58) # chipped
		"sign":
			c = Color(0.95, 0.85, 0.15) if (absi(x - 16) + absi(y - 16) < 14) else Color(0.08, 0.08, 0.08)
			if x > 14 and x < 18 and y > 8 and y < 20:
				c = Color(0.08, 0.08, 0.08)
			if x > 14 and x < 18 and y > 21 and y < 25:
				c = Color(0.08, 0.08, 0.08)
		_:
			var g := 0.6 + n * 0.1
			c = Color(g, g, g)
	return _q(c)


# ------------------------------------------------------------------ meshes
## box with uvs in world meters (density = texture repeats per meter) and faces split
## into cells no bigger than `cell` meters, so the affine warp stays authentic but sane
static func box_mesh(size: Vector3, density := 1.0, cell := 1.2, ao_base := -100.0, seed := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	# normal, u axis, v axis
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.RIGHT, Vector3.BACK, Vector3.DOWN],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN],
		[Vector3.BACK, Vector3.LEFT, Vector3.DOWN],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + int(size.x * 1000 + size.y * 77 + size.z * 13)
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var su := absf(u.dot(size))
		var sv := absf(v.dot(size))
		var nu := maxi(1, ceili(su / cell))
		var nv := maxi(1, ceili(sv / cell))
		var origin := n * absf(n.dot(h)) - u * su * 0.5 - v * sv * 0.5
		for i in nu:
			for j in nv:
				var p := []
				var uvs := []
				for k in [[0, 0], [1, 0], [1, 1], [0, 1]]:
					var a := float(i + k[0]) / nu * su
					var b := float(j + k[1]) / nv * sv
					p.append(origin + u * a + v * b)
					uvs.append(Vector2(a, b) * density)
				var shade := 1.0 + rng.randf_range(-0.04, 0.04)
				var cols := []
				for q in p:
					var ao := 1.0
					if ao_base > -99.0:
						# fake baked ao: darker toward the floor, like vertex lit psx levels
						ao = lerpf(0.55, 1.0, clampf((ao_base + q.y + h.y) / 1.4, 0.0, 1.0))
					cols.append(Color(shade * ao, shade * ao, shade * ao))
				for t in [[0, 1, 2], [0, 2, 3]]:
					for idx in t:
						st.set_normal(n)
						st.set_color(cols[idx])
						st.set_uv(uvs[idx])
						st.add_vertex(p[idx])
	return st.commit()


## flat shaded cylinder along +Y, unit height, centered. uvs wrap around in meters
static func cyl_mesh(radius: float, height: float, segs := 8, density := 1.0, caps := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hh := height * 0.5
	var circ := TAU * radius
	var rings := maxi(1, ceili(height / 1.2))
	for s in segs:
		var a0 := float(s) / segs * TAU
		var a1 := float(s + 1) / segs * TAU
		var p0 := Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := Vector3(cos(a1), 0, sin(a1)) * radius
		var n := ((p0 + p1) * 0.5).normalized()
		var u0 := float(s) / segs * circ * density
		var u1 := float(s + 1) / segs * circ * density
		var sh := 0.94 + 0.06 * float(s % 2)
		for r in rings:
			var y0 := -hh + height * float(r) / rings
			var y1 := -hh + height * float(r + 1) / rings
			var q := [p0 + Vector3(0, y0, 0), p1 + Vector3(0, y0, 0), p1 + Vector3(0, y1, 0), p0 + Vector3(0, y1, 0)]
			var uv := [Vector2(u0, y0 * density), Vector2(u1, y0 * density), Vector2(u1, y1 * density), Vector2(u0, y1 * density)]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(n)
				st.set_color(Color(sh, sh, sh))
				st.set_uv(uv[idx])
				st.add_vertex(q[idx])
		if caps:
			for side in [-1, 1]:
				var cn := Vector3(0, side, 0)
				var c := Vector3(0, hh * side, 0)
				var tri := [c, p0 + c, p1 + c] if side < 0 else [c, p1 + c, p0 + c]
				for v in tri:
					st.set_normal(cn)
					st.set_color(Color(0.9, 0.9, 0.9))
					st.set_uv(Vector2(v.x, v.z) * density)
					st.add_vertex(v)
	return st.commit()


## a quad (both sides) for fences, signs etc. size in meters, faces +Z
static func quad_mesh(size: Vector2, density := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	for side in [1, -1]:
		var p := [Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, hy, 0)]
		var uv := [Vector2(0, size.y), Vector2(size.x, size.y), Vector2(size.x, 0), Vector2(0, 0)]
		var order := [0, 1, 2, 0, 2, 3] if side == 1 else [0, 2, 1, 0, 3, 2]
		for idx in order:
			st.set_normal(Vector3(0, 0, side))
			st.set_color(Color.WHITE)
			st.set_uv(uv[idx] * density)
			st.add_vertex(p[idx])
	return st.commit()
