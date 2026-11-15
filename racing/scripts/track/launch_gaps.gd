class_name LaunchGaps
extends Node
## Launch gaps (design doc 8.4): the road ends at a lip, there is an empty
## drop, and it picks up again further on. The lip is a launch pad: whatever
## speed a kart arrives at, it flies the one planned arc that ends on the
## landing, held on line and level in the air, so it lands every time. On
## the way its model somersaults (the body underneath stays upright).
##
## A track lists its gaps in Track.gaps as [from, to] in metres round the
## lap; the road builder leaves those stretches out. The arc leaves along
## the road's own slope at the lip, so shape the road for the jump you want.

const MIN_SPEED := 22.0     # a slow kart is thrown at least this fast (m/s)
const RIDE := 0.55          # kart centre above the road
const HOLD := 7.0           # how firmly a kart is held to the arc

var track: Track
var karts: Array[Kart] = []
var _arcs: Array[Dictionary] = []    # {from, to, a, b, lift}
var _last := {}                      # kart -> lap offset last tick
var _flights := {}                   # kart -> {arc, t, T, side}


func setup(t: Track, all: Array[Kart]) -> void:
	track = t
	karts = all
	for g: Array in t.gaps:
		var a := t.road_frame(g[0])
		var b := t.road_frame(g[1])
		var p0 := a.origin + Vector3.UP * RIDE
		var p1 := b.origin + Vector3.UP * RIDE
		var flat := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
		var fwd := -a.basis.z
		var slope := fwd.y / maxf(0.05, Vector2(fwd.x, fwd.z).length())
		# Height over the straight line between lip and landing, set so the
		# arc leaves along the road's slope at the lip.
		var lift := maxf(1.5, (slope * flat.length() - (p1.y - p0.y)) / 4.0)
		_arcs.append({"from": float(g[0]), "to": float(g[1]), "p0": p0, "p1": p1, "span": flat.length(), "lift": lift, "a": a, "b": b})


## Where the arc is, `u` of the way across (0 lip, 1 landing).
static func arc_point(arc: Dictionary, u: float) -> Vector3:
	var p: Vector3 = (arc["p0"] as Vector3).lerp(arc["p1"], u)
	p.y += 4.0 * float(arc["lift"]) * u * (1.0 - u)
	return p


## The slope the arc lands at (rise over run; negative is downhill), for
## shaping the landing road to meet it.
static func landing_slope(arc: Dictionary) -> float:
	var rise: float = (arc["p1"] as Vector3).y - (arc["p0"] as Vector3).y
	return (rise - 4.0 * float(arc["lift"])) / float(arc["span"])


func flying(k: Kart) -> bool:
	return _flights.has(k)


func _physics_process(delta: float) -> void:
	if track == null:
		return
	for k in karts:
		if not is_instance_valid(k):
			continue
		if _flights.has(k):
			_fly(k, delta)
			continue
		var off := track.offset_of(k.global_position)
		var before: float = _last.get(k, off)
		_last[k] = off
		for arc in _arcs:
			var lip: float = arc["from"]
			# Just crossed the lip, on the road, going forwards.
			if before < lip and off >= lip and off - before < 12.0:
				var local := track.road_local(k.global_position)
				if absf(local.x) < Track.ROAD_WIDTH * 0.5 + 1.5 and absf(local.y) < 3.0:
					var speed := maxf(MIN_SPEED, Vector2(k.linear_velocity.x, k.linear_velocity.z).length())
					_flights[k] = {"arc": arc, "t": 0.0, "T": float(arc["span"]) / speed, "side": clampf(local.x, -5.0, 5.0)}


func _fly(k: Kart, delta: float) -> void:
	var f: Dictionary = _flights[k]
	var arc: Dictionary = f["arc"]
	f["t"] += delta
	var T: float = f["T"]
	var u := clampf(float(f["t"]) / T, 0.0, 1.0)
	var a: Transform3D = arc["a"]
	var b: Transform3D = arc["b"]
	var vis := k.get_meta("visual", null) as Node3D
	if vis:
		# One forward somersault about the kart's middle, eased in and out.
		var turn := -TAU * smoothstep(0.08, 0.92, u)
		var pivot := Vector3(0.0, 0.45, 0.0)
		var spin := Basis(Vector3.RIGHT, turn)
		vis.transform = Transform3D(spin, pivot - spin * pivot)
	if not k.remote:
		# Held to the arc: the planned velocity plus a pull back onto the line.
		var right := a.basis.x.lerp(b.basis.x, u).normalized()
		var want := arc_point(arc, u) + right * float(f["side"]) * (1.0 - 0.5 * u)
		var ahead := arc_point(arc, minf(u + 0.02, 1.0)) - arc_point(arc, maxf(u - 0.02, 0.0))
		var planned := ahead / (0.04 * T) if u < 0.98 else -b.basis.z * (float(arc["span"]) / T)
		k.linear_velocity = planned + (want - k.global_position) * HOLD
		# Kept level, nose along the flight.
		var nose := planned.normalized()
		var target := Basis.looking_at(nose, Vector3.UP)
		var err := (target * k.global_transform.basis.inverse()).get_rotation_quaternion()
		var axis := err.get_axis()
		var angle := err.get_angle()
		if angle > PI:
			angle -= TAU
		k.angular_velocity = axis.normalized() * angle * 8.0 if axis.length() > 0.001 else Vector3.ZERO
	if u >= 1.0:
		if vis:
			vis.transform = Transform3D.IDENTITY
		if not k.remote:
			# Set down rolling along the landing road at the speed it flew.
			k.linear_velocity = -b.basis.z * (float(arc["span"]) / T)
			k.angular_velocity = Vector3.ZERO
		_flights.erase(k)
		_last[k] = track.offset_of(k.global_position)
