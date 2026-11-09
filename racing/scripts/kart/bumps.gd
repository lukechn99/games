class_name KartBumps
extends Node
## Kart-to-kart bumps (design doc 7.2). Karts don't collide with each other
## as rigid boxes: that let a rear-end hit kick a kart into a 180° spin.
## Instead, each kart has an oriented footprint including its wheels; overlapping
## karts are pushed apart and trade some speed, weighted by mass. Bumps
## shove; they never spin anyone round. This also matches how online play
## will work: each phone pushes only its own kart.

const RESTITUTION := 0.35
const MAX_PUSH := 9.0       # m/s, so a lag spike can't launch anyone
const YAW_NUDGE := 0.35     # rad/s of wiggle on a solid hit, for feel

var karts: Array[Kart] = []


func _init() -> void:
	process_physics_priority = 1  # after the karts have moved


func _physics_process(_delta: float) -> void:
	for i in karts.size():
		for j in range(i + 1, karts.size()):
			_pair(karts[i], karts[j])


func half_extents(k: Kart) -> Vector2:
	var size: Vector3 = k.chassis["size"]
	var half := Vector2(size.x, size.z) * 0.5
	var tire_half := float(k.tires["width"]) * 1.35 * 0.5
	var outset := float(k.tires["width"]) * 0.17
	for i in 4:
		var angle := k.steer_angle if i < 2 else 0.0
		var c := absf(cos(angle))
		var s := absf(sin(angle))
		var center := k.wheel_mount(i)
		# The wheel's outer spacer rotates with the steering pivot too.
		center += Basis(Vector3.UP, -angle) * Vector3(signf(center.x) * outset, 0, 0)
		half.x = maxf(half.x, absf(center.x) + tire_half * c + k.wheel_radius() * s)
		half.y = maxf(half.y, absf(center.z) + tire_half * s + k.wheel_radius() * c)
	return half


func _axes(k: Kart) -> Array[Vector2]:
	var back := Vector2(k.global_basis.z.x, k.global_basis.z.z).normalized()
	return [Vector2(back.y, -back.x), back]


func _pair(a: Kart, b: Kart) -> void:
	if absf(a.global_position.y - b.global_position.y) > 1.2:
		return
	var ha := half_extents(a)
	var hb := half_extents(b)
	var delta := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
	if delta.length_squared() > pow(ha.length() + hb.length(), 2):
		return
	var aa := _axes(a)
	var ab := _axes(b)
	var deepest := INF
	var normal := Vector3.ZERO
	# Separating axes keep the rectangular wheel envelope aligned with each
	# kart, even when they meet at an angle. Choose the least separation.
	for axis: Vector2 in [aa[0], aa[1], ab[0], ab[1]]:
		var ra := ha.x * absf(axis.dot(aa[0])) + ha.y * absf(axis.dot(aa[1]))
		var rb := hb.x * absf(axis.dot(ab[0])) + hb.y * absf(axis.dot(ab[1]))
		var projection := delta.dot(axis)
		var penetration := ra + rb - absf(projection)
		if penetration <= 0.0:
			return
		if penetration < deepest:
			deepest = penetration
			var direction := 1.0 if projection >= 0.0 else -1.0
			normal = Vector3(axis.x, 0, axis.y) * direction
	if deepest <= 0.0:
		return
	if a.remote and b.remote:
		return  # their own games handle bumps between them
	# Each game only pushes its own karts: another player's kart acts like
	# something very heavy here, and their game pushes them back.
	var inv_a := 0.0 if a.remote else 1.0 / a.mass
	var inv_b := 0.0 if b.remote else 1.0 / b.mass
	var share_a := inv_a / (inv_a + inv_b)
	# Separate them, the lighter kart moving further.
	var fix := normal * deepest
	a.global_position -= fix * share_a
	b.global_position += fix * (1.0 - share_a)
	# Trade speed along the line between them.
	var vn := (b.linear_velocity - a.linear_velocity).dot(normal)
	if vn >= 0.0:
		return
	var j := clampf(-(1.0 + RESTITUTION) * vn / (inv_a + inv_b), 0.0, MAX_PUSH / maxf(inv_a, inv_b))
	a.linear_velocity -= normal * j * inv_a
	b.linear_velocity += normal * j * inv_b
	var strength := clampf(-vn / 12.0, 0.0, 1.0)
	if strength > 0.15:
		var side := signf(a.global_transform.basis.x.dot(normal))
		a.angular_velocity.y += side * YAW_NUDGE * strength
		b.angular_velocity.y -= side * YAW_NUDGE * strength
		a.crashed.emit(strength * 0.7)
		b.crashed.emit(strength * 0.7)
