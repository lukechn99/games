class_name Parts
## Every kart part and surface as plain numbers, so tuning never touches
## physics code. The design doc (section 5) describes what each part is for;
## the balancing rules are still to be decided, so treat these as first guesses.

## Surfaces: `grip` multiplies tire grip, `drag` slows the kart (per second),
## `color` paints the track so players can read it.
const SURFACES := {
	"asphalt": {"grip": 1.0, "drag": 0.02, "color": Color(0.36, 0.37, 0.42)},
	"dirt": {"grip": 0.8, "drag": 0.25, "color": Color(0.64, 0.47, 0.3)},
	"grass": {"grip": 0.7, "drag": 0.9, "color": Color(0.42, 0.72, 0.33)},
	"sand": {"grip": 0.65, "drag": 1.2, "color": Color(0.93, 0.83, 0.58)},
	"ice": {"grip": 0.28, "drag": 0.0, "color": Color(0.78, 0.92, 1.0)},
	"snow": {"grip": 0.55, "drag": 0.5, "color": Color(0.96, 0.97, 1.0)},
	"boost": {"grip": 1.0, "drag": -2.5, "color": Color(1.0, 0.62, 0.15)},
}

## Chassis: sets turning and the hit box (design doc 5.2).
## Sizes in metres; forward is -Z. `max_steer` in radians.
const CHASSIS := {
	"frame": {
		"name": "Go-kart frame",
		"size": Vector3(1.3, 0.5, 2.0), "wheelbase": 1.45, "track": 1.2,
		"mass": 140.0, "max_steer": 0.5, "high_speed_steer": 0.42,
		"top_speed": 27.0, "accel": 1500.0,
		"wheel_radius": [0.26, 0.36], "color": Color(0.95, 0.35, 0.3),
	},
	"soapbox": {
		"name": "Soapbox",
		"size": Vector3(1.05, 0.5, 1.6), "wheelbase": 1.15, "track": 1.0,
		"mass": 110.0, "max_steer": 0.6, "high_speed_steer": 0.5,
		"top_speed": 25.5, "accel": 1300.0,
		"wheel_radius": [0.22, 0.3], "color": Color(0.3, 0.65, 0.95),
	},
	"hauler": {
		"name": "Hauler",
		"size": Vector3(1.6, 0.65, 2.3), "wheelbase": 1.7, "track": 1.45,
		"mass": 210.0, "max_steer": 0.42, "high_speed_steer": 0.38,
		"top_speed": 27.5, "accel": 2050.0,
		"wheel_radius": [0.3, 0.42], "color": Color(0.96, 0.72, 0.2),
	},
	"racer": {
		"name": "Racer",
		"size": Vector3(1.15, 0.42, 2.5), "wheelbase": 1.9, "track": 1.15,
		"mass": 150.0, "max_steer": 0.44, "high_speed_steer": 0.36,
		"top_speed": 29.0, "accel": 1450.0,
		"wheel_radius": [0.24, 0.32], "color": Color(0.45, 0.85, 0.45),
	},
}

## Wheels and tires: handling and grip per surface (design doc 5.3).
## `grip` is the friction coefficient on a neutral surface; `by_surface`
## multiplies it on each surface. `drift` scales rear grip while drifting
## (lower = looser) and how fast drifts charge boost.
const TIRES := {
	"slicks": {
		"name": "Slicks", "radius": 0.3, "width": 0.3, "grip": 1.35,
		"by_surface": {"asphalt": 1.1, "dirt": 0.75, "grass": 0.75, "sand": 0.7, "ice": 0.8, "snow": 0.7},
		"top_speed": 1.03, "spring": 1.0, "drift": 0.62, "drift_charge": 1.0, "color": Color(0.15, 0.15, 0.17),
	},
	"knobby": {
		"name": "Knobby off-road", "radius": 0.33, "width": 0.34, "grip": 1.25,
		"by_surface": {"asphalt": 0.95, "dirt": 1.25, "grass": 1.25, "sand": 1.1, "ice": 0.95, "snow": 1.1},
		"top_speed": 0.97, "spring": 1.1, "drift": 0.66, "drift_charge": 0.9, "color": Color(0.28, 0.22, 0.18),
	},
	"balloon": {
		"name": "Balloon", "radius": 0.36, "width": 0.4, "grip": 1.2,
		"by_surface": {"asphalt": 0.95, "dirt": 1.1, "grass": 1.1, "sand": 1.35, "ice": 0.95, "snow": 1.05},
		"top_speed": 0.98, "spring": 0.75, "drift": 0.7, "drift_charge": 1.1, "color": Color(0.3, 0.3, 0.36),
	},
	"studded": {
		"name": "Studded", "radius": 0.3, "width": 0.3, "grip": 1.22,
		"by_surface": {"asphalt": 0.95, "dirt": 1.0, "grass": 0.95, "sand": 0.75, "ice": 2.6, "snow": 1.35},
		"top_speed": 0.99, "spring": 1.0, "drift": 0.66, "drift_charge": 1.0, "color": Color(0.22, 0.25, 0.3),
	},
}

## Drivers share one base body (design doc 5.4). Weight class adds mass.
const DRIVERS := {
	"fox": {"name": "Fox", "weight": "medium", "body": Color(0.96, 0.5, 0.16), "belly": Color(1, 0.96, 0.9), "features": ["pointed_ears", "bushy_tail"]},
	"frog": {"name": "Frog", "weight": "small", "body": Color(0.35, 0.8, 0.3), "belly": Color(0.85, 0.95, 0.55), "features": ["top_eyes"]},
	"rhino": {"name": "Rhino", "weight": "large", "body": Color(0.55, 0.58, 0.64), "belly": Color(0.72, 0.74, 0.78), "features": ["horn", "round_ears"]},
	"deer": {"name": "Deer", "weight": "medium", "body": Color(0.76, 0.52, 0.32), "belly": Color(0.98, 0.9, 0.78), "features": ["antlers", "round_ears"]},
}

const WEIGHT_MASS := {"small": 15.0, "medium": 25.0, "large": 40.0}
const WEIGHT_SCALE := {"small": 0.9, "medium": 1.0, "large": 1.12}


static func surface(name: String) -> Dictionary:
	return SURFACES.get(name, SURFACES["asphalt"])


## Friction coefficient for a tire on a surface.
static func tire_grip(tires: Dictionary, surface_name: String) -> float:
	var by: Dictionary = tires["by_surface"]
	return float(tires["grip"]) * float(by.get(surface_name, 1.0)) * float(surface(surface_name)["grip"])
