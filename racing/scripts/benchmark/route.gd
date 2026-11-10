class_name BenchmarkRoute
extends RefCounted
## Fixed driving line plus observed, per-lap evidence. Never moves a kart or
## edits the world to manufacture a successful route.

var track: Track
var lake := Vector2.ZERO
var evidence := {}
var errors: Array[String] = []
var route_name := "cave"


func _init(t: Track) -> void:
	track = t
	if track.layout == "frost":
		lake = FrostTrack.lake_span(track)
		route_name = "underwater"
	elif track.layout == "mine":
		route_name = "tunnel"


func take_branch(bi: int) -> bool:
	return bi >= 0 and track.branches[bi]["kind"] == route_name


func frost_target(offset: float) -> Vector3:
	var f := track.transform_at(offset)
	# Approach hole 1 at +6 m, then stay right of all sunken boulders. Ease
	# back to the centre on the exit ramp. This is ordinary steering.
	var entry := lerpf(lake.x, lake.y, float(FrostTrack.HOLES[1][0]))
	var lateral := 6.0 * smoothstep(lake.x - 35.0, entry - 12.0, offset)
	lateral = lerpf(lateral, 6.8, smoothstep(entry, entry + 18.0, offset))
	lateral *= 1.0 - smoothstep(lake.y - FrostTrack.EXIT_LEN, lake.y, offset)
	return f.origin + f.basis.x * lateral


func observe(kart: Kart, off: float) -> void:
	if kart.lap < 1 or kart.lap > 3:
		return
	var seen: Dictionary = evidence.get(kart.lap, {})
	if track.layout == "frost":
		var hole: Array = FrostTrack.HOLES[1]
		var hf := track.transform_at(lerpf(lake.x, lake.y, float(hole[0])))
		var hp := hf.origin + hf.basis.x * float(hole[1])
		var flat := Vector2(kart.global_position.x - hp.x, kart.global_position.z - hp.z)
		if flat.length() < float(hole[2]) and kart.global_position.y < -0.8 and kart.global_position.y > -3.0:
			seen["entry_hole_1"] = true
		var u := inverse_lerp(lake.x, lake.y, off)
		if u > 0.4 and u < 0.7:
			if kart.global_position.y < -3.0 and FrostTrack.in_lake(kart.global_position):
				seen["underwater"] = true
			else:
				fail("lap %d missed underwater road" % kart.lap)
	else:
		var bi := track.branch_at(off)
		if bi >= 0 and take_branch(bi):
			var b: Dictionary = track.branches[bi]
			var u := inverse_lerp(float(b["from"]), float(b["to"]), off)
			if u > 0.4 and u < 0.6:
				var expected := track.branch_frame(off, bi).origin
				if kart.global_position.distance_to(expected) < Track.ROAD_WIDTH * 0.5 + 2.0:
					seen[route_name] = true
				else:
					fail("lap %d missed %s" % [kart.lap, route_name])
	evidence[kart.lap] = seen


func valid_lap(lap: int) -> bool:
	var seen: Dictionary = evidence.get(lap, {})
	return seen.has(route_name) and (route_name != "underwater" or seen.has("entry_hole_1"))


func fail(reason: String) -> void:
	if errors.size() < 8 and not errors.has(reason):
		errors.append(reason)
