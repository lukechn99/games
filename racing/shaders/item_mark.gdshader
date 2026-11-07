// The question mark inside the item box: bold yellow with an orange rim
// (the rim is its own mesh, MarkEdge). Unshaded so it stays bright.
shader_type spatial;
// Drawn after the see-through shell (alpha pass, higher priority), so the
// pink jelly doesn't tint the yellow to orange.
render_mode unshaded, depth_draw_never;

uniform vec3 color : source_color = vec3(1.0, 0.88, 0.22);
uniform float size = 1.2;
uniform float lift = 0.05;   // toward the camera: the yellow face sits in front of its orange rim

void vertex() {
	// Always face the camera, so the question mark reads while the box spins.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size;
	VERTEX.x *= 1.25;   // a chunkier question mark
	VERTEX.z += lift;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = color * mix(0.8, 1.15, facing);
	ALPHA = 1.0;
}
