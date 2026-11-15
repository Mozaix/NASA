class_name Questions
extends RefCounted
## Questions for the debris dodge in the cruise. Each encounter asks one question about the player's own
## mission, worked out from the bundled NASA data, and one about space debris or meteoroids.
## Every question: {id, q, right, wrong: [two], why}.

## Space debris and meteoroids. Explanations stick to well-established physics and NASA practice.
const HAZARD := [
	{"id": "debris_speed", "q": "Why can a fleck of paint damage a spacecraft?",
	 "right": "It moves several kilometres per second, so it hits very hard",
	 "wrong": ["Paint is magnetic and sticks to metal", "Space makes everything heavier"],
	 "why": "Impact energy grows with the square of speed. In low Earth orbit, objects move at about 7 to 8 km/s."},
	{"id": "debris_where", "q": "Where is most human-made space debris found?",
	 "right": "In low Earth orbit, close to Earth",
	 "wrong": ["Between Mars and Jupiter", "Close to the Sun"],
	 "why": "Most tracked debris is in low Earth orbit, within about 2,000 km of Earth's surface, where most satellites fly."},
	{"id": "debris_iss", "q": "What does the International Space Station do when tracked debris may come too close?",
	 "right": "It fires its thrusters to move out of the way",
	 "wrong": ["It shoots the debris down", "Nothing: debris cannot reach that high"],
	 "why": "NASA tracks debris near the station and plans debris avoidance manoeuvres when the risk is high enough."},
	{"id": "debris_shield", "q": "How do spacecraft protect themselves from small debris?",
	 "right": "Layered shields that break up a particle before it reaches the hull",
	 "wrong": ["A magnetic force field", "Painting the spacecraft black"],
	 "why": "Whipple shields, used on the ISS, have a thin outer bumper that shatters a particle so the layers behind can stop the spread-out pieces."},
	{"id": "debris_drag", "q": "Why does debris in low orbit eventually fall back to Earth?",
	 "right": "Thin air at that height slowly drags it down",
	 "wrong": ["The Moon pulls it back", "Sunlight pushes it down"],
	 "why": "Earth's atmosphere thins out with height but never quite ends. Its drag slowly lowers objects in low orbit until they burn up."},
	{"id": "meteoroid_what", "q": "What is a meteoroid?",
	 "right": "A bit of rock or dust travelling through space",
	 "wrong": ["A broken satellite", "A cloud of frozen gas around a planet"],
	 "why": "NASA describes meteoroids as objects in space that range in size from dust grains to small asteroids."},
	{"id": "meteoroid_burn", "q": "What happens to most meteoroids that hit Earth's atmosphere?",
	 "right": "They burn up and are seen as shooting stars",
	 "wrong": ["They bounce back into space", "They all land as rocks on the ground"],
	 "why": "Air in front of a meteoroid is squeezed and heated so much that most burn up high in the sky. The streak of light is called a meteor."},
	{"id": "debris_cascade", "q": "Why are collisions between pieces of space debris a problem?",
	 "right": "Each crash breaks into more pieces that can hit other things",
	 "wrong": ["They make satellites go faster", "They make the Sun dimmer"],
	 "why": "A collision turns two objects into a cloud of fragments, and each fragment can hit something else."},
	{"id": "iss_speed", "q": "About how fast does the International Space Station travel?",
	 "right": "About 28,000 km per hour",
	 "wrong": ["About 900 km per hour, like a jet", "About 300,000 km per second, like light"],
	 "why": "The ISS circles Earth about every 90 minutes at roughly 7.7 km/s, which is about 28,000 km per hour."},
	{"id": "iss_float", "q": "Why do astronauts on the space station float?",
	 "right": "They and the station are falling around Earth together",
	 "wrong": ["There is no gravity in space", "The station is held up by magnets"],
	 "why": "At the station's height gravity is still about 90% as strong as on the ground. Everything aboard is in free fall around Earth, so nothing presses on the floor."},
	{"id": "graveyard", "q": "What happens to many old satellites high above Earth when they stop working?",
	 "right": "They are pushed into a higher 'graveyard' orbit out of the way",
	 "wrong": ["Astronauts collect them", "They are recharged by the Sun and keep working"],
	 "why": "Satellites in geostationary orbit, about 36,000 km up, are usually boosted a few hundred kilometres higher at the end of their life, clear of working satellites."},
	{"id": "tracking", "q": "How do teams on the ground know where pieces of debris are?",
	 "right": "Radars and telescopes track them",
	 "wrong": ["Astronauts count them by looking out of the window", "Debris glows in the dark"],
	 "why": "Radars and telescopes track tens of thousands of objects in Earth orbit, from about the size of a softball upwards."},
	{"id": "mass_energy", "q": "Two pieces of debris hit at the same speed. Which does more damage?",
	 "right": "The heavier piece",
	 "wrong": ["The lighter piece", "They always do the same damage"],
	 "why": "Impact energy is half the mass times the speed squared, so at the same speed a heavier piece carries more energy."},
	{"id": "meteoroid_source", "q": "Where do most meteoroids come from?",
	 "right": "Broken bits of comets and asteroids",
	 "wrong": ["Old satellites", "Volcanoes on the Moon"],
	 "why": "Most meteoroids are pieces knocked off asteroids or dust shed by comets as they near the Sun."},
	{"id": "meteor_shower", "q": "What causes a meteor shower?",
	 "right": "Earth passing through dust left behind by a comet",
	 "wrong": ["Two stars crashing into each other", "Many satellites burning up at once"],
	 "why": "A comet leaves a trail of dust along its orbit. When Earth crosses that trail each year, many grains burn up in the sky at once."},
	{"id": "micrometeoroid", "q": "What is a micrometeoroid?",
	 "right": "A tiny grain of space dust, often smaller than a grain of sand",
	 "wrong": ["A small moon", "A piece of a rocket engine"],
	 "why": "Micrometeoroids are tiny, but at speeds of many kilometres per second they can still pit windows and wear down surfaces."},
	{"id": "less_debris", "q": "How do mission teams avoid making new space debris?",
	 "right": "They plan for old stages and satellites to come down and burn up",
	 "wrong": ["They paint satellites a bright colour", "They only launch at night"],
	 "why": "Rocket stages and satellites in low orbit are planned to re-enter and burn up in the atmosphere within a few years of the end of their mission."},
	{"id": "moon_craters", "q": "Why does the Moon have so many more craters than Earth?",
	 "right": "It has no air to burn up meteoroids and no weather to wear craters away",
	 "wrong": ["The Moon is made of softer rock", "Meteoroids are attracted to the Moon"],
	 "why": "Earth's atmosphere burns up most small meteoroids, and wind, water and moving plates erase old craters. The Moon has none of these."},
	{"id": "high_debris", "q": "Why does debris high above Earth stay up for so long?",
	 "right": "There is almost no air that high to slow it down",
	 "wrong": ["Sunlight pushes it higher every day", "The Moon's gravity holds it in place"],
	 "why": "Above about 1,000 km the air is so thin that drag is tiny, so debris there can stay in orbit for centuries or longer."},
	{"id": "ram_side", "q": "Which side of a spacecraft in orbit gets hit by debris most often?",
	 "right": "The side facing the way it is flying",
	 "wrong": ["The side facing away from Earth", "Every side equally"],
	 "why": "A spacecraft runs into most debris head-on as it moves, so the forward-facing side usually gets the most hits and the thickest shielding."},
]

## Two questions per encounter: one about this mission, then one about debris or meteoroids.
## `used` holds ids already asked on this mission so nothing repeats.
static func encounter(target: Dictionary, plan: Dictionary, used: Array) -> Array:
	var out: Array = []
	var mission: Array = mission_questions(target, plan).filter(func(q: Dictionary) -> bool: return not used.has(q.id))
	var hazard: Array = HAZARD.filter(func(q: Dictionary) -> bool: return not used.has(q.id))
	mission.shuffle()
	hazard.shuffle()
	if not mission.is_empty():
		out.append(mission[0])
	if not hazard.is_empty():
		out.append(hazard[0])
	for q: Dictionary in out:
		used.append(q.id)
	return out

## A "bigger, smaller or about the same" question from one value compared with Earth's.
static func _compare(id: String, q: String, value: float, earth_value: float, more: String, less: String, same: String, why: String, same_band: float = -1.0) -> Dictionary:
	var is_same := absf(value - earth_value) <= same_band if same_band >= 0.0 else absf(value / earth_value - 1.0) < 0.1
	var right := same if is_same else (more if value > earth_value else less)
	var wrong := [more, less, same]
	wrong.erase(right)
	return {"id": id, "q": q, "right": right, "wrong": wrong, "why": why}

## Puts the right answer at a random place among the wrong ones. `avoid` is the slot the right
## answer took last time; it is used again only now and then, so the answer never sits in one place.
static func arrange(q: Dictionary, rng: RandomNumberGenerator, avoid: int = -1) -> Array:
	var wrong: Array = (q.get("wrong", []) as Array).duplicate()
	wrong.shuffle()
	var n := wrong.size() + 1
	var slot := rng.randi_range(0, n - 1)
	if slot == avoid and rng.randf() < 0.75:
		slot = (slot + rng.randi_range(1, n - 1)) % n
	wrong.insert(slot, q.right)
	return wrong.map(func(a: Variant) -> String: return str(a))

## Questions built from this target's own numbers.
static func mission_questions(t: Dictionary, plan: Dictionary) -> Array:
	var out: Array = []
	var nm := str(t.get("name", "your target"))
	var g = t.get("gravity")
	if g != null and str(t.get("id", "")) != "earth":
		var ratio := float(g) / 9.8
		var right := "Weaker than Earth's" if ratio < 0.9 else ("Stronger than Earth's" if ratio > 1.1 else "About the same as Earth's")
		var all := ["Weaker than Earth's", "Stronger than Earth's", "About the same as Earth's"]
		all.erase(right)
		var where := " at the cloud tops" if str(t.get("class", "")).contains("giant") or str(t.get("id", "")) in ["jupiter", "saturn", "uranus", "neptune"] else ""
		out.append({"id": "m_gravity", "q": "How does gravity on %s compare with Earth's?" % nm, "right": right, "wrong": all,
			"why": "Gravity on %s%s is about %.1f m/s², which is %d%% of Earth's 9.8 m/s²." % [nm, where, float(g), int(round(ratio * 100.0))]})
	var days := float(plan.get("days", 0.0))
	if days > 0.0 and str(plan.get("kind", "")) != "interstellar":
		var right_t := Orbital.format_time(days)
		var wrong_t: Array = []
		for k: float in [0.2, 4.0, 0.45, 2.5]:
			var w := Orbital.format_time(days * k)
			if w != right_t and not wrong_t.has(w):
				wrong_t.append(w)
		if wrong_t.size() >= 2:
			out.append({"id": "m_trip", "q": "How long does your transfer to %s take?" % nm, "right": right_t, "wrong": wrong_t.slice(0, 2),
				"why": "A Hohmann transfer follows half of an ellipse from Earth's orbit to the target's. For %s that takes %s." % [nm, right_t]})
	var moons = t.get("n_moons")
	if moons != null:
		var n := int(moons)
		var opts: Array = []
		for v: int in [n, n + 2 + n / 2, maxi(n - 1 - n / 3, 0) if n > 1 else n + 1]:
			if not opts.has(str(v)):
				opts.append(str(v))
		if opts.size() == 3:
			out.append({"id": "m_moons", "q": "How many known moons does %s have?" % nm, "right": str(n), "wrong": [opts[1], opts[2]],
				"why": "NASA lists %d known moon%s for %s. New moons are still being found around the giant planets." % [n, "" if n == 1 else "s", nm]})
	if str(plan.get("kind", "")) == "hohmann":
		out.append({"id": "m_window", "q": "Why did your launch date matter for this trip?",
			"right": "Earth and the target must be lined up for the cheapest path",
			"wrong": ["Rockets can only launch in summer", "The Sun is in the way the rest of the year"],
			"why": "Both planets keep moving. Launching when they are lined up lets a transfer orbit meet the target with the least fuel."})
	var earth := Data.body("earth")
	if t.get("day_hours") != null and str(t.get("id", "")) != "earth":
		var dh := absf(float(t.day_hours))
		out.append(_compare("m_day", "Is a day on %s longer or shorter than a day on Earth?" % nm, dh, 24.0, "Longer than Earth's", "Shorter than Earth's", "About the same as Earth's",
			"A day on %s lasts about %s, compared with 24 hours on Earth." % [nm, Orbital.format_time(dh / 24.0) if dh >= 48.0 else "%.1f hours" % dh]))
	if t.get("temp_c") != null and str(t.get("id", "")) != "earth":
		var tc := float(t.temp_c)
		out.append(_compare("m_temp", "Is %s hotter or colder than Earth on average?" % nm, tc, 15.0, "Hotter than Earth", "Colder than Earth", "About the same as Earth",
			"The average temperature on %s is about %d °C. Earth's average is about 15 °C." % [nm, int(round(tc))], 10.0))
	if t.get("radius_km") != null and str(t.get("id", "")) != "earth" and str(t.get("kind", "")) != "exoplanet":
		var rk := float(t.radius_km)
		out.append(_compare("m_size", "Is %s bigger or smaller than Earth?" % nm, rk, 6371.0, "Bigger than Earth", "Smaller than Earth", "About the same size as Earth",
			"%s has a radius of about %s km. Earth's is about 6,371 km." % [nm, UI.grouped(int(rk))]))
	if str(t.get("kind", "")) == "planet" and t.get("a_km") != null and str(t.get("id", "")) != "earth":
		var au := float(t.a_km) / float(earth.get("a_km", 149598023.0))
		out.append({"id": "m_sun", "q": "Is %s closer to the Sun than Earth, or farther away?" % nm,
			"right": "Closer than Earth" if au < 1.0 else "Farther than Earth", "wrong": ["Farther than Earth" if au < 1.0 else "Closer than Earth", "The same distance as Earth"],
			"why": "%s orbits about %.2f times as far from the Sun as Earth does." % [nm, au]})
	if t.get("escape_kms") != null and str(t.get("id", "")) != "earth" and absf(float(t.escape_kms) - 11.2) > 0.3:
		var e := float(t.escape_kms)
		out.append({"id": "m_escape", "q": "Which world needs the most speed to escape its gravity?",
			"right": "Earth" if e < 11.2 else nm, "wrong": [nm if e < 11.2 else "Earth", "They need exactly the same speed"],
			"why": "Escape velocity is %.1f km/s from %s and 11.2 km/s from Earth." % [e, nm]})
	return out
