class_name StarlinerTrack
extends RefCounted
## Starliner Run (design doc 8.4): a lap of a giant starship, inside and out.
## Launch from the hangar, a long glass corridor, the engine room, up to the
## low-gravity hall, out along the hull with no walls, and down through the
## cargo deck. About 2,000 m. A Series 2 track: it brings its own world
## (Track.kit_of), with no ground, grass or mountains.
##
## This is the grey-box: the lap, its walls and the space around it. Set
## pieces, mechanics (gravity, vents, the airlock, cargo lifts) and art come
## after the lap is proven drivable.

const POINTS := [
	# Hangar: the grid, launching along the ship's length.
	Vector3(0, 0, 60), Vector3(0, 0, -40),
	# Glass corridor: long and fast, with one gentle sweep.
	Vector3(-10, 0, -150), Vector3(-6, 0, -260), Vector3(8, 0, -360),
	# Round into the engine room.
	Vector3(40, 0, -432), Vector3(105, 0, -462), Vector3(180, 0, -450),
	# Engine room: S-bends between the reactors.
	Vector3(240, 0, -408), Vector3(300, 0, -430), Vector3(362, 0, -398),
	# The climb to the low-gravity hall.
	Vector3(402, 4, -338), Vector3(412, 8, -250), Vector3(384, 10, -172),
	# Low-gravity hall.
	Vector3(352, 10, -100), Vector3(372, 10, -20),
	# Out through the lock and up onto the hull.
	Vector3(402, 15, 62), Vector3(384, 20, 150), Vector3(304, 22, 204),
	# Hull walk: a long open sweep with nothing either side.
	Vector3(200, 22, 218), Vector3(100, 20, 196), Vector3(-28, 14, 206),
	# Cargo deck: down a chicane and back to the hangar.
	Vector3(-58, 8, 160), Vector3(-30, 3, 112),
]
## Stretches inside the ship, by point number (walled and roofed); the rest
## (the hull walk) is open to space.
const INSIDE := [[0, 16], [21.4, 24]]
const WALL_H := 7.0
const DECK := Color(0.9, 0.925, 0.96)        # panel white
const WALL := Color(0.36, 0.4, 0.48)         # deck grey
const NAVY := Color(0.078, 0.106, 0.2)       # hull navy
const CYAN := Color(0.21, 0.88, 1.0)         # reactor cyan
const AMBER := Color(1.0, 0.7, 0.12)         # warning amber
const VIOLET := Color(0.69, 0.29, 0.88)      # nebula violet


static func configure(t: Track) -> void:
	t.points = POINTS
	t.surface_zones = []
	t.rail_zones = []
	t.ground_y = -60.0
	t.road_color = DECK.darkened(0.45)
	t.kerb_colors = [CYAN.darkened(0.15), DECK]


static func plan(_t: Track) -> void:
	pass


## The sky and light for this track (main.gd, when the world is made).
static func world(env: Environment, sun: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = NAVY.darkened(0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.95)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = false
	sun.light_color = Color(0.95, 0.97, 1.0)
	sun.light_energy = 0.9


static func crate_frames(t: Track) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for u in [0.16, 0.5, 0.8]:
		out.append(t.transform_at(t.length * u))
	return out


static func build(t: Track) -> void:
	_walls(t)
	_space(t)


## Lap distance of point number `i` (fractions fall between points).
static func _at(t: Track, i: float) -> float:
	var n := POINTS.size()
	var a := t.offset_of(POINTS[int(floorf(i)) % n])
	var b := t.offset_of(POINTS[int(ceilf(i)) % n])
	if b < a:
		b += t.length
	return lerpf(a, b, i - floorf(i))


## Corridor walls and a roof wherever the lap is inside the ship. The walls
## are solid; the roof is only drawn.
static func _walls(t: Track) -> void:
	var half := Track.ROAD_WIDTH * 0.5 + 1.0
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	for span: Array in INSIDE:
		var d0 := _at(t, span[0])
		var d1 := _at(t, span[1])
		if d1 <= d0:
			d1 += t.length
		var d := d0
		var index := 0
		while d < d1:
			var a := t.road_frame(d)
			var b := t.road_frame(minf(d + 4.0, d1))
			# A stripe of warning amber low on the wall every few panels.
			var c := WALL if index % 6 != 0 else WALL.lerp(AMBER, 0.55)
			for side in [-1.0, 1.0]:
				var a0: Vector3 = a.origin + a.basis.x * side * half
				var b0: Vector3 = b.origin + b.basis.x * side * half
				var a1 := a0 + Vector3.UP * WALL_H
				var b1 := b0 + Vector3.UP * WALL_H
				_quad(walls, a0, b0, b1, a1, c, side < 0.0)
			var ra := a.origin + Vector3.UP * WALL_H
			var rb := b.origin + Vector3.UP * WALL_H
			_quad(roof, ra - a.basis.x * half, rb - b.basis.x * half, rb + b.basis.x * half, ra + a.basis.x * half, WALL.darkened(0.25), true)
			d += 4.0
			index += 1
	walls.generate_normals()
	var wall_mesh := walls.commit()
	var body := StaticBody3D.new()
	body.set_meta("surface", "asphalt")
	t.add_child(body)
	var shape := CollisionShape3D.new()
	var tri := wall_mesh.create_trimesh_shape() as ConcavePolygonShape3D
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)
	var mat := Palette.toon(Color.WHITE, true)
	var two_sided := mat.duplicate() as StandardMaterial3D
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wi := MeshInstance3D.new()
	wi.mesh = wall_mesh
	wi.material_override = two_sided
	body.add_child(wi)
	roof.generate_normals()
	var ri := MeshInstance3D.new()
	ri.mesh = roof.commit()
	ri.material_override = two_sided
	t.add_child(ri)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flip := false) -> void:
	var order := [a, b, c, a, c, d] if not flip else [a, c, b, a, d, c]
	for v: Vector3 in order:
		st.set_color(col)
		st.add_vertex(v)


## What's outside: stars, a planet below, and the ship's own bulk under the
## decks. Three draw calls.
static func _space(t: Track) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stars := SurfaceTool.new()
	stars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(180, 0, -120)
	for i in 700:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 1)).normalized()
		var p := centre + dir * 1500.0
		var size := rng.randf_range(1.5, 4.5)
		var right := dir.cross(Vector3.UP).normalized() * size
		var up := right.cross(dir).normalized() * size
		var c := Color.WHITE.lerp(CYAN if i % 5 == 0 else VIOLET, rng.randf() * 0.5)
		_quad(stars, p - right - up, p + right - up, p + right + up, p - right + up, c)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	var si := MeshInstance3D.new()
	si.mesh = stars.commit()
	si.material_override = glow
	si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(si)
	# A planet, below and to one side.
	var planet := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 520.0
	ball.height = 1040.0
	ball.radial_segments = 48
	ball.rings = 24
	planet.mesh = ball
	planet.material_override = Palette.toon(VIOLET.lerp(CYAN, 0.25))
	planet.position = centre + Vector3(-520, -640, 520)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(planet)
	# The ship under the decks: one long dark body (drawn only; drive off
	# the hull walk and you fall past it).
	var hull := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(560, 30, 800)
	hull.mesh = box
	hull.material_override = Palette.toon(NAVY.lightened(0.08))
	hull.position = Vector3(180, -18.5, -120)
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(hull)
