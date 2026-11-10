class_name GrandPrixSummary
extends RefCounted
## Build final standings from the room's completed-race snapshots. Missing
## historical data is distinct from a recorded DNF (older rooms/clients).

const TRACK_NAMES := {"meadow": "Meadow Loop", "mine": "Mining Mountain", "frost": "Frosty Pass"}


static func ranked_ids(points: Dictionary) -> Array:
	var ids := points.keys()
	ids.sort_custom(func(a, b):
		return int(points[a]) > int(points[b]) if int(points[a]) != int(points[b]) else str(a) < str(b))
	return ids


static func build(cup: Dictionary, me: String, name_of: Callable) -> Dictionary:
	var history: Array = cup.get("results", [])
	var tracks: Array = cup.get("tracks", ["meadow", "mine", "frost"])
	var points: Dictionary = cup.get("points", {})
	var headers := []
	for track in tracks:
		headers.append(TRACK_NAMES.get(track, str(track)))
	var rows := []
	var ids := ranked_ids(points)
	for i in ids.size():
		var id := str(ids[i])
		var cells := []
		var total_time := 0.0
		var finished := 0
		var known := 0
		for track in tracks:
			var record: Dictionary = {}
			for result in history:
				if result.get("track") == track:
					record = result
					break
			var finish: Dictionary = record.get("finish", {})
			if not record.is_empty():
				known += 1
			var best := -1.0
			for lap in (record.get("laps", {}) as Dictionary).get(id, []):
				best = float(lap) if best < 0.0 else minf(best, float(lap))
			var time := float(finish.get(id, -1.0))
			if time >= 0.0:
				finished += 1
				total_time += time
			cells.append({"available": not record.is_empty(), "time": time, "best": best,
				"place": int((record.get("places", {}) as Dictionary).get(id, 0)),
				"points": int((record.get("points", {}) as Dictionary).get(id, 0))})
		rows.append({"place": i + 1, "name": "You" if id == me else str(name_of.call(id)),
			"you": id == me, "points": int(points[id]), "tracks": cells,
			"finished": finished, "known": known, "total_time": total_time if finished == tracks.size() else -1.0})
	return {"headers": headers, "rows": rows}
