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
	# No drift button on phones: holding brake while steering at speed starts
	# a drift (and keeps it going), and letting go fires the boost.
	var steering := absf(float(c["steer"])) > 0.35
	if float(c["brake"]) > 0.5 and (kart.drifting or (steering and kart.speed > Kart.DRIFT_MIN_SPEED)):
		c["drift"] = true
		c["brake"] = 0.0
		c["throttle"] = 1.0
	if locked:
		c["throttle"] = 0.0
		c["drift"] = false
	kart.input = c
	if Input.is_action_just_pressed("respawn"):
		kart.respawn()
