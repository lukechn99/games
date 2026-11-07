// Torch flames: bright, flickering, licking upwards. UV.y runs 0 at the
// base to 1 at the tip of each flame (mine_track.gd _flame).
shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float up = UV.y * UV.y;
	float seed = floor(world.x * 0.5) + floor(world.z * 0.5);
	VERTEX.x += sin(TIME * 11.0 + seed * 3.0) * 0.09 * up;
	VERTEX.z += cos(TIME * 9.0 + seed * 2.0) * 0.09 * up;
	VERTEX.y += sin(TIME * 13.0 + seed) * 0.08 * up;
}

void fragment() {
	float f = 0.85 + 0.15 * sin(TIME * 17.0 + world.x * 5.0);
	// White-yellow at the root, orange to red at the tip.
	vec3 c = mix(vec3(1.0, 0.92, 0.55), vec3(1.0, 0.42, 0.08), smoothstep(0.1, 0.8, UV.y));
	ALBEDO = c * f * 1.8;
}
