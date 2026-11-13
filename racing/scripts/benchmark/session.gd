class_name BenchmarkSession
extends RefCounted
## The game's only benchmark entry point. No benchmark policy belongs in AI,
## physics, track geometry or normal race progression.


static func attach(race: Node, query: String) -> bool:
	var params := {}
	for item in query.trim_prefix("?").split("&"):
		var pair := item.split("=", true, 1)
		params[pair[0]] = pair[1] if pair.size() > 1 else ""
	if not params.has("bench") and not params.has("benchqualities") and not params.has("benchhalves") and not params.has("benchmedium"):
		return false
	var halves := params.has("benchqualities") or params.has("benchhalves") or params.has("benchmedium")
	var context := BenchmarkContext.new(race, race.track, race.player_kart, race.karts, func(): return race.get("_racing"))
	if halves:
		# Keep all rivals on the same route too, preserving their builds/levels.
		for child in race.get_children():
			if child is BotDriver:
				var replacement := BenchmarkDriver.new(child.kart, race.track, child.level, child.noise_seed)
				var enabled := child.is_physics_processing()
				var index := child.get_index()
				var lane: float = child.lane
				child.free()
				race.add_child(replacement)
				race.move_child(replacement, index)
				replacement.lane = lane
				replacement.set_physics_process(enabled)
		var driver := BenchmarkDriver.new(race.player_kart, race.track, "hard", 99)
		driver.record_route = true
		race.add_child(driver)
		var bench: QualityBench = MediumBench.new() if params.has("benchmedium") else QualityBench.new()
		bench.context = context
		bench.route = driver.route
		race.add_child(bench)
	else:
		race.add_child(BotDriver.new(race.player_kart, race.track, "hard", 99))
		var bench := Bench.new()
		bench.context = context
		if params.has("bench") and not str(params["bench"]).is_empty():
			bench.seconds = clampf(float(params["bench"]), 1.0, 300.0)
		# ?benchwall=SECONDS: how long a slow machine may take before the run
		# stops as "partial" (default 120 s, right for phones).
		if params.has("benchwall"):
			bench.wall_limit = clampf(float(params["benchwall"]), 10.0, 900.0)
		race.add_child(bench)
	return true
