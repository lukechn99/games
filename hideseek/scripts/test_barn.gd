class_name TestBarn
extends RefCounted
## H0's test barn (design doc 16): a barn you can walk into, a hayloft
## up a ramp, stalls, and the yard by the doors, dressed with every prop in
## the pool. Scenery copies of each prop are one MultiMesh (one draw call
## per kind) with a solid box each, so paint can land on them.

const LAYER_WORLD := 1
const LAYER_PLAYERS := 2
const LAYER_PROPS := 4


const LOFT_Y := 3.0

## The barn's inside has four areas (owner, 2026-11-25): horse stalls down
## the west side, a tool corner and a tractor bay under the loft, and a hay
## corner in the south-east, so it isn't one big room.
const STALL_FRONT := -4.4                     # stall fronts face the aisle here
const STALL_EDGES := [-11.85, -8.4, -4.95, -1.5, 1.95]
const TRACTOR := Vector3(4.0, 0.0, 8.0)       # parked facing the north door

## [kind, position, yaw] for props standing on something.
const STANDING := [
	# Loft bales.
	["bale", Vector3(-6.0, LOFT_Y, 6.0), 0.0], ["bale", Vector3(-6.0, LOFT_Y + 0.5, 6.0), 0.0],
	["bale", Vector3(-4.9, LOFT_Y, 6.0), 0.0], ["bale", Vector3(-6.0, LOFT_Y, 7.1), 0.0],
	["bale", Vector3(-4.9, LOFT_Y, 7.1), 0.0], ["bale", Vector3(-4.9, LOFT_Y + 0.5, 7.1), 0.0],
	["bale", Vector3(-6.0, LOFT_Y + 0.5, 7.1), 0.0], ["bale", Vector3(-6.0, LOFT_Y + 1.0, 7.1), 0.0],
	["bale", Vector3(-2.5, LOFT_Y, 10.8), PI / 2], ["bale", Vector3(-2.5, LOFT_Y + 0.5, 10.8), PI / 2],
	# Loose bales in the hay corner and the aisle (the stacked steps are added in scenery()).
	["bale", Vector3(2.9, 0.0, -8.3), 0.4], ["bale", Vector3(5.3, 0.0, -8.5), -0.15], ["bale", Vector3(-1.0, 0.0, 6.0), 0.3],
	# Trash cans by the doors, inside and out, and in the tool corner.
	["trash_can", Vector3(2.8, 0.0, 11.2), 0.0], ["trash_can", Vector3(3.5, 0.0, 11.2), 0.4],
	["trash_can", Vector3(-3.0, 0.0, 12.9), 0.0], ["trash_can", Vector3(3.0, 0.0, -12.9), 1.0],
	["trash_can", Vector3(-4.0, 0.0, 5.2), 0.2],
	# Tires stacked in the tractor bay, two in the yard.
	["tire", Vector3(6.9, 0.0, 10.9), 0.0], ["tire", Vector3(6.9, 0.2, 10.9), 0.5], ["tire", Vector3(6.9, 0.4, 10.9), 1.1],
	["tire", Vector3(6.9, 0.0, 9.9), 0.0], ["tire", Vector3(4.0, 0.0, 14.0), 0.0], ["tire", Vector3(4.9, 0.0, 14.4), 0.0],
	# Chairs: one at the workbench.
	["chair", Vector3(-2.6, 0.0, -10.6), 0.3], ["chair", Vector3(3.0, 0.0, 2.0), -2.2],
	["chair", Vector3(2.0, LOFT_Y, 10.4), PI], ["chair", Vector3(-1.5, 0.0, 14.0), 2.6],
	["chair", Vector3(-6.4, 0.0, 6.4), -PI / 2],
	# Crates on the tool corner's shelves and by the south door.
	["crate", Vector3(-6.9, 0.14, 11.55), 0.0], ["crate", Vector3(-5.7, 0.14, 11.55), 0.0],
	["crate", Vector3(-3.0, 0.0, -11.2), 0.0], ["crate", Vector3(-2.4, 0.0, -11.3), 0.3],
	["crate", Vector3(0.0, LOFT_Y, 11.0), 0.6],
	# Buckets: one in each stall, on the workbench and shelf, by the doors.
	["bucket", Vector3(-7.4, 0.0, -11.4), 0.0], ["bucket", Vector3(-7.4, 0.0, -7.95), 0.0],
	["bucket", Vector3(-7.4, 0.0, -4.5), 0.0], ["bucket", Vector3(-7.4, 0.0, -1.05), 0.0],
	["bucket", Vector3(-7.45, 0.96, 7.5), 0.0], ["bucket", Vector3(-6.3, 0.79, 11.55), 0.0],
	["bucket", Vector3(2.2, 0.0, 11.5), 0.0], ["bucket", Vector3(-4.0, 0.0, 13.5), 0.0],
	# In the farmhouse: kitchen chairs round the table, a trash can and a
	# bucket in the kitchen, a crate (toy box) and chairs upstairs.
	["chair", Vector3(-22.4, 0.3, 6.85), PI], ["chair", Vector3(-21.2, 0.3, 6.85), PI],
	["chair", Vector3(-22.4, 0.3, 8.4), 0.0], ["chair", Vector3(-21.2, 0.3, 8.4), 0.0],
	["trash_can", Vector3(-20.5, 0.3, 9.0), 0.0], ["bucket", Vector3(-23.5, 1.2, 4.6), 0.0],
	["crate", Vector3(-23.2, 0.3, 1.8), 0.3], ["crate", Vector3(-21.2, 3.0, -0.9), 0.0],
	["chair", Vector3(-16.8, 3.0, 3.6), -PI / 2], ["bucket", Vector3(-20.6, 3.0, 5.0), 0.0],
]

## [kind, point on the wall at the ground, wall's outward normal]: props
## leaning against a wall.
const LEANING := [
	["rake", Vector3(7.85, 0.0, -4.0), Vector3(-1, 0, 0)],
	["rake", Vector3(7.85, 0.0, -3.0), Vector3(-1, 0, 0)],
	["rake", Vector3(-3.4, 0.0, 11.85), Vector3(0, 0, -1)],
	["rake", Vector3(-2.9, 0.0, 11.85), Vector3(0, 0, -1)],
	["rake", Vector3(5.0, 0.0, 12.15), Vector3(0, 0, 1)],
	["rake", Vector3(-4.0, 0.0, -11.85), Vector3(0, 0, 1)],
]

## Hand-placed hiding spots for sandbox hiders and, later, bots (design 12).
const SPOTS := [
	["bale", Vector3(4.3, 0.5, -9.7), 0.0],          # on the hay steps
	["bale", Vector3(-3.8, LOFT_Y, 6.0), 0.0],
	["trash_can", Vector3(4.2, 0.0, 11.2), 0.0],
	["tire", Vector3(6.9, 0.6, 10.9), 0.0],          # on top of the tire stack
	["chair", Vector3(-3.6, 0.0, -10.2), 0.0],
	["crate", Vector3(-3.0, 0.6, -11.2), 0.0],
	["bucket", Vector3(-7.4, 0.0, 1.5), 0.0],        # in the last stall
	["bucket", Vector3(-7.45, 0.96, 6.6), 0.0],      # on the workbench
	["rake", Vector3(7.85, 0.0, -5.0), Vector3(-1, 0, 0)],
	["rake", Vector3(-2.45, 0.0, 11.85), Vector3(0, 0, -1)],
	["chair", Vector3(-20.7, 0.3, 4.7), 0.4],        # a spare kitchen chair by the wall
	["bucket", Vector3(-23.5, 1.2, 2.0), 0.0],       # on the kitchen counter
	["crate", Vector3(-23.3, 3.0, 2.6), 0.2],        # upstairs, back bedroom
	["trash_can", Vector3(-17.0, 0.3, -1.0), 0.0],   # living room corner
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
	# Hay corner: bales stacked in steps against the south and east walls,
	# four high at the back down to one at the front.
	for col in [7.3, 6.3, 5.3, 4.3]:
		for row in 4:
			for h in 4 - row:
				out.append(["bale", Transform3D(Basis(), Vector3(col, h * 0.5, -11.5 + row * 0.6))])
	for s in STANDING:
		out.append([s[0], Transform3D(Basis(Vector3.UP, s[2]), s[1])])
	for s in LEANING:
		out.append([s[0], lean_transform(s[0], s[1], s[2])])
	return out


## Where the farmhouse and silo stand (outsides only until the H1 farm).
const HOUSE := Vector3(-20.0, 0.0, 4.0)
const SILO := Vector3(13.5, 0.0, -7.0)


static func build(root: Node3D) -> void:
	var b := Surfaces.Builder.new()
	var solid := StaticBody3D.new()
	solid.name = "Solid"
	solid.add_to_group("nav")
	solid.collision_layer = LAYER_WORLD
	solid.collision_mask = 0
	root.add_child(solid)

	# Ground: grass, with packed dirt at the barn doors and the porch.
	_block(b, "grass", solid, Vector3(70, 1, 70), Vector3(0, -0.5, 0))
	# Grass on out to the horizon (looks only; the play area is 70 m).
	for i in 4:
		var d := Vector3.FORWARD.rotated(Vector3.UP, i * PI / 2)
		var side := d.cross(Vector3.UP).abs()
		b.box("grass", side * 470 + d.abs() * 200 + Vector3(0, 0.2, 0), d * 135 + Vector3(0, -0.1, 0))
	for z in [-14.5, 14.5]:
		_block(b, "dirt", null, Vector3(7, 0.02, 5), Vector3(0, 0.01, z))
	_block(b, "dirt", null, Vector3(5, 0.02, 7), HOUSE + Vector3(7.9, 0.01, 0.0))
	_barn(b, solid)
	_house(b, solid, root)
	_silo(b, solid)
	Boundary.build(root, b, solid)
	Meadow.build(root)
	root.add_child(b.commit("Buildings"))
	_tractor(root, solid)

	# Scenery props: one MultiMesh per kind, a solid box each.
	var by_kind := {}
	for s in scenery():
		by_kind.get_or_add(s[0], []).append(s[1])
	var props := Node3D.new()
	props.name = "Scenery"
	props.add_to_group("nav")
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


## The red barn: board-and-batten siding, white trim, open sliding doors
## with X braces, a metal roof, plank floors.
static func _barn(b: Surfaces.Builder, solid: StaticBody3D) -> void:
	_block(b, "floor", null, Vector3(15.7, 0.02, 23.7), Vector3(0, 0.01, 0))
	for x in [-8.0, 8.0]:
		_block(b, "barn_siding", solid, Vector3(0.3, 5, 24.3), Vector3(x, 2.5, 0))
	for z in [-12.0, 12.0]:
		for x in [-5.0, 5.0]:
			_block(b, "barn_siding", solid, Vector3(6, 5, 0.3), Vector3(x, 2.5, z))
		_block(b, "barn_siding", solid, Vector3(4, 1, 0.3), Vector3(0, 4.5, z))
		var out: float = signf(z)
		# Gable: outside and inside faces.
		var zo: float = z + out * 0.15
		var zi: float = z - out * 0.15
		if out > 0:
			b.tri("barn_siding", Vector3(-8, 5, zo), Vector3(8, 5, zo), Vector3(0, 8, zo))
			b.tri("barn_siding", Vector3(-8, 5, zi), Vector3(0, 8, zi), Vector3(8, 5, zi))
		else:
			b.tri("barn_siding", Vector3(-8, 5, zo), Vector3(0, 8, zo), Vector3(8, 5, zo))
			b.tri("barn_siding", Vector3(-8, 5, zi), Vector3(8, 5, zi), Vector3(0, 8, zi))
		# Trim: door frame, hayloft door, corners.
		var tz: float = z + out * 0.06
		for x in [-2.12, 2.12]:
			_block(b, "trim", null, Vector3(0.25, 4.25, 0.42), Vector3(x, 2.12, tz))
		_block(b, "trim", null, Vector3(4.5, 0.25, 0.42), Vector3(0, 4.12, tz))
		_frame(b, Vector3(0, 6.1, z + out * 0.17), Vector2(2.0, 1.8), out)
		_block(b, "dark", null, Vector3(1.8, 1.6, 0.04), Vector3(0, 6.1, z + out * 0.155))
		for x in [-8.0, 8.0]:
			_block(b, "trim", null, Vector3(0.42, 5.0, 0.42), Vector3(x, 2.5, z))
		# Sliding doors, slid open, and their track.
		_block(b, "dark", null, Vector3(10.2, 0.14, 0.12), Vector3(0, 4.3, z + out * 0.24))
		for side in [-1.0, 1.0]:
			_barn_door(b, solid, Vector3(side * 3.15, 2.05, z + out * 0.25), out)
	# Roof: two slopes from the eaves (5 m) to the ridge (8 m), overhanging.
	var slope := atan2(3.0, 8.0)
	for side in [-1.0, 1.0]:
		var rb := Basis(Vector3.BACK, side * -slope)
		_block(b, "barn_roof", solid, Vector3(9.4, 0.12, 25.4), Vector3(side * 4.2, 6.55, 0), rb)
	_stalls(b, solid)
	_tool_corner(b, solid)
	# Hayloft over the north third, its railing, and a ramp up the east wall.
	_block(b, "floor", solid, Vector3(15.7, 0.3, 7.85), Vector3(0, LOFT_Y - 0.15, 7.92))
	_block(b, "floor", solid, Vector3(13.4, 0.9, 0.12), Vector3(-1.15, LOFT_Y + 0.45, 4.05))
	var run := Vector3(0, LOFT_Y, 6.2)
	var ramp_basis := Basis(Vector3.RIGHT, -atan2(run.y, run.z))
	_block(b, "floor", solid, Vector3(1.4, 0.2, run.length()), Vector3(7.1, LOFT_Y / 2 - 0.1, 4.0 - run.z / 2), ramp_basis)


## Four horse stalls down the west wall: board walls with black bars above,
## a front with an open gate, straw bedding, a hay rack and a water bucket.
static func _stalls(b: Surfaces.Builder, solid: StaticBody3D) -> void:
	var back := -7.85
	var depth := STALL_FRONT - back
	var mid_x := (back + STALL_FRONT) / 2
	for z in STALL_EDGES.slice(1):
		_bar_wall(b, solid, Vector3(mid_x, 0, z), depth, "x")
	for i in STALL_EDGES.size() - 1:
		var z0: float = STALL_EDGES[i]
		var z1: float = STALL_EDGES[i + 1]
		# Front: boards and bars along 2 m, then the gate, swung open.
		var front_len := (z1 - z0) - 1.35
		_bar_wall(b, solid, Vector3(STALL_FRONT, 0, z0 + front_len / 2), front_len, "z")
		_block(b, "floor", solid, Vector3(0.14, 2.35, 0.14), Vector3(STALL_FRONT, 1.17, z1 - 0.05))
		var gate_at := Vector3(STALL_FRONT + 0.62, 0, z1 - 1.35)
		_block(b, "floor", solid, Vector3(1.2, 1.15, 0.06), gate_at + Vector3(0, 0.7, 0))
		for y in [0.25, 1.15]:
			_block(b, "bars", null, Vector3(1.24, 0.06, 0.08), gate_at + Vector3(0, y, 0))
		# Straw bedding with a heap or two.
		_block(b, "straw", null, Vector3(depth - 0.1, 0.03, z1 - z0 - 0.12), Vector3(mid_x, 0.035, (z0 + z1) / 2))
		b.dome("straw", 0.75, 0.22, Vector3(mid_x - 0.6, 0.03, (z0 + z1) / 2 + 0.5), 16, 4)
		# Hay rack on the back wall, with hay in it.
		var rz := (z0 + z1) / 2
		_block(b, "bars", null, Vector3(0.05, 0.05, 1.3), Vector3(back + 0.45, 1.85, rz))
		_block(b, "bars", null, Vector3(0.05, 0.05, 1.3), Vector3(back + 0.04, 1.15, rz))
		var slope := atan2(0.41, 0.7)
		for k in 7:
			var bz := rz - 0.6 + k * 0.2
			_block(b, "bars", null, Vector3(0.03, 0.81, 0.03), Vector3(back + 0.245, 1.5, bz), Basis(Vector3.BACK, slope))
		_block(b, "straw", null, Vector3(0.3, 0.5, 1.2), Vector3(back + 0.2, 1.62, rz), Basis(Vector3.BACK, slope * 0.6))


## A stall wall: boards to 1.3 m, black bars above to 2.2 m. `along` is the
## axis it runs along ("x" or "z"); `at` its middle at the floor.
static func _bar_wall(b: Surfaces.Builder, solid: StaticBody3D, at: Vector3, length: float, along: String) -> void:
	var d := Vector3(1, 0, 0) if along == "x" else Vector3(0, 0, 1)
	var thin := Vector3(0, 0, 1) if along == "x" else Vector3(1, 0, 0)
	var size := func(l: float, h: float, t: float) -> Vector3: return d * l + Vector3(0, h, 0) + thin * t
	_block(b, "floor", null, size.call(length, 1.3, 0.08), at + Vector3(0, 0.65, 0))
	_block(b, "bars", null, size.call(length, 0.06, 0.1), at + Vector3(0, 2.2, 0))
	var n := int(length / 0.16)
	for k in n:
		var off := -length / 2 + (k + 0.5) * length / n
		_block(b, "bars", null, size.call(0.03, 0.9, 0.03), at + d * off + Vector3(0, 1.75, 0))
	# One solid box for the whole wall: you can't jump over 2.2 m.
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size.call(length, 2.25, 0.12)
	cs.shape = box
	cs.position = at + Vector3(0, 1.125, 0)
	solid.add_child(cs)


## The tool corner under the loft (north-west): a workbench with a pegboard
## of hanging tools, shelves, and long-handled tools on the north wall.
static func _tool_corner(b: Surfaces.Builder, solid: StaticBody3D) -> void:
	var wall := -7.85
	var bench := Vector3(wall + 0.38, 0, 7.2)
	_block(b, "floor", solid, Vector3(0.75, 0.08, 4.0), bench + Vector3(0, 0.92, 0))
	_block(b, "floor", null, Vector3(0.7, 0.04, 3.9), bench + Vector3(0, 0.25, 0))
	for z in [-1.9, 1.9]:
		for x in [-0.3, 0.3]:
			_block(b, "handle", null, Vector3(0.07, 0.88, 0.07), bench + Vector3(x, 0.44, z))
	# On the bench: a toolbox, a vise, paint cans.
	_block(b, "toolbox", solid, Vector3(0.32, 0.24, 0.55), bench + Vector3(0, 1.08, -1.2))
	_block(b, "metal", null, Vector3(0.26, 0.03, 0.3), bench + Vector3(0, 1.21, -1.2))
	_block(b, "metal", null, Vector3(0.2, 0.18, 0.12), bench + Vector3(0.2, 1.05, 0.9))
	for i in 3:
		b.cylinder("metal", 0.08, 0.16, bench + Vector3(-0.1 + i * 0.03, 0.96, 1.5 + i * 0.18), 12)
	# Pegboard and hanging tools: hammers, wrenches, a saw, screwdrivers.
	var pb := Vector3(wall + 0.02, 1.75, 7.2)
	_block(b, "pegboard", null, Vector3(0.03, 1.1, 3.6), pb)
	var tool_x := wall + 0.06
	for i in 3:
		var tz := 5.7 + i * 0.35
		_block(b, "handle", null, Vector3(0.03, 0.34, 0.035), Vector3(tool_x, 1.6, tz))
		_block(b, "metal", null, Vector3(0.04, 0.05, 0.14), Vector3(tool_x, 1.79, tz))
	for i in 4:
		var wz := 6.9 + i * 0.16
		var l := 0.18 + i * 0.05
		_block(b, "metal", null, Vector3(0.02, l, 0.035), Vector3(tool_x, 1.95 - l / 2, wz))
	_block(b, "metal", null, Vector3(0.015, 0.16, 0.6), Vector3(tool_x, 1.55, 7.9))
	_block(b, "handle", null, Vector3(0.04, 0.14, 0.12), Vector3(tool_x, 1.58, 8.25))
	for i in 4:
		var sz := 8.6 + i * 0.12
		_block(b, "toolbox", null, Vector3(0.03, 0.1, 0.03), Vector3(tool_x, 1.95, sz))
		_block(b, "metal", null, Vector3(0.015, 0.16, 0.015), Vector3(tool_x, 1.82, sz))
	# Shelves on the north wall.
	var sh := Vector3(-6.3, 0, 11.6)
	for x in [-1.28, 1.28]:
		for z in [-0.22, 0.22]:
			_block(b, "metal", solid, Vector3(0.05, 2.2, 0.05), sh + Vector3(x, 1.1, z))
	for y in [0.12, 0.77, 1.42, 2.07]:
		_block(b, "floor", solid, Vector3(2.6, 0.04, 0.5), sh + Vector3(0, y, 0))
	for i in 6:
		b.cylinder("toolbox" if i % 2 == 0 else "metal", 0.09, 0.18, sh + Vector3(-1.1 + i * 0.35, 1.44, 0.0), 12)
	_block(b, "toolbox", null, Vector3(0.5, 0.3, 0.35), sh + Vector3(0.6, 2.24, 0))
	# Long tools hanging on the north wall: a shovel, a pitchfork, a hoe.
	for i in 3:
		var tx := -4.8 + i * 0.4
		var wz := 11.8
		_block(b, "handle", null, Vector3(0.035, 1.3, 0.035), Vector3(tx, 1.25, wz))
		match i:
			0:
				_block(b, "metal", null, Vector3(0.24, 0.32, 0.02), Vector3(tx, 0.48, wz))
			1:
				for t in 4:
					_block(b, "metal", null, Vector3(0.015, 0.3, 0.015), Vector3(tx - 0.09 + t * 0.06, 0.45, wz))
				_block(b, "metal", null, Vector3(0.22, 0.03, 0.02), Vector3(tx, 0.6, wz))
			2:
				_block(b, "metal", null, Vector3(0.18, 0.12, 0.015), Vector3(tx, 0.56, wz - 0.03))
	_block(b, "handle", null, Vector3(1.3, 0.05, 0.04), Vector3(-4.4, 1.92, 11.83))


## The tractor bay: the tractor model, parked facing the north door, with a
## few solid boxes for its body and wheels.
static func _tractor(root: Node3D, solid: StaticBody3D) -> void:
	var path := "res://assets/models/tractor.glb"
	if not ResourceLoader.exists(path):
		return
	var inst := (load(path) as PackedScene).instantiate()
	var mi := inst.find_children("*", "MeshInstance3D", true, false)
	if mi.is_empty():
		inst.free()
		return
	var t := MeshInstance3D.new()
	t.name = "Tractor"
	t.mesh = (mi[0] as MeshInstance3D).mesh
	# Keep the model's own offset (the tractor's origin isn't at its base):
	# without it the tractor sat 0.5 m into the floor, off its solid boxes.
	var own := (mi[0] as Node3D).transform
	inst.free()
	t.transform = Transform3D(Basis(Vector3.UP, PI), TRACTOR) * own
	root.add_child(t)
	for box in [[Vector3(1.95, 1.5, 1.6), Vector3(0, 0.75, -0.75)], [Vector3(1.35, 1.4, 2.2), Vector3(0, 0.7, 0.6)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box[0]
		cs.shape = bs
		cs.position = TRACTOR + box[1]
		solid.add_child(cs)


## One leaf of a sliding barn door: red boards in a white frame with an X.
static func _barn_door(b: Surfaces.Builder, solid: StaticBody3D, at: Vector3, out: float) -> void:
	var w := 2.1
	var h := 4.1
	_block(b, "barn_siding", solid, Vector3(w, h, 0.1), at)
	var f := at + Vector3(0, 0, out * 0.07)
	_frame(b, f, Vector2(w, h), out)
	var diag := Vector2(w - 0.3, h - 0.3)
	var ang := atan2(diag.y, diag.x)
	for sgn in [-1.0, 1.0]:
		_block(b, "trim", null, Vector3(diag.length(), 0.16, 0.05), f, Basis(Vector3.BACK, sgn * ang))


## A white trim frame (width x height) facing out along z.
static func _frame(b: Surfaces.Builder, at: Vector3, size: Vector2, out: float) -> void:
	var t := 0.16
	for x in [-1.0, 1.0]:
		_block(b, "trim", null, Vector3(t, size.y, 0.05), at + Vector3(x * (size.x - t) / 2, 0, 0))
	for y in [-1.0, 1.0]:
		_block(b, "trim", null, Vector3(size.x, t, 0.05), at + Vector3(0, y * (size.y - t) / 2, 0))


## The farmhouse: two storeys of white lap siding on a concrete footing, a
## shingle roof, windows, and inside (owner, 2026-11-27: explorable, simple
## enough to search). Downstairs the front door opens into the living room;
## wide doorways lead to the kitchen and a small bedroom. Straight stairs go
## up to a landing and two bedrooms. Doorways are 1.2 m, no dead ends.
const HOUSE_FLOOR := 0.3         # ground floor, level with the porch
const HOUSE_UP := 3.0            # upstairs floor
const DOOR_W := 1.2
const DOOR_H := 2.2


static func _house(b: Surfaces.Builder, solid: StaticBody3D, root: Node3D = null) -> void:
	var c := HOUSE
	var hw := 4.0           # half width (x); the front (+x) faces the barn
	var hl := 5.5           # half length (z); the ridge runs along z
	var top := 6.0
	var rise := 2.6
	var t := 0.25           # outer wall thickness
	var ix := hw - t / 2    # inner faces
	var iz := hl - t / 2
	_block(b, "concrete", solid, Vector3(hw * 2 + 0.3, HOUSE_FLOOR, hl * 2 + 0.3), c + Vector3(0, HOUSE_FLOOR / 2, 0))
	_block(b, "floor", null, Vector3(hw * 2 - t, 0.02, hl * 2 - t), c + Vector3(0, HOUSE_FLOOR + 0.01, 0))
	var wall_h := top - HOUSE_FLOOR
	var wy := HOUSE_FLOOR + wall_h / 2
	# Outer walls; the front one has the door.
	# Windows: [along, centre height], cut through the walls so you can
	# see in and out (owner, 2026-11-27).
	var side_wins := [[c.z - 3.0, 1.9], [c.z + 3.0, 1.9], [c.z - 3.0, 4.5], [c.z, 4.5], [c.z + 3.0, 4.5]]
	var end_wins := [[c.x - 2.0, 1.9], [c.x + 2.0, 1.9], [c.x - 2.0, 4.5], [c.x + 2.0, 4.5]]
	_wall_along_z(b, solid, "house_siding", c.x - hw, c.z - hl, c.z + hl, HOUSE_FLOOR, top, t, [], side_wins)
	_wall_along_z(b, solid, "house_siding", c.x + hw, c.z - hl, c.z + hl, HOUSE_FLOOR, top, t, [c.z], side_wins)
	for z in [-hl, hl]:
		_wall_along_x(b, solid, "house_siding", c.z + z, c.x - hw, c.x + hw, HOUSE_FLOOR, top, t, [], end_wins)
		var zo: float = c.z + z + signf(z) * 0.125
		var l := Vector3(c.x - hw, top, zo)
		var r := Vector3(c.x + hw, top, zo)
		var apex := Vector3(c.x, top + rise, zo)
		if z > 0:
			b.tri("house_siding", l, r, apex)
		else:
			b.tri("house_siding", l, apex, r)
		_window(b, c + Vector3(0, 7.0, z + signf(z) * 0.14), "z", signf(z), false)
		for x in [-2.0, 2.0]:
			_window(b, c + Vector3(x, 1.9, z + signf(z) * 0.14), "z", signf(z))
			_window(b, c + Vector3(x, 4.5, z + signf(z) * 0.14), "z", signf(z))
			_pane(b, c + Vector3(x, 1.9, z - signf(z) * (t / 2 + 0.01)), "z")
			_pane(b, c + Vector3(x, 4.5, z - signf(z) * (t / 2 + 0.01)), "z")
	for x in [-hw, hw]:
		for z in [-hl, hl]:
			_block(b, "trim", null, Vector3(0.36, wall_h, 0.36), c + Vector3(x, wy, z))
	for zz in [-3.0, 3.0]:
		_window(b, c + Vector3(hw + 0.14, 1.9, zz), "x", 1.0)
		_window(b, c + Vector3(-hw - 0.14, 1.9, zz), "x", -1.0)
		_pane(b, c + Vector3(ix - 0.01, 1.9, zz), "x")
		_pane(b, c + Vector3(-ix + 0.01, 1.9, zz), "x")
	for zz in [-3.0, 0.0, 3.0]:
		_window(b, c + Vector3(hw + 0.14, 4.5, zz), "x", 1.0)
		_window(b, c + Vector3(-hw - 0.14, 4.5, zz), "x", -1.0)
		_pane(b, c + Vector3(ix - 0.01, 4.5, zz), "x")
		_pane(b, c + Vector3(-ix + 0.01, 4.5, zz), "x")
	# Inside the outer walls: wallpaper downstairs, plaster upstairs.
	for floor_ in [[HOUSE_FLOOR, HOUSE_UP - 0.15, "wallpaper"], [HOUSE_UP, top, "plaster"]]:
		var y0: float = floor_[0]
		var y1: float = floor_[1]
		var surf: String = floor_[2]
		_wall_along_z(b, null, surf, c.x - ix + 0.01, c.z - iz, c.z + iz, y0, y1, 0.02, [], side_wins)
		_wall_along_z(b, null, surf, c.x + ix - 0.01, c.z - iz, c.z + iz, y0, y1, 0.02, [c.z] if y0 < 1.0 else [], side_wins)
		for z in [-iz + 0.01, iz - 0.01]:
			_wall_along_x(b, null, surf, c.z + z, c.x - ix, c.x + ix, y0, y1, 0.02, [], end_wins)
	# The front door, swung open into the living room, and its frame.
	_block(b, "door", null, Vector3(1.05, 2.15, 0.06), c + Vector3(hw - 0.66, HOUSE_FLOOR + 1.08, -0.63))
	_frame_x(b, c + Vector3(hw + 0.15, HOUSE_FLOOR + DOOR_H / 2 + 0.05, 0), Vector2(DOOR_W + 0.25, DOOR_H + 0.15))
	# Upstairs floor (the ceiling below), with the stairwell open.
	var sw0 := 2.375                # stairwell: x from here to the front wall
	var st_top := 1.0               # stairs climb towards -z, top end here
	var st_bot := 4.6               # 0.8 m clear of the back wall to step on
	var slab_y := HOUSE_UP - 0.075
	_block(b, "floor", solid, Vector3(ix + sw0, 0.15, iz * 2), c + Vector3((sw0 - ix) / 2, slab_y, 0))
	_block(b, "floor", solid, Vector3(ix - sw0, 0.15, st_top + iz), c + Vector3((sw0 + ix) / 2, slab_y, (st_top - iz) / 2))
	_block(b, "plaster", null, Vector3(ix * 2, 0.1, iz * 2), c + Vector3(0, top - 0.05, 0))
	# Stairs: a ramp to walk on, drawn as steps, closed underneath.
	var run := st_bot - st_top
	var up := HOUSE_UP - HOUSE_FLOOR
	var steps := 14
	for i in steps:
		var z0 := st_bot - (i + 1) * run / steps
		var h := (i + 1) * up / steps
		_block(b, "floor", null, Vector3(ix - sw0 - 0.02, h, run / steps), c + Vector3((sw0 + ix) / 2, HOUSE_FLOOR + h / 2, z0 + run / steps / 2))
	var ramp := Basis(Vector3.RIGHT, atan2(up, run))
	var cs := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(ix - sw0, 0.1, sqrt(run * run + up * up))
	cs.shape = rb
	cs.transform = Transform3D(ramp, c + Vector3((sw0 + ix) / 2, HOUSE_FLOOR + up / 2 - 0.02, (st_top + st_bot) / 2))
	solid.add_child(cs)
	# Railing round the stairwell upstairs.
	_block(b, "handle", solid, Vector3(0.08, 0.95, iz - st_top), c + Vector3(sw0, HOUSE_UP + 0.47, (st_top + iz) / 2))
	for i in 9:
		_block(b, "handle", null, Vector3(0.05, 0.9, 0.05), c + Vector3(sw0, HOUSE_UP + 0.45, st_top + i * (iz - st_top) / 8))
	# Downstairs rooms: a wall at x = 0 with doorways to the bedroom (back
	# left) and the kitchen (back right), and a wall between those two.
	_wall_along_z(b, solid, "wallpaper", c.x, c.z - iz, c.z + iz, HOUSE_FLOOR, HOUSE_UP - 0.15, 0.12, [c.z - 3.2, c.z + 2.2])
	_wall_along_x(b, solid, "wallpaper", c.z - 1.0, c.x - ix, c.x, HOUSE_FLOOR, HOUSE_UP - 0.15, 0.12, [])
	# Upstairs: bedroom A at the front (door off the landing), bedroom B at
	# the back (door off the landing).
	_wall_along_z(b, solid, "plaster", c.x, c.z - iz, c.z + iz, HOUSE_UP, top - 0.1, 0.12, [c.z + 3.5])
	_wall_along_x(b, solid, "plaster", c.z, c.x, c.x + ix, HOUSE_UP, top - 0.1, 0.12, [c.x + 1.2])
	_furnish(b, solid, c)
	# Roof, overhanging 0.5 m all round, and a chimney.
	var ang := atan2(rise, hw)
	var rrun := hw + 0.5
	var slab := rrun / cos(ang)
	for side in [-1.0, 1.0]:
		var rbs := Basis(Vector3.BACK, side * -ang)
		var mid := Vector3(c.x + side * rrun / 2, top + rise - tan(ang) * rrun / 2 + 0.06, c.z)
		_block(b, "shingles", solid, Vector3(slab, 0.14, hl * 2 + 1.0), mid, rbs)
	_block(b, "concrete", null, Vector3(0.8, 2.2, 0.8), c + Vector3(-1.6, top + rise - 0.2, 3.6))
	# Porch: level with the floor, a ramp up its steps, a roof on posts.
	_block(b, "concrete", solid, Vector3(3.2, HOUSE_FLOOR, 5.4), c + Vector3(hw + 1.6, HOUSE_FLOOR / 2, 0))
	_block(b, "concrete", null, Vector3(0.5, 0.15, 2.0), c + Vector3(hw + 3.45, 0.075, 0))
	var pr := CollisionShape3D.new()
	var prb := BoxShape3D.new()
	prb.size = Vector3(1.4, 0.1, 2.0)
	pr.shape = prb
	pr.transform = Transform3D(Basis(Vector3.BACK, atan2(HOUSE_FLOOR, 1.3)), c + Vector3(hw + 3.75, HOUSE_FLOOR / 2 - 0.05, 0))
	solid.add_child(pr)
	for z in [-2.5, 2.5]:
		_block(b, "trim", solid, Vector3(0.18, 2.8, 0.18), c + Vector3(hw + 3.0, 1.7, z))
	_block(b, "shingles", solid, Vector3(3.6, 0.12, 5.8), c + Vector3(hw + 1.75, 3.2, 0), Basis(Vector3.BACK, -0.18))
	# Warm lamps in each room (no shadows: cheap).
	if root and Props.house_lamps:
		for at in [Vector3(2, 2.4, -2.5), Vector3(-2, 2.4, 2.5), Vector3(-2, 2.4, -3.2), Vector3(2, 5.4, -2.5), Vector3(-2, 5.4, 0.5), Vector3(1.2, 5.4, 3.0)]:
			var lamp := OmniLight3D.new()
			lamp.position = c + at
			lamp.omni_range = 4.2
			lamp.light_energy = 0.9
			lamp.light_color = Color(1.0, 0.88, 0.7)
			lamp.shadow_enabled = false
			root.add_child(lamp)


const WIN_W := 1.0
const WIN_H := 1.35


## A wall running along z at `x`, from z0 to z1, y0 to y1, with 1.2 m
## doorways centred at `doors` (z) and window openings at `windows`
## ([z, centre height]). Windows are open to the eye but not to bodies:
## the collision has only the doorways cut out.
static func _wall_along_z(b: Surfaces.Builder, solid: StaticBody3D, surf: String, x: float, z0: float, z1: float, y0: float, y1: float, thick: float, doors: Array, windows := []) -> void:
	_wall(b, solid, surf, "z", x, z0, z1, y0, y1, thick, doors, windows)


static func _wall_along_x(b: Surfaces.Builder, solid: StaticBody3D, surf: String, z: float, x0: float, x1: float, y0: float, y1: float, thick: float, doors: Array, windows := []) -> void:
	_wall(b, solid, surf, "x", z, x0, x1, y0, y1, thick, doors, windows)


static func _wall(b: Surfaces.Builder, solid: StaticBody3D, surf: String, axis: String, fixed: float, a0: float, a1: float, y0: float, y1: float, thick: float, doors: Array, windows: Array) -> void:
	var door_holes := []
	for d in doors:
		door_holes.append([d - DOOR_W / 2, d + DOOR_W / 2, y0, y0 + DOOR_H])
	var holes := door_holes.duplicate()
	for w in windows:
		if w[1] - WIN_H / 2 > y0 and w[1] + WIN_H / 2 < y1:
			holes.append([w[0] - WIN_W / 2, w[0] + WIN_W / 2, w[1] - WIN_H / 2, w[1] + WIN_H / 2])
	_wall_pieces(b, null, surf, axis, fixed, a0, a1, y0, y1, thick, holes)
	if solid:
		_wall_pieces(null, solid, surf, axis, fixed, a0, a1, y0, y1, thick, door_holes)


## Fills a wall rectangle with boxes around rectangular holes ([a0, a1,
## y0, y1] each): column by column between hole edges.
static func _wall_pieces(b: Surfaces.Builder, solid: StaticBody3D, surf: String, axis: String, fixed: float, a0: float, a1: float, y0: float, y1: float, thick: float, holes: Array) -> void:
	var edges := [a0, a1]
	for h in holes:
		for e in [h[0], h[1]]:
			if e > a0 and e < a1 and not edges.has(e):
				edges.append(e)
	edges.sort()
	for i in edges.size() - 1:
		var p: float = edges[i]
		var q: float = edges[i + 1]
		if q - p < 0.001:
			continue
		var mid := (p + q) / 2
		var gaps := holes.filter(func(h): return h[0] <= mid and mid <= h[1])
		gaps.sort_custom(func(g, k): return g[2] < k[2])
		var spans := []
		var cur := y0
		for g in gaps:
			if g[2] > cur:
				spans.append([cur, g[2]])
			cur = maxf(cur, g[3])
		if y1 > cur:
			spans.append([cur, y1])
		for sp in spans:
			var size := Vector3(thick, sp[1] - sp[0], q - p) if axis == "z" else Vector3(q - p, sp[1] - sp[0], thick)
			var at := Vector3(fixed, (sp[0] + sp[1]) / 2, mid) if axis == "z" else Vector3(mid, (sp[0] + sp[1]) / 2, fixed)
			if b:
				b.box(surf, size, at)
			if solid:
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = size
				cs.shape = box
				cs.position = at
				solid.add_child(cs)


## A window seen from inside: its white frame (the glass is outside).
static func _pane(b: Surfaces.Builder, at: Vector3, axis: String) -> void:
	var s := func(along: float, up: float, thick: float) -> Vector3:
		return Vector3(thick, up, along) if axis == "x" else Vector3(along, up, thick)
	_block(b, "trim", null, s.call(1.24, 0.1, 0.05), at + Vector3(0, 0.72, 0))
	_block(b, "trim", null, s.call(1.3, 0.1, 0.12), at + Vector3(0, -0.72, 0))


## Furniture: a few big pieces in every room for hiders to sit beside and
## seekers to search. Local coordinates from the house's centre.
static func _furnish(b: Surfaces.Builder, solid: StaticBody3D, c: Vector3) -> void:
	var f := HOUSE_FLOOR
	var u := HOUSE_UP
	var piece := func(surf: String, size: Vector3, at: Vector3, collide := true) -> void:
		_block(b, surf, solid if collide else null, size, c + at + Vector3(0, size.y / 2, 0))
	# Living room: sofa, armchair, coffee table, rug, bookshelf.
	piece.call("fabric", Vector3(2.2, 0.45, 0.9), Vector3(1.9, f, -4.85))
	piece.call("fabric", Vector3(2.2, 0.55, 0.22), Vector3(1.9, f + 0.45, -5.2))
	for x in [0.85, 2.95]:
		piece.call("fabric", Vector3(0.2, 0.25, 0.9), Vector3(x, f + 0.45, -4.85), false)
	piece.call("rug", Vector3(2.6, 0.01, 1.8), Vector3(1.9, f + 0.02, -3.4), false)
	piece.call("handle", Vector3(1.0, 0.4, 0.6), Vector3(1.9, f, -3.4))
	piece.call("fabric2", Vector3(0.85, 0.45, 0.85), Vector3(3.25, f, -2.0))
	piece.call("fabric2", Vector3(0.85, 0.45, 0.2), Vector3(3.25, f + 0.45, -1.68))
	piece.call("handle", Vector3(0.35, 1.8, 1.4), Vector3(0.24, f, -0.6))
	for i in 3:
		for k in 5:
			var col: String = ["blanket", "fabric", "fabric2", "linen", "rug"][(i + k) % 5]
			piece.call(col, Vector3(0.22, 0.3, 0.18), Vector3(0.3, f + 0.15 + i * 0.55, -1.1 + k * 0.24), false)
	# Kitchen: counters with a stove and sink, a fridge, a table.
	piece.call("cabinet", Vector3(0.65, 0.88, 5.0), Vector3(-3.5, f, 1.7))
	piece.call("counter", Vector3(0.7, 0.04, 5.0), Vector3(-3.5, f + 0.88, 1.7), false)
	piece.call("counter", Vector3(0.55, 0.02, 0.6), Vector3(-3.5, f + 0.92, 3.2), false)
	piece.call("metal", Vector3(0.45, 0.02, 0.5), Vector3(-3.5, f + 0.92, 0.5), false)
	piece.call("appliance", Vector3(0.75, 1.85, 0.7), Vector3(-3.45, f, 4.9))
	piece.call("handle", Vector3(1.4, 0.06, 0.9), Vector3(-1.8, f + 0.72, 3.6))
	for x in [-2.4, -1.2]:
		for z in [3.25, 3.95]:
			piece.call("handle", Vector3(0.06, 0.72, 0.06), Vector3(x, f, z), false)
	var tc := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(1.4, 0.78, 0.9)
	tc.shape = tb
	tc.position = c + Vector3(-1.8, f + 0.39, 3.6)
	solid.add_child(tc)
	# Downstairs bedroom: bed, nightstand, wardrobe.
	_bed(piece, Vector3(-2.9, f, -4.2), false)
	piece.call("handle", Vector3(0.45, 0.55, 0.45), Vector3(-1.85, f, -5.0))
	piece.call("handle", Vector3(1.0, 2.0, 0.55), Vector3(-0.85, f, -5.05))
	# Bedroom A (upstairs front): bed, dresser, rug.
	_bed(piece, Vector3(2.7, u, -4.2), false)
	piece.call("handle", Vector3(1.2, 0.9, 0.5), Vector3(0.8, u, -5.05))
	piece.call("rug", Vector3(2.0, 0.01, 1.4), Vector3(1.6, u + 0.01, -2.2), false)
	# Bedroom B (upstairs back): two beds, a wardrobe.
	_bed(piece, Vector3(-2.75, u, -4.4), true)
	_bed(piece, Vector3(-2.75, u, -1.6), true)
	piece.call("handle", Vector3(0.55, 2.0, 1.0), Vector3(-3.55, u, 4.5))
	# Landing: a little table.
	piece.call("handle", Vector3(0.5, 0.75, 0.5), Vector3(0.45, u, 4.9))


## A bed: frame, mattress, blanket and pillow. `along_x`: lying along x.
static func _bed(piece: Callable, at: Vector3, along_x: bool) -> void:
	var sz := Vector3(2.0, 0.3, 1.2) if along_x else Vector3(1.4, 0.3, 2.0)
	piece.call("handle", sz, at)
	piece.call("linen", sz * Vector3(0.96, 0.6, 0.96), at + Vector3(0, 0.3, 0), false)
	piece.call("blanket", sz * Vector3(0.98 if not along_x else 0.62, 0.3, 0.62 if not along_x else 0.98), at + Vector3(0.3 if along_x else 0, 0.42, 0.0 if along_x else 0.3), false)
	piece.call("linen", Vector3(0.4, 0.12, 0.6) if along_x else Vector3(0.6, 0.12, 0.4), at + (Vector3(-0.7, 0.48, 0) if along_x else Vector3(0, 0.48, -0.7)), false)
	var head := Vector3(0.08, 0.9, sz.z) if along_x else Vector3(sz.x, 0.9, 0.08)
	piece.call("handle", head, at + (Vector3(-sz.x / 2, 0, 0) if along_x else Vector3(0, 0, -sz.z / 2)))


## A window on a wall facing along `axis` ("x" or "z"), `out` = +1 or -1.
static func _window(b: Surfaces.Builder, at: Vector3, axis: String, out: float, clear := true) -> void:
	var w := 1.0
	var h := 1.35
	var t := 0.12
	var s := func(along: float, up: float, thick: float) -> Vector3:
		return Vector3(thick, up, along) if axis == "x" else Vector3(along, up, thick)
	var o := func(along: float, up: float) -> Vector3:
		return at + (Vector3(0, up, along) if axis == "x" else Vector3(along, up, 0))
	_block(b, "clear_glass" if clear else "glass", null, s.call(w, h, 0.04), at)
	for a in [-1.0, 1.0]:
		_block(b, "trim", null, s.call(t, h + t * 2, 0.08), o.call(a * (w + t) / 2, 0))
	_block(b, "trim", null, s.call(w + t * 2, t, 0.08), o.call(0, (h + t) / 2))
	_block(b, "trim", null, s.call(w + t * 3, t, 0.14), o.call(0, -(h + t) / 2))
	_block(b, "trim", null, s.call(t * 0.5, h, 0.06), o.call(0, 0))
	_block(b, "trim", null, s.call(w, t * 0.5, 0.06), o.call(0, 0))


static func _frame_x(b: Surfaces.Builder, at: Vector3, size: Vector2) -> void:
	var t := 0.14
	for z in [-1.0, 1.0]:
		_block(b, "trim", null, Vector3(0.05, size.y, t), at + Vector3(0, 0, z * (size.x - t) / 2))
	_block(b, "trim", null, Vector3(0.05, t, size.x), at + Vector3(0, (size.y - t) / 2, 0))


## The silo: shiny galvanized steel on a concrete footing, banded, with a
## domed cap and a ladder up the side facing the barn.
static func _silo(b: Surfaces.Builder, solid: StaticBody3D) -> void:
	var r := 2.6
	var h := 13.0
	b.cylinder("concrete", r + 0.3, 0.5, SILO)
	_block(b, "concrete", null, Vector3((r + 0.3) * 2, 0.02, (r + 0.3) * 2), SILO + Vector3(0, 0.49, 0))
	b.cylinder("silo_metal", r, h, SILO + Vector3(0, 0.5, 0))
	for y in [3.5, 6.5, 9.5, 12.5]:
		b.cylinder("silo_metal", r + 0.04, 0.1, SILO + Vector3(0, y, 0))
	b.dome("silo_metal", r + 0.08, 1.7, SILO + Vector3(0, 0.5 + h, 0))
	var lx := SILO.x - r - 0.18
	for z in [-0.24, 0.24]:
		_block(b, "silo_metal", null, Vector3(0.06, h - 1.0, 0.06), Vector3(lx, 1.0 + (h - 1.0) / 2, SILO.z + z))
	var y := 1.2
	while y < h:
		_block(b, "silo_metal", null, Vector3(0.05, 0.05, 0.5), Vector3(lx, y, SILO.z))
		y += 0.4
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r + 0.3
	cyl.height = h + 2.0
	cs.shape = cyl
	cs.position = SILO + Vector3(0, cyl.height / 2, 0)
	solid.add_child(cs)


## A solid box for one scenery prop. Paint sticks to it.
static func prop_body(kind: String, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_PROPS
	body.collision_mask = 0
	body.transform = xf
	body.set_meta("prop", kind)
	var cs := CollisionShape3D.new()
	cs.shape = Props.shape(kind)
	cs.position.y = Props.size(kind).y / 2
	body.add_child(cs)
	return body


static func _block(b: Surfaces.Builder, surface: String, body: StaticBody3D, s: Vector3, at: Vector3, basis := Basis()) -> void:
	b.box(surface, s, at, basis)
	if body:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s
		cs.shape = box
		cs.transform = Transform3D(basis, at)
		body.add_child(cs)


## Godot's Compatibility renderer draws a shadow-casting sun in its own
## pass and adds it to the picture after conversion to screen colours, which
## overshoots: lit surfaces came out ~1.4x brighter on screen with shadows
## on. With these two, sunlit grass matches the no-shadow picture while
## shade (inside the barn, under the eaves) reads as shade: less fill light,
## a little more sun. Measured with ?ambient= and ?sunscale= (DESIGN 9.3b).
const SHADOW_SUN_SCALE := 0.45
const SHADOW_AMBIENT := 0.4


static func environment(root: Node3D, shadows := true, sun_scale := -1.0, ambient := -1.0) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.6, 0.9)
	sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.95)
	sky_mat.ground_horizon_color = Color(0.56, 0.66, 0.46)
	sky_mat.ground_bottom_color = Color(0.5, 0.45, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Mostly warm-neutral fill with a little sky: pure sky light is blue, and
	# turns straw in the shade olive green.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.86, 0.82, 0.76)
	env.ambient_light_sky_contribution = 0.3
	env.ambient_light_energy = 0.62
	if shadows:
		env.ambient_light_energy = ambient if ambient >= 0.0 else SHADOW_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 0.85
	if shadows:
		sun.light_energy *= sun_scale if sun_scale >= 0.0 else SHADOW_SUN_SCALE
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_blur = 1.5
	root.add_child(sun)


## Hiders' props come only from the scenery (design 9.2).
static func pool() -> Array:
	var out := []
	for s in scenery():
		if not out.has(s[0]):
			out.append(s[0])
	return out


## Where seeker bots wander when they have nothing to go on: one point in
## each part of the farm.
const PATROL := [
	Vector3(0, 0, 0), Vector3(-2.8, 0, -6.0), Vector3(-3.5, 0, 8.0), Vector3(1.5, 0, 6.5),
	Vector3(2.5, 0, -7.0), Vector3(-2.0, LOFT_Y, 8.0), Vector3(3.0, LOFT_Y, 9.5), Vector3(0, 0, 17.0),
	Vector3(0, 0, -17.0), Vector3(-11.5, 0, 4.0), Vector3(9.5, 0, -12.0), Vector3(5.0, 0, 15.0),
	# The farmhouse: living room, kitchen, bedroom, both bedrooms upstairs.
	Vector3(-18.0, 0.3, 1.0), Vector3(-22.9, 0.3, 5.0), Vector3(-22.0, 0.3, 0.5),
	Vector3(-18.0, 3.0, 0.5), Vector3(-22.0, 3.0, 3.0),
	# Round the edges: by the combine, along the driveway, the far corners.
	Vector3(-8.0, 0, -21.5), Vector3(4.0, 0, -27.0), Vector3(0, 0, 27.0),
	Vector3(26.0, 0, 26.0), Vector3(-26.0, 0, -26.0), Vector3(27.0, 0, -5.0),
]


## A walkable map for bots, baked from the barn's solid shapes and scenery
## (stalls, tractor, bales are obstacles; the ramp leads to the loft).
static func navigation(root: Node3D) -> NavigationRegion3D:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.3         # 1.2 m house doorways stay open (0.6 m clear)
	nm.agent_height = 1.65        # whole cells (0.15 m)
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.15
	nm.cell_height = 0.15
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = LAYER_WORLD | LAYER_PROPS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = "nav"
	nm.filter_baking_aabb = AABB(Vector3(-35, -1, -35), Vector3(70, 8, 70))
	var src := NavigationMeshSourceGeometryData3D.new()
	var t0 := Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(nm, src, root)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	print("hideseek: walkable map baked in %d ms" % (Time.get_ticks_msec() - t0))
	var region := NavigationRegion3D.new()
	region.name = "Nav"
	region.navigation_mesh = nm
	root.add_child(region)
	var map := region.get_navigation_map()
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	return region


## Places a hider bot with prop `kind` could sit: the hand-placed spots,
## plus beside (and for stackable props, on top of) every scenery copy of
## the same prop: hiding next to something just like you. The caller checks
## each is free.
static func hiding_places(kind: String) -> Array:
	var out := []
	for sp in SPOTS:
		if sp[0] == kind:
			out.append(spot_transform(sp))
	var sz := Props.size(kind)
	var stackable := kind in ["bale", "crate", "tire"]
	for s in scenery():
		if s[0] != kind:
			continue
		var xf: Transform3D = s[1]
		if Props.leans(kind):
			for d in [-0.55, 0.55]:
				out.append(Transform3D(xf.basis, xf.origin + xf.basis.x * d))
			continue
		for off in [xf.basis.x * (sz.x + 0.06), -xf.basis.x * (sz.x + 0.06), xf.basis.z * (sz.z + 0.06), -xf.basis.z * (sz.z + 0.06)]:
			out.append(Transform3D(xf.basis, xf.origin + Vector3(off.x, 0, off.z)))
		if stackable:
			out.append(Transform3D(xf.basis, xf.origin + Vector3(0, sz.y, 0)))
	return out
