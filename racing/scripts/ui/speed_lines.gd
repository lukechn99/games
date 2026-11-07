class_name SpeedLines
extends Control
## Streaks rushing in from the edges of the screen when you're flat out or
## boosting, as in Mario Kart (design doc 9.4). Plain 2D lines, so it costs
## next to nothing on a phone.

var kart: Kart
var _seeds: Array[Vector3] = []   # angle, length, speed of each streak
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 34:
		_seeds.append(Vector3(rng.randf() * TAU, rng.randf_range(0.12, 0.3), rng.randf_range(0.8, 1.6)))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if kart == null:
		return
	var fast := clampf((absf(kart.speed) / maxf(kart.top_speed(), 1.0) - 0.82) / 0.18, 0.0, 1.0)
	var amount := maxf(fast * 0.55, 1.0 if kart.boost_time > 0.0 else 0.0)
	if amount <= 0.01:
		return
	var c := size * 0.5
	var reach := size.length() * 0.5
	for s in _seeds:
		# Each streak slides inward and starts again, at its own pace.
		var phase := fmod(_t * s.z * 2.2 + s.x, 1.0)
		var dir := Vector2(cos(s.x), sin(s.x))
		var outer := 1.05 - phase * 0.25
		var inner := outer - s.y
		var a := (1.0 - phase) * 0.55 * amount
		draw_line(c + dir * reach * inner, c + dir * reach * outer, Color(1, 1, 1, a), 2.5 + 2.0 * amount, true)
