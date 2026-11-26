// Orientation is a browser concern, independent of motion-sensor permission
// and Godot's rendering loop. Update the prompt on the physical rotation event;
// the iframe's layout viewport can still have its old dimensions at that point.
(function () {
  // A page can word the prompt: <script src="landscape.js" data-message="...">
  var script = document.currentScript
  var message = (script && script.getAttribute('data-message')) || 'Turn your phone sideways to race'
  var coarse = matchMedia('(pointer: coarse)')
  var portrait = matchMedia('(orientation: portrait)')
  var orientation = screen.orientation
  var topPortrait = null
  try { if (window.top !== window) topPortrait = window.top.matchMedia('(orientation: portrait)') } catch (e) {}
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
    // The whole page's shape, not the game frame's: the frame is resized late.
    if (topPortrait) return topPortrait.matches
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
    card.innerHTML = '<div><div style="font-size:48px;margin-bottom:12px" aria-hidden="true">↻</div>' + message + '</div>'
    document.body.appendChild(card)
    update()
  }
  // On a phone the first event can come before the browser reports the new
  // orientation, and the next one seconds later (the prompt stayed up for
  // seconds after turning). So on any sign of a turn, look again every
  // frame for a second.
  var polling = 0
  function kick() {
    update()
    if (polling > 0) { polling = 60; return }
    polling = 60
    var tick = function () {
      update()
      if (--polling > 0) requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  }
  // The page around the game (same site) hears about a turn first: the
  // game's own frame is resized after it.
  var top = window
  try { if (window.top !== window && window.top.document) top = window.top } catch (e) {}
  var targets = top === window ? [window] : [window, top]
  for (var i = 0; i < targets.length; i++) {
    targets[i].addEventListener('orientationchange', kick)
    targets[i].addEventListener('resize', kick)
    if (targets[i].visualViewport) targets[i].visualViewport.addEventListener('resize', kick)
  }
  if (window.visualViewport) window.visualViewport.addEventListener('scroll', update)
  if (orientation && orientation.addEventListener) orientation.addEventListener('change', kick)
  coarse.addEventListener('change', kick)
  portrait.addEventListener('change', kick)
  if (top !== window) top.matchMedia('(orientation: portrait)').addEventListener('change', kick)
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
