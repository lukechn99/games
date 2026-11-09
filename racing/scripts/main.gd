extends Node3D
## M0 test race: your kart and three computer drivers on the test loop.
## Tune the feel in the Garage (top right), drive with keys, a gamepad,
## touch or tilt. See docs/racing/DESIGN.md.

const BOT_BUILDS := [
	{"chassis": "hauler", "tires": "knobby", "driver": "rhino", "level": "medium"},
	{"chassis": "soapbox", "tires": "balloon", "driver": "frog", "level": "easy"},
	{"chassis": "racer", "tires": "studded", "driver": "deer", "level": "hard"},
]

var track: Track
var karts: Array[Kart] = []
var player_kart: Kart
var player: PlayerDriver
var camera: ChaseCamera
var hud: Hud
var center_text := ""
var _countdown := 0.0
var _racing := false
var _finish_order: Array[Kart] = []
var sun: DirectionalLight3D
var lobby: Lobby
var items: Items
var _in_lobby := false
var _tour := 0.0
var _env: Environment
var _fps_time := 0.0          # seconds of racing measured so far
var _fps_frames := 0


func _ready() -> void:
	var preview_query := str(JavaScriptBridge.eval("location.search", true)) if OS.has_feature("web") else OS.get_environment("KW_QUERY")
	Palette.theme = "mine" if preview_query.contains("track=mine") else "frost" if preview_query.contains("track=frost") else "meadow"
	Palette.preview_pop = not preview_query.contains("palette=classic")
	_build_world()
	track = Track.new()
	# (Outside a browser, tools can pass the same flags in KW_QUERY.)
	var q0 := str(JavaScriptBridge.eval("location.search", true)) if OS.has_feature("web") else OS.get_environment("KW_QUERY")
	_capture_intro = q0.contains("introreview")
	_trace_intro = q0.contains("introtrace") or _capture_intro
	if q0.contains("track=mine"):
		track.layout = "mine"
	elif q0.contains("track=frost"):
		track.layout = "frost"
	if q0.contains("laps="):   # for checking the finish quickly
		track.laps = clampi(int(q0.split("laps=")[1].split("&")[0]), 1, 9)
	add_child(track)
	camera = ChaseCamera.new()
	add_child(camera)
	hud = Hud.new()
	hud.race = self
	add_child(hud)
	hud.parts_changed.connect(_on_parts_changed)
	hud.restart_requested.connect(start_race)
	results = ResultsScreen.new()
	add_child(results)
	results.again_pressed.connect(_on_again)

	if Net.active:
		_start_online()
		return
	player_kart = _spawn_kart("frame", "slicks", "fox", 0)
	player_kart.display_name = "You"
	player = PlayerDriver.new(player_kart)
	add_child(player)
	for i in BOT_BUILDS.size():
		var b: Dictionary = BOT_BUILDS[i]
		var k := _spawn_kart(b["chassis"], b["tires"], b["driver"], i + 1)
		k.display_name = Parts.DRIVERS[b["driver"]]["name"]
		var bot := BotDriver.new(k, track, b["level"], i + 3)
		add_child(bot)
		bot.set_meta("kart", k)
	var bumps := KartBumps.new()
	bumps.karts = karts
	add_child(bumps)
	items = Items.new()
	add_child(items)
	items.setup(track, karts, karts)
	for k in karts:
		if k != player_kart:
			k.set_meta("bot_items", true)
	camera.follow(player_kart)
	hud.minimap.setup(track, karts, player_kart)
	start_race()
	var q := q0
	if q.contains("map"):
		_map_review(q)
	elif q.contains("showroom"):
		_showroom(q)
	elif q.contains("cam="):
		_camera_view(q)
	elif q.contains("autodrive"):
		# For reviewing the look mid-race: no lobby, and a computer driver
		# drives your kart while the chase camera follows it.
		player.set_physics_process(false)
		_autopilot_review = true
		add_child(BotDriver.new(player_kart, track, "hard", 99))
		if q.contains("view=side"):
			ChaseCamera.review_offset = Vector2(4.0, 2.5)
		if q.contains("introt="):
			_intro_pin = float(q.split("introt=")[1].split("&")[0])
		if q.contains("bench"):
			# Measure the race (tools/bench): ?bench or ?bench=SECONDS.
			var bench := Bench.new()
			bench.race = self
			if q.contains("bench="):
				bench.seconds = clampf(float(q.split("bench=")[1].split("&")[0]), 1.0, 300.0)
			_benching = true
			add_child(bench)
		if q.contains("intro"):
			# Start from the aerial tour, as after the kart builder.
			_fly_over(0.0)
			camera.follow(player_kart)
			start_race()
			_begin_intro()
	else:
		_open_lobby()
	# Compile every shader now, behind the lobby, instead of mid-race (once
	# the track's roadside plants, placed a frame late, are in).
	await get_tree().physics_frame
	await get_tree().physics_frame
	ShaderWarmup.new().warm(self, camera)


# --- Online (a Game Night room) -----------------------------------------
# The room's rules (lib/games/racing/rules.ts) decide the karts, who's
# ready, when the lights go green and the finishing order. Each game drives
# its own kart (and the host's game drives the computer drivers), and sends
# their positions to everyone else 15 times a second.

var _online_ready := false
var _owned: Array[Kart] = []      # karts this game drives and sends
var _by_id := {}                  # player id -> Kart
var _send_t := 0.0
var _reported := {}               # player id -> true once their finish is sent
var results: ResultsScreen
var _benching := false          # ?bench: keep the quality fixed
var _autopilot_review := false   # ?autodrive: a bot drives you all along
var _autopilot: BotDriver        # drives your kart on after you finish
var _done := false                # online: the room says the race is over
var _state := {}                  # the room's latest state (online)
var _results_tick := 0.0


func _start_online() -> void:
	_open_lobby_online()
	Net.state_changed.connect(_on_net_state)
	Net.relay_received.connect(_on_relay)


func _open_lobby_online() -> void:
	Controls.release_inputs()
	lobby = Lobby.new()
	lobby.online = true
	add_child(lobby)
	lobby.parts_changed.connect(func(c, t, d): Net.act({"type": "pick", "chassis": c, "tires": t, "driver": d}))
	lobby.ready_pressed.connect(func(): Net.act({"type": "ready"}))
	lobby.open([])
	_in_lobby = true
	hud.visible = false
	camera.set_process(false)


func _on_net_state(st: Dictionary) -> void:
	_state = st
	var seats: Array = st.get("seats", [])
	var picks: Dictionary = st.get("picks", {})
	if not _online_ready:
		_build_online_karts(seats, picks)
		_online_ready = true
		print("[race] lobby open with %d racers" % seats.size())
	# Karts follow everyone's picks.
	for id in seats:
		var k: Kart = _by_id.get(id)
		var p: Dictionary = picks.get(id, {})
		if k and not p.is_empty() and (k.chassis_id != p["chassis"] or k.tires_id != p["tires"] or k.driver_id != p["driver"]):
			k.configure(p["chassis"], p["tires"], p["driver"])
			(k.get_meta("visual") as KartVisual).rebuild()
	var list := []
	for id in seats:
		var p: Dictionary = picks.get(id, {})
		list.append({"name": ("You" if id == Net.me else Net.name_of(id)), "ready": bool(p.get("ready", false))})
	lobby.set_players(list)
	var phase := str(st.get("phase", "pick"))
	if phase == "race" and _in_lobby:
		lobby.close()
		_in_lobby = false
		camera.follow(player_kart if player_kart else karts[0])
		start_race()
		# Everyone's lights go green at the same moment, by the host's clock;
		# the fly-in fills the time before the numbers.
		_countdown = maxf(0.5, float(st.get("startAt", 0.0)) / 1000.0 - Net.host_now())
		_begin_intro(maxf(0.5, _countdown - 3.0))
		var cup: Variant = st.get("cup")
		if cup is Dictionary:
			hud.flash("Grand Prix  race %d of %d" % [int(cup["race"]) + 1, (cup["tracks"] as Array).size()], 5.0)
		print("[race] green in %.1f s (start %.1f, host now %.1f), %d karts" % [_countdown, float(st.get("startAt", 0.0)) / 1000.0, Net.host_now(), karts.size()])
	if phase == "done":
		_show_results(st)


func _build_online_karts(seats: Array, picks: Dictionary) -> void:
	for i in seats.size():
		var id: String = seats[i]
		var p: Dictionary = picks.get(id, {"chassis": "frame", "tires": "slicks", "driver": "fox", "bot": false})
		var k := _spawn_kart(p["chassis"], p["tires"], p["driver"], i)
		k.set_meta("pid", id)
		_by_id[id] = k
		if id == Net.me:
			player_kart = k
			k.display_name = "You"
			player = PlayerDriver.new(k)
			add_child(player)
			_owned.append(k)
		elif Net.is_bot(id) and Net.is_host:
			k.display_name = Net.name_of(id)
			var bot := BotDriver.new(k, track, "medium", i + 3)
			add_child(bot)
			_owned.append(k)
		else:
			k.display_name = Net.name_of(id)
			k.make_remote()
	if player_kart == null:
		# Watching: follow the first kart.
		player_kart = karts[0]
		player = PlayerDriver.new(null)
	var bumps := KartBumps.new()
	bumps.karts = karts
	add_child(bumps)
	items = Items.new()
	add_child(items)
	items.setup(track, karts, _owned)
	for k in _owned:
		if k != _by_id.get(Net.me):
			k.set_meta("bot_items", true)
	# Items we use show up in everyone's game.
	items.used.connect(func(kind, p, d, sv): Net.relay({"i": [kind, p.x, p.y, p.z, d.x, d.y, d.z, sv]}))
	camera.follow(player_kart)
	hud.minimap.setup(track, karts, player_kart)
	var me: Kart = _by_id.get(Net.me)
	if me:
		lobby.choice = {"chassis": me.chassis_id, "tires": me.tires_id, "driver": me.driver_id}
		lobby._dress()
		lobby._refresh()
	for k in karts:
		k.global_transform = track.grid_transform(karts.find(k))
	ShaderWarmup.new().warm(self, camera)


func _on_relay(from: String, data: Variant) -> void:
	if not data is Dictionary:
		return
	var it: Variant = (data as Dictionary).get("i")
	if it is Array and (it as Array).size() == 8 and items:
		var a: Array = it
		items.spawn(str(a[0]), Vector3(a[1], a[2], a[3]), Vector3(a[4], a[5], a[6]), int(a[7]))
		return
	var ks: Variant = (data as Dictionary).get("k")
	if not ks is Dictionary:
		return
	for id in ks:
		var k: Kart = _by_id.get(id)
		if k and k.remote:
			if not k._net_seen:
				print("[race] seeing %s's kart" % Net.name_of(id))
			k.apply_net(ks[id])


func _physics_process(delta: float) -> void:
	if not Net.active or _owned.is_empty():
		return
	_send_t += delta
	if _send_t >= 1.0 / 15.0:
		_send_t = 0.0
		var ks := {}
		for k in _owned:
			ks[k.get_meta("pid")] = k.net_state()
		Net.relay({"k": ks})


func _report_finish(k: Kart) -> void:
	if not Net.active or not _owned.has(k):
		return
	var id: String = k.get_meta("pid")
	if _reported.has(id):
		return
	_reported[id] = true
	if k == _by_id.get(Net.me):
		Net.act({"type": "finish", "time": k.race_time})
	else:
		Net.act({"type": "finish", "time": k.race_time, "who": id})


func _show_results(_st: Dictionary) -> void:
	_done = true
	_refresh_results()


func _on_again() -> void:
	if Net.active:
		if Net.is_host:
			var cup: Variant = _state.get("cup")
			if cup is Dictionary and int(cup["race"]) + 1 < (cup["tracks"] as Array).size():
				Net.act({"type": "next"})   # the next race of the Grand Prix
			else:
				Net.room("playAgain")
	else:
		start_race()
		camera.follow(player_kart)


## Your lap times, from the race clock at each line crossing.
func lap_times(k: Kart) -> Array:
	var splits: Array = k.get_meta("splits", [])
	var out := []
	var prev := 0.0
	for t in splits:
		out.append(float(t) - prev)
		prev = float(t)
	return out


func _refresh_results() -> void:
	if player_kart == null:
		return
	var order := karts.duplicate()
	order.sort_custom(func(a, b): return place_of(a) < place_of(b))
	var rows := []
	# Online, the room's record of who finished and when is the word on it.
	var fin: Dictionary = _state.get("finish", {}) if Net.active else {}
	if not fin.is_empty():
		order.sort_custom(func(a, b):
			var ta: float = float(fin.get(a.get_meta("pid", ""), INF))
			var tb: float = float(fin.get(b.get_meta("pid", ""), INF))
			return ta < tb if ta != tb else place_of(a) < place_of(b))
	var n := 1
	for k in order:
		var t: float = k.race_time if k.finished else (-2.0 if _done else -1.0)
		var id: String = k.get_meta("pid", "")
		if fin.has(id):
			t = float(fin[id])
		rows.append([n, k.display_name, t, k == player_kart])
		n += 1
	var again := not Net.active or (Net.is_host and _done)
	var note := ""
	# A Grand Prix: the standings so far, once the room has added up the race.
	var cup_rows := []
	var cup_title := ""
	var again_label := "Race again"
	var cup: Variant = _state.get("cup") if Net.active else null
	if cup is Dictionary:
		var race := int(cup["race"]) + 1
		var total := (cup["tracks"] as Array).size()
		var last_race := race >= total
		cup_title = "Grand Prix  race %d of %d" % [race, total] if not (_done and last_race) else "Grand Prix  final standings"
		if not last_race:
			again_label = "Next race"
		if _done:
			var pts: Dictionary = cup["points"]
			var got: Dictionary = cup.get("last", {})
			var ids := pts.keys()
			ids.sort_custom(func(a, b): return int(pts[a]) > int(pts[b]))
			for i in ids.size():
				var id: String = ids[i]
				cup_rows.append([i + 1, "You" if id == Net.me else Net.name_of(id), int(pts[id]), int(got.get(id, 0)), id == Net.me])
	if Net.active:
		if not _done:
			note = "Waiting for the others to finish…"
		elif not Net.is_host:
			note = "The host starts the next race." if again_label == "Next race" else "The host can start another race."
	results.show_results(place_of(player_kart), lap_times(player_kart), rows, again, note, cup_title, cup_rows, again_label)
	hud.touch.visible = false


## You're over the line: a computer takes the wheel and does a cool-down
## lap while you look at the times.
func _finish_player() -> void:
	center_text = ""
	if player:
		player.set_physics_process(false)
	if _autopilot == null and not _autopilot_review:
		_autopilot = BotDriver.new(player_kart, track, "easy", 77)
		add_child(_autopilot)
	_refresh_results()


## Behind the lobby: a slow aerial circle round the whole track.
func _fly_over(delta: float) -> void:
	camera.near = ChaseCamera.AERIAL_NEAR
	_tour += delta
	var center := track.map_centre()
	var r := track.map_radius() * 1.05 + 40.0
	var a := _tour * 0.08
	_tour_pos = center + Vector3(cos(a) * r, 150.0 + r * 0.1, sin(a) * r)
	camera.global_position = _tour_pos
	camera.look_at(center + Vector3(0, -10, 0), Vector3.UP)
	camera.fov = 55.0


# --- Fly-in -------------------------------------------------------------
# Once everyone's ready, the camera carries on from exactly where the aerial
# tour has it, turning the same way at the same pace, and spirals down round
# the middle of the map to come to rest right where the race camera sits
# behind your kart. Nothing jumps: position, aim and speed all carry on.

const INTRO := 8.0         # slow: one unhurried turn, coming down
const TOUR_SPIN := 0.08    # the aerial tour's turn rate, rad/s
var _intro_len := INTRO
var _intro_left := 0.0
var _intro_pin := -1.0     # ?introt=T: hold the fly-in at T (0..1), for checking it
var _intro_from := Vector3.ZERO   # [radius, height, angle] round the map's middle
var _intro_lift := 0.0     # extra height to clear hills, eased in and out
var _tour_pos := Vector3.ZERO     # where the aerial tour last put the camera
var _trace_intro := false
var _intro_samples: Array = []
var intro_report := {}
var _capture_intro := false
var _intro_capture_index := 0


func _begin_intro(seconds := INTRO) -> void:
	if _intro_left > 0.0:
		return   # already flying in
	_intro_len = seconds
	_intro_left = seconds
	# From where the aerial tour put the camera (by now the race camera has
	# already been snapped behind the kart, so not from the camera itself).
	if _tour_pos == Vector3.ZERO:
		_fly_over(0.0)
	var off := _tour_pos - track.map_centre()
	_intro_from = Vector3(Vector2(off.x, off.z).length(), _tour_pos.y, atan2(off.z, off.x))
	_intro_lift = 0.0
	_intro_samples.clear()
	intro_report.clear()
	_intro_capture_index = 0
	camera.set_process(false)
	hud.visible = false
	# Standalone: the countdown starts after the fly-in. (Online it's set by
	# the host's clock, already counting.)
	if not Net.active:
		_countdown = 3.0 + seconds


func _intro(delta: float) -> void:
	_intro_left = maxf(0.0, _intro_left - delta)
	var t := 1.0 - _intro_left / _intro_len
	if _intro_pin >= 0.0:
		t = _intro_pin
		_intro_left = _intro_len
	var s := t * t * (3.0 - 2.0 * t)   # ease in and out
	var rest: Array = camera.rest_view()
	var rest0: Vector3 = rest[0]
	var mid := track.map_centre()
	var to_end := Vector2(rest0.x - mid.x, rest0.z - mid.z)
	# Round the middle, the way the tour was turning, to come out on the
	# race camera's side: whatever's left of the turn, or one more if that's
	# too little to read as a circle.
	var sweep := fposmod(atan2(to_end.y, to_end.x) - _intro_from.z, TAU)
	if sweep < PI * 0.5:
		sweep += TAU
	# Hermite: starts at the tour's own turn rate, eases to a stop on the grid.
	var h10 := t * t * t - 2.0 * t * t + t
	var h01 := -2.0 * t * t * t + 3.0 * t * t
	var ang := _intro_from.z + TOUR_SPIN * _intro_len * h10 + sweep * h01
	var radius := lerpf(_intro_from.x, to_end.length(), s)
	# Holds its height for a while, then comes down onto the kart.
	var height := lerpf(_intro_from.y, rest0.y, s * s)
	var pos := mid + Vector3(cos(ang) * radius, height, sin(ang) * radius)
	# Keep clear of hills on the way, letting the margin go as it lands.
	var need := 0.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 300.0, pos + Vector3.DOWN * 300.0))
	if not hit.is_empty():
		need = maxf(0.0, (hit["position"] as Vector3).y + 25.0 - pos.y)
	_intro_lift = need if _intro_pin >= 0.0 else lerpf(_intro_lift, need, 1.0 - exp(-delta * 3.0))
	# Fade AFTER smoothing: filtering an already-faded target leaves residual
	# height at t=1, which used to disappear in a single frame at follow().
	pos.y += _intro_lift * (1.0 - smoothstep(0.8, 1.0, t))
	# Aim: from the middle of the map (where the tour looked) round to the
	# race camera's view of the road ahead.
	var look := (mid + Vector3(0, -10, 0)).lerp(rest[1], smoothstep(0.1, 1.0, t))
	camera.global_position = pos
	camera.look_at(look, Vector3.UP)
	camera.fov = lerpf(55.0, ChaseCamera.BASE_FOV, smoothstep(0.5, 1.0, t))
	camera.near = lerpf(ChaseCamera.AERIAL_NEAR, ChaseCamera.BASE_NEAR, smoothstep(0.65, 1.0, t))
	if _trace_intro:
		_intro_samples.append({"t": t, "position": [pos.x, pos.y, pos.z], "rest_distance": pos.distance_to(rest0), "lift": pos.y - height})
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__introProgress = %f" % t, true)
			# Hold the actual animated pose for screenshots; a slow browser can
			# otherwise advance beyond the requested frame before capture runs.
			var stops := [0.85, 0.92, 0.96, 1.0]
			if _capture_intro and _intro_capture_index < stops.size() and t >= stops[_intro_capture_index]:
				JavaScriptBridge.eval("window.__introFrame = {index:%d,t:%f}; window.__introHold = true" % [_intro_capture_index, t], true)
				_intro_capture_index += 1
	if _intro_left <= 0.0:
		var before_handoff := camera.global_transform
		camera.resume_from_current_view()
		camera.set_process(true)
		hud.visible = true
		if _trace_intro:
			intro_report = {"track": track.layout, "handoff_jump_m": before_handoff.origin.distance_to(camera.global_position), "samples": _intro_samples}
			print("[intro] %s handoff %.6f m" % [track.layout, intro_report.handoff_jump_m])
			if OS.has_feature("web"):
				JavaScriptBridge.eval("window.__introReport = " + JSON.stringify(intro_report), true)


## Races begin with everyone picking a kart and tapping Ready (design doc 4).
func _open_lobby() -> void:
	Controls.release_inputs()
	if lobby == null:
		lobby = Lobby.new()
		add_child(lobby)
		lobby.parts_changed.connect(func(c, t, d):
			_on_parts_changed(c, t, d)
			hud.set_choice(c, t, d))
		lobby.all_ready.connect(func():
			_in_lobby = false
			camera.follow(player_kart)
			start_race()
			_begin_intro())
	var names := []
	for k in karts:
		if k != player_kart:
			names.append(k.display_name)
	lobby.choice = {"chassis": player_kart.chassis_id, "tires": player_kart.tires_id, "driver": player_kart.driver_id}
	lobby.open(names)
	_in_lobby = true
	hud.visible = false
	camera.set_process(false)
	_tour = 0.0


## ?map[=entry|exit]: orthographic inspection without race UI or moving karts.
func _map_review(q: String) -> void:
	set_process(false)
	_env.fog_enabled = false   # inspection should reveal surfaces, not haze
	hud.visible = false
	player.set_physics_process(false)
	for child in get_children():
		if child is BotDriver:
			child.set_physics_process(false)
	for k in karts:
		k.freeze = true
	camera.set_process(false)
	camera.set_physics_process(false)
	var review := MapReview.new()
	review.track = track
	review.camera = camera
	add_child(review)
	review.setup(q)


## ?cam=OFFSET[,SIDE,HEIGHT,LOOK]: a still camera at that point of the lap,
## for reviewing the track's scenery.
func _camera_view(q: String) -> void:
	var spec := q.split("cam=")[1].split("&")[0].split(",")
	var off := float(spec[0])
	var side := float(spec[1]) if spec.size() > 1 else 0.0
	var height := float(spec[2]) if spec.size() > 2 else 3.0
	var look := float(spec[3]) if spec.size() > 3 else 30.0
	camera.set_process(false)
	camera.set_physics_process(false)
	var f := track.transform_at(off)
	var lf := track.transform_at(off + look)
	# A fifth value "b": along the route beside the main road there.
	if spec.size() > 4 and spec[4] == "b" and track.branch_at(off) >= 0:
		var bi := track.branch_at(off)
		f = track.branch_frame(off, bi)
		lf = track.branch_frame(off + look, bi)
	camera.global_position = f.origin + f.basis.x * side + Vector3.UP * height
	camera.look_at(lf.origin + Vector3.UP * 1.5, Vector3.UP)
	camera.fov = 70.0
	hud.visible = false


## ?showroom: every chassis side by side, parked, for reviewing the models.
## Add &tires=knobby or &driver=deer to swap those on all of them.
func _showroom(q: String) -> void:
	var tires := "slicks"
	var driver := "fox"
	for t in Parts.TIRES:
		if q.contains("tires=" + t):
			tires = t
	for d in Parts.DRIVERS:
		if q.contains("driver=" + d):
			driver = d
	set_process(false)
	hud.visible = false
	for c in get_children():
		if c is BotDriver or c is PlayerDriver:
			c.queue_free()
	var ids := Parts.CHASSIS.keys()
	var base := track.transform_at(60.0)
	for i in karts.size():
		var k := karts[i]
		k.configure(ids[i % ids.size()], tires, driver)
		(k.get_meta("visual") as KartVisual).rebuild()
		k.freeze = true
		if q.contains("compression="):
			k.set_physics_process(false)
			k.wheel_compression.fill(clampf(float(q.split("compression=")[1].split("&")[0]), 0.0, 1.0) * Kart.SUSPENSION_TRAVEL)
		k.global_transform = Transform3D(base.basis.rotated(Vector3.UP, 0.6 + (PI if q.contains("flip") else 0.0)), base.origin + base.basis.x * (float(i) - 1.5) * 3.2 + Vector3.UP * 0.32)
		k.input = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "drift": false}
	camera.set_process(false)
	camera.global_position = base.origin - base.basis.z * 6.5 + base.basis.x * 1.5 + Vector3.UP * 2.6
	camera.look_at(base.origin + Vector3.UP * 0.4, Vector3.UP)
	camera.fov = 52.0
	# &drivers: every animal, one per kart. &face=N: close-up of kart N's driver.
	if q.contains("drivers"):
		var dids := Parts.DRIVERS.keys()
		for i in karts.size():
			karts[i].configure(ids[i % ids.size()], tires, dids[i % dids.size()])
			(karts[i].get_meta("visual") as KartVisual).rebuild()
	if q.contains("face="):
		var n := int(q.split("face=")[1].substr(0, 1))
		var kx := karts[clampi(n, 0, karts.size() - 1)].global_transform
		var head := kx.origin + kx.basis.y * 1.05
		camera.global_position = head - kx.basis.z * 1.5 + kx.basis.y * 0.15
		camera.look_at(head, Vector3.UP)
		camera.fov = 40.0


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	# Deep blue overhead, paling to a bright haze at the horizon.
	mat.sky_top_color = Color(0.18, 0.55, 0.96)
	mat.sky_horizon_color = Color(0.8, 0.93, 1.0)
	mat.sky_curve = 0.11
	mat.ground_horizon_color = Color(0.78, 0.9, 1.0)
	mat.ground_bottom_color = Color(0.66, 0.78, 0.84)   # hazy, in case any shows past the ground
	mat.sun_angle_max = 20.0
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42
	# Part sky, part a neutral warm grey: all-sky light tinted grey roads
	# and rock purple, where Mario Kart's read neutral.
	env.ambient_light_color = Color(0.86, 0.84, 0.8)
	env.ambient_light_sky_contribution = 0.3   # (more sky light tinted soft-shaded colours blue)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY  # metal and water reflect the sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# A soft glow around the brightest things: lamps, glints, boost flames.
	env.glow_intensity = 0.6
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	if Palette.preview_pop:
		mat.sky_top_color = Color("48b9ef")
		env.ambient_light_sky_contribution = 0.12
		env.fog_light_color = Color("dce9eb")
		env.fog_density = 0.00055
		if Palette.theme == "mine":
			mat.sky_top_color = Color("49bfd5")
			env.fog_light_color = Color("eddbc1")
		elif Palette.theme == "frost":
			mat.sky_top_color = Color("57b9f1")
			env.fog_light_color = Color("dfeefa")
			env.fog_density = 0.00065
	_env = env
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.87, 1.0)  # the horizon colour, so distance fades into sky
	env.fog_density = 0.0012
	# A little extra colour and punch, like a sunny cartoon (design doc 9.4).
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.94, 0.82)   # a touch warm, against the cool sky light
	if Palette.preview_pop and Palette.theme == "frost":
		sun.light_color = Color("f5faff")
	sun.light_specular = 1.0
	# Real shadows only near the camera, so they stay cheap (design doc 9.4).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	add_child(sun)
	_apply_quality()
	Controls.quality_changed.connect(_apply_quality)
	get_viewport().size_changed.connect(_fit_resolution)


## Graphics levels (design doc 9.1). High: 4x anti-aliasing, glow, surface
## relief, clear-coat paint (and sun shadows with ?shadows=on). Medium: 2x
## anti-aliasing, glow and relief. Low: none of those, and the 3D view drawn
## at 75% resolution.
func _apply_quality() -> void:
	var q := Controls.quality
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	_fit_resolution()
	_env.glow_enabled = q >= Controls.Quality.MEDIUM
	sun.shadow_enabled = Controls.shadows and q == Controls.Quality.HIGH
	Palette.apply_quality(q >= Controls.Quality.MEDIUM, q == Controls.Quality.HIGH)
	# Low also draws less: no kart-shaped shadows (the soft patch stays),
	# and the roadside plants and small rocks only close to the camera.
	KartVisual.cast_shadows = q >= Controls.Quality.MEDIUM
	Track.detail_reach = 0.45 if q == Controls.Quality.LOW else 1.0
	for n in get_tree().get_nodes_in_group("detail"):
		var gi := n as GeometryInstance3D
		gi.visibility_range_end = float(gi.get_meta("far")) * Track.detail_reach
	_fps_time = 0.0
	_fps_frames = 0


## Phones have very sharp screens (3 pixels per point is common), so
## drawing the 3D view at full sharpness costs 5 to 9 times the pixels of a
## laptop for little visible gain. Draw the 3D view at a pixel budget instead
## (High about 2 million pixels, Medium 1.2, Low 0.6) and let it scale up;
## menus and text stay full sharpness. This is usually the biggest single
## speed-up on phones (design doc 14).
func _fit_resolution() -> void:
	var vp := get_viewport()
	var px := float(vp.size.x * vp.size.y)
	var budget: float = [600000.0, 1200000.0, 2000000.0][Controls.quality]
	vp.scaling_3d_scale = clampf(sqrt(budget / maxf(px, 1.0)), 0.5, 1.0)


## Everyone starts on Low (Controls). If a player raises it and the device
## can't keep up (6 seconds of racing under 45 frames a second), step back
## down a level, without overwriting their saved choice.
func _watch_frame_rate(delta: float) -> void:
	# (Not while benchmarking: the quality asked for is the one measured.)
	if Controls.quality == Controls.Quality.LOW or _benching:
		return
	_fps_time += delta
	_fps_frames += 1
	if _fps_time >= 6.0:
		var fps := _fps_frames / _fps_time
		_fps_time = 0.0
		_fps_frames = 0
		if fps < 45.0:
			Controls.set_quality((Controls.quality - 1) as Controls.Quality, false)
			hud.flash("Graphics: %s, for smoother play" % Controls.quality_name(), 2.0)


static var _blob: StandardMaterial3D


## A soft dark oval that fades out at the edges.
func _blob_material() -> StandardMaterial3D:
	if _blob:
		return _blob
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.5))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.55, Color(0, 0, 0, 0.32))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_blob = StandardMaterial3D.new()
	_blob.albedo_texture = tex
	_blob.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blob.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blob.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _blob


func _spawn_kart(chassis: String, tires: String, driver: String, slot: int) -> Kart:
	var k := Kart.new()
	k.configure(chassis, tires, driver)
	k.number = slot + 1
	k.track = track
	add_child(k)
	var vis := KartVisual.new(k)
	k.add_child(vis)
	k.set_meta("visual", vis)
	var shadow := MeshInstance3D.new()  # soft blob shadow, on every device
	var quad := QuadMesh.new()
	quad.size = Vector2(1.9, 2.7)
	shadow.mesh = quad
	shadow.rotation.x = -PI / 2
	shadow.position.y = -0.24
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.material_override = _blob_material()
	k.add_child(shadow)
	k.add_child(TireDust.new(k))
	k.crashed.connect(func(s): if k == player_kart and s > 0.5: hud.flash("Ouch!", 0.8))
	k.lap_completed.connect(func(lap, _t): _on_lap(k, lap))
	karts.append(k)
	return k


func start_race() -> void:
	Controls.release_inputs()
	_finish_order.clear()
	_done = false
	results.hide_results()
	hud.touch.visible = Controls.is_touch_device() or hud._query_has("touch")
	if _autopilot:
		_autopilot.queue_free()
		_autopilot = null
	if player and not _autopilot_review:
		player.set_physics_process(true)
	for i in karts.size():
		var k := karts[i]
		k.global_transform = track.grid_transform(i)
		k.linear_velocity = Vector3.ZERO
		k.angular_velocity = Vector3.ZERO
		k.lap = 0
		k.next_checkpoint = 0
		k.race_time = 0.0
		k.finished = false
		k.set_meta("splits", [])
		k.boost_time = 0.0
		k.held_item = ""
		k.sticky_time = 0.0
		k.reset_physics_interpolation()
		k.hold = true
	_countdown = 3.0
	_racing = false
	player.locked = true
	_set_bots_enabled(false)


func _set_bots_enabled(on: bool) -> void:
	for c in get_children():
		if c is BotDriver:
			c.set_physics_process(on)
			if not on:
				(c as BotDriver).kart.input = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false}


func _process(delta: float) -> void:
	if _capture_intro and OS.has_feature("web") and bool(JavaScriptBridge.eval("window.__introHold === true", true)):
		return
	if _in_lobby:
		_fly_over(delta)
		return
	if _intro_left > 0.0:
		_intro(delta)
	if _racing:
		_watch_frame_rate(delta)
	if not _racing:
		var before := ceili(_countdown)
		_countdown -= delta
		if _countdown > 0.0:
			center_text = str(ceili(_countdown)) if _countdown <= 3.0 else ""
		else:
			center_text = "GO!"
			for k in karts:
				k.hold = false
			_racing = true
			player.locked = false
			_set_bots_enabled(true)
			for k in karts:
				k.race_time = 0.0
			if OS.has_feature("web") and str(JavaScriptBridge.eval("location.search", true)).contains("finishnow"):
				# For checking the finish: everyone on the last lap, just short of the line.
				for i in karts.size():
					var k := karts[i]
					k.lap = track.laps
					k.next_checkpoint = 0
					var f := track.transform_at(track.length - 30.0 - i * 9.0)
					k.global_transform = Transform3D(f.basis, f.origin + Vector3.UP * 0.6 + f.basis.x * ((i % 2) * 3.0 - 1.5))
					k.reset_physics_interpolation()
		if before != ceili(_countdown):
			pass
	elif center_text == "GO!" and player_kart.race_time > 1.0:
		center_text = ""
	camera.look_back = Input.is_key_pressed(KEY_C)
	if results.visible:
		_results_tick -= delta
		if _results_tick <= 0.0:
			_results_tick = 0.5
			_refresh_results()


func _on_lap(k: Kart, lap: int) -> void:
	if lap >= 2 and lap <= track.laps + 1:
		var splits: Array = k.get_meta("splits", [])
		splits.append(k.race_time)
		k.set_meta("splits", splits)
	if k.finished and not _finish_order.has(k):
		_finish_order.append(k)
		_report_finish(k)
	if k != player_kart:
		return
	if k.finished:
		_finish_player()
	elif lap == track.laps:
		hud.flash("Final lap!")
	elif lap > 1:
		hud.flash("Lap %d" % lap, 1.2)


func place_of(k: Kart) -> int:
	if _finish_order.has(k):
		return _finish_order.find(k) + 1
	var mine := track.race_distance(k)
	var place := _finish_order.size() + 1
	for other in karts:
		if other != k and not _finish_order.has(other) and track.race_distance(other) > mine:
			place += 1
	return place


func _on_parts_changed(chassis: String, tires: String, driver: String) -> void:
	player_kart.configure(chassis, tires, driver)
	(player_kart.get_meta("visual") as KartVisual).rebuild()
