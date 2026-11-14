class_name Viewpoints
extends RefCounted
## Each track's fixed camera spots (design doc 14.3): where the verify
## command measures what's drawn and takes its pictures, the same every run.
## Every track gets eight spots evenly round the lap, one over the starting
## grid, one in the middle of each alternate route, and one from the air. A track adds named spots for
## its set pieces in EXTRA: [name, metres round the lap, side, height, look
## ahead, "b" to stand on the alternate route there].

const EVEN := 8
const EXTRA := {
	"frost": [["hairpin", 176.0, 0.0, 2.6, 24.0, ""]],
}


## [{name, pos, target}] for this track.
static func of(track: Track) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in EVEN:
		out.append(_spot(track, "lap%02d" % int(100.0 * i / EVEN), track.length * i / EVEN + 2.0, 0.0, 3.0, 30.0, false))
	# Over the whole starting grid: eight karts in one view.
	var last := track.grid_transform(7)
	var line := track.transform_at(0.0)
	out.append({"name": "grid", "pos": last.origin + last.basis.z * 9.0 + Vector3.UP * 4.5, "target": line.origin + Vector3.UP * 0.5})
	# The middle of each alternate route.
	var seen := {}
	var from := {}
	var d := 0.0
	while d < track.length:
		var bi := track.branch_at(d)
		if bi >= 0:
			if not from.has(bi):
				from[bi] = d
			seen[bi] = d
		d += 5.0
	for bi in seen:
		var mid: float = (float(from[bi]) + float(seen[bi])) * 0.5
		out.append(_spot(track, "route%d" % bi, mid, 0.0, 3.0, 30.0, true))
	for e: Array in EXTRA.get(track.layout, []):
		out.append(_spot(track, e[0], e[1], e[2], e[3], e[4], e[5] == "b"))
	# From the air: above the middle of the lap, high enough to see it all.
	var lo := Vector3.INF
	var hi := -Vector3.INF
	d = 0.0
	while d < track.length:
		var p := track.transform_at(d).origin
		lo = lo.min(p)
		hi = hi.max(p)
		d += 20.0
	var mid3 := (lo + hi) * 0.5
	var reach := maxf(hi.x - lo.x, hi.z - lo.z)
	out.append({"name": "air", "pos": mid3 + Vector3(0.0, reach * 0.75, reach * 0.55), "target": mid3})
	return out


static func _spot(track: Track, name: String, off: float, side: float, height: float, look: float, on_branch: bool) -> Dictionary:
	var f := track.transform_at(off)
	var lf := track.transform_at(off + look)
	if on_branch and track.branch_at(off) >= 0:
		var bi := track.branch_at(off)
		f = track.branch_frame(off, bi)
		lf = track.branch_frame(off + look, bi)
	return {"name": name, "pos": f.origin + f.basis.x * side + Vector3.UP * height, "target": lf.origin + Vector3.UP * 1.5}
