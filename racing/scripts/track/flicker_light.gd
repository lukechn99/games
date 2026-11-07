class_name FlickerLight
extends OmniLight3D
## A torch or lantern: its light wavers like a flame.

var _base := 0.0
var _t := 0.0
var _seed := 0.0


func _ready() -> void:
	_base = light_energy
	_seed = randf() * 100.0


func _process(delta: float) -> void:
	_t += delta
	light_energy = _base * (0.82 + 0.12 * sin(_t * 9.0 + _seed) + 0.08 * sin(_t * 23.0 + _seed * 2.0))
