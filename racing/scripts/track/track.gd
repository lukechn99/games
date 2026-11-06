class_name Track
extends Node3D
## A track built from a racing line (design doc 8.1). The line gives us the
## road mesh, surfaces, checkpoints, respawn points, the minimap and the
## path bots follow, so a new track is mostly a new set of points.
##
## This one is the M0 test loop: a "highway" start straight with guardrails,
## an ice patch, a dirt section, a jump and plenty of trees to hit.

const ROAD_WIDTH := 14.0
const CHECKPOINTS := 12
const KIT_RACING := "res://assets/vendor/kenney_racing_kit/"
const KIT_NATURE := "res://assets/vendor/kenney_nature_kit/"

## Racing line, in metres, clockwise. y is height.
## The far side climbs a hill (up to 7 m), drops down past the ice and
## crests before the jump; the start straight stays at ground level.
const POINTS := [
	Vector3(0, 0, 40), Vector3(0, 0, -60), Vector3(0, 0.5, -140), Vector3(25, 2.5, -190), Vector3(80, 5.5, -205),
	Vector3(135, 7, -180), Vector3(150, 6, -125), Vector3(150, 3.5, -70), Vector3(185, 2.5, -25),
	Vector3(210, 2.5, 35), Vector3(190, 2.5, 85), Vector3(140, 1.5, 95), Vector3(105, 0.5, 65),
	Vector3(70, 0, 95), Vector3(40, 0, 140), Vector3(0, 0, 130),
]
## Corners bank toward the inside, up to this angle, set by how sharp they are.
const MAX_BANK := deg_to_rad(15.0)
const BANK_PER_TURN := 6.5   # bank (radians) per radian-per-metre of turn
const SLOPE := 2.5           # embankments drop 1 m for every 2.5 m outward
## Stretches of the lap with their own surface: [from, to] as fractions of the lap.
const SURFACE_ZONES := [
	{"from": 0.405, "to": 0.475, "surface": "ice"},
	{"from": 0.68, "to": 0.76, "surface": "dirt"},
	{"from": 0.145, "to": 0.16, "surface": "boost"},
]
## Where guardrails run along the road (the "highway"), as lap fractions.
const RAIL_ZONES := [[0.0, 0.17], [0.93, 1.0], [0.52, 0.62]]
const JUMP_AT := 0.59
const LAPS := 3

var curve := Curve3D.new()
var length := 0.0
var laps := LAPS
var trees_hit_radius := 26.0
var _samples: Array[Transform3D] = []   # every 2 m along the line
var _bank: PackedFloat32Array = []       # bank angle every 2 m
var _skirt: PackedFloat32Array = []      # embankment width every 2 m
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 42
	_build_curve()
	_build_ground()
	_build_road()
	_build_rails()
	_build_jump()
	_build_start()
	_build_scenery()


func _build_curve() -> void:
	var n := POINTS.size()
	for i in n + 1:
		var p: Vector3 = POINTS[i % n]
		var prev: Vector3 = POINTS[(i - 1 + n) % n]
		var next: Vector3 = POINTS[(i + 1) % n]
		var handle := (next - prev) / 6.0
		curve.add_point(p, -handle, handle)
	curve.bake_interval = 1.0
	length = curve.get_baked_length()
	# Bank each corner by how sharply the line turns, smoothed so the road
	# rolls in and out of corners gradually.
	var raw: Array[float] = []
	var d := 0.0
	while d < length:
		var a := _flat_dir(d - 8.0)
		var b := _flat_dir(d + 8.0)
		raw.append(clampf(a.signed_angle_to(b, Vector3.UP) / 16.0 * BANK_PER_TURN, -MAX_BANK, MAX_BANK))
		d += 2.0
	var n_s := raw.size()
	_bank.resize(n_s)
	for i in n_s:
		var acc := 0.0
		for k in range(-6, 7):
			acc += raw[(i + k + n_s) % n_s]
		_bank[i] = acc / 13.0
	_skirt.resize(n_s)
	d = 0.0
	while d < length:
		_samples.append(transform_at(d))
		d += 2.0


func _flat_dir(offset: float) -> Vector3:
	var p := curve.sample_baked(fposmod(offset, length), true)
	var ahead := curve.sample_baked(fposmod(offset + 1.0, length), true)
	var f := ahead - p
	f.y = 0.0
	return f.normalized()


## Bank angle at `offset` (positive tips the right edge up, for left turns).
func bank_at(offset: float) -> float:
	if _bank.is_empty():
		return 0.0
	var x := fposmod(offset, length) / 2.0
	var i := int(x) % _bank.size()
	return lerpf(_bank[i], _bank[(i + 1) % _bank.size()], x - floorf(x))


## Position and facing on the racing line at `offset` metres. The facing is
## level; the position is lifted on banked corners so the low edge of the
## road meets the ground instead of sinking into it.
func transform_at(offset: float) -> Transform3D:
	offset = fposmod(offset, length)
	var p := curve.sample_baked(offset, true)
	var bank := bank_at(offset)
	p.y = maxf(p.y, sin(absf(bank)) * (ROAD_WIDTH * 0.5 + 1.1))
	var basis := Basis.looking_at(_flat_dir(offset), Vector3.UP)
	return Transform3D(basis, p)


## Like transform_at, but `basis.x` follows the road's bank (for building it).
func road_frame(offset: float) -> Transform3D:
	var t := transform_at(offset)
	var b := bank_at(offset)
	var right := t.basis.x * cos(b) + Vector3.UP * sin(b)
	t.basis = Basis(right, t.basis.z.cross(right).normalized(), t.basis.z)
	return t


func offset_of(pos: Vector3) -> float:
	return curve.get_closest_offset(pos)


func surface_at_fraction(f: float) -> String:
	for z in SURFACE_ZONES:
		if f >= z["from"] and f < z["to"]:
			return z["surface"]
	return "asphalt"


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return m


func _body(surface: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta("surface", surface)
	add_child(b)
	return b


func _build_ground() -> void:
	var b := _body("grass")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1400, 2, 1400)
	shape.shape = box
	shape.position = Vector3(80, -1, -30)
	b.add_child(shape)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(80, 0, -30)
	mi.material_override = _mat(Parts.surface("grass")["color"])
	b.add_child(mi)


## The road ribbon, split into one body per surface so the physics knows what
## each wheel is on. Kerbs on the edges are painted into the same mesh.
func _build_road() -> void:
	var groups := {}
	var step := 2.0
	var d := 0.0
	while d < length:
		var f := d / length
		var s := surface_at_fraction(f)
		if not groups.has(s):
			groups[s] = SurfaceTool.new()
			(groups[s] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
		var st: SurfaceTool = groups[s]
		var a := road_frame(d)
		var b := road_frame(minf(d + step, length))
		_quad_strip(st, a, b, s, int(d / step))
		if not groups.has("grass"):
			groups["grass"] = SurfaceTool.new()
			(groups["grass"] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
		_embankment(groups["grass"], a, b, int(d / step))
		d += step
	for s in groups:
		var st: SurfaceTool = groups[s]
		st.generate_normals()
		var mesh := st.commit()
		var body := _body(s)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat(Color.WHITE)
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var shape := mesh.create_trimesh_shape()
		# Solid from both sides, so nothing can slip through the road or the
		# banks and end up underneath.
		shape.backface_collision = true
		col.shape = shape
		body.add_child(col)


## Where the road sits above the ground, a grassy bank slopes down to meet it.
func _embankment(st: SurfaceTool, a: Transform3D, b: Transform3D, index: int) -> void:
	var edge := ROAD_WIDTH * 0.5 + 1.1
	var widest := 0.0
	for side in [-1.0, 1.0]:
		var ea: Vector3 = a.origin + a.basis.x * side * edge
		var eb: Vector3 = b.origin + b.basis.x * side * edge
		var h := maxf(ea.y, eb.y)
		if h < 0.08:
			continue
		var out_a: Vector3 = (a.basis.x * Vector3(1, 0, 1)).normalized() * side
		var out_b: Vector3 = (b.basis.x * Vector3(1, 0, 1)).normalized() * side
		var w := h * SLOPE + 1.0
		widest = maxf(widest, w)
		var ga := Vector3(ea.x, -0.02, ea.z) + out_a * w
		var gb := Vector3(eb.x, -0.02, eb.z) + out_b * w
		var c: Color = Parts.surface("grass")["color"]
		c = c.darkened(0.06) if index % 2 == 0 else c
		var tri := [ea, ga, gb, ea, gb, eb] if side > 0 else [ea, gb, ga, ea, eb, gb]
		for v in tri:
			st.set_color(c)
			st.add_vertex(v)
	if index < _skirt.size():
		_skirt[index] = widest


func _quad_strip(st: SurfaceTool, a: Transform3D, b: Transform3D, s: String, index: int) -> void:
	var half := ROAD_WIDTH * 0.5
	var base: Color = Parts.surface(s)["color"]
	var lift := Vector3.UP * 0.04
	# Road, then a kerb on each side (red and white blocks every 2 m).
	var kerb := Color(0.92, 0.22, 0.2) if index % 2 == 0 else Color(0.97, 0.97, 0.97)
	var bands := [[-half, half, base], [-half - 1.1, -half, kerb], [half, half + 1.1, kerb]]
	for band in bands:
		var c: Color = band[2]
		var p0 := a.origin + a.basis.x * float(band[0]) + lift
		var p1 := a.origin + a.basis.x * float(band[1]) + lift
		var p2 := b.origin + b.basis.x * float(band[1]) + lift
		var p3 := b.origin + b.basis.x * float(band[0]) + lift
		# Subtle stripes so speed reads on a plain road.
		if band[0] == -half and s == "asphalt" and index % 8 == 0:
			c = c.lightened(0.05)
		for v in [p0, p2, p1, p0, p3, p2]:
			st.set_color(c)
			st.add_vertex(v)


## A basis with a local scale (the kit's models are 1 unit; we scale them up).
func _sl(b: Basis, s: Vector3) -> Basis:
	return b * Basis.from_scale(s)


func _mesh_of(path: String) -> Mesh:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var root := scene.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			found = (n as MeshInstance3D).mesh
		stack.append_array(n.get_children())
	root.free()
	return found


## Many copies of one model in a single draw call (design doc 9.1).
func _scatter(path: String, xforms: Array[Transform3D]) -> void:
	var mesh := _mesh_of(path)
	if mesh == null or xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Palette.restyle(mesh)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


func _in_rail_zone(f: float) -> bool:
	for z in RAIL_ZONES:
		if f >= z[0] and f <= z[1]:
			return true
	return false


## Guardrails along the highway stretches: solid, low friction so karts
## scrape along them instead of stopping dead (design doc 8.2).
func _build_rails() -> void:
	var visuals: Array[Transform3D] = []
	var body := _body("asphalt")
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 0.2
	body.physics_material_override = mat
	var seg := 4.0
	var d := 0.0
	while d < length:
		var f := d / length
		if _in_rail_zone(f):
			var a := road_frame(d)
			for side in [-1.0, 1.0]:
				var pos: Vector3 = a.origin + a.basis.x * side * (ROAD_WIDTH * 0.5 + 1.8)
				var col := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(0.4, 1.2, seg + 0.4)
				col.shape = box
				col.transform = Transform3D(a.basis, pos + Vector3.UP * 0.6)
				body.add_child(col)
				# The kit's rail is 1 unit long along -Z and 0.28 tall.
				var vis := Transform3D(_sl(a.basis, Vector3(6.0, 3.6, seg)), pos + a.basis.z * (seg * 0.5) - a.basis.x * side * 0.15)
				visuals.append(vis)
		d += seg
	_scatter(KIT_RACING + "railDouble.glb", visuals)


func _build_jump() -> void:
	var d := JUMP_AT * length
	var a := road_frame(d)
	var w := ROAD_WIDTH * 0.8
	var l := 7.0
	var h := 1.3
	var pts := PackedVector3Array()
	for x in [-w / 2, w / 2]:
		pts.append(Vector3(x, 0.04, l / 2))
		pts.append(Vector3(x, 0.04, -l / 2))
		pts.append(Vector3(x, h, -l / 2))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var body := _body("asphalt")
	body.transform = a
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.98, 0.75, 0.2)
	var L := [Vector3(-w / 2, 0.04, l / 2), Vector3(-w / 2, 0.04, -l / 2), Vector3(-w / 2, h, -l / 2)]
	var R := [Vector3(w / 2, 0.04, l / 2), Vector3(w / 2, 0.04, -l / 2), Vector3(w / 2, h, -l / 2)]
	for tri in [[L[0], L[2], R[2]], [L[0], R[2], R[0]], [L[1], R[1], R[2]], [L[1], R[2], L[2]], [L[0], L[1], L[2]], [R[0], R[2], R[1]]]:
		for v in tri:
			st.set_color(c if v.y > 0.1 or tri == [L[0], L[2], R[2]] else c.darkened(0.3))
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color.WHITE)
	body.add_child(mi)


func _place(path: String, xf: Transform3D) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var n: Node3D = scene.instantiate()
	n.transform = xf
	Palette.restyle_tree(n)
	add_child(n)


func _build_start() -> void:
	var a := transform_at(0.0)
	# Checkered start line painted across the road.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 14
	for i in cells:
		for j in 2:
			var c := Color.WHITE if (i + j) % 2 == 0 else Color(0.1, 0.1, 0.12)
			var x0 := -ROAD_WIDTH / 2 + ROAD_WIDTH * i / cells
			var x1 := x0 + ROAD_WIDTH / cells
			var z0 := -0.5 + j * 0.5
			var z1 := z0 + 0.5
			for v in [Vector3(x0, 0.06, z0), Vector3(x1, 0.06, z1), Vector3(x1, 0.06, z0), Vector3(x0, 0.06, z0), Vector3(x0, 0.06, z1), Vector3(x1, 0.06, z1)]:
				st.set_color(c)
				st.add_vertex(a * v)
	st.generate_normals()
	var line := MeshInstance3D.new()
	line.mesh = st.commit()
	line.material_override = _mat(Color.WHITE)
	add_child(line)
	# Overhead banner (the kit's is ~1.26 wide), towers, flags, a grandstand.
	var s := (ROAD_WIDTH + 4.0) / 1.26
	_place(KIT_RACING + "overhead.glb", Transform3D(_sl(a.basis, Vector3(s, s * 0.9, s)), a.origin - a.basis.x * (ROAD_WIDTH / 2 + 2.0) + a.basis.x * 0.16 * s))
	for side in [-1.0, 1.0]:
		_place(KIT_RACING + "flagCheckers.glb", Transform3D(_sl(a.basis, Vector3.ONE * 3.0), a.origin + a.basis.x * side * (ROAD_WIDTH / 2 + 3.0) + a.basis.z * 6.0))
	# Grandstands face the road from beyond the guardrail. The kit's stand is
	# 1×1 with its back along +X, so turn it to face the track.
	for spot in [[length - 45.0, 1.0], [30.0, 1.0], [length - 20.0, -1.0]]:
		var st_xf := transform_at(spot[0])
		var side: float = spot[1]
		var facing := st_xf.basis.rotated(Vector3.UP, -PI / 2 if side > 0 else PI / 2)
		_place(KIT_RACING + "grandStand.glb", Transform3D(_sl(facing, Vector3(14.0, 7.0, 7.0)), st_xf.origin + st_xf.basis.x * side * (ROAD_WIDTH / 2 + 9.0) - st_xf.basis.z * 7.0))
	var tents := transform_at(length - 95.0)
	_place(KIT_RACING + "tentLong.glb", Transform3D(_sl(tents.basis.rotated(Vector3.UP, -PI / 2), Vector3.ONE * 4.0), tents.origin - tents.basis.x * (ROAD_WIDTH / 2 + 14.0)))
	# Cones marking the inside of the first corner.
	var cones: Array[Transform3D] = []
	for k in 8:
		var c := transform_at(length * 0.12 + k * 6.0)
		cones.append(Transform3D(_sl(c.basis, Vector3.ONE * 5.0), c.origin + c.basis.x * (ROAD_WIDTH / 2 + 0.6)))
	_scatter(KIT_RACING + "pylon.glb", cones)


## Distance from the road's centre line, minus any embankment there, so
## scenery never ends up buried in a bank or floating over one.
func _distance_to_line(p: Vector3) -> float:
	var best := INF
	for i in _samples.size():
		var s := _samples[i]
		var dd := Vector2(p.x - s.origin.x, p.z - s.origin.z).length() - (_skirt[i] if i < _skirt.size() else 0.0)
		if dd < best:
			best = dd
	return best


## Background and scenery (design doc 8.2): far mountains, trees and rocks.
## Trees and rocks near the road are solid: drive off line and you'll hit one.
func _build_scenery() -> void:
	var kinds := ["tree_default", "tree_oak", "tree_fat", "tree_pineRoundA", "tree_pineRoundB", "tree_pineTallA", "tree_simple", "tree_cone"]
	var trees := {}
	for k in kinds:
		trees[k] = [] as Array[Transform3D]
	var rocks: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var flowers: Array[Transform3D] = []
	var solid := _body("grass")
	var tries := 0
	var placed := 0
	while placed < 340 and tries < 4000:
		tries += 1
		var p := Vector3(_rng.randf_range(-260, 420), 0, _rng.randf_range(-420, 360))
		var dist := _distance_to_line(p)
		if dist < ROAD_WIDTH * 0.5 + 7.0:
			continue
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var sc := _rng.randf_range(5.5, 8.5)
		(trees[kind] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p))
		if dist < trees_hit_radius:
			var col := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.06 * sc  # about the trunk, not the leaves
			cyl.height = 6.0
			col.shape = cyl
			col.position = p + Vector3.UP * 3.0
			solid.add_child(col)
		placed += 1
	for k in kinds:
		var arr: Array[Transform3D] = []
		arr.assign(trees[k])
		_scatter(KIT_NATURE + k + ".glb", arr)
	for i in 70:
		var p := Vector3(_rng.randf_range(-200, 380), 0, _rng.randf_range(-360, 300))
		var dist := _distance_to_line(p)
		if dist < ROAD_WIDTH * 0.5 + 4.0:
			continue
		if i % 3 == 0:
			# Boulders: taller than a kart, with straight sides, so you bump
			# into them. (A low, rounded hit shape worked like a ramp and
			# threw karts into the air.)
			var sc := _rng.randf_range(3.0, 5.0)
			rocks.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * 2.6, sc)), p))
			if dist < trees_hit_radius:
				var col := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = 0.36 * sc
				cyl.height = 0.26 * sc * 2.6
				col.shape = cyl
				col.position = p + Vector3.UP * cyl.height * 0.5
				solid.add_child(col)
		elif i % 3 == 1:
			bushes.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(3.0, 5.0)), p))
		else:
			flowers.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 4.0), p))
	_scatter(KIT_NATURE + "rock_largeA.glb", rocks)
	_scatter(KIT_NATURE + "plant_bushLarge.glb", bushes)
	_scatter(KIT_NATURE + "flower_yellowA.glb", flowers)
	_build_mountains()


func _build_mountains() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(80, 0, -30)
	var colors := [Color(0.48, 0.62, 0.78), Color(0.55, 0.68, 0.82), Color(0.42, 0.56, 0.72)]
	for i in 26:
		var a := TAU * i / 26.0 + _rng.randf() * 0.1
		var r := _rng.randf_range(560, 640)
		var base := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var h := _rng.randf_range(70, 160)
		var w := _rng.randf_range(90, 160)
		var side := Vector3(-sin(a), 0, cos(a)) * w
		var c: Color = colors[i % colors.size()]
		var peak := base + Vector3.UP * h
		for v in [base - side, peak, base + side]:
			st.set_color(c)
			st.add_vertex(v)
		var snow_c := Color(0.96, 0.97, 1.0)
		for v in [peak.lerp(base - side, 0.22), peak, peak.lerp(base + side, 0.22)]:
			st.set_color(snow_c)
			st.add_vertex(v + (center - base).normalized() * 0.5)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _mat(Color.WHITE)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)


# --- Race progress -------------------------------------------------------

## Where to drop a kart that fell off or flipped: a little behind where it was.
func respawn_transform(pos: Vector3) -> Transform3D:
	var off := offset_of(pos) - 6.0
	var t := transform_at(off)
	t.origin += Vector3.UP * 1.2
	return t


## Grid slots behind the start line, two abreast.
func grid_transform(slot: int) -> Transform3D:
	var row := slot / 2
	var side := -1.0 if slot % 2 == 0 else 1.0
	var t := transform_at(length - 8.0 - row * 7.0)
	t.origin += t.basis.x * side * 3.2 + Vector3.UP * 0.6
	return t


## Laps count only when every checkpoint is passed in order (design doc 5).
func update_progress(kart: Kart) -> void:
	var off := offset_of(kart.global_position)
	var cp_len := length / CHECKPOINTS
	var target := kart.next_checkpoint * cp_len
	var past := fposmod(off - target, length)
	if past < 25.0:
		if kart.next_checkpoint == 0:
			kart.lap += 1
			if kart.lap > laps:
				kart.finished = true
			kart.lap_completed.emit(kart.lap, kart.race_time)
		kart.next_checkpoint = (kart.next_checkpoint + 1) % CHECKPOINTS


## Distance raced, for positions ("3rd").
func race_distance(kart: Kart) -> float:
	# Grid slots sit just before the line at lap 0, so this keeps rising
	# smoothly as karts cross it and complete laps.
	return kart.lap * length + offset_of(kart.global_position)


## Track outline for the minimap, flattened to 2D.
func outline(points := 120) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points:
		var p := curve.sample_baked(length * i / points)
		out.append(Vector2(p.x, p.z))
	return out
