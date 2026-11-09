import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

function page({ physical = 'portrait-primary', legacy, coarse = true } = {}) {
  const window = new EventTarget()
  window.orientation = legacy
  window.visualViewport = Object.assign(new EventTarget(), { width: 390, height: 844, offsetLeft: 0, offsetTop: 0 })
  const orientation = physical === null ? undefined : Object.assign(new EventTarget(), { type: physical })
  const queries = {
    '(pointer: coarse)': Object.assign(new EventTarget(), { matches: coarse }),
    '(orientation: portrait)': Object.assign(new EventTarget(), { matches: true }),
  }
  const elements = []
  const document = Object.assign(new EventTarget(), {
    head: { appendChild() {} }, body: { appendChild(e) { elements.push(e) } },
    createElement() { return { style: {}, setAttribute() {} } },
  })
  vm.runInNewContext(readFileSync(new URL('./landscape.js', import.meta.url), 'utf8'), {
    window, document, screen: { orientation }, matchMedia: (query) => queries[query], innerWidth: 390, innerHeight: 844,
  })
  return { window, orientation, queries, card: elements[0] }
}

test('physical rotation hides the prompt before an iframe viewport catches up', () => {
  const p = page()
  assert.equal(p.card.hidden, false)
  p.orientation.type = 'landscape-primary'
  p.orientation.dispatchEvent(new Event('change'))
  assert.equal(p.card.hidden, true)
  assert.equal(p.queries['(orientation: portrait)'].matches, true, 'layout still has the old portrait size')
  p.orientation.type = 'portrait-primary'
  p.orientation.dispatchEvent(new Event('change'))
  assert.equal(p.card.hidden, false)
})
test('prompt dimensions follow visible viewport changes without timers', () => {
  const p = page()
  Object.assign(p.window.visualViewport, { width: 320, height: 480, offsetTop: 12 })
  p.window.visualViewport.dispatchEvent(new Event('resize'))
  assert.deepEqual(p.card.style, { width: '320px', height: '480px', left: '0px', top: '12px' })
})
test('legacy iOS orientation works independently of motion-sensor support', () => {
  const p = page({ physical: null, legacy: 0 })
  assert.equal(p.card.hidden, false)
  p.window.orientation = -90
  p.window.dispatchEvent(new Event('orientationchange'))
  assert.equal(p.card.hidden, true)
})
test('media-query fallback works and desktop needs no rotation prompt', () => {
  const p = page({ physical: null })
  p.queries['(orientation: portrait)'].matches = false
  p.queries['(orientation: portrait)'].dispatchEvent(new Event('change'))
  assert.equal(p.card.hidden, true)
  assert.equal(page({ coarse: false }).card.hidden, true)
})
