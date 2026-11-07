class_name SetDressing
extends RefCounted
## Roadside clutter that makes a circuit look busy and looked-after, as in
## Mario Kart (design doc 9.4): red chevron boards round the sharp corners,
## feather banners along the straights, cone clusters at the apexes and
## billboards for made-up sponsors. Everything but the billboard lettering
## is merged into a couple of meshes, so it costs a few draw calls.

const SPONSORS := [
	["ZOOMIX", Color(0.98, 0.78, 0.12), Color(0.85, 0.15, 0.12)],
	["Honeybee Tyres", Color(0.15, 0.2, 0.32), Color(1.0, 0.8, 0.2)],
	["PEBBLE POP", Color(0.3, 0.75, 0.95), Color(1.0, 1.0, 1.0)],
	["Quick Fox Oil", Color(0.92, 0.3, 0.12), Color(1.0, 0.95, 0.85)],
	["TURBO TREATS", Color(0.55, 0.3, 0.85), Color(1.0, 0.9, 0.3)],
	["Meadow Motors", Color(0.2, 0.65, 0.35), Color(1.0, 1.0, 1.0)],
]


static func build(t: Track) -> void:
	var st := SetPieces._new_st()
	var cones: Array[Transform3D] = []
	var corners := _corners(t)
	for c in corners:
		_chevrons(t, st, c[0], c[1], cones)
	_banners(t, st, corners)
	_billboards(t, st, corners)
	SetPieces._commit(t, st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))
	t._scatter(Track.KIT_RACING + "pylon.glb", cones, 150.0)


## Sharp corners: [offset of the apex, which way it turns (+1 right)].
static func _corners(t: Track) -> Array:
	var out := []
	var d := 20.0
	var last := -999.0
	while d < t.length - 20.0:
		var a := -t.road_frame(d - 14.0).basis.z
		var b := -t.road_frame(d + 14.0).basis.z
		var turn := Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))
		if absf(turn) > 0.55 and d - last > 70.0 and t.branch_at(d) < 0:
			# Walk on to where it turns hardest.
			var best := d
			var best_turn := absf(turn)
			for k in range(1, 12):
				var dd := d + k * 2.0
				var aa := -t.road_frame(dd - 14.0).basis.z
				var bb := -t.road_frame(dd + 14.0).basis.z
				var tt := absf(Vector2(aa.x, aa.z).angle_to(Vector2(bb.x, bb.z)))
				if tt > best_turn:
					best_turn = tt
					best = dd
			out.append([best, signf(turn)])
			last = best
			d = best + 40.0
		d += 4.0
	return out


static func _clear(t: Track, p: Vector3, room: float) -> bool:
	return t.distance_to_road(p) > Track.ROAD_WIDTH * 0.5 + room and not t._blocked(p) and not t.in_water(p)


## Three or four red boards with white arrows on the outside of a corner,
## turned to face the karts coming into it.
static func _chevrons(t: Track, st: SurfaceTool, apex: float, turn: float, cones: Array[Transform3D]) -> void:
	# A right-hander (turn > 0) has its boards on the left, arrows pointing
	# right as the driver sees them.
	var outside := -turn
	for k in 4:
		var d := apex - 18.0 + k * 9.0
		var f := t.road_frame(d)
		var p := f.origin + f.basis.x * outside * (Track.ROAD_WIDTH * 0.5 + 4.6)
		if not _clear(t, p, 3.0):
			continue
		var fwd := -f.basis.z
		# Face the oncoming karts, angled a little in toward the road.
		var facing := (-fwd).rotated(Vector3.UP, outside * 0.35)
		var right := facing.cross(Vector3.UP).normalized()
		var top := maxf(f.origin.y, 0.0) + 3.1
		var ground := minf(f.origin.y, 0.0)
		for sx: float in [-1.0, 1.0]:
			SetPieces._box(st, Transform3D(Basis.looking_at(facing), Vector3(p.x, (ground + top) * 0.5, p.z) + right * sx), Vector3(0.12, top - ground, 0.12), Color(0.75, 0.76, 0.8))
		var c := Vector3(p.x, top, p.z)
		var board := Basis.looking_at(facing)
		SetPieces._box(st, Transform3D(board, c), Vector3(2.7, 2.2, 0.14), Color(0.9, 0.12, 0.12))
		SetPieces._box(st, Transform3D(board, c), Vector3(2.9, 2.4, 0.1), Color(0.97, 0.97, 0.97))
		# The arrow: two white bars meeting in a point, toward the turn.
		# `right` is the viewer's left, so this points the arrow into the turn.
		var dir := outside
		var tip := c + facing * 0.09 + right * dir * 0.62
		for sy: float in [-1.0, 1.0]:
			var mid := tip - right * dir * 0.46 + Vector3.UP * sy * 0.44
			var b := Basis.looking_at(facing).rotated(facing, sy * dir * 0.75)
			SetPieces._box(st, Transform3D(b, mid), Vector3(1.38, 0.38, 0.05), Color(1, 1, 1))
	# A few cones at the apex, on the inside.
	var fa := t.road_frame(apex)
	for k in 3:
		var p := fa.origin - fa.basis.x * outside * (Track.ROAD_WIDTH * 0.5 + 2.4 + k * 0.7) + fa.basis.z * (k - 1) * 1.1
		if _clear(t, p, 1.5):
			p.y = maxf(fa.origin.y - 0.3, 0.0)
			cones.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.6), p))


## Feather banners: tall curved flags on poles, in pairs along the straights.
static func _banners(t: Track, st: SurfaceTool, corners: Array) -> void:
	var colors := [Color(0.95, 0.2, 0.22), Color(0.2, 0.55, 0.95), Color(1.0, 0.72, 0.12)]
	var d := 50.0
	var i := 0
	while d < t.length - 90.0:
		var near_corner := false
		for c in corners:
			if absf(c[0] - d) < 45.0:
				near_corner = true
		if not near_corner and t.branch_at(d) < 0:
			var f := t.road_frame(d)
			for s: float in [-1.0, 1.0]:
				var p := f.origin + f.basis.x * s * (Track.ROAD_WIDTH * 0.5 + 3.4)
				if _clear(t, p, 2.5):
					_feather(st, Vector3(p.x, minf(f.origin.y, 0.0), p.z), maxf(f.origin.y, 0.0), -f.basis.z, colors[i % colors.size()])
			i += 1
		d += 42.0


static func _feather(st: SurfaceTool, base: Vector3, road_y: float, fwd: Vector3, color: Color) -> void:
	var pole_top := road_y + 4.6
	SetPieces._box(st, Transform3D(Basis.IDENTITY, Vector3(base.x, (base.y + pole_top) * 0.5, base.z)), Vector3(0.09, pole_top - base.y, 0.09), Color(0.85, 0.86, 0.9))
	# The cloth streams back from the pole: a tall sail, widest near the top.
	var back := -Vector3(fwd.x, 0, fwd.z).normalized()
	var steps := 8
	var h0 := road_y + 1.0
	var h1 := pole_top - 0.05
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	for k in steps + 1:
		var u := float(k) / steps
		var y := lerpf(h0, h1, u)
		var w := 1.05 * pow(sin(PI * clampf(u * 0.85 + 0.12, 0.0, 1.0)), 0.7)
		var a := Vector3(base.x, y, base.z)
		var b := a + back * w + Vector3.UP * (0.25 * u)
		if k > 0:
			# A white stripe along the pole, the rest in colour.
			var mid0 := prev_a.lerp(prev_b, 0.18)
			var mid1 := a.lerp(b, 0.18)
			SetPieces._quad(st, prev_a, mid0, mid1, a, Color(0.97, 0.97, 0.97))
			SetPieces._quad(st, a, mid1, mid0, prev_a, Color(0.97, 0.97, 0.97))
			SetPieces._quad(st, mid0, prev_b, b, mid1, color)
			SetPieces._quad(st, mid1, b, prev_b, mid0, color)
		prev_a = a
		prev_b = b


## Big sponsor boards back from the road on the straights, angled toward
## the oncoming karts.
static func _billboards(t: Track, st: SurfaceTool, corners: Array) -> void:
	var n := 0
	var d := 120.0
	while d < t.length - 120.0 and n < SPONSORS.size():
		var near_corner := false
		for c in corners:
			if absf(c[0] - d) < 30.0:
				near_corner = true
		var f := t.road_frame(d)
		var s := -1.0 if n % 2 == 0 else 1.0
		var p := f.origin + f.basis.x * s * (Track.ROAD_WIDTH * 0.5 + 9.0)
		if not near_corner and t.branch_at(d) < 0 and _clear(t, p, 6.0):
			var facing := (f.basis.z).rotated(Vector3.UP, s * 0.5)   # toward oncoming karts
			var board := Basis.looking_at(-facing)
			var right := board.x
			var ground := minf(f.origin.y, 0.0)
			var c := Vector3(p.x, maxf(f.origin.y, 0.0) + 4.2, p.z)
			var sp: Array = SPONSORS[n]
			for sx: float in [-2.6, 2.6]:
				SetPieces._box(st, Transform3D(board, Vector3(p.x, (ground + c.y) * 0.5, p.z) + right * sx), Vector3(0.22, c.y - ground, 0.22), Color(0.3, 0.32, 0.36))
			SetPieces._box(st, Transform3D(board, c), Vector3(7.6, 3.3, 0.25), Color(0.95, 0.95, 0.95))
			SetPieces._box(st, Transform3D(board, c + facing * 0.02), Vector3(7.2, 2.9, 0.26), sp[1])
			# A bold stripe along the bottom.
			SetPieces._box(st, Transform3D(board, c + facing * 0.03 - Vector3.UP * 1.05), Vector3(7.2, 0.5, 0.27), sp[2])
			var label := Label3D.new()
			label.text = sp[0]
			label.font_size = 140
			label.pixel_size = 0.009
			label.outline_size = 28
			label.modulate = sp[2]
			label.outline_modulate = Color(0.08, 0.08, 0.1)
			label.double_sided = false
			label.shaded = false
			label.visibility_range_end = 220.0
			label.transform = Transform3D(board, c + facing * 0.16 + Vector3.UP * 0.25)
			t.add_child(label)
			n += 1
			d += 160.0
		else:
			d += 20.0
