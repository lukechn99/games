import { test } from 'node:test'
import assert from 'node:assert/strict'
import { baselineEligible, incompatibilities } from './compare.mjs'

const progress = { seconds: 0, lap_counter: 1, next_checkpoint: 1, position: [0, 0, 0] }
const run = () => ({ schema: 2, partial: false, valid: true, errors: 0, browser: { dpr: 1 }, start_progress: progress, end_progress: progress, progress_samples: [progress] })
test('changed builds may be compared, changed browser/DPR may not', () => {
  assert.deepEqual(incompatibilities({ ...run(), build: 'new' }, { ...run(), build: 'old' }), [])
  assert.ok(incompatibilities({ ...run(), browser: { dpr: 3 } }, run()).includes('browser differs'))
})
test('partial, backgrounded, errored and old runs cannot become baselines', () => {
  for (const patch of [{ partial: true }, { valid: false }, { errors: 1 }, { schema: 1 }, { failed: 'timeout' }]) {
    const bad = { ...run(), ...patch }
    assert.equal(baselineEligible(bad), false)
    assert.ok(incompatibilities(run(), bad).length)
  }
})
test('same duration with a different route is not comparable', () => {
  const alternate = { ...run(), progress_samples: [{ ...progress, position: [50, 0, 0] }] }
  assert.ok(incompatibilities(alternate, run()).includes('sampled route coverage differs'))
})
test('sweep samples and wall-duration windows cannot masquerade as fixed-quality baselines', () => {
  assert.ok(incompatibilities({ ...run(), duration_clock: 'wall' }, run()).includes('duration_clock differs'))
  assert.ok(incompatibilities({ ...run(), sampling_mode: 'quality_sweep' }, run()).includes('sampling_mode differs'))
  assert.deepEqual(incompatibilities({ ...run(), duration_clock: 'simulation', sampling_mode: 'single_quality' }, run()), [])
})
