class_name Water
extends Node
## water surface for the forest: depth tinted (shallow sand -> deep teal) from a baked terrain height map,
## moving foam along every bank, chunky scrolling wavelets, and ring ripples wherever something touches it.
## it stays an opaque surface (no depth texture) so it works the same in the web renderer.
##   Water.splash(world_pos, strength)   from anything that hits the water

const CODE := """
shader_type spatial;
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform float water_y = -0.32;
uniform float half_size = 40.0;
uniform vec3 shallow : source_color = vec3(0.3, 0.42, 0.33);
uniform vec3 deep : source_color = vec3(0.07, 0.25, 0.27);
uniform vec3 foam : source_color = vec3(0.92, 0.96, 0.95);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.72, 0.9);
uniform vec2 pond = vec2(19.0, 7.0);
uniform float now = 0.0;
uniform vec4 rip[10];
varying vec3 wp;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), f.x), f.y);
}
float surf(vec2 p, float flow) {
	// the stream runs along +x, the pond only shivers
	vec2 drift = vec2(TIME * 0.5 * flow, 0.0);
	float h = vn((p - drift) * 1.9 + vec2(0.0, TIME * 0.12)) * 0.6;
	h += vn((p - drift * 1.6) * 4.3 - vec2(TIME * 0.2, TIME * 0.17)) * 0.3;
	for (int i = 0; i < 10; i++) {
		float age = now - rip[i].z;
		if (rip[i].w > 0.0 && age < 3.0 && age >= 0.0) {
			float d = distance(p, rip[i].xy);
			float front = age * 0.55;
			float env = exp(-age * 1.4) * (1.0 - smoothstep(front, front + 0.08, d)) * smoothstep(front - 0.5, front - 0.05, d + 0.1);
			h += sin((d - front) * 38.0) * env * rip[i].w * 1.6;
		}
	}
	return h;
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wp.xz;
	float th = texture(hmap, p / (half_size * 2.0) + 0.5).r;
	float depth = water_y - th;
	float flow = smoothstep(4.0, 7.5, distance(p, pond));
	float e = 0.06;
	float h0 = surf(p, flow);
	float hx = surf(p + vec2(e, 0.0), flow);
	float hz = surf(p + vec2(0.0, e), flow);
	vec3 n = normalize(vec3((h0 - hx) * 0.09 / e, 1.0, (h0 - hz) * 0.09 / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float d01 = clamp(depth / 0.3, 0.0, 1.0);
	vec3 col = mix(shallow, deep, d01 * d01 * (3.0 - 2.0 * d01));
	// sky sheen at grazing angles
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 4.0);
	col = mix(col, sky_tint, fres * 0.4);
	// foam: a wobbling line at every bank + streaks where the stream is quick and shallow
	float wob = vn(p * 3.1 + vec2(TIME * 0.3, 0.0)) * 0.05;
	float line = 1.0 - smoothstep(0.006, 0.028 + wob * 0.5, depth);
	float lap = (1.0 - smoothstep(0.0, 0.035, abs(depth - 0.07 - 0.02 * sin(TIME * 1.3 + vn(p * 0.8) * 6.0)))) * 0.4;
	float streak = smoothstep(0.7, 0.82, vn(vec2((p.x - TIME * 0.9) * 0.8, p.y * 4.0))) * flow * (1.0 - smoothstep(0.05, 0.2, depth)) * 0.55;
	float fk = clamp(max(line, lap * step(0.5, vn(p * 5.0 + TIME * 0.2) + 0.1)) + streak, 0.0, 1.0);
	col = mix(col, foam, fk);
	ALBEDO = col;
	ROUGHNESS = mix(0.1, 0.6, fk);
	SPECULAR = 0.45;
	METALLIC = 0.0;
}
"""

static var mat: ShaderMaterial
static var _rip: Array = []
static var _next := 0
static var _now := 0.0
var _cat: Node3D
var _wade_t := 0.0


static func apply(mi: MeshInstance3D) -> Water:
	var sh := Shader.new()
	sh.code = CODE
	mat = ShaderMaterial.new()
	mat.shader = sh
	# bake the terrain heights once: 2 samples per metre is plenty for a shoreline
	var half := ForestLevel.HALF
	var n := int(half * 4.0)
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	for iz in n:
		for ix in n:
			var x := (ix + 0.5) / n * half * 2.0 - half
			var z := (iz + 0.5) / n * half * 2.0 - half
			img.set_pixel(ix, iz, Color(ForestLevel.height(x, z), 0, 0))
	mat.set_shader_parameter("hmap", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("water_y", ForestLevel.WATER_Y)
	mat.set_shader_parameter("half_size", half)
	mat.set_shader_parameter("pond", ForestLevel.POND)
	_rip.clear()
	for i in 10:
		_rip.append(Vector4(0, 0, -100, 0))
	mat.set_shader_parameter("rip", _rip)
	mi.material_override = mat
	var w := Water.new()
	w.name = "WaterFx"
	mi.add_child(w)
	return w


static func is_water(x: float, z: float) -> bool:
	return ForestLevel.height(x, z) < ForestLevel.WATER_Y


## ring ripple at a world position. strength ~0.3 (a frog) .. 1.0 (the cat jumping in)
static func splash(pos: Vector3, strength := 0.6) -> void:
	if mat == null or _rip.is_empty():
		return
	_rip[_next] = Vector4(pos.x, pos.z, _now, strength)
	_next = (_next + 1) % _rip.size()
	mat.set_shader_parameter("rip", _rip)
	if strength >= 0.3:
		Soundscape.play("splash" if strength > 0.6 else "plop", pos, strength, 1.0 + (0.6 - strength) * 0.5)


func set_sky(c: Color) -> void:
	mat.set_shader_parameter("sky_tint", c)


func _process(dt: float) -> void:
	_now += dt
	mat.set_shader_parameter("now", _now)
	if _cat == null or not is_instance_valid(_cat):
		_cat = get_tree().get_first_node_in_group("player") as Node3D
		return
	# the cat wading: a ring every few steps while it moves, a big one when it drops in
	var p := _cat.global_position
	if p.y < ForestLevel.WATER_Y + 0.06 and is_water(p.x, p.z):
		var v: Vector3 = _cat.get("velocity") if _cat.get("velocity") != null else Vector3.ZERO
		var sp := Vector2(v.x, v.z).length()
		_wade_t -= dt * (0.6 + sp)
		if _wade_t < 0.0 and (sp > 0.2 or v.y < -1.0):
			_wade_t = 0.45
			splash(p, clampf(0.35 + sp * 0.12 + maxf(-v.y, 0.0) * 0.2, 0.3, 1.0))
	else:
		_wade_t = 0.0
