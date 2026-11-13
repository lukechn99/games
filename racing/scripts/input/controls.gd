extends Node
## Autoload "Controls": one place that turns keyboard, gamepad, touch and tilt
## into the same {steer, throttle, brake, drift, item} a kart understands
## (design doc 10). Players pick their scheme; nothing else needs to know.

enum Scheme { AUTO, TILT, TOUCH_BUTTONS }

const TILT_DEAD_ZONE := 3.0   # degrees around level that count as straight
const TILT_FULL_LOCK := 25.0  # degrees for full steering (no need to tip the phone far)

var scheme := Scheme.AUTO:
	set(value):
		if scheme != value:
			scheme = value
			release_inputs()
var auto_gas := false         # optional assist; phones have a gas button
var tilt_full_lock := TILT_FULL_LOCK
var tilt_trim := 0.0          # degrees, for people who hold their phone slightly tilted
var shake_level := 1.0        # 1 full, 0.5 gentle, 0 off
## Graphics quality (design doc 9.1). Everyone starts on Low, so the game
## runs on as many devices as possible; players can raise it in the garage,
## and the choice is remembered on this device. If a raised level can't keep
## up, the race steps back down by itself (main.gd).
enum Quality { LOW, MEDIUM, HIGH }
var quality := Quality.LOW
## Real-time sun shadows, only on High. Off until they look right in the
## browser renderer (they brightened the scene); ?shadows=on to try them.
var shadows := false

signal quality_changed
signal inputs_released

## Touch buttons write here (see touch_controls.gd).
var touch := {"steer": 0.0, "brake": false, "gas": false, "item": false}

var _tilt_smoothed := 0.0
var suspended := false
var _web_interrupt: JavaScriptObject


func _ready() -> void:
	if OS.has_feature("web"):
		_web_interrupt = JavaScriptBridge.create_callback(_browser_interrupt)
		var mobile := JavaScriptBridge.get_interface("racingMobile")
		if mobile:
			mobile.subscribe(_web_interrupt)
	_add_action("steer_left", [KEY_A, KEY_LEFT], [], [JOY_AXIS_LEFT_X, -1.0])
	_add_action("steer_right", [KEY_D, KEY_RIGHT], [], [JOY_AXIS_LEFT_X, 1.0])
	_add_action("gas", [KEY_W, KEY_UP], [], [JOY_AXIS_TRIGGER_RIGHT, 1.0])
	_add_action("brake", [KEY_S, KEY_DOWN], [], [JOY_AXIS_TRIGGER_LEFT, 1.0])
	_add_action("drift", [KEY_SHIFT, KEY_SPACE], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("item", [KEY_E, KEY_ENTER], [JOY_BUTTON_A])
	_add_action("respawn", [KEY_R], [JOY_BUTTON_Y])
	if Query.has("shake=off"):
		shake_level = 0.0
	shadows = Query.has("shadows=on")
	if OS.has_feature("web"):
		var saved := str(JavaScriptBridge.eval("(function(){try{return localStorage.getItem('kw_quality')||''}catch(e){return ''}})()", true))
		var names := ["low", "medium", "high"]
		if names.has(saved):
			quality = names.find(saved) as Quality
		for name in names:
			if Query.has("quality=" + name):
				quality = names.find(name) as Quality


func set_quality(q: Quality, remember := true) -> void:
	quality = q
	if remember and OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('kw_quality','%s')}catch(e){}" % ["low", "medium", "high"][q], true)
	quality_changed.emit()


func quality_name() -> String:
	return ["Low", "Medium", "High"][quality]


func _add_action(name: String, keys: Array, buttons: Array = [], axis: Array = []) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(name, e)
	if axis.size() == 2:
		var e := InputEventJoypadMotion.new()
		e.axis = axis[0]
		e.axis_value = axis[1]
		InputMap.action_add_event(name, e)


func is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available()


func uses_auto_gas() -> bool:
	return auto_gas and (scheme != Scheme.AUTO or is_touch_device())


## The current controls for the player's kart.
func read(delta: float) -> Dictionary:
	if suspended:
		return {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "drift": false, "item": false}
	var steer := Input.get_axis("steer_left", "steer_right") + float(touch["steer"])
	if scheme == Scheme.TILT:
		var tilt := tilt_steer(delta)
		if absf(tilt) > absf(steer):
			steer = tilt
	var gas := Input.get_action_strength("gas")
	if touch["gas"] or uses_auto_gas():
		gas = 1.0
	var brake := Input.get_action_strength("brake")
	if touch["brake"]:
		brake = 1.0
		if uses_auto_gas():
			gas = 0.0
	return {
		"steer": clampf(steer, -1.0, 1.0),
		"throttle": gas,
		"brake": brake,
		"drift": Input.is_action_pressed("drift"),
		"item": Input.is_action_just_pressed("item") or touch["item"],
	}


func release_inputs() -> void:
	for key in ["gas", "brake", "item"]:
		touch[key] = false
	touch["steer"] = 0.0
	_tilt_smoothed = 0.0
	inputs_released.emit()


func _browser_interrupt(args: Array) -> void:
	suspended = bool(args[0])
	release_inputs()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		suspended = true
		release_inputs()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		suspended = false
		release_inputs()


# --- Tilt -----------------------------------------------------------------
# The page's tilt.js reads the motion sensor and works out how far the
# phone's long edge is from level, in degrees (positive = tilted right).
# Godot's web build can't read sensors itself (design doc 10.1).

func tilt_state() -> String:
	if not OS.has_feature("web"):
		return "unsupported"
	return str(JavaScriptBridge.eval("(window.racingTilt && window.racingTilt.state) || 'off'", true))


func tilt_degrees() -> float:
	if not OS.has_feature("web"):
		return 0.0
	return float(JavaScriptBridge.eval("(window.racingTilt && window.racingTilt.deg) || 0", true))


func tilt_steer(delta: float) -> float:
	if tilt_state() != "on":
		return 0.0
	return steer_from_degrees(tilt_degrees() - tilt_trim, delta)


## Level is straight ahead; a small dead zone, then a straight line to full lock.
func steer_from_degrees(deg: float, delta: float) -> float:
	var mag := maxf(0.0, absf(deg) - TILT_DEAD_ZONE) / maxf(1.0, tilt_full_lock - TILT_DEAD_ZONE)
	var target := clampf(mag, 0.0, 1.0) * signf(deg)
	_tilt_smoothed = lerpf(_tilt_smoothed, target, clampf(delta * 18.0, 0.0, 1.0))
	return _tilt_smoothed


## Where the "Steer by tilting" button is, so tilt.js can ask iOS for motion
## permission inside the tap itself (iOS only allows it from a real tap).
func publish_tilt_button(rect_in_canvas_px: Rect2) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.racingTiltButton = {x:%f, y:%f, w:%f, h:%f}" % [
			rect_in_canvas_px.position.x, rect_in_canvas_px.position.y, rect_in_canvas_px.size.x, rect_in_canvas_px.size.y], true)
