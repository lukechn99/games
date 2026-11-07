class_name BotDriver
extends Node
## A computer driver (design doc 12). It drives the same kart, through the
## same `input`, as a player, so bots get chassis, tires and surfaces for
## free. It aims at a point ahead on the racing line, slows for corners based
## on how sharp they are, and drifts the sharp ones on higher levels.

const LEVELS := {
	"easy": {"pace": 0.82, "brake_early": 1.35, "wobble": 0.12, "drift": false, "lane": 3.0},
	"medium": {"pace": 0.92, "brake_early": 1.15, "wobble": 0.06, "drift": true, "lane": 2.2},
	"hard": {"pace": 1.0, "brake_early": 1.0, "wobble": 0.02, "drift": true, "lane": 1.5},
}

var kart: Kart
var track: Track
var level := "medium"
var lane := 0.0              # preferred offset from the racing line, metres
var _noise := FastNoiseLite.new()
var _t := 0.0
var _stuck := 0.0
var _fell_on_lap := -1        # after a fall, stay on the main road for the lap


func _init(k: Kart, t: Track, lvl := "medium", seed_value := 0) -> void:
	kart = k
	track = t
	level = lvl
	_noise.seed = seed_value
	_noise.frequency = 0.25
	# Run before the kart's own physics each tick.
	process_physics_priority = -1


func _ready() -> void:
	lane = (float(get_index() % 3) - 1.0) * float(LEVELS[level]["lane"])
	kart.respawned.connect(func(): _fell_on_lap = kart.lap)


func _physics_process(delta: float) -> void:
	if kart == null or track == null:
		return
	_t += delta
	var cfg: Dictionary = LEVELS[level]
	var off := track.offset_of(kart.global_position)
	var spd := maxf(kart.speed, 0.0)
	var look := 7.0 + spd * 0.55
	var aim := track.transform_at(off + look)
	var wander := lane + _noise.get_noise_1d(_t) * 3.0 * float(cfg["wobble"]) * 10.0
	# Where the road splits, each bot picks a side, and switches lap to lap.
	# Easy bots leave the rope bridge alone, and anyone who has just fallen
	# off keeps to the main road for the rest of that lap.
	var bi := track.branch_at(off + look)
	var bridge: bool = bi >= 0 and track.branches[bi]["kind"] == "bridge"
	# Narrow: the bridge, or the mine's trestle over the cavern.
	var narrow: bool = bi >= 0 and not track._branch_has_road(bi, off + look)
	var take := bi >= 0 and (kart.lap + get_index() + bi) % 2 == 0
	if bridge and (level == "easy" or _fell_on_lap == kart.lap):
		take = false
	if take and narrow:
		wander *= 0.15   # down the middle of the planks
	var target := aim.origin + aim.basis.x * wander
	if take:
		target += aim.basis.x * track.branch_offset(off + look, bi)

	var to := target - kart.global_position
	to.y = 0.0
	var fwd := -kart.global_transform.basis.z
	fwd.y = 0.0
	var angle := fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	# signed_angle_to is positive anticlockwise (left); our steer is positive right.
	var steer := clampf(-angle * 2.4, -1.0, 1.0)

	# Corner speed: how much the line turns over the next stretch.
	var bend := _bend_ahead(off + 4.0, 10.0 + spd * float(cfg["brake_early"]) * 1.3)
	var corner_speed := sqrt(9.8 * Parts.tire_grip(kart.tires, kart.surface_name) * 0.95 / maxf(bend, 0.0005))
	var want := minf(kart.top_speed() * float(cfg["pace"]), corner_speed * float(cfg["pace"]))
	var throttle := 1.0
	var brake := 0.0
	if spd > want + 1.5:
		throttle = 0.0
		brake = clampf((spd - want) / 6.0, 0.2, 1.0)
	elif spd > want:
		throttle = 0.3

	var drift := false
	if bool(cfg["drift"]) and bend > 0.012 and spd > 14.0 and absf(steer) > 0.35:
		drift = true

	# Stuck against something: back off and turn away.
	_stuck = _stuck + delta if spd < 1.0 and throttle > 0.5 else 0.0
	if _stuck > 1.2:
		throttle = 0.0
		brake = 1.0
		steer = -steer
		if _stuck > 2.6:
			_stuck = 0.0

	kart.input = {"steer": steer, "throttle": throttle, "brake": brake, "drift": drift}


## Average turning (radians per metre) of the line between `from` and `from + span`.
func _bend_ahead(from: float, span: float) -> float:
	var a := track.transform_at(from)
	var b := track.transform_at(from + span)
	var fa := -a.basis.z
	var fb := -b.basis.z
	return absf(fa.signed_angle_to(fb, Vector3.UP)) / span
