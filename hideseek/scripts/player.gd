class_name Player
extends CharacterBody3D
## A seeker (first person, a capsule) or a hider (third person, shaped
## exactly like its prop). The same node is used for the person playing
## (`controlled`) and for sandbox hiders sitting in their spots.

const GRAVITY := 20.0
const SEEKER_SPEED := 5.0
const HIDER_SPEED := 5.2
const EYE := 1.6

var id := ""
var role := "seeker"
var kind := ""
var locked := false
var controlled := false          # moved by physics here (you, or a bot on the host)
var has_camera := false          # the person playing on this device
var remote := false              # someone else: follows their relayed position
var shirt := Color(0.75, 0.2, 0.18)
var frozen := false               # seekers during the hide phase
var input := PlayerInput.new()
var yaw := 0.0
var pitch := -0.15
var prop_basis := Basis()
var camera: Camera3D

var _farmhand: Farmhand
var _shape: CollisionShape3D
var _visual: MeshInstance3D
var _pivot: Node3D
var _arm: SpringArm3D


func _init() -> void:
	collision_layer = TestBarn.LAYER_PLAYERS
	collision_mask = TestBarn.LAYER_WORLD | TestBarn.LAYER_PLAYERS | TestBarn.LAYER_PROPS
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.2
	_shape = CollisionShape3D.new()
	add_child(_shape)
	_visual = MeshInstance3D.new()
	add_child(_visual)


func _ready() -> void:
	set_physics_process(controlled)
	set_process(remote)
	if has_camera:
		_pivot = Node3D.new()
		add_child(_pivot)
		_arm = SpringArm3D.new()
		_arm.collision_mask = TestBarn.LAYER_WORLD
		_arm.margin = 0.2
		_pivot.add_child(_arm)
		camera = Camera3D.new()
		camera.fov = 75
		camera.near = 0.05
		_arm.add_child(camera)
		camera.current = true
	set_role(role, kind)


## Become a seeker, or a hider shaped like `prop`.
func set_role(r: String, prop := "") -> void:
	role = r
	kind = prop
	locked = false
	prop_basis = Basis(Vector3.UP, yaw)
	if role == "hider":
		_shape.shape = Props.shape(kind)
		_visual.mesh = Props.mesh(kind)
		_visual.visible = true
	else:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.75
		_shape.shape = cap
		# Others see a farmhand; your own first-person view shows nothing.
		_visual.mesh = null
		if not has_camera and _farmhand == null:
			_farmhand = Farmhand.new()
			_farmhand.colour = shirt
			add_child(_farmhand)
	if _farmhand:
		_farmhand.visible = role == "seeker"
	_apply_basis()
	if _pivot:
		if role == "hider":
			_pivot.position = Vector3(0, Props.size(kind).y + 0.5, 0)
			_arm.spring_length = 3.2 + Props.size(kind).length() * 0.6
		else:
			_pivot.position = Vector3(0, EYE, 0)
			_arm.spring_length = 0.0
		_aim()


## Put a hider exactly where a scenery prop would be.
func place(xf: Transform3D) -> void:
	position = xf.origin
	prop_basis = xf.basis
	locked = true
	_apply_basis()


func speed() -> float:
	if role == "hider":
		return HIDER_SPEED * Props.speed_factor(kind)
	return SEEKER_SPEED


## Lock or unlock rotation. A leaning prop (a rake) tips against the
## nearest wall when locked, like the scenery copies.
func toggle_lock() -> void:
	if role != "hider":
		return
	locked = not locked
	if not locked:
		prop_basis = Basis(Vector3.UP, yaw)
	elif Props.leans(kind):
		var wall := _nearest_wall()
		if not wall.is_empty():
			var xf := TestBarn.lean_transform(kind, Vector3(wall["point"].x, global_position.y, wall["point"].z), wall["normal"])
			global_position = Vector3(xf.origin.x, global_position.y, xf.origin.z)
			prop_basis = xf.basis
	_apply_basis()


func aim_transform() -> Transform3D:
	return camera.global_transform if camera else global_transform


func _physics_process(delta: float) -> void:
	yaw -= input.look.x
	pitch = clampf(pitch - input.look.y, -1.35, 1.25)
	input.look = Vector2.ZERO
	var jump := input.take("jump")
	var dir := Vector3.ZERO
	if not frozen:
		dir = Basis(Vector3.UP, yaw) * Vector3(input.move.x, 0, -input.move.y)
		if dir.length() > 1.0:
			dir = dir.normalized()
	var target := dir * speed()
	var blend := 1.0 - exp(-(14.0 if is_on_floor() else 4.0) * delta)
	velocity.x = lerpf(velocity.x, target.x, blend)
	velocity.z = lerpf(velocity.z, target.z, blend)
	if is_on_floor():
		if jump and not frozen:
			velocity.y = HideRules.jump_speed(GRAVITY)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if role == "hider" and not locked:
		prop_basis = Basis(Vector3.UP, yaw)
		_apply_basis()
	elif role == "seeker":
		_apply_basis()
	if _farmhand and _farmhand.visible:
		_farmhand.animate(delta, global_position, 1 if is_on_floor() else 0)
	_aim()


## Eye height for aiming (bots) and where paint comes from.
func eye() -> Vector3:
	if camera:
		return camera.global_position
	return global_position + Vector3(0, EYE, 0)


# ------------------------------------------------------------ remote --

var _goal_pos := Vector3.ZERO
var _goal_yaw := 0.0
var _goal_basis := Basis()
var _heard := false


## Where another player says they are (relayed about 12 times a second).
func hear(pos: Vector3, look_yaw: float, basis_q: Quaternion, is_locked: bool) -> void:
	_goal_pos = pos
	_goal_yaw = look_yaw
	_goal_basis = Basis(basis_q)
	locked = is_locked
	if not _heard:
		_heard = true
		position = pos
		yaw = look_yaw
		prop_basis = _goal_basis
		_apply_basis()


func _process(delta: float) -> void:
	if not _heard:
		return
	var k := 1.0 - exp(-14.0 * delta)
	if position.distance_to(_goal_pos) > 4.0:
		position = _goal_pos
	else:
		position = position.lerp(_goal_pos, k)
	yaw = lerp_angle(yaw, _goal_yaw, k)
	prop_basis = prop_basis.slerp(_goal_basis, k).orthonormalized()
	_apply_basis()
	if _farmhand and _farmhand.visible:
		_farmhand.animate(delta, global_position)


func _aim() -> void:
	if _pivot:
		_pivot.rotation = Vector3(pitch, yaw, 0)


func _apply_basis() -> void:
	_visual.basis = prop_basis if role == "hider" else Basis(Vector3.UP, yaw)
	if _farmhand:
		_farmhand.basis = Basis(Vector3.UP, yaw)
	if role == "hider":
		_shape.transform = Transform3D(prop_basis, prop_basis * Vector3(0, Props.size(kind).y / 2, 0))
	else:
		_shape.transform = Transform3D(Basis(), Vector3(0, 0.875, 0))


func _nearest_wall() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.6, 0)
	var best := {}
	var best_d := 1.0
	for i in 8:
		var d := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 8)
		var q := PhysicsRayQueryParameters3D.create(from, from + d * best_d, TestBarn.LAYER_WORLD)
		var hit := space.intersect_ray(q)
		if hit and absf(hit["normal"].y) < 0.3:
			var dist := from.distance_to(hit["position"])
			if dist < best_d:
				best_d = dist
				best = {"point": hit["position"], "normal": Vector3(hit["normal"].x, 0, hit["normal"].z).normalized()}
	return best
