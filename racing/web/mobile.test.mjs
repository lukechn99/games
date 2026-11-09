import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

test('browser interruptions clear input even without motion sensor support', () => {
  const window = new EventTarget()
  const document = new EventTarget()
  document.hidden = false
  window.racingTilt = { deg: 20 }
  vm.runInNewContext(readFileSync(new URL('./mobile.js', import.meta.url), 'utf8'), { window, document })
  const states = []
  window.racingMobile.subscribe((s) => states.push(s))
  window.dispatchEvent(new Event('blur'))
  assert.equal(states.at(-1), true)
  assert.equal(window.racingTilt.deg, 0)
  document.hidden = true
  document.dispatchEvent(new Event('visibilitychange'))
  window.dispatchEvent(new Event('focus'))
  assert.equal(states.at(-1), true, 'focus must not resume a still-hidden page')
  document.hidden = false
  document.dispatchEvent(new Event('visibilitychange'))
  assert.equal(states.at(-1), false)
  const before = states.length
  document.dispatchEvent(new Event('touchcancel'))
  assert.equal(states.length, before + 1)
  window.dispatchEvent(new Event('pagehide'))
  assert.equal(states.at(-1), true)
  window.dispatchEvent(new Event('pageshow'))
  assert.equal(states.at(-1), false)
})
