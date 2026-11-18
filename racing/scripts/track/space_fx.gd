class_name SpaceFx
extends RefCounted
## Cosmic Crossing's moving air (design doc 8.6): the red planet's dust
## devils and the saucer's vents. Each is a see-through funnel whose
## surface swirls and rises (a shader, no texture), with soft puffs thrown
## off it (particles), so neither is a solid shape or a flat glow.

static var _swirl: Shader
static var _puff: Texture2D


## A funnel's material: wisps of `tint` turning round it and rising.
static func swirl(tint: Color, alpha: float, turn: float, rise: float) -> ShaderMaterial:
	if _swirl == null:
		_swirl = Shader.new()
		_swirl.code = """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.8, 0.45, 0.28, 1.0);
uniform float alpha = 0.55;
uniform float turn = 1.5;
uniform float rise = 0.6;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	// Wisps wrap round the funnel (UV.x) and climb it (UV.y).
	vec2 p = vec2(UV.x * 7.0 + TIME * turn + UV.y * 2.5, UV.y * 4.0 + TIME * rise);
	float n = noise(p) * 0.65 + noise(p * 2.3 + vec2(TIME * turn * 0.7, 0.0)) * 0.35;
	float ends = smoothstep(0.0, 0.18, UV.y) * smoothstep(1.0, 0.62, UV.y);
	// Most solid where the funnel is seen edge-on, like real dust.
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.4);
	ALBEDO = tint.rgb * (0.7 + 0.55 * n);
	ALPHA = smoothstep(0.32, 0.78, n) * ends * alpha * (0.3 + 0.7 * edge);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _swirl
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("turn", turn)
	m.set_shader_parameter("rise", rise)
	return m


## A soft round puff for particles.
static func puff() -> Texture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_puff = tex
	return _puff


static func _funnel(bottom: float, top: float, height: float, mat: Material) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.bottom_radius = bottom
	cone.top_radius = top
	cone.height = height
	cone.radial_segments = 16
	cone.rings = 4
	cone.cap_top = false
	cone.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3.UP * height * 0.5
	return mi


static func _puffs(amount: int, life: float, tint: Color, size: Vector2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	p.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(tint, 0.0))
	ramp.set_color(1, Color(tint, 0.0))
	ramp.add_point(0.2, Color(tint, 0.55))
	ramp.add_point(0.7, Color(tint, 0.3))
	p.color_ramp = ramp
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = grow
	p.gravity = Vector3.ZERO
	return p


## A dust devil, about 11 m tall: a swirling funnel of rust dust, a fainter
## one inside it, and dust thrown up and round from its foot.
static func dust_devil() -> Node3D:
	var root := Node3D.new()
	var dust := Color(0.86, 0.5, 0.32)
	root.add_child(_funnel(0.9, 4.6, 11.0, swirl(dust, 0.7, 1.8, 0.9)))
	root.add_child(_funnel(0.5, 2.6, 9.0, swirl(dust.lightened(0.15), 0.5, -2.4, 1.3)))
	var p := _puffs(34, 2.6, dust, Vector2(1.6, 3.2))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 2.2
	p.emission_ring_inner_radius = 0.6
	p.emission_ring_height = 0.6
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.tangential_accel_min = 5.0
	p.tangential_accel_max = 8.0
	p.radial_accel_min = 0.5
	p.radial_accel_max = 1.5
	p.position = Vector3.UP * 0.5
	root.add_child(p)
	return root


## A vent's gas: a column of pale gas boiling upward, puffs racing up it.
## `set_level` (0 off, a little for the warning's sputter, 1 full).
class Vent extends Node3D:
	var column: MeshInstance3D
	var puffs: CPUParticles3D
	var height := 16.0

	func setup(width: float, h: float) -> void:
		height = h
		var gas := Color(0.86, 1.0, 0.92)
		column = SpaceFx._funnel(width * 0.45, width * 0.95, h, SpaceFx.swirl(gas, 0.6, 0.8, 2.6))
		add_child(column)
		puffs = SpaceFx._puffs(40, 1.3, gas, Vector2(1.8, 3.6))
		puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		puffs.emission_box_extents = Vector3(width * 0.35, 0.3, 1.0)
		puffs.direction = Vector3.UP
		puffs.spread = 10.0
		puffs.initial_velocity_min = h * 0.8
		puffs.initial_velocity_max = h * 1.15
		puffs.damping_min = 2.0
		puffs.damping_max = 4.0
		add_child(puffs)
		set_level(0.0)

	func set_level(l: float) -> void:
		column.visible = l >= 0.99
		puffs.emitting = l > 0.0
		# A sputter: short, slow puffs that don't climb far.
		var v := height * (0.15 if l < 0.99 else 1.0)
		puffs.initial_velocity_min = v * 0.8
		puffs.initial_velocity_max = v * 1.15


static func vent(width: float, height: float) -> Vent:
	var v := Vent.new()
	v.setup(width, height)
	return v


## Something that wanders a closed loop by itself (dust devils away from
## the road).
class Roamer extends Node3D:
	var curve: Curve3D
	var speed := 5.0
	var _d := 0.0

	func _process(delta: float) -> void:
		_d = fposmod(_d + speed * delta, curve.get_baked_length())
		position = curve.sample_baked(_d, true)


static func roamer(thing: Node3D, path: PackedVector3Array, speed: float) -> Roamer:
	var r := Roamer.new()
	r.curve = KitDress.loop_curve(path)
	r.speed = speed
	r.add_child(thing)
	r.position = path[0]
	return r
