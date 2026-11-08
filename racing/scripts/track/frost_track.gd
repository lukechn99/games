class_name FrostTrack
extends RefCounted
## Frosty Pass (design doc 8.3): a snowy mountain pass. From the start
## straight the road climbs two icy hairpins, runs over the summit (snow
## drifts), comes down a long descent where giant snowballs roll across
## the road, and swings round a wide bend at the bottom of the pass. Inside
## that bend lies a frozen lake: the shortcut runs straight across the ice,
## shorter but slippery (studded tyres shine). Snowy pines everywhere.

## Racing line, clockwise from the start line.
const POINTS := [
	Vector3(0, 0, 40), Vector3(0, 0, -30), Vector3(8, 1, -95),
	# Hairpin one (right), climbing.
	Vector3(35, 2.5, -125), Vector3(68, 4, -118), Vector3(80, 5.5, -90), Vector3(88, 7, -40),
	# Hairpin two (left).
	Vector3(100, 8.5, -5), Vector3(130, 10, 4), Vector3(152, 11.5, -15), Vector3(160, 13, -60),
	# Up to the summit.
	Vector3(165, 15, -120), Vector3(150, 16, -175), Vector3(110, 16, -205),
	# The descent (rolling snowballs).
	Vector3(50, 9, -225), Vector3(-20, 2, -225),
	# Round the bottom of the pass, the lake inside the bend.
	Vector3(-80, 0, -205), Vector3(-140, 0, -175), Vector3(-185, 0, -110), Vector3(-190, 0, -40),
	Vector3(-160, 0, 25), Vector3(-110, 0, 55),
	# Home.
	Vector3(-60, 0, 90), Vector3(-18, 0, 105), Vector3(0, 0, 85),
]
## The shortcut across the frozen lake: from the start of the bend to its end.
## The road leads onto the ice, which is wide open, but has holes in it:
## drop through one and you land on a sunken road under the ice, which runs
## the length of the lake and climbs back out through an opening at the
## far shore.
const SHORTCUT := [Vector2(-80, -205), Vector2(-88, -150), Vector2(-93, -80), Vector2(-95, -10), Vector2(-110, 55)]
const LAKE_CENTER := Vector3(-92, 0, -75)
const LAKE_RX := 40.0
const LAKE_RZ := 105.0
const ICE_Y := 0.1
const DEEP := -7.5          # the sunken road's surface
## Holes in the ice: [fraction along the lake, sideways metres, radius].
const HOLES := [[0.2, -6.0, 3.6], [0.31, 7.0, 3.4], [0.43, -1.5, 4.0], [0.55, 7.5, 3.4], [0.66, -7.5, 3.8], [0.74, 2.0, 3.2]]
const EXIT_LEN := 30.0      # the ramp out climbs over the last metres of the lake
const EXIT_HALF := 9.0

## Where snowballs roll across the road (indices into POINTS, between).
const ROLL_SPOTS := [[13, 14], [14, 15]]


static func configure(t: Track) -> void:
	t.points = POINTS
	t.rail_zones = [[0.0, 0.05], [0.95, 1.0]]
	t.ground_y = 0.0
	t.trees_hit_radius = 24.0


static func plan(t: Track) -> void:
	var L := t.length
	var zones := []
	# Icy hairpins: from the turn-in to the exit of each.
	for pair in [[3, 5], [7, 9]]:
		var a := t.offset_of(POINTS[pair[0]]) - 6.0
		var b := t.offset_of(POINTS[pair[1]]) + 6.0
		zones.append({"from": a / L, "to": b / L, "surface": "ice"})
	# Snow drifting over the summit road.
	var s0 := t.offset_of(POINTS[11])
	var s1 := t.offset_of(POINTS[12])
	zones.append({"from": (s0 + 15.0) / L, "to": (s1 - 10.0) / L, "surface": "snow"})
	# A boost pad as the descent starts.
	var bp := t.offset_of(POINTS[13]) + 20.0
	zones.append({"from": bp / L, "to": (bp + 14.0) / L, "surface": "boost"})
	t.surface_zones = zones
	_add_chord(t, SHORTCUT, "lake")
	t.branches[t.branches.size() - 1]["surface"] = "ice"


## The shortcut as its own path: the polyline smoothed, walked at an even
## pace from one end to the other while the main road runs from `from` to
## `to`, and eased onto the main road over the last 25 m at each end.
static func _add_chord(t: Track, line2: Array, kind: String) -> void:
	var c := Curve3D.new()
	for i in line2.size():
		var p: Vector2 = line2[i]
		var prev: Vector2 = line2[maxi(i - 1, 0)]
		var next: Vector2 = line2[mini(i + 1, line2.size() - 1)]
		var hnd := Vector3(next.x - prev.x, 0, next.y - prev.y) / 6.0
		c.add_point(Vector3(p.x, 0, p.y), -hnd, hnd)
	c.bake_interval = 0.5
	var first: Vector2 = line2[0]
	var last: Vector2 = line2[line2.size() - 1]
	var from := t.offset_of(Vector3(first.x, 0, first.y))
	var to := t.offset_of(Vector3(last.x, 0, last.y))
	var clen := c.get_baked_length()
	var pts := PackedVector3Array()
	var d := from
	while d <= to + 1.0:
		var u := clampf((d - from) / (to - from), 0.0, 1.0)
		var q := c.sample_baked(u * clen, true)
		var m := t.transform_at(d).origin
		q.y = m.y
		var e := smoothstep(0.0, 1.0, clampf(minf(d - from, to - d) / 25.0, 0.0, 1.0))
		pts.append(m.lerp(q, e))
		d += 1.0
	t.add_branch(from, to, PackedFloat32Array(), kind, pts)


static func build(t: Track) -> void:
	_frozen_lake(t)
	_snowmen(t)
	var r := Rollers.new()
	r.track = t
	t.add_child(r)


static func lake_branch(t: Track) -> int:
	for i in t.branches.size():
		if t.branches[i]["kind"] == "lake":
			return i
	return -1


## Inside the lake's shore (ignoring height).
static func in_lake(p: Vector3, grow := 1.0) -> bool:
	var dx := (p.x - LAKE_CENTER.x) / (LAKE_RX * grow)
	var dz := (p.z - LAKE_CENTER.z) / (LAKE_RZ * grow)
	return dx * dx + dz * dz < 1.0


## The shortcut has ordinary road only on land: over the lake it's ice.
static func has_road(t: Track, i: int, d: float) -> bool:
	return not in_lake(t.branch_frame(d, i).origin, 1.02)


## Where the shortcut is over the lake: [first offset, last offset].
static func lake_span(t: Track) -> Vector2:
	var bi := lake_branch(t)
	var b: Dictionary = t.branches[bi]
	var a := INF
	var z := -INF
	var d: float = b["from"]
	while d <= float(b["to"]):
		if in_lake(t.branch_frame(d, bi).origin):
			a = minf(a, d)
			z = maxf(z, d)
		d += 1.0
	return Vector2(a, z)


## Item crates: on the start straight, on the descent, and a row down on the
## sunken road (a reward for falling in).
static func crate_frames(t: Track) -> Array[Transform3D]:
	var out: Array[Transform3D] = [t.transform_at(75.0), t.transform_at(t.offset_of(POINTS[14]) + 25.0)]
	var span := lake_span(t)
	var f := t.branch_frame(lerpf(span.x, span.y, 0.5), lake_branch(t))
	f.origin.y = DEEP + 1.2
	out.append(f)
	return out


## Ground collision with the lake cut out, so you can fall through a hole.
## (Track._build_ground asks for it.)
static func ground_collision(t: Track, body: StaticBody3D) -> void:
	var lo := Vector2(LAKE_CENTER.x - LAKE_RX - 2.0, LAKE_CENTER.z - LAKE_RZ - 2.0)
	var hi := Vector2(LAKE_CENTER.x + LAKE_RX + 2.0, LAKE_CENTER.z + LAKE_RZ + 2.0)
	var big := 1400.0
	var c := Vector2(80, -30)
	var x0 := c.x - big * 0.5
	var x1 := c.x + big * 0.5
	var z0 := c.y - big * 0.5
	var z1 := c.y + big * 0.5
	# Four boxes round the lake's rectangle...
	for r: Rect2 in [Rect2(x0, z0, lo.x - x0, z1 - z0), Rect2(hi.x, z0, x1 - hi.x, z1 - z0),
			Rect2(lo.x, z0, hi.x - lo.x, lo.y - z0), Rect2(lo.x, hi.y, hi.x - lo.x, z1 - hi.y)]:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 2.0, r.size.y)
		col.shape = box
		col.position = Vector3(r.position.x + r.size.x * 0.5, t.ground_y - 1.0, r.position.y + r.size.y * 0.5)
		body.add_child(col)
	# ...and flat snowy shore inside the rectangle but outside the lake.
	var faces := PackedVector3Array()
	var step := 2.0
	var x := lo.x
	while x < hi.x:
		var z := lo.y
		while z < hi.y:
			if not in_lake(Vector3(x + step * 0.5, 0, z + step * 0.5), 0.99):
				var a := Vector3(x, 0, z)
				var b := Vector3(x + step, 0, z)
				var cc := Vector3(x + step, 0, z + step)
				var d := Vector3(x, 0, z + step)
				faces.append_array([a, b, cc, a, cc, d])
			z += step
		x += step
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var col2 := CollisionShape3D.new()
	col2.shape = shape
	body.add_child(col2)


## The frozen lake: an ice sheet with holes, dark water showing through
## them, and under it a lakebed with a sunken road and kelp.
static func _frozen_lake(t: Track) -> void:
	var bi := lake_branch(t)
	var span := lake_span(t)
	var holes: Array[Vector3] = []   # (x, z, radius)
	for h in HOLES:
		var f := t.branch_frame(lerpf(span.x, span.y, float(h[0])), bi)
		var p: Vector3 = f.origin + f.basis.x * float(h[1])
		holes.append(Vector3(p.x, p.z, float(h[2])))
	# The exit opening, along the road's line for the last EXIT_LEN metres.
	var exit_frames: Array[Transform3D] = []
	var d := span.y - EXIT_LEN
	while d <= span.y + 4.0:
		exit_frames.append(t.branch_frame(d, bi))
		d += 2.0

	var in_hole := func(p: Vector3) -> bool:
		for h in holes:
			if Vector2(p.x - h.x, p.z - h.y).length() < h.z:
				return true
		for f in exit_frames:
			var l := f.affine_inverse() * Vector3(p.x, f.origin.y, p.z)
			if absf(l.x) < EXIT_HALF and absf(l.z) < 1.2:
				return true
		return false

	# Ice sheet: a 2 m grid over the lake, leaving out the holes.
	var ice := SurfaceTool.new()
	ice.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0
	var x := LAKE_CENTER.x - LAKE_RX - 2.0
	while x < LAKE_CENTER.x + LAKE_RX + 2.0:
		var z := LAKE_CENTER.z - LAKE_RZ - 2.0
		while z < LAKE_CENTER.z + LAKE_RZ + 2.0:
			var mid := Vector3(x + step * 0.5, ICE_Y, z + step * 0.5)
			if in_lake(mid, 1.02) and not in_hole.call(mid):
				var a := Vector3(x, ICE_Y, z)
				var b := Vector3(x + step, ICE_Y, z)
				var cc := Vector3(x + step, ICE_Y, z + step)
				var dd := Vector3(x, ICE_Y, z + step)
				for v in [a, cc, b, a, dd, cc]:
					ice.set_normal(Vector3.UP)
					ice.add_vertex(v)
			z += step
		x += step
	var ice_body := t._body("ice", true)
	var ice_mesh := ice.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = ice_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.88, 0.98)
	m.albedo_texture = load(Palette.TEX_DIR + "ice.png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 9.0
	m.roughness = 0.15
	m.metallic_specular = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # seen from below too
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	ice_body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := ice_mesh.create_trimesh_shape()
	shape.backface_collision = true
	col.shape = shape
	ice_body.add_child(col)
	# A rim of broken ice round each hole, so you can see them coming.
	var rim := SetPieces._new_st()
	for h in holes:
		var n := 14
		for k in n:
			var a0 := TAU * k / n
			var p := Vector3(h.x + cos(a0) * (h.z + 0.25), ICE_Y + 0.12, h.y + sin(a0) * (h.z + 0.25))
			SetPieces._box(rim, Transform3D(Basis(Vector3.UP, -a0 + 0.3 * sin(k * 2.1)), p), Vector3(0.9, 0.35 + 0.2 * absf(sin(k * 1.7)), 0.6), Color(0.85, 0.95, 1.0))
	SetPieces._commit(t, rim, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE))
	# Dark water just under the ice (seen through the holes, and from below).
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(LAKE_RX * 2.0, LAKE_RZ * 2.0)
	water.mesh = wm
	water.position = LAKE_CENTER + Vector3.UP * -0.6
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.05, 0.22, 0.38, 0.55)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water.material_override = wmat
	t.add_child(water)
	# The lakebed: sand, a little below the sunken road.
	var bed := t._body("sand", true)
	var bst := SurfaceTool.new()
	bst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array[Vector3] = []
	var nseg := 40
	for k in nseg:
		var a1 := TAU * k / nseg
		ring.append(LAKE_CENTER + Vector3(cos(a1) * LAKE_RX * 1.05, DEEP - 0.4, sin(a1) * LAKE_RZ * 1.05))
	for k in nseg:
		for v in [LAKE_CENTER + Vector3.UP * (DEEP - 0.4), ring[k], ring[(k + 1) % nseg]]:
			bst.set_color(Color(0.55, 0.62, 0.6))
			bst.set_normal(Vector3.UP)
			bst.add_vertex(v)
	# Steep banks up from the bed to the ice, all round.
	for k in nseg:
		var a2: Vector3 = ring[k]
		var b2: Vector3 = ring[(k + 1) % nseg]
		var a3 := Vector3(a2.x, ICE_Y - 0.05, a2.z)
		var b3 := Vector3(b2.x, ICE_Y - 0.05, b2.z)
		for v in [a2, a3, b3, a2, b3, b2]:
			bst.set_color(Color(0.42, 0.5, 0.52))
			bst.set_normal((LAKE_CENTER - a2).normalized())
			bst.add_vertex(v)
	var bmesh := bst.commit()
	var bmi := MeshInstance3D.new()
	bmi.mesh = bmesh
	var bmat := Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE).duplicate() as StandardMaterial3D
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmi.material_override = bmat
	bed.add_child(bmi)
	var bcol := CollisionShape3D.new()
	var bshape := bmesh.create_trimesh_shape()
	bshape.backface_collision = true
	bcol.shape = bshape
	bed.add_child(bcol)
	# The sunken road: the shortcut's line, down under the ice, climbing out
	# through the opening at the far end.
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	d = span.x
	var idx := 0
	while d < span.y + 6.0:
		var fa := t.branch_frame(d, bi)
		var fb := t.branch_frame(d + 2.0, bi)
		fa.origin.y = _deep_y(d, span)
		fb.origin.y = _deep_y(d + 2.0, span)
		t._quad_strip(road, fa, fb, "asphalt", idx, d, 0.0, 0.0, Color(0.36, 0.42, 0.5))
		d += 2.0
		idx += 1
	road.generate_normals()
	var rmesh := road.commit()
	var rbody := t._body("asphalt", true)
	var rmi := MeshInstance3D.new()
	rmi.mesh = rmesh
	rmi.material_override = t._road_mat()
	rbody.add_child(rmi)
	var rcol := CollisionShape3D.new()
	var rshape := rmesh.create_trimesh_shape()
	rshape.backface_collision = true
	rcol.shape = rshape
	rbody.add_child(rcol)
	# Kelp swaying either side of the sunken road.
	var kelp := SetPieces._new_st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 60:
		var f := t.branch_frame(lerpf(span.x, span.y - EXIT_LEN, rng.randf()), bi)
		var side := -1.0 if k % 2 == 0 else 1.0
		var p := f.origin + f.basis.x * side * rng.randf_range(Track.ROAD_WIDTH * 0.5 + 3.0, 30.0)
		if not in_lake(p, 0.9):
			continue
		var hgt := rng.randf_range(2.0, 5.5)
		p.y = DEEP - 0.4 + hgt * 0.5
		SetPieces._box(kelp, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), Vector3(0.35, hgt, 0.12), Color(0.2, 0.55, 0.32).lerp(Color(0.35, 0.65, 0.25), rng.randf()))
	SetPieces._commit(t, kelp, Palette.leaves(Color(0.25, 0.6, 0.3)))
	for i in 4:
		var zc := LAKE_CENTER.z + (i - 1.5) * LAKE_RZ * 0.5
		t._keep_clear.append(Vector3(LAKE_CENTER.x, zc, LAKE_RX + 6.0))


## The sunken road's height: deep under the lake, rising to the shore over
## the last EXIT_LEN metres.
static func _deep_y(d: float, span: Vector2) -> float:
	var u := clampf((d - (span.y - EXIT_LEN)) / EXIT_LEN, 0.0, 1.0)
	return lerpf(DEEP, ICE_Y + 0.05, smoothstep(0.0, 1.0, u))


## A few snowmen cheering by the start and on the summit.
static func _snowmen(t: Track) -> void:
	var xs: Array[Transform3D] = []
	for spot in [[18.0, 1.0], [30.0, -1.0], [t.offset_of(POINTS[12]), 1.0], [t.offset_of(POINTS[12]) + 14.0, -1.0], [t.length - 40.0, 1.0]]:
		var f := t.transform_at(spot[0])
		var p := f.origin + f.basis.x * float(spot[1]) * (Track.ROAD_WIDTH * 0.5 + 6.0)
		p.y = maxf(f.origin.y - 1.0, t.ground_y)
		var face := Basis.looking_at(-(f.basis.x * float(spot[1])), Vector3.UP)
		xs.append(Transform3D(face.scaled(Vector3.ONE * 1.2), p))
	t._scatter(Track.MODELS + "snowman.glb", xs)


## Giant snowballs rolling down across the road on the descent, one after
## another. They run on the race clock (the host's, online), so every phone
## sees them in the same place. One knocks you sideways.
class Rollers extends Node3D:
	const RADIUS := 2.1
	const SPAN := 24.0       # metres either side of the road's centre
	const CROSS := 4.2       # seconds to roll across
	const PERIOD := 7.5
	var track: Track
	var _balls: Array[Dictionary] = []
	var _karts: Array = []
	var _find := 0.0

	func _ready() -> void:
		var mesh := SphereMesh.new()
		mesh.radius = RADIUS
		mesh.height = RADIUS * 2.0
		mesh.radial_segments = 20
		mesh.rings = 10
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.96, 0.97, 1.0)
		m.albedo_texture = load(Palette.TEX_DIR + "ice.png")
		m.uv1_scale = Vector3(3, 2, 1)
		m.roughness = 0.8
		var i := 0
		for spot in ROLL_SPOTS:
			for k in 2:
				var a := track.offset_of(POINTS[spot[0]])
				var b := track.offset_of(POINTS[spot[1]])
				var d := lerpf(a, b, 0.3 + 0.4 * k)
				var n := MeshInstance3D.new()
				n.mesh = mesh
				n.material_override = m
				add_child(n)
				_balls.append({"node": n, "d": d, "phase": i * 1.9, "hit": {}, "dir": 1.0 if i % 2 == 0 else -1.0})
				i += 1

	func _clock() -> float:
		var net := get_node_or_null("/root/Net")
		if net and net.active:
			return net.host_now()
		return Time.get_ticks_msec() / 1000.0

	func _physics_process(delta: float) -> void:
		_find -= delta
		if _find <= 0.0:
			_find = 2.0
			_karts = get_tree().root.find_children("*", "Kart", true, false)
		var now := _clock()
		for b in _balls:
			var t := fposmod(now + float(b["phase"]), PERIOD)
			var n: MeshInstance3D = b["node"]
			if t > CROSS:
				n.visible = false
				b["hit"] = {}
				continue
			n.visible = true
			var f := track.road_frame(float(b["d"]))
			var u := t / CROSS
			var x := lerpf(SPAN, -SPAN, u) * float(b["dir"])
			var p := f.origin + f.basis.x * x
			p.y = track.transform_at(float(b["d"])).origin.y + RADIUS - 0.3
			n.position = p
			n.basis = Basis(f.basis.z, x / RADIUS)
			for k in _karts:
				if not is_instance_valid(k):
					continue
				var kart := k as Kart
				if kart == null or (b["hit"] as Dictionary).has(kart):
					continue
				var rel := kart.global_position - p
				if Vector2(rel.x, rel.z).length() < RADIUS + 0.9 and absf(rel.y) < RADIUS + 1.0:
					b["hit"][kart] = true
					kart.knock(p)
