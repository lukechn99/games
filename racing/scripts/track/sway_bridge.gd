class_name SwayBridge
extends Node3D
## The rope bridge on Mining Mountain: a plank deck that sags in the middle
## and sways side to side in the wind, most in the middle. It's built from
## short sections, each a moving solid body, so karts ride on it (and slide
## off if they don't steer against the sway).

const WIDTH := 6.0
const SWAY := 1.6        # metres side to side, in the middle
const ROLL := 0.09       # radians of tilt, in the middle
const SAG := 1.8         # metres the middle hangs down
const PERIOD := 4.5      # seconds for one sway

var _parts: Array[Dictionary] = []   # {body, rest: Transform3D, u}
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
	var wood := StandardMaterial3D.new()
	wood.albedo_color = MineTrack.WOOD
	wood.albedo_texture = load(Palette.TEX_DIR + "wood.png")
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3.ONE / 1.5
	wood.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.82, 0.7, 0.48)
	rope.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var step := 3.0
	d = d0
	while d < d1:
		var fa := t.branch_frame(d, i)
		var fb := t.branch_frame(minf(d + step, d1), i)
		var u := (d + step * 0.5 - d0) / maxf(1.0, d1 - d0)
		var mid := (fa.origin + fb.origin) * 0.5 + Vector3.UP * (0.04 - SAG * sin(PI * u))
		var fwd := fb.origin - fa.origin
		fwd.y = 0.0
		var basis := Basis.looking_at(fwd.normalized(), Vector3.UP)
		var len := fwd.length() + 0.15
		var body := AnimatableBody3D.new()
		body.sync_to_physics = true
		body.set_meta("surface", "asphalt")
		body.set_meta("floor", true)
		body.transform = Transform3D(basis, mid)
		add_child(body)
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WIDTH, 0.3, len)
		col.shape = box
		col.position = Vector3(0, -0.15, 0)
		body.add_child(col)
		# Planks with gaps, two rope rails on posts.
		for k in 3:
			var plank := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(WIDTH, 0.18, len / 3.0 - 0.12)
			plank.mesh = pb
			plank.material_override = wood
			plank.position = Vector3(0, -0.09, -len * 0.5 + len / 6.0 + k * len / 3.0)
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
		_parts.append({"body": body, "rest": body.transform, "u": u})
		d += step


func _physics_process(delta: float) -> void:
	_t += delta
	var w := sin(_t * TAU / PERIOD) + 0.35 * sin(_t * TAU / (PERIOD * 0.43) + 1.0)
	for p in _parts:
		var rest: Transform3D = p["rest"]
		var k := sin(PI * float(p["u"]))
		var xf := rest
		xf.origin += rest.basis.x * w * SWAY * k
		xf.basis = rest.basis.rotated(rest.basis.z, -w * ROLL * k)
		(p["body"] as AnimatableBody3D).transform = xf
