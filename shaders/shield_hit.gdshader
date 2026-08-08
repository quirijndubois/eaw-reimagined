shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	if (dist > 1.0) discard;

	// Single smooth ring expanding from center to edge
	float ring_r = progress * 0.92;
	float ring   = exp(-pow((dist - ring_r) * 18.0, 2.0));

	// Soft trailing inner glow behind the ring
	float trail = exp(-pow((dist - max(0.0, ring_r - 0.12)) * 11.0, 2.0)) * 0.3;

	// Fade out as ring approaches edge
	float fade = 1.0 - smoothstep(0.5, 1.0, progress);

	float alpha = (ring + trail) * fade * smoothstep(1.0, 0.82, dist);

	// Cool blue-white, slightly warmer at center
	vec3 col = mix(vec3(0.85, 0.97, 1.0), vec3(0.22, 0.58, 1.0), dist);
	ALBEDO = col;
	ALPHA  = clamp(alpha, 0.0, 1.0);
}
