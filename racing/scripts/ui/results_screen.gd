class_name ResultsScreen
extends CanvasLayer
## After you cross the line: your place, your lap times and the standings,
## filled in live as the others finish. A computer drives your kart on
## round the track behind it.

signal again_pressed

const GOLD := Color(1.0, 0.84, 0.2)
const SILVER := Color(0.86, 0.9, 0.96)
const BRONZE := Color(0.95, 0.62, 0.35)
const INK := Color(0.08, 0.1, 0.18)
const MUTED := Color(0.72, 0.76, 0.86)

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _total: Label
var _laps: VBoxContainer
var _table: VBoxContainer
var _again: Button
var _note: Label
var _body: BoxContainer


func _ready() -> void:
	layer = 7
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.04, 0.09, 0.45)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.92)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = _label(v, 52)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 12)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_total = _label(v, 20, MUTED)
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 34)
	v.add_child(_body)
	var left := VBoxContainer.new()
	_body.add_child(left)
	_label(left, 17, MUTED).text = "Your laps"
	_laps = VBoxContainer.new()
	left.add_child(_laps)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(right)
	_label(right, 17, MUTED).text = "Standings"
	_table = VBoxContainer.new()
	right.add_child(_table)
	_again = Button.new()
	_again.text = "Race again"
	_again.custom_minimum_size = Vector2(0, 50)
	_again.add_theme_font_size_override("font_size", 20)
	_again.pressed.connect(func(): again_pressed.emit())
	for st in ["normal", "hover", "pressed", "focus"]:
		var bs := StyleBoxFlat.new()
		bs.bg_color = GOLD.darkened(0.15 if st == "pressed" else 0.0).lightened(0.08 if st == "hover" else 0.0)
		bs.set_corner_radius_all(12)
		_again.add_theme_stylebox_override(st, bs)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_again.add_theme_color_override(st, INK)
	v.add_child(_again)
	_note = _label(v, 16, MUTED)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(parent: Control, px: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


static func clock(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


## place: yours. laps: your lap times. rows: [place, name, time or -1 (still
## racing) or -2 (didn't finish), is_you]. can_again: show the button; note
## goes under it.
func show_results(place: int, laps: Array, rows: Array, can_again: bool, note: String) -> void:
	visible = true
	_title.text = "%d%s place!" % [place, _ordinal(place)]
	_title.add_theme_color_override("font_color", [GOLD, SILVER, BRONZE][place - 1] if place <= 3 else Color.WHITE)
	var total := 0.0
	for t in laps:
		total += float(t)
	_total.text = "Total  " + clock(total)
	var best := 1e9
	for t in laps:
		best = minf(best, float(t))
	_fill(_laps, laps.size())
	for i in laps.size():
		var l: Label = _laps.get_child(i)
		var t := float(laps[i])
		l.text = "Lap %d   %s%s" % [i + 1, clock(t), "   best" if t == best and laps.size() > 1 else ""]
		l.add_theme_color_override("font_color", GOLD if t == best and laps.size() > 1 else Color.WHITE)
	_fill(_table, rows.size())
	for i in rows.size():
		var r: Array = rows[i]
		var l: Label = _table.get_child(i)
		var t := float(r[2])
		var when := clock(t) if t >= 0.0 else ("racing…" if t > -1.5 else "didn't finish")
		l.text = "%d.  %s   %s" % [int(r[0]), r[1], when]
		l.add_theme_color_override("font_color", GOLD if bool(r[3]) else (Color.WHITE if t >= 0.0 else MUTED))
	_again.visible = can_again
	_note.text = note
	_note.visible = note != ""


func hide_results() -> void:
	visible = false


func _fill(box: VBoxContainer, n: int) -> void:
	while box.get_child_count() < n:
		_label(box, 20)
	while box.get_child_count() > n:
		var c := box.get_child(box.get_child_count() - 1)
		box.remove_child(c)
		c.queue_free()


func _ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "th"
	return {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")


func _process(_delta: float) -> void:
	if not visible:
		return
	var vs := get_viewport().get_visible_rect().size
	_dim.position = Vector2.ZERO
	_dim.size = vs
	# Side by side when there's room, else stacked (a phone held upright).
	var want_v := vs.x < 560.0
	if want_v != (_body is VBoxContainer):
		var nb: BoxContainer = VBoxContainer.new() if want_v else HBoxContainer.new()
		nb.add_theme_constant_override("separation", 14 if want_v else 34)
		var parent := _body.get_parent()
		parent.add_child(nb)
		parent.move_child(nb, _body.get_index())
		for c in _body.get_children():
			c.reparent(nb)
		_body.queue_free()
		_body = nb
	var s := _panel.get_combined_minimum_size()
	# Shrink to fit short screens (a phone on its side).
	var k := minf(1.0, minf((vs.y - 16.0) / s.y, (vs.x - 16.0) / s.x))
	_panel.scale = Vector2.ONE * k
	_panel.size = s
	_panel.position = (vs - s * k) * 0.5
