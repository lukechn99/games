class_name CloudDrift
extends Node3D
## Turns the clouds slowly round the track, so the sky is never still.

func _process(delta: float) -> void:
	rotation.y += delta * 0.006
