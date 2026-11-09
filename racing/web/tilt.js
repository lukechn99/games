// Tilt steering for the kart racer (design doc 10.1).
//
// Holding the phone sideways like a steering wheel, the kart goes straight
// when the phone's long edge is level with the ground. We read gravity from
// the motion sensor and work out how far the long edge tips from level.
//
// window.racingTilt = { state: 'off' | 'needs-permission' | 'on' | 'denied' | 'unsupported',
//                       deg: degrees from level, positive = turned right (clockwise) }
//
// iOS only allows the sensor after a real tap, and Godot handles taps a
// frame later, so we listen for the tap here and check whether it landed on
// the game's "Steer by tilting" button (window.racingTiltButton, set by Godot).
(function () {
  var tilt = (window.racingTilt = { state: 'off', deg: 0, flat: false })
  var Motion = window.DeviceMotionEvent
  if (!Motion) {
    tilt.state = 'unsupported'
    return
  }
  var needsPermission = typeof Motion.requestPermission === 'function'
  var listening = false
  // Which way gravity reads along the phone's short edge tells us both which
  // way it's rotated and the platform's sign convention (iOS and Android
  // report gravity with opposite signs). Remember the last confident reading.
  var side = 0

  function onMotion(e) {
    if (window.racingMobile && window.racingMobile.suspended) return
    var g = e.accelerationIncludingGravity
    if (!g || g.x == null) return
    var x = g.x, y = g.y, z = g.z
    var len = Math.sqrt(x * x + y * y + z * z) || 1
    if (Math.abs(x) > 3) side = x > 0 ? -1 : 1
    if (!side) {
      // Phone nearly flat before we've seen it upright: fall back on the
      // screen orientation (90 = rotated anticlockwise).
      var a = (screen.orientation && screen.orientation.angle) || window.orientation || 90
      side = a === 90 ? 1 : -1
    }
    var deg = (Math.asin(Math.max(-1, Math.min(1, y / len))) * 180) / Math.PI
    // Positive = turned right (clockwise). Checked on a real phone: the
    // sign was the wrong way round, so it is flipped here.
    tilt.deg = -deg * side
    tilt.flat = Math.abs(z) / len > 0.97
    tilt.state = 'on'
  }

  function start() {
    if (listening) return
    listening = true
    window.addEventListener('devicemotion', onMotion)
    if (tilt.state === 'off' || tilt.state === 'needs-permission') tilt.state = 'waiting'
    setTimeout(function () {
      if (tilt.state === 'waiting') tilt.state = 'unsupported' // no sensor events arrived
    }, 2500)
  }

  function ask() {
    if (!needsPermission) return start()
    Motion.requestPermission()
      .then(function (r) {
        if (r === 'granted') start()
        else tilt.state = 'denied'
      })
      .catch(function () {
        tilt.state = 'denied'
      })
  }

  window.racingAskTilt = ask
  tilt.state = needsPermission ? 'needs-permission' : 'off'

  function hit(clientX, clientY) {
    var b = window.racingTiltButton
    var c = document.querySelector('canvas')
    if (!b || !c) return false
    var r = c.getBoundingClientRect()
    var x = ((clientX - r.left) * c.width) / r.width
    var y = ((clientY - r.top) * c.height) / r.height
    return x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h
  }
  document.addEventListener(
    'touchend',
    function (e) {
      var t = e.changedTouches[0]
      if (t && hit(t.clientX, t.clientY)) ask()
      keepLandscape()
    },
    true,
  )

  // Landscape only on phones (design doc 10.3). Tilting the phone hard to
  // steer used to flip the game into portrait. Where the browser allows it
  // (Android), go full screen and lock to landscape on the first tap; it has
  // to happen inside a tap. iPhones don't allow locking, so there a "turn
  // your phone sideways" card covers the game while it's held upright.
  var triedLock = false
  function keepLandscape() {
    if (triedLock || !matchMedia('(pointer: coarse)').matches) return
    triedLock = true
    var el = document.documentElement
    var full = el.requestFullscreen ? el.requestFullscreen({ navigationUI: 'hide' }) : null
    var lock = function () {
      if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(function () {})
    }
    if (full && full.then) full.then(lock).catch(lock)
    else lock()
  }
  var css = document.createElement('style')
  css.textContent =
    '#racing-rotate{display:none;position:fixed;inset:0;z-index:99;background:#171c2e;color:#fff;' +
    'font:600 20px system-ui,sans-serif;align-items:center;justify-content:center;text-align:center;padding:24px}' +
    '@media (orientation: portrait) and (pointer: coarse){#racing-rotate{display:flex}}'
  document.head.appendChild(css)
  function addCard() {
    if (document.getElementById('racing-rotate')) return
    var card = document.createElement('div')
    card.id = 'racing-rotate'
    card.innerHTML = '<div><div style="font-size:48px;margin-bottom:12px">↻</div>Turn your phone sideways to race</div>'
    document.body.appendChild(card)
  }
  // Rotating a phone fires "resize" before the new size has settled, so the
  // game (and its loading screen) could stay the old shape for a while.
  // Nudge it again as the rotation finishes.
  function nudge() {
    ;[50, 200, 500, 1000].forEach(function (ms) {
      setTimeout(function () {
        window.dispatchEvent(new Event('resize'))
      }, ms)
    })
  }
  window.addEventListener('orientationchange', nudge)
  if (screen.orientation && screen.orientation.addEventListener) screen.orientation.addEventListener('change', nudge)
  if (window.visualViewport) window.visualViewport.addEventListener('resize', function () {
    window.dispatchEvent(new Event('resize'))
  })
  if (document.body) addCard()
  else document.addEventListener('DOMContentLoaded', addCard)
  document.addEventListener(
    'click',
    function (e) {
      if (hit(e.clientX, e.clientY)) ask()
    },
    true,
  )
})()
