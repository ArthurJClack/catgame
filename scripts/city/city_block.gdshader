shader_type spatial;
// the dense city block's one material (city_block.gd). every box carries its colour in COLOR
// and a pattern id in UV.x (+ glow strength in UV.y), so a whole 12 m cell is one draw call.
// patterns are drawn in world space: brick courses, concrete slabs, planks, grass, grating,
// glowing windows / neon, dark glass, rippling water, asphalt, awning stripes, leaves, tiles.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float wet = 0.75;

varying vec3 wpos;
varying vec3 wnrm;
varying flat float pat;
varying flat float glow;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	pat = UV.x;
	glow = UV.y;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 to_linear(vec3 c) {
	return pow(c, vec3(2.2));
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb);
	vec3 an = abs(wnrm);
	bool top = an.y > 0.6;
	vec2 uv = top ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	int p = int(pat + 0.5);
	float n = noise(uv * 2.7) * 0.6 + noise(uv * 9.0) * 0.3 + noise(uv * 31.0) * 0.1;
	float r = 0.88;
	float m = 0.0;
	vec3 e = vec3(0.0);
	if (p == 1) {            // brick, 25 x 8 cm courses, running bond
		vec2 b = uv / vec2(0.25, 0.08);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = fract(b);
		float mortar = clamp(step(f.x, 0.07) + step(f.y, 0.14), 0.0, 1.0);
		float h = hash(floor(b));
		c *= top ? (0.85 + 0.2 * n) : mix(0.78 + 0.34 * h, 0.5, mortar);
	} else if (p == 2) {     // concrete / pavement slabs
		vec2 f = fract(uv / 1.2);
		float joint = step(f.x, 0.012) + step(f.y, 0.012);
		c *= (0.8 + 0.3 * n) * (1.0 - 0.35 * clamp(joint, 0.0, 1.0));
	} else if (p == 3) {     // planks
		vec2 q = top ? uv : uv.yx;
		float plank = floor(q.y / 0.14);
		float h = hash(vec2(plank, 3.0));
		float seam = step(fract(q.y / 0.14), 0.06);
		c *= (0.75 + 0.3 * h + 0.15 * noise(vec2(q.x * 1.5, plank * 7.0))) * (1.0 - 0.4 * seam);
		r = 0.8;
	} else if (p == 4) {     // grass
		c *= 0.7 + 0.5 * n;
		c = mix(c, c * vec3(1.15, 1.05, 0.7), noise(uv * 0.4));
		r = 0.95;
	} else if (p == 5) {     // metal grating / painted metal
		vec2 g = fract(uv / 0.05);
		float bar = top ? clamp(step(g.x, 0.25) + step(g.y, 0.25), 0.0, 1.0) : 1.0;
		c *= mix(0.35, 1.0, bar) * (0.85 + 0.25 * n);
		r = 0.45;
		m = 0.6;
	} else if (p == 6) {     // glow: lit windows, neon, signal lenses
		float flick = 0.85 + 0.15 * noise(uv * 3.0 + vec2(TIME * 0.05));
		e = c * glow * flick;
		c *= 0.15;
		r = 0.4;
	} else if (p == 7) {     // dark glass
		c = c * 0.25 + vec3(0.01, 0.012, 0.02);
		r = 0.06;
		m = 0.7;
	} else if (p == 8) {     // water
		float w = noise(uv * 3.0 + vec2(TIME * 0.4, TIME * 0.25)) + noise(uv * 7.0 - vec2(TIME * 0.3));
		c = c * (0.6 + 0.25 * w);
		r = 0.03;
		m = 0.3;
		NORMAL = normalize(NORMAL + vec3(w - 1.0, 0.0, noise(uv * 5.0 + TIME * 0.5) - 0.5) * 0.12);
	} else if (p == 9) {     // asphalt
		c *= 0.75 + 0.35 * noise(uv * 18.0) + 0.15 * noise(uv * 0.7);
		r = 0.9;
	} else if (p == 10) {    // awning fabric stripes
		float s = step(0.5, fract((top ? uv.x : uv.x + uv.y) / 0.35));
		c *= mix(1.0, 0.55, s) * (0.9 + 0.15 * n);
		r = 0.95;
	} else if (p == 11) {    // leaves
		c *= 0.55 + 0.7 * noise(uv * 6.0) * noise(uv * 17.0 + 3.0);
		r = 0.9;
	} else if (p == 12) {    // tiles
		vec2 f = fract(uv / 0.3);
		float joint = clamp(step(f.x, 0.04) + step(f.y, 0.04), 0.0, 1.0);
		c *= (0.85 + 0.2 * hash(floor(uv / 0.3))) * (1.0 - 0.3 * joint);
		r = 0.35;
	} else {
		c *= 0.9 + 0.18 * n;
	}
	if (p != 6 && p != 8) {
		// street grime: soot near the ground, rain streaks down the walls
		float soot = smoothstep(1.4, 0.0, wpos.y) * 0.22;
		if (!top) {
			soot += smoothstep(0.55, 0.9, noise(vec2(uv.x * 4.0, uv.y * 0.25))) * 0.12;
		}
		c *= 1.0 - soot;
		// it's raining: low flat ground is wet and shiny
		if (top && wpos.y < 0.4 && (p == 9 || p == 2 || p == 0 || p == 12)) {
			float puddle = smoothstep(0.45, 0.7, noise(uv * 0.6));
			r = mix(r, 0.08, wet * (0.45 + 0.55 * puddle));
			c *= 1.0 - 0.35 * wet * puddle;
			m = max(m, 0.15 * wet);
		}
	}
	ALBEDO = c;
	ROUGHNESS = r;
	METALLIC = m;
	EMISSION = e;
}
