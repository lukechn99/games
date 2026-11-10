import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

function page(track, readyState = 'complete') {
  const element = () => ({ style: {}, children: [], attributes: {}, appendChild(e) { this.children.push(e) }, setAttribute(k, v) { this.attributes[k] = v } })
  const progress = element(), notice = element(), status = element()
  status.children.push(progress, notice)
  const document = Object.assign(new EventTarget(), {
    readyState, head: element(), createElement: element,
    getElementById: id => id === 'status' ? status : null,
  })
  const location = new URL('https://example.com/games/racing/index.html?track=' + track)
  vm.runInNewContext(readFileSync(new URL('./loading.js', import.meta.url), 'utf8'), { document, location, URL, URLSearchParams })
  return { document, status, progress, notice }
}

for (const [track, name] of Object.entries({ meadow: 'Meadow Loop', mine: 'Mining Mountain', frost: 'Frosty Pass' })) {
  test(`${track} uses its own aerial under a project base path`, () => {
    const p = page(track)
    assert.equal(p.document.head.children[0].href, `https://example.com/games/tracks/aerial-${track}.jpg`)
    assert.equal(p.document.title, 'Animal Karts — ' + name)
    assert.equal(p.status.children[2].children[1].textContent, name)
    assert.equal(p.status.children[0], p.progress)
    assert.equal(p.status.children[1], p.notice)
  })
}
test('unknown tracks use Meadow and decoration waits for the engine shell', () => {
  const p = page('__proto__', 'loading')
  assert.equal(p.status.children.length, 2)
  p.document.dispatchEvent(new Event('DOMContentLoaded'))
  assert.equal(p.status.children.length, 3)
  assert.equal(p.status.attributes['aria-label'], 'Loading Meadow Loop')
  p.document.dispatchEvent(new Event('DOMContentLoaded'))
  assert.equal(p.status.children.length, 3)
})
