extends SceneTree
## Headless checks for Hide and Seek. Run with:
##   godot --headless --path hideseek --fixed-fps 60 -s tests/run_tests.gd
## Ends with "hide and seek checks: N failures".

var failures := 0
var passes := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(120.0)
	watchdog.timeout.connect(func():
		print("FAIL  timed out")
		print("hide and seek checks: 1 failures")
		quit(1))
	_test_prop_pool()
	_test_rerolls()
	_test_ammo_and_finding()
	_test_spark_schedule()
	_test_paint_fade()
	await _test_bale_jumps_onto_stack()
	await _test_seeker_jumps_onto_stack()
	await _test_jump_height()
	await _test_rake_leans_on_lock()
	await _test_paintball_hits()
	await _test_edge_flash()
	print("\n%d passed, %d failed" % [passes, failures])
	print("hide and seek checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func check(ok: bool, name: String, detail := "") -> void:
	if ok:
		passes += 1
		print("  ok   ", name, "  ", detail)
	else:
		failures += 1
		print("  FAIL ", name, "  ", detail)


func _test_prop_pool() -> void:
	var pool := TestBarn.pool()
	var counts := {}
	for s in TestBarn.scenery():
		counts[s[0]] = counts.get(s[0], 0) + 1
	check(pool.all(func(k): return Props.KINDS.has(k)), "pool props all have models", str(pool))
	check(pool.all(func(k): return counts[k] >= 2), "every hider prop appears at least twice as scenery", str(counts))
	for k in ["bale", "trash_can", "tire", "chair", "rake"]:
		check(pool.has(k), "pool has the owner's idea: " + k)
	var spot_kinds := TestBarn.SPOTS.map(func(s): return s[0])
	check(spot_kinds.all(func(k): return pool.has(k)), "hiding spots only use pool props")


func _test_rerolls() -> void:
	var r := HideRules.new(TestBarn.pool(), 7)
	r.add_hider("h")
	var first: String = r.players["h"]["prop"]
	check(TestBarn.pool().has(first), "hider gets a random prop from the pool", first)
	var a := r.reroll("h")
	var second: String = r.players["h"]["prop"]
	var b := r.reroll("h")
	var third: String = r.players["h"]["prop"]
	check(a and b and second != first and third != second, "two rerolls, each a different prop", "%s > %s > %s" % [first, second, third])
	check(not r.reroll("h") and r.players["h"]["prop"] == third, "a third reroll is refused")
	var seen := {}
	for s in 40:
		var rr := HideRules.new(TestBarn.pool(), s)
		rr.add_hider("x")
		seen[rr.players["x"]["prop"]] = true
	check(seen.size() == TestBarn.pool().size(), "random assignment reaches every prop", str(seen.keys()))


func _test_ammo_and_finding() -> void:
	var r := HideRules.new(TestBarn.pool(), 1)
	r.add_seeker("s")
	r.add_hider("h1")
	r.add_hider("h2")
	var shots := 0
	while r.shoot("s"):
		shots += 1
	check(shots == HideRules.START_AMMO, "a seeker has %d paintballs, then can't shoot" % HideRules.START_AMMO, str(shots))
	check(r.winner(60.0) == "hiders", "hiders win when every seeker is out of paint")
	r.players["s"]["ammo"] = 2
	r.find("s", "h1", 50.0)
	check(r.players["s"]["ammo"] == 2 + HideRules.AMMO_PER_FIND, "finding a hider gives +%d" % HideRules.AMMO_PER_FIND)
	check(r.players["h1"]["role"] == "seeker" and r.players["h1"]["ammo"] == HideRules.START_AMMO, "a found hider joins the seekers with fresh paint")
	check(not r.find("s", "h1", 51.0), "a found hider can't be found twice")
	check(r.winner(52.0) == "" and r.phase(52.0) == "seek", "the round goes on while a hider is left")
	r.find("h1", "h2", 60.0)
	check(r.winner(61.0) == "seekers", "seekers win when every hider is found")
	var r2 := HideRules.new(TestBarn.pool(), 1)
	r2.add_seeker("s")
	r2.add_hider("h")
	check(r2.phase(10.0) == "hide" and r2.winner(10.0) == "", "nobody wins during the hide phase")
	check(r2.winner(HideRules.HIDE_TIME + HideRules.SEEK_TIME) == "hiders", "hiders win when time runs out")


func _test_spark_schedule() -> void:
	var r := HideRules.new(TestBarn.pool(), 3)
	for id in ["a", "b", "c"]:
		r.add_hider(id)
	var starts := r.cycle_starts()
	check(starts == [25.0, 50.0, 75.0, 100.0, 125.0, 140.0, 155.0, 170.0], "every 25 s, then every 15 s in the last minute", str(starts))
	var bl := r.bursts(["a", "b", "c"])
	check(bl.size() == starts.size() * 3, "each cycle sparks every hider once", str(bl.size()))
	var one_at_a_time := true
	for i in range(1, bl.size()):
		if bl[i]["at"] - bl[i - 1]["at"] < HideRules.SPARK_GAP - 0.001:
			one_at_a_time = false
	check(one_at_a_time, "hiders spark one at a time, a second apart")
	var orders := {}
	for c in starts.size():
		orders[str(bl.slice(c * 3, c * 3 + 3).map(func(b): return b["id"]))] = true
	check(orders.size() > 1, "the order changes between cycles", str(orders.size()))
	check(str(r.bursts(["c", "a", "b"])) == str(bl), "every phone works out the same schedule")
	var first_a := HideRules.time_to_next(bl, "a", 0.0)
	check(first_a >= HideRules.HIDE_TIME + 25.0 and first_a <= HideRules.HIDE_TIME + 27.0, "a hider's first burst is in the first cycle", str(first_a))
	r.players["a"]["role"] = "seeker"
	check(not r.burst_live(bl.filter(func(b): return b["id"] == "a")[0]), "found hiders stop sparking")


func _test_paint_fade() -> void:
	check(HideRules.paint_alpha(0) == 1.0 and HideRules.paint_alpha(20) == 1.0, "paint is bright for 20 s")
	check(is_equal_approx(HideRules.paint_alpha(30), 0.5), "then fades", str(HideRules.paint_alpha(30)))
	check(HideRules.paint_alpha(40) == 0.0, "and is gone at 40 s")


## A world with a floor and a double stack of bales at the origin.
func _world() -> Node3D:
	var w := Node3D.new()
	root.add_child(w)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position.y = -0.5
	floor.add_child(cs)
	w.add_child(floor)
	w.add_child(TestBarn.prop_body("bale", Transform3D(Basis(), Vector3.ZERO)))
	w.add_child(TestBarn.prop_body("bale", Transform3D(Basis(), Vector3(0, 0.5, 0))))
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(0.3, 4, 6)
	wcs.shape = wb
	wcs.position = Vector3(6, 2, 0)
	wall.add_child(wcs)
	w.add_child(wall)
	return w


func _player(w: Node3D, r: String, kind: String, at: Vector3) -> Player:
	var p := Player.new()
	p.controlled = true
	p.role = r
	p.kind = kind
	p.position = at
	w.add_child(p)
	return p


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## The owner's example: a bale hider jumps up onto two stacked bales.
func _test_bale_jumps_onto_stack() -> void:
	var w := _world()
	var p := _player(w, "hider", "bale", Vector3(0, 0, 1.3))
	await _frames(20)
	p.input.move = Vector2(0, 1)          # forward is -Z, towards the stack
	p.input.jump = true
	for i in 60:                          # let go of forward once over it
		await physics_frame
		if p.global_position.z < 0.05:
			p.input.move = Vector2.ZERO
	await _frames(40)
	check(p.global_position.y > 0.95 and p.global_position.y < 1.1 and absf(p.global_position.z) < 0.5, "a bale hider jumps onto a double stack of bales", "at %v" % p.global_position)
	w.free()


func _test_seeker_jumps_onto_stack() -> void:
	var w := _world()
	var p := _player(w, "seeker", "", Vector3(0, 0, 2.0))
	await _frames(20)
	p.input.move = Vector2(0, 1)
	p.input.jump = true
	for i in 60:
		await physics_frame
		if p.global_position.z < 0.05:
			p.input.move = Vector2.ZERO
	await _frames(40)
	check(p.global_position.y > 0.95, "a seeker can climb the same stack", "at %v" % p.global_position)
	w.free()


func _test_jump_height() -> void:
	var w := _world()
	var p := _player(w, "hider", "bucket", Vector3(-4, 0, -4))
	await _frames(20)
	var base := p.global_position.y
	p.input.jump = true
	var peak := base
	for i in 70:
		await physics_frame
		peak = maxf(peak, p.global_position.y)
	check(absf(peak - base - HideRules.JUMP_HEIGHT) < 0.1, "jump is about %.1f m" % HideRules.JUMP_HEIGHT, "%.2f m" % (peak - base))
	check(p.is_on_floor(), "and lands again")
	w.free()


func _test_rake_leans_on_lock() -> void:
	var w := _world()
	var p := _player(w, "hider", "rake", Vector3(5.4, 0, 0))
	await _frames(20)
	p.toggle_lock()
	var tilt := p.prop_basis.y.angle_to(Vector3.UP)
	check(p.locked and tilt > 0.15, "a rake hider leans against the wall when locked", "tilt %.2f rad" % tilt)
	check(p.prop_basis.y.x > 0.0, "towards the wall")
	p.toggle_lock()
	check(p.prop_basis.y.angle_to(Vector3.UP) < 0.01, "and stands up when unlocked")
	w.free()


func _test_paintball_hits() -> void:
	var w := _world()
	var h := Player.new()
	h.role = "hider"
	h.kind = "crate"
	w.add_child(h)
	h.place(Transform3D(Basis(), Vector3(0, 0, -6)))
	var got := []
	var shot := Paint.fire(w, Transform3D(Basis(), Vector3(0, 0.6, -2)), Color.RED, RID())
	shot.hit.connect(func(c, _p, _n): got.append(c))
	var shot2 := Paint.fire(w, Transform3D(Basis(), Vector3(0, 0.6, 3)), Color.BLUE, RID())
	shot2.hit.connect(func(c, _p, _n): got.append(c))
	await _frames(30)
	check(got.size() == 2, "both paintballs hit something", str(got.size()))
	check(got.has(h), "a paintball hits a hider")
	check(got.any(func(c): return c is StaticBody3D and c.get_meta("prop", "") == "bale"), "and a scenery prop")
	var far := []
	var shot3 := Paint.fire(w, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 1.5, 10)), Color.RED, RID())
	shot3.hit.connect(func(c, _p, _n): far.append(c))
	await _frames(60)
	check(far.is_empty() and not is_instance_valid(shot3), "paintballs stop after their range", str(far))
	w.free()


func _test_edge_flash() -> void:
	var hud := Hud.new()
	root.add_child(hud)
	await process_frame
	var r := HideRules.new(TestBarn.pool(), 1)
	r.add_hider("me")
	var p := Player.new()
	p.role = "hider"
	p.kind = "bucket"
	root.add_child(p)
	hud.show_state(r, p, 60.0, 8.0, 0.05)
	check(hud.edge_strength() == 0.0, "no flash long before your burst")
	var peak := 0.0
	for i in 40:
		hud.show_state(r, p, 60.0, 4.0 - i * 0.1, 0.05)
		peak = maxf(peak, hud.edge_strength())
	check(peak > 0.5, "edges flash in the 5 s before your burst", "peak %.2f" % peak)
	hud.free()
	p.free()
