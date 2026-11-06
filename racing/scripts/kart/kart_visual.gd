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
var _materials := {}


func _init(k: Kart) -> void:
	kart = k


func _ready() -> void:
	rebuild()


func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := c.to_html() + str(rough)
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	_materials[key] = m
	return m


func _mesh(mesh: Mesh, c: Color, parent: Node3D, pos := Vector3.ZERO, scale_v := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.scale = scale_v
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_wobbly.clear()
	_wobble_vel.clear()
	_wobble_pos.clear()
	var ch := kart.chassis
	var size: Vector3 = ch["size"]
	var color: Color = ch["color"]
	var body_y := size.y * 0.5 + 0.05

	# Chassis: a rounded tub, a nose, a seat and a steering wheel.
	_mesh(_box(Vector3(size.x * 0.82, size.y * 0.55, size.z * 0.9)), color, self, Vector3(0, body_y, 0))
	_mesh(_box(Vector3(size.x * 0.6, size.y * 0.35, size.z * 0.25)), color.lightened(0.15), self, Vector3(0, body_y + 0.02, -size.z * 0.52))
	_mesh(_box(Vector3(size.x * 1.02, 0.12, 0.25)), Color(0.2, 0.2, 0.24), self, Vector3(0, body_y - 0.05, -size.z * 0.5))  # front bumper
	_mesh(_box(Vector3(size.x * 1.02, 0.12, 0.25)), Color(0.2, 0.2, 0.24), self, Vector3(0, body_y - 0.05, size.z * 0.5))   # rear bumper
	_mesh(_box(Vector3(size.x * 0.5, 0.35, 0.12)), color.darkened(0.25), self, Vector3(0, body_y + 0.32, size.z * 0.18))   # seat back
	var column := Node3D.new()
	column.position = Vector3(0, body_y + 0.3, -size.z * 0.12)
	column.rotation.x = deg_to_rad(-55)
	add_child(column)
	var wheel_mesh := TorusMesh.new()
	wheel_mesh.inner_radius = 0.11
	wheel_mesh.outer_radius = 0.15
	wheel_mesh.rings = 12
	wheel_mesh.ring_segments = 6
	_wheel_ring = _mesh(wheel_mesh, Color(0.15, 0.15, 0.18), column)
	# Item rack at the back (design doc 6.1 option B): empty for now.

	# Boost flame and drift sparks, hidden until needed.
	_boost_flame = _mesh(_cone(0.18, 0.6), Color(1.0, 0.6, 0.15), self, Vector3(0, body_y, size.z * 0.6), Vector3.ONE, Vector3(-PI / 2, 0, 0))
	_boost_flame.material_override = _glow(Color(1.0, 0.62, 0.2))
	_boost_flame.visible = false
	_sparks = _mesh(_sphere(0.12, 4, 6), Color(0.4, 0.75, 1.0), self, Vector3(0, 0.1, size.z * 0.5))
	_sparks.material_override = _glow(Color(0.45, 0.8, 1.0))
	_sparks.visible = false

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
		_mesh(cyl, tire_color, spin, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI / 2))
		_mesh(_box(Vector3(width * 1.02, r * 0.9, r * 0.25)), Color(0.85, 0.85, 0.88), spin)  # hub, shows the spin
		if kart.tires_id == "knobby" or kart.tires_id == "studded":
			for k in 6:
				var a := TAU * k / 6.0
				_mesh(_box(Vector3(width * 1.05, 0.06, 0.08)), tire_color.lightened(0.25), spin, Vector3(0, cos(a) * r, sin(a) * r), Vector3.ONE, Vector3(a, 0, 0))
		_wheels.append(pivot)

	_build_driver(body_y + 0.12, size)


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## The shared base body: a soft bean with a big head, stubby arms and legs.
func _build_driver(seat_y: float, size: Vector3) -> void:
	var d := kart.driver
	var body_c: Color = d["body"]
	var belly_c: Color = d["belly"]
	var s: float = Parts.WEIGHT_SCALE[d["weight"]]
	_driver = Node3D.new()
	_driver.position = Vector3(0, seat_y, size.z * 0.08)
	_driver.scale = Vector3.ONE * s
	add_child(_driver)

	_torso = Node3D.new()
	_driver.add_child(_torso)
	_mesh(_capsule(0.28, 0.75), body_c, _torso, Vector3(0, 0.3, 0))
	_mesh(_sphere(0.2), belly_c, _torso, Vector3(0, 0.25, -0.13), Vector3(1.0, 1.2, 0.5))
	# Arms reach forward to the wheel.
	for side in [-1.0, 1.0]:
		_mesh(_capsule(0.07, 0.42), body_c, _torso, Vector3(0.22 * side, 0.38, -0.2), Vector3.ONE, Vector3(deg_to_rad(-70), 0, side * 0.35))
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
