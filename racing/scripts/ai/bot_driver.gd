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
var noise_seed: int:
	get:
		return _noise.seed
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
	# Medium and hard drivers do a trick off every lip (LaunchGaps reads
	# this; pressing drift at the lip would start a drift hop on the ground).
	kart.set_meta("tricks", level != "easy")
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
	var wander := lane + _noise.get_noise_1d(_t) * 3.0 * float(cfg["wobble"]) * 10.0
	# Where the road splits, each bot picks a side, and switches lap to lap.
	# Easy bots leave the rope bridge alone, and anyone who has just fallen
	# off keeps to the main road for the rest of that lap.
	var bi := track.branch_at(off + look)
	# Narrow: the bridge, or the mine's trestle over the cavern.
	var narrow: bool = bi >= 0 and not track._branch_has_road(bi, off + look)
	var take := _take_branch(bi, off)
	if take and narrow:
		wander *= 0.15   # down the middle of the planks
	var on_path: bool = take and not (track.branches[bi].get("pts", PackedVector3Array()) as PackedVector3Array).is_empty()
	# Vents that blow karts away (the saucer): keep to the open side.
	for h: Dictionary in track.fx_hazards:
		if h.get("blow", false):
			var ahead := fposmod(float(h["at"]) - off, track.length)
			if ahead > 0.0 and ahead < 70.0:
				wander = 4.0 if float(h["from_x"]) + float(h["to_x"]) < 0.0 else -4.0
	var target := _target_at(off + look, wander, bi, take)
	# In a crater you can drive anywhere: make for one of its lips (a bowl
	# with several, the moon's first crater, is picked lap by lap).
	var zone := track.free_zone_at(kart.global_position)
	if zone >= 0:
		var lips := track.pads_of_zone(zone)
		if not lips.is_empty():
			var p: Dictionary = lips[(kart.lap + get_index()) % lips.size()]
			var dir: Vector3 = p["dir"]
			target = (p["centre"] as Vector3) + dir * (float(p["r"]) + 14.0)

	# A boulder on the way (the sunken road under Frosty Pass's ice): aim
	# past its nearer side. Bots drove straight into them and backed off for
	# seconds.
	var kp := kart.global_position
	for o: Vector4 in track.obstacles:
		var rel := Vector3(o.x - kp.x, 0.0, o.z - kp.z)
		var aim := Vector3(target.x - kp.x, 0.0, target.z - kp.z)
		if absf(o.y - kp.y) > 3.0 or aim.length() < 0.1:
			continue
		var dir := aim.normalized()
		var ahead := rel.dot(dir)
		var side := dir.cross(Vector3.UP).dot(rel)   # + : obstacle to the right
		var clear := o.w + 2.2
		if ahead > 0.0 and ahead < look + 6.0 and absf(side) < clear:
			var left := -dir.cross(Vector3.UP)
			target = Vector3(o.x, target.y, o.z) + (left if side >= 0.0 else -left) * (clear + 0.5)
			break

	var to := target - kart.global_position
	to.y = 0.0
	var fwd := -kart.global_transform.basis.z
	fwd.y = 0.0
	var angle := fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	# signed_angle_to is positive anticlockwise (left); our steer is positive right.
	var steer := clampf(-angle * 2.4, -1.0, 1.0)

	# Corner speed: how much the line turns over the next stretch.
	var span := 10.0 + spd * float(cfg["brake_early"]) * 1.3
	var bend := _bend_ahead(off + 4.0, span)
	if on_path:
		var fa := -track.branch_frame(off + 4.0, bi).basis.z
		var fb := -track.branch_frame(off + 4.0 + span, bi).basis.z
		bend = absf(fa.signed_angle_to(fb, Vector3.UP)) / span
	var corner_speed := sqrt(9.8 * Parts.tire_grip(kart.tires, kart.surface_name) * 0.95 / maxf(bend, 0.0005))
	var want := minf(kart.top_speed() * float(cfg["pace"]), corner_speed * float(cfg["pace"]))
	if kart.surface_name == "ice":
		want *= 0.88   # a little careful on ice
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


## Route choice and target calculation are extension points for driving policies.
func _take_branch(bi: int, _offset: float) -> bool:
	var take := bi >= 0 and (kart.lap + get_index() + bi) % 2 == 0
	if bi >= 0 and track.branches[bi]["kind"] == "bridge" and (level == "easy" or _fell_on_lap == kart.lap):
		take = false
	return take


func _target_at(offset: float, lateral: float, bi: int, take: bool) -> Vector3:
	var frame := track.transform_at(offset)
	var target := frame.origin + frame.basis.x * lateral
	if take:
		if not (track.branches[bi].get("pts", PackedVector3Array()) as PackedVector3Array).is_empty():
			frame = track.branch_frame(offset, bi)
			target = frame.origin + frame.basis.x * lateral
		else:
			target += frame.basis.x * track.branch_offset(offset, bi)
	return target
