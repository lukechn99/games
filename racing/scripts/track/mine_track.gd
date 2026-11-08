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
## The valley floor, far below the ledge (the ledge is about two thirds of
## the way up the mountain).
const FLOOR := -32.0
const SCALE := 0.64   # (0.5 at first; stretched for a longer run through the tunnel)
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
		# Level round the start, so karts wait on the grid without rolling.
		if i <= 1 or i >= n - 3:
			y = 14.0
		pts.append(world(SKETCH[i], y))
	t.points = pts
	t.surface_zones = [
		{"from": 0.43, "to": 0.5, "surface": "dirt"},
		{"from": 0.06, "to": 0.075, "surface": "boost"},
	]
	t.rail_zones = []
	t.ground_y = FLOOR
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
		t.moving_crates = bridge.crate_spots()
		t.bridge = bridge
		_fork(t, bi)
	_outer_slope(t, bi)
	_fences(t)
	_props(t)
	SetPieces._clouds(t)


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
	var cav_at: Array[bool] = []    # in the cavern, where the shell is far wider
	var ti := _branch_index(t, "tunnel")
	if ti >= 0:
		var b: Dictionary = t.branches[ti]
		var d: float = b["from"]
		while d <= b["to"]:
			route.append(t.branch_frame(d, ti).origin)
			covered.append(absf(t.branch_offset(d, ti)) >= 30.0)
			var u := _u(t, ti, d)
			cav_at.append(u > CAVERN[0] - 0.03 and u < CAVERN[1] + 0.03)
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
	var near := PackedFloat32Array()  # 1 on the flat run-off beside the road
	near.resize(nx * nz)
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
			near[k] = clampf((half + 14.0 - dist) / 4.0, 0.0, 1.0)
			var h := y_r - 0.35
			if dist > half + 12.0:
				# Steep slopes, easing into a rounded summit instead of a flat
				# snowfield.
				var rise := (dist - half - 12.0) * 1.5
				h += (rise if rise < 55.0 else 55.0 + (rise - 55.0) * 0.35) + noise.get_noise_2d(p.x, p.y) * 7.0
			if dist < half + 1.5:
				h = y_r - 0.8   # under the road edge
			# The tunnel: high above it inside, cut down where it comes out.
			# (Only where the tunnel has its own roof: outside that, an open cut,
			# so there's never a hole in the mountain without a tunnel in it.)
			# Where it's buried, the mountain stays whole and arches over the
			# tunnel's rock shell (much wider over the cavern), so from outside
			# it's solid all the way over.
			var cut := INF
			var arch := -INF
			for ri in route.size():
				var r := route[ri]
				var dr := Vector2(r.x, r.z).distance_to(p)
				if dr > 26.0:
					continue
				var shell_r := Track.ROAD_WIDTH * 0.5 + (16.0 if cav_at[ri] else 3.2) + 1.5
				var tall := 0.9 if cav_at[ri] else 0.75
				if dr < 9.0 and not (covered[ri] and h > r.y + 6.5):
					cut = minf(cut, r.y - 0.35)
				elif covered[ri] and dr < shell_r and h > r.y + 6.5:
					if dr < 9.0:
						roof[k] = 1
					arch = maxf(arch, r.y + tall * sqrt(maxf(shell_r * shell_r - dr * dr, 0.0)) + 3.0)
			if cut < INF:
				h = minf(h, cut)
			elif arch > -INF and (dist > half + 12.0 or roof[k] == 1):
				h = maxf(h, arch)
			heights[k] = h
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Right over the tunnel: the same rock surface, but only to look at (as
	# solid ground it upset the karts below), so the mountain is whole from
	# the air even where the tunnel's shell is too far away to be drawn.
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var capped := false
	for iz in nz - 1:
		for ix in nx - 1:
			var ks := [iz * nx + ix, iz * nx + ix + 1, (iz + 1) * nx + ix + 1, (iz + 1) * nx + ix]
			var all_in := true
			var over := false
			for kk in ks:
				if inside[kk] == 0:
					all_in = false
				if roof[kk] == 1:
					over = true
			if not all_in:
				continue
			var into := cap if over else st
			capped = capped or over
			var v := []
			var nr := []
			for kk in ks:
				var gx: int = kk % nx
				var gz: int = kk / nx
				v.append(Vector3(lo.x + gx * step, heights[kk], lo.y + gz * step))
				nr.append(near[kk])
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for qi in tri:
					var q: Vector3 = v[qi]
					var c := _mountain_color(q.y, noise.get_noise_2d(q.x * 3.0, q.z * 3.0))
					c.a = nr[qi]   # the rock shader turns this into gravel run-off
					into.set_color(c)
					into.add_vertex(q)
	if capped:
		cap.generate_normals()
		var cmi := MeshInstance3D.new()
		cmi.mesh = cap.commit()
		cmi.material_override = rock_material()
		t.add_child(cmi)
	st.generate_normals()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.set_meta("surface", "dirt")
	body.set_meta("floor", true)
	t.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = rock_material()
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	# Keep the valley trees off the mountain.
	t.no_scenery = poly


## Layered sandstone with grassy ledges and a snowy top (shaders/rock.gdshader).
static func rock_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rock.gdshader")
	m.set_shader_parameter("detail", load(Palette.TEX_DIR + "rock.png"))
	# Snow only on the very top, and a soft blue-white so it isn't glare.
	m.set_shader_parameter("snow_line", 100.0)
	m.set_shader_parameter("snow", Color(0.86, 0.9, 0.97))
	return m


static func _mountain_color(y: float, n: float) -> Color:
	var c := ROCK.lerp(ROCK_DARK, clampf(0.5 + n * 0.6, 0.0, 1.0) * 0.5)
	# Pale bands of strata, then snow near the top.
	if int(y / 6.0) % 3 == 0:
		c = c.lightened(0.08)
	if y > 78.0 + n * 6.0:
		c = SNOW
	return c


# --- The mine tunnel ---------------------------------------------------------

## A teardrop of flame: a narrow base, a fat middle and a point, with UV.y
## running 0..1 up it so the flame shader can lick the top about.
static func _flame(st: SurfaceTool, base: Vector3) -> void:
	var rings := [[0.0, 0.09], [0.22, 0.16], [0.45, 0.1], [0.75, 0.0]]
	var sides := 6
	for r in rings.size() - 1:
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var pts := []
			for rr in [r, r + 1]:
				for a in [a0, a1]:
					var h: float = rings[rr][0]
					var w: float = rings[rr][1]
					pts.append([base + Vector3(cos(a) * w, h, sin(a) * w), h / 0.75])
			for idx in [0, 2, 1, 1, 2, 3]:
				st.set_uv(Vector2(0.0, pts[idx][1]))
				st.set_color(Color.WHITE)
				st.add_vertex(pts[idx][0])


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
		# A floor out to the walls each side, so there's no gutter to drop
		# into (everywhere but over the cavern pit itself, including the
		# stretch either side of it where the walls already open out).
		if not (u > CAVERN[0] and u < CAVERN[1]):
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
	_collars(t, i, d0, d1)
	_torches(t, i, d0, d1)
	_cavern(t, i)
	_coal(t, i)


## A rock face round each tunnel mouth: a wide ring out from the tunnel's
## end down to below the ground, so you never see daylight round the edge
## of the tunnel or through the mountain beside the mouth.
static func _collars(t: Track, i: int, d0: float, d1: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arc := 12
	for d in [d0, d1]:
		var f := t.branch_frame(d, i)
		var ri := Track.ROAD_WIDTH * 0.5 + 3.2
		var inner := []
		var outer := []
		for k in arc + 1:
			var a := PI * float(k) / arc
			var dir := f.basis.x * cos(a) + Vector3.UP * sin(a) * 0.75
			var lump := 0.4 * sin(d * 0.5 + k * 1.9)
			inner.append(f.origin + dir * (ri + lump) - f.basis.z * 0.0)
			var o := f.origin + (f.basis.x * cos(a) * 1.0 + Vector3.UP * sin(a) * 0.9) * (ri + 16.0 + 3.0 * sin(k * 2.3))
			outer.append(o)
		# Down to the ground each side.
		for side in [0, arc]:
			var dn := Vector3.DOWN * 8.0
			SetPieces._quad(st, inner[side], outer[side], outer[side] + dn, inner[side] + dn, ROCK_DARK.darkened(0.1))
		for k in arc:
			SetPieces._quad(st, inner[k], outer[k], outer[k + 1], inner[k + 1], ROCK.lerp(ROCK_DARK, 0.4 + 0.2 * float(k % 2)))
	var m := rock_material()
	SetPieces._commit(t, st, m)
	# (Double-sided through the shader: rock.gdshader culls nothing.)


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
		_flame(flames, p + Vector3.UP * 0.32)
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
	for e in [[da, 1.0], [db, -1.0]]:
		var f := t.branch_frame(e[0], i)
		var w := Track.ROAD_WIDTH * 0.5 + 18.0
		# Right up to the road's underside: from lower down you could see
		# under the tunnel floor and out of the mountain.
		var top := f.origin - Vector3.UP * 0.03
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
	# Just the cavern's footprint (it's deep inside the mountain): any bigger
	# and it showed as a black sheet over the valley outside.
	plane.size = Vector2(Track.ROAD_WIDTH + 36.0, (db - da) + 2.0)
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
		# A heap of lumps rather than one blob: a low mound with chunks on it.
		SetPieces._boulder(st, p - Vector3.UP * 0.15, 1.5, 0.55, 40 + k)
		var rng := RandomNumberGenerator.new()
		rng.seed = 90 + k
		for j in 9:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.0, 1.3)
			var q := p + f.basis.x * cos(a) * r + f.basis.z * sin(a) * r
			q.y = p.y - 0.1 + (1.3 - r) * 0.35
			SetPieces._boulder(st, q, rng.randf_range(0.25, 0.45), rng.randf_range(0.25, 0.5), 200 + k * 20 + j)
		spots.append(p)
		k += 1
	var coal := StandardMaterial3D.new()
	coal.vertex_color_use_as_albedo = false
	coal.albedo_color = Color(0.09, 0.08, 0.075)
	coal.roughness = 0.45
	coal.metallic_specular = 0.25
	coal.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	# The sky can't be seen in here, so don't let it tint the coal blue.
	coal.disable_ambient_light = true
	coal.emission_enabled = true
	coal.emission = Color(0.035, 0.025, 0.02)
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


## Outside the ledge the mountain keeps going down: a slope falling away from
## the road's edge to the valley floor, rocky near the top and grassy lower
## down, instead of a sheer drop straight onto grass. Not under the rope
## bridge, which spans a real gap.
static func _outer_slope(t: Track, bi: int) -> void:
	# Outside the ledge the mountain keeps falling, as steep as the face
	# above: bare rock in rough steps all the way down to the valley floor
	# far below. Drive off and you tumble down it (and are put back).
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = 12
	noise.frequency = 0.06
	var edge := Track.ROAD_WIDTH * 0.5 + 1.0
	var xs := [0.0, 1.0, 2.5, 5.0, 8.0, 11.5, 15.5, 20.0, 25.0, 30.5, 36.5, 43.0, 50.0]
	var step := 4.0
	var rows := []
	var d := 0.0
	while d <= t.length + 0.1:
		var f := t.road_frame(fmod(d, t.length))
		var out := (f.basis.x * Vector3(1, 0, 1)).normalized() * t.ledge_out
		var e := f.origin + f.basis.x * t.ledge_out * edge
		var row := []
		for x: float in xs:
			var p := e + out * x
			# About 1.6 down for every 1 out, in rough ledges and bulges.
			var drop := x * 1.6 + noise.get_noise_2d(p.x, p.z) * minf(x * 0.35, 4.0)
			drop += floor(x / 6.0) * 0.8 * (0.5 + 0.5 * noise.get_noise_2d(p.z, p.x))
			var y := maxf(e.y - 0.25 - drop, FLOOR - 0.5)
			p += out * noise.get_noise_2d(p.x * 2.0, p.z * 2.0) * minf(x * 0.15, 2.5)
			row.append(Vector3(p.x, y, p.z))
		var gap := false
		if bi >= 0:
			var b: Dictionary = t.branches[bi]
			gap = d > float(b["from"]) + 8.0 and d < float(b["to"]) - 8.0
		rows.append([row, gap])
		d += step
	for r in rows.size() - 1:
		if rows[r][1] or rows[r + 1][1]:
			continue
		var ra: Array = rows[r][0]
		var rb: Array = rows[r + 1][0]
		for k in xs.size() - 1:
			var c := Color(0.62, 0.55, 0.47, 1.0 if k == 0 else 0.0)
			var quad := [ra[k], rb[k], rb[k + 1], ra[k], rb[k + 1], ra[k + 1]] if t.ledge_out > 0 else [ra[k], rb[k + 1], rb[k], ra[k], ra[k + 1], rb[k + 1]]
			for v in quad:
				rock.set_color(c)
				rock.add_vertex(v)
	rock.generate_normals()
	var mesh := rock.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = rock_material()
	var body := StaticBody3D.new()
	body.set_meta("surface", "dirt")
	t.add_child(body)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)


## Where the rope bridge leaves the ledge: a solid barrier along the split,
## so you can't drive off into the gap between, with a big sign at its nose
## pointing to each way.
static func _fork(t: Track, bi: int) -> void:
	var b: Dictionary = t.branches[bi]
	var nose := -1.0
	var d: float = b["from"]
	while d < float(b["to"]):
		if absf(t.branch_offset(d, bi)) >= Track.ROAD_WIDTH + 2.2:
			nose = d
			break
		d += 0.5
	if nose < 0.0:
		return
	var side := signf(t.branch_offset(nose, bi))   # which side the bridge is on
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.set_meta("surface", "rail")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0
	pm.bounce = 0.2
	body.physics_material_override = pm
	t.add_child(body)
	# The barrier: timber-and-stripes blocks down the middle of the split.
	d = nose
	var k := 0
	while d < nose + 34.0 and d < float(b["to"]):
		var f := t.road_frame(d)
		var mid := f.origin + f.basis.x * t.branch_offset(d, bi) * 0.5
		var f2 := t.road_frame(d + 2.0)
		var mid2 := f2.origin + f2.basis.x * t.branch_offset(d + 2.0, bi) * 0.5
		var fwd := mid2 - mid
		fwd.y = 0.0
		var basis := Basis.looking_at(fwd.normalized(), Vector3.UP)
		var c := (mid + mid2) * 0.5 + Vector3.UP * 0.55
		SetPieces._box(st, Transform3D(basis, c), Vector3(0.8, 1.1, 2.0), Color(0.98, 0.78, 0.12) if k % 2 == 0 else Color(0.15, 0.13, 0.12))
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.9, 1.4, 2.1)
		col.shape = box
		col.transform = Transform3D(basis, c + Vector3.UP * 0.15)
		body.add_child(col)
		d += 2.0
		k += 1
	# The sign, on two posts at the nose, facing the oncoming karts.
	var f := t.road_frame(nose - 1.0)
	var p := f.origin + f.basis.x * t.branch_offset(nose, bi) * 0.5
	var facing := f.basis.z
	var board := Basis.looking_at(-facing)
	for sx: float in [-2.6, 2.6]:
		SetPieces._box(st, Transform3D(board, p + board.x * sx + Vector3.UP * 1.9), Vector3(0.22, 3.8, 0.22), WOOD)
	var c := p + Vector3.UP * 3.4
	SetPieces._box(st, Transform3D(board, c), Vector3(6.8, 1.9, 0.2), Color(0.96, 0.9, 0.7))
	SetPieces._box(st, Transform3D(board, c - facing * 0.03), Vector3(7.1, 2.2, 0.16), WOOD.darkened(0.2))
	SetPieces._commit(t, st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))
	# board.x is the viewer's right. The bridge is `side` of the road.
	for e in [["<< BRIDGE", "ROAD >>"] if side < 0 else ["<< ROAD", "BRIDGE >>"]]:
		for j in 2:
			var label := Label3D.new()
			label.text = e[j]
			label.font_size = 80
			label.pixel_size = 0.009
			label.outline_size = 18
			label.modulate = Color(0.75, 0.2, 0.1) if e[j].contains("BRIDGE") else Color(0.15, 0.25, 0.4)
			label.outline_modulate = Color(1, 1, 1)
			label.shaded = false
			label.transform = Transform3D(board, c + facing * 0.12 + board.x * (-1.7 if j == 0 else 1.7))
			t.add_child(label)


## Mine carts and lanterns by the start, on the mountain's shoulder.
static func _props(t: Track) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# (The rocks at the foot of the mountain wall are now Blender models:
	# TerrainDressing.)
	for k in 3:
		var f := t.transform_at(t.length - 20.0 - k * 7.0)
		var p := f.origin - f.basis.x * t.ledge_out * (Track.ROAD_WIDTH * 0.5 + 6.0)
		SetPieces._box(st, Transform3D(f.basis, p + Vector3.UP * 0.9), Vector3(1.8, 1.0, 2.6), Color(0.5, 0.36, 0.26))
		SetPieces._box(st, Transform3D(f.basis, p + Vector3.UP * 1.45), Vector3(1.6, 0.3, 2.4), Color(0.17, 0.14, 0.12))  # coal
		for s: float in [-1.0, 1.0]:
			for e: float in [-0.8, 0.8]:
				SetPieces._box(st, Transform3D(f.basis, p + f.basis.x * s * 0.95 + f.basis.z * e + Vector3.UP * 0.35), Vector3(0.2, 0.6, 0.6), Color(0.3, 0.3, 0.33))
	SetPieces._commit(t, st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))
