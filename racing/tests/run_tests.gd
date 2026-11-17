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
	_test_coin_counter_size()
	_test_tree_assets()
	_test_wheel_arch_clearance()
	await _test_rear_end_bump()
	_test_wheel_bumps()
	await _test_boulder_is_not_a_ramp()
	await _test_bots_lap_the_track()
	await _test_fall_off_respawns()
	await _test_clean_start()
	await _test_items()
	await _test_mine()
	await _test_frost()
	await _test_launch_gap()
	await _test_kit_dress()
	await _test_space()
	await _test_track_fx()
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
	var bench = load("res://scripts/benchmark/bench.gd")
	var intervals: Array[float] = [10.0, 20.0, 40.0, 60.0, 200.0]
	var result: Dictionary = bench.frame_stats(intervals)
	check(result.p50 == 40.0 and result.p95 == 200.0 and result.p99 == 200.0 and result.max == 200.0, "wall-clock percentiles retain long hitches")
	check(result.over_33ms == 3 and result.over_50ms == 2 and result.over_100ms == 1 and is_equal_approx(result.fps, 15.2), "wall-clock FPS and hitch counts use elapsed intervals")


func _test_coin_counter_size() -> void:
	var counter = load("res://scripts/ui/coin_counter.gd").new()
	root.add_child(counter)
	for child in counter.get_children():
		if child is TextureRect:
			check(child.size.y <= ThemeDB.fallback_font.get_height(20), "HUD coin respects the text height despite its larger render texture")
	counter.free()


func _test_tree_assets() -> void:
	var budgets := {"tree_puffy": 900, "pine_tall": 750, "tree_round": 750, "snowpine_tall": 750, "snowpine_round": 650}
	var shared: Material
	for name in budgets:
		var scene: PackedScene = load("res://assets/models/%s.glb" % name)
		var instance := scene.instantiate()
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		var mesh: Mesh = meshes[0].mesh
		var arrays := mesh.surface_get_arrays(0)
		var triangles := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		check(mesh.get_surface_count() == 1 and triangles > 0 and triangles <= budgets[name], "%s import stays within one surface and its triangle budget" % name)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var styled := Palette.restyle(mesh)
		var mat: ShaderMaterial = styled.surface_get_material(0)
		if shared == null:
			shared = mat
		check(colors.size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() and mat == shared and mat.shader != null, "%s preserves linear vertex colours with the shared tree material" % name)
		instance.free()


func _test_wheel_arch_clearance() -> void:
	var ok := true
	var count := 0
	for style in ["frame", "hauler"]:
		for tires in Parts.TIRES:
			var k := Kart.new()
			k.configure(style, tires, "fox")
			var visual = load("res://scripts/kart/kart_visual.gd").new(k, false)
			for part in visual._model_parts(visual.MODELS[style]):
				if not (String(part[0]).begins_with("Paint_fender") or String(part[0]).begins_with("Trim_arch")):
					continue
				var arch := MeshInstance3D.new()
				arch.mesh = part[1]
				arch.transform = Transform3D(Basis.IDENTITY, Vector3.UP * (0.25 - Kart.SUSPENSION_TRAVEL * 0.6 - 0.3)) * part[2]
				visual._fit_wheel_arch(arch)
				var bounds := arch.transform * arch.mesh.get_aabb()
				ok = ok and bounds.end.y >= k.wheel_mount(0).y + k.wheel_radius() + 0.1
				count += 1
				arch.free()
			visual.free()
			k.free()
	check(ok and count == 24, "all frame and hauler tyre builds have arch crown clearance at full compression")


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


func _test_wheel_bumps() -> void:
	_pad()
	var a := _kart("frame", "balloon")
	var b := _kart("frame", "balloon")
	var bumps := KartBumps.new()
	var half := bumps.half_extents(a)
	b.global_position = a.global_position + Vector3.RIGHT * (half.x * 2.0 - 0.02)
	b.linear_velocity = Vector3.LEFT * 6.0
	a.coins = 10
	b.coins = 10
	check(b.global_position.x - a.global_position.x > float(a.chassis["size"].x), "wheel contact begins while chassis boxes are still apart")
	bumps._pair(a, b)
	check(a.linear_velocity.x < 0.0 and b.linear_velocity.x > -6.0, "tyre-edge contact trades speed")
	check(a.coins == 0 and b.coins == 0, "a solid kart-to-kart crash loses all coins")
	check(b.global_position.x - a.global_position.x >= half.x * 2.0 - 0.001, "wheel footprints separate after a bump")
	a.steer_angle = float(a.chassis["max_steer"])
	check(bumps.half_extents(a).x > half.x, "front-wheel steering expands the contact footprint")
	b.global_position = a.global_position + Vector3(0, 2, 0)
	var before := a.linear_velocity
	bumps._pair(a, b)
	check(a.linear_velocity == before, "vertically separated karts do not bump")
	bumps.free()


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
	# Collection and respawn reuse the coin's slot in its batch, and the
	# shared mesh. (Coins are drawn in batches: one draw call a line.)
	var coin: Dictionary = items._coins[0]
	var coin_node: Items.Slot = coin["node"]
	var coin_id := coin_node.get_instance_id()
	a.global_position = coin["pos"]
	b.global_position = Vector3(1000, 1000, 1000)
	items._update_coins(0.0)
	check(not coin_node.visible and a.coins == 1, "collecting a coin hides it")
	a.global_position += Vector3.RIGHT * 10.0
	items._update_coins(Items.COIN_RESPAWN + 0.1)
	check(coin_node.visible and coin_node.get_instance_id() == coin_id, "coin respawn reuses the same slot")
	var coin_batch: Items.Batch = items._batches.values().filter(func(b): return (b as Items.Batch).slots.has(coin_node))[0]
	check(coin_batch.parts[0][0] == Items.coin_mesh(), "road and HUD share the cached coin mesh")
	check(items._batches.size() < items._coins.size() + items._crates.size(), "coins and boxes share batches (%d batches for %d things)" % [items._batches.size(), items._coins.size() + items._crates.size()])
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
	var rollers: FrostTrack.Rollers
	for child in track.get_children():
		if child is FrostTrack.Rollers:
			rollers = child
	var clock_before := rollers._clock()
	await _ticks(6)
	check(is_equal_approx(rollers._clock() - clock_before, 0.1), "offline snowballs advance on physics time, independent of runner speed")
	var merge_smooth := true
	var merge_d := track._flat_to - 2.0
	while merge_d < track._flat_to + 62.0:
		merge_smooth = merge_smooth and absf(track.transform_at(merge_d + 0.5).origin.y - track.transform_at(merge_d).origin.y) < 0.1
		merge_d += 0.5
	check(merge_smooth, "lake merge restores road height gradually without a steep bank-lift step")
	var icy_support := true
	var icy_samples := 0
	for zone: Array in track.ice_bank_zones:
		var d := float(zone[0]) * track.length + 12.0
		while d < float(zone[1]) * track.length - 12.0:
			var turn := track._flat_dir(d - 8.0).signed_angle_to(track._flat_dir(d + 8.0), Vector3.UP)
			if absf(turn) > 0.1:
				var frame := track.road_frame(d)
				icy_support = icy_support and signf(frame.basis.x.y) == signf(turn) and absf(track.bank_at(d)) >= deg_to_rad(7.9)
				icy_samples += 1
			d += 2.0
	check(icy_support and icy_samples > 0, "icy bends bank their outside edge upward with gentle minimum support")
	# Ice comes in short patches with dry road between, not long slides.
	var ice_patches := 0
	var longest_ice := 0.0
	for zone in track.surface_zones:
		if zone["surface"] == "ice":
			ice_patches += 1
			longest_ice = maxf(longest_ice, (float(zone["to"]) - float(zone["from"])) * track.length)
	check(ice_patches >= 4 and longest_ice <= 15.0, "Frosty Pass ice is short patches (%d, longest %.0f m)" % [ice_patches, longest_ice])

	# Sand gun: Frosty Pass only; sprays an S of sand ahead for 5 s; sand
	# makes ice grip like road, then blows away.
	var sk := Kart.new()
	sk.configure("frame", "slicks", "fox")
	sk.track = track
	_world.add_child(sk)
	var sall: Array[Kart] = [sk]
	var sitems := Items.new()
	_world.add_child(sitems)
	sitems.setup(track, sall, sall)
	check("sandgun" in sitems.pool(), "the sand gun is in Frosty Pass crates")
	var patch: Dictionary = {}
	for zone in track.surface_zones:
		if zone["surface"] == "ice":
			patch = zone
			break
	var pd := (float(patch["from"]) + float(patch["to"])) * 0.5 * track.length
	var pf := track.road_frame(pd)
	sk.global_transform = Transform3D(pf.basis, pf.origin + Vector3.UP * 0.6)
	await _ticks(20)
	check(sk.surface_name == "ice", "a kart on an ice patch is on ice", sk.surface_name)
	# Spray from behind the patch, so the S lands on it.
	sk.global_transform = Transform3D(pf.basis, pf.origin + pf.basis.z * Items.SAND_AHEAD + Vector3.UP * 0.6)
	sk.linear_velocity = Vector3.ZERO
	sitems.spawn("sandgun", sk.global_position, -pf.basis.z, 7)
	await _ticks(int(Items.SPRAY_TIME * 60.0) - 30)
	var left := false
	var right := false
	for pile in Items.sand:
		var side := ((pile[0] as Vector3) - sk.global_position).dot(sk.global_transform.basis.x)
		left = left or side < -2.5
		right = right or side > 2.5
	check(Items.sand.size() > 25 and left and right, "the spray lays sand weaving to both sides", str(Items.sand.size()))
	await _ticks(60)
	var piles := Items.sand.size()
	await _ticks(30)
	check(Items.sand.size() <= piles and sitems._sprays.is_empty(), "spraying stops after 5 seconds")
	sk.global_transform = Transform3D(pf.basis, pf.origin + Vector3.UP * 0.6)
	sk.linear_velocity = Vector3.ZERO
	Items.sand.append([pf.origin, Items.SAND_LIFE])
	await _ticks(20)
	check(sk.surface_name == "asphalt", "ice under sand grips like road", sk.surface_name)
	await _ticks(int(Items.SAND_LIFE * 60.0) + 10)
	check(Items.sand.is_empty(), "sand blows away after %d seconds" % Items.SAND_LIFE)
	sk.global_transform = Transform3D(pf.basis, pf.origin + Vector3.UP * 0.6)
	sk.linear_velocity = Vector3.ZERO
	await _ticks(20)
	check(sk.surface_name == "ice", "and the ice is slippery again", sk.surface_name)

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


## Launch gaps (design doc 8.4), on the proving ground.
func _test_launch_gap() -> void:
	print("Launch gaps")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	track.layout = "proving"
	_world.add_child(track)
	await physics_frame
	await physics_frame
	check(track.gaps.size() == 1, "the proving ground has a launch gap")
	var lip: float = track.gaps[0][0]
	var landing: float = track.gaps[0][1]
	check(landing - lip > 30.0, "the gap is a real gap (%.0f m)" % (landing - lip))
	# Nothing to stand on in the gap; road either side of it.
	var space := _world.get_world_3d().direct_space_state
	var probe := func(d: float) -> bool:
		var p := track.road_frame(d).origin
		return not space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 4.0)).is_empty()
	check(not probe.call((lip + landing) * 0.5) and not probe.call(lip + 6.0), "there is no road in the gap")
	check(probe.call(lip - 4.0) and probe.call(landing + 4.0), "and road at the lip and the landing")
	# A kart on the floor beside a raised road is off it (it can't climb back).
	var beside := Kart.new()
	beside.configure("frame", "slicks", "fox")
	beside.track = track
	_world.add_child(beside)
	var near := track.road_frame(lip - 20.0)
	beside.global_position = near.origin + near.basis.x * 15.0 + Vector3.DOWN * 4.0
	check(beside._fallen_off(), "a kart well below a Series 2 road counts as off it")
	beside.global_position = near.origin + Vector3.UP * 0.5
	check(not beside._fallen_off(), "and one on the road doesn't")
	beside.free()
	# Karts arriving fast, slow and off-centre all land beyond it, upright.
	# Two press drift at the lip: a trick (a somersault, and a boost on
	# landing). The others just fly it.
	var cases := [["fast", 32.0, 0.0, true], ["slow", 6.0, 0.0, false], ["off-centre", 26.0, 4.5, true], ["off the other side", 18.0, -4.5, false]]
	for c: Array in cases:
		var k := Kart.new()
		k.configure("frame", "slicks", "fox")
		k.track = track
		_world.add_child(k)
		var vis := Node3D.new()
		k.add_child(vis)
		k.set_meta("visual", vis)
		var all: Array[Kart] = [k]
		var launch := LaunchGaps.new()
		launch.setup(track, all)
		_world.add_child(launch)
		var f := track.road_frame(lip - 14.0)
		k.global_transform = Transform3D(f.basis, f.origin + f.basis.x * float(c[2]) + Vector3.UP * 0.6)
		k.linear_velocity = -f.basis.z * float(c[1])
		var flew := false
		var flipped := 0.0
		var resets := [0]
		k.respawned.connect(func(): resets[0] += 1)
		var boosted := false
		for i in 60 * 7:
			var to_lip := lip - track.offset_of(k.global_position)
			k.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": bool(c[3]) and to_lip > 0.0 and to_lip < 2.5}
			await physics_frame
			if launch.flying(k):
				flew = true
				flipped = maxf(flipped, absf(vis.transform.basis.get_euler().x) + (PI if vis.transform.basis.y.y < 0.0 else 0.0))
			elif flew:
				boosted = k.boost_time > 0.0
				break
		await _ticks(40)
		var off := track.offset_of(k.global_position)
		var local := track.road_local(k.global_position)
		check(flew and resets[0] == 0 and off > landing and absf(local.x) < Track.ROAD_WIDTH * 0.5 and absf(local.y) < 1.5,
			"a %s kart flies the gap and lands on the road" % c[0], "flew %s resets %d off %.0f (landing %.0f) local %s" % [flew, resets[0], off, landing, local])
		check(k.global_transform.basis.y.dot(Vector3.UP) > 0.9 and vis.transform.is_equal_approx(Transform3D.IDENTITY),
			"and comes down wheels-first", "up %.2f" % k.global_transform.basis.y.dot(Vector3.UP))
		if c[3]:
			check(flipped > 2.0 and boosted, "a trick off the lip somersaults and boosts on landing", "flipped %.1f boosted %s" % [flipped, boosted])
		else:
			check(flipped < 0.2 and not boosted, "no trick: no somersault, no boost (and no penalty)", "flipped %.1f boosted %s" % [flipped, boosted])
		launch.free()
		k.free()


## Zones and timed hazards (TrackFx), on the proving ground.
func _test_track_fx() -> void:
	print("Zones and timed hazards")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	track.layout = "proving"
	_world.add_child(track)
	await physics_frame
	await physics_frame
	var k := Kart.new()
	k.configure("frame", "slicks", "fox")
	k.track = track
	_world.add_child(k)
	var all: Array[Kart] = [k]
	var fx := TrackFx.new()
	_world.add_child(fx)
	fx.setup(track, all)
	var zone := func(kind: String) -> Dictionary:
		for z in track.fx_zones:
			if z["kind"] == kind:
				return z
		return {}
	var park := func(d: float, x := 0.0, speed := 0.0) -> void:
		var f := track.road_frame(d)
		k.global_transform = Transform3D(f.basis, f.origin + f.basis.x * x + Vector3.UP * 0.6)
		k.linear_velocity = -f.basis.z * speed
		k.angular_velocity = Vector3.ZERO
	# Gravity.
	var g: Dictionary = zone.call("gravity")
	park.call((float(g["from"]) + float(g["to"])) * 0.5)
	await _ticks(5)
	check(is_equal_approx(k.gravity_scale, 0.4), "gravity is lighter inside a gravity zone", str(k.gravity_scale))
	park.call(float(g["to"]) + 12.0)
	await _ticks(5)
	check(is_equal_approx(k.gravity_scale, 1.0), "and normal again outside it", str(k.gravity_scale))
	# Drag: the same roll loses more speed in the water.
	var dz: Dictionary = zone.call("drag")
	k.input = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "drift": false}
	park.call(float(dz["from"]) + 2.0, 0.0, 18.0)
	await _ticks(40)
	var wet := k.linear_velocity.length()
	park.call(float(g["to"]) + 12.0, 0.0, 18.0)
	await _ticks(40)
	var dry := k.linear_velocity.length()
	check(wet < dry - 2.0, "a drag zone slows a rolling kart", "wet %.1f dry %.1f" % [wet, dry])
	# Wind: pushed one way, then the other, as the gust swings.
	var w: Dictionary = zone.call("wind")
	var pushes := {}
	for i in 2:
		fx._elapsed = float(w["period"]) * (0.25 + 0.5 * i)   # full gust each way
		park.call((float(w["from"]) + float(w["to"])) * 0.5)
		var right := track.road_frame((float(w["from"]) + float(w["to"])) * 0.5).basis.x
		await _ticks(20)
		pushes[i] = k.linear_velocity.dot(right)
	check(pushes[0] > 0.2 and pushes[1] < -0.2, "wind pushes a kart sideways, swinging both ways", str(pushes))
	# A timed jet: knocks a kart in its half of the road while live, and
	# leaves alone a kart in the other half, or one there while it's off.
	var h: Dictionary = track.fx_hazards[0]
	var live_h: Dictionary = fx.hazards[0]
	fx._elapsed = 0.2   # live
	park.call(float(h["at"]), -3.5)
	await _ticks(6)
	check((live_h["hit"] as Dictionary).has(k), "a live jet knocks a kart in it")
	fx._elapsed = 2.0   # off: its record of who it hit clears
	await _ticks(3)
	fx._elapsed = 0.2
	park.call(float(h["at"]), 4.0)
	await _ticks(6)
	check(not (live_h["hit"] as Dictionary).has(k), "but not a kart in the clear half of the road")
	fx._elapsed = 2.0
	park.call(float(h["at"]), -3.5)
	await _ticks(6)
	check(not (live_h["hit"] as Dictionary).has(k), "nor one passing while it's off")
	check(TrackFx.live(h, 0.2) and not TrackFx.live(h, 2.0), "the jet follows its timer")
	# A kart just knocked is let through for a moment, then hazards count again.
	fx._knocked[k] = 10.0
	check(fx.spared(k, 12.0) and not fx.spared(k, 10.0 + TrackFx.GRACE + 0.5), "a knocked kart gets a few seconds' grace from hazards")


## Trackside dressing for Series 2 (design doc 8.5).
func _test_kit_dress() -> void:
	print("Trackside dressing")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	track.layout = "proving"
	_world.add_child(track)
	await physics_frame
	# Variety comes from where a thing stands, so it's the same in every game.
	var here := Transform3D(Basis(), Vector3(12.5, 0, -40.25))
	check(KitDress.varied(here, 1.0, 0.3).is_equal_approx(KitDress.varied(here, 1.0, 0.3)), "a prop's size and turn depend only on its place")
	check(not KitDress.varied(here).basis.is_equal_approx(KitDress.varied(Transform3D(Basis(), Vector3(80, 0, 3))).basis), "and differ from place to place")
	# Spots beside the road face it, clear of the kerb, and skip launch gaps.
	var lip: float = track.gaps[0][0]
	var landing: float = track.gaps[0][1]
	var spots := KitDress.beside(track, lip - 30.0, landing + 30.0, 5.0, 3.0)
	var ok := not spots.is_empty()
	for x in spots:
		var local := track.road_local(x.origin)
		var to_road := (track.road_frame(track.offset_of(x.origin)).origin - x.origin).normalized()
		if absf(local.x) < Track.ROAD_WIDTH * 0.5 + 2.0 or (-x.basis.z).dot(to_road) < 0.8 or track.in_gap(track.offset_of(x.origin)):
			ok = false
	check(ok, "spots beside the road face it from beyond the kerb, none in a gap", "%d spots" % spots.size())
	check(KitDress.off_road(track, track.road_frame(50.0).origin + Vector3(0, 0, 0), 5.0) == false and KitDress.off_road(track, Vector3(5000, 0, 5000), 30.0), "scenery can tell road from open ground")
	# A mover carries its copies round its loop, evenly spaced.
	var loop := PackedVector3Array([Vector3(0, 5, 0), Vector3(40, 5, 0), Vector3(40, 5, 40), Vector3(0, 5, 40)])
	var m := KitDress.mover(_world, "boat", loop, 10.0, 4, {"level": true})
	var before := m.where(0).origin
	for i in 30:
		await process_frame
	var after := m.where(0).origin
	check(after.distance_to(before) > 0.5, "things on a path move by themselves", "%.1f m" % after.distance_to(before))
	check(m.where(0).origin.distance_to(m.where(2).origin) > 20.0, "and keep apart round the loop")
	check(absf(m.where(1).basis.y.y - 1.0) < 0.01, "level ones stay upright")
	# The three tracks have their research-led set pieces.
	check(Track.kit_of("funfair") != null and Track.kit_of("windy") != null, "kits are registered")


## The space track (design doc 8.6): crater lips that send you where you
## steer, gliders on long jumps, falling only when hit in the air, vents
## that blow you off and put you back, and craters you can drive round.
func _test_space() -> void:
	print("Cosmic Crossing")
	if _world:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	var track := Track.new()
	track.layout = "starliner"
	_world.add_child(track)
	await physics_frame
	await physics_frame
	var C: Dictionary = StarlinerTrack.CRATERS
	var zone_of := func(key: String) -> int:
		var c: Vector2 = C[key]
		for i in track.free_zones.size():
			var z: Vector3 = track.free_zones[i][0]
			if Vector2(z.x, z.z).distance_to(c) < 1.0:
				return i
		return -1
	check(track.free_zones.size() == 5 and track.pads.size() == 7, "five craters, seven lips (three out of the first)", "%d zones %d pads" % [track.free_zones.size(), track.pads.size()])
	# Off the road inside a crater is still on the track.
	var probe := Kart.new()
	probe.configure("frame", "slicks", "fox")
	probe.track = track
	_world.add_child(probe)
	var t0: Vector2 = C["T"]
	probe.global_position = Vector3(t0.x + 14.0, StarlinerTrack.ground(t0 + Vector2(14, 0), "moon") + 0.6, t0.y)
	check(not probe._fallen_off(), "a kart driving round a crater's bowl is not off the road")
	probe.free()
	# Out of the first crater, where you steer decides where you land.
	for want: String in ["M", "L", "R"]:
		var target: Vector2 = C[want]
		var dir2 := (target - t0).normalized()
		var dir := Vector3(dir2.x, 0, dir2.y)
		var k := _space_kart(track)
		var at := t0 + dir2 * (StarlinerTrack.CR - 6.0)
		k.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(at.x, StarlinerTrack.ground(at, "moon") + 0.8, at.y))
		k.linear_velocity = dir * 20.0
		var launch := _space_launch(track, k)
		var flew := false
		for i in 60 * 6:
			k.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
			await physics_frame
			if launch.flying(k):
				flew = true
			elif flew:
				break
		await _ticks(20)
		check(flew and track.free_zone_at(k.global_position) == zone_of.call(want), "out over the lip towards %s, it lands in %s" % [want, want],
			"flew %s zone %d at %s" % [flew, track.free_zone_at(k.global_position), k.global_position.round()])
		launch.free()
		k.free()
	# The last crater fires you to the red planet under a glider, and you
	# land on its road.
	var b0: Vector2 = C["B"]
	var k2 := _space_kart(track)
	var at2 := b0 + Vector2(0, -(StarlinerTrack.CR - 6.0))
	k2.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(at2.x, StarlinerTrack.ground(at2, "moon") + 0.8, at2.y))
	k2.linear_velocity = Vector3.FORWARD * 20.0
	var launch2 := _space_launch(track, k2)
	var glided := false
	var flew2 := false
	var hit := false
	for i in 60 * 10:
		k2.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		await physics_frame
		if launch2.flying(k2):
			flew2 = true
			for c in (k2.get_meta("visual") as Node3D).get_children():
				if c is MeshInstance3D:
					glided = true
		elif flew2:
			break
	await _ticks(30)
	check(flew2 and glided and StarlinerTrack.world_of(k2.global_position) == "mars" and absf(track.road_local(k2.global_position).x) < Track.ROAD_WIDTH * 0.5,
		"the last crater launches you, gliding, onto the red planet's road", "glided %s at %s" % [glided, k2.global_position.round()])
	check((k2.get_meta("visual") as Node3D).get_child_count() == 0, "and the glider folds away when you land")
	# Hit by an item in the air: you fall, and are put back before the lip.
	k2.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(at2.x, StarlinerTrack.ground(at2, "moon") + 0.8, at2.y))
	k2.linear_velocity = Vector3.FORWARD * 20.0
	var put_back := [0]
	k2.respawned.connect(func(): put_back[0] += 1)
	for i in 60 * 6:
		k2.input = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		await physics_frame
		if launch2.flying(k2) and not hit and k2.global_position.distance_to(Vector3(at2.x, k2.global_position.y, at2.y)) > 60.0:
			k2.knock(k2.global_position + Vector3.RIGHT)
			hit = true
		if put_back[0] > 0:
			break
	check(hit and put_back[0] == 1 and StarlinerTrack.world_of(k2.global_position) == "moon" and not launch2.flying(k2),
		"hit by an item in the air, you fall and are put back on the moon", "hit %s put back %d at %s" % [hit, put_back[0], k2.global_position.round()])
	launch2.free()
	k2.free()
	# A saucer vent sputters first, then blows you off and puts you back.
	var vent: Dictionary = {}
	for h: Dictionary in track.fx_hazards:
		if h.get("blow", false):
			vent = h
			break
	check(not vent.is_empty() and TrackFx.live(vent, 0.0 - float(vent["phase"]) + 0.1) and not TrackFx.live(vent, float(vent["period"]) - float(vent["phase"]) - float(vent["warn"]) * 0.5),
		"the saucer has vents that warn before they blow")
	var k3 := _space_kart(track)
	var all: Array[Kart] = [k3]
	var fx := TrackFx.new()
	fx.setup(track, all)
	_world.add_child(fx)
	var vf := track.road_frame(float(vent["at"]))
	k3.global_transform = Transform3D(vf.basis, vf.origin + vf.basis.x * (float(vent["from_x"]) + float(vent["to_x"])) * 0.5 + Vector3.UP * 0.6)
	fx._elapsed = fposmod(-float(vent["phase"]), float(vent["period"])) + 0.2
	var rose := 0.0
	var back := [0]
	k3.respawned.connect(func(): back[0] += 1)
	for i in 60 * 3:
		await physics_frame
		rose = maxf(rose, k3.global_position.y - vf.origin.y)
		if back[0] > 0:
			break
	check(rose > 8.0 and back[0] == 1 and StarlinerTrack.world_of(k3.global_position) == "saucer",
		"a vent blows you up into space, then you're put back on the saucer", "rose %.1f put back %d" % [rose, back[0]])
	fx.free()
	k3.free()
	# The shoulders slow you; the road doesn't.
	var f := track.road_frame(track.length - 40.0)
	var space := _world.get_world_3d().direct_space_state
	var surface_at := func(x: float) -> String:
		var p := f.origin + f.basis.x * x
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0))
		return String((r["collider"] as Object).get_meta("surface", "?")) if not r.is_empty() else "none"
	check(surface_at.call(11.0) == "moondust" and Parts.surface("moondust")["drag"] > 0.5 and surface_at.call(0.0) == "asphalt",
		"dust shoulders beside the road slow you", "%s / %s" % [surface_at.call(0.0), surface_at.call(11.0)])


func _space_kart(track: Track) -> Kart:
	var k := Kart.new()
	k.configure("frame", "slicks", "fox")
	k.track = track
	_world.add_child(k)
	var vis := Node3D.new()
	k.add_child(vis)
	k.set_meta("visual", vis)
	return k


func _space_launch(track: Track, k: Kart) -> LaunchGaps:
	var all: Array[Kart] = [k]
	var launch := LaunchGaps.new()
	launch.setup(track, all)
	_world.add_child(launch)
	return launch
