// Item box shell (assets/models/item_box.glb, built in Blender): pink jelly.
// Saturated pink through the middle so the yellow question mark shows
// through, lighter and more solid toward the rounded edges, with a glossy
// highlight. The colour is fixed (not reflected sky), so it never washes
// out to pale blue in bright scenes.
shader_type spatial;
render_mode diffuse_toon, specular_schlick_ggx, cull_back, depth_draw_opaque;

uniform vec3 jelly : source_color = vec3(1.0, 0.32, 0.74);
uniform vec3 edge : source_color = vec3(1.0, 0.62, 0.9);

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 1.8);
	// A slow wobble of brightness, like light moving through jelly.
	float wob = 0.06 * sin(TIME * 2.3 + VERTEX.x * 3.0 + VERTEX.y * 2.0);
	ALBEDO = mix(jelly, edge, rim) * (1.0 + wob);
	EMISSION = jelly * 0.35;   // glows a little, even in shade
	ROUGHNESS = 0.12;
	SPECULAR = 0.9;
	ALPHA = mix(0.5, 0.94, smoothstep(0.0, 0.8, rim));
}
