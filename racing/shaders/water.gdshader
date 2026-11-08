// Lake water (design doc 9.4): slow waves, deep and shallow blues, the sky
// reflected more at low angles (fresnel), and sun glints that come and go.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.08, 0.32, 0.6);
uniform vec3 shallow : source_color = vec3(0.2, 0.52, 0.8);
uniform vec3 sky : source_color = vec3(0.62, 0.84, 1.0);

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
	vec3 col = mix(deep, shallow, smoothstep(-1.0, 1.3, w));
	// Tilt the surface normal with the waves so highlights move.
	vec3 n = normalize(vec3(cos(world.x * 0.55 + TIME * 1.3) * 0.12, 1.0, sin(world.z * 0.47 - TIME) * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky, fresnel * 0.7);
	float g = wave(world.xz * 2.3 + 11.0, TIME * 1.7) * wave(world.zx * 3.1 - 7.0, TIME * 2.1);
	col += vec3(smoothstep(0.82, 0.95, g)) * 0.5;
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	METALLIC = 0.0;
}
