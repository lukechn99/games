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
    },
    true,
  )
  document.addEventListener(
    'click',
    function (e) {
      if (hit(e.clientX, e.clientY)) ask()
    },
    true,
  )
})()
