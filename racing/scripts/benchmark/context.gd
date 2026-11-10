class_name BenchmarkContext
extends RefCounted
## Explicit read-only inputs to measurement. Only Session adapts the game's
## scene layout and private race-running flag to this interface.

var scene: Node
var track: Track
var player_kart: Kart
var karts: Array[Kart]
var _running: Callable


func _init(root_node: Node, course: Track, player: Kart, racers: Array[Kart], running: Callable) -> void:
	scene = root_node
	track = course
	player_kart = player
	karts = racers
	_running = running


func is_running() -> bool:
	return bool(_running.call())
