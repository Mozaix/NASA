shader_type spatial;
// Ground of the 3D launch site: the NASA/USGS Landsat colour (30 m pixels) with fine noise on top,
// so the desert keeps some texture when the camera is close to the pad.

uniform sampler2D color_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 48.0;

void fragment() {
	vec3 c = texture(color_tex, UV).rgb;
	float d1 = texture(detail_tex, UV * detail_scale).r;
	float d2 = texture(detail_tex, UV * detail_scale * 6.7 + vec2(0.31, 0.17)).r;
	c *= 0.86 + 0.22 * d1 + 0.12 * (d2 - 0.5);
	ALBEDO = c;
	ROUGHNESS = 0.96;
	SPECULAR = 0.2;
}
