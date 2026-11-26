class_name Bots
extends RefCounted
## Computer players (design doc 12), run only by the host's game (or in
## practice). A bot is an ordinary Player node driven by a brain here; it
## acts through the same rules as a person (Session.act with "as").
##
## Seeker bots walk the farm on a navigation mesh. A spark plume tells them
## roughly where to look (less exactly the farther away they are); there
## they paint objects in sight near the spot, now and then sensing the right
## one (better bots more often), and they chase a hider they see move.
## Hider bots pick a free spot beside matching scenery during the hide phase.

const LEVELS := {
	"easy": {"err": 0.35, "sense": 0.12, "shots": 3, "spread": 0.06, "react": 1.3, "spot": 0.5},
	"medium": {"err": 0.2, "sense": 0.25, "shots": 4, "spread": 0.035, "react": 0.9, "spot": 0.75},
	"hard": {"err": 0.12, "sense": 0.4, "shots": 5, "spread": 0.02, "react": 0.6, "spot": 0.95},
}


class Seeker:
	var body: Player
	var level: Dictionary
	var rng := RandomNumberGenerator.new()
	var nav_map: RID
	var _path := PackedVector3Array()
	var _path_i := 0
	var _goal := Vector3.ZERO
	var _goal_kind := ""            # "patrol" | "spark" | "chase"
	var _goal_age := 0.0
	var _shots_left := 0
	var _aim_wait := 0.0
	var _aim_at: Node3D = null
	var _painted := {}              # instance id -> time painted
	var _clock := 0.0
	var _stuck_t := 0.0
	var _last_pos := Vector3.ZERO
	var _repath := 0.0

	func _init(p: Player, lvl: String, map: RID, seed: int) -> void:
		body = p
		level = Bots.LEVELS.get(lvl, Bots.LEVELS["medium"])
		nav_map = map
		rng.seed = seed
		_new_patrol()

	## A spark burst went off at `pos`: head there, roughly.
	func hear(pos: Vector3) -> void:
		var d := body.global_position.distance_to(pos)
		var err: float = d * float(level["err"])
		var guess := pos + Vector3(rng.randf_range(-err, err), 0, rng.randf_range(-err, err))
		if _goal_kind != "chase" and (_goal_kind != "spark" or d < body.global_position.distance_to(_goal)):
			_set_goal(guess, "spark")

	## One physics step. `suspects`: every object a hider could be
	## ([Node3D, centre]); `hiders`: the hider Player nodes; `fire`: called
	## with (bot, target node, aim point) to shoot.
	func think(delta: float, seek: bool, suspects: Array, hiders: Array, fire: Callable) -> void:
		_clock += delta
		var inp := body.input
		inp.move = Vector2.ZERO
		if not seek:
			return
		# A hider seen moving: go for it.
		if _goal_kind != "chase":
			for h in hiders:
				if h.velocity.length() > 1.0 and body.global_position.distance_to(h.global_position) < 14.0 and _sees(h):
					if rng.randf() < float(level["spot"]):
						_set_goal(h.global_position, "chase")
						_aim_at = h
						_shots_left = 2
						_aim_wait = float(level["react"]) * 0.6
					break
		# Aiming and shooting.
		if _shots_left > 0 and _aim_at != null and is_instance_valid(_aim_at):
			_face(_center(_aim_at))
			_aim_wait -= delta
			if _aim_wait <= 0.0:
				var p := _center(_aim_at) + Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)) * float(level["spread"]) * body.eye().distance_to(_center(_aim_at))
				fire.call(self, _aim_at, p)
				_painted[_aim_at.get_instance_id()] = _clock
				_shots_left -= 1
				_aim_at = _pick(suspects, hiders) if _shots_left > 0 else null
				_aim_wait = float(level["react"]) * rng.randf_range(0.6, 1.2)
				if _aim_at == null:
					_shots_left = 0
					_new_patrol()
			return
		# No route yet (the map comes online a frame late, or no way there).
		if _path.is_empty():
			_repath -= delta
			if _repath <= 0.0:
				_repath = 0.5
				_plan()
				if _path.is_empty() and _goal_age > 3.0:
					_new_patrol()
			_goal_age += delta
			return
		# Arrived where the sparks were: search there.
		var arrive := 2.5 if _goal_kind == "spark" else 1.2
		if _flat(body.global_position - _goal).length() < arrive or _path_i >= _path.size():
			if _goal_kind == "spark" or _goal_kind == "chase":
				_shots_left = int(level["shots"])
				_aim_at = _pick(suspects, hiders)
				_aim_wait = float(level["react"])
				if _aim_at == null:
					_shots_left = 0
					_new_patrol()
			else:
				_new_patrol()
			return
		_walk(delta)
		_goal_age += delta
		if _goal_kind == "spark" and _goal_age > 25.0:
			_new_patrol()

	func _walk(delta: float) -> void:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 1.5
			_plan()
		while _path_i < _path.size() and _flat(_path[_path_i] - body.global_position).length() < 0.45:
			_path_i += 1
		if _path_i >= _path.size():
			return
		var to := _path[_path_i] - body.global_position
		body.yaw = atan2(-to.x, -to.z)
		body.pitch = lerpf(body.pitch, -0.1, 0.1)
		body.input.move = Vector2(0, 1)
		# Stuck against something: hop, and plan again.
		_stuck_t += delta
		if _stuck_t > 1.2:
			if body.global_position.distance_to(_last_pos) < 0.3:
				body.input.jump = true
				_repath = 0.0
			_stuck_t = 0.0
			_last_pos = body.global_position

	func _plan() -> void:
		if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
			_path = PackedVector3Array()
			return
		_path = NavigationServer3D.map_get_path(nav_map, body.global_position, _goal, true)
		_path_i = 1 if _path.size() > 1 else 0

	func _set_goal(p: Vector3, kind: String) -> void:
		_goal = p
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			var snapped := NavigationServer3D.map_get_closest_point(nav_map, p)
			if snapped != Vector3.ZERO:
				_goal = snapped
		_path = PackedVector3Array()
		_goal_kind = kind
		_goal_age = 0.0
		_repath = 0.0

	func _new_patrol() -> void:
		_set_goal(TestBarn.PATROL[rng.randi_range(0, TestBarn.PATROL.size() - 1)], "patrol")

	## The next thing to paint near the goal: something in sight that
	## hasn't just been painted. Now and then the bot senses the right one.
	func _pick(suspects: Array, hiders: Array) -> Node3D:
		var near := []
		for s in suspects:
			var n: Node3D = s[0]
			if not is_instance_valid(n):
				continue
			if _painted.has(n.get_instance_id()) and _clock - float(_painted[n.get_instance_id()]) < HideRules.PAINT_BRIGHT + HideRules.PAINT_FADE:
				continue
			var c: Vector3 = s[1]
			if _flat(c - _goal).length() > 5.5 or body.eye().distance_to(c) > 16.0:
				continue
			if not _sees_point(c, n):
				continue
			near.append([n, c])
		if near.is_empty():
			return null
		if rng.randf() < float(level["sense"]):
			for e in near:
				if hiders.has(e[0]):
					return e[0]
		var best: Node3D = null
		var best_w := -1.0
		for e in near:
			var w := rng.randf() / (1.0 + _flat(e[1] - _goal).length())
			if w > best_w:
				best_w = w
				best = e[0]
		return best

	func _face(p: Vector3) -> void:
		var to := p - body.eye()
		body.yaw = atan2(-to.x, -to.z)
		body.pitch = atan2(to.y, _flat(to).length())

	func _sees(n: Node3D) -> bool:
		return _sees_point(_center(n), n)

	func _sees_point(p: Vector3, target: Node3D) -> bool:
		var q := PhysicsRayQueryParameters3D.create(body.eye(), p, TestBarn.LAYER_WORLD | TestBarn.LAYER_PROPS | TestBarn.LAYER_PLAYERS, [body.get_rid()])
		var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
		return hit.is_empty() or hit["collider"] == target

	static func _center(n: Node3D) -> Vector3:
		var kind: String = n.get("kind") if n is Player else n.get_meta("prop", "")
		var h := Props.size(kind).y if kind != "" else 1.0
		return n.global_position + n.global_basis.y * h * 0.5

	static func _flat(v: Vector3) -> Vector3:
		return Vector3(v.x, 0, v.z)


class Hider:
	var body: Player
	var rng := RandomNumberGenerator.new()
	var hide_at := -1.0
	var hidden := false

	func _init(p: Player, seed: int) -> void:
		body = p
		rng.seed = seed

	## During the hide phase (`hide_s` long): partway through, take a free
	## spot that suits the prop. `free` checks a transform.
	func think(t: float, hide_s: float, free: Callable) -> void:
		if hide_at < 0.0:
			hide_at = rng.randf_range(0.1, 0.45) * hide_s
		if hidden or t >= hide_s or t < hide_at:
			return
		var places := TestBarn.hiding_places(body.kind)
		for i in range(places.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = places[i]
			places[i] = places[j]
			places[j] = tmp
		for xf in places:
			if free.call(xf, body):
				body.place(xf)
				hidden = true
				return
		hidden = true          # nowhere free: stay put
