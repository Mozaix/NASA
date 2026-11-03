shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
// Real NASA map when there is one; otherwise a labelled procedural surface from real values.
uniform sampler2D map_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_map = false;
uniform int style = 0; // 0 banded, 1 rocky
uniform vec3 band_a : source_color = vec3(0.8);
uniform vec3 band_b : source_color = vec3(0.5);
uniform vec3 band_c : source_color = vec3(0.9);
uniform float seed = 0.0;
uniform float lava = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}
varying vec3 obj;
void vertex() {
	obj = normalize(VERTEX);
}
void fragment() {
	vec3 c;
	if (use_map) {
		c = texture(map_tex, UV).rgb;
	} else if (style == 0) {
		vec3 p = obj + vec3(seed);
		float w = fbm(p * vec3(3.0, 1.0, 3.0)) - 0.5;
		float lat = obj.y + w * 0.09;
		float b = sin(lat * 13.0 + seed) * 0.5 + 0.5;
		float b2 = sin(lat * 31.0 + seed * 2.0) * 0.5 + 0.5;
		c = mix(band_a, band_b, b);
		c = mix(c, band_c, b2 * 0.35 + fbm(p * vec3(8.0, 24.0, 8.0)) * 0.25);
	} else {
		float h = fbm(obj * 3.2 + vec3(seed));
		float h2 = fbm(obj * 12.0 + vec3(seed * 1.7));
		c = mix(band_a, band_b, smoothstep(0.32, 0.55, h));
		c = mix(c, band_c, smoothstep(0.5, 0.72, h * 0.6 + h2 * 0.4));
		EMISSION = vec3(1.5, 0.42, 0.07) * lava * (1.0 - smoothstep(0.004, 0.022, abs(h - 0.47)));
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
