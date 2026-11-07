shader_type spatial;
render_mode diffuse_toon, specular_disabled;
// Meadow ground: one green would look like felt, so the colour drifts
// between a deep, a fresh and a sun-dried green in broad patches, with a
// finer mottle and the grass detail texture on top, all from world space so
// the ground plane and the banks match where they meet.

uniform sampler2D detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 deep : source_color = vec3(0.22, 0.55, 0.2);
uniform vec3 fresh : source_color = vec3(0.42, 0.78, 0.26);
uniform vec3 dry : source_color = vec3(0.66, 0.78, 0.3);
uniform float tile_m = 7.0;
uniform bool use_vertex = false;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = wpos.xz;
	float broad = vnoise(p / 60.0) * 0.65 + vnoise(p / 23.0) * 0.35;
	float fine = vnoise(p / 3.1);
	vec3 c = mix(deep, fresh, smoothstep(0.25, 0.6, broad));
	c = mix(c, dry, smoothstep(0.62, 0.85, broad) * 0.8);
	c *= 0.9 + 0.2 * fine;
	if (use_vertex) {
		// Banks: their vertex colour shades them (darker low down).
		c *= COLOR.rgb / vec3(0.4, 0.8, 0.26);
	}
	float tex = texture(detail, p / tile_m).r;
	ALBEDO = c * mix(0.75, 1.0, tex);
	ROUGHNESS = 1.0;
}
