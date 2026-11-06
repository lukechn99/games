extends Node
## Autoload "Controls": one place that turns keyboard, gamepad, touch and tilt
## into the same {steer, throttle, brake, drift, item} a kart understands
## (design doc 10). Players pick their scheme; nothing else needs to know.

enum Scheme { AUTO, TILT, TOUCH_BUTTONS }

const TILT_DEAD_ZONE := 3.0   # degrees around level that count as straight
const TILT_FULL_LOCK := 30.0  # degrees for full steering

var scheme := Scheme.AUTO
var auto_gas := false         # optional assist; phones have a gas button
var tilt_full_lock := TILT_FULL_LOCK
var tilt_trim := 0.0          # degrees, for people who hold their phone slightly tilted
var shake_level := 1.0        # 1 full, 0.5 gentle, 0 off
## Graphics quality (design doc 9.1). Everyone starts on High; if the frame
## rate drops, the race steps down a level by itself (main.gd).
enum Quality { LOW, MEDIUM, HIGH }
var quality := Quality.HIGH
## Real-time sun shadows, only on High. Off until they look right in the
## browser renderer (they brightened the scene); ?shadows=on to try them.
var shadows := false

signal quality_changed

## Touch buttons write here (see touch_controls.gd).
var touch := {"steer": 0.0, "brake": false, "gas": false, "item": false}

var _tilt_smoothed := 0.0


func _ready() -> void:
	_add_action("steer_left", [KEY_A, KEY_LEFT], [], [JOY_AXIS_LEFT_X, -1.0])
	_add_action("steer_right", [KEY_D, KEY_RIGHT], [], [JOY_AXIS_LEFT_X, 1.0])
	_add_action("gas", [KEY_W, KEY_UP], [], [JOY_AXIS_TRIGGER_RIGHT, 1.0])
	_add_action("brake", [KEY_S, KEY_DOWN], [], [JOY_AXIS_TRIGGER_LEFT, 1.0])
	_add_action("drift", [KEY_SHIFT, KEY_SPACE], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("item", [KEY_E, KEY_ENTER], [JOY_BUTTON_A])
	_add_action("respawn", [KEY_R], [JOY_BUTTON_Y])
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("location.search", true))
		if query.contains("shake=off"):
			shake_level = 0.0
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("location.search", true))
		shadows = q.contains("shadows=on")
		for name in ["low", "medium", "high"]:
			if q.contains("quality=" + name):
				quality = ["low", "medium", "high"].find(name) as Quality


func set_quality(q: Quality) -> void:
	quality = q
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
