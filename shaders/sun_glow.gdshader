shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.9, 0.7);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float g = pow(clamp(1.0 - r, 0.0, 1.0), 3.2);
	ALBEDO = color * g * 2.2;
}
