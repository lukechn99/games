class_name LaunchGaps
extends Node
## Jumps (design doc 8.4, 8.6), on Mario Kart's rules: no skill needed to
## make one. Whatever speed a kart arrives at, it flies one planned arc that
## ends on the landing, held on line and level, so it lands every time.
##
## Two kinds:
## - Gaps in the road (Track.gaps: [from, to, options] in metres round the
##   lap). Crossing the lip on the road launches you; the road builder
##   leaves the stretch out.
## - Pads (Track.pads): a lip on the rim of a bowl, which launches whoever
##   drives out over it, wherever they came from in the bowl. A bowl with
##   several lips sends you where you steer (the moon's craters).
##
## Options for either: "lift" (metres over the straight line), "min_speed"
## (the slowest a kart flies it), "fly_speed" (flown at this speed,
## whatever the kart's: long jumps between worlds), "slow" (flight speed
## factor), "glide" (a glider opens), "pads" (a gap only there so the road
## builder leaves it out: pads do the launching).
##
## Pressing drift as you leave a lip (just before, or just after) is a
## trick: a somersault, and a short boost when you land. Missing it costs
## nothing. The one way to fall is to be hit by an item in the air: the
## kart drops, and is put back on the road.

const MIN_SPEED := 22.0     # a slow kart is thrown at least this fast (m/s)
const RIDE := 0.55          # kart centre above the road
const LAND := 0.3           # ...where the flight ends: about where it sits (a
                            # higher set-down dropped it for 0.3 s first)
const HOLD := 7.0           # how firmly a kart is held to the arc
const TRICK_EARLY := 0.25   # seconds before the lip a drift press still counts
const TRICK_LATE := 0.3     # and after it
const TRICK_BOOST := 0.7    # seconds of boost for a trick
const GLIDE_SPAN := 90.0    # gliders open on jumps longer than this

var track: Track
var karts: Array[Kart] = []
var _arcs: Array[Dictionary] = []    # one per road gap
var _pads: Array[Dictionary] = []
var _last := {}                      # kart -> lap offset last tick
var _flights := {}                   # kart -> {arc, t, T, speed, side, trick, ...}
var _pressed := {}                   # kart -> time drift was last pressed
var _held := {}                      # kart -> drift held last tick
var _dropped := {}                   # kart -> seconds until it's put back
var _clock := 0.0


func setup(t: Track, all: Array[Kart]) -> void:
	track = t
	karts = all
	for g: Array in t.gaps:
		var a := t.road_frame(g[0])
		var b := t.road_frame(g[1])
		var opt: Dictionary = g[2] if g.size() > 2 else {}
		# ("land_up": the landing's road lies under the ground there, a crater.)
		var arc := make_arc(a.origin + Vector3.UP * RIDE, b.origin + Vector3.UP * (LAND + float(opt.get("land_up", 0.0))), a, b, opt)
		arc["from"] = float(g[0])
		arc["to"] = float(g[1])
		arc["pads"] = bool(opt.get("pads", false))
		_arcs.append(arc)
	_pads = t.pads
	for k in karts:
		if is_instance_valid(k):
			k.respawned.connect(_on_respawn.bind(k))


## Put back on the road (a fall, a reset): whatever flight it was on is over.
func _on_respawn(k: Kart) -> void:
	if _flights.has(k):
		_end(k, _flights[k])
	_dropped.erase(k)


## An arc from `p0` to `p1`, leaving along `a` and landing along `b`.
static func make_arc(p0: Vector3, p1: Vector3, a: Transform3D, b: Transform3D, opt: Dictionary) -> Dictionary:
	var flat := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	var fwd := -a.basis.z
	var slope := fwd.y / maxf(0.05, Vector2(fwd.x, fwd.z).length())
	# Height over the straight line between lip and landing, set by default
	# so the arc leaves along the road's slope at the lip.
	var lift: float = opt.get("lift", maxf(1.5, (slope * flat.length() - (p1.y - p0.y)) / 4.0))
	return {"p0": p0, "p1": p1, "span": flat.length(), "lift": lift, "a": a, "b": b,
		"min_speed": float(opt.get("min_speed", MIN_SPEED)), "slow": float(opt.get("slow", 1.0)),
		"fly_speed": float(opt.get("fly_speed", 0.0)), "glide": bool(opt.get("glide", flat.length() > GLIDE_SPAN))}


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


## Has `k` just driven out over pad `p`'s lip? (Also used by tests.)
static func over_lip(p: Dictionary, pos: Vector3, vel: Vector3) -> bool:
	var c: Vector3 = p["centre"]
	var dir: Vector3 = p["dir"]
	var v := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
	var along := v.dot(dir)
	var across := (v - dir * along).length()
	return along >= float(p["r"]) - 1.0 and along < float(p["r"]) + 4.0 and across < float(p["half"]) \
		and Vector3(vel.x, 0.0, vel.z).dot(dir) > 2.0 and pos.y > float(p["rim_y"]) - 3.0


func flying(k: Kart) -> bool:
	return _flights.has(k)


func _physics_process(delta: float) -> void:
	if track == null:
		return
	_clock += delta
	for k in karts:
		if not is_instance_valid(k):
			continue
		var drift := bool(k.input.get("drift", false))
		if drift and not _held.get(k, false):
			_pressed[k] = _clock
		_held[k] = drift
		if _dropped.has(k):
			_dropped[k] = float(_dropped[k]) - delta
			if k.collision_mask == 0:
				k.collision_mask = 1
			if float(_dropped[k]) <= 0.0:
				_dropped.erase(k)
				if not k.remote:
					k.respawn_reason = "hit in the air"
					k.respawn()
				_last[k] = track.offset_of(k.global_position)
			continue
		if _flights.has(k):
			_fly(k, delta)
			continue
		var off := track.offset_of(k.global_position)
		var before: float = _last.get(k, off)
		_last[k] = off
		var launched := false
		for arc in _arcs:
			if arc["pads"]:
				continue
			var lip: float = arc["from"]
			# Just crossed the lip, on the road, going forwards.
			if before < lip and off >= lip and off - before < 12.0:
				var local := track.road_local(k.global_position)
				if absf(local.x) < Track.ROAD_WIDTH * 0.5 + 1.5 and absf(local.y) < 3.0:
					_launch(k, arc, clampf(local.x, -5.0, 5.0))
					launched = true
					break
		if launched:
			continue
		for p in _pads:
			if over_lip(p, k.global_position, k.linear_velocity):
				var a := Transform3D(Basis.looking_at(p["dir"], Vector3.UP), k.global_position)
				var b: Transform3D = p["to"]
				_launch(k, make_arc(k.global_position, b.origin + Vector3.UP * LAND, a, b, p), 0.0)
				break


func _launch(k: Kart, arc: Dictionary, side: float) -> void:
	var speed := maxf(float(arc["min_speed"]), Vector2(k.linear_velocity.x, k.linear_velocity.z).length())
	var fly := float(arc["fly_speed"]) if float(arc["fly_speed"]) > 0.0 else speed * float(arc["slow"])
	var f := {"arc": arc, "t": 0.0, "T": float(arc["span"]) / fly, "speed": speed, "side": side,
		"trick": _clock - float(_pressed.get(k, -10.0)) < TRICK_EARLY, "knocked": k.knocked_ms,
		# Computer drivers flip for show, but get no boost: they don't brake
		# for the extra speed, and were thrown off bends after landings.
		"show": bool(k.get_meta("tricks", false))}
	if arc["glide"]:
		f["glider"] = _open_glider(k)
	_flights[k] = f
	k.set_meta("airborne", true)
	# The arc is planned clear of everything, so nothing in the world can
	# snag it on the way (a crater's rim rail did, and the hold then dragged
	# the kart down through the bowl).
	if not k.remote:
		f["mask"] = k.collision_mask
		k.collision_mask = 0


func _fly(k: Kart, delta: float) -> void:
	var f: Dictionary = _flights[k]
	var arc: Dictionary = f["arc"]
	f["t"] += delta
	var T: float = f["T"]
	var u := clampf(float(f["t"]) / T, 0.0, 1.0)
	var a: Transform3D = arc["a"]
	var b: Transform3D = arc["b"]
	if not f["trick"] and float(f["t"]) < TRICK_LATE and float(_pressed.get(k, -10.0)) > _clock - float(f["t"]) - 0.001:
		f["trick"] = true
	# Hit by an item in the air: the one way to fall.
	if k.knocked_ms != int(f["knocked"]) and u > 0.05 and u < 0.92:
		_end(k, f)
		_dropped[k] = 1.6
		return
	var vis := k.get_meta("visual", null) as Node3D
	if vis:
		if f["trick"] or f["show"]:
			# A forward somersault about the kart's middle, eased in and out.
			var turn := -TAU * smoothstep(0.08, 0.92, u)
			var pivot := Vector3(0.0, 0.45, 0.0)
			var spin := Basis(Vector3.RIGHT, turn)
			vis.transform = Transform3D(spin, pivot - spin * pivot)
		else:
			vis.transform = Transform3D.IDENTITY
	if f.has("glider"):
		var g := f["glider"] as Node3D
		if is_instance_valid(g):
			# Opens over the first moment, folds away as it lands.
			var s := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.93, 1.0, u))
			g.scale = Vector3.ONE * maxf(s, 0.01)
	if not k.remote:
		# Held to the arc: the planned velocity plus a pull back onto the line.
		var right := a.basis.x.lerp(b.basis.x, u).normalized()
		var want := arc_point(arc, u) + right * float(f["side"]) * (1.0 - 0.5 * u)
		var ahead := arc_point(arc, minf(u + 0.02, 1.0)) - arc_point(arc, maxf(u - 0.02, 0.0))
		var planned := ahead / (0.04 * T) if u < 0.98 else -b.basis.z * (float(arc["span"]) / T)
		k.linear_velocity = planned + (want - k.global_position) * HOLD
		# Kept level, nose along the flight.
		var nose := Vector3(planned.x, planned.y * 0.35, planned.z).normalized()
		var target := Basis.looking_at(nose, Vector3.UP)
		var err := (target * k.global_transform.basis.inverse()).get_rotation_quaternion()
		var axis := err.get_axis()
		var angle := err.get_angle()
		if angle > PI:
			angle -= TAU
		k.angular_velocity = axis.normalized() * angle * 8.0 if axis.length() > 0.001 else Vector3.ZERO
	if u >= 1.0:
		_end(k, f)
		if not k.remote:
			# Set down rolling along the landing road at the speed it arrived,
			# level with the road under it: nose down from the descent, the
			# front wheels struck first and the kart pitched, bottomed out
			# and spun (Windy City's drawbridge). Only turned, not moved:
			# moved down onto the road, karts caught the landing road's
			# raised edge (Cosmic Crossing).
			k.linear_velocity = -b.basis.z * float(f["speed"])
			k.angular_velocity = Vector3.ZERO
			var q := PhysicsRayQueryParameters3D.create(k.global_position, k.global_position - Vector3.UP * 4.0, 1, [k.get_rid()])
			var hit := k.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and (hit["normal"] as Vector3).dot(Vector3.UP) > 0.6:
				var n := hit["normal"] as Vector3
				var ahead := -b.basis.z - n * (-b.basis.z).dot(n)
				k.global_basis = Basis.looking_at(ahead.normalized(), n)
			if f["trick"]:
				k.boost_time = maxf(k.boost_time, TRICK_BOOST)


func _end(k: Kart, f: Dictionary) -> void:
	var vis := k.get_meta("visual", null) as Node3D
	if vis:
		vis.transform = Transform3D.IDENTITY
	if f.has("glider") and is_instance_valid(f["glider"]):
		(f["glider"] as Node3D).queue_free()
	_flights.erase(k)
	if f.has("mask"):
		k.collision_mask = int(f["mask"])
	if k.has_meta("airborne"):
		k.remove_meta("airborne")
	_last[k] = track.offset_of(k.global_position)


func _open_glider(k: Kart) -> Node3D:
	var g := MeshInstance3D.new()
	g.mesh = KitTools.model("glider")
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.scale = Vector3.ONE * 0.01
	var vis := k.get_meta("visual", null) as Node3D
	(vis if vis else k).add_child(g)
	return g
