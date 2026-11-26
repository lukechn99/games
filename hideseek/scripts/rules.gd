class_name HideRules
extends RefCounted
## The round's rules on the same data, with the same names, as the room's
## rules (lib/games/hideseek/rules.ts): solo practice runs these, a room
## runs those, and the game reads either the same way. Keep the two in step;
## both have tests. Times in the state are host-clock milliseconds.
##
## State: {round, seed, startAt, hideMs, seekMs, seats, members{id: {role,
## prop, rerolls, ammo, foundAt}}, hidersAtStart, finds, scores, winner,
## overAt, sought}

const HIDE_MS := 45000.0
const SEEK_MS := 180000.0
const RESULTS_MS := 8000.0
const FINAL_STRETCH := 60.0      # sparks come faster in the last minute (s)
const SPARK_EVERY := 25.0
const SPARK_EVERY_FINAL := 15.0
const SPARK_GAP := 1.0           # hiders spark one at a time
const WARNING := 5.0             # edge flash before your own burst
const START_AMMO := 100
const AMMO_PER_FIND := 3
const REROLLS := 2
const PAINT_BRIGHT := 20.0
const PAINT_FADE := 20.0
const JUMP_HEIGHT := 1.3

## Same order as PROPS in rules.ts.
const PROPS := ["bale", "trash_can", "tire", "chair", "crate", "bucket", "rake"]


## Seekers for a room of `players` (bots count), at least one.
static func seeker_count(players: int) -> int:
	return maxi(1, (players + 1) / 3)


## Pick the seekers at random; everyone else hides.
static func deal_seekers(ids: Array, rng: RandomNumberGenerator) -> Array:
	var pool := ids.duplicate()
	pool.sort()
	var out := []
	for i in seeker_count(ids.size()):
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


static func random_prop(rng: RandomNumberGenerator, exclude := "") -> String:
	return Props.random_kind(rng, PROPS, exclude)


## A new match: the first round dealt.
static func setup(seats: Array, now: float, rng: RandomNumberGenerator) -> Dictionary:
	return deal({"seats": seats.duplicate(), "scores": {}, "sought": {}, "round": 0}, now, rng)


## Deal a round: seekers at random, a random prop for every hider.
static func deal(prev: Dictionary, now: float, rng: RandomNumberGenerator) -> Dictionary:
	var seats: Array = prev["seats"]
	var seekers := deal_seekers(seats, rng)
	var members := {}
	var sought: Dictionary = prev.get("sought", {}).duplicate()
	for id in seats:
		var seeker := seekers.has(id)
		members[id] = {"role": "seeker" if seeker else "hider", "prop": "" if seeker else random_prop(rng),
			"rerolls": 0 if seeker else REROLLS, "ammo": START_AMMO if seeker else 0, "foundAt": null}
		if seeker:
			sought[id] = int(sought.get(id, 0)) + 1
	return {"round": int(prev["round"]) + 1, "seed": rng.randi_range(0, 999999999), "startAt": now,
		"hideMs": HIDE_MS, "seekMs": SEEK_MS, "seats": seats, "members": members,
		"hidersAtStart": seats.filter(func(id): return not seekers.has(id)), "finds": [],
		"scores": prev.get("scores", {}).duplicate(), "winner": null, "overAt": null, "sought": sought}


static func elapsed(s: Dictionary, now: float) -> float:
	return now - float(s["startAt"])


static func phase(s: Dictionary, now: float) -> String:
	if s.get("winner") != null:
		return "over"
	return "hide" if elapsed(s, now) < float(s["hideMs"]) else "seek"


static func ids(s: Dictionary, role: String) -> Array:
	var m: Dictionary = s["members"]
	return m.keys().filter(func(id): return m[id]["role"] == role)


## Who has won at `now`, or "".
static func decide(s: Dictionary, now: float) -> String:
	var t := elapsed(s, now)
	if t < float(s["hideMs"]):
		return ""
	if ids(s, "hider").is_empty():
		return "seekers"
	if t >= float(s["hideMs"]) + float(s["seekMs"]):
		return "hiders"
	var seekers := ids(s, "seeker")
	if not seekers.is_empty() and seekers.all(func(id): return int(s["members"][id]["ammo"]) <= 0):
		return "hiders"
	return ""


## Apply one action. Returns {"state": ...} or {"error": ...}.
static func action(s: Dictionary, pid: String, a: Dictionary, now: float, rng: RandomNumberGenerator) -> Dictionary:
	var who: String = a.get("as", pid)
	var members: Dictionary = s["members"]
	if not members.has(who):
		return {"error": "You are not in this round."}
	var ph := phase(s, now)
	if ph == "over":
		return {"error": "The round is over."}
	var n := s.duplicate(true)
	var m: Dictionary = n["members"][who]
	match str(a.get("type", "")):
		"reroll":
			if m["role"] != "hider" or int(m["rerolls"]) <= 0:
				return {"error": "No rerolls left."}
			m["rerolls"] = int(m["rerolls"]) - 1
			m["prop"] = random_prop(rng, m["prop"])
		"shoot":
			if m["role"] != "seeker" or ph != "seek" or int(m["ammo"]) <= 0:
				return {"error": "Can't shoot now."}
			m["ammo"] = int(m["ammo"]) - 1
		"find":
			var hid := str(a.get("hider", ""))
			if m["role"] != "seeker" or ph != "seek" or not n["members"].has(hid) or n["members"][hid]["role"] != "hider":
				return {"error": "Not a hider."}
			var at := elapsed(s, now)
			m["ammo"] = int(m["ammo"]) + AMMO_PER_FIND
			var h: Dictionary = n["members"][hid]
			h["role"] = "seeker"
			h["ammo"] = START_AMMO
			h["foundAt"] = at
			n["finds"].append({"seeker": who, "hider": hid, "at": at})
		_:
			return {"error": "Unknown action."}
	return {"state": settle(n, now)}


## Called a few times a second: decide the round, then deal the next.
static func tick(s: Dictionary, now: float, rng: RandomNumberGenerator) -> Dictionary:
	if s.get("winner") != null:
		if now - float(s["overAt"]) >= RESULTS_MS:
			return deal(s, now, rng)
		return s
	return settle(s, now)


static func settle(s: Dictionary, now: float) -> Dictionary:
	if s.get("winner") != null:
		return s
	var w := decide(s, now)
	if w == "":
		return s
	var n := s.duplicate(true)
	n["winner"] = w
	n["overAt"] = now
	n["scores"] = _score(s, now)
	return n


## Points for the round (design 5): hiders 1 per 30 s survived in the seek
## phase and 3 for surviving; seekers 3 per find.
static func _score(s: Dictionary, now: float) -> Dictionary:
	var scores: Dictionary = s["scores"].duplicate()
	var hide := float(s["hideMs"])
	var end := minf(elapsed(s, now), hide + float(s["seekMs"]))
	for id in s["hidersAtStart"]:
		if not s["members"].has(id):
			continue
		var m: Dictionary = s["members"][id]
		var until: float = end if m["foundAt"] == null else float(m["foundAt"])
		var pts := int(floor(maxf(0.0, until - hide) / 30000.0)) + (3 if m["foundAt"] == null else 0)
		scores[id] = int(scores.get(id, 0)) + pts
	for f in s["finds"]:
		scores[f["seeker"]] = int(scores.get(f["seeker"], 0)) + 3
	return scores


# ------------------------------------------------------------- sparks --

## When each spark cycle starts, in seconds into the seek phase.
static func cycle_starts(seek_s: float) -> Array:
	var out := []
	var t := 0.0
	while true:
		var left := seek_s - t
		t += SPARK_EVERY if left > FINAL_STRETCH else SPARK_EVERY_FINAL
		if t >= seek_s:
			break
		out.append(t)
	return out


## Every burst of the round: [{at (seconds into the round), id}], sorted.
## Each cycle sparks the round's hiders in a fresh order from the round's
## seed, so every phone works out the same schedule with no messages.
static func bursts(s: Dictionary) -> Array:
	var order0: Array = s["hidersAtStart"].duplicate()
	order0.sort()
	var hide_s := float(s["hideMs"]) / 1000.0
	var out := []
	var cycle := 0
	for start in cycle_starts(float(s["seekMs"]) / 1000.0):
		var order := order0.duplicate()
		var r := RandomNumberGenerator.new()
		r.seed = hash(["sparks", int(s["seed"]), cycle])
		for i in range(order.size() - 1, 0, -1):
			var j := r.randi_range(0, i)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		for i in order.size():
			out.append({"at": hide_s + start + i * SPARK_GAP, "id": order[i]})
		cycle += 1
	return out


## Seconds until `id`'s next burst after `t` (seconds into the round).
static func time_to_next(bursts_list: Array, id: String, t: float) -> float:
	for b in bursts_list:
		if b["id"] == id and b["at"] > t:
			return b["at"] - t
	return INF


## Seconds until the next cycle, as everyone sees it.
static func time_to_next_cycle(s: Dictionary, t: float) -> float:
	var hide_s := float(s["hideMs"]) / 1000.0
	for c in cycle_starts(float(s["seekMs"]) / 1000.0):
		if hide_s + c > t:
			return hide_s + c - t
	return INF


## 1 while fresh, then fading to 0 (design 7).
static func paint_alpha(age: float) -> float:
	if age <= PAINT_BRIGHT:
		return 1.0
	return clampf(1.0 - (age - PAINT_BRIGHT) / PAINT_FADE, 0.0, 1.0)


## Speed needed to jump JUMP_HEIGHT under `gravity`.
static func jump_speed(gravity: float) -> float:
	return sqrt(2.0 * gravity * JUMP_HEIGHT)
