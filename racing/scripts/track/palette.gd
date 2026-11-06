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
	"dirt": Color(0.72, 0.45, 0.25),
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

const METAL_KIT := ["grey", "metal", "metalDark", "chrome"]

static var _cache := {}


## A flat cartoon-shaded material. `vertex_colors` uses per-vertex colours
## (for merged meshes); `outline` adds an ink outline around the shape.
static func toon(c: Color, vertex_colors := false, outline := 0.0, finish := Finish.MATTE) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), vertex_colors, outline, finish]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = str(finish)
	m.albedo_color = c
	m.vertex_color_use_as_albedo = vertex_colors
	m.vertex_color_is_srgb = true  # merged meshes store our colours as written
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	match finish:
		Finish.METAL:
			m.metallic = 0.45
			m.metallic_specular = 1.0
			m.roughness = 0.22
			m.specular_mode = BaseMaterial3D.SPECULAR_TOON
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.2
		Finish.PAINT:
			m.metallic_specular = 0.6
			m.roughness = 0.38
			m.specular_mode = BaseMaterial3D.SPECULAR_TOON
			m.rim_enabled = true
			m.rim = 0.2
			m.rim_tint = 0.6
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
		var c: Color = KIT.get(name, (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color.WHITE)
		out.surface_set_material(i, toon(c, false, 0.0, Finish.METAL if name in METAL_KIT else Finish.MATTE))
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
