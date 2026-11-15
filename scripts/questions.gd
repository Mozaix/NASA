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
	if t.get("escape_kms") != null and str(t.get("id", "")) != "earth" and absf(float(t.escape_kms) - 11.2) > 0.3:
		var e := float(t.escape_kms)
		out.append({"id": "m_escape", "q": "Which world needs the most speed to escape its gravity?",
			"right": "Earth" if e < 11.2 else nm, "wrong": [nm if e < 11.2 else "Earth", "They need exactly the same speed"],
			"why": "Escape velocity is %.1f km/s from %s and 11.2 km/s from Earth." % [e, nm]})
	return out
