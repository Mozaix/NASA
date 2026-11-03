extends Node
## 2D Rocket Builder: parts, physics, money and the daily leaderboard.
## Earth's values come from NASA fact sheets. Part stats, prices and rewards are game values.
## Prediction and flight run the same Sim, so a predicted height is a real simulated result.

const START_MONEY := 600
const FLIGHTS_PER_GAME := 6
const MOON_M := 384400000.0
const G0 := 9.80665
const BOARD_SIZE := 10
const NAME_MAX := 18

const SLOT_ORDER: Array[String] = ["nose", "fins", "tank", "engine", "boosters", "utank", "uengine"]
const SLOT_TITLES := {
	"nose": "Nose shape", "fins": "Fins", "tank": "Main fuel tank", "engine": "Main engine",
	"boosters": "Side boosters", "utank": "Second stage tank", "uengine": "Second stage engine",
}
const PARTS := {
	"nose": [
		{"id": "cap", "name": "Flat cap", "cost": 0, "mass": 0.05, "cd": 0.90, "stab": 0.0, "desc": "Pushes a lot of air."},
		{"id": "cone", "name": "Cone", "cost": 120, "mass": 0.06, "cd": 0.50, "stab": 0.0, "desc": "Cuts drag a lot, cheaply."},
		{"id": "ogive", "name": "Ogive", "cost": 350, "mass": 0.07, "cd": 0.34, "stab": 0.0, "desc": "Smooth curve, low drag."},
		{"id": "needle", "name": "Needle", "cost": 800, "mass": 0.09, "cd": 0.24, "stab": -0.25, "desc": "Lowest drag, harder to keep straight."},
		{"id": "shuttle", "name": "Winged shuttle", "cost": 1500, "mass": 0.40, "cd": 0.70, "stab": 0.7, "reward": 1.5, "desc": "Heavy and draggy, but glides home: earns 50% more money."},
	],
	"fins": [
		{"id": "nofins", "name": "No fins", "cost": 0, "mass": 0.0, "stab": 0.0, "dcd": 0.0, "desc": "Nothing keeps the rocket pointing forward."},
		{"id": "small", "name": "Small fins", "cost": 60, "mass": 0.02, "stab": 1.0, "dcd": 0.03, "desc": "Enough to fly straight."},
		{"id": "large", "name": "Large fins", "cost": 220, "mass": 0.05, "stab": 1.6, "dcd": 0.07, "desc": "Very steady, a little more drag."},
		{"id": "swept", "name": "Swept fins", "cost": 700, "mass": 0.04, "stab": 1.5, "dcd": 0.02, "desc": "Steady with very little drag."},
	],
	"tank": [
		{"id": "t1", "name": "Small", "cost": 0, "prop": 0.8, "dry": 0.5, "w": 1.2, "h": 4.0, "desc": "0.8 tonnes of fuel."},
		{"id": "t2", "name": "Medium", "cost": 300, "prop": 3.0, "dry": 0.6, "w": 1.6, "h": 7.0, "desc": "3 tonnes of fuel."},
		{"id": "t3", "name": "Large", "cost": 1200, "prop": 12.0, "dry": 2.0, "w": 2.4, "h": 11.0, "desc": "12 tonnes of fuel."},
		{"id": "t4", "name": "Huge", "cost": 4500, "prop": 60.0, "dry": 5.0, "w": 3.4, "h": 19.0, "desc": "60 tonnes of fuel."},
	],
	"engine": [
		{"id": "e1", "name": "Pop", "cost": 0, "thrust": 25.0, "isp": 230.0, "mass": 0.25, "desc": "25 kN. Only lifts a small tank."},
		{"id": "e2", "name": "Sparrow", "cost": 250, "thrust": 80.0, "isp": 260.0, "mass": 0.40, "desc": "80 kN."},
		{"id": "e3", "name": "Swift", "cost": 1000, "thrust": 300.0, "isp": 285.0, "mass": 1.0, "desc": "300 kN."},
		{"id": "e4", "name": "Goliath", "cost": 3800, "thrust": 1000.0, "isp": 300.0, "mass": 2.8, "desc": "1,000 kN."},
	],
	"boosters": [
		{"id": "b0", "name": "None", "cost": 0, "n": 0, "prop": 0.0, "dry": 0.0, "thrust": 0.0, "isp": 200.0, "w": 0.0, "h": 0.0, "desc": "No extra push."},
		{"id": "b1", "name": "2 small", "cost": 300, "n": 2, "prop": 0.6, "dry": 0.15, "thrust": 40.0, "isp": 200.0, "w": 0.5, "h": 3.0, "desc": "A short, strong kick at liftoff."},
		{"id": "b2", "name": "2 large", "cost": 1400, "n": 2, "prop": 3.0, "dry": 0.6, "thrust": 200.0, "isp": 220.0, "w": 0.8, "h": 6.0, "desc": "Lifts much bigger rockets."},
		{"id": "b3", "name": "4 heavy", "cost": 5000, "n": 4, "prop": 8.0, "dry": 1.2, "thrust": 500.0, "isp": 240.0, "w": 1.1, "h": 9.0, "desc": "Lifts almost anything."},
	],
	"utank": [
		{"id": "u0", "name": "None", "cost": 0, "prop": 0.0, "dry": 0.0, "w": 0.0, "h": 0.0, "desc": "A single-stage rocket."},
		{"id": "u1", "name": "Small", "cost": 250, "prop": 0.4, "dry": 0.1, "w": 0.9, "h": 1.5, "desc": "Drops dead weight on the way up."},
		{"id": "u2", "name": "Medium", "cost": 900, "prop": 1.5, "dry": 0.25, "w": 1.2, "h": 2.5, "desc": "1.5 tonnes of fuel."},
		{"id": "u3", "name": "Large", "cost": 3000, "prop": 12.0, "dry": 1.0, "w": 1.8, "h": 5.5, "desc": "12 tonnes of fuel."},
	],
	"uengine": [
		{"id": "ue0", "name": "None", "cost": 0, "thrust": 0.0, "isp": 300.0, "mass": 0.0, "desc": "Needed if you add a second stage tank."},
		{"id": "ue1", "name": "Vacuum small", "cost": 400, "thrust": 25.0, "isp": 320.0, "mass": 0.08, "desc": "25 kN, efficient."},
		{"id": "ue2", "name": "Vacuum medium", "cost": 1400, "thrust": 80.0, "isp": 350.0, "mass": 0.22, "desc": "80 kN, very efficient."},
		{"id": "ue3", "name": "Hydrogen", "cost": 4200, "thrust": 180.0, "isp": 450.0, "mass": 0.5, "desc": "180 kN, the most efficient."},
	],
}

## One rocket in flight. Typed fields, so thousands of steps stay fast enough to predict every option.
class Sim:
	var mu := 3.986e14
	var radius := 6378000.0
	var rho0 := 1.217
	var scale_h := 8500.0
	var h := 0.0
	var x := 0.0
	var vx := 0.0
	var vy := 0.0
	var theta := 0.0
	var omega := 0.0
	var t := 0.0
	var q := 0.0
	var q_max := 0.0
	var thrust_now := 0.0
	var broken := false
	var lifted := false
	var crashed := false
	var h_max := 0.0
	var fixed_mass := 0.0
	var cd := 0.0
	var margin := 0.0
	var b_on := false
	var b_attached := false
	var b_prop := 0.0
	var b_dry := 0.0
	var b_thrust := 0.0
	var b_mdot := 0.0
	var b_area := 0.0
	var main_on := true
	var main_attached := true
	var main_prop := 0.0
	var main_dry := 0.0
	var main_thrust := 0.0
	var main_mdot := 0.0
	var main_area := 0.0
	var up_has := false
	var up_on := false
	var up_prop := 0.0
	var up_dry := 0.0
	var up_thrust := 0.0
	var up_mdot := 0.0
	var up_area := 0.0
	var event := ""

	func burning() -> bool:
		return b_on or main_on or up_on

	func mass() -> float:
		var m := fixed_mass + up_dry + up_prop
		if main_attached:
			m += main_dry + main_prop
		if b_attached:
			m += b_dry + b_prop
		return m

	func area() -> float:
		var a := up_area
		if main_attached:
			a = maxf(a, main_area)
			if b_attached:
				a += b_area
		return a

	func step(dt: float, steer: float = 0.0, gust: float = 0.0) -> void:
		t += dt
		event = ""
		var thrust := 0.0
		if b_on:
			thrust += b_thrust
			b_prop -= b_mdot * dt
			if b_prop <= 0.0:
				b_prop = 0.0
				b_on = false
				b_attached = false
				event = "boosters"
		if main_on:
			thrust += main_thrust
			main_prop -= main_mdot * dt
			if main_prop <= 0.0:
				main_prop = 0.0
				main_on = false
				if up_has:
					main_attached = false
					b_attached = false
					up_on = true
					event = "stage"
		elif up_on:
			thrust += up_thrust
			up_prop -= up_mdot * dt
			if up_prop <= 0.0:
				up_prop = 0.0
				up_on = false
		thrust_now = thrust
		var m := mass()
		var r := radius + h
		var g := mu / (r * r)
		var rho := rho0 * exp(-maxf(h, 0.0) / scale_h)
		var v2 := vx * vx + vy * vy
		q = 0.5 * rho * v2
		q_max = maxf(q_max, q)
		var v := sqrt(v2)
		var drag := q * cd * area()
		var dx := 0.0
		var dy := 0.0
		if v > 0.01:
			dx = drag / m * vx / v
			dy = drag / m * vy / v
		var ax := thrust / m * sin(theta) - dx
		var ay := thrust / m * cos(theta) - g - dy
		if not lifted:
			if ay <= 0.0:
				return  # still sitting on the pad
			lifted = true
		vx += ax * dt
		vy += ay * dt
		h += vy * dt
		x += vx * dt
		h_max = maxf(h_max, h)
		if h <= 0.0 and vy < 0.0:
			# Back on the ground: a weak stage cannot hold a rocket up forever.
			h = 0.0
			vx = 0.0
			vy = 0.0
			crashed = true
			b_on = false
			main_on = false
			up_on = false
			return
		# Fins turn the rocket back toward its direction of travel. Without them, air pushes it further away.
		var path := atan2(vx, vy) if v > 5.0 else theta
		var err := wrapf(theta - path, -PI, PI)
		var qn := q / 10000.0
		var ang := -3.0 * margin * qn * err + gust / (1.0 + maxf(margin, 0.0)) + (steer * 0.9 if thrust > 0.0 else 0.0)
		omega += (ang - 1.6 * omega) * dt
		theta += omega * dt
		if absf(err) > 0.7 and q > 2000.0:
			broken = true

## Rocket steadiness: above zero it self-corrects, below zero it will tumble once the air pushes hard.
func stability(d: Dictionary) -> float:
	var need := 0.6
	if part("boosters", d.boosters).n > 0:
		need += 0.1
	if has_upper(d):
		need += 0.15
	return float(part("fins", d.fins).stab) + float(part("nose", d.nose).stab) - need

func has_upper(d: Dictionary) -> bool:
	return d.utank != "u0" and d.uengine != "ue0"

func make_sim(d: Dictionary) -> Sim:
	var s := Sim.new()
	var e: Dictionary = Data.body("earth")
	s.mu = Orbital.G * float(e.mass_kg)
	s.radius = float(e.radius_km) * 1000.0
	s.rho0 = float(e.get("surface_density", 1.217))
	s.scale_h = float(e.get("scale_height_km", 8.5)) * 1000.0
	var nose: Dictionary = part("nose", d.nose)
	var fins: Dictionary = part("fins", d.fins)
	var tank: Dictionary = part("tank", d.tank)
	var eng: Dictionary = part("engine", d.engine)
	var bo: Dictionary = part("boosters", d.boosters)
	var ut: Dictionary = part("utank", d.utank)
	var ue: Dictionary = part("uengine", d.uengine)
	s.fixed_mass = (float(nose.mass) + float(fins.mass)) * 1000.0
	s.cd = float(nose.cd) + float(fins.dcd)
	s.margin = stability(d)
	if s.margin < 0.0:
		s.theta = 0.01  # no rocket is perfectly straight; an unstable one will not stay that way
	s.main_prop = float(tank.prop) * 1000.0
	s.main_dry = (float(tank.dry) + float(eng.mass)) * 1000.0
	s.main_thrust = float(eng.thrust) * 1000.0
	s.main_mdot = s.main_thrust / (float(eng.isp) * G0)
	s.main_area = PI * pow(float(tank.w) * 0.5, 2.0)
	var n := int(bo.n)
	if n > 0:
		s.b_on = true
		s.b_attached = true
		s.b_prop = float(bo.prop) * n * 1000.0
		s.b_dry = float(bo.dry) * n * 1000.0
		s.b_thrust = float(bo.thrust) * n * 1000.0
		s.b_mdot = s.b_thrust / (float(bo.isp) * G0)
		s.b_area = PI * pow(float(bo.w) * 0.5, 2.0) * n
	if has_upper(d):
		s.up_has = true
		s.up_prop = float(ut.prop) * 1000.0
		s.up_dry = (float(ut.dry) + float(ue.mass)) * 1000.0
		s.up_thrust = float(ue.thrust) * 1000.0
		s.up_mdot = s.up_thrust / (float(ue.isp) * G0)
		s.up_area = PI * pow(float(ut.w) * 0.5, 2.0)
	else:
		# Half a second stage is dead weight, and the prediction should show that.
		s.fixed_mass += (float(ut.prop) + float(ut.dry) + float(ue.mass)) * 1000.0
	return s

## Highest point of a coasting rocket, from orbital energy. Capped at the Moon's distance.
func apogee_from(s: Sim) -> float:
	var r := s.radius + s.h
	var v2 := s.vx * s.vx + s.vy * s.vy
	var energy := v2 * 0.5 - s.mu / r
	if energy >= 0.0:
		return MOON_M
	var ang_mom := r * absf(s.vx)
	var a := -s.mu / (2.0 * energy)
	var ecc := sqrt(maxf(1.0 + 2.0 * energy * ang_mom * ang_mom / (s.mu * s.mu), 0.0))
	return minf(a * (1.0 + ecc) - s.radius, MOON_M)

func twr(d: Dictionary) -> float:
	var s := make_sim(d)
	var thrust := s.main_thrust + s.b_thrust
	return thrust / (s.mass() * 9.81)

var _cache: Dictionary = {}

## Fly the design straight up with no wind and a perfect pilot.
func predict(d: Dictionary) -> Dictionary:
	var key := str(d.values())
	if _cache.has(key):
		return _cache[key]
	var s := make_sim(d)
	var out := {"reason": "ok", "twr": twr(d), "margin": s.margin, "apogee": 0.0, "breakup_h": 0.0}
	if float(out.twr) <= 1.0:
		out.reason = "no_liftoff"
		_cache[key] = out
		return out
	while s.burning() and not s.broken and not s.crashed:
		s.step(0.25)
	while not s.broken and not s.crashed and s.h < 120000.0 and s.vy > 0.0:
		s.step(0.5)
	if s.broken:
		out.reason = "breakup"
		out.breakup_h = s.h
		out.apogee = s.h_max
	elif s.h >= 120000.0:
		out.apogee = maxf(apogee_from(s), s.h_max)
	else:
		out.apogee = s.h_max
	out.q_max = s.q_max
	_cache[key] = out
	return out

# ---- One player's game. All of this resets; the leaderboard does not. ----

var money := START_MONEY
var owned: Dictionary = {}
var design: Dictionary = {}
var flights_left := FLIGHTS_PER_GAME
var best_m := 0.0
var best_design := ""
var reached: Dictionary = {}
var total_earned := 0
var last_flight: Dictionary = {}
var board_path := "user://leaderboard.json"
var pending_submit := false

func _ready() -> void:
	new_game()

func new_game() -> void:
	money = START_MONEY
	owned = {}
	design = {}
	for slot: String in SLOT_ORDER:
		var first: Dictionary = PARTS[slot][0]
		owned[first.id] = true
		design[slot] = first.id
	flights_left = FLIGHTS_PER_GAME
	best_m = 0.0
	best_design = ""
	reached = {}
	total_earned = 0
	last_flight = {}

func part(slot: String, id: Variant) -> Dictionary:
	for p: Dictionary in PARTS[slot]:
		if p.id == id:
			return p
	return {}

func is_owned(id: String) -> bool:
	return owned.has(id)

## Equip an owned part, or buy and equip one the player can afford. Returns false if neither.
func choose(slot: String, id: String) -> bool:
	var p := part(slot, id)
	if p.is_empty():
		return false
	if not is_owned(id):
		if int(p.cost) > money:
			return false
		money -= int(p.cost)
		owned[id] = true
	design[slot] = id
	return true

## Every purchase worth considering: single parts, and pairs that only help together.
func upgrade_candidates() -> Array:
	var out: Array = []
	for slot: String in SLOT_ORDER:
		for p: Dictionary in PARTS[slot]:
			if p.id != design[slot] and not is_owned(p.id) and int(p.cost) <= money:
				out.append({"parts": [[slot, p.id]], "cost": int(p.cost), "design": with_part(slot, p.id), "label": "%s: %s" % [SLOT_TITLES[slot], p.name]})
	for pair: Array in [["tank", "engine", "fuel tank and engine"], ["utank", "uengine", "second stage"]]:
		var a_slot: String = pair[0]
		var b_slot: String = pair[1]
		for a: Dictionary in PARTS[a_slot]:
			for b: Dictionary in PARTS[b_slot]:
				if (a.id == "u0") != (b.id == "ue0") or a.id == "u0":
					continue
				var cost := (0 if is_owned(a.id) else int(a.cost)) + (0 if is_owned(b.id) else int(b.cost))
				if cost <= 0 or cost > money or (a.id == design[a_slot] and b.id == design[b_slot]):
					continue
				var d := design.duplicate()
				d[a_slot] = a.id
				d[b_slot] = b.id
				out.append({"parts": [[a_slot, a.id], [b_slot, b.id]], "cost": cost, "design": d, "label": "%s + %s %s" % [a.name, b.name, pair[2]]})
	return out

## The affordable upgrade that adds the most height per dollar, or an empty result.
func best_upgrade() -> Dictionary:
	var now := float(predict(design).apogee)
	var best := {}
	var best_rate := 0.0
	for c: Dictionary in upgrade_candidates():
		var after: Dictionary = predict(c.design)
		var gain := float(after.apogee) - now
		if after.reason != "ok" or gain <= 0.0:
			continue
		var rate := gain / float(c.cost)
		if rate > best_rate:
			best_rate = rate
			best = c
			best["gain"] = gain
	return best

func apply_upgrade(u: Dictionary) -> void:
	for pair: Array in u.parts:
		choose(pair[0], pair[1])

func with_part(slot: String, id: String) -> Dictionary:
	var d := design.duplicate()
	d[slot] = id
	return d

## Money for a height: a smooth reward, plus one-time bonuses for passing each real milestone.
func earnings(apogee_m: float, d: Dictionary, count_bonus: bool = true) -> Dictionary:
	var km := maxf(apogee_m, 0.0) / 1000.0
	var base := 42.0 * pow(km, 0.40)
	var mult := float(part("nose", d.nose).get("reward", 1.0))
	var bonus := 0
	var passed: Array = []
	for m: Dictionary in Data.milestones:
		if km >= float(m.km) and not reached.has(m.id):
			if count_bonus:
				bonus += int(m.bonus)
			passed.append(m)
	return {"pay": int(round(base * mult)), "bonus": bonus, "passed": passed, "total": int(round(base * mult)) + bonus}

func record_flight(apogee_m: float, broke: bool) -> Dictionary:
	var e := earnings(apogee_m, design)
	money += int(e.total)
	total_earned += int(e.total)
	for m: Dictionary in e.passed:
		reached[m.id] = true
	flights_left -= 1
	var was_best := apogee_m > best_m
	if was_best:
		best_m = apogee_m
		best_design = describe(design)
	last_flight = {"apogee": apogee_m, "broke": broke, "earn": e, "best": was_best, "predicted": float(predict(design).apogee)}
	return last_flight

func describe(d: Dictionary) -> String:
	var bits := PackedStringArray()
	bits.append("%s tank" % str(part("tank", d.tank).name))
	bits.append("%s engine" % str(part("engine", d.engine).name))
	if d.boosters != "b0":
		bits.append("%s boosters" % str(part("boosters", d.boosters).name))
	if has_upper(d):
		bits.append("second stage")
	bits.append(str(part("nose", d.nose).name).to_lower())
	bits.append(str(part("fins", d.fins).name).to_lower())
	return ", ".join(bits)

static func format_height(m: float) -> String:
	var km := m / 1000.0
	if km >= MOON_M / 1000.0:
		return "384,400 km (the Moon!)"
	if km >= 1000.0:
		return "%s km" % UI.grouped(int(km))
	if km >= 10.0:
		return "%.0f km" % km
	if km >= 1.0:
		return "%.1f km" % km
	return "%.0f m" % m

# ---- Leaderboard: kept across games so the day's winner can be read at the end ----

static func clean_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c >= 32 and c != 127:
			out += raw[i]
	out = out.strip_edges()
	if out.is_empty():
		return "Anonymous"
	return out.substr(0, NAME_MAX).strip_edges()

func _load_board() -> Array:
	if not FileAccess.file_exists(board_path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(board_path))
	return parsed if parsed is Array else []

func _save_board(entries: Array) -> void:
	# Write to a temporary file first, so a crash cannot wipe the day's scores.
	var tmp := board_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Could not save the leaderboard")
		return
	f.store_string(JSON.stringify(entries))
	f.close()
	DirAccess.rename_absolute(tmp, board_path)

func today() -> String:
	return Time.get_date_string_from_system()

## Adds a score and returns the new entry.
func add_score(player: String, height_m: float, rocket: String) -> Dictionary:
	var entries := _load_board()
	var entry := {"name": clean_name(player), "height": height_m, "rocket": rocket, "date": today(), "at": Time.get_unix_time_from_system(), "id": "%d-%d" % [Time.get_ticks_usec(), entries.size()]}
	entries.append(entry)
	_save_board(entries)
	return entry

## Today's scores, highest first. On a tie, whoever got there first ranks higher.
func todays_board() -> Array:
	var out: Array = []
	var day := today()
	for e: Variant in _load_board():
		if e is Dictionary and e.get("date") == day:
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.height) == float(b.height):
			return float(a.at) < float(b.at)
		return float(a.height) > float(b.height))
	return out

func clear_today() -> void:
	var keep: Array = []
	var day := today()
	for e: Variant in _load_board():
		if e is Dictionary and e.get("date") != day:
			keep.append(e)
	_save_board(keep)
