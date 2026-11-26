class_name Controls
extends Control
## Keyboard and mouse, gamepad and touch, all filling one PlayerInput
## (design doc 10). Touch: drag on the left to move, drag on the right to
## look, buttons on the right. Draws its own buttons, so several fingers work.

const MOUSE_LOOK := 0.0025
const TOUCH_LOOK := 0.0055
const PAD_LOOK := 2.6
const STICK := 70.0

var input := PlayerInput.new()
var role := "seeker"
var touching := false             # a touch screen: show the touch layout

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_at := Vector2.ZERO
var _look_finger := -1
var _look_last := Vector2.ZERO
var _button_fingers := {}         # finger -> button name
var _buttons := {}                # name -> {at, r, label}
var _stick_home := Vector2(150, 570)   # where the stick rests, bottom left
var _laid_out_for := Vector2.ZERO
## The page draws the stick and buttons (web/touch.js) when it can: Godot's
## own stick never caught a thumb on iPhone. Then every touch that reaches
## the game is for looking around.
var page_controls := false
var _page_move := Vector2.ZERO
var _page_held := false
var _role_sent := ""
var _last_touch_ms := -100000
var _interruptions := -1
var _check_t := 0.0
## Touch diagnostics shown on phones while we chase the iPhone stick bug.
var counts := {"touch": 0, "drag": 0, "mbtn": 0, "mmove": 0}


func _ready() -> void:
	if OS.has_feature("web"):
		page_controls = bool(JavaScriptBridge.eval("!!window.hsTouch", true))
		if page_controls:
			touching = true
	# Phones show the stick and buttons from the start, not after a first
	# touch (players didn't know they could move).
	touching = DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()


func set_role(r: String) -> void:
	role = r
	if page_controls:
		JavaScriptBridge.eval("window.hsTouch.setRole('%s')" % r, true)
		_role_sent = r
	_layout()


func _layout() -> void:
	# The screen as it is now (not this node's size, which can lag behind a
	# rotation: the controls were left below the screen after turning a
	# phone from upright to sideways).
	var s := get_viewport_rect().size
	_laid_out_for = s
	var u := clampf(minf(s.y / 720.0, s.x / 1280.0), 0.7, 1.6)
	_buttons.clear()
	# Keep thumbs off the screen edges: iPhone Safari holds back touches that
	# start near the left edge (back swipe) or the bottom (home swipe) while it
	# decides whether they're its own gestures, so a stick in the corner
	# lagged and stuttered (owner's report) while looking around was fine.
	var br := s - Vector2(130, 160) * u
	if role == "seeker":
		_buttons["fire"] = {"at": br, "r": 62 * u, "label": "Shoot"}
	else:
		_buttons["reroll"] = {"at": br, "r": 50 * u, "label": "Switch prop"}
		_buttons["lock"] = {"at": br + Vector2(-20, -135) * u, "r": 40 * u, "label": "Lock"}
		_buttons["decoy"] = {"at": br + Vector2(-130, -95) * u, "r": 40 * u, "label": "Decoy"}
	_buttons["jump"] = {"at": br + Vector2(-150, 30) * u, "r": 46 * u, "label": "Jump"}
	_stick_home = Vector2(maxf(230 * u, s.x * 0.15), s.y - maxf(210 * u, s.y * 0.3))
	queue_redraw()


func _process(delta: float) -> void:
	if get_viewport_rect().size != _laid_out_for:
		_layout()
	# Safari can swallow a touch's end (a call, a swipe from the edge, the
	# tab losing focus); mobile.js counts those: let go of everything.
	_check_t -= delta
	if touching and OS.has_feature("web") and _check_t <= 0.0:
		_check_t = 0.2
		var n := int(JavaScriptBridge.eval("window.racingMobile ? window.racingMobile.interruptions : 0", true))
		if _interruptions >= 0 and n != _interruptions:
			release_all()
		_interruptions = n
	var kb := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)))
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pad.length() < 0.2:
		pad = Vector2.ZERO
	var stick := Vector2.ZERO
	if page_controls:
		var raw: Variant = JSON.parse_string(str(JavaScriptBridge.eval("window.hsTouch.take()", true)))
		if raw is Dictionary:
			_page_move = Vector2(float(raw.get("x", 0)), float(raw.get("y", 0)))
			_page_held = bool(raw.get("held", false))
			for name in raw.get("p", []):
				if str(name) in ["fire", "jump", "reroll", "lock", "decoy"]:
					input.set(str(name), true)
		stick = _page_move.limit_length(1.0)
	elif _stick_finger >= 0:
		var v := (_stick_at - _stick_origin) / STICK
		stick = Vector2(v.x, -v.y).limit_length(1.0)
	input.move = (kb + pad + stick).limit_length(1.0)
	var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() > 0.2:
		input.look += look * PAD_LOOK * delta
	if touching:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		counts["touch"] += 1
	elif event is InputEventScreenDrag:
		counts["drag"] += 1
	elif event is InputEventMouseButton:
		counts["mbtn"] += 1
	elif event is InputEventMouseMotion:
		counts["mmove"] += 1
	if event is InputEventScreenTouch:
		touching = true
		_last_touch_ms = Time.get_ticks_msec()
		_touch(event)
	elif event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		_drag(event)

	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input.look += event.relative * MOUSE_LOOK
	elif event is InputEventMouseButton and event.pressed and not touching:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			input.fire = true
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: input.jump = true
			KEY_F: input.reroll = true
			KEY_R: input.lock = true
			KEY_Q: input.decoy = true
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: input.jump = true
			JOY_BUTTON_X: input.reroll = true
			JOY_BUTTON_Y: input.lock = true
			JOY_BUTTON_B: input.decoy = true
			JOY_BUTTON_RIGHT_SHOULDER: input.fire = true


## Let go of the stick, the look finger and every button.
func release_all() -> void:
	_stick_finger = -1
	_look_finger = -1
	_button_fingers.clear()
	input.move = Vector2.ZERO


func _touch(e: InputEventScreenTouch) -> void:
	if page_controls:
		# The page has the stick and buttons; touches here look around.
		if e.pressed:
			_look_finger = e.index
			_look_last = e.position
		elif e.index == _look_finger:
			_look_finger = -1
		return
	if e.pressed:
		for name in _buttons:
			var b: Dictionary = _buttons[name]
			if e.position.distance_to(b["at"]) <= b["r"] * 1.15:
				_button_fingers[e.index] = name
				input.set(name, true)
				return
		# A new thumb on the left always takes the stick, even if an old
		# finger never reported letting go (Safari can swallow that), so the
		# stick can't get stuck "held".
		if e.position.x < get_viewport_rect().size.x * 0.42:
			_stick_finger = e.index
			_stick_origin = e.position
			_stick_at = e.position
		elif _look_finger < 0:
			_look_finger = e.index
			_look_last = e.position
	else:
		_button_fingers.erase(e.index)
		if e.index == _stick_finger:
			_stick_finger = -1
		if e.index == _look_finger:
			_look_finger = -1


func _drag(e: InputEventScreenDrag) -> void:
	if e.index == _stick_finger:
		_stick_at = e.position
	elif e.index == _look_finger:
		input.look += (e.position - _look_last) * TOUCH_LOOK
		_look_last = e.position


func _draw() -> void:
	if not touching or page_controls:
		return
	var font := get_theme_default_font()
	for name in _buttons:
		var b: Dictionary = _buttons[name]
		var held: bool = _button_fingers.values().has(name)
		draw_circle(b["at"], b["r"], Color(1, 1, 1, 0.38 if held else 0.2))
		draw_arc(b["at"], b["r"], 0, TAU, 40, Color(1, 1, 1, 0.7), 2.0)
		var fs := int(b["r"] * (0.42 if b["label"].length() < 8 else 0.3))
		var w := font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, b["at"] + Vector2(-w / 2, fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# The movement stick: resting bottom left; a thumb anywhere on the left
	# side picks it up there.
	var base := _stick_origin if _stick_finger >= 0 else _stick_home
	var knob := base + ((_stick_at - _stick_origin).limit_length(STICK) if _stick_finger >= 0 else Vector2.ZERO)
	draw_circle(base, STICK, Color(1, 1, 1, 0.16))
	draw_arc(base, STICK, 0, TAU, 48, Color(1, 1, 1, 0.55), 2.0)
	draw_circle(knob, 30, Color(1, 1, 1, 0.5 if _stick_finger >= 0 else 0.35))
	if _stick_finger < 0:
		var fs := 15
		var t := "Move"
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, base + Vector2(-w / 2, STICK + 22), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.8))


func diagnostics() -> String:
	var held := _page_held if page_controls else _stick_finger >= 0
	return "%s · touch %d · drag %d · stick %s · move %.1f,%.1f · screen %dx%d" % ["page stick" if page_controls else "game stick",
		counts["touch"], counts["drag"], "held" if held else "-", input.move.x, input.move.y, get_viewport_rect().size.x, get_viewport_rect().size.y]
