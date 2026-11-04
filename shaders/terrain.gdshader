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
uniform float detail_amt = 0.16;
uniform float bump_amt = 9.0;
uniform float lava = 0.0;
uniform float time_s = 0.0;
uniform vec3 pad_pos = vec3(0.0);
uniform float pad_radius = 0.0;

// How far this chunk has blended toward the next coarser mesh, so detail levels change without popping.
instance uniform float morph = 0.0;
instance uniform float lod_step = 1.0;

varying vec3 wpos;

float mirror1(float v, float size) {
	float m = mod(v, 2.0 * size);
	return m < size ? m : 2.0 * size - m;
}

float raw_height(vec2 grid, float texel) {
	ivec2 p = ivec2(int(round(mirror1(grid.x * texel, world_m) / texel)), int(round(mirror1(grid.y * texel, world_m) / texel)));
	p = clamp(p, ivec2(0), ivec2(int(n_side) - 1));
	return texelFetch(height_tex, p, 0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float texel = world_m / n_side;
	vec2 grid = round(w.xz / texel);
	float raw = raw_height(grid, texel);
	if (morph > 0.0) {
		// Vertices the coarser mesh does not have slide onto the line that mesh would draw.
		vec2 m = mod(grid, 2.0 * lod_step);
		bool odd_x = m.x > 0.5;
		bool odd_z = m.y > 0.5;
		float coarse = raw;
		if (odd_x && odd_z) {
			coarse = 0.5 * (raw_height(grid + vec2(lod_step, -lod_step), texel) + raw_height(grid + vec2(-lod_step, lod_step), texel));
		} else if (odd_x) {
			coarse = 0.5 * (raw_height(grid + vec2(lod_step, 0.0), texel) + raw_height(grid - vec2(lod_step, 0.0), texel));
		} else if (odd_z) {
			coarse = 0.5 * (raw_height(grid + vec2(0.0, lod_step), texel) + raw_height(grid - vec2(0.0, lod_step), texel));
		}
		raw = mix(raw, coarse, morph);
	}
	float h = (raw - y_ref) * y_scale;
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
	// Sampled gradient for the fine bumps. Screen-space derivatives are blocky at this scale.
	vec2 bump = vec2(0.0);
	if (near_fade > 0.0) {
		float e = 0.006;
		bump = vec2(texture(detail_tex, wpos.xz * 0.07 + vec2(e, 0.0)).r - d2, texture(detail_tex, wpos.xz * 0.07 + vec2(0.0, e)).r - d2);
		n.xz -= bump * bump_amt * near_fade;
	}
	vec3 c = texture(color_tex, uv).rgb;
	c *= 1.0 + grain * detail_amt * 1.6;
	if (lava > 0.0) {
		// Thin glowing veins where the noise crosses its midpoint, brightest in the low ground.
		float vein = abs(texture(detail_tex, wpos.xz * 0.0052).r - 0.5);
		float crack = 1.0 - smoothstep(0.004, 0.03, vein);
		float pulse = 0.8 + 0.2 * sin(time_s * 0.7 + wpos.x * 0.01);
		EMISSION = vec3(1.5, 0.42, 0.06) * crack * pulse * lava;
		c *= 1.0 - crack * 0.6;
	}
	if (pad_radius > 0.0) {
		float r = length(wpos.xz - pad_pos.xz);
		float pulse = 0.65 + 0.35 * sin(time_s * 3.0);
		float ring = 1.0 - smoothstep(0.0, 1.6, abs(r - pad_radius));
		float inner = 1.0 - smoothstep(0.0, 0.8, abs(r - pad_radius * 0.45));
		// A cross at the centre, to aim at when looking straight down.
		vec2 d = abs(wpos.xz - pad_pos.xz);
		float cross = (1.0 - smoothstep(0.5, 1.1, min(d.x, d.y))) * (1.0 - smoothstep(pad_radius * 0.32, pad_radius * 0.36, max(d.x, d.y)));
		EMISSION += vec3(0.1, 0.9, 0.6) * (ring + inner * 0.7 + cross) * pulse;
		c = mix(c, c * 0.7, (1.0 - smoothstep(pad_radius - 1.0, pad_radius, r)) * 0.5);
	}
	ALBEDO = clamp(c, 0.0, 1.0);
	ROUGHNESS = 0.96;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);
}
