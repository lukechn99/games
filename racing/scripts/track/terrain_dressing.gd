class_name TerrainDressing
extends RefCounted
## Rock and stone models from Blender (tools/blender/terrain.py) dressed onto
## the tracks, so the ground has real shape instead of flat textures:
##
## - Meadow Loop: a boulder wall along the foot of the rock face on the high
##   ledge, and loose rocks scattered along the verges.
## - Mining Mountain: layered cliff slabs stepping up the mountain wall beside
##   the ledge, and rocks on the shoulder and down the outer slope.
##
## Each model is drawn as instanced copies (a few draw calls per 160 m patch).
## Rocks big enough to matter near the road are solid.

const WALL := "res://assets/models/terrain_boulder_wall.glb"
const CLIFF := "res://assets/models/terrain_cliff.glb"
const ROCKS := ["res://assets/models/terrain_rock0.glb", "res://assets/models/terrain_rock1.glb",
	"res://assets/models/terrain_rock2.glb", "res://assets/models/terrain_rock3.glb"]


static func build(t: Track) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	if t.layout == "meadow":
		_ledge_wall(t, rng)
		_verge_rocks(t, rng, 70, 3.5, 30.0)
	else:
		_mine_cliffs(t, rng)
		_verge_rocks(t, rng, 90, 3.0, 40.0)


static func _flat_facing(f: Transform3D, side: float) -> Basis:
	# The models face -z; turn them to face the road from `side`.
	var x := (f.basis.x * Vector3(1, 0, 1)).normalized() * side
	return Basis.looking_at(x, Vector3.UP)


## Boulders stacked along the foot of the ledge's rock face.
static func _ledge_wall(t: Track, rng: RandomNumberGenerator) -> void:
	var xs: Array[Transform3D] = []
	var inner := -t.ledge_out
	var d := Track.LEDGE[0] + 3.0
	while d < Track.LEDGE[1] - 3.0:
		var f := t.road_frame(d)
		var p := f.origin + f.basis.x * inner * (Track.ROAD_WIDTH * 0.5 + 1.9)
		var b := _flat_facing(f, inner).rotated(Vector3.UP, rng.randf_range(-0.08, 0.08))
		xs.append(Transform3D(b.scaled(Vector3(1.0, rng.randf_range(1.5, 1.9), 1.0)), p - Vector3.UP * 0.3))
		d += 7.0
	t._scatter(WALL, xs)


## Layered rock slabs climbing the mountain beside the ledge. Each has a
## solid base, so you can't drive into them.
static func _mine_cliffs(t: Track, rng: RandomNumberGenerator) -> void:
	var xs: Array[Transform3D] = []
	var inner := -t.ledge_out
	var body := StaticBody3D.new()
	body.set_meta("surface", "rock")
	t.add_child(body)
	var d := 30.0
	while d < t.length - 30.0:
		var skip := false
		for k in [-12.0, 0.0, 12.0]:
			if t.branch_at(d + k) >= 0:
				skip = true
		if not skip:
			var f := t.road_frame(d)
			var p := f.origin + f.basis.x * inner * (Track.ROAD_WIDTH * 0.5 + 7.5 + rng.randf_range(0.0, 2.5))
			var sc := rng.randf_range(0.9, 1.25)
			var b := _flat_facing(f, inner).rotated(Vector3.UP, rng.randf_range(-0.15, 0.15))
			xs.append(Transform3D(b.scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.2), sc)), p - Vector3.UP * 0.6))
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(9.0 * sc, 3.0, 2.5)
			col.shape = box
			col.transform = Transform3D(b, p + Vector3.UP * 1.0 + b.z * 1.2)
			body.add_child(col)
		d += rng.randf_range(8.0, 10.0)
	t._scatter(CLIFF, xs)


## Loose rocks along both verges: a few big ones (solid if near the road),
## more small ones.
static func _verge_rocks(t: Track, rng: RandomNumberGenerator, count: int, near: float, far: float) -> void:
	var lists := [[], [], [], []]
	var body := StaticBody3D.new()
	body.set_meta("surface", "rock")
	t.add_child(body)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 20:
		tries += 1
		var d := rng.randf() * t.length
		if t.branch_at(d) >= 0:
			continue
		var f := t.road_frame(d)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := Track.ROAD_WIDTH * 0.5 + near + pow(rng.randf(), 1.5) * far
		var p := f.origin + f.basis.x * side * lat
		if t.distance_to_road(p) < Track.ROAD_WIDTH * 0.5 + near - 0.5 or t.in_water(p):
			continue
		if t.layout == "meadow" and t._blocked(p):
			continue
		# Sit it on the ground.
		var space := t.get_world_3d().direct_space_state if t.is_inside_tree() else null
		if space:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 30.0))
			if hit.is_empty():
				continue
			p = hit["position"]
		var big := rng.randf() < 0.25
		var sc := rng.randf_range(1.2, 2.2) if big else rng.randf_range(0.35, 0.9)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.7, 1.1), sc))
		lists[rng.randi() % 4].append(Transform3D(b, p))
		if big and lat < Track.ROAD_WIDTH * 0.5 + 12.0:
			var col := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.8 * sc
			cyl.height = 1.6 * sc
			col.shape = cyl
			col.position = p + Vector3.UP * cyl.height * 0.5
			body.add_child(col)
		placed += 1
	for i in 4:
		var arr: Array[Transform3D] = []
		arr.assign(lists[i])
		t._scatter(ROCKS[i], arr, 260.0)
