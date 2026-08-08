shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Must match WORLD_BOUNDS in minimap.gd and play_area.gd
const float WORLD_BOUNDS = 75.0;

void fragment() {
	float wx = (UV.x - 0.5) * WORLD_BOUNDS * 2.0;
	float wz = (UV.y - 0.5) * WORLD_BOUNDS * 2.0;

	float fw = max(fwidth(wx), 0.008);
	float fz = max(fwidth(wz), 0.008);

	// ── Minor grid (every 1 unit) ──────────────────────────────────────────
	float gx = abs(fract(wx + 0.5) - 0.5);
	float gz = abs(fract(wz + 0.5) - 0.5);
	float line_x = 1.0 - smoothstep(0.0, fw, gx);
	float line_z = 1.0 - smoothstep(0.0, fz, gz);
	float minor = max(line_x, line_z);

	// ── Major grid (every 5 units) ─────────────────────────────────────────
	float mx = abs(fract(wx / 5.0 + 0.5) - 0.5) * 5.0;
	float mz = abs(fract(wz / 5.0 + 0.5) - 0.5) * 5.0;
	float maj_x = 1.0 - smoothstep(0.0, fw * 1.6, mx);
	float maj_z = 1.0 - smoothstep(0.0, fz * 1.6, mz);
	float major = max(maj_x, maj_z);

	// ── Boundary glow ──────────────────────────────────────────────────────
	float edge_dist = min(min(wx + WORLD_BOUNDS, WORLD_BOUNDS - wx),
	                      min(wz + WORLD_BOUNDS, WORLD_BOUNDS - wz));
	float border = 1.0 - smoothstep(0.0, 0.8, edge_dist);

	// ── Distance fade from camera ──────────────────────────────────────────
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(vec2(wx - cam.x, wz - cam.z));
	float dist_fade = exp(-dist * 0.032);

	// ── Compose — grey, very subtle ────────────────────────────────────────
	float alpha = (minor * 0.011 + major * 0.020 + border * 0.11) * dist_fade;
	alpha = clamp(alpha, 0.0, 1.0);

	// Slightly warmer grey for border, cool grey for grid
	vec3 col = mix(vec3(0.55, 0.55, 0.55), vec3(0.70, 0.70, 0.72), border);

	ALBEDO = col;
	ALPHA  = alpha;
}
