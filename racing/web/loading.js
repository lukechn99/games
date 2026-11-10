// The existing Godot status overlay owns loading/error/removal. Decorate it
// with a lightweight, map-specific still; no extra game loop or WebGL work.
;(function () {
  'use strict'
  var tracks = { meadow: 'Meadow Loop', mine: 'Mining Mountain', frost: 'Frosty Pass' }
  var requested = new URLSearchParams(location.search).get('track')
  var track = Object.prototype.hasOwnProperty.call(tracks, requested) ? requested : 'meadow'
  var image = new URL('../tracks/aerial-' + track + '.jpg', location.href).href
  var preload = document.createElement('link')
  preload.rel = 'preload'
  preload.as = 'image'
  preload.href = image
  document.head.appendChild(preload)
  var style = document.createElement('style')
  style.textContent = '#status{visibility:visible;background-size:cover;background-position:center;background-color:#14233b}' +
    '#status-splash{display:none!important}' +
    '#status-progress{bottom:7%;width:min(520px,80vw);height:14px;accent-color:#ffc928;z-index:1}' +
    '.racing-loading-caption{position:absolute;bottom:14%;left:16px;right:16px;text-align:center;color:#fff1ce;font:600 20px/1.5 system-ui,sans-serif;text-shadow:0 2px 5px #101820}' +
    '.racing-loading-caption img{display:block;width:min(460px,70vw);height:auto;margin:0 auto 8px;filter:drop-shadow(0 2px 2px #fff1ce)}'
  document.head.appendChild(style)
  document.title = 'Animal Karts — ' + tracks[track]
  function decorate() {
    var status = document.getElementById('status')
    if (!status) return
    status.style.backgroundImage = 'linear-gradient(0deg,rgba(8,18,35,.8),rgba(8,18,35,.05) 80%),url(' + JSON.stringify(image) + ')'
    status.setAttribute('aria-label', 'Loading ' + tracks[track])
    var caption = document.createElement('div')
    caption.className = 'racing-loading-caption'
    var title = document.createElement('img')
    title.src = new URL('../branding/animal-karts.svg', location.href).href
    title.alt = 'Animal Karts'
    var name = document.createElement('span')
    name.textContent = tracks[track]
    caption.appendChild(title)
    caption.appendChild(name)
    status.appendChild(caption)
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', decorate, { once: true })
  else decorate()
})()
