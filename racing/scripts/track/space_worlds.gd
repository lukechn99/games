class_name SpaceWorlds
extends RefCounted
## What Cosmic Crossing is made of (design doc 8.6): the moon and the red
## planet with the road cut into them, the moon's crater bowls with their
## rim rails and side ramps, dust shoulders and guardrails along every road,
## the flying saucer, and space round it all.

const EDGE := Track.ROAD_WIDTH * 0.5 + 1.1   # where the road's kerb ends
const RAIL_H := 1.3
const VERGE := 46.0     # the fine ground beside a road reaches this far out
const VERGE_AT: Array[float] = [0.0, 3.0, 7.0, 13.0, 21.0, 31.4]   # its steps beyond the rail


static func build(t: Track) -> void:
	var samples := _road_samples(t)
	_shoulders(t, samples)
	_planet(t, StarlinerTrack.MOON, "moon", samples)
	_planet(t, StarlinerTrack.MARS, "mars", samples)
	_craters(t, samples)
	_saucer(t)
	_dress(t)
	_space(t)


## The road every 4 m (not across jumps): [frame, world, in a crater].
static func _road_samples(t: Track) -> Array:
	var out := []
	var d := 0.0
	while d < t.length:
		if not t.in_gap(d):
			var f := t.road_frame(d)
			out.append([f, StarlinerTrack.world_of(f.origin), _in_bowl(f.origin, 1.0), d])
		d += 4.0
	return out


## Dust either side of the road, a little lower than it, that slows you;
## then a guardrail. (In craters the bowl is the shoulder.)
static func _shoulders(t: Track, samples: Array) -> void:
	var surf := {}
	var hit := SurfaceTool.new()
	hit.begin(Mesh.PRIMITIVE_TRIANGLES)
	# One mesh per world, so a world out of view isn't drawn.
	var rail_of := {}
	for w: String in ["moon", "mars", "saucer"]:
		var r := SurfaceTool.new()
		r.begin(Mesh.PRIMITIVE_TRIANGLES)
		rail_of[w] = r
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := EDGE + StarlinerTrack.SHOULDER
	for i in samples.size() - 1:
		var sa: Array = samples[i]
		var sb: Array = samples[i + 1]
		if sa[2] or sb[2] or float(sb[3]) - float(sa[3]) > 4.5 or sa[1] != sb[1]:
			continue
		var a: Transform3D = sa[0]
		var b: Transform3D = sb[0]
		var world: String = sa[1]
		var rails: SurfaceTool = rail_of[world]
		var name: String = {"moon": "moondust", "mars": "reddust", "saucer": "grate"}[world]
		if not surf.has(name):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			surf[name] = st
		var st: SurfaceTool = surf[name]
		var dust: Color = {"moon": StarlinerTrack.MOON_C.darkened(0.08), "mars": StarlinerTrack.RUST_LIGHT.darkened(0.05), "saucer": StarlinerTrack.HULL.darkened(0.25)}[world]
		var lip: Color = StarlinerTrack.ROAD.darkened(0.3)
		for side: float in [-1.0, 1.0]:
			var flip := side < 0.0
			var ax := a.basis.x * side
			var bx := b.basis.x * side
			# The slab's edge, then the dust.
			var a0 := a.origin + ax * EDGE
			var b0 := b.origin + bx * EDGE
			var a1 := a.origin + ax * (EDGE + 1.2) - Vector3.UP * 0.5
			var b1 := b.origin + bx * (EDGE + 1.2) - Vector3.UP * 0.5
			var a2 := a.origin + ax * outer - Vector3.UP * 0.5
			var b2 := b.origin + bx * outer - Vector3.UP * 0.5
			KitTools.quad(st, a0, b0, b1, a1, lip, flip)
			KitTools.quad(st, a1, b1, b2, a2, dust if i % 2 == 0 else dust.lightened(0.04), flip)
			# The guardrail: posts, two beams, and solid behind (two sheets).
			if i % 3 == 0:
				var foot := a2 + ax * 0.2
				KitTools.box(rails, Transform3D(a.basis, foot + Vector3.UP * RAIL_H * 0.5), Vector3(0.22, RAIL_H, 0.22), Color(0.92, 0.93, 0.95))
			var beam_col: Color = {"moon": Color(0.2, 0.45, 0.95), "mars": Color(1.0, 0.55, 0.15), "saucer": StarlinerTrack.CYAN}[world]
			for y: float in [0.65, 1.15]:
				var pa := a2 + ax * 0.12 + Vector3.UP * y
				var pb := b2 + bx * 0.12 + Vector3.UP * y
				var up := Vector3.UP * 0.13
				KitTools.quad(glow if world == "saucer" else rails, pa - up, pb - up, pb + up, pa + up, beam_col if y > 1.0 else Color(0.92, 0.93, 0.95), flip)
			for k: float in [0.2, 1.0]:
				var ha := a2 + ax * k
				var hb := b2 + bx * k
				KitTools.quad(hit, ha - Vector3.UP * 0.5, hb - Vector3.UP * 0.5, hb + Vector3.UP * RAIL_H, ha + Vector3.UP * RAIL_H, Color.WHITE, flip)
	for name: String in surf:
		var st: SurfaceTool = surf[name]
		st.generate_normals()
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = Palette.toon(Color.WHITE, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.add_child(mi)
		KitTools.solid(t, mesh, name)
	for w: String in rail_of:
		KitTools.commit(t, rail_of[w], Palette.toon(Color.WHITE, true), true)
	KitTools.commit(t, glow, KitTools.glow(Color.WHITE), true)
	hit.generate_normals()
	KitTools.solid(t, hit.commit())


## A world: a ball, its top shaped round the road (cut into the ground
## where it rises beside the road, built up where it falls away), with holes
## where the crater bowls go. Coloured like a planet (the moon's grey
## highlands and dark seas; the red planet's rust plains, dark lands and an
## ice cap), then marked by its features: craters dent the moon all over and
## volcanoes rise from the red planet, so neither outline is a perfect circle.
static func _planet(t: Track, body: Dictionary, world: String, samples: Array) -> void:
	var cx := float(body["x"])
	var cz := float(body["z"])
	var a := float(body["a"])
	var top := float(body["top"])
	var centre := Vector3(cx, top - a, cz)
	# The road on this world, in 24 m cells, for finding the nearest bit.
	var cells := {}
	for s: Array in samples:
		if s[1] != world or s[2]:
			continue
		var f: Transform3D = s[0]
		var key := Vector2i(floori(f.origin.x / 24.0), floori(f.origin.z / 24.0))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(f)
	var features := _features(world, body, cells)
	# Rings: close together across the top where the road is, then evenly
	# round the rest of the ball.
	var rings: Array[Vector2] = []   # (distance out, height)
	var d := 0.0
	var flat := a * 0.55
	while d < flat:
		rings.append(Vector2(d, StarlinerTrack.body_h(body, Vector2(cx + d, cz))))
		d += 3.0 if d < 12.0 else 11.0   # (the verge carries the detail by the road)
	var phi0 := asin(flat / a)
	var n := 22
	for k in range(1, n + 1):
		var phi := lerpf(phi0, PI, float(k) / n)
		rings.append(Vector2(a * sin(phi), top - a + a * cos(phi)))
	var segs := 56
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	for r in rings.size():
		var ring: Vector2 = rings[r]
		for k in segs:
			var ang := TAU * k / segs
			var p := Vector3(cx + cos(ang) * ring.x, ring.y, cz + sin(ang) * ring.x)
			if world == "moon" and ring.x < flat:
				p.y = StarlinerTrack.ground(Vector2(p.x, p.z), "moon")
			var dir := (p - centre).normalized()
			var lift := _feature_lift(features, dir)
			p += dir * lift.x
			var natural := p.y
			if ring.x < flat:
				p.y = _shape_round_road(cells, p, natural)
			verts.append(p)
			st.set_color(_tint(world, dir, natural - p.y, lift))
			st.add_vertex(p)
	# Shared corners, so the ball is shaded smooth rather than in facets.
	for r in rings.size() - 1:
		for k in segs:
			var i0 := r * segs + k
			var i1 := r * segs + (k + 1) % segs
			var i2 := (r + 1) * segs + (k + 1) % segs
			var i3 := (r + 1) * segs + k
			if world == "moon" and _in_bowl((verts[i0] + verts[i2]) * 0.5, 15.0):
				continue
			for i: int in [i0, i2, i1, i0, i3, i2]:
				st.add_index(i)
	KitTools.commit(t, st, ground_material(world))
	_verge(t, samples, world, body, features)
	# Lava glowing in each volcano's crater.
	var lava := SurfaceTool.new()
	lava.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for f: Dictionary in features:
		if f["kind"] != "volcano":
			continue
		any = true
		var dir: Vector3 = f["dir"]
		var floor_at := centre + dir * (a + _feature_lift([f], dir).x + 0.6)
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := dir.cross(side).normalized()
		var r := float(f["arad"]) * a * 0.16
		for m in 12:
			var a0 := TAU * m / 12.0
			var a1 := TAU * (m + 1) / 12.0
			KitTools.quad(lava, floor_at, floor_at + (side * cos(a0) + up * sin(a0)) * r, floor_at + (side * cos(a1) + up * sin(a1)) * r, floor_at,
				Color(1.0, 0.45, 0.12) if m % 2 == 0 else Color(1.0, 0.65, 0.22))
	if any:
		KitTools.commit(t, lava, KitTools.glow(Color.WHITE), true)


## The moon's craters and the red planet's volcanoes, off the road: each a
## direction from the centre, an angular radius and a size.
static func _features(world: String, body: Dictionary, cells: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 if world == "moon" else 57
	var a := float(body["a"])
	var centre := Vector3(float(body["x"]), float(body["top"]) - a, float(body["z"]))
	var clear_of_road := func(dir: Vector3, arad: float) -> bool:
		var p := centre + dir * a
		for c: Array in cells.values():
			for f: Transform3D in c:
				if Vector2(p.x - f.origin.x, p.z - f.origin.z).length() < arad * a * 1.6 + 30.0:
					return false
		for c: Vector2 in StarlinerTrack.CRATERS.values():
			if world == "moon" and Vector2(p.x, p.z).distance_to(c) < arad * a * 1.6 + 50.0:
				return false
		return true
	if world == "moon":
		var tries := 0
		while out.size() < 34 and tries < 500:
			tries += 1
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var arad := deg_to_rad(rng.randf_range(4.0, 14.0))
			if dir.y > 0.55 and not clear_of_road.call(dir, arad):
				continue
			var overlaps := false
			for f in out:
				if dir.angle_to(f["dir"]) < (arad + float(f["arad"])) * 0.9:
					overlaps = true
			if not overlaps:
				out.append({"kind": "crater", "dir": dir, "arad": arad, "h": arad * a * 0.26})
	else:
		# Volcanoes beside the road, that it weaves between.
		for c: Array in StarlinerTrack.MARS_CONES:
			var q := StarlinerTrack.mars_at(Vector2(c[0], c[1]))
			var p := Vector3(q.x, StarlinerTrack.ground(q, "mars"), q.y)
			out.append({"kind": "volcano", "dir": (p - centre).normalized(), "arad": float(c[2]) / a, "h": float(c[3])})
		# And three great ones round the sides, facing away from the moon
		# and the saucer, so no jump flies into one.
		for v: Array in [[150.0, 78.0, 15.0, 95.0], [225.0, 70.0, 13.0, 80.0], [300.0, 84.0, 14.0, 90.0]]:
			var az := deg_to_rad(v[0])
			var phi := deg_to_rad(v[1])
			out.append({"kind": "volcano", "dir": Vector3(sin(phi) * cos(az), cos(phi), sin(phi) * sin(az)),
				"arad": deg_to_rad(v[2]), "h": v[3]})
	return out


## How far the ground rises (+) or sinks along the way out, and how much
## of a feature this is (for colouring): (lift, crater floor 0..1, volcano
## slope 0..1, caldera 0..1).
static func _feature_lift(features: Array[Dictionary], v: Vector3) -> Vector4:
	var lift := 0.0
	var floor_k := 0.0
	var slope_k := 0.0
	var caldera := 0.0
	for f: Dictionary in features:
		var r := v.angle_to(f["dir"]) / float(f["arad"])
		if r > 1.6:
			continue
		var h := float(f["h"])
		if f["kind"] == "crater":
			if r < 1.0:
				lift += -h + h * 1.4 * r * r
				floor_k = maxf(floor_k, 1.0 - r)
			else:
				var u := (r - 1.0) / 0.6
				lift += h * 0.55 * (1.0 - u) * (1.0 - u)
		elif r < 1.0:
			# A steep cone on a broad base.
			var shield := h * (0.65 * pow(1.0 - r, 1.15) + 0.35 * pow(1.0 - r, 3.0))
			if r < 0.18:
				# The caldera: a pit in the summit.
				var rim := h * (0.65 * pow(0.82, 1.15) + 0.35 * pow(0.82, 3.0))
				shield = rim - h * 0.22 * (1.0 - r / 0.18)
				caldera = 1.0 - r / 0.18
			lift += shield
			slope_k = maxf(slope_k, 1.0 - r)
	return Vector4(lift, floor_k, slope_k, caldera)


static var _ground_shader: Shader
static var _ground_mats := {}


## The worlds' ground: their painted colours, with rock drawn into the
## surface (no extra triangles): lumpy relief that catches the light, small
## pits with pale rims scattered everywhere, and fine grain. The moon's is
## pocked; the red planet's is rougher and streaked.
static func ground_material(world: String) -> ShaderMaterial:
	if _ground_mats.has(world):
		return _ground_mats[world]
	if _ground_shader == null:
		_ground_shader = Shader.new()
		_ground_shader.code = """shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform float pits = 1.0;
uniform float streaks = 0.0;
uniform float relief = 1.0;
varying vec3 wpos;
varying vec3 tint;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = pow(COLOR.rgb, vec3(2.2));
}
void fragment() {
	// Rock at three sizes: boulders' lumps, stones, grit.
	float lumps = noise(wpos * 0.11);
	float stones = noise(wpos * 0.42 + 7.3);
	float grit = noise(wpos * 1.9 + 3.1);
	// Small pits: blobs of the noise pushed past a threshold, rimmed.
	float pn = noise(wpos * 0.06 + 11.0) * 0.7 + noise(wpos * 0.17 + 5.0) * 0.3;
	float pit = smoothstep(0.66, 0.74, pn) * pits;
	float rim = (smoothstep(0.6, 0.66, pn) - smoothstep(0.66, 0.7, pn)) * pits;
	float streak = streaks * smoothstep(0.55, 0.8, noise(vec3(wpos.x * 0.02, wpos.y * 0.3, wpos.z * 0.02)));
	vec3 c = tint * (0.74 + 0.36 * lumps) * (0.9 + 0.18 * stones) * (0.94 + 0.12 * grit);
	c *= 1.0 - 0.3 * pit - 0.15 * streak;
	c *= 1.0 + 0.22 * rim;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	// Bumps from the same rock: bend the surface's facing by how the height
	// changes across the screen.
	float h = (lumps * 1.4 + stones * 0.5 + grit * 0.12 - pit * 0.8 + rim * 0.5) * relief;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 0.9);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _ground_shader
	m.set_shader_parameter("pits", 1.0 if world == "moon" else 0.45)
	m.set_shader_parameter("streaks", 0.0 if world == "moon" else 1.0)
	m.set_shader_parameter("relief", 1.0 if world == "moon" else 1.25)
	_ground_mats[world] = m
	return m


## The ground beside the road meets the dust shoulders, then eases back to
## the world's own shape.
static func _shape_round_road(cells: Dictionary, p: Vector3, natural: float) -> float:
	var key := Vector2i(floori(p.x / 24.0), floori(p.z / 24.0))
	var best := 1e9
	var level := natural
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for f: Transform3D in cells.get(key + Vector2i(dx, dz), []):
				var dd := Vector2(p.x - f.origin.x, p.z - f.origin.z).length()
				if dd < best:
					best = dd
					level = f.origin.y - 1.0
	# Near the road the world's coarse ground stays well under the fine
	# verge (`_verge`), which carries the shape there; its big triangles
	# would otherwise lift over the road where the land rises beside it.
	if best < VERGE:
		return minf(natural, level - 2.5)
	return lerpf(minf(natural, level - 2.5), natural, smoothstep(VERGE, VERGE + 14.0, best))


## Fine ground either side of the road, from the guardrail out to VERGE:
## level with the shoulder at the rail, then rising or falling to the
## world's own shape (volcanoes and all) at the far edge.
static func _verge(t: Track, samples: Array, world: String, body: Dictionary, features: Array[Dictionary]) -> void:
	var a := float(body["a"])
	var centre := Vector3(float(body["x"]), float(body["top"]) - a, float(body["z"]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail := EDGE + StarlinerTrack.SHOULDER
	var any := false
	var shape := func(f: Transform3D, side: float, out: float) -> Array:
		var q := f.origin + f.basis.x * side * (rail + out)
		var g := Vector2(q.x, q.z)
		var y := StarlinerTrack.ground(g, world) if world == "mars" else StarlinerTrack.body_h(body, g)
		var p := Vector3(q.x, y, q.z)
		var dir := (p - centre).normalized()
		var lift := _feature_lift(features, dir)
		p += dir * lift.x
		var shoulder := f.origin.y - 0.55
		var u := smoothstep(0.0, VERGE - rail, out)
		var natural := p.y
		p.y = lerpf(shoulder, natural, u)
		return [p, _tint(world, dir, absf(natural - p.y) * (1.0 - u), lift)]
	for i in samples.size() - 1:
		var sa: Array = samples[i]
		var sb: Array = samples[i + 1]
		if sa[1] != world or sb[1] != world or sa[2] or sb[2] or float(sb[3]) - float(sa[3]) > 4.5:
			continue
		any = true
		var fa: Transform3D = sa[0]
		var fb: Transform3D = sb[0]
		for side: float in [-1.0, 1.0]:
			for k in VERGE_AT.size() - 1:
				var a0: Array = shape.call(fa, side, VERGE_AT[k])
				var a1: Array = shape.call(fa, side, VERGE_AT[k + 1])
				var b0: Array = shape.call(fb, side, VERGE_AT[k])
				var b1: Array = shape.call(fb, side, VERGE_AT[k + 1])
				var quad := [a0, b0, b1, a1] if side > 0.0 else [a0, a1, b1, b0]
				for idx: int in [0, 1, 2, 0, 2, 3]:
					st.set_color(quad[idx][1])
					st.add_vertex(quad[idx][0])
	if any:
		var mi := KitTools.commit(t, st, ground_material(world))
		mi.visibility_range_end = 700.0


static func _in_bowl(p: Vector3, apron: float) -> bool:
	for c: Vector2 in StarlinerTrack.CRATERS.values():
		if Vector2(p.x, p.z).distance_to(c) < StarlinerTrack.CR + apron:
			return true
	return false


## Ground colour, by direction from the world's centre, like a planet:
## the moon's pale highlands and dark seas, the red planet's rust plains,
## dusty pale lands, dark lands and its south ice cap; then the features'
## own colours (crater floors and rims, volcano slopes and calderas).
static func _tint(world: String, dir: Vector3, cut: float, lift: Vector4) -> Color:
	var big := _vnoise(dir * 2.3 + Vector3(3.1, 0.7, 1.9))
	var mid := _vnoise(dir * 6.0 + Vector3(0.4, 5.2, 2.6))
	var fine := _vnoise(dir * 19.0)
	if world == "moon":
		var highland := Color(0.8, 0.8, 0.82).lerp(Color(0.7, 0.7, 0.74), mid)
		var sea := Color(0.4, 0.41, 0.47).lerp(Color(0.48, 0.49, 0.55), fine)
		var c := highland.lerp(sea, smoothstep(0.52, 0.62, big) * 0.9)
		c = c.darkened(0.08 * (fine - 0.5))
		if lift.y > 0.0:
			c = c.darkened(0.28 * lift.y)          # crater floors darker
		elif lift.x > 0.5:
			c = c.lightened(0.18)                 # their rims paler
		return c.darkened(0.1) if cut > 1.5 else c
	if dir.y < -0.86:
		return Color(0.94, 0.95, 0.98).lerp(Color(0.8, 0.55, 0.45), smoothstep(-0.9, -0.86, dir.y))   # the ice cap
	if lift.w > 0.0:
		return Color(0.16, 0.07, 0.05)   # a caldera's scorched pit
	var plains := StarlinerTrack.RUST.lerp(StarlinerTrack.RUST_LIGHT, smoothstep(0.3, 0.8, mid))
	var c := plains.lerp(StarlinerTrack.RUST_DARK, smoothstep(0.55, 0.68, big) * 0.75)
	c = c.lightened(0.06 * (fine - 0.5))
	if lift.z > 0.0:
		# A volcano's slopes: darker rock towards the summit.
		c = c.lerp(Color(0.4, 0.2, 0.14), lift.z * 0.7)
	return c.darkened(0.1) if cut > 1.5 else c


## Smooth noise over space, 0..1 (for colouring worlds; never random).
static func _vnoise(p: Vector3) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector3.ONE * 3.0 - f * 2.0)
	var n := 0.0
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var c := i + Vector3(dx, dy, dz)
				var h := absf(sin(c.x * 127.1 + c.y * 311.7 + c.z * 74.7) * 43758.5453)
				h -= floorf(h)
				var w := (f.x if dx == 1 else 1.0 - f.x) * (f.y if dy == 1 else 1.0 - f.y) * (f.z if dz == 1 else 1.0 - f.z)
				n += h * w
	return n


## The craters' bowls (you can drive anywhere in them), their rims railed
## except for the ways in and the lips out, and a gate of lights on each lip.
static func _craters(t: Track, _samples: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hit := SurfaceTool.new()
	hit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lights := SurfaceTool.new()
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radii: Array[float] = [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 27.0, 30.0, 32.5, 36.5, 41.0, 47.0]
	var segs := 32
	for key: String in StarlinerTrack.CRATERS:
		var c: Vector2 = StarlinerTrack.CRATERS[key]
		var pts: Array[Vector3] = []
		for r: float in radii:
			for k in segs:
				var ang := TAU * k / segs
				var q := c + Vector2(cos(ang), sin(ang)) * r
				pts.append(Vector3(q.x, StarlinerTrack.ground(q, "moon"), q.y))
		for i in radii.size() - 1:
			for k in segs:
				var i0 := i * segs + k
				var i1 := i * segs + (k + 1) % segs
				var i2 := (i + 1) * segs + (k + 1) % segs
				var i3 := (i + 1) * segs + k
				var u := radii[i] / StarlinerTrack.CR
				var col := StarlinerTrack.MOON_DARK.lerp(StarlinerTrack.MOON_C, clampf(u * u, 0.0, 1.0)) if u <= 1.0 else StarlinerTrack.MOON_C.lightened(0.08 * (1.0 - clampf(u - 1.0, 0.0, 1.0) * 2.0))
				KitTools.quad(st, pts[i0], pts[i3], pts[i2], pts[i1], col)
		# The ways out (and the road's way in), with the rail broken there.
		var gaps: Array[Vector2] = []    # (direction angle, half-width in metres)
		for p: Dictionary in t.pads:
			if Vector2((p["centre"] as Vector3).x, (p["centre"] as Vector3).z).distance_to(c) < 1.0:
				var dir: Vector3 = p["dir"]
				gaps.append(Vector2(atan2(dir.z, dir.x), float(p["half"]) + 1.0))
				_lip_gate(lights, c, dir, p)
		if key == "T":
			# The road in from the moon's road.
			gaps.append(Vector2(atan2(-StarlinerTrack.FIELD.y, -StarlinerTrack.FIELD.x), Track.ROAD_WIDTH * 0.5 + 2.0))
		var steps := 64
		for k in steps:
			var a0 := TAU * k / steps
			var a1 := TAU * (k + 1) / steps
			var open := false
			for g: Vector2 in gaps:
				var mid := (a0 + a1) * 0.5
				if absf(angle_difference(mid, g.x)) * (StarlinerTrack.CR + 1.0) < g.y:
					open = true
			if open:
				continue
			var pa := Vector2(cos(a0), sin(a0))
			var pb := Vector2(cos(a1), sin(a1))
			var r := StarlinerTrack.CR + 1.0
			var fa := Vector3(c.x + pa.x * r, StarlinerTrack.ground(c + pa * r, "moon"), c.y + pa.y * r)
			var fb := Vector3(c.x + pb.x * r, StarlinerTrack.ground(c + pb * r, "moon"), c.y + pb.y * r)
			for k2: float in [0.0, 0.8]:
				var oa := Vector3(pa.x, 0, pa.y) * k2
				var ob := Vector3(pb.x, 0, pb.y) * k2
				# Solid well above the rail: a kart coming up the bowl fast leaves
				# the crest in the air, and cleared a rail-high wall.
				KitTools.quad(hit, fa + oa - Vector3.UP * 0.5, fb + ob - Vector3.UP * 0.5, fb + ob + Vector3.UP * 5.0, fa + oa + Vector3.UP * 5.0, Color.WHITE)
			if k % 2 == 0:
				KitTools.box(rails, Transform3D(Basis(), fa + Vector3.UP * RAIL_H * 0.5), Vector3(0.22, RAIL_H, 0.22), Color(0.92, 0.93, 0.95))
			var up := Vector3.UP * 0.13
			KitTools.quad(rails, fa + Vector3.UP * 1.15 - up, fb + Vector3.UP * 1.15 - up, fb + Vector3.UP * 1.15 + up, fa + Vector3.UP * 1.15 + up, Color(0.2, 0.45, 0.95))
			KitTools.quad(rails, fa + Vector3.UP * 0.65 - up, fb + Vector3.UP * 0.65 - up, fb + Vector3.UP * 0.65 + up, fa + Vector3.UP * 0.65 + up, Color(0.92, 0.93, 0.95))
	st.index()              # shared corners: shaded smooth, not in facets
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = ground_material("moon")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(mi)
	# Firm ground: the bowls are the road here (the lap's road lies just
	# under them), so you drive on what you see.
	KitTools.solid(t, mesh, "regolith")
	KitTools.commit(t, rails, Palette.toon(Color.WHITE, true), true)
	KitTools.commit(t, lights, KitTools.glow(Color.WHITE), true)
	hit.generate_normals()
	KitTools.solid(t, hit.commit())


## Two glowing posts either side of a lip, and an arrow on the ground
## pointing out: cyan straight on, amber to a side crater.
static func _lip_gate(st: SurfaceTool, c: Vector2, dir: Vector3, p: Dictionary) -> void:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var col := StarlinerTrack.CYAN if absf(dir.x) < 0.1 else StarlinerTrack.AMBER
	var lip := Vector2(c.x, c.y) + Vector2(dir.x, dir.z) * StarlinerTrack.CR
	var base := Vector3(lip.x, StarlinerTrack.ground(lip, "moon"), lip.y)
	for s: float in [-1.0, 1.0]:
		var at := base + side * s * (float(p["half"]) + 0.8)
		KitTools.box(st, Transform3D(Basis.looking_at(dir, Vector3.UP), at + Vector3.UP * 1.8), Vector3(0.5, 3.6, 0.5), col)
	# A chevron on the bowl wall just inside the lip.
	var inside := Vector2(c.x, c.y) + Vector2(dir.x, dir.z) * (StarlinerTrack.CR - 7.0)
	var g := Vector3(inside.x, StarlinerTrack.ground(inside, "moon") + StarlinerTrack.RIDE + 0.08, inside.y)
	for s: float in [-1.0, 1.0]:
		var tail := g + side * s * 2.8 - dir * 1.0
		var tip := g + dir * 1.6
		var w := dir * 0.9
		KitTools.quad(st, tail, tip, tip + w, tail + w, col, s > 0.0)


## The flying saucer: a deck with a glass dome, lights round its rim and
## glowing underneath, vent housings by the road, and the last vent's
## column of gas that always blows.
static func _saucer(t: Track) -> void:
	var c := StarlinerTrack.SAUCER
	var deck := c.y - 0.75
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body: a profile (distance out, height) spun round.
	var prof: Array[Vector2] = [Vector2(0, deck), Vector2(60, deck), Vector2(StarlinerTrack.SAUCER_R - 4.0, deck), Vector2(StarlinerTrack.SAUCER_R, deck - 1.5),
		Vector2(StarlinerTrack.SAUCER_R + 3.0, deck - 4.5), Vector2(StarlinerTrack.SAUCER_R - 8.0, deck - 10.0), Vector2(70, deck - 17.0), Vector2(30, deck - 21.0), Vector2(0, deck - 22.0)]
	var cols: Array[Color] = [StarlinerTrack.HULL, StarlinerTrack.HULL.darkened(0.08), StarlinerTrack.HULL.darkened(0.15), StarlinerTrack.HULL.lightened(0.05), Color(0.6, 0.64, 0.72), Color(0.5, 0.54, 0.62), Color(0.42, 0.46, 0.55), Color(0.38, 0.42, 0.5)]
	_spin(st, c, prof, cols, 48)
	# The dome, glass with a lit band.
	var dome: Array[Vector2] = []
	for k in 9:
		var a := PI * 0.5 * k / 8.0
		dome.append(Vector2(44.0 * cos(a), deck + 24.0 * sin(a)))
	var glass: Array[Color] = []
	for k in 8:
		glass.append(Color(0.25, 0.6, 0.85).lerp(Color(0.6, 0.85, 1.0), k / 8.0))
	_spin(st, c, dome, glass, 40)
	for k in 40:
		var a := TAU * k / 40.0
		var p := c + Vector3(cos(a) * 44.3, 3.0 - 0.75, sin(a) * 44.3)
		KitTools.box(glow, Transform3D(Basis(Vector3.UP, -a), p), Vector3(0.3, 1.2, 3.0), StarlinerTrack.AMBER if k % 2 == 0 else StarlinerTrack.CYAN)
	# Lights round the rim and a glowing ring underneath.
	for k in 72:
		var a := TAU * k / 72.0
		var p := c + Vector3(cos(a) * (StarlinerTrack.SAUCER_R + 1.6), -3.0 - 0.75, sin(a) * (StarlinerTrack.SAUCER_R + 1.6))
		KitTools.box(glow, Transform3D(Basis(Vector3.UP, -a), p), Vector3(1.4, 1.4, 1.4), StarlinerTrack.CYAN if k % 3 else StarlinerTrack.AMBER)
	for k in 48:
		var a0 := TAU * k / 48.0
		var a1 := TAU * (k + 1) / 48.0
		for r: Vector2 in [Vector2(52.0, 58.0)]:
			var y := deck - 18.6
			KitTools.quad(glow, c + Vector3(cos(a0) * r.x, y - c.y, sin(a0) * r.x), c + Vector3(cos(a1) * r.x, y - c.y, sin(a1) * r.x),
				c + Vector3(cos(a1) * r.y, y - c.y, sin(a1) * r.y), c + Vector3(cos(a0) * r.y, y - c.y, sin(a0) * r.y), Color(0.5, 1.0, 0.75))
	# Vent housings beside the road: warning-striped boxes with a lamp.
	for h: Dictionary in t.fx_hazards:
		if not h.get("blow", false):
			continue
		var f := t.road_frame(float(h["at"]))
		var s := signf(float(h["from_x"]) + float(h["to_x"]))
		var at := f.origin + f.basis.x * s * (EDGE + StarlinerTrack.SHOULDER + 2.2)
		KitTools.box(st, Transform3D(f.basis, at + Vector3.UP * 1.6), Vector3(2.4, 3.2, 4.0), Color(0.3, 0.32, 0.38))
		for k in 4:
			KitTools.box(st, Transform3D(f.basis, at + Vector3.UP * (0.4 + k * 0.8) - f.basis.x * s * 1.25), Vector3(0.1, 0.4, 4.0), StarlinerTrack.AMBER if k % 2 == 0 else Color(0.12, 0.12, 0.14))
		KitTools.box(glow, Transform3D(f.basis, at + Vector3.UP * 3.6), Vector3(0.8, 0.8, 0.8), StarlinerTrack.AMBER)
	KitTools.commit(t, st, Palette.toon(Color.WHITE, true))
	KitTools.commit(t, glow, KitTools.glow(Color.WHITE), true)
	# The last vent: gas across the whole road, always blowing.
	var vf := t.road_frame(StarlinerTrack._at(t, "vent"))
	var gas := SpaceFx.vent(Track.ROAD_WIDTH + 4.0, 55.0)
	gas.transform = Transform3D(vf.basis, vf.origin - vf.basis.z * 2.0)
	t.add_child(gas)
	gas.set_level(1.0)
	var grate := SurfaceTool.new()
	grate.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 7:
		KitTools.box(grate, Transform3D(vf.basis, vf.origin + Vector3.UP * 0.05 - vf.basis.z * (0.2 + k * 0.7)), Vector3(Track.ROAD_WIDTH, 0.06, 0.35), Color(0.75, 1.0, 0.85))
	KitTools.commit(t, grate, KitTools.glow(Color.WHITE))
	# Little green aliens cheering on the deck by the start.
	var spots: Array[Transform3D] = []
	var start := StarlinerTrack._at(t, "start")
	for x in KitDress.beside(t, start - 50.0, start + 70.0, 3.0, StarlinerTrack.SHOULDER + 3.2, [-1.0]):
		spots.append(Transform3D(x.basis, Vector3(x.origin.x, deck + 0.75 - 0.5, x.origin.z)))
	KitDress.crowd(t, spots, [Color(0.45, 0.9, 0.4), Color(0.6, 1.0, 0.55), Color(0.35, 0.8, 0.6)], 1)


## A surface of revolution round `c`: profile points (distance out,
## height), one colour per band.
static func _spin(st: SurfaceTool, c: Vector3, prof: Array[Vector2], cols: Array[Color], segs: int) -> void:
	for i in prof.size() - 1:
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p := prof[i]
			var q := prof[i + 1]
			var v0 := Vector3(c.x + cos(a0) * p.x, p.y, c.z + sin(a0) * p.x)
			var v1 := Vector3(c.x + cos(a1) * p.x, p.y, c.z + sin(a1) * p.x)
			var v2 := Vector3(c.x + cos(a1) * q.x, q.y, c.z + sin(a1) * q.x)
			var v3 := Vector3(c.x + cos(a0) * q.x, q.y, c.z + sin(a0) * q.x)
			KitTools.quad(st, v0, v1, v2, v3, cols[mini(i, cols.size() - 1)], true)


## Rocks, the moon base at the start, astronauts cheering, dust devils
## roaming the red planet, and arrows on every sharp bend.
static func _dress(t: Track) -> void:
	KitDress.chevrons(t, StarlinerTrack.NAVY, StarlinerTrack.CYAN, [[StarlinerTrack._at(t, "t_lip") - 70.0, StarlinerTrack._at(t, "b_lip") + 10.0]],
		EDGE - Track.ROAD_WIDTH * 0.5 + StarlinerTrack.SHOULDER + 0.9)
	var moon_rocks: Array[Transform3D] = []
	var mars_rocks: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 110:
		var on_mars := i % 2 == 1
		var body: Dictionary = StarlinerTrack.MARS if on_mars else StarlinerTrack.MOON
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * float(body["a"]) * 0.75
		var q := Vector2(float(body["x"]) + cos(ang) * r, float(body["z"]) + sin(ang) * r)
		var p := Vector3(q.x, 0.0, q.y)
		if not KitDress.off_road(t, p, EDGE + StarlinerTrack.SHOULDER + 8.0) or (not on_mars and _in_bowl(p, 18.0)):
			continue
		p.y = StarlinerTrack.ground(q, "mars" if on_mars else "moon") - 0.4
		var size := rng.randf_range(0.3, 1.2) if not on_mars else rng.randf_range(0.5, 1.6)
		var x := KitDress.varied(Transform3D(Basis(), p), size, 0.3)
		(mars_rocks if on_mars else moon_rocks).append(x)
	KitDress.scatter(t, "asteroid", moon_rocks, 240.0, 100.0)
	KitDress.scatter(t, "mars_rock", mars_rocks, 240.0, 100.0)
	# A moon base beside the first crater, where the saucer drops you:
	# modules, dishes, aerials.
	var mods: Array[Transform3D] = []
	var dishes: Array[Transform3D] = []
	var aerials: Array[Transform3D] = []
	var T: Vector2 = StarlinerTrack.CRATERS["T"]
	var k := 0
	for off: Vector2 in [Vector2(62, -40), Vector2(70, -8), Vector2(64, 24), Vector2(84, -26), Vector2(86, 10), Vector2(56, 50), Vector2(52, -62)]:
		var q := T + off
		var p := Vector3(q.x, StarlinerTrack.ground(q, "moon") - 0.4, q.y)
		var face := Basis.looking_at(Vector3(T.x - q.x, 0, T.y - q.y).normalized(), Vector3.UP)
		match k % 3:
			0: mods.append(Transform3D(face.scaled(Vector3.ONE * 1.4), p))
			1: dishes.append(Transform3D(face.scaled(Vector3.ONE * 1.2), p))
			_: aerials.append(Transform3D(Basis(), p))
		k += 1
	KitTools.place(t, "cargo_pod", mods, 320.0)
	KitTools.place(t, "dish", dishes, 360.0)
	KitTools.place(t, "antenna", aerials, 360.0)
	# Dust devils roaming the red planet, away from the road.
	for c: Vector2 in [Vector2(-115, 105), Vector2(150, -75), Vector2(-95, -140)]:
		var centre := StarlinerTrack.mars_at(c)
		var loop := PackedVector3Array()
		for n in 6:
			var a := TAU * n / 6.0
			var q := centre + Vector2(cos(a), sin(a)) * 30.0
			loop.append(Vector3(q.x, StarlinerTrack.ground(q, "mars") - 0.5, q.y))
		t.add_child(SpaceFx.roamer(SpaceFx.dust_devil(), loop, 5.0))


## Space: stars all round, a far sun, and a ringed giant in the distance.
static func _space(t: Track) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stars := SurfaceTool.new()
	stars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(150, 150, -330)
	for i in 420:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var p := centre + dir * 2200.0
		var size := rng.randf_range(3.0, 9.0)
		var right := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized() * size
		var up := right.cross(dir).normalized() * size
		var c := Color.WHITE.lerp(StarlinerTrack.CYAN if i % 5 == 0 else StarlinerTrack.VIOLET, rng.randf() * 0.5)
		KitTools.quad(stars, p - right - up, p + right - up, p + right + up, p - right + up, c)
	# The sun, and a soft glow round it.
	var sun_dir := Vector3(-0.5, 0.35, 0.8).normalized()
	var sp := centre + sun_dir * 2100.0
	var sr := sun_dir.cross(Vector3.UP).normalized()
	var su := sr.cross(sun_dir).normalized()
	for ring: Array in [[140.0, Color(1.0, 0.95, 0.75)], [230.0, Color(0.45, 0.32, 0.2)]]:
		var r: float = ring[0]
		for n in 24:
			var a0 := TAU * n / 24.0
			var a1 := TAU * (n + 1) / 24.0
			KitTools.quad(stars, sp - sun_dir * (r * 0.01), sp + (sr * cos(a0) + su * sin(a0)) * r, sp + (sr * cos(a1) + su * sin(a1)) * r, sp - sun_dir * (r * 0.01), ring[1])
	var si := KitTools.commit(t, stars, KitTools.glow(Color.WHITE), true)
	si.extra_cull_margin = 4000.0
	# A ringed giant, far off.
	var giant := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 420.0
	ball.height = 840.0
	ball.radial_segments = 20
	ball.rings = 10
	giant.mesh = ball
	giant.material_override = Palette.toon(StarlinerTrack.VIOLET.lerp(StarlinerTrack.CYAN, 0.3))
	giant.position = centre + Vector3(1500, -350, 900)
	giant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(giant)
	var rings := SurfaceTool.new()
	rings.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tilt := Basis(Vector3(1, 0, 0.4).normalized(), 0.4)
	for band: Array in [[520.0, 590.0, StarlinerTrack.VIOLET.lightened(0.35)], [605.0, 700.0, StarlinerTrack.CYAN.lerp(Color.WHITE, 0.4)]]:
		for n in 48:
			var a0 := TAU * n / 48.0
			var a1 := TAU * (n + 1) / 48.0
			var u0 := tilt * Vector3(cos(a0), 0, sin(a0))
			var u1 := tilt * Vector3(cos(a1), 0, sin(a1))
			KitTools.quad(rings, u0 * float(band[0]), u1 * float(band[0]), u1 * float(band[1]), u0 * float(band[1]), band[2])
	var ri := KitTools.commit(t, rings, KitTools.glow(Color.WHITE), true)
	ri.position = giant.position
