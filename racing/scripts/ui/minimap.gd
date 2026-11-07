class_name Minimap
extends Control
## Top-right minimap (design doc 10.3): the track outline from the racing line
## and every kart as a numbered dot. Yours is bigger, with a direction arrow.

var track: Track
var karts: Array[Kart] = []
var me: Kart
var _outline := PackedVector2Array()
var _min := Vector2.ZERO
var _max := Vector2.ONE


func setup(t: Track, all: Array[Kart], player: Kart) -> void:
	track = t
	karts = all
	me = player
	_outline = t.outline(160)
	_min = _outline[0]
	_max = _outline[0]
	for p in _outline:
		_min = _min.min(p)
		_max = _max.max(p)


func _process(_delta: float) -> void:
	queue_redraw()


func _to_map(p: Vector2) -> Vector2:
	var span := _max - _min
	var pad := 10.0
	var scale_f := minf((size.x - pad * 2) / span.x, (size.y - pad * 2) / span.y)
	var used := span * scale_f
	var origin := (size - used) * 0.5
	return origin + (p - _min) * scale_f


func _draw() -> void:
	if track == null:
		return
	# No panel: just a thick, see-through white ribbon of the track, as in
	# Mario Kart, so the world shows through behind it.
	var pts := PackedVector2Array()
	for p in _outline:
		pts.append(_to_map(p))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.1, 0.12, 0.2, 0.28), 15.0, true)
	draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.62), 11.0, true)
	var start := _to_map(_outline[0])
	draw_circle(start, 4.0, Color(0.1, 0.1, 0.1))
	var font := get_theme_default_font()
	for k in karts:
		if k == me:
			continue
		var p := _to_map(Vector2(k.global_position.x, k.global_position.z))
		draw_circle(p, 8.0, Color(1, 1, 1))
		draw_circle(p, 6.0, k.chassis["color"])
		draw_string(font, p + Vector2(7, 4), str(k.number), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 0.1, 0.12))
	if me:
		var p := _to_map(Vector2(me.global_position.x, me.global_position.z))
		var f := -me.global_transform.basis.z
		var dir := Vector2(f.x, f.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_circle(p, 11.0, Color(1, 1, 1))
		draw_circle(p, 9.0, Color(0.1, 0.12, 0.2))
		draw_colored_polygon(PackedVector2Array([p + dir * 8.0, p - dir * 4.5 + side * 5.5, p - dir * 4.5 - side * 5.5]), me.chassis["color"].lightened(0.25))


func _panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.28)
	sb.set_corner_radius_all(14)
	return sb
