class_name Bench
extends Node
## ?bench[=SECONDS]: measures a race (design doc 14.2). Turned on by the
## query flag (with ?autodrive, so a computer drives); it waits for the
## green light, then for SECONDS of racing (default 30) samples the engine's
## counters every frame, at a few moments works out where the draw calls come
## from, and watches for trouble: karts reset onto the road, karts stuck, laps.
## At the end it prints one line, "[bench] {json}", to the console and keeps
## the same object in window.__bench, for tools/bench/bench.mjs (or a person
## on a real device, who can copy it from the screen).

const SPOTS := 4          # draw breakdowns taken during the run

signal completed(result: Dictionary)

var context: BenchmarkContext
var publish_result := true  # QualityBench combines samples into one report.
var use_wall_duration := false
var external_window := false
var segment_from_m := 0.0
var segment_to_m := 0.0
var _window_complete := false
var seconds := 30.0
var wall_limit := 120.0   # real seconds after the green light; slow machines stop early ("partial")

var _t := 0.0
var _frames := 0
var _draws := 0.0
var _draws_max := 0
var _objects := 0.0
var _prims := 0.0
var _prims_max := 0
var _phys := 0.0
var _proc := 0.0
var _frame_ms: Array[float] = []
var _resets := {}         # kart name -> count
var _reasons := {}        # why (for the first few)
var _stuck := {}          # kart name -> seconds slower than 2 m/s
var _stuck_now := {}
var _sources := {}        # source -> [draws, nodes]
var _spots_done := 0
var _done := false
var _label: Label
var _wall0 := 0
var _last_frame_us := 0
var _wall_frames: Array[float] = []
var _interruptions_start := 0
var _progress := []
var _start_progress := {}
var _viewport_start := Vector2i.ZERO
var _resized := false
var _quality_start := ""
var _startup_ms := 0.0
var _scale_start := 1.0
var _msaa_start := Viewport.MSAA_DISABLED
var _render_config_changed := false


func _ready() -> void:
	set_process(true)
	_label = Label.new()
	_label.visible = publish_result
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(12, 120)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size = Vector2(700, 0)
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	layer.add_child(_label)


func _process(delta: float) -> void:
	if _done or not context.is_running():
		return
	if _t == 0.0:
		_wall0 = Time.get_ticks_msec()
		_last_frame_us = Time.get_ticks_usec()
		_interruptions_start = _interruptions()
		_start_progress = _player_progress()
		_viewport_start = get_viewport().size
		_quality_start = Controls.quality_name().to_lower()
		_scale_start = get_viewport().scaling_3d_scale
		_msaa_start = get_viewport().msaa_3d
		if OS.has_feature("web"):
			_startup_ms = float(JavaScriptBridge.eval("window.__benchStartedAt = performance.now()", true))
		for k: Kart in context.karts:
			_resets[k.display_name] = 0
			_stuck[k.display_name] = 0.0
			_stuck_now[k.display_name] = 0.0
			k.respawned.connect(_on_respawn.bind(k))
	var now_us := Time.get_ticks_usec()
	if _frames > 0:
		_wall_frames.append((now_us - _last_frame_us) / 1000.0)
	_last_frame_us = now_us
	_resized = _resized or get_viewport().size != _viewport_start
	_render_config_changed = _render_config_changed or get_viewport().msaa_3d != _msaa_start or not is_equal_approx(get_viewport().scaling_3d_scale, _scale_start)
	_t += delta
	_frames += 1
	var p := Performance
	var d := int(p.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var pr := int(p.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_draws += d
	_draws_max = maxi(_draws_max, d)
	_prims += pr
	_prims_max = maxi(_prims_max, pr)
	_objects += p.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_phys += p.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_proc += p.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_frame_ms.append(delta * 1000.0)
	for k: Kart in context.karts:
		var n := k.display_name
		if k.linear_velocity.length() < 2.0 and not k.finished:
			_stuck_now[n] += delta
			_stuck[n] = maxf(_stuck[n], _stuck_now[n])
		else:
			_stuck_now[n] = 0.0
	var wall := (Time.get_ticks_msec() - _wall0) / 1000.0
	var elapsed := wall if use_wall_duration else _t
	var fraction := elapsed / seconds
	if external_window:
		fraction = inverse_lerp(segment_from_m, segment_to_m, context.track.offset_of(context.player_kart.global_position))
	if _spots_done < SPOTS and fraction >= (_spots_done + 0.5) / SPOTS:
		_spots_done += 1
		_progress.append(_player_progress())
		_breakdown()
	_label.text = "bench %.0f / %.0f s" % [_t, seconds]
	if (not external_window and elapsed >= seconds) or wall >= wall_limit:
		_finish()


func has_samples() -> bool:
	return _frames > 1


func finish_window() -> void:
	if _done or not has_samples():
		return
	_window_complete = true
	_finish()


func _on_respawn(k: Kart) -> void:
	_resets[k.display_name] += 1
	if _reasons.size() < 6:
		_reasons["%s@%.0fs" % [k.display_name, _t]] = k.respawn_reason


## What the race camera draws right now, by source: each visible mesh's
## surfaces (twice with a second pass), after frustum and distance culling.
## An estimate of the engine's opaque pass; shadows and the sky aren't in it.
func _breakdown() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var planes := cam.get_frustum()
	var eye := cam.global_position
	var stack: Array[Node] = [context.scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var g := n as GeometryInstance3D
		if g == null or not g.is_visible_in_tree():
			continue
		var draws := 0
		var what := ""
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			var m: Mesh = (g as MeshInstance3D).mesh
			draws = m.get_surface_count()
			what = _mesh_label(m, g.material_override if g.material_override else m.surface_get_material(0))
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh and (g as MultiMeshInstance3D).multimesh.mesh:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm.visible_instance_count == 0 or mm.instance_count == 0:
				continue
			draws = mm.mesh.get_surface_count()
			what = "scatter " + _mesh_label(mm.mesh, g.material_override)
		elif g is Label3D or g is SpriteBase3D:
			draws = 1
			what = g.get_class()
		elif g is GPUParticles3D or g is CPUParticles3D:
			draws = 1
			what = "particles"
		else:
			continue
		var box := g.global_transform * g.get_aabb()
		var c := box.get_center()
		var e := box.size * 0.5
		var inside := true
		for pl in planes:
			if pl.distance_to(c) > absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z:
				inside = false
				break
		if not inside:
			continue
		if g.visibility_range_end > 0.0 and c.distance_to(eye) - e.length() > g.visibility_range_end:
			continue
		if g.material_overlay or (g.material_override and g.material_override.next_pass):
			draws *= 2
		var key := _owner_of(g) + ": " + what
		var t: Array = _sources.get(key, [0, 0])
		t[0] += draws
		t[1] += 1
		_sources[key] = t


func _owner_of(n: Node) -> String:
	var p := n.get_parent()
	while p != null and p != context.scene:
		if p is Kart:
			return "kart"
		var s: Script = p.get_script()
		if s and s.get_global_name() != "":
			return String(s.get_global_name())
		p = p.get_parent()
	return "main"


func _mesh_label(m: Mesh, mat: Material) -> String:
	var path := m.resource_path
	if path.contains(".glb") or path.contains(".gltf"):
		return path.get_file().get_slice("::", 0).get_basename()
	if m.resource_name != "":
		return m.resource_name
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		return (mat as ShaderMaterial).shader.resource_path.get_file().get_basename()
	if m is PrimitiveMesh:
		return m.get_class()
	return "mesh"


func _finish() -> void:
	_done = true
	var f := float(_frames)
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var laps := {}
	var total_resets := 0
	for k: Kart in context.karts:
		laps[k.display_name] = maxi(0, k.lap - 1)
		total_resets += int(_resets[k.display_name])
	var worst_stuck := 0.0
	for n in _stuck:
		worst_stuck = maxf(worst_stuck, _stuck[n])
	var src := []
	for key in _sources:
		src.append([key, int(round(_sources[key][0] / float(maxi(1, _spots_done)))), int(round(_sources[key][1] / float(maxi(1, _spots_done))))])
	src.sort_custom(func(a, b): return a[1] > b[1])
	var wall_stats := frame_stats(_wall_frames)
	var vp := get_viewport()
	var browser_info: Variant = {}
	if OS.has_feature("web"):
		browser_info = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify({user_agent:navigator.userAgent,dpr:devicePixelRatio,css_size:[innerWidth,innerHeight],canvas_size:[document.querySelector('canvas').width,document.querySelector('canvas').height]})", true)))
	var out := {
		"schema": 2,
		"duration_clock": "track_half" if external_window else "wall" if use_wall_duration else "simulation",
		"startup_to_green_ms": _startup_ms,
		"requested_seconds": seconds,
		"valid": _interruptions() == _interruptions_start and not _resized and not _render_config_changed and _quality_start == Controls.quality_name().to_lower(),
		"render_config_changed": _render_config_changed,
		"interruptions": _interruptions() - _interruptions_start,
		"resized": _resized,
		"godot_version": Engine.get_version_info()["string"],
		"browser": browser_info,
		"viewport_size": [vp.size.x, vp.size.y],
		"scale_3d": vp.scaling_3d_scale,
		"msaa_samples": [0, 2, 4, 8][vp.msaa_3d],
		"render_size_estimate": [int(vp.size.x * vp.scaling_3d_scale), int(vp.size.y * vp.scaling_3d_scale)],
		"kart_count": context.karts.size(),
		"control_mode": "autodrive",
		"seeds": {"player_bot": 99, "rival_bots": [3, 4, 5], "items": 99, "track": 42},
		"start_progress": _start_progress,
		"end_progress": _player_progress(),
		"progress_samples": _progress,
		"wall_frames_ms": _wall_frames,
		"wall_frame_stats": wall_stats,
		"wall_race_s": (Time.get_ticks_msec() - _wall0) / 1000.0,
		"track": context.track.layout,
		"quality": Controls.quality_name().to_lower(),
		"seconds": snappedf(_t, 0.1),
		"partial": not _window_complete if external_window else ((Time.get_ticks_msec() - _wall0) / 1000.0 if use_wall_duration else _t) < seconds - 0.5,
		"frames": _frames,
		"simulation_fps": snappedf(f / _t, 0.1),
		"simulation_frame_p50": snappedf(sorted[sorted.size() / 2], 0.1),
		"simulation_frame_p95": snappedf(sorted[int(sorted.size() * 0.95)], 0.1),
		"draws": int(_draws / f),
		"draws_max": _draws_max,
		"objects": int(_objects / f),
		"tris_k": int(_prims / f / 1000.0),
		"tris_k_max": int(_prims_max / 1000.0),
		"physics_ms": snappedf(_phys / f, 0.01),
		"process_ms": snappedf(_proc / f, 0.01),
		"resets": total_resets,
		"reset_reasons": _reasons,
		"stuck_s": snappedf(worst_stuck, 0.1),
		"player_completed_laps": maxi(0, int(context.player_kart.lap) - 1),
		"laps": laps,
		"sources": src.slice(0, 25),
	}
	var json := JSON.stringify(out)
	if publish_result:
		print("[bench] ", json)
	if publish_result and OS.has_feature("web"):
		JavaScriptBridge.eval("window.__bench = " + json + ";", true)
	_label.text = "bench %s %s: %.1f wall fps (p95 %.0f ms, p99 %.0f ms)\n%d draws, %dk tris, process %.1f ms, physics %.1f ms, %d completed laps\n%s" % [
		out.track, out.quality, wall_stats.fps, wall_stats.p95, wall_stats.p99,
		out.draws, out.tris_k, out.process_ms, out.physics_ms, out.player_completed_laps,
		"INVALID: interrupted, resized or quality changed" if not out.valid else "PARTIAL run" if out.partial else "Complete sample"]
	completed.emit(out)


func _interruptions() -> int:
	if not OS.has_feature("web"):
		return 0
	return int(JavaScriptBridge.eval("(window.racingMobile && window.racingMobile.interruptions) || 0", true))


func _player_progress() -> Dictionary:
	var k: Kart = context.player_kart
	return {"seconds": snappedf(_t, 0.01), "lap_counter": k.lap,
		"next_checkpoint": k.next_checkpoint, "offset_m": snappedf(context.track.offset_of(k.global_position), 0.1),
		"position": [snappedf(k.global_position.x, 0.1), snappedf(k.global_position.y, 0.1), snappedf(k.global_position.z, 0.1)]}


static func frame_stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var out := {"fps": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0, "over_33ms": 0, "over_50ms": 0, "over_100ms": 0}
	if sorted.is_empty():
		return out
	var total := 0.0
	for ms in values:
		total += ms
		for threshold in [33, 50, 100]:
			if ms > threshold:
				out["over_%dms" % threshold] += 1
	out.fps = snappedf(1000.0 * values.size() / maxf(total, 0.001), 0.1)
	for percentile in [50, 95, 99]:
		out["p%d" % percentile] = snappedf(sorted[maxi(0, int(ceil(sorted.size() * percentile / 100.0)) - 1)], 0.1)
	out.max = snappedf(sorted[-1], 0.1)
	return out
