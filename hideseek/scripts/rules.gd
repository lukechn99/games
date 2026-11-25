class_name HideRules
extends RefCounted
## The round's rules, with no nodes, so they can be tested headless and
## later mirrored in lib/games/hideseek/rules.ts (design doc 13).
## Times are seconds since the round started, on the host's clock.

const HIDE_TIME := 45.0
const SEEK_TIME := 180.0
const FINAL_STRETCH := 60.0      # sparks come faster in the last minute
const SPARK_EVERY := 25.0
const SPARK_EVERY_FINAL := 15.0
const SPARK_GAP := 1.0           # hiders spark one at a time
const WARNING := 5.0             # edge flash before your own burst
const START_AMMO := 12
const AMMO_PER_FIND := 3
const REROLLS := 2
const PAINT_BRIGHT := 20.0
const PAINT_FADE := 20.0
const JUMP_HEIGHT := 1.3

var hide_time := HIDE_TIME
var seek_time := SEEK_TIME
var seed := 1
var pool: Array = []
## id -> {role: "hider"|"seeker", prop, rerolls, ammo, found_at}
var players := {}
var finds: Array = []            # [{seeker, hider, at}]
var _rng := RandomNumberGenerator.new()


func _init(prop_pool: Array, round_seed := 1) -> void:
	pool = prop_pool
	seed = round_seed
	_rng.seed = hash(["props", round_seed])


func add_hider(id: String) -> void:
	players[id] = {"role": "hider", "prop": Props.random_kind(_rng, pool), "rerolls": REROLLS, "ammo": 0, "found_at": -1.0}


func add_seeker(id: String) -> void:
	players[id] = {"role": "seeker", "prop": "", "rerolls": 0, "ammo": START_AMMO, "found_at": -1.0}


func ids(role: String) -> Array:
	return players.keys().filter(func(id): return players[id]["role"] == role)


## Swap a hider's prop for a different random one. False when out of rerolls.
func reroll(id: String) -> bool:
	var p: Dictionary = players[id]
	if p["role"] != "hider" or p["rerolls"] <= 0:
		return false
	p["rerolls"] -= 1
	p["prop"] = Props.random_kind(_rng, pool, p["prop"])
	return true


## Spend a paintball. False (no shot) when empty.
func shoot(id: String) -> bool:
	var p: Dictionary = players[id]
	if p["role"] != "seeker" or p["ammo"] <= 0:
		return false
	p["ammo"] -= 1
	return true


## A seeker paints a hider: the hider joins the seekers (design 4).
func find(seeker_id: String, hider_id: String, at: float) -> bool:
	var h: Dictionary = players.get(hider_id, {})
	if h.is_empty() or h["role"] != "hider":
		return false
	h["role"] = "seeker"
	h["found_at"] = at
	h["ammo"] = START_AMMO
	if players.has(seeker_id):
		players[seeker_id]["ammo"] += AMMO_PER_FIND
	finds.append({"seeker": seeker_id, "hider": hider_id, "at": at})
	return true


func phase(t: float) -> String:
	if t < hide_time:
		return "hide"
	if winner(t) != "":
		return "over"
	return "seek"


## "" while the round is on; "seekers" or "hiders" once it's decided.
func winner(t: float) -> String:
	if t < hide_time:
		return ""
	if ids("hider").is_empty():
		return "seekers"
	if t >= hide_time + seek_time:
		return "hiders"
	var seekers := ids("seeker")
	if not seekers.is_empty() and seekers.all(func(id): return players[id]["ammo"] <= 0):
		return "hiders"
	return ""


## When each spark cycle starts, in seconds into the seek phase.
func cycle_starts() -> Array:
	var out := []
	var t := 0.0
	while true:
		var left := seek_time - t
		t += SPARK_EVERY if left > FINAL_STRETCH else SPARK_EVERY_FINAL
		if t >= seek_time:
			break
		out.append(t)
	return out


## Every burst of the round: [{at (round time), id}], sorted. Each cycle
## sparks the hiders in a fresh random order, so the order gives nothing
## away. A burst belongs to whoever was a hider at the round's start; skip
## the ones already found with `burst_live`.
func bursts(hider_ids: Array) -> Array:
	var out := []
	var cycle := 0
	for start in cycle_starts():
		var order := hider_ids.duplicate()
		order.sort()
		var r := RandomNumberGenerator.new()
		r.seed = hash(["sparks", seed, cycle])
		for i in range(order.size() - 1, 0, -1):
			var j := r.randi_range(0, i)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		for i in order.size():
			out.append({"at": hide_time + start + i * SPARK_GAP, "id": order[i]})
		cycle += 1
	return out


func burst_live(b: Dictionary) -> bool:
	var p: Dictionary = players.get(b["id"], {})
	return not p.is_empty() and p["role"] == "hider"


## Seconds until `id`'s next burst after `t` (INF if none).
static func time_to_next(bursts_list: Array, id: String, t: float) -> float:
	for b in bursts_list:
		if b["id"] == id and b["at"] > t:
			return b["at"] - t
	return INF


## Seconds until the next cycle, as everyone sees it.
func time_to_next_cycle(t: float) -> float:
	for s in cycle_starts():
		var at: float = hide_time + s
		if at > t:
			return at - t
	return INF


## 1 while fresh, then fading to 0 (design 7).
static func paint_alpha(age: float) -> float:
	if age <= PAINT_BRIGHT:
		return 1.0
	return clampf(1.0 - (age - PAINT_BRIGHT) / PAINT_FADE, 0.0, 1.0)


## Speed needed to jump JUMP_HEIGHT under `gravity`.
static func jump_speed(gravity: float) -> float:
	return sqrt(2.0 * gravity * JUMP_HEIGHT)
