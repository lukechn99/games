class_name ProvingTrack
extends RefCounted
## The proving ground: a plain oval with one of each Series 2 mechanic on it
## (design doc 8.4), where each is built and tested before a track uses it.
## Not in the track picker (?track=proving).

const POINTS := [
	Vector3(0, 0, 60), Vector3(0, 0, -20),
	# A ramp up to a launch gap, and the landing beyond it.
	Vector3(0, 1.5, -66), Vector3(0, 6, -112), Vector3(0, 3.5, -166), Vector3(0, 0, -214),
	Vector3(8, 0, -262), Vector3(44, 0, -304), Vector3(100, 0, -306), Vector3(136, 0, -262),
	Vector3(142, 0, -110), Vector3(140, 0, 40), Vector3(104, 0, 100), Vector3(40, 0, 102),
]
const NAME := "Proving Ground"
const SIGN_FONT := "res://assets/fonts/lilita_one.woff2"
const SIGN_INK := Color(1, 1, 1)
const SIGN_EDGE := Color(0.1, 0.1, 0.2)
const SIGN_BOARD := Color(0.2, 0.24, 0.32)
const SIGN_TRIM := Color(1.0, 0.7, 0.12)
const LIP := 3       # the launch gap runs from this point...
const LANDING := 4   # ...to this one


static func configure(t: Track) -> void:
	t.points = POINTS
	t.surface_zones = []
	t.rail_zones = []
	t.ground_y = -60.0


static func plan(t: Track) -> void:
	t.gaps = [[t.offset_of(POINTS[LIP]), t.offset_of(POINTS[LANDING])]]
	# Along the back straight (points 10 to 11): low gravity, then a jet
	# across the left half of the road, then a cross-wind.
	var a := t.offset_of(POINTS[10])
	t.fx_zones = [
		{"kind": "gravity", "from": a + 10.0, "to": a + 50.0, "scale": 0.4},
		{"kind": "wind", "from": a + 90.0, "to": a + 140.0, "push": 9.0, "period": 6.0},
		{"kind": "drag", "from": a - 60.0, "to": a - 30.0, "drag": 1.2},
	]
	t.fx_hazards = [{"at": a + 70.0, "from_x": -7.0, "to_x": 0.0, "period": 4.0, "on": 1.3, "phase": 0.0}]


static func world(_env: Environment, _sun: DirectionalLight3D) -> void:
	pass


static func crate_frames(t: Track) -> Array[Transform3D]:
	return [t.transform_at(t.length * 0.6)]


static func road_material(_m: ShaderMaterial) -> void:
	pass


static func build(_t: Track) -> void:
	pass
