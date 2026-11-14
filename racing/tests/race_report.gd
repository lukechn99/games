extends SceneTree
## The verify command's fast race (design doc 14.3): eight computer drivers
## race each track with nothing drawn, as fast as the machine allows, and one
## line per track says how it went: "[race] {json}".
##   KW_TRACKS=meadow,mine   which tracks (default all)   KW_LAPS=2
## Reports lap times, resets (and why), the longest a kart was stuck, how
## many laps used each route, items used by kind, and the slowest single
## step against the typical one (a freeze, such as loading on first use).

const BUILDS := [["frame", "slicks"], ["hauler", "knobby"], ["soapbox", "balloon"], ["racer", "studded"]]
const LEVELS := ["hard", "medium", "easy", "hard", "medium", "hard", "easy", "medium"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tracks := OS.get_environment("KW_TRACKS")
	var laps := int(OS.get_environment("KW_LAPS")) if OS.get_environment("KW_LAPS") != "" else 2
	for layout in (tracks.split(",") if tracks != "" else PackedStringArray(["meadow", "mine", "frost"])):
		await _race(layout, laps)
	quit(0)


func _race(layout: String, laps: int) -> void:
	var wall0 := Time.get_ticks_msec()
	var world := Node3D.new()
	root.add_child(world)
	var track := Track.new()
	track.layout = layout
	track.laps = laps
	world.add_child(track)
	await physics_frame
	await physics_frame
	var karts: Array[Kart] = []
	for i in 8:
		var k := Kart.new()
		k.configure(BUILDS[i % 4][0], BUILDS[i % 4][1], Parts.DRIVERS.keys()[i % Parts.DRIVERS.size()] if Parts.DRIVERS is Dictionary else Parts.DRIVERS[i % Parts.DRIVERS.size()])
		k.track = track
		k.display_name = "kart%d" % i
		k.number = i + 1
		k.next_checkpoint = 0
		k.set_meta("bot_items", true)
		world.add_child(k)
		k.global_transform = track.grid_transform(i)
		karts.append(k)
		world.add_child(BotDriver.new(k, track, LEVELS[i], i + 2))
	var bumps := KartBumps.new()
	bumps.karts = karts
	world.add_child(bumps)
	var items := Items.new()
	world.add_child(items)
	items.setup(track, karts, karts)

	var lap_times: Array[float] = []
	var crossed := {}
	var done := {}
	var count := {"resets": 0}   # (a dictionary: lambdas copy plain numbers)
	var reasons := {}
	var used := {}
	var t := [0.0]
	for k in karts:
		# (Emitted on crossing the line into lap `lap`, with the race clock:
		# the first crossing, off the grid, starts lap 1.)
		k.lap_completed.connect(func(lap: int, time: float):
			if lap >= 2:
				lap_times.append(time - float(crossed.get(k, 0.0)))
			crossed[k] = time
			if lap > laps:
				done[k] = true)
		k.respawned.connect(func():
			count["resets"] += 1
			if reasons.size() < 5:
				reasons["%s@%.0fs" % [k.display_name, t[0]]] = k.respawn_reason)
	items.used.connect(func(kind: String, _p, _d, _s): used[kind] = int(used.get(kind, 0)) + 1)

	var stuck_now := {}
	var stuck := 0.0
	var on_route := {}        # kart -> {route kind: true} this lap
	var last_lap := {}
	var routes := {"main": 0}
	var steps: Array[float] = []
	var worst := 0.0
	var worst_at := 0.0
	var last_us := Time.get_ticks_usec()
	var frame := 0
	while done.size() < karts.size() and t[0] < laps * 150.0:
		await physics_frame
		t[0] += 1.0 / 60.0
		frame += 1
		var now := Time.get_ticks_usec()
		var ms := (now - last_us) / 1000.0
		last_us = now
		if frame > 30:       # (the first steps settle the karts)
			steps.append(ms)
			if ms > worst:
				worst = ms
				worst_at = t[0]
		for k in karts:
			# A lap just ended: note which routes it used.
			if int(last_lap.get(k, 0)) != k.lap:
				var first: bool = not last_lap.has(k)
				last_lap[k] = k.lap
				if not first:
					var took: Dictionary = on_route.get(k, {})
					if took.is_empty():
						routes["main"] += 1
					for kind in took:
						routes[kind] = int(routes.get(kind, 0)) + 1
				on_route.erase(k)
			if done.has(k):
				continue
			stuck_now[k] = float(stuck_now.get(k, 0.0)) + 1.0 / 60.0 if k.linear_velocity.length() < 2.0 and t[0] > 5.0 else 0.0
			stuck = maxf(stuck, stuck_now[k])
			if frame % 6 != 0:
				continue
			# Which route is this kart on?
			var off := track.offset_of(k.global_position)
			var bi := track.branch_at(off)
			if bi >= 0:
				var p := k.global_position
				# (Clearly nearer the branch: the two run together where they part and rejoin.)
				if p.distance_to(track.branch_frame(off, bi).origin) + 4.0 < p.distance_to(track.transform_at(off).origin):
					if not on_route.has(k):
						on_route[k] = {}
					on_route[k][str(track.branches[bi].get("kind", "route%d" % bi))] = true
	steps.sort()
	lap_times.sort()
	var typical: float = steps[steps.size() / 2] if not steps.is_empty() else 0.0
	print("[race] ", JSON.stringify({
		"track": layout, "laps": laps, "karts": karts.size(), "finished": done.size(),
		"lap_min": snappedf(lap_times[0], 0.1) if not lap_times.is_empty() else 0.0,
		"lap_max": snappedf(lap_times[-1], 0.1) if not lap_times.is_empty() else 0.0,
		"resets": count["resets"], "reset_reasons": reasons, "stuck_s": snappedf(stuck, 0.1),
		"routes": routes, "items": used,
		"step_ms": snappedf(typical, 0.01), "step_max_ms": snappedf(worst, 0.1), "step_max_at_s": snappedf(worst_at, 0.1),
		"sim_s": snappedf(t[0], 0.1), "wall_s": snappedf((Time.get_ticks_msec() - wall0) / 1000.0, 0.1),
	}))
	world.free()
	Items.sand.clear()
	await physics_frame
