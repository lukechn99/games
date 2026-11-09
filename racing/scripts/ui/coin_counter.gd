class_name CoinCounter
extends Control
## The road coin's shared mesh, rendered into a tiny HUD preview at 20 Hz.

var coins := 0:
	set(value):
		if coins != value:
			coins = value
			queue_redraw()
var animate := true
var _preview: SubViewport
var _coin: MeshInstance3D
var _elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(82, 28)
	_preview = SubViewport.new()
	_preview.size = Vector2i(48, 48)
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_preview)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = environment
	_preview.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_color = Color(1, 0.95, 0.8)
	_preview.add_child(sun)
	_coin = MeshInstance3D.new()
	_coin.mesh = Items.coin_mesh()
	_coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.add_child(_coin)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.25
	camera.position = Vector3(2, 0.3, 0.7)
	_preview.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var icon := TextureRect.new()
	icon.texture = _preview.get_texture()
	# With the camera's framing, a 20 px box makes the coin silhouette match
	# the 20 px font's numeral height rather than tower above it.
	icon.position = Vector2(50, 4)
	icon.size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)


func _process(delta: float) -> void:
	if not animate or not is_visible_in_tree():
		_preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_elapsed += delta
	if _elapsed >= 0.05:
		_coin.rotation.y += _elapsed * 1.8
		_elapsed = 0.0
		_preview.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var count := "%d×" % coins
	draw_string_outline(font, Vector2(0, 21), count, HORIZONTAL_ALIGNMENT_RIGHT, 46, 20, 4, Color(0.1, 0.12, 0.18))
	draw_string(font, Vector2(0, 21), count, HORIZONTAL_ALIGNMENT_RIGHT, 46, 20, Color.WHITE)
