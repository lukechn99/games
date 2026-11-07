class_name SwayBridge
extends Node3D
## The rope bridge on Mining Mountain: a plank deck that sags in the middle
## and sways side to side in the wind, most in the middle. Karts weigh it
## down: the planks under a kart dip, and spring back with a bounce when it
## has gone. It's built from short sections, each a moving solid body, so
## karts ride on it (and slide off if they don't steer against the sway).

const WIDTH := 6.0
const SWAY := 1.6        # metres side to side, in the middle
const ROLL := 0.09       # radians of tilt, in the middle
const SAG := 5.0         # metres the middle hangs down
const DIP := 0.55        # metres a kart presses the planks down
const SPRING := 38.0     # how stiff the ropes are when they bounce back
const DAMP := 5.0
const PERIOD := 4.5      # seconds for one sway

var _parts: Array[Dictionary] = []   # {body, rest: Transform3D, u, dip, vel, len}
var _t := 0.0


func build(t: Track, i: int) -> void:
	var b: Dictionary = t.branches[i]
	var from: float = b["from"]
	var to: float = b["to"]
	# The deck spans where the bridge is apart from the main road.
	var d0 := from
	var d1 := to
	var d := from
	while d < to:
		if absf(t.branch_offset(d, i)) >= Track.BRANCH_SPLIT:
			d0 = d
			break
		d += 1.0
	d = to
	while d > from:
		if absf(t.branch_offset(d, i)) >= Track.BRANCH_SPLIT:
			d1 = d
			break
		d -= 1.0
	# Posts and rails in plain wood; the deck in baked planks (boards with
	# gaps, nails and grain, tools/make_surfaces.py), projected in each
	# section's own frame so the boards always run across the deck.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = MineTrack.WOOD
	wood.albedo_texture = load(Palette.TEX_DIR + "wood.png")
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3.ONE / 1.5
	wood.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var deck := StandardMaterial3D.new()
	deck.albedo_color = MineTrack.WOOD.lightened(0.15)
	deck.albedo_texture = load(Palette.TEX_DIR + "surf_planks.png")
	deck.uv1_triplanar = true
	deck.uv1_world_triplanar = false
	deck.uv1_scale = Vector3.ONE / 4.0
	deck.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	deck.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	Palette.add_relief(deck, "surf_planks", 1.0)
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.82, 0.7, 0.48)
	rope.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var step := 3.0
	d = d0
	while d < d1:
		var fa := t.branch_frame(d, i)
		var fb := t.branch_frame(minf(d + step, d1), i)
		var u := (d + step * 0.5 - d0) / maxf(1.0, d1 - d0)
		# Each section follows the curve of the sag, so the deck is a smooth
		# hanging curve rather than steps.
		var ua := (d - d0) / maxf(1.0, d1 - d0)
		var ub := (minf(d + step, d1) - d0) / maxf(1.0, d1 - d0)
		var end_a := fa.origin + Vector3.UP * (0.04 - SAG * sin(PI * ua))
		var end_b := fb.origin + Vector3.UP * (0.04 - SAG * sin(PI * ub))
		var mid := (end_a + end_b) * 0.5
		var fwd := end_b - end_a
		var basis := Basis.looking_at(fwd.normalized(), Vector3.UP)
		var len := fwd.length() + 0.15
		var body := AnimatableBody3D.new()
		body.sync_to_physics = true
		body.set_meta("surface", "asphalt")
		body.set_meta("floor", true)
		body.set_meta("deck", true)   # karts on it aren't "off the road" (kart.gd)
		body.transform = Transform3D(basis, mid)
		add_child(body)
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WIDTH, 0.3, len)
		col.shape = box
		col.position = Vector3(0, -0.15, 0)
		body.add_child(col)
		# The deck, then two rope rails on posts.
		var plank := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(WIDTH, 0.18, len - 0.04)
		plank.mesh = pb
		plank.material_override = deck
		plank.position = Vector3(0, -0.09, 0)
		body.add_child(plank)
		for s: float in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.16, 1.2, 0.16)
			post.mesh = pm
			post.material_override = wood
			post.position = Vector3(s * (WIDTH * 0.5 + 0.1), 0.6, -len * 0.5)
			body.add_child(post)
			var line := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.05
			lm.bottom_radius = 0.05
			lm.height = len
			line.mesh = lm
			line.material_override = rope
			line.rotation = Vector3(PI / 2, 0, 0)
			line.position = Vector3(s * (WIDTH * 0.5 + 0.1), 1.1, 0)
			body.add_child(line)
		_parts.append({"body": body, "rest": body.transform, "u": u, "dip": 0.0, "vel": 0.0, "len": len})
		d += step


## True when `pos` is over the deck (or just above or below it): karts here
## are on the bridge, however far below the road line the sag takes them.
func holds(pos: Vector3) -> bool:
	for p in _parts:
		var body: Node3D = p["body"]
		var l: Vector3 = body.global_transform.affine_inverse() * pos
		if absf(l.z) <= float(p["len"]) * 0.5 + 0.2 and absf(l.x) < WIDTH * 0.5 + 0.8 and l.y > -1.2 and l.y < 4.0:
			return true
	return false


## Item crates hover over the middle of the deck and ride with it.
func crate_spots() -> Array:
	if _parts.is_empty():
		return []
	var p: Dictionary = _parts[_parts.size() / 2]
	var out := []
	for x in [-1.8, 0.0, 1.8]:
		out.append({"node": p["body"], "local": Vector3(x, 1.0, 0.0)})
	return out


func _physics_process(delta: float) -> void:
	_t += delta
	var w := sin(_t * TAU / PERIOD) + 0.35 * sin(_t * TAU / (PERIOD * 0.43) + 1.0)
	var karts := get_tree().get_nodes_in_group("karts")
	for p in _parts:
		var rest: Transform3D = p["rest"]
		var k := sin(PI * float(p["u"]))
		# How hard karts are pressing on this section (and its neighbours a
		# little): the planks dip toward that, on springy ropes.
		var press := 0.0
		for kart in karts:
			var l: Vector3 = rest.affine_inverse() * (kart as Node3D).global_position
			if absf(l.x) < WIDTH * 0.5 + 0.5 and l.y > -1.0 and l.y < 2.5:
				press += exp(-pow(l.z / (float(p["len"]) * 1.4), 2.0))
		var target := -DIP * minf(press, 1.6) * clampf(k * 1.6, 0.0, 1.0)
		p["vel"] = float(p["vel"]) + ((target - float(p["dip"])) * SPRING - float(p["vel"]) * DAMP) * delta
		p["dip"] = float(p["dip"]) + float(p["vel"]) * delta
		var xf := rest
		xf.origin += Vector3.UP * float(p["dip"])
		xf.origin += rest.basis.x * w * SWAY * k
		xf.basis = rest.basis.rotated(rest.basis.z, -w * ROLL * k)
		(p["body"] as AnimatableBody3D).transform = xf
