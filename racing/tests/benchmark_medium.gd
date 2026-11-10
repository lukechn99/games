extends SceneTree
## Real game preset adapter: every probe phase restores Medium, then changes
## exactly one viewport feature. No simulated copy of the preset logic.
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	print("  ok   " if ok else "  FAIL ", message)
	if not ok:
		failures += 1

func _run() -> void:
	root.size = Vector2i(1600, 900)
	OS.set_environment("KW_QUERY", "?autodrive&benchmedium")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var probe: Node
	var script: Script = load("res://scripts/benchmark/medium_bench.gd")
	for child in scene.get_children():
		if child.get_script() == script:
			probe = child
	check(probe != null, "Medium feature test is installed by the real session adapter")
	if probe == null:
		quit(1)
		return
	var pixels := float(root.size.x * root.size.y)
	for i in 6:
		probe._apply_phase(i)
		var actual := pixels * root.scaling_3d_scale * root.scaling_3d_scale
		var expected_msaa: int = [1, 0, 1, 1, 0, 1][i]
		var expected_pixels: float = [1200000, 1200000, 900000, 900000, 1200000, 1200000][i]
		check(int(root.msaa_3d) == expected_msaa and absf(actual - expected_pixels) < 2.0, "phase %d applies only its AA/pixel variant" % (i + 1))
		check(int(root.get_node("Controls").quality) == 1 and Palette.relief_on and not Palette.clearcoat_on and KartVisual.cast_shadows and is_equal_approx(Track.detail_reach, 1.0), "phase %d retains Medium shading, shadows and detail" % (i + 1))
	check(probe._phase_label(0) == probe._phase_label(5) and probe._phase_label(1) == probe._phase_label(4) and probe._phase_label(2) == probe._phase_label(3), "feature order is balanced around the run midpoint")
	check(probe._mode() == "medium_ablation", "feature probes cannot masquerade as regular quality results")
	var reports: Array[Dictionary] = []
	probe.completed.connect(func(report): reports.append(report))
	var elapsed := 0.0
	while reports.is_empty() and elapsed < 450.0:
		await physics_frame
		elapsed += 1.0 / 60.0
	check(not reports.is_empty(), "real-game Medium probe completes three laps")
	if not reports.is_empty():
		var report: Dictionary = reports[0]
		check(report.valid and report.results.size() == 6, "all six Medium feature samples are valid")
		var correct := true
		for i in report.results.size():
			var sample: Dictionary = report.results[i]
			correct = correct and sample.quality == "medium" and sample.feature_profile == probe._phase_label(i) and sample.msaa_samples == [2, 0, 2, 2, 0, 2][i]
			var actual_pixels: int = sample.render_size_estimate[0] * sample.render_size_estimate[1]
			var expected_pixels: int = [1200000, 1200000, 900000, 900000, 1200000, 1200000][i]
			correct = correct and abs(actual_pixels - expected_pixels) < 5000
		check(correct, "report retains actual Medium quality, feature labels and AA settings")
	# A feature change inside a window must invalidate it even if the
	# quality enum itself stays Medium.
	var sampler: Node = load("res://scripts/benchmark/bench.gd").new()
	sampler.context = probe.context
	sampler.seconds = 1.0
	sampler.publish_result = false
	var changed: Array[Dictionary] = []
	sampler.completed.connect(func(result): changed.append(result))
	scene.add_child(sampler)
	for i in 4:
		await physics_frame
	root.msaa_3d = Viewport.MSAA_DISABLED
	for i in 120:
		if not changed.is_empty():
			break
		await physics_frame
	check(not changed.is_empty() and not changed[0].valid and changed[0].render_config_changed, "a mid-sample AA change invalidates a Medium window")
	scene.free()
	await process_frame
	await process_frame
	OS.set_environment("KW_QUERY", "")
	print("medium checks: %d failures" % failures)
	quit(1 if failures else 0)
