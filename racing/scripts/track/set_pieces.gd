class_name SetPieces
extends RefCounted
## The things that make the track feel like a place (design doc 9.4):
## a lake below the high ledge, a rock tunnel, a stone bridge, sign gantries,
## the rocky island where the road splits, bleachers with a cheering crowd,
## flags, drifting clouds and soft shade under everything that stands up.
##
## All of it is cheap on phones: a handful of meshes, one draw call per kind
## of repeated thing, and shade drawn as soft dark patches instead of
## real-time shadows.

const SUN_EULER := Vector3(-52, -35, 0)  # matches the sun in main.gd

static var _shade_mat: StandardMaterial3D


static func build(t: Track) -> void:
	_lake(t)
	_tunnel(t)
	_bridge(t)
	for d in Track.GANTRIES:
		_gantry(t, d)
	_island(t)
	_bleachers(t, 600.0)
	_bleachers(t, t.length - 72.0, -1.0)
	_start_flags(t)
	_clouds(t)


# --- Shade -------------------------------------------------------------------

## Which way the sun's light travels, flattened, and how far a shadow
## stretches per metre of height.
static func sun_ground_offset() -> Vector3:
	var dir := Basis.from_euler(SUN_EULER * PI / 180.0) * Vector3.FORWARD
	var flat := Vector3(dir.x, 0.0, dir.z)
	var stretch := flat.length() / maxf(0.2, -dir.y)
	return flat.normalized() * stretch


static func shade_material() -> StandardMaterial3D:
	if _shade_mat:
		return _shade_mat
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.42))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.6, Color(0, 0, 0, 0.3))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_shade_mat = StandardMaterial3D.new()
	_shade_mat.albedo_texture = tex
	_shade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shade_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_shade_mat.render_priority = -1
	return _shade_mat


## Soft shade on flat ground for things of the given footprint and height:
## each entry is [base position, radius, height]. One draw call for all.
static func ground_shade(parent: Node3D, items: Array) -> void:
	if items.is_empty():
		return
	var off := sun_ground_offset()
	var along := off.normalized()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.orientation = PlaneMesh.FACE_Y
	mm.mesh = quad
	mm.instance_count = items.size()
	for i in items.size():
		var base: Vector3 = items[i][0]
		var r: float = items[i][1]
		var h: float = items[i][2]
		var reach := off.length() * h
		var center := base + along * reach * 0.45
		center.y = base.y + 0.035
		var across := Vector3.UP.cross(along).normalized()
		var basis := Basis(across * (r * 2.4), Vector3.UP, along * (reach * 0.9 + r * 2.4))
		mm.set_instance_transform(i, Transform3D(basis, center))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = shade_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## A soft dark patch lying on the road at `offset`, `across` × `along` metres,
## shifted sideways by `side_m`.
static func road_shade(t: Track, offset: float, across: float, along: float, side_m := 0.0, dark := 1.0) -> void:
	var f := t.road_frame(offset)
	var quad := QuadMesh.new()
	quad.size = Vector2(across, along)
	quad.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.transform = Transform3D(f.basis, f.origin + f.basis.x * side_m + f.basis.y * 0.08)
	var m := shade_material()
	if dark != 1.0:
		m = m.duplicate()
		m.albedo_color = Color(1, 1, 1, dark)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(mi)


# --- Mesh helpers ------------------------------------------------------------

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(v)


## A box from a transform and size, added to a SurfaceTool.
static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var faces := [
		[[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]],
		[[1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1]],
		[[1, -1, 1], [1, -1, -1], [1, 1, -1], [1, 1, 1]],
		[[-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1]],
		[[-1, 1, 1], [1, 1, 1], [1, 1, -1], [-1, 1, -1]],
		[[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1]],
	]
	for f in faces:
		var v := []
		for c in f:
			v.append(p.call(c[0], c[1], c[2]))
		# Faces wind clockwise seen from outside (Godot's front face).
		_quad(st, v[0], v[3], v[2], v[1], col)


static func _commit(t: Node3D, st: SurfaceTool, mat: Material, solid := false, surface := "asphalt") -> MeshInstance3D:
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if solid:
		var body := StaticBody3D.new()
		body.set_meta("surface", surface)
		t.add_child(body)
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var shape := mesh.create_trimesh_shape()
		shape.backface_collision = true
		col.shape = shape
		body.add_child(col)
	else:
		t.add_child(mi)
	return mi


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _solid_cylinder(t: Node3D, pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", "rock")
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	col.shape = cyl
	col.position = pos + Vector3.UP * height * 0.5
	body.add_child(col)
	t.add_child(body)


## A lumpy rock column: rough sides, darker in the creases at the bottom.
static func _boulder(st: SurfaceTool, base: Vector3, radius: float, height: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var segs := 9
	var rings := 4
	var pts := []
	for r in rings + 1:
		var row := []
		var y := height * r / rings
		var taper := lerpf(1.0, 0.55, float(r) / rings)
		for s in segs:
			var a := TAU * s / segs
			var rr := radius * taper * rng.randf_range(0.8, 1.15)
			row.append(base + Vector3(cos(a) * rr, y + rng.randf_range(-0.3, 0.3) * (1 if r > 0 else 0), sin(a) * rr))
		pts.append(row)
	var c := Color(0.62, 0.6, 0.58)
	for r in rings:
		var shade := c.darkened(0.3 * (1.0 - float(r) / rings))
		for s in segs:
			var s2 := (s + 1) % segs
			_quad(st, pts[r][s], pts[r][s2], pts[r + 1][s2], pts[r + 1][s], shade)
	var top := base + Vector3.UP * (height + 0.4)
	for s in segs:
		var s2 := (s + 1) % segs
		for v in [pts[rings][s], pts[rings][s2], top]:
			st.set_color(c.lightened(0.05))
			st.add_vertex(v)


# --- Set pieces --------------------------------------------------------------

## A lake below the cliff on the outside of the high ledge. Falling in puts
## you back on the road (Track.in_water).
static func _lake(t: Track) -> void:
	var st := _new_st()
	var edge := Track.ROAD_WIDTH * 0.5 + 1.0
	var d := Track.LEDGE[0] - 10.0
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	var first := true
	while d <= Track.LEDGE[1] + 10.0:
		var f := t.transform_at(d)
		var u := clampf((d - Track.LEDGE[0] + 10.0) / (Track.LEDGE[1] - Track.LEDGE[0] + 20.0), 0.0, 1.0)
		var width := 12.0 + 48.0 * sin(u * PI)
		var p_in := f.origin + f.basis.x * t.ledge_out * edge
		var p_out := f.origin + f.basis.x * t.ledge_out * (edge + width)
		p_in.y = 0.25
		p_out.y = 0.25
		if not first:
			if t.ledge_out > 0:
				_quad(st, prev_in, p_in, p_out, prev_out, Color.WHITE)
			else:
				_quad(st, prev_in, prev_out, p_out, p_in, Color.WHITE)
		prev_in = p_in
		prev_out = p_out
		first = false
		d += 4.0
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(mi)
	# Reeds and rocks along the far shore are left to the scenery's keep-clear.


## A rock tunnel on the climb: a thick arch following the road, stone inside
## with lamps, rough rock outside, and a darker road in the shade within.
static func _tunnel(t: Track) -> void:
	var inner_st := _new_st()
	var outer_st := _new_st()
	var lamps := _new_st()
	var ri := Track.ROAD_WIDTH * 0.5 + 2.6
	var thick := 3.2
	var arc := 12
	var d0: float = Track.TUNNEL[0]
	var d1: float = Track.TUNNEL[1]
	var rings := []
	var d := d0
	while d <= d1 + 0.01:
		var f := t.road_frame(d)
		var inner := []
		var outer := []
		for k in arc + 3:
			var p_in: Vector3
			var p_out: Vector3
			var bump := 0.6 * sin(d * 0.31 + k * 1.7) + 0.4 * sin(d * 0.13 + k)
			if k == 0 or k == arc + 2:
				# Legs go down into the bank so there's no gap at the road edge.
				var sx := 1.0 if k == 0 else -1.0
				p_in = f.origin + f.basis.x * sx * ri - Vector3.UP * 3.0
				p_out = f.origin + f.basis.x * sx * (ri + thick + 1.5) - Vector3.UP * 3.0
			else:
				var a := PI * float(k - 1) / arc
				var dir := f.basis.x * cos(a) + f.basis.y * sin(a) * 0.78
				p_in = f.origin + dir * ri
				p_out = f.origin + dir * (ri + thick + bump) + Vector3.UP * (1.5 * sin(a))
			inner.append(p_in)
			outer.append(p_out)
		rings.append([inner, outer])
		d += 3.0
	var stone := Color(0.55, 0.52, 0.5)
	var rock := Color(0.6, 0.58, 0.55)
	for r in rings.size() - 1:
		var a_in: Array = rings[r][0]
		var b_in: Array = rings[r + 1][0]
		var a_out: Array = rings[r][1]
		var b_out: Array = rings[r + 1][1]
		for k in a_in.size() - 1:
			# Inside faces the road; outside faces the sky.
			_quad(inner_st, a_in[k], b_in[k], b_in[k + 1], a_in[k + 1], stone.darkened(0.35))
			_quad(outer_st, a_out[k], a_out[k + 1], b_out[k + 1], b_out[k], rock.darkened(0.1 if k == 0 or k == a_in.size() - 2 else 0.0))
	# Portals: stone faces joining inside and outside at each end.
	for e in [0, rings.size() - 1]:
		var ins: Array = rings[e][0]
		var outs: Array = rings[e][1]
		for k in ins.size() - 1:
			if e == 0:
				_quad(inner_st, ins[k], ins[k + 1], outs[k + 1], outs[k], stone)
			else:
				_quad(inner_st, ins[k], outs[k], outs[k + 1], ins[k + 1], stone)
	# Warm lamps along the ceiling.
	d = d0 + 4.0
	while d < d1 - 2.0:
		var f := t.road_frame(d)
		_box(lamps, Transform3D(f.basis, f.origin + f.basis.y * (ri * 0.78 - 0.25)), Vector3(1.6, 0.18, 0.5), Color(1.0, 0.86, 0.55))
		# Every other lamp really lights the tunnel (and karts driving through).
		if int((d - d0) / 7.0) % 2 == 0:
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.8, 0.5)
			light.light_energy = 1.6
			light.omni_range = 11.0
			light.omni_attenuation = 1.2
			light.position = f.origin + f.basis.y * (ri * 0.78 - 1.0)
			t.add_child(light)
		d += 7.0
	_commit(t, inner_st, _stone_mat(), true, "rock")
	_commit(t, outer_st, _rock_mat())
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.8, 0.45)
	glow.emission_energy_multiplier = 1.5
	_commit(t, lamps, glow)
	# It's darker inside.
	var mid := (d0 + d1) * 0.5
	var dark := _new_st()
	d = d0 + 1.0
	while d < d1 - 1.0:
		var fa := t.road_frame(d)
		var fb := t.road_frame(d + 2.0)
		var hw := Track.ROAD_WIDTH * 0.5 + 1.2
		var lift := 0.075
		var depth := clampf(minf(d - d0, d1 - d) / 6.0, 0.0, 1.0)
		var c := Color(0.02, 0.02, 0.06, 0.55 * depth)
		var pa0 := fa.origin - fa.basis.x * hw + fa.basis.y * lift
		var pa1 := fa.origin + fa.basis.x * hw + fa.basis.y * lift
		var pb0 := fb.origin - fb.basis.x * hw + fb.basis.y * lift
		var pb1 := fb.origin + fb.basis.x * hw + fb.basis.y * lift
		_quad(dark, pa0, pb0, pb1, pa1, c)
		d += 2.0
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_commit(t, dark, dm)
	t.keep_clear(t.transform_at(mid).origin, 30.0)


## A stone bridge between two gate towers, high over the ice.
static func _bridge(t: Track) -> void:
	var d: float = Track.BRIDGE_AT
	var f := t.transform_at(d)
	var road_y := t.road_frame(d).origin.y
	var st := _new_st()
	var stone := Color(0.78, 0.74, 0.68)
	var deck_y := road_y + 7.5
	var span := 13.0
	var flat := Basis(f.basis.x, Vector3.UP, f.basis.x.cross(Vector3.UP))
	# Deck and parapets.
	_box(st, Transform3D(flat, f.origin * Vector3(1, 0, 1) + Vector3.UP * deck_y), Vector3(span * 2.0, 1.4, 5.0), stone)
	for s: float in [-1.0, 1.0]:
		_box(st, Transform3D(flat, f.origin * Vector3(1, 0, 1) + Vector3.UP * (deck_y + 1.1) + f.basis.z * s * 2.2), Vector3(span * 2.0, 0.8, 0.5), stone.darkened(0.05))
	# A shallow arch under the deck.
	for k in 10:
		var x := lerpf(-span + 3.0, span - 3.0, (k + 0.5) / 10.0)
		var sag := 2.2 * (1.0 - pow(x / (span - 3.0), 2.0))
		_box(st, Transform3D(flat, f.origin * Vector3(1, 0, 1) + f.basis.x * x + Vector3.UP * (deck_y - 0.7 - (2.2 - sag) * 0.5 - 0.2)), Vector3((span * 2.0 - 6.0) / 10.0 + 0.05, (2.2 - sag) + 0.4, 4.6), stone.darkened(0.08))
	# Gate towers either side, standing on the ground.
	var tower := _new_st()
	for s: float in [-1.0, 1.0]:
		var c: Vector3 = f.origin * Vector3(1, 0, 1) + f.basis.x * s * (span + 2.0)
		var h := deck_y + 4.0
		_box(tower, Transform3D(flat, c + Vector3.UP * h * 0.5), Vector3(5.0, h, 6.0), stone)
		# Battlements.
		for k in 3:
			for side2 in [-1.0, 1.0]:
				_box(tower, Transform3D(flat, c + Vector3.UP * (h + 0.6) + f.basis.x * (k - 1) * 1.7 + f.basis.z * side2 * 2.6), Vector3(0.9, 1.2, 0.8), stone.darkened(0.05))
		_solid_cylinder(t, c, 3.0, h)
		t.keep_clear(c, 8.0)
	_commit(t, st, _stone_mat())
	_commit(t, tower, _stone_mat())
	# Its shade falls across the road.
	var off := sun_ground_offset() * (deck_y - road_y)
	var local := t.road_frame(d).basis.inverse() * off
	road_shade(t, d + local.z * -1.0, span * 2.2, 7.0, local.x, 0.9)


## A metal sign gantry: two posts, a lattice beam, a bright sign.
static func _gantry(t: Track, d: float) -> void:
	var f := t.road_frame(d)
	var flat := t.transform_at(d)
	var st := _new_st()
	var metal := Color(0.82, 0.84, 0.88)
	var half := Track.ROAD_WIDTH * 0.5 + 2.6
	var h := 7.0
	for s: float in [-1.0, 1.0]:
		var base: Vector3 = flat.origin + flat.basis.x * s * half
		base.y = minf(base.y, f.origin.y) - 1.0
		_box(st, Transform3D(flat.basis, base + Vector3.UP * (h + 1.0) * 0.5), Vector3(0.45, h + 1.0, 0.45), metal)
		_solid_cylinder(t, base, 0.35, h + 1.0)
	var top := flat.origin + Vector3.UP * (f.origin.y - flat.origin.y + h)
	for y in [0.0, 1.2]:
		_box(st, Transform3D(flat.basis, top + Vector3.UP * y), Vector3(half * 2.0 + 0.6, 0.25, 0.3), metal)
	for k in 12:
		var x := lerpf(-half, half, (k + 0.5) / 12.0)
		var tilt := 0.6 if k % 2 == 0 else -0.6
		_box(st, Transform3D(flat.basis.rotated(flat.basis.z, tilt), top + flat.basis.x * x + Vector3.UP * 0.6), Vector3(0.12, 1.5, 0.12), metal)
	var metal_mat := Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.METAL)
	_commit(t, st, metal_mat)
	# The sign: our colours, facing the drivers.
	var sign := _new_st()
	var colors := [Color(1.0, 0.68, 0.1), Color(0.2, 0.55, 0.95)]
	var sc: Color = colors[int(d) % 2]
	_box(sign, Transform3D(flat.basis, top + Vector3.UP * 0.6 + flat.basis.z * 0.3), Vector3(half * 1.1, 1.3, 0.15), sc)
	for k in 5:
		_box(sign, Transform3D(flat.basis, top + Vector3.UP * 0.6 + flat.basis.z * 0.4 + flat.basis.x * (k - 2) * 2.4), Vector3(1.2, 0.5, 0.05), Color(1, 1, 1))
	_commit(t, sign, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))
	road_shade(t, d + 3.0, half * 2.0, 3.0, sun_ground_offset().x * 2.0, 0.7)


## Where the road splits (design doc 9.4): the main road stays out under the
## sky and has the boost pad where the routes meet again. The second route
## dives into a hill: a dark cave lit by glowing mushrooms and crystals, with
## two strips of glowing moss that boost you and crystal pillars to weave
## round. Longer and riskier, but faster if you hit the moss.
static func _island(t: Track) -> void:
	# Where the two roads are fully apart.
	var d0 := -1.0
	var d1 := -1.0
	var d: float = Track.BRANCH[0]
	while d < Track.BRANCH[1]:
		if absf(t.branch_offset(d)) >= Track.BRANCH_SPLIT:
			if d0 < 0.0:
				d0 = d
			d1 = d
		d += 1.0
	_cones(t, d0, d1)
	_cave(t, d0 + 6.0, d1 - 6.0)
	# The hill over the cave fills the island; keep trees off it.
	var mid := t.branch_frame((d0 + d1) * 0.5)
	t.keep_clear(mid.origin, 40.0)


static func _cones(t: Track, d0: float, d1: float) -> void:
	var cones := _new_st()
	for d in [d0, d1]:
		var f := t.transform_at(d)
		var p := f.origin + f.basis.x * t.branch_offset(d) * 0.5
		for k in 3:
			var c := p + f.basis.z * (k - 1) * 1.6 * (1.0 if d == d0 else -1.0)
			_box(cones, Transform3D(Basis(), c + Vector3.UP * 0.4), Vector3(0.6, 0.8, 0.6), Color(1.0, 0.55, 0.08))
			_box(cones, Transform3D(Basis(), c + Vector3.UP * 0.5), Vector3(0.66, 0.15, 0.66), Color(1, 1, 1))
	_commit(t, cones, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))


static func _cave(t: Track, d0: float, d1: float) -> void:
	var inner_st := _new_st()
	var outer_st := _new_st()
	var ri := Track.ROAD_WIDTH * 0.5 + 1.8
	var arc := 14
	var rings := []
	var d := d0
	while d <= d1 + 0.01:
		var f := t.branch_frame(d)
		var inner := []
		var outer := []
		for k in arc + 3:
			var p_in: Vector3
			var p_out: Vector3
			if k == 0 or k == arc + 2:
				var sx := 1.0 if k == 0 else -1.0
				p_in = f.origin + f.basis.x * sx * ri - Vector3.UP * 2.0
				p_out = f.origin + f.basis.x * sx * (ri + 9.0) - Vector3.UP * 2.0
			else:
				var a := PI * float(k - 1) / arc
				var lump := 0.5 * sin(d * 0.4 + k * 2.1) + 0.3 * sin(d * 0.17 + k)
				var dir := f.basis.x * cos(a) + Vector3.UP * sin(a) * 0.68
				p_in = f.origin + dir * (ri + lump * 0.4)
				# Outside: a broad grassy hill rather than a tube.
				p_out = f.origin + f.basis.x * cos(a) * (ri + 7.0) + Vector3.UP * (sin(a) * (ri * 0.68 + 3.5) + lump)
			inner.append(p_in)
			outer.append(p_out)
		rings.append([inner, outer])
		d += 3.0
	var cave_rock := Color(0.34, 0.31, 0.46)
	for r in rings.size() - 1:
		var a_in: Array = rings[r][0]
		var b_in: Array = rings[r + 1][0]
		var a_out: Array = rings[r][1]
		var b_out: Array = rings[r + 1][1]
		for k in a_in.size() - 1:
			_quad(inner_st, a_in[k], b_in[k], b_in[k + 1], a_in[k + 1], cave_rock.darkened(0.15 * float(k % 3)))
			# Rock low down, grass over the top of the hill.
			var up := float(min(k, a_in.size() - 2 - k)) / (a_in.size() * 0.5)
			var col := Color(0.6, 0.58, 0.55).lerp(Color(0.42, 0.78, 0.3), smoothstep(0.35, 0.6, up))
			_quad(outer_st, a_out[k], a_out[k + 1], b_out[k + 1], b_out[k], col)
	for e in [0, rings.size() - 1]:
		var ins: Array = rings[e][0]
		var outs: Array = rings[e][1]
		for k in ins.size() - 1:
			if e == 0:
				_quad(inner_st, ins[k], ins[k + 1], outs[k + 1], outs[k], Color(0.5, 0.47, 0.45))
			else:
				_quad(inner_st, ins[k], outs[k], outs[k + 1], ins[k + 1], Color(0.5, 0.47, 0.45))
	_commit(t, inner_st, _rock_mat(), true, "rock")
	_commit(t, outer_st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "rock", 6.0))
	# Darker road inside.
	var dark := _new_st()
	d = d0 + 1.0
	while d < d1 - 1.0:
		var fa := t.branch_frame(d)
		var fb := t.branch_frame(d + 2.0)
		var hw := Track.ROAD_WIDTH * 0.5 + 1.2
		var depth := clampf(minf(d - d0, d1 - d) / 8.0, 0.0, 1.0)
		var c := Color(0.02, 0.0, 0.08, 0.62 * depth)
		var lift := Vector3.UP * 0.075
		_quad(dark, fa.origin - fa.basis.x * hw + lift, fb.origin - fb.basis.x * hw + lift, fb.origin + fb.basis.x * hw + lift, fa.origin + fa.basis.x * hw + lift, c)
		d += 2.0
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_commit(t, dark, dm)
	# Neon life: mushrooms along the walls, crystals on the walls and roof.
	var glow := _new_st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var neon := [Color(0.2, 1.0, 0.95), Color(1.0, 0.3, 0.9), Color(0.6, 1.0, 0.25), Color(0.55, 0.5, 1.0)]
	d = d0 + 2.0
	while d < d1 - 2.0:
		var f := t.branch_frame(d)
		for side: float in [-1.0, 1.0]:
			# A cluster of mushrooms at the foot of the wall.
			var base := f.origin + f.basis.x * side * (ri - 0.7) + f.basis.z * rng.randf_range(-1.0, 1.0)
			var col: Color = neon[rng.randi() % neon.size()]
			for m in rng.randi_range(2, 4):
				var p := base + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
				var h := rng.randf_range(0.35, 0.9)
				_box(glow, Transform3D(Basis(), p + Vector3.UP * h * 0.5), Vector3(0.12, h, 0.12), Color(0.85, 0.9, 1.0))
				_box(glow, Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU), p + Vector3.UP * h), Vector3(0.5, 0.16, 0.5) * rng.randf_range(0.7, 1.3), col)
			# A crystal sticking out of the wall, angled up.
			var a := rng.randf_range(0.35, 1.2)
			var cpos := f.origin + f.basis.x * side * cos(a) * (ri + 0.4) + Vector3.UP * sin(a) * (ri + 0.4) * 0.68
			var cb := Basis.looking_at((f.origin + Vector3.UP * 2.0 - cpos).normalized(), Vector3.UP).rotated(f.basis.z, rng.randf_range(-0.3, 0.3))
			_box(glow, Transform3D(cb * Basis.from_scale(Vector3(0.35, 0.35, 1.5)), cpos), Vector3.ONE, neon[(rng.randi() + 1) % neon.size()])
		d += 3.0
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/neon.gdshader")
	_commit(t, glow, gm)
	# Coloured light from the glow, so karts inside light up too.
	var n := 4
	for i in n:
		var f := t.branch_frame(lerpf(d0, d1, (i + 0.5) / n))
		var light := OmniLight3D.new()
		light.light_color = neon[i % neon.size()]
		light.light_energy = 1.8
		light.omni_range = 12.0
		light.position = f.origin + Vector3.UP * 3.5
		t.add_child(light)
	# Crystal pillars near the walls to weave round.
	var pillars := _new_st()
	for u in [0.52, 0.56]:
		var f := t.branch_frame(lerpf(Track.BRANCH[0], Track.BRANCH[1], u))
		var sx := -1.0 if u < 0.54 else 1.0
		var p := f.origin + f.basis.x * sx * 5.3  # near the walls, so the racing line stays open
		_box(pillars, Transform3D(Basis().rotated(Vector3.UP, 0.4), p + Vector3.UP * 2.5), Vector3(1.3, 5.0, 1.3), neon[0] if sx < 0 else neon[1])
		_solid_cylinder(t, p, 0.8, 5.0)
	_commit(t, pillars, gm)


static func _ramp(t: Track, f: Transform3D, w: float, l: float, h: float) -> void:
	var pts := PackedVector3Array()
	for x in [-w / 2, w / 2]:
		pts.append(Vector3(x, 0.05, l / 2))
		pts.append(Vector3(x, 0.05, -l / 2))
		pts.append(Vector3(x, h, -l / 2))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var body := StaticBody3D.new()
	body.set_meta("surface", "asphalt")
	body.set_meta("floor", true)
	body.transform = f
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	t.add_child(body)
	var st := _new_st()
	var c := Color(0.3, 0.75, 1.0)
	var L := [Vector3(-w / 2, 0.05, l / 2), Vector3(-w / 2, 0.05, -l / 2), Vector3(-w / 2, h, -l / 2)]
	var R := [Vector3(w / 2, 0.05, l / 2), Vector3(w / 2, 0.05, -l / 2), Vector3(w / 2, h, -l / 2)]
	_quad(st, L[0], L[2], R[2], R[0], c)
	_quad(st, L[1], R[1], R[2], L[2], c.darkened(0.3))
	for v in [L[0], L[1], L[2]]:
		st.set_color(c.darkened(0.2))
		st.add_vertex(v)
	for v in [R[0], R[2], R[1]]:
		st.set_color(c.darkened(0.2))
		st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT)
	body.add_child(mi)


## Bleachers facing the road, full of fans who jump and cheer.
static func _bleachers(t: Track, d: float, side := 0.0) -> void:
	if side == 0.0:
		side = signf(t.bank_at(d)) if absf(t.bank_at(d)) > 0.01 else 1.0
		side = -side  # the outside of the corner
	# Slide back along the road until no part of the stand is near any road
	# (a corner further on can curve toward it: a bot kept hitting one).
	for attempt in 12:
		if _stand_clear(t, d, side):
			break
		d -= 8.0
	var f := t.transform_at(d)
	var face := f.basis.rotated(Vector3.UP, PI / 2 if side > 0 else -PI / 2)  # -Z faces the road
	var origin := f.origin + f.basis.x * side * (Track.ROAD_WIDTH * 0.5 + 9.0)
	origin.y = 0.0
	var st := _new_st()
	var tiers := 5
	var width := 18.0
	var wood := Color(0.86, 0.6, 0.36)
	for k in tiers:
		var y := 0.5 + k * 0.7
		var z := k * 1.1
		_box(st, Transform3D(face, origin + face * Vector3(0, y * 0.5, z)), Vector3(width, y, 1.1), wood if k % 2 == 0 else wood.darkened(0.08))
	_commit(t, st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "wood", 1.5))
	# A striped roof on metal posts.
	var roof := _new_st()
	var metal := Color(0.82, 0.84, 0.88)
	for x in [-width * 0.5 + 0.3, width * 0.5 - 0.3]:
		_box(roof, Transform3D(face, origin + face * Vector3(x, 3.6, tiers * 1.1 - 0.4)), Vector3(0.25, 7.2, 0.25), metal)
	for k in 6:
		var c := Color(0.96, 0.22, 0.25) if k % 2 == 0 else Color(1, 1, 1)
		_box(roof, Transform3D(face.rotated(face.x, -0.25), origin + face * Vector3(-width * 0.5 + width * (k + 0.5) / 6.0, 7.2, tiers * 0.55)), Vector3(width / 6.0, 0.15, tiers * 1.1 + 1.0), c)
	_commit(t, roof, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, tiers * 0.7 + 0.5, tiers * 1.1)
	col.shape = box
	col.transform = Transform3D(face, origin + face * Vector3(0, box.size.y * 0.5, tiers * 0.55 - 0.5))
	body.add_child(col)
	t.add_child(body)
	# The crowd: one draw call, everyone bobbing on their own beat.
	var people := []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d)
	for k in tiers:
		for n in 15:
			if rng.randf() < 0.15:
				continue
			var x := -width * 0.5 + 0.8 + (width - 1.6) * (n + rng.randf_range(-0.2, 0.2)) / 14.0
			people.append(origin + face * Vector3(x, 0.5 + k * 0.7, k * 1.1 - 0.1))
	_crowd(t, people, face)
	ground_shade(t, [[origin + face * Vector3(0, 0, 3.0), width * 0.45, 7.0]])
	t.keep_clear(origin + face * Vector3(0, 0, 3.0), 14.0)


static func _stand_clear(t: Track, d: float, side: float) -> bool:
	var f := t.transform_at(d)
	var face := f.basis.rotated(Vector3.UP, PI / 2 if side > 0 else -PI / 2)
	var origin := f.origin + f.basis.x * side * (Track.ROAD_WIDTH * 0.5 + 9.0)
	for x in [-9.5, 0.0, 9.5]:
		for z in [-1.0, 7.0]:
			if t.distance_to_road(origin + face * Vector3(x, 0, z)) < Track.ROAD_WIDTH * 0.5 + 4.0:
				return false
	return true


static func _crowd(t: Track, spots: Array, face: Basis) -> void:
	var st := _new_st()
	var body := CapsuleMesh.new()
	body.radius = 0.26
	body.height = 0.95
	body.radial_segments = 8
	body.rings = 2
	st.append_from(body, 0, Transform3D(Basis(), Vector3(0, 0.48, 0)))
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.44
	head.radial_segments = 8
	head.rings = 4
	st.append_from(head, 0, Transform3D(Basis(), Vector3(0, 1.12, 0)))
	var mesh := st.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = spots.size()
	var shirts := [Color(0.96, 0.22, 0.25), Color(1.0, 0.68, 0.1), Color(0.2, 0.55, 0.95), Color(0.3, 0.8, 0.4), Color(0.95, 0.95, 0.97), Color(0.75, 0.4, 0.9), Color(1.0, 0.5, 0.65)]
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(face.rotated(Vector3.UP, PI), spots[i]))
		mm.set_instance_color(i, shirts[(i * 7 + i / 3) % shirts.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crowd.gdshader")
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(mmi)


## Flags fluttering on poles along the start straight.
static func _start_flags(t: Track) -> void:
	var poles := _new_st()
	var cloth_mesh := QuadMesh.new()
	cloth_mesh.size = Vector2(2.2, 1.3)
	cloth_mesh.subdivide_width = 8
	cloth_mesh.subdivide_depth = 2
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flag.gdshader")
	var colors := [Color(0.96, 0.22, 0.25), Color(1.0, 0.68, 0.1), Color(0.2, 0.55, 0.95), Color(0.3, 0.8, 0.4)]
	var i := 0
	var d := t.length - 70.0
	while d < t.length + 26.0:
		var f := t.transform_at(fposmod(d, t.length))
		for s: float in [-1.0, 1.0]:
			if s == t.branch_side and fposmod(d, t.length) < 40.0 and fposmod(d, t.length) > Track.BRANCH[0] - 8.0:
				continue
			var base: Vector3 = f.origin + f.basis.x * s * (Track.ROAD_WIDTH * 0.5 + 4.2)
			base.y = 0.0
			_box(poles, Transform3D(f.basis, base + Vector3.UP * 3.0), Vector3(0.14, 6.0, 0.14), Color(0.85, 0.86, 0.9))
			var cloth := MeshInstance3D.new()
			cloth.mesh = cloth_mesh
			# The flag hangs off the pole, streaming backwards along the road.
			cloth.transform = Transform3D(f.basis.rotated(Vector3.UP, PI / 2), base + Vector3.UP * 5.2 + f.basis.z * 1.15)
			var m: ShaderMaterial = mat.duplicate()
			m.set_shader_parameter("color", colors[i % colors.size()])
			m.set_shader_parameter("phase", float(i) * 1.3)
			cloth.material_override = m
			cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			t.add_child(cloth)
			i += 1
		d += 16.0
	_commit(t, poles, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.METAL))


## Puffy clouds drifting slowly round the sky.
static func _clouds(t: Track) -> void:
	var st := _new_st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var center := Vector3(80, 0, -30)
	for c in 11:
		var a := TAU * c / 11.0 + rng.randf() * 0.3
		var r := rng.randf_range(260, 480)
		var p := center + Vector3(cos(a) * r, rng.randf_range(95, 150), sin(a) * r)
		for k in 5:
			var s := SphereMesh.new()
			var size := rng.randf_range(16, 28)
			s.radius = size
			s.height = size * 1.1
			s.radial_segments = 10
			s.rings = 5
			var off := Vector3(rng.randf_range(-30, 30), rng.randf_range(-3, 6), rng.randf_range(-12, 12))
			st.append_from(s, 0, Transform3D(Basis.from_scale(Vector3(1.4, 0.6, 1.0)).rotated(Vector3.UP, a), p + off.rotated(Vector3.UP, a)))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.55, 0.62, 0.75)
	m.disable_fog = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pivot := CloudDrift.new()
	pivot.position = center
	mi.position = -center
	pivot.add_child(mi)
	t.add_child(pivot)


static func _stone_mat() -> StandardMaterial3D:
	return Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "stone", 3.2)


static func _rock_mat() -> StandardMaterial3D:
	return Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.MATTE, "rock", 5.0)
