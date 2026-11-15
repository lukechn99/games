class_name WindyTrack
extends RefCounted
## Windy City Circuit (design doc 8.4): Chicago streets by day, dark
## underground. A lakefront drive, a ramp down through a parking garage to
## the lower street (the city really is stacked like this), back up over a
## river bridge in the wind, under the elevated train, between towers where
## gusts push you about, down to riverside hairpins, and round a fountain.
## About 2,200 m. A Series 2 kit. Buildings and signs are generic: no real
## logos, artworks or named landmarks.
##
## The lap, by point number: lakefront 0-2.6, parking garage 2.6-5.2 (timed
## barrier arms), lower street 5.2-9.4, river bridge 10-11 (wind), under the
## train 12-14.5, tower canyon 14.5-17.5 (wind), riverwalk 18-23, fountain
## 23-25, and back.

const NAME := "Windy City Circuit"
const SIGN_FONT := "res://assets/fonts/black_ops_one.woff2"
const SKY := Color(0.435, 0.765, 0.95)       # city sky
const STONE := Color(0.86, 0.84, 0.78)       # limestone
const STEEL := Color(0.3, 0.42, 0.54)        # steel blue
const LAKE := Color(0.18, 0.65, 0.72)        # lake teal
const ORANGE := Color(1.0, 0.6, 0.24)        # tunnel orange
const DARK := Color(0.09, 0.11, 0.15)        # underground
const GREEN := Color(0.62, 0.95, 0.6)        # the lower level's green lamps
const SIGN_INK := Color(1, 1, 1)
const SIGN_EDGE := Color(0.08, 0.12, 0.2)
const SIGN_BOARD := STEEL
const SIGN_TRIM := ORANGE

const FOUNTAIN_AT := Vector3(-74, 10, -62)
const POINTS := [
	# Lakefront drive: the grid, the lake on the right.
	Vector3(0, 10, 60), Vector3(0, 10, -60), Vector3(0, 10, -160),
	# The ramp down, through the parking garage.
	Vector3(18, 8, -228), Vector3(70, 3.5, -262), Vector3(140, 1, -272),
	# The lower street, under the city.
	Vector3(230, 1, -272), Vector3(318, 1, -268), Vector3(372, 2.5, -300),
	# Up into daylight and over the river.
	Vector3(386, 6.5, -362), Vector3(386, 10, -432), Vector3(386, 11, -520),
	# Under the elevated train.
	Vector3(360, 10, -582), Vector3(290, 10, -604), Vector3(190, 10, -600),
	# The tower canyon.
	Vector3(105, 10, -584), Vector3(22, 10, -560), Vector3(-48, 10, -520),
	# The riverwalk: hairpins down by the water.
	Vector3(-82, 10, -445), Vector3(-132, 6, -380), Vector3(-80, 4, -318), Vector3(-132, 4, -250), Vector3(-86, 6.5, -172),
	# Round the fountain and back to the lakefront.
	Vector3(-112, 9, -102), Vector3(-114, 10, -30), Vector3(-88, 10, 40),
	Vector3(-66, 10, 108), Vector3(-28, 10, 150), Vector3(0, 10, 122),
]


static func _at(t: Track, i: float) -> float:
	return KitTools.at(t, POINTS, i)


static func configure(t: Track) -> void:
	t.points = POINTS
	t.surface_zones = []
	t.rail_zones = []
	t.ground_y = -60.0
	t.kerb_colors = [Color(0.74, 0.73, 0.7), STONE]


static func plan(t: Track) -> void:
	var L := t.length
	# The river bridge is a drawbridge, and it's up: jump the gap between
	# its leaves.
	t.gaps = [[_at(t, 10.32), _at(t, 10.72), {"lift": 6.0, "min_speed": 25.0}]]
	t.surface_zones = [{"from": _at(t, 6.3) / L, "to": _at(t, 6.6) / L, "surface": "boost"},
		{"from": _at(t, 16.2) / L, "to": _at(t, 16.5) / L, "surface": "boost"}]
	# Wind over the bridge and between the towers.
	t.fx_zones = [
		{"kind": "wind", "from": _at(t, 10.0), "to": _at(t, 11.2), "push": 22.0, "period": 5.0},
		{"kind": "wind", "from": _at(t, 14.6), "to": _at(t, 17.4), "push": 26.0, "period": 4.2},
	]
	# The garage's barrier arms take turns, so one lane is always open.
	t.fx_hazards = []
	# Steam bursting from grates in the lower street, one side then the other.
	t.fx_hazards.append({"at": _at(t, 6.95), "from_x": -7.0, "to_x": -0.5, "period": 4.6, "on": 1.2, "phase": 0.0, "color": Color(0.9, 0.95, 1.0)})
	t.fx_hazards.append({"at": _at(t, 8.1), "from_x": 0.5, "to_x": 7.0, "period": 4.6, "on": 1.2, "phase": 2.3, "color": Color(0.9, 0.95, 1.0)})
	for at in [3.3, 4.4]:
		var d := _at(t, at)
		t.fx_hazards.append({"at": d, "from_x": -7.0, "to_x": -0.3, "period": 5.0, "on": 2.2, "phase": at, "color": ORANGE})
		t.fx_hazards.append({"at": d, "from_x": 0.3, "to_x": 7.0, "period": 5.0, "on": 2.2, "phase": at + 2.5, "color": ORANGE})


static func world(env: Environment, _sun: DirectionalLight3D) -> void:
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	if sky:
		sky.sky_top_color = SKY.darkened(0.18)
		sky.sky_horizon_color = Color(0.88, 0.94, 1.0)
	env.fog_light_color = Color(0.84, 0.91, 0.98)
	env.fog_density = 0.0009


static func road_material(_m: ShaderMaterial) -> void:
	pass


static func crate_frames(t: Track) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for at in [1.5, 6.6, 13.2, 20.5]:
		out.append(t.transform_at(_at(t, at)))
	return out


static func build(t: Track) -> void:
	var concrete := Color(0.2, 0.21, 0.25)
	var kerb := Color(0.7, 0.7, 0.68)
	KitTools.rooms(t, [
		[0.0, _at(t, 2.6), 5.0, "open", STONE, kerb],
		[_at(t, 2.6), _at(t, 5.2), 6.0, "rail", ORANGE],      # the garage
		[_at(t, 5.2), _at(t, 9.4), 6.5, "solid", GREEN],      # the lower street
		[_at(t, 9.4), t.length - 0.02, 5.0, "open", STONE, kerb],
	], concrete, concrete)
	_garage(t)
	_city(t)
	_bridge(t)
	_train(t)
	_fountain(t)
	_dress(t)
	t._build_boost_ramp(_at(t, 1.3), 1.0)
	t._build_boost_ramp(_at(t, 13.3), -1.0)
	# The lake and the river: one sheet of water under everything.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	water.mesh = plane
	water.material_override = Palette.toon(LAKE, false, 0.0, Palette.Finish.PAINT)
	water.position = Vector3(130, -1.5, -230)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(water)


## The parking garage: a floor and a low ceiling out past the rails, rows of
## columns, painted bays and parked cars.
static func _garage(t: Track) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cars: Array[Transform3D] = []
	var trucks: Array[Transform3D] = []
	var half := Track.ROAD_WIDTH * 0.5 + 1.0
	var floor_c := Color(0.26, 0.27, 0.31)
	var d := _at(t, 2.6)
	var end := _at(t, 5.2)
	var index := 0
	while d < end:
		var a := t.road_frame(d)
		var b := t.road_frame(minf(d + 5.0, end))
		for side: float in [-1.0, 1.0]:
			var a0 := a.origin + a.basis.x * side * half
			var a1 := a.origin + a.basis.x * side * (half + 15.0)
			var b0 := b.origin + b.basis.x * side * half
			var b1 := b.origin + b.basis.x * side * (half + 15.0)
			KitTools.quad(st, a0, b0, b1, a1, floor_c, side > 0.0)
			KitTools.quad(st, a0 + Vector3.UP * 6.0, b0 + Vector3.UP * 6.0, b1 + Vector3.UP * 6.0, a1 + Vector3.UP * 6.0, floor_c.darkened(0.3), side < 0.0)
			KitTools.quad(st, a1, b1, b1 + Vector3.UP * 6.0, a1 + Vector3.UP * 6.0, floor_c.darkened(0.15), side < 0.0)
			# A bay line, and in most bays a car.
			var mid := a.origin.lerp(b.origin, 0.5)
			KitTools.quad(lines, a0 + a.basis.x * side * 1.0 + Vector3.UP * 0.03, a0 + a.basis.x * side * 6.5 + Vector3.UP * 0.03,
				a0 + a.basis.x * side * 6.5 - a.basis.z * 0.2 + Vector3.UP * 0.03, a0 + a.basis.x * side * 1.0 - a.basis.z * 0.2 + Vector3.UP * 0.03, Color(1.0, 0.85, 0.3), side > 0.0)
			if index % 5 == 2:
				trucks.append(Transform3D(a.basis.rotated(Vector3.UP, PI * 0.5 * side), mid + a.basis.x * side * (half + 6.0)))
			elif (index + int(side)) % 3 != 0:
				cars.append(Transform3D(a.basis.rotated(Vector3.UP, PI * 0.5 * side), mid + a.basis.x * side * (half + 4.0)))
			if index % 3 == 0:
				KitTools.box(st, Transform3D(a.basis, a.origin + a.basis.x * side * (half + 8.5) + Vector3.UP * 3.0), Vector3(0.9, 6.0, 0.9), Color(0.5, 0.5, 0.52))
		d += 5.0
		index += 1
	KitTools.commit(t, st, Palette.toon(Color.WHITE, true), true)
	KitTools.commit(t, lines, KitTools.glow(Color.WHITE), true)
	KitTools.place(t, "city_car", cars, 160.0)
	KitTools.place(t, "box_truck", trucks, 160.0)


## Pavements, street lamps and tower blocks along the streets above ground.
static func _city(t: Track) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 312
	var road: Array[Vector3] = []
	var d := 0.0
	while d < t.length:
		road.append(t.transform_at(d).origin)
		d += 12.0
	var pave := SurfaceTool.new()
	pave.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blocks := []
	var lamps: Array[Transform3D] = []
	var trees: Array[Transform3D] = []
	var signals: Array[Transform3D] = []
	var tanks: Array[Transform3D] = []
	var shop := [Color(0.85, 0.25, 0.25), LAKE, ORANGE, Color(0.2, 0.3, 0.55), Color(0.3, 0.62, 0.36)]
	var half := Track.ROAD_WIDTH * 0.5 + 1.0
	var under := [_at(t, 2.6), _at(t, 9.4)]
	var tints := [STONE, STONE.darkened(0.12), STEEL.lightened(0.35), STEEL, Color(0.72, 0.52, 0.42)]
	d = 0.0
	var index := 0
	while d < t.length:
		var a := t.road_frame(d)
		var b := t.road_frame(minf(d + 10.0, t.length))
		var above: bool = d < under[0] or d > under[1]
		for side: float in [-1.0, 1.0]:
			var out_a := a.origin + a.basis.x * side * (half + 11.0)
			# The lake is beside the lakefront drive: nothing built there.
			var lakeside: bool = out_a.x > 6.0 and out_a.z > -205.0
			if above and not lakeside:
				var out_b := b.origin + b.basis.x * side * (half + 11.0)
				KitTools.quad(pave, a.origin + a.basis.x * side * half + Vector3.UP * 0.12, b.origin + b.basis.x * side * half + Vector3.UP * 0.12,
					out_b + Vector3.UP * 0.12, out_a + Vector3.UP * 0.12, STONE.darkened(0.08) if index % 2 == 0 else STONE.darkened(0.14), side > 0.0)
				if index % 3 == 0:
					lamps.append(Transform3D(Basis.looking_at(a.basis.z * side, Vector3.UP).rotated(Vector3.UP, PI * 0.5), a.origin + a.basis.x * side * (half + 1.6)))
				elif index % 3 == 2 and not t.in_gap(d):
					trees.append(KitDress.varied(Transform3D(Basis(), a.origin + a.basis.x * side * (half + 6.0)), 1.0, 0.18))
				if index % 16 == 5 and side > 0.0 and not t.in_gap(d):
					var arm := -a.basis.x
					signals.append(Transform3D(Basis(arm, Vector3.UP, arm.cross(Vector3.UP)), a.origin + a.basis.x * (half + 1.2)))
			if index % 3 == 1 and not lakeside:
				# A block set back from the road, if it's clear of every other road.
				var w := rng.randf_range(20.0, 34.0)
				var deep := rng.randf_range(20.0, 30.0)
				var tall := rng.randf_range(36.0, 150.0) if above else rng.randf_range(30.0, 90.0)
				var centre := a.origin + a.basis.x * side * (half + 13.0 + deep * 0.5)
				var clear := true
				for p in road:
					if Vector2(p.x - centre.x, p.z - centre.z).length() < maxf(w, deep) * 0.75 + 10.0:
						clear = false
						break
				if clear:
					var base := Vector3(centre.x, -1.5, centre.z)
					var turn := Basis(Vector3.UP, atan2(a.basis.x.x, a.basis.x.z))
					blocks.append([base, Vector3(w, tall + a.origin.y + 1.5, deep), tints[rng.randi() % tints.size()], turn])
					if above:
						# The block's plaza, a shop awning facing the road, and
						# on the lower ones a water tank on the roof.
						var along := -a.basis.z
						var c0 := Vector3(centre.x, a.origin.y + 0.1, centre.z)
						var px := a.basis.x * (deep * 0.5 + 5.0)
						var pz := along * (w * 0.5 + 5.0)
						KitTools.quad(pave, c0 - px - pz, c0 - px + pz, c0 + px + pz, c0 + px - pz, STONE.darkened(0.2))
						KitTools.quad(pave, c0 - px - pz, c0 + px - pz, c0 + px + pz, c0 - px + pz, STONE.darkened(0.2))
						var front := centre - a.basis.x * side * (deep * 0.5 + 1.4)
						KitTools.box(pave, Transform3D(a.basis, Vector3(front.x, a.origin.y + 4.2, front.z)), Vector3(2.8, 0.5, w * 0.7), shop[index % shop.size()])
						if tall < 80.0:
							tanks.append(Transform3D(Basis(), Vector3(centre.x, tall + a.origin.y, centre.z)))
		d += 10.0
		index += 1
	KitTools.commit(t, pave, Palette.toon(Color.WHITE, true))
	KitTools.place(t, "street_lamp", lamps, 240.0)
	KitDress.scatter(t, "tree_planter", trees, 230.0)
	KitDress.scatter(t, "traffic_light", signals, 260.0)
	KitTools.place(t, "water_tank", tanks)
	KitTools.buildings(t, blocks)


## The river bridge: steel frames overhead and a stone tower at each end.
static func _bridge(t: Track) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Track.ROAD_WIDTH * 0.5 + 1.6
	var d := _at(t, 10.05)
	var end := _at(t, 11.0)
	while d < end:
		var f := t.road_frame(d)
		if not t.in_gap(d) and not t.in_gap(d + 7.0) and not t.in_gap(d - 7.0):
			for side: float in [-1.0, 1.0]:
				KitTools.box(st, Transform3D(f.basis, f.origin + f.basis.x * side * half + Vector3.UP * 4.5), Vector3(0.8, 9.0, 0.8), STEEL)
			KitTools.box(st, Transform3D(f.basis, f.origin + Vector3.UP * 9.2), Vector3(half * 2.0 + 0.8, 0.8, 0.8), STEEL)
		d += 12.0
	# The two leaves of the drawbridge, raised: girders tilting up from each
	# side of the gap, tipped with warning lights.
	var lights := SurfaceTool.new()
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gap: Array = t.gaps[0]
	for end_of: Array in [[float(gap[0]), 1.0], [float(gap[1]), -1.0]]:
		var f := t.road_frame(end_of[0])
		var into: Vector3 = -f.basis.z * float(end_of[1])      # towards the gap
		var tilt := f.basis.rotated(f.basis.x, 0.5 * float(end_of[1]))
		for side: float in [-1.0, 1.0]:
			var root := f.origin + f.basis.x * side * (half + 0.2)
			var mid := root + into * 7.0 + Vector3.UP * 4.2
			KitTools.box(st, Transform3D(tilt, mid), Vector3(1.0, 1.6, 18.0), STEEL.lightened(0.15))
			KitTools.box(st, Transform3D(tilt, mid + Vector3.UP * 1.3), Vector3(0.5, 0.5, 18.0), ORANGE)
			KitTools.box(lights, Transform3D(tilt, root + into * 14.6 + Vector3.UP * 9.0), Vector3(0.9, 0.9, 0.9), Color(1.0, 0.25, 0.2))
		# Under the leaf: a pier in the river.
		KitTools.box(st, Transform3D(f.basis, f.origin - into * 3.0 - Vector3.UP * 6.5), Vector3(half * 2.0 + 4.0, 12.0, 7.0), STONE.darkened(0.1))
	KitTools.commit(t, lights, KitTools.glow(Color.WHITE))
	for at in [10.0, 11.05]:
		var f := t.road_frame(_at(t, at))
		for side: float in [-1.0, 1.0]:
			KitTools.box(st, Transform3D(f.basis, f.origin + f.basis.x * side * (half + 3.0) + Vector3.UP * 4.0), Vector3(6.0, 30.0, 6.0), STONE)
	KitTools.commit(t, st, Palette.toon(Color.WHITE, true))


## The elevated railway over the road, and a train running along it.
static func _train(t: Track) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Track.ROAD_WIDTH * 0.5 + 1.8
	var d0 := _at(t, 12.0)
	var d1 := _at(t, 14.5)
	var d := d0
	var index := 0
	while d < d1:
		var a := t.road_frame(d)
		var b := t.road_frame(minf(d + 8.0, d1))
		var mid := a.origin.lerp(b.origin, 0.5) + Vector3.UP * 9.0
		KitTools.box(st, Transform3D(Basis.looking_at((b.origin - a.origin).normalized(), Vector3.UP), mid), Vector3(9.0, 0.9, 8.2), STEEL.darkened(0.25))
		if index % 2 == 0:
			for side: float in [-1.0, 1.0]:
				KitTools.box(st, Transform3D(a.basis, a.origin + a.basis.x * side * half + Vector3.UP * 4.5), Vector3(0.9, 9.0, 0.9), STEEL)
		d += 8.0
		index += 1
	KitTools.commit(t, st, Palette.toon(Color.WHITE, true))
	var train := Train.new()
	train.track = t
	train.from = d0 + 10.0
	train.to = d1 - 10.0
	t.add_child(train)


## A basin with a tall jet, inside the bend before the lakefront.
static func _fountain(t: Track) -> void:
	var basin := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 9.0
	ring.bottom_radius = 9.6
	ring.height = 1.2
	basin.mesh = ring
	basin.material_override = Palette.toon(STONE)
	basin.position = FOUNTAIN_AT + Vector3.UP * 0.6
	t.add_child(basin)
	var jet := MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.top_radius = 0.3
	col.bottom_radius = 1.4
	col.height = 11.0
	jet.mesh = col
	jet.material_override = KitTools.glow(Color(0.8, 0.95, 1.0))
	jet.position = FOUNTAIN_AT + Vector3.UP * 6.5
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(jet)
	var pool := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 8.6
	disc.bottom_radius = 8.6
	disc.height = 0.1
	pool.mesh = disc
	pool.material_override = KitTools.glow(LAKE.lightened(0.3))
	pool.position = FOUNTAIN_AT + Vector3.UP * 1.15
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(pool)


## Street life: corner arrows, lights and signs underground, flags and
## crowds along the lakefront, by the fountain and between the towers, and
## boats on the lake and the river.
static func _dress(t: Track) -> void:
	var L := t.length
	KitDress.chevrons(t, Color(0.1, 0.13, 0.22), ORANGE)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	KitDress.edge_lights(t, glow, _at(t, 2.6), _at(t, 5.2), 7.0, ORANGE)
	KitDress.edge_lights(t, glow, _at(t, 5.2), _at(t, 9.4), 7.0, GREEN)
	_lower_street(t, glow)
	# Lit signs hung from the lower street's ceiling.
	var d := _at(t, 5.4)
	var index := 0
	while d < _at(t, 9.2):
		var f := t.road_frame(d)
		for side: float in [-1.0, 1.0]:
			KitTools.box(glow, Transform3D(f.basis, f.origin + f.basis.x * side * 3.6 + Vector3.UP * 5.5), Vector3(4.6, 1.1, 0.2), Color(0.25, 0.9, 0.5) if (index + int(side)) % 2 == 0 else Color(0.3, 0.7, 1.0))
		d += 46.0
		index += 1
	# The fountain's ring of smaller jets.
	for k in 8:
		var ang := TAU * k / 8.0
		KitTools.box(glow, Transform3D(Basis(), FOUNTAIN_AT + Vector3(cos(ang) * 6.0, 3.6, sin(ang) * 6.0)), Vector3(0.35, 5.0, 0.35), Color(0.8, 0.95, 1.0))
	KitTools.commit(t, glow, KitTools.glow(Color.WHITE))
	var flags := SurfaceTool.new()
	flags.begin(Mesh.PRIMITIVE_TRIANGLES)
	KitDress.bunting(t, flags, L - 58.0, L + 150.0, 21.0, [ORANGE, LAKE, Color.WHITE, STEEL.lightened(0.3)], 7.5)
	KitDress.bunting(t, flags, _at(t, 14.8), _at(t, 17.2), 26.0, [ORANGE, LAKE, Color.WHITE, Color(0.85, 0.25, 0.25)], 7.5)
	KitTools.commit(t, flags, Palette.toon(Color.WHITE, true), true)
	# Crowds on the city side of the lakefront (two lots: the one behind the
	# camera isn't drawn), round the fountain and in the tower canyon.
	var tints := [ORANGE, LAKE, Color(0.9, 0.9, 0.95), Color(0.85, 0.25, 0.25), Color(1.0, 0.82, 0.3), STEEL.lightened(0.3)]
	var city_side := [-1.0]
	KitDress.crowd(t, KitDress.beside(t, L - 60.0, L - 6.0, 2.8, 2.6, city_side), tints, 2)
	KitDress.crowd(t, KitDress.beside(t, 4.0, 120.0, 2.8, 2.6, city_side), tints, 2)
	KitDress.crowd(t, KitDress.beside(t, _at(t, 15.0), _at(t, 17.0), 3.0, 2.6), tints, 2)
	var ring: Array[Transform3D] = []
	for k in 26:
		var ang := TAU * k / 26.0
		var out := Vector3(cos(ang), 0.0, sin(ang))
		ring.append(Transform3D(Basis.looking_at(out, Vector3.UP), FOUNTAIN_AT + out * 12.5))
	KitDress.crowd(t, ring, tints, 1)
	# Sailing boats out on the lake, and more passing under the drawbridge.
	var lake := PackedVector3Array([Vector3(90, -1.4, 40), Vector3(150, -1.4, -70), Vector3(250, -1.4, -150), Vector3(330, -1.4, -30), Vector3(240, -1.4, 110), Vector3(140, -1.4, 130)])
	KitDress.mover(t, "boat", lake, 6.0, 6, {"size": 2.2, "bob": 0.2, "level": true})
	var mid := t.road_frame((float(t.gaps[0][0]) + float(t.gaps[0][1])) * 0.5).origin
	var river := PackedVector3Array()
	for k in 8:
		var ang := TAU * k / 8.0
		river.append(Vector3(mid.x + cos(ang) * 170.0, -1.4, mid.z + sin(ang) * 9.0))
	KitDress.mover(t, "boat", river, 8.0, 5, {"size": 1.8, "bob": 0.2, "level": true})


## The lower street, after the real one under Chicago's riverside drive: a
## service road lined with columns and loading-dock doors, pipes along the
## ceiling, hazard stripes, and green light.
static func _lower_street(t: Track, glow: SurfaceTool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := Track.ROAD_WIDTH * 0.5 + 1.0
	var doors := [STEEL, Color(0.6, 0.32, 0.2), Color(0.42, 0.44, 0.48), Color(0.2, 0.42, 0.4)]
	var d := _at(t, 5.3)
	var end := _at(t, 9.3)
	var index := 0
	while d < end:
		var f := t.road_frame(d)
		for side: float in [-1.0, 1.0]:
			var at_wall := f.origin + f.basis.x * side * (wall - 0.12)
			if index % 2 == 0:
				# A column against the wall, striped at the foot.
				KitTools.box(st, Transform3D(f.basis, at_wall - f.basis.x * side * 0.15 + Vector3.UP * 3.25), Vector3(0.5, 6.5, 1.1), Color(0.5, 0.51, 0.54))
				KitTools.box(st, Transform3D(f.basis, at_wall - f.basis.x * side * 0.2 + Vector3.UP * 0.6), Vector3(0.56, 1.2, 1.16), Color(1.0, 0.82, 0.2))
			elif (index / 2 + int(side)) % 2 == 0:
				# A loading-dock door with a lit number plate over it.
				KitTools.box(st, Transform3D(f.basis, at_wall + Vector3.UP * 2.1), Vector3(0.1, 4.2, 5.2), doors[(index / 2) % doors.size()])
				KitTools.box(st, Transform3D(f.basis, at_wall + Vector3.UP * 0.25), Vector3(0.14, 0.5, 5.6), Color(1.0, 0.82, 0.2))
				KitTools.box(glow, Transform3D(f.basis, at_wall + Vector3.UP * 4.75), Vector3(0.1, 0.5, 2.2), GREEN.lerp(Color.WHITE, 0.4))
		# Pipes along the ceiling.
		var g := t.road_frame(minf(d + 7.0, end))
		var along := Basis.looking_at((g.origin - f.origin).normalized(), Vector3.UP)
		for x: float in [-5.2, -4.4, 5.0]:
			KitTools.box(st, Transform3D(along, (f.origin + g.origin) * 0.5 + f.basis.x * x + Vector3.UP * 6.0), Vector3(0.45, 0.45, 7.2), Color(0.55, 0.3, 0.2) if x > 0.0 else Color(0.35, 0.42, 0.5))
		d += 7.0
		index += 1
	KitTools.commit(t, st, Palette.toon(Color.WHITE, true))


## Three cars running back and forth along the elevated railway.
class Train extends Node3D:
	var track: Track
	var from := 0.0
	var to := 0.0
	var _t := 0.0
	var _cars: Array[MeshInstance3D] = []

	func _ready() -> void:
		for i in 3:
			var car := MeshInstance3D.new()
			car.mesh = KitTools.model("train_car")
			car.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(car)
			_cars.append(car)

	func _process(delta: float) -> void:
		_t += delta
		var span := to - from - 32.0
		var u := fposmod(_t * 22.0 / span, 2.0)
		var head := from + 32.0 + span * (u if u < 1.0 else 2.0 - u)
		for i in _cars.size():
			var f := track.road_frame(head - i * 15.0)
			_cars[i].global_transform = Transform3D(f.basis, f.origin + Vector3.UP * 9.5)
