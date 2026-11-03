shader_type sky;
// Gradient sky per world with sun disc, plus the NASA star map where the air is thin.
uniform vec3 top_color : source_color = vec3(0.0);
uniform vec3 horizon_color : source_color = vec3(0.0);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform float sun_size = 0.0035;
uniform float sun_glow = 0.2;
uniform float stars_amt = 1.0;
uniform sampler2D stars_tex : source_color, filter_linear, repeat_enable;
uniform bool has_stars = false;
uniform vec3 planet_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 planet_color : source_color = vec3(0.0);
uniform float planet_size = 0.0;

void sky() {
	vec3 d = normalize(EYEDIR);
	float t = pow(clamp(1.0 - max(d.y, 0.0), 0.0, 1.0), 3.5);
	vec3 col = mix(top_color, horizon_color, t);
	if (d.y < 0.0) {
		col = horizon_color * 0.55;
	}
	if (stars_amt > 0.001 && has_stars && d.y > -0.1) {
		vec2 uv = vec2(atan(d.x, d.z) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
		col += texture(stars_tex, uv).rgb * stars_amt * 1.5;
	}
	if (planet_size > 0.0) {
		float c = dot(d, normalize(planet_dir));
		float edge = smoothstep(cos(planet_size), cos(planet_size * 0.985), c);
		col = mix(col, planet_color * (0.55 + 0.45 * d.y), edge);
	}
	float s = dot(d, normalize(LIGHT0_DIRECTION));
	float disc = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.6, s);
	float glow = pow(max(s, 0.0), 180.0) * sun_glow + pow(max(s, 0.0), 12.0) * sun_glow * 0.25;
	COLOR = col + sun_color * (disc * 14.0 + glow);
}
