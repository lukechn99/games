extends Node3D
## H0 sandbox (design doc 16): the test barn, you as a seeker or a hider,
## and three sandbox hiders sitting in hand-placed spots. Runs one round
## after another; Tab (or Switch) changes sides.
##
## Test links: ?role=hider, ?hide=SECONDS, ?t=SECONDS (start the clock
## there), ?at=X,Z[,Y]&look=YAW,PITCH (degrees), ?seed=N, ?sparknow,
## ?relief=off (no normal maps), ?shadows=off, ?ambient=E&sunscale=K
## (light levels with shadows on, for tuning).

const SANDBOX_HIDE := 15.0       # the real game hides for 45 s
const SANDBOX_HIDERS := 3

var rules: HideRules
var me: Player
var hiders := {}                 # id -> Player (sandbox hiders)
var bursts: Array = []
var t := 0.0
var role := "seeker"
var hud: Hud
var _next_burst := 0
var _round_over_at := -1.0
var _fire_cool := 0.0
var _paint_root: Node3D
var _rng := RandomNumberGenerator.new()
var _query := {}
var _round := 0
var _warm := 0
var _warm_nodes: Array[Node] = []


func _ready() -> void:
	_query = _read_query()
	role = "hider" if _query.get("role", "") == "hider" else "seeker"
	Props.relief = _query.get("relief", "on") != "off"
	TestBarn.environment(self, _query.get("shadows", "on") != "off", float(_query.get("sunscale", "-1")), float(_query.get("ambient", "-1")))
	TestBarn.build(self)
	_paint_root = Node3D.new()
	_paint_root.name = "Paint"
	add_child(_paint_root)
	hud = Hud.new()
	add_child(hud)
	_start_round()
	_warm_up()


## Draw a burst, a splat and a paintball once behind the loading cover, so
## their shaders are compiled before play (racing LEARNINGS).
func _warm_up() -> void:
	hud.cover(true)
	var cam := me.aim_transform()
	var ahead := cam.origin - cam.basis.z * 3.0
	var p := Paint.fire(self, cam, Paint.COLORS[1], me.get_rid())
	p.set_physics_process(false)
	_warm_nodes = [Sparks.burst(self, ahead), Paint.Splat.create(self, ahead, cam.basis.z, Paint.COLORS[0], _rng), p]
	_warm = 12


func _start_round() -> void:
	_round += 1
	for c in _paint_root.get_children():
		c.queue_free()
	for h in hiders.values():
		h.queue_free()
	hiders.clear()
	if me:
		me.queue_free()
	var seed := int(_query.get("seed", "0")) + _round
	_rng.seed = hash(["sandbox", seed])
	rules = HideRules.new(TestBarn.pool(), seed)
	rules.hide_time = float(_query.get("hide", str(SANDBOX_HIDE)))
	var spots := TestBarn.SPOTS.duplicate()
	for i in range(spots.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	for i in SANDBOX_HIDERS:
		var id := "hider%d" % (i + 1)
		rules.add_hider(id)
		rules.players[id]["prop"] = spots[i][0]
		var h := Player.new()
		h.id = id
		h.role = "hider"
		h.kind = spots[i][0]
		add_child(h)
		h.place(TestBarn.spot_transform(spots[i]))
		hiders[id] = h
	if role == "seeker":
		rules.add_seeker("me")
	else:
		rules.add_hider("me")
	me = Player.new()
	me.id = "me"
	me.controlled = true
	me.role = role
	me.kind = rules.players["me"]["prop"]
	me.input = hud.controls.input
	if role == "seeker":
		me.position = Vector3(0, 0, 19)
	else:
		me.position = Vector3(0, 0, 2)
	if _query.has("at"):
		var a: PackedStringArray = _query["at"].split(",")
		me.position = Vector3(float(a[0]), float(a[2]) if a.size() > 2 else 0.0, float(a[1]))
	if _query.has("look"):
		var l: PackedStringArray = _query["look"].split(",")
		me.yaw = deg_to_rad(float(l[0]))
		me.pitch = deg_to_rad(float(l[1])) if l.size() > 1 else 0.0
	add_child(me)
	hud.controls.set_role(role)
	t = float(_query.get("t", "0")) if _round == 1 else 0.0
	bursts = rules.bursts(rules.ids("hider"))
	if _query.has("sparknow") and _round == 1:
		var at := t + 1.0
		for id in rules.ids("hider"):
			bursts.push_front({"at": at, "id": id})
			at += HideRules.SPARK_GAP
		bursts.sort_custom(func(a, b): return a["at"] < b["at"])
	_next_burst = 0
	while _next_burst < bursts.size() and bursts[_next_burst]["at"] <= t:
		_next_burst += 1
	_round_over_at = -1.0
	hud.toast("You're a seeker: find %d hiders" % SANDBOX_HIDERS if role == "seeker" else "You're a %s. Hide!" % Props.display_name(me.kind))


func _process(delta: float) -> void:
	if _warm > 0:
		_warm -= 1
		if _warm == 0:
			hud.cover(false)
			for n in _warm_nodes:
				if is_instance_valid(n):
					n.queue_free()
			_warm_nodes.clear()
	t += delta
	_fire_cool -= delta
	var ph := rules.phase(t)
	me.frozen = me.role == "seeker" and ph == "hide"
	var input := hud.controls.input
	if input.take("switch_role"):
		role = "hider" if role == "seeker" else "seeker"
		_start_round()
		return
	if input.take("fire") and me.role == "seeker" and ph == "seek" and _fire_cool <= 0:
		if rules.shoot("me"):
			_fire_cool = 0.28
			var p := Paint.fire(self, me.aim_transform(), Paint.COLORS[_rng.randi_range(0, Paint.COLORS.size() - 1)], me.get_rid())
			p.hit.connect(_on_paint_hit.bind(p.color))
		else:
			hud.toast("Out of paint!", 1.5)
	if input.take("reroll") and me.role == "hider" and ph != "over":
		if rules.reroll("me"):
			me.set_role("hider", rules.players["me"]["prop"])
			hud.toast("You're a %s now" % Props.display_name(me.kind), 1.8)
		else:
			hud.toast("No rerolls left", 1.5)
	if input.take("lock"):
		me.toggle_lock()
	# Sparks on schedule.
	while _next_burst < bursts.size() and bursts[_next_burst]["at"] <= t:
		var b: Dictionary = bursts[_next_burst]
		_next_burst += 1
		if rules.burst_live(b) and ph != "over":
			var who: Player = me if b["id"] == "me" else hiders.get(b["id"])
			if who:
				Sparks.burst(self, who.global_position + Vector3(0, Props.size(who.kind).y * 0.6, 0))
	var mine := HideRules.time_to_next(bursts.slice(_next_burst), "me", t) if me.role == "hider" else INF
	hud.show_state(rules, me, t, mine, delta)
	var w := rules.winner(t)
	if w != "" and _round_over_at < 0:
		_round_over_at = t
		hud.toast("Seekers win!" if w == "seekers" else "Hiders win!", 5.0)
	if _round_over_at >= 0 and t - _round_over_at > 6.0:
		_start_round()


func _on_paint_hit(collider: Object, point: Vector3, normal: Vector3, color: Color) -> void:
	if collider is Player and collider.role == "hider" and collider != me:
		var h: Player = collider
		if rules.find("me", h.id, t):
			Sparks.burst(self, h.global_position + Vector3(0, Props.size(h.kind).y * 0.5, 0), false)
			hiders.erase(h.id)
			h.queue_free()
			hud.hit_marker()
			hud.toast("Found a hider in the %s! +%d paintballs" % [Props.display_name(h.kind).to_lower(), HideRules.AMMO_PER_FIND])
		return
	Paint.Splat.create(_paint_root, point, normal, color, _rng)


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
