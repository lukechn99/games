class_name ItemBox
extends Control
## The item you're holding, in a glossy rounded frame at the top left, as in
## Mario Kart (design doc 10.3).

var item := ""
var hint := ""   # the key to use it, on keyboards


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.13, 0.24, 0.78)
	sb.set_corner_radius_all(int(size.x * 0.22))
	sb.set_border_width_all(4)
	sb.border_color = Color(0.86, 0.9, 1.0, 0.95)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	draw_style_box(sb, r)
	# A sheen across the top half.
	var gloss := StyleBoxFlat.new()
	gloss.bg_color = Color(1, 1, 1, 0.12)
	gloss.set_corner_radius_all(int(size.x * 0.18))
	draw_style_box(gloss, Rect2(Vector2(7, 7), Vector2(size.x - 14, size.y * 0.42)))
	TouchControls.draw_item_icon(self, size * 0.5, size.x * 0.3, item)
	if hint != "" and item != "":
		var font := get_theme_default_font()
		draw_string_outline(font, Vector2(size.x - 22, size.y - 8), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(0.05, 0.05, 0.1))
		draw_string(font, Vector2(size.x - 22, size.y - 8), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
