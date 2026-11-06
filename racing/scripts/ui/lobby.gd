class_name Lobby
extends CanvasLayer
## The kart-selection screen before each race (design doc 4 and 5).
## A see-through menu over a slow aerial tour of the whole track (main.gd
## flies the camera). Options on the left, the chosen kart turning on its
## stand on the right, and Ready in the bottom-right corner.
##
## Everyone picks a chassis, wheels and a driver, and how they'll steer, then
## taps Ready. The race starts when every player is ready. The chosen kart
## turns slowly on a stand with its driver standing beside it, waving.
##
## Online play will fill `players` from the room; for now it's you plus the
## computer drivers, who are always ready.

signal parts_changed(chassis: String, tires: String, driver: String)
signal all_ready

var choice := {"chassis": "frame", "tires": "slicks", "driver": "fox"}
var players: Array = []   # [{name, ready}]

var _root: Control
var _preview: SubViewport
var _preview_box: SubViewportContainer
var _kart: Kart
var _kart_vis: KartVisual
var _stand_vis: KartVisual
var _turn: Node3D
var _buttons := {}
var _list: VBoxContainer
var _ready_btn: Button
var _tilt_btn: Button
var _stick_btn: Button
var _tilt_note: Label
var _stats: Label
var _t := 0.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	# A light shade over the aerial view so the menu reads clearly.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.14, 0.25)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_build_preview()
	_build_panel()
	_refresh()


func open(names: Array) -> void:
	players = [{"name": "You", "ready": false}]
	for n in names:
		players.append({"name": n, "ready": true})
	visible = true
	_ready_btn.disabled = false
	_ready_btn.text = "Ready!"
	_refresh()


# --- The turntable --------------------------------------------------------

func _build_preview() -> void:
	_preview_box = SubViewportContainer.new()
	_preview_box.stretch = true
	_root.add_child(_preview_box)
	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.msaa_3d = Viewport.MSAA_4X
	_preview.transparent_bg = true
	_preview_box.add_child(_preview)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.8)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	_preview.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	_preview.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.75, 1.0)
	_preview.add_child(rim)
	# A round stand with a stripe round the edge.
	var stand := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.3
	cyl.bottom_radius = 2.4
	cyl.height = 0.3
	cyl.radial_segments = 48
	stand.mesh = cyl
	stand.position = Vector3(0, -0.15, 0)
	stand.material_override = Palette.toon(Color(0.86, 0.88, 0.94), false, 0.0, Palette.Finish.PAINT)
	_preview.add_child(stand)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 2.3
	tor.outer_radius = 2.45
	tor.rings = 48
	ring.mesh = tor
	ring.position = Vector3(0, -0.02, 0)
	ring.material_override = Palette.toon(Color(1.0, 0.68, 0.1), false, 0.0, Palette.Finish.PAINT)
	_preview.add_child(ring)
	_turn = Node3D.new()
	_preview.add_child(_turn)
	# A parked kart to dress: frozen, it never moves on its own.
	_kart = Kart.new()
	_kart.freeze = true
	_kart.configure(choice["chassis"], choice["tires"], choice["driver"])
	_turn.add_child(_kart)
	_kart_vis = KartVisual.new(_kart)
	_kart_vis.empty = true
	_kart.add_child(_kart_vis)
	_kart.position = Vector3(0, 0.12, 0)
	_stand_vis = KartVisual.new(_kart, true, true)
	_preview.add_child(_stand_vis)
	_stand_vis.position = Vector3(2.0, 0.42, 0.9)
	_stand_vis.rotation.y = PI - 0.45
	var cam := Camera3D.new()
	cam.position = Vector3(0.9, 2.6, 7.4)
	cam.fov = 38.0
	_preview.add_child(cam)
	cam.look_at(Vector3(0.9, 0.55, 0.2), Vector3.UP)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_turn.rotation.y += delta * 0.45
	# The driver bobs about, happy to be picked.
	_stand_vis.position.y = 0.42 + absf(sin(_t * 2.2)) * 0.06
	_stand_vis.rotation.z = sin(_t * 2.2) * 0.05
	_stand_vis.rotation.y = PI - 0.45 + sin(_t * 0.9) * 0.15
	_layout(get_viewport().get_visible_rect().size)
	if _tilt_btn:
		var r := _tilt_btn.get_global_rect()
		Controls.publish_tilt_button(get_viewport().get_final_transform() * r)
		_tilt_note.text = {
			"on": "Tilt is on: hold the phone like a steering wheel. Level is straight.",
			"needs-permission": "Tap Tilt and allow motion access when asked.",
			"denied": "Motion access was turned down; allow it in your browser settings.",
			"unsupported": "No tilt sensor here: you'll steer with the joystick or keys.",
			"waiting": "Waiting for the motion sensor…",
		}.get(Controls.tilt_state(), "Tilt: steer by turning the phone like a wheel.")


# --- The options panel ----------------------------------------------------

func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.2, 0.78)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	var title := Label.new()
	title.text = "Pick your kart"
	title.add_theme_font_size_override("font_size", 26)
	v.add_child(title)
	_option_row(v, "Chassis", "chassis", Parts.CHASSIS)
	_option_row(v, "Wheels", "tires", Parts.TIRES)
	_option_row(v, "Driver", "driver", Parts.DRIVERS)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 14)
	_stats.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stats)
	_section(v, "Steering")
	var row := HBoxContainer.new()
	v.add_child(row)
	_stick_btn = _button(row, "Joystick")
	_stick_btn.toggle_mode = true
	_stick_btn.pressed.connect(func(): _set_scheme(Controls.Scheme.TOUCH_BUTTONS))
	_tilt_btn = _button(row, "Tilt")
	_tilt_btn.toggle_mode = true
	_tilt_btn.pressed.connect(func(): _set_scheme(Controls.Scheme.TILT))
	_tilt_note = Label.new()
	_tilt_note.add_theme_font_size_override("font_size", 13)
	_tilt_note.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	_tilt_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_tilt_note)
	_section(v, "Racers")
	_list = VBoxContainer.new()
	v.add_child(_list)
	_ready_btn = Button.new()
	_ready_btn.text = "Ready!"
	_ready_btn.custom_minimum_size = Vector2(0, 56)
	_ready_btn.add_theme_font_size_override("font_size", 24)
	var green := StyleBoxFlat.new()
	green.bg_color = Color(0.22, 0.72, 0.36)
	green.set_corner_radius_all(14)
	_ready_btn.add_theme_stylebox_override("normal", green)
	var green_h := green.duplicate()
	green_h.bg_color = Color(0.28, 0.8, 0.42)
	_ready_btn.add_theme_stylebox_override("hover", green_h)
	_ready_btn.add_theme_stylebox_override("pressed", green)
	var grey := green.duplicate()
	grey.bg_color = Color(0.3, 0.33, 0.4)
	_ready_btn.add_theme_stylebox_override("disabled", grey)
	_ready_btn.pressed.connect(_on_ready)
	_root.add_child(_ready_btn)


func _section(v: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	v.add_child(l)


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 42)
	b.focus_mode = Control.FOCUS_NONE
	# The picked option is bright yellow with dark text, so it's obvious.
	var on := StyleBoxFlat.new()
	on.bg_color = Color(1.0, 0.74, 0.18)
	on.set_corner_radius_all(10)
	on.content_margin_left = 12
	on.content_margin_right = 12
	var off := on.duplicate()
	off.bg_color = Color(0.2, 0.23, 0.32)
	var hover := on.duplicate()
	hover.bg_color = Color(0.26, 0.3, 0.42)
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.08))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.12, 0.1, 0.08))
	parent.add_child(b)
	return b


func _option_row(v: Control, title: String, key: String, options: Dictionary) -> void:
	_section(v, title)
	var flow := HFlowContainer.new()
	v.add_child(flow)
	_buttons[key] = {}
	for id in options:
		var b := _button(flow, options[id]["name"])
		b.toggle_mode = true
		b.pressed.connect(func():
			choice[key] = id
			_dress()
			parts_changed.emit(choice["chassis"], choice["tires"], choice["driver"])
			_refresh())
		_buttons[key][id] = b


func _set_scheme(s: Controls.Scheme) -> void:
	Controls.scheme = s
	_refresh()


func _dress() -> void:
	_kart.configure(choice["chassis"], choice["tires"], choice["driver"])
	_kart_vis.rebuild()
	_stand_vis.rebuild()


func _refresh() -> void:
	for key in _buttons:
		for id in _buttons[key]:
			(_buttons[key][id] as Button).button_pressed = choice[key] == id
	if _tilt_btn:
		_tilt_btn.button_pressed = Controls.scheme == Controls.Scheme.TILT
		_stick_btn.button_pressed = Controls.scheme != Controls.Scheme.TILT
	var ch: Dictionary = Parts.CHASSIS[choice["chassis"]]
	var ti: Dictionary = Parts.TIRES[choice["tires"]]
	_stats.text = "%s. %s" % [ch.get("blurb", ch["name"]), ti.get("blurb", ti["name"])]
	if _list:
		for c in _list.get_children():
			c.queue_free()
		for p in players:
			var l := Label.new()
			l.text = p["name"] + ("  —  ready" if p["ready"] else "  —  choosing")
			l.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if p["ready"] else Color(0.9, 0.9, 0.95))
			_list.add_child(l)


func _on_ready() -> void:
	players[0]["ready"] = true
	_ready_btn.disabled = true
	_ready_btn.text = "Waiting for everyone…"
	_refresh()
	if players.all(func(p): return p["ready"]):
		visible = false
		Controls.publish_tilt_button(Rect2())
		all_ready.emit()


## Options on the left, the turning kart on the right, Ready in the
## bottom-right corner.
func _layout(vs: Vector2) -> void:
	_root.size = vs
	var panel: Control = _root.get_node("Panel")
	var pad := 12.0
	var pw := clampf(vs.x * 0.44, 300.0, 520.0)
	panel.position = Vector2(pad, pad)
	panel.size = Vector2(pw, vs.y - pad * 2.0)
	var bw := clampf(vs.x * 0.24, 180.0, 300.0)
	_ready_btn.size = Vector2(bw, 60)
	_ready_btn.position = Vector2(vs.x - bw - pad * 2.0, vs.y - 60 - pad * 2.0)
	_preview_box.position = Vector2(pw + pad * 2.0, pad)
	_preview_box.size = Vector2(vs.x - pw - pad * 3.0, vs.y - 60 - pad * 4.0)
