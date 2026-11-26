class_name Hud
extends CanvasLayer
## Timer, next-spark countdown, ammo or rerolls, crosshair, toasts, the
## seekers' blindfold in the hide phase, and the hider's edge flash.

const EDGE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.25, 1.0);
void fragment() {
	vec2 d = min(UV, 1.0 - UV);
	float e = 1.0 - smoothstep(0.0, 0.11, min(d.x * 0.6, d.y));
	COLOR = vec4(tint.rgb, tint.a * e * strength);
}
"""

var controls: Controls
var _clock: Label
var _sparks: Label
var _status: Label
var _toast: Label
var _help: Label
var _blind: ColorRect
var _blind_text: Label
var _edge: ColorRect
var _cover: ColorRect
var _cross: Control
var _toast_left := 0.0
var _marker_left := 0.0
var _flash_phase := 0.0


func _init() -> void:
	layer = 5


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_edge = _rect(root, Color.WHITE)
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = EDGE_SHADER
	_edge.material = sm
	_blind = _rect(root, Color(0.04, 0.05, 0.08, 0.97))
	_blind_text = _label(_blind, 34, Control.PRESET_CENTER)
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	root.add_child(_cross)
	_clock = _label(root, 30, Control.PRESET_CENTER_TOP)
	_clock.position.y += 14
	_sparks = _label(root, 20, Control.PRESET_TOP_RIGHT)
	_sparks.position += Vector2(-24, 18)
	# Top left, clear of the phone's movement stick.
	_status = _label(root, 22, Control.PRESET_TOP_LEFT)
	_status.position += Vector2(18, 12)
	_toast = _label(root, 30, Control.PRESET_CENTER)
	_toast.position.y -= 110
	_help = _label(root, 15, Control.PRESET_TOP_LEFT)
	_help.position += Vector2(18, 48)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help.modulate.a = 0.8
	controls = Controls.new()
	root.add_child(controls)
	_cover = _rect(root, Color(0.53, 0.78, 0.95))


func _rect(parent: Control, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _label(parent: Control, fs: int, preset: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH if preset in [Control.PRESET_CENTER, Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM] else (Control.GROW_DIRECTION_BEGIN if preset == Control.PRESET_TOP_RIGHT else Control.GROW_DIRECTION_END)
	if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_CENTER_BOTTOM]:
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return l


func cover(on: bool) -> void:
	_cover.visible = on


func toast(text: String, seconds := 2.5) -> void:
	_toast.text = text
	_toast_left = seconds


func hit_marker() -> void:
	_marker_left = 0.35


## Called every frame by the game, with the round state (rules.ts's shape).
func show_round(s: Dictionary, session: Session, me: Player, t: float, ph: String, next_mine: float, delta: float) -> void:
	var hide_s := float(s["hideMs"]) / 1000.0
	var seek_s := float(s["seekMs"]) / 1000.0
	var mine: Dictionary = s["members"].get(session.me, {})
	if ph == "hide":
		_clock.text = "Hide!  %s" % _mmss(hide_s - t)
	elif ph == "seek":
		_clock.text = "Seek  %s" % _mmss(hide_s + seek_s - t)
	else:
		_clock.text = "Seekers win!" if s["winner"] == "seekers" else "Hiders win!"
	var nc := HideRules.time_to_next_cycle(s, t)
	_sparks.text = "Sparks in %d" % ceili(nc) if ph == "seek" and nc < INF else ""
	_sparks.visible = _sparks.text != ""
	var hiders_left := HideRules.ids(s, "hider").size()
	if mine.is_empty():
		_status.text = "Watching · Hiders left %d" % hiders_left
		_status.add_theme_color_override("font_color", Color.WHITE)
	elif me.role == "seeker":
		var ammo := int(mine["ammo"])
		_status.text = "Seeker · Paintballs %d · Hiders left %d" % [ammo, hiders_left]
		_status.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if ammo <= 10 else Color.WHITE)
	else:
		_status.text = "%s · Rerolls %d · %s" % [Props.display_name(me.kind), int(mine["rerolls"]), "Locked" if me.locked else "Unlocked"]
		_status.add_theme_color_override("font_color", Color.WHITE)
	_blind.visible = me.role == "seeker" and ph == "hide"
	_blind_text.text = "Hiders are hiding…\n%s" % _mmss(hide_s - t)
	_cross.visible = me.role == "seeker" and not _blind.visible
	_cross.queue_redraw()
	_edge_flash(next_mine, delta)
	_toast_left -= delta
	_toast.visible = _toast_left > 0
	_toast.modulate.a = clampf(_toast_left * 2.0, 0, 1)
	_marker_left -= delta
	var touch := controls.touching
	if me.role == "seeker":
		_help.text = "" if touch else "Click to look around\nWASD move · Space jump\nClick to paint"
	else:
		_help.text = "" if touch else "Click to look around\nWASD move · Space jump\nF reroll · R lock rotation"


## The hider's warning (design 6): edges flash for WARNING seconds before
## their own burst, faster as it gets closer. No numbers.
func _edge_flash(until: float, delta: float) -> void:
	var s := 0.0
	if until <= HideRules.WARNING:
		var close := 1.0 - until / HideRules.WARNING
		_flash_phase += delta * lerpf(1.2, 5.0, close)
		s = pow(maxf(sin(_flash_phase * TAU), 0.0), 2.0) * lerpf(0.55, 1.0, close)
	else:
		_flash_phase = 0.0
	(_edge.material as ShaderMaterial).set_shader_parameter("strength", s)
	_edge.visible = s > 0.001


func edge_strength() -> float:
	return (_edge.material as ShaderMaterial).get_shader_parameter("strength")


func _draw_cross() -> void:
	var c := Color(1, 1, 1, 0.9)
	_cross.draw_circle(Vector2.ZERO, 3.0, c)
	if _marker_left > 0:
		var r := Color(1, 0.3, 0.4)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_cross.draw_line(d * 8, d * 18, r, 3.0)


static func _mmss(s: float) -> String:
	var n := maxi(0, ceili(s))
	return "%d:%02d" % [n / 60, n % 60]
