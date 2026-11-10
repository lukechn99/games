class_name MediumBench
extends QualityBench
## Phone-only evidence decides the next preset change. Each candidate changes
## one feature, keeps actual Medium materials/detail, and samples both halves.

const VARIANTS := [0, 1, 2, 2, 1, 0]
const LABELS := ["Medium base", "Medium AA off", "Medium 900k cap"]
const PIXEL_CAP := 900000.0


func _quality_for_phase(_index: int) -> int:
	return Controls.Quality.MEDIUM


func _apply_phase(index: int) -> void:
	# The game's normal quality signal restores current Medium settings
	# before each single-variable experiment. No duplicated preset values,
	# cached viewport dimensions or writes to saved preferences.
	Controls.set_quality(Controls.Quality.MEDIUM, false)
	var vp := get_viewport()
	if VARIANTS[index] == 1:
		vp.msaa_3d = Viewport.MSAA_DISABLED
	elif VARIANTS[index] == 2:
		var pixels := float(vp.size.x * vp.size.y)
		vp.scaling_3d_scale = minf(vp.scaling_3d_scale, sqrt(PIXEL_CAP / maxf(pixels, 1.0)))


func _phase_label(index: int) -> String:
	return LABELS[VARIANTS[index]]


func _mode() -> String:
	return "medium_ablation"


func _report_name() -> String:
	return "Medium feature test"


func _result_line(r: Dictionary) -> String:
	var size: Array = r.render_size_estimate
	return "L%d H%d %s: %.1f fps | p95 %.0f, p99 %.0f ms | %dk px, AA%d" % [
		r.lap, r.half, r.feature_profile, r.wall_frame_stats.fps,
		r.wall_frame_stats.p95, r.wall_frame_stats.p99,
		int(size[0] * size[1] / 1000), r.msaa_samples]
