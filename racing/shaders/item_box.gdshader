// Item box shell (assets/models/item_box.glb, built in Blender): see-through
// glass whose edges shimmer through the rainbow as you look across them,
// brightest at the rim, like the classic kart-racer item box.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

vec3 rainbow(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.2);
	vec3 band = rainbow(rim * 1.6 + TIME * 0.35 + dot(NORMAL, vec3(0.3, 0.6, 0.2)));
	// The whole face carries colour (a soft rainbow drifting over it), the
	// edges more strongly, so it reads from far off.
	vec3 face = rainbow(TIME * 0.2 + dot(NORMAL, vec3(0.5, 0.3, 0.2)) * 0.6) * 0.55 + vec3(0.35, 0.55, 0.7);
	ALBEDO = mix(face, band * 1.35, smoothstep(0.05, 0.55, rim)) + vec3(1.0) * pow(rim, 6.0) * 0.9;
	ALPHA = mix(0.55, 0.97, smoothstep(0.0, 0.7, rim));
}
