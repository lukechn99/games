class_name PlayerInput
extends RefCounted
## What a player wants to do this frame, from any device (or a test).

var move := Vector2.ZERO     # x right, y forward, length up to 1
var look := Vector2.ZERO     # radians to turn: x yaw, y pitch
var jump := false
var fire := false            # seekers: paintball
var reroll := false          # hiders
var lock := false            # hiders


## Read a button press once.
func take(button: String) -> bool:
	var v: bool = get(button)
	set(button, false)
	return v
