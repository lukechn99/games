// Item crate: a glowing crystal cube that shifts colour, with a bright edge.
shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec3 a = vec3(0.25, 1.0, 0.95);
	vec3 b = vec3(1.0, 0.35, 0.9);
	float t = 0.5 + 0.5 * sin(TIME * 2.0 + local.y * 3.0);
	vec3 c = mix(a, b, t);
	// Brighter towards the edges, like a cut gem.
	vec3 e = abs(local) * 2.0 / 1.1;
	float edge = smoothstep(0.75, 1.0, max(max(min(e.x, e.y), min(e.y, e.z)), min(e.x, e.z)));
	ALBEDO = c * (0.75 + 0.9 * edge);
	ALPHA = 0.85;
}
