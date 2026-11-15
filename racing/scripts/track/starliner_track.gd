class_name StarlinerTrack
extends RefCounted
## Starliner Run (design doc 8.4): a lap of a giant starship, inside and out.
## Launch from the hangar, a long glass corridor, the engine room, up to the
## low-gravity hall, out along the hull with no walls, and down through the
## cargo deck. About 2,000 m. A Series 2 track: it brings its own world
## (Track.kit_of), with no ground, grass or mountains.
##
## The lap, by point number: hangar 0-1.5, glass corridor 1.5-4.6, engine
## room 4.6-10.6 (plasma jets), the climb 10.6-13.6, the low-gravity hall
## 13.6-16 (a floating launch gap), the airlock at 16 (alternating energy
## barriers), the hull walk 16-21.4 (open: no walls), the cargo deck 21.4-24.

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
const NAME := "Starliner Run"
const SIGN_FONT := "res://assets/fonts/black_ops_one.woff2"
const DECK := Color(0.9, 0.925, 0.96)        # panel white
const WALL := Color(0.36, 0.4, 0.48)         # deck grey
const NAVY := Color(0.078, 0.106, 0.2)       # hull navy
const CYAN := Color(0.21, 0.88, 1.0)         # reactor cyan
const AMBER := Color(1.0, 0.7, 0.12)         # warning amber
const VIOLET := Color(0.69, 0.29, 0.88)      # nebula violet
const SIGN_INK := DECK
const SIGN_EDGE := NAVY
const SIGN_BOARD := Color(0.14, 0.19, 0.34)
const SIGN_TRIM := CYAN
## The inside of the ship, by point number: [from, to, wall height, style,
## light colour]. "glass" walls are a low rail with pillars, so you see out;
## "rail" is a low lit rail under a high roof, open to the hall around it.
const ROOMS := [
	[0.0, 1.5, 11.0, "solid", AMBER],      # hangar
	[1.5, 4.6, 7.5, "glass", CYAN],        # glass corridor
	[4.6, 10.6, 17.0, "rail", CYAN],       # engine room: open to the reactors
	[10.6, 13.6, 7.0, "solid", VIOLET],    # the climb
	[13.6, 16.0, 12.0, "solid", VIOLET],   # low-gravity hall
	[21.4, 24.0, 13.0, "rail", AMBER],     # cargo deck: open to the stacks
]


static func configure(t: Track) -> void:
	t.points = POINTS
	t.surface_zones = []
	t.rail_zones = []
	t.ground_y = -60.0
	t.road_color = Color(0.62, 0.66, 0.74)
	t.kerb_colors = [CYAN.darkened(0.1), DECK]


static func plan(t: Track) -> void:
	# The low-gravity hall: everything floats, and a gap in the floor to
	# drift across.
	t.fx_zones = [{"kind": "gravity", "from": _at(t, 13.8), "to": _at(t, 15.9), "scale": 0.4}]
	t.gaps = [[_at(t, 14.25), _at(t, 14.8), {"lift": 5.5, "min_speed": 18.0, "slow": 0.62}]]
	# Engine room: plasma jets across half the road, one after another.
	t.fx_hazards = []
	var i := 0
	for at in [7.7, 8.5, 9.3, 10.1]:
		var left := i % 2 == 0
		t.fx_hazards.append({"at": _at(t, at), "from_x": -7.0 if left else 0.5, "to_x": -0.5 if left else 7.0, "period": 4.0, "on": 1.3, "phase": i * 1.1, "color": CYAN})
		i += 1
	# The airlock onto the hull: two energy barriers that take turns, so one
	# side is always open.
	var lock := _at(t, 16.15)
	t.fx_hazards.append({"at": lock, "from_x": -7.0, "to_x": -0.3, "period": 5.0, "on": 2.3, "phase": 0.0, "color": AMBER})
	t.fx_hazards.append({"at": lock, "from_x": 0.3, "to_x": 7.0, "period": 5.0, "on": 2.3, "phase": 2.5, "color": AMBER})


## The sky and light for this track (main.gd, when the world is made).
static func world(env: Environment, sun: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = NAVY.darkened(0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.95)
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = false
	sun.light_color = Color(0.95, 0.97, 1.0)
	sun.light_energy = 0.85


## Deck plating in place of asphalt, with no centre line.
static func road_material(m: ShaderMaterial) -> void:
	m.set_shader_parameter("detail", KitTools.plate_texture())
	m.set_shader_parameter("surf", KitTools.plate_texture())
	m.set_shader_parameter("relief", 0.0)
	m.set_shader_parameter("paint", false)
	m.set_shader_parameter("wear", 0.0)


static func crate_frames(t: Track) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for at in [3.0, 12.2, 19.5]:
		out.append(t.transform_at(_at(t, at)))
	return out


static func build(t: Track) -> void:
	_rooms(t)
	_props(t)
	_space(t)


## Lap distance of point number `i` (fractions fall between points).
static func _at(t: Track, i: float) -> float:
	var n := POINTS.size()
	var a := t.offset_of(POINTS[int(floorf(i)) % n])
	var b := t.offset_of(POINTS[int(ceilf(i)) % n])
	if b < a:
		b += t.length
	return fposmod(lerpf(a, b, i - floorf(i)), t.length) if i < float(n) else t.length - 0.01


## Walls, roof and lights for every room, then the airlock frame.
static func _rooms(t: Track) -> void:
	var half := Track.ROAD_WIDTH * 0.5 + 1.0
	var list := []
	for room: Array in ROOMS:
		list.append([_at(t, room[0]), _at(t, room[1]), room[2], room[3], room[4]])
	KitTools.rooms(t, list, WALL, DECK.darkened(0.15))
	# The airlock frame, where the ship ends and the hull walk begins.
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	var f := t.road_frame(_at(t, 16.0))
	for side: float in [-1.0, 1.0]:
		KitTools.box(frame, Transform3D(f.basis, f.origin + f.basis.x * side * (half + 0.6) + Vector3.UP * 6.0), Vector3(1.6, 12.0, 2.4), DECK)
	KitTools.box(frame, Transform3D(f.basis, f.origin + Vector3.UP * 12.4), Vector3(half * 2.0 + 2.8, 1.6, 2.4), AMBER)
	KitTools.commit(t, frame, Palette.toon(Color.WHITE, true))


## Reactors towering over the engine room, cargo stacked beside the cargo
## deck, and dishes along the hull.
static func _props(t: Track) -> void:
	var out := Track.ROAD_WIDTH * 0.5 + 5.5
	var reactors: Array[Transform3D] = []
	var at := 5.2
	var i := 0
	while at < 10.4:
		var f := t.road_frame(_at(t, at))
		var side := 1.0 if i % 2 == 0 else -1.0
		reactors.append(Transform3D(Basis().scaled(Vector3.ONE * 1.25), f.origin + f.basis.x * side * out - Vector3.UP * 1.0))
		at += 0.62
		i += 1
	KitTools.place(t, "reactor", reactors, 420.0)
	var pods: Array[Transform3D] = []
	at = 21.7
	i = 0
	while at < 23.6:
		var f := t.road_frame(_at(t, at))
		var side := 1.0 if i % 2 == 0 else -1.0
		for level in 3 + i % 2:
			pods.append(Transform3D(f.basis.rotated(Vector3.UP, 0.12 * (level % 2)), f.origin + f.basis.x * side * (out - 1.8) + Vector3.UP * (2.45 * level)))
		at += 0.36
		i += 1
	KitTools.place(t, "cargo_pod", pods, 320.0)
	var dishes: Array[Transform3D] = []
	at = 16.8
	i = 0
	while at < 21.2:
		var f := t.road_frame(_at(t, at))
		var side := 1.0 if i % 2 == 0 else -1.0
		dishes.append(Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * 1.5), f.origin + f.basis.x * side * (out + 6.0) - Vector3.UP * 3.0))
		at += 0.75
		i += 1
	KitTools.place(t, "dish", dishes, 380.0)


## What's outside: stars, a planet below, and the ship's own bulk under the
## decks. Three draw calls.
static func _space(t: Track) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stars := SurfaceTool.new()
	stars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(180, 0, -120)
	for i in 900:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 1)).normalized()
		var p := centre + dir * 1500.0
		var size := rng.randf_range(2.5, 7.0)
		var right := dir.cross(Vector3.UP).normalized() * size
		var up := right.cross(dir).normalized() * size
		var c := Color.WHITE.lerp(CYAN if i % 5 == 0 else VIOLET, rng.randf() * 0.5)
		KitTools.quad(stars, p - right - up, p + right - up, p + right + up, p - right + up, c)
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
	hull.position = Vector3(180, -17.6, -120)
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(hull)
