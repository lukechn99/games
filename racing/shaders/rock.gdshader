shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;
// Mining Mountain's rock. Cartoon cliffs read as layers: warm bands of
// sandstone of different shades, a dark seam between them, wavering a
// little so they don't look ruled. Ledges flat enough to hold soil turn
// grassy, and above the snow line they're white. Everything is worked out
// from world position, so the bands run straight across the whole mountain.

uniform sampler2D detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 6.0;
uniform float band_m = 4.5;
uniform float snow_line = 78.0;
uniform vec3 tone_a : source_color = vec3(0.76, 0.58, 0.4);
uniform vec3 tone_b : source_color = vec3(0.64, 0.49, 0.37);
uniform vec3 tone_c : source_color = vec3(0.54, 0.41, 0.33);
uniform vec3 seam : source_color = vec3(0.3, 0.22, 0.18);
uniform vec3 moss : source_color = vec3(0.42, 0.62, 0.27);
uniform vec3 snow : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 gravel : source_color = vec3(0.8, 0.68, 0.5);
uniform bool use_gravel = true;   // vertex alpha marks run-off (the mine mountain)

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

float triplanar(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(detail, p.zy / tile_m).r * w.x + texture(detail, p.xz / tile_m).r * w.y + texture(detail, p.xy / tile_m).r * w.z;
}

void fragment() {
	vec3 n = normalize(wnorm);
	float warp = vnoise(wpos.xz / 30.0) * 1.6 + vnoise(wpos.xz / 9.0) * 0.4;
	float band = wpos.y / band_m + warp;
	float layer = floor(band);
	float h = hash(vec2(layer, 3.7));
	vec3 c = h < 0.34 ? tone_a : (h < 0.67 ? tone_b : tone_c);
	float f = fract(band);
	float aa = fwidth(band) * 1.5;
	c = mix(seam, c, smoothstep(0.0, 0.07 + aa, f) * (1.0 - smoothstep(0.96 - aa, 1.0, f) * 0.6));
	c *= 0.92 + 0.16 * vnoise(wpos.xz / 5.0 + wpos.y * 0.3);
	// Grass on ledges, snow on top.
	float flat_ = smoothstep(0.86, 0.95, n.y) * smoothstep(0.45, 0.6, vnoise(wpos.xz / 14.0));
	// (Only up the mountain: near the road it read as a green smear.)
	flat_ *= smoothstep(32.0, 40.0, wpos.y);
	c = mix(c, moss * (0.9 + 0.2 * vnoise(wpos.xz / 5.0)), 0.8 * flat_ * step(wpos.y, snow_line + warp * 4.0));
	float s = smoothstep(snow_line - 2.0, snow_line + 2.0, wpos.y + warp * 4.0) * smoothstep(0.35, 0.55, n.y);
	c = mix(c, snow, s);
	// Beside the road (vertex alpha): packed gravel run-off, speckled.
	float g = use_gravel ? smoothstep(0.2, 0.8, COLOR.a) : 0.0;
	vec3 gc = gravel * (0.92 + 0.12 * vnoise(wpos.xz / 2.0)) * (0.92 + 0.12 * vnoise(wpos.xz / 8.0));
	c = mix(c, gc, g);
	ALBEDO = c * mix(0.85, 1.03, triplanar(wpos, n));
	ROUGHNESS = 1.0;
}
