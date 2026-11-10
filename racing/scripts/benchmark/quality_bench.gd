class_name QualityBench
extends Node
## Three laps, distance-gated halves: L/M, H/H, M/L. The controller owns
## scheduling and validation; Bench owns measurement and Route owns steering.

signal completed(report: Dictionary)

const ORDER := [Controls.Quality.LOW, Controls.Quality.MEDIUM, Controls.Quality.HIGH,
	Controls.Quality.HIGH, Controls.Quality.MEDIUM, Controls.Quality.LOW]
var context: BenchmarkContext
var settle_distance_m := 50.0
var _phase := -1
var _sample: Bench
var _results: Array[Dictionary] = []
var _label: Label
var _done := false
var route: BenchmarkRoute
var _interruptions_start := 0
var _viewport_start := Vector2i.ZERO
var _errors: Array[String] = []


static func phase_at(lap: int, offset: float, length: float) -> int:
	if lap < 1:
		return -1
	return mini(6, (lap - 1) * 2 + (1 if offset >= length * 0.5 else 0))


func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(12, 120)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	layer.add_child(_label)
	_apply_phase(0)


func _process(_delta: float) -> void:
	if _done or not context.is_running():
		return
	_label.size.x = minf(850.0, get_viewport().size.x - 24.0)
	var offset: float = context.track.offset_of(context.player_kart.global_position)
	var next := phase_at(context.player_kart.lap, offset, context.track.length)
	if next < 0:
		_label.text = "bench: approaching the start line"
		return
	if _phase >= 0:
		if get_viewport().size != _viewport_start:
			_fail("viewport resized")
		if _interruptions() != _interruptions_start:
			_fail("run interrupted")
		if Controls.quality != _quality_for_phase(_phase):
			_fail("quality changed outside the schedule")
	if next != _phase:
		if next != _phase + 1:
			_fail("missed or reversed a half-track boundary")
		if _sample != null:
			if _sample.has_samples():
				_sample.finish_window()
			else:
				_fail("half ended before a usable sample")
				_sample.queue_free()
				_sample = null
		if next >= 6 or not _errors.is_empty():
			_finish()
			return
		_phase = next
		if _phase == 0:
			_interruptions_start = _interruptions()
			_viewport_start = get_viewport().size
		_apply_phase(_phase)
	if not route.errors.is_empty():
		_fail(route.errors[0])
	if not _errors.is_empty():
		_finish()
		return
	var sample_from: float = (_phase % 2) * context.track.length * 0.5 + settle_distance_m
	if _sample == null and offset >= sample_from:
		_sample = Bench.new()
		_sample.context = context
		_sample.publish_result = false
		_sample.external_window = true
		_sample.segment_from_m = sample_from
		_sample.segment_to_m = (_phase % 2 + 1) * context.track.length * 0.5
		_sample.wall_limit = 600.0
		_sample.completed.connect(_on_sample_completed)
		add_child(_sample)
	_label.text = _summary() + "\nLap %d half %d: %s (%s)" % [_phase / 2 + 1, _phase % 2 + 1,
		_phase_label(_phase), "settling" if _sample == null else "sampling"]


func _on_sample_completed(result: Dictionary) -> void:
	result["sampling_mode"] = _mode()
	result["feature_profile"] = _phase_label(_phase)
	result["route"] = route.route_name
	result["lap"] = _phase / 2 + 1
	result["half"] = _phase % 2 + 1
	result["phase"] = _phase + 1
	result["segment_from_m"] = (_phase % 2) * context.track.length * 0.5
	result["segment_to_m"] = (_phase % 2 + 1) * context.track.length * 0.5
	result["measured_from_m"] = result.segment_from_m + settle_distance_m
	result["page_to_sample_start_ms"] = result.startup_to_green_ms
	result.erase("startup_to_green_ms")
	result.erase("requested_seconds")
	_results.append(result)
	_sample.queue_free()
	_sample = null
	if result.partial:
		_fail("half-track sample timed out")
	elif not result.valid:
		_fail("sample rendering settings changed" if result.get("render_config_changed", false) else "sample interrupted or resized")


func _finish() -> void:
	_done = true
	if _sample != null:
		_sample.queue_free()
		_sample = null
	for lap in range(1, 4):
		if not route.valid_lap(lap):
			_fail("lap %d did not complete the required route" % lap)
	var valid := _errors.is_empty() and route.errors.is_empty() and _results.size() == 6 and _results.all(func(r): return r.valid and not r.partial)
	var order: Array[String] = []
	for i in 6:
		order.append(_phase_label(i))
	var out := {"schema": 4, "mode": _mode(), "track": context.track.layout,
		"order": order,
		"settle_distance_m": settle_distance_m, "valid": valid, "partial": _results.size() != 6,
		"route": route.route_name, "route_evidence": route.evidence, "errors": _errors + route.errors,
		"results": _results}
	var json := JSON.stringify(out)
	print("[bench] ", json)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__bench = " + json + ";", true)
	_label.text = _summary() + "\n" + ("Complete: fixed route on all three laps" if valid else "INVALID: " + "; ".join(out.errors))
	completed.emit(out)


func _summary() -> String:
	var text := "bench %s — %s, fixed %s route" % [context.track.layout, _report_name(), route.route_name]
	for r in _results:
		text += "\n" + _result_line(r)
	return text


func _quality_for_phase(index: int) -> int:
	return ORDER[index]


func _apply_phase(index: int) -> void:
	Controls.set_quality(_quality_for_phase(index) as Controls.Quality, false)


func _phase_label(index: int) -> String:
	return ["low", "medium", "high"][_quality_for_phase(index)]


func _mode() -> String:
	return "track_halves"


func _report_name() -> String:
	return "three laps"


func _result_line(r: Dictionary) -> String:
	return "Lap %d half %d %s: %.1f fps | p95 %.0f, p99 %.0f ms | %d draws" % [
		r.lap, r.half, String(r.quality).capitalize(), r.wall_frame_stats.fps,
		r.wall_frame_stats.p95, r.wall_frame_stats.p99, r.draws]


func _fail(reason: String) -> void:
	if _errors.size() < 8 and not _errors.has(reason):
		_errors.append(reason)


func _interruptions() -> int:
	if not OS.has_feature("web"):
		return 0
	return int(JavaScriptBridge.eval("(window.racingMobile && window.racingMobile.interruptions) || 0", true))
