class_name Atmos
extends Node3D
## outdoor look: gradient sky with a sun disc (stars + moon at night), drifting low poly clouds,
## sun / fog / post settings, and air particles (pollen motes in the light, falling leaves).
## also owns the time of day: `hour` 0..24, everything else is derived from it in apply_time().
##   var a := Atmos.new(); add_child(a)   (builds its own WorldEnvironment + sun)

const SKY_CODE := """
shader_type sky;
uniform vec3 top : source_color = vec3(0.2, 0.42, 0.8);
uniform vec3 horizon : source_color = vec3(0.72, 0.8, 0.84);
uniform vec3 ground : source_color = vec3(0.3, 0.38, 0.28);
uniform vec3 sun_col : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_glow = 1.0;
uniform float stars = 0.0;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, top, pow(up, 0.5));
	if (d.y < 0.0) {
		col = mix(horizon, ground, clamp(-d.y * 5.0, 0.0, 1.0));
	}
	float sd = max(dot(d, sun_dir), 0.0);
	// warm haze toward the sun, strongest near the horizon
	col += sun_col * (pow(sd, 6.0) * 0.16 + pow(sd, 48.0) * 0.4) * sun_glow * (1.0 - up * 0.5);
	col += sun_col * smoothstep(0.99935, 0.9997, sd) * 12.0 * step(0.0, d.y + 0.02);
	if (stars > 0.0 && d.y > 0.0) {
		// blocky stars: hash a grid on the dome
		vec2 g = d.xz / (d.y + 0.35) * 46.0;
		vec2 c = floor(g);
		float r = h2(c);
		vec2 f = fract(g) - 0.5;
		float tw = 0.75 + 0.25 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
		float s = step(0.985, r) * step(max(abs(f.x), abs(f.y)), 0.09 + 0.1 * h2(c + 3.0)) * tw;
		col += vec3(0.9, 0.95, 1.0) * s * stars * smoothstep(0.0, 0.25, d.y) * 1.6;
		float md = dot(d, moon_dir);
		col += vec3(0.85, 0.9, 1.0) * (smoothstep(0.9988, 0.9992, md) * 2.2 + pow(max(md, 0.0), 90.0) * 0.25) * stars;
	}
	COLOR = col;
}
"""

## time of day keyframes: hour, sky top, horizon, sun colour, sun energy, ambient colour, ambient energy, fog colour, stars
const KEYS := [
	[0.0, Color(0.012, 0.02, 0.055), Color(0.04, 0.06, 0.11), Color(0.55, 0.65, 1.0), 0.22, Color(0.22, 0.3, 0.5), 0.3, Color(0.04, 0.06, 0.1), 1.0],
	[4.6, Color(0.02, 0.03, 0.08), Color(0.07, 0.09, 0.15), Color(0.55, 0.65, 1.0), 0.22, Color(0.22, 0.3, 0.5), 0.3, Color(0.05, 0.07, 0.12), 1.0],
	[6.0, Color(0.2, 0.3, 0.55), Color(0.95, 0.6, 0.4), Color(1.0, 0.55, 0.3), 0.7, Color(0.5, 0.5, 0.62), 0.34, Color(0.75, 0.6, 0.55), 0.15],
	[7.5, Color(0.25, 0.45, 0.8), Color(0.85, 0.8, 0.7), Color(1.0, 0.8, 0.58), 1.5, Color(0.56, 0.66, 0.78), 0.33, Color(0.78, 0.8, 0.76), 0.0],
	[12.0, Color(0.17, 0.4, 0.82), Color(0.68, 0.8, 0.88), Color(1.0, 0.95, 0.84), 1.9, Color(0.55, 0.68, 0.82), 0.36, Color(0.72, 0.82, 0.86), 0.0],
	[16.5, Color(0.2, 0.42, 0.8), Color(0.78, 0.8, 0.76), Color(1.0, 0.88, 0.66), 1.75, Color(0.56, 0.66, 0.8), 0.34, Color(0.78, 0.8, 0.74), 0.0],
	[18.6, Color(0.22, 0.32, 0.6), Color(1.0, 0.62, 0.32), Color(1.0, 0.58, 0.26), 1.25, Color(0.62, 0.55, 0.6), 0.36, Color(0.9, 0.66, 0.48), 0.0],
	[19.6, Color(0.1, 0.14, 0.36), Color(0.8, 0.38, 0.3), Color(1.0, 0.42, 0.25), 0.35, Color(0.4, 0.42, 0.62), 0.32, Color(0.42, 0.34, 0.42), 0.35],
	[20.6, Color(0.02, 0.035, 0.1), Color(0.1, 0.11, 0.2), Color(0.55, 0.65, 1.0), 0.2, Color(0.24, 0.32, 0.52), 0.3, Color(0.06, 0.08, 0.14), 1.0],
	[24.0, Color(0.012, 0.02, 0.055), Color(0.04, 0.06, 0.11), Color(0.55, 0.65, 1.0), 0.22, Color(0.22, 0.3, 0.5), 0.3, Color(0.04, 0.06, 0.1), 1.0],
]

var hour := 15.2
## game hours per real second. 0 = frozen
var day_speed := 0.0
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var clouds: Array[Node3D] = []
var motes: CPUParticles3D
var leaves: CPUParticles3D
var cloud_mat: StandardMaterial3D
var fog_density := 0.0032
var _applied := -99.0
var _compat := false


func _ready() -> void:
	_compat = RenderingServer.get_rendering_device() == null
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sh := Shader.new()
	sh.code = SKY_CODE
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 5.0
	env.tonemap_exposure = 0.92
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 2.0
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_density = fog_density
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.95, 0.95, 0.88)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.28
	env.adjustment_contrast = 1.1
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_blur = 1.4
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_volumetric_fog_energy = 2.2
	add_child(sun)
	_build_clouds()
	_build_particles()
	apply_time()


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1701
	cloud_mat = StandardMaterial3D.new()
	cloud_mat.vertex_color_use_as_albedo = true
	cloud_mat.roughness = 1.0
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.disable_fog = true
	for k in 16:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var puffs := rng.randi_range(4, 7)
		var src := LowPoly.sphere(7, 4)
		var arr := src.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var x := -float(puffs) * 0.5
		for p in puffs:
			var mid := 1.0 - absf(float(p) / (puffs - 1) - 0.5) * 1.2
			var s := Vector3(rng.randf_range(1.6, 2.4), rng.randf_range(0.8, 1.3) * mid, rng.randf_range(1.2, 2.0))
			var off := Vector3(x, s.y * 0.35, rng.randf_range(-0.5, 0.5))
			x += s.x * 0.55
			for i in verts.size():
				var v := verts[i]
				# flat bottoms: clouds sit on a level base
				v.y = maxf(v.y, -0.18)
				var n := norms[i]
				# baked shading: bright tops, grey-blue bellies (unshaded so they stay clean at any sun angle)
				var lit := clampf(n.y * 0.5 + 0.62, 0.0, 1.0)
				st.set_color(Color(0.62, 0.68, 0.78).lerp(Color(1, 1, 1), lit))
				st.set_normal(n)
				st.add_vertex(v * s + off)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = cloud_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := rng.randf() * TAU
		var r := rng.randf_range(60.0, 240.0)
		mi.position = Vector3(cos(a) * r, rng.randf_range(70.0, 110.0), sin(a) * r)
		mi.rotation.y = rng.randf_range(-0.3, 0.3)
		mi.scale = Vector3.ONE * rng.randf_range(7.0, 15.0)
		mi.extra_cull_margin = 10.0
		add_child(mi)
		clouds.append(mi)


func _build_particles() -> void:
	# pollen / dust motes that catch the light, in a box that follows the camera
	motes = CPUParticles3D.new()
	motes.amount = 140
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(9, 2.2, 9)
	motes.direction = Vector3(1, 0.15, 0.4)
	motes.spread = 40.0
	motes.gravity = Vector3(0, -0.01, 0)
	motes.initial_velocity_min = 0.05
	motes.initial_velocity_max = 0.22
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.008, 0.008)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_color = Color(1.0, 0.97, 0.8)
	qm.vertex_color_use_as_albedo = true
	q.material = qm
	motes.mesh = q
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.local_coords = false
	add_child(motes)
	# the odd leaf spinning down
	leaves = CPUParticles3D.new()
	leaves.amount = 26
	leaves.lifetime = 11.0
	leaves.preprocess = 11.0
	leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	leaves.emission_box_extents = Vector3(14, 0.5, 14)
	leaves.direction = Vector3(1, 0, 0.4)
	leaves.spread = 60.0
	leaves.gravity = Vector3(0.12, -0.5, 0.05)
	leaves.initial_velocity_min = 0.1
	leaves.initial_velocity_max = 0.5
	leaves.damping_min = 0.6
	leaves.damping_max = 0.9
	leaves.angular_velocity_min = -160.0
	leaves.angular_velocity_max = 160.0
	leaves.particle_flag_rotate_y = true
	leaves.angle_min = 0.0
	leaves.angle_max = 360.0
	var lq := QuadMesh.new()
	lq.size = Vector2(0.05, 0.035)
	var lm := StandardMaterial3D.new()
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.vertex_color_use_as_albedo = true
	lm.roughness = 0.9
	lq.material = lm
	leaves.mesh = lq
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.62, 0.2))
	grad.set_color(1, Color(0.8, 0.55, 0.15))
	leaves.color_initial_ramp = grad
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	leaves.local_coords = false
	add_child(leaves)


## 0 at night, 1 in full day
func daylight() -> float:
	return clampf((_sun_dir().y + 0.08) / 0.3, 0.0, 1.0)


func is_night() -> bool:
	return hour < 5.2 or hour > 20.2


func _sun_dir() -> Vector3:
	# sun rises in the east (+x), tops out leaning south (+z), sets west. 6h = horizon
	var a := (hour - 6.0) / 12.0 * PI
	return Vector3(cos(a) * 0.82, sin(a), 0.45 * maxf(sin(a), -0.2) + 0.25).normalized()


func apply_time() -> void:
	_applied = hour
	var h := fposmod(hour, 24.0)
	var k := 0
	for i in KEYS.size() - 1:
		if h >= KEYS[i][0] and h <= KEYS[i + 1][0]:
			k = i
			break
	var a: Array = KEYS[k]
	var b: Array = KEYS[k + 1]
	var f: float = smoothstep(0.0, 1.0, (h - a[0]) / (b[0] - a[0]))
	var top: Color = (a[1] as Color).lerp(b[1], f)
	var hor: Color = (a[2] as Color).lerp(b[2], f)
	var sc: Color = (a[3] as Color).lerp(b[3], f)
	var se: float = lerpf(a[4], b[4], f)
	var ac: Color = (a[5] as Color).lerp(b[5], f)
	var ae: float = lerpf(a[6], b[6], f)
	var fc: Color = (a[7] as Color).lerp(b[7], f)
	var st: float = lerpf(a[8], b[8], f)
	var sd := _sun_dir()
	var md := (-sd + Vector3(0.0, 0.25, 0.3)).normalized()
	# the one directional light is the sun by day and the moon at night
	var ld := sd if sd.y > -0.06 else md
	if ld.y < 0.07:
		ld = Vector3(ld.x, 0.07, ld.z).normalized()
	sun.look_at_from_position(Vector3.ZERO, -ld, Vector3.UP)
	sun.light_color = sc
	sun.light_energy = se
	sky_mat.set_shader_parameter("top", top)
	sky_mat.set_shader_parameter("horizon", hor)
	sky_mat.set_shader_parameter("ground", hor.lerp(Color(0.2, 0.28, 0.18), 0.6) * (0.35 + 0.65 * daylight()))
	sky_mat.set_shader_parameter("sun_col", sc if sd.y > -0.06 else Color(0, 0, 0))
	sky_mat.set_shader_parameter("sun_dir", sd)
	sky_mat.set_shader_parameter("moon_dir", md)
	sky_mat.set_shader_parameter("stars", st)
	env.ambient_light_color = ac
	# the web / compatibility renderer has no ssao or fog to fill the shadows in, so give it more sky light
	env.ambient_light_energy = ae * (1.9 if _compat else 1.0)
	env.fog_light_color = fc
	env.fog_density = fog_density * (1.0 + (1.0 - daylight()) * 0.8)
	env.volumetric_fog_density = lerpf(0.003, 0.006, daylight())
	var cl := Color(0.14, 0.17, 0.26).lerp(Color.WHITE, daylight())
	# sunset paints the clouds
	cl = cl.lerp(Color(1.0, 0.72, 0.55), clampf(1.0 - absf(sd.y) / 0.25, 0.0, 1.0) * 0.55 * daylight())
	cloud_mat.albedo_color = cl
	motes.emitting = daylight() > 0.3
	(motes.mesh as QuadMesh).material.albedo_color = Color(1.0, 0.97, 0.8) * (0.5 + 0.9 * daylight())


func _process(dt: float) -> void:
	if day_speed != 0.0:
		hour = fposmod(hour + day_speed * dt, 24.0)
	if absf(hour - _applied) > 0.004:
		apply_time()
	for c in clouds:
		c.position.x += dt * 0.9
		if c.position.x > 260.0:
			c.position.x -= 520.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := cam.global_position
		motes.global_position = p + Vector3(0, 1.2, 0)
		leaves.global_position = p + Vector3(0, 5.0, 0)
