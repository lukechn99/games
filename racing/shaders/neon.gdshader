// Glowing cave plants and crystals: vertex colour, glowing and gently pulsing.
shader_type spatial;
render_mode unshaded;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float pulse = 0.8 + 0.2 * sin(TIME * 2.0 + world.x * 0.7 + world.z * 0.5);
	ALBEDO = COLOR.rgb * (0.9 + 0.6 * pulse);
}
