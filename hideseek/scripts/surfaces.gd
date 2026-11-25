class_name Surfaces
extends RefCounted
## Building and ground surfaces (tools/textures.py): seamless colour and
## normal maps, loaded straight from their JPEGs. They're named .jpg.bin so
## Godot doesn't import them and ships the small files as they are (an
## import re-encodes them losslessly, several times larger). A Builder that merges geometry into one
## draw call per surface, with UVs in metres so every wall uses the same scale.

const DIR := "res://assets/textures/"

## Metres covered by one copy of each texture (same as tools/textures.py).
const TILE := {
	"barn_siding": 2.4, "trim": 1.2, "barn_roof": 2.0, "house_siding": 1.8,
	"shingles": 2.0, "silo_metal": 2.0, "floor": 2.4, "grass": 3.0,
	"dirt": 3.0, "concrete": 2.0,
}

## How each surface takes the light. Metal shines (design: "metal shine for
## the silo"), paint and wood stay soft.
const FINISH := {
	"silo_metal": {"metallic": 0.85, "roughness": 0.28, "specular": 0.6},
	"barn_roof": {"metallic": 0.55, "roughness": 0.5},
	"trim": {"roughness": 0.7},
	"house_siding": {"roughness": 0.75},
	"shingles": {"roughness": 0.95},
	"grass": {"roughness": 1.0, "specular": 0.2},
	"dirt": {"roughness": 1.0, "specular": 0.25},
}

## Untextured finishes.
const PLAIN := {
	"glass": {"color": Color(0.16, 0.22, 0.28), "metallic": 0.4, "roughness": 0.08},
	"door": {"color": Color(0.17, 0.32, 0.25), "roughness": 0.6},
	"dark": {"color": Color(0.08, 0.07, 0.07), "roughness": 1.0},
}

static var _mats := {}


static func material(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	if PLAIN.has(name):
		var p: Dictionary = PLAIN[name]
		m.albedo_color = p["color"]
		m.metallic = p.get("metallic", 0.0)
		m.roughness = p.get("roughness", 0.8)
	else:
		var f: Dictionary = FINISH.get(name, {})
		m.albedo_texture = _texture(name + "_albedo.jpg.bin")
		if Props.relief:
			m.normal_enabled = true
			m.normal_texture = _texture(name + "_normal.jpg.bin")
		m.metallic = f.get("metallic", 0.0)
		m.metallic_specular = f.get("specular", 0.5)
		m.roughness = f.get("roughness", 0.85)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[name] = m
	return m


static func _texture(file: String) -> Texture2D:
	var img := Image.new()
	var err := img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(DIR + file))
	if err != OK:
		push_error("missing texture " + file)
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Collects geometry per surface; commit() makes one mesh with one surface
## (one draw call) per material.
class Builder:
	var _st := {}

	func _tool(surface: String) -> SurfaceTool:
		if not _st.has(surface):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[surface] = st
		return _st[surface]

	func _uv(surface: String, p: Vector3, n: Vector3) -> Vector2:
		var t: float = Surfaces.TILE.get(surface, 1.0)
		var a := n.abs()
		if a.y >= a.x and a.y >= a.z:
			return Vector2(p.x, p.z) / t
		if a.x >= a.z:
			return Vector2(p.z * signf(n.x), -p.y) / t
		return Vector2(-p.x * signf(n.z), -p.y) / t

	func _vert(st: SurfaceTool, surface: String, p: Vector3, n: Vector3, uv = null) -> void:
		st.set_normal(n)
		st.set_uv(uv if uv != null else _uv(surface, p, n))
		st.add_vertex(p)

	## A box, UVs projected from world space (so neighbouring boxes line up).
	func box(surface: String, size: Vector3, at: Vector3, b := Basis()) -> void:
		var bm := BoxMesh.new()
		bm.size = size
		var arr := bm.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var st := _tool(surface)
		var xf := Transform3D(b, at)
		for i in idx:
			_vert(st, surface, xf * verts[i], (b * norms[i]).normalized())

	## A flat triangle, seen from the side a -> b -> c turns anticlockwise
	## (Godot's front faces are clockwise, so it's emitted reversed).
	func tri(surface: String, a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (b - a).cross(c - a).normalized()
		var st := _tool(surface)
		for p in [a, c, b]:
			_vert(st, surface, p, n)

	## An open cylinder (silo), with the texture wrapping a whole number of
	## times so there is no seam.
	func cylinder(surface: String, radius: float, height: float, at: Vector3, segments := 40) -> void:
		var t: float = Surfaces.TILE.get(surface, 1.0)
		var repeats := maxf(1.0, roundf(TAU * radius / t))
		var st := _tool(surface)
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var n0 := Vector3(cos(a0), 0, sin(a0))
			var n1 := Vector3(cos(a1), 0, sin(a1))
			var u0 := -repeats * i / segments
			var u1 := -repeats * (i + 1) / segments
			var v1 := -height / t
			var p00 := at + n0 * radius
			var p10 := at + n1 * radius
			var p01 := p00 + Vector3(0, height, 0)
			var p11 := p10 + Vector3(0, height, 0)
			for q in [[p00, n0, Vector2(u0, 0)], [p11, n1, Vector2(u1, v1)], [p01, n0, Vector2(u0, v1)],
					[p00, n0, Vector2(u0, 0)], [p10, n1, Vector2(u1, 0)], [p11, n1, Vector2(u1, v1)]]:
				_vert(st, surface, q[0], q[1], q[2])

	## A dome cap (silo roof).
	func dome(surface: String, radius: float, rise: float, at: Vector3, segments := 40, rings := 8) -> void:
		var t: float = Surfaces.TILE.get(surface, 1.0)
		var repeats := maxf(1.0, roundf(TAU * radius / t))
		var st := _tool(surface)
		var pt := func(i: int, j: int) -> Array:
			var a := TAU * i / segments
			var phi := (PI / 2) * j / rings
			var r := radius * cos(phi)
			var p: Vector3 = at + Vector3(cos(a) * r, rise * sin(phi), sin(a) * r)
			var n := Vector3(cos(a) * cos(phi) / radius, sin(phi) / rise, sin(a) * cos(phi) / radius).normalized()
			return [p, n, Vector2(-repeats * i / segments, -(PI / 2 * radius) * j / rings / t)]
		for j in rings:
			for i in segments:
				var a: Array = pt.call(i, j)
				var b: Array = pt.call(i + 1, j)
				var c: Array = pt.call(i + 1, j + 1)
				var d: Array = pt.call(i, j + 1)
				for q in [a, c, d, a, b, c]:
					_vert(st, surface, q[0], q[1], q[2])

	func commit(name: String) -> MeshInstance3D:
		var mesh := ArrayMesh.new()
		for surface in _st:
			var st: SurfaceTool = _st[surface]
			st.generate_tangents()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, Surfaces.material(surface))
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = mesh
		return mi
