// Fans in the bleachers: each one hops and cheers on its own beat.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float phase = o.x * 1.37 + o.z * 0.91;
	float hop = max(0.0, sin(TIME * (5.0 + fract(phase) * 3.0) + phase));
	VERTEX.y += hop * hop * 0.28;
	// Lean side to side a little.
	VERTEX.x += sin(TIME * 2.0 + phase) * 0.06 * VERTEX.y;
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
