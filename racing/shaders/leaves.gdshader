// Tree leaves swaying in the breeze. Movement grows with height, so trunks
// stay put; each tree sways on its own timing from where it stands.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform vec3 color : source_color = vec3(0.36, 0.8, 0.24);
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 world;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - 0.25, 0.0);
	float t = TIME * 1.4 + o.x * 0.21 + o.z * 0.17;
	VERTEX.x += sin(t) * 0.035 * h;
	VERTEX.z += cos(t * 0.8 + 1.3) * 0.025 * h;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// A little leafy texture, projected from above and the side.
	float d = texture(detail, world.xz * 0.35).r * 0.5 + texture(detail, world.xy * 0.35).r * 0.5;
	ALBEDO = color * mix(0.85, 1.08, d);
}
