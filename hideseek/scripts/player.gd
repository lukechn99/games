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
var controlled := false
var frozen := false               # seekers during the hide phase
var input := PlayerInput.new()
var yaw := 0.0
var pitch := -0.15
var prop_basis := Basis()
var camera: Camera3D

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
	if controlled:
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
		var box := BoxShape3D.new()
		box.size = Props.size(kind)
		_shape.shape = box
		_visual.mesh = Props.mesh(kind)
		_visual.visible = true
	else:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.75
		_shape.shape = cap
		_visual.mesh = null
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
	_aim()


func _aim() -> void:
	if _pivot:
		_pivot.rotation = Vector3(pitch, yaw, 0)


func _apply_basis() -> void:
	_visual.basis = prop_basis
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
