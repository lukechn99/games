class_name ShaderWarmup
extends Node3D
## Draws one tiny copy of every mesh and material in the scene, for a few
## frames right in front of the camera, while a menu covers the screen
## (design doc 14). The browser renderer compiles each shader the first time
## it is drawn, which froze the game for a moment whenever something new came
## into view: the tunnel, the crowd, boost flames, dust. Doing it up front
## moves all of those hitches to the menu, where nobody notices.
##
## A lamp sits next to the copies, because things lit by a lamp use a
## different shader (that's why the tunnel hitched the first time).

const FRAMES := 4

var _left := FRAMES


func warm(root: Node, camera: Camera3D) -> void:
	var seen := {}
	var stack: Array[Node] = [root]
	var i := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mesh: Mesh = null
		var mats: Array[Material] = []
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mesh = mi.mesh
			if mi.material_override:
				mats.append(mi.material_override)
		elif n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			if mmi.multimesh:
				mesh = mmi.multimesh.mesh
			if mmi.material_override:
				mats.append(mmi.material_override)
		elif n is CPUParticles3D:
			var p := n as CPUParticles3D
			mesh = p.mesh
			if p.material_override:
				mats.append(p.material_override)
		if mesh == null:
			continue
		var key := "%d|%s" % [mesh.get_instance_id(), mats.map(func(m): return m.get_instance_id())]
		if seen.has(key):
			continue
		seen[key] = true
		var copy := MeshInstance3D.new()
		copy.mesh = mesh
		if not mats.is_empty():
			copy.material_override = mats[0]
			if mats[0].next_pass:
				pass  # next_pass compiles with its owner
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Spread on a little grid in front of the camera, shrunk to a dot.
		var aabb := mesh.get_aabb()
		var s := 0.05 / maxf(0.01, aabb.get_longest_axis_size())
		copy.transform = Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3((i % 20) * 0.06 - 0.6, (i / 20) * 0.06 - 0.3, -2.0) - aabb.get_center() * s)
		add_child(copy)
		i += 1
	var lamp := OmniLight3D.new()
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, 0, -1.5)
	add_child(lamp)
	camera.add_child(self)
	print("shader warm-up: %d meshes" % i)


func _process(_delta: float) -> void:
	_left -= 1
	if _left <= 0:
		queue_free()
