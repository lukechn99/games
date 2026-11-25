class_name Sparks
extends Node3D
## The hider's tell (design doc 6): a pop of confetti and sparks on the
## prop, and a plume that shoots up about 9 m and bursts, drawn over roofs
## so it shows outside a building. CPU particles: cheap and the same on
## every device. Draw one while loading (warm_up) so the first isn't a hitch.

const PLUME_HEIGHT := 9.0
const PLUME_RISE := 0.65
const CONFETTI := [Color(1.0, 0.33, 0.45), Color(1.0, 0.8, 0.2), Color(0.3, 0.75, 1.0), Color(0.45, 0.9, 0.4), Color(0.85, 0.45, 1.0), Color(1.0, 1.0, 1.0)]

var with_plume := true
static var _mats := {}


static func burst(parent: Node, at: Vector3, plume := true) -> Sparks:
	var s := Sparks.new()
	s.with_plume = plume
	parent.add_child(s)
	s.global_position = at
	return s


func _ready() -> void:
	add_child(_particles(80, 1.4, Vector2(3.5, 6.5), 70.0, -7.0, Vector2(0.075, 0.045), _confetti_colors(), false, true))
	add_child(_particles(36, 0.5, Vector2(5.0, 9.0), 80.0, -4.0, Vector2(0.05, 0.05), _one(Color(1.0, 0.92, 0.55)), false, true))
	if with_plume:
		var rocket := Node3D.new()
		add_child(rocket)
		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		sm.radial_segments = 8
		sm.rings = 4
		head.mesh = sm
		head.material_override = _material(true)
		rocket.add_child(head)
		var trail := _particles(70, 0.55, Vector2(0.2, 0.6), 180.0, -1.0, Vector2(0.1, 0.1), _one(Color(1.0, 0.85, 0.4)), true, false)
		rocket.add_child(trail)
		var tw := create_tween()
		tw.tween_property(rocket, "position", Vector3(0, PLUME_HEIGHT, 0), PLUME_RISE).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func():
			trail.emitting = false
			head.visible = false
			var pop := _particles(70, 1.1, Vector2(4.0, 6.0), 180.0, -3.0, Vector2(0.14, 0.14), _confetti_colors(), true, true)
			pop.position = rocket.position
			add_child(pop))
	get_tree().create_timer(3.2).timeout.connect(queue_free)


func _particles(amount: int, life: float, speed: Vector2, spread: float, gravity: float, quad: Vector2, colors: Gradient, over_roofs: bool, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.95 if one_shot else 0.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angle_min = 0
	p.angle_max = 360
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(0.7, 1))
	shrink.add_point(Vector2(1, 0))
	p.scale_amount_curve = shrink
	p.color_initial_ramp = colors
	var q := QuadMesh.new()
	q.size = quad
	q.material = _material(over_roofs)
	p.mesh = q
	p.emitting = true
	return p


static func _material(over_roofs: bool) -> StandardMaterial3D:
	if not _mats.has(over_roofs):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if over_roofs:
			m.no_depth_test = true
			m.render_priority = 10
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[over_roofs] = m
	return _mats[over_roofs]


static func _confetti_colors() -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in CONFETTI.size():
		offs.append(float(i) / CONFETTI.size())
		cols.append(CONFETTI[i])
	g.offsets = offs
	g.colors = cols
	return g


static func _one(c: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0])
	g.colors = PackedColorArray([c])
	return g
