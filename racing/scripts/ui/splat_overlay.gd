class_name SplatOverlay
extends Control
## Coal dust splattered over the screen after driving through a coal pile.
## The blotches drift and fade as the dust blows away.

const LIFE := 2.6

var _blobs: Array[Dictionary] = []
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func splat() -> void:
	_t = LIFE
	_blobs.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 14:
		var c := Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.15, 0.85))
		var dots := []
		for k in rng.randi_range(3, 7):
			dots.append([Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.06, rng.randf_range(0.02, 0.07)])
		_blobs.append({"c": c, "dots": dots, "drift": Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(0.02, 0.1))})


func _process(delta: float) -> void:
	if _t <= 0.0:
		return
	_t -= delta
	queue_redraw()


func _draw() -> void:
	if _t <= 0.0:
		return
	var s := size
	var a := clampf(_t / LIFE, 0.0, 1.0)
	var age := LIFE - _t
	for b in _blobs:
		var c: Vector2 = b["c"] + b["drift"] * age
		for d in b["dots"]:
			var r: float = d[1] * minf(s.x, s.y) * (1.0 + age * 0.15)
			draw_circle((c + d[0]) * s, r, Color(0.06, 0.05, 0.07, 0.75 * a))
