extends Node
## Mission state, spacecraft parts, budget and scoring.
## Part costs, masses and engine figures are GAME VALUES, not NASA data.

const BUDGET_LIMIT := 2500.0  # $M

const LAUNCHERS := [
	{"id": "medium", "name": "Medium Lift", "lift_t": 25.0, "cost": 160.0, "desc": "Reliable and cheap. Inner solar system only, unless the payload is tiny."},
	{"id": "heavy", "name": "Heavy Lift", "lift_t": 65.0, "cost": 380.0, "desc": "The workhorse for Mars and the Moon."},
	{"id": "super", "name": "Super Heavy Lift", "lift_t": 130.0, "cost": 1100.0, "desc": "Needed for the outer planets."},
]
const STAGES := [
	{"id": "storable", "name": "Storable Chemical", "isp": 320.0, "dry_t": 2.5, "cost": 90.0, "time": 1.0, "desc": "Simple, cheap, low efficiency."},
	{"id": "hydrolox", "name": "Hydrogen / Oxygen", "isp": 450.0, "dry_t": 4.5, "cost": 190.0, "time": 1.0, "desc": "Best chemical efficiency."},
	{"id": "nuclear", "name": "Nuclear Thermal (concept)", "isp": 900.0, "dry_t": 14.0, "cost": 620.0, "time": 1.0, "desc": "Very efficient and heavy. Reaches the outer planets."},
	{"id": "ion", "name": "Solar/Nuclear Electric", "isp": 3000.0, "dry_t": 3.5, "cost": 330.0, "time": 1.5, "desc": "Huge efficiency, low thrust: travel takes 50% longer."},
	{"id": "sail", "name": "Interstellar Light Sail (concept)", "isp": 0.0, "dry_t": 0.5, "cost": 1500.0, "time": 1.0, "exo_only": true, "desc": "Assumes 20% of light speed. No such craft exists today."},
]
const LANDERS := [
	{"id": "airbag", "name": "Parachute + Airbags", "mass_t": 0.8, "cost": 90.0, "needs_atmo": true, "descent_factor": 0.04, "tolerance": 12.0, "fuel": 0.55, "desc": "Bounces down softly. Atmosphere required. Forgiving but imprecise."},
	{"id": "skycrane", "name": "Heat Shield + Sky Crane", "mass_t": 3.2, "cost": 260.0, "needs_atmo": true, "descent_factor": 0.09, "tolerance": 6.0, "fuel": 1.0, "desc": "Precision landing with an atmosphere."},
	{"id": "retro", "name": "Retro-propulsive Lander", "mass_t": 2.4, "cost": 210.0, "needs_atmo": false, "descent_factor": 1.05, "tolerance": 5.0, "fuel": 1.0, "desc": "Works anywhere solid, burns a lot of propellant."},
	{"id": "probe", "name": "Atmospheric Probe", "mass_t": 0.5, "cost": 110.0, "needs_atmo": true, "descent_factor": 0.03, "probe": true, "tolerance": 99.0, "fuel": 1.0, "desc": "For worlds with no surface. Flies through the cloud tops."},
]
const POWERS := [
	{"id": "solar", "name": "Solar Arrays", "mass_t": 0.15, "cost": 40.0, "watts_1au": 2400.0, "desc": "Output falls with distance squared from the Sun."},
	{"id": "solar_big", "name": "Large Solar Arrays", "mass_t": 0.5, "cost": 95.0, "watts_1au": 9000.0, "desc": "Enough for Jupiter, at a mass penalty."},
	{"id": "rtg", "name": "Radioisotope Generator", "mass_t": 0.06, "cost": 150.0, "watts": 110.0, "desc": "Constant, modest power anywhere, even in shadow."},
	{"id": "rtg2", "name": "Twin Radioisotope Generators", "mass_t": 0.12, "cost": 280.0, "watts": 220.0, "desc": "Constant power for a full instrument suite."},
]
const INSTRUMENTS := [
	{"id": "camera", "name": "Mast Camera", "mass_t": 0.03, "cost": 30.0, "watts": 15.0, "bonus": 5.0, "desc": "+5 science per point of interest."},
	{"id": "spectrometer", "name": "Spectrometer", "mass_t": 0.05, "cost": 70.0, "watts": 40.0, "unlock": "rock", "desc": "Required for ROCK samples."},
	{"id": "drill", "name": "Rock Drill", "mass_t": 0.09, "cost": 90.0, "watts": 60.0, "unlock": "core", "desc": "Required for CORE samples."},
	{"id": "sampler", "name": "Atmosphere Sampler", "mass_t": 0.03, "cost": 45.0, "watts": 20.0, "unlock": "gas", "desc": "Required for GAS samples on probe missions."},
]
const ROVER := {"id": "rover", "name": "Rover Chassis", "mass_t": 0.9, "cost": 240.0, "desc": "Six wheels. Required to leave the landing site."}
const SCI_VALUES := {"regolith": 30.0, "rock": 60.0, "core": 90.0, "gas": 70.0}

var mission: Dictionary = {}
var best_scores: Dictionary = {}

func _ready() -> void:
	new_mission()
	var f := ConfigFile.new()
	if f.load("user://scores.cfg") == OK:
		best_scores = f.get_value("scores", "best", {})

func new_mission() -> void:
	mission = {
		"target_id": "mars", "region_id": "gale",
		"launcher": "heavy", "stage": "hydrolox", "lander": "skycrane", "power": "rtg2", "rover": true,
		"instruments": ["camera", "spectrometer", "drill"], "propellant_t": 34.0,
		"launch_unix": 0.0, "launch_quality": 1.0, "correction_quality": 1.0,
		"landed": false, "crashes": 0, "landing_rating": 0.0, "assisted": false, "orbit_science": 0.0,
		"pois": {}, "samples": [], "facts_seen": [], "science": 0.0,
		"phase": "planning", "aborted": false, "distance_m": 0.0,
	}

func part(list: Array, id: String) -> Dictionary:
	for p: Dictionary in list:
		if p.id == id:
			return p
	return {}

func target() -> Dictionary:
	return Data.body(mission.target_id)

func launcher() -> Dictionary:
	return part(LAUNCHERS, mission.launcher)

func stage() -> Dictionary:
	return part(STAGES, mission.stage)

func lander() -> Dictionary:
	return part(LANDERS, mission.lander)

func power() -> Dictionary:
	return part(POWERS, mission.power)

func is_probe_mission() -> bool:
	return not target().get("has_surface", false)

func dry_mass() -> float:
	var m := float(stage().dry_t) + float(lander().mass_t) + float(power().mass_t)
	if mission.rover and not is_probe_mission():
		m += float(ROVER.mass_t)
	for id: String in mission.instruments:
		m += float(part(INSTRUMENTS, id).mass_t)
	return m

func total_mass() -> float:
	return dry_mass() + float(mission.propellant_t)

func cost() -> float:
	var c := float(launcher().cost) + float(stage().cost) + float(lander().cost) + float(power().cost)
	if mission.rover and not is_probe_mission():
		c += float(ROVER.cost)
	for id: String in mission.instruments:
		c += float(part(INSTRUMENTS, id).cost)
	return c

func distance_au() -> float:
	var t := target()
	if t.kind == "exoplanet":
		return 1.0  # lit by its own star; panels are assumed sized to it
	var p: Dictionary = t if t.kind == "planet" else Data.body(t.parent)
	return float(p.a_km) * 1000.0 / Orbital.AU

func power_available() -> float:
	var p := power()
	if p.has("watts"):
		return float(p.watts)
	var w := float(p.watts_1au) / pow(distance_au(), 2.0)
	if mission.region_id == "shackleton":
		w *= 0.35  # low Sun at the pole, stated in the validation message
	return w

func power_needed() -> float:
	var w := 40.0
	if mission.rover and not is_probe_mission():
		w += 45.0
	for id: String in mission.instruments:
		w += float(part(INSTRUMENTS, id).watts)
	return w

func dv_plan() -> Dictionary:
	var t := target()
	var o: Dictionary = Orbital.plan(t)
	var parent: String = t.id if t.kind == "planet" else str(t.get("parent", ""))
	var factor := 1.0
	if o.kind == "hohmann" and mission.launch_unix > 0.0:
		factor = Orbital.window_factor(parent, mission.launch_unix)
	o.window_factor = factor
	o.departure = float(o.departure) * factor
	o.capture = float(o.capture) * factor
	o.descent = 0.0
	if o.kind != "interstellar":
		o.descent = Orbital.descent_burn(t, lander())
	o.total = float(o.departure) + float(o.capture) + float(o.descent)
	o.days = float(o.days) * float(stage().time)
	return o

func dv_have() -> float:
	if stage().id == "sail":
		return 1e9
	return Orbital.delta_v(float(stage().isp), total_mass(), dry_mass())

func dv_margin() -> float:
	return dv_have() - float(dv_plan().total)

## Everything that blocks launch, as plain sentences. An empty list means ready.
func problems() -> Array[String]:
	var out: Array[String] = []
	var t := target()
	if cost() > BUDGET_LIMIT:
		out.append("Over budget by $%d M." % int(cost() - BUDGET_LIMIT))
	if total_mass() > float(launcher().lift_t):
		out.append("Too heavy: %.1f t on a launcher that lifts %.0f t." % [total_mass(), float(launcher().lift_t)])
	if t.kind == "exoplanet" and stage().id != "sail":
		out.append("Only the interstellar sail can reach another star.")
	if t.kind != "exoplanet" and stage().id == "sail":
		out.append("The interstellar sail cannot brake at a solar system target.")
	if stage().id != "sail" and dv_margin() < 0.0:
		out.append("Not enough delta-v: short by %.2f km/s. Add propellant or use a better engine." % (-dv_margin() / 1000.0))
	if lander().get("needs_atmo", false) and not Data.has_atmosphere(t):
		out.append("%s needs an atmosphere, and %s has too little." % [lander().name, t.name])
	if is_probe_mission() and not lander().get("probe", false):
		out.append("%s has no solid surface. Choose the Atmospheric Probe." % t.name)
	if not is_probe_mission() and lander().get("probe", false):
		out.append("A probe cannot land on %s. Choose a lander." % t.name)
	if not is_probe_mission() and not mission.rover:
		out.append("A rover is required to explore the surface.")
	if power_available() < power_needed():
		out.append("Not enough power: %.0f W available at %s, %.0f W needed." % [power_available(), t.name, power_needed()])
	if t.id == "venus" and lander().id == "airbag":
		out.append("Airbags cannot survive Venus' surface conditions. Use a Sky Crane.")
	return out

func can_collect(sample: String) -> bool:
	if sample == "regolith":
		return true
	for id: String in mission.instruments:
		if part(INSTRUMENTS, id).get("unlock", "") == sample:
			return true
	return false

func add_science(amount: float) -> void:
	mission.science = float(mission.science) + amount

func score() -> Dictionary:
	var m := mission
	var success := 0.0
	if m.phase in ["transfer", "orbit", "landing", "surface", "debrief"]:
		success += 100.0
	if float(m.orbit_science) > 0.0:
		success += 50.0
	if m.landed:
		success += 200.0 + float(m.landing_rating) * 100.0
	if int(m.crashes) > 0:
		success = maxf(0.0, success - 60.0 * float(m.crashes))
	if m.assisted:
		success -= 60.0
	var budget_left: float = maxf(0.0, BUDGET_LIMIT - cost())
	var budget_pts: float = budget_left / BUDGET_LIMIT * 250.0
	if not m.landed:
		budget_pts *= 0.3
	var total: float = success + float(m.science) + budget_pts
	var rank := "Mission Trainee"
	if total >= 1000.0:
		rank = "Flight Director"
	elif total >= 750.0:
		rank = "Principal Investigator"
	elif total >= 500.0:
		rank = "Mission Specialist"
	return {"success": success, "science": float(m.science), "budget": budget_pts, "total": total, "rank": rank}

func save_best(total: float) -> bool:
	var id: String = mission.target_id
	var better := total > float(best_scores.get(id, 0.0))
	if better:
		best_scores[id] = total
		var f := ConfigFile.new()
		f.set_value("scores", "best", best_scores)
		f.save("user://scores.cfg")
	return better

## Pick a sensible, launchable design for the chosen target. Used by "Auto-design" and by tests.
func auto_design() -> void:
	var t := target()
	var probe := is_probe_mission()
	mission.lander = "probe" if probe else ("skycrane" if Data.has_atmosphere(t) else "retro")
	mission.instruments = ["camera", "sampler"] if probe else ["camera", "spectrometer", "drill"]
	mission.rover = not probe
	mission.power = "rtg2" if distance_au() > 2.0 else "solar_big"
	if t.kind == "exoplanet":
		mission.stage = "sail"
		mission.launcher = "heavy"
		mission.propellant_t = 0.0
		return
	var best := {}
	for l: Dictionary in LAUNCHERS:
		for s: Dictionary in STAGES:
			if s.id == "sail":
				continue
			mission.launcher = l.id
			mission.stage = s.id
			var need := float(dv_plan().total) * 1.06
			var ratio := exp(need / (float(s.isp) * Orbital.G0))
			mission.propellant_t = 0.0
			var prop := dry_mass() * (ratio - 1.0)
			mission.propellant_t = snappedf(prop + 0.25, 0.5)
			if not problems().is_empty():
				continue
			if best.is_empty() or cost() < float(best.cost):
				best = {"cost": cost(), "launcher": l.id, "stage": s.id, "prop": mission.propellant_t}
	if not best.is_empty():
		mission.launcher = best.launcher
		mission.stage = best.stage
		mission.propellant_t = best.prop
