// Hide and Seek's phone controls, drawn and handled by the page (not by
// Godot): a floating movement stick on the left and buttons on the right.
// The browser's own touch events are the most dependable on iPhone Safari
// (Godot's own stick never worked there: touches reached the game at
// coordinates that didn't match the screen, so the stick never caught a
// thumb). Swipes anywhere else still reach the game, for looking around.
//
// The game polls window.hsTouch.take() every frame: {"x", "y", "p": [presses]}
// (x right, y forward, each -1..1) and sets the buttons with setRole().
(function () {
  if (!(matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window)) return
  var R = 64                       // stick radius, CSS px
  var move = { x: 0, y: 0 }
  var presses = []
  var stickId = null
  var origin = null
  var role = ''

  var css = document.createElement('style')
  css.textContent =
    '#hs-touch{position:fixed;inset:0;z-index:50;pointer-events:none;-webkit-user-select:none;user-select:none;' +
    '-webkit-touch-callout:none;font:600 15px system-ui,sans-serif;color:#fff}' +
    '#hs-zone{position:absolute;left:0;top:22%;width:42%;bottom:0;pointer-events:auto;touch-action:none}' +
    '.hs-ring{position:absolute;width:' + 2 * R + 'px;height:' + 2 * R + 'px;margin:-' + R + 'px 0 0 -' + R + 'px;border-radius:50%;' +
    'border:2px solid rgba(255,255,255,.6);background:rgba(255,255,255,.14);pointer-events:none}' +
    '.hs-knob{position:absolute;width:58px;height:58px;margin:-29px 0 0 -29px;border-radius:50%;background:rgba(255,255,255,.45);pointer-events:none}' +
    '.hs-label{position:absolute;transform:translate(-50%,0);font-size:13px;opacity:.85;pointer-events:none}' +
    '.hs-btn{position:absolute;border-radius:50%;border:2px solid rgba(255,255,255,.65);background:rgba(255,255,255,.18);' +
    'display:flex;align-items:center;justify-content:center;text-align:center;line-height:1.05;pointer-events:auto;touch-action:none}' +
    '.hs-btn.down{background:rgba(255,255,255,.4)}'
  document.head.appendChild(css)

  var root = document.createElement('div')
  root.id = 'hs-touch'
  var zone = document.createElement('div')
  zone.id = 'hs-zone'
  var ring = document.createElement('div')
  ring.className = 'hs-ring'
  var knob = document.createElement('div')
  knob.className = 'hs-knob'
  var label = document.createElement('div')
  label.className = 'hs-label'
  label.textContent = 'Move'
  root.appendChild(zone)
  root.appendChild(ring)
  root.appendChild(knob)
  root.appendChild(label)
  var buttons = document.createElement('div')
  root.appendChild(buttons)

  // Where the stick rests: in from the left and bottom edges, where iPhone
  // Safari holds touches back while it checks for its back/home swipes.
  function home() {
    return { x: Math.max(110, innerWidth * 0.15), y: innerHeight - Math.max(100, innerHeight * 0.3) }
  }
  function draw() {
    var o = origin || home()
    ring.style.left = o.x + 'px'
    ring.style.top = o.y + 'px'
    knob.style.left = o.x + move.x * R + 'px'
    knob.style.top = o.y - move.y * R + 'px'
    label.style.left = o.x + 'px'
    label.style.top = o.y + R + 6 + 'px'
    label.style.display = origin ? 'none' : ''
  }

  function find(list, id) {
    for (var i = 0; i < list.length; i++) if (list[i].identifier === id) return list[i]
    return null
  }
  zone.addEventListener('touchstart', function (e) {
    e.preventDefault()
    var t = e.changedTouches[0]
    stickId = t.identifier           // a new thumb always takes the stick
    origin = { x: t.clientX, y: t.clientY }
    move = { x: 0, y: 0 }
    draw()
  }, { passive: false })
  zone.addEventListener('touchmove', function (e) {
    e.preventDefault()
    var t = find(e.touches, stickId)
    if (!t || !origin) return
    var dx = t.clientX - origin.x
    var dy = t.clientY - origin.y
    var d = Math.hypot(dx, dy)
    if (d > R) { dx *= R / d; dy *= R / d }
    move = { x: dx / R, y: -dy / R }
    draw()
  }, { passive: false })
  function end(e) {
    if (stickId !== null && !find(e.touches, stickId)) {
      stickId = null
      origin = null
      move = { x: 0, y: 0 }
      draw()
    }
  }
  zone.addEventListener('touchend', end)
  zone.addEventListener('touchcancel', end)
  // Safari interruptions (a call, the tab hidden) can swallow touchend.
  window.addEventListener('blur', function () { stickId = null; origin = null; move = { x: 0, y: 0 }; draw() })

  var LAYOUTS = {
    seeker: [['fire', 'Shoot', 124, 0, 0], ['jump', 'Jump', 92, -150, 30]],
    hider: [['reroll', 'Switch<br>prop', 100, 0, 0], ['lock', 'Lock', 80, -20, -135], ['decoy', 'Decoy', 80, -130, -95], ['jump', 'Jump', 92, -150, 30]],
  }
  function layoutButtons() {
    buttons.innerHTML = ''
    var spec = LAYOUTS[role] || []
    var k = Math.max(0.7, Math.min(1.25, innerHeight / 400))
    var bx = innerWidth - 80 * k
    var by = innerHeight - 105 * k
    spec.forEach(function (b) {
      var el = document.createElement('div')
      el.className = 'hs-btn'
      var size = b[2] * 0.62 * k
      el.style.width = el.style.height = size + 'px'
      el.style.left = bx + b[3] * 0.62 * k - size / 2 + 'px'
      el.style.top = by + b[4] * 0.62 * k - size / 2 + 'px'
      el.innerHTML = b[1]
      el.style.fontSize = (b[0] === 'fire' ? 17 : 13) * k + 'px'
      el.addEventListener('touchstart', function (e) {
        e.preventDefault()
        presses.push(b[0])
        el.classList.add('down')
      }, { passive: false })
      var up = function (e) { e.preventDefault(); el.classList.remove('down') }
      el.addEventListener('touchend', up, { passive: false })
      el.addEventListener('touchcancel', up, { passive: false })
      buttons.appendChild(el)
    })
  }

  window.hsTouch = {
    take: function () {
      var out = JSON.stringify({ x: move.x, y: move.y, p: presses, held: stickId !== null })
      presses = []
      return out
    },
    setRole: function (r) {
      if (r === role) return
      role = r
      layoutButtons()
    },
  }
  function onResize() { layoutButtons(); draw() }
  window.addEventListener('resize', onResize)
  if (window.visualViewport) window.visualViewport.addEventListener('resize', onResize)
  function mount() {
    document.body.appendChild(root)
    draw()
  }
  if (document.body) mount()
  else document.addEventListener('DOMContentLoaded', mount)
})()
