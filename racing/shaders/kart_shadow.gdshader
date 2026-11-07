// A kart's shadow cast by the sun: its shape squashed flat onto the ground
// along the light, so it has the kart's outline and falls to one side
// (real-time shadows are off in the browser renderer; design doc 9.4).
shader_type spatial;
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_always, shadows_disabled;

uniform vec3 light_dir = vec3(0.4, -0.8, 0.45);   // the way the light travels
uniform vec3 plane_point;
uniform vec3 plane_normal = vec3(0.0, 1.0, 0.0);
uniform float strength = 0.6;
uniform vec3 tint : source_color = vec3(0.1, 0.1, 0.17);

void vertex() {
	vec3 w = VERTEX;
	vec3 l = normalize(light_dir);
	float denom = min(dot(l, plane_normal), -0.2);
	float t = dot(plane_point - w, plane_normal) / denom;
	// Each point lifts a hair by how high it was, so overlapping layers
	// mostly fail the depth test and the shadow darkens about once.
	float h = max(dot(w - plane_point, plane_normal), 0.0);
	VERTEX = w + l * t + plane_normal * (0.075 + h * 0.004);   // (the road is drawn 4 cm above its collision surface)
}

void fragment() {
	ALBEDO = tint;
	ALPHA = strength;
}
