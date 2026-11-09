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
	_test_touch_interruptions()
	_test_benchmark_stats()
	await _test_rear_end_bump()
	await _test_boulder_is_not_a_ramp()
	await _test_bots_lap_the_track()
	await _test_fall_off_respawns()
	await _test_clean_start()
	await _test_items()
	await _test_mine()
	await _test_frost()
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
	k.coins = 10
	k.crashed.connect(func(s): hits.append(s))
	await _drive(k, 0.4, 0.0, 0.0)
	await _drive(k, 5.0, 0.0, 1.0)
	var biggest: float = hits.max() if not hits.is_empty() else 0.0
	check(biggest > 0.4, "driving into a wall flags a big crash (for screen shake)", "strength %.2f" % biggest)
	check(k.coins == 0, "a wall crash loses every coin")
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


func _test_touch_interruptions() -> void:
	print("touch interruptions")
	var c: Node = root.get_node("/root/Controls")
	var ui = load("res://scripts/ui/touch_controls.gd").new()
	root.add_child(ui)
	ui.size = Vector2(1280, 720)
	c.scheme = Controls.Scheme.TOUCH_BUTTONS
	ui._layout()
	var gas := InputEventScreenTouch.new()
	gas.index = 1
	gas.pressed = true
	gas.position = (ui.buttons["gas"] as Rect2).get_center()
	var brake := InputEventScreenTouch.new()
	brake.index = 2
	brake.pressed = true
	brake.position = (ui.buttons["brake"] as Rect2).get_center()
	ui._input(gas)
	ui._input(brake)
	check(c.touch.gas and c.touch.brake, "two fingers can hold independent pedals")
	brake.pressed = false
	ui._input(brake)
	check(c.touch.gas and not c.touch.brake, "releasing one pedal preserves the other")
	var cancel := InputEventScreenTouch.new()
	cancel.index = 1
	cancel.canceled = true
	ui._input(cancel)
	check(not c.touch.gas and ui._fingers.is_empty(), "cancellation clears held fingers")
	var stick := InputEventScreenTouch.new()
	stick.index = 3
	stick.position = Vector2(200, 600)
	stick.pressed = true
	ui._input(stick)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(280, 600)
	ui._input(drag)
	check(c.touch.steer > 0.5, "dragging the steering finger turns the kart")
	c.release_inputs()
	ui._input(drag)
	check(c.touch.steer == 0.0, "a stale drag cannot restore steering after interruption")
	for interruption in ["focus", "hide", "scheme", "layout"]:
		ui.show()
		c.suspended = false
		ui._input(gas)
		c.touch.steer = 0.8
		c.touch.item = true
		c.steer_from_degrees(30, 1)
		match interruption:
			"focus": c._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			"hide": ui.hide()
			"scheme": c.scheme = Controls.Scheme.TILT
			"layout": ui._layout()
		check(not c.touch.gas and not c.touch.item and c.touch.steer == 0.0 and c._tilt_smoothed == 0.0 and ui._fingers.is_empty(), "%s clears held input and tilt history" % interruption)
	c.auto_gas = true
	c._browser_interrupt([true])
	check(c.read(0.016).throttle == 0.0, "background suspension also blocks automatic throttle")
	c._browser_interrupt([false])
	c.auto_gas = false
	ui.show()
	ui._input(gas)
	check(c.touch.gas, "a fresh touch works after resuming")
	ui.free()
	c.scheme = Controls.Scheme.AUTO


func _test_benchmark_stats() -> void:
	var bench = load("res://scripts/ui/bench.gd")
	var intervals: Array[float] = [10.0, 20.0, 40.0, 60.0, 200.0]
	var result: Dictionary = bench.frame_stats(intervals)
	check(result.p50 == 40.0 and result.p95 == 200.0 and result.p99 == 200.0 and result.max == 200.0, "wall-clock percentiles retain long hitches")
	check(result.over_33ms == 3 and result.over_50ms == 2 and result.over_100ms == 1 and is_equal_approx(result.fps, 15.2), "wall-clock FPS and hitch counts use elapsed intervals")


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


func _test_items() -> void:
	print("items")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	_world.add_child(track)
	var a := Kart.new()
	a.configure("frame", "slicks", "fox")
	a.track = track
	_world.add_child(a)
	var b := Kart.new()
	b.configure("frame", "slicks", "frog")
	b.track = track
	_world.add_child(b)
	var all: Array[Kart] = [a, b]
	var items := Items.new()
	_world.add_child(items)
	items.setup(track, all, all)
	# Collection and respawn reuse the original node and shared mesh.
	var coin: Dictionary = items._coins[0]
	var coin_node: MeshInstance3D = coin["node"]
	var coin_id := coin_node.get_instance_id()
	a.global_position = coin["pos"]
	b.global_position = Vector3(1000, 1000, 1000)
	items._update_coins(0.0)
	check(not coin_node.visible and a.coins == 1, "collecting a coin hides its existing node")
	a.global_position += Vector3.RIGHT * 10.0
	items._update_coins(Items.COIN_RESPAWN + 0.1)
	check(coin_node.visible and coin_node.get_instance_id() == coin_id, "coin respawn reuses the same node")
	check(coin_node.mesh == Items.coin_mesh(), "road and HUD share the cached coin mesh")
	# Park kart A in the first row of crates.
	var d: float = lerpf(Track.BRANCH[0], Track.BRANCH[1], Items.CRATE_ROWS[0])
	var f := track.branch_frame(d)
	a.global_transform = Transform3D(f.basis, f.origin + f.basis.x * Items.CRATE_LANES[1] + Vector3.UP * 0.6)
	await _ticks(90)
	check(a.held_item in Items.KINDS, "driving through a crate gives you an item", a.held_item)
	# Honey: kart B behind drives through it.
	a.held_item = "honey"
	a.global_transform = Transform3D(f.basis, f.origin + Vector3.UP * 0.6)
	b.global_transform = Transform3D(f.basis, f.origin + f.basis.z * 12.0 + Vector3.UP * 0.6)
	await _ticks(10)
	a.input = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false, "item": true}
	await _ticks(2)
	a.input["item"] = false
	check(a.held_item == "", "using an item spends it")
	var stuck := [false]
	b.coins = 10
	for i in 120:
		b.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		await physics_frame
		if b.sticky_time > 0.0:
			stuck[0] = true
	check(stuck[0], "a kart driving through honey gets stuck")
	check(b.coins == 0, "a honey hit loses every coin")
	# Tumbleweed: knocks sideways without spinning round or flipping.
	var c := _kart("frame", "slicks", "fox", Vector3(500, 0.6, 500))
	_pad_under(c.global_position)
	await _ticks(30)
	var yaw0 := c.global_rotation.y
	c.coins = 10
	c.knock(c.global_position + c.global_transform.basis.x * 1.0)
	check(c.coins == 0, "a knock loses every coin immediately")
	var worst := 0.0
	var up := 1.0
	for i in 90:
		c.input = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "drift": false}
		await physics_frame
		worst = maxf(worst, absf(angle_difference(yaw0, c.global_rotation.y)))
		up = minf(up, c.global_transform.basis.y.dot(Vector3.UP))
	check(worst < deg_to_rad(90.0) and up > 0.7, "a tumbleweed hit shoves you but doesn't spin or flip you", "turned %d°, uprightness %.2f" % [int(rad_to_deg(worst)), up])


func _pad_under(p: Vector3) -> void:
	var b := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 2, 80)
	c.shape = box
	c.position = Vector3(p.x, -1, p.z)
	b.add_child(c)
	_world.add_child(b)


## Mining Mountain: bots get round, someone uses the tunnel and someone the
## swaying bridge, and nobody falls off more than now and then.
func _test_mine() -> void:
	print("Mining Mountain")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	track.layout = "mine"
	_world.add_child(track)
	var bots: Array[Kart] = []
	var builds := [["frame", "slicks", "hard"], ["hauler", "knobby", "medium"], ["soapbox", "balloon", "easy"], ["racer", "studded", "hard"]]
	var respawns := [0, 0, 0, 0]
	for i in builds.size():
		var k := Kart.new()
		k.configure(builds[i][0], builds[i][1], "fox")
		k.track = track
		_world.add_child(k)
		k.global_transform = track.grid_transform(i)
		_world.add_child(BotDriver.new(k, track, builds[i][2], i + 7))
		bots.append(k)
		var idx := i
		k.respawned.connect(func(): respawns[idx] += 1)
	var bumps := KartBumps.new()
	bumps.karts = bots
	_world.add_child(bumps)
	var on_branch := {}
	var lap_time := [0.0, 0.0, 0.0, 0.0]
	var t := 0.0
	while t < 200.0:
		await physics_frame
		t += 1.0 / 60.0
		for i in bots.size():
			var k := bots[i]
			if k.lap >= 1 and lap_time[i] == 0.0:
				lap_time[i] = -t
			elif k.lap >= 2 and lap_time[i] < 0.0:
				lap_time[i] = t + lap_time[i]
			var o := track.offset_of(k.global_position)
			var b := track.branch_at(o)
			if b >= 0 and absf(track.branch_offset(o, b)) > 20.0:
				var f := track.branch_frame(o, b)
				if Vector2(f.origin.x - k.global_position.x, f.origin.z - k.global_position.z).length() < Track.ROAD_WIDTH * 0.5:
					on_branch[track.branches[b]["kind"]] = true
		if lap_time.all(func(x): return x > 0.0):
			break
	for i in bots.size():
		check(lap_time[i] > 0.0, "%s bot (%s) laps Mining Mountain" % [builds[i][2], builds[i][0]],
			"lap %.1f s, %d falls, now lap %d at %d m" % [lap_time[i], respawns[i], bots[i].lap, int(track.offset_of(bots[i].global_position))])
	check(respawns.reduce(func(a, x): return a + x, 0) <= 4, "bots rarely fall off the ledge or bridge", "%s" % [respawns])
	check(on_branch.size() >= 2, "bots take both the tunnel and the rope bridge", "%s" % [on_branch.keys()])
	print("  lap length %.0f m" % track.length)
	# A lone kart from pole, straight down the road: nothing to hit.
	bumps.queue_free()
	for b in bots:
		b.queue_free()
	await physics_frame
	var k := Kart.new()
	k.configure("frame", "slicks", "fox")
	k.track = track
	_world.add_child(k)
	k.global_transform = track.grid_transform(0)
	var hits := []
	k.crashed.connect(func(sp): hits.append("%.2f at %d m" % [sp, int(track.offset_of(k.global_position))]))
	for i in 360:
		k.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		await physics_frame
	check(hits.is_empty(), "a clean start on Mining Mountain", "%s" % [hits])
	# Parked in the middle of the rope bridge, well below the road line
	# because of the sag: still on the bridge, so no reset.
	k.queue_free()
	await physics_frame
	var bridge: SwayBridge = track.find_children("*", "SwayBridge", true, false)[0]
	var part: Node3D = bridge._parts[bridge._parts.size() / 2]["body"]
	var resets := [0]
	var why := []
	# At a few points in the sway, so it isn't luck of timing.
	for trial in 4:
		var parked := Kart.new()
		parked.configure("frame", "slicks", "fox")
		parked.track = track
		_world.add_child(parked)
		parked.global_transform = Transform3D(part.global_transform.basis, part.global_position + Vector3.UP * 0.5)
		parked.respawned.connect(func(): resets[0] += 1; why.append(parked.respawn_reason))
		for i in 150:
			parked.input = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false}
			await physics_frame
		parked.queue_free()
		for i in 37 + trial * 23:
			await physics_frame
	check(resets[0] == 0, "sitting on the sagging bridge doesn't reset you", "%d resets %s" % [resets[0], why])


func _test_frost() -> void:
	print("Frosty Pass")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	track.layout = "frost"
	_world.add_child(track)
	await physics_frame
	# The junction must cover the full drivable width of BOTH paths. Test
	# the polygon and actual colliders, which use the same rendered mesh.
	var coverage_ok := true
	var collision_ok := true
	for zone in RoadJunction.ranges(track):
		var data := RoadJunction.model(track, zone)
		coverage_ok = coverage_ok and not (data["indices"] as PackedInt32Array).is_empty()
		for key in ["main", "branch"]:
			var rows: Array[Transform3D] = data[key]
			for row in rows:
				for x in [-6.0, -3.0, 0.0, 3.0, 6.0]:
					var p: Vector3 = row.origin + row.basis.x * x
					coverage_ok = coverage_ok and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), data["polygon"])
					var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p - Vector3.UP * 3.0)
					var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
					collision_ok = collision_ok and not hit.is_empty() and (hit["collider"] as Node).get_meta("surface", "") == "asphalt" and absf((hit["position"] as Vector3).y - p.y) < 0.5
	check(coverage_ok, "Frost junction polygons cover both roads across their full driving width")
	check(collision_ok, "Frost junction meshes provide continuous collision under both roads")
	# Dropped through a hole in the ice: lands on the sunken road under the
	# lake, isn't reset, and can drive on out the far end.
	var span := FrostTrack.lake_span(track)
	var h: Array = FrostTrack.HOLES[2]
	var f := track.transform_at(lerpf(span.x, span.y, float(h[0])))
	var k := Kart.new()
	k.configure("frame", "studded", "fox")
	k.track = track
	_world.add_child(k)
	k.global_transform = Transform3D(f.basis, f.origin + f.basis.x * float(h[1]) + Vector3.UP * 1.5)
	var resets := []
	k.respawned.connect(func(): resets.append(k.respawn_reason))
	var lowest := 99.0
	for i in 120:
		k.input = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false}
		await physics_frame
		lowest = minf(lowest, k.global_position.y)
	check(lowest < -5.0 and resets.is_empty(), "falling through the ice lands on the sunken road", "lowest %.1f m, resets %s" % [lowest, resets])
	# At full racing speed, straight over a hole: you still go through.
	var h2: Array = FrostTrack.HOLES[3]
	var hf := track.transform_at(lerpf(span.x, span.y, float(h2[0])))
	var hc: Vector3 = hf.origin + hf.basis.x * float(h2[1])
	var fast := Kart.new()
	fast.configure("racer", "slicks", "fox")
	fast.track = track
	_world.add_child(fast)
	fast.global_transform = Transform3D(hf.basis, hc + hf.basis.z * 30.0 + Vector3.UP * 0.6)
	fast.linear_velocity = -hf.basis.z * 27.0
	var low2 := 99.0
	for i in 150:
		fast.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		await physics_frame
		low2 = minf(low2, fast.global_position.y)
	check(low2 < -4.0, "flat out over a hole, you still drop through", "lowest %.1f m" % low2)
	fast.queue_free()
	# Drive on (steering for the shortcut's line) and come up the far end.
	var out := false
	for i in 900:
		var o := track.offset_of(k.global_position)
		var aim := track.transform_at(o + 12.0).origin
		# Weave round the sunken boulders.
		for r in FrostTrack.SUNKEN_ROCKS:
			var rf := track.transform_at(lerpf(span.x, span.y, float(r[0])))
			var rp: Vector3 = rf.origin + rf.basis.x * float(r[1])
			if Vector2(rp.x - aim.x, rp.z - aim.z).length() < 4.5:
				aim += rf.basis.x * (6.0 if float(r[1]) <= 0.0 else -6.0)
		var to := (aim - k.global_position)
		var steer := clampf(k.global_transform.basis.x.dot(to.normalized()) * 2.0, -1.0, 1.0)
		k.input = {"steer": steer, "throttle": 1.0, "brake": 0.0, "drift": false}
		await physics_frame
		if k.global_position.y > -0.3 and o > span.y:
			out = true
			break
	check(out and resets.is_empty(), "the sunken road climbs out at the far shore", "y %.1f at %d m (lake ends %d), resets %s" % [k.global_position.y, int(track.offset_of(k.global_position)), int(span.y), resets])
	k.queue_free()
	await physics_frame
	# Computer drivers lap it, and use both ways round the lake.
	var bots: Array[Kart] = []
	var builds := [["frame", "studded", "hard"], ["hauler", "knobby", "medium"], ["soapbox", "balloon", "easy"], ["racer", "studded", "hard"]]
	var respawns := [0, 0, 0, 0]
	for i in builds.size():
		var b := Kart.new()
		b.configure(builds[i][0], builds[i][1], "fox")
		b.track = track
		_world.add_child(b)
		b.global_transform = track.grid_transform(i)
		_world.add_child(BotDriver.new(b, track, builds[i][2], i + 7))
		bots.append(b)
		var idx := i
		b.respawned.connect(func(): respawns[idx] += 1)
	var lap_time := [0.0, 0.0, 0.0, 0.0]
	var on_lake := false
	var on_detour := false
	var di := FrostTrack.detour_branch(track)
	var t := 0.0
	while t < 220.0:
		await physics_frame
		t += 1.0 / 60.0
		for i in bots.size():
			var b := bots[i]
			if b.lap >= 1 and lap_time[i] == 0.0:
				lap_time[i] = -t
			elif b.lap >= 2 and lap_time[i] < 0.0:
				lap_time[i] = t + lap_time[i]
			if FrostTrack.in_lake(b.global_position, 0.9):
				on_lake = true
			var bo := track.offset_of(b.global_position)
			if track.branch_at(bo) == di and Vector2(b.global_position.x - track.branch_frame(bo, di).origin.x, b.global_position.z - track.branch_frame(bo, di).origin.z).length() < 8.0 and absf(track.branch_offset(bo, di)) > 25.0:
				on_detour = true
		if lap_time.all(func(x): return x > 0.0):
			break
	for i in bots.size():
		check(lap_time[i] > 0.0, "%s bot (%s) laps Frosty Pass" % [builds[i][2], builds[i][0]],
			"lap %.1f s, %d resets, now lap %d at %d m" % [lap_time[i], respawns[i], bots[i].lap, int(track.offset_of(bots[i].global_position))])
	check(on_lake and on_detour, "bots cross the frozen lake, and some take the detour", "lake %s, detour %s" % [on_lake, on_detour])
	check(respawns.reduce(func(a, x): return a + x, 0) <= 6, "bots rarely need resetting on Frosty Pass", "%s" % [respawns])
	print("  lap length %.0f m" % track.length)
