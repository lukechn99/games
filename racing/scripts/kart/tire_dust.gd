class_name TireDust
extends CPUParticles3D
## Dust, grass bits and drift smoke kicked up behind the rear wheels
## (design doc 9.4). One small particle system per kart.

const COLORS := {
	"dirt": Color(0.8, 0.6, 0.4),
	"grass": Color(0.55, 0.78, 0.4),
	"sand": Color(0.95, 0.86, 0.62),
	"snow": Color(1, 1, 1),
	"ice": Color(0.9, 0.97, 1.0),
	"asphalt": Color(0.88, 0.88, 0.9),
}

var kart: Kart
var _mat: StandardMaterial3D


func _init(k: Kart) -> void:
	kart = k
	amount = 26
	lifetime = 0.9
	local_coords = false
	emitting = false
	var size: Vector3 = k.chassis["size"]
	position = Vector3(0, 0.12, size.z * 0.45)
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(size.x * 0.45, 0.05, 0.1)
	direction = Vector3(0, 0.6, 1)
	spread = 30.0
	initial_velocity_min = 1.0
	initial_velocity_max = 2.6
	gravity = Vector3(0, 0.6, 0)
	damping_min = 1.5
	damping_max = 2.5
	scale_amount_min = 0.5
	scale_amount_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.55))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	mesh = quad
	_mat = StandardMaterial3D.new()
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	_mat.albedo_texture = tex
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	var s := kart.surface_name
	var loose := s == "dirt" or s == "grass" or s == "sand" or s == "snow"
	var on := kart.grounded_wheels >= 2 and kart.speed > 6.0 and (loose or kart.drifting)
	emitting = on
	if on:
		color = COLORS.get(s, COLORS["asphalt"])
