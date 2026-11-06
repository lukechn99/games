// Lake water (design doc 9.4): slow waves, deep and shallow blues, and a
// few sun glints that come and go.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec3 deep : source_color = vec3(0.1, 0.36, 0.66);
uniform vec3 shallow : source_color = vec3(0.22, 0.56, 0.82);

varying vec3 world;

float wave(vec2 p, float t) {
	return sin(p.x * 0.55 + t * 1.3 + sin(p.y * 0.21 + t * 0.4) * 2.0)
		* cos(p.y * 0.47 - t * 1.05 + sin(p.x * 0.17) * 2.0);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave(world.xz * 0.5, TIME) * 0.07;
}

void fragment() {
	float w = wave(world.xz, TIME) + 0.5 * wave(world.zx * 1.9 + 3.0, TIME * 1.3);
	ALBEDO = mix(deep, shallow, smoothstep(-1.0, 1.3, w));
	// Glints only where two wave patterns crest together, so they're sparse.
	float g = wave(world.xz * 2.3 + 11.0, TIME * 1.7) * wave(world.zx * 3.1 - 7.0, TIME * 2.1);
	ALBEDO += vec3(smoothstep(0.82, 0.95, g)) * 0.5;
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
}
