// The question mark inside the item box: bright white, with a slow
// rainbow sheen across its bevels.
shader_type spatial;
render_mode unshaded;

vec3 rainbow(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 sheen = rainbow(TIME * 0.4 + (1.0 - facing) * 1.2);
	ALBEDO = mix(vec3(1.0), sheen, (1.0 - facing) * 0.6) * 1.1;
}
