class_name PerfOverlay
extends Label
## ?perf: frame rate, frame time spikes, process time and what's drawn, on
## screen and in the browser console every 2 seconds (design doc 14).

var _t := 0.0
var _frames := 0
var _worst := 0.0
var _previous_us := 0


func _ready() -> void:
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	position = Vector2(12, 90)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _previous_us == 0:
		_previous_us = now
		return
	var delta := (now - _previous_us) / 1000000.0
	_previous_us = now
	_t += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if delta > 0.05:
		print("[perf] hitch %.0f ms at %.1f s, draws %d" % [delta * 1000.0, Time.get_ticks_msec() / 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _t < 2.0:
		return
	var p := Performance
	var line := "fps %.0f  worst %.0f ms  process %.1f ms  physics %.1f ms  draws %d  objects %d  tris %dk" % [
		_frames / _t, _worst * 1000.0,
		p.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		p.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		p.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		p.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		int(p.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]
	text = line
	print("[perf] ", line)
	_t = 0.0
	_frames = 0
	_worst = 0.0
