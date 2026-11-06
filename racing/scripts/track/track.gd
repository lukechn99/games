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
## Set pieces (design doc 9.4), as lap offsets in metres.
const LEDGE := [255.0, 350.0]     # high ledge: cliff down to a lake outside, rock wall inside
const TUNNEL := [172.0, 214.0]    # rock tunnel on the climb
const BRIDGE_AT := 445.0          # stone bridge over the ice
const GANTRIES := [118.0, 540.0]  # metal sign gantries over the highway
const BRANCH := [30.0, 170.0]     # the road splits round a rocky island here
const BRANCH_SHIFT := 26.0        # how far the second route swings out
const BRANCH_SPLIT := ROAD_WIDTH + 2.2   # past this, the routes are separate roads
## Detail texture and tiling per road surface (UVs: one unit = 14 m).
const SURFACE_TEX := {"asphalt": ["asphalt", 1.0], "boost": ["asphalt", 1.0], "dirt": ["dirt", 2.0], "ice": ["ice", 2.0]}

var curve := Curve3D.new()
var length := 0.0
var laps := LAPS
var trees_hit_radius := 26.0
var _samples: Array[Transform3D] = []   # every 2 m along the line
var _bank: PackedFloat32Array = []       # bank angle every 2 m
var _skirt: PackedFloat32Array = []      # embankment width every 2 m
var _rng := RandomNumberGenerator.new()
var lake_center := Vector3.ZERO
var lake_radius := 0.0
var ledge_out := 1.0          # which side of the road the lake is on (+1 right)
var branch_side := 1.0        # which side the second route swings out to
var _keep_clear: Array[Vector3] = []   # (x, z, radius): no scenery here
var _branch_samples: Array[Vector3] = []


func _ready() -> void:
	_rng.seed = 42
	_build_curve()
	_plan_set_pieces()
	_build_ground()
	_build_road()
	_build_branch()
	_build_rails()
	_build_jump()
	_build_start()
	SetPieces.build(self)
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


## Track material: our colours in the vertex colours, with an optional
## detail texture. `uv` tiles it on the mesh's own UVs; `tri` (metres) projects
## it from the world instead, for meshes without UVs.
func _mat(c: Color, tex := "", uv := 1.0, tri := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	if tex != "":
		m.albedo_texture = load(Palette.TEX_DIR + tex + ".png")
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if tri > 0.0:
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE / tri
			m.uv1_triplanar_sharpness = 4.0
		else:
			m.uv1_scale = Vector3(uv, uv, 1.0)
		Palette.add_relief(m, tex, 0.8)
	return m


## `floor`: something karts drive on (road, banks, ground, ramps), as
## opposed to something they hit (rails, rocks, trees). Karts ignore bumps
## from the edges of floor pieces (kart.gd).
func _body(surface: String, floor := false) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta("surface", surface)
	b.set_meta("floor", floor)
	add_child(b)
	return b


func _build_ground() -> void:
	var b := _body("grass", true)
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
	mi.material_override = _mat(Parts.surface("grass")["color"], "grass", 1400.0 / 7.0)
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
		var shift := absf(branch_offset(d))
		if shift > 0.3 and shift < BRANCH_SPLIT:
			# Where the routes part, one wide piece of road covers both, so
			# there are no overlapping layers and no seams (design doc 9.4).
			_merged_strip(st, d, minf(d + step, length), int(d / step))
		else:
			_quad_strip(st, a, b, s, int(d / step), d)
			if shift >= BRANCH_SPLIT:
				var ba := branch_frame(d)
				var bb := branch_frame(minf(d + step, BRANCH[1]))
				var bs := "boost" if _in_moss(d) else "asphalt"
				# The moss glows green rather than boost-pad orange.
				var moss := Color(0.35, 1.0, 0.45) if bs == "boost" else Color(0, 0, 0, 0)
				_quad_strip(_group(groups, bs) if bs != s else st, ba, bb, bs, int(d / step), d, 0.0, 0.0, moss)
		_embankment(_group(groups, "grass"), _group(groups, "rock"), a, b, int(d / step), d)
		d += step
	_commit_groups(groups)


## Glowing moss strips that boost you, inside the cave route.
func _in_moss(d: float) -> bool:
	var u := (d - BRANCH[0]) / (BRANCH[1] - BRANCH[0])
	return (u > 0.42 and u < 0.47) or (u > 0.6 and u < 0.65)


## One road surface from the main road's far edge to the second route's far
## edge, with kerbs only on the outside.
func _merged_strip(st: SurfaceTool, da: float, db: float, index: int) -> void:
	var side := branch_side
	var half := ROAD_WIDTH * 0.5
	var lift := Vector3.UP * 0.04
	var ma := road_frame(da)
	var mb := road_frame(db)
	var aa := branch_frame(da)
	var ab := branch_frame(db)
	var near_a := ma.origin - ma.basis.x * side * half
	var near_b := mb.origin - mb.basis.x * side * half
	var far_a := aa.origin + aa.basis.x * side * half
	var far_b := ab.origin + ab.basis.x * side * half
	var base: Color = Parts.surface("asphalt")["color"]
	var kerb := Color(0.92, 0.22, 0.2) if index % 2 == 0 else Color(0.97, 0.97, 0.97)
	var va := da / 14.0
	var vb := db / 14.0
	var bands := [
		[near_a, far_a, near_b, far_b, base],
		[near_a - ma.basis.x * side * 1.1, near_a, near_b - mb.basis.x * side * 1.1, near_b, kerb],
		[far_a, far_a + aa.basis.x * side * 1.1, far_b, far_b + ab.basis.x * side * 1.1, kerb],
	]
	for band in bands:
		var p0: Vector3 = band[0] + lift
		var p1: Vector3 = band[1] + lift
		var p3: Vector3 = band[2] + lift
		var p2: Vector3 = band[3] + lift
		var c: Color = band[4]
		var w := p0.distance_to(p1) / ROAD_WIDTH
		var uvs := {p0: Vector2(0, va), p1: Vector2(w, va), p2: Vector2(w, vb), p3: Vector2(0, vb)}
		# Keep the same winding as the main road whichever side we're on.
		var order := [p0, p2, p1, p0, p3, p2] if side > 0 else [p0, p1, p2, p0, p2, p3]
		for v in order:
			st.set_color(c)
			st.set_uv(uvs[v])
			st.add_vertex(v)


func _group(groups: Dictionary, key: String) -> SurfaceTool:
	if not groups.has(key):
		groups[key] = SurfaceTool.new()
		(groups[key] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
	return groups[key]


## One static body per surface (keys may carry a "#tag" to keep meshes apart).
func _commit_groups(groups: Dictionary) -> void:
	for key in groups:
		var s: String = String(key).split("#")[0]
		var st: SurfaceTool = groups[key]
		st.generate_normals()
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var body := _body(s, s != "rock")
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if s == "grass":
			mi.material_override = _mat(Color.WHITE, "grass", 1.0, 7.0)
		elif s == "rock":
			mi.material_override = _mat(Color.WHITE, "rock", 1.0, 5.0)
		else:
			var t: Array = SURFACE_TEX.get(s, ["", 1.0])
			mi.material_override = _mat(Color.WHITE, t[0], t[1])
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var shape := mesh.create_trimesh_shape()
		# Solid from both sides, so nothing can slip through the road or the
		# banks and end up underneath.
		shape.backface_collision = true
		col.shape = shape
		body.add_child(col)


## Where the road sits above the ground, a grassy bank slopes down to meet it.
func _embankment(st: SurfaceTool, rock: SurfaceTool, a: Transform3D, b: Transform3D, index: int, d := -1.0) -> void:
	var edge := ROAD_WIDTH * 0.5 + 1.1
	var widest := 0.0
	var on_ledge := d >= LEDGE[0] and d < LEDGE[1]
	for side in [-1.0, 1.0]:
		var ea: Vector3 = a.origin + a.basis.x * side * edge
		var eb: Vector3 = b.origin + b.basis.x * side * edge
		if on_ledge:
			# Carved into the hillside: a sheer cliff down to the lake on the
			# outside, a rock wall rising on the inside (design doc 9.4).
			_rock_side(rock, ea, eb, (a.basis.x * Vector3(1, 0, 1)).normalized() * side, (b.basis.x * Vector3(1, 0, 1)).normalized() * side, side == ledge_out, index, side)
			widest = maxf(widest, 14.0)
			continue
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
		var tri := [ea, gb, ga, ea, eb, gb] if side > 0 else [ea, ga, gb, ea, gb, eb]
		for v in tri:
			st.set_color(c)
			st.add_vertex(v)
	if index < _skirt.size():
		_skirt[index] = widest


## The rock's cross-section at one point: (outward, height above the edge).
## Smoothly varying lumps so the face reads as natural rock.
func _rock_profile(cliff: bool, edge_y: float, index: int) -> Array[Vector2]:
	var bump := sin(index * 0.37) * 0.7 + sin(index * 0.11) * 1.4
	if cliff:
		return [Vector2(0, 0), Vector2(0.6, -1.2), Vector2(1.4 + bump * 0.3, -edge_y * 0.55), Vector2(2.4 + bump * 0.2, -edge_y - 0.8)]
	var top := 7.5 + bump
	return [Vector2(0, 0), Vector2(0.4, 0.5), Vector2(1.4 + bump * 0.3, top), Vector2(5.0, top + 1.2), Vector2(9.0 + (edge_y + top) * 1.1, -edge_y - 0.02)]


## A rock cross-section along one road edge: `cliff` drops to the water,
## otherwise a wall rises from the kerb and slopes away behind.
func _rock_side(st: SurfaceTool, ea: Vector3, eb: Vector3, out_a: Vector3, out_b: Vector3, cliff: bool, index: int, side: float) -> void:
	var pa := _rock_profile(cliff, ea.y, index)
	var pb := _rock_profile(cliff, eb.y, index + 1)
	var c := Color(0.66, 0.63, 0.6)
	for k in pa.size() - 1:
		var p0: Vector2 = pa[k]
		var p1: Vector2 = pa[k + 1]
		var q0: Vector2 = pb[k]
		var q1: Vector2 = pb[k + 1]
		var a0 := ea + out_a * p0.x + Vector3.UP * p0.y
		var a1 := ea + out_a * p1.x + Vector3.UP * p1.y
		var b0 := eb + out_b * q0.x + Vector3.UP * q0.y
		var b1 := eb + out_b * q1.x + Vector3.UP * q1.y
		# Darker low down and in the creases where light doesn't reach.
		var c0 := c.darkened(0.25 if p0.y < -1.0 or k == 0 else 0.0)
		var c1 := c.darkened(0.25 if p1.y < -1.0 else 0.0)
		var quad := [[a0, c0], [b1, c1], [a1, c1], [a0, c0], [b0, c0], [b1, c1]] if side > 0 else [[a0, c0], [a1, c1], [b1, c1], [a0, c0], [b1, c1], [b0, c0]]
		for q in quad:
			st.set_color(q[1])
			st.add_vertex(q[0])


func _quad_strip(st: SurfaceTool, a: Transform3D, b: Transform3D, s: String, index: int, d := 0.0, skip_kerb := 0.0, lift_extra := 0.0, tint := Color(0, 0, 0, 0)) -> void:
	var half := ROAD_WIDTH * 0.5
	var base: Color = Parts.surface(s)["color"] if tint.a == 0.0 else tint
	var lift := Vector3.UP * (0.04 + lift_extra)
	# Road, then a kerb on each side (red and white blocks every 2 m).
	var kerb := Color(0.92, 0.22, 0.2) if index % 2 == 0 else Color(0.97, 0.97, 0.97)
	var bands := [[-half, half, base]]
	if skip_kerb >= 0.0:
		bands.append([-half - 1.1, -half, kerb])
	if skip_kerb <= 0.0:
		bands.append([half, half + 1.1, kerb])
	# Texture coordinates: across the road and along it, 14 m per tile.
	var va := d / 14.0
	var vb := (d + a.origin.distance_to(b.origin)) / 14.0
	for band in bands:
		var c: Color = band[2]
		var x0 := float(band[0])
		var x1 := float(band[1])
		var p0 := a.origin + a.basis.x * x0 + lift
		var p1 := a.origin + a.basis.x * x1 + lift
		var p2 := b.origin + b.basis.x * x1 + lift
		var p3 := b.origin + b.basis.x * x0 + lift
		var u0 := x0 / ROAD_WIDTH + 0.5
		var u1 := x1 / ROAD_WIDTH + 0.5
		var uvs := {p0: Vector2(u0, va), p1: Vector2(u1, va), p2: Vector2(u1, vb), p3: Vector2(u0, vb)}
		# Subtle stripes so speed reads on a plain road.
		if band[0] == -half and s == "asphalt" and index % 8 == 0:
			c = c.lightened(0.05)
		for v in [p0, p2, p1, p0, p3, p2]:
			st.set_color(c)
			st.set_uv(uvs[v])
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


## Many copies of one model, one draw call per patch of ground (design doc
## 9.1). Splitting into 160 m patches lets the camera skip patches behind it
## or (with `far`) too far away to matter.
func _scatter(path: String, xforms: Array[Transform3D], far := 0.0) -> void:
	var mesh := _mesh_of(path)
	if mesh == null or xforms.is_empty():
		return
	var cells := {}
	for x in xforms:
		var key := Vector2i(floori(x.origin.x / 160.0), floori(x.origin.z / 160.0))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(x)
	var styled := Palette.restyle(mesh)
	for key in cells:
		var list: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = styled
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if far > 0.0:
			mmi.visibility_range_end = far
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
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
	var body := _body("rail")
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
				if side == branch_side and d > BRANCH[0] - 6.0 and d < BRANCH[1] + 2.0:
					continue  # leave the way open into the second route
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
	var body := _body("asphalt", true)
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
	for b in _branch_samples:
		best = minf(best, Vector2(p.x - b.x, p.z - b.z).length())
	return best


## Flat distance from `p` to the nearest point of the racing line.
func distance_to_road(p: Vector3) -> float:
	var best := INF
	for t in _samples:
		best = minf(best, Vector2(p.x - t.origin.x, p.z - t.origin.z).length())
	return best


## Places scenery must stay out of (the lake, set pieces).
func _blocked(p: Vector3) -> bool:
	for c in _keep_clear:
		if Vector2(p.x - c.x, p.z - c.y).length() < c.z:
			return true
	return false


func keep_clear(p: Vector3, radius: float) -> void:
	_keep_clear.append(Vector3(p.x, p.z, radius))


# --- Set-piece planning ----------------------------------------------------

func _plan_set_pieces() -> void:
	var centroid := Vector3.ZERO
	for t in _samples:
		centroid += t.origin
	centroid /= maxf(1.0, _samples.size())
	# The lake lies outside the high ledge.
	var mid := transform_at((LEDGE[0] + LEDGE[1]) * 0.5)
	ledge_out = 1.0 if (mid.origin + mid.basis.x * 10.0).distance_to(centroid) > (mid.origin - mid.basis.x * 10.0).distance_to(centroid) else -1.0
	var d := LEDGE[0]
	while d <= LEDGE[1]:
		var t := transform_at(d)
		for k in 6:
			keep_clear(t.origin + t.basis.x * ledge_out * (ROAD_WIDTH * 0.5 + 6.0 + k * 10.0), 9.0)
			keep_clear(t.origin - t.basis.x * ledge_out * (ROAD_WIDTH * 0.5 + 6.0 + k * 3.0), 5.0)
		d += 8.0
	# The second route swings out to whichever side has more room.
	var room := {}
	for side in [-1.0, 1.0]:
		var bm := transform_at((BRANCH[0] + BRANCH[1]) * 0.5)
		var p: Vector3 = bm.origin + bm.basis.x * float(side) * (BRANCH_SHIFT + 10.0)
		var best := INF
		for i in _samples.size():
			var dd := absf(i * 2.0 - (BRANCH[0] + BRANCH[1]) * 0.5)
			if minf(dd, length - dd) > 120.0:
				best = minf(best, p.distance_to(_samples[i].origin))
		room[side] = best
	branch_side = 1.0 if room[1.0] > room[-1.0] else -1.0
	d = BRANCH[0]
	while d <= BRANCH[1]:
		var bt := branch_frame(d)
		_branch_samples.append(bt.origin)
		d += 2.0


## How far the second route is from the racing line at `offset` (signed:
## + is to the right). Zero outside the split.
func branch_offset(offset: float) -> float:
	var o := fposmod(offset, length)
	if o <= BRANCH[0] or o >= BRANCH[1]:
		return 0.0
	var t := (o - BRANCH[0]) / (BRANCH[1] - BRANCH[0])
	return branch_side * BRANCH_SHIFT * smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(0.6, 1.0, t))


## The second route's road frame: swung out sideways, facing along itself.
func branch_frame(offset: float) -> Transform3D:
	var a := transform_at(offset)
	var b := transform_at(offset + 1.0)
	var pa := a.origin + a.basis.x * branch_offset(offset)
	var pb := b.origin + b.basis.x * branch_offset(offset + 1.0)
	var f := pb - pa
	f.y = 0.0
	return Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), pa)


## The second route: asphalt round the island, with a ramp of its own
## (the main road has the boost pad), so neither way is clearly faster.
func _build_branch() -> void:
	pass  # built with the main road now (_build_road)


## Water: falling in counts as out of bounds (kart.gd).
func in_water(pos: Vector3) -> bool:
	if pos.y > 1.2:
		return false
	var off := offset_of(pos)
	if off < LEDGE[0] - 10.0 or off > LEDGE[1] + 10.0:
		return false
	var local := transform_at(off).affine_inverse() * pos
	return local.x * ledge_out > ROAD_WIDTH * 0.5 + 1.0


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
	var solid := _body("tree")
	var shade := []   # soft shade under every tree and rock (design doc 9.4)
	var tries := 0
	var placed := 0
	while placed < 340 and tries < 4000:
		tries += 1
		var p := Vector3(_rng.randf_range(-260, 420), 0, _rng.randf_range(-420, 360))
		var dist := _distance_to_line(p)
		if dist < ROAD_WIDTH * 0.5 + 7.0 or _blocked(p):
			continue
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var sc := _rng.randf_range(5.5, 8.5)
		(trees[kind] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p))
		shade.append([p, 0.3 * sc, 1.3 * sc])
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
		if dist < ROAD_WIDTH * 0.5 + 4.0 or _blocked(p):
			continue
		if i % 3 == 0:
			# Boulders: taller than a kart, with straight sides, so you bump
			# into them. (A low, rounded hit shape worked like a ramp and
			# threw karts into the air.)
			var sc := _rng.randf_range(3.0, 5.0)
			rocks.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * 2.6, sc)), p))
			shade.append([p, 0.4 * sc, 0.68 * sc])
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
	_scatter(KIT_NATURE + "plant_bushLarge.glb", bushes, 220.0)
	_scatter(KIT_NATURE + "flower_yellowA.glb", flowers, 140.0)
	SetPieces.ground_shade(self, shade)
	_build_mountains()


func _build_mountains() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(80, 0, -30)
	# Two rings: the far one is paler and bluer, fading toward the sky, so
	# the world has layers instead of one flat backdrop (design doc 9.4).
	var near_colors := [Color(0.42, 0.56, 0.7), Color(0.47, 0.6, 0.74), Color(0.38, 0.52, 0.66)]
	var far_colors := [Color(0.62, 0.76, 0.92), Color(0.66, 0.79, 0.94), Color(0.6, 0.74, 0.9)]
	for i in 60:
		var far := i >= 26
		var colors: Array = far_colors if far else near_colors
		var n_ring := 34 if far else 26
		var a := TAU * (i - (26 if far else 0)) / n_ring + _rng.randf() * 0.1 + (0.09 if far else 0.0)
		var r := _rng.randf_range(820, 900) if far else _rng.randf_range(560, 640)
		var base := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var h := _rng.randf_range(130, 230) if far else _rng.randf_range(70, 160)
		var w := _rng.randf_range(140, 220) if far else _rng.randf_range(90, 160)
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
