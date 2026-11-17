class_name StarlinerTrack
extends RefCounted
## Starliner Run (design doc 8.6): a lap across two little worlds and a
## flying saucer, on Mario Kart's rules for jumps (no skill needed to make
## one; a trick off the lip for a boost; you only fall if hit in the air).
##
## The moon: from the base, into a diamond of five craters. Each crater's
## far rim launches you into the next; out of the first you choose by
## steering: straight on to the middle crater, or left or right into a side
## crater. The last crater launches you across space to the red planet.
## The red planet: a winding road over rust dust, with dust devils. Then a
## jump to the saucer: round its rim past vents that warn, then blow karts
## off into space; the last vent always blows, and carries you back to the
## moon.
##
## Roads are raised slabs with dust shoulders that slow you, and guardrails
## beyond. Gravity points down everywhere (like every other track), so each
## world is a squashed ball and the road keeps to its gentle top.

const NAME := "Starliner Run"
const SIGN_FONT := "res://assets/fonts/black_ops_one.woff2"
const NAVY := Color(0.078, 0.106, 0.2)       # space
const CYAN := Color(0.21, 0.88, 1.0)         # saucer lights
const AMBER := Color(1.0, 0.7, 0.12)         # warnings
const VIOLET := Color(0.69, 0.29, 0.88)      # nebula
const MOON_C := Color(0.74, 0.74, 0.78)      # moon dust
const MOON_DARK := Color(0.46, 0.46, 0.53)   # crater floors, maria
const RUST := Color(0.7, 0.3, 0.16)          # the red planet
const RUST_LIGHT := Color(0.88, 0.52, 0.3)
const RUST_DARK := Color(0.44, 0.17, 0.1)
const HULL := Color(0.8, 0.84, 0.9)          # the saucer
const ROAD := Color(0.6, 0.62, 0.68)         # the raised road everywhere
const SIGN_INK := Color(0.95, 0.96, 1.0)
const SIGN_EDGE := NAVY
const SIGN_BOARD := Color(0.14, 0.19, 0.34)
const SIGN_TRIM := CYAN

## The worlds: squashed balls, by the centre of their top (x, z), the height
## of the top, and their radii across (a) and up (b).
const MOON := {"x": 0.0, "z": 0.0, "top": 200.0, "a": 320.0, "b": 160.0}
const MARS := {"x": 0.0, "z": -690.0, "top": 150.0, "a": 300.0, "b": 150.0}
const SAUCER := Vector3(300, 140, -360)   # centre of its deck
const SAUCER_R := 130.0
const RING := 105.0                       # the road's radius round the deck
const LAND_AT := 160.0                    # degrees round the ring: the jump from Mars lands here
const VENT_AT := -160.0                   # and the last vent (the angle falls as you drive)
const RIDE := 0.5                         # the road's height above the ground
const SHOULDER := 6.5                     # dust either side, before the guardrail
const CR := 30.0                          # crater radius (to the rim crest)
const CRATERS := {"T": Vector2(-30, 50), "M": Vector2(-30, -40), "B": Vector2(-30, -130),
	"L": Vector2(-100, -40), "R": Vector2(40, -40)}
## The roads, as points across the ground (x, z), sampled into the lap.
const START := [Vector2(20, 125), Vector2(-12, 118), Vector2(-28, 104), Vector2(-30, 90), Vector2(-30, 80)]
const MOON_IN := [Vector2(137, -131), Vector2(130, -50), Vector2(122, 30), Vector2(108, 96), Vector2(76, 124), Vector2(46, 126)]
const MARS_ROAD := [Vector2(-30, -545), Vector2(-52, -615), Vector2(-38, -695), Vector2(15, -745),
	Vector2(85, -748), Vector2(130, -705), Vector2(120, -660), Vector2(130, -600)]
const POINTS := []   # built in configure (_points)

static var _marks := {}   # name -> a point on the lap


static func configure(t: Track) -> void:
	t.points = _points()
	t.surface_zones = []
	t.rail_zones = []
	t.ground_y = -260.0
	t.view_far = 2600.0
	t.road_color = ROAD
	t.kerb_colors = [ROAD.darkened(0.12), ROAD.lightened(0.12)]


## The lap as points: the moon's craters, the jump to Mars, its road, the
## jump to the saucer, round its rim, the jump home and the moon's road to
## the start. Through jumps the points follow the flight, so lap distance
## keeps counting in the air.
static func _points() -> Array:
	_marks = {}
	var pts: Array[Vector3] = []
	_marks["start"] = _ground(START[0], "moon")
	pts.append_array(_road(START, "moon", 3.0))
	var t: Vector2 = CRATERS["T"]
	var m: Vector2 = CRATERS["M"]
	var b: Vector2 = CRATERS["B"]
	_line(pts, Vector2(t.x, t.y + CR - 2.0), Vector2(t.x, t.y - CR), "moon", 2.0)
	_marks["t_lip"] = pts[pts.size() - 1]
	_marks["m_land"] = _ground(Vector2(m.x, m.y + CR * 0.55), "moon")
	_flight(pts, _marks["t_lip"], _marks["m_land"], 11.0, 10.0)
	_line(pts, Vector2(m.x, m.y + CR * 0.55), Vector2(m.x, m.y - CR), "moon", 2.0)
	_marks["m_lip"] = pts[pts.size() - 1]
	_marks["b_land"] = _ground(Vector2(b.x, b.y + CR * 0.55), "moon")
	_flight(pts, _marks["m_lip"], _marks["b_land"], 11.0, 10.0)
	_line(pts, Vector2(b.x, b.y + CR * 0.55), Vector2(b.x, b.y - CR), "moon", 2.0)
	_marks["b_lip"] = pts[pts.size() - 1]
	_marks["mars_land"] = _ground(MARS_ROAD[0], "mars")
	_flight(pts, _marks["b_lip"], _marks["mars_land"], 45.0, 25.0)
	pts.append_array(_road(MARS_ROAD, "mars", 5.0))
	_marks["mars_lip"] = pts[pts.size() - 1]
	_marks["saucer_land"] = _ring_point(LAND_AT)
	_flight(pts, _marks["mars_lip"], _marks["saucer_land"], 30.0, 25.0)
	var a := LAND_AT
	while a > VENT_AT + 0.01:
		pts.append(_ring_point(a))
		a -= 2.5
	pts.append(_ring_point(VENT_AT))
	_marks["vent"] = pts[pts.size() - 1]
	_marks["moon_land"] = _ground(MOON_IN[0], "moon")
	_flight(pts, _marks["vent"], _marks["moon_land"], 40.0, 25.0)
	var home := _road(MOON_IN, "moon", 5.0)
	pts.append_array(home)
	return pts


## The ground's height at (x, z) on a world.
static func ground(p: Vector2, world: String) -> float:
	if world == "saucer":
		return SAUCER.y
	if world == "mars":
		return body_h(MARS, p)
	var h := body_h(MOON, p)
	for c: Vector2 in CRATERS.values():
		h += crater_off(p.distance_to(c))
	return h


static func body_h(b: Dictionary, p: Vector2) -> float:
	var d := Vector2(p.x - float(b["x"]), p.y - float(b["z"])).length()
	return float(b["top"]) - float(b["b"]) * (1.0 - sqrt(maxf(0.0, 1.0 - pow(d / float(b["a"]), 2.0))))


## A crater's shape by distance from its centre: a bowl 5.5 m deep, a rim
## 2.5 m high (so a slow kart can still climb out), an apron back down to
## the plain.
static func crater_off(r: float) -> float:
	if r < CR:
		return -5.5 + 8.0 * pow(r / CR, 2.0)
	if r < CR + 16.0:
		var u := (r - CR) / 16.0
		return 2.5 * (1.0 - u) * (1.0 - u)
	return 0.0


static func _ground(p: Vector2, world: String) -> Vector3:
	return Vector3(p.x, ground(p, world) + RIDE, p.y)


static func _ring_point(deg: float) -> Vector3:
	var r := deg_to_rad(deg)
	return Vector3(SAUCER.x + cos(r) * RING, SAUCER.y + RIDE, SAUCER.z + sin(r) * RING)


## A smooth road through `path`, every `step` metres, on the ground.
static func _road(path: Array, world: String, step: float) -> Array[Vector3]:
	var c := Curve2D.new()
	var n := path.size()
	for i in n:
		var prev: Vector2 = path[maxi(i - 1, 0)]
		var next: Vector2 = path[mini(i + 1, n - 1)]
		var h := (next - prev) / 6.0
		c.add_point(path[i], -h, h)
	c.bake_interval = 1.0
	var out: Array[Vector3] = []
	var length := c.get_baked_length()
	var d := 0.0
	while d < length - step * 0.5:
		out.append(_ground(c.sample_baked(d), world))
		d += step
	out.append(_ground(path[n - 1], world))
	return out


static func _line(pts: Array[Vector3], from: Vector2, to: Vector2, world: String, step: float) -> void:
	var n := maxi(1, int(from.distance_to(to) / step))
	for i in n + 1:
		pts.append(_ground(from.lerp(to, float(i) / n), world))


## Points along a jump's flight (not the ends), so the lap follows it.
static func _flight(pts: Array[Vector3], from: Vector3, to: Vector3, lift: float, step: float) -> void:
	var n := maxi(2, int(Vector2(to.x - from.x, to.z - from.z).length() / step))
	for i in range(1, n):
		var u := float(i) / n
		var p := from.lerp(to, u)
		p.y += 4.0 * lift * u * (1.0 - u)
		pts.append(p)


## Lap distance of a named point.
static func _at(t: Track, name: String) -> float:
	return t.offset_of(_marks[name])


## Which world a place is on.
static func world_of(p: Vector3) -> String:
	if Vector2(p.x - SAUCER.x, p.z - SAUCER.z).length() < SAUCER_R + 20.0:
		return "saucer"
	if Vector2(p.x - float(MARS["x"]), p.z - float(MARS["z"])).length() < float(MARS["a"]) + 20.0:
		return "mars"
	return "moon"


static func plan(t: Track) -> void:
	var L := t.length
	# The craters: drive anywhere in them, and out over a lip on the rim.
	t.free_zones = []
	for c: Vector2 in CRATERS.values():
		t.free_zones.append([Vector3(c.x, ground(c, "moon"), c.y), CR + 16.0])   # out to the apron
	var T: Vector2 = CRATERS["T"]
	var M: Vector2 = CRATERS["M"]
	var B: Vector2 = CRATERS["B"]
	var Lc: Vector2 = CRATERS["L"]
	var Rc: Vector2 = CRATERS["R"]
	t.pads = [
		_pad(T, M, {"lift": 11.0, "half": 8.5}), _pad(T, Lc, {"lift": 15.0}), _pad(T, Rc, {"lift": 15.0}),
		_pad(M, B, {"lift": 11.0, "half": 8.5}), _pad(Lc, B, {"lift": 15.0}), _pad(Rc, B, {"lift": 15.0}),
	]
	# The last crater fires you across space to the red planet.
	var mars := _pad(B, B + Vector2(0, -100), {"lift": 45.0, "fly_speed": 72.0, "glide": true, "half": 8.5})
	mars["to"] = t.road_frame(_at(t, "mars_land"))
	t.pads.append(mars)
	t.gaps = [
		[_at(t, "t_lip"), _at(t, "m_land"), {"pads": true}],
		[_at(t, "m_lip"), _at(t, "b_land"), {"pads": true}],
		[_at(t, "b_lip"), _at(t, "mars_land"), {"pads": true}],
		[_at(t, "mars_lip"), _at(t, "saucer_land"), {"lift": 30.0, "fly_speed": 62.0, "glide": true}],
		[_at(t, "vent"), _at(t, "moon_land"), {"lift": 40.0, "fly_speed": 62.0, "glide": true}],
	]
	# Boosts: down the base straight, and two on the red planet.
	var mars0 := _at(t, "mars_land")
	t.surface_zones = [
		{"from": (mars0 + 150.0) / L, "to": (mars0 + 162.0) / L, "surface": "boost"},
		{"from": (mars0 + 330.0) / L, "to": (mars0 + 342.0) / L, "surface": "boost"},
	]
	# The saucer's vents: each covers half the road, sputters as a warning,
	# then blows whoever is on it off into space. They take turns.
	t.fx_hazards = []
	var ring0 := _at(t, "saucer_land")
	var ring1 := _at(t, "vent")
	var span := fposmod(ring1 - ring0, L)
	var i := 0
	for u: float in [0.14, 0.3, 0.46, 0.62, 0.78]:
		var left := i % 2 == 0
		t.fx_hazards.append({"at": fposmod(ring0 + span * u, L), "from_x": -7.0 if left else 0.4, "to_x": -0.4 if left else 7.0,
			"period": 5.2, "on": 1.6, "warn": 1.5, "phase": i * 1.3, "blow": true, "height": 16.0, "depth": 3.0,
			"color": Color(0.75, 1.0, 0.85)})
		i += 1
	# Dust devils crossing the red planet's road.
	for u: float in [0.3, 0.62]:
		t.fx_hazards.append({"at": mars0 + _mars_len(t) * u, "sweep": 3.2 + u, "model": "dust_devil", "phase": u})


static func _mars_len(t: Track) -> float:
	return fposmod(_at(t, "mars_lip") - _at(t, "mars_land"), t.length)


## A lip on crater `from`'s rim towards `to` (a crater: you land on its
## near side, facing on).
static func _pad(from: Vector2, to: Vector2, opt: Dictionary) -> Dictionary:
	var dir2 := (to - from).normalized()
	var dir := Vector3(dir2.x, 0.0, dir2.y)
	var lip := from + dir2 * CR
	var land := to - dir2 * CR * 0.55
	var p := opt.duplicate()
	p["centre"] = Vector3(from.x, ground(from, "moon"), from.y)
	p["dir"] = dir
	p["r"] = CR
	p["half"] = opt.get("half", 6.5)
	p["rim_y"] = ground(lip, "moon")
	p["to"] = Transform3D(Basis.looking_at(dir, Vector3.UP), _ground(land, "moon"))
	return p


## Space, and a warm sun low over the worlds.
static func world(env: Environment, sun: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.74, 0.92)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = false
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.05


## A plain raised slab: no lines, no texture.
static func road_material(m: ShaderMaterial) -> void:
	m.set_shader_parameter("relief", 0.0)
	m.set_shader_parameter("paint", false)
	m.set_shader_parameter("wear", 0.0)


static func crate_frames(t: Track) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.append(t.transform_at(_at(t, "start") + 40.0))
	out.append(t.transform_at(_at(t, "mars_land") + 240.0))
	out.append(t.transform_at(fposmod(_at(t, "saucer_land") + 60.0, t.length)))
	# A reward for taking a side crater: boxes on its floor.
	for k: String in ["L", "R"]:
		var c: Vector2 = CRATERS[k]
		var to: Vector2 = CRATERS["B"]
		var dir := (to - c).normalized()
		out.append(Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP), _ground(c, "moon")))
	return out


static func build(t: Track) -> void:
	SpaceWorlds.build(t)
