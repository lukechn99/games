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
const LIP := 3       # the launch gap runs from this point...
const LANDING := 4   # ...to this one


static func configure(t: Track) -> void:
	t.points = POINTS
	t.surface_zones = []
	t.rail_zones = []
	t.ground_y = -60.0


static func plan(t: Track) -> void:
	t.gaps = [[t.offset_of(POINTS[LIP]), t.offset_of(POINTS[LANDING])]]


static func world(_env: Environment, _sun: DirectionalLight3D) -> void:
	pass


static func crate_frames(t: Track) -> Array[Transform3D]:
	return [t.transform_at(t.length * 0.6)]


static func build(_t: Track) -> void:
	pass
