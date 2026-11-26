extends Node3D
## Hide and Seek (design doc). The round comes from a Session: the Game
## Night room's rules (?room=1) or solo practice (you and three bots, the
## same rules run here). Every round deals roles at random.
##
## Everyone in the round is a Player node: you (controlled, with the
## camera), other people (following their relayed positions), and bots
## (driven by Bots brains, only on the host's game; others see them through
## the host's relay). Positions go out ~12 times a second; each paintball
## shot is relayed so everyone sees it fly and splat; whoever fired decides
## whether it found someone and tells the rules.
##
## Test links (practice): ?role=hider|seeker, ?hide=SECONDS, ?t=SECONDS
## (start the clock there), ?bots=N, ?at=X,Z[,Y]&look=YAW,PITCH (degrees),
## ?seed=N, ?sparknow, ?relief=off, ?shadows=off, ?ambient=E&sunscale=K.

const PRACTICE_HIDE := 15.0      # practice hides for 15 s; rooms use 45
const SEND_EVERY := 1.0 / 12.0
const SHIRTS := [Color(0.75, 0.2, 0.18), Color(0.2, 0.5, 0.3), Color(0.85, 0.6, 0.15), Color(0.45, 0.3, 0.65),
	Color(0.15, 0.5, 0.7), Color(0.8, 0.35, 0.55), Color(0.4, 0.4, 0.4), Color(0.6, 0.45, 0.25), Color(0.1, 0.3, 0.6), Color(0.6, 0.7, 0.2)]

var session: Session
var hud: Hud
var me: Player
var roster := {}                 # id -> Player
var brains := {}                 # id -> Bots.Seeker | Bots.Hider (host only)
var bursts: Array = []
var _round := -1
var _next_burst := 0
var _paint_root: Node3D
var _rng := RandomNumberGenerator.new()
var _query := {}
var _fire_cool := 0.0
var _send_t := 0.0
var _warm := 0
var _warm_nodes: Array[Node] = []
var _nav: NavigationRegion3D
var _scenery: Array = []         # [StaticBody3D, centre] for bots to suspect
var _shown_over := false
var _known: Dictionary = {}      # id -> {role, prop} last seen, to spot changes
var _decoys := {}                # decoy id -> its solid body (with the mesh)
var _decoyed := {}               # hider bots that have dropped their decoys
var _debug_t := 0.0
var _shots_seen := 0             # others' shots shown here
var _sent := 0
var _got := 0


func _ready() -> void:
	_query = _read_query()
	Props.relief = _query.get("relief", "on") != "off"
	TestBarn.environment(self, _query.get("shadows", "on") != "off", float(_query.get("sunscale", "-1")), float(_query.get("ambient", "-1")))
	TestBarn.build(self)
	for body in get_node("Scenery").get_children():
		if body is StaticBody3D:
			_scenery.append([body, body.global_position + body.global_basis.y * Props.size(body.get_meta("prop")).y * 0.5])
	_paint_root = Node3D.new()
	_paint_root.name = "Paint"
	add_child(_paint_root)
	hud = Hud.new()
	add_child(hud)
	if _query.has("touch"):          # test switch: the phone layout on a computer
		hud.controls.touching = true
	session = Session.new()
	add_child(session)
	session.changed.connect(_sync)
	session.relayed.connect(_on_relay)
	var in_room := OS.has_feature("web") and _query.has("room")
	var hide_ms := float(_query.get("hide", str(PRACTICE_HIDE))) * 1000.0
	session.start(in_room, int(_query.get("bots", "3")), hide_ms, int(_query.get("seed", "0")), float(_query.get("t", "0")) * 1000.0)
	if not in_room and _query.has("role"):
		_force_role(_query["role"])
	_rng.seed = hash(["game", int(_query.get("seed", "0"))])
	hud.toast("Joining the round…" if in_room else "Practice: you and %d bots" % int(_query.get("bots", "3")), 3.0)
	hud.cover(true)
	_warm = 12


## Practice test links: put you on the side asked for.
func _force_role(want: String) -> void:
	var s := session.state
	if s["members"]["me"]["role"] == want:
		return
	for id in s["members"]:
		if s["members"][id]["role"] == want:
			var a: Dictionary = s["members"][id]
			s["members"][id] = s["members"]["me"]
			s["members"]["me"] = a
			s["hidersAtStart"] = s["seats"].filter(func(x): return s["members"][x]["role"] == "hider")
			return


func _now_s() -> float:
	return session.now_ms() / 1000.0


## Seconds into the round.
func _t() -> float:
	return HideRules.elapsed(session.state, session.now_ms()) / 1000.0


# --------------------------------------------------------------- rounds --

func _sync() -> void:
	var s := session.state
	if s.is_empty():
		return
	if int(s["round"]) != _round:
		_new_round()
	else:
		_update_members()
	_sync_decoys()


func _new_round() -> void:
	var s := session.state
	_round = int(s["round"])
	_shown_over = false
	for c in _paint_root.get_children():
		c.queue_free()
	for n in roster.values():
		n.queue_free()
	roster.clear()
	brains.clear()
	_known.clear()
	for d in _decoys.values():
		d.queue_free()
	_decoys.clear()
	_decoyed.clear()
	me = null
	if session.is_host and _nav == null and _has_bots():
		_nav = TestBarn.navigation(self)
	var seats: Array = s["seats"]
	var by_role := {"hider": 0, "seeker": 0}
	for id in seats:
		if not s["members"].has(id):
			continue
		var m: Dictionary = s["members"][id]
		var p := Player.new()
		p.id = id
		p.role = m["role"]
		p.kind = m["prop"]
		p.shirt = SHIRTS[seats.find(id) % SHIRTS.size()]
		var mine: bool = id == session.me
		var bot: bool = session.is_bot(id) or (not session.in_room and id != "me")
		var run_bot: bool = bot and session.is_host
		p.controlled = mine or (run_bot and p.role == "seeker")
		p.has_camera = mine
		p.remote = not mine and not run_bot
		if mine:
			p.input = hud.controls.input
		# Seekers start in the yard; hiders in the middle of the barn.
		var i: int = by_role[p.role]
		by_role[p.role] = i + 1
		if p.role == "seeker":
			p.position = Vector3(-3.0 + i * 1.5, 0, 18.5)
		else:
			p.position = Vector3(-2.0 + (i % 4) * 1.3, 0, 1.0 - (i / 4) * 1.3)
		add_child(p)
		roster[id] = p
		_known[id] = {"role": m["role"], "prop": m["prop"]}
		if mine:
			me = p
			if _query.has("at"):
				var a: PackedStringArray = _query["at"].split(",")
				p.position = Vector3(float(a[0]), float(a[2]) if a.size() > 2 else 0.0, float(a[1]))
			if _query.has("look"):
				var l: PackedStringArray = _query["look"].split(",")
				p.yaw = deg_to_rad(float(l[0]))
				p.pitch = deg_to_rad(float(l[1])) if l.size() > 1 else 0.0
		elif p.role == "seeker":
			_label(p, session.name_of(id))
		if run_bot:
			_give_brain(id, p)
	if me == null:
		# Watching (joined mid-match): a seeker without paint.
		me = Player.new()
		me.id = session.me
		me.role = "seeker"
		me.controlled = true
		me.has_camera = true
		me.input = hud.controls.input
		me.position = Vector3(0, 0, 18.5)
		add_child(me)
	hud.controls.set_role(me.role)
	bursts = HideRules.bursts(s)
	if _query.has("sparknow") and _round == 1:
		var at := _t() + 1.0
		for id in s["hidersAtStart"]:
			bursts.push_front({"at": at, "id": id})
			at += HideRules.SPARK_GAP
		bursts.sort_custom(func(a, b): return a["at"] < b["at"])
	_next_burst = 0
	var t := _t()
	while _next_burst < bursts.size() and bursts[_next_burst]["at"] <= t:
		_next_burst += 1
	if s["members"].has(session.me):
		var m: Dictionary = s["members"][session.me]
		var seekers := HideRules.ids(s, "seeker").size()
		var nh := HideRules.ids(s, "hider").size()
		hud.toast("Round %d: you're a seeker. Find %d hider%s" % [_round, nh, "" if nh == 1 else "s"] if m["role"] == "seeker"
			else "Round %d: you're a hider, a %s. Hide! (%d seeker%s)" % [_round, Props.display_name(m["prop"]).to_lower(), seekers, "" if seekers == 1 else "s"], 4.0)
	else:
		hud.toast("Watching this round; you'll play the next", 4.0)


func _has_bots() -> bool:
	if not session.in_room:
		return true
	for p in session.players:
		if bool(p.get("bot", false)):
			return true
	return false


func _give_brain(id: String, p: Player) -> void:
	var seed := hash([id, _round])
	if p.role == "seeker":
		brains[id] = Bots.Seeker.new(p, session.bot_level(id), _nav.get_navigation_map() if _nav else RID(), seed)
	else:
		brains[id] = Bots.Hider.new(p, seed)


func _label(p: Player, text: String) -> void:
	var l := Label3D.new()
	l.name = "Name"
	l.text = text
	l.position = Vector3(0, 2.05, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.pixel_size = 0.005
	l.outline_size = 10
	l.no_depth_test = false
	p.add_child(l)


## Rerolls and finds come back in the state: change the bodies to match.
func _update_members() -> void:
	var s := session.state
	for id in roster.keys():
		var p: Player = roster[id]
		if not s["members"].has(id):
			p.queue_free()
			roster.erase(id)
			brains.erase(id)
			continue
		var m: Dictionary = s["members"][id]
		var was: Dictionary = _known.get(id, {})
		if was.get("role") == m["role"] and was.get("prop") == m["prop"]:
			continue
		var found: bool = was.get("role") == "hider" and m["role"] == "seeker"
		_known[id] = {"role": m["role"], "prop": m["prop"]}
		p.set_role(m["role"], m["prop"])
		if found:
			Sparks.burst(self, p.global_position + Vector3(0, 0.6, 0), false)
			var by := ""
			for f in s["finds"]:
				if f["hider"] == id:
					by = f["seeker"]
			if p == me:
				hud.toast("%s found you! Now you're a seeker" % session.name_of(by), 3.5)
				hud.controls.set_role("seeker")
			else:
				hud.toast("%s found %s" % [("You" if by == session.me else session.name_of(by)), session.name_of(id)], 2.5)
				if p.get_node_or_null("Name") == null:
					_label(p, session.name_of(id))
			if brains.has(id) and session.is_host:
				p.controlled = true
				p.set_physics_process(true)
				p.velocity = Vector3.ZERO
				_give_brain(id, p)
		elif p == me:
			hud.toast("You're a %s now" % Props.display_name(m["prop"]).to_lower(), 1.8)


# ----------------------------------------------------------------- play --

func _process(delta: float) -> void:
	if _warm > 0:
		_warm -= 1
		if _warm == 0:
			_warm_up_done()
		elif _warm == 6 and me:
			_warm_up()
	var s := session.state
	if s.is_empty() or me == null:
		return
	var now := session.now_ms()
	var t := _t()
	var ph := HideRules.phase(s, now)
	_fire_cool -= delta
	var mine: Dictionary = s["members"].get(session.me, {})
	me.frozen = me.role == "seeker" and ph == "hide"
	for id in roster:
		if brains.has(id) and roster[id].role == "seeker":
			roster[id].frozen = ph == "hide"
	var input := hud.controls.input
	if input.take("fire") and me.role == "seeker" and ph == "seek" and _fire_cool <= 0 and not mine.is_empty():
		if int(mine["ammo"]) > 0:
			_fire_cool = 0.28
			_shoot(session.me, me, me.aim_transform())
		else:
			hud.toast("Out of paint!", 1.5)
	if input.take("reroll") and me.role == "hider" and ph != "over":
		if int(mine.get("rerolls", 0)) > 0:
			session.act({"type": "reroll"})
		else:
			hud.toast("No prop switches left", 1.5)
	if input.take("lock"):
		me.toggle_lock()
	if input.take("decoy") and me.role == "hider" and ph != "over":
		if int(mine.get("decoys", 0)) > 0:
			_drop_decoy(session.me, me.global_transform.origin, me.prop_basis)
			hud.toast("Decoy dropped", 1.2)
		else:
			hud.toast("No decoys left", 1.5)
	# Sparks on schedule.
	while _next_burst < bursts.size() and bursts[_next_burst]["at"] <= t:
		var b: Dictionary = bursts[_next_burst]
		_next_burst += 1
		var m: Dictionary = s["members"].get(b["id"], {})
		if ph != "over" and not m.is_empty() and m["role"] == "hider" and roster.has(b["id"]):
			var who: Player = roster[b["id"]]
			var at := who.global_position + Vector3(0, Props.size(who.kind).y * 0.6, 0)
			Sparks.burst(self, at)
			for id in brains:
				if brains[id] is Bots.Seeker:
					brains[id].hear(at)
	# Hider bots hide, then leave a couple of decoys somewhere else.
	for id in brains:
		if brains[id] is Bots.Hider:
			var hb: Bots.Hider = brains[id]
			hb.think(t, float(s["hideMs"]) / 1000.0, _is_free)
			if hb.hidden and not _decoyed.has(id):
				_decoyed[id] = true
				_bot_decoys(id, hb.body)
	# Positions out.
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = SEND_EVERY
		_send_positions()
	var next_mine := HideRules.time_to_next(bursts.slice(_next_burst), session.me, t) if me.role == "hider" else INF
	hud.show_round(s, session, me, t, ph, next_mine, delta)
	_debug_t -= delta
	if _debug_t <= 0.0 and OS.has_feature("web"):
		_debug_t = 0.5
		_publish_debug(ph)
	if ph == "over" and not _shown_over:
		_shown_over = true
		hud.toast(_results(s), HideRules.RESULTS_MS / 1000.0)


func _physics_process(delta: float) -> void:
	if session == null or session.state.is_empty():
		return
	var seek := HideRules.phase(session.state, session.now_ms()) == "seek"
	var hiders := []
	for id in roster:
		if roster[id].role == "hider":
			hiders.append(roster[id])
	var suspects := _scenery.duplicate()
	for d in _decoys.values():
		if is_instance_valid(d):
			suspects.append([d, d.global_position + Vector3(0, 0.3, 0)])
	for h in hiders:
		suspects.append([h, h.global_position])
	for id in brains:
		if brains[id] is Bots.Seeker:
			brains[id].think(delta, seek, suspects, hiders, _bot_fire.bind(id))


## Drop a decoy for `id` (you or a bot this game runs).
func _drop_decoy(id: String, at: Vector3, b: Basis) -> void:
	var q := b.get_rotation_quaternion()
	var a := {"type": "decoy", "at": [at.x, at.y, at.z], "q": [q.x, q.y, q.z, q.w]}
	if id != session.me:
		a["as"] = id
	session.act(a)


func _bot_decoys(id: String, body: Player) -> void:
	var places := TestBarn.hiding_places(body.kind)
	var dropped := 0
	for i in range(places.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = places[i]
		places[i] = places[j]
		places[j] = tmp
	for xf in places:
		if dropped >= 2:
			break
		if xf.origin.distance_to(body.global_position) > 4.0 and _is_free(xf, body):
			_drop_decoy(id, xf.origin, xf.basis)
			dropped += 1


## Decoys come from the round state: show new ones, pop removed ones.
func _sync_decoys() -> void:
	var want := {}
	for d in session.state.get("decoys", []):
		want[str(d["id"])] = d
	for id in _decoys.keys():
		if not want.has(id):
			var body: Node3D = _decoys[id]
			Sparks.burst(self, body.global_position + Vector3(0, 0.4, 0), false)
			body.queue_free()
			_decoys.erase(id)
	for id in want:
		if _decoys.has(id):
			continue
		var d: Dictionary = want[id]
		var at: Array = d["at"]
		var q: Array = d["q"]
		var xf := Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()), Vector3(at[0], at[1], at[2]))
		var body := TestBarn.prop_body(str(d["prop"]), xf)
		body.set_meta("decoy", id)
		var mi := MeshInstance3D.new()
		mi.mesh = Props.mesh(str(d["prop"]))
		body.add_child(mi)
		add_child(body)
		_decoys[id] = body


func _bot_fire(brain: Bots.Seeker, _target: Node3D, aim: Vector3, id: String) -> void:
	var m: Dictionary = session.state["members"].get(id, {})
	if m.is_empty() or int(m["ammo"]) <= 0:
		return
	var from := brain.body.eye()
	_shoot(id, brain.body, Transform3D(Basis.looking_at(aim - from), from))


## Fire a paintball for `id` (you or a bot this game runs): count it with
## the rules, show it, relay it, and report a find if it hits a hider.
func _shoot(id: String, shooter: Player, from: Transform3D) -> void:
	var a := {"type": "shoot"}
	if id != session.me:
		a["as"] = id
	session.act(a)
	var ci := _rng.randi_range(0, Paint.COLORS.size() - 1)
	var p := Paint.fire(self, from, Paint.COLORS[ci], shooter.get_rid())
	p.hit.connect(_on_paint_hit.bind(p.color, id))
	var o := p.global_position
	var d := p.velocity.normalized()
	session.relay({"t": "shot", "by": id, "o": [o.x, o.y, o.z], "d": [d.x, d.y, d.z], "c": ci})


func _on_paint_hit(collider: Object, point: Vector3, normal: Vector3, color: Color, by: String) -> void:
	if collider is StaticBody3D and collider.has_meta("decoy"):
		var a := {"type": "pop", "decoy": collider.get_meta("decoy")}
		if by != session.me:
			a["as"] = by
		session.act(a)
		if by == session.me:
			hud.toast("A decoy!", 1.2)
		return
	if collider is Player and collider.role == "hider" and collider.id != by:
		var a := {"type": "find", "hider": collider.id}
		if by != session.me:
			a["as"] = by
		session.act(a)
		if by == session.me:
			hud.hit_marker()
		return
	if collider is Player:
		return
	Paint.Splat.create(_paint_root, point, normal, color, _rng)


## Someone else's shot: show it fly and splat (they decide what it found).
func _remote_shot(d: Dictionary) -> void:
	_shots_seen += 1
	var shooter: Player = roster.get(str(d.get("by", "")))
	var o: Array = d["o"]
	var dir: Array = d["d"]
	var origin := Vector3(o[0], o[1], o[2])
	var fwd := Vector3(dir[0], dir[1], dir[2])
	var ci := int(d.get("c", 0)) % Paint.COLORS.size()
	var p := Paint.fire(self, Transform3D(Basis.looking_at(fwd), origin), Paint.COLORS[ci], shooter.get_rid() if shooter else RID())
	p.global_position = origin
	p.hit.connect(func(c, pt, n):
		if not c is Player and not (c is StaticBody3D and c.has_meta("decoy")):
			Paint.Splat.create(_paint_root, pt, n, Paint.COLORS[ci], _rng))


## A summary of what this game sees, for the end-to-end test
## (tests/e2e/hideseek.mjs reads window.hsDebug in each player's frame).
func _publish_debug(ph: String) -> void:
	var seen := {}
	var kinds := {}
	var roles := {}
	for id in roster:
		var p: Player = roster[id]
		seen[id] = [snappedf(p.global_position.x, 0.01), snappedf(p.global_position.y, 0.01), snappedf(p.global_position.z, 0.01)]
		kinds[id] = p.kind
		roles[id] = p.role
	var d := {"me": session.me, "host": session.is_host, "round": _round, "phase": ph, "roles": roles, "kinds": kinds,
		"seen": seen, "shotsSeen": _shots_seen, "sent": _sent, "got": _got, "finds": session.state.get("finds", []).size(), "bots": brains.size()}
	JavaScriptBridge.eval("window.hsDebug = %s" % JSON.stringify(d), true)


func _send_positions() -> void:
	if not session.in_room:
		return
	var out := []
	for id in roster:
		var p: Player = roster[id]
		if p == me or brains.has(id):
			var q := p.prop_basis.get_rotation_quaternion()
			var g := p.global_position
			out.append({"i": id, "p": [snappedf(g.x, 0.01), snappedf(g.y, 0.01), snappedf(g.z, 0.01)], "w": snappedf(p.yaw, 0.01),
				"q": [snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001), snappedf(q.w, 0.001)], "l": p.locked})
	if not out.is_empty():
		_sent += 1
		session.relay({"t": "pos", "r": _round, "a": out})


func _on_relay(_from: String, data: Variant) -> void:
	_got += 1
	if not data is Dictionary:
		return
	match str(data.get("t", "")):
		"pos":
			if int(data.get("r", -1)) != _round:
				return
			for e in data.get("a", []):
				var p: Player = roster.get(str(e.get("i", "")))
				if p == null or not p.remote:
					continue
				var pos: Array = e["p"]
				var q: Array = e["q"]
				p.hear(Vector3(pos[0], pos[1], pos[2]), float(e["w"]), Quaternion(q[0], q[1], q[2], q[3]).normalized(), bool(e.get("l", false)))
		"shot":
			_remote_shot(data)


## Is `xf` a free place for `body`'s prop (nothing in the way, something
## underneath)? For hider bots.
func _is_free(xf: Transform3D, body: Player) -> bool:
	var size := Props.size(body.kind)
	if absf(xf.origin.x) > 34.0 or absf(xf.origin.z) > 34.0:
		return false
	var box := BoxShape3D.new()
	box.size = size * 0.94
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * (size.y / 2 + 0.02))
	q.collision_mask = TestBarn.LAYER_WORLD | TestBarn.LAYER_PROPS | TestBarn.LAYER_PLAYERS
	q.exclude = [body.get_rid()]
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var down := PhysicsRayQueryParameters3D.create(xf.origin + Vector3(0, 0.1, 0), xf.origin - Vector3(0, 0.15, 0), TestBarn.LAYER_WORLD | TestBarn.LAYER_PROPS, [body.get_rid()])
	return not space.intersect_ray(down).is_empty()


func _results(s: Dictionary) -> String:
	var lines := ["Seekers win!" if s["winner"] == "seekers" else "Hiders win!"]
	var scores: Dictionary = s["scores"]
	var ids: Array = scores.keys()
	ids.sort_custom(func(a, b): return int(scores[a]) > int(scores[b]))
	for id in ids.slice(0, 5):
		lines.append("%s  %d" % [("You" if id == session.me else session.name_of(id)), int(scores[id])])
	return "\n".join(lines)


## Draw a burst, a splat and a paintball once behind the loading cover, so
## their shaders are compiled before play (racing LEARNINGS).
func _warm_up() -> void:
	var cam := me.aim_transform()
	var ahead := cam.origin - cam.basis.z * 3.0
	var p := Paint.fire(self, cam, Paint.COLORS[1], me.get_rid())
	p.set_physics_process(false)
	_warm_nodes = [Sparks.burst(self, ahead), Paint.Splat.create(self, ahead, cam.basis.z, Paint.COLORS[0], _rng), p]


func _warm_up_done() -> void:
	hud.cover(false)
	for n in _warm_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_warm_nodes.clear()


func _read_query() -> Dictionary:
	var raw := ""
	if OS.has_feature("web"):
		raw = str(JavaScriptBridge.eval("location.search", true)).trim_prefix("?")
	else:
		raw = "&".join(OS.get_cmdline_user_args())
	var out := {}
	for part in raw.split("&", false):
		var kv := part.split("=", true, 1)
		out[kv[0].trim_prefix("--")] = kv[1].uri_decode() if kv.size() > 1 else ""
	return out
