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
const MODELS := "res://assets/models/"   # our own, built in Blender (tools/blender/)

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

## Which track this is: "meadow" (Meadow Loop) or "mine" (Mining Mountain).
var layout := "meadow"
var points: Array = POINTS
var surface_zones: Array = SURFACE_ZONES
var rail_zones: Array = RAIL_ZONES
## Other routes that leave the main road and rejoin it: each is
## {from, to, shift: PackedFloat32Array (sideways offset every metre), kind}.
var branches: Array[Dictionary] = []
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
## Item crates that ride on something moving (the mine's rope bridge):
## {node, local} pairs, read by items.gd.
var moving_crates: Array = []
## Height of the land under everything (Mining Mountain's ledge is high up
## the mountain, so its valley floor is far below).
var ground_y := 0.0
## How far small scenery draws, as a share of its usual range (0.45 on Low
## graphics; main.gd sets it).
static var detail_reach := 1.0
var coin_spots: Array[Vector3] = []   # coins on the road (dressing.gd, items.gd)
var bridge: Node3D   # the mine's rope bridge (SwayBridge), if any


## The middle of the lap and how far it reaches, for aerial views.
func map_centre() -> Vector3:
	var c := Vector3.ZERO
	for x in _samples:
		c += x.origin
	c /= maxf(1.0, _samples.size())
	c.y = 0.0
	return c


func map_radius() -> float:
	var c := map_centre()
	var r := 0.0
	for x in _samples:
		r = maxf(r, Vector2(x.origin.x - c.x, x.origin.z - c.z).length())
	return r


## Under the frozen lake's ice (Frosty Pass): on the sunken road, not off
## the track.
func under_lake(pos: Vector3) -> bool:
	return layout == "frost" and pos.y < 0.0 and pos.y > FrostTrack.DEEP - 4.0 and FrostTrack.in_lake(pos, 1.05)


## On the rope bridge's deck (see SwayBridge.holds).
func on_bridge(pos: Vector3) -> bool:
	return bridge != null and bridge.holds(pos)
var branch_side := 1.0        # which side the second route swings out to
var _keep_clear: Array[Vector3] = []   # (x, z, radius): no scenery here
var _branch_samples: Array[Vector3] = []
var _branch_sample_offsets: PackedFloat32Array = []
var _flat_from := 0.0   # a stretch with no banking (set by a layout)
var _flat_to := 0.0


func _ready() -> void:
	_rng.seed = 42
	if layout == "mine":
		MineTrack.configure(self)
		_build_curve()
		MineTrack.plan(self)
		_build_ground()
		_build_road()
		_build_start(false)
		MineTrack.build(self)
		_build_scenery()
		return
	if layout == "frost":
		FrostTrack.configure(self)
		_build_curve()
		FrostTrack.plan(self)
		_build_ground()
		_build_road()
		_build_rails()
		_build_start()
		SetDressing.build(self)
		FrostTrack.build(self)
		_build_scenery()
		return
	_build_curve()
	_plan_set_pieces()
	_build_ground()
	_build_road()
	_build_rails()
	_build_jump()
	if layout == "meadow":
		for r in ramp_spots():
			_build_boost_ramp(r[0], r[1])
	_build_start()
	SetPieces.build(self)
	_build_scenery()


func _build_curve() -> void:
	var n := points.size()
	for i in n + 1:
		var p: Vector3 = points[i % n]
		var prev: Vector3 = points[(i - 1 + n) % n]
		var next: Vector3 = points[(i + 1) % n]
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
	if layout == "frost" and _flat_from < _flat_to and fposmod(offset, length) > _flat_from and fposmod(offset, length) < _flat_to:
		return 0.0   # the frozen lake and its detour: flat, so the roads meet level
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
	var main := curve.get_closest_offset(pos)
	if _branch_samples.is_empty():
		return main
	# On a route beside the main road (a shortcut across a lake, say), the
	# nearest bit of main road can be a quite different part of the lap:
	# go by the route instead when it's clearly the closer road.
	var dm := curve.get_closest_point(pos).distance_to(pos)
	var best := dm - 4.0
	var off := main
	for i in _branch_samples.size():
		var dd := _branch_samples[i].distance_to(pos)
		if dd < best:
			best = dd
			off = _branch_sample_offsets[i]
	return off


func surface_at_fraction(f: float) -> String:
	for z in surface_zones:
		if f >= z["from"] and f < z["to"]:
			return z["surface"]
	return "asphalt"


const MINE_ROAD := Color(0.47, 0.37, 0.28)


## The road's own material (shaders/road.gdshader): tarmac with patches,
## worn lanes and edge lines; on the mine, packed earth with no paint.
## The road shader for a paved stretch, or (kind "dirt") the loose, rutted
## stretches that slow you down, which get the same baked relief.
func _road_mat(kind := "asphalt") -> ShaderMaterial:
	var dirt := kind == "dirt" or layout == "mine"
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road.gdshader")
	if kind == "ice":
		# Glassy, frosted: the ice texture, its edge lines, and some sheen.
		m.set_shader_parameter("detail", load(Palette.TEX_DIR + "ice.png"))
		m.set_shader_parameter("paint", true)
		m.set_shader_parameter("wear", 0.0)
		m.set_shader_parameter("surf", load(Palette.TEX_DIR + "surf_asphalt.png"))
		m.set_shader_parameter("surf_n", load(Palette.TEX_DIR + "surf_asphalt_n.png"))
		m.set_shader_parameter("relief", 0.4 if Palette.relief_on else 0.0)
		m.set_shader_parameter("ruts", false)
		Palette.relief_shaders.append(m)
		return m
	m.set_shader_parameter("detail", load(Palette.TEX_DIR + ("dirt" if dirt else "asphalt") + ".png"))
	m.set_shader_parameter("paint", not dirt)
	m.set_shader_parameter("wear", 0.2 if kind == "dirt" else (0.35 if layout == "mine" else 0.5))
	var surf := "dirt" if dirt else "asphalt"
	m.set_shader_parameter("surf", load(Palette.TEX_DIR + "surf_" + surf + ".png"))
	m.set_shader_parameter("surf_n", load(Palette.TEX_DIR + "surf_" + surf + "_n.png"))
	m.set_shader_parameter("ruts", dirt)
	m.set_shader_parameter("relief", 1.0 if Palette.relief_on else 0.0)
	Palette.relief_shaders.append(m)
	return m


## Grass with drifting patches of colour (shaders/grass.gdshader).
func _grass_mat(banks: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/grass.gdshader")
	m.set_shader_parameter("detail", load(Palette.TEX_DIR + "grass.png"))
	m.set_shader_parameter("use_vertex", banks)
	if layout == "frost":
		# Snow: blue-white in the hollows, bright on top, a hint of warmth.
		m.set_shader_parameter("deep", Color(0.78, 0.85, 0.95))
		m.set_shader_parameter("fresh", Color(0.95, 0.97, 1.0))
		m.set_shader_parameter("dry", Color(0.98, 0.97, 0.95))
		m.set_shader_parameter("detail", load(Palette.TEX_DIR + "ice.png"))
		m.set_shader_parameter("tile_m", 11.0)
	_grass_mats.append(m)
	if _road_dist:
		_apply_road_distance(m)
	return m


var _grass_mats: Array[ShaderMaterial] = []
var _road_dist: ImageTexture
var _road_dist_rect := Rect2()

## A small map of how far each spot of ground is from the road's edge (1 px
## a metre, up to 12 m), so the grass shader can drift sand and dust over
## the verge right beside the road, as on a real circuit (design doc 9.4).
## Skipped without a screen (tests).
func _bake_road_distance() -> void:
	if DisplayServer.get_name() == "headless" or layout != "meadow":
		return
	var pts: Array[Vector3] = []
	var d := 0.0
	while d < length:
		pts.append(road_frame(d).origin)
		var bi := branch_at(d)
		if bi >= 0 and absf(branch_offset(d, bi)) > 1.0:
			pts.append(branch_frame(d, bi).origin)
		d += 1.5
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	lo -= Vector2(24, 24)
	hi += Vector2(24, 24)
	var w := int(hi.x - lo.x)
	var h := int(hi.y - lo.y)
	var px := PackedByteArray()
	px.resize(w * h)
	px.fill(255)
	var half := ROAD_WIDTH * 0.5
	const REACH := 12.0
	var r := int(half + REACH) + 1
	for p in pts:
		var cx := int(p.x - lo.x)
		var cz := int(p.z - lo.y)
		for z in range(maxi(cz - r, 0), mini(cz + r + 1, h)):
			var dz := float(z) + 0.5 - (p.z - lo.y)
			var row := z * w
			for x in range(maxi(cx - r, 0), mini(cx + r + 1, w)):
				var dx := float(x) + 0.5 - (p.x - lo.x)
				var e := sqrt(dx * dx + dz * dz) - half
				var v := int(clampf(e / REACH, 0.0, 1.0) * 255.0)
				if v < px[row + x]:
					px[row + x] = v
	_road_dist = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_L8, px))
	_road_dist_rect = Rect2(lo, Vector2(w, h))
	for m in _grass_mats:
		_apply_road_distance(m)


func _apply_road_distance(m: ShaderMaterial) -> void:
	m.set_shader_parameter("road_dist", _road_dist)
	m.set_shader_parameter("dist_origin", _road_dist_rect.position)
	m.set_shader_parameter("dist_size", _road_dist_rect.size)
	m.set_shader_parameter("use_dist", true)


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
	if layout == "frost":
		FrostTrack.ground_collision(self, b)   # with the frozen lake cut out
	else:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1400, 2, 1400)
		shape.shape = box
		shape.position = Vector3(80, ground_y - 1.0, -30)
		b.add_child(shape)
	var plane := PlaneMesh.new()
	# Out past the farthest mountains, so from high up (the fly-in) the
	# ground runs on under them instead of stopping short.
	plane.size = Vector2(2600, 2600)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(80, ground_y, -30)
	mi.material_override = _grass_mat(false)
	if layout == "frost":
		var gm: ShaderMaterial = mi.material_override
		gm.set_shader_parameter("hole", Vector4(FrostTrack.LAKE_CENTER.x, FrostTrack.LAKE_CENTER.z, FrostTrack.LAKE_RX, FrostTrack.LAKE_RZ))
	if layout == "mine":
		# The valley floor far below the ledge, softened into haze.
		var m: ShaderMaterial = mi.material_override
		var haze := Color(0.7, 0.82, 0.88)
		m.set_shader_parameter("deep", Color(0.22, 0.55, 0.2).lerp(haze, 0.55))
		m.set_shader_parameter("fresh", Color(0.42, 0.78, 0.26).lerp(haze, 0.55))
		m.set_shader_parameter("dry", Color(0.66, 0.78, 0.3).lerp(haze, 0.55))
	b.add_child(mi)
	_bake_road_distance()


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
		var bi := branch_at(d)
		var shift := absf(branch_offset(d, bi)) if bi >= 0 else 0.0
		if shift > 0.3 and shift < BRANCH_SPLIT:
			# Where the routes part, one wide piece of road covers both, so
			# there are no overlapping layers and no seams (design doc 9.4).
			_merged_strip(st, d, minf(d + step, length), int(d / step), bi)
		else:
			# (Across Frosty Pass's frozen lake the ice is the road.)
			if not (layout == "frost" and FrostTrack.main_on_ice(a.origin) and FrostTrack.main_on_ice(b.origin)):
				_quad_strip(st, a, b, s, int(d / step), d)
			if shift >= BRANCH_SPLIT and _branch_has_road(bi, d):
				var bend: float = branches[bi]["to"]
				var ba := _branch_strip_frame(d, bi)
				var bb := _branch_strip_frame(minf(d + step, bend), bi)
				var bs: String = "boost" if _in_moss(d) else branches[bi].get("surface", "asphalt")
				# The moss glows green rather than boost-pad orange.
				var moss := Color(0.35, 1.0, 0.45) if bs == "boost" else Color(0, 0, 0, 0)
				_quad_strip(_group(groups, bs) if bs != s else st, ba, bb, bs, int(d / step), d, 0.0, 0.0, moss)
		# Where the merged piece covers the road's edge, no bank on that side
		# (its top poked through the road as a thin green line).
		var no_bank := 0.0
		if shift > 0.3 and shift < BRANCH_SPLIT:
			no_bank = signf(branch_offset(d, bi))
		_embankment(_group(groups, "grass"), _group(groups, "rock"), a, b, int(d / step), d, no_bank)
		d += step
	_commit_groups(groups)


## Whether route `i` has ordinary road at `d` (the mine's rope bridge and
## cavern rails are built separately).
func _branch_has_road(i: int, d: float) -> bool:
	if layout == "mine":
		return MineTrack.has_road(self, i, d)
	if layout == "frost":
		return FrostTrack.has_road(self, i, d)
	return true


## Glowing moss strips that boost you, inside the cave route.
func _in_moss(d: float) -> bool:
	if layout != "meadow":
		return false
	var u := (d - BRANCH[0]) / (BRANCH[1] - BRANCH[0])
	return (u > 0.42 and u < 0.47) or (u > 0.6 and u < 0.65)


## One road surface from the main road's far edge to the second route's far
## edge, with kerbs only on the outside.
func _merged_strip(st: SurfaceTool, da: float, db: float, index: int, bi := 0) -> void:
	var side := signf(branch_offset(da, bi) + branch_offset(db, bi))
	if side == 0.0:
		side = 1.0
	var half := ROAD_WIDTH * 0.5
	var lift := Vector3.UP * 0.04
	var ma := road_frame(da)
	var mb := road_frame(db)
	var aa := branch_frame(da, bi)
	var ab := branch_frame(db, bi)
	var near_a := ma.origin - ma.basis.x * side * half
	var near_b := mb.origin - mb.basis.x * side * half
	# The far edge stays on the main road's cross-line, so this piece meets
	# the main road and the separate route without a gap even where the
	# route comes in at a steep angle.
	var xa := _flat(ma.basis.x)
	var xb := _flat(mb.basis.x)
	aa.basis.x = xa
	ab.basis.x = xb
	var far_a := aa.origin + xa * side * half
	var far_b := ab.origin + xb * side * half
	# Close in, the far edge follows the main road's bank, so the piece meets
	# the plain road after the merge level (no lip); out at the split it is
	# level with the separate route.
	far_a.y = lerpf((ma.origin + ma.basis.x * (branch_offset(da, bi) + side * half)).y, far_a.y, clampf(absf(branch_offset(da, bi)) / BRANCH_SPLIT, 0.0, 1.0))
	far_b.y = lerpf((mb.origin + mb.basis.x * (branch_offset(db, bi) + side * half)).y, far_b.y, clampf(absf(branch_offset(db, bi)) / BRANCH_SPLIT, 0.0, 1.0))
	var base: Color = Parts.surface("asphalt")["color"]
	var kerb := Color(0.92, 0.22, 0.2) if index % 2 == 0 else Color(0.97, 0.97, 0.97)
	if layout == "frost":
		kerb = Color(0.2, 0.45, 0.92) if index % 2 == 0 else Color(0.97, 0.97, 0.97)
	if layout == "mine":
		base = MINE_ROAD
		kerb = Color(0.45, 0.3, 0.17) if index % 2 == 0 else Color(0.38, 0.25, 0.14)
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
		if c != base:
			# Kerbs: band[0]/[2] are on the road side for the far kerb, band[1]/[3] for the near one.
			_kerb(st, p0, p1, p3, p2, c, va, vb, band[0] == far_a, side > 0)
			continue
		# Across: 0..1 over the road (edge lines at each side); kerbs sit
		# outside that range so the road shader leaves them plain.
		var u0 := 0.0 if c == base else -0.2
		var u1 := 1.0 if c == base else -0.1
		var uvs := {p0: Vector2(u0, va), p1: Vector2(u1, va), p2: Vector2(u1, vb), p3: Vector2(u0, vb)}
		# Keep the same winding as the main road whichever side we're on.
		var order := [p0, p2, p1, p0, p3, p2] if side > 0 else [p0, p1, p2, p0, p2, p3]
		for v in order:
			st.set_color(c)
			st.set_uv(uvs[v])
			st.add_vertex(v)


func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized()


## Route `i`'s frame for its own road strip. Near where it joins the main
## road it turns to square up with the main road's cross-line, so its end
## lines up with the merged piece (see _merged_strip).
func _branch_strip_frame(d: float, i: int) -> Transform3D:
	var f := branch_frame(d, i)
	var t := clampf((absf(branch_offset(d, i)) - BRANCH_SPLIT) / 10.0, 0.0, 1.0)
	var x := _flat(road_frame(d).basis.x).slerp(f.basis.x, t).normalized()
	f.basis = Basis(x, Vector3.UP, x.cross(Vector3.UP))
	return f


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
		if s != "grass" and s != "rock":
			st.generate_tangents()   # the road's baked relief needs them
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var body := _body(s, s != "rock")
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if s == "grass":
			mi.material_override = _grass_mat(true)
		elif s == "rock":
			# Layered stone (the mine's rock shader, in cooler greys).
			var rm := MineTrack.rock_material()
			rm.set_shader_parameter("use_gravel", false)
			rm.set_shader_parameter("snow_line", 999.0)
			# (On the mine, the mountain's own sandstone, so the cliff under
			# the ledge matches it.)
			if layout != "mine":
				rm.set_shader_parameter("band_m", 1.8)
				rm.set_shader_parameter("tone_a", Color(0.78, 0.73, 0.64))
				rm.set_shader_parameter("tone_b", Color(0.68, 0.63, 0.56))
				rm.set_shader_parameter("tone_c", Color(0.6, 0.56, 0.51))
				rm.set_shader_parameter("seam", Color(0.36, 0.32, 0.29))
				rm.set_shader_parameter("grass_top", true)
			mi.material_override = rm
		elif s == "asphalt":
			mi.material_override = _road_mat()
		elif s == "dirt":
			mi.material_override = _road_mat("dirt")
		elif s == "ice":
			mi.material_override = _road_mat("ice")
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
func _embankment(st: SurfaceTool, rock: SurfaceTool, a: Transform3D, b: Transform3D, index: int, d := -1.0, skip_side := 0.0) -> void:
	var edge := ROAD_WIDTH * 0.5 + 1.1
	var widest := 0.0
	var on_ledge := (d >= LEDGE[0] and d < LEDGE[1]) if layout == "meadow" else layout == "mine"
	for side in [-1.0, 1.0]:
		if side == skip_side:
			continue
		var ea: Vector3 = a.origin + a.basis.x * side * edge
		var eb: Vector3 = b.origin + b.basis.x * side * edge
		if on_ledge:
			# Carved into the hillside: a sheer cliff down to the lake on the
			# outside, a rock wall rising on the inside (design doc 9.4).
			# On the mountain the inside is the mountain itself (mine_track.gd).
			# (On the mountain both sides are the mountain itself: mine_track.gd
			# builds the face above and the fall below.)
			if layout == "mine":
				continue
			var out_a: Vector3 = (a.basis.x * Vector3(1, 0, 1)).normalized() * side
			var out_b: Vector3 = (b.basis.x * Vector3(1, 0, 1)).normalized() * side
			_rock_side(rock, ea, eb, out_a, out_b, side == ledge_out, index, side)
			# Close off the rock at each end of the ledge, so you can't see
			# into it from the road either side.
			if layout == "meadow":
				var seg := a.origin.distance_to(b.origin)
				if d - seg < LEDGE[0]:
					_rock_cap(rock, ea, out_a, _rock_profile(side == ledge_out, ea.y, index))
				if d + seg * 1.5 >= LEDGE[1]:
					_rock_cap(rock, eb, out_b, _rock_profile(side == ledge_out, eb.y, index + 1))
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


## The flat end of a rock section: its profile filled down to the ground,
## facing both ways.
func _rock_cap(st: SurfaceTool, e: Vector3, out: Vector3, profile: Array[Vector2]) -> void:
	var poly := PackedVector2Array(profile)
	var ground := -e.y - 0.05
	var last: Vector2 = profile[profile.size() - 1]
	poly.append(Vector2(last.x, ground))
	poly.append(Vector2(0.0, ground))
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	var c := Color(0.6, 0.57, 0.54)
	for k in range(0, tris.size(), 3):
		var v := []
		for j in 3:
			var p2: Vector2 = poly[tris[k + j]]
			v.append(e + out * p2.x + Vector3.UP * p2.y)
		for order in [[0, 1, 2], [0, 2, 1]]:
			for j in order:
				st.set_color(c)
				st.add_vertex(v[j])


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
	# Road, then a kerb on each side (red and white blocks every 2 m). On the
	# mine the road is packed earth and stone, edged with timber.
	var kerb := Color(0.92, 0.22, 0.2) if index % 2 == 0 else Color(0.97, 0.97, 0.97)
	if layout == "frost":
		kerb = Color(0.2, 0.45, 0.92) if index % 2 == 0 else Color(0.97, 0.97, 0.97)
	if layout == "mine":
		kerb = Color(0.45, 0.3, 0.17) if index % 2 == 0 else Color(0.38, 0.25, 0.14)
		if s == "asphalt" and tint.a == 0.0:
			base = MINE_ROAD
		elif s == "dirt" and tint.a == 0.0:
			base = Color(0.6, 0.4, 0.25)   # loose ochre gravel, darker than the packed road's orange
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
		if band[0] != -half:
			# A kerb: raised, ramped up from the road (x0 is the road side
			# for the right-hand kerb, x1 for the left).
			_kerb(st, p0, p1, p3, p2, c, va, vb, x0 == half, true)
			continue
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


## A kerb from x0 to x1 (a0/a1 at one end of the step, b0/b1 at the other),
## raised in a low rumble-strip profile: a ramp up from the road, a flat top,
## a short slope down the outside to meet the bank. `road_at_x0`: which
## side the road is on. `ccw`: the winding the road strip uses there.
const KERB_PROFILE := [[0.0, 0.0], [0.32, 0.1], [0.8, 0.1], [1.0, 0.0]]

func _kerb(st: SurfaceTool, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, c: Color, va: float, vb: float, road_at_x0: bool, ccw: bool) -> void:
	var prev_a := a0
	var prev_b := b0
	for k in range(1, KERB_PROFILE.size()):
		var f0: float = KERB_PROFILE[k - 1][0]
		var f1: float = KERB_PROFILE[k][0]
		var h0: float = KERB_PROFILE[k - 1][1]
		var h1: float = KERB_PROFILE[k][1]
		if not road_at_x0:
			# Walk the profile from the outside in.
			f0 = 1.0 - float(KERB_PROFILE[KERB_PROFILE.size() - k][0])
			f1 = 1.0 - float(KERB_PROFILE[KERB_PROFILE.size() - k - 1][0])
			h0 = KERB_PROFILE[KERB_PROFILE.size() - k][1]
			h1 = KERB_PROFILE[KERB_PROFILE.size() - k - 1][1]
		var q0 := a0.lerp(a1, f0) + Vector3.UP * h0
		var q1 := a0.lerp(a1, f1) + Vector3.UP * h1
		var r0 := b0.lerp(b1, f0) + Vector3.UP * h0
		var r1 := b0.lerp(b1, f1) + Vector3.UP * h1
		# Same layout as the road quads: p0=q0, p1=q1, p2=r1, p3=r0.
		var uvs := {q0: Vector2(-0.15, va), q1: Vector2(-0.12, va), r1: Vector2(-0.12, vb), r0: Vector2(-0.15, vb)}
		var order := [q0, r1, q1, q0, r0, r1] if ccw else [q0, q1, r1, q0, r1, r0]
		# The ramp faces a touch darker so the shape reads.
		var shade := c if absf(h1 - h0) < 0.001 else c.darkened(0.22)
		for v in order:
			st.set_color(shade)
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
			mmi.visibility_range_end = far * detail_reach
			mmi.set_meta("far", far)
			mmi.add_to_group("detail")
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(mmi)


func _in_rail_zone(f: float) -> bool:
	for z in rail_zones:
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
				# Our guardrail (tools/blender/props.py): 4 m long, centred.
				var vis := Transform3D(a.basis.rotated(a.basis.y, PI if side > 0 else 0.0), pos)
				visuals.append(vis)
		d += seg
	_scatter(MODELS + "guardrail.glb", visuals)


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


## Where the two boost ramps go: on a straight, each on one side of the road
## only, so you have to line up for it. [offset, side].
func ramp_spots() -> Array:
	var out := []
	for want in [[0.38, -1.0], [0.78, 1.0]]:
		var d: float = want[0] * length
		var tries := 0
		while tries < 60:
			if _good_ramp_spot(d):
				out.append([d, want[1]])
				break
			d += 7.0
			tries += 1
	return out


func _good_ramp_spot(d: float) -> bool:
	if d < 80.0 or d > length - 60.0 or absf(d - JUMP_AT * length) < 90.0:
		return false
	if branch_at(d) >= 0 or branch_at(d - 30.0) >= 0 or branch_at(d + 40.0) >= 0:
		return false
	if d > TUNNEL[0] - 40.0 and d < TUNNEL[1] + 20.0:
		return false
	if absf(d - BRIDGE_AT) < 50.0:
		return false
	for g in GANTRIES:
		if absf(d - g) < 15.0:
			return false
	# Straight for a good way either side, so the landing is on the road.
	var a := -road_frame(d - 15.0).basis.z
	var b := -road_frame(d + 35.0).basis.z
	return absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))) < 0.22


## A half-width ramp painted as a boost panel: drive up it and you're
## boosted into the air. It sits to one side, so it's worth aiming for.
func _build_boost_ramp(d: float, side: float) -> void:
	var a := road_frame(d)
	a.origin += a.basis.x * side * ROAD_WIDTH * 0.24
	var w := ROAD_WIDTH * 0.4
	var l := 6.0
	var h := 0.95
	var pts := PackedVector3Array()
	for x in [-w / 2, w / 2]:
		pts.append(Vector3(x, 0.04, l / 2))
		pts.append(Vector3(x, 0.04, -l / 2))
		pts.append(Vector3(x, h, -l / 2))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var body := _body("boost", true)
	body.transform = a
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.98, 0.3, 0.62)
	var L := [Vector3(-w / 2, 0.04, l / 2), Vector3(-w / 2, 0.04, -l / 2), Vector3(-w / 2, h, -l / 2)]
	var R := [Vector3(w / 2, 0.04, l / 2), Vector3(w / 2, 0.04, -l / 2), Vector3(w / 2, h, -l / 2)]
	for tri in [[L[0], L[2], R[2]], [L[0], R[2], R[0]], [L[1], R[1], R[2]], [L[1], R[2], L[2]], [L[0], L[1], L[2]], [R[0], R[2], R[1]]]:
		for v in tri:
			st.set_color(c if tri == [L[0], L[2], R[2]] or tri == [L[0], R[2], R[0]] else Color(0.95, 0.95, 0.95))
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color.WHITE)
	body.add_child(mi)
	# Glowing chevrons up the slope, pointing the way.
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope := Vector3(0, h, -l).normalized()
	var up := Vector3(0, l, h).normalized()
	for k in 3:
		var centre := Vector3(0, 0.04, l / 2).lerp(Vector3(0, h, -l / 2), 0.2 + k * 0.3) + up * 0.03
		for sx: float in [-1.0, 1.0]:
			var tip := centre + slope * 0.55
			var o0 := centre + Vector3(sx * w * 0.38, 0, 0) - slope * 0.25
			var o1 := o0 + slope * 0.5
			var t1 := tip + slope * 0.5
			for v in ([tip, o0, o1, tip, o1, t1] if sx > 0 else [tip, o1, o0, tip, t1, o1]):
				glow.set_color(Color.WHITE)
				glow.add_vertex(v)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.92, 0.4)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gi := MeshInstance3D.new()
	gi.mesh = glow.commit()
	gi.material_override = gm
	body.add_child(gi)


func _place(path: String, xf: Transform3D) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var n: Node3D = scene.instantiate()
	n.transform = xf
	Palette.restyle_tree(n)
	add_child(n)


func _build_start(stands := true) -> void:
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
	# A painted bracket in front of every grid slot, like a real circuit.
	if layout == "meadow":
		for slot in 8:
			var g := grid_transform(slot)
			g.origin -= Vector3.UP * 0.6
			var w := 1.35
			for r in [[Vector2(-w, -1.55), Vector2(w, -1.25)], [Vector2(-w, -1.55), Vector2(-w + 0.28, 0.1)], [Vector2(w - 0.28, -1.55), Vector2(w, 0.1)]]:
				var p0: Vector2 = r[0]
				var p1: Vector2 = r[1]
				for v in [Vector3(p0.x, 0.13, p0.y), Vector3(p1.x, 0.13, p1.y), Vector3(p1.x, 0.13, p0.y), Vector3(p0.x, 0.13, p0.y), Vector3(p0.x, 0.13, p1.y), Vector3(p1.x, 0.13, p1.y)]:
					st.set_color(Color(0.95, 0.95, 0.92))
					st.add_vertex(g * v)
	st.generate_normals()
	var line := MeshInstance3D.new()
	line.mesh = st.commit()
	line.material_override = _mat(Color.WHITE)
	add_child(line)
	# The start arch (our own, centred on the road), flags, grandstands.
	_start_sign(a)
	for side in [-1.0, 1.0]:
		_place(KIT_RACING + "flagCheckers.glb", Transform3D(_sl(a.basis, Vector3.ONE * 3.0), a.origin + a.basis.x * side * (ROAD_WIDTH / 2 + 3.0) + a.basis.z * 6.0))
	if not stands:
		return
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
var no_scenery := PackedVector2Array()   # an area kept clear (the mountain)


func _blocked(p: Vector3) -> bool:
	if no_scenery.size() > 2 and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), no_scenery):
		return true
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
	var shift := PackedFloat32Array()
	d = BRANCH[0]
	while d <= BRANCH[1] + 1.0:
		var t := (d - BRANCH[0]) / (BRANCH[1] - BRANCH[0])
		shift.append(branch_side * BRANCH_SHIFT * smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(0.6, 1.0, t)))
		d += 1.0
	add_branch(BRANCH[0], BRANCH[1], shift, "cave")


## Register another route: sideways offsets from the main road every metre
## from `from` to `to` (signed: + is to the right).
## `pts` (optional): the route's own path, a point per metre of the main
## road from `from`, for routes whose sideways offset would fold back on
## itself (a shortcut across the inside of a tight bend).
func add_branch(from: float, to: float, shift: PackedFloat32Array, kind: String, pts := PackedVector3Array()) -> void:
	branches.append({"from": from, "to": to, "shift": shift, "kind": kind, "pts": pts})
	var d := from
	while d <= to:
		_branch_samples.append(branch_frame(d, branches.size() - 1).origin)
		_branch_sample_offsets.append(d)
		d += 2.0


## How far route `i` is from the racing line at `offset` (signed: + is to
## the right). Zero outside its stretch.
func branch_offset(offset: float, i := 0) -> float:
	if i >= branches.size():
		return 0.0
	var b: Dictionary = branches[i]
	var o := fposmod(offset, length)
	if o <= b["from"] or o >= b["to"]:
		return 0.0
	var pts: PackedVector3Array = b.get("pts", PackedVector3Array())
	if not pts.is_empty():
		var f := transform_at(o)
		return (_branch_point(b, o) - f.origin).dot(f.basis.x)
	var tab: PackedFloat32Array = b["shift"]
	var x := o - float(b["from"])
	var k := int(x)
	if k + 1 >= tab.size():
		return tab[tab.size() - 1] if not tab.is_empty() else 0.0
	return lerpf(tab[k], tab[k + 1], x - k)


## Which route is beside the main road at `offset`, or -1.
func branch_at(offset: float) -> int:
	var o := fposmod(offset, length)
	for i in branches.size():
		if o > branches[i]["from"] and o < branches[i]["to"]:
			return i
	return -1


## Route `i`'s road frame: swung out sideways, facing along itself.
func branch_frame(offset: float, i := 0) -> Transform3D:
	if i < branches.size() and not (branches[i].get("pts", PackedVector3Array()) as PackedVector3Array).is_empty():
		var br: Dictionary = branches[i]
		var o := fposmod(offset, length)
		if o <= float(br["from"]) or o >= float(br["to"]):
			return transform_at(o)   # outside its stretch: the main road, as for offset routes
		var q0 := _branch_point(br, o)
		var q1 := _branch_point(br, minf(o + 1.0, float(br["to"])))
		if q1.distance_to(q0) < 0.01:
			q1 = q0 + (q0 - _branch_point(br, o - 1.0))
		var fd := q1 - q0
		fd.y = 0.0
		return Transform3D(Basis.looking_at(fd.normalized(), Vector3.UP), q0)
	var a := transform_at(offset)
	var b := transform_at(offset + 1.0)
	var pa := a.origin + a.basis.x * branch_offset(offset, i)
	var pb := b.origin + b.basis.x * branch_offset(offset + 1.0, i)
	var f := pb - pa
	f.y = 0.0
	if f.length() < 0.01:
		return Transform3D(a.basis, pa)
	return Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), pa)


func _branch_point(b: Dictionary, o: float) -> Vector3:
	var pts: PackedVector3Array = b["pts"]
	var x := clampf(o - float(b["from"]), 0.0, pts.size() - 1.001)
	var k := int(x)
	return pts[k].lerp(pts[mini(k + 1, pts.size() - 1)], x - k)


## Where a kart is relative to the nearest road (the main road or a route
## beside it): local position in that road's frame.
func road_local(pos: Vector3) -> Vector3:
	var off := offset_of(pos)
	var best := road_frame(off).affine_inverse() * pos
	var i := branch_at(off)
	if i >= 0:
		var alt := branch_frame(off, i)
		alt.basis = road_frame(off).basis
		var l := alt.affine_inverse() * pos
		if absf(l.x) < absf(best.x):
			best = l
	return best


## Rows of item crates: a frame for each row, across the road it's on.
func crate_frames() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if layout == "mine":
		return MineTrack.crate_frames(self)
	if layout == "frost":
		return FrostTrack.crate_frames(self)
	for u in [0.36, 0.72]:
		out.append(branch_frame(lerpf(BRANCH[0], BRANCH[1], u)))
	return out


## The second route: asphalt round the island, with a ramp of its own
## (the main road has the boost pad), so neither way is clearly faster.
func _build_branch() -> void:
	pass  # built with the main road now (_build_road)


## Water: falling in counts as out of bounds (kart.gd).
func in_water(pos: Vector3) -> bool:
	if layout != "meadow" or pos.y > 1.2:
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
	var tree_dir := KIT_NATURE
	if layout == "frost":
		# Snow-laden pines (our Blender models, about 1 m tall at scale 1).
		kinds = ["snowpine_tall", "snowpine_round"]
		tree_dir = MODELS
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
		var p := Vector3(_rng.randf_range(-260, 420), ground_y, _rng.randf_range(-420, 360))
		var dist := _distance_to_line(p)
		if dist < ROAD_WIDTH * 0.5 + 7.0 or _blocked(p):
			continue
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var sc := _rng.randf_range(5.5, 8.5) if layout != "frost" else _rng.randf_range(0.9, 1.5)
		var ks := sc * (6.0 if layout == "frost" else 1.0)   # in kit-tree units, for shade and trunks
		(trees[kind] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p))
		shade.append([p, 0.3 * ks, 1.3 * ks])
		if dist < trees_hit_radius:
			var col := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.06 * ks  # about the trunk, not the leaves
			cyl.height = 6.0
			col.shape = cyl
			col.position = p + Vector3.UP * 3.0
			solid.add_child(col)
		placed += 1
	for k in kinds:
		var arr: Array[Transform3D] = []
		arr.assign(trees[k])
		_scatter(tree_dir + k + ".glb", arr)
	for i in 70:
		var p := Vector3(_rng.randf_range(-200, 380), ground_y, _rng.randf_range(-360, 300))
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
		elif layout == "frost":
			continue
		elif i % 3 == 1:
			bushes.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(3.0, 5.0)), p))
		else:
			flowers.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 4.0), p))
	_scatter(KIT_NATURE + "rock_largeA.glb", rocks)
	_scatter(KIT_NATURE + "plant_bushLarge.glb", bushes, 220.0)
	_scatter(KIT_NATURE + "flower_yellowA.glb", flowers, 140.0)
	_puffy_trees(shade)
	SetPieces.ground_shade(self, shade)
	_build_mountains()
	Dressing.build(self)
	if layout == "meadow":
		_roadside_flora.call_deferred()
	# Rocks need the ground to sit on, so a frame later too.
	_terrain_dressing.call_deferred()


## Round, puffy cartoon trees (our Blender model) dotted among the kit trees,
## a few close to the road. Their trunks are solid.
func _puffy_trees(shade: Array) -> void:
	var xs: Array[Transform3D] = []
	var solid := _body("tree")
	var tries := 0
	while xs.size() < 70 and tries < 3000:
		tries += 1
		var p := Vector3(_rng.randf_range(-260, 420), ground_y, _rng.randf_range(-420, 360))
		var dist := _distance_to_line(p)
		if dist < ROAD_WIDTH * 0.5 + 6.0 or dist > 140.0 or _blocked(p) or in_water(p):
			continue
		var sc := _rng.randf_range(0.8, 1.35)
		xs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p))
		shade.append([p, 1.6 * sc, 4.5 * sc])
		if dist < trees_hit_radius:
			var col := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.3 * sc
			cyl.height = 4.0
			col.shape = cyl
			col.position = p + Vector3.UP * 2.0
			solid.add_child(col)
	_scatter(MODELS + ("snowpine_tall.glb" if layout == "frost" else "tree_puffy.glb"), xs)


func _terrain_dressing() -> void:
	await get_tree().physics_frame
	if is_inside_tree():
		TerrainDressing.build(self)


## Grass tufts, flowers and small bushes along both sides of the road, so
## the verge looks lived-in close up (design doc 9.4). Drawn only near the
## camera. Placed once the ground can be felt, so they sit on the banks.
func _roadside_flora() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var lists := {"grass_large": [] as Array[Transform3D], "flower_redA": [] as Array[Transform3D],
		"flower_yellowA": [] as Array[Transform3D], "plant_bush": [] as Array[Transform3D]}
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var half := ROAD_WIDTH * 0.5
	var d := 0.0
	while d < length:
		var f := road_frame(d)
		for side: float in [-1.0, 1.0]:
			var n := rng.randi_range(2, 4)
			var clump := "flower_redA" if rng.randf() < 0.5 else "flower_yellowA"
			var flowery := rng.randf() < 0.45
			for k in n:
				var lat := half + 1.6 + pow(rng.randf(), 1.6) * 9.0
				var p := f.origin + f.basis.x * side * lat + f.basis.z * rng.randf_range(-1.2, 1.2)
				if distance_to_road(p) < half + 1.3 or _blocked(p) or in_water(p):
					continue
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 6.0, p + Vector3.DOWN * 12.0)
				var hit := space.intersect_ray(q)
				if hit.is_empty() or hit["collider"].get_meta("surface", "") != "grass":
					continue
				var kind := "grass_large"
				var sc := rng.randf_range(2.4, 3.4)
				var r := rng.randf()
				if flowery and r < 0.6:
					kind = clump
					sc = rng.randf_range(3.0, 4.2)
				elif r < 0.06:
					kind = "plant_bush"
					sc = rng.randf_range(4.0, 6.0)
				var up: Vector3 = (hit["normal"] as Vector3).lerp(Vector3.UP, 0.5).normalized()
				var b := Basis(Vector3.UP, rng.randf() * TAU)
				b = Basis(Quaternion(Vector3.UP, up)) * b
				(lists[kind] as Array).append(Transform3D(b.scaled(Vector3.ONE * sc), hit["position"]))
		d += rng.randf_range(1.1, 2.0)
	for kind in lists:
		var arr: Array[Transform3D] = []
		arr.assign(lists[kind])
		_scatter(KIT_NATURE + kind + ".glb", arr, 190.0)  # (measured to the middle of each 160 m patch)


func _build_mountains() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(80, ground_y, -30)
	var haze := Color(0.78, 0.9, 1.0)
	# Three layers, each paler toward the sky (design doc 9.4): rolling green
	# hills close in, then blue mountains, then pale far peaks. Every
	# mountain has a sunlit face and a shaded face, and its foot fades into
	# the haze, like distance in a painted backdrop.
	for i in 44:
		var a := TAU * i / 44.0 + _rng.randf() * 0.08
		var r := _rng.randf_range(430, 500)
		var base := center + Vector3(cos(a) * r, -1.0, sin(a) * r)
		var side := Vector3(-sin(a), 0, cos(a)) * _rng.randf_range(60, 110)
		var h := _rng.randf_range(22, 55)
		var top := Color(0.33, 0.6, 0.3).lerp(Color(0.42, 0.66, 0.34), _rng.randf())
		if layout == "frost":
			top = Color(0.84, 0.9, 0.97).lerp(Color(0.93, 0.95, 0.99), _rng.randf())
		var segs := 10
		for k in segs:
			var t0 := PI * k / segs
			var t1 := PI * (k + 1) / segs
			var p0 := base - side * cos(t0) + Vector3.UP * sin(t0) * h
			var p1 := base - side * cos(t1) + Vector3.UP * sin(t1) * h
			# Lit on the side facing the sun (roughly the first half).
			var lit := top.lightened(0.08) if k < segs / 2 else top.darkened(0.08)
			for v in [[base, top.lerp(haze, 0.45)], [p0, lit], [p1, lit]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	for i in 60:
		var far := i >= 26
		var n_ring := 34 if far else 26
		var a := TAU * (i - (26 if far else 0)) / n_ring + _rng.randf() * 0.1 + (0.09 if far else 0.0)
		var r := _rng.randf_range(820, 900) if far else _rng.randf_range(560, 640)
		var base := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var h := _rng.randf_range(130, 230) if far else _rng.randf_range(70, 160)
		var w := _rng.randf_range(140, 220) if far else _rng.randf_range(90, 160)
		var side := Vector3(-sin(a), 0, cos(a)) * w
		var inward := (center - base).normalized()
		var body := Color(0.62, 0.75, 0.9) if far else Color(0.38, 0.52, 0.7).lerp(Color(0.44, 0.58, 0.72), _rng.randf())
		var lit := body.lightened(0.12)
		var shade := body.darkened(0.12)
		if layout == "frost":
			# Snow-capped: the peaks white, fading down into the blue.
			lit = Color(0.97, 0.98, 1.0)
			shade = Color(0.8, 0.86, 0.95)
		var peak := base + Vector3.UP * h + side * _rng.randf_range(-0.25, 0.25)
		var foot := base + inward * w * 0.4   # the ridge comes toward us
		var foot_c := body.lerp(haze, 0.6)
		for v in [[base - side, lit.lerp(haze, 0.6)], [peak, lit], [foot, foot_c]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
		for v in [[foot, foot_c], [peak, shade], [base + side, shade.lerp(haze, 0.6)]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
		# A snow cap following the same two faces.
		var cap := 0.26
		var l := peak.lerp(base - side, cap)
		var m := peak.lerp(foot, cap)
		var rr := peak.lerp(base + side, cap)
		var lift := inward * 0.5
		for v in [[l, Color(0.97, 0.98, 1.0)], [peak, Color(0.97, 0.98, 1.0)], [m, Color(0.93, 0.95, 1.0)]]:
			st.set_color(v[1])
			st.add_vertex(v[0] + lift)
		for v in [[m, Color(0.82, 0.87, 0.96)], [peak, Color(0.86, 0.9, 0.98)], [rr, Color(0.8, 0.85, 0.95)]]:
			st.set_color(v[1])
			st.add_vertex(v[0] + lift)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := _mat(Color.WHITE)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)


# --- Race progress -------------------------------------------------------

## Where to drop a kart that fell off or flipped: a little behind where it was.
func respawn_transform(pos: Vector3) -> Transform3D:
	var off := offset_of(pos) - 6.0
	var t := transform_at(off)
	# Fell off a route beside the main road (the mine's cavern trestle, say):
	# back onto that route, not across on the main road. The rope bridge is
	# the exception: you're put back on the main road below it.
	var bi := branch_at(off)
	if bi >= 0 and branches[bi]["kind"] != "bridge":
		var bf := branch_frame(off, bi)
		var flat := Vector2(pos.x, pos.z)
		if flat.distance_to(Vector2(bf.origin.x, bf.origin.z)) < flat.distance_to(Vector2(t.origin.x, t.origin.z)):
			t = bf
	t.origin += Vector3.UP * 1.2
	return t


## Grid slots behind the start line, two abreast.
## The start arch: two pillars either side of the road, centred on it, and
## the name in big letters on a board across the top, facing the grid.
## (The kit's arch wasn't symmetrical: one leg stood on the road.)
func _start_sign(a: Transform3D) -> void:
	var st := SetPieces._new_st()
	var mine := layout == "mine"
	var frost := layout == "frost"
	var c := a.origin + Vector3.UP * 7.1
	var w := ROAD_WIDTH + 5.6
	var pillar := Color(0.55, 0.36, 0.2) if mine else Color(0.96, 0.96, 0.96)
	var trim := Color(0.95, 0.72, 0.15) if mine else (Color(0.25, 0.55, 0.95) if frost else Color(0.92, 0.18, 0.18))
	var board := Color(0.3, 0.2, 0.13) if mine else (Color(0.1, 0.27, 0.58) if frost else Color(0.12, 0.6, 0.32))
	for side: float in [-1.0, 1.0]:
		var foot := a.origin + a.basis.x * side * (ROAD_WIDTH * 0.5 + 2.6)
		SetPieces._box(st, Transform3D(a.basis, foot + Vector3.UP * 3.7), Vector3(1.1, 8.6, 1.1), pillar)
		SetPieces._box(st, Transform3D(a.basis, foot + Vector3.UP * 0.4), Vector3(1.5, 0.8, 1.5), trim)
		SetPieces._box(st, Transform3D(a.basis, foot + Vector3.UP * 5.2), Vector3(1.25, 0.3, 1.25), trim)
	SetPieces._box(st, Transform3D(a.basis, c), Vector3(w + 0.6, 2.9, 0.9), pillar)
	SetPieces._box(st, Transform3D(a.basis, c + a.basis.z * 0.12), Vector3(w - 0.4, 2.3, 0.7), board)
	SetPieces._box(st, Transform3D(a.basis, c + a.basis.z * 0.14 - Vector3.UP * 1.0), Vector3(w - 0.4, 0.3, 0.72), trim)
	SetPieces._commit(self, st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))
	# The track's name, lettered to suit it: chunky squared-off stencil on the
	# mine's timber, a soft rounded script over the meadow.
	var label := Label3D.new()
	# (Frosty Pass: chunky rounded letters, snow-white on deep blue.)
	label.text = "MINING MOUNTAIN" if mine else ("Frosty Pass" if frost else "Meadow Loop")
	label.font = load("res://assets/fonts/black_ops_one.woff2" if mine else ("res://assets/fonts/lilita_one.woff2" if frost else "res://assets/fonts/pacifico.woff2"))
	label.font_size = 200
	label.outline_size = 40 if mine else 48
	label.modulate = Color(1.0, 0.8, 0.2) if mine else (Color(0.97, 0.99, 1.0) if frost else Color(1.0, 0.98, 0.9))
	label.outline_modulate = Color(0.2, 0.12, 0.06) if mine else (Color(0.12, 0.3, 0.7) if frost else Color(0.86, 0.16, 0.16))
	# As big as fits the board.
	var text_w := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x + label.outline_size
	var text_h := label.font.get_height(label.font_size)
	label.pixel_size = minf((w - 1.6) / text_w, (3.9 if not mine and not frost else 2.6) / text_h)   # (the script runs tall for its size)
	label.shaded = false
	label.double_sided = false
	label.transform = Transform3D(a.basis, c + a.basis.z * 0.5 + Vector3.UP * (0.12 if mine else 0.0))
	add_child(label)


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
	# A loop, because a shortcut can carry a kart past more than one
	# checkpoint at once (they still all count, in order).
	for guard in 3:
		var target := kart.next_checkpoint * cp_len
		var past := fposmod(off - target, length)
		if past >= 60.0:
			break
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
