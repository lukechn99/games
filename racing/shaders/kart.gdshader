shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
// Karts and drivers, shaded like Mario Kart's: bright, saturated colour
// with soft (not stepped) sunlight, a clear highlight, a lit rim, and a
// cheap reflection of the sky so paint looks glossy. The renderer's own sky
// ambient tinted the paint blue (red went pink, yellow tan), so ambient here
// is neutral and set by us. Colour comes from the merged mesh's vertex
// colours (with the baked occlusion already in them), or `tint`.

uniform bool use_vertex = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float gloss = 0.0;          // 0 matte .. 1 glassy
uniform float metal = 0.0;          // metal tints its reflection by its colour
uniform float ambient = 0.4;        // light in the shade (with the sun, adds to about 1: more clipped orange to yellow)
uniform float sun_gain = 0.62;
uniform float rim_amt = 0.25;
uniform vec3 sky_col : source_color = vec3(0.55, 0.78, 1.0);
uniform vec3 horizon_col : source_color = vec3(0.92, 0.96, 1.0);
uniform vec3 ground_col : source_color = vec3(0.34, 0.36, 0.33);

void fragment() {
	vec3 base = (use_vertex ? COLOR.rgb : vec3(1.0)) * tint.rgb;
	ALBEDO = base;
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	// What the surface reflects, in world space: a sky-to-ground gradient
	// stands in for the environment, strongest at grazing angles.
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz;
	vec3 env = r.y > 0.0 ? mix(horizon_col, sky_col, smoothstep(0.0, 0.6, r.y)) : mix(horizon_col, ground_col, smoothstep(0.0, 0.25, -r.y));
	float f = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
	float refl = gloss * mix(0.06, 0.75, f);
	vec3 shine = env * mix(vec3(1.0), base * 1.6, metal);
	EMISSION = base * ambient + shine * refl;
	ALBEDO = base * (1.0 - refl * 0.8);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Soft but definite: most of the lit side is fully lit, then a smooth
	// roll into shade.
	float d = smoothstep(-0.05, 0.55, ndl);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR * sun_gain;
	// A clear highlight, tighter the glossier it is.
	vec3 h = normalize(LIGHT + VIEW);
	float sp = pow(max(dot(NORMAL, h), 0.0), mix(12.0, 180.0, gloss));
	SPECULAR_LIGHT += smoothstep(0.25, 0.7, sp) * gloss * 0.9 * ATTENUATION * LIGHT_COLOR;
	// Rim: edges catch the light where the sun reaches.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * smoothstep(-0.3, 0.3, ndl);
	DIFFUSE_LIGHT += rim * rim_amt * ATTENUATION * LIGHT_COLOR;
}
