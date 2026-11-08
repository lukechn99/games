class_name Hud
extends CanvasLayer
## Race HUD (design doc 10.3) and a "garage" panel for swapping parts and
## controls while we tune the karts. The real kart builder comes in M2.

signal parts_changed(chassis: String, tires: String, driver: String)
signal restart_requested

var race: Node
var touch: TouchControls
var minimap: Minimap
var _place: Label
var _speed: Label
var _lap: Label
var _center: Label
var _banner: Label
var _tilt: Label
var _garage: PanelContainer
var _tilt_button: Button
var _tilt_status: Label
var _choice := {"chassis": "frame", "tires": "slicks", "driver": "fox"}
var _group_buttons := {}
var _banner_time := 0.0
var _root: Control
var _garage_btn: Button


func _ready() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root

	touch = TouchControls.new()
	root.add_child(touch)
	touch.set_anchors_preset(Control.PRESET_TOP_LEFT)
	touch.visible = Controls.is_touch_device() or _query_has("touch")

	_item_box = ItemBox.new()
	_item_box.size = Vector2(92, 92)
	_item_box.position = Vector2(16, 14)
	_item_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_item_box)
	_place = _label(root, 64, Vector2(122, 2))
	_place.add_theme_constant_override("outline_size", 14)
	_speed = _label(root, 20, Vector2(128, 82))
	_lap = _label(root, 26, Vector2(0, 14))
	_lap.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lap.position = Vector2(-160, 14)
	_lap.size = Vector2(320, 40)
	_center = _label(root, 110, Vector2.ZERO)
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.size = Vector2(600, 140)
	_center.position = Vector2(-300, -150)
	_banner = _label(root, 34, Vector2.ZERO)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.size = Vector2(600, 50)
	_banner.position = Vector2(-300, 62)
	_tilt = _label(root, 18, Vector2.ZERO)
	_tilt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tilt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tilt.size = Vector2(300, 30)
	_tilt.position = Vector2(-150, -40)

	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.size = Vector2(230, 190)
	minimap.position = Vector2(-246, 8)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)

	var garage_btn := Button.new()
	_garage_btn = garage_btn
	garage_btn.text = "Garage"
	garage_btn.add_theme_font_size_override("font_size", 20)
	garage_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	garage_btn.position = Vector2(-120, 182)
	garage_btn.size = Vector2(104, 44)
	garage_btn.pressed.connect(func(): _garage.visible = not _garage.visible)
	root.add_child(garage_btn)
	_build_garage(root)
	if _query_has("perf"):
		root.add_child(PerfOverlay.new())


func _query_has(s: String) -> bool:
	return OS.has_feature("web") and str(JavaScriptBridge.eval("location.search", true)).contains(s)


func _label(parent: Control, size_px: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.12))
	l.add_theme_constant_override("outline_size", maxi(4, size_px / 6))
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_garage(root: Control) -> void:
	_garage = PanelContainer.new()
	_garage.set_anchors_preset(Control.PRESET_CENTER)
	_garage.custom_minimum_size = Vector2(620, 0)
	_garage.position = Vector2(-310, -250)
	_garage.visible = false
	root.add_child(_garage)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.16, 0.92)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_garage.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_garage.add_child(v)
	# Title row with a close (X) button in the top-right corner, where
	# people expect it. Escape closes the garage too.
	var top := HBoxContainer.new()
	v.add_child(top)
	_heading(top, "Garage")
	(top.get_child(0) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x := Button.new()
	x.custom_minimum_size = Vector2(48, 48)
	x.tooltip_text = "Close the garage"
	x.focus_mode = Control.FOCUS_NONE
	x.draw.connect(func():
		var c := x.size * 0.5
		var k := 10.0
		var col := Color(1, 1, 1, 0.95)
		x.draw_line(c + Vector2(-k, -k), c + Vector2(k, k), col, 3.5, true)
		x.draw_line(c + Vector2(k, -k), c + Vector2(-k, k), col, 3.5, true))
	x.pressed.connect(func(): _garage.visible = false)
	top.add_child(x)
	_choices(v, "Chassis", "chassis", Parts.CHASSIS)
	_choices(v, "Wheels", "tires", Parts.TIRES)
	_choices(v, "Driver", "driver", Parts.DRIVERS)

	_heading(v, "Steering", 20)
	var row := HBoxContainer.new()
	v.add_child(row)
	var touch_btn := _button(row, "Buttons")
	touch_btn.pressed.connect(func(): _set_scheme(Controls.Scheme.TOUCH_BUTTONS))
	_tilt_button = _button(row, "Steer by tilting")
	_tilt_button.pressed.connect(func(): _set_scheme(Controls.Scheme.TILT))
	_tilt_status = Label.new()
	_tilt_status.add_theme_font_size_override("font_size", 15)
	_tilt_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tilt_status.custom_minimum_size = Vector2(560, 0)
	v.add_child(_tilt_status)

	var row2 := HBoxContainer.new()
	v.add_child(row2)
	var shake := _button(row2, "Shake: full")
	shake.pressed.connect(func():
		Controls.shake_level = 0.5 if Controls.shake_level == 1.0 else (0.0 if Controls.shake_level == 0.5 else 1.0)
		shake.text = "Shake: " + {1.0: "full", 0.5: "gentle", 0.0: "off"}[Controls.shake_level])
	var gas := _button(row2, "Auto gas: off")
	gas.pressed.connect(func():
		Controls.auto_gas = not Controls.auto_gas
		gas.text = "Auto gas: " + ("on" if Controls.auto_gas else "off")
		touch._layout())
	var gfx := _button(row2, "Graphics: " + Controls.quality_name())
	# Low, then Medium, then High, then back to Low.
	gfx.pressed.connect(func(): Controls.set_quality(((Controls.quality + 1) % 3) as Controls.Quality))
	Controls.quality_changed.connect(func(): gfx.text = "Graphics: " + Controls.quality_name())
	var restart := _button(row2, "Restart race")
	restart.pressed.connect(func():
		_garage.visible = false
		restart_requested.emit())


func _heading(v: Control, text: String, size_px := 26) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	v.add_child(l)


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(0, 44)
	parent.add_child(b)
	return b


func _choices(v: Control, title: String, key: String, options: Dictionary) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	v.add_child(l)
	var row := HBoxContainer.new()
	v.add_child(row)
	_group_buttons[key] = []
	for id in options:
		var b := _button(row, options[id]["name"])
		b.toggle_mode = true
		b.button_pressed = _choice[key] == id
		b.pressed.connect(func():
			_choice[key] = id
			for other in _group_buttons[key]:
				other.button_pressed = other == b
			parts_changed.emit(_choice["chassis"], _choice["tires"], _choice["driver"]))
		_group_buttons[key].append(b)


func set_choice(chassis: String, tires: String, driver: String) -> void:
	_choice = {"chassis": chassis, "tires": tires, "driver": driver}


func _set_scheme(s: Controls.Scheme) -> void:
	Controls.scheme = s
	touch._layout()


func flash(text: String, seconds := 2.0) -> void:
	_banner.text = text
	_banner_time = seconds


## Lay everything out from the real screen size (it changes when phones rotate).
var _item: Label
var _item_box: ItemBox
var _lines: SpeedLines
var _splat: SplatOverlay
var _under: ColorRect
var _splat_kart: Kart


func _layout(vs: Vector2) -> void:
	if _item == null:
		_item = _label(_root, 20, Vector2(16, 88))
	_root.position = Vector2.ZERO
	_root.size = vs
	if touch.size != vs:
		touch.position = Vector2.ZERO
		touch.size = vs
	_lap.position = Vector2(vs.x * 0.5 - _lap.size.x * 0.5, 14)
	_center.position = Vector2(vs.x * 0.5 - _center.size.x * 0.5, vs.y * 0.3 - _center.size.y * 0.5)
	_banner.position = Vector2(vs.x * 0.5 - _banner.size.x * 0.5, 62)
	_tilt.position = Vector2(vs.x * 0.5 - _tilt.size.x * 0.5, vs.y - 44)
	minimap.position = Vector2(vs.x - minimap.size.x - 16, 12)
	_garage_btn.position = Vector2(vs.x - _garage_btn.size.x - 16, minimap.size.y + 22)
	var gs := _garage.get_combined_minimum_size()
	_garage.position = ((vs - gs) * 0.5).max(Vector2(8, 8))
	_garage.size = gs


func _process(delta: float) -> void:
	_layout(get_viewport().get_visible_rect().size)
	if race == null:
		return
	var me: Kart = race.player_kart
	if me == null:
		return
	if _splat == null:
		_splat = SplatOverlay.new()
		_root.add_child(_splat)
		_root.move_child(_splat, 0)
	# Under the frozen lake: everything through blue-green water.
	if _under == null:
		_under = ColorRect.new()
		_under.color = Color(0.05, 0.35, 0.5, 0.32)
		_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_under)
		_root.move_child(_under, 0)
	_under.size = _root.size
	_under.visible = race.camera != null and race.track.under_lake(race.camera.global_position)
	if _lines == null:
		_lines = SpeedLines.new()
		_root.add_child(_lines)
		_root.move_child(_lines, 0)
	_lines.kart = me
	_lines.size = _root.size
	if _splat_kart != me:
		if _splat_kart and _splat_kart.splattered.is_connected(_splat.splat):
			_splat_kart.splattered.disconnect(_splat.splat)
		_splat_kart = me
		me.splattered.connect(_splat.splat)
	_splat.size = _root.size
	var place: int = race.place_of(me)
	_place.text = "%d%s" % [place, _ordinal(place)]
	# Gold, silver, bronze, then white.
	_place.add_theme_color_override("font_color", [Color(1.0, 0.84, 0.2), Color(0.86, 0.9, 0.96), Color(0.95, 0.62, 0.35)][place - 1] if place <= 3 else Color.WHITE)
	_speed.text = "%d km/h    coins %d" % [int(absf(me.speed) * 3.6), me.coins]
	var t: float = me.race_time
	_lap.text = "Lap %d/%d   %d:%04.1f" % [clampi(me.lap, 1, race.track.laps), race.track.laps, int(t / 60.0), fmod(t, 60.0)]
	_center.text = race.center_text
	touch.drift_stage = me.drift_stage()
	# The item you hold, with a quick spin through the icons as you pick it up.
	var shown := me.held_item
	if me.item_spin > 0.0:
		var pool: Array = race.items.pool() if race.items else Items.KINDS
		shown = pool[int(me.item_spin * 12.0) % pool.size()]
	touch.held_item = shown
	_item.text = ""
	if _item_box.item != shown:
		_item_box.item = shown
		_item_box.hint = "" if touch.visible else "E"
		_item_box.queue_redraw()
	if touch.visible:
		touch.queue_redraw()
	_banner_time -= delta
	_banner.visible = _banner_time > 0.0

	# Tilt: show the steering angle so players can feel where level is.
	var state := Controls.tilt_state()
	if Controls.scheme == Controls.Scheme.TILT:
		if state == "on":
			var deg := Controls.tilt_degrees() - Controls.tilt_trim
			_tilt.text = "◀ %+d° ▶" % int(round(deg)) if absf(deg) > 1.0 else "— level —"
		else:
			_tilt.text = {"needs-permission": "Tap “Steer by tilting” to allow motion", "denied": "Motion access was turned down", "unsupported": "No motion sensor: using buttons", "waiting": "Waiting for the motion sensor…"}.get(state, "")
	else:
		_tilt.text = ""
	if _garage.visible:
		_tilt_status.text = {
			"on": "Tilt steering is on. Hold the phone sideways like a steering wheel; level is straight ahead.",
			"needs-permission": "Tap “Steer by tilting” and allow motion access when your phone asks.",
			"denied": "Motion access was turned down. Allow it in your browser's settings, then try again.",
			"unsupported": "This device doesn't report tilt, so buttons and keys are used.",
			"waiting": "Waiting for the motion sensor…",
			"off": "On a phone, tap “Steer by tilting” to steer like a wheel.",
		}.get(state, "")
		var r := _tilt_button.get_global_rect()
		Controls.publish_tilt_button(get_viewport().get_final_transform() * r)
	else:
		Controls.publish_tilt_button(Rect2())


func _ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "th"
	return {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")


func _unhandled_input(event: InputEvent) -> void:
	if _garage.visible and event.is_action_pressed("ui_cancel"):
		_garage.visible = false
		get_viewport().set_input_as_handled()
