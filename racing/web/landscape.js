// Orientation is a browser concern, independent of motion-sensor permission
// and Godot's rendering loop. Update the prompt on the physical rotation event;
// the iframe's layout viewport can still have its old dimensions at that point.
(function () {
  var coarse = matchMedia('(pointer: coarse)')
  var portrait = matchMedia('(orientation: portrait)')
  var orientation = screen.orientation
  var card
  var css = document.createElement('style')
  css.textContent =
    'html,body{margin:0;width:100%;height:100%;overflow:hidden}' +
    '#canvas{position:fixed;inset:0;width:100vw!important;height:100vh!important;height:100dvh!important}' +
    '#racing-rotate{position:fixed;inset:0;z-index:99;box-sizing:border-box;' +
    'width:100vw;height:100vh;height:100dvh;display:flex;background:#171c2e;color:#fff;' +
    'font:600 clamp(16px,4vw,20px) system-ui,sans-serif;align-items:center;justify-content:center;' +
    'text-align:center;padding:24px;overflow:hidden}' +
    '#racing-rotate[hidden]{display:none}' +
    '#racing-rotate>div{max-width:28ch}'
  document.head.appendChild(css)

  function isPortrait() {
    if (orientation && /^(portrait|landscape)-/.test(orientation.type)) return orientation.type.indexOf('portrait') === 0
    if (typeof window.orientation === 'number') return Math.abs(window.orientation) !== 90
    return portrait.matches
  }

  function update() {
    if (!card) return
    card.hidden = !coarse.matches || !isPortrait()
    // visualViewport accounts for browser bars and an iframe's visible area.
    // No delayed resize events: Godot polls the real canvas size each frame.
    var view = window.visualViewport
    card.style.width = (view ? view.width : innerWidth) + 'px'
    card.style.height = (view ? view.height : innerHeight) + 'px'
    card.style.left = (view ? view.offsetLeft : 0) + 'px'
    card.style.top = (view ? view.offsetTop : 0) + 'px'
  }

  function addCard() {
    card = document.createElement('div')
    card.id = 'racing-rotate'
    card.setAttribute('role', 'status')
    card.innerHTML = '<div><div style="font-size:48px;margin-bottom:12px" aria-hidden="true">↻</div>Turn your phone sideways to race</div>'
    document.body.appendChild(card)
    update()
  }
  window.addEventListener('orientationchange', update)
  window.addEventListener('resize', update)
  if (orientation && orientation.addEventListener) orientation.addEventListener('change', update)
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', update)
    window.visualViewport.addEventListener('scroll', update)
  }
  coarse.addEventListener('change', update)
  portrait.addEventListener('change', update)
  if (document.body) addCard()
  else document.addEventListener('DOMContentLoaded', addCard)

  // Android can lock landscape after a tap. iOS uses the rotation prompt.
  var triedLock = false
  function keepLandscape() {
    if (triedLock || !coarse.matches) return
    triedLock = true
    var el = document.documentElement
    var full = el.requestFullscreen ? el.requestFullscreen({ navigationUI: 'hide' }) : null
    var lock = function () {
      if (orientation && orientation.lock) orientation.lock('landscape').catch(function () {})
    }
    if (full && full.then) full.then(lock).catch(lock)
    else lock()
  }
  document.addEventListener('touchend', keepLandscape, true)
})()
