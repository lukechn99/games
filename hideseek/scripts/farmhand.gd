class_name Farmhand
extends Node3D
## How other players see a seeker (owner, 2026-11-27): a cute chibi
## farmhand: big round head, straw hat, denim overalls, rubber boots, a
## paintball marker with a pink hopper. Each player has their own colour
## (shirt, hat band, boots). Blush is a faint tint in the face's colours,
## not a separate shape.
##
## Jointed: hips and knees swing the legs; while walking the body bobs and
## rolls a little side to side and the arms sway; it stretches in the air
## and squashes on landing. Feet at the origin, facing -Z, about 1.6 m tall.

## Player colours, in seat order.
const COLOURS := {
	"Tomato": Color(0.86, 0.24, 0.2), "Sky": Color(0.28, 0.6, 0.92), "Leaf": Color(0.33, 0.7, 0.32),
	"Berry": Color(0.6, 0.32, 0.75), "Sunflower": Color(0.97, 0.78, 0.2), "Tangerine": Color(0.98, 0.55, 0.18),
	"Mint": Color(0.35, 0.82, 0.68), "Bubblegum": Color(0.96, 0.5, 0.7), "Slate": Color(0.45, 0.5, 0.58),
	"Cocoa": Color(0.55, 0.36, 0.24),
}

const SKIN := Color(0.98, 0.8, 0.66)
const BLUSH := Color(1.0, 0.55, 0.55)
const DENIM := Color(0.3, 0.45, 0.72)
const STRAW := Color(0.95, 0.8, 0.42)
const HAIR := Color(0.45, 0.25, 0.12)
const EYE := Color(0.1, 0.08, 0.08)
const S := 1.16                  # mockup units to metres

var colour := Color(0.86, 0.24, 0.2)

var _body: Node3D                # bobs, rolls, squashes
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _head: Node3D
var _phase := 0.0
var _amount := 0.0
var _squash := 0.0               # >0 squashed, <0 stretched
var _squash_v := 0.0
var _air := false
var _last := Vector3.INF

static var _material: StandardMaterial3D
static var _meshes := {}


static func colour_at(i: int) -> Color:
	return COLOURS.values()[i % COLOURS.size()]


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var parts := _parts(colour)
	_body.add_child(_mi(parts["torso"]))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.8 * S, 0)
	_body.add_child(_head)
	_head.add_child(_mi(parts["head"]))
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.09 * S, 0.42 * S, 0)
		_body.add_child(hip)
		hip.add_child(_mi(parts["thigh"]))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.17 * S, 0)
		hip.add_child(knee)
		knee.add_child(_mi(parts["shin"]))
		_hips.append(hip)
		_knees.append(knee)
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.2 * S, 0.74 * S, 0)
		_body.add_child(arm)
		arm.add_child(_mi(parts["arm_l" if side < 0 else "arm_r"]))
		_arms.append(arm)
	_body.add_child(_mi(parts["marker"]))


func _mi(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


## Call every frame with where the body is. `on_floor`: 1 on the ground,
## 0 in the air, -1 unknown (someone else's player: judged from movement).
func animate(delta: float, pos: Vector3, on_floor := -1) -> void:
	if delta <= 0.0:
		return
	if _last == Vector3.INF:
		_last = pos
	var v := (pos - _last) / delta
	_last = pos
	var speed := Vector2(v.x, v.z).length()
	_amount = lerpf(_amount, clampf(speed / 4.0, 0.0, 1.0), 1.0 - exp(-10.0 * delta))
	_phase = fmod(_phase + speed / (0.55 * S) * PI * delta, TAU)
	var a := _amount
	var swing := sin(_phase)
	for i in 2:
		var s := swing if i == 0 else -swing
		_hips[i].rotation.x = deg_to_rad(32.0) * s * a
		_knees[i].rotation.x = -deg_to_rad(48.0) * maxf(0.0, sin(_phase + (0.0 if i == 0 else PI) - 0.9)) * a
		_arms[i].rotation.x = deg_to_rad(10.0) * -s * a
	# Bob up on each step, roll a touch side to side.
	var bob := absf(sin(_phase)) * 0.06 * a
	_body.position.y = bob
	_body.rotation.z = deg_to_rad(5.5) * swing * a
	_head.rotation.z = -deg_to_rad(3.0) * swing * a
	# Jumping: stretch going up, squash on landing, springing back.
	var flying := on_floor == 0 if on_floor >= 0 else absf(v.y) > 0.6
	if flying and v.y > 1.5:
		_squash = -0.12
	if _air and not flying:
		_squash = 0.2
		_squash_v = 0.0
	_air = flying
	# A damped spring, stepped in small slices so a slow frame can't blow it up.
	var left := minf(delta, 0.25)
	while left > 0.0:
		var h := minf(left, 1.0 / 120.0)
		_squash_v += (-_squash * 180.0 - _squash_v * 14.0) * h
		_squash += _squash_v * h
		left -= h
	_squash = clampf(_squash, -0.25, 0.3)
	var sy := 1.0 - _squash
	var sxz := 1.0 + _squash * 0.6
	_body.scale = Vector3(sxz, sy, sxz)


# ---------------------------------------------------------------- meshes --

static func _parts(shirt: Color) -> Dictionary:
	var key := shirt.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var boot := shirt.darkened(0.45)
	var out := {}
	# Torso: shirt under denim overalls with a bib, straps and gold buttons.
	var t := _begin()
	_ellipsoid(t, Vector3(0, 0.64, 0), Vector3(0.2, 0.2, 0.16), shirt)
	_ellipsoid(t, Vector3(0, 0.56, 0), Vector3(0.205, 0.14, 0.165), DENIM)
	_box(t, Vector3(0, 0.68, -0.15), Vector3(0.17, 0.14, 0.04), DENIM)
	for sx in [-0.1, 0.1]:
		_box(t, Vector3(sx, 0.78, -0.09), Vector3(0.035, 0.03, 0.14), DENIM)
		_ellipsoid(t, Vector3(sx * 0.7, 0.74, -0.172), Vector3(0.02, 0.02, 0.01), Color(0.95, 0.8, 0.3))
	out["torso"] = _end(t)
	# Head (pivot at the neck): skin with a faint blush painted in, hair,
	# eyes with a highlight, a little smile, and the straw hat.
	var h := _begin()
	var c := Vector3(0, 0.24, 0)
	_ellipsoid(h, c, Vector3(0.28, 0.258, 0.266), SKIN, true)
	_ellipsoid(h, c + Vector3(0, 0.08, 0.05), Vector3(0.27, 0.12, 0.26), HAIR)
	for sx in [-0.1, 0.1]:
		_ellipsoid(h, c + Vector3(sx, -0.02, -0.245), Vector3(0.045, 0.06, 0.02), EYE)
		_ellipsoid(h, c + Vector3(sx - 0.012, 0.005, -0.262), Vector3(0.014, 0.016, 0.008), Color.WHITE)
	_ellipsoid(h, c + Vector3(0, -0.1, -0.255), Vector3(0.03, 0.012, 0.01), EYE)
	_cyl(h, c + Vector3(0, 0.16, 0), 0.42, 0.42, 0.03, STRAW)
	_cyl(h, c + Vector3(0, 0.25, 0), 0.22, 0.24, 0.16, STRAW)
	_cyl(h, c + Vector3(0, 0.2, 0), 0.245, 0.245, 0.04, shirt)
	out["head"] = _end(h)
	# A leg: thigh (pivot at the hip), shin and boot (pivot at the knee).
	var th := _begin()
	_capsule(th, Vector3.ZERO, Vector3(0, -0.17, 0), 0.065, DENIM)
	out["thigh"] = _end(th)
	var sh := _begin()
	_capsule(sh, Vector3.ZERO, Vector3(0, -0.16, 0), 0.055, DENIM)
	_ellipsoid(sh, Vector3(0, -0.18, -0.04), Vector3(0.075, 0.06, 0.11), boot)
	out["shin"] = _end(sh)
	# Arms (pivot at the shoulder) reaching forward to hold the marker.
	for side in [-1.0, 1.0]:
		var ar := _begin()
		var hand := Vector3(-side * 0.07, -0.14, -0.24)
		_capsule(ar, Vector3.ZERO, hand, 0.055, shirt)
		_ellipsoid(ar, hand, Vector3(0.06, 0.06, 0.06), SKIN)
		out["arm_l" if side < 0 else "arm_r"] = _end(ar)
	var mk := _begin()
	_box(mk, Vector3(0, 0.6, -0.34), Vector3(0.06, 0.09, 0.28), Color(0.16, 0.17, 0.2))
	_cyl_z(mk, Vector3(0, 0.62, -0.54), 0.025, 0.16, Color(0.16, 0.17, 0.2))
	_ellipsoid(mk, Vector3(0, 0.7, -0.3), Vector3(0.07, 0.06, 0.07), Color(0.98, 0.42, 0.65))
	out["marker"] = _end(mk)
	_meshes[key] = out
	return out


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _end(st: SurfaceTool) -> ArrayMesh:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.6
	var m := st.commit()
	m.surface_set_material(0, _material)
	return m


## A smooth ellipsoid. With `face`, a faint blush is painted into the
## vertex colours on the cheeks.
static func _ellipsoid(st: SurfaceTool, at: Vector3, r: Vector3, col: Color, face := false) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 28 if face else 16
	sm.rings = 14 if face else 8
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in arr[Mesh.ARRAY_INDEX]:
		var p: Vector3 = verts[i] * r * S
		var c := col
		if face:
			for sx in [-0.17, 0.17]:
				var d := Vector2(verts[i].x * r.x - sx, verts[i].y * r.y + 0.09).length()
				if verts[i].z < 0.0:
					c = c.lerp(BLUSH, 0.22 * clampf(1.0 - d / 0.055, 0.0, 1.0))
		st.set_color(c)
		st.set_uv(Vector2.ZERO)
		st.set_normal((norms[i] / r).normalized())
		st.add_vertex(at * S + p)


static func _box(st: SurfaceTool, at: Vector3, half: Vector3, col: Color) -> void:
	var b := BoxMesh.new()
	b.size = half * 2.0 * S
	Props._add(st, b, Transform3D(Basis(), at * S), col)


static func _cyl(st: SurfaceTool, at: Vector3, top: float, bottom: float, h: float, col: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = top * S
	c.bottom_radius = bottom * S
	c.height = h * S
	c.radial_segments = 24
	c.rings = 1
	Props._add(st, c, Transform3D(Basis(), at * S), col)


static func _cyl_z(st: SurfaceTool, at: Vector3, r: float, h: float, col: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r * S
	c.bottom_radius = r * S
	c.height = h * S
	c.radial_segments = 10
	c.rings = 1
	Props._add(st, c, Transform3D(Basis(Vector3.RIGHT, PI / 2), at * S), col)


## A limb segment from `a` to `b` with rounded ends.
static func _capsule(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var c := CapsuleMesh.new()
	var len := a.distance_to(b)
	c.radius = r * S
	c.height = (len + r * 2.0) * S
	c.radial_segments = 12
	c.rings = 4
	var up := (b - a).normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(x, up, x.cross(up))
	Props._add(st, c, Transform3D(basis, (a + b) * 0.5 * S), col)
