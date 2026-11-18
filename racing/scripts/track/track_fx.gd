class_name TrackFx
extends Node3D
## Series 2's shared track mechanics (design doc 8.4), driven by lists a kit
## fills in:
##
## zones: stretches of the lap that change how karts move.
##   {from, to, kind: "gravity", scale}            lighter (or heavier) gravity
##   {from, to, kind: "wind", push, period}        a sideways gust that swings
##                                                 left and right on the clock
##   {from, to, kind: "drag", drag}                shallow water: slows you
##   (any of those may add from_x, to_x: only that strip of the road's width)
##   {kind: "spin", centre, radius, turn}          a turning platform: karts
##                                                 on it are carried the way
##                                                 it turns (rad/s)
## hazards: things on a timer that knock a kart that touches them.
##   {at, from_x, to_x, period, on, phase, color}  a jet or barrier across part
##                                                 of the road (x: metres from
##                                                 the centre line), live for
##                                                 `on` seconds of each period
##   {at, sweep, model, phase}                     something that crosses the
##                                                 road and back, `sweep`
##                                                 seconds each way (a bumper
##                                                 car): always there
##
## Timers run on the race's shared clock, so every game in an online race
## sees the same thing. Remote karts are only watched, never pushed.

const WARN := 0.7        # seconds a hazard glows before it fires
const JET_H := 4.5
const GRACE := 4.0       # seconds a kart just knocked is let through hazards

var track: Track
var karts: Array[Kart] = []
var zones: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var _elapsed := 0.0
var _in_gravity := {}
var _knocked := {}       # kart -> when a hazard last knocked it (race clock)


func setup(t: Track, all: Array[Kart]) -> void:
	track = t
	karts = all
	zones = t.fx_zones
	hazards = []
	for h: Dictionary in t.fx_hazards:
		hazards.append(_make_hazard(h))


func now() -> float:
	var net := get_node_or_null("/root/Net")
	if net and net.active:
		return net.host_now()
	return _elapsed


## Is this hazard live at time `t`? (Also used by tests.)
static func live(h: Dictionary, t: float) -> bool:
	return fposmod(t + float(h.get("phase", 0.0)), float(h["period"])) < float(h["on"])


## -1..1: which way and how hard a wind zone blows at time `t`.
static func gust(z: Dictionary, t: float) -> float:
	var x := sin(TAU * t / float(z.get("period", 6.0)))
	return signf(x) * smoothstep(0.15, 0.6, absf(x))


func _make_hazard(h: Dictionary) -> Dictionary:
	var out := h.duplicate()
	var f := track.road_frame(float(h["at"]))
	if h.has("sweep"):
		var car: Node3D
		if h["model"] == "dust_devil":
			car = SpaceFx.dust_devil()
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = KitTools.model(h["model"])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			car = mi
		add_child(car)
		out["frame"] = f
		out["node"] = car
		out["hit"] = {}
		return out
	var x0: float = h["from_x"]
	var x1: float = h["to_x"]
	var c: Color = h.get("color", Color(0.21, 0.88, 1.0))
	var mid := f.origin + f.basis.x * (x0 + x1) * 0.5
	# The jet itself (shown while live), and its floor strip (always there,
	# brightening just before it fires).
	var jet: Node3D
	if h.get("blow", false):
		# A vent: gas boiling up from the road (SpaceFx).
		jet = SpaceFx.vent(absf(x1 - x0), float(h.get("height", JET_H)))
		jet.transform = Transform3D(f.basis, mid)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(absf(x1 - x0), float(h.get("height", JET_H)), float(h.get("depth", 0.9)))
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = _glow(c, 0.75)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(f.basis, mid + Vector3.UP * float(h.get("height", JET_H)) * 0.5)
		mi.visible = false
		jet = mi
	add_child(jet)
	var strip := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(absf(x1 - x0), 0.06, float(h.get("depth", 0.9)) + 0.4)
	strip.mesh = plate
	var sm := _glow(c.darkened(0.55), 1.0)
	strip.material_override = sm
	strip.transform = Transform3D(f.basis, mid + Vector3.UP * 0.07)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	out["frame"] = f
	out["jet"] = jet
	out["strip_mat"] = sm
	out["dim"] = c.darkened(0.55)
	out["bright"] = c.lightened(0.3)
	out["hit"] = {}
	return out


static func _glow(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _physics_process(delta: float) -> void:
	if track == null:
		return
	_elapsed += delta
	var t := now()
	for h in hazards:
		if h.has("sweep"):
			_sweep(h, t)
			continue
		var on := live(h, t)
		var soon := live(h, t + float(h.get("warn", WARN)))
		h["active"] = on
		if h.get("blow", false):
			# A vent: sputters for its warning, then the full column.
			(h["jet"] as SpaceFx.Vent).set_level(1.0 if on else (0.25 if soon else 0.0))
		else:
			(h["jet"] as Node3D).visible = on
		(h["strip_mat"] as StandardMaterial3D).albedo_color = h["bright"] if on or (soon and fposmod(t * 6.0, 1.0) < 0.5) else h["dim"]
		if not on:
			h["hit"] = {}
	for k in karts:
		if not is_instance_valid(k) or k.remote:
			continue
		var off := track.offset_of(k.global_position)
		var light := 1.0
		for z in zones:
			if z["kind"] == "spin":
				_spin(k, z, delta)
				continue
			if not _within(off, z):
				continue
			if z.has("from_x"):
				var x := track.road_local(k.global_position).x
				if x < float(z["from_x"]) or x > float(z["to_x"]):
					continue
			match z["kind"]:
				"gravity":
					light = float(z["scale"])
				"wind":
					var right := track.transform_at(off).basis.x
					k.apply_central_force(right * gust(z, t) * float(z["push"]) * k.mass)
				"drag":
					var v := k.linear_velocity
					var keep := maxf(0.0, 1.0 - float(z["drag"]) * delta)
					k.linear_velocity = Vector3(v.x * keep, v.y, v.z * keep)
		if not is_equal_approx(k.gravity_scale, light):
			k.gravity_scale = light
		for h in hazards:
			if h.has("sweep") or not h.get("active", false) or (h["hit"] as Dictionary).has(k) or spared(k, t):
				continue
			var local: Vector3 = (h["frame"] as Transform3D).affine_inverse() * k.global_position
			if local.x > minf(h["from_x"], h["to_x"]) - 0.8 and local.x < maxf(h["from_x"], h["to_x"]) + 0.8 and absf(local.z) < float(h.get("depth", 0.9)) * 0.5 + 1.15 and local.y > -1.0 and local.y < float(h.get("height", JET_H)):
				h["hit"][k] = true
				_knocked[k] = t
				if h.get("blow", false):
					_blow(k, h)
				else:
					k.knock((h["frame"] as Transform3D).origin + (h["frame"] as Transform3D).basis.x * (float(h["from_x"]) + float(h["to_x"])) * 0.5 - (h["frame"] as Transform3D).basis.z * 2.0)


## A kart a hazard has just knocked is let through for a moment. Without
## this, a kart thrown back from a timed jet can arrive again exactly as it
## next fires, over and over (one sat in the haunted house for 30 s).
func spared(k: Kart, t: float) -> bool:
	return _knocked.has(k) and t - float(_knocked[k]) < GRACE and t >= float(_knocked[k])


func _within(off: float, z: Dictionary) -> bool:
	var a: float = z["from"]
	var b: float = z["to"]
	return (off >= a and off <= b) if a <= b else (off >= a or off <= b)


## Where a sweeper is across the road at time `t` (metres from the centre).
static func sweep_x(h: Dictionary, t: float) -> float:
	var u := fposmod(t / float(h["sweep"]) + float(h.get("phase", 0.0)), 2.0)
	return lerpf(-5.6, 5.6, smoothstep(0.0, 1.0, u if u < 1.0 else 2.0 - u))


func _sweep(h: Dictionary, t: float) -> void:
	var f: Transform3D = h["frame"]
	var x := sweep_x(h, t)
	var going := signf(sweep_x(h, t + 0.05) - x)
	var p := f.origin + f.basis.x * x
	(h["node"] as Node3D).global_transform = Transform3D(Basis.looking_at(f.basis.x * (going if going != 0.0 else 1.0), Vector3.UP), p)
	for k in karts:
		if not is_instance_valid(k):
			continue
		var gap := k.global_position - p
		var near := Vector2(gap.x, gap.z).length() < 2.6 and absf(gap.y) < 2.0
		if near and not (h["hit"] as Dictionary).has(k) and not spared(k, t):
			h["hit"][k] = true
			_knocked[k] = t
			k.knock(p)
		elif not near and Vector2(gap.x, gap.z).length() > 5.0:
			(h["hit"] as Dictionary).erase(k)


## A turning platform: a kart on it is carried the way the platform moves
## under it, so going with the turn is quicker and against it slower.
func _spin(k: Kart, z: Dictionary, delta: float) -> void:
	var c: Vector3 = z["centre"]
	var r := k.global_position - c
	if absf(r.y) > 2.5 or Vector2(r.x, r.z).length() > float(z["radius"]):
		return
	var under := Vector3(-r.z, 0.0, r.x) * float(z["turn"])   # the platform's velocity here
	k.linear_velocity += under * 0.55 * delta


## A vent's blast: straight up, a little to its side, still rolling on.
## The kart falls back by itself; only if it comes down off the track does
## the usual recovery put it back.
func _blow(k: Kart, h: Dictionary) -> void:
	var f: Transform3D = h["frame"]
	var side := signf(float(h["from_x"]) + float(h["to_x"]))
	k.knocked_ms = Time.get_ticks_msec() + 1
	var v := k.linear_velocity
	k.linear_velocity = Vector3(v.x, 0.0, v.z) * 0.4 + Vector3.UP * 21.0 + f.basis.x * side * 2.5
	k.angular_velocity = f.basis.z * 1.2 * side
	k.crashed.emit(0.8)
