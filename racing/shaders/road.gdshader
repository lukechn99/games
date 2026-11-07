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
// Baked relief (tools/make_surfaces.py): a 4 m tile of greyscale detail with
// occlusion, and its normal map, so the flat road lights as if bumpy.
uniform sampler2D surf : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surf_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float relief = 1.0;
uniform bool ruts = false;   // wheel ruts down the lanes (the mine's dirt road)

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
	float tex = mix(1.0, texture(detail, UV).r, 0.5);
	// (One baked tile every 9 m: finer than that shimmered like static at speed.)
	vec2 suv = vec2(UV.x, UV.y) * (14.0 / 9.0);
	tex *= mix(1.0, texture(surf, suv).r * 1.2, 0.6);
	vec3 nm = texture(surf_n, suv).rgb * 2.0 - 1.0;
	if (ruts && UV.x >= 0.0 && UV.x <= 1.0) {
		// Two grooves where the wheels run: slope of a pair of soft dips.
		float slope = 0.0;
		for (int k = 0; k < 2; k++) {
			float d = (UV.x - (k == 0 ? 0.36 : 0.64)) / 0.045;
			slope += -2.0 * d * exp(-d * d);
			tex *= 1.0 - 0.18 * exp(-d * d);
		}
		nm.x += slope * 0.45;
	}
	NORMAL_MAP = normalize(nm) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = relief;
	float rough = 0.92;
	if (UV.x >= 0.0 && UV.x <= 1.0) {
		// Coarse tarmac: stones in the mix show as light and dark grit.
		// Broad mottling only (fine grit read as static at speed).
		float speck = vnoise(wpos.xz / 2.5);
		c *= mix(0.92, 1.08, speck);
		float n = vnoise(wpos.xz / 38.0) * 0.6 + vnoise(wpos.xz / 7.0) * 0.4;
		c *= mix(0.86, 1.12, n);
		// Sealed patches of fresher, darker tar.
		float patch = smoothstep(0.8, 0.83, vnoise(wpos.xz / 3.5 + 31.0));
		c = mix(c, c * 0.8, patch * wear * 1.4);
		// Cracks in some stretches.
		// A few long, wandering hairline cracks: where a slow noise crosses
		// one value, with a finer wobble so it isn't smooth.
		float cn = vnoise(wpos.xz / 9.0 + 3.0) * 0.8 + vnoise(wpos.xz / 1.7) * 0.2;
		float cw = fwidth(cn) * 1.2 + 0.002;
		float cr = 1.0 - smoothstep(cw * 0.4, cw, abs(cn - 0.5));
		cr *= smoothstep(0.55, 0.7, vnoise(wpos.xz / 30.0 + 11.0)) * (1.0 - patch);
		c = mix(c, c * 0.55, cr * wear * 1.6);
		float lanes = exp(-pow((UV.x - 0.33) / 0.07, 2.0)) + exp(-pow((UV.x - 0.67) / 0.07, 2.0));
		lanes *= 0.55 + 0.45 * vnoise(wpos.xz / 2.5);
		c = mix(c, c * 0.68, lanes * wear);
		rough -= lanes * wear * 0.3;
		if (paint) {
			float aa = fwidth(UV.x) * 1.5;
			// Bold edge lines, and a dashed line down the middle.
			float e = smoothstep(0.024 - aa, 0.024, UV.x) * (1.0 - smoothstep(0.062, 0.062 + aa, UV.x))
				+ smoothstep(0.938 - aa, 0.938, UV.x) * (1.0 - smoothstep(0.976, 0.976 + aa, UV.x));
			float along = fract(UV.y * 14.0 / 10.0);
			float dash = (1.0 - smoothstep(0.011, 0.011 + aa, abs(UV.x - 0.5))) * step(along, 0.38);
			e = max(e, dash);
			// Worn a little, so it's paint, not plastic.
			e *= 0.72 + 0.28 * vnoise(wpos.xz * 1.3);
			e *= 1.0 - cr * 0.7;
			c = mix(c, paint_color, e);
			tex = mix(tex, 1.0, e * 0.6);
		}
	}
	ALBEDO = c * tex;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
