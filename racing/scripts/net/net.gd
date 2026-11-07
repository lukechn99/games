extends Node
## Autoload "Net": the game's link to a Game Night room (design doc 13).
##
## When the game is embedded in a room page (?room=1), the page sends the
## race state from the room's rules, and passes kart positions between
## players. Outside a room the game runs on its own with computer drivers.

signal state_changed(state: Dictionary)
signal relay_received(from: String, data: Variant)

var active := false
var me := ""
var is_host := false
var round := 0
var state: Dictionary = {}
var players: Array = []       # [{id, name, bot}]
var _clock := 0.0             # host clock minus ours, ms


func _ready() -> void:
	if OS.has_feature("web"):
		active = str(JavaScriptBridge.eval("location.search", true)).contains("room=")
	set_process(active)


func _process(_delta: float) -> void:
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
				round = int(m.get("round", 0))
				_clock = float(m.get("clock", 0.0))
				players = m.get("players", [])
				state = m.get("state", {})
				state_changed.emit(state)
			"relay":
				relay_received.emit(str(m.get("from", "")), m.get("data"))


func _send(msg: Dictionary) -> void:
	JavaScriptBridge.eval("window.racingNet && window.racingNet.send(%s)" % JSON.stringify(JSON.stringify(msg)), true)


## A game action for the room's race rules (lib/games/racing/rules.ts).
func act(action: Dictionary) -> void:
	if active:
		_send({"kind": "act", "action": action})


## A room action, like starting another round.
func room(action: String) -> void:
	if active:
		_send({"kind": "room", "action": action})


## Fast, throwaway data for everyone else (kart positions).
func relay(data: Variant) -> void:
	if active:
		_send({"kind": "relay", "data": data})


## The host's clock, in seconds, for a countdown everyone shares.
func host_now() -> float:
	var ms := float(JavaScriptBridge.eval("Date.now()", true))
	return (ms + _clock) / 1000.0


func name_of(id: String) -> String:
	for p in players:
		if str(p.get("id", "")) == id:
			return str(p.get("name", "?"))
	return "?"


## A computer driver (from the room's player list).
func is_bot(id: String) -> bool:
	for p in players:
		if str(p.get("id", "")) == id:
			return bool(p.get("bot", false))
	return false
