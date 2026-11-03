shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(0.4, 0.6, 1.0);
uniform float strength = 1.0;
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float rim = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	float lit = smoothstep(-0.35, 0.6, dot(-wn, normalize(sun_dir)));
	ALBEDO = color * rim * lit * strength * 1.6;
}
