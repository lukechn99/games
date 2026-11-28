class_name Paint
extends Node3D
## A paintball in flight (design doc 7): fast, a slight drop, short range.
## Each physics step casts a ray along its path; `hit` reports what it hit.

signal hit(collider: Object, point: Vector3, normal: Vector3)

const SPEED := 38.0
const RANGE := 15.0
const DROP := 5.0
const COLORS := [Color(1.0, 0.25, 0.6), Color(0.2, 0.75, 1.0), Color(1.0, 0.85, 0.1), Color(0.4, 1.0, 0.35)]

var velocity := Vector3.ZERO
var color := Color.WHITE
var exclude: Array[RID] = []
var _travelled := 0.0
static var _ball_mat := {}


static func fire(parent: Node, from: Transform3D, paint_color: Color, shooter: RID) -> Paint:
	var p := Paint.new()
	p.color = paint_color
	p.velocity = -from.basis.z * SPEED
	p.exclude = [shooter]
	parent.add_child(p)
	p.global_position = from.origin - from.basis.z * 0.3 + from.basis.y * -0.12
	return p


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = ball_material(color)
	add_child(mi)


static func ball_material(c: Color) -> StandardMaterial3D:
	if not _ball_mat.has(c):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		_ball_mat[c] = m
	return _ball_mat[c]


func _physics_process(delta: float) -> void:
	velocity.y -= DROP * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, TestBarn.LAYER_WORLD | TestBarn.LAYER_PLAYERS | TestBarn.LAYER_PROPS, exclude)
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	if h:
		hit.emit(h["collider"], h["position"], h["normal"])
		queue_free()
		return
	global_position = to
	_travelled += from.distance_to(to)
	if _travelled > RANGE:
		queue_free()


## A splat that stays bright, then fades (HideRules.paint_alpha).
class Splat extends Node3D:
	var age := 0.0
	var _mat: StandardMaterial3D
	static var _tex: Texture2D

	## `size` is the splat's width: smaller on small props (Props.splat_size)
	## so it doesn't hang off their edges.
	static func create(parent: Node, point: Vector3, normal: Vector3, c: Color, rng: RandomNumberGenerator, size := 0.56) -> Splat:
		var s := Splat.new()
		s._mat = StandardMaterial3D.new()
		s._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s._mat.albedo_color = c
		s._mat.albedo_texture = blob()
		s._mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		s._mat.render_priority = 1
		var z := normal.normalized()
		var x := z.cross(Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT).normalized()
		var b := Basis(x, z.cross(x), z) * Basis(Vector3.BACK, rng.randf() * TAU)
		parent.add_child(s)
		s.global_transform = Transform3D(b, point + z * 0.012)
		var k := size / 0.56
		s._quad(Vector2.ZERO, rng.randf_range(0.5, 0.56) * k)
		for i in rng.randi_range(4, 6):
			var a := rng.randf() * TAU
			s._quad(Vector2(cos(a), sin(a)) * rng.randf_range(0.2, 0.3) * k, rng.randf_range(0.06, 0.11) * k)
		return s

	static func blob() -> Texture2D:
		if _tex == null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.6, 0.7])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
			var t := GradientTexture2D.new()
			t.gradient = g
			t.fill = GradientTexture2D.FILL_RADIAL
			t.fill_from = Vector2(0.5, 0.5)
			t.fill_to = Vector2(0.5, 0.0)
			t.width = 64
			t.height = 64
			_tex = t
		return _tex

	func _quad(at: Vector2, size: float) -> void:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		mi.mesh = q
		mi.material_override = _mat
		mi.position = Vector3(at.x, at.y, 0)
		add_child(mi)

	func _process(delta: float) -> void:
		age += delta
		var a := HideRules.paint_alpha(age)
		_mat.albedo_color.a = a
		if a <= 0.0:
			queue_free()
