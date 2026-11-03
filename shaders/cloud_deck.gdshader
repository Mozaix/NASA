shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
// Rolling cloud tops for gas and ice giants (procedural; colours are interpretive).
uniform vec3 band_a : source_color = vec3(0.8);
uniform vec3 band_b : source_color = vec3(0.5);
uniform vec3 band_c : source_color = vec3(0.9);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float amp = 18.0;
uniform float t = 0.0;
varying vec3 wp;
float h_at(vec2 p) {
	float a = textureLod(noise_tex, p * 0.0009 + vec2(t * 0.002, 0.0), 0.0).r;
	float b = textureLod(noise_tex, p * 0.0042 - vec2(t * 0.004, t * 0.001), 0.0).r;
	return (a * 0.75 + b * 0.25 - 0.5) * 2.0;
}
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = h_at(w.xz) * amp;
	wp = vec3(w.x, VERTEX.y, w.z);
}
void fragment() {
	float n1 = texture(noise_tex, wp.xz * 0.0012 + vec2(t * 0.002, 0.0)).r;
	float n2 = texture(noise_tex, wp.xz * 0.009 - vec2(t * 0.004, 0.0)).r;
	float lat = wp.z * 0.0035 + (n1 - 0.5) * 2.6;
	float b = sin(lat * 3.0) * 0.5 + 0.5;
	vec3 c = mix(band_a, band_b, b);
	c = mix(c, band_c, smoothstep(0.45, 0.8, n2) * 0.6);
	float dx = dFdx(n2) * 40.0;
	float dy = dFdy(n2) * 40.0;
	NORMAL = normalize(NORMAL + vec3(dx, dy, 0.0));
	ALBEDO = c * (0.85 + n1 * 0.3);
	ROUGHNESS = 1.0;
}
