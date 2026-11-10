extends SceneTree
## Benchmark integration lives outside the gameplay test suite. Physics, real
## route geometry, measured half boundaries and fixed-distance settling.
var failures := 0
var bench_script: Script

class RaceFixture extends Node3D:
	var track: Track
	var player_kart: Kart
	var karts: Array[Kart] = []
	var _racing := true

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	print("  ok   " if ok else "  FAIL ", message)
	if not ok:
		failures += 1

func _run() -> void:
	bench_script = load("res://scripts/benchmark/quality_bench.gd")
	check(bench_script.phase_at(0, 990, 1000) == -1, "grid is excluded")
	check(bench_script.phase_at(1, 499.9, 1000) == 0 and bench_script.phase_at(1, 500, 1000) == 1, "half boundary uses distance")
	check(bench_script.phase_at(4, 0, 1000) == 6, "three completed laps end the run")
	for quality in [0, 1, 2]:
		var positions: Array[int] = []
		for i in 6:
			if bench_script.ORDER[i] == quality:
				positions.append(i)
		check(positions.size() == 2 and positions[0] % 2 != positions[1] % 2 and positions[0] + positions[1] == 5, "quality %d covers both halves with symmetric ordering" % quality)
	for layout in ["meadow", "mine", "frost"]:
		await _drive(layout)
	print("benchmark checks: %d failures" % failures)
	quit(1 if failures else 0)

func _drive(layout: String) -> void:
	var fixture := RaceFixture.new()
	root.add_child(fixture)
	fixture.track = Track.new()
	fixture.track.layout = layout
	fixture.add_child(fixture.track)
	await physics_frame
	await physics_frame
	for i in 4:
		var k := Kart.new()
		var builds := [["frame", "slicks"], ["hauler", "knobby"], ["soapbox", "balloon"], ["racer", "studded"]]
		k.configure(builds[i][0], builds[i][1], "fox")
		k.track = fixture.track
		k.display_name = "kart%d" % i
		k.number = i + 1
		k.next_checkpoint = 0
		fixture.add_child(k)
		k.global_transform = fixture.track.grid_transform(i)
		fixture.karts.append(k)
		if i > 0:
			fixture.add_child(BotDriver.new(k, fixture.track, ["hard", "medium", "easy", "hard"][i], i + 2))
	fixture.player_kart = fixture.karts[0]
	var bumps := KartBumps.new()
	bumps.karts = fixture.karts
	fixture.add_child(bumps)
	var session: Script = load("res://scripts/benchmark/session.gd")
	var before := fixture.get_child_count()
	check(not session.attach(fixture, "?autodrive&note=bench") and fixture.get_child_count() == before, "non-benchmark queries leave the race untouched")
	check(session.attach(fixture, "?autodrive&benchqualities"), "benchmark session attaches")
	var bench: Node
	var drivers := 0
	for child in fixture.get_children():
		if child.get_script() == bench_script:
			bench = child
		if child is BenchmarkDriver:
			drivers += 1
	check(drivers == 4, "one fixed-route driver per kart")
	var reports: Array[Dictionary] = []
	bench.completed.connect(func(r): reports.append(r))
	var t := 0.0
	while t < 450.0 and reports.is_empty():
		await physics_frame
		t += 1.0 / 60.0
		if int(t * 60) % 1200 == 0:
			var p := fixture.player_kart
			print("TRACE %s %.0fs lap%d %.0fm y%.1f speed%.1f" % [layout, t, p.lap, fixture.track.offset_of(p.global_position), p.global_position.y, p.speed])
	check(not reports.is_empty(), "%s completes the benchmark" % layout)
	if not reports.is_empty():
		var report := reports[0]
		check(report.valid, "%s valid: %s" % [layout, report.errors])
		check(report.results.size() == 6, "%s has six half-track samples" % layout)
		var coverage: bool = report.results.size() == 6
		for i in report.results.size():
			var sample: Dictionary = report.results[i]
			var expected_from: float = (i % 2) * fixture.track.length * 0.5 + 50.0
			coverage = coverage and sample.quality == ["low", "medium", "high", "high", "medium", "low"][i] and sample.lap == i / 2 + 1 and sample.half == i % 2 + 1
			coverage = coverage and is_equal_approx(sample.measured_from_m, expected_from) and absf(sample.start_progress.offset_m - expected_from) < 4.0
		check(coverage, "%s samples use the planned quality, lap, half and measured start" % layout)
		print("EVIDENCE ", layout, " ", report.route_evidence)
	fixture.free()
	await physics_frame
