class_name FunfairTrack
extends RefCounted
## Funfair Frenzy (design doc 8.4): a daytime seaside funfair. The road
## borrows the rides: it climbs a coaster's lift hill and flies off the end
## where the track breaks away, sweeps round the big wheel, is carried round
## a carousel, runs through a dark haunted house, splashes through a log
## flume and dodges bumper cars. About 1,900 m. A Series 2 kit.
##
## The lap, by point number: midway 0-2, coaster climb 2-4, the launch gap
## 4-5, run-out 5-7, round the big wheel 9-13, the carousel 14-18, haunted
## house 19.6-21.6, log flume 22-23, bumper cars 23.4-25, back to the midway.

const NAME := "Funfair Frenzy"
const SIGN_FONT := "res://assets/fonts/lilita_one.woff2"
const RED := Color(0.91, 0.2, 0.29)          # candy red
const SUN := Color(1.0, 0.78, 0.16)          # sunshine
const TEAL := Color(0.09, 0.65, 0.63)        # tent teal
const CREAM := Color(1.0, 0.95, 0.85)        # cream
const PINK := Color(1.0, 0.5, 0.71)          # bubblegum
const SKY := Color(0.345, 0.72, 0.94)        # seaside sky
const SIGN_INK := CREAM
const SIGN_EDGE := Color(0.5, 0.08, 0.16)
const SIGN_BOARD := RED
const SIGN_TRIM := SUN

const WHEEL_AT := Vector3(272, 0, -398)
const CAROUSEL_AT := Vector3(352, 0, -250)
const POINTS := [
	# The midway: the grid, between the stalls.
	Vector3(0, 0, 60), Vector3(0, 0, -40),
	# The coaster's lift hill, climbing to the lip.
	Vector3(0, 3, -120), Vector3(0, 11, -200), Vector3(0, 21, -272),
	# The track breaks away: karts fly to here, and run out downhill.
	Vector3(0, 12, -352), Vector3(0, 5, -412),
	Vector3(28, 2, -468), Vector3(95, 0.5, -500), Vector3(170, 0, -486),
	# Round the big wheel.
	Vector3(240, 0, -478), Vector3(312, 0, -470), Vector3(350, 0, -420), Vector3(350, 0, -350),
	# The carousel: an arc round its west side.
	Vector3(343, 0, -300), Vector3(331, 0, -271), Vector3(322, 0, -250), Vector3(331, 0, -229), Vector3(343, 0, -200),
	# The haunted house.
	Vector3(358, 0, -140), Vector3(342, 0, -60), Vector3(300, 0, 15),
	# The log flume, then the bumper cars.
	Vector3(245, 0, 75), Vector3(170, 0, 105), Vector3(100, 0, 150), Vector3(60, 0, 200),
	# Back onto the midway.
	Vector3(15, 0, 205), Vector3(0, 0, 160), Vector3(0, 0, 110),
]


static func _at(t: Track, i: float) -> float:
	return KitTools.at(t, POINTS, i)


static func configure(t: Track) -> void:
	t.points = POINTS
	t.surface_zones = []
	t.rail_zones = []
	t.ground_y = -40.0
	t.kerb_colors = [RED, CREAM]


static func plan(t: Track) -> void:
	var L := t.length
	# The coaster jump, and a boost strip on the run-out.
	t.gaps = [[_at(t, 4.0), _at(t, 5.0), {"lift": 9.0, "min_speed": 27.0}]]
	t.surface_zones = [{"from": _at(t, 5.25) / L, "to": _at(t, 5.6) / L, "surface": "boost"}]
	# The carousel carries karts the way they're going round it.
	var mid := t.road_frame(_at(t, 16.0))
	var r := mid.origin - CAROUSEL_AT
	var with_travel := signf(Vector3(-r.z, 0.0, r.x).dot(-mid.basis.z))
	t.fx_zones = [
		{"kind": "spin", "centre": CAROUSEL_AT, "radius": 44.0, "turn": 0.4 * with_travel},
		# The flume: water either side of a dry plank down the middle.
		{"kind": "drag", "from": _at(t, 22.05), "to": _at(t, 22.9), "drag": 1.5, "from_x": -9.0, "to_x": -2.4},
		{"kind": "drag", "from": _at(t, 22.05), "to": _at(t, 22.9), "drag": 1.5, "from_x": 2.4, "to_x": 9.0},
	]
	# Pop-ups in the haunted house, and bumper cars crossing the road.
	t.fx_hazards = []
	var i := 0
	for at in [20.0, 20.6, 21.2]:
		var left := i % 2 == 0
		t.fx_hazards.append({"at": _at(t, at), "from_x": -7.0 if left else 0.5, "to_x": -0.5 if left else 7.0, "period": 4.4, "on": 1.2, "phase": i * 1.5, "color": Color(0.5, 1.0, 0.45)})
		i += 1
	i = 0
	for at in [23.6, 24.2, 24.75]:
		t.fx_hazards.append({"at": _at(t, at), "sweep": 2.6, "model": "bumper_car", "phase": i * 0.7})
		i += 1


static func world(env: Environment, _sun: DirectionalLight3D) -> void:
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	if sky:
		sky.sky_top_color = SKY.darkened(0.12)
		sky.sky_horizon_color = Color(0.86, 0.95, 1.0)
	env.fog_light_color = Color(0.82, 0.92, 1.0)
	env.fog_density = 0.0008


static func road_material(_m: ShaderMaterial) -> void:
	pass


static func crate_frames(t: Track) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for at in [2.6, 13.4, 21.75]:
		out.append(t.transform_at(_at(t, at)))
	return out


static func build(t: Track) -> void:
	_ground(t)
	_coaster(t)
	_rides(t)
	_house(t)
	_flume(t)
	_midway(t)


## Sand to drive back from, and the sea beyond it.
static func _ground(t: Track) -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", "grass")
	body.set_meta("floor", true)
	t.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1100, 2, 1100)
	shape.shape = box
	shape.position = Vector3(175, -1.02, -150)
	body.add_child(shape)
	var sand := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1100, 1100)
	sand.mesh = plane
	sand.material_override = Palette.toon(Color(0.96, 0.86, 0.62))
	sand.position = Vector3(175, -0.02, -150)
	sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(sand)
	var sea := MeshInstance3D.new()
	var wide := PlaneMesh.new()
	wide.size = Vector2(5000, 5000)
	sea.mesh = wide
	sea.material_override = Palette.toon(Color(0.16, 0.6, 0.78), false, 0.0, Palette.Finish.PAINT)
	sea.position = Vector3(175, -0.6, -150)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(sea)


## The coaster: legs under the raised road, yellow rails along its edges, and
## the broken ends of the track at the gap.
static func _coaster(t: Track) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Track.ROAD_WIDTH * 0.5 + 1.3
	var d := _at(t, 1.6)
	var end := _at(t, 7.6)
	var index := 0
	while d < end:
		var f := t.road_frame(d)
		if f.origin.y > 1.2 and not t.in_gap(d):
			for side: float in [-1.0, 1.0]:
				# A rail along the edge.
				var g := t.road_frame(d + 6.0)
				if not t.in_gap(d + 6.0):
					var mid := (f.origin + g.origin) * 0.5 + f.basis.x * side * half + Vector3.UP * 0.5
					KitTools.box(st, Transform3D(Basis.looking_at((g.origin - f.origin).normalized(), Vector3.UP), mid), Vector3(0.35, 0.35, 6.2), SUN)
				# A leg down to the sand every other step.
				if index % 2 == 0:
					var top := f.origin + f.basis.x * side * (half - 0.4) - Vector3.UP * 0.4
					KitTools.box(st, Transform3D(Basis(), Vector3(top.x, top.y * 0.5, top.z)), Vector3(0.9, top.y, 0.9), RED if index % 4 == 0 else CREAM)
		d += 6.0
		index += 1
	# Where the track breaks: bent rail ends curling up past the lip.
	var lip := t.road_frame(_at(t, 4.0) - 0.5)
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var p := lip.origin + lip.basis.x * side * half - lip.basis.z * (1.5 + k * 2.2) + Vector3.UP * (0.6 + k * k * 0.5)
			KitTools.box(st, Transform3D(lip.basis.rotated(lip.basis.x, 0.25 * (k + 1)), p), Vector3(0.35, 0.35, 2.6), SUN)
	KitTools.commit(t, st, Palette.toon(Color.WHITE, true, 0.0, Palette.Finish.PAINT))


## The big wheel and the carousel, both turning.
static func _rides(t: Track) -> void:
	var face := Basis(Vector3.UP, 0.7)
	var stand: Array[Transform3D] = [Transform3D(face, WHEEL_AT)]
	KitTools.place(t, "big_wheel_stand", stand)
	var wheel := MeshInstance3D.new()
	wheel.mesh = KitTools.model("big_wheel")
	wheel.transform = Transform3D(face, WHEEL_AT + Vector3.UP * 33.0)
	wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(wheel)
	var turn := Spinner.new()
	turn.target = wheel
	turn.axis = Vector3.BACK
	turn.speed = 0.12
	t.add_child(turn)
	var carousel := MeshInstance3D.new()
	carousel.mesh = KitTools.model("carousel")
	carousel.transform = Transform3D(Basis().scaled(Vector3.ONE * 2.1), CAROUSEL_AT)
	carousel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(carousel)
	var round_it := Spinner.new()
	round_it.target = carousel
	round_it.axis = Vector3.UP
	round_it.speed = 0.4
	t.add_child(round_it)


## The haunted house: a dark tunnel with a sickly glow, and a tall front.
static func _house(t: Track) -> void:
	var dark := Color(0.2, 0.14, 0.3)
	KitTools.rooms(t, [[_at(t, 19.6), _at(t, 21.6), 8.0, "solid", Color(0.5, 1.0, 0.45)]], dark, dark)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Track.ROAD_WIDTH * 0.5 + 1.0
	for at in [19.6, 21.6]:
		var f := t.road_frame(_at(t, at))
		for side: float in [-1.0, 1.0]:
			KitTools.box(st, Transform3D(f.basis, f.origin + f.basis.x * side * (half + 2.5) + Vector3.UP * 7.0), Vector3(5.0, 14.0, 3.0), dark.lightened(0.12))
			KitTools.box(st, Transform3D(f.basis, f.origin + f.basis.x * side * (half + 2.5) + Vector3.UP * 15.5), Vector3(3.4, 3.0, 2.2), PINK.darkened(0.45))
		KitTools.box(st, Transform3D(f.basis, f.origin + Vector3.UP * 11.0), Vector3(half * 2.0 + 10.0, 6.0, 3.0), dark.lightened(0.05))
	KitTools.commit(t, st, Palette.toon(Color.WHITE, true))


## The flume: bright water over each side of the road, a dry plank between.
static func _flume(t: Track) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := _at(t, 22.05)
	var end := _at(t, 22.9)
	var index := 0
	while d < end:
		var a := t.road_frame(d)
		var b := t.road_frame(minf(d + 4.0, end))
		var blue := Color(0.3, 0.75, 0.95) if index % 2 == 0 else Color(0.42, 0.82, 0.98)
		for side: float in [-1.0, 1.0]:
			var a0 := a.origin + a.basis.x * side * 2.4 + Vector3.UP * 0.09
			var a1 := a.origin + a.basis.x * side * 8.0 + Vector3.UP * 0.09
			var b0 := b.origin + b.basis.x * side * 2.4 + Vector3.UP * 0.09
			var b1 := b.origin + b.basis.x * side * 8.0 + Vector3.UP * 0.09
			KitTools.quad(st, a0, b0, b1, a1, blue, side > 0.0)
		d += 4.0
		index += 1
	KitTools.commit(t, st, KitTools.glow(Color.WHITE), true)


## Stalls and balloons along the midway and by the bumper cars.
static func _midway(t: Track) -> void:
	var stalls: Array[Transform3D] = []
	var bunches: Array[Transform3D] = []
	var out := Track.ROAD_WIDTH * 0.5 + 6.5
	var spots := []
	var d := t.length - 70.0
	while d < t.length + 110.0:
		spots.append(d)
		d += 18.0
	d = _at(t, 23.3)
	while d < _at(t, 25.2):
		spots.append(d)
		d += 22.0
	var index := 0
	for at: float in spots:
		var f := t.road_frame(fposmod(at, t.length))
		for side: float in [-1.0, 1.0]:
			var p := f.origin + f.basis.x * side * out
			p.y = 0.0
			stalls.append(Transform3D(Basis.looking_at(f.basis.x * side, Vector3.UP).scaled(Vector3.ONE * 1.5), p))
			if index % 2 == 0:
				bunches.append(Transform3D(Basis().scaled(Vector3.ONE * 1.4), p + f.basis.z * 6.0 - f.basis.x * side * 1.5))
			index += 1
	KitTools.place(t, "stall", stalls, 260.0)
	KitTools.place(t, "balloons", bunches, 220.0)
