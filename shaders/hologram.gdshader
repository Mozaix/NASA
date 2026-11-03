shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Projected-light look for the mission builder.
uniform vec3 color : source_color = vec3(0.3, 0.85, 1.0);
uniform float flash = 0.0;
uniform float strength = 1.0;
uniform sampler2D map_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_map = false;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.8);
	float scan = 0.72 + 0.28 * sin(wp.y * 42.0 - TIME * 4.0);
	float flicker = 0.94 + 0.06 * sin(TIME * 23.0);
	float surface = 0.16;
	if (use_map) {
		vec3 m = texture(map_tex, UV).rgb;
		surface = 0.08 + 0.7 * dot(m, vec3(0.33));
	}
	vec3 base = mix(color, vec3(1.0, 0.8, 0.35), flash);
	ALBEDO = base * (surface + rim * 1.3 + flash * 0.5) * scan * flicker * strength;
}
