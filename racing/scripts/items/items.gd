class_name Items
extends Node3D
## Item crates and the items in play (design doc 6).
##
## Crates sit in rows across the cave route, glowing like the crystals, and
## come back 3 seconds after you drive through one. You hold one item; use it
## with the item button (E on a keyboard).
## - Honey puddle: dropped behind you. Drive through it and you're slow and
##   sluggish for 2 seconds. It lasts 15 seconds or 3 karts.
## - Tumbleweed: rolled backwards down the track from your kart. It bounces
##   about unpredictably and knocks karts sideways.
## - Sand gun (Frosty Pass): sprays sand for 5 seconds in a weaving S across
##   the road ahead of you. Ice under sand grips like road, for anyone, until
##   the sand blows away 8 seconds later.
##
## Online, using an item is sent to everyone, so every game shows it; each
## game only applies hits to the karts it drives (like bumps).

signal used(kind: String, pos: Vector3, dir: Vector3, seed_value: int)

const KINDS := ["honey", "tumbleweed"]
const CRATE_ROWS := [0.36, 0.72]          # where along the split (see Track.BRANCH)
const CRATE_LANES := [-4.5, -1.5, 1.5, 4.5]
const RESPAWN := 3.0
const SPIN := 0.9                         # the "what did I get?" pause

var track: Track
var karts: Array[Kart] = []
## Karts this game drives (pick up crates and take hits). Default: all.
var owned: Array[Kart] = []

var _crates: Array[Dictionary] = []      # {node, pos, away}
var _honey: Array[Dictionary] = []       # {node, pos, life, uses, inside: {}}
var _weeds: Array[Dictionary] = []       # {node, pos, vel, life, rng, hit: {}}
var _snowballs: Array[Dictionary] = []   # {node, pos, vel, age}
var _sprays: Array[Dictionary] = []      # {kart, t, next, phase, gun, jet}
const SPRAY_TIME := 5.0                   # seconds of spraying
const SAND_LIFE := 8.0                    # how long sand lies before it blows away
const SAND_R := 2.2                       # each pile's radius (m)
const SAND_AHEAD := 8.0                   # where it lands, ahead of the kart
const SAND_SWEEP := 4.0                   # the S: side to side, ± metres...
const SAND_WEAVE := 1.6                   # ...once each way in this many seconds
## Sand on the ground, for every kart's tyres: [position, seconds left].
static var sand: Array = []
var _sand_mm: MultiMeshInstance3D
const SNOWBALL_SPEED := 34.0              # faster than any kart
var _was_pressed := {}
var _rng := RandomNumberGenerator.new()
var _bot_wait := {}


func setup(t: Track, all: Array[Kart], mine: Array[Kart]) -> void:
	track = t
	karts = all
	owned = mine
	_rng.seed = 99
	sand.clear()
	for f in track.crate_frames():
		for x in CRATE_LANES:
			var p: Vector3 = f.origin + f.basis.x * x + Vector3.UP * 1.0
			var n := _crate_mesh()
			n.position = p
			add_child(n)
			_crates.append({"node": n, "pos": p, "away": 0.0})
	_spawn_coins()
	# Crates on moving things (the mine's rope bridge) follow them.
	for m in track.moving_crates:
		var n := _crate_mesh()
		var host: Node3D = m["node"]
		var p: Vector3 = host.global_transform * (m["local"] as Vector3) if host.is_inside_tree() else Vector3.ZERO
		n.position = p
		add_child(n)
		_crates.append({"node": n, "pos": p, "away": 0.0, "host": host, "local": m["local"]})


# --- Looks ---------------------------------------------------------------

static var _crate_mat: ShaderMaterial
static var _mark_mat: ShaderMaterial
static var _box_parts: Array = []   # [mesh, material, transform]
static var _honey_mat: StandardMaterial3D
static var _weed_mat: StandardMaterial3D


func _crate_mesh() -> Node3D:
	# The item box is a model built in Blender (tools/blender/item_box.py): a
	# pink jelly cube with a yellow question mark inside, rimmed in orange.
	var root := Node3D.new()
	if _box_parts.is_empty():
		var scene: PackedScene = load("res://assets/models/item_box.glb")
		var inst := scene.instantiate()
		_crate_mat = ShaderMaterial.new()
		_crate_mat.shader = load("res://shaders/item_box.gdshader")
		_mark_mat = ShaderMaterial.new()
		_mark_mat.shader = load("res://shaders/item_mark.gdshader")
		var rim := ShaderMaterial.new()
		rim.shader = _mark_mat.shader
		rim.set_shader_parameter("color", Color(1.0, 0.45, 0.08))
		rim.set_shader_parameter("lift", 0.0)
		_mark_mat.render_priority = 2
		rim.render_priority = 1
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var mat: Material = _crate_mat
			if m.name.begins_with("MarkEdge"):
				mat = rim
			elif m.name.begins_with("Mark"):
				mat = _mark_mat
			_box_parts.append([m.mesh, mat, m.transform])
		inst.free()
	var spin := Node3D.new()
	spin.rotation = Vector3(0.0, 0.0, 0.25)
	spin.scale = Vector3.ONE * 1.2
	root.add_child(spin)
	for p in _box_parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = p[1]
		mi.transform = p[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spin.add_child(mi)
	return root


func _honey_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.1
	cyl.height = 0.06
	cyl.radial_segments = 20
	mi.mesh = cyl
	if _honey_mat == null:
		_honey_mat = StandardMaterial3D.new()
		_honey_mat.albedo_color = Color(1.0, 0.68, 0.12)
		_honey_mat.roughness = 0.1
		_honey_mat.metallic_specular = 1.0
		_honey_mat.rim_enabled = true
		_honey_mat.rim = 0.4
	mi.material_override = _honey_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _weed_mesh() -> Node3D:
	var root := Node3D.new()
	if _weed_mat == null:
		_weed_mat = StandardMaterial3D.new()
		_weed_mat.albedo_color = Color(0.82, 0.63, 0.36)
		_weed_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	# A tangle of twiggy rings.
	for i in 6:
		var mi := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.62
		tor.outer_radius = 0.7
		tor.rings = 14
		tor.ring_segments = 4
		mi.mesh = tor
		mi.material_override = _weed_mat
		mi.rotation = Vector3(i * 1.1, i * 0.7, i * 0.4)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


# --- Each frame -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if track == null:
		return
	_crate_pickups(delta)
	_use_items()
	_update_honey(delta)
	_update_coins(delta)
	_update_weeds(delta)
	_update_snowballs(delta)
	_update_sprays(delta)
	_update_sand(delta)


func _crate_pickups(delta: float) -> void:
	for c in _crates:
		var node: Node3D = c["node"]
		if c["away"] > 0.0:
			c["away"] -= delta
			node.visible = c["away"] <= 0.0
			continue
		if c.has("host") and is_instance_valid(c["host"]):
			c["pos"] = (c["host"] as Node3D).global_transform * (c["local"] as Vector3)
			node.position = c["pos"]
		node.rotation.y += delta * 1.5
		node.position.y = c["pos"].y + sin(Time.get_ticks_msec() / 400.0 + c["pos"].x) * 0.15
		for k in karts:
			if k.global_position.distance_to(c["pos"]) < 1.7:
				c["away"] = RESPAWN
				node.visible = false
				if owned.has(k) and k.held_item == "" and k.item_spin <= 0.0:
					k.item_spin = SPIN
					var pool := pool()
					k.set_meta("pending_item", pool[_rng.randi() % pool.size()])
				break
	for k in owned:
		if k.item_spin <= 0.0 and k.has_meta("pending_item"):
			k.held_item = k.get_meta("pending_item")
			k.remove_meta("pending_item")


## What crates can give here: the snowball only on snowy tracks (design doc 6).
func pool() -> Array:
	return KINDS + ["snowball", "sandgun"] if track and track.layout == "frost" else KINDS


func _use_items() -> void:
	for k in owned:
		var pressed := bool(k.input.get("item", false))
		var fire: bool = pressed and not bool(_was_pressed.get(k, false))
		_was_pressed[k] = pressed
		if k.has_meta("bot_items"):
			fire = _bot_wants(k)
		if fire and k.held_item != "" and k.item_spin <= 0.0:
			var kind := k.held_item
			k.held_item = ""
			var back := k.global_transform.basis.z
			back.y = 0.0
			back = back.normalized()
			var seed_value := _rng.randi()
			# Dropped behind, except the snowball (bowled ahead) and the sand
			# gun (sprays ahead, from the kart itself).
			var ahead := kind in ["snowball", "sandgun"]
			var dir := -back if ahead else back
			var at := k.global_position + dir * ({"snowball": 3.2, "sandgun": 0.0}.get(kind, 2.6) as float)
			spawn(kind, at, dir, seed_value)
			used.emit(kind, at, dir, seed_value)


## Computer drivers use an item when someone is close behind, or after a while.
func _bot_wants(k: Kart) -> bool:
	if k.held_item == "" or k.item_spin > 0.0:
		_bot_wait.erase(k)
		return false
	_bot_wait[k] = float(_bot_wait.get(k, 0.0)) + get_physics_process_delta_time()
	for other in karts:
		if other == k:
			continue
		var rel := other.global_position - k.global_position
		if k.held_item == "sandgun":
			break   # (decided below, by the road ahead, not by rivals)
		if k.held_item == "snowball":
			# Bowl it at someone a little way ahead.
			if rel.length() < 45.0 and rel.dot(-k.global_transform.basis.z) > 6.0:
				return true
		elif rel.length() < 25.0 and rel.dot(k.global_transform.basis.z) > 3.0:
			return true
	if k.held_item == "sandgun":
		return _ice_ahead(k) or _bot_wait[k] > 20.0
	return _bot_wait[k] > 8.0


## Ice on the road 6 to 30 m ahead of this kart (a computer driver's cue to
## spray sand).
func _ice_ahead(k: Kart) -> bool:
	var fwd := -k.global_transform.basis.z
	for d in [6.0, 14.0, 22.0, 30.0]:
		var p: Vector3 = k.global_position + fwd * d
		if FrostTrack.main_on_ice(p) or track.surface_at_fraction(fposmod(track.offset_of(p), track.length) / track.length) == "ice":
			return true
	return false


## Put an item into play (ours, or one another player used).
func spawn(kind: String, pos: Vector3, dir: Vector3, seed_value: int) -> void:
	match kind:
		"honey":
			var ground := _ground_below(pos)
			var mi := _honey_mesh()
			mi.position = ground + Vector3.UP * 0.07
			add_child(mi)
			_honey.append({"node": mi, "pos": ground, "life": 15.0, "uses": 0, "inside": {}})
		"tumbleweed":
			var n := _weed_mesh()
			n.position = pos + Vector3.UP * 0.8
			add_child(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			_weeds.append({"node": n, "pos": pos + Vector3.UP * 0.8, "vel": dir * 13.0, "life": 9.0, "rng": rng, "hit": {}, "hop": 0.0})
		"sandgun":
			# The kart that fired: the nearest to where it was used.
			var who: Kart = null
			for k in karts:
				if who == null or k.global_position.distance_to(pos) < who.global_position.distance_to(pos):
					who = k
			if who == null or who.global_position.distance_to(pos) > 6.0:
				return
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var gun := _gun_node()
			who.add_child(gun)
			_sprays.append({"kart": who, "t": 0.0, "next": 0.0, "phase": rng.randf() * TAU, "gun": gun})
		"snowball":
			var n := MeshInstance3D.new()
			n.mesh = _snow_mesh()
			n.position = pos
			add_child(n)
			_snowballs.append({"node": n, "pos": pos, "vel": dir * SNOWBALL_SPEED, "age": 0.0})


func _ground_below(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p - Vector3.UP * 6.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else p


func _update_honey(delta: float) -> void:
	for h in _honey.duplicate():
		h["life"] -= delta
		for k in karts:
			var inside: bool = Vector2(k.global_position.x - h["pos"].x, k.global_position.z - h["pos"].z).length() < 2.1 and absf(k.global_position.y - h["pos"].y) < 1.5
			if inside and not h["inside"].has(k):
				h["uses"] += 1
				if owned.has(k):
					k.stick(2.0)
			if inside:
				h["inside"][k] = true
			else:
				h["inside"].erase(k)
		var node: Node3D = h["node"]
		if h["life"] < 1.0:
			node.scale = Vector3.ONE * maxf(0.05, h["life"])
		if h["life"] <= 0.0 or (h["uses"] >= 3 and h["inside"].is_empty()):
			node.queue_free()
			_honey.erase(h)


func _update_weeds(delta: float) -> void:
	for w in _weeds.duplicate():
		w["life"] -= delta
		var rng: RandomNumberGenerator = w["rng"]
		var vel: Vector3 = w["vel"]
		# Roll along the road the way it was thrown, wandering side to side.
		var off := track.offset_of(w["pos"])
		var frame := track.transform_at(off)
		var along := -frame.basis.z if vel.dot(-frame.basis.z) > 0.0 else frame.basis.z
		var to_line: Vector3 = frame.origin - w["pos"]
		to_line.y = 0.0
		vel = vel.lerp(along * 13.0 + frame.basis.x * rng.randf_range(-6.0, 6.0) + to_line * 0.4, clampf(delta * 1.5, 0.0, 1.0))
		w["vel"] = vel
		var pos: Vector3 = w["pos"] + vel * delta
		# Bounce: hop again whenever it lands.
		w["hop"] += delta * (5.0 + rng.randf() * 3.0)
		pos.y = frame.origin.y + 0.75 + absf(sin(w["hop"])) * 1.3
		w["pos"] = pos
		var node: Node3D = w["node"]
		node.position = pos
		node.rotate(Vector3.UP.cross(vel.normalized()).normalized() if vel.length() > 0.1 else Vector3.RIGHT, delta * vel.length() / 0.7)
		for k in karts:
			if not w["hit"].has(k) and k.global_position.distance_to(pos) < 1.8:
				w["hit"][k] = true
				if owned.has(k):
					k.knock(pos)
		if w["life"] <= 0.0:
			node.queue_free()
			_weeds.erase(w)


# --- Snowball -----------------------------------------------------------------
# Bowled ahead along the road, growing as it rolls (design doc 6): the further
# it goes, the bigger the hit. Bursts on the first kart it reaches, or when
# it leaves the road (a bank or a wall), or after a while.

static var _snow: SphereMesh


func _snow_mesh() -> SphereMesh:
	if _snow == null:
		_snow = SphereMesh.new()
		_snow.radius = 1.0
		_snow.height = 2.0
		_snow.radial_segments = 16
		_snow.rings = 8
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.96, 0.97, 1.0)
		m.albedo_texture = load(Palette.TEX_DIR + "ice.png")
		m.roughness = 0.85
		_snow.material = m
	return _snow


func _update_snowballs(delta: float) -> void:
	for b in _snowballs.duplicate():
		b["age"] += delta
		var age: float = b["age"]
		var r := 0.45 + 1.05 * minf(1.0, age / 3.0)
		var off := track.offset_of(b["pos"])
		var frame := track.transform_at(off)
		var vel: Vector3 = b["vel"]
		var along := -frame.basis.z if vel.dot(-frame.basis.z) > 0.0 else frame.basis.z
		var to_line: Vector3 = frame.origin - b["pos"]
		to_line.y = 0.0
		# Follows the road round the bends, drifting a little toward its middle.
		vel = vel.lerp(along * SNOWBALL_SPEED + to_line * 0.25, clampf(delta * 3.0, 0.0, 1.0))
		b["vel"] = vel
		var pos: Vector3 = b["pos"] + vel * delta
		var ground := _ground_below(pos + Vector3.UP * 2.0)
		pos.y = ground.y + r
		b["pos"] = pos
		var node: Node3D = b["node"]
		node.position = pos
		node.scale = Vector3.ONE * r
		if vel.length() > 0.1:
			node.rotate(Vector3.UP.cross(vel.normalized()).normalized(), delta * vel.length() / r)
		var burst := age > 6.0
		var local: Vector3 = track.road_local(pos)
		if absf(local.x) > Track.ROAD_WIDTH * 0.5 + 2.0:
			burst = true   # into the bank or a wall
		for k in karts:
			if age > 0.25 and k.global_position.distance_to(pos) < r + 0.9:
				if owned.has(k):
					k.knock(pos)
					k.linear_velocity *= 0.55   # a big snowball stops you, not just shoves you
				burst = true
				break
		if burst:
			_puff(pos, r)
			node.queue_free()
			_snowballs.erase(b)


## A burst of snow.
# --- Sand gun -----------------------------------------------------------------

static var _gun_scene: PackedScene


## The blaster on the kart's nose, with a jet of sand from its nozzle.
func _gun_node() -> Node3D:
	if _gun_scene == null:
		_gun_scene = load("res://assets/models/sand_gun.glb")
	var root := Node3D.new()
	root.position = Vector3(0, 0.75, -1.1)
	root.add_child(_gun_scene.instantiate())
	var jet := CPUParticles3D.new()
	jet.position = Vector3(0, 0, -0.6)
	jet.amount = 40
	jet.lifetime = 0.6
	jet.direction = Vector3(0, 0.35, -1)
	jet.spread = 14.0
	jet.initial_velocity_min = 11.0
	jet.initial_velocity_max = 15.0
	jet.gravity = Vector3(0, -16, 0)
	jet.scale_amount_min = 0.08
	jet.scale_amount_max = 0.16
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 4
	m.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Parts.surface("sand")["color"]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	jet.mesh = m
	jet.local_coords = false
	root.add_child(jet)
	return root


func _update_sprays(delta: float) -> void:
	for sp in _sprays.duplicate():
		var k: Kart = sp["kart"]
		sp["t"] += delta
		var gun: Node3D = sp["gun"]
		if not is_instance_valid(k) or sp["t"] >= SPRAY_TIME:
			if is_instance_valid(gun):
				gun.queue_free()
			_sprays.erase(sp)
			continue
		# The nozzle swings side to side with the S it draws.
		var swing := sin(TAU * float(sp["t"]) / SAND_WEAVE + float(sp["phase"]))
		gun.rotation.y = -swing * 0.45
		sp["next"] -= delta
		if sp["next"] > 0.0:
			continue
		sp["next"] = 0.12
		var fwd := -k.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP)
		var at := _ground_below(k.global_position + fwd * (SAND_AHEAD + k.linear_velocity.length() * 0.15) + right * swing * SAND_SWEEP)
		sand.append([at, SAND_LIFE])


## Sand piles: one batched mesh for all of them (a single draw call).
func _update_sand(delta: float) -> void:
	if sand.is_empty() and _sand_mm == null:
		return
	for s in sand:
		s[1] -= delta
	sand = sand.filter(func(s): return s[1] > 0.0)
	if _sand_mm == null:
		_sand_mm = MultiMeshInstance3D.new()
		_sand_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cyl := CylinderMesh.new()
		cyl.top_radius = SAND_R * 0.8
		cyl.bottom_radius = SAND_R
		cyl.height = 0.08
		cyl.radial_segments = 12
		cyl.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Parts.surface("sand")["color"]
		mat.albedo_texture = load(Palette.TEX_DIR + "dirt.png") if ResourceLoader.exists(Palette.TEX_DIR + "dirt.png") else null
		mat.uv1_triplanar = true
		mat.roughness = 1.0
		cyl.material = mat
		mm.mesh = cyl
		_sand_mm.multimesh = mm
		add_child(_sand_mm)
	var mm := _sand_mm.multimesh
	if mm.instance_count < sand.size():
		mm.instance_count = maxi(64, sand.size() * 2)
	mm.visible_instance_count = sand.size()
	for i in sand.size():
		var s: Array = sand[i]
		# Grows in as it lands, thins away in its last second.
		var k := minf(1.0, (SAND_LIFE - float(s[1])) * 6.0) * minf(1.0, float(s[1]))
		var b := Basis().scaled(Vector3(maxf(k, 0.05), 1.0, maxf(k, 0.05))).rotated(Vector3.UP, float(i) * 1.7)
		mm.set_instance_transform(i, Transform3D(b, (s[0] as Vector3) + Vector3.UP * 0.02))


## True where sand lies on the ground (tyres grip there: kart.gd).
static func sanded(p: Vector3) -> bool:
	for s in sand:
		var q: Vector3 = s[0]
		if absf(q.y - p.y) < 1.5 and Vector2(q.x - p.x, q.z - p.z).length_squared() < SAND_R * SAND_R:
			return true
	return false


func _puff(at: Vector3, r: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 3.0 * r
	p.initial_velocity_max = 6.0 * r
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.25 * r
	p.scale_amount_max = 0.5 * r
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.98, 1.0)
	m.material = mat
	p.mesh = m
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


# --- Coins ------------------------------------------------------------------
# Spinning gold coins in rows on the road (Dressing._coins). Each adds 1% to
# your top speed, up to 10; being hit by an item costs three (kart.gd).

const COIN_RESPAWN := 10.0
const COIN_MAX := 10
var _coins: Array[Dictionary] = []   # {node, pos, away}
static var _coin_mesh: Mesh


static func coin_mesh() -> Mesh:
	if _coin_mesh == null:
		var scene: PackedScene = load("res://assets/models/coin.glb")
		if scene == null:
			return null
		var inst := scene.instantiate()
		var mi := inst.find_children("*", "MeshInstance3D", true, false)
		if not mi.is_empty():
			_coin_mesh = Palette.restyle((mi[0] as MeshInstance3D).mesh)
		inst.free()
	return _coin_mesh


func _spawn_coins() -> void:
	if track.coin_spots.is_empty():
		return
	var mesh := coin_mesh()
	for p in track.coin_spots:
		var n := MeshInstance3D.new()
		n.mesh = mesh
		n.position = p
		n.scale = Vector3.ONE * 1.3
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		_coins.append({"node": n, "pos": p, "away": 0.0})


func _update_coins(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for c in _coins:
		var node: Node3D = c["node"]
		if c["away"] > 0.0:
			c["away"] -= delta
			node.visible = c["away"] <= 0.0
			continue
		node.rotation.y = t * 3.0
		node.position.y = c["pos"].y + sin(t * 3.0 + c["pos"].x) * 0.1
		for k in karts:
			if k.global_position.distance_to(c["pos"]) < 1.6:
				c["away"] = COIN_RESPAWN
				node.visible = false
				if owned.has(k):
					k.coins = mini(COIN_MAX, k.coins + 1)
				break
