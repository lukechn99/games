class_name Spots
extends Node
## ?spots: visits each of the track's viewpoints (Viewpoints), with the race
## frozen on the grid, and at each one counts what the frame draws, then waits
## for the page to take its picture. tools/verify/verify.mjs drives it:
##   window.__spot = {i, name}   set when a spot is ready to photograph
##   window.__spot_ack = i       the page's reply; the game moves on
##   window.__spots = {...}      the results, when all are done
## Outside a browser it just measures and prints "[spots] {json}".

const SETTLE := 10        # frames to let the view settle before measuring
const SAMPLE := 4         # frames measured
const LOAD_FRAMES := 40   # at the start: scenery placed late, shaders warmed

var race: Node            # main.gd
var _spots: Array[Dictionary] = []
var _i := -1
var _frame := 0
var _draws := 0.0
var _prims := 0.0
var _objects := 0.0
var _waiting := false
var _wait_frames := 0
var _out := []
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _i < 0:
		if _frame < LOAD_FRAMES:
			return
		# Freeze the race where it stands: karts on the grid, nothing moving.
		get_tree().paused = true
		_spots = Viewpoints.of(race.track)
		var cam: Camera3D = race.camera
		cam.set_process(false)
		cam.set_physics_process(false)
		cam.fov = 70.0
		_next()
		return
	if _waiting:
		_wait_frames += 1
		var ack := int(JavaScriptBridge.eval("window.__spot_ack ?? -1", true)) if OS.has_feature("web") else _i
		if ack == _i or _wait_frames > 1800:
			_next()
		return
	if _frame > SETTLE:
		_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	if _frame >= SETTLE + SAMPLE:
		var s: Dictionary = _spots[_i]
		_out.append({"name": s["name"], "draws": int(round(_draws / SAMPLE)), "tris_k": int(round(_prims / SAMPLE / 1000.0)), "objects": int(round(_objects / SAMPLE))})
		_waiting = true
		_wait_frames = 0
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__spot = {i: %d, name: '%s'};" % [_i, s["name"]], true)


func _next() -> void:
	_i += 1
	_waiting = false
	_frame = 0
	_draws = 0.0
	_prims = 0.0
	_objects = 0.0
	if _i >= _spots.size():
		_done = true
		var json := JSON.stringify({"track": race.track.layout, "quality": Controls.quality_name().to_lower(), "spots": _out})
		print("[spots] ", json)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__spots = " + json + ";", true)
		return
	var s: Dictionary = _spots[_i]
	var cam: Camera3D = race.camera
	cam.global_position = s["pos"]
	cam.look_at(s["target"], Vector3.UP)
