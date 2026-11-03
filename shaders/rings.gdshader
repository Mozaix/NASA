shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_lambert, specular_disabled;
// Procedural ring brightness: artistic, with the Cassini Division placed at about 1.95 planet radii.
uniform float inner = 1.24;
uniform float outer = 2.27;
uniform vec3 tint : source_color = vec3(0.86, 0.78, 0.62);
varying float rr;
void vertex() { rr = length(VERTEX.xz); }
float bands(float r) {
	return 0.55 + 0.25 * sin(r * 90.0) * sin(r * 37.0) + 0.2 * sin(r * 211.0);
}
void fragment() {
	float a = smoothstep(inner, inner + 0.03, rr) * (1.0 - smoothstep(outer - 0.02, outer, rr));
	float gap = 1.0 - (smoothstep(1.92, 1.94, rr) * (1.0 - smoothstep(2.0, 2.02, rr)));
	float c_ring = mix(0.35, 1.0, smoothstep(1.5, 1.56, rr));
	ALBEDO = tint * (0.7 + 0.4 * bands(rr));
	ALPHA = a * gap * c_ring * clamp(bands(rr * 1.3) + 0.25, 0.0, 1.0) * 0.92;
	ROUGHNESS = 1.0;
}
