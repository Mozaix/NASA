shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// Displaced on the GPU from a height texture so every chunk can share one mesh.
// Outside the map the terrain is mirrored, which keeps the edge seamless under the horizon haze.

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D color_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform float world_m = 4096.0;
uniform float n_side = 1024.0;
uniform float y_scale = 1.0;
uniform float y_ref = 0.0;
uniform float skirt = 18.0;
uniform float detail_amt = 0.22;
uniform float lava = 0.0;
uniform float time_s = 0.0;
uniform vec3 pad_pos = vec3(0.0);
uniform float pad_radius = 0.0;

varying vec3 wpos;

float mirror1(float v, float size) {
	float m = mod(v, 2.0 * size);
	return m < size ? m : 2.0 * size - m;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float texel = world_m / n_side;
	ivec2 p = ivec2(int(round(mirror1(w.x, world_m) / texel)), int(round(mirror1(w.z, world_m) / texel)));
	p = clamp(p, ivec2(0), ivec2(int(n_side) - 1));
	float h = (texelFetch(height_tex, p, 0).r - y_ref) * y_scale;
	VERTEX.y = h - UV.x * skirt;
	wpos = vec3(w.x, h, w.z);
}

void fragment() {
	float sx = mod(wpos.x, 2.0 * world_m) < world_m ? 1.0 : -1.0;
	float sz = mod(wpos.z, 2.0 * world_m) < world_m ? 1.0 : -1.0;
	vec2 uv = vec2(mirror1(wpos.x, world_m), mirror1(wpos.z, world_m)) / world_m;
	vec3 n = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	n.x *= sx;
	n.z *= sz;
	// Small-scale detail: the source imagery is hundreds of metres per pixel, so close to the
	// rover this procedural grain is all that is visible. It only modulates the real colour.
	float d1 = texture(detail_tex, wpos.xz * 0.011).r;
	float d2 = texture(detail_tex, wpos.xz * 0.07).r;
	float d3 = texture(detail_tex, wpos.xz * 0.43).r;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near_fade = 1.0 - smoothstep(60.0, 420.0, dist);
	float grain = (d1 - 0.5) * 0.7 + (d2 - 0.5) * 0.8 + (d3 - 0.5) * near_fade;
	vec2 slope = vec2(dFdx(grain), dFdy(grain));
	vec3 c = texture(color_tex, uv).rgb;
	c *= 1.0 + grain * detail_amt * 1.6;
	if (lava > 0.0) {
		float crack = smoothstep(0.60, 0.74, texture(detail_tex, wpos.xz * 0.018 + vec2(time_s * 0.002)).r) * (1.0 - smoothstep(0.0, 0.5, n.y - 0.75));
		EMISSION = vec3(1.8, 0.5, 0.08) * crack * lava;
	}
	if (pad_radius > 0.0) {
		float r = length(wpos.xz - pad_pos.xz);
		float ring = 1.0 - smoothstep(0.0, 1.6, abs(r - pad_radius));
		float pulse = 0.65 + 0.35 * sin(time_s * 3.0);
		EMISSION += vec3(0.1, 0.9, 0.6) * ring * pulse;
	}
	ALBEDO = clamp(c, 0.0, 1.0);
	ROUGHNESS = 0.96;
	vec3 vn = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);
	vn.xy += slope * 2.2 * near_fade;
	NORMAL = normalize(vn);
}
