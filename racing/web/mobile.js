// Browser interruptions can swallow touchend. Notify Godot even while its
// frame loop is suspended; returning to the page requires fresh touches.
(function () {
  var subscribers = []
  var blurred = false
  var hidden = document.hidden
  var mobile = window.racingMobile = { interruptions: 0, suspended: hidden }
  mobile.subscribe = function (callback) {
    subscribers.push(callback)
    callback(mobile.suspended)
  }
  function interrupt() {
    mobile.interruptions++
    mobile.suspended = blurred || hidden
    if (window.racingTilt) window.racingTilt.deg = 0
    subscribers.forEach(function (callback) { callback(mobile.suspended) })
  }
  window.addEventListener('blur', function () { blurred = true; interrupt() })
  window.addEventListener('focus', function () { blurred = false; interrupt() })
  document.addEventListener('visibilitychange', function () { hidden = document.hidden; interrupt() })
  window.addEventListener('pagehide', function () { hidden = true; interrupt() })
  window.addEventListener('pageshow', function () { hidden = document.hidden; interrupt() })
  document.addEventListener('touchcancel', interrupt, true)
  document.addEventListener('pointercancel', interrupt, true)
  window.addEventListener('orientationchange', interrupt)
})()
