class_name Dressing
extends RefCounted
## Our own Blender props (assets/models, tools/blender/props.py) placed
## round the tracks: street lamps along Meadow Loop's highway, windmills in
## its fields, stone lanterns at Mining Mountain's tunnel mouths, and rows
## of coins on the road (picked up in items.gd).

const LAMP := "res://assets/models/lamp_post.glb"
const WINDMILL := "res://assets/models/windmill.glb"
const LANTERN := "res://assets/models/lantern.glb"


static func build(t: Track) -> void:
	if t.layout == "meadow":
		_lamps(t)
		_windmills(t)
	else:
		_lanterns(t)
	_coins(t)


## Lamps on the highway stretches, behind the guardrail, arms over the road.
static func _lamps(t: Track) -> void:
	var xs: Array[Transform3D] = []
	var d := 0.0
	var k := 0
	while d < t.length:
		if t._in_rail_zone(d / t.length) and t.branch_at(d) < 0:
			var f := t.road_frame(d)
			var side := 1.0 if k % 2 == 0 else -1.0
			var p := f.origin + f.basis.x * side * (Track.ROAD_WIDTH * 0.5 + 3.0)
			if t.distance_to_road(p) > Track.ROAD_WIDTH * 0.5 + 2.0:
				p.y = minf(f.origin.y, 0.0) if f.origin.y > 0.5 else f.origin.y
				var flat := Basis(Vector3.UP, atan2(-f.basis.z.x, -f.basis.z.z) + PI)
				# The arm reaches along +x; turn it to point over the road.
				var b := flat if side < 0 else flat.rotated(Vector3.UP, PI)
				xs.append(Transform3D(b, p))
			k += 1
		d += 38.0
	t._scatter(LAMP, xs)


## A few windmills out in the fields, sails turning.
static func _windmills(t: Track) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var placed := 0
	var tries := 0
	while placed < 4 and tries < 400:
		tries += 1
		var p := Vector3(rng.randf_range(-220, 380), 0, rng.randf_range(-380, 320))
		var dist := t._distance_to_line(p)
		if dist < 45.0 or dist > 150.0 or t._blocked(p) or t.in_water(p):
			continue
		var scene: PackedScene = load(WINDMILL)
		if scene == null:
			return
		var n: Node3D = scene.instantiate()
		Palette.restyle_tree(n)
		# Face roughly toward the road.
		var near := t.transform_at(t.offset_of(p)).origin
		var to := (near - p) * Vector3(1, 0, 1)
		n.transform = Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z) + PI).scaled(Vector3.ONE * 2.2), p)
		t.add_child(n)
		var sails := n.find_child("Sails", true, false) as Node3D
		if sails:
			var sp := Spinner.new()
			sp.target = sails
			sp.speed = rng.randf_range(0.5, 0.9)
			t.add_child(sp)
		t.keep_clear(p, 12.0)
		placed += 1


## Stone lanterns either side of each tunnel mouth, glowing.
static func _lanterns(t: Track) -> void:
	var xs: Array[Transform3D] = []
	for i in t.branches.size():
		if t.branches[i]["kind"] != "tunnel":
			continue
		var b: Dictionary = t.branches[i]
		var d0 := -1.0
		var d1 := -1.0
		var d: float = b["from"]
		while d < float(b["to"]):
			if absf(t.branch_offset(d, i)) >= 28.0:
				if d0 < 0.0:
					d0 = d
				d1 = d
			d += 1.0
		for e in [[d0 - 3.0, 1.0], [d1 + 3.0, -1.0]]:
			if e[0] < 0.0:
				continue
			var f := t.branch_frame(e[0], i)
			for sx: float in [-1.0, 1.0]:
				var p := f.origin + f.basis.x * sx * (Track.ROAD_WIDTH * 0.5 + 1.8)
				xs.append(Transform3D(Basis(Vector3.UP, randf() * 0.3).scaled(Vector3.ONE * 1.2), p - Vector3.UP * 0.05))
	t._scatter(LANTERN, xs)


## Rows of coins along the racing line on straights, alternating sides.
static func _coins(t: Track) -> void:
	var spots: Array[Vector3] = []
	var n := 6 if t.layout == "meadow" else 8
	for k in n:
		var d := t.length * (0.08 + 0.85 * k / float(n))
		if t.branch_at(d) >= 0 or t.branch_at(d + 20.0) >= 0:
			d += 40.0
		if t.branch_at(d) >= 0:
			continue
		# A diagonal across the road, alternating which way, so you have to
		# steer across to collect the whole line.
		var dir := 1.0 if k % 2 == 0 else -1.0
		for j in 5:
			var f := t.road_frame(d + j * 4.0)
			var lane := dir * lerpf(-4.5, 4.5, j / 4.0)
			spots.append(f.origin + f.basis.x * lane + f.basis.y * 0.9)
	t.coin_spots = spots
