class_name Session
extends Node
## Where the round comes from. In a Game Night room (?room=1) it's the
## room's rules on the host, reached through the page (net.js, shared with
## the racer; this side follows racing/scripts/net/net.gd). Otherwise it's
## solo practice: the same rules (rules.gd) run here, with you and three bots.
##
## Either way the game reads `state` (rules.ts's shape), calls act() and
## relay(), and listens to `changed` and `relayed`.

signal changed
signal relayed(from: String, data: Variant)

var in_room := false
var me := "me"
var is_host := true
var state: Dictionary = {}
var players: Array = []          # [{id, name, bot, level}]

var _clock := 0.0                # host clock minus ours, ms (room)
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var _game_ms := 1000.0           # practice runs on game time (tests run it fast)


## `practice_bots` bots join you in practice; `hide_ms` shortens hiding.
func start(room: bool, practice_bots := 3, hide_ms := -1.0, seed := 0, start_offset_ms := 0.0) -> void:
	in_room = room
	if in_room:
		return                   # wait for the page's first "state"
	_rng.seed = hash(["practice", seed])
	players = [{"id": "me", "name": "You", "bot": false, "level": null}]
	var seats := ["me"]
	for i in practice_bots:
		var id := "bot%d" % (i + 1)
		seats.append(id)
		players.append({"id": id, "name": "Bot %d" % (i + 1), "bot": true, "level": "medium"})
	state = HideRules.setup(seats, now_ms() - start_offset_ms, _rng)
	_hide_ms = hide_ms
	_apply_practice_times()
	changed.emit.call_deferred()


var _hide_ms := -1.0


func _apply_practice_times() -> void:
	if _hide_ms >= 0.0:
		state["hideMs"] = _hide_ms


## The host's clock, ms.
func now_ms() -> float:
	if in_room:
		return float(JavaScriptBridge.eval("Date.now()", true)) + _clock
	return _game_ms


## A rules action (rules.ts HideSeekAction).
func act(a: Dictionary) -> void:
	if in_room:
		_send({"kind": "act", "action": a})
		return
	var r := HideRules.action(state, me, a, now_ms(), _rng)
	if r.has("state"):
		state = r["state"]
		changed.emit()


## Fast throwaway data for everyone else (positions, shots).
func relay(data: Variant) -> void:
	if in_room:
		_send({"kind": "relay", "data": data})


func name_of(id: String) -> String:
	for p in players:
		if str(p.get("id", "")) == id:
			return str(p.get("name", "?"))
	return "?"


func is_bot(id: String) -> bool:
	for p in players:
		if str(p.get("id", "")) == id:
			return bool(p.get("bot", false))
	return false


func bot_level(id: String) -> String:
	for p in players:
		if str(p.get("id", "")) == id and p.get("level") != null:
			return str(p["level"])
	return "medium"


func _process(delta: float) -> void:
	if not in_room:
		_game_ms += delta * 1000.0
		_tick -= delta
		if _tick <= 0.0 and not state.is_empty():
			_tick = 0.25
			var round_before := int(state["round"])
			var n := HideRules.tick(state, now_ms(), _rng)
			if n != state:
				state = n
				if int(state["round"]) != round_before:
					_apply_practice_times()
				changed.emit()
		return
	var raw := str(JavaScriptBridge.eval("window.racingNet ? window.racingNet.take() : '[]'", true))
	var msgs: Variant = JSON.parse_string(raw)
	if not msgs is Array:
		return
	for m in msgs:
		if not m is Dictionary:
			continue
		match str(m.get("kind", "")):
			"state":
				me = str(m.get("me", ""))
				is_host = bool(m.get("isHost", false))
				_clock = float(m.get("clock", 0.0))
				players = m.get("players", [])
				var st: Variant = m.get("state", {})
				if st is Dictionary and st != state:
					state = st
					changed.emit()
			"relay":
				relayed.emit(str(m.get("from", "")), m.get("data"))


func _send(msg: Dictionary) -> void:
	JavaScriptBridge.eval("window.racingNet && window.racingNet.send(%s)" % JSON.stringify(JSON.stringify(msg)), true)
