class_name KartVisual
extends Node3D
## Placeholder kart and driver built from simple shapes, so every chassis,
## tire and driver combination works from day one (design doc 5.5). The
## real models will replace the shapes but keep the same mounting points.
##
## The driver is the shared rounded base body (design doc 5.4) with a few
## animal features, and it leans, bobs and wobbles with the kart (9.2).

var kart: Kart
var _wheels: Array[Node3D] = []
var _driver: Node3D
var _torso: Node3D
var _head: Node3D
var _wobbly: Array[Node3D] = []   # ears, tails, antlers: swing with momentum
var _wobble_vel: Array[Vector2] = []
var _wobble_pos: Array[Vector2] = []
var _wheel_ring: Node3D
var _boost_flame: MeshInstance3D
var _exhaust_tips: Array[Vector3] = []
var _exhaust_flames: Array[MeshInstance3D] = []
var _sparks: MeshInstance3D
var _lean := 0.0
var _bob := 0.0
var _bob_vel := 0.0
var _finish := Palette.Finish.PAINT  # parts built from now on


## `standing`: just the driver, standing on its own feet beside the kart
## (the kart-selection screen), instead of the kart with the driver seated.
var standing := false
## `empty`: the kart with nobody in it (the driver stands beside it).
var empty := false


func _init(k: Kart, merge := true, stand := false) -> void:
	kart = k
	standing = stand
	if not merge:
		set_meta("nomerge", true)


func _ready() -> void:
	rebuild()
	if not standing and get_meta("nomerge", false) == false:
		_add_contact_shadow()


## Exhaust flames: small and flickery while driving, big on a boost or a
## mini-turbo, out when stopped.
func _update_exhaust() -> void:
	if _exhaust_flames.is_empty():
		return
	var go: bool = absf(kart.speed) > 1.0 or float(kart.input.get("throttle", 0.0)) > 0.1
	var size := 0.0
	if kart.boost_time > 0.0:
		size = 1.15 + randf() * 0.35
	elif go:
		size = 0.32 + randf() * 0.12
	for fl in _exhaust_flames:
		fl.visible = size > 0.0
		fl.scale = Vector3(0.9, 1.0, 0.9) * size


# --- Contact shadow ---------------------------------------------------------
# A soft dark patch on whatever is under the kart, so it sits on the road
# instead of floating (real sun shadows are off in the browser renderer).
# It shrinks and fades as the kart leaves the ground.

var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D


func _add_contact_shadow() -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.orientation = PlaneMesh.FACE_Y
	_shadow = MeshInstance3D.new()
	_shadow.mesh = q
	# Darker in the middle than the scenery's shade blobs.
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.62))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.55, Color(0, 0, 0, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	_shadow_mat = SetPieces.shade_material().duplicate()
	_shadow_mat.albedo_texture = tex
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	_shadow.visible = false
	add_child(_shadow)


func _update_shadow() -> void:
	if _shadow == null or not is_inside_tree():
		return
	# Centred between the wheels, about the size of the wheelbase.
	var mid := Vector3.ZERO
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for i in 4:
		var m := kart.wheel_mount(i)
		mid += m * 0.25
		lo = lo.min(m)
		hi = hi.max(m)
	var size := Vector2(hi.x - lo.x + 0.9, hi.z - lo.z + 1.1)
	var from := kart.global_transform * Vector3(mid.x, 0.0, mid.z) + Vector3.UP * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 7.0)
	q.exclude = [kart.get_rid()]
	q.collision_mask = 1
	var hit := kart.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(Vector3.UP) < 0.5:
		_shadow.visible = false
		if _cast:
			_cast.visible = false
		return
	var n: Vector3 = hit["normal"]
	# Height of the kart above its usual ride height.
	var h := maxf(0.0, from.y - 0.6 - (hit["position"] as Vector3).y - 0.6)
	var fwd := -kart.global_transform.basis.z
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := fwd.cross(n).normalized()
	var grow := 1.0 + h * 0.25
	_shadow.global_transform = Transform3D(Basis(right * size.x * grow, n, -fwd * size.y * grow), hit["position"] + n * 0.09)
	_shadow_mat.albedo_color = Color(1, 1, 1, clampf(1.0 - h * 0.35, 0.0, 1.0) * 0.7)
	_shadow.visible = true
	if _cast:
		_cast_mat.set_shader_parameter("plane_point", hit["position"])
		_cast_mat.set_shader_parameter("plane_normal", n)
		_cast_mat.set_shader_parameter("strength", 0.6 * clampf(1.2 - h * 0.25, 0.0, 1.0))
		_cast.visible = cast_shadows


## Paintwork shines softly, metal sharply, rubber and fur not at all (9.4).
func _mat(c: Color) -> StandardMaterial3D:
	var finish := _finish
	if finish == Palette.Finish.PAINT:
		if c in [METAL, CHROME, Color(0.6, 0.6, 0.64), Color(0.45, 0.47, 0.52)]:
			finish = Palette.Finish.METAL
		elif c == DARK or c.v < 0.22:
			finish = Palette.Finish.MATTE
	return Palette.toon(c, false, 0.0, finish)


func _mesh(mesh: Mesh, c: Color, parent: Node3D, pos := Vector3.ZERO, scale_v := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.scale = scale_v
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float, rings := 8, segs := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.rings = rings
	s.radial_segments = segs
	return s


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.rings = 4
	c.radial_segments = 10
	return c


func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


## Rebuild everything, e.g. after the player swaps a part.
func rebuild() -> void:
	for c in get_children():
		if c != _shadow:
			# Detach now, not at the end of the frame: otherwise the merge
			# below picks up the old kart's meshes (its black outline shell
			# got merged in as solid bodywork, darkening the whole kart).
			remove_child(c)
			c.queue_free()
	_inks.clear()
	_cast = null
	_wheels.clear()
	_rack = null
	_rack_item = ""
	_finish = Palette.Finish.PAINT
	_wobbly.clear()
	_wobble_vel.clear()
	_wobble_pos.clear()
	_wheel_ring = null
	_torso = null
	_head = null
	_driver = null
	_boost_flame = null
	_exhaust_tips.clear()
	_exhaust_flames.clear()
	_sparks = null
	if standing:
		_build_standing()
		return
	var ch := kart.chassis
	var size: Vector3 = ch["size"]
	var color: Color = ch["color"]
	var body_y := size.y * 0.5 + 0.05

	# Chassis: a go-kart built from metal tubes with aerodynamic bodywork
	# (nose fairing, side pods, rear bumper). Every piece is placed from the
	# chassis's own wheel mounts, so wheels and driver always line up (5.5).
	var seat := _build_frame(kart.chassis_id, color)
	var column := Node3D.new()
	column.position = seat["wheel_at"]
	column.rotation.x = deg_to_rad(-60)
	add_child(column)
	var wheel_mesh := TorusMesh.new()
	wheel_mesh.inner_radius = 0.1
	wheel_mesh.outer_radius = 0.14
	wheel_mesh.rings = 12
	wheel_mesh.ring_segments = 6
	_wheel_ring = _mesh(wheel_mesh, Color(0.15, 0.15, 0.18), column)
	_mesh(_box(Vector3(0.12, 0.03, 0.06)), Color(0.15, 0.15, 0.18), _wheel_ring)
	body_y = seat["y"]

	# Boost flame and drift sparks, hidden until needed.
	_boost_flame = _mesh(_cone(0.18, 0.6), Color(1.0, 0.6, 0.15), self, Vector3(0, body_y, size.z * 0.6), Vector3.ONE, Vector3(-PI / 2, 0, 0))
	_boost_flame.material_override = _glow(Color(1.0, 0.62, 0.2))
	_boost_flame.visible = false
	_boost_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Little flames at each exhaust: a flicker at idle, a roar on a boost.
	if not _exhaust_tips.is_empty():
		_boost_flame.scale = Vector3.ZERO   # the exhausts carry the boost now
		var fst := SurfaceTool.new()
		fst.begin(Mesh.PRIMITIVE_TRIANGLES)
		MineTrack._flame(fst, Vector3.ZERO)
		var fmesh := fst.commit()
		var fmat := ShaderMaterial.new()
		fmat.shader = load("res://shaders/flame.gdshader")
		for tip in _exhaust_tips:
			var fl := MeshInstance3D.new()
			fl.mesh = fmesh
			fl.material_override = fmat
			fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fl.set_meta("keep", true)
			fl.visibility_range_end = 60.0
			# Point the flame back and a little up, out of the pipe.
			var up := Vector3(0, 0.34, 1).normalized()
			fl.transform = Transform3D(Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)), tip)
			add_child(fl)
			_exhaust_flames.append(fl)
	_sparks = _mesh(_sphere(0.12, 4, 6), Color(0.4, 0.75, 1.0), self, Vector3(0, 0.1, size.z * 0.5))
	_sparks.material_override = _glow(Color(0.45, 0.8, 1.0))
	_sparks.visible = false
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Wheels snap to the chassis's mounting points.
	# Fat, chunky tyres like a cartoon racer's (design doc 9.4): wider than
	# the physics wheel (looks only), rounded shoulders, tread blocks all the
	# way round and a bright painted rim.
	var r := kart.wheel_radius()
	var tire_color: Color = kart.tires["color"]
	var width: float = kart.tires["width"] * 1.35
	var rim_color := Color(0.98, 0.8, 0.18) if kart.tires_id != "studded" else CHROME
	var wheel_model := _model_parts(WHEEL_MODEL) if ResourceLoader.exists(WHEEL_MODEL) else []
	for i in 4:
		var pivot := Node3D.new()
		pivot.position = kart.wheel_mount(i)
		add_child(pivot)
		var spin := Node3D.new()
		# Grow outward, so the wider tyre doesn't eat into the bodywork.
		spin.position.x = signf(kart.wheel_mount(i).x) * kart.tires["width"] * 0.17
		pivot.add_child(spin)
		if not wheel_model.is_empty():
			# The Blender wheel (tools/blender/wheel.py): radius 0.5, width 0.46.
			var sc := Transform3D(Basis.from_scale(Vector3(width / 0.46, r / 0.5, r / 0.5)), Vector3.ZERO)
			for part in wheel_model:
				var name: String = part[0]
				var c := tire_color
				_finish = Palette.Finish.MATTE
				if name.begins_with("Rim_dark") or name.begins_with("Rim_spoke"):
					c = rim_color.darkened(0.15)
					_finish = Palette.Finish.PAINT
				elif name.begins_with("Rim"):
					c = rim_color
					_finish = Palette.Finish.PAINT
				elif name.begins_with("Hub"):
					c = Color(0.62, 0.6, 0.58)
					_finish = Palette.Finish.PAINT
				elif name.begins_with("Nut"):
					c = DARK
				var mi := _mesh(part[1], c, spin)
				mi.transform = sc * part[2]
			_finish = Palette.Finish.PAINT
			_wheels.append(pivot)
			continue
		_finish = Palette.Finish.MATTE  # rubber
		var cyl := CylinderMesh.new()
		cyl.top_radius = r * 0.97
		cyl.bottom_radius = r * 0.97
		cyl.height = width * 0.78
		cyl.radial_segments = 18
		cyl.rings = 1
		_mesh(cyl, tire_color, spin, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI / 2))
		for sx: float in [-1.0, 1.0]:
			var side := TorusMesh.new()
			side.inner_radius = r * 0.56
			side.outer_radius = r * 0.97
			side.rings = 18
			side.ring_segments = 8
			_mesh(side, tire_color, spin, Vector3(sx * width * 0.36, 0, 0), Vector3.ONE, Vector3(0, 0, PI / 2))
		var n_tread := 14
		var tall := 0.07 if kart.tires_id == "knobby" or kart.tires_id == "studded" else 0.035
		for k in n_tread:
			var a := TAU * k / n_tread
			for sx: float in [-1.0, 1.0]:
				var blk := Vector3(width * 0.34, tall, r * 0.17)
				_mesh(_box(blk), tire_color.lightened(0.06), spin, Vector3(sx * width * 0.19, cos(a) * (r * 0.97 + tall * 0.3), sin(a) * (r * 0.97 + tall * 0.3)), Vector3.ONE, Vector3(a + sx * 0.12, 0, 0))
		_finish = Palette.Finish.PAINT
		var rim := CylinderMesh.new()
		rim.top_radius = r * 0.56
		rim.bottom_radius = r * 0.56
		rim.height = width * 0.92
		rim.radial_segments = 14
		rim.rings = 1
		_mesh(rim, rim_color, spin, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI / 2))
		var hub := CylinderMesh.new()
		hub.top_radius = r * 0.2
		hub.bottom_radius = r * 0.2
		hub.height = width * 0.98
		hub.radial_segments = 8
		hub.rings = 1
		_mesh(hub, CHROME, spin, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI / 2))
		_mesh(_box(Vector3(width * 0.95, r * 0.75, r * 0.14)), rim_color.darkened(0.25), spin)  # spokes, show the spin
		_wheels.append(pivot)

	if not empty:
		_finish = Palette.Finish.MATTE  # fur and cloth
		_build_driver(body_y, size, seat["z"])
		_finish = Palette.Finish.PAINT
	if not has_meta("nomerge"):
		_merge_all()


const OUTLINE_W := 0.025
const AO_FLOOR := 0.42   # how dark the deepest baked occlusion gets
const METAL := Color(0.78, 0.8, 0.84)
const CHROME := Color(0.86, 0.87, 0.9)
const DARK := Color(0.16, 0.16, 0.2)


## A metal tube from a to b.
func _tube(a: Vector3, b: Vector3, r: float, c := METAL, parent: Node3D = self) -> MeshInstance3D:
	var d := b - a
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = d.length()
	cyl.radial_segments = 8
	cyl.rings = 1
	var mi := _mesh(cyl, c, parent, (a + b) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	return mi


## A tube bent through several points (bumpers, nerf bars, roll hoops).
func _bent(points: Array, r: float, c := METAL) -> void:
	for i in points.size() - 1:
		_tube(points[i], points[i + 1], r, c)
		if i > 0:
			_mesh(_sphere(r, 4, 6), c, self, points[i])


## A smooth tapered shell along -Z: `front` and `back` radii, squashed to `w` by `h`.
func _fairing(center: Vector3, length: float, front: float, back: float, w: float, h: float, c: Color) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = front
	cyl.bottom_radius = back
	cyl.height = length
	cyl.radial_segments = 14
	cyl.rings = 2
	var mi := _mesh(cyl, c, self, center)
	mi.basis = Basis(Vector3.RIGHT, -PI / 2) * Basis.from_scale(Vector3(w, 1.0, h))
	return mi


## Builds the frame and bodywork for one chassis style. Returns where the
## driver sits and where the steering wheel goes.
## Chassis with bodywork modelled in Blender (tools/blender/), by chassis id.
const MODELS := {
	"frame": "res://assets/models/kart_frame.glb",
	"soapbox": "res://assets/models/kart_soapbox.glb",
	"hauler": "res://assets/models/kart_hauler.glb",
	"racer": "res://assets/models/kart_racer.glb",
}
## Where each model seats the driver ([height, z]), puts the steering wheel
## and ends its exhausts, in the model's own space (ground at 0, wheel
## centres at 0.3); printed by the Blender scripts when they export.
const MODEL_FIT := {
	"frame": {"seat": [0.25, 0.27], "wheel_at": Vector3(0, 0.62, -0.28), "exhausts": [Vector3(-0.21, 0.69, 1.19), Vector3(0.21, 0.69, 1.19)]},
	"soapbox": {"seat": [0.2, 0.15], "wheel_at": Vector3(0, 0.56, -0.32), "exhausts": []},
	"hauler": {"seat": [0.32, 0.22], "wheel_at": Vector3(0, 0.74, -0.3), "exhausts": [Vector3(-0.5, 1.16, 0.84), Vector3(0.5, 1.16, 0.84)]},
	"racer": {"seat": [0.18, 0.12], "wheel_at": Vector3(0, 0.5, -0.4), "exhausts": [Vector3(-0.1, 0.41, 1.42), Vector3(0.1, 0.41, 1.42)]},
}
const WHEEL_MODEL := "res://assets/models/wheel.glb"
static var _model_meshes := {}   # path -> [[name, Mesh], ...]


func _model_parts(path: String) -> Array:
	if not _model_meshes.has(path):
		var out := []
		var scene: PackedScene = load(path)
		if scene:
			var inst := scene.instantiate()
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				var xf := Transform3D.IDENTITY
				var n: Node = m
				while n != null and n != inst:
					xf = (n as Node3D).transform * xf
					n = n.get_parent()
				out.append([String(m.name), m.mesh, xf])
			inst.free()
		_model_meshes[path] = out
	return _model_meshes[path]


## The Blender bodywork, painted by part name (tools/blender/kart.py). The
## model is built with the wheel centres 0.3 above its ground; ours sit at
## the suspension's rest height. Returns the seat like _build_frame.
## Metal parts are a warm gunmetal and not mirror-like: in the game, chrome
## reflected the sky and washed out to pale blue.
func _build_model_frame(style: String, path: String, color: Color) -> Dictionary:
	var fl := kart.wheel_mount(0)
	var axle_y := fl.y - Kart.SUSPENSION_TRAVEL * 0.6
	var shift := Transform3D(Basis.IDENTITY, Vector3(0, axle_y - 0.3, 0))
	var accent := Color(1.0, 0.84, 0.18) if color.r > color.g or color.b > color.g else Color(0.98, 0.98, 0.98)
	for part in _model_parts(path):
		var name: String = part[0]
		# The steering wheel is built in code, so it can turn with the steering.
		if name.begins_with("Trim_wheel") or name.begins_with("Accent_wheelhub") or name.begins_with("Trim_column"):
			continue
		var c := DARK
		_finish = Palette.Finish.MATTE
		if name.begins_with("Paint"):
			c = color
			_finish = Palette.Finish.PAINT
		elif name.begins_with("Accent"):
			c = accent
			_finish = Palette.Finish.PAINT
		elif name.begins_with("Metal"):
			c = Color(0.5, 0.46, 0.42)
			_finish = Palette.Finish.PAINT
		elif name.begins_with("Plate"):
			c = Color(0.97, 0.97, 0.97)
			_finish = Palette.Finish.PAINT
		elif name.begins_with("Wood"):
			c = Color(0.62, 0.42, 0.25)
		var mi := _mesh(part[1], c, self)
		mi.transform = shift * part[2]
		if name.begins_with("Paint_fender") or name.begins_with("Trim_arch"):
			_fit_wheel_arch(mi)
	_finish = Palette.Finish.PAINT
	var low := axle_y - 0.3
	var fit: Dictionary = MODEL_FIT[style]
	for tip: Vector3 in fit["exhausts"]:
		_exhaust_tips.append(tip + Vector3.UP * low)
	return {"y": low + float(fit["seat"][0]), "z": float(fit["seat"][1]), "wheel_at": (fit["wheel_at"] as Vector3) + Vector3.UP * low}


func _fit_wheel_arch(arch: MeshInstance3D) -> void:
	# Fit the imported arch to this build's swept tyre envelope. Keep the
	# lower attachment height and stretch the crown to clear full compression.
	var box := arch.transform * arch.mesh.get_aabb()
	var center := box.get_center()
	var index := 0
	var closest := INF
	for i in 4:
		var mount := kart.wheel_mount(i)
		var distance := Vector2(center.x - mount.x, center.z - mount.z).length_squared()
		if distance < closest:
			closest = distance
			index = i
	var mount := kart.wheel_mount(index)
	var angle := float(kart.chassis["max_steer"]) if index < 2 else 0.0
	var half_width := float(kart.tires["width"]) * 1.35 * 0.5
	var radius := kart.wheel_radius()
	var lateral := half_width * cos(angle) + radius * sin(angle) + 0.04
	var longitudinal := maxf(radius, radius * cos(angle) + half_width * sin(angle)) + 0.06
	var crown := mount.y + radius + 0.12
	var scale_fit := Vector3(maxf(1.0, lateral * 2.0 / box.size.x), maxf(1.0, (crown - box.position.y) / box.size.y), maxf(1.0, longitudinal * 2.0 / box.size.z))
	var anchor := Vector3(center.x, box.position.y, center.z)
	var target := Vector3(mount.x + signf(mount.x) * float(kart.tires["width"]) * 0.17, anchor.y, mount.z)
	arch.transform = Transform3D(Basis.from_scale(scale_fit), target - anchor * scale_fit) * arch.transform


func _build_frame(style: String, color: Color) -> Dictionary:
	if MODELS.has(style) and ResourceLoader.exists(MODELS[style]):
		return _build_model_frame(style, MODELS[style], color)
	var fl := kart.wheel_mount(0)
	var rr := kart.wheel_mount(3)
	var tx := absf(fl.x)          # half track
	var fz := fl.z                # front axle (negative)
	var rz := rr.z                # rear axle
	var y := fl.y - (Kart.SUSPENSION_TRAVEL * 0.6)  # wheel-centre height at rest
	var low := y - 0.05           # frame rails sit just below the axles
	var rail_x := tx * 0.42
	var tube := 0.035
	var paint := color
	var accent := color.lightened(0.35)

	# Main rails and cross tubes.
	_bent([Vector3(-rail_x, low, rz + 0.1), Vector3(-rail_x, low, fz - 0.05), Vector3(-rail_x * 0.55, low, fz - 0.3)], tube)
	_bent([Vector3(rail_x, low, rz + 0.1), Vector3(rail_x, low, fz - 0.05), Vector3(rail_x * 0.55, low, fz - 0.3)], tube)
	_tube(Vector3(-rail_x * 0.55, low, fz - 0.3), Vector3(rail_x * 0.55, low, fz - 0.3), tube)
	for z in [fz, (fz + rz) * 0.5, rz]:
		_tube(Vector3(-tx + 0.1, low, z), Vector3(tx - 0.1, low, z), tube * 0.9)   # axle carriers
	# Floor tray.
	_mesh(_box(Vector3(rail_x * 2.0, 0.02, (rz - fz) * 0.8)), DARK, self, Vector3(0, low - 0.02, (fz + rz) * 0.5))
	# Rear bumper bar wrapping behind the rear wheels.
	var by := low + 0.06
	_bent([Vector3(-tx - 0.08, by, rz - 0.05), Vector3(-tx - 0.08, by, rz + 0.45), Vector3(tx + 0.08, by, rz + 0.45), Vector3(tx + 0.08, by, rz - 0.05)], tube * 1.2)
	_tube(Vector3(-rail_x, low, rz + 0.1), Vector3(-rail_x, by, rz + 0.45), tube)
	_tube(Vector3(rail_x, low, rz + 0.1), Vector3(rail_x, by, rz + 0.45), tube)
	# Front bumper loop under the nose.
	_bent([Vector3(-tx * 0.7, low + 0.02, fz - 0.15), Vector3(-tx * 0.45, low + 0.02, fz - 0.55), Vector3(tx * 0.45, low + 0.02, fz - 0.55), Vector3(tx * 0.7, low + 0.02, fz - 0.15)], tube)

	# Bodywork, aerodynamic shells in the chassis colour.
	var nose_len := 0.55
	var pod_len := (rz - fz) * 0.62
	match style:
		"soapbox":
			# A rounded egg-shaped shell over a light frame.
			var shell := _mesh(_sphere(0.5, 8, 14), paint, self, Vector3(0, low + 0.16, (fz + rz) * 0.5 - 0.15))
			shell.scale = Vector3(rail_x * 2.4, 0.42, (rz - fz) * 0.95)
			_mesh(_sphere(0.5, 6, 10), accent, self, Vector3(0, low + 0.16, fz - 0.15), Vector3(rail_x * 1.4, 0.32, 0.5))
		"hauler":
			# Chunky: wide boxy pods, double bumpers and a roll hoop.
			_fairing(Vector3(0, low + 0.12, fz - 0.25), nose_len, 0.22, 0.3, 1.5, 0.55, paint)
			for side in [-1.0, 1.0]:
				_fairing(Vector3(side * (tx - 0.02), low + 0.1, (fz + rz) * 0.5), pod_len, 0.16, 0.16, 1.2, 0.8, paint)
			_bent([Vector3(-tx - 0.12, by + 0.12, rz + 0.5), Vector3(tx + 0.12, by + 0.12, rz + 0.5)], tube * 1.4, DARK)
			var hoop_z := rz - 0.2
			_bent([Vector3(-rail_x, low, hoop_z), Vector3(-rail_x * 0.9, low + 0.85, hoop_z + 0.05), Vector3(rail_x * 0.9, low + 0.85, hoop_z + 0.05), Vector3(rail_x, low, hoop_z)], tube * 1.3)
		"racer":
			# Long, low and pointy, with a rear wing.
			_fairing(Vector3(0, low + 0.09, fz - 0.35), nose_len + 0.35, 0.05, 0.26, 1.3, 0.45, paint)
			for side in [-1.0, 1.0]:
				_fairing(Vector3(side * (tx - 0.08), low + 0.06, (fz + rz) * 0.5 + 0.05), pod_len, 0.07, 0.15, 1.0, 0.55, paint)
				_tube(Vector3(side * rail_x * 0.8, low, rz + 0.25), Vector3(side * rail_x * 0.8, low + 0.6, rz + 0.35), tube)
			_mesh(_box(Vector3(tx * 2.0, 0.04, 0.32)), accent, self, Vector3(0, low + 0.62, rz + 0.38))
		_:
			# Classic sprint kart: nose cone, side pods, number plate.
			_fairing(Vector3(0, low + 0.1, fz - 0.3), nose_len, 0.1, 0.28, 1.35, 0.5, paint)
			for side in [-1.0, 1.0]:
				_fairing(Vector3(side * (tx - 0.05), low + 0.08, (fz + rz) * 0.5), pod_len, 0.09, 0.14, 1.1, 0.7, paint)
	# Number plate on the nose.
	var plate := _mesh(_sphere(0.11, 4, 10), Color(0.97, 0.97, 0.97), self, Vector3(0, low + 0.28, fz - 0.05), Vector3(1.0, 1.0, 0.25))
	plate.rotation.x = deg_to_rad(-25)

	# Engine and exhaust at the back (not on the soapbox: it's gravity powered).
	if style != "soapbox":
		_mesh(_box(Vector3(0.24, 0.22, 0.28)), Color(0.45, 0.47, 0.52), self, Vector3(rail_x + 0.05, low + 0.15, rz - 0.05))
		_mesh(_box(Vector3(0.2, 0.06, 0.24)), DARK, self, Vector3(rail_x + 0.05, low + 0.28, rz - 0.05))
		# Twin chrome exhausts poking out the back, with flared tips that
		# spit flame (see _update_exhaust).
		for sx: float in [-1.0, 1.0]:
			var x := sx * 0.2
			var tip := Vector3(x, low + 0.34, rz + 0.52)
			_bent([Vector3(rail_x * 0.0 + x * 0.6, low + 0.15, rz + 0.05), Vector3(x, low + 0.22, rz + 0.3), tip], 0.045, CHROME)
			var bell := CylinderMesh.new()
			bell.top_radius = 0.05
			bell.bottom_radius = 0.075
			bell.height = 0.12
			bell.radial_segments = 10
			bell.rings = 1
			_mesh(bell, CHROME, self, tip + Vector3(0, 0.02, 0.04), Vector3.ONE, Vector3(deg_to_rad(70), 0, 0))
			_exhaust_tips.append(tip + Vector3(0, 0.04, 0.1))

	# Bucket seat and the steering column.
	var seat_z := (fz + rz) * 0.5 + (rz - fz) * 0.12
	var seat_y := low + 0.08
	_mesh(_sphere(0.24, 6, 10), DARK, self, Vector3(0, seat_y + 0.08, seat_z + 0.05), Vector3(1.0, 0.55, 1.0))
	_mesh(_box(Vector3(0.38, 0.42, 0.06)), DARK, self, Vector3(0, seat_y + 0.25, seat_z + 0.2), Vector3.ONE, Vector3(deg_to_rad(-15), 0, 0))
	var wheel_at := Vector3(0, seat_y + 0.45, seat_z - 0.42)
	_tube(Vector3(0, low, fz + 0.05), wheel_at, 0.02, DARK)
	return {"y": seat_y, "z": seat_z, "wheel_at": wheel_at}


## Merge each group of parts that moves together into one mesh with an ink
## outline (design doc 9.1): a kart drops from ~70 draw calls to ~15.
func _merge_all() -> void:
	if _boost_flame:
		_boost_flame.set_meta("keep", true)
		_sparks.set_meta("keep", true)
	var groups: Array[Node3D] = []
	for g in ([self, _driver, _torso, _head] if standing else [self, _torso, _head]):
		if g != null:
			groups.append(g)
	for w in _wheels:
		groups.append(w.get_child(0))
	if _wheel_ring:
		groups.append(_wheel_ring.get_parent())
	groups.append_array(_wobbly)
	for g in groups:
		_merge(g)
	if not standing and get_meta("nomerge", false) == false:
		_build_cast_shadow()


# --- Cast shadow ------------------------------------------------------------
# The whole kart and driver as one silhouette mesh, flattened onto the ground
# along the sun by shaders/kart_shadow.gdshader. One extra draw per kart.

## Which way the sunlight travels for kart shadows: from the same side as
## the sun in main.gd, but lower in the sky, so shadows reach out to the
## side where you can see them (as in Mario Kart), not hide under the kart.
static var sun_dir := Basis.from_euler(Vector3(deg_to_rad(-36), deg_to_rad(-35), 0)) * Vector3.FORWARD

static var cast_shadows := true   # off on Low graphics (main.gd)
var _inks: Array = []
var _cast: MeshInstance3D
var _cast_mat: ShaderMaterial


func _build_cast_shadow() -> void:
	var verts := PackedVector3Array()
	for pair in _inks:
		var mesh: ArrayMesh = pair[0]
		var xf := Transform3D.IDENTITY
		var n: Node = pair[1]
		while n != null and n != self:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			for i in idx:
				verts.append(xf * v[i])
		else:
			for p in v:
				verts.append(xf * p)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cast_mat = ShaderMaterial.new()
	_cast_mat.shader = load("res://shaders/kart_shadow.gdshader")
	_cast_mat.set_shader_parameter("light_dir", sun_dir)
	_cast = MeshInstance3D.new()
	_cast.mesh = m
	_cast.material_override = _cast_mat
	_cast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cast.visibility_range_end = 70.0
	_cast.visible = false
	# Huge bounds: the vertices move to the ground in the shader.
	_cast.extra_cull_margin = 4.0
	add_child(_cast)


func _merge(group: Node3D) -> void:
	var parts: Array[MeshInstance3D] = []
	var xforms: Array[Transform3D] = []
	_collect(group, Transform3D.IDENTITY, parts, xforms, true)
	if parts.size() < 1:
		return
	# One surface per finish, so metal still shines and fur stays matte.
	var by_finish := {}
	for i in parts.size():
		var f := int(parts[i].material_override.resource_name)
		if not by_finish.has(f):
			by_finish[f] = []
		by_finish[f].append(i)
	var mesh := ArrayMesh.new()
	for f in by_finish:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _combine(parts, xforms, by_finish[f]))
		mesh.surface_set_material(mesh.get_surface_count() - 1, Palette.kart(f))
	# The ink outline is its own single mesh that only draws for karts near
	# the camera: far away it's too thin to see, and skipping it halves the
	# draw calls for the rest of the pack (design doc 14).
	var all := []
	for i in parts.size():
		all.append(i)
	var ink := ArrayMesh.new()
	ink.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _combine(parts, xforms, all))
	for mi in parts:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	var merged := MeshInstance3D.new()
	merged.mesh = mesh
	group.add_child(merged)
	# (No black ink outline: Mario Kart's karts have none; light, rim and
	# reflections shape them. The combined shape still makes the cast shadow.)
	_inks.append([ink, group])


func _combine(parts: Array[MeshInstance3D], xforms: Array[Transform3D], which: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in which:
		var mi := parts[i]
		var xf := xforms[i]
		var c: Color = (mi.material_override as StandardMaterial3D).albedo_color
		var arr := mi.mesh.surface_get_arrays(0)
		var base := verts.size()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		# Blender models carry baked ambient occlusion in their vertex
		# colours (tools/blender/common.py bake_ao): darker in creases and
		# underneath. Softened, so shade never goes to black.
		var ao: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var nb := xf.basis.inverse().transposed()
		for k in v.size():
			verts.append(xf * v[k])
			normals.append((nb * n[k]).normalized())
			if ao.size() == v.size() and mi.has_meta("vcol"):
				colors.append(ao[k].linear_to_srgb())   # painted (and shaded) in Blender
			elif ao.size() == v.size():
				var o := lerpf(AO_FLOOR, 1.0, smoothstep(0.0, 0.75, ao[k].r))   # only real creases darken
				colors.append(Color(c.r * o, c.g * o, c.b * o, c.a))
			else:
				colors.append(c)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			for k in v.size():
				indices.append(base + k)
		else:
			for k in idx:
				indices.append(base + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Mesh parts under `node`, with transforms relative to the group. Stops at
## plain Node3D children (they move on their own, so they're merged separately).
func _collect(node: Node3D, xf: Transform3D, parts: Array[MeshInstance3D], xforms: Array[Transform3D], is_root: bool) -> void:
	for c in node.get_children():
		if not c is Node3D or c.has_meta("keep"):
			continue
		var child := c as Node3D
		var cx := xf * child.transform
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is StandardMaterial3D:
			# Stretched parts merge too: _combine transforms normals by the
			# inverse transpose, so they shade as they did on their own.
			# (They used to stay separate, which left every Blender wheel as
			# ~10 draw calls: half of all draws in a race. Design doc 14.2.)
			parts.append(child)
			xforms.append(cx)
			_collect(child, cx, parts, xforms, false)
		elif not is_root and not child is MeshInstance3D:
			continue


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## The shared base body: a soft bean with a big head, stubby arms and legs.
## The driver on its own: the same body and features, on two stubby legs,
## with its arms down instead of reaching for a wheel.
func _build_standing() -> void:
	_finish = Palette.Finish.MATTE
	_build_driver(0.42, Vector3.ONE, 0.0, false)
	var d := kart.driver
	var body_c: Color = d["body"]
	for side in ([] if DRIVER_MODELS.has(kart.driver_id) else [-1.0, 1.0]):
		_mesh(_capsule(0.1, 0.5), body_c, _driver, Vector3(0.13 * side, -0.18, 0))
		_mesh(_sphere(0.11), body_c.darkened(0.15), _driver, Vector3(0.13 * side, -0.42, -0.06), Vector3(1.0, 0.6, 1.4))
	_merge_all()


## Drivers sculpted in Blender (tools/blender/drivers.py): one smooth
## surface for the body and one for the head, painted in their vertex
## colours, plus small separate pieces (eyes, lids, brows, goggles) and the
## parts that wobble (the fox's tail, the deer's antlers).
const DRIVER_MODELS := {
	"fox": "res://assets/models/driver_fox.glb",
	"frog": "res://assets/models/driver_frog.glb",
	"rhino": "res://assets/models/driver_rhino.glb",
	"deer": "res://assets/models/driver_deer.glb",
}
const HEAD_PIVOT := Vector3(0, 0.72, 0)


func _build_driver_model(path: String, seated: bool) -> void:
	_torso = Node3D.new()
	_driver.add_child(_torso)
	_head = Node3D.new()
	_head.position = HEAD_PIVOT
	_torso.add_child(_head)
	var to_head := Transform3D(Basis.IDENTITY, -HEAD_PIVOT)
	var keep := _finish
	for part in _model_parts(path):
		var name: String = part[0]
		var mesh: Mesh = part[1]
		var xf: Transform3D = part[2]
		_finish = Palette.Finish.MATTE
		if name.begins_with("Body_"):
			if name.begins_with("Body_seated") != seated:
				continue
			var mi := _mesh(mesh, Color.WHITE, _torso)
			mi.transform = xf
			mi.set_meta("vcol", true)
		elif name.begins_with("Head"):
			var mi := _mesh(mesh, Color.WHITE, _head)
			mi.transform = to_head * xf
			mi.set_meta("vcol", true)
		elif name.begins_with("Tail") or name.begins_with("Antler"):
			var parent := _torso if name.begins_with("Tail") else _head
			var pivot := Node3D.new()
			pivot.position = xf.origin if parent == _torso else (to_head * xf).origin
			pivot.set_meta("base_rot", Vector3.ZERO)
			parent.add_child(pivot)
			var mi := _mesh(mesh, Color.WHITE, pivot)
			mi.basis = xf.basis
			mi.set_meta("vcol", true)
			_wobbly.append(pivot)
			_wobble_vel.append(Vector2.ZERO)
			_wobble_pos.append(Vector2.ZERO)
		else:
			# Small pieces keep the colour they were given in Blender.
			var mat := mesh.surface_get_material(0) as StandardMaterial3D
			var col := mat.albedo_color if mat else Color(0.1, 0.1, 0.1)
			if name.begins_with("Eye") or name.begins_with("Nose") or name.begins_with("Lens"):
				_finish = Palette.Finish.PAINT
			elif name.begins_with("Rim"):
				_finish = Palette.Finish.METAL
			var mi := _mesh(mesh, col, _head)
			mi.transform = to_head * xf
	_finish = keep


func _build_driver(seat_y: float, size: Vector3, seat_z: float, seated := true) -> void:
	var d := kart.driver
	var body_c: Color = d["body"]
	var belly_c: Color = d["belly"]
	var s: float = Parts.WEIGHT_SCALE[d["weight"]]
	_driver = Node3D.new()
	_driver.position = Vector3(0, seat_y, seat_z)
	_driver.scale = Vector3.ONE * s
	add_child(_driver)
	if DRIVER_MODELS.has(kart.driver_id) and ResourceLoader.exists(DRIVER_MODELS[kart.driver_id]):
		_build_driver_model(DRIVER_MODELS[kart.driver_id], seated)
		return

	# Cute, not realistic (design doc 5.4): a big round head on a small
	# body, big glossy eyes with a sparkle, pink cheeks, a little snout and
	# smile. Same base for every animal; features make the animal.
	_torso = Node3D.new()
	_driver.add_child(_torso)
	_mesh(_capsule(0.26, 0.64), body_c, _torso, Vector3(0, 0.26, 0))
	_mesh(_sphere(0.19), belly_c, _torso, Vector3(0, 0.22, -0.16), Vector3(1.0, 1.15, 0.38))  # tummy
	for side: float in [-1.0, 1.0]:
		var arm: MeshInstance3D
		if seated:
			# Arms reach forward to the wheel.
			arm = _mesh(_capsule(0.075, 0.36), body_c, _torso, Vector3(0.21 * side, 0.34, -0.19), Vector3.ONE, Vector3(deg_to_rad(-70), 0, side * 0.35))
		else:
			var wave: bool = side > 0.0
			arm = _mesh(_capsule(0.075, 0.36), body_c, _torso, Vector3(0.28 * side, 0.4 if wave else 0.2, -0.02), Vector3.ONE, Vector3(0, 0, side * (2.4 if wave else 0.35)))
		_mesh(_sphere(0.075), belly_c, arm, Vector3(0, -0.2, 0))  # paw
	_head = Node3D.new()
	_head.position = Vector3(0, 0.72, 0)
	_torso.add_child(_head)
	_mesh(_sphere(0.34, 12, 18), body_c, _head, Vector3.ZERO, Vector3(1.08, 0.95, 1.0))
	var feats: Array = d["features"]
	var frog := feats.has("top_eyes")
	# Snout and nose (the frog has a wide smiling face instead).
	if not frog:
		var snout_c := belly_c if not feats.has("horn") else body_c.lightened(0.18)
		_mesh(_sphere(0.13), snout_c, _head, Vector3(0, -0.11, -0.27), Vector3(1.25, 0.78, 0.95))
		_finish = Palette.Finish.PAINT
		_mesh(_sphere(0.045, 4, 8), Color(0.12, 0.08, 0.1), _head, Vector3(0, -0.06, -0.385), Vector3(1.3, 0.85, 0.9))
		_finish = Palette.Finish.MATTE
	# A small "w" smile; the frog gets a wide one.
	if frog:
		_mesh(_capsule(0.014, 0.3), Color(0.18, 0.1, 0.12), _head, Vector3(0, -0.14, -0.33), Vector3.ONE, Vector3(0, 0, PI / 2))
	else:
		for side: float in [-1.0, 1.0]:
			_mesh(_capsule(0.011, 0.07), Color(0.18, 0.1, 0.12), _head, Vector3(0.025 * side, -0.17, -0.355), Vector3.ONE, Vector3(0, 0, side * 1.0))
	# Pink cheeks.
	for side: float in [-1.0, 1.0]:
		_mesh(_sphere(0.06, 4, 8), Color(1.0, 0.55, 0.62), _head, Vector3(0.2 * side, -0.08, -0.26), Vector3(1.3, 0.7, 0.4))
	# Big glossy eyes, each with a white sparkle.
	if not frog:
		for side: float in [-1.0, 1.0]:
			_eye(_head, Vector3(0.135 * side, 0.03, -0.29), side)

	for f in feats:
		match f:
			"pointed_ears":
				for side: float in [-1.0, 1.0]:
					var ear := _wobbly_part(_cone(0.12, 0.3), body_c, _head, Vector3(0.18 * side, 0.27, 0.02), Vector3(0, 0, -side * 0.3))
					_mesh(_cone(0.07, 0.2), belly_c, ear, Vector3(0, 0.1, -0.05))  # inner ear
			"round_ears":
				for side: float in [-1.0, 1.0]:
					var ear := _wobbly_part(_sphere(0.1), body_c.darkened(0.08), _head, Vector3(0.27 * side, 0.2, 0.02), Vector3.ZERO)
					_mesh(_sphere(0.06), Color(1.0, 0.75, 0.75), ear, Vector3(0, 0.12, -0.05), Vector3(1.0, 1.0, 0.4))
			"bushy_tail":
				var tail := _wobbly_part(_capsule(0.13, 0.6), body_c, _torso, Vector3(0, 0.12, 0.3), Vector3(deg_to_rad(60), 0, 0))
				_mesh(_sphere(0.11), Color(1, 0.97, 0.92), tail, Vector3(0, 0.27, 0))
			"top_eyes":
				# Frog: big round eyes sitting on top of the head.
				for side: float in [-1.0, 1.0]:
					_mesh(_sphere(0.15), body_c, _head, Vector3(0.16 * side, 0.2, -0.1))
					_eye(_head, Vector3(0.16 * side, 0.2, -0.25), side, 1.25)
			"horn":
				_mesh(_cone(0.085, 0.26), Color(0.95, 0.93, 0.86), _head, Vector3(0, 0.0, -0.4), Vector3.ONE, Vector3(deg_to_rad(-62), 0, 0))
			"antlers":
				for side: float in [-1.0, 1.0]:
					var a := _wobbly_part(_capsule(0.03, 0.38), Color(0.6, 0.42, 0.25), _head, Vector3(0.13 * side, 0.3, 0.04), Vector3(0, 0, -side * 0.4))
					_mesh(_capsule(0.025, 0.2), Color(0.6, 0.42, 0.25), a, Vector3(0.05 * side, 0.1, 0), Vector3.ONE, Vector3(0, 0, -side * 0.9))


## A big cartoon eye: a glossy dark oval with a white sparkle up and out.
func _eye(parent: Node3D, pos: Vector3, side: float, k := 1.0) -> void:
	var keep := _finish
	_finish = Palette.Finish.MATTE  # the white sparkles do the shine
	_mesh(_sphere(0.075 * k, 6, 10), Color(0.07, 0.05, 0.09), parent, pos, Vector3(0.85, 1.15, 0.6))
	_finish = Palette.Finish.MATTE
	_mesh(_sphere(0.026 * k, 4, 6), Color(1, 1, 1), parent, pos + Vector3(0.025 * side, 0.04, -0.04) * k)
	_mesh(_sphere(0.012 * k, 3, 5), Color(1, 1, 1), parent, pos + Vector3(-0.02 * side, -0.035, -0.04) * k)
	_finish = keep


func _wobbly_part(mesh: Mesh, c: Color, parent: Node3D, pos: Vector3, rot: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation = rot
	pivot.set_meta("base_rot", rot)
	parent.add_child(pivot)
	var mi := _mesh(mesh, c, pivot)
	mi.position = Vector3(0, 0.12, 0)
	_wobbly.append(pivot)
	_wobble_vel.append(Vector2.ZERO)
	_wobble_pos.append(Vector2.ZERO)
	return pivot


## The held item rides on the back of the kart (design doc 6.1), so the
## karts behind can see what's coming.
var _rack: Node3D
var _rack_item := ""


func _update_rack() -> void:
	var want := kart.held_item if kart.item_spin <= 0.0 else ""
	if want == _rack_item:
		return
	_rack_item = want
	if _rack:
		_rack.queue_free()
		_rack = null
	if want == "":
		return
	_rack = Node3D.new()
	var size: Vector3 = kart.chassis["size"]
	_rack.position = Vector3(0, 0.62, size.z * 0.42)
	add_child(_rack)
	match want:
		"honey":
			var pot := CylinderMesh.new()
			pot.top_radius = 0.15
			pot.bottom_radius = 0.19
			pot.height = 0.28
			_mesh(pot, Color(1.0, 0.7, 0.15), _rack)
			_mesh(_box(Vector3(0.34, 0.06, 0.34)), Color(0.6, 0.35, 0.18), _rack, Vector3(0, 0.16, 0))
		"tumbleweed":
			for i in 3:
				var tor := TorusMesh.new()
				tor.inner_radius = 0.18
				tor.outer_radius = 0.22
				tor.rings = 10
				tor.ring_segments = 4
				_mesh(tor, Color(0.82, 0.63, 0.36), _rack, Vector3.ZERO, Vector3.ONE, Vector3(i * 1.0, i * 0.6, 0))


func _process(delta: float) -> void:
	if kart == null or _wheels.is_empty():
		return
	_update_rack()
	_update_shadow()
	for i in 4:
		var pivot := _wheels[i]
		var mount := kart.wheel_mount(i)
		var travel := Kart.SUSPENSION_TRAVEL
		var y := mount.y - (travel - kart.wheel_compression[i])
		pivot.position = Vector3(mount.x, lerpf(pivot.position.y, y, 0.5), mount.z)
		pivot.rotation.y = -kart.steer_angle if i < 2 else 0.0
		pivot.get_child(0).rotation.x = -kart.wheel_spin
	if _wheel_ring:
		_wheel_ring.rotation.y = -kart.steer_angle * 2.2

	# Driver: lean against the turn, bob with the suspension, spring back.
	if _torso == null:
		return
	_lean = lerpf(_lean, clampf(-kart.lateral_g * 0.22, -0.4, 0.4), clampf(delta * 6.0, 0.0, 1.0))
	_bob_vel += (-_bob * 140.0 - _bob_vel * 9.0) * delta
	_bob_vel -= clampf(kart.vertical_kick, -3.0, 3.0) * 0.9
	_bob += _bob_vel * delta
	_bob = clampf(_bob, -0.12, 0.12)
	_torso.rotation.z = _lean
	_torso.position.y = _bob
	_torso.scale = Vector3(1.0 - _bob * 0.6, 1.0 + _bob * 1.2, 1.0 - _bob * 0.6)  # squash and stretch
	_head.rotation.y = lerpf(_head.rotation.y, kart.steer_angle * 0.9, clampf(delta * 5.0, 0.0, 1.0))
	_head.rotation.z = _lean * 0.5

	# Ears, tails and antlers trail behind the motion like springs.
	var accel := Vector2(kart.lateral_g, -kart.speed * 0.02 + _bob_vel * 0.3)
	for i in _wobbly.size():
		var v := _wobble_vel[i]
		var p := _wobble_pos[i]
		v += (-p * 90.0 - v * 7.0 + accel * 2.5) * delta
		p += v * delta
		p = p.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
		_wobble_vel[i] = v
		_wobble_pos[i] = p
		var base: Vector3 = _wobbly[i].get_meta("base_rot")
		_wobbly[i].rotation = base + Vector3(p.y, 0, p.x)

	_boost_flame.visible = kart.boost_time > 0.0 and _exhaust_flames.is_empty()
	if _boost_flame.visible:
		_boost_flame.scale = Vector3.ONE * (0.8 + randf() * 0.5)
	_update_exhaust()
	var stage := kart.drift_stage()
	_sparks.visible = kart.drifting
	if _sparks.visible:
		var colors := [Color(0.85, 0.85, 0.9), Color(0.4, 0.75, 1.0), Color(1.0, 0.6, 0.2), Color(0.85, 0.4, 1.0)]
		(_sparks.material_override as StandardMaterial3D).albedo_color = colors[stage]
		(_sparks.material_override as StandardMaterial3D).emission = colors[stage]
		_sparks.position.x = -kart.drift_dir * float(kart.chassis["track"]) * 0.5
		_sparks.scale = Vector3.ONE * (0.6 + randf() * 0.8)
