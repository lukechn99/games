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
	_build_world()
	track = Track.new()
	add_child(track)
	camera = ChaseCamera.new()
	add_child(camera)
	hud = Hud.new()
	hud.race = self
	add_child(hud)
	hud.parts_changed.connect(_on_parts_changed)
	hud.restart_requested.connect(start_race)

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
	var q := str(JavaScriptBridge.eval("location.search", true)) if OS.has_feature("web") else ""
	if q.contains("showroom"):
		_showroom(q)
	elif q.contains("cam="):
		_camera_view(q)
	else:
		_open_lobby()
	# Compile every shader now, behind the lobby, instead of mid-race.
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
var _results: Label


func _start_online() -> void:
	_open_lobby_online()
	Net.state_changed.connect(_on_net_state)
	Net.relay_received.connect(_on_relay)


func _open_lobby_online() -> void:
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
		hud.visible = true
		camera.set_process(true)
		camera.follow(player_kart if player_kart else karts[0])
		start_race()
		# Everyone's lights go green at the same moment, by the host's clock.
		_countdown = maxf(0.5, float(st.get("startAt", 0.0)) / 1000.0 - Net.host_now())
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


func _show_results(st: Dictionary) -> void:
	if _results == null:
		var layer := CanvasLayer.new()
		layer.layer = 6
		add_child(layer)
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.1, 0.18, 0.85)
		sb.set_corner_radius_all(18)
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		sb.content_margin_top = 18
		sb.content_margin_bottom = 18
		panel.add_theme_stylebox_override("panel", sb)
		panel.set_anchors_preset(Control.PRESET_CENTER)
		layer.add_child(panel)
		var v := VBoxContainer.new()
		panel.add_child(v)
		_results = Label.new()
		_results.add_theme_font_size_override("font_size", 22)
		v.add_child(_results)
		if Net.is_host:
			var again := Button.new()
			again.text = "Race again"
			again.custom_minimum_size = Vector2(0, 52)
			again.add_theme_font_size_override("font_size", 20)
			again.pressed.connect(func(): Net.room("playAgain"))
			v.add_child(again)
		else:
			var wait := Label.new()
			wait.text = "The host can start another race."
			v.add_child(wait)
		panel.reset_size()
		panel.position = -panel.size * 0.5
	var finish: Dictionary = st.get("finish", {})
	var order: Array = finish.keys()
	order.sort_custom(func(a, b): return float(finish[a]) < float(finish[b]))
	var lines := ["Results"]
	var n := 1
	for id in order:
		var t := float(finish[id])
		lines.append("%d.  %s   %d:%05.2f" % [n, ("You" if id == Net.me else Net.name_of(id)), int(t / 60.0), fmod(t, 60.0)])
		n += 1
	for id in st.get("seats", []):
		if not finish.has(id):
			lines.append("–   %s   didn't finish" % ("You" if id == Net.me else Net.name_of(id)))
	_results.text = "\n".join(lines)


## Behind the lobby: a slow aerial circle round the whole track.
func _fly_over(delta: float) -> void:
	_tour += delta
	var center := Vector3(95, 0, -40)
	var a := _tour * 0.08
	camera.global_position = center + Vector3(cos(a) * 260.0, 150.0, sin(a) * 260.0)
	camera.look_at(center + Vector3(0, -10, 0), Vector3.UP)
	camera.fov = 55.0


## Races begin with everyone picking a kart and tapping Ready (design doc 4).
func _open_lobby() -> void:
	if lobby == null:
		lobby = Lobby.new()
		add_child(lobby)
		lobby.parts_changed.connect(func(c, t, d):
			_on_parts_changed(c, t, d)
			hud.set_choice(c, t, d))
		lobby.all_ready.connect(func():
			_in_lobby = false
			hud.visible = true
			camera.set_process(true)
			camera.follow(player_kart)
			start_race())
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
		k.global_transform = Transform3D(base.basis.rotated(Vector3.UP, 0.6), base.origin + base.basis.x * (float(i) - 1.5) * 3.2 + Vector3.UP * 0.32)
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
	mat.sky_top_color = Color(0.2, 0.5, 0.98)
	mat.sky_horizon_color = Color(0.62, 0.84, 1.0)
	mat.ground_horizon_color = Color(0.62, 0.84, 1.0)
	mat.ground_bottom_color = Color(0.4, 0.6, 0.35)
	mat.sun_angle_max = 20.0
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY  # metal and water reflect the sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# A soft glow around the brightest things: lamps, glints, boost flames.
	env.glow_intensity = 0.6
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env = env
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.84, 1.0)  # the horizon colour, so distance fades into sky
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.8
	sun.light_color = Color(1.0, 0.97, 0.9)   # a touch warm, against the cool sky light
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
	_fps_time = 0.0
	_fps_frames = 0


## Phones have very sharp screens (3 pixels per point is common), so
## drawing the 3D view at full sharpness costs 5 to 9 times the pixels of a
## laptop for little visible gain. Draw the 3D view at a pixel budget instead
## (High about 2 million pixels, Medium 1.4, Low 0.9) and let it scale up;
## menus and text stay full sharpness. This is usually the biggest single
## speed-up on phones (design doc 14).
func _fit_resolution() -> void:
	var vp := get_viewport()
	var px := float(vp.size.x * vp.size.y)
	var budget: float = [900000.0, 1400000.0, 2000000.0][Controls.quality]
	vp.scaling_3d_scale = clampf(sqrt(budget / maxf(px, 1.0)), 0.5, 1.0)


## Start on the best graphics and step down if the device can't keep up:
## each 6 seconds of racing below 45 frames a second drops one level.
func _watch_frame_rate(delta: float) -> void:
	if Controls.quality == Controls.Quality.LOW:
		return
	_fps_time += delta
	_fps_frames += 1
	if _fps_time >= 6.0:
		var fps := _fps_frames / _fps_time
		_fps_time = 0.0
		_fps_frames = 0
		if fps < 45.0:
			Controls.set_quality((Controls.quality - 1) as Controls.Quality)
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
	_finish_order.clear()
	for i in karts.size():
		var k := karts[i]
		k.global_transform = track.grid_transform(i)
		k.linear_velocity = Vector3.ZERO
		k.angular_velocity = Vector3.ZERO
		k.lap = 0
		k.next_checkpoint = 0
		k.race_time = 0.0
		k.finished = false
		k.boost_time = 0.0
		k.held_item = ""
		k.sticky_time = 0.0
		k.reset_physics_interpolation()
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
	if _in_lobby:
		_fly_over(delta)
		return
	if _racing:
		_watch_frame_rate(delta)
	if not _racing:
		var before := ceili(_countdown)
		_countdown -= delta
		if _countdown > 0.0:
			center_text = str(ceili(_countdown))
		else:
			center_text = "GO!"
			_racing = true
			player.locked = false
			_set_bots_enabled(true)
			for k in karts:
				k.race_time = 0.0
		if before != ceili(_countdown):
			pass
	elif center_text == "GO!" and player_kart.race_time > 1.0:
		center_text = ""
	camera.look_back = Input.is_key_pressed(KEY_C)


func _on_lap(k: Kart, lap: int) -> void:
	if k.finished and not _finish_order.has(k):
		_finish_order.append(k)
		_report_finish(k)
	if k != player_kart:
		return
	if k.finished:
		center_text = "%d%s place!" % [place_of(k), hud._ordinal(place_of(k))]
		if not Net.active:
			hud.flash("Garage → Restart race to go again", 6.0)
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
