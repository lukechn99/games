class_name Spinner
extends Node
## Turns a node slowly round one of its own axes (windmill sails).

var target: Node3D
var axis := Vector3.BACK
var speed := 0.8   # radians a second


func _process(delta: float) -> void:
	if target:
		target.rotate_object_local(axis, speed * delta)
