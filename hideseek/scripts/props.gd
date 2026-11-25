class_name Props
extends RefCounted
## Every object a hider can become (design doc 9.2). Scenery copies and
## hiders use the same mesh from here, so a hider looks exactly like the
## real thing. Each prop is one merged mesh with vertex colours: one draw.
##
## Origin is the bottom centre. `size` is the collision box.

const STRAW := Color(0.86, 0.72, 0.36)
const TWINE := Color(0.55, 0.42, 0.22)
const METAL := Color(0.58, 0.61, 0.63)
const METAL_DARK := Color(0.42, 0.45, 0.48)
const RUBBER := Color(0.14, 0.14, 0.15)
const WOOD := Color(0.63, 0.45, 0.27)
const WOOD_DARK := Color(0.45, 0.31, 0.18)
const BLUE_PAINT := Color(0.34, 0.5, 0.66)

## size class: small moves faster, large slower (design 8).
const KINDS := {
	"bale": {"name": "Hay bale", "size": Vector3(1.0, 0.5, 0.55), "class": "large"},
	"trash_can": {"name": "Trash can", "size": Vector3(0.62, 0.86, 0.62), "class": "medium"},
	"tire": {"name": "Tire", "size": Vector3(0.76, 0.2, 0.76), "class": "medium"},
	"chair": {"name": "Chair", "size": Vector3(0.48, 0.97, 0.48), "class": "medium"},
	"crate": {"name": "Crate", "size": Vector3(0.6, 0.6, 0.6), "class": "medium"},
	"bucket": {"name": "Bucket", "size": Vector3(0.36, 0.32, 0.36), "class": "small"},
	"rake": {"name": "Rake", "size": Vector3(0.42, 1.55, 0.12), "class": "medium", "leans": true},
}

const MODELS := "res://assets/models/%s.glb"

const SPEED := {"small": 1.1, "medium": 0.95, "large": 0.8}

static var _meshes := {}
static var relief := true        # normal maps; off on Low (and ?relief=off)
static var _material: StandardMaterial3D


static func kinds() -> Array:
	return KINDS.keys()


static func size(kind: String) -> Vector3:
	return KINDS[kind]["size"]


static func display_name(kind: String) -> String:
	return KINDS[kind]["name"]


static func speed_factor(kind: String) -> float:
	return SPEED[KINDS[kind]["class"]]


static func leans(kind: String) -> bool:
	return KINDS[kind].get("leans", false)


## A random prop from `pool`, never the same as `exclude` (a reroll must
## change something). Uses the caller's own generator (LEARNINGS: no shared
## random generators).
static func random_kind(rng: RandomNumberGenerator, pool: Array, exclude := "") -> String:
	var choices := pool.filter(func(k): return k != exclude)
	if choices.is_empty():
		return exclude
	return choices[rng.randi_range(0, choices.size() - 1)]


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.9
	return _material


## The Blender model (assets/models/<kind>.glb, tools/blender/props.py)
## if there is one, else the block-built stand-in below.
static func mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var path := MODELS % kind
		var m: Mesh = null
		if ResourceLoader.exists(path):
			var inst := (load(path) as PackedScene).instantiate()
			var mi := inst.find_children("*", "MeshInstance3D", true, false)
			if not mi.is_empty():
				m = (mi[0] as MeshInstance3D).mesh
			inst.free()
		if m and not relief:
			m = m.duplicate()
			var mat := (m.surface_get_material(0) as StandardMaterial3D).duplicate()
			mat.normal_enabled = false
			m.surface_set_material(0, mat)
		_meshes[kind] = m if m else _build(kind)
	return _meshes[kind]


static func has_model(kind: String) -> bool:
	return ResourceLoader.exists(MODELS % kind)


static func _build(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"bale":
			_box(st, Vector3(1.0, 0.5, 0.55), Vector3(0, 0.25, 0), STRAW)
			for x in [-0.27, 0.27]:
				_box(st, Vector3(0.05, 0.52, 0.57), Vector3(x, 0.25, 0), TWINE)
		"trash_can":
			_cyl(st, 0.28, 0.26, 0.8, Vector3(0, 0.4, 0), METAL)
			for y in [0.2, 0.6]:
				_cyl(st, 0.295, 0.295, 0.04, Vector3(0, y, 0), METAL_DARK)
			_cyl(st, 0.31, 0.31, 0.05, Vector3(0, 0.825, 0), METAL_DARK)
			_box(st, Vector3(0.14, 0.04, 0.04), Vector3(0, 0.87, 0), METAL_DARK)
		"tire":
			var t := TorusMesh.new()
			t.inner_radius = 0.18
			t.outer_radius = 0.38
			t.rings = 16
			t.ring_segments = 8
			_add(st, t, Transform3D(Basis(), Vector3(0, 0.1, 0)), RUBBER)
		"chair":
			_box(st, Vector3(0.46, 0.05, 0.46), Vector3(0, 0.45, 0), WOOD)
			for x in [-0.2, 0.2]:
				for z in [-0.2, 0.2]:
					_box(st, Vector3(0.05, 0.45, 0.05), Vector3(x, 0.225, z), WOOD_DARK)
				_box(st, Vector3(0.05, 0.5, 0.05), Vector3(x, 0.72, -0.2), WOOD_DARK)
			_box(st, Vector3(0.44, 0.08, 0.04), Vector3(0, 0.92, -0.2), WOOD)
			_box(st, Vector3(0.44, 0.06, 0.03), Vector3(0, 0.7, -0.2), WOOD)
		"crate":
			_box(st, Vector3(0.56, 0.56, 0.56), Vector3(0, 0.3, 0), WOOD)
			for x in [-0.27, 0.27]:
				for z in [-0.27, 0.27]:
					_box(st, Vector3(0.07, 0.6, 0.07), Vector3(x, 0.3, z), WOOD_DARK)
			for y in [0.035, 0.565]:
				_box(st, Vector3(0.6, 0.07, 0.07), Vector3(0, y, 0.27), WOOD_DARK)
				_box(st, Vector3(0.6, 0.07, 0.07), Vector3(0, y, -0.27), WOOD_DARK)
		"bucket":
			_cyl(st, 0.17, 0.14, 0.3, Vector3(0, 0.15, 0), BLUE_PAINT)
			_cyl(st, 0.178, 0.178, 0.03, Vector3(0, 0.3, 0), METAL)
		"rake":
			_cyl(st, 0.02, 0.02, 1.45, Vector3(0, 0.725, 0), WOOD)
			_box(st, Vector3(0.42, 0.05, 0.05), Vector3(0, 1.47, 0), METAL_DARK)
			for i in 7:
				_box(st, Vector3(0.025, 0.1, 0.025), Vector3(-0.18 + i * 0.06, 1.53, 0.02), METAL_DARK)
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, material())
	return m


static func _box(st: SurfaceTool, s: Vector3, at: Vector3, c: Color) -> void:
	var b := BoxMesh.new()
	b.size = s
	_add(st, b, Transform3D(Basis(), at), c)


static func _cyl(st: SurfaceTool, top: float, bottom: float, h: float, at: Vector3, c: Color) -> void:
	var cy := CylinderMesh.new()
	cy.top_radius = top
	cy.bottom_radius = bottom
	cy.height = h
	cy.radial_segments = 14
	cy.rings = 1
	_add(st, cy, Transform3D(Basis(), at), c)


static func _add(st: SurfaceTool, m: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
	var arr := m.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_color(c)
		st.set_normal((xf.basis * norms[i]).normalized())
		st.set_uv(uvs[i] if i < uvs.size() else Vector2.ZERO)
		st.add_vertex(xf * verts[i])
