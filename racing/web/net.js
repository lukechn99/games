// Bridge between the game and the Game Night room page that embeds it
// (lib/games/racing/RacingView.tsx). Messages from the page are queued here
// for Godot to collect each frame; Godot sends through window.racingNet.send.
// Shared by every Godot game: <script src="net.js" data-source="hideseek">
// names the game in its messages (default 'racing').
(function () {
  var script = document.currentScript
  var source = (script && script.getAttribute('data-source')) || 'racing'
  var inbox = []
  var embedded = window.parent && window.parent !== window
  window.racingNet = {
    embedded: embedded,
    take: function () {
      var out = inbox
      inbox = []
      return JSON.stringify(out)
    },
    send: function (json) {
      if (!embedded) return
      var msg = JSON.parse(json)
      msg.source = source
      window.parent.postMessage(msg, '*')
    },
  }
  window.addEventListener('message', function (e) {
    if (e.source !== window.parent) return
    var m = e.data
    if (!m || m.source !== 'game-night') return
    inbox.push(m)
  })
  if (embedded) window.parent.postMessage({ source: source, kind: 'ready' }, '*')
})()
