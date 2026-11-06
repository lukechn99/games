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
	camera.follow(player_kart)
	hud.minimap.setup(track, karts, player_kart)
	start_race()
	var q := str(JavaScriptBridge.eval("location.search", true)) if OS.has_feature("web") else ""
	if q.contains("showroom"):
		_showroom(q)


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
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.84, 1.0)
	env.fog_density = 0.0007
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.8
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


func _apply_quality() -> void:
	sun.shadow_enabled = Controls.shadows
	_fps_time = 0.0
	_fps_frames = 0


## If a phone can't keep up with shadows, turn them off once, early in the
## race, and say so. Players can turn them back on in the garage.
func _watch_frame_rate(delta: float) -> void:
	if not Controls.shadows or _fps_time > 8.0:
		return
	_fps_time += delta
	_fps_frames += 1
	if _fps_time > 8.0 and _fps_frames / _fps_time < 40.0:
		Controls.set_shadows(false)
		_fps_time = 99.0
		hud.flash("Shadows off for smoother play", 2.0)


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
	if k != player_kart:
		return
	if k.finished:
		center_text = "%d%s place!" % [place_of(k), hud._ordinal(place_of(k))]
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
