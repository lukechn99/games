// Compare only equivalent scenarios and sampled route coverage. Build hashes
// intentionally differ when testing an optimization; tool/device settings may not.
export function baselineEligible(x) {
  return x?.schema === 2 && !x.failed && !x.partial && x.valid === true && x.errors === 0
}

export function incompatibilities(x, baseline) {
  if (!baseline) return ['no baseline']
  if (!baselineEligible(x) || !baselineEligible(baseline)) return ['incomplete, invalid, errored or legacy result']
  const reasons = []
  for (const [field, legacy] of [['duration_clock', 'simulation'], ['sampling_mode', 'single_quality']]) {
    if ((x[field] || legacy) !== (baseline[field] || legacy)) reasons.push(`${field} differs`)
  }
  for (const field of ['track', 'quality', 'feature_profile', 'msaa_samples', 'route', 'segment_from_m', 'segment_to_m', 'measured_from_m', 'requested_seconds', 'godot_version', 'kart_count', 'control_mode', 'seeds', 'viewport_size', 'scale_3d', 'browser', 'browser_version', 'runner']) {
    if (JSON.stringify(x[field]) !== JSON.stringify(baseline[field])) reasons.push(`${field} differs`)
  }
  const xs = [x.start_progress, ...x.progress_samples, x.end_progress]
  const bs = [baseline.start_progress, ...baseline.progress_samples, baseline.end_progress]
  if (xs.length !== bs.length || xs.some((s, i) => {
    const b = bs[i]
    return !b || s.lap_counter !== b.lap_counter || s.next_checkpoint !== b.next_checkpoint ||
      Math.abs(s.seconds - b.seconds) > 0.5 || Math.hypot(...s.position.map((p, j) => p - b.position[j])) > 20
  })) reasons.push('sampled route coverage differs')
  return reasons
}

/** What a baseline keeps of a run: everything but the bulky detail. */
export function baselineRecord(x) {
  const omit = new Set(['sources', 'error_lines', 'reset_reasons', 'wall_frames_ms'])
  return Object.fromEntries(Object.entries(x).filter(([key]) => !omit.has(key)))
}
