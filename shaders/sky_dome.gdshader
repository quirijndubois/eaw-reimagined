shader_type spatial;
render_mode cull_front, unshaded, depth_draw_never;

uniform float star_density : hint_range(0.90, 1.0) = 0.967;
uniform float star_brightness : hint_range(0.5, 5.0) = 2.0;
uniform vec3 nebula_color_a : source_color = vec3(0.07, 0.0, 0.18);
uniform vec3 nebula_color_b : source_color = vec3(0.0, 0.04, 0.16);

varying vec3 v_dir;

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec3(1,0,0));
	float c = hash(i + vec3(0,1,0));
	float d = hash(i + vec3(1,1,0));
	float e = hash(i + vec3(0,0,1));
	float f2 = hash(i + vec3(1,0,1));
	float g = hash(i + vec3(0,1,1));
	float h = hash(i + vec3(1,1,1));
	return mix(
		mix(mix(a,b,f.x), mix(c,d,f.x), f.y),
		mix(mix(e,f2,f.x), mix(g,h,f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	return noise3(p)*0.5 + noise3(p*2.1)*0.25 + noise3(p*4.3)*0.125;
}

vec3 star_field(vec3 dir, float scale, float density, float brightness) {
	vec3 d = dir * scale;
	vec3 cell = floor(d);
	vec3 col = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 c = cell + vec3(float(x), float(y), float(z));
				float h = hash(c);
				if (h > density) {
					vec3 sp = c + vec3(hash(c*1.7+1.3), hash(c*2.3+0.7), hash(c*3.1+2.1));
					float dist = length(d - sp);
					float b = (h - density) / (1.0 - density) * brightness;
					float color_t = hash(c * 5.7);
					vec3 star_col = mix(vec3(1.0, 0.93, 0.78), vec3(0.80, 0.91, 1.0), color_t);
					col += star_col * b * smoothstep(0.42, 0.0, dist);
				}
			}
		}
	}
	return col;
}

void vertex() {
	// Model-space vertex position = radial direction from sphere center
	v_dir = VERTEX;
	// Force fragment to the far clip plane so it always renders behind geometry
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.w;
}

void fragment() {
	vec3 dir = normalize(v_dir);
	vec3 color = vec3(0.0);

	// Main star field
	color += star_field(dir, 175.0, star_density, star_brightness);

	// Denser Milky Way band
	float band = 1.0 - smoothstep(0.0, 0.22, abs(dot(dir, normalize(vec3(0.1, 1.0, 0.25)))));
	if (band > 0.005) {
		color += star_field(dir, 340.0, 0.60, 0.5) * band;
		color += vec3(0.09, 0.07, 0.055) * band * 0.35;
	}

	// Nebula
	float n1 = fbm(dir * 2.7 + vec3(1.4, 0.6, 0.5));
	float n2 = fbm(dir * 2.1 + vec3(0.2, 1.6, 0.8));
	n1 = pow(max(0.0, n1 - 0.34), 2.8) * 0.55;
	n2 = pow(max(0.0, n2 - 0.41), 2.2) * 0.32;
	color += nebula_color_a * n1;
	color += nebula_color_b * n2;

	ALBEDO = color;
}
