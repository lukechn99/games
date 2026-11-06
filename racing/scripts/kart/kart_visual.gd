class_name KartVisual
extends Node3D
## Placeholder kart and driver built from simple shapes, so every chassis,
## tire and driver combination works from day one (design doc 5.5). The
## real models will replace the shapes but keep the same mounting points.
##
## The driver is the shared rounded base body (design doc 5.4) with a few
## animal features, and it leans, bobs and wobbles with the kart (9.2).

var kart: Kart
var _wheels: Array[Node3D] = []
var _driver: Node3D
var _torso: Node3D
var _head: Node3D
var _wobbly: Array[Node3D] = []   # ears, tails, antlers: swing with momentum
var _wobble_vel: Array[Vector2] = []
var _wobble_pos: Array[Vector2] = []
var _wheel_ring: Node3D
var _boost_flame: MeshInstance3D
var _sparks: MeshInstance3D
var _lean := 0.0
var _bob := 0.0
var _bob_vel := 0.0
var _finish := Palette.Finish.PAINT  # parts built from now on


## `standing`: just the driver, standing on its own feet beside the kart
## (the kart-selection screen), instead of the kart with the driver seated.
var standing := false
## `empty`: the kart with nobody in it (the driver stands beside it).
var empty := false


func _init(k: Kart, merge := true, stand := false) -> void:
	kart = k
	standing = stand
	if not merge:
		set_meta("nomerge", true)


func _ready() -> void:
	rebuild()


## Paintwork shines softly, metal sharply, rubber and fur not at all (9.4).
func _mat(c: Color) -> StandardMaterial3D:
	var finish := _finish
	if finish == Palette.Finish.PAINT:
		if c in [METAL, CHROME, Color(0.6, 0.6, 0.64), Color(0.45, 0.47, 0.52)]:
			finish = Palette.Finish.METAL
		elif c == DARK or c.v < 0.22:
			finish = Palette.Finish.MATTE
	return Palette.toon(c, false, 0.0, finish)


func _mesh(mesh: Mesh, c: Color, parent: Node3D, pos := Vector3.ZERO, scale_v := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.scale = scale_v
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float, rings := 8, segs := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.rings = rings
	s.radial_segments = segs
	return s


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.rings = 4
	c.radial_segments = 10
	return c


func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


## Rebuild everything, e.g. after the player swaps a part.
func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_wheels.clear()
	_finish = Palette.Finish.PAINT
	_wobbly.clear()
	_wobble_vel.clear()
	_wobble_pos.clear()
	_wheel_ring = null
	_torso = null
	_head = null
	_driver = null
	_boost_flame = null
	_sparks = null
	if standing:
		_build_standing()
		return
	var ch := kart.chassis
	var size: Vector3 = ch["size"]
	var color: Color = ch["color"]
	var body_y := size.y * 0.5 + 0.05

	# Chassis: a go-kart built from metal tubes with aerodynamic bodywork
	# (nose fairing, side pods, rear bumper). Every piece is placed from the
	# chassis's own wheel mounts, so wheels and driver always line up (5.5).
	var seat := _build_frame(kart.chassis_id, color)
	var column := Node3D.new()
	column.position = seat["wheel_at"]
	column.rotation.x = deg_to_rad(-60)
	add_child(column)
	var wheel_mesh := TorusMesh.new()
	wheel_mesh.inner_radius = 0.1
	wheel_mesh.outer_radius = 0.14
	wheel_mesh.rings = 12
	wheel_mesh.ring_segments = 6
	_wheel_ring = _mesh(wheel_mesh, Color(0.15, 0.15, 0.18), column)
	_mesh(_box(Vector3(0.12, 0.03, 0.06)), Color(0.15, 0.15, 0.18), _wheel_ring)
	body_y = seat["y"]

	# Boost flame and drift sparks, hidden until needed.
	_boost_flame = _mesh(_cone(0.18, 0.6), Color(1.0, 0.6, 0.15), self, Vector3(0, body_y, size.z * 0.6), Vector3.ONE, Vector3(-PI / 2, 0, 0))
	_boost_flame.material_override = _glow(Color(1.0, 0.62, 0.2))
	_boost_flame.visible = false
	_boost_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks = _mesh(_sphere(0.12, 4, 6), Color(0.4, 0.75, 1.0), self, Vector3(0, 0.1, size.z * 0.5))
	_sparks.material_override = _glow(Color(0.45, 0.8, 1.0))
	_sparks.visible = false
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Wheels snap to the chassis's mounting points.
	var r := kart.wheel_radius()
	var tire_color: Color = kart.tires["color"]
	var width: float = kart.tires["width"]
	for i in 4:
		var pivot := Node3D.new()
		pivot.position = kart.wheel_mount(i)
		add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = width
		cyl.radial_segments = 14
		cyl.rings = 1
		_finish = Palette.Finish.MATTE  # rubber
		_mesh(cyl, tire_color, spin, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI / 2))
		_finish = Palette.Finish.PAINT
		var rim := CylinderMesh.new()
		rim.top_radius = r * 0.55
		rim.bottom_radius = r * 0.55
		rim.height = width * 1.04
		rim.radial_segments = 10
		rim.rings = 1
		_mesh(rim, CHROME, spin, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI / 2))  # shiny rim
		_mesh(_box(Vector3(width * 1.08, r * 0.7, r * 0.16)), DARK, spin)  # spokes, show the spin
		if kart.tires_id == "knobby" or kart.tires_id == "studded":
			for k in 6:
				var a := TAU * k / 6.0
				_finish = Palette.Finish.MATTE
				_mesh(_box(Vector3(width * 1.05, 0.06, 0.08)), tire_color.lightened(0.25), spin, Vector3(0, cos(a) * r, sin(a) * r), Vector3.ONE, Vector3(a, 0, 0))
		_wheels.append(pivot)

	if not empty:
		_finish = Palette.Finish.MATTE  # fur and cloth
		_build_driver(body_y, size, seat["z"])
		_finish = Palette.Finish.PAINT
	if not has_meta("nomerge"):
		_merge_all()


const OUTLINE_W := 0.025
const METAL := Color(0.78, 0.8, 0.84)
const CHROME := Color(0.86, 0.87, 0.9)
const DARK := Color(0.16, 0.16, 0.2)


## A metal tube from a to b.
func _tube(a: Vector3, b: Vector3, r: float, c := METAL, parent: Node3D = self) -> MeshInstance3D:
	var d := b - a
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = d.length()
	cyl.radial_segments = 8
	cyl.rings = 1
	var mi := _mesh(cyl, c, parent, (a + b) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	return mi


## A tube bent through several points (bumpers, nerf bars, roll hoops).
func _bent(points: Array, r: float, c := METAL) -> void:
	for i in points.size() - 1:
		_tube(points[i], points[i + 1], r, c)
		if i > 0:
			_mesh(_sphere(r, 4, 6), c, self, points[i])


## A smooth tapered shell along -Z: `front` and `back` radii, squashed to `w` by `h`.
func _fairing(center: Vector3, length: float, front: float, back: float, w: float, h: float, c: Color) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = front
	cyl.bottom_radius = back
	cyl.height = length
	cyl.radial_segments = 14
	cyl.rings = 2
	var mi := _mesh(cyl, c, self, center)
	mi.basis = Basis(Vector3.RIGHT, -PI / 2) * Basis.from_scale(Vector3(w, 1.0, h))
	return mi


## Builds the frame and bodywork for one chassis style. Returns where the
## driver sits and where the steering wheel goes.
func _build_frame(style: String, color: Color) -> Dictionary:
	var fl := kart.wheel_mount(0)
	var rr := kart.wheel_mount(3)
	var tx := absf(fl.x)          # half track
	var fz := fl.z                # front axle (negative)
	var rz := rr.z                # rear axle
	var y := fl.y - (Kart.SUSPENSION_TRAVEL * 0.6)  # wheel-centre height at rest
	var low := y - 0.05           # frame rails sit just below the axles
	var rail_x := tx * 0.42
	var tube := 0.035
	var paint := color
	var accent := color.lightened(0.35)

	# Main rails and cross tubes.
	_bent([Vector3(-rail_x, low, rz + 0.1), Vector3(-rail_x, low, fz - 0.05), Vector3(-rail_x * 0.55, low, fz - 0.3)], tube)
	_bent([Vector3(rail_x, low, rz + 0.1), Vector3(rail_x, low, fz - 0.05), Vector3(rail_x * 0.55, low, fz - 0.3)], tube)
	_tube(Vector3(-rail_x * 0.55, low, fz - 0.3), Vector3(rail_x * 0.55, low, fz - 0.3), tube)
	for z in [fz, (fz + rz) * 0.5, rz]:
		_tube(Vector3(-tx + 0.1, low, z), Vector3(tx - 0.1, low, z), tube * 0.9)   # axle carriers
	# Floor tray.
	_mesh(_box(Vector3(rail_x * 2.0, 0.02, (rz - fz) * 0.8)), DARK, self, Vector3(0, low - 0.02, (fz + rz) * 0.5))
	# Rear bumper bar wrapping behind the rear wheels.
	var by := low + 0.06
	_bent([Vector3(-tx - 0.08, by, rz - 0.05), Vector3(-tx - 0.08, by, rz + 0.45), Vector3(tx + 0.08, by, rz + 0.45), Vector3(tx + 0.08, by, rz - 0.05)], tube * 1.2)
	_tube(Vector3(-rail_x, low, rz + 0.1), Vector3(-rail_x, by, rz + 0.45), tube)
	_tube(Vector3(rail_x, low, rz + 0.1), Vector3(rail_x, by, rz + 0.45), tube)
	# Front bumper loop under the nose.
	_bent([Vector3(-tx * 0.7, low + 0.02, fz - 0.15), Vector3(-tx * 0.45, low + 0.02, fz - 0.55), Vector3(tx * 0.45, low + 0.02, fz - 0.55), Vector3(tx * 0.7, low + 0.02, fz - 0.15)], tube)

	# Bodywork, aerodynamic shells in the chassis colour.
	var nose_len := 0.55
	var pod_len := (rz - fz) * 0.62
	match style:
		"soapbox":
			# A rounded egg-shaped shell over a light frame.
			var shell := _mesh(_sphere(0.5, 8, 14), paint, self, Vector3(0, low + 0.16, (fz + rz) * 0.5 - 0.15))
			shell.scale = Vector3(rail_x * 2.4, 0.42, (rz - fz) * 0.95)
			_mesh(_sphere(0.5, 6, 10), accent, self, Vector3(0, low + 0.16, fz - 0.15), Vector3(rail_x * 1.4, 0.32, 0.5))
		"hauler":
			# Chunky: wide boxy pods, double bumpers and a roll hoop.
			_fairing(Vector3(0, low + 0.12, fz - 0.25), nose_len, 0.22, 0.3, 1.5, 0.55, paint)
			for side in [-1.0, 1.0]:
				_fairing(Vector3(side * (tx - 0.02), low + 0.1, (fz + rz) * 0.5), pod_len, 0.16, 0.16, 1.2, 0.8, paint)
			_bent([Vector3(-tx - 0.12, by + 0.12, rz + 0.5), Vector3(tx + 0.12, by + 0.12, rz + 0.5)], tube * 1.4, DARK)
			var hoop_z := rz - 0.2
			_bent([Vector3(-rail_x, low, hoop_z), Vector3(-rail_x * 0.9, low + 0.85, hoop_z + 0.05), Vector3(rail_x * 0.9, low + 0.85, hoop_z + 0.05), Vector3(rail_x, low, hoop_z)], tube * 1.3)
		"racer":
			# Long, low and pointy, with a rear wing.
			_fairing(Vector3(0, low + 0.09, fz - 0.35), nose_len + 0.35, 0.05, 0.26, 1.3, 0.45, paint)
			for side in [-1.0, 1.0]:
				_fairing(Vector3(side * (tx - 0.08), low + 0.06, (fz + rz) * 0.5 + 0.05), pod_len, 0.07, 0.15, 1.0, 0.55, paint)
				_tube(Vector3(side * rail_x * 0.8, low, rz + 0.25), Vector3(side * rail_x * 0.8, low + 0.6, rz + 0.35), tube)
			_mesh(_box(Vector3(tx * 2.0, 0.04, 0.32)), accent, self, Vector3(0, low + 0.62, rz + 0.38))
		_:
			# Classic sprint kart: nose cone, side pods, number plate.
			_fairing(Vector3(0, low + 0.1, fz - 0.3), nose_len, 0.1, 0.28, 1.35, 0.5, paint)
			for side in [-1.0, 1.0]:
				_fairing(Vector3(side * (tx - 0.05), low + 0.08, (fz + rz) * 0.5), pod_len, 0.09, 0.14, 1.1, 0.7, paint)
	# Number plate on the nose.
	var plate := _mesh(_sphere(0.11, 4, 10), Color(0.97, 0.97, 0.97), self, Vector3(0, low + 0.28, fz - 0.05), Vector3(1.0, 1.0, 0.25))
	plate.rotation.x = deg_to_rad(-25)

	# Engine and exhaust at the back (not on the soapbox: it's gravity powered).
	if style != "soapbox":
		_mesh(_box(Vector3(0.24, 0.22, 0.28)), Color(0.45, 0.47, 0.52), self, Vector3(rail_x + 0.05, low + 0.15, rz - 0.05))
		_mesh(_box(Vector3(0.2, 0.06, 0.24)), DARK, self, Vector3(rail_x + 0.05, low + 0.28, rz - 0.05))
		_bent([Vector3(rail_x + 0.12, low + 0.15, rz + 0.1), Vector3(rail_x + 0.2, low + 0.2, rz + 0.35), Vector3(rail_x + 0.2, low + 0.26, rz + 0.5)], 0.035, Color(0.6, 0.6, 0.64))

	# Bucket seat and the steering column.
	var seat_z := (fz + rz) * 0.5 + (rz - fz) * 0.12
	var seat_y := low + 0.08
	_mesh(_sphere(0.24, 6, 10), DARK, self, Vector3(0, seat_y + 0.08, seat_z + 0.05), Vector3(1.0, 0.55, 1.0))
	_mesh(_box(Vector3(0.38, 0.42, 0.06)), DARK, self, Vector3(0, seat_y + 0.25, seat_z + 0.2), Vector3.ONE, Vector3(deg_to_rad(-15), 0, 0))
	var wheel_at := Vector3(0, seat_y + 0.45, seat_z - 0.42)
	_tube(Vector3(0, low, fz + 0.05), wheel_at, 0.02, DARK)
	return {"y": seat_y, "z": seat_z, "wheel_at": wheel_at}


## Merge each group of parts that moves together into one mesh with an ink
## outline (design doc 9.1): a kart drops from ~70 draw calls to ~15.
func _merge_all() -> void:
	if _boost_flame:
		_boost_flame.set_meta("keep", true)
		_sparks.set_meta("keep", true)
	var groups: Array[Node3D] = []
	for g in ([self, _driver, _torso, _head] if standing else [self, _torso, _head]):
		if g != null:
			groups.append(g)
	for w in _wheels:
		groups.append(w.get_child(0))
	if _wheel_ring:
		groups.append(_wheel_ring.get_parent())
	groups.append_array(_wobbly)
	for g in groups:
		_merge(g)


func _merge(group: Node3D) -> void:
	var parts: Array[MeshInstance3D] = []
	var xforms: Array[Transform3D] = []
	_collect(group, Transform3D.IDENTITY, parts, xforms, true)
	if parts.size() < 1:
		return
	# One surface per finish, so metal still shines and fur stays matte.
	var by_finish := {}
	for i in parts.size():
		var f := int(parts[i].material_override.resource_name)
		if not by_finish.has(f):
			by_finish[f] = []
		by_finish[f].append(i)
	var mesh := ArrayMesh.new()
	for f in by_finish:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _combine(parts, xforms, by_finish[f]))
		mesh.surface_set_material(mesh.get_surface_count() - 1, Palette.toon(Color.WHITE, true, 0.0, f))
	# The ink outline is its own single mesh that only draws for karts near
	# the camera: far away it's too thin to see, and skipping it halves the
	# draw calls for the rest of the pack (design doc 14).
	var all := []
	for i in parts.size():
		all.append(i)
	var ink := ArrayMesh.new()
	ink.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _combine(parts, xforms, all))
	for mi in parts:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	var merged := MeshInstance3D.new()
	merged.mesh = mesh
	group.add_child(merged)
	var outline := MeshInstance3D.new()
	outline.mesh = ink
	outline.material_override = Palette.outline_material(OUTLINE_W)
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.visibility_range_end = 28.0
	group.add_child(outline)


func _combine(parts: Array[MeshInstance3D], xforms: Array[Transform3D], which: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in which:
		var mi := parts[i]
		var xf := xforms[i]
		var c: Color = (mi.material_override as StandardMaterial3D).albedo_color
		var arr := mi.mesh.surface_get_arrays(0)
		var base := verts.size()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var nb := xf.basis.inverse().transposed()
		for k in v.size():
			verts.append(xf * v[k])
			normals.append((nb * n[k]).normalized())
			colors.append(c)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			for k in v.size():
				indices.append(base + k)
		else:
			for k in idx:
				indices.append(base + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Mesh parts under `node`, with transforms relative to the group. Stops at
## plain Node3D children (they move on their own, so they're merged separately).
func _collect(node: Node3D, xf: Transform3D, parts: Array[MeshInstance3D], xforms: Array[Transform3D], is_root: bool) -> void:
	for c in node.get_children():
		if not c is Node3D or c.has_meta("keep"):
			continue
		var child := c as Node3D
		var cx := xf * child.transform
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is StandardMaterial3D:
			var sc := cx.basis.get_scale()
			if absf(sc.x - sc.y) > 0.01 or absf(sc.y - sc.z) > 0.01:
				# Stretched shells shade wrongly once merged, so they stay
				# separate (with the same toon look and outline).
				var mi := child as MeshInstance3D
				var m := mi.material_override as StandardMaterial3D
				mi.material_override = Palette.toon(m.albedo_color, false, OUTLINE_W, int(m.resource_name))
				_collect(child, cx, parts, xforms, false)
				continue
			parts.append(child)
			xforms.append(cx)
			_collect(child, cx, parts, xforms, false)
		elif not is_root and not child is MeshInstance3D:
			continue


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## The shared base body: a soft bean with a big head, stubby arms and legs.
## The driver on its own: the same body and features, on two stubby legs,
## with its arms down instead of reaching for a wheel.
func _build_standing() -> void:
	_finish = Palette.Finish.MATTE
	_build_driver(0.42, Vector3.ONE, 0.0, false)
	var d := kart.driver
	var body_c: Color = d["body"]
	for side in [-1.0, 1.0]:
		_mesh(_capsule(0.1, 0.5), body_c, _driver, Vector3(0.13 * side, -0.18, 0))
		_mesh(_sphere(0.11), body_c.darkened(0.15), _driver, Vector3(0.13 * side, -0.42, -0.06), Vector3(1.0, 0.6, 1.4))
	_merge_all()


func _build_driver(seat_y: float, size: Vector3, seat_z: float, seated := true) -> void:
	var d := kart.driver
	var body_c: Color = d["body"]
	var belly_c: Color = d["belly"]
	var s: float = Parts.WEIGHT_SCALE[d["weight"]]
	_driver = Node3D.new()
	_driver.position = Vector3(0, seat_y, seat_z)
	_driver.scale = Vector3.ONE * s
	add_child(_driver)

	_torso = Node3D.new()
	_driver.add_child(_torso)
	_mesh(_capsule(0.28, 0.75), body_c, _torso, Vector3(0, 0.3, 0))
	_mesh(_sphere(0.2), belly_c, _torso, Vector3(0, 0.25, -0.13), Vector3(1.0, 1.2, 0.5))
	# Arms reach forward to the wheel.
	for side in [-1.0, 1.0]:
		if seated:
			_mesh(_capsule(0.07, 0.42), body_c, _torso, Vector3(0.22 * side, 0.38, -0.2), Vector3.ONE, Vector3(deg_to_rad(-70), 0, side * 0.35))
		else:
			# Arms at its sides, one raised in a little wave.
			var wave: bool = side > 0.0
			_mesh(_capsule(0.07, 0.42), body_c, _torso, Vector3(0.3 * side, 0.45 if wave else 0.22, -0.02), Vector3.ONE, Vector3(0, 0, side * (2.4 if wave else 0.35)))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.78, 0)
	_torso.add_child(_head)
	_mesh(_sphere(0.3, 10, 14), body_c, _head)
	_mesh(_sphere(0.17), belly_c, _head, Vector3(0, -0.06, -0.22), Vector3(1.1, 0.8, 0.6))  # face patch
	for side in [-1.0, 1.0]:
		_mesh(_sphere(0.05, 4, 6), Color(0.08, 0.08, 0.1), _head, Vector3(0.11 * side, 0.05, -0.27))  # eyes

	for f in d["features"]:
		match f:
			"pointed_ears":
				for side in [-1.0, 1.0]:
					_wobbly_part(_cone(0.11, 0.3), body_c, _head, Vector3(0.17 * side, 0.3, 0), Vector3(0, 0, -side * 0.25))
			"round_ears":
				for side in [-1.0, 1.0]:
					_wobbly_part(_sphere(0.09), body_c.darkened(0.1), _head, Vector3(0.24 * side, 0.22, 0.02), Vector3.ZERO)
			"bushy_tail":
				var tail := _wobbly_part(_capsule(0.12, 0.6), body_c, _torso, Vector3(0, 0.15, 0.32), Vector3(deg_to_rad(60), 0, 0))
				_mesh(_sphere(0.1), Color(1, 0.97, 0.92), tail, Vector3(0, 0.27, 0))
			"top_eyes":
				for side in [-1.0, 1.0]:
					var eye := _mesh(_sphere(0.1), body_c, _head, Vector3(0.13 * side, 0.26, -0.12))
					_mesh(_sphere(0.05, 4, 6), Color(0.08, 0.08, 0.1), eye, Vector3(0, 0.02, -0.08))
			"horn":
				_mesh(_cone(0.08, 0.28), Color(0.92, 0.9, 0.82), _head, Vector3(0, 0.02, -0.38), Vector3.ONE, Vector3(deg_to_rad(-70), 0, 0))
			"antlers":
				for side in [-1.0, 1.0]:
					var a := _wobbly_part(_capsule(0.03, 0.4), Color(0.55, 0.38, 0.22), _head, Vector3(0.12 * side, 0.32, 0.02), Vector3(0, 0, -side * 0.4))
					_mesh(_capsule(0.025, 0.2), Color(0.55, 0.38, 0.22), a, Vector3(0.05 * side, 0.1, 0), Vector3.ONE, Vector3(0, 0, -side * 0.9))


func _wobbly_part(mesh: Mesh, c: Color, parent: Node3D, pos: Vector3, rot: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation = rot
	pivot.set_meta("base_rot", rot)
	parent.add_child(pivot)
	var mi := _mesh(mesh, c, pivot)
	mi.position = Vector3(0, 0.12, 0)
	_wobbly.append(pivot)
	_wobble_vel.append(Vector2.ZERO)
	_wobble_pos.append(Vector2.ZERO)
	return pivot


func _process(delta: float) -> void:
	if kart == null or _wheels.is_empty():
		return
	for i in 4:
		var pivot := _wheels[i]
		var mount := kart.wheel_mount(i)
		var travel := Kart.SUSPENSION_TRAVEL
		var y := mount.y - (travel - kart.wheel_compression[i])
		pivot.position = Vector3(mount.x, lerpf(pivot.position.y, y, 0.5), mount.z)
		pivot.rotation.y = -kart.steer_angle if i < 2 else 0.0
		pivot.get_child(0).rotation.x = -kart.wheel_spin
	if _wheel_ring:
		_wheel_ring.rotation.y = -kart.steer_angle * 2.2

	# Driver: lean against the turn, bob with the suspension, spring back.
	if _torso == null:
		return
	_lean = lerpf(_lean, clampf(-kart.lateral_g * 0.22, -0.4, 0.4), clampf(delta * 6.0, 0.0, 1.0))
	_bob_vel += (-_bob * 140.0 - _bob_vel * 9.0) * delta
	_bob_vel -= clampf(kart.vertical_kick, -3.0, 3.0) * 0.9
	_bob += _bob_vel * delta
	_bob = clampf(_bob, -0.12, 0.12)
	_torso.rotation.z = _lean
	_torso.position.y = _bob
	_torso.scale = Vector3(1.0 - _bob * 0.6, 1.0 + _bob * 1.2, 1.0 - _bob * 0.6)  # squash and stretch
	_head.rotation.y = lerpf(_head.rotation.y, kart.steer_angle * 0.9, clampf(delta * 5.0, 0.0, 1.0))
	_head.rotation.z = _lean * 0.5

	# Ears, tails and antlers trail behind the motion like springs.
	var accel := Vector2(kart.lateral_g, -kart.speed * 0.02 + _bob_vel * 0.3)
	for i in _wobbly.size():
		var v := _wobble_vel[i]
		var p := _wobble_pos[i]
		v += (-p * 90.0 - v * 7.0 + accel * 2.5) * delta
		p += v * delta
		p = p.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
		_wobble_vel[i] = v
		_wobble_pos[i] = p
		var base: Vector3 = _wobbly[i].get_meta("base_rot")
		_wobbly[i].rotation = base + Vector3(p.y, 0, p.x)

	_boost_flame.visible = kart.boost_time > 0.0
	if _boost_flame.visible:
		_boost_flame.scale = Vector3.ONE * (0.8 + randf() * 0.5)
	var stage := kart.drift_stage()
	_sparks.visible = kart.drifting
	if _sparks.visible:
		var colors := [Color(0.85, 0.85, 0.9), Color(0.4, 0.75, 1.0), Color(1.0, 0.6, 0.2), Color(0.85, 0.4, 1.0)]
		(_sparks.material_override as StandardMaterial3D).albedo_color = colors[stage]
		(_sparks.material_override as StandardMaterial3D).emission = colors[stage]
		_sparks.position.x = -kart.drift_dir * float(kart.chassis["track"]) * 0.5
		_sparks.scale = Vector3.ONE * (0.6 + randf() * 0.8)
