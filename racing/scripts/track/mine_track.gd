class_name MineTrack
extends RefCounted
## Mining Mountain (design doc 8.3, from the user's sketch in
## docs/racing/mine-shaft-sketch.png).
##
## - The main road runs round the outside of a mountain on a ledge: the
##   mountain rises on the left, a cliff drops away on the right.
## - Through the mountain: an old mine tunnel, held up by timber frames and
##   lit by flickering torches, with coal piles to dodge and a deep cavern in
##   the middle crossed on a narrow mine-cart trestle. Fall off and you're put
##   back on the road. It's shorter than going round.
## - The rope bridge: a shortcut straight across a gap on the other side. It
##   sways in the wind, so it's easy to fall off.

## The sketch's outline, in sketch pixels, in driving order (the cliff is on
## the right). 1 pixel is SCALE metres.
const SKETCH := [
	Vector2(430, 1487), Vector2(560, 1465), Vector2(650, 1415), Vector2(700, 1350), Vector2(740, 1260),
	Vector2(745, 1160), Vector2(700, 1080), Vector2(630, 1010), Vector2(625, 940), Vector2(650, 860),
	Vector2(690, 760), Vector2(705, 660), Vector2(700, 580), Vector2(640, 530), Vector2(530, 522),
	Vector2(450, 550), Vector2(400, 612), Vector2(300, 645), Vector2(240, 700), Vector2(205, 780),
	Vector2(210, 860), Vector2(240, 930), Vector2(262, 1000), Vector2(262, 1080), Vector2(215, 1140),
	Vector2(170, 1220), Vector2(165, 1310), Vector2(210, 1400), Vector2(300, 1470),
]
## The tunnel (blue) and the rope bridge (red), in sketch pixels.
const TUNNEL := [Vector2(490, 1460), Vector2(565, 1420), Vector2(612, 1340), Vector2(640, 1220), Vector2(645, 1130), Vector2(628, 1015)]
const BRIDGE := [Vector2(206, 790), Vector2(203, 1160)]
const SCALE := 0.5
const CAVERN := [0.42, 0.6]      # the cavern, as a fraction of the tunnel
const COAL := [0.2, 0.3, 0.7, 0.8]

const ROCK := Color(0.55, 0.47, 0.4)
const ROCK_DARK := Color(0.36, 0.3, 0.27)
const WOOD := Color(0.6, 0.4, 0.24)
const SNOW := Color(0.95, 0.96, 1.0)


static func world(p: Vector2, y := 0.0) -> Vector3:
	return Vector3((p.x - 450.0) * SCALE, y, (p.y - 1000.0) * SCALE)


static func configure(t: Track) -> void:
	var pts: Array = []
	var n := SKETCH.size()
	for i in n:
		# The ledge climbs to the far side of the mountain and back down.
		var u := float(i) / n
		var y := 14.0 + 9.0 * (1.0 - cos(u * TAU)) * 0.5 + 2.0 * sin(u * TAU * 3.0)
		pts.append(world(SKETCH[i], y))
	t.points = pts
	t.surface_zones = [
		{"from": 0.43, "to": 0.5, "surface": "dirt"},
		{"from": 0.06, "to": 0.075, "surface": "boost"},
	]
	t.rail_zones = []
	t.trees_hit_radius = 0.0


## Work out which side the cliff is on and where the two shortcuts run.
static func plan(t: Track) -> void:
	var centroid := Vector3.ZERO
	for s in t._samples:
		centroid += s.origin
	centroid /= maxf(1.0, t._samples.size())
	var mid := t.transform_at(t.length * 0.25)
	t.ledge_out = 1.0 if (mid.origin + mid.basis.x * 10.0).distance_to(centroid) > (mid.origin - mid.basis.x * 10.0).distance_to(centroid) else -1.0
	_add_chord(t, TUNNEL, "tunnel")
	_add_chord(t, BRIDGE, "bridge")


## A shortcut that leaves the main road and rejoins it along a polyline: for
## each metre of the main road between the two ends, the sideways distance to
## where the road's cross-line meets the polyline.
static func _add_chord(t: Track, sketch: Array, kind: String) -> void:
	var line: Array[Vector2] = []
	for p in sketch:
		var w := world(p)
		line.append(Vector2(w.x, w.z))
	var a := t.offset_of(world(sketch[0]))
	var b := t.offset_of(world(sketch[sketch.size() - 1]))
	var from := minf(a, b)
	var to := maxf(a, b)
	var shift := PackedFloat32Array()
	var d := from
	while d <= to + 1.0:
		var f := t.transform_at(d)
		var o := Vector2(f.origin.x, f.origin.z)
		var side := Vector2(f.basis.x.x, f.basis.x.z).normalized()
		var best := 0.0
		var found := false
		for k in line.size() - 1:
			var hit: Variant = Geometry2D.line_intersects_line(o, side, line[k], line[k + 1] - line[k])
			if hit == null:
				continue
			var h: Vector2 = hit
			var u := (h - line[k]).dot(line[k + 1] - line[k]) / (line[k + 1] - line[k]).length_squared()
			if u < -0.01 or u > 1.01:
				continue
			var s := (h - o).dot(side)
			if not found or absf(s) < absf(best):
				best = s
				found = true
		# Ease in and out at the ends, where the routes meet.
		var e := clampf(minf(d - from, to - d) / 25.0, 0.0, 1.0)
		shift.append(best * smoothstep(0.0, 1.0, e))
		d += 1.0
	t.add_branch(from, to, shift, kind)


static func _branch_index(t: Track, kind: String) -> int:
	for i in t.branches.size():
		if t.branches[i]["kind"] == kind:
			return i
	return -1


static func _u(t: Track, i: int, d: float) -> float:
	var b: Dictionary = t.branches[i]
	return (d - float(b["from"])) / (float(b["to"]) - float(b["from"]))


## The bridge and the cavern trestle are built separately.
static func has_road(t: Track, i: int, d: float) -> bool:
	var kind: String = t.branches[i]["kind"]
	if kind == "bridge":
		return false
	var u := _u(t, i, d)
	return not (u > CAVERN[0] and u < CAVERN[1])


static func crate_frames(t: Track) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var ti := _branch_index(t, "tunnel")
	if ti >= 0:
		var b: Dictionary = t.branches[ti]
		for u in [0.33, 0.68]:
			out.append(t.branch_frame(lerpf(b["from"], b["to"], u), ti))
	# And a row on the main road, on the far side of the mountain.
	out.append(t.transform_at(t.length * 0.55))
	return out


static func build(t: Track) -> void:
	_mountain(t)
	var ti := _branch_index(t, "tunnel")
	if ti >= 0:
		_tunnel(t, ti)
	var bi := _branch_index(t, "bridge")
	if bi >= 0:
		var bridge := SwayBridge.new()
		t.add_child(bridge)
		bridge.build(t, bi)
	_fences(t)
	_props(t)


# --- The mountain ------------------------------------------------------------

## A height-field mountain filling the inside of the loop: a rocky shoulder
## level with the road, then steep slopes up to a snowy peak. Over the
## tunnel it stays high (the tunnel runs underneath); where the tunnel comes
## out it's cut down to the shoulder, which leaves a rock face over the
## tunnel mouth.
static func _mountain(t: Track) -> void:
	var poly := PackedVector2Array()
	var ys := PackedFloat32Array()
	for s in t._samples:
		poly.append(Vector2(s.origin.x, s.origin.z))
		ys.append(s.origin.y)
	var route: Array[Vector3] = []
	var covered: Array[bool] = []   # under the tunnel's own roof here
	var ti := _branch_index(t, "tunnel")
	if ti >= 0:
		var b: Dictionary = t.branches[ti]
		var d: float = b["from"]
		while d <= b["to"]:
			route.append(t.branch_frame(d, ti).origin)
			covered.append(absf(t.branch_offset(d, ti)) >= 30.0)
			d += 3.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var step := 5.0
	var nx := int((hi.x - lo.x) / step) + 2
	var nz := int((hi.y - lo.y) / step) + 2
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.03
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var inside := PackedByteArray()
	inside.resize(nx * nz)
	var roof := PackedByteArray()   # raised over the tunnel: the tunnel shows through here
	roof.resize(nx * nz)
	var half := Track.ROAD_WIDTH * 0.5
	for iz in nz:
		for ix in nx:
			var p := lo + Vector2(ix, iz) * step
			var k := iz * nx + ix
			var is_in := Geometry2D.is_point_in_polygon(p, poly)
			inside[k] = 1 if is_in else 0
			# Nearest bit of road, and how high it is there.
			var best := INF
			var y_r := 0.0
			for j in range(0, poly.size(), 2):
				var dd := p.distance_squared_to(poly[j])
				if dd < best:
					best = dd
					y_r = ys[j]
			var dist := sqrt(best)
			var h := y_r - 0.35
			if dist > half + 12.0:
				h += minf((dist - half - 12.0) * 1.5, 70.0) + noise.get_noise_2d(p.x, p.y) * 6.0
			if dist < half + 1.5:
				h = y_r - 0.8   # under the road edge
			# The tunnel: high above it inside, cut down where it comes out.
			# (Only where the tunnel has its own roof: outside that, an open cut,
			# so there's never a hole in the mountain without a tunnel in it.)
			for ri in route.size():
				var r := route[ri]
				var dr := Vector2(r.x, r.z).distance_to(p)
				if dr < 9.0:
					if h > r.y + 6.5 and covered[ri]:
						h = maxf(h, r.y + 10.0)
						roof[k] = 1
					else:
						h = minf(h, r.y - 0.35)
			heights[k] = h
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz - 1:
		for ix in nx - 1:
			var ks := [iz * nx + ix, iz * nx + ix + 1, (iz + 1) * nx + ix + 1, (iz + 1) * nx + ix]
			var all_in := true
			for kk in ks:
				if inside[kk] == 0 or roof[kk] == 1:
					all_in = false
			if not all_in:
				continue
			var v := []
			for kk in ks:
				var gx: int = kk % nx
				var gz: int = kk / nx
				v.append(Vector3(lo.x + gx * step, heights[kk], lo.y + gz * step))
			for tri in [[v[0], v[1], v[2]], [v[0], v[2], v[3]]]:
				for q in tri:
					st.set_color(_mountain_color(q.y, noise.get_noise_2d(q.x * 3.0, q.z * 3.0)))
					st.add_vertex(q)
	st.generate_normals()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.set_meta("surface", "dirt")
	body.set_meta("floor", true)
	t.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "rock", 6.0)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	# Keep the valley trees off the mountain.
	t.no_scenery = poly


static func _mountain_color(y: float, n: float) -> Color:
	var c := ROCK.lerp(ROCK_DARK, clampf(0.5 + n * 0.6, 0.0, 1.0) * 0.5)
	# Pale bands of strata, then snow near the top.
	if int(y / 6.0) % 3 == 0:
		c = c.lightened(0.08)
	if y > 78.0 + n * 6.0:
		c = SNOW
	return c


# --- The mine tunnel ---------------------------------------------------------

static func _tunnel(t: Track, i: int) -> void:
	var b: Dictionary = t.branches[i]
	var from: float = b["from"]
	var to: float = b["to"]
	# Only where the route is well inside the mountain (it runs through an
	# open cut on the shoulder before that).
	var d0 := to
	var d1 := from
	var dd := from
	while dd <= to:
		if absf(t.branch_offset(dd, i)) >= 28.0:
			d0 = minf(d0, dd)
			d1 = maxf(d1, dd)
		dd += 1.0
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	var timber := SurfaceTool.new()
	timber.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gutter := SurfaceTool.new()
	gutter.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arc := 12
	var prev: Array = []
	var d := d0
	var n := 0
	while d <= d1:
		var f := t.branch_frame(d, i)
		var u := _u(t, i, d)
		var cav := u > CAVERN[0] - 0.03 and u < CAVERN[1] + 0.03
		# In the cavern the roof lifts far away and the floor drops into darkness.
		var ri := Track.ROAD_WIDTH * 0.5 + (16.0 if cav else 3.2)
		var tall := 0.9 if cav else 0.75
		var ring := []
		for k in arc + 3:
			var p: Vector3
			if k == 0 or k == arc + 2:
				var sx := 1.0 if k == 0 else -1.0
				p = f.origin + f.basis.x * sx * ri - Vector3.UP * (40.0 if cav else 3.0)
			else:
				var a := PI * float(k - 1) / arc
				var lump := 0.4 * sin(d * 0.5 + k * 1.9) * (3.0 if cav else 1.0)
				p = f.origin + (f.basis.x * cos(a) + Vector3.UP * sin(a) * tall) * (ri + lump)
			ring.append(p)
		if not prev.is_empty():
			for k in ring.size() - 1:
				var c := ROCK_DARK.darkened(0.25 + 0.1 * float(k % 2))
				SetPieces._quad(shell, prev[k], ring[k], ring[k + 1], prev[k + 1], c)
		prev = ring
		# A floor out to the walls each side, so there's no gutter to drop into.
		if not cav:
			var fb := t.branch_frame(minf(d + 2.0, d1), i)
			for sx: float in [-1.0, 1.0]:
				var e0 := f.origin + f.basis.x * sx * (Track.ROAD_WIDTH * 0.5 + 0.8) - Vector3.UP * 0.02
				var w0 := f.origin + f.basis.x * sx * (ri + 0.6) - Vector3.UP * 0.02
				var e1 := fb.origin + fb.basis.x * sx * (Track.ROAD_WIDTH * 0.5 + 0.8) - Vector3.UP * 0.02
				var w1 := fb.origin + fb.basis.x * sx * (ri + 0.6) - Vector3.UP * 0.02
				SetPieces._quad(gutter, e0, w0, w1, e1, ROCK_DARK.darkened(0.15))
		# Timber frames: two posts and a beam across, every 6 m.
		if not cav and n % 3 == 0:
			var hw := Track.ROAD_WIDTH * 0.5 + 1.2
			var post_h := 4.3
			for s: float in [-1.0, 1.0]:
				SetPieces._box(timber, Transform3D(f.basis, f.origin + f.basis.x * s * hw + Vector3.UP * post_h * 0.5), Vector3(0.45, post_h, 0.45), WOOD)
			SetPieces._box(timber, Transform3D(f.basis, f.origin + Vector3.UP * post_h), Vector3(hw * 2.0 + 0.4, 0.5, 0.5), WOOD.darkened(0.1))
		d += 2.0
		n += 1
	# Seen from inside, and from outside where it shows through the mountain.
	var sm: StandardMaterial3D = Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "rock", 4.0).duplicate()
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	SetPieces._commit(t, shell, sm, true, "rock")
	SetPieces._commit(t, timber, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "wood", 1.5))
	var gm: StandardMaterial3D = Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "dirt", 2.0).duplicate()
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gi := SetPieces._commit(t, gutter, gm, true, "dirt")
	gi.get_parent().set_meta("floor", true)
	_torches(t, i, d0, d1)
	_cavern(t, i)
	_coal(t, i)


## Torches on the walls, with real flickering light from some of them.
static func _torches(t: Track, i: int, d0: float, d1: float) -> void:
	var flames := SurfaceTool.new()
	flames.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sticks := SurfaceTool.new()
	sticks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := d0 + 6.0
	var k := 0
	while d < d1 - 6.0:
		var u := _u(t, i, d)
		if u > CAVERN[0] - 0.04 and u < CAVERN[1] + 0.04:
			d += 12.0
			continue
		var f := t.branch_frame(d, i)
		var s := 1.0 if k % 2 == 0 else -1.0
		var p := f.origin + f.basis.x * s * (Track.ROAD_WIDTH * 0.5 + 1.2) + Vector3.UP * 3.2
		SetPieces._box(sticks, Transform3D(f.basis.rotated(f.basis.z, -s * 0.3), p), Vector3(0.14, 0.7, 0.14), WOOD.darkened(0.2))
		SetPieces._box(flames, Transform3D(f.basis, p + Vector3.UP * 0.5), Vector3(0.28, 0.42, 0.28), Color(1.0, 0.6, 0.15))
		if k % 2 == 0:
			var light := FlickerLight.new()
			light.light_color = Color(1.0, 0.62, 0.3)
			light.light_energy = 2.6
			light.omni_range = 16.0
			light.position = p + Vector3.UP * 0.6 - f.basis.x * s * 0.6
			t.add_child(light)
		d += 12.0
		k += 1
	SetPieces._commit(t, sticks, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE))
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/flame.gdshader")
	SetPieces._commit(t, flames, fm)


## The cavern: a deep dark pit crossed on a narrow mine-cart trestle with
## rails. Fall off and you're out of bounds (put back on the road).
static func _cavern(t: Track, i: int) -> void:
	var b: Dictionary = t.branches[i]
	var from: float = b["from"]
	var to: float = b["to"]
	var da := lerpf(from, to, CAVERN[0])
	var db := lerpf(from, to, CAVERN[1])
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var legs := SurfaceTool.new()
	legs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 3.2
	var d := da
	var n := 0
	while d < db:
		var fa := t.branch_frame(d, i)
		var fb := t.branch_frame(minf(d + 1.5, db), i)
		var lift := Vector3.UP * 0.04
		SetPieces._quad(deck, fa.origin - fa.basis.x * hw + lift, fb.origin - fb.basis.x * hw + lift, fb.origin + fb.basis.x * hw + lift, fa.origin + fa.basis.x * hw + lift, WOOD if n % 2 == 0 else WOOD.darkened(0.12))
		# Sleepers and two steel rails.
		SetPieces._box(rails, Transform3D(fa.basis, fa.origin + Vector3.UP * 0.1), Vector3(hw * 1.6, 0.12, 0.3), WOOD.darkened(0.3))
		for s: float in [-1.0, 1.0]:
			SetPieces._box(rails, Transform3D(fa.basis, fa.origin + fa.basis.x * s * 0.9 + Vector3.UP * 0.2 - fa.basis.z * 0.75), Vector3(0.12, 0.1, 1.55), Color(0.7, 0.72, 0.76))
		# Trestle legs going down into the dark.
		if n % 4 == 0:
			for s: float in [-1.0, 1.0]:
				SetPieces._box(legs, Transform3D(fa.basis.rotated(fa.basis.z, s * 0.12), fa.origin + fa.basis.x * s * (hw + 1.0) - Vector3.UP * 12.0), Vector3(0.4, 24.0, 0.4), WOOD.darkened(0.25))
			SetPieces._box(legs, Transform3D(fa.basis, fa.origin - Vector3.UP * 6.0), Vector3(hw * 2.4, 0.4, 0.4), WOOD.darkened(0.3))
		d += 1.5
		n += 1
	# Rock faces at each end of the pit, from the tunnel floor down into the
	# dark, so you never see daylight under the far end.
	var ends := SurfaceTool.new()
	ends.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in [[da + 0.3, 1.0], [db - 0.3, -1.0]]:
		var f := t.branch_frame(e[0], i)
		var w := Track.ROAD_WIDTH * 0.5 + 18.0
		var top := f.origin - Vector3.UP * 0.6
		var bottom := Vector3(f.origin.x, 0.0, f.origin.z)
		var x := f.basis.x * w
		SetPieces._quad(ends, top - x, top + x, bottom + x, bottom - x, ROCK_DARK.darkened(0.45))
	var em: StandardMaterial3D = Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "rock", 4.0).duplicate()
	em.cull_mode = BaseMaterial3D.CULL_DISABLED
	SetPieces._commit(t, ends, em)
	var dm := SetPieces._commit(t, deck, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "wood", 1.5), true, "asphalt")
	dm.get_parent().set_meta("floor", true)
	SetPieces._commit(t, rails, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.METAL))
	SetPieces._commit(t, legs, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE))
	# The pit's floor, far below, in darkness.
	var mid := t.branch_frame((da + db) * 0.5, i)
	var pit := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, (db - da) + 90)
	pit.mesh = plane
	pit.transform = Transform3D(mid.basis, Vector3(mid.origin.x, 0.3, mid.origin.z))
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.02, 0.01, 0.03)
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pit.material_override = pm
	t.add_child(pit)
	# A few lanterns hanging over the trestle, and a glow far below.
	for k in 3:
		var f := t.branch_frame(lerpf(da, db, (k + 0.5) / 3.0), i)
		var l := FlickerLight.new()
		l.light_color = Color(1.0, 0.7, 0.35)
		l.light_energy = 2.4
		l.omni_range = 16.0
		l.position = f.origin + Vector3.UP * 5.0
		t.add_child(l)


## Coal piles on the tunnel road: driving into one slows you and splatters
## coal dust over your screen, which blows away.
static func _coal(t: Track, i: int) -> void:
	var b: Dictionary = t.branches[i]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spots: Array[Vector3] = []
	var k := 0
	for u in COAL:
		var f := t.branch_frame(lerpf(b["from"], b["to"], u), i)
		var p := f.origin + f.basis.x * (2.8 if k % 2 == 0 else -2.8)
		SetPieces._boulder(st, p - Vector3.UP * 0.1, 1.5, 0.9, 40 + k)
		spots.append(p)
		k += 1
	var coal := StandardMaterial3D.new()
	coal.vertex_color_use_as_albedo = false
	coal.albedo_color = Color(0.07, 0.065, 0.07)
	coal.roughness = 0.55
	coal.metallic_specular = 0.45
	SetPieces._commit(t, st, coal)
	var piles := CoalPiles.new()
	piles.spots = spots
	t.add_child(piles)


# --- Railings and props --------------------------------------------------------

## Wooden railings on the cliff side through the tight corners (the straights
## are left open, for drama).
static func _fences(t: Track) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.set_meta("surface", "rail")
	t.add_child(body)
	var d := 0.0
	while d < t.length:
		if absf(t.bank_at(d)) > deg_to_rad(4.0) and t.branch_at(d) < 0:
			var f := t.road_frame(d)
			var p := f.origin + f.basis.x * t.ledge_out * (Track.ROAD_WIDTH * 0.5 + 1.4)
			SetPieces._box(st, Transform3D(f.basis, p + Vector3.UP * 0.5), Vector3(0.25, 1.0, 0.25), WOOD)
			SetPieces._box(st, Transform3D(f.basis, p + Vector3.UP * 0.85 + f.basis.z * 2.0), Vector3(0.14, 0.18, 4.0), WOOD.lightened(0.1))
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.4, 1.1, 4.1)
			col.shape = box
			col.transform = Transform3D(f.basis, p + Vector3.UP * 0.55 + f.basis.z * 2.0)
			body.add_child(col)
		d += 4.0
	SetPieces._commit(t, st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "wood", 1.5))


## Mine carts and lanterns by the start, on the mountain's shoulder.
static func _props(t: Track) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var f := t.transform_at(t.length - 20.0 - k * 7.0)
		var p := f.origin - f.basis.x * t.ledge_out * (Track.ROAD_WIDTH * 0.5 + 6.0)
		SetPieces._box(st, Transform3D(f.basis, p + Vector3.UP * 0.9), Vector3(1.8, 1.0, 2.6), Color(0.5, 0.36, 0.26))
		SetPieces._box(st, Transform3D(f.basis, p + Vector3.UP * 1.45), Vector3(1.6, 0.3, 2.4), Color(0.12, 0.11, 0.12))  # coal
		for s: float in [-1.0, 1.0]:
			for e: float in [-0.8, 0.8]:
				SetPieces._box(st, Transform3D(f.basis, p + f.basis.x * s * 0.95 + f.basis.z * e + Vector3.UP * 0.35), Vector3(0.2, 0.6, 0.6), Color(0.3, 0.3, 0.33))
	SetPieces._commit(t, st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))
