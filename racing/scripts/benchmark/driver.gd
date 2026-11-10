class_name BenchmarkDriver
extends BotDriver
## Fixed-route AI used only by benchmark sessions. Normal BotDriver knows
## nothing about benchmark URLs, route names, sampling or graphics quality.

var route: BenchmarkRoute
var record_route := false
var _offset := 0.0


func _init(k: Kart, t: Track, lvl := "hard", seed_value := 99) -> void:
	super(k, t, lvl, seed_value)
	route = BenchmarkRoute.new(t)


func _ready() -> void:
	super()
	if record_route:
		kart.respawned.connect(func(): route.fail("kart reset on lap %d" % kart.lap))


func _take_branch(bi: int, offset: float) -> bool:
	_offset = offset
	return route.take_branch(bi)


func _target_at(offset: float, lateral: float, bi: int, take: bool) -> Vector3:
	if track.layout == "frost" and offset > route.lake.x - 35.0 and offset < route.lake.y:
		return route.frost_target(offset)
	return super(offset, lateral, bi, take)


func _physics_process(delta: float) -> void:
	super(delta)
	if record_route:
		route.observe(kart, _offset)
	if track.layout == "frost":
		var entry := lerpf(route.lake.x, route.lake.y, float(FrostTrack.HOLES[1][0]))
		if _offset > route.lake.x - 20.0 and _offset < entry + 12.0 and kart.global_position.y > -3.0:
			kart.input["drift"] = false
			if kart.speed > 12.0:
				kart.input["throttle"] = 0.0
				kart.input["brake"] = 0.5
