// ps1-style surface: vertices snap to a low-res grid (the wobble), textures are nearest-filtered
// and affine-mapped (they warp across big polygons), lighting is per vertex.
shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_disabled, cull_back;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 1.0;
uniform bool world_uv = true;   // planar uvs from world position (walls, floors, crates)
uniform float snap = 160.0;     // lower = more wobble
uniform float emission = 0.0;
uniform bool vcol = false;      // multiply by the vertex color (merged meshes: peds, building tints)

varying vec3 affine_uv;  // uv * w, divided back in fragment = affine (no perspective correction)
varying vec3 w_nrm;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 uv = UV;
	if (world_uv) {
		vec3 n = abs(w_nrm);
		uv = n.y > 0.5 ? wp.xz : (n.x > n.z ? wp.zy : wp.xy);
		uv.y = -uv.y;
	}
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec2 g = vec2(snap, snap * 0.5625);
	clip.xy = floor(clip.xy / clip.w * g + 0.5) / g * clip.w;
	POSITION = clip;
	affine_uv = vec3(uv * uv_scale * clip.w, clip.w);
}

void fragment() {
	vec2 uv = affine_uv.xy / affine_uv.z;
	vec3 c = texture(albedo_tex, uv).rgb * tint.rgb;
	if (vcol) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	EMISSION = c * emission;
}
