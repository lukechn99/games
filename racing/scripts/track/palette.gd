class_name Palette
## Our bold cartoon palette (design doc 9.1). The Kenney kits are CC0, so we
## restyle them freely: each kit material is matched by name and replaced
## with a toon material in our colours. Anything we build ourselves uses
## the same colours, so everything looks like one world.

const KIT := {
	"leafsGreen": Color(0.36, 0.8, 0.24),
	"leafsDark": Color(0.13, 0.6, 0.29),
	"grass": Color(0.42, 0.82, 0.27),
	"woodBark": Color(0.62, 0.36, 0.2),
	"woodBarkDark": Color(0.5, 0.29, 0.17),
	"wood": Color(0.86, 0.56, 0.3),
	"woodDark": Color(0.62, 0.37, 0.2),
	"woodInner": Color(0.98, 0.86, 0.68),
	"dirt": Color(0.64, 0.6, 0.57),   # the kit's boulders use this one: grey rock
	"red": Color(0.96, 0.22, 0.25),
	"colorRed": Color(0.96, 0.22, 0.25),
	"colorYellow": Color(1.0, 0.68, 0.1),
	"pylon": Color(1.0, 0.55, 0.08),
	"grey": Color(0.9, 0.91, 0.94),
	"glass": Color(0.35, 0.6, 0.9),
	"road": Color(0.26, 0.27, 0.33),
	"net": Color(0.95, 0.95, 0.97),
	"checkers": Color(1, 1, 1),
}

const OUTLINE := Color(0.13, 0.1, 0.16)

## How a surface catches the light (design doc 9.4).
## MATTE: wood, rock, grass, fur, rubber. No shine.
## PAINT: kart bodywork. A soft highlight and a little rim light.
## METAL: tubes, rims, rails. A sharp bright highlight.
enum Finish { MATTE, PAINT, METAL }

## (The kit's "grey" is painted steel, not chrome: as chrome it mirrored the
## sky and the start arch and rails looked like blue glass.)
const METAL_KIT := ["metal", "metalDark", "chrome"]
const PAINT_KIT := ["grey"]
## Detail textures for kit materials: [texture, metres per tile].
const KIT_TEX := {
	"dirt": ["rock", 2.5],
	"woodBark": ["rock", 1.0],
	"woodBarkDark": ["rock", 1.0],
	"wood": ["wood", 1.5],
	"woodDark": ["wood", 1.5],
	"woodInner": ["wood", 1.0],
	"grass": ["grass", 2.0],
}
const TEX_DIR := "res://assets/textures/"

static var _cache := {}
static var relief_shaders: Array[ShaderMaterial] = []   # shader materials with a 'relief' strength
static var _detailed: Array[StandardMaterial3D] = []   # materials with normal maps
static var _shiny: Array[StandardMaterial3D] = []      # paint and metal
static var relief_on := true     # set by main.gd from the graphics quality
static var clearcoat_on := true


## Turn surface relief (normal maps) and clear-coat shine on or off for
## every material, when the graphics quality changes.
static func apply_quality(relief: bool, clearcoat: bool) -> void:
	relief_on = relief
	clearcoat_on = clearcoat
	for m in _detailed:
		m.normal_enabled = relief
	for m in relief_shaders:
		if is_instance_valid(m):
			m.set_shader_parameter("relief", 1.0 if relief else 0.0)
	for m in _shiny:
		m.clearcoat_enabled = clearcoat and m.get_meta("paint", false)


## Give a textured material the matching normal map (assets/textures/*_n.png).
static func add_relief(m: StandardMaterial3D, tex: String, strength := 1.0) -> void:
	var path := TEX_DIR + tex + "_n.png"
	if not ResourceLoader.exists(path):
		return
	m.normal_texture = load(path)
	m.normal_scale = strength
	m.normal_enabled = relief_on
	_detailed.append(m)


## A flat cartoon-shaded material. `vertex_colors` uses per-vertex colours
## (for merged meshes); `outline` adds an ink outline around the shape.
## `tex` adds a greyscale detail texture (assets/textures) over the colour.
## With `tile_m` > 0 it is projected from the world (triplanar), one tile
## every `tile_m` metres, so it works on models without texture coordinates.
static func toon(c: Color, vertex_colors := false, outline := 0.0, finish := Finish.MATTE, tex := "", tile_m := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s|%s" % [c.to_html(), vertex_colors, outline, finish, tex, tile_m]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = str(finish)
	m.albedo_color = c
	m.vertex_color_use_as_albedo = vertex_colors
	m.vertex_color_is_srgb = true  # merged meshes store our colours as written
	# Soft light that wraps round the shapes (as in Mario Kart), not hard
	# cartoon steps.
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	if tex != "":
		m.albedo_texture = load(TEX_DIR + tex + ".png")
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if tile_m > 0.0:
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE / tile_m
			m.uv1_triplanar_sharpness = 4.0
		add_relief(m, tex)
	match finish:
		Finish.METAL:
			# Chrome-like: mostly reflects the sky, with a sharp sun highlight.
			m.metallic = 0.85
			m.metallic_specular = 1.0
			m.roughness = 0.18
			m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			m.rim_enabled = true
			m.rim = 0.3
			m.rim_tint = 0.3
			_shiny.append(m)
		Finish.PAINT:
			# Glossy paint with a clear coat that catches the sun.
			m.metallic_specular = 0.6
			m.roughness = 0.35
			m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			m.rim_enabled = true
			m.rim = 0.12
			m.rim_tint = 0.9   # rim light in the paint colour, so it doesn't wash out
			m.clearcoat = 0.6
			m.clearcoat_roughness = 0.15
			m.set_meta("paint", true)
			m.clearcoat_enabled = clearcoat_on
			_shiny.append(m)
		_:
			m.roughness = 1.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if outline > 0.0:
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.albedo_color = OUTLINE
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = outline
		m.next_pass = o
	_cache[key] = m
	return m


## Karts and drivers: soft, glossy shading like Mario Kart's rather than
## the scenery's hard cartoon steps (shaders/kart.gdshader). `c` tints it
## when there are no vertex colours (pieces kept apart from the merged kart).
static func kart(finish: int, c := Color.WHITE) -> ShaderMaterial:
	var key := "kart|%s|%s" % [finish, c.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/kart.gdshader")
	m.resource_name = str(finish)
	m.set_shader_parameter("use_vertex", c == Color.WHITE)
	m.set_shader_parameter("tint", c)
	match finish:
		Finish.METAL:
			m.set_shader_parameter("gloss", 0.75)
			m.set_shader_parameter("metal", 1.0)
		Finish.PAINT:
			m.set_shader_parameter("gloss", 0.6)
		_:
			# Fur, rubber, cloth: no gloss at all (fur looked shiny).
			m.set_shader_parameter("gloss", 0.0)
			m.set_shader_parameter("rim_amt", 0.12)
	_cache[key] = m
	return m


## The ink outline on its own (drawn as a separate, nearby-only mesh).
static func outline_material(width: float) -> StandardMaterial3D:
	var key := "outline|%s" % width
	if _cache.has(key):
		return _cache[key]
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.albedo_color = OUTLINE
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = width
	_cache[key] = o
	return o


## Leaves that sway in the wind (shaders/leaves.gdshader).
static func leaves(c: Color) -> ShaderMaterial:
	var key := "leaves|" + c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/leaves.gdshader")
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("detail", load(TEX_DIR + "grass.png"))
	_cache[key] = m
	return m


## A copy of a kit mesh with our colours in place of the kit's.
static func restyle(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var key := "mesh|%d" % mesh.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var out: Mesh = mesh.duplicate()
	for i in out.get_surface_count():
		var src := mesh.surface_get_material(i)
		var name := src.resource_name if src else ""
		if name == "TreeVertex":
			if not _cache.has("tree_vertex"):
				var tree := ShaderMaterial.new()
				tree.shader = load("res://shaders/tree.gdshader")
				_cache["tree_vertex"] = tree
			out.surface_set_material(i, _cache["tree_vertex"])
			continue
		var c: Color = KIT.get(name, (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color.WHITE)
		if name.begins_with("leafs"):
			out.surface_set_material(i, leaves(c))
			continue
		var t: Array = KIT_TEX.get(name, ["", 0.0])
		out.surface_set_material(i, toon(c, false, 0.0, Finish.METAL if name in METAL_KIT else (Finish.PAINT if name in PAINT_KIT else Finish.MATTE), t[0], t[1]))
	_cache[key] = out
	return out


## Restyle every mesh in a placed kit scene.
static func restyle_tree(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.mesh = restyle(mi.mesh)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		stack.append_array(n.get_children())
