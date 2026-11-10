#!/usr/bin/env node
// Lettering studies rendered from the actual OFL fonts already in the game.
import { mkdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { browser, REPO } from './lib.mjs'
const out = join(REPO, 'racing/tools/bench/out/branding')
await mkdir(out, { recursive: true })
const fonts = await Promise.all(['pacifico', 'lilita_one', 'black_ops_one'].map(async name => {
  const data = await readFile(join(REPO, 'racing/assets/fonts', `${name}.woff2`))
  return `@font-face{font-family:${name};src:url(data:font/woff2;base64,${data.toString('base64')})}`
}))
const logo = type => `<div class="logo ${type}"><span class="animal">${type === 'b' ? 'Animal' : 'animal'}</span><span class="karts">KARTS</span></div>`
const b = await browser()
try {
  const page = await b.newPage({ viewport: { width: 1200, height: 1050 }, deviceScaleFactor: 1 })
  await page.setContent(`<style>${fonts.join('')}
*{box-sizing:border-box}body{margin:0;padding:34px;background:#101b2d;color:#fff1ce;font-family:Arial,sans-serif}h1{margin:0 0 8px;font-size:28px}p{margin:0 0 24px;color:#b8c9de;font-size:16px}.study{margin-top:18px;border:1px solid #34435c;border-radius:16px;overflow:hidden}.caption{padding:12px 18px;background:#1c2b43;font-size:16px}.views{display:grid;grid-template-columns:2fr 1fr;height:230px}.large{display:flex;align-items:center;justify-content:center;background:#fff7e7}.small{display:flex;flex-direction:column;align-items:center;justify-content:center;background:#203954;gap:18px}.small em{font:13px Arial;color:#cad6e4}.logo{position:relative;display:flex;align-items:baseline;gap:17px;color:#162842;filter:drop-shadow(0 4px 0 #16284233)}.animal{font-size:73px;font-family:pacifico;color:#f04432}.karts{font:76px black_ops_one;letter-spacing:-3px;color:#246bdb}.b{gap:14px;transform:rotate(-3deg)}.b .animal{font:86px lilita_one;color:#246bdb}.b .karts{color:#ffc928;-webkit-text-stroke:2px #162842;text-shadow:3px 4px #162842}.c{flex-direction:column;align-items:center;gap:0;line-height:1}.c .animal{font:65px pacifico;color:#216744;margin-bottom:-3px;z-index:1}.c .karts{font-size:85px;color:#f04432;letter-spacing:5px}.small .logo{transform:scale(.43);transform-origin:center;white-space:nowrap;max-width:290px}.small .b{transform:scale(.43) rotate(-3deg)}.small .animal{color:#fff1ce}.small .karts{color:#ffc928}.small .c{transform:scale(.65)}
</style><h1>Animal Karts — lettering samples</h1><p>Expressive “animal” paired with a boxier “KARTS”. Large on light; smaller on dark.</p>${[
 ['a','A · Flowing script — Pacifico + Black Ops One'],
 ['b','B · Bold and playful — Lilita One + Black Ops One'],
 ['c','C · Stacked badge — Pacifico + Black Ops One'],
].map(([type,label]) => `<section class="study"><div class="caption">${label}</div><div class="views"><div class="large">${logo(type)}</div><div class="small">${logo(type)}<em>Small-screen treatment</em></div></div></section>`).join('')}`)
  await page.evaluate(() => document.fonts.ready)
  await page.screenshot({ path: join(out, 'animal-karts-lettering.png') })
  console.log(join(out, 'animal-karts-lettering.png'))
} finally { await b.close() }
