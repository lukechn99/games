shader_type spatial;
render_mode diffuse_toon, specular_schlick_ggx;
// The road surface (design doc 9.4). Vertex colours still carry the base
// colour and the kerbs; on top of that: a detail texture, broad patches of
// lighter and darker tarmac, darker worn lanes where tyres run, and painted
// edge lines. UV.x runs 0..1 across the road (kerbs fall outside that) and
// UV.y along it, one unit every 14 m.

uniform sampler2D detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool paint = true;
uniform float wear = 0.5;
uniform vec3 paint_color : source_color = vec3(0.93, 0.92, 0.88);

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
	// (This renderer hands vertex colours over ready to use.)
	vec3 c = COLOR.rgb;
	float tex = texture(detail, UV).r;
	float rough = 0.92;
	if (UV.x >= 0.0 && UV.x <= 1.0) {
		float n = vnoise(wpos.xz / 38.0) * 0.6 + vnoise(wpos.xz / 7.0) * 0.4;
		c *= mix(0.86, 1.12, n);
		float lanes = exp(-pow((UV.x - 0.33) / 0.07, 2.0)) + exp(-pow((UV.x - 0.67) / 0.07, 2.0));
		lanes *= 0.55 + 0.45 * vnoise(wpos.xz / 2.5);
		c = mix(c, c * 0.68, lanes * wear);
		rough -= lanes * wear * 0.3;
		if (paint) {
			float aa = fwidth(UV.x) * 1.5;
			float e = smoothstep(0.022 - aa, 0.022, UV.x) * (1.0 - smoothstep(0.042, 0.042 + aa, UV.x))
				+ smoothstep(0.958 - aa, 0.958, UV.x) * (1.0 - smoothstep(0.978, 0.978 + aa, UV.x));
			// Worn a little, so it's paint, not plastic.
			e *= 0.75 + 0.25 * vnoise(wpos.xz * 1.3);
			c = mix(c, paint_color, e);
			tex = mix(tex, 1.0, e * 0.6);
		}
	}
	ALBEDO = c * tex;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
