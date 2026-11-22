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
// close up fixes (cat eye height is ~0.25 m, so floors and walls sit right at the lens):
// textures are perspective correct up to affine_fade.x m and fade into the affine warp by
// affine_fade.y m. a 4 m city quad with one corner near you otherwise bends its tile lines into
// zigzags that swim as you walk. past ~3 quads away every poly is far enough that the warp is mild
uniform vec2 affine_fade = vec2(2.0, 12.0);
uniform float affine_near = 1.5; // affine weight floor (m): verts at / behind the lens can't blow up
uniform vec2 snap_fade = vec2(0.6, 3.0); // no vertex snap closer than x m, full snap past y m

varying vec3 affine_uv;  // uv * w, divided back in fragment = affine (no perspective correction)
varying vec2 true_uv;    // the same uv, perspective correct (used close to the camera)
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
	if (clip.w > 0.05) {
		vec2 g = vec2(snap, snap * 0.5625);
		vec2 ndc = clip.xy / clip.w;
		vec2 snapped = floor(ndc * g + 0.5) / g;
		clip.xy = mix(ndc, snapped, smoothstep(snap_fade.x, snap_fade.y, clip.w)) * clip.w;
	}
	POSITION = clip;
	float w = max(clip.w, affine_near);
	true_uv = uv * uv_scale;
	affine_uv = vec3(true_uv * w, w);
}

void fragment() {
	vec2 uv = mix(true_uv, affine_uv.xy / affine_uv.z, smoothstep(affine_fade.x, affine_fade.y, -VERTEX.z));
	vec3 c = texture(albedo_tex, uv).rgb * tint.rgb;
	if (vcol) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	EMISSION = c * emission;
}
