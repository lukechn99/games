class_name MapReview
extends Node
## Developer-only visual inspection: north-up orthographic surfaces, optional
## route guides and an oblique view to reveal missing terrain walls.

var track: Track
var camera: Camera3D
var target := Vector3.ZERO
var span := 400.0
var oblique := false
var _guides: Node3D
var _label: Label
var _dragging := false
var _preset := "whole"


func setup(query: String) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 3000.0
	# A high inspection camera must not hide terrain through gameplay's
	# distance culling. Include scenery placed on deferred ready frames.
	await get_tree().physics_frame
	await get_tree().physics_frame
	for geometry: GeometryInstance3D in track.find_children("*", "GeometryInstance3D", true, false):
		geometry.visibility_range_begin = 0.0
		geometry.visibility_range_end = 0.0
	_guides = Node3D.new()
	add_child(_guides)
	_route(false, Color(1.0, 0.35, 0.05))
	for i in track.branches.size():
		_route(true, Color(0.05, 0.95, 1.0), i)
	_guides.visible = query.contains("guides=on")
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.visible = not query.contains("clean")
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	oblique = query.contains("oblique")
	preset("entry" if query.contains("map=entry") else "exit" if query.contains("map=exit") else "whole")
	# Publish readiness after warm-up copies have disappeared, rather than
	# guessing a screenshot delay on a slow software renderer.
	for i in 8:
		await get_tree().process_frame
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__mapReady = true", true)


func preset(which: String) -> void:
	_preset = which
	if track.layout == "frost" and which != "whole":
		var lake := FrostTrack.lake_span(track)
		var bi := FrostTrack.detour_branch(track)
		var d: float = track.branches[bi]["from" if which == "entry" else "to"]
		var shore := track.transform_at(lake.x if which == "entry" else lake.y).origin
		target = track.transform_at(d).origin.lerp(shore, 0.5)
		span = 135.0
	else:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var d := 0.0
		while d < track.length:
			var p := track.transform_at(d).origin
			lo = lo.min(p)
			hi = hi.max(p)
			for i in track.branches.size():
				p = track.branch_frame(d, i).origin
				lo = lo.min(p)
				hi = hi.max(p)
			d += 2.0
		target = (lo + hi) * 0.5
		var size := camera.get_viewport().get_visible_rect().size
		span = maxf(hi.z - lo.z + 70.0, (hi.x - lo.x + 70.0) * size.y / maxf(size.x, 1.0))
	_update_camera()


func _update_camera() -> void:
	camera.size = span
	camera.global_position = target + Vector3(0, 650, 450 if oblique else 0)
	camera.look_at(target, Vector3.UP if oblique else Vector3.FORWARD)
	_label.text = "%s map · %s · guides %s\nDrag / arrows: pan · wheel / +/-: zoom · O: top/oblique · L: route guides\n1: whole track · 2/3: Frost lake entry/exit · orange: main · cyan: detour" % [track.layout, "oblique" if oblique else "top", "on" if _guides.visible else "off"]
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__mapState = " + JSON.stringify({"preset": _preset, "oblique": oblique, "guides": _guides.visible, "span": span, "x": target.x, "z": target.z}), true)


func _unhandled_input(event: InputEvent) -> void:
	if _label == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			span = clampf(span * (0.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.85), 25.0, 1600.0)
	elif event is InputEventMouseMotion and _dragging:
		var px := camera.get_viewport().get_visible_rect().size.y
		target -= Vector3(event.relative.x, 0, event.relative.y) * span / maxf(px, 1.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: preset("whole")
			KEY_2: preset("entry")
			KEY_3: preset("exit")
			KEY_O: oblique = not oblique
			KEY_L: _guides.visible = not _guides.visible
			KEY_EQUAL, KEY_PLUS: span = maxf(25.0, span * 0.85)
			KEY_MINUS: span = minf(1600.0, span / 0.85)
			KEY_LEFT: target.x -= span * 0.08
			KEY_RIGHT: target.x += span * 0.08
			KEY_UP: target.z -= span * 0.08
			KEY_DOWN: target.z += span * 0.08
			_: return
	else:
		return
	_update_camera()
	get_viewport().set_input_as_handled()


func _route(branch: bool, color: Color, i := 0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start: float = track.branches[i]["from"] if branch else 0.0
	var end: float = track.branches[i]["to"] if branch else track.length
	var d := start
	while d < end:
		var a := track.branch_frame(d, i) if branch else track.transform_at(d)
		var b := track.branch_frame(minf(d + 2.0, end), i) if branch else track.transform_at(minf(d + 2.0, end))
		for p in [a.origin - a.basis.x * 0.35, b.origin + b.basis.x * 0.35, a.origin + a.basis.x * 0.35,
				a.origin - a.basis.x * 0.35, b.origin - b.basis.x * 0.35, b.origin + b.basis.x * 0.35]:
			st.add_vertex(p + Vector3.UP * 0.5)
		d += 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guides.add_child(mi)
