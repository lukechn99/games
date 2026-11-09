class_name RoadJunction
extends RefCounted
## A junction is the polygon union of the two real road footprints. The old
## widened strip could not represent a fork whose rows were not collinear.
## Triangulate that union once for BOTH drawing and collision.

static func ranges(t: Track) -> Array[Vector2]:
	var br: Dictionary = t.branches[FrostTrack.detour_branch(t)]
	var lake := FrostTrack.lake_span(t)
	return [Vector2(floorf(float(br["from"]) / 2.0) * 2.0 - 10.0, floorf(minf(float(br["from"]) + 90.0, lake.x - 4.0) / 2.0) * 2.0),
		Vector2(ceilf(maxf(float(br["to"]) - 90.0, lake.y + 8.0) / 2.0) * 2.0, ceilf(float(br["to"]) / 2.0) * 2.0 + 10.0)]


static func contains(zones: Array[Vector2], d: float) -> bool:
	for z in zones:
		if d >= z.x and d < z.y:
			return true
	return false


static func frames(t: Track, zone: Vector2, branch: bool) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var bi := FrostTrack.detour_branch(t)
	var d := zone.x
	while d <= zone.y + 0.01:
		out.append(t.branch_frame(d, bi) if branch else t.road_frame(d))
		d += 2.0
	return out


static func footprint(rows: Array[Transform3D]) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for f in rows:
		var p := f.origin - f.basis.x * Track.ROAD_WIDTH * 0.5
		poly.append(Vector2(p.x, p.z).snapped(Vector2.ONE * 0.0001))
	for i in range(rows.size() - 1, -1, -1):
		var p := rows[i].origin + rows[i].basis.x * Track.ROAD_WIDTH * 0.5
		poly.append(Vector2(p.x, p.z).snapped(Vector2.ONE * 0.0001))
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	return poly


static func model(t: Track, zone: Vector2) -> Dictionary:
	var main := frames(t, zone, false)
	var branch := frames(t, zone, true)
	var polygons := Geometry2D.merge_polygons(footprint(main), footprint(branch))
	assert(polygons.size() == 1, "A road fork must be one connected polygon without holes")
	var poly: PackedVector2Array = polygons[0]
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	return {"polygon": poly, "indices": Geometry2D.triangulate_polygon(poly), "main": main, "branch": branch, "heights": {}}


static func height_at(p: Vector2, data: Dictionary) -> float:
	var cache: Dictionary = data["heights"]
	if cache.has(p):
		return cache[p]
	var best := INF
	var height := 0.0
	for key in ["main", "branch"]:
		var rows: Array[Transform3D] = data[key]
		for i in range(rows.size() - 1):
			var a := Vector2(rows[i].origin.x, rows[i].origin.z)
			var b := Vector2(rows[i + 1].origin.x, rows[i + 1].origin.z)
			var u := clampf((p - a).dot(b - a) / maxf(a.distance_squared_to(b), 0.00001), 0.0, 1.0)
			var distance := p.distance_squared_to(a.lerp(b, u))
			if distance < best:
				best = distance
				height = lerpf(rows[i].origin.y, rows[i + 1].origin.y, u)
	cache[p] = height
	return height


static func point(p: Vector2, data: Dictionary, lift := 0.04) -> Vector3:
	return Vector3(p.x, height_at(p, data) + lift, p.y)


static func build(t: Track, zones: Array[Vector2], groups: Dictionary) -> void:
	var road := t._group(groups, "asphalt#junction")
	var banks := t._group(groups, "grass")
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zone in zones:
		var data := model(t, zone)
		var poly: PackedVector2Array = data["polygon"]
		var indices: PackedInt32Array = data["indices"]
		assert(not indices.is_empty(), "Road junction triangulation failed")
		for i in range(0, indices.size(), 3):
			_triangle(road, poly[indices[i]], poly[indices[i + 1]], poly[indices[i + 2]], data)
		var outward: Array[Vector2] = []
		for i in poly.size():
			var prev := (poly[i] - poly[(i - 1 + poly.size()) % poly.size()]).normalized()
			var next := (poly[(i + 1) % poly.size()] - poly[i]).normalized()
			var n0 := Vector2(prev.y, -prev.x)
			var n1 := Vector2(next.y, -next.x)
			var bisector := (n0 + n1).normalized()
			outward.append(bisector / maxf(0.5, bisector.dot(n1)))
		for i in poly.size():
			var j := (i + 1) % poly.size()
			if _cut(poly[i], poly[j], data):
				continue   # no kerb or stop-line across a continuing road
			var a := point(poly[i], data)
			var b := point(poly[j], data)
			var ao := a + Vector3(outward[i].x, 0, outward[i].y) * 1.1
			var bo := b + Vector3(outward[j].x, 0, outward[j].y) * 1.1
			var color := Color(0.2, 0.45, 0.92) if i % 2 == 0 else Color(0.97, 0.97, 0.97)
			t._kerb(road, a, ao, b, bo, color, 0.0, 1.0, true, false)
			# Close the graded road down to the snow rather than leaving an
			# exposed/floating edge in the aerial and oblique views.
			var height := maxf(ao.y, bo.y) - t.ground_y
			if height > 0.08:
				var ga := ao + Vector3(outward[i].x, 0, outward[i].y) * (height * Track.SLOPE + 1.0)
				var gb := bo + Vector3(outward[j].x, 0, outward[j].y) * (height * Track.SLOPE + 1.0)
				ga.y = t.ground_y - 0.02
				gb.y = t.ground_y - 0.02
				for v in [ao, ga, gb, ao, gb, bo]:
					banks.set_color(Parts.surface("grass")["color"])
					banks.add_vertex(v)
			# Paint follows the actual polygon boundary, never a stretched UV.
			var p0 := point(poly[i] - outward[i] * 0.4, data, 0.08)
			var p1 := point(poly[i] - outward[i] * 0.75, data, 0.08)
			var p2 := point(poly[j] - outward[j] * 0.75, data, 0.08)
			var p3 := point(poly[j] - outward[j] * 0.4, data, 0.08)
			for v in [p0, p1, p2, p0, p2, p3]:
				paint.add_vertex(v)
		# Centre dashes follow the actual driving paths through the fork.
		for key in ["main", "branch"]:
			var rows: Array[Transform3D] = data[key]
			for i in range(rows.size() - 1):
				if fposmod(zone.x + i * 2.0, 10.0) >= 3.8:
					continue
				if key == "branch" and rows[i].origin.distance_to((data["main"] as Array[Transform3D])[i].origin) < 5.0:
					continue
				var a := rows[i]
				var b := rows[i + 1]
				for v in [a.origin - a.basis.x * 0.15, b.origin + b.basis.x * 0.15, a.origin + a.basis.x * 0.15,
						a.origin - a.basis.x * 0.15, b.origin - b.basis.x * 0.15, b.origin + b.basis.x * 0.15]:
					paint.add_vertex(point(Vector2(v.x, v.z), data, 0.08))
	paint.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = paint.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.92, 0.88)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(mi)


static func _cut(a: Vector2, b: Vector2, data: Dictionary) -> bool:
	for key in ["main", "branch"]:
		var rows: Array[Transform3D] = data[key]
		for f: Transform3D in [rows[0], rows[rows.size() - 1]]:
			var pa := Vector3(a.x, f.origin.y, a.y) - f.origin
			var pb := Vector3(b.x, f.origin.y, b.y) - f.origin
			if absf(pa.dot(f.basis.z)) < 0.02 and absf(pb.dot(f.basis.z)) < 0.02:
				return true
	return false


static func _triangle(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, data: Dictionary, depth := 0) -> void:
	# Keep the graded junction close to the source road's height profile.
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	if depth < 16 and maxf(ab, maxf(bc, ca)) > 8.0:
		if ab >= bc and ab >= ca:
			var mid := a.lerp(b, 0.5)
			_triangle(st, a, mid, c, data, depth + 1)
			_triangle(st, mid, b, c, data, depth + 1)
		elif bc >= ca:
			var mid := b.lerp(c, 0.5)
			_triangle(st, a, b, mid, data, depth + 1)
			_triangle(st, a, mid, c, data, depth + 1)
		else:
			var mid := c.lerp(a, 0.5)
			_triangle(st, a, b, mid, data, depth + 1)
			_triangle(st, mid, b, c, data, depth + 1)
		return
	for p in [a, b, c]:
		st.set_color(Parts.surface("asphalt")["color"])
		st.set_uv(p / 14.0)
		st.add_vertex(point(p, data))
