shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
// glTF stores COLOR_0 in linear space. Compatibility interprets vertex
// colours as sRGB regardless of BaseMaterial3D.vertex_color_is_srgb, so
// undo that extra conversion without rebuilding meshes or losing their LODs.

uniform bool preview_pop = false;
uniform vec3 preview_green : source_color = vec3(0.396, 0.725, 0.212);

void vertex() {
	if (OUTPUT_IS_SRGB) {
		vec3 c = max(COLOR.rgb, vec3(0.0));
		COLOR.rgb = mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	if (preview_pop && COLOR.g > COLOR.r * 1.3 && COLOR.g > COLOR.b * 1.2) {
		ALBEDO = mix(COLOR.rgb, preview_green, 0.3);
	}
	ROUGHNESS = 1.0;
}
