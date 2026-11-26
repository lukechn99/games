extends SceneTree
## Headless checks for Hide and Seek. Run with:
##   godot --headless --path hideseek --fixed-fps 60 -s tests/run_tests.gd
## Ends with "hide and seek checks: N failures".

var failures := 0
var passes := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(240.0)
	watchdog.timeout.connect(func():
		print("FAIL  timed out")
		print("hide and seek checks: 1 failures")
		quit(1))
	_test_prop_pool()
	_test_rerolls()
	_test_ammo_and_finding()
	_test_dealing_roles()
	_test_decoys()
	_test_rules_match_the_room()
	_test_spark_schedule()
	_test_paint_fade()
	await _test_bale_jumps_onto_stack()
	await _test_seeker_jumps_onto_stack()
	await _test_jump_height()
	await _test_rake_leans_on_lock()
	await _test_paintball_hits()
	await _test_edge_flash()
	await _test_phone_controls_after_turning()
	await _test_bots_play_a_round()
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
	for k in pool:
		if Props.has_model(k):
			var m := Props.mesh(k)
			var aabb := m.get_aabb()
			var tri := 0
			for si in m.get_surface_count():
				tri += (m.surface_get_array_index_len(si) if m.surface_get_array_index_len(si) > 0 else m.surface_get_array_len(si)) / 3
			check(m.get_surface_count() == 1, "%s model is one surface (one draw call)" % k)
			check(tri <= 1500, "%s model is within 1,500 triangles" % k, str(tri))
			check((aabb.size - Props.size(k)).abs().x < 0.06 and absf(aabb.size.y - Props.size(k).y) < 0.06 and absf(aabb.size.z - Props.size(k).z) < 0.06, "%s model matches its collision box" % k, "%v vs %v" % [aabb.size, Props.size(k)])
			check(absf(aabb.position.y) < 0.02, "%s model stands on its origin" % k, str(aabb.position.y))
	var missing := Surfaces.TILE.keys().filter(func(n): return Surfaces.material(n).albedo_texture == null or Surfaces.material(n).normal_texture == null)
	check(missing.is_empty(), "every building and ground surface has its textures", str(missing))
	var spot_kinds := TestBarn.SPOTS.map(func(s): return s[0])
	check(spot_kinds.all(func(k): return pool.has(k)), "hiding spots only use pool props")


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _seeker_of(st: Dictionary) -> String:
	return HideRules.ids(st, "seeker")[0]


func _test_rerolls() -> void:
	var r := _rng(7)
	var st := HideRules.setup(["a", "b", "c", "d"], 1000.0, r)
	var h: String = st["hidersAtStart"][0]
	var first: String = st["members"][h]["prop"]
	check(HideRules.PROPS.has(first), "a hider gets a random prop from the pool", first)
	var s1: Dictionary = HideRules.action(st, h, {"type": "reroll"}, 2000.0, r)["state"]
	var s2: Dictionary = HideRules.action(s1, h, {"type": "reroll"}, 3000.0, r)["state"]
	var props := [first, s1["members"][h]["prop"], s2["members"][h]["prop"]]
	check(props[1] != props[0] and props[2] != props[1], "two rerolls, each a different prop", str(props))
	check(HideRules.action(s2, h, {"type": "reroll"}, 4000.0, r).has("error"), "a third reroll is refused")
	var seen := {}
	for i in 60:
		var x := HideRules.setup(["a", "b"], 0.0, _rng(i))
		seen[x["members"][x["hidersAtStart"][0]]["prop"]] = true
	check(seen.size() == HideRules.PROPS.size(), "random props reach every prop", str(seen.keys()))


func _test_ammo_and_finding() -> void:
	var r := _rng(5)
	var st := HideRules.setup(["a", "b", "c", "d"], 1000.0, r)
	var seek := 1000.0 + HideRules.HIDE_MS + 1.0
	var sk := _seeker_of(st)
	var h: String = st["hidersAtStart"][0]
	check(HideRules.action(st, sk, {"type": "shoot"}, 2000.0, r).has("error"), "no paint in the hide phase")
	st = HideRules.action(st, sk, {"type": "shoot"}, seek, r)["state"]
	check(int(st["members"][sk]["ammo"]) == HideRules.START_AMMO - 1, "100 paintballs to spend", str(st["members"][sk]["ammo"]))
	st = HideRules.action(st, sk, {"type": "find", "hider": h}, seek + 10, r)["state"]
	check(int(st["members"][sk]["ammo"]) == HideRules.START_AMMO - 1 + HideRules.AMMO_PER_FIND, "a find gives +3")
	check(st["members"][h]["role"] == "seeker" and int(st["members"][h]["ammo"]) == HideRules.START_AMMO, "a found hider joins the seekers with fresh paint")
	check(HideRules.action(st, sk, {"type": "find", "hider": h}, seek + 20, r).has("error"), "a found hider can't be found twice")
	var other: String = st["hidersAtStart"][1]
	st = HideRules.action(st, "a" if sk != "a" else "b", {"type": "find", "hider": other, "as": sk}, seek + 30, r)["state"]
	check(st["members"][other]["role"] == "seeker", "a player can act for a bot ('as')")
	for x in HideRules.ids(st, "hider"):
		st = HideRules.action(st, sk, {"type": "find", "hider": x}, seek + 40, r)["state"]
	check(st["winner"] == "seekers" and int(st["scores"][sk]) >= 6, "seekers win when all are found", str(st["scores"]))
	var next := HideRules.tick(st, seek + 40 + HideRules.RESULTS_MS, r)
	check(int(next["round"]) == 2 and next["winner"] == null and next["scores"] == st["scores"], "then a new round deals again, scores kept")
	var t2 := HideRules.setup(["a", "b"], 0.0, _rng(3))
	check(HideRules.tick(t2, HideRules.HIDE_MS + HideRules.SEEK_MS, r)["winner"] == "hiders", "hiders win when time runs out")
	var sk2 := _seeker_of(t2)
	t2["members"][sk2]["ammo"] = 1
	t2 = HideRules.action(t2, sk2, {"type": "shoot"}, HideRules.HIDE_MS + 5, r)["state"]
	check(t2["winner"] == "hiders", "hiders win when every seeker is out of paint")


func _test_decoys() -> void:
	var r := _rng(5)
	var st := HideRules.setup(["a", "b", "c", "d"], 1000.0, r)
	var h: String = st["hidersAtStart"][0]
	var sk := _seeker_of(st)
	for i in HideRules.DECOYS:
		st = HideRules.action(st, h, {"type": "decoy", "at": [i, 0, 1], "q": [0, 0, 0, 1]}, 2000.0, r)["state"]
	check(st["decoys"].size() == 3 and st["decoys"].all(func(d): return d["prop"] == st["members"][h]["prop"]), "a hider drops three decoys of their prop")
	check(HideRules.action(st, h, {"type": "decoy", "at": [0, 0, 0], "q": [0, 0, 0, 1]}, 2000.0, r).has("error"), "and no more")
	var seek := 1000.0 + HideRules.HIDE_MS + 1.0
	st = HideRules.action(st, sk, {"type": "pop", "decoy": st["decoys"][0]["id"]}, seek, r)["state"]
	check(st["decoys"].size() == 2, "a seeker painting a decoy pops it")


func _test_dealing_roles() -> void:
	var counts := []
	for n in range(2, 11):
		counts.append(HideRules.seeker_count(n))
	check(counts == [1, 1, 1, 2, 2, 2, 3, 3, 3], "seekers for 2 to 10 players", str(counts))
	var seen := {}
	for i in 200:
		var st := HideRules.setup(["me", "bot1", "bot2", "bot3"], 0.0, _rng(i))
		var s := HideRules.ids(st, "seeker")
		seen[s[0]] = seen.get(s[0], 0) + 1
	check(seen.size() == 4 and seen.values().all(func(v): return v > 30), "every player can be dealt seeker, about evenly", str(seen))


## The game's rules must match the room's (lib/games/hideseek/rules.ts).
func _test_rules_match_the_room() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../lib/games/hideseek/rules.ts")
	var ts := FileAccess.get_file_as_string(path)
	if ts == "":
		check(true, "rules.ts not found here; skipped")
		return
	var num := func(name: String) -> float:
		var re := RegEx.create_from_string("export const %s = ([0-9_]+)" % name)
		var m := re.search(ts)
		return float(m.get_string(1).replace("_", "")) if m else -1.0
	var pairs := {"DECOYS": HideRules.DECOYS, "HIDE_MS": HideRules.HIDE_MS, "SEEK_MS": HideRules.SEEK_MS, "RESULTS_MS": HideRules.RESULTS_MS,
		"START_AMMO": HideRules.START_AMMO, "AMMO_PER_FIND": HideRules.AMMO_PER_FIND, "REROLLS": HideRules.REROLLS}
	var bad := []
	for k in pairs:
		if num.call(k) != float(pairs[k]):
			bad.append("%s %s vs %s" % [k, num.call(k), pairs[k]])
	check(bad.is_empty(), "the game's numbers match the room's rules", str(bad))
	var props := RegEx.create_from_string("export const PROPS = \\[([^\\]]*)\\]").search(ts)
	var list := Array(props.get_string(1).replace("'", "").replace(" ", "").split(",")) if props else []
	check(list == HideRules.PROPS, "same props, same order", str(list))


func _test_spark_schedule() -> void:
	var st := HideRules.setup(["a", "b", "c", "d"], 0.0, _rng(3))
	var starts := HideRules.cycle_starts(HideRules.SEEK_MS / 1000.0)
	check(starts == [25.0, 50.0, 75.0, 100.0, 125.0, 140.0, 155.0, 170.0], "every 25 s, then every 15 s in the last minute", str(starts))
	var bl := HideRules.bursts(st)
	var n: int = st["hidersAtStart"].size()
	check(bl.size() == starts.size() * n, "each cycle sparks every hider once", str(bl.size()))
	var one_at_a_time := true
	for i in range(1, bl.size()):
		if bl[i]["at"] - bl[i - 1]["at"] < HideRules.SPARK_GAP - 0.001:
			one_at_a_time = false
	check(one_at_a_time, "hiders spark one at a time, a second apart")
	var orders := {}
	for c in starts.size():
		orders[str(bl.slice(c * n, c * n + n).map(func(b): return b["id"]))] = true
	check(orders.size() > 1, "the order changes between cycles", str(orders.size()))
	var copy := st.duplicate(true)
	copy["seed"] = float(st["seed"])      # as it arrives from the room (JSON)
	copy["hidersAtStart"].reverse()
	check(str(HideRules.bursts(copy)) == str(bl), "every phone works out the same schedule")


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
	var ses := Session.new()
	root.add_child(ses)
	ses.start(false, 1)
	await process_frame
	var p := Player.new()
	p.role = "hider"
	p.kind = "bucket"
	root.add_child(p)
	var st := ses.state
	hud.show_round(st, ses, p, 60.0, "seek", 8.0, 0.05)
	check(hud.edge_strength() == 0.0, "no flash long before your burst")
	var peak := 0.0
	for i in 40:
		hud.show_round(st, ses, p, 60.0, "seek", 4.0 - i * 0.1, 0.05)
		peak = maxf(peak, hud.edge_strength())
	check(peak > 0.5, "edges flash in the 5 s before your burst", "peak %.2f" % peak)
	hud.free()
	ses.free()
	p.free()


## The phone controls were laid out for an upright screen and stayed below
## the bottom after the phone was turned sideways. Turn it; all must show.
func _test_phone_controls_after_turning() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1560)          # upright
	root.add_child(vp)
	var c := Controls.new()
	c.touching = true
	vp.add_child(c)
	c.set_role("hider")
	await process_frame
	vp.size = Vector2i(1560, 720)          # sideways
	await process_frame
	await process_frame
	var rect := Rect2(Vector2.ZERO, Vector2(vp.size))
	var out := []
	for name in c._buttons:
		var b: Dictionary = c._buttons[name]
		if not rect.grow(-4).has_point(b["at"] + Vector2(b["r"], b["r"])) or not rect.has_point(b["at"] - Vector2(b["r"], b["r"])):
			out.append(name)
	if not rect.has_point(c._stick_home + Vector2(0, Controls.STICK)):
		out.append("stick")
	check(out.is_empty(), "after turning the phone, the stick and every button are on screen", str(out))
	check(c._buttons.has("decoy") and c._buttons.has("reroll") and c._buttons.has("lock"), "hiders get Switch prop, Lock and Decoy")
	check(c._buttons["reroll"]["at"].x > vp.size.x * 0.75, "buttons sit at the right edge", str(c._buttons["reroll"]["at"]))
	var edge := 120.0
	check(c._stick_home.x - Controls.STICK > edge * 0.8 and vp.size.y - (c._stick_home.y + Controls.STICK) > edge * 0.8,
		"the stick rests clear of the left and bottom edges (iPhone system swipes)", str(c._stick_home))
	c.set_role("seeker")
	check(c._buttons.has("fire") and c._buttons["fire"]["label"] == "Shoot", "seekers get Shoot")
	vp.free()


## A whole practice round, played headless at full speed: you hide (and
## stay put), a seeker bot hunts, three... hider bots take free spots.
func _test_bots_play_a_round() -> void:
	OS.set_environment("HS_TEST", "1")
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	game.set("_query", {})
	root.add_child(game)
	game.call("_force_role", "hider")
	game.session.state["hideMs"] = 3000.0
	game.session.state["hidersAtStart"] = game.session.state["seats"].filter(func(x): return game.session.state["members"][x]["role"] == "hider")
	await process_frame
	game.call("_new_round")
	var seeker_id := ""
	for id in game.brains:
		if game.brains[id] is Bots.Seeker:
			seeker_id = id
	check(seeker_id != "", "practice as a hider has a seeker bot")
	var bot: Player = game.roster.get(seeker_id)
	var start := bot.global_position if bot else Vector3.ZERO
	# Hide phase: the hider bots take free spots.
	for i in 60 * 5:
		await physics_frame
	var placed := 0
	for id in game.brains:
		if game.brains[id] is Bots.Hider and game.brains[id].hidden:
			placed += 1
	check(placed == 2, "hider bots take their spots during the hide phase", str(placed))
	check(game.session.state["decoys"].size() >= 2, "and leave decoys elsewhere", str(game.session.state["decoys"].size()))
	var travelled := 0.0
	var last := bot.global_position
	var found_at := -1.0
	for i in 60 * 150:
		await physics_frame
		if is_instance_valid(bot):
			travelled += bot.global_position.distance_to(last)
			last = bot.global_position
		if game.session.state["finds"].size() > 0 and found_at < 0.0:
			found_at = i / 60.0
			break
	var st: Dictionary = game.session.state
	var shots: int = HideRules.START_AMMO - int(st["members"][seeker_id]["ammo"]) + HideRules.AMMO_PER_FIND * st["finds"].size()
	check(travelled > 15.0, "the seeker bot walks the farm", "%.0f m" % travelled)
	check(shots >= 1, "and paints things", "%d shots" % shots)
	check(found_at > 0.0, "and finds a hider within the round", "after %.0f s" % found_at)
	var nav: NavigationRegion3D = game.get_node_or_null("Nav")
	if nav:
		var path := NavigationServer3D.map_get_path(nav.get_navigation_map(), Vector3(0, 0, 18), Vector3(-2, TestBarn.LOFT_Y, 8), true)
		check(path.size() > 1 and path[path.size() - 1].y > TestBarn.LOFT_Y - 0.4, "bots can walk from the yard up to the loft", str(path[path.size() - 1]) if path.size() else "no path")
	game.free()
