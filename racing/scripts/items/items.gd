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
var _was_pressed := {}
var _rng := RandomNumberGenerator.new()
var _bot_wait := {}


func setup(t: Track, all: Array[Kart], mine: Array[Kart]) -> void:
	track = t
	karts = all
	owned = mine
	_rng.seed = 99
	for u in CRATE_ROWS:
		var d: float = lerpf(Track.BRANCH[0], Track.BRANCH[1], u)
		var f := track.branch_frame(d)
		for x in CRATE_LANES:
			var p: Vector3 = f.origin + f.basis.x * x + Vector3.UP * 1.0
			var n := _crate_mesh()
			n.position = p
			add_child(n)
			_crates.append({"node": n, "pos": p, "away": 0.0})


# --- Looks ---------------------------------------------------------------

static var _crate_mat: ShaderMaterial
static var _honey_mat: StandardMaterial3D
static var _weed_mat: StandardMaterial3D


func _crate_mesh() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.1
	mi.mesh = box
	if _crate_mat == null:
		_crate_mat = ShaderMaterial.new()
		_crate_mat.shader = load("res://shaders/crate.gdshader")
	mi.material_override = _crate_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation = Vector3(0.6, 0.0, 0.6)
	root.add_child(mi)
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
	_update_weeds(delta)


func _crate_pickups(delta: float) -> void:
	for c in _crates:
		var node: Node3D = c["node"]
		if c["away"] > 0.0:
			c["away"] -= delta
			node.visible = c["away"] <= 0.0
			continue
		node.rotation.y += delta * 1.5
		node.position.y = c["pos"].y + sin(Time.get_ticks_msec() / 400.0 + c["pos"].x) * 0.15
		for k in karts:
			if k.global_position.distance_to(c["pos"]) < 1.7:
				c["away"] = RESPAWN
				node.visible = false
				if owned.has(k) and k.held_item == "" and k.item_spin <= 0.0:
					k.item_spin = SPIN
					k.set_meta("pending_item", KINDS[_rng.randi() % KINDS.size()])
				break
	for k in owned:
		if k.item_spin <= 0.0 and k.has_meta("pending_item"):
			k.held_item = k.get_meta("pending_item")
			k.remove_meta("pending_item")


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
			spawn(kind, k.global_position + back * 2.6, back, seed_value)
			used.emit(kind, k.global_position + back * 2.6, back, seed_value)


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
		if rel.length() < 25.0 and rel.dot(k.global_transform.basis.z) > 3.0:
			return true
	return _bot_wait[k] > 8.0


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
