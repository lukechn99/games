// A flag rippling in the wind. UV.x runs from the pole (0) to the tip (1).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, cull_disabled;

uniform vec3 color : source_color = vec3(0.96, 0.22, 0.25);
uniform float phase = 0.0;

void vertex() {
	float from_pole = UV.x;
	VERTEX.z += sin(TIME * 5.5 + phase - from_pole * 6.0) * 0.28 * from_pole;
	VERTEX.y += sin(TIME * 3.1 + phase - from_pole * 4.0) * 0.06 * from_pole;
}

void fragment() {
	vec3 c = color;
	// A white stripe near the pole.
	c = mix(c, vec3(1.0), step(UV.x, 0.18) * step(0.06, UV.x));
	ALBEDO = c;
}
