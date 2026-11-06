class_name ChaseCamera
extends Camera3D
## Follows a kart from behind on a soft spring, widens its view at speed and
## shakes on crashes (design doc 7.3 and 8).
##
## Shake uses "trauma": crashes add to it, it fades over about half a
## second, and the shake is trauma squared, so small bumps barely register
## and big crashes really rattle.

const DISTANCE := 5.2
const HEIGHT := 2.1
const LOOK_AHEAD := 4.0
const BASE_FOV := 68.0
const SPEED_FOV := 12.0

var target: Kart
var trauma := 0.0
var look_back := false
var _noise := FastNoiseLite.new()
var _t := 0.0
var _pos := Vector3.ZERO
var _fov_punch := 0.0


func _ready() -> void:
	_noise.seed = 7
	_noise.frequency = 1.6
	fov = BASE_FOV
	near = 0.1
	far = 900.0


func follow(kart: Kart) -> void:
	if target and target.crashed.is_connected(_on_crash):
		target.crashed.disconnect(_on_crash)
		target.landed.disconnect(_on_land)
	target = kart
	target.crashed.connect(_on_crash)
	target.landed.connect(_on_land)
	_pos = _desired_position()
	global_position = _pos


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount * Controls.shake_level, 0.0, 1.0)
	_fov_punch = maxf(_fov_punch, amount * 6.0 * Controls.shake_level)
	if OS.has_feature("web") and amount > 0.25 and Controls.shake_level > 0.0:
		# Android buzzes; iPhone browsers ignore vibration.
		JavaScriptBridge.eval("navigator.vibrate && navigator.vibrate(%d)" % int(30 + amount * 60), true)


func _on_crash(strength: float) -> void:
	add_trauma(0.15 + strength * 0.5)


func _on_land(strength: float) -> void:
	if strength > 0.25:
		add_trauma(strength * 0.35)


func _flat_forward() -> Vector3:
	var f := -target.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.1:
		return Vector3.FORWARD
	return f.normalized()


func _desired_position() -> Vector3:
	var f := _flat_forward()
	if look_back:
		f = -f
	return target.global_position - f * DISTANCE + Vector3.UP * HEIGHT


func _process(delta: float) -> void:
	if target == null:
		return
	_t += delta
	var desired := _desired_position()
	_pos = _pos.lerp(desired, clampf(delta * (14.0 if look_back else 7.0), 0.0, 1.0))
	var f := _flat_forward() * (-1.0 if look_back else 1.0)
	var look := target.global_position + f * LOOK_AHEAD + Vector3.UP * 0.8

	var shake := trauma * trauma
	var offset := Vector3(_noise.get_noise_2d(_t * 30.0, 0.0), _noise.get_noise_2d(0.0, _t * 30.0), 0.0) * 0.45 * shake
	global_position = _pos + offset
	look_at(look + offset * 0.5, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, _noise.get_noise_2d(_t * 25.0, 99.0) * 0.08 * shake)
	trauma = maxf(0.0, trauma - delta * 1.8)

	var speed_t := clampf(absf(target.speed) / 28.0, 0.0, 1.0)
	var boost := 6.0 if target.boost_time > 0.0 else 0.0
	_fov_punch = move_toward(_fov_punch, 0.0, delta * 20.0)
	fov = lerpf(fov, BASE_FOV + SPEED_FOV * speed_t + boost + _fov_punch, clampf(delta * 4.0, 0.0, 1.0))
