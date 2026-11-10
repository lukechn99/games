class_name QualityBench
extends Node
## ?autodrive&bench=10&benchqualities: two rounds in one continuous race.
## Samples cover different track sections; they are not matched A/B workloads.

const SETTLE_SECONDS := 2.0
const QUALITIES := [Controls.Quality.LOW, Controls.Quality.MEDIUM, Controls.Quality.HIGH,
	Controls.Quality.LOW, Controls.Quality.MEDIUM, Controls.Quality.HIGH]

var race: Node
var seconds := 10.0
var _index := 0
var _settle_started_us := 0
var _sample: Bench
var _results: Array[Dictionary] = []
var _label: Label
var _started := false
var _done := false
var _interruptions_start := 0
var _viewport_start := Vector2i.ZERO
var _resized := false
var _unexpected_quality := false


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
	Controls.set_quality(Controls.Quality.LOW, false)


func _process(_delta: float) -> void:
	if _done or not race.get("_racing"):
		return
	_label.size.x = minf(760.0, get_viewport().size.x - 24.0)
	if not _started:
		_started = true
		_interruptions_start = _interruptions()
		_viewport_start = get_viewport().size
	_resized = _resized or get_viewport().size != _viewport_start
	_unexpected_quality = _unexpected_quality or Controls.quality != QUALITIES[_index]
	var name := "%s round %d" % [["Low", "Medium", "High"][QUALITIES[_index]], _index / 3 + 1]
	if _sample == null:
		if _settle_started_us == 0:
			_settle_started_us = Time.get_ticks_usec()
		var elapsed := (Time.get_ticks_usec() - _settle_started_us) / 1000000.0
		_label.text = _summary() + "\n%s: settling %.1f / %.1f s" % [name, elapsed, SETTLE_SECONDS]
		if elapsed >= SETTLE_SECONDS:
			_sample = Bench.new()
			_sample.race = race
			_sample.seconds = seconds
			_sample.publish_result = false
			_sample.use_wall_duration = true
			_sample.completed.connect(_on_sample_completed)
			add_child(_sample)
	else:
		var elapsed := (Time.get_ticks_msec() - _sample._wall0) / 1000.0 if _sample._frames > 0 else 0.0
		_label.text = _summary() + "\n%s: sampling %.0f / %.0f s" % [name, elapsed, seconds]


func _on_sample_completed(result: Dictionary) -> void:
	result["sampling_mode"] = "quality_sweep"
	result["round"] = _index / 3 + 1
	result["phase"] = _index + 1
	result["page_to_sample_start_ms"] = result.startup_to_green_ms
	result.erase("startup_to_green_ms")
	_results.append(result)
	_sample.queue_free()
	_sample = null
	_index += 1
	_settle_started_us = 0
	if _index < QUALITIES.size():
		Controls.set_quality(QUALITIES[_index], false)
		return
	_done = true
	var valid := not _resized and not _unexpected_quality and _interruptions() == _interruptions_start and _results.all(func(r): return r.valid)
	var out := {"schema": 3, "mode": "quality_sweep", "track": race.track.layout, "rounds": 2,
		"requested_seconds_per_sample": seconds, "settle_seconds": SETTLE_SECONDS,
		"valid": valid, "partial": _results.any(func(r): return r.partial),
		"different_track_sections": true, "results": _results}
	var json := JSON.stringify(out)
	print("[bench] ", json)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__bench = " + json + ";", true)
	_label.text = _summary() + "\n" + ("INVALID: interrupted, resized or quality changed" if not valid else "PARTIAL run" if out.partial else "Complete samples") + "\nDifferent track sections; not a matched quality comparison."


func _summary() -> String:
	var text := "bench %s — 2 rounds, %.0f s per sample" % [race.track.layout, seconds]
	for r in _results:
		var stats: Dictionary = r.wall_frame_stats
		text += "\n%d %s: %.1f fps | p95 %.0f, p99 %.0f ms | %d draws%s" % [
			r.round, String(r.quality).capitalize(), stats.fps, stats.p95, stats.p99, r.draws,
			" INVALID" if not r.valid else " PARTIAL" if r.partial else ""]
	return text


func _interruptions() -> int:
	if not OS.has_feature("web"):
		return 0
	return int(JavaScriptBridge.eval("(window.racingMobile && window.racingMobile.interruptions) || 0", true))
