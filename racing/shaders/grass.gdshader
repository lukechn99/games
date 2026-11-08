shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
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
// How far the ground is from the road's edge (track.gd _bake_road_distance).
uniform sampler2D road_dist : filter_linear, repeat_disable;
uniform vec2 dist_origin;
uniform vec2 dist_size = vec2(1.0);
uniform bool use_dist = false;
uniform vec3 sand : source_color = vec3(0.86, 0.66, 0.44);
// A hole in the ground (Frosty Pass's frozen lake): centre x, z, radii.
uniform vec4 hole = vec4(0.0, 0.0, 0.0, 0.0);

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
	if (hole.z > 0.0 && length((p - hole.xy) / hole.zw) < 1.0) {
		discard;
	}
	float broad = vnoise(p / 60.0) * 0.65 + vnoise(p / 23.0) * 0.35;
	float fine = vnoise(p / 3.1);
	vec3 c = mix(deep, fresh, smoothstep(0.25, 0.6, broad));
	c = mix(c, dry, smoothstep(0.62, 0.85, broad) * 0.8);
	c *= 0.9 + 0.2 * fine;
	if (use_vertex) {
		// Banks: their vertex colour shades them (darker low down).
		c *= COLOR.rgb / vec3(0.4, 0.8, 0.26);
	}
	if (use_dist) {
		// Sand and dust blown over the verge: a ragged band beside the
		// road, with a few pebbles and the grass thinning into it.
		vec2 uv = (p - dist_origin) / dist_size;
		float edge = texture(road_dist, uv).r * 12.0;
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) edge = 12.0;
		float rag = vnoise(p / 2.2) * 0.6 + vnoise(p / 7.0) * 0.4;
		float s = 1.0 - smoothstep(2.4 + rag * 2.6, 3.8 + rag * 4.2, edge);
		vec3 sc = sand * (0.92 + 0.12 * vnoise(p * 0.5));
		float pebble = smoothstep(0.82, 0.88, vnoise(p * 0.9)) * s;
		sc = mix(sc, sc * 0.62, pebble);
		// A darker, lusher fringe where the grass meets the sand.
		float fringe = (1.0 - smoothstep(2.0 + rag * 3.0, 6.0 + rag * 4.0, edge)) * (1.0 - s);
		c *= 1.0 - fringe * 0.18;
		c = mix(c, sc, s);
	}
	float tex = texture(detail, p / tile_m).r;
	ALBEDO = c * mix(0.9, 1.0, tex);
	ROUGHNESS = 1.0;
}
