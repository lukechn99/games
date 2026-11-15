class_name KitTools
extends RefCounted
## Shared helpers for Series 2 track kits (design doc 8.4): Blender models
## placed many at a time, glowing surfaces, and simple strips of wall.

static var _models := {}
static var _plate: ImageTexture


## A Blender prop (assets/models/NAME.glb) as one mesh, shaded like the
## karts: soft, glossy paint. Materials named "Glow…" shine by themselves
## (no light needed, so they cost nothing extra).
static func model(name: String) -> Mesh:
	if not _models.has(name):
		var inst: Node = (load("res://assets/models/%s.glb" % name) as PackedScene).instantiate()
		var src: MeshInstance3D = inst if inst is MeshInstance3D else inst.find_children("*", "MeshInstance3D", true, false)[0]
		var m: Mesh = src.mesh.duplicate()
		for i in m.get_surface_count():
			var sm := m.surface_get_material(i) as BaseMaterial3D
			var c: Color = sm.albedo_color if sm else Color(0.8, 0.8, 0.8)
			if sm and sm.resource_name.begins_with("Glow"):
				m.surface_set_material(i, glow(c))
			else:
				m.surface_set_material(i, Palette.kart(Palette.Finish.PAINT, c))
		inst.free()
		_models[name] = m
	return _models[name]


## Many copies of a prop in one go (one draw call per material). `far`:
## don't draw it beyond this many metres (0: always).
static func place(parent: Node3D, name: String, xforms: Array[Transform3D], far := 0.0) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = model(name)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if far > 0.0:
		mi.visibility_range_end = far
	parent.add_child(mi)


static func glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	return m


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flip := false) -> void:
	var order := [a, b, c, a, c, d] if not flip else [a, c, b, a, d, c]
	for v: Vector3 in order:
		st.set_color(col)
		st.add_vertex(v)


## A box from quads (for frames, pillars and signs), in vertex colour.
static func box(st: SurfaceTool, at: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	for f: Array in [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
			[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
			[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var corners: Array[Vector3] = []
		for c: Vector3 in [n - u - v, n - u + v, n + u + v, n + u - v]:
			corners.append(at * Vector3(c.x * h.x, c.y * h.y, c.z * h.z))
		quad(st, corners[0], corners[1], corners[2], corners[3], col)


static func commit(parent: Node3D, st: SurfaceTool, mat: Material, two_sided := false) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := mat
	if two_sided and mat is BaseMaterial3D:
		m = mat.duplicate()
		(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Solid, unseen walls from a wall mesh (a road's sides).
static func solid(parent: Node3D, mesh: Mesh, surface := "asphalt") -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", surface)
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)


## Indoor stretches of a lap: walls, a roof and lights. Each room is
## [from, to, wall height, style, light colour, (its own wall colour)], with
## from and to in metres round the lap. Styles: "solid" (full walls with a line of light), "glass"
## (a low rail and pillars: you see out), "rail" (a low lit rail under a
## high roof, open to the hall around). Walls are solid to the roof in every
## style. "open" is outdoors: a low barrier, no roof and no lights (still
## solid to its height, so karts stay on the road).
static func rooms(t: Track, list: Array, wall: Color, pillar: Color) -> void:
	var half := Track.ROAD_WIDTH * 0.5 + 1.0
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lights := SurfaceTool.new()
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hit := SurfaceTool.new()
	hit.begin(Mesh.PRIMITIVE_TRIANGLES)
	for room: Array in list:
		var d0: float = room[0]
		var d1: float = room[1]
		if d1 <= d0:
			d1 += t.length
		var h: float = room[2]
		var glass: bool = room[3] == "glass"
		var rail: bool = room[3] == "rail"
		var open: bool = room[3] == "open"
		var lamp: Color = room[4]
		var own: Color = room[5] if room.size() > 5 else wall
		var d := d0
		var index := 0
		while d < d1 - 0.1:
			var a := t.road_frame(d)
			var b := t.road_frame(minf(d + 4.0, d1))
			for side: float in [-1.0, 1.0]:
				var a0: Vector3 = a.origin + a.basis.x * side * half
				var b0: Vector3 = b.origin + b.basis.x * side * half
				var flip: bool = side < 0.0
				quad(hit, a0, b0, b0 + Vector3.UP * h, a0 + Vector3.UP * h, wall, flip)
				# A second sheet just behind: a kart hitting a single thin
				# sheet hard, at an angle, can slip through it.
				var a2 := a0 + a.basis.x * side * 0.8
				var b2 := b0 + b.basis.x * side * 0.8
				quad(hit, a2, b2, b2 + Vector3.UP * h, a2 + Vector3.UP * h, wall, flip)
				var top := 0.9 if open else (1.3 if glass or rail else h)
				var shade := own if index % 2 == 0 else own.lightened(0.07)
				quad(walls, a0, b0, b0 + Vector3.UP * top, a0 + Vector3.UP * top, shade, flip)
				if glass:
					if index % 3 == 0:
						var mid := a0.lerp(b0, 0.12)
						quad(walls, a0 + Vector3.UP * top, mid + Vector3.UP * top, mid + Vector3.UP * h, a0 + Vector3.UP * h, pillar, flip)
				elif open:
					pass
				elif rail:
					quad(lights, a0 + Vector3.UP * 1.3, b0 + Vector3.UP * 1.3, b0 + Vector3.UP * 1.3 - b.basis.x * side * 0.5, a0 + Vector3.UP * 1.3 - a.basis.x * side * 0.5, lamp, not flip)
				else:
					quad(lights, a0 + Vector3.UP * 2.3 - a.basis.x * side * 0.05, b0 + Vector3.UP * 2.3 - b.basis.x * side * 0.05,
						b0 + Vector3.UP * 2.75 - b.basis.x * side * 0.05, a0 + Vector3.UP * 2.75 - a.basis.x * side * 0.05, lamp, flip)
			var ra := a.origin + Vector3.UP * h
			var rb := b.origin + Vector3.UP * h
			if not open:
				quad(walls, ra - a.basis.x * half, rb - b.basis.x * half, rb + b.basis.x * half, ra + a.basis.x * half, own.darkened(0.3), true)
			if index % 4 == 1 and not open:
				var la := ra.lerp(rb, 0.2) - Vector3.UP * 0.06
				var lb := ra.lerp(rb, 0.5) - Vector3.UP * 0.06
				quad(lights, la - a.basis.x * 3.5, lb - b.basis.x * 3.5, lb + b.basis.x * 3.5, la + a.basis.x * 3.5, lamp.lerp(Color.WHITE, 0.5), true)
			d += 4.0
			index += 1
	commit(parent_of(t), walls, Palette.toon(Color.WHITE, true), true)
	commit(parent_of(t), lights, glow(Color.WHITE), true)
	hit.generate_normals()
	solid(t, hit.commit())


static func parent_of(t: Track) -> Node3D:
	return t


## Lap distance of point number `i` of a kit's POINTS (fractions fall
## between points; the point count itself is the end of the lap).
static func at(t: Track, points: Array, i: float) -> float:
	var n := points.size()
	if i >= float(n):
		return t.length - 0.01
	var a := t.offset_of(points[int(floorf(i)) % n])
	var b := t.offset_of(points[int(ceilf(i)) % n])
	if b < a:
		b += t.length
	return fposmod(lerpf(a, b, i - floorf(i)), t.length)


## Deck plating: pale panels with dark seams and a few rivets, tiling.
static func plate_texture() -> ImageTexture:
	if _plate == null:
		var n := 128
		var img := Image.create(n, n, true, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var v := 0.86
				var px := x % 64
				var py := y % 64
				if px < 2 or py < 2:
					v = 0.5
				elif px < 4 or py < 4:
					v = 0.95
				elif (px in [10, 11, 54, 55]) and (py in [10, 11, 54, 55]):
					v = 0.6
				# Alternate panels a shade apart.
				if ((x / 64) + (y / 64)) % 2 == 0:
					v *= 0.94
				img.set_pixel(x, y, Color(v, v, v))
		img.generate_mipmaps()
		_plate = ImageTexture.create_from_image(img)
	return _plate


## Rows of windows on a pale wall, tiling (two windows by two floors).
static var _windows: ImageTexture


static func window_texture() -> ImageTexture:
	if _windows == null:
		var n := 64
		var img := Image.create(n, n, true, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var px := x % 32
				var py := y % 32
				var glass := px > 7 and px < 25 and py > 8 and py < 26
				img.set_pixel(x, y, Color(0.34, 0.46, 0.6) if glass else Color(1, 1, 1))
		img.generate_mipmaps()
		_windows = ImageTexture.create_from_image(img)
	return _windows


## City blocks: many boxes in one draw call, each [base centre, size,
## colour], with windows that tile the same on every size of block.
static func buildings(parent: Node3D, blocks: Array) -> void:
	if blocks.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = blocks.size()
	for i in blocks.size():
		var b: Array = blocks[i]
		var size: Vector3 = b[1]
		var turn: Basis = b[3] if b.size() > 3 else Basis()
		mm.set_instance_transform(i, Transform3D(turn * Basis().scaled(size), (b[0] as Vector3) + Vector3.UP * size.y * 0.5))
		mm.set_instance_color(i, b[2])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = window_texture()
	mat.vertex_color_use_as_albedo = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 9.0
	mat.roughness = 0.9
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
