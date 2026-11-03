extends Node
## Simple real orbital mechanics: Hohmann transfers, patched-conic burns, launch windows.
## Formulas are standard; planet data comes from the NASA fact sheets and JPL elements.

const G := 6.6743e-11
const MU_SUN := 1.32712440018e20
const G0 := 9.80665
const AU := 1.495978707e11
const LY := 9.4607e15
const PC_TO_LY := 3.26156
const LEO_ALT := 300000.0
const SECONDS_PER_DAY := 86400.0
const C_LIGHT := 299792458.0
## Approximate speed of Voyager 1, used only to show how far away the stars are.
const VOYAGER_SPEED := 17000.0
## GAME ASSUMPTION, shown in the UI: a concept interstellar light sail at 20% of light speed.
const SAIL_SPEED_C := 0.2

func mu_of(body: Dictionary) -> float:
	return G * float(body.get("mass_kg", 0.0))

func radius_m(body: Dictionary) -> float:
	return float(body.get("radius_km", 1.0)) * 1000.0

func hohmann_days(a1: float, a2: float, mu: float = MU_SUN) -> float:
	var a := (a1 + a2) * 0.5
	return PI * sqrt(a * a * a / mu) / SECONDS_PER_DAY

## Hyperbolic excess speeds at each end of a heliocentric Hohmann transfer (m/s).
func hohmann_vinf(a1: float, a2: float, mu: float = MU_SUN) -> Vector2:
	var at := (a1 + a2) * 0.5
	var v1 := sqrt(mu / a1)
	var v2 := sqrt(mu / a2)
	var vt1 := sqrt(mu * (2.0 / a1 - 1.0 / at))
	var vt2 := sqrt(mu * (2.0 / a2 - 1.0 / at))
	return Vector2(abs(vt1 - v1), abs(v2 - vt2))

## Burn from a circular orbit of radius r to a hyperbola with excess speed vinf.
func escape_burn(vinf: float, mu: float, r: float) -> float:
	return sqrt(vinf * vinf + 2.0 * mu / r) - sqrt(mu / r)

## Capture into a bound, highly elliptical orbit with periapsis r (giant planets).
func capture_elliptical(vinf: float, mu: float, r: float) -> float:
	return sqrt(vinf * vinf + 2.0 * mu / r) - sqrt(1.9 * mu / r)

func descent_burn(body: Dictionary, lander: Dictionary) -> float:
	var r := radius_m(body)
	var orbit_v := sqrt(mu_of(body) / r)
	var factor := float(lander.get("descent_factor", 1.0))
	if not Data.has_atmosphere(body):
		factor = 1.05
	return orbit_v * factor

## Full estimate for a target. Returns delta-v legs in m/s and travel time in days.
func plan(target: Dictionary) -> Dictionary:
	var earth: Dictionary = Data.body("earth")
	var mu_e := mu_of(earth)
	var r_leo := radius_m(earth) + LEO_ALT
	var out := {"departure": 0.0, "capture": 0.0, "days": 0.0, "kind": "hohmann", "vinf_dep": 0.0, "vinf_arr": 0.0}
	var kind: String = target.get("kind", "planet")
	if kind == "exoplanet":
		var dist_m := float(target.get("sy_dist", 10.0)) * PC_TO_LY * LY
		out.kind = "interstellar"
		out.days = dist_m / (SAIL_SPEED_C * C_LIGHT) / SECONDS_PER_DAY
		out.voyager_years = dist_m / VOYAGER_SPEED / SECONDS_PER_DAY / 365.25
		out.light_years = float(target.get("sy_dist", 10.0)) * PC_TO_LY
		return out
	if target.id == "earth":
		out.kind = "orbit"
		out.days = 0.25
		out.departure = 0.0
		out.capture = 0.0
		return out
	if target.id == "moon":
		var a_moon := float(target.a_km) * 1000.0
		var at := (r_leo + a_moon) * 0.5
		var v_p := sqrt(mu_e * (2.0 / r_leo - 1.0 / at))
		out.departure = v_p - sqrt(mu_e / r_leo)
		var v_a := sqrt(mu_e * (2.0 / a_moon - 1.0 / at))
		var vinf_m: float = abs(sqrt(mu_e / a_moon) - v_a)
		out.capture = escape_burn(vinf_m, mu_of(target), radius_m(target) + 100000.0)
		out.days = hohmann_days(r_leo, a_moon, mu_e)
		out.kind = "lunar"
		return out
	var planet: Dictionary = target if kind == "planet" else Data.body(target.parent)
	var a1 := float(earth.a_km) * 1000.0
	var a2 := float(planet.a_km) * 1000.0
	var vinf := hohmann_vinf(a1, a2)
	out.vinf_dep = vinf.x
	out.vinf_arr = vinf.y
	out.departure = escape_burn(vinf.x, mu_e, r_leo)
	out.days = hohmann_days(a1, a2)
	var mu_p := mu_of(planet)
	var giant := float(planet.radius_km) > 20000.0
	if kind == "planet":
		var r_p := radius_m(planet) * 1.1 if giant else radius_m(planet) + 300000.0
		out.capture = capture_elliptical(vinf.y, mu_p, r_p) if giant else escape_burn(vinf.y, mu_p, r_p)
	else:
		# Arrive at the parent planet with periapsis at the moon's orbit, then capture at the moon.
		var r_m := float(target.a_km) * 1000.0
		var v_peri := sqrt(vinf.y * vinf.y + 2.0 * mu_p / r_m)
		var vinf_moon: float = abs(v_peri - sqrt(mu_p / r_m))
		out.capture = escape_burn(vinf_moon, mu_of(target), radius_m(target) + 100000.0)
	return out

# ---- Dates and planet positions (JPL approximate elements) ----

func unix_to_jd(unix: float) -> float:
	return unix / SECONDS_PER_DAY + 2440587.5

func date_string(unix: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

## Heliocentric mean longitude in degrees.
func mean_longitude(planet_id: String, unix: float) -> float:
	var e: Dictionary = Data.elements.planets[planet_id]
	var t := (unix_to_jd(unix) - 2451545.0) / 36525.0
	return fposmod(float(e.L_deg) + float(e.L_rate_deg_cy) * t, 360.0)

## Angle by which the planet leads Earth at launch for an ideal Hohmann arrival.
func ideal_phase(planet_id: String) -> float:
	var earth: Dictionary = Data.body("earth")
	var p: Dictionary = Data.body(planet_id)
	var days := hohmann_days(float(earth.a_km) * 1000.0, float(p.a_km) * 1000.0)
	var n := 360.0 / float(p.orbit_days)
	return fposmod(180.0 - n * days, 360.0)

func phase_error(planet_id: String, unix: float) -> float:
	var current := fposmod(mean_longitude(planet_id, unix) - mean_longitude("earth", unix), 360.0)
	return wrapf(current - ideal_phase(planet_id), -180.0, 180.0)

## Simplified off-window penalty. Labelled as a model in the UI. 1.0 means an ideal window.
func window_factor(planet_id: String, unix: float) -> float:
	var err: float = abs(phase_error(planet_id, unix)) / 180.0
	return 1.0 + 0.9 * err * err

func synodic_days(planet_id: String) -> float:
	var earth_p := float(Data.body("earth").orbit_days)
	var p := float(Data.body(planet_id).orbit_days)
	return 1.0 / abs(1.0 / earth_p - 1.0 / p)

## Evenly spaced launch dates from `start_unix`, each scored by phase error.
func window_table(planet_id: String, start_unix: float, count: int, step_days: float) -> Array:
	var rows: Array = []
	for i in count:
		var u := start_unix + float(i) * step_days * SECONDS_PER_DAY
		rows.append({"unix": u, "date": date_string(u), "error": phase_error(planet_id, u), "factor": window_factor(planet_id, u)})
	return rows

func best_window(planet_id: String, start_unix: float, horizon_days: float) -> float:
	var best_u := start_unix
	var best_e := 1e9
	var d := 0.0
	while d < horizon_days:
		var u := start_unix + d * SECONDS_PER_DAY
		var e: float = abs(phase_error(planet_id, u))
		if e < best_e:
			best_e = e
			best_u = u
		d += 2.0
	return best_u

# ---- Rocket equation ----

func delta_v(isp: float, m_wet: float, m_dry: float) -> float:
	if m_dry <= 0.0 or m_wet <= m_dry:
		return 0.0
	return isp * G0 * log(m_wet / m_dry)

func format_time(days: float) -> String:
	if days < 2.0:
		return "%.0f hours" % (days * 24.0)
	if days < 365.25 * 2.0:
		return "%.0f days" % days
	var years := days / 365.25
	if years < 1000.0:
		return "%.1f years" % years
	return "%s years" % UI.grouped(int(years))
