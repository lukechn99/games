class_name Kart
extends RigidBody3D
## An arcade kart on a rigid body (design doc 7.1). Four downward rays act as
## springs; each wheel then pushes against the ground with grip from its tire
## and the surface under it. All numbers come from the chassis and tires.
##
## Whoever drives it (a player or a bot) just fills in `input` every frame.

signal crashed(strength: float)
signal landed(strength: float)
signal respawned
signal lap_completed(lap: int, time: float)

const SUSPENSION_TRAVEL := 0.32
const LATERAL_STIFFNESS := 0.55
const DOWNFORCE := 0.9
const AIR_LEVELLING := 9.0
const DRIFT_MIN_SPEED := 9.0
const DRIFT_SLIP := 0.49  # radians (28°): how far the nose points into a drift
const MAX_YAW_RATE := 4.0  # rad/s: hits can turn you, but never whip you round
const BOOST_STAGES := [[0.7, 0.55], [1.5, 0.95], [2.4, 1.4]]  # [drift seconds, boost seconds]
const BOOST_FORCE := 1.25  # times the chassis acceleration
const BOOST_SPEED := 1.22  # top speed multiplier while boosting

var chassis: Dictionary
var tires: Dictionary
var driver: Dictionary
var driver_id := ""
var chassis_id := ""
var tires_id := ""
var display_name := "Kart"
var number := 1

## Controls for this physics tick. steer: -1 (left) to 1 (right).
var input := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "drift": false}

var steer_angle := 0.0
var speed := 0.0          # forward speed, m/s
var grounded_wheels := 0
var surface_name := "asphalt"
var drifting := false
var drift_dir := 0.0
var drift_time := 0.0
var boost_time := 0.0
var air_time := 0.0
var wheel_spin := 0.0
var wheel_compression: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_grounded: Array[bool] = [false, false, false, false]
var lateral_g := 0.0      # sideways acceleration, for the driver's lean
var vertical_kick := 0.0  # suspension jolt this tick, for the driver's bob

var track: Node = null    # set by the race; provides respawn points and laps
var lap := 0
var next_checkpoint := 1
var race_time := 0.0
var finished := false

var _wheel_mounts: Array[Vector3] = []
var _spring := 0.0
var _damper := 0.0
var _prev_velocity := Vector3.ZERO
var _upside_down_time := 0.0
var _collision: CollisionShape3D
var _off_track_time := 0.0
var _calm_vy := 0.0  # upward speed before touching a wall
var _box_bottom := 0.05
var _good_v := Vector3.ZERO   # velocity before any phantom bump
var _good_w := Vector3.ZERO
var _was_drift_pressed := false
var _drift_exit := 0.0     # seconds left blending grip back in after a drift
const DRIFT_EXIT := 0.35


func _ready() -> void:
	continuous_cd = true
	# Karts live on layer 2 and only collide with the world (layer 1);
	# kart-to-kart bumps are handled gently by KartBumps instead.
	collision_layer = 2
	collision_mask = 1
	# Contacts are watched so a wall can stop a kart but never throw it (below).
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	# Replace Godot's default damping: all drag comes from the surfaces.
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 2.0
	linear_damp = 0.0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.05
	mat.bounce = 0.15
	physics_material_override = mat
	if chassis.is_empty():
		configure("frame", "slicks", "fox")


## Build the kart from parts. Safe to call again to swap parts.
func configure(new_chassis: String, new_tires: String, new_driver: String) -> void:
	chassis_id = new_chassis
	tires_id = new_tires
	driver_id = new_driver
	chassis = Parts.CHASSIS[new_chassis]
	tires = Parts.TIRES[new_tires]
	driver = Parts.DRIVERS[new_driver]
	mass = float(chassis["mass"]) + float(Parts.WEIGHT_MASS[driver["weight"]])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)

	# The hit box comes from the chassis only (design doc 5.5).
	var size: Vector3 = chassis["size"]
	if _collision == null:
		_collision = CollisionShape3D.new()
		add_child(_collision)
	var box := BoxShape3D.new()
	# The hit box rides clear of the road: the wheels (rays) hold the kart
	# up, and the box is for walls, rocks, trees and landing upside down. Its
	# bottom is raised and its top stays put, so the kart balances the same.
	_box_bottom = 0.2
	box.size = Vector3(size.x, maxf(0.2, size.y - 0.15), size.z)
	_collision.shape = box
	_collision.position = Vector3(0, _box_bottom + box.size.y * 0.5, 0)

	var half_wb := float(chassis["wheelbase"]) * 0.5
	var half_tr := float(chassis["track"]) * 0.5
	_wheel_mounts = [
		Vector3(-half_tr, 0.25, -half_wb), Vector3(half_tr, 0.25, -half_wb),  # front left, front right
		Vector3(-half_tr, 0.25, half_wb), Vector3(half_tr, 0.25, half_wb),    # rear left, rear right
	]
	# Spring: hold the kart up with ~40% of the travel compressed at rest.
	var per_wheel := mass * 9.8 / 4.0
	_spring = per_wheel / (SUSPENSION_TRAVEL * 0.4) * float(tires["spring"])
	_damper = 2.0 * sqrt(_spring * mass / 4.0) * 0.45


func wheel_radius() -> float:
	var r: Array = chassis["wheel_radius"]
	return clampf(float(tires["radius"]), float(r[0]), float(r[1]))


func wheel_mount(i: int) -> Vector3:
	return _wheel_mounts[i]


func top_speed() -> float:
	return float(chassis["top_speed"]) * float(tires["top_speed"]) * (BOOST_SPEED if boost_time > 0.0 else 1.0)


## Walls, rocks and trees stop you or knock you sideways; they never launch
## you into the air or flip you over. A hit at speed used to tip the nose up
## and throw the kart several metres high (the "phantom" launches).
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var walled := false
	var phantom := false
	var inv := state.transform.affine_inverse()
	for i in state.get_contact_count():
		if state.get_contact_local_normal(i).dot(Vector3.UP) < 0.6:
			# A sideways push from the floor itself, low on the hit box: that's
			# the box catching the edge where two road pieces meet, not a wall.
			# Real physics engines call these "ghost" collisions. Undo it.
			var other := state.get_contact_collider_object(i)
			var low := (inv * state.get_contact_local_position(i)).y < _box_bottom + 0.15
			if other != null and other.get_meta("floor", false) and low:
				phantom = true
			else:
				walled = true
	if phantom and not walled:
		state.linear_velocity = _good_v
		state.angular_velocity = _good_w
		return
	_good_v = state.linear_velocity
	_good_w = state.angular_velocity
	if walled:
		var v := state.linear_velocity
		if v.y > _calm_vy:
			v.y = _calm_vy
		state.linear_velocity = v
		var up := state.transform.basis.y
		var w := state.angular_velocity
		state.angular_velocity = up * w.dot(up) + (w - up * w.dot(up)) * 0.2
	else:
		_calm_vy = maxf(state.linear_velocity.y, 0.0)


func _physics_process(delta: float) -> void:
	if _wheel_mounts.is_empty():
		return
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var space := get_world_3d().direct_space_state
	var radius := wheel_radius()
	var ray_len := SUSPENSION_TRAVEL + radius
	var throttle := clampf(float(input["throttle"]), 0.0, 1.0)
	var brake := clampf(float(input["brake"]), 0.0, 1.0)
	speed = linear_velocity.dot(fwd)
	var top := top_speed()

	_update_steering(delta)
	_update_drift(delta)

	grounded_wheels = 0
	vertical_kick = 0.0
	var surfaces := {}
	var params := PhysicsRayQueryParameters3D.new()
	params.exclude = [get_rid()]
	params.collision_mask = 1

	for i in 4:
		var mount := xf * _wheel_mounts[i]
		params.from = mount
		params.to = mount - up * ray_len
		var hit := space.intersect_ray(params)
		# Wheels only roll on ground, never on the face of a wall or rock.
		# (Without this a wheel touching a wall pushed the kart up it, and
		# the kart was thrown into the air.)
		if not hit.is_empty() and (hit["normal"] as Vector3).dot(Vector3.UP) < 0.6:
			hit = {}
		if hit.is_empty():
			wheel_grounded[i] = false
			wheel_compression[i] = lerpf(wheel_compression[i], 0.0, 0.3)
			continue
		wheel_grounded[i] = true
		grounded_wheels += 1
		var dist: float = (hit["position"] - mount).length()
		var compression := clampf(ray_len - dist, 0.0, SUSPENSION_TRAVEL)
		wheel_compression[i] = compression
		var offset: Vector3 = mount - global_position
		var point_vel := linear_velocity + angular_velocity.cross(offset)
		var compress_speed := -point_vel.dot(up)
		var load := maxf(0.0, _spring * compression + _damper * compress_speed)
		# A stiff bump stop near the end of travel, so downforce at speed and
		# hard landings never bottom the kart out onto its hit box (that
		# scraping is what caught on road edges and threw karts about).
		var stop := compression - SUSPENSION_TRAVEL * 0.7
		if stop > 0.0:
			# Firm while squashing, soft while springing back, so landings
			# are caught instead of bouncing the kart back into the air.
			load += _spring * (5.0 if compress_speed > 0.0 else 1.0) * stop + _damper * maxf(compress_speed, 0.0) * 0.8
		vertical_kick = maxf(vertical_kick, compress_speed)
		apply_force(up * load, offset)

		# Tire forces in the plane of the ground.
		var normal: Vector3 = hit["normal"]
		var s := _surface_of(hit["collider"])
		surfaces[s] = int(surfaces.get(s, 0)) + 1
		var wheel_fwd := fwd
		if i < 2:
			wheel_fwd = fwd.rotated(up, -steer_angle)
		wheel_fwd = (wheel_fwd - normal * wheel_fwd.dot(normal)).normalized()
		var wheel_right := wheel_fwd.cross(normal).normalized()
		var v_side := point_vel.dot(wheel_right)
		var v_long := point_vel.dot(wheel_fwd)

		var mu := Parts.tire_grip(tires, s)
		if drifting and i >= 2:
			mu *= float(tires["drift"])
		var max_force := mu * maxf(load, mass * 9.8 * 0.15)

		var f_side := -v_side * (mass * 0.25) / delta * LATERAL_STIFFNESS
		if drifting:
			f_side *= 0.02  # the drift steers the momentum itself (below)
		elif _drift_exit > 0.0:
			f_side *= lerpf(1.0, 0.05, _drift_exit / DRIFT_EXIT)
		var f_long := 0.0
		var accel := float(chassis["accel"]) * (BOOST_FORCE + 1.0 if boost_time > 0.0 else 1.0)
		if throttle > 0.0 and speed < top:
			# Full pull until 70% of top speed, then fading to nothing at the top.
			f_long += accel * throttle * clampf((top - speed) / (top * 0.3), 0.0, 1.0) * 0.25
		if brake > 0.0:
			if speed > 0.8:
				f_long -= float(chassis["accel"]) * 1.7 * brake * 0.25
			elif speed > -top * 0.35:
				f_long -= float(chassis["accel"]) * 0.6 * brake * 0.25  # reverse
		f_long -= v_long * mass * 0.012 * 0.25  # rolling resistance
		var force := wheel_fwd * f_long + wheel_right * f_side
		if force.length() > max_force:
			force = force.normalized() * max_force
		# Push a little above the contact patch so cornering doesn't roll the kart over.
		var at: Vector3 = hit["position"] - global_position + up * (radius * 0.9)
		apply_force(force, at)

	surface_name = _dominant(surfaces)
	if grounded_wheels > 0:
		var drag := float(Parts.surface(surface_name)["drag"])
		if surface_name == "boost":
			boost_time = maxf(boost_time, 0.4)
		elif drag > 0.0:
			var flat := linear_velocity - up * linear_velocity.dot(up)
			apply_central_force(-flat * drag * mass * (float(grounded_wheels) / 4.0))
		apply_central_force(-up * DOWNFORCE * mass * 0.05 * speed * speed / 9.0)
		if drifting:
			# Hold a steady drift: steer the yaw rate toward a target circle.
			# Steering into the drift tightens it; steering out widens it.
			var into := clampf(float(input["steer"]) * drift_dir, -1.0, 1.0)
			var radius_m := lerpf(24.0, 11.0, (into + 1.0) * 0.5)
			var flat_v := linear_velocity - up * linear_velocity.dot(up)
			var want_w := -drift_dir * flat_v.length() / radius_m
			var have_w := angular_velocity.dot(up)
			apply_torque(up * (want_w - have_w) * mass * 1.6)
			# Arcade drift: the nose points into the corner and the momentum
			# follows it round at speed, instead of the kart spinning out.
			var flat_fwd := (fwd - up * fwd.dot(up)).normalized()
			var travel := flat_fwd.rotated(up, drift_dir * DRIFT_SLIP)
			var spd := flat_v.length()
			var dir := flat_v.normalized().slerp(travel, clampf(delta * 7.0, 0.0, 1.0))
			if throttle > 0.0 and spd < top * 0.97:
				spd += 2.0 * delta
			linear_velocity = dir * spd + up * linear_velocity.dot(up)
		if air_time > 0.35:
			landed.emit(clampf(-_prev_velocity.y / 14.0, 0.0, 1.0))
		air_time = 0.0
	else:
		air_time += delta
		var level := up.cross(Vector3.UP)
		apply_torque((level * AIR_LEVELLING - angular_velocity * 1.5) * mass * 0.6)

	if _drift_exit > 0.0 and grounded_wheels > 0:
		# Coming out of a drift: swing the momentum back in line with the nose
		# without losing speed, while grip returns.
		_drift_exit -= delta
		var flat_v := linear_velocity - up * linear_velocity.dot(up)
		var flat_fwd := (fwd - up * fwd.dot(up)).normalized()
		var dir := flat_v.normalized().slerp(flat_fwd, clampf(delta * 9.0, 0.0, 1.0))
		linear_velocity = dir * flat_v.length() + up * linear_velocity.dot(up)
	if boost_time > 0.0:
		boost_time -= delta
		if grounded_wheels > 0:
			apply_central_force(fwd * float(chassis["accel"]) * 0.6)

	# Backstop against violent spins (wall hits at an angle): outside a drift,
	# cap how fast the kart can rotate about its own up axis.
	var yaw := angular_velocity.dot(up)
	if not drifting and absf(yaw) > MAX_YAW_RATE:
		angular_velocity -= up * (yaw - signf(yaw) * MAX_YAW_RATE)
	_detect_crash(delta)
	_check_recovery(delta)
	lateral_g = lerpf(lateral_g, linear_velocity.dot(xf.basis.x) * angular_velocity.dot(up) / 9.8, 0.2)
	wheel_spin += speed / maxf(radius, 0.1) * delta
	if track != null and not finished:
		race_time += delta
		track.update_progress(self)


func _update_steering(delta: float) -> void:
	var steer := clampf(float(input["steer"]), -1.0, 1.0)
	if drifting:
		# Mid-drift, steering tightens or widens the drift instead of reversing it.
		steer = drift_dir * (0.55 + 0.45 * steer * drift_dir)
	var t := clampf(absf(speed) / float(chassis["top_speed"]), 0.0, 1.0)
	var max_steer := lerpf(float(chassis["max_steer"]), float(chassis["high_speed_steer"]), t)
	if speed < -0.5:
		steer = -steer  # reversing
	steer_angle = move_toward(steer_angle, steer * max_steer, delta * 4.0)


func _update_drift(delta: float) -> void:
	var pressed := bool(input["drift"])
	var steer := float(input["steer"])
	if pressed and not _was_drift_pressed and not drifting and grounded_wheels >= 2 and speed > DRIFT_MIN_SPEED and absf(steer) > 0.2:
		drifting = true
		drift_dir = signf(steer)
		drift_time = 0.0
		apply_central_impulse(Vector3.UP * mass * 1.6)  # the little hop into a drift
	_was_drift_pressed = pressed
	if not drifting:
		return
	if grounded_wheels > 0:
		drift_time += delta * float(tires["drift_charge"])
	var flat_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
	if not pressed or flat_speed < DRIFT_MIN_SPEED * 0.6:
		drifting = false
		_drift_exit = DRIFT_EXIT
		for stage in range(BOOST_STAGES.size() - 1, -1, -1):
			if drift_time >= BOOST_STAGES[stage][0]:
				boost_time = maxf(boost_time, BOOST_STAGES[stage][1])
				break
		drift_time = 0.0


## 0 none, 1-3 as the drift charges (for sparks and the HUD).
func drift_stage() -> int:
	if not drifting:
		return 0
	var stage := 0
	for i in BOOST_STAGES.size():
		if drift_time >= BOOST_STAGES[i][0]:
			stage = i + 1
	return stage


func _detect_crash(delta: float) -> void:
	# A sudden change in velocity that gravity, the engine and the tires can't
	# explain is a crash. Scale it to 0-1 for the screen shake.
	var dv := linear_velocity - _prev_velocity
	dv.y = 0.0
	var jolt := dv.length() / maxf(delta * 60.0, 0.0001)
	if jolt > 2.2 and _prev_velocity.length() > 4.0:
		crashed.emit(clampf((jolt - 2.2) / 7.0, 0.05, 1.0))
	_prev_velocity = linear_velocity


func _check_recovery(delta: float) -> void:
	var upright := global_transform.basis.y.dot(Vector3.UP)
	_upside_down_time = _upside_down_time + delta if upright < 0.35 else 0.0
	_off_track_time = _off_track_time + delta if _fallen_off() else 0.0
	if global_position.y < -12.0 or _upside_down_time > 1.6 or _off_track_time > 0.4:
		respawn()


## Out of bounds, like falling off the course in Mario Kart: under the road,
## well below it, or far from it. The kart is put back on the road.
func _fallen_off() -> bool:
	if track == null:
		return false
	var frame: Transform3D = track.road_frame(track.offset_of(global_position))
	var local: Vector3 = frame.affine_inverse() * global_position
	var under_road: bool = local.y < -2.0 and absf(local.x) < Track.ROAD_WIDTH * 0.5 + 2.0
	return under_road or local.y < -6.0 or absf(local.x) > 45.0 or track.in_water(global_position)


func respawn() -> void:
	var xf := global_transform
	if track != null:
		xf = track.respawn_transform(global_position)
	else:
		# No track (tests): set it back on its wheels where it is.
		var f := -xf.basis.z
		f.y = 0.0
		if f.length() < 0.1:
			f = Vector3.FORWARD
		xf = Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), xf.origin + Vector3.UP * 1.0)
	global_transform = xf
	linear_velocity = -xf.basis.z * 6.0
	angular_velocity = Vector3.ZERO
	_prev_velocity = linear_velocity
	drifting = false
	_upside_down_time = 0.0
	_off_track_time = 0.0
	reset_physics_interpolation()
	respawned.emit()


func _surface_of(collider: Object) -> String:
	if collider != null and collider.has_meta("surface"):
		return String(collider.get_meta("surface"))
	return "asphalt"


func _dominant(counts: Dictionary) -> String:
	var best := surface_name
	var n := 0
	for k in counts:
		if int(counts[k]) > n:
			n = int(counts[k])
			best = k
	return best
