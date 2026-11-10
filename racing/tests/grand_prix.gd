extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	print("  ok   " if ok else "  FAIL ", message)
	if not ok:
		failures += 1

func _cup() -> Dictionary:
	return {"tracks": ["meadow", "mine", "frost"], "points": {"a": 42, "b": 39}, "results": [
		{"track": "meadow", "finish": {"a": 61.0, "b": 60.0}, "places": {"a": 2, "b": 1}, "points": {"a": 12, "b": 15}, "laps": {"a": [20.0, 20.0, 21.0], "b": [19.0, 20.0, 21.0]}},
		{"track": "mine", "finish": {"a": 70.0, "b": 75.0}, "places": {"a": 1, "b": 2}, "points": {"a": 15, "b": 12}, "laps": {"a": [22.0, 23.0, 25.0], "b": [24.0, 25.0, 26.0]}},
		{"track": "frost", "finish": {"a": 51.0, "b": 52.0}, "places": {"a": 1, "b": 2}, "points": {"a": 15, "b": 12}, "laps": {"a": [16.0, 17.0, 18.0], "b": [17.0, 17.0, 18.0]}},
	]}

func _run() -> void:
	var cup := _cup()
	var summary := GrandPrixSummary.build(cup, "a", func(id): return "Racer " + id)
	check(summary.headers == ["Meadow Loop", "Mining Mountain", "Frosty Pass"], "all three track headers are retained")
	check(summary.rows[0].you and summary.rows[0].points == 42 and is_equal_approx(summary.rows[0].total_time, 182.0), "overall points and race time cover all three tracks")
	check(summary.rows[0].tracks[0].best == 20.0 and summary.rows[0].tracks[1].best == 22.0 and summary.rows[0].tracks[2].best == 16.0, "best laps are per track")
	var dnf := cup.duplicate(true)
	dnf.results[1].finish.erase("b")
	dnf.results[1].laps.erase("b")
	dnf.results[1].places.erase("b")
	dnf.results[1].points.b = 0
	var incomplete := GrandPrixSummary.build(dnf, "a", func(id): return id)
	check(incomplete.rows[1].finished == 2 and incomplete.rows[1].total_time < 0.0 and incomplete.rows[1].tracks[1].time < 0.0, "DNF does not create a fake time or a partial aggregate total")
	var legacy := cup.duplicate(true)
	legacy.erase("results")
	var unavailable := GrandPrixSummary.build(legacy, "a", func(id): return id)
	check(not unavailable.rows[0].tracks[0].available and unavailable.rows[0].known == 0, "older rooms show missing history as unavailable, not DNF")
	var screen := ResultsScreen.new()
	root.add_child(screen)
	screen.show_results(3, [1.0, 2.0, 3.0], [], true, "", "Grand Prix  final standings", [], "Race again", summary)
	await process_frame
	await process_frame
	check(screen._title.text == "1st in the Grand Prix!", "final heading uses cup place instead of the last track's place")
	check(screen._history.get_child_count() == 15 and not screen._body.visible, "final grid shows every track instead of only the last race")
	# Eight-racer results scroll vertically instead of shrinking every row.
	var large := summary.duplicate(true)
	large.rows = []
	for i in 8:
		var row: Dictionary = summary.rows[0].duplicate(true)
		row.name = "Racer %d" % (i + 1)
		row.you = i == 0
		row.place = i + 1
		large.rows.append(row)
	screen.show_results(1, [], [], true, "", "Grand Prix  final standings", [], "Race again", large)
	await process_frame
	await process_frame
	check(screen._history_scroll.custom_minimum_size.y < screen._history.get_combined_minimum_size().y, "eight-racer history has a bounded scrolling area")
	var first_cell := screen._history.get_child(0).get_instance_id()
	screen._history_scroll.scroll_vertical = 30
	var scroll_before := screen._history_scroll.scroll_vertical
	screen.show_results(3, [], [], true, "", "Grand Prix  final standings", [], "Race again", large)
	check(screen._history.get_child(0).get_instance_id() == first_cell and screen._history_scroll.scroll_vertical == scroll_before, "unchanged room refresh preserves result controls and scroll position")
	screen.show_results(2, [20.0, 21.0, 22.0], [], true, "")
	check(not screen._history_scroll.visible and screen._body.visible, "single-race results retain their normal layout")
	screen.free()
	await process_frame
	print("Grand Prix checks: %d failures" % failures)
	quit(1 if failures else 0)
