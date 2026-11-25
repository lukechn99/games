class_name TestBarn
extends RefCounted
## H0's grey test barn (design doc 16): a barn you can walk into, a hayloft
## up a ramp, stalls, and the yard by the doors, dressed with every prop in
## the pool. Scenery copies of each prop are one MultiMesh (one draw call
## per kind) with a solid box each, so paint can land on them.

const LAYER_WORLD := 1
const LAYER_PLAYERS := 2
const LAYER_PROPS := 4

const BARN_RED := Color(0.62, 0.3, 0.27)
const BOARDS := Color(0.55, 0.44, 0.32)
const ROOF := Color(0.36, 0.33, 0.33)
const GRASS := Color(0.45, 0.62, 0.32)
const DIRT := Color(0.6, 0.5, 0.36)

const LOFT_Y := 3.0

## [kind, position, yaw] for props standing on something.
const STANDING := [
	# Bale stacks on the ground floor: a double stack a bale can hop onto.
	["bale", Vector3(5.0, 0.0, -8.0), 0.0], ["bale", Vector3(5.0, 0.5, -8.0), 0.0],
	["bale", Vector3(5.0, 0.0, -6.9), 0.0], ["bale", Vector3(5.0, 0.0, -9.1), 0.0], ["bale", Vector3(5.0, 0.5, -9.1), 0.0],
	["bale", Vector3(3.6, 0.0, -9.1), PI / 2], ["bale", Vector3(-1.0, 0.0, 6.0), 0.3],
	# Loft bales.
	["bale", Vector3(-6.0, LOFT_Y, 6.0), 0.0], ["bale", Vector3(-6.0, LOFT_Y + 0.5, 6.0), 0.0],
	["bale", Vector3(-4.9, LOFT_Y, 6.0), 0.0], ["bale", Vector3(-6.0, LOFT_Y, 7.1), 0.0],
	["bale", Vector3(-4.9, LOFT_Y, 7.1), 0.0], ["bale", Vector3(-4.9, LOFT_Y + 0.5, 7.1), 0.0],
	["bale", Vector3(-6.0, LOFT_Y + 0.5, 7.1), 0.0], ["bale", Vector3(-6.0, LOFT_Y + 1.0, 7.1), 0.0],
	["bale", Vector3(-2.5, LOFT_Y, 10.8), PI / 2], ["bale", Vector3(-2.5, LOFT_Y + 0.5, 10.8), PI / 2],
	# Trash cans by the doors, inside and out.
	["trash_can", Vector3(2.8, 0.0, 11.2), 0.0], ["trash_can", Vector3(3.5, 0.0, 11.2), 0.4],
	["trash_can", Vector3(-3.0, 0.0, 12.9), 0.0], ["trash_can", Vector3(3.0, 0.0, -12.9), 1.0],
	# Tires: a stack of three, singles, one in the yard.
	["tire", Vector3(6.5, 0.0, -10.5), 0.0], ["tire", Vector3(6.5, 0.2, -10.5), 0.5], ["tire", Vector3(6.5, 0.4, -10.5), 1.1],
	["tire", Vector3(6.6, 0.0, -9.5), 0.0], ["tire", Vector3(4.0, 0.0, 14.0), 0.0], ["tire", Vector3(4.9, 0.0, 14.4), 0.0],
	# Chairs.
	["chair", Vector3(-3.0, 0.0, -10.5), 0.3], ["chair", Vector3(3.0, 0.0, 2.0), -2.2],
	["chair", Vector3(2.0, LOFT_Y, 10.4), PI], ["chair", Vector3(-1.5, 0.0, 14.0), 2.6],
	# Crates.
	["crate", Vector3(-6.5, 0.0, -10.8), 0.0], ["crate", Vector3(-6.5, 0.6, -10.8), 0.2],
	["crate", Vector3(-5.8, 0.0, -10.8), 0.0], ["crate", Vector3(0.0, LOFT_Y, 11.0), 0.6],
	["crate", Vector3(1.0, 0.0, -11.0), 0.0],
	# Buckets in the stalls and by the door.
	["bucket", Vector3(-7.0, 0.0, -6.0), 0.0], ["bucket", Vector3(-6.0, 0.0, -2.0), 0.0],
	["bucket", Vector3(2.2, 0.0, 11.5), 0.0], ["bucket", Vector3(-4.0, 0.0, 13.5), 0.0],
	["bucket", Vector3(-6.6, 0.0, 1.8), 0.0],
]

## [kind, point on the wall at the ground, wall's outward normal]: props
## leaning against a wall.
const LEANING := [
	["rake", Vector3(7.85, 0.0, -4.0), Vector3(-1, 0, 0)],
	["rake", Vector3(7.85, 0.0, -3.0), Vector3(-1, 0, 0)],
	["rake", Vector3(-7.85, 0.0, 3.0), Vector3(1, 0, 0)],
	["rake", Vector3(5.0, 0.0, 12.15), Vector3(0, 0, 1)],
	["rake", Vector3(-4.0, 0.0, -11.85), Vector3(0, 0, 1)],
]

## Hand-placed hiding spots for sandbox hiders and, later, bots (design 12).
const SPOTS := [
	["bale", Vector3(5.0, 1.0, -8.0), 0.0],          # on top of the double stack
	["bale", Vector3(-3.8, LOFT_Y, 6.0), 0.0],
	["trash_can", Vector3(4.2, 0.0, 11.2), 0.0],
	["tire", Vector3(6.5, 0.6, -10.5), 0.0],
	["chair", Vector3(-3.6, 0.0, -10.2), 0.0],
	["crate", Vector3(-5.8, 0.6, -10.8), 0.0],
	["bucket", Vector3(-7.1, 0.0, -2.4), 0.0],
	["rake", Vector3(7.85, 0.0, -5.0), Vector3(-1, 0, 0)],
]

const LEAN_ANGLE := 0.2  # radians off upright


## Transform of a prop leaning on a wall: the prop's flat side faces the
## wall and its top touches it.
static func lean_transform(kind: String, wall_point: Vector3, normal: Vector3) -> Transform3D:
	var h := Props.size(kind).y
	var b := Basis.looking_at(-normal)                 # local +Z = normal
	b = b * Basis(Vector3.RIGHT, -LEAN_ANGLE)          # tip the top towards the wall
	var base := wall_point + normal * (h * sin(LEAN_ANGLE) + 0.08)
	return Transform3D(b, Vector3(base.x, wall_point.y, base.z))


static func spot_transform(spot: Array) -> Transform3D:
	if spot[2] is Vector3:
		return lean_transform(spot[0], spot[1], spot[2])
	return Transform3D(Basis(Vector3.UP, spot[2]), spot[1])


## Every scenery prop as [kind, transform].
static func scenery() -> Array:
	var out := []
	for s in STANDING:
		out.append([s[0], Transform3D(Basis(Vector3.UP, s[2]), s[1])])
	for s in LEANING:
		out.append([s[0], lean_transform(s[0], s[1], s[2])])
	return out


static func build(root: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var solid := StaticBody3D.new()
	solid.name = "Barn"
	solid.collision_layer = LAYER_WORLD
	solid.collision_mask = 0
	root.add_child(solid)

	# Ground, with a dirt apron at each door.
	_block(st, solid, Vector3(70, 1, 70), Vector3(0, -0.5, 0), GRASS)
	_block(st, null, Vector3(6, 0.02, 5), Vector3(0, 0.01, 14.5), DIRT)
	_block(st, null, Vector3(6, 0.02, 5), Vector3(0, 0.01, -14.5), DIRT)
	_block(st, null, Vector3(15.7, 0.02, 23.7), Vector3(0, 0.01, 0), BOARDS)
	# Side walls, end walls with a 4 m door, lintels.
	for x in [-8.0, 8.0]:
		_block(st, solid, Vector3(0.3, 5, 24.3), Vector3(x, 2.5, 0), BARN_RED)
	for z in [-12.0, 12.0]:
		for x in [-5.0, 5.0]:
			_block(st, solid, Vector3(6, 5, 0.3), Vector3(x, 2.5, z), BARN_RED)
		_block(st, solid, Vector3(4, 1, 0.3), Vector3(0, 4.5, z), BARN_RED)
	# Roof: two slopes from the eaves (5 m) to the ridge (8 m).
	var slope := atan2(3.0, 8.0)
	for side in [-1.0, 1.0]:
		var b := Basis(Vector3.BACK, side * -slope)
		_block(st, solid, Vector3(8.9, 0.2, 25.0), Vector3(side * 4.0, 6.6, 0), ROOF, b)
	# Stalls on the west side.
	for z in [-8.0, -4.0, 0.0]:
		_block(st, solid, Vector3(3.2, 1.2, 0.15), Vector3(-6.4, 0.6, z), BOARDS)
	# Hayloft over the north third, its railing, and a ramp up the east wall.
	_block(st, solid, Vector3(15.7, 0.3, 7.85), Vector3(0, LOFT_Y - 0.15, 7.92), BOARDS)
	_block(st, solid, Vector3(13.4, 0.9, 0.12), Vector3(-1.15, LOFT_Y + 0.45, 4.05), BOARDS)
	var run := Vector3(0, LOFT_Y, 6.2)
	var ramp_basis := Basis(Vector3.RIGHT, -atan2(run.y, run.z))
	_block(st, solid, Vector3(1.4, 0.2, run.length()), Vector3(7.1, LOFT_Y / 2 - 0.1, 4.0 - run.z / 2), BOARDS, ramp_basis)

	var m := st.commit()
	m.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "BarnMesh"
	root.add_child(mi)

	# Scenery props: one MultiMesh per kind, a solid box each.
	var by_kind := {}
	for s in scenery():
		by_kind.get_or_add(s[0], []).append(s[1])
	var props := Node3D.new()
	props.name = "Scenery"
	root.add_child(props)
	for kind in by_kind:
		var xforms: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Props.mesh(kind)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = kind
		props.add_child(mmi)
		for xf in xforms:
			props.add_child(prop_body(kind, xf))


## A solid box for one scenery prop. Paint sticks to it.
static func prop_body(kind: String, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_PROPS
	body.collision_mask = 0
	body.transform = xf
	body.set_meta("prop", kind)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Props.size(kind)
	cs.shape = box
	cs.position.y = box.size.y / 2
	body.add_child(cs)
	return body


static func _block(st: SurfaceTool, body: StaticBody3D, s: Vector3, at: Vector3, c: Color, b := Basis()) -> void:
	var bm := BoxMesh.new()
	bm.size = s
	Props._add(st, bm, Transform3D(b, at), c)
	if body:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s
		cs.shape = box
		cs.transform = Transform3D(b, at)
		body.add_child(cs)


static func environment(root: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.6, 0.9)
	sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.95)
	sky_mat.ground_horizon_color = Color(0.6, 0.66, 0.55)
	sky_mat.ground_bottom_color = Color(0.35, 0.4, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.96, 0.88)
	root.add_child(sun)


## Hiders' props come only from the scenery (design 9.2).
static func pool() -> Array:
	var out := []
	for s in scenery():
		if not out.has(s[0]):
			out.append(s[0])
	return out
