class_name TouchControls
extends Control
## On-screen controls for phones (design doc 10.3):
## - Left: a joystick for steering (hidden when steering by tilt). It appears
##   wherever your thumb lands in the left part of the screen.
## - Right: two equal buttons, brake and gas, with icons instead of words.
## - Above them: the ability button, showing the held item's icon.
## - Steering by tilt: gas bottom-right, brake bottom-left, item above gas.
## Handles several fingers at once and writes into Controls.touch.

var buttons := {}            # "brake" | "gas" | "item" -> Rect2
var held_item := ""          # item id, drawn as an icon
var drift_stage := 0
var _fingers := {}           # touch index -> button name or "stick"
var _stick_finger := -1
var _stick_base := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _stick_home := Vector2.ZERO
var _stick_radius := 80.0
var _u := 90.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	visibility_changed.connect(_visibility_changed)
	Controls.inputs_released.connect(_release_fingers)
	_layout()


func _layout() -> void:
	Controls.release_inputs()
	var s := size
	_u = clampf(minf(s.x, s.y) * 0.2, 64.0, 140.0)   # button size, at least 64 px
	var pad := _u * 0.28
	var bottom := s.y - pad - _u
	buttons.clear()
	buttons["gas"] = Rect2(s.x - pad - _u, bottom, _u, _u)
	if _stick_enabled():
		buttons["brake"] = Rect2(s.x - pad * 2.0 - _u * 2.0, bottom, _u, _u)
		var mid: float = ((buttons["gas"] as Rect2).get_center().x + (buttons["brake"] as Rect2).get_center().x) * 0.5
		buttons["item"] = Rect2(mid - _u * 0.55, bottom - pad - _u * 1.1, _u * 1.1, _u * 1.1)
	else:
		# Steering by tilt: no joystick, so it's like pedals. Gas in the
		# bottom-right corner, brake in the bottom-left, the item above gas.
		buttons["brake"] = Rect2(pad, bottom, _u, _u)
		buttons["item"] = Rect2(s.x - pad - _u * 1.05, bottom - pad - _u * 1.1, _u * 1.1, _u * 1.1)
	_stick_radius = _u * 0.85
	_stick_home = Vector2(pad + _stick_radius + _u * 0.2, s.y - pad - _stick_radius)
	if _stick_finger < 0:
		_stick_base = _stick_home
		_stick_knob = _stick_home
	queue_redraw()


func _stick_enabled() -> bool:
	return Controls.scheme != Controls.Scheme.TILT


func _in_stick_zone(p: Vector2) -> bool:
	return p.x < size.x * 0.45 and p.y > size.y * 0.3


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or Controls.suspended:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.canceled:
			Controls.release_inputs()
			return
		if t.pressed:
			var b := _button_at(t.position)
			if b != "":
				_fingers[t.index] = b
				get_viewport().set_input_as_handled()
			elif _stick_enabled() and _stick_finger < 0 and _in_stick_zone(t.position):
				_stick_finger = t.index
				_stick_base = t.position
				_stick_knob = t.position
				_fingers[t.index] = "stick"
				get_viewport().set_input_as_handled()
		else:
			if t.index == _stick_finger:
				_stick_finger = -1
				_stick_base = _stick_home
				_stick_knob = _stick_home
			_fingers.erase(t.index)
		_sync()

	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			var off := d.position - _stick_base
			if off.length() > _stick_radius:
				# Let the base follow a thumb that drifts too far.
				_stick_base += off.normalized() * (off.length() - _stick_radius)
				off = off.normalized() * _stick_radius
			_stick_knob = _stick_base + off
			_sync()


func _release_fingers() -> void:
	_fingers.clear()
	_stick_finger = -1
	_stick_base = _stick_home
	_stick_knob = _stick_home
	queue_redraw()


func _visibility_changed() -> void:
	if not is_visible_in_tree():
		Controls.release_inputs()


func _exit_tree() -> void:
	Controls.release_inputs()


func _button_at(p: Vector2) -> String:
	for name in buttons:
		if (buttons[name] as Rect2).grow(14.0).has_point(p):
			return name
	return ""


func _sync() -> void:
	for k in ["brake", "gas", "item"]:
		Controls.touch[k] = false
	for i in _fingers:
		if _fingers[i] != "stick":
			Controls.touch[_fingers[i]] = true
	var x := (_stick_knob.x - _stick_base.x) / _stick_radius
	Controls.touch["steer"] = 0.0 if absf(x) < 0.12 else clampf((absf(x) - 0.12) / 0.88, 0.0, 1.0) * signf(x)
	queue_redraw()


func _draw() -> void:
	var white := Color(1, 1, 1, 0.92)
	if _stick_enabled():
		var active := _stick_finger >= 0
		draw_circle(_stick_base, _stick_radius, Color(1, 1, 1, 0.16 if active else 0.1))
		draw_arc(_stick_base, _stick_radius, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0, true)
		draw_circle(_stick_knob, _u * 0.36, Color(1, 1, 1, 0.55 if active else 0.35))
		# Little left/right hints on the ring.
		for side in [-1.0, 1.0]:
			var tip := _stick_base + Vector2(side * (_stick_radius - 14.0), 0)
			_triangle(tip, Vector2(side, 0), 9.0, Color(1, 1, 1, 0.6))
	for name in buttons:
		var r: Rect2 = buttons[name]
		var down: bool = Controls.touch.get(name, false)
		var fill := Color(1, 1, 1, 0.4 if down else 0.18)
		if name == "brake" and drift_stage > 0:
			fill = [Color(1, 1, 1, 0.3), Color(0.4, 0.75, 1.0, 0.5), Color(1.0, 0.6, 0.2, 0.55), Color(0.85, 0.4, 1.0, 0.6)][drift_stage]
		var c := r.get_center()
		var radius := r.size.x * 0.5
		draw_circle(c, radius, fill)
		draw_arc(c, radius, 0, TAU, 48, Color(1, 1, 1, 0.55), 3.0, true)
		var k := radius * 0.28
		match name:
			"gas":     # two chevrons pointing up: go
				_chevron(c + Vector2(0, -k * 0.55), -1.0, k, white)
				_chevron(c + Vector2(0, k * 0.55), -1.0, k, white)
			"brake":   # two chevrons pointing down: slow down
				_chevron(c + Vector2(0, -k * 0.55), 1.0, k, white)
				_chevron(c + Vector2(0, k * 0.55), 1.0, k, white)
			"item":
				_item_icon(c, radius * 0.55, held_item)


func _triangle(tip: Vector2, dir: Vector2, s: float, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * s * 1.4 + side * s, tip - dir * s * 1.4 - side * s]), col)


## A "^" (dir -1) or "v" (dir 1) chevron.
func _chevron(c: Vector2, dir: float, k: float, col: Color) -> void:
	var w := k * 1.1
	draw_polyline(PackedVector2Array([c + Vector2(-w, -dir * k * 0.5), c + Vector2(0, dir * k * 0.5), c + Vector2(w, -dir * k * 0.5)]), col, k * 0.38, true)


## Icons for abilities (design doc 6). Empty: a dashed ring, waiting for a crate.
func _item_icon(c: Vector2, s: float, item: String) -> void:
	draw_item_icon(self, c, s, item)


static func draw_item_icon(ci: CanvasItem, c: Vector2, s: float, item: String) -> void:
	match item:
		"honey":
			ci.draw_circle(c + Vector2(0, s * 0.15), s * 0.75, Color(1.0, 0.72, 0.15))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.5, -s * 0.85), Vector2(s, s * 0.35)), Color(0.85, 0.55, 0.2))
			ci.draw_circle(c + Vector2(s * 0.25, s * 0.05), s * 0.15, Color(1, 0.9, 0.6))
		"tumbleweed":
			for i in 7:
				var a := TAU * i / 7.0
				ci.draw_arc(c + Vector2(cos(a), sin(a)) * s * 0.25, s * 0.55, a, a + PI * 1.3, 12, Color(0.85, 0.68, 0.4), 3.0, true)
		"snowball":
			ci.draw_circle(c, s * 0.8, Color(0.95, 0.97, 1.0))
			ci.draw_arc(c, s * 0.8, PI * 0.1, PI * 0.9, 12, Color(0.7, 0.8, 0.95), 4.0, true)
		_:
			for i in 12:
				var a := TAU * i / 12.0
				ci.draw_arc(c, s * 0.8, a, a + TAU / 24.0, 4, Color(1, 1, 1, 0.55), 3.0, true)
