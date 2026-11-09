extends SceneTree
## Actual scene transitions, including terrain clearance and the chase-camera
## handoff. The trace also supports browser capture review via ?introtrace.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	for layout in ["meadow", "mine", "frost"]:
		OS.set_environment("KW_QUERY", "autodrive&intro&introtrace&track=" + layout)
		var race = load("res://scripts/main.gd").new()
		root.add_child(race)
		for i in 900:
			await process_frame
			if not race.intro_report.is_empty():
				break
		if race.intro_report.is_empty():
			printerr("FAIL intro timed out: ", layout)
			failures += 1
		else:
			var report: Dictionary = race.intro_report
			var samples: Array = report.samples
			var penultimate: Dictionary = samples[-2]
			for sample: Dictionary in samples:
				if sample.t < 0.9999:
					penultimate = sample
			var final: Dictionary = samples[-1]
			var ok: bool = report.handoff_jump_m < 0.001 and final.rest_distance < 0.001 and penultimate.rest_distance < 0.1
			print("%s %s intro: handoff %.4f m, penultimate %.4f m, final %.4f m" % ["PASS" if ok else "FAIL", layout, report.handoff_jump_m, penultimate.rest_distance, final.rest_distance])
			if not ok:
				failures += 1
		race.queue_free()
		await process_frame
	print("intro checks: %d failures" % failures)
	quit(1 if failures else 0)
