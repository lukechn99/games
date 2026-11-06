class_name TouchControls
extends Control
## On-screen buttons for phones (design doc 10.3): brake bottom-left (plus
## left/right when steering by touch), drift and item bottom-right. Handles
## several fingers at once and writes straight into Controls.touch.

var buttons := {}        # name -> Rect2, laid out in _layout()
var _fingers := {}       # touch index -> button name
var held_item := ""      # shown on the item button
var drift_stage := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var s := size
	var u := clampf(minf(s.x, s.y) * 0.17, 64.0, 130.0)   # button size, at least 64 px
	var pad := u * 0.3
	var bottom := s.y - pad - u
	buttons.clear()
	var touch_steer := Controls.scheme != Controls.Scheme.TILT
	if touch_steer:
		buttons["left"] = Rect2(pad, bottom, u * 1.1, u)
		buttons["right"] = Rect2(pad * 2.0 + u * 1.1, bottom, u * 1.1, u)
		buttons["brake"] = Rect2(s.x * 0.5 - u * 0.6, bottom + u * 0.15, u * 1.2, u * 0.85)
	else:
		buttons["brake"] = Rect2(pad, bottom, u * 1.3, u)
	buttons["item"] = Rect2(s.x - pad - u * 1.2, bottom - u * 0.35, u * 1.2, u * 1.35)
	buttons["drift"] = Rect2(s.x - pad * 2.0 - u * 2.4, bottom, u * 1.15, u)
	if not Controls.uses_auto_gas():
		buttons["gas"] = Rect2(s.x - pad - u * 1.2, bottom - u * 1.6, u * 1.2, u)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var b := _button_at(t.position)
			if b != "":
				_fingers[t.index] = b
				get_viewport().set_input_as_handled()
		else:
			_fingers.erase(t.index)
		_sync()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _fingers.has(d.index):
			var b := _button_at(d.position)
			# Sliding between left and right works without lifting.
			if b != "" and b != _fingers[d.index] and (b == "left" or b == "right"):
				_fingers[d.index] = b
				_sync()


func _button_at(p: Vector2) -> String:
	for name in buttons:
		if (buttons[name] as Rect2).grow(12.0).has_point(p):
			return name
	return ""


func _sync() -> void:
	for k in Controls.touch:
		Controls.touch[k] = false
	for i in _fingers:
		Controls.touch[_fingers[i]] = true
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var labels := {"left": "◀", "right": "▶", "brake": "BRAKE", "drift": "DRIFT", "item": "ITEM", "gas": "GAS"}
	for name in buttons:
		var r: Rect2 = buttons[name]
		var down: bool = Controls.touch.get(name, false)
		var fill := Color(1, 1, 1, 0.38 if down else 0.18)
		if name == "drift" and drift_stage > 0:
			fill = [Color(1, 1, 1, 0.3), Color(0.4, 0.75, 1.0, 0.45), Color(1.0, 0.6, 0.2, 0.5), Color(0.85, 0.4, 1.0, 0.55)][drift_stage]
		draw_style_box(_box(fill), r)
		if name == "left" or name == "right":
			var c := r.get_center()
			var w := r.size.y * 0.22 * (-1.0 if name == "left" else 1.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(w, 0), c + Vector2(-w, -absf(w)), c + Vector2(-w, absf(w))]), Color(1, 1, 1, 0.92))
			continue
		var text: String = labels[name]
		if name == "item" and held_item != "":
			text = held_item
		var fs := int(r.size.y * (0.42 if text.length() <= 1 else 0.24))
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, r.get_center() + Vector2(-ts.x * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92))


func _box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = Color(1, 1, 1, 0.55)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	return sb
