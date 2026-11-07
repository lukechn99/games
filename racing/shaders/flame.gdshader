// Torch flames: bright, flickering, licking upwards.
shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float up = max(VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * 11.0 + world.x * 3.0) * 0.08 * up * 4.0;
	VERTEX.z += cos(TIME * 9.0 + world.z * 3.0) * 0.08 * up * 4.0;
	VERTEX.y *= 1.0 + 0.25 * sin(TIME * 13.0 + world.x);
}

void fragment() {
	float f = 0.8 + 0.2 * sin(TIME * 17.0 + world.x * 5.0);
	ALBEDO = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.85, 0.35), f) * 1.6;
}
