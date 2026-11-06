class_name PlayerDriver
extends Node
## Feeds the player's controls (keyboard, gamepad, touch or tilt) into their kart.

var kart: Kart
var locked := true  # during the countdown


func _init(k: Kart) -> void:
	kart = k
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	var c := Controls.read(delta)
	if locked:
		c["throttle"] = 0.0
		c["drift"] = false
	kart.input = c
	if Input.is_action_just_pressed("respawn"):
		kart.respawn()
