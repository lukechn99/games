class_name KartBumps
extends Node
## Kart-to-kart bumps (design doc 7.2). Karts don't collide with each other
## as rigid boxes: that let a rear-end hit kick a kart into a 180° spin.
## Instead, each kart is two circles (front and back), and overlapping
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


func _circles(k: Kart) -> Array[Vector3]:
	var size: Vector3 = k.chassis["size"]
	var back := k.global_transform.basis.z
	back.y = 0.0
	back = back.normalized() * size.z * 0.27
	var c := k.global_position + k.global_transform.basis.y * 0.3
	return [c - back, c + back]


func _pair(a: Kart, b: Kart) -> void:
	var ra := float(a.chassis["size"].x) * 0.5
	var rb := float(b.chassis["size"].x) * 0.5
	if a.global_position.distance_squared_to(b.global_position) > 16.0:
		return
	var deepest := 0.0
	var normal := Vector3.ZERO
	for pa in _circles(a):
		for pb in _circles(b):
			var d := pb - pa
			if absf(d.y) > 1.2:
				continue
			d.y = 0.0
			var pen := ra + rb - d.length()
			if pen > deepest:
				deepest = pen
				normal = d.normalized() if d.length() > 0.001 else Vector3.RIGHT
	if deepest <= 0.0:
		return
	var inv_a := 1.0 / a.mass
	var inv_b := 1.0 / b.mass
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
