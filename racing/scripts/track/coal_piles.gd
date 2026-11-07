class_name CoalPiles
extends Node3D
## Coal piles in the mine tunnel: drive into one and you lose a chunk of
## speed and get coal dust splattered over your screen, which blows away.

var spots: Array[Vector3] = []
var _cool := {}


func _physics_process(delta: float) -> void:
	for k in _cool.keys():
		_cool[k] -= delta
		if _cool[k] <= 0.0:
			_cool.erase(k)
	for n in get_tree().get_nodes_in_group("karts"):
		var k := n as Kart
		if k == null or k.remote or _cool.has(k):
			continue
		for p in spots:
			if k.global_position.distance_to(p) < 2.3:
				_cool[k] = 1.5
				k.linear_velocity *= 0.6
				k.splattered.emit()
				k.crashed.emit(0.35)
				break
