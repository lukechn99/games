class_name KitDress
extends RefCounted
## Trackside life for Series 2 kits (design doc 8.5): the things that make a
## lap feel like a place. Corner arrows, gateways, bunting, edge lights,
## aprons beside the road, cheering crowds, and things that move on their own
## paths. Everything here is drawn only, never solid, and each call is one
## draw call (two for a crowd's far and near sides at most).


## Arrow boards on the outside of every sharp bend, pointing the way round.
## `skip`: [from, to] stretches (metres) to leave alone.
static func chevrons(t: Track, board: Color, arrow: Color, skip: Array = [], beyond := 0.7) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var out := Track.ROAD_WIDTH * 0.5 + beyond
	var d := 0.0
	while d < t.length:
		var a := -t.road_frame(d).basis.z
		var b := -t.road_frame(d + 36.0).basis.z
		var turn := Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))   # + is to the right
		var left_alone := t.in_gap(d) or t.in_gap(d + 30.0)
		for s: Array in skip:
			if d > float(s[0]) - 30.0 and d < float(s[1]):
				left_alone = true
		if absf(turn) > 0.42 and not left_alone:
			var side := -signf(turn)
			for k in 4:
				var f := t.road_frame(d + 6.0 + k * 9.0)
				var p := f.origin + f.basis.x * side * out + Vector3.UP * 1.9
				var along := -f.basis.x * side      # the way the arrow points
				var face := f.basis.z               # towards the karts coming
				var w := along * 1.25
				var h := Vector3.UP * 0.85
				KitTools.quad(st, p - w - h, p + w - h, p + w + h, p - w + h, board, side < 0.0)
				var q := p + face * 0.04
				for half: float in [-1.0, 1.0]:
					# Two slanted bars meeting at the tip.
					var tip := q + along * 0.7
					var tail := q - along * 0.25 + Vector3.UP * 0.62 * half
					var thick := along * 0.42
					KitTools.quad(st, tail - thick, tip - thick, tip, tail, arrow, (side < 0.0) != (half < 0.0))
			d += 70.0
		else:
			d += 10.0
	KitTools.commit(KitTools.parent_of(t), st, KitTools.glow(Color.WHITE), true)


## A gateway over the road at `f`: two striped posts and a beam.
static func arch(st: SurfaceTool, f: Transform3D, a: Color, b: Color, height := 8.0, thick := 1.3) -> void:
	var half := Track.ROAD_WIDTH * 0.5 + 1.6
	for side: float in [-1.0, 1.0]:
		var n := 4
		for k in n:
			var y := height * (k + 0.5) / n
			KitTools.box(st, Transform3D(f.basis, f.origin + f.basis.x * side * half + Vector3.UP * y), Vector3(thick, height / n, thick), a if k % 2 == 0 else b)
	var n2 := 7
	for k in n2:
		var x := (half * 2.0 + thick) * ((k + 0.5) / n2 - 0.5)
		KitTools.box(st, Transform3D(f.basis, f.origin + f.basis.x * x + Vector3.UP * (height + thick * 0.5)), Vector3((half * 2.0 + thick) / n2, thick * 1.2, thick), b if k % 2 == 0 else a)


## Strings of little flags across the road, every `every` metres.
static func bunting(t: Track, st: SurfaceTool, from: float, to: float, every: float, cols: Array, height := 6.5) -> void:
	var half := Track.ROAD_WIDTH * 0.5 + 1.8
	var d := from
	var row := 0
	while d < to:
		var f := t.road_frame(fposmod(d, t.length))
		var n := 11
		for k in n:
			var u := (k + 0.5) / n
			var sag := 1.6 * 4.0 * u * (1.0 - u)
			var p := f.origin + f.basis.x * lerpf(-half, half, u) + Vector3.UP * (height - sag)
			var w := f.basis.x * 0.55
			var c: Color = cols[(k + row) % cols.size()]
			for v: Vector3 in [p - w, p + w, p - Vector3.UP * 1.1]:
				st.set_color(c)
				st.add_vertex(v)
		# The poles it hangs from.
		for side: float in [-1.0, 1.0]:
			KitTools.box(st, Transform3D(f.basis, f.origin + f.basis.x * side * half + Vector3.UP * height * 0.5), Vector3(0.25, height, 0.25), Color(0.95, 0.95, 0.92))
		d += every
		row += 1


## Small glowing studs along both edges of the road.
static func edge_lights(t: Track, st: SurfaceTool, from: float, to: float, every: float, col: Color, out := 0.3, size := 0.32) -> void:
	var half := Track.ROAD_WIDTH * 0.5 + out
	var d := from
	while d < to:
		if not t.in_gap(fposmod(d, t.length)):
			var f := t.road_frame(fposmod(d, t.length))
			for side: float in [-1.0, 1.0]:
				KitTools.box(st, Transform3D(f.basis, f.origin + f.basis.x * side * half + Vector3.UP * (size * 0.5 + 0.05)), Vector3(size, size, size * 2.0), col)
		d += every


## A strip of ground beside the road on both sides, in alternating colours
## (boardwalk planks, paving). `keep`: a callable(point) → bool for where.
static func apron(t: Track, st: SurfaceTool, from: float, to: float, width: float, cols: Array, step := 4.0, keep := Callable()) -> void:
	var half := Track.ROAD_WIDTH * 0.5 + 0.9
	var d := from
	var index := 0
	while d < to:
		var a := t.road_frame(fposmod(d, t.length))
		var b := t.road_frame(fposmod(minf(d + step, to), t.length))
		if not t.in_gap(fposmod(d + step * 0.5, t.length)) and (not keep.is_valid() or keep.call(a.origin)):
			for side: float in [-1.0, 1.0]:
				var a0 := a.origin + a.basis.x * side * half + Vector3.UP * 0.03
				var b0 := b.origin + b.basis.x * side * half + Vector3.UP * 0.03
				var a1 := a.origin + a.basis.x * side * (half + width) + Vector3.UP * 0.03
				var b1 := b.origin + b.basis.x * side * (half + width) + Vector3.UP * 0.03
				KitTools.quad(st, a0, b0, b1, a1, cols[index % cols.size()], side > 0.0)
		d += step
		index += 1


## Places beside the road: a frame every `every` metres from `from` to `to`
## on each of `sides`, `out` metres beyond the kerb, facing the road.
static func beside(t: Track, from: float, to: float, every: float, out: float, sides: Array = [-1.0, 1.0]) -> Array[Transform3D]:
	var list: Array[Transform3D] = []
	var half := Track.ROAD_WIDTH * 0.5 + out
	var d := from
	while d < to:
		var o := fposmod(d, t.length)
		if not t.in_gap(o):
			var f := t.road_frame(o)
			for side: float in sides:
				list.append(Transform3D(Basis.looking_at(-f.basis.x * side, Vector3.UP), f.origin + f.basis.x * side * half))
		d += every
	return list


## True if `p` is at least `clear` metres (on the map) from every part of
## the road. For scattering scenery that mustn't land on another stretch.
static func off_road(t: Track, p: Vector3, clear: float) -> bool:
	var key := t.get_instance_id()
	if not _road_cache.has(key):
		var pts := PackedVector2Array()
		var d := 0.0
		while d < t.length:
			var o := t.transform_at(d).origin
			pts.append(Vector2(o.x, o.z))
			d += 8.0
		_road_cache = {key: pts}
	for q: Vector2 in _road_cache[key]:
		if q.distance_to(Vector2(p.x, p.z)) < clear:
			return false
	return true

static var _road_cache := {}


## Many copies of a prop spread over a wide area, split into squares of
## `cell` metres so that only the ones near the camera are drawn (`far`).
static func scatter(parent: Node3D, name: String, xforms: Array[Transform3D], far: float, cell := 110.0) -> void:
	var groups := {}
	for x in xforms:
		var key := Vector2i(floori(x.origin.x / cell), floori(x.origin.z / cell))
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(x)
	for key: Vector2i in groups:
		var list: Array = groups[key]
		var centre := Vector3.ZERO
		for x: Transform3D in list:
			centre += x.origin
		centre /= list.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = KitTools.model(name)
		mm.instance_count = list.size()
		for i in list.size():
			var x: Transform3D = list[i]
			mm.set_instance_transform(i, Transform3D(x.basis, x.origin - centre))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.position = centre
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = far
		parent.add_child(mi)


## A smooth closed curve through `path` (what a Mover travels).
static func loop_curve(path: PackedVector3Array) -> Curve3D:
	var curve := Curve3D.new()
	for p in path:
		curve.add_point(p)
	curve.add_point(path[0])
	var n := path.size()
	for i in n + 1:
		var h := (path[(i + 1) % n] - path[(i - 1 + n) % n]) * 0.22
		curve.set_point_in(i, -h)
		curve.set_point_out(i, h)
	return curve


## A size and a turn that vary from place to place but are always the same
## at the same place (never the shared random generator: see LEARNINGS).
static func varied(x: Transform3D, scale := 1.0, spread := 0.25, turn := true) -> Transform3D:
	var h := absf(sin(x.origin.x * 12.9898 + x.origin.z * 78.233) * 43758.5453)
	h -= floorf(h)
	var b := x.basis
	if turn:
		b = b.rotated(Vector3.UP, h * TAU)
	return Transform3D(b.scaled(Vector3.ONE * scale * (1.0 + (h - 0.5) * 2.0 * spread)), x.origin)


## A cheering crowd: rows of little spectators hopping on the spot, each a
## colour from `tints`. `spots` are places facing the road (see `beside`);
## each gets `deep` rows behind it.
static func crowd(parent: Node3D, spots: Array[Transform3D], tints: Array, deep := 2, far := 170.0) -> void:
	if spots.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = KitTools.model("fan")
	mm.instance_count = spots.size() * deep
	var i := 0
	for s: Transform3D in spots:
		for row in deep:
			var back := s.basis.z * (row * 1.3) + s.basis.x * (0.7 if row % 2 == 1 else 0.0)
			var x := varied(Transform3D(s.basis, s.origin + back + Vector3.UP * row * 0.35), 1.0, 0.18, false)
			mm.set_instance_transform(i, x)
			mm.set_instance_color(i, tints[int(absf(x.origin.x * 7.0 + x.origin.z * 13.0)) % tints.size()])
			i += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _crowd_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = far
	parent.add_child(mi)

static var _crowd_mat: ShaderMaterial


static func _crowd_material() -> ShaderMaterial:
	if _crowd_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode diffuse_toon, specular_disabled;
varying vec3 tint;
void vertex() {
	// Each hops to its own beat, from where it stands.
	float beat = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
	VERTEX.y += abs(sin(TIME * 5.5 + beat)) * 0.32;
	tint = pow(COLOR.rgb, vec3(2.2));
}
void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.8;
}
"""
		_crowd_mat = ShaderMaterial.new()
		_crowd_mat.shader = sh
	return _crowd_mat


## Copies of a model travelling round a closed path on their own (a coaster
## train, boats, ships, balloons). One draw call for the lot.
class Mover extends MultiMeshInstance3D:
	var path := PackedVector3Array()   # a closed loop of points
	var speed := 20.0                  # metres a second
	var count := 1
	var spacing := 0.0                 # metres between copies (0: evenly round)
	var size := 1.0
	var bob := 0.0                     # metres of gentle rise and fall
	var level := false                 # stay upright on slopes (boats, balloons)
	var _curve: Curve3D
	var _t := 0.0

	func _ready() -> void:
		_curve = KitDress.loop_curve(path)
		var box := AABB(path[0], Vector3.ZERO)
		for p in path:
			box = box.expand(p)
		custom_aabb = box.grow(30.0 * size + bob)
		multimesh.instance_count = count
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_place()

	func _process(delta: float) -> void:
		_t += delta
		_place()

	func _place() -> void:
		for i in count:
			multimesh.set_instance_transform(i, where(i))

	## Where copy `i` is now.
	func where(i: int) -> Transform3D:
		var total := _curve.get_baked_length()
		var gap := spacing if spacing > 0.0 else total / count
		var d := fposmod(_t * speed - i * gap, total)
		var p := _curve.sample_baked(d, true)
		var ahead := _curve.sample_baked(fposmod(d + 2.0, total), true) - p
		if level:
			ahead.y = 0.0
		if ahead.length() < 0.001:
			ahead = Vector3.FORWARD
		if bob > 0.0:
			p.y += sin(_t * 0.6 + i * 1.9) * bob
		return Transform3D(Basis.looking_at(ahead.normalized(), Vector3.UP).scaled(Vector3.ONE * size), p)


static func mover(parent: Node3D, model: String, path: PackedVector3Array, speed: float, count: int, opts := {}) -> Mover:
	var m := Mover.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = KitTools.model(model)
	m.multimesh = mm
	m.path = path
	m.speed = speed
	m.count = count
	m.spacing = opts.get("spacing", 0.0)
	m.size = opts.get("size", 1.0)
	m.bob = opts.get("bob", 0.0)
	m.level = opts.get("level", false)
	if opts.has("far"):
		m.visibility_range_end = opts["far"]
	parent.add_child(m)
	return m
