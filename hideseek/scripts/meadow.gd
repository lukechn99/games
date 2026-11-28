class_name Meadow
## Grass that looks grown rather than mown (owner, 2026-11-28): tufts poking
## up in patches (a noise field decides where it's thick, thin or bare),
## uncut grass hugging the walls, fence and tree lines where a mower can't
## reach, and worn bald spots of dirt that fade into the lawn. The tufts are
## one instanced mesh (one draw call, no shadows) swaying a little in the wind.
## Looks only: nothing here collides.

static var enabled := true   # ?grass=off: no tufts (bald spots stay)

const STEP := 0.42         # candidate spacing (m), jittered
const EDGE := 34.5         # the play ground's half size
const UNCUT := 0.95        # how far from a wall the long grass reaches

# Where grass can't grow: [x0, z0, x1, z1].
const BARE := [
	[-8.25, -12.3, 8.25, 12.3],          # barn
	[-3.6, 11.9, 3.6, 17.1], [-3.6, -17.1, 3.6, -11.9],   # dirt at its doors
	[-24.3, -1.8, -15.7, 9.8],           # farmhouse
	[-15.8, 1.2, -12.2, 6.8],            # porch and steps
	[-14.6, 0.4, -9.4, 7.6],             # dirt in front of it
	[-1.6, 16.8, 1.6, 34.0],             # driveway
	[-10.7, -30.7, -5.3, -22.2],         # combine
]
# Walls the long grass grows against: [x0, z0, x1, z1] (measured from the
# outside), gaps for the doors.
const WALLS := [
	[-8.15, -12.15, 8.15, 12.15],
	[-24.15, -1.65, -15.85, 9.65],
]


static func build(root: Node3D) -> void:
	var p := plan()
	if not enabled:
		root.add_child(_bald_mesh(p["bald"], RandomNumberGenerator.new()))
		return
	var xforms: Array = p["xforms"]
	var tints: Array = p["tints"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2812
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tuft_mesh(rng)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassTufts"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	root.add_child(_bald_mesh(p["bald"], rng))


## Where every tuft goes (the same every time): {xforms, tints, bald}.
static func plan() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2811
	var patches := FastNoiseLite.new()
	patches.seed = 7
	patches.frequency = 0.07
	var fine := FastNoiseLite.new()
	fine.seed = 11
	fine.frequency = 0.35
	var bald := _bald_spots(rng)
	var xforms := []
	var tints := []
	var x := -EDGE
	while x <= EDGE:
		var z := -EDGE
		while z <= Boundary.FRONT + 2.2:
			var p := Vector2(x + rng.randf_range(-0.2, 0.2), z + rng.randf_range(-0.2, 0.2))
			z += STEP
			if _bare(p):
				continue
			var wall := _wall_distance(p)
			var dry := false
			var size := 1.0
			if wall < UNCUT:
				# Uncut along the walls: thick and long.
				if rng.randf() > 0.85:
					continue
				size = rng.randf_range(1.5, 2.3) * lerpf(1.0, 0.75, wall / UNCUT)
			else:
				var b := _in_bald(p, bald)
				if b < 0.85:
					continue
				if b < 1.3:
					# Thin, dry, short grass round a bald spot.
					if rng.randf() > 0.3:
						continue
					dry = true
					size = rng.randf_range(0.5, 0.8)
				else:
					var n := patches.get_noise_2d(p.x, p.y) + fine.get_noise_2d(p.x, p.y) * 0.35
					var keep := smoothstep(-0.25, 0.5, n) * 0.85 + 0.03
					if rng.randf() > keep:
						continue
					size = rng.randf_range(0.65, 1.25)
					if rng.randf() < 0.025:
						size = rng.randf_range(1.7, 2.2)     # a stray long clump
					dry = rng.randf() < 0.06
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * rng.randf_range(0.8, 1.2), size, size * rng.randf_range(0.8, 1.2)))
			xforms.append(Transform3D(basis, Vector3(p.x, 0, p.y)))
			var k := rng.randf_range(0.88, 1.1)
			tints.append(Color(1.7 * k, 1.25 * k, 0.9 * k) if dry else Color(k * rng.randf_range(0.94, 1.06), k, k * rng.randf_range(0.9, 1.05)))
		x += STEP
	return {"xforms": xforms, "tints": tints, "bald": bald}


## True where grass can't grow (buildings, dirt, the driveway).
static func _bare(p: Vector2) -> bool:
	for r in BARE:
		if p.x > r[0] and p.x < r[2] and p.y > r[1] and p.y < r[3]:
			return true
	if p.distance_to(Vector2(TestBarn.SILO.x, TestBarn.SILO.z)) < 2.8:
		return true
	return false


## Distance to the nearest wall, fence or tree line the mower misses.
static func _wall_distance(p: Vector2) -> float:
	var d := INF
	for r in WALLS:
		var dx := maxf(maxf(r[0] - p.x, 0.0), p.x - r[2])
		var dz := maxf(maxf(r[1] - p.y, 0.0), p.y - r[3])
		var e := sqrt(dx * dx + dz * dz)
		# The barn's doorways are open: no long grass in front of them.
		if r[0] == -8.15 and absf(p.x) < 2.3 and absf(p.y) > 12.0:
			e = INF
		d = minf(d, e)
	d = minf(d, p.distance_to(Vector2(TestBarn.SILO.x, TestBarn.SILO.z)) - 2.8)
	if absf(p.x) > Boundary.GATE + 0.3:
		d = minf(d, absf(p.y - Boundary.FRONT) - 0.1)       # both sides of the fence
	d = minf(d, Boundary.EAST - 0.4 - p.x)                   # the cypress
	d = minf(d, p.x - (Boundary.WEST + 0.6))                 # the leafy trees
	d = minf(d, p.y - (Boundary.BACK + 0.4))                 # into the corn
	return d


# --- bald spots -----------------------------------------------------------

## Worn patches out on the lawn: [centre, radius, lobe phases].
static func _bald_spots(rng: RandomNumberGenerator) -> Array:
	var out := []
	var tries := 0
	while out.size() < 18 and tries < 400:
		tries += 1
		var c := Vector2(rng.randf_range(-29, 29), rng.randf_range(-27, 29))
		var r := rng.randf_range(0.8, 2.1)
		if _bare(c) or _wall_distance(c) < r + 2.0:
			continue
		var clear := true
		for o in out:
			if c.distance_to(o[0]) < r + o[1] + 3.0:
				clear = false
		if clear:
			out.append([c, r, rng.randf() * TAU, rng.randf() * TAU])
	return out


## The edge of a bald spot at angle a: a lumpy circle.
static func _edge(s: Array, a: float) -> float:
	return s[1] * (1.0 + 0.22 * sin(3.0 * a + s[2]) + 0.12 * sin(5.0 * a + s[3]))


## 0 at a spot's centre, 1 on its edge, more outside (the nearest spot).
static func _in_bald(p: Vector2, spots: Array) -> float:
	var best := INF
	for s in spots:
		var v: Vector2 = p - s[0]
		best = minf(best, v.length() / _edge(s, v.angle()))
	return best


## The spots: dirt, solid in the middle, fading out over the edge.
static func _bald_mesh(spots: Array, rng: RandomNumberGenerator) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile: float = Surfaces.TILE.get("dirt", 2.0)
	var segs := 28
	for s in spots:
		var c: Vector2 = s[0]
		var rings := [[0.0, 1.0], [0.55, 1.0], [0.85, 0.75], [1.15, 0.0]]
		var pts := []
		for ring in rings:
			var row := []
			for i in segs:
				var a := TAU * i / segs
				var r: float = _edge(s, a) * ring[0] * rng.randf_range(0.94, 1.06) if ring[0] > 0 else 0.0
				row.append([c + Vector2(cos(a), sin(a)) * r, ring[1]])
			pts.append(row)
		for j in rings.size() - 1:
			for i in segs:
				var q := [pts[j][i], pts[j][(i + 1) % segs], pts[j + 1][(i + 1) % segs], pts[j + 1][i]]
				for k in [0, 2, 1, 0, 3, 2]:
					var v: Vector2 = q[k][0]
					st.set_color(Color(1.04, 1.0, 0.92, q[k][1]))
					st.set_normal(Vector3.UP)
					st.set_uv(v / tile)
					st.add_vertex(Vector3(v.x, 0.006, v.y))
	var m := Surfaces.material("dirt").duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.name = "BaldSpots"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- the tuft ---------------------------------------------------------------

const SWAY := """
shader_type spatial;
render_mode cull_disabled;

// The tufts take their colour from the ground right under them (owner,
// 2026-11-28: blend in), lightened a little towards the tips, and are lit
// as if facing straight up, like the ground, from both sides.
uniform sampler2D ground : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile = 3.0;
varying vec2 spot;

void vertex() {
	float h = UV.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	spot = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xz;
	VERTEX.x += sin(TIME * 1.6 + w.x * 0.45 + w.z * 0.3) * 0.05 * h * h;
	VERTEX.z += sin(TIME * 1.2 + w.z * 0.4) * 0.035 * h * h;
}

void fragment() {
	ALBEDO = texture(ground, spot / tile).rgb * COLOR.rgb;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
"""


## A clump of a dozen thin blades, ground-coloured at the root and lighter at
## the tips, leaning out from the middle. One triangle a blade. About 0.3 m
## tall at size 1.
static func _tuft_mesh(rng: RandomNumberGenerator) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Multipliers on the ground's own colour: as is at the root, a touch
	# lighter and yellower at the tip.
	var root_col := Color(1.0, 1.0, 1.0)
	var tip_col := Color(1.2, 1.16, 1.05)
	for i in 12:
		var a := TAU * i / 12 + rng.randf_range(-0.35, 0.35)
		var out := Vector3(cos(a), 0, sin(a))
		var base := out * rng.randf_range(0.0, 0.06)
		var h := rng.randf_range(0.17, 0.34)
		var tip := base + out * rng.randf_range(0.04, 0.14) + Vector3(0, h, 0)
		var side := out.cross(Vector3.UP).normalized() * rng.randf_range(0.012, 0.019)
		var n := (out * 0.3 + Vector3.UP).normalized()
		var tc := tip_col.lerp(root_col, rng.randf_range(0.0, 0.3))
		for v in [[base - side, root_col, 0.0], [tip, tc, 1.0], [base + side, root_col, 0.0]]:
			st.set_color(v[1])
			st.set_normal(n)
			st.set_uv(Vector2(0, v[2]))
			st.add_vertex(v[0])
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SWAY
	m.shader = sh
	m.set_shader_parameter("ground", Surfaces.material("grass").albedo_texture)
	m.set_shader_parameter("tile", Surfaces.TILE["grass"])
	st.set_material(m)
	return st.commit()
