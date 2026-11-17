class_name SpaceWorlds
extends RefCounted
## What Starliner Run is made of (design doc 8.6): the moon and the red
## planet with the road cut into them, the moon's crater bowls with their
## rim rails and side ramps, dust shoulders and guardrails along every road,
## the flying saucer, and space round it all.

const EDGE := Track.ROAD_WIDTH * 0.5 + 1.1   # where the road's kerb ends
const RAIL_H := 1.3


static func build(t: Track) -> void:
	var samples := _road_samples(t)
	_shoulders(t, samples)
	_planet(t, StarlinerTrack.MOON, "moon", samples)
	_planet(t, StarlinerTrack.MARS, "mars", samples)
	_craters(t, samples)
	_crater_ramps(t)
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


## A world: a squashed ball, its top shaped round the road (cut into the
## ground where it rises beside it, built up where it falls away), with
## holes where the crater bowls go.
static func _planet(t: Track, body: Dictionary, world: String, samples: Array) -> void:
	var cx := float(body["x"])
	var cz := float(body["z"])
	var a := float(body["a"])
	var bb := float(body["b"])
	var top := float(body["top"])
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
	# Rings: close together across the top, wider down the sides and under.
	var rings: Array[Vector2] = []   # (distance out, height)
	var d := 0.0
	var flat := a * 0.8
	while d < flat:
		rings.append(Vector2(d, StarlinerTrack.body_h(body, Vector2(cx + d, cz))))
		d += 3.0 if d < 12.0 else 7.0
	var phi0 := asin(flat / a)
	for k in range(1, 11):
		var phi := lerpf(phi0, PI, float(k) / 10.0)
		rings.append(Vector2(a * sin(phi), top - bb + bb * cos(phi)))
	var segs := 56
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	for r in rings.size():
		var ring: Vector2 = rings[r]
		for k in segs:
			var ang := TAU * k / segs
			var p := Vector3(cx + cos(ang) * ring.x, ring.y, cz + sin(ang) * ring.x)
			var natural := p.y
			if world == "moon":
				p.y = StarlinerTrack.ground(Vector2(p.x, p.z), "moon") if ring.x < flat else p.y
			elif ring.x < flat:
				p.y += _dunes(p) * smoothstep(0.0, 40.0, ring.x)
			natural = p.y
			if ring.x < flat:
				p.y = _shape_round_road(cells, p, natural)
			verts.append(p)
			cols.append(_tint(world, p, ring, natural - p.y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings.size() - 1:
		for k in segs:
			var i0 := r * segs + k
			var i1 := r * segs + (k + 1) % segs
			var i2 := (r + 1) * segs + (k + 1) % segs
			var i3 := (r + 1) * segs + k
			if world == "moon" and _in_bowl((verts[i0] + verts[i2]) * 0.5, 15.0):
				continue
			for i: int in [i0, i2, i1, i0, i3, i2]:
				st.set_color(cols[i])
				st.add_vertex(verts[i])
	KitTools.commit(t, st, Palette.toon(Color.WHITE, true))


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
	var inner := EDGE + StarlinerTrack.SHOULDER + 2.0
	if best < inner:
		return minf(level, natural) if natural < level - 6.0 else level
	return lerpf(level, natural, smoothstep(inner, inner + 18.0, best))


static func _in_bowl(p: Vector3, apron: float) -> bool:
	for c: Vector2 in StarlinerTrack.CRATERS.values():
		if Vector2(p.x, p.z).distance_to(c) < StarlinerTrack.CR + apron:
			return true
	return false


## The red planet's dunes (gentle; never under the road).
static func _dunes(p: Vector3) -> float:
	return 1.6 * sin(p.x * 0.045 + sin(p.z * 0.03) * 2.0) * sin(p.z * 0.05)


## Ground colour: the moon grey with darker seas and small pale craters;
## the red planet rust with light dust and dark streaks, and an ice cap
## underneath.
static func _tint(world: String, p: Vector3, ring: Vector2, cut: float) -> Color:
	var n := sin(p.x * 0.021 + 1.3) * sin(p.z * 0.017 + 0.4) + 0.5 * sin(p.x * 0.07 - p.z * 0.05)
	if world == "moon":
		var c := StarlinerTrack.MOON_C.lerp(StarlinerTrack.MOON_DARK, clampf(n * 0.6, 0.0, 0.7))
		for k in 24:
			var at := Vector2(sin(k * 12.9898) * 230.0, cos(k * 78.233) * 230.0)
			var r := 6.0 + fposmod(k * 7.3, 9.0)
			var dd := Vector2(p.x, p.z).distance_to(at)
			if dd < r:
				c = c.darkened(0.25) if dd < r * 0.75 else c.lightened(0.18)
		if cut > 1.5:
			c = c.darkened(0.12)   # the walls of a cutting
		return c
	if ring.y < float(StarlinerTrack.MARS["top"]) - float(StarlinerTrack.MARS["b"]) * 1.75:
		return Color(0.95, 0.95, 0.98)   # the ice cap
	var c := StarlinerTrack.RUST.lerp(StarlinerTrack.RUST_LIGHT, clampf(n * 0.5 + 0.3, 0.0, 1.0))
	# Dark lands in blotches, not bands.
	var blot := sin(p.x * 0.019 + 0.7) * sin(p.z * 0.023 - 1.1) + 0.45 * sin(p.x * 0.051 + p.z * 0.037)
	if blot > 0.45:
		c = c.lerp(StarlinerTrack.RUST_DARK, clampf((blot - 0.45) * 1.2, 0.0, 0.6))
	return c.darkened(0.1) if cut > 1.5 else c


## The craters' bowls (you can drive anywhere in them), their rims railed
## except for the ways in and the lips out, and a gate of lights on each lip.
static func _craters(t: Track, samples: Array) -> void:
	# The road on the moon, in cells: the bowls are lowered under it.
	var cells := {}
	for s: Array in samples:
		if s[1] != "moon":
			continue
		var f: Transform3D = s[0]
		var key := Vector2i(floori(f.origin.x / 12.0), floori(f.origin.z / 12.0))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(f)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hit := SurfaceTool.new()
	hit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lights := SurfaceTool.new()
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radii: Array[float] = [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 27.0, 30.0, 32.5, 36.5, 41.0, 47.0]
	var segs := 36
	for key: String in StarlinerTrack.CRATERS:
		var c: Vector2 = StarlinerTrack.CRATERS[key]
		var pts: Array[Vector3] = []
		for r: float in radii:
			for k in segs:
				var ang := TAU * k / segs
				var q := c + Vector2(cos(ang), sin(ang)) * r
				var p := Vector3(q.x, StarlinerTrack.ground(q, "moon"), q.y)
				p.y = _under_road(cells, p, 12.0)
				pts.append(p)
		for i in radii.size() - 1:
			for k in segs:
				var i0 := i * segs + k
				var i1 := i * segs + (k + 1) % segs
				var i2 := (i + 1) * segs + (k + 1) % segs
				var i3 := (i + 1) * segs + k
				var u := radii[i] / StarlinerTrack.CR
				var col := StarlinerTrack.MOON_DARK.lerp(StarlinerTrack.MOON_C, clampf(u * u, 0.0, 1.0)) if u <= 1.0 else StarlinerTrack.MOON_C.lightened(0.08 * (1.0 - clampf(u - 1.0, 0.0, 1.0) * 2.0))
				if (k + i) % 2 == 0:
					col = col.darkened(0.04)
				KitTools.quad(st, pts[i0], pts[i3], pts[i2], pts[i1], col)
		# The ways out (and the road's way in), with the rail broken there.
		var gaps: Array[Vector2] = []    # (direction angle, half-width in metres)
		for p: Dictionary in t.pads:
			if Vector2((p["centre"] as Vector3).x, (p["centre"] as Vector3).z).distance_to(c) < 1.0:
				var dir: Vector3 = p["dir"]
				gaps.append(Vector2(atan2(dir.z, dir.x), float(p["half"]) + 1.0))
				_lip_gate(lights, c, dir, p)
		if key == "T":
			gaps.append(Vector2(PI * 0.5, Track.ROAD_WIDTH * 0.5 + 2.0))   # the road in from the base
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
				KitTools.quad(hit, fa + oa - Vector3.UP * 0.5, fb + ob - Vector3.UP * 0.5, fb + ob + Vector3.UP * RAIL_H, fa + oa + Vector3.UP * RAIL_H, Color.WHITE)
			if k % 2 == 0:
				KitTools.box(rails, Transform3D(Basis(), fa + Vector3.UP * RAIL_H * 0.5), Vector3(0.22, RAIL_H, 0.22), Color(0.92, 0.93, 0.95))
			var up := Vector3.UP * 0.13
			KitTools.quad(rails, fa + Vector3.UP * 1.15 - up, fb + Vector3.UP * 1.15 - up, fb + Vector3.UP * 1.15 + up, fa + Vector3.UP * 1.15 + up, Color(0.2, 0.45, 0.95))
			KitTools.quad(rails, fa + Vector3.UP * 0.65 - up, fb + Vector3.UP * 0.65 - up, fb + Vector3.UP * 0.65 + up, fa + Vector3.UP * 0.65 + up, Color(0.92, 0.93, 0.95))
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Palette.toon(Color.WHITE, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(mi)
	# Firm ground: the bowls are the track here, not the shoulder.
	KitTools.solid(t, mesh, "dirt")
	KitTools.commit(t, rails, Palette.toon(Color.WHITE, true), true)
	KitTools.commit(t, lights, KitTools.glow(Color.WHITE), true)
	hit.generate_normals()
	KitTools.solid(t, hit.commit())


## Ground that would rise through the road (a bowl curves up across it)
## is kept just under it, and eases back beside it.
static func _under_road(cells: Dictionary, p: Vector3, cell: float) -> float:
	var key := Vector2i(floori(p.x / cell), floori(p.z / cell))
	var y := p.y
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for f: Transform3D in cells.get(key + Vector2i(dx, dz), []):
				var local := f.affine_inverse() * p
				if absf(local.z) > 3.0:
					continue
				var road := (f * Vector3(local.x, 0.0, 0.0)).y
				var x := absf(local.x)
				if x < EDGE + 4.0:
					# Under the road, then rising to meet its edge (no step to
					# catch a kart coming back on), then the bowl's own shape.
					var under := road - 0.4 + 0.36 * smoothstep(EDGE - 1.5, EDGE, x)
					y = minf(y, lerpf(under, p.y, smoothstep(EDGE, EDGE + 4.0, x))) if x < EDGE else lerpf(under, p.y, smoothstep(EDGE, EDGE + 4.0, x))
	return y


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


## Ramps out of the first crater to its side lips, and in each side crater
## a road from where you land to its lip, with a boost on the way.
static func _crater_ramps(t: Track) -> void:
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var boost := SurfaceTool.new()
	boost.begin(Mesh.PRIMITIVE_TRIANGLES)
	var T: Vector2 = StarlinerTrack.CRATERS["T"]
	var B: Vector2 = StarlinerTrack.CRATERS["B"]
	for k: String in ["L", "R"]:
		var side: Vector2 = StarlinerTrack.CRATERS[k]
		var out := (side - T).normalized()
		_strip(road, null, [T + out * 9.0, T + out * StarlinerTrack.CR], 9.0, -1.0, -1.0)
		var into := (side - T).normalized()
		var on := (B - side).normalized()
		var land := side - into * StarlinerTrack.CR * 0.55
		var path := [land, side - into * 4.0 + on * 2.0, side + on * 10.0, side + on * StarlinerTrack.CR]
		_strip(road, boost, path, 10.0, 0.4, 0.62)
	road.generate_normals()
	var mesh := road.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Palette.toon(Color.WHITE, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(mi)
	KitTools.solid(t, mesh, "asphalt")
	boost.generate_normals()
	var bm := boost.commit()
	var bi := MeshInstance3D.new()
	bi.mesh = bm
	bi.material_override = KitTools.glow(Color.WHITE)
	t.add_child(bi)
	KitTools.solid(t, bm, "boost")


## A raised road strip through `path` (points across the ground), hugging
## the bowl it runs through; from `b0` to `b1` of the way along it is a
## boost pad instead.
static func _strip(road: SurfaceTool, boost: SurfaceTool, path: Array, width: float, b0: float, b1: float) -> void:
	var c := Curve2D.new()
	for i in path.size():
		var prev: Vector2 = path[maxi(i - 1, 0)]
		var next: Vector2 = path[mini(i + 1, path.size() - 1)]
		c.add_point(path[i], -(next - prev) / 6.0, (next - prev) / 6.0)
	c.bake_interval = 0.5
	var length := c.get_baked_length()
	var step := 2.0
	var d := 0.0
	var index := 0
	while d < length - 0.01:
		var e := minf(d + step, length)
		var pa := c.sample_baked(d)
		var pb := c.sample_baked(e)
		var dir := (pb - pa).normalized()
		var right := Vector2(-dir.y, dir.x)
		var corners: Array[Vector3] = []
		for q: Vector2 in [pa - right * width * 0.5, pb - right * width * 0.5, pb + right * width * 0.5, pa + right * width * 0.5]:
			corners.append(Vector3(q.x, StarlinerTrack.ground(q, "moon") + 0.07, q.y))   # flush: no edge to catch on
		var u := (d + e) * 0.5 / length
		var on_boost := boost != null and u > b0 and u < b1
		var col := Color(1.0, 0.62, 0.15) if on_boost else (StarlinerTrack.ROAD if index % 2 == 0 else StarlinerTrack.ROAD.darkened(0.04))
		KitTools.quad(boost if on_boost else road, corners[0], corners[1], corners[2], corners[3], col)
		d = e
		index += 1


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
	_spin(st, c, prof, cols, 64)
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
	# The last vent: a column of gas across the whole road, always blowing.
	var vf := t.road_frame(StarlinerTrack._at(t, "vent"))
	var gas := MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.bottom_radius = 5.0
	col.top_radius = 16.0
	col.height = 60.0
	col.radial_segments = 16
	col.rings = 1
	col.cap_top = false
	col.cap_bottom = false
	gas.mesh = col
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 1.0, 0.85, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	gas.material_override = m
	gas.transform = Transform3D(vf.basis.scaled(Vector3(1.6, 1.0, 0.6)), vf.origin + Vector3.UP * 30.0 - vf.basis.z * 2.0)
	gas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(gas)
	var grate := SurfaceTool.new()
	grate.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 7:
		KitTools.box(grate, Transform3D(vf.basis, vf.origin + Vector3.UP * 0.05 - vf.basis.z * (0.2 + k * 0.7)), Vector3(Track.ROAD_WIDTH, 0.06, 0.35), Color(0.75, 1.0, 0.85))
	KitTools.commit(t, grate, KitTools.glow(Color.WHITE))
	# Little green aliens cheering on the deck by the landing.
	var spots: Array[Transform3D] = []
	var land := StarlinerTrack._at(t, "saucer_land")
	for x in KitDress.beside(t, land + 20.0, land + 110.0, 3.0, StarlinerTrack.SHOULDER + 3.2, [-1.0]):
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
	KitDress.chevrons(t, StarlinerTrack.NAVY, StarlinerTrack.CYAN, [], EDGE - Track.ROAD_WIDTH * 0.5 + StarlinerTrack.SHOULDER + 0.9)
	var moon_rocks: Array[Transform3D] = []
	var mars_rocks: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 150:
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
	# The moon base along the start straight: modules, dishes, aerials.
	var start := StarlinerTrack._at(t, "start")
	var mods: Array[Transform3D] = []
	var dishes: Array[Transform3D] = []
	var aerials: Array[Transform3D] = []
	var k := 0
	for x in KitDress.beside(t, start - 70.0, start + 10.0, 16.0, StarlinerTrack.SHOULDER + 7.0):
		var p := x.origin - Vector3.UP * 0.6
		match k % 3:
			0: mods.append(Transform3D(x.basis.scaled(Vector3.ONE * 1.4), p))
			1: dishes.append(Transform3D(x.basis.scaled(Vector3.ONE * 1.2), p))
			_: aerials.append(Transform3D(Basis(), p))
		k += 1
	KitTools.place(t, "cargo_pod", mods, 320.0)
	KitTools.place(t, "dish", dishes, 360.0)
	KitTools.place(t, "antenna", aerials, 360.0)
	# Astronauts (white and orange) cheering behind the base's rail.
	var suits := [Color(0.95, 0.95, 0.97), Color(1.0, 0.6, 0.2), Color(0.9, 0.92, 1.0)]
	KitDress.crowd(t, KitDress.beside(t, start - 64.0, start - 6.0, 3.0, StarlinerTrack.SHOULDER + 3.0, [1.0]), suits, 1)
	KitDress.crowd(t, KitDress.beside(t, start + 4.0, start + 40.0, 3.0, StarlinerTrack.SHOULDER + 3.0, [1.0]), suits, 1)
	# Dust devils roaming the red planet, away from the road.
	var mx := float(StarlinerTrack.MARS["x"])
	var mz := float(StarlinerTrack.MARS["z"])
	for j in 3:
		var loop := PackedVector3Array()
		var c := Vector2(mx + [-150.0, 160.0, 40.0][j], mz + [40.0, -60.0, 170.0][j])
		for n in 6:
			var a := TAU * n / 6.0
			var q := c + Vector2(cos(a), sin(a)) * 45.0
			loop.append(Vector3(q.x, StarlinerTrack.ground(q, "mars") - 0.5, q.y))
		KitDress.mover(t, "dust_devil", loop, 6.0, 1, {"size": 1.4, "far": 600.0})


## Space: stars all round, a far sun, and a ringed giant in the distance.
static func _space(t: Track) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stars := SurfaceTool.new()
	stars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(150, 150, -330)
	for i in 1100:
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
	ball.radial_segments = 40
	ball.rings = 20
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
