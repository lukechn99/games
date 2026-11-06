extends SceneTree
## Headless physics tests for the kart (design doc 7). Run with:
##   godot --headless --path racing --fixed-fps 60 -s tests/run_tests.gd
## Each test drives a kart with scripted inputs and checks how it behaves.

var failures := 0
var passes := 0
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_settles()
	await _test_top_speed_and_accel()
	await _test_turning_by_chassis()
	await _test_ice_grip_by_tires()
	await _test_drift_boost()
	await _test_wall_crash_signal()
	await _test_flip_recovery()
	await _test_slalom_stays_upright()
	_test_tilt_mapping()
	await _test_rear_end_bump()
	await _test_boulder_is_not_a_ramp()
	await _test_bots_lap_the_track()
	await _test_fall_off_respawns()
	await _test_clean_start()
	print("\n%d passed, %d failed" % [passes, failures])
	quit(1 if failures > 0 else 0)


func check(ok: bool, name: String, detail := "") -> void:
	if ok:
		passes += 1
		print("  ok   ", name, "  ", detail)
	else:
		failures += 1
		print("  FAIL ", name, "  ", detail)


# --- helpers ---------------------------------------------------------------

func _pad(surface := "asphalt") -> void:
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var b := StaticBody3D.new()
	b.set_meta("surface", surface)
	var c := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	c.shape = box
	c.position = Vector3(0, -1, 0)
	b.add_child(c)
	_world.add_child(b)


func _kart(chassis := "frame", tires := "slicks", driver := "fox", at := Vector3(0, 0.6, 0)) -> Kart:
	var k := Kart.new()
	k.configure(chassis, tires, driver)
	_world.add_child(k)
	k.global_position = at
	return k


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _drive(k: Kart, seconds: float, steer := 0.0, throttle := 1.0, brake := 0.0, drift := false) -> void:
	k.input = {"steer": steer, "throttle": throttle, "brake": brake, "drift": drift}
	await _ticks(int(seconds * 60.0))


# --- tests -----------------------------------------------------------------

func _test_settles() -> void:
	print("settling")
	_pad()
	for id in Parts.CHASSIS:
		var k := _kart(id, "slicks")
		await _drive(k, 2.0, 0.0, 0.0)
		var still := k.linear_velocity.length() < 0.15 and k.angular_velocity.length() < 0.15
		check(k.grounded_wheels == 4 and still and k.global_transform.basis.y.dot(Vector3.UP) > 0.99, "%s comes to rest on four wheels" % id,
			"wheels %d, v %.2f" % [k.grounded_wheels, k.linear_velocity.length()])
		k.free()


func _test_top_speed_and_accel() -> void:
	print("speed")
	for id in Parts.CHASSIS:
		_pad()
		var k := _kart(id, "slicks")
		await _drive(k, 0.5, 0.0, 0.0)
		var t := 0.0
		var t20 := -1.0
		k.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		while t < 12.0:
			await physics_frame
			t += 1.0 / 60.0
			if t20 < 0.0 and k.speed >= 20.0:
				t20 = t
		var top := k.top_speed()
		check(k.speed > top * 0.88 and k.speed < top * 1.03, "%s reaches its top speed" % id, "%.1f of %.1f m/s" % [k.speed, top])
		check(t20 > 1.2 and t20 < 4.5, "%s gets to 72 km/h in a fair time" % id, "%.2f s" % t20)


func _turn_radius(chassis: String, tires: String, surface: String, speed: float) -> float:
	_pad(surface)
	var k := _kart(chassis, tires)
	await _drive(k, 0.4, 0.0, 0.0)
	# Get up to speed, then hold full steering at a steady speed.
	k.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
	while k.speed < speed:
		await physics_frame
	var samples := 0.0
	var acc := 0.0
	for i in 240:
		var th := 1.0 if k.speed < speed else 0.0
		k.input = {"steer": 1.0, "throttle": th, "brake": 0.0, "drift": false}
		await physics_frame
		if i > 120:
			var w := absf(k.angular_velocity.y)
			if w > 0.01:
				acc += k.linear_velocity.length() / w
				samples += 1.0
	return acc / maxf(samples, 1.0)


func _test_turning_by_chassis() -> void:
	print("turning (chassis sets turn radius)")
	var r := {}
	for id in Parts.CHASSIS:
		r[id] = await _turn_radius(id, "slicks", "asphalt", 9.0)
	check(r["soapbox"] < r["frame"] and r["frame"] < r["hauler"] and r["frame"] < r["racer"], "soapbox turns tightest, hauler and racer widest",
		", ".join(r.keys().map(func(k): return "%s %.1f m" % [k, r[k]])))


func _test_ice_grip_by_tires() -> void:
	print("grip (tires by surface)")
	var slicks_ice: float = await _turn_radius("frame", "slicks", "ice", 14.0)
	var studs_ice: float = await _turn_radius("frame", "studded", "ice", 14.0)
	var slicks_tar: float = await _turn_radius("frame", "slicks", "asphalt", 14.0)
	check(studs_ice < slicks_ice * 0.75, "studded tires hold a tighter line on ice than slicks", "studded %.1f m, slicks %.1f m" % [studs_ice, slicks_ice])
	check(slicks_tar < slicks_ice * 0.75, "slicks grip far better on asphalt than ice", "asphalt %.1f m, ice %.1f m" % [slicks_tar, slicks_ice])


func _test_drift_boost() -> void:
	print("drift")
	_pad()
	var k := _kart()
	await _drive(k, 0.4, 0.0, 0.0)
	await _drive(k, 3.0, 0.0, 1.0)
	await _drive(k, 0.1, 0.6, 1.0, 0.0, false)
	await _drive(k, 2.6, 0.6, 1.0, 0.0, true)
	check(k.drifting and k.drift_stage() >= 2, "holding drift through a turn charges boost", "stage %d" % k.drift_stage())
	var before := k.speed
	await _drive(k, 0.05, 0.0, 1.0, 0.0, false)
	check(k.boost_time > 0.8, "releasing fires a boost", "%.2f s of boost" % k.boost_time)
	await _drive(k, 0.8, 0.0, 1.0)
	check(k.speed > before + 1.0, "the boost speeds the kart up", "%.1f → %.1f m/s" % [before, k.speed])


func _test_wall_crash_signal() -> void:
	print("crashes")
	_pad()
	var wall := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 3, 1)
	c.shape = box
	wall.add_child(c)
	wall.position = Vector3(0, 1.5, -70)
	_world.add_child(wall)
	var k := _kart()
	var hits: Array[float] = []
	k.crashed.connect(func(s): hits.append(s))
	await _drive(k, 0.4, 0.0, 0.0)
	await _drive(k, 5.0, 0.0, 1.0)
	var biggest: float = hits.max() if not hits.is_empty() else 0.0
	check(biggest > 0.4, "driving into a wall flags a big crash (for screen shake)", "strength %.2f" % biggest)
	var k2 := _kart("frame", "slicks", "fox", Vector3(10, 0.6, 0))
	var soft: Array[float] = []
	k2.crashed.connect(func(s): soft.append(s))
	await _drive(k2, 4.0, 0.3, 1.0)
	check(soft.is_empty(), "ordinary driving and cornering doesn't shake the screen", "%d false crashes" % soft.size())


func _test_flip_recovery() -> void:
	print("recovery")
	_pad()
	var k := _kart("frame", "slicks", "fox", Vector3(0, 1.5, 0))
	k.rotation = Vector3(0, 0, PI)
	var got := [false]
	k.respawned.connect(func(): got[0] = true)
	await _drive(k, 3.0, 0.0, 0.0)
	check(got[0] and k.global_transform.basis.y.dot(Vector3.UP) > 0.9, "an upside-down kart is put back on its wheels")


func _test_slalom_stays_upright() -> void:
	print("stability")
	for id in Parts.CHASSIS:
		_pad()
		var k := _kart(id, "slicks")
		await _drive(k, 0.3, 0.0, 0.0)
		await _drive(k, 3.0, 0.0, 1.0)
		var worst := 1.0
		for i in 12:
			var s := 1.0 if i % 2 == 0 else -1.0
			k.input = {"steer": s, "throttle": 1.0, "brake": 0.0, "drift": false}
			for j in 50:
				await physics_frame
				worst = minf(worst, k.global_transform.basis.y.dot(Vector3.UP))
		check(worst > 0.8, "%s stays upright through a flat-out slalom" % id, "lowest uprightness %.2f" % worst)


func _test_tilt_mapping() -> void:
	print("tilt")
	var c: Node = root.get_node("/root/Controls")
	var big := 1.0
	check(is_equal_approx(c.steer_from_degrees(2.0, big), 0.0), "inside the dead zone, level is straight ahead")
	c.steer_from_degrees(0.0, big)
	check(c.steer_from_degrees(40.0, big) > 0.99, "tilting past full lock is full right")
	c.steer_from_degrees(0.0, big)
	var halfway := -(Controls.TILT_DEAD_ZONE + (Controls.TILT_FULL_LOCK - Controls.TILT_DEAD_ZONE) * 0.5)
	check(c.steer_from_degrees(halfway, big) < -0.45 and c.steer_from_degrees(halfway, big) > -0.55, "halfway to full lock is half steering", "%.2f" % c.steer_from_degrees(halfway, big))


func _test_rear_end_bump() -> void:
	print("bumps")
	_pad()
	var front := _kart("frame", "slicks", "fox", Vector3(0, 0.6, -6))
	var back := _kart("hauler", "slicks", "rhino", Vector3(0.4, 0.6, 0))
	var bumps := KartBumps.new()
	bumps.karts = [front, back]
	_world.add_child(bumps)
	await _drive(front, 0.4, 0.0, 0.0)
	back.input = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "drift": false}
	back.linear_velocity = Vector3(0, 0, -25)
	var max_yaw := 0.0
	var touched := [false]
	front.crashed.connect(func(_s): touched[0] = true)
	for i in 90:
		await physics_frame
		max_yaw = maxf(max_yaw, maxf(absf(front.angular_velocity.y), absf(back.angular_velocity.y)))
	check(touched[0] and front.linear_velocity.length() > 3.0, "a heavy kart rear-ending at 90 km/h shoves the one ahead", "front now %.1f m/s" % front.linear_velocity.length())
	check(max_yaw < 1.5, "...without spinning either kart round", "max yaw %.2f rad/s" % max_yaw)
	var ahead := -front.global_transform.basis.z
	check(absf(rad_to_deg(ahead.signed_angle_to(Vector3.FORWARD, Vector3.UP))) < 25.0, "...and the front kart still faces forward")


func _test_bots_lap_the_track() -> void:
	print("bots on the test track")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	_world.add_child(track)
	var bots: Array[Kart] = []
	var builds := [["frame", "slicks", "hard"], ["hauler", "knobby", "medium"], ["soapbox", "balloon", "easy"], ["racer", "studded", "hard"]]
	for i in builds.size():
		var k := Kart.new()
		k.configure(builds[i][0], builds[i][1], "fox")
		k.track = track
		_world.add_child(k)
		k.global_transform = track.grid_transform(i)
		var d := BotDriver.new(k, track, builds[i][2], i)
		_world.add_child(d)
		bots.append(k)
	var bumps := KartBumps.new()
	bumps.karts = bots
	_world.add_child(bumps)
	var spins := [0]
	var spin_at := []
	var last_spin := [-99.0, -99.0, -99.0, -99.0]
	var respawns := [0, 0, 0, 0]
	for i in bots.size():
		var idx := i
		bots[i].respawned.connect(func(): respawns[idx] += 1)
	var lap_time := [0.0, 0.0, 0.0, 0.0]
	var took_branch := [0]
	var took_main := [0]
	var t := 0.0
	var limit := 180.0
	while t < limit:
		await physics_frame
		t += 1.0 / 60.0
		for i in bots.size():
			if bots[i].lap >= 1 and lap_time[i] == 0.0:
				lap_time[i] = -t  # crossed the start line: lap timing starts
			elif bots[i].lap >= 2 and lap_time[i] < 0.0:
				lap_time[i] = t + lap_time[i]
		for i in bots.size():
			var k := bots[i]
			var o := track.offset_of(k.global_position)
			if absf(track.branch_offset(o)) > Track.BRANCH_SHIFT * 0.9:
				var lx: float = (track.transform_at(o).affine_inverse() * k.global_position).x
				if absf(lx) > Track.BRANCH_SHIFT * 0.6:
					took_branch[0] += 1
				else:
					took_main[0] += 1
			var road := -track.transform_at(track.offset_of(k.global_position)).basis.z
			var fwd := -k.global_transform.basis.z
			fwd.y = 0.0
			if absf(fwd.normalized().signed_angle_to(road, Vector3.UP)) > deg_to_rad(120) and Vector2(k.linear_velocity.x, k.linear_velocity.z).length() > 3.0 and t - last_spin[i] > 5.0:
				last_spin[i] = t
				spins[0] += 1
				spin_at.append("kart %d at %d m, %.0f m/s, drifting %s, %d wheels down, t %.0f s" % [i, int(track.offset_of(k.global_position)), k.speed, k.drifting, k.grounded_wheels, t])
		if lap_time.all(func(x): return x > 0.0):
			break
	for i in bots.size():
		var avg := track.length / maxf(lap_time[i], 0.01)
		check(lap_time[i] > 0.0 and avg > 13.0, "%s bot (%s, %s) laps at a racing pace" % [builds[i][2], builds[i][0], builds[i][1]],
			"lap %.1f s, avg %.1f m/s, %d respawns" % [lap_time[i], avg, respawns[i]])
	check(spins[0] == 0, "nobody gets spun round in the pack (hills, banks, bumps)", "%d spins %s" % [spins[0], spin_at])
	check(took_branch[0] > 0 and took_main[0] > 0, "bots use both routes where the road splits", "%d frames on the second route, %d on the main road" % [took_branch[0], took_main[0]])
	print("  lap length %.0f m" % track.length)


func _test_boulder_is_not_a_ramp() -> void:
	print("boulders")
	_pad()
	# Same hit shape as the track's boulders (track.gd, _build_scenery).
	var rock := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.36 * 4.0
	cyl.height = 0.26 * 4.0 * 2.6
	c.shape = cyl
	c.position = Vector3(0.6, cyl.height * 0.5, -60)
	rock.add_child(c)
	_world.add_child(rock)
	var k := _kart()
	var top := [0.0]
	for i in 300:
		k.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		await physics_frame
		top[0] = maxf(top[0], k.global_position.y)
	check(top[0] < 1.2, "hitting a boulder at speed bumps you, it doesn't launch you", "highest %.2f m" % top[0])


func _test_fall_off_respawns() -> void:
	print("falling off")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	_world.add_child(track)
	var k := Kart.new()
	k.configure("frame", "slicks", "fox")
	k.track = track
	_world.add_child(k)
	# Find a raised stretch and drop the kart well under the road there.
	var best := 0.0
	for o in range(0, int(track.length), 5):
		if track.road_frame(o).origin.y > track.road_frame(best).origin.y:
			best = o
	var frame: Transform3D = track.road_frame(best)
	k.global_transform = Transform3D(frame.basis, frame.origin - frame.basis.y * 4.0)
	var got := [false]
	k.respawned.connect(func(): got[0] = true)
	await _ticks(90)
	var back: Vector3 = track.road_frame(track.offset_of(k.global_position)).affine_inverse() * k.global_position
	check(got[0] and back.y > -1.0, "a kart that ends up under the road is put back on it", "road %.1f m up, kart %.1f m from the road surface" % [frame.origin.y, back.y])


## The user kept hitting "something invisible" right after the start: the
## hit box scraped the road at speed and caught on the edges between road
## pieces (the boost pad). Driving straight from pole must hit nothing.
func _test_clean_start() -> void:
	print("clean start")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	_world.add_child(track)
	var k := Kart.new()
	k.configure("frame", "slicks", "fox")
	k.track = track
	_world.add_child(k)
	k.global_transform = track.grid_transform(0)
	var hits := []
	k.crashed.connect(func(s): hits.append("%.2f at %d m" % [s, int(track.offset_of(k.global_position))]))
	while track.offset_of(k.global_position) < 165.0 or track.offset_of(k.global_position) > 900.0:
		k.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		await physics_frame
	check(hits.is_empty(), "driving straight from pole hits nothing (no phantom bumps)", "%s" % [hits])
