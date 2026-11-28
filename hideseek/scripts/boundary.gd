class_name Boundary
## The farm's edges (owner, 2026-11-27), each side its own look:
##   front (+z)  a white picket fence with an open gate, a dirt driveway from
##               the gate to the barn door, and a road with a mailbox outside
##   east (+x)   rows of cypress
##   back (-z)   a parked combine in front of about 3 m of standing corn
##   west (-x)   leafy trees
## Invisible walls taller than the fence keep everyone in, and a ring of trees
## sits on the horizon. Plants are instanced: one draw call per kind.

const FRONT := 31.0      # fence line (z)
const BACK := -30.4      # corn starts here (z), going back
const EAST := 31.2       # first cypress row (x)
const WEST := -31.0      # first leafy row (x)
const GATE := 1.6        # half width of the gate opening
const WALL_H := 4.0      # the invisible walls; the fence is 1 m
const COMBINE := Vector3(-8.0, 0.0, -26.5)   # facing the yard


static func build(root: Node3D, b: Surfaces.Builder, solid: StaticBody3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	_fence(b)
	_driveway_and_road(b)
	_walls(solid)
	_combine(root, solid)
	_plants(root, rng)


# --------------------------------------------------------------- front --

static func _fence(b: Surfaces.Builder) -> void:
	var z := FRONT
	var x0 := WEST + 0.5
	var x1 := EAST - 0.2
	for run in [[x0, -GATE], [GATE, x1]]:
		var a: float = run[0]
		var e: float = run[1]
		var mid := (a + e) / 2
		for y in [0.3, 0.75]:
			_box(b, "trim", Vector3(e - a, 0.08, 0.04), Vector3(mid, y, z - 0.03))
		var n := int((e - a) / 2.4)
		for i in n + 1:
			_box(b, "trim", Vector3(0.1, 1.15, 0.1), Vector3(lerpf(a, e, float(i) / n), 0.575, z - 0.07))
		var count := int((e - a) / 0.16)
		for i in count:
			_picket(b, Vector3(a + 0.08 + i * (e - a - 0.16) / (count - 1), 0, z), Basis())
	# The gate: two leaves swung open outwards, towards the road.
	for side in [-1.0, 1.0]:
		var hinge := Vector3(side * GATE, 0, z)
		var basis := Basis(Vector3.UP, side * 1.35)
		var along := basis * Vector3(-side, 0, 0)
		for y in [0.3, 0.75]:
			_box(b, "trim", Vector3(GATE - 0.1, 0.08, 0.04), hinge + along * (GATE / 2) + Vector3(0, y, 0), basis)
		_box(b, "trim", Vector3(GATE * 1.08, 0.06, 0.03), hinge + along * (GATE / 2) + Vector3(0, 0.52, 0), basis * Basis(Vector3.BACK, side * 0.3))
		for i in 9:
			_picket(b, hinge + along * (0.12 + i * (GATE - 0.25) / 8), basis)
	# Gate posts, a bit taller.
	for side in [-1.0, 1.0]:
		_box(b, "trim", Vector3(0.14, 1.35, 0.14), Vector3(side * (GATE + 0.06), 0.675, z - 0.07))
		_box(b, "trim", Vector3(0.2, 0.06, 0.2), Vector3(side * (GATE + 0.06), 1.38, z - 0.07))


## One picket: a board with a pointed top.
static func _picket(b: Surfaces.Builder, at: Vector3, basis: Basis) -> void:
	_box(b, "trim", Vector3(0.09, 0.92, 0.025), at + Vector3(0, 0.46, 0), basis)
	_box(b, "trim", Vector3(0.064, 0.064, 0.025), at + Vector3(0, 0.92, 0), basis * Basis(Vector3.BACK, PI / 4))


static func _driveway_and_road(b: Surfaces.Builder) -> void:
	# Packed dirt from the barn's south door out through the gate to the road.
	_box(b, "dirt", Vector3(3.0, 0.02, FRONT + 2.2 - 16.9), Vector3(0, 0.01, (16.9 + FRONT + 2.2) / 2))
	# The road: asphalt along x, a dashed centre line, white edges.
	var rz := FRONT + 5.2
	_box(b, "asphalt", Vector3(600, 0.03, 6.0), Vector3(0, 0.012, rz))
	for edge in [-2.75, 2.75]:
		_box(b, "road_white", Vector3(600, 0.01, 0.12), Vector3(0, 0.03, rz + edge))
	for i in range(-25, 26):
		_box(b, "road_yellow", Vector3(3.0, 0.01, 0.12), Vector3(i * 6.0, 0.03, rz))
	# Mailbox by the gate, on the road side of the fence.
	var m := Vector3(GATE + 1.3, 0, FRONT + 1.4)
	_box(b, "handle", Vector3(0.1, 1.05, 0.1), m + Vector3(0, 0.525, 0))
	_box(b, "handle", Vector3(0.18, 0.04, 0.5), m + Vector3(0, 1.07, 0))
	_box(b, "metal", Vector3(0.24, 0.2, 0.48), m + Vector3(0, 1.19, 0))
	_box(b, "metal", Vector3(0.17, 0.17, 0.48), m + Vector3(0, 1.29, 0), Basis(Vector3.BACK, PI / 4))
	_box(b, "toolbox", Vector3(0.02, 0.24, 0.05), m + Vector3(0.13, 1.33, -0.1))
	_box(b, "toolbox", Vector3(0.02, 0.07, 0.13), m + Vector3(0.13, 1.42, -0.04))


static func _box(b: Surfaces.Builder, surf: String, size: Vector3, at: Vector3, basis := Basis()) -> void:
	b.box(surf, size, at, basis)


# --------------------------------------------------------------- walls --

## Invisible walls round the play area, taller than the fence so nobody can
## jump out.
static func _walls(solid: StaticBody3D) -> void:
	var w := WALL_H
	var fx := (EAST - 0.4 + WEST + 0.4) / 2
	var span_x := (EAST - 0.4) - (WEST + 0.4)
	var span_z := (FRONT + 0.3) - (BACK + 0.3)
	var fz := (FRONT + 0.3 + BACK + 0.3) / 2
	for box in [
		[Vector3(span_x + 2, w, 1), Vector3(fx, w / 2, FRONT + 0.3 + 0.5)],
		[Vector3(span_x + 2, w, 1), Vector3(fx, w / 2, BACK + 0.3 - 0.5)],
		[Vector3(1, w, span_z + 2), Vector3(EAST - 0.4 + 0.5, w / 2, fz)],
		[Vector3(1, w, span_z + 2), Vector3(WEST + 0.4 - 0.5, w / 2, fz)],
	]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box[0]
		cs.shape = bs
		cs.position = box[1]
		cs.name = "Bound"
		solid.add_child(cs)


# --------------------------------------------------------------- combine --

## The combine (tools/blender/props.py), parked facing the yard, with solid
## boxes for its body and header. Scenery only: not a hider prop.
static func _combine(root: Node3D, solid: StaticBody3D) -> void:
	var path := "res://assets/models/combine.glb"
	if not ResourceLoader.exists(path):
		return
	var inst := (load(path) as PackedScene).instantiate()
	var mi := inst.find_children("*", "MeshInstance3D", true, false)
	if mi.is_empty():
		inst.free()
		return
	var m := MeshInstance3D.new()
	m.name = "Combine"
	m.mesh = (mi[0] as MeshInstance3D).mesh
	var own := (mi[0] as Node3D).transform
	inst.free()
	m.transform = Transform3D(Basis(Vector3.UP, PI), COMBINE) * own
	root.add_child(m)
	# Model +Y (Blender) is forward; turned to face +z here.
	for box in [[Vector3(3.6, 4.2, 5.2), Vector3(0, 2.1, -0.85)], [Vector3(5.0, 1.4, 1.6), Vector3(0, 0.7, 3.15)], [Vector3(1.3, 1.6, 1.4), Vector3(0, 0.8, 2.0)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box[0]
		cs.shape = bs
		cs.position = COMBINE + box[1]
		solid.add_child(cs)


# --------------------------------------------------------------- plants --

static func _plants(root: Node3D, rng: RandomNumberGenerator) -> void:
	var cypress := []
	for row in 2:
		var x := EAST + row * 1.5
		var z := -33.0 + row * 1.1
		while z < 34.0:
			cypress.append(_xf(rng, Vector3(x + rng.randf_range(-0.15, 0.15), 0, z), rng.randf_range(0.85, 1.15)))
			z += 2.2
	_instances(root, "Cypress", _cypress_mesh(), cypress, true, rng, 0.08)
	var leafy := []
	var z := -33.0
	while z < 34.0:
		leafy.append(_xf(rng, Vector3(WEST - rng.randf_range(0.2, 1.0), 0, z), rng.randf_range(0.8, 1.2)))
		leafy.append(_xf(rng, Vector3(WEST - rng.randf_range(2.6, 3.6), 0, z + 2.3), rng.randf_range(0.85, 1.25)))
		z += rng.randf_range(4.0, 5.0)
	_instances(root, "LeafyTrees", _leafy_mesh(), leafy, true, rng, 0.1)
	var corn := []
	for row in 6:
		var cz := BACK - 0.3 - row * 0.62
		var x := WEST + 1.2 + rng.randf_range(0, 0.3)
		while x < EAST - 0.8:
			corn.append(_xf(rng, Vector3(x, 0, cz + rng.randf_range(-0.08, 0.08)), rng.randf_range(0.85, 1.1)))
			x += rng.randf_range(0.28, 0.42)
	_instances(root, "Corn", _corn_mesh(), corn, false, rng, 0.06)
	var far := []
	for i in 260:
		var a := TAU * i / 260 + rng.randf_range(-0.01, 0.01)
		var r := rng.randf_range(150.0, 200.0)
		far.append(_xf(rng, Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(2.2, 3.4)))
	_instances(root, "HorizonTrees", _far_mesh(), far, false, rng, 0.12)


static func _xf(rng: RandomNumberGenerator, at: Vector3, s: float) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.92, 1.08), s))
	return Transform3D(basis, at)


static func _instances(root: Node3D, name: String, mesh: Mesh, xforms: Array, shadows: bool, rng: RandomNumberGenerator, tint: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var k := 1.0 + rng.randf_range(-tint, tint)
		mm.set_instance_color(i, Color(k * rng.randf_range(0.96, 1.04), k, k * rng.randf_range(0.94, 1.02)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


# Plant meshes: vertex-coloured, one surface each.

static func _material(double_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A lumpy ellipsoid: radius jittered per vertex (seam-safe) for foliage.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, segs: int, rings: int, lump: float, seed_: int) -> void:
	var pts := []
	for j in rings + 1:
		var row := []
		var v := PI * j / rings
		for i in segs + 1:
			var u := TAU * (i % segs) / segs
			var n := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
			var k := 1.0
			if j > 0 and j < rings:
				k += lump * (fmod(sin(float((i % segs) * 12.9898 + j * 78.233 + seed_)) * 43758.5453, 1.0) - 0.5) * 2.0
			row.append(c + n * r * k)
		pts.append(row)
	for j in rings:
		var shade := lerpf(0.72, 1.12, 1.0 - float(j) / rings)
		var cc := Color(col.r * shade, col.g * shade, col.b * shade)
		for i in segs:
			var a: Vector3 = pts[j][i]
			var b_: Vector3 = pts[j][i + 1]
			var c_: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			for p in [a, d, c_, a, c_, b_]:
				st.set_color(cc)
				st.set_normal(((p - c) / (r * r)).normalized())
				st.add_vertex(p)


static func _trunk(st: SurfaceTool, base: Vector3, r: float, h: float, col: Color) -> void:
	var segs := 6
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var q := [base + p0 * r, base + p0 * r * 0.7 + Vector3(0, h, 0), base + p1 * r * 0.7 + Vector3(0, h, 0), base + p1 * r]
		var ns := [p0, p0, p1, p1]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(ns[k])
			st.add_vertex(q[k])


static func _commit(st: SurfaceTool, double_sided := false) -> Mesh:
	st.set_material(_material(double_sided))
	return st.commit()


static func _cypress_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, Vector3.ZERO, 0.16, 0.9, Color(0.32, 0.23, 0.16))
	_blob(st, Vector3(0, 3.4, 0), Vector3(0.95, 3.0, 0.95), Color(0.16, 0.3, 0.15), 9, 8, 0.1, 1)
	_blob(st, Vector3(0, 6.2, 0), Vector3(0.45, 0.9, 0.45), Color(0.17, 0.32, 0.16), 7, 5, 0.1, 2)
	return _commit(st)


static func _leafy_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, Vector3.ZERO, 0.28, 3.2, Color(0.36, 0.27, 0.19))
	var green := Color(0.3, 0.48, 0.2)
	_blob(st, Vector3(0, 4.6, 0), Vector3(2.4, 2.0, 2.4), green, 10, 7, 0.14, 3)
	_blob(st, Vector3(1.3, 4.0, 0.6), Vector3(1.6, 1.4, 1.6), green * 0.95, 8, 6, 0.14, 4)
	_blob(st, Vector3(-1.1, 4.2, -0.9), Vector3(1.7, 1.5, 1.7), green * 1.05, 8, 6, 0.14, 5)
	_blob(st, Vector3(0.2, 6.0, 0.1), Vector3(1.5, 1.2, 1.5), green * 1.08, 8, 6, 0.14, 6)
	return _commit(st)


static func _far_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, Vector3.ZERO, 0.3, 2.0, Color(0.36, 0.36, 0.36))
	# Hazy blue-green: far away.
	_blob(st, Vector3(0, 3.6, 0), Vector3(2.4, 2.2, 2.4), Color(0.4, 0.5, 0.44), 7, 5, 0.15, 7)
	_blob(st, Vector3(1.4, 3.0, 0.4), Vector3(1.6, 1.4, 1.6), Color(0.38, 0.48, 0.42), 6, 4, 0.15, 8)
	return _commit(st)


## A corn plant late in summer: a stalk, drooping leaves, an ear and a
## tassel. Double-sided, no shadows.
static func _corn_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stalk := Color(0.52, 0.56, 0.24)
	var h := 2.2
	# Stalk: a thin square column.
	for i in 4:
		var a0 := Vector3(0.025, 0, 0).rotated(Vector3.UP, i * PI / 2 + PI / 4)
		var a1 := Vector3(0.025, 0, 0).rotated(Vector3.UP, (i + 1) * PI / 2 + PI / 4)
		var n := ((a0 + a1) / 2).normalized()
		for p in [a0, a0 * 0.6 + Vector3(0, h, 0), a1 * 0.6 + Vector3(0, h, 0), a0, a1 * 0.6 + Vector3(0, h, 0), a1]:
			_v(st, p, n, stalk)
	# Leaves: long blades rising then drooping, spiralling up the stalk.
	for k in 7:
		var y := 0.45 + k * 0.24
		var dir := Vector3.RIGHT.rotated(Vector3.UP, k * 2.4)
		var side := dir.cross(Vector3.UP) * 0.05
		var len: float = 0.75 - absf(k - 3) * 0.06
		var base := Vector3(0, y, 0)
		var mid: Vector3 = base + dir * len * 0.5 + Vector3(0, 0.22, 0)
		var tip: Vector3 = base + dir * len + Vector3(0, -0.05, 0)
		var c0 := Color(0.36, 0.5, 0.17)
		var c1 := Color(0.66, 0.64, 0.3)
		var up := Vector3.UP
		_v(st, base - side, up, c0); _v(st, mid - side * 0.8, up, c0); _v(st, mid + side * 0.8, up, c0)
		_v(st, base - side, up, c0); _v(st, mid + side * 0.8, up, c0); _v(st, base + side, up, c0)
		_v(st, mid - side * 0.8, up, c0); _v(st, tip, up, c1); _v(st, mid + side * 0.8, up, c0)
	# An ear in its husk, and the tassel.
	var ear := Vector3(0.06, 1.15, 0)
	for i in 4:
		var a0 := Vector3(0.045, 0, 0).rotated(Vector3.UP, i * PI / 2)
		var a1 := Vector3(0.045, 0, 0).rotated(Vector3.UP, (i + 1) * PI / 2)
		var n := ((a0 + a1) / 2).normalized()
		var top := ear + Vector3(0.05, 0.32, 0)
		for p in [ear + a0, top, ear + a1]:
			_v(st, p, n, Color(0.7, 0.68, 0.36))
	for i in 5:
		var d := Vector3(0.14, 0.22, 0).rotated(Vector3.UP, i * TAU / 5)
		_v(st, Vector3(0, h - 0.05, 0), Vector3.UP, Color(0.72, 0.6, 0.34))
		_v(st, Vector3(0, h + 0.3, 0), Vector3.UP, Color(0.8, 0.68, 0.4))
		_v(st, Vector3(0, h - 0.05, 0) + d, Vector3.UP, Color(0.76, 0.62, 0.36))
	return _commit(st, true)


static func _v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.add_vertex(p)
