extends Node
## Headless test suite. Run with: godot --headless --path . res://tests/run_tests.tscn
## Checks physics against textbook values, data integrity, the shipped game logic and every scene.

var fails: Array[String] = []
var passes := 0

func check(cond: bool, name: String, detail: Variant = "") -> void:
	if cond:
		passes += 1
	else:
		fails.append("%s  %s" % [name, str(detail)])

func near(a: float, b: float, tol: float, name: String) -> void:
	check(absf(a - b) <= tol, name, "got %.3f, expected %.3f +/- %.3f" % [a, b, tol])

func _ready() -> void:
	test_orbital()
	test_data()
	test_design_all_targets()
	test_scoring()
	test_input()
	test_rocket_physics()
	test_rocket_prediction()
	test_rocket_limits()
	test_rocket_economy()
	test_leaderboard()
	test_terrain()
	test_rover_contact()
	await test_autoland()
	await test_player_reports()
	await test_learning()
	test_version_stamp()
	test_tips()
	await test_demo()
	await test_rocket_scenes()
	await test_scenes()
	await test_hatch()
	await test_parachute()
	await test_salvage()
	test_learning_results()
	await test_orbit_button()
	await test_bahrain()
	await test_countdown()
	print("\nPASSED %d, FAILED %d" % [passes, fails.size()])
	for f in fails:
		print("  FAIL: ", f)
	Sfx._stop_all()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit(1 if fails.size() > 0 else 0)

func test_orbital() -> void:
	# Published Hohmann values: Earth to Mars 259 days, Jupiter 2.7 years, Neptune 30.6 years.
	var e: Dictionary = Data.body("earth")
	var a1 := float(e.a_km) * 1000.0
	near(Orbital.hohmann_days(a1, float(Data.body("mars").a_km) * 1000.0), 259.0, 3.0, "Mars transfer days")
	near(Orbital.hohmann_days(a1, float(Data.body("jupiter").a_km) * 1000.0) / 365.25, 2.73, 0.05, "Jupiter transfer years")
	near(Orbital.hohmann_days(a1, float(Data.body("neptune").a_km) * 1000.0) / 365.25, 30.6, 0.4, "Neptune transfer years")
	var mars := Orbital.plan(Data.body("mars"))
	near(float(mars.departure) / 1000.0, 3.6, 0.2, "Mars departure km/s from LEO")
	near(float(mars.vinf_dep) / 1000.0, 2.94, 0.1, "Mars departure v-infinity")
	near(float(mars.vinf_arr) / 1000.0, 2.65, 0.1, "Mars arrival v-infinity")
	var moon := Orbital.plan(Data.body("moon"))
	near(float(moon.departure) / 1000.0, 3.1, 0.15, "Moon translunar injection km/s")
	near(float(moon.days), 5.0, 0.4, "Moon Hohmann days")
	near(Orbital.delta_v(450.0, 10.0, 2.0), 450.0 * 9.80665 * log(5.0), 0.01, "Rocket equation")
	near(Orbital.synodic_days("mars"), 780.0, 5.0, "Mars synodic period")
	near(Orbital.synodic_days("venus"), 584.0, 5.0, "Venus synodic period")
	# Real optimal Earth-Mars phase angle is about 44 degrees.
	near(Orbital.ideal_phase("mars"), 44.0, 2.0, "Mars ideal phase angle")
	# Successive Mars windows must repeat at the synodic period. 2026-11 to 2029-01 region.
	var start := Time.get_unix_time_from_datetime_string("2026-06-01T00:00:00")
	var w1 := Orbital.best_window("mars", start, 780.0)
	var w2 := Orbital.best_window("mars", w1 + 200.0 * 86400.0, 780.0)
	near((w2 - w1) / 86400.0, 780.0, 12.0, "Mars window spacing")
	print("  Mars windows: ", Orbital.date_string(w1), " then ", Orbital.date_string(w2))
	# Real Mars launch opportunity is near Nov-Dec 2026 and Dec 2028-Jan 2029.
	check(Orbital.date_string(w1) >= "2026-08-01" and Orbital.date_string(w1) <= "2027-01-31", "First Mars window near late 2026", Orbital.date_string(w1))
	check(Orbital.window_factor("mars", w1) < 1.01, "Best window costs nothing extra", Orbital.window_factor("mars", w1))

func test_data() -> void:
	check(Data.targets().size() >= 60, "At least 8 planets + 8 moons + exoplanets", Data.targets().size())
	near(float(Data.body("mars").gravity), 3.7, 0.05, "Mars gravity from fact sheet")
	near(float(Data.body("moon").gravity), 1.6, 0.05, "Moon gravity from fact sheet")
	near(float(Data.body("jupiter").gravity), 23.1, 0.1, "Jupiter gravity from fact sheet")
	near(float(Data.body("titan").gravity), 1.35, 0.03, "Titan derived gravity")
	near(float(Data.body("europa").gravity), 1.31, 0.03, "Europa derived gravity")
	for t: Dictionary in Data.targets():
		check(float(t.get("radius_km", 0.0)) > 0.0, t.name + " has a radius")
		check(float(t.get("mass_kg", 0.0)) > 0.0, t.name + " has a mass")
		check(t.get("gravity") != null and float(t.gravity) > 0.0, t.name + " has gravity")
		check(not (t.get("facts", []) as Array).is_empty(), t.name + " has NASA facts")
		for f: Dictionary in t.get("facts", []):
			check(str(f.get("url", "")).begins_with("http"), t.name + " fact has a source URL")
	var exo_count := 0
	for t: Dictionary in Data.targets():
		if t.kind == "exoplanet":
			exo_count += 1
			check(t.get("sy_dist") != null, t.name + " has a distance")
	check(exo_count >= 45, "About 50 exoplanets", exo_count)
	for rid: String in Data.regions:
		var r: Dictionary = Data.regions[rid]
		check(not (r.pois as Array).is_empty(), rid + " has POIs")
		for f: String in ["height.f32", "color.jpgdata", "normal.pngdata", "minimap.jpgdata"]:
			check(FileAccess.file_exists("res://data/regions/%s/%s" % [rid, f]), rid + "/" + f)
	check(FileAccess.file_exists("res://data/SOURCES.md"), "SOURCES.md exists")

## Demo mode must be flyable for every choice it offers, with any rocket it allows.
func test_demo() -> void:
	var picker: Node = (load("res://scenes/demo_picker.tscn") as PackedScene).instantiate()
	add_child(picker)
	await get_tree().process_frame
	check(Game.is_demo(), "Picker turns demo mode on")
	var dests: Array = picker.DESTINATIONS
	for i in dests.size():
		picker._choose_destination(i, true)
		for kit: Dictionary in picker.KITS:
			picker._choose_kit(str(kit.id))
			check(Game.problems().is_empty(), "Demo mission flies: %s/%s" % [dests[i].id, kit.id], Game.problems())
		var any := false
		for l: Dictionary in Game.LAUNCHERS:
			if Game.can_design_with(str(l.id)):
				any = true
				var keep: String = Game.mission.launcher
				Game.design_with(str(l.id))
				check(Game.problems().is_empty(), "Offered rocket works: %s/%s" % [dests[i].id, l.id], Game.problems())
				Game.design_with(keep)
		check(any, "Some rocket reaches " + str(dests[i].id))
	# Stepping through the page draws cards and hologram parts for each step.
	for i in 4:
		picker._show_step(i)
		await get_tree().process_frame
		check(picker._cards.get_child_count() >= 2, "Choices side by side on step %d" % i, picker._cards.get_child_count())
		check(picker._holo.get_child_count() >= 1, "Hologram shows something on step %d" % i)
	# The last step's hologram must hold the rocket, lander, rover and each instrument.
	picker._choose_kit("lab")
	for id: String in ["rocket", "lander", "rover", "camera", "spectrometer", "drill"]:
		check(picker._parts.has(id), "Hologram includes " + id)
	picker.queue_free()
	await get_tree().process_frame
	# Demo surface: only two stops, both collectable, on the same terrain as the full game.
	Game.new_mission()
	Game.mission.demo = true
	Game.mission.target_id = "mars"
	Game.mission.region_id = "gale"
	Game.mission.instruments = ["camera"]
	Game.auto_design()
	Game.mission.instruments = ["camera"]
	var surface: Node = (load("res://scenes/surface.tscn") as PackedScene).instantiate()
	add_child(surface)
	await get_tree().process_frame
	check(surface.pois.size() == 2, "Demo has two stops", surface.pois.size())
	surface.queue_free()
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Look-down view points the camera straight at the ground under the lander.
	Game.new_mission()
	Game.auto_design()
	var land: Node = (load("res://scenes/landing.tscn") as PackedScene).instantiate()
	add_child(land)
	await get_tree().process_frame
	land.toggle_look_down()
	for f in 40:
		land._process(1.0 / 60.0)
	var facing: Vector3 = -land.cam.global_basis.z
	check(facing.dot(Vector3.DOWN) > 0.98, "Look-down camera faces the ground", facing)
	check(absf(land.cam.global_position.x - land.craft.global_position.x) < 1.0, "Look-down camera sits at the lander")
	land.toggle_look_down()
	for f in 40:
		land._process(1.0 / 60.0)
	check((-land.cam.global_basis.z).dot(Vector3.DOWN) < 0.9, "Returning restores the chase view")
	land.queue_free()
	await get_tree().process_frame
	Sfx.stop_loops()
	Game.new_mission()

func test_rocket_physics() -> void:
	var R := Rocket2D
	R.new_game()
	var d: Dictionary = R.design.duplicate()
	# With no gravity or air, the sim must reproduce the rocket equation.
	d.tank = "t3"
	d.engine = "e3"
	var s = R.make_sim(d)
	s.mu = 0.0
	s.rho0 = 0.0
	s.margin = 1.0
	s.theta = 0.0
	var m0: float = s.mass()
	var m1: float = m0 - s.main_prop
	while s.burning():
		s.step(0.02)
	near(s.vy, Orbital.delta_v(285.0, m0, m1), 12.0, "Sim matches the rocket equation")
	# Earth's values come from the NASA fact sheet data.
	var e: Dictionary = Data.body("earth")
	check(e.has("surface_density") and e.has("scale_height_km"), "Earth air data is bundled")
	var s2 = R.make_sim(R.design)
	near(s2.mu / pow(s2.radius, 2.0), 9.8, 0.05, "Surface gravity from real mass and radius")
	# A vertical shot above the air follows energy conservation.
	var s3 = R.make_sim(R.design)
	s3.h = 200000.0
	s3.vy = 3000.0
	s3.lifted = true
	var r: float = s3.radius + s3.h
	var want: float = 1.0 / (1.0 / r - 3000.0 * 3000.0 / (2.0 * s3.mu)) - s3.radius
	near(R.apogee_from(s3), want, 1.0, "Apogee from orbital energy")

func test_rocket_prediction() -> void:
	var R := Rocket2D
	R.new_game()
	var start: Dictionary = R.design.duplicate()
	var bare: Dictionary = R.predict(start)
	print("  starter rocket: %s, reason %s, twr %.2f" % [R.format_height(float(bare.apogee)), bare.reason, float(bare.twr)])
	check(bare.reason == "breakup", "Starter with no fins tumbles", bare)
	var finned: Dictionary = R.predict(R.with_part("fins", "small"))
	print("  with small fins: %s" % R.format_height(float(finned.apogee)))
	check(float(finned.apogee) > float(bare.apogee) * 2.0, "Fins make a big difference", finned)
	check(finned.reason == "ok", "Small fins fix the tumble", finned)
	# Better noses go higher, once the rocket is stable.
	R.choose("fins", "small")
	R.money = 100000
	var last := 0.0
	for id: String in ["cap", "cone", "ogive"]:
		var h: float = R.predict(R.with_part("nose", id)).apogee
		check(h > last, "Nose %s beats the previous one" % id, h)
		last = h
	# A huge tank on a tiny engine never leaves the pad.
	check(R.predict(R.with_part("tank", "t4")).reason == "no_liftoff", "Too heavy to lift off is predicted")
	# Half a second stage is dead weight, and predicted to hurt.
	check(float(R.predict(R.with_part("utank", "u1")).apogee) < float(finned.apogee), "A tank with no engine hurts")
	# The prediction must match a real flight with no wind and no steering.
	for parts: Dictionary in [{"fins": "small"}, {"fins": "small", "tank": "t2", "engine": "e2", "nose": "cone"}, {"fins": "large", "tank": "t3", "engine": "e3", "nose": "ogive", "boosters": "b2", "utank": "u2", "uengine": "ue2"}]:
		var d: Dictionary = R.design.duplicate()
		d.merge(parts, true)
		var p: Dictionary = R.predict(d)
		var s = R.make_sim(d)
		while s.burning() and not s.broken:
			s.step(1.0 / 20.0)
		while not s.broken and s.h < 120000.0 and s.vy > 0.0:
			s.step(1.0 / 20.0)
		var actual: float = R.apogee_from(s) if s.h >= 120000.0 else s.h
		print("  prediction %s, flown %s" % [R.format_height(float(p.apogee)), R.format_height(actual)])
		check(absf(actual - float(p.apogee)) < maxf(float(p.apogee) * 0.05, 300.0), "Prediction matches the flight", [p.apogee, actual])
	R.new_game()

func test_rocket_limits() -> void:
	var R := Rocket2D
	R.new_game()
	# No design may ever report a negative or impossible height, whatever is combined.
	var worst := 0.0
	var count := 0
	var stages_help := 0
	for t: Dictionary in R.PARTS.tank:
		for e: Dictionary in R.PARTS.engine:
			for b: Dictionary in R.PARTS.boosters:
				for u: Array in [["u0", "ue0"], ["u1", "ue1"], ["u2", "ue2"], ["u3", "ue3"], ["u3", "ue1"], ["u0", "ue2"]]:
					var d := {"nose": "ogive", "fins": "large", "tank": t.id, "engine": e.id, "boosters": b.id, "utank": u[0], "uengine": u[1]}
					var a := float(R.predict(d).apogee)
					worst = minf(worst, a)
					check(a <= R.MOON_M and not is_nan(a), "Height is sensible", [d, a])
					count += 1
	check(worst >= 0.0, "No design reports a negative height", worst)
	print("  checked %d designs" % count)
	# A second stage must be worth having on a rocket that can carry it.
	var base := {"nose": "ogive", "fins": "large", "tank": "t3", "engine": "e3", "boosters": "b0", "utank": "u0", "uengine": "ue0"}
	var staged := base.duplicate()
	staged.utank = "u2"
	staged.uengine = "ue2"
	print("  one stage %s, two stages %s" % [R.format_height(float(R.predict(base).apogee)), R.format_height(float(R.predict(staged).apogee))])
	check(float(R.predict(staged).apogee) > float(R.predict(base).apogee) * 1.3, "Second stage helps", [base, staged])
	# The best parts must be able to reach every milestone, so the top of the ladder is real.
	var top := {"nose": "ogive", "fins": "swept", "tank": "t4", "engine": "e4", "boosters": "b3", "utank": "u3", "uengine": "ue3"}
	print("  every best part: %s" % R.format_height(float(R.predict(top).apogee)))
	check(float(R.predict(top).apogee) >= R.MOON_M, "The best rocket can reach the Moon's distance", R.predict(top))
	check(R.predict(top).reason == "ok", "The best rocket flies", R.predict(top))

func test_rocket_economy() -> void:
	var R := Rocket2D
	# Money rules
	R.new_game()
	check(R.money == R.START_MONEY, "Game starts with the starter money")
	check(not R.choose("tank", "t4"), "Cannot buy what you cannot afford")
	check(R.money == R.START_MONEY and R.design.tank == "t1", "A refused purchase changes nothing")
	check(R.choose("fins", "small"), "Can buy fins")
	check(R.money == R.START_MONEY - 60, "Buying costs money")
	check(R.choose("fins", "nofins") and R.money == R.START_MONEY - 60, "Owned parts swap for free")
	check(R.choose("fins", "small") and R.money == R.START_MONEY - 60, "No double charge")
	# Milestone bonuses are paid once.
	var first: Dictionary = R.record_flight(60000.0, false)
	check(int(first.earn.bonus) == 60 + 180, "Passing two milestones pays both", first.earn.bonus)
	var second: Dictionary = R.record_flight(60000.0, false)
	check(int(second.earn.bonus) == 0, "A milestone pays only once", second.earn.bonus)
	check(R.flights_left == R.FLIGHTS_PER_GAME - 2, "Flights are used up")
	# Shuttle pays more for the same height.
	var plain: Dictionary = R.earnings(100000.0, R.design, false)
	var shuttle: Dictionary = R.earnings(100000.0, R.with_part("nose", "shuttle"), false)
	check(int(shuttle.pay) > int(plain.pay), "Winged shuttle earns more")
	# Reset wipes the player's progress.
	R.new_game()
	check(R.money == R.START_MONEY and R.owned.size() == R.SLOT_ORDER.size() and R.flights_left == R.FLIGHTS_PER_GAME and R.best_m == 0.0 and R.reached.is_empty(), "New game resets everything")
	# A sensible player, buying the best predicted gain per dollar, must keep climbing.
	var heights: Array[String] = []
	var prev := 0.0
	var climbed := 0
	for f in R.FLIGHTS_PER_GAME:
		_greedy_buy(R)
		var p: Dictionary = R.predict(R.design)
		var h: float = float(p.apogee) * 0.9
		heights.append(R.format_height(h))
		if h > prev * 1.05:
			climbed += 1
		prev = maxf(prev, h)
		R.record_flight(h, false)
	print("  greedy game: ", heights, " money left $", R.money)
	check(climbed >= R.FLIGHTS_PER_GAME - 1, "Each flight can beat the last", heights)
	check(prev >= 300000.0, "A good game reaches well into space", prev)
	check(prev < R.MOON_M, "The Moon stays out of reach of a first-try greedy game", prev)
	R.new_game()

func _greedy_buy(R: Node) -> void:
	for round_i in 12:
		var u: Dictionary = R.best_upgrade()
		if u.is_empty():
			return
		R.apply_upgrade(u)

func test_rocket_scenes() -> void:
	var R := Rocket2D
	var keep: String = R.board_path
	R.board_path = "user://test_board2.json"
	R.new_game()
	R.choose("fins", "small")
	var build: Node = (load("res://scenes/rocket2d.tscn") as PackedScene).instantiate()
	add_child(build)
	await get_tree().process_frame
	var cards: int = build._chips.size()
	check(cards == 29, "Every part has a card", cards)
	var waited := 0
	while (not build._queue.is_empty() or build._suggest_pending) and waited < 600:
		await get_tree().process_frame
		waited += 1
	check(build._queue.is_empty(), "All part predictions finish", waited)
	var chip: Label = build._chips["nose/cone"]
	check(chip.text.begins_with("+"), "Cone shows a predicted gain", chip.text)
	check(build._chips["tank/t4"].text == "Too heavy", "Huge tank on a tiny engine says so", build._chips["tank/t4"].text)
	build.queue_free()
	await get_tree().process_frame
	# Fly whole flights through the real scene: stable, unstable and a rocket too heavy to lift.
	for case: Array in [["fins", "small", false], ["fins", "nofins", true]]:
		R.new_game()
		R.choose(case[0], case[1])
		var fl: Node = (load("res://scenes/rocket2d_flight.tscn") as PackedScene).instantiate()
		add_child(fl)
		await get_tree().process_frame
		fl.set_physics_process(false)
		fl.auto_steer = true
		fl.launch()
		var n := 0
		while fl.state != "done" and n < 60 * 240:
			fl.advance(1.0 / 60.0)
			n += 1
		check(fl.state == "done", "Flight ends", n)
		check(bool(R.last_flight.broke) == case[2], "Flight outcome for " + str(case[1]), R.last_flight)
		check(R.flights_left == R.FLIGHTS_PER_GAME - 1, "Flight uses one launch")
		check(R.money > R.START_MONEY - 60, "Flight pays money", R.money)
		fl.queue_free()
		await get_tree().process_frame
	R.new_game()
	R.money = 100000
	R.choose("tank", "t4")
	var heavy: Node = (load("res://scenes/rocket2d_flight.tscn") as PackedScene).instantiate()
	add_child(heavy)
	await get_tree().process_frame
	heavy.set_physics_process(false)
	heavy.launch()
	var hn := 0
	while heavy.state != "done" and hn < 60 * 240:
		heavy.advance(1.0 / 60.0)
		hn += 1
	check(heavy.state == "done" and float(R.last_flight.apogee) == 0.0, "Too heavy stays on the pad and ends", R.last_flight)
	heavy.queue_free()
	await get_tree().process_frame
	# Score entry saves, resets the player, and keeps the board.
	R.new_game()
	R.choose("fins", "small")
	R.record_flight(50000.0, false)
	R.pending_submit = true
	var lb: Node = (load("res://scenes/leaderboard.tscn") as PackedScene).instantiate()
	add_child(lb)
	await get_tree().process_frame
	lb._name.text = "  Ada\n "
	lb.submit()
	check(R.todays_board().size() == 1 and R.todays_board()[0].name == "Ada", "Name is saved cleanly", R.todays_board())
	check(R.money == R.START_MONEY and R.best_m == 0.0 and not R.pending_submit, "Saving resets the game for the next player")
	lb._on_clear()
	check(R.todays_board().size() == 1, "First press of clear does not delete")
	lb._on_clear()
	check(R.todays_board().is_empty(), "Second press of clear deletes")
	lb.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(R.board_path))
	R.board_path = keep
	R.new_game()
	Sfx.stop_loops()

func test_leaderboard() -> void:
	var R := Rocket2D
	var keep: String = R.board_path
	R.board_path = "user://test_board.json"
	R.clear_today()
	check(R.todays_board().is_empty(), "Board starts empty")
	R.add_score("Ada", 5000.0, "x")
	R.add_score("Grace", 90000.0, "x")
	R.add_score("Katherine", 400000.0, "x")
	R.add_score("Second Ada", 5000.0, "x")
	var b: Array = R.todays_board()
	check(b.size() == 4 and b[0].name == "Katherine" and b[1].name == "Grace", "Highest first", b)
	check(b[2].name == "Ada" and b[3].name == "Second Ada", "On a tie, the earlier score ranks higher")
	check(R.clean_name("   ") == "Anonymous", "Blank names become Anonymous")
	check(R.clean_name("a\nb\tc") == "abc", "Control characters are removed")
	check(R.clean_name("x".repeat(60)).length() == R.NAME_MAX, "Long names are cut")
	check(R.clean_name("Zo\u00eb \u6771") == "Zo\u00eb \u6771", "International names survive")
	# Scores from another day do not count today, and survive a clear.
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string(R.board_path))
	entries.append({"name": "Yesterday", "height": 9e9, "rocket": "", "date": "2020-01-01", "at": 1.0, "id": "y"})
	R._save_board(entries)
	check(R.todays_board()[0].name == "Katherine", "Other days are not on today's board")
	# Starting a new game must not touch the board.
	R.new_game()
	check(R.todays_board().size() == 4, "A new game keeps the leaderboard")
	R.clear_today()
	check(R.todays_board().is_empty(), "Clearing removes today's scores")
	check(R._load_board().size() == 1, "Clearing keeps other days")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(R.board_path))
	R.board_path = keep

func test_scoring() -> void:
	Game.new_mission()
	Game.mission.target_id = "jupiter"
	Game.auto_design()
	Game.mission.phase = "debrief"
	var before: Dictionary = Game.score()
	Game.mission.samples.append({"poi": "A", "type": "gas"})
	var after: Dictionary = Game.score()
	check(float(after.success) > float(before.success) + 200.0, "Sampling counts as success on a probe mission")
	check(float(after.budget) > float(before.budget), "Probe missions keep their budget points", after)
	Game.new_mission()

func test_input() -> void:
	# Every action needs a keyboard binding. Everything used in play also needs a gamepad binding.
	for action: String in Settings.ACTIONS:
		check(InputMap.has_action(action), "Action exists: " + action)
		var has_key := false
		var has_pad := false
		for e: InputEvent in InputMap.action_get_events(action):
			has_key = has_key or e is InputEventKey
			has_pad = has_pad or e is InputEventJoypadButton or e is InputEventJoypadMotion
		check(has_key, action + " has a key")
		check(has_pad, action + " has a gamepad binding")
	# A simulated gamepad press must reach the game through the same action a key uses.
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	check(InputMap.event_is_action(pad, "thrust"), "Gamepad A triggers the main action")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = -1.0
	check(InputMap.event_is_action(stick, "move_forward"), "Left stick up moves forward")
	# Rebinding works, and is restored so the test leaves no trace.
	var keep: Dictionary = Settings.custom_keys.duplicate()
	Settings.custom_keys["thrust"] = KEY_J
	Settings.rebuild_input()
	var j := InputEventKey.new()
	j.physical_keycode = KEY_J
	check(InputMap.action_has_event("thrust", j), "Rebinding a key takes effect")
	Settings.custom_keys = keep
	Settings.rebuild_input()

func test_design_all_targets() -> void:
	var impossible: Array[String] = []
	for t: Dictionary in Data.targets():
		Game.new_mission()
		Game.mission.target_id = t.id
		var regs: Array = t.get("regions", [])
		Game.mission.region_id = regs[0].id if not regs.is_empty() else ""
		if t.kind != "exoplanet" and t.id != "earth" and t.id != "moon":
			var parent: String = t.id if t.kind == "planet" else str(t.parent)
			Game.mission.launch_unix = Orbital.best_window(parent, 1798761600.0, Orbital.synodic_days(parent) * 1.1)
		Game.auto_design()
		var problems := Game.problems()
		if not problems.is_empty():
			impossible.append("%s: %s" % [t.name, problems[0]])
	check(impossible.is_empty(), "Every target can be designed within budget", impossible)
	Game.new_mission()

func test_terrain() -> void:
	var t := Terrain.new()
	add_child(t)
	t.setup_region(Data.regions["gale"])
	# Aeolis Mons rises high above Curiosity's plain. NASA: about 5 km.
	var poi: Dictionary = {}
	for p: Dictionary in Data.regions["gale"].pois:
		if str(p.name).begins_with("Aeolis"):
			poi = p
	var peak := t.real_elevation(float(poi.u) * t.world_m, float(poi.v) * t.world_m)
	var floor_e := t.real_elevation(float(Data.regions["gale"].landing_uv[0]) * t.world_m, float(Data.regions["gale"].landing_uv[1]) * t.world_m)
	check(peak - floor_e > 3000.0, "Mount Sharp stands well above the Bradbury plain", "%f - %f" % [peak, floor_e])
	near(floor_e, -4500.0, 250.0, "Bradbury Landing elevation against the published value of about -4,500 m")
	near(t.height_at(float(Data.regions["gale"].landing_uv[0]) * t.world_m, float(Data.regions["gale"].landing_uv[1]) * t.world_m), 0.0, 0.5, "Landing site is the world height reference")
	check(t.normal_at(2000.0, 2000.0).y > 0.0, "Terrain normals point up")
	t.queue_free()
	var oly: Dictionary = Data.regions["olympus"]
	near(float(oly.height_max_m), 21200.0, 300.0, "Olympus Mons summit from MOLA")

## Drive the real rover over real terrain and measure how far it cuts into the ground.
func test_rover_contact() -> void:
	for rid: String in ["gale", "valles", "shackleton"]:
		var world := Node3D.new()
		add_child(world)
		var t := Terrain.new()
		world.add_child(t)
		t.setup_region(Data.regions[rid])
		var r := Rover.new()
		world.add_child(r)
		var uv: Array = Data.regions[rid].landing_uv
		r.global_position = t.uv_to_world(float(uv[0]), float(uv[1]))
		r.setup(t, 3.7, Color.WHITE)
		r.place(r.global_position)
		var worst_wheel := 0.0
		var worst_body := 0.0
		var worst_axle_drift := 0.0
		for i in 2400:
			var steer := sin(float(i) * 0.013) * 0.7
			r.tick(1.0 / 60.0, 1.0, steer, i % 400 < 200, false)
			if i < 30:
				continue
			var axles := r.wheel_axles()
			for a in axles.size():
				var w: Node3D = axles[a]
				# In the chassis frame an axle may only move up and down. Any fore-aft motion means orbiting.
				var local: Vector3 = r.body_node().to_local(w.global_position)
				worst_axle_drift = maxf(worst_axle_drift, absf(local.z - (Rover.WHEELS[a] as Vector3).z))
			for w: Node3D in axles:
				var ground := t.height_at(w.global_position.x, w.global_position.z)
				worst_wheel = maxf(worst_wheel, ground - (w.global_position.y - Rover.WHEEL_R))
			for c: Vector3 in Rover.BODY_CORNERS:
				var pt: Vector3 = r.body_node().global_transform * c
				worst_body = maxf(worst_body, t.height_at(pt.x, pt.z) - pt.y)
		print("  %s: wheel penetration %.2f m, body penetration %.2f m, axle drift %.2f m, driven %.0f m" % [rid, worst_wheel, worst_body, worst_axle_drift, r.distance])
		check(r.distance > 500.0, rid + " rover actually drove", r.distance)
		check(worst_wheel < 0.12, rid + " wheels stay on the ground", worst_wheel)
		check(worst_body < 0.02, rid + " body stays above the ground", worst_body)
		check(worst_axle_drift < 0.01, rid + " wheels spin on their own axles", worst_axle_drift)
		world.queue_free()
	for rid: String in Data.regions:
		var t3 := Terrain.new()
		add_child(t3)
		t3.setup_region(Data.regions[rid])
		var uv3: Array = Data.regions[rid].landing_uv
		var spot := t3.flat_spot(float(uv3[0]), float(uv3[1]))
		var slope := t3.footprint_slope(spot.x, spot.z)
		var moved := Vector2(spot.x - float(uv3[0]) * t3.world_m, spot.z - float(uv3[1]) * t3.world_m).length()
		print("  %s: pad slope %.1f deg, moved %.0f m in game (%.1f km real)" % [rid, slope, moved, moved * float(Data.regions[rid].hscale) / 1000.0])
		check(slope <= 11.0, rid + " has a landable pad", slope)
		t3.queue_free()
	# Physics must use the same surface the player sees: the exact triangles of the finest mesh.
	var t2 := Terrain.new()
	add_child(t2)
	t2.setup_region(Data.regions["valles"])
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 4000:
		var x := rng.randf_range(100.0, 3900.0)
		var z := rng.randf_range(100.0, 3900.0)
		worst = maxf(worst, absf(t2.height_at(x, z) - _mesh_height(t2, x, z)))
	print("  physics vs rendered surface, worst gap: %.3f m" % worst)
	check(worst < 0.01, "Physics height matches rendered triangles", worst)
	t2.queue_free()

## Height of the finest LOD mesh, from the same vertices and diagonal the renderer draws.
func _mesh_height(t: Terrain, x: float, z: float) -> float:
	var fx := x / t.texel
	var fz := z / t.texel
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var a := t.vertex_height(ix, iz)
	var b := t.vertex_height(ix + 1, iz)
	var c := t.vertex_height(ix, iz + 1)
	var d := t.vertex_height(ix + 1, iz + 1)
	if tx + tz < 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)

## Fly the landing autopilot, the option players have, onto every site in the game.
func test_autoland() -> void:
	var cases: Array = []
	for rid: String in Data.regions:
		cases.append([Data.regions[rid].body, rid])
	cases.append_array([["triton", ""], ["exo_trappist_1_e", ""], ["exo_55_cnc_e", ""], ["exo_proxima_cen_b", ""], ["exo_k2_18_b", ""]])
	cases.append(["mars", "gale", "airbag"])
	cases.append(["titan", "titan_site", "airbag"])
	for c: Array in cases:
		var body: Dictionary = Data.body(str(c[0]))
		if body.is_empty() or not body.get("has_surface", false):
			continue
		Game.new_mission()
		Game.mission.target_id = c[0]
		Game.mission.region_id = c[1]
		Game.auto_design()
		if c.size() > 2:
			Game.mission.lander = c[2]
		# Worst flying the planner allows, so the margin is tested rather than the best case.
		Game.mission.launch_quality = 0.6
		Game.mission.correction_quality = 0.7
		var inst: Node = (load("res://scenes/landing.tscn") as PackedScene).instantiate()
		add_child(inst)
		await get_tree().process_frame
		inst.auto_pilot = true
		var steps := 0
		while inst.state == "fly" and steps < 60 * 300:
			inst._physics_process(1.0 / 60.0)
			steps += 1
		var stats: Dictionary = Game.mission.get("landing_stats", {})
		var label := "%s/%s" % [c[0], c[1]]
		print("  land %-26s %-8s %5.0fs  fuel %3.0f%%  sink %.1f m/s  slope %.0f deg  lander %s" % [label, inst.state, float(steps) / 60.0, float(stats.get("fuel_left", 0.0)) * 100.0, float(stats.get("sink", 0.0)), float(stats.get("slope", 0.0)), Game.lander().id])
		check(inst.state == "landed", "Autopilot lands at " + label, stats)
		check(steps < 60 * 110, "Descent takes under two minutes at " + label, float(steps) / 60.0)
		if Game.lander().id != "airbag":
			check(float(stats.get("fuel_left", 0.0)) > 0.08, "Fuel to spare at " + label, stats.get("fuel_left", 0.0))
		inst.queue_free()
		await get_tree().process_frame
		Sfx.stop_loops()
	Game.new_mission()

func test_scenes() -> void:
	# Every scene must load and run a frame without script errors, for each kind of target.
	for id: String in ["mars", "moon", "jupiter", "exo_trappist_1_e", "titan", "triton"]:
		if Data.body(id).is_empty():
			check(false, "Target exists: " + id)
			continue
		Game.new_mission()
		Game.mission.target_id = id
		var regs: Array = Data.body(id).get("regions", [])
		Game.mission.region_id = regs[0].id if not regs.is_empty() else ""
		Game.auto_design()
		var scenes: Array[String] = ["launch", "transfer", "orbit", "surface", "debrief"]
		if Data.body(id).get("has_surface", false):
			scenes.insert(3, "landing")
		for s: String in scenes:
			var packed: PackedScene = load("res://scenes/%s.tscn" % s)
			check(packed != null, "scene loads: " + s)
			if packed == null:
				continue
			var inst := packed.instantiate()
			add_child(inst)
			await get_tree().process_frame
			await get_tree().process_frame
			inst.queue_free()
			await get_tree().process_frame
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for s: String in ["main_menu", "planner", "archive", "settings", "credits", "demo_picker", "rocket2d", "rocket2d_flight", "leaderboard", "results"]:
		var packed: PackedScene = load("res://scenes/%s.tscn" % s)
		var inst := packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		inst.queue_free()
		await get_tree().process_frame
		check(true, "ui scene: " + s)

## Regression checks for the second round of player reports.
func test_player_reports() -> void:
	# The coarse ring beyond the map must never overlap the map, on any map size.
	for setup: Array in [["gale", null], ["", "exo_trappist_1_e"], ["shackleton", null]]:
		var t := Terrain.new()
		add_child(t)
		if setup[1] == null:
			t.setup_region(Data.regions[setup[0]])
		else:
			t.setup_procedural(Data.body(setup[1]), Data.art(setup[1]))
		var overlaps := 0
		for mi: MeshInstance3D in t._ring:
			var span: float = float(Terrain.CHUNK_TEXELS) * mi.scale.x
			if mi.position.x < t.world_m - 0.01 and mi.position.x + span > 0.01 and mi.position.z < t.world_m - 0.01 and mi.position.z + span > 0.01:
				overlaps += 1
		check(overlaps == 0, "No second layer of ground over the map, n=%d" % t.n, overlaps)
		check(t._ring.size() > 0, "Map still has an outer ring, n=%d" % t.n)
		t.queue_free()
	await get_tree().process_frame

	# The ship meets the planet on arrival, for any launch date and any engine.
	var worst_start := 0.0
	var worst_end := 0.0
	var dates: Array[float] = [1798761600.0, 1798761600.0 + 86400.0 * 137.0, 1798761600.0 + 86400.0 * 501.0]
	for id: String in ["mercury", "venus", "mars", "jupiter", "saturn", "uranus", "neptune", "titan", "europa"]:
		for stage: String in ["hydrolox", "ion"]:
			for u: float in dates:
				Game.new_mission()
				Game.mission.target_id = id
				Game.mission.lander = "probe" if not Data.body(id).get("has_surface", false) else "retro"
				Game.mission.stage = stage
				Game.mission.launch_unix = u
				var inst: Node = (load("res://scenes/transfer.tscn") as PackedScene).instantiate()
				add_child(inst)
				inst.set_process(false)
				var parent: String = id if Data.body(id).kind == "planet" else str(Data.body(id).parent)
				var arrive := u + float(inst._days) * 86400.0
				var body: Dictionary = {}
				var earth: Dictionary = {}
				for b: Dictionary in inst.bodies:
					if b.data.id == parent:
						body = b
					if b.data.id == "earth":
						earth = b
				var end_a: float = (body.angle as Callable).call(arrive)
				var end_r: float = inst.dist_units(float(body.r))
				worst_end = maxf(worst_end, inst._path_point(1.0).distance_to(Vector3(cos(end_a) * end_r, 0.0, -sin(end_a) * end_r)))
				var start_a: float = (earth.angle as Callable).call(u)
				var start_r: float = inst.dist_units(float(earth.r))
				worst_start = maxf(worst_start, inst._path_point(0.0).distance_to(Vector3(cos(start_a) * start_r, 0.0, -sin(start_a) * start_r)))
				inst.free()
	check(worst_end < 0.05, "Path ends at the planet's real arrival position", worst_end)
	check(worst_start < 0.05, "Path starts at Earth", worst_start)
	print("  transfer alignment worst: start %.4f, end %.4f units" % [worst_start, worst_end])
	Game.new_mission()

	# Autopilot handover: it must land whenever the engine could physically still stop the fall.
	var hand_fails := 0
	var hand_runs := 0
	for rid: String in ["tranquility", "tycho", "shackleton"]:
		for delay: float in [0.0, 3.0, 6.0, 10.0, 12.0, 15.0, 17.0]:
			Game.new_mission()
			Game.mission.target_id = "moon"
			Game.mission.region_id = rid
			Game.auto_design()
			var land: Node = (load("res://scenes/landing.tscn") as PackedScene).instantiate()
			add_child(land)
			await get_tree().process_frame
			land.auto_pilot = false
			var steps := 0
			while land.state == "fly" and steps < 60 * 300:
				land.auto_pilot = float(steps) / 60.0 >= delay
				land._physics_process(1.0 / 60.0)
				steps += 1
			hand_runs += 1
			if land.state != "landed":
				hand_fails += 1
				print("  autopilot handover failed: %s after %.0fs: %s" % [rid, delay, Game.mission.get("landing_stats", {})])
			land.queue_free()
			await get_tree().process_frame
			Sfx.stop_loops()
	check(hand_fails == 0, "Autopilot recovers a late handover on the Moon", "%d of %d failed" % [hand_fails, hand_runs])
	Game.new_mission()

	# Launch: no input at full throttle breaks up, managed flight reaches orbit, spins are scored.
	var pad_rocket := func() -> Node:
		Game.new_mission()
		Game.auto_design()
		var l: Node = (load("res://scenes/launch.tscn") as PackedScene).instantiate()
		add_child(l)
		return l
	var hands_off: Node = pad_rocket.call()
	await get_tree().process_frame
	hands_off.ignite()
	var n := 0
	while hands_off.state == "ascent" and n < 60 * 60:
		hands_off._ascent(1.0 / 60.0)
		n += 1
	check(hands_off.state == "broken", "Full throttle with no input breaks the rocket up", hands_off.state)
	check(int(Game.mission.rockets_lost) == 1, "A lost rocket is counted")
	check(float(Game.score().success) == 0.0, "A rocket lost before orbit earns no launch credit", Game.score().success)
	hands_off.queue_free()
	await get_tree().process_frame
	var managed: Node = pad_rocket.call()
	await get_tree().process_frame
	managed.auto_fly = true
	managed.ignite()
	n = 0
	var peak := 0.0
	while managed.state == "ascent" and n < 60 * 90:
		managed._ascent(1.0 / 60.0)
		peak = maxf(peak, float(managed.stress))
		n += 1
	check(managed.state == "coast", "Managed throttle reaches orbit", managed.state)
	print("  managed ascent: %.0fs, peak stress %.2f, red time %.2fs" % [float(n) / 60.0, peak, float(managed.red_time)])
	check(bool(Game.mission.reached_orbit), "Reaching orbit is recorded")
	managed.queue_free()
	await get_tree().process_frame
	var flips: Node = pad_rocket.call()
	await get_tree().process_frame
	flips.ignite()
	flips.altitude = 40.0
	flips.speed = 2.0
	Input.action_press("move_forward")
	Input.action_press("trick")
	for i in 60 * 2:
		flips._spin_controls(1.0 / 60.0)
		flips._ascent(1.0 / 60.0)
	check(float(flips.stress) >= 0.0 and flips.trick.in_combo() and flips.trick.half_turns == 2, "Two seconds of flipping counts half-turns", flips.trick.half_turns)
	Input.action_release("move_forward")
	Input.action_press("move_right")
	for i in 60:
		flips._spin_controls(1.0 / 60.0)
	Input.action_release("move_right")
	Input.action_release("trick")
	var expected: int = flips.trick.payout()
	check(flips.trick.mult >= 3, "Changing axis raises the multiplier", flips.trick.mult)
	for i in 60 * 5:
		flips._spin_controls(1.0 / 60.0)
	check(int(Game.mission.trick_points) == expected and expected > 0, "An idle moment with the nose straight banks the combo", Game.mission.trick_points)
	flips.queue_free()
	await get_tree().process_frame

	# 2D: with the main stage gone, the upper engine's flame starts at the bottom of the upper stage.
	var r2d_flight: Node = (load("res://scenes/rocket2d_flight.tscn") as PackedScene).instantiate()
	add_child(r2d_flight)
	await get_tree().process_frame
	r2d_flight.sim.main_attached = false
	check(r2d_flight.upper_flame_base(Vector2(100, 200), 4.0, 0.3) == Vector2(100, 200), "Upper stage flame sits under the upper stage")
	r2d_flight.queue_free()
	await get_tree().process_frame

	# Wiggling earns nothing.
	var tr := TrickScore.new()
	for i in 200:
		tr.spin(0.5 if i % 2 == 0 else -0.5, 0.0)
	check(not tr.in_combo(), "Wiggling back and forth scores nothing", tr.half_turns)

	# Rover: rock damage, immunity at low speed, wreck, bail, repair, and the heading stays free of damage.
	Game.new_mission()
	var tw := Terrain.new()
	add_child(tw)
	tw.setup_region(Data.regions["gale"])
	var make_rover := func() -> Rover:
		var ro := Rover.new()
		add_child(ro)
		ro.global_position = tw.uv_to_world(0.5, 0.5)
		ro.setup(tw, 3.7, Color.GRAY)
		ro.place(ro.global_position)
		ro.heading = 0.0
		return ro
	# Player report: reverse went extremely fast. Holding S for 20 s, with boost held too, stays slow.
	var rv: Rover = make_rover.call()
	var top_rev := 0.0
	for i in 60 * 20:
		rv.tick(1.0 / 60.0, -1.0, 0.0, true, false)
		top_rev = maxf(top_rev, Vector2(rv.velocity.x, rv.velocity.z).length())
	check(top_rev <= Rover.REVERSE_SPEED + 1.5, "Reverse stays at a crawl, even with boost held", top_rev)
	var rf: Rover = make_rover.call()
	rf.velocity = Vector3(0, 0, 20.0) * rf.forward_dir().z
	var braked := 0.0
	for i in 60:
		rf.tick(1.0 / 60.0, -1.0, 0.0, false, false)
	braked = Vector2(rf.velocity.x, rf.velocity.z).length()
	check(braked < 20.0, "Pressing S while rolling forward brakes", braked)
	rv.queue_free()
	rf.queue_free()
	var r1: Rover = make_rover.call()
	var ahead := r1.global_position + Vector3(0, 0, 12)
	r1.rocks = [Vector4(ahead.x, tw.height_at(ahead.x, ahead.z), ahead.z, 1.5)]
	r1.velocity = Vector3(0, 0, 24.0)
	var hit := 0.0
	for i in 60:
		r1.tick(1.0 / 60.0, 1.0, 0.0, false, false)
		hit += r1.last_hit
	check(hit > 5.0 and r1.health < 100.0, "Hitting a rock at speed hurts", r1.health)
	check(r1.velocity.z < 10.0, "A rock stops the rover", r1.velocity.z)
	check(r1.global_position.distance_to(ahead) > 1.0, "The rover does not pass through the rock", r1.global_position.distance_to(ahead))
	r1.queue_free()
	var r2: Rover = make_rover.call()
	var slow_at := r2.global_position + Vector3(0, 0, 4)
	r2.rocks = [Vector4(slow_at.x, tw.height_at(slow_at.x, slow_at.z), slow_at.z, 1.5)]
	for i in 120:
		r2.velocity = Vector3(0, r2.velocity.y, 3.0)
		r2.tick(1.0 / 60.0, 0.0, 0.0, false, false)
	check(is_equal_approx(r2.health, 100.0), "A gentle bump does no damage", r2.health)
	r2.repair(5.0)
	r2.queue_free()
	var r3: Rover = make_rover.call()
	r3._take_damage(200.0)
	check(r3.health == 0.0, "Health stops at zero", r3.health)
	r3.velocity = Vector3.ZERO
	var p0 := r3.global_position
	for i in 60:
		r3.tick(1.0 / 60.0, 1.0, 0.0, true, false)
	check(r3.global_position.distance_to(p0) < 1.0, "A wrecked rover cannot drive", r3.global_position.distance_to(p0))
	r3.repair(30.0)
	check(is_equal_approx(r3.health, 30.0), "Repair restores health", r3.health)
	r3.queue_free()
	# A clean flip pays out; landing inverted is a bail that costs health.
	var r4: Rover = make_rover.call()
	r4.global_position.y += 40.0
	r4.grounded = false
	for i in 60 * 3:
		var going: bool = r4._flip > -TAU + 0.05
		r4.trick_held = going
		r4.tick(1.0 / 60.0, 1.0 if going else 0.0, 0.0, false, false)
		if r4.grounded:
			break
	var before_paid := int(Game.mission.trick_points)
	check(r4.trick.half_turns == 2 or before_paid > 0, "A full flip in the air counts", r4.trick.half_turns)
	while not r4.grounded:
		r4.tick(1.0 / 60.0, 0.0, 0.0, false, false)
	r4.tick(1.0 / 60.0, 0.0, 0.0, false, false)
	check(int(Game.mission.trick_points) >= 200, "Landing a full flip pays out", Game.mission.trick_points)
	check(is_equal_approx(r4.health, 100.0), "A clean landing costs no health", r4.health)
	r4.queue_free()
	var r5: Rover = make_rover.call()
	r5.global_position.y += 30.0
	r5.grounded = false
	r5._flip = PI
	r5.trick.spin(PI + 0.01, 0.0)
	while not r5.grounded:
		r5.tick(1.0 / 60.0, 0.0, 0.0, false, false)
		r5._flip = PI
	r5.tick(1.0 / 60.0, 0.0, 0.0, false, false)
	check(r5.health < 100.0 and not r5.trick.in_combo(), "Landing upside down is a bail", r5.health)
	r5.queue_free()
	tw.queue_free()
	await get_tree().process_frame

	# Probe: a sudden full-stick turn eases in, and the body never snaps.
	var pr := ProbeCraft.new()
	var cloud := World.CloudWorld.new()
	cloud.setup(Data.art("jupiter"))
	add_child(cloud)
	add_child(pr)
	pr.setup(cloud, 24.0, Color.WHITE)
	pr.place(Vector3(2000, 70, 2000))
	for i in 120:
		pr.tick(1.0 / 60.0, 1.0, 0.0, false, false)
	var worst_bank := 0.0
	var worst_rate_step := 0.0
	var prev_bank: float = pr.rotation.z
	var prev_heading: float = pr.heading
	var prev_rate := 0.0
	for i in 240:
		var st := 1.0 if i < 120 else -1.0
		pr.tick(1.0 / 60.0, 1.0, st, false, false)
		worst_bank = maxf(worst_bank, absf(pr.rotation.z - prev_bank))
		var rate: float = pr.heading - prev_heading
		worst_rate_step = maxf(worst_rate_step, absf(rate - prev_rate))
		prev_bank = pr.rotation.z
		prev_heading = pr.heading
		prev_rate = rate
	check(worst_bank < 0.03, "Probe banking changes gradually", worst_bank)
	check(worst_rate_step < 0.002, "Probe turn rate builds gradually", worst_rate_step)
	print("  probe: worst bank step %.4f rad, worst turn-rate step %.5f rad/frame" % [worst_bank, worst_rate_step])
	pr.queue_free()
	cloud.queue_free()
	await get_tree().process_frame
	Game.new_mission()

func test_learning() -> void:
	# Every quote the lessons rely on survived the source check.
	for id: String in ["max_q", "window", "landing", "wheels"]:
		check(Data.lessons.has(id) and str(Data.lessons[id].get("url", "")).contains("nasa.gov"), "lesson quote verified: " + id)
	Game.new_mission()
	Game.mission.target_id = "mars"
	Game.mission.region_id = "gale"
	check(Game.landing_lesson().is_empty(), "no landing lesson before a landing attempt")
	check(Game.rover_lesson().is_empty(), "no rover lesson before the rover is hurt")
	# A launch break-up reports where it happened.
	Game.mission.rockets_lost = 1
	Game.mission.breakup_km = 12.0
	Game.mission.breakup_air = exp(-12.0 / 8.5)
	var launch := Game.launch_lesson()
	check(launch.text.contains("12 km") and launch.text.contains("24%"), "break-up lesson uses this flight's numbers", launch.text)
	check(launch.fact.text.contains("Max Q"), "break-up lesson quotes NASA")
	# Off-window launches show their cost. The best window doesn't.
	var u := Orbital.best_window("mars", 1798761600.0, Orbital.synodic_days("mars") * 1.1)
	Game.mission.launch_unix = u
	check(not Game.window_lesson().text.contains("more delta-v"), "best window has no penalty line", Game.window_lesson().text)
	Game.mission.launch_unix = u + Orbital.synodic_days("mars") * 0.5 * 86400.0
	check(Game.window_lesson().text.contains("more delta-v"), "off-window launch reports its cost", Game.window_lesson().text)
	# Each crash cause gets its own explanation.
	Game.mission.crashes = 1
	Game.mission.landing_stats = {"sink": 30.0, "drift": 0.0, "slope": 2.0, "limit": 5.0, "brake_m": 50.0}
	check(Game.landing_lesson().text.contains("50 m"), "hard impact gives the braking height", Game.landing_lesson().text)
	Game.mission.landing_stats = {"sink": 2.0, "drift": 20.0, "slope": 2.0, "limit": 5.0}
	check(Game.landing_lesson().text.contains("Sideways"), "drift crash explains drift")
	Game.mission.landing_stats = {"sink": 2.0, "drift": 0.0, "slope": 40.0, "limit": 5.0}
	check(Game.landing_lesson().text.contains("Steep"), "slope crash explains slope")
	check(Game.gravity_lesson().text.contains("38%"), "Mars gravity compared with Earth", Game.gravity_lesson().text)
	Game.mission.rover_health = 40.0
	check(Game.rover_lesson().fact.text.contains("sharp rocks"), "damaged rover lesson quotes NASA")
	check(Game.lessons().size() == 5, "all five lessons appear", Game.lessons().size())
	# Lessons are safe on every target, including ones with no window or surface.
	for id: String in Data.bodies.keys() + ["exo_trappist_1_e"]:
		Game.new_mission()
		Game.mission.target_id = id
		Game.mission.launch_unix = 1798761600.0
		Game.mission.crashes = 1
		Game.mission.landing_stats = {}
		check(Game.lessons() is Array, "lessons build for " + id)
	# Quiz totals: a damaged file starts again, and each pair counts once.
	var path := "user://quiz_test.json"
	DirAccess.remove_absolute(path)
	check(int(QuizScene.load_results(path).runs) == 0, "quiz totals start empty")
	QuizScene.record(1, 3, path)
	var r := QuizScene.record(0, 2, path)
	check(int(r.runs) == 2 and int(r.before_total) == 1 and int(r.after_total) == 5, "quiz totals add up", r)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	check(int(QuizScene.load_results(path).runs) == 0, "damaged quiz file is ignored")
	DirAccess.remove_absolute(path)
	# The after-round runs start to finish, with results written only to a test path.
	Game.new_mission()
	Game.quiz_stage = "after"
	Game.quiz_before = 1
	var quiz: QuizScene = load("res://scenes/quiz.tscn").instantiate()
	quiz.results_path = path
	add_child(quiz)
	await get_tree().process_frame
	quiz.auto_advance()
	check(quiz.score == 3, "right answers all score", quiz.score)
	check(Game.quiz_before == -1, "a finished pair cannot be counted twice")
	check(int(QuizScene.load_results(path).runs) == 1, "after-round records one result")
	quiz.queue_free()
	DirAccess.remove_absolute(path)
	Game.new_mission()

func test_version_stamp() -> void:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	check(v.is_valid_float(), "project.godot has a version number", v)
	var stamp: Label = Flow.get_node("VersionStamp")
	check(stamp.text == "v" + v, "stamp shows the project version", stamp.text)
	check(stamp.mouse_filter == Control.MOUSE_FILTER_IGNORE, "stamp can't block clicks")
	# An empty number here makes the macOS export use the one in project.godot.
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.contains('application/short_version=""') and presets.contains('application/version=""'), "exports don't carry their own version number")

## How-to-play popups: every playable screen has one, opening pauses the game, closing restores it,
## and each card is only shown automatically once.
func test_tips() -> void:
	var saved_seen: Dictionary = Tips.seen.duplicate()
	var saved_on: bool = Tips.enabled
	for scene_name: String in ["MainMenu", "Planner", "DemoPicker", "Quiz", "Launch", "Transfer", "Orbit", "Landing", "Hatch", "Surface", "Debrief", "Rocket2DBuild", "Rocket2DFlight"]:
		var tip := Tips.tip_for(scene_name)
		check(not tip.is_empty() and str(tip.get("title", "")) != "" and (tip.get("steps", []) as Array).size() >= 2, "tip exists for " + scene_name)
	for path: String in Flow.SCENES.values():
		var root_name := FileAccess.get_file_as_string(path).get_slice('[node name="', 1).get_slice('"', 0)
		if root_name in ["Launch", "Landing", "Surface", "Hatch", "Orbit", "Transfer", "Planner"]:
			check(Tips.has_tip(root_name), "mission screen %s has a tip" % root_name)
	check(not Tips.has_tip("Credits"), "screens without controls have no tip")
	get_tree().paused = false
	check(Tips.show_tip("Launch"), "tip opens")
	check(Tips.is_open() and get_tree().paused, "open tip pauses the game")
	check(Tips.seen.has("Launch"), "opened tip is remembered")
	Tips.close()
	check(not Tips.is_open() and not get_tree().paused, "closing the tip unpauses")
	Tips.enabled = true
	Tips.seen = {"Launch": true}
	Tips.maybe_show("Launch")
	check(not Tips.is_open(), "seen tip is not shown again")
	Tips.seen = saved_seen
	Tips.set_enabled(saved_on)

## The power-core mini-game: every channel can be driven down its middle without a touch,
## channels never overlap, walls cost stability, and enough touches blow the core.
func test_hatch() -> void:
	var lanes: Array = HatchScene.LANES
	for i in lanes.size():
		var hw: float = lanes[i].hw
		check(hw - HatchScene.ROD_R >= 8.0, "hatch lane %d leaves room around the rod" % i)
		for j in lanes.size():
			if j == i:
				continue
			for p: Vector2 in lanes[i].pts:
				var c := HatchScene.closest_on(j, p)
				check(float(c.dist) > hw + float(lanes[j].hw) + 6.0, "hatch lane %d stays clear of lane %d" % [i, j])
	Game.new_mission()
	Game.mission.target_id = "mars"
	Game.mission.region_id = "gale"
	var packed: PackedScene = load("res://scenes/hatch.tscn")
	var h: HatchScene = packed.instantiate()
	add_child(h)
	await get_tree().process_frame
	h.auto_advance()
	for k in 900:
		h._process(1.0 / 60.0)
		if h.state != "play" and h.state != "to_bay":
			break
	check(h.seated_count() == 3, "hatch: autopilot seats all three rods", h.seated_count())
	check(h.touches == 0, "hatch: the middle of each channel never touches a wall", h.touches)
	check(int(Game.mission.get("core", {}).get("bonus", 0)) == 60, "hatch: clean run earns +60 science")
	h.queue_free()
	await get_tree().process_frame
	var h2: HatchScene = packed.instantiate()
	add_child(h2)
	await get_tree().process_frame
	h2.size = Vector2(1600, 900)
	h2.state = "play"
	h2.held = 0
	for k in 4:
		h2._cooldown = 0.0
		h2._move_rod(0, Vector2(300, 400))
	check(h2.state == "boom" and h2.stability <= 0.0, "hatch: four wall hits blow the core", [h2.state, h2.stability])
	h2._retry()
	check(h2.state == "play" and h2.stability == 100.0 and h2.seated_count() == 0, "hatch: retry gives a fresh set of rods")
	h2.queue_free()
	await get_tree().process_frame

## The parachute: its lines reach the lander, and opening it far too fast tears it.
func test_parachute() -> void:
	var lander := Models.lander(true)
	add_child(lander)
	for n: String in ["Chute", "Drogue"]:
		var node: Node3D = lander.get_node(n)
		var lowest := INF
		for c: Node in node.get_children():
			var mi := c as MeshInstance3D
			var h := (mi.mesh as CylinderMesh).height
			lowest = minf(lowest, mi.position.y - h * 0.5 * absf(mi.basis.y.y))
		check(node.get_child_count() > 6, "%s has suspension lines" % n, node.get_child_count())
		check(absf(lowest - 4.6) < 0.3, "%s lines end on the lander's top" % n, lowest)
	lander.queue_free()
	for case: Array in [["early", 3.0], ["patient", 0.0]]:
		Game.new_mission()
		Game.mission.target_id = "mars"
		Game.mission.region_id = "gale"
		Game.auto_design()
		Game.mission.lander = "airbag"
		var inst: Node = (load("res://scenes/landing.tscn") as PackedScene).instantiate()
		add_child(inst)
		await get_tree().process_frame
		check(inst.drogue.visible and not inst.chute.visible, "drogue flies first, main canopy packed")
		inst.auto_pilot = true
		if case[1] > 0.0:
			inst.vel.y = -inst.chute_safe_speed * 2.0
			inst.open_chute()
		var steps := 0
		while inst.state == "fly" and steps < 60 * 300:
			inst._physics_process(1.0 / 60.0)
			steps += 1
		if case[0] == "early":
			check(inst.chute_torn, "opening at twice the rated speed tears the parachute", inst.chute_damage)
			check(inst.state == "crashed", "a torn parachute on Mars means a hard landing", inst.state)
			check(Game.landing_lesson().text.contains("square of speed"), "the lesson explains the tear")
		else:
			check(not inst.chute_torn and inst.state == "landed", "autopilot waits for a safe speed and lands", [inst.chute_torn, inst.state])
		inst.queue_free()
		await get_tree().process_frame
		Sfx.stop_loops()
	Game.new_mission()

## Salvage: perfect play installs every part; out-of-order bolts are refused; over-torque strips.
func test_salvage() -> void:
	var g := SalvageGame.new()
	add_child(g)
	await get_tree().process_frame
	g.auto_complete()
	var s := g.summary()
	check(g.phase == "done" and int(s.parts) == 3, "salvage: all three parts done", s)
	check(int(s.in_spec) == int(s.bolts) and int(s.stripped) == 0, "salvage: perfect torque on every bolt", s)
	check((s.working as Array).size() == 3, "salvage: every part works", s.working)
	g.queue_free()
	var h := SalvageGame.new()
	add_child(h)
	await get_tree().process_frame
	for i in h.bolts.size():
		h.active = i
		h.turn(i, 0.5)
	check(not h.bolts[0].out, "salvage: turning clockwise does not unscrew")
	for i in h.bolts.size():
		h.active = i
		h.turn(i, -3.0)
	check(h.phase == "move", "salvage: all bolts out frees the part", h.phase)
	h._finish_move()
	var first: int = h.part().order[0]
	var wrong: int = h.part().order[1]
	check(not h._can_use(wrong), "salvage: bolts must follow the spec sheet order")
	check(h._can_use(first), "salvage: the first bolt in the order can be turned")
	h.active = first
	h.turn(first, 1.0 + 0.5 / SalvageGame.TORQUE_PER_TURN)
	h._settle(first)
	check(h.bolts[first].state == "under", "salvage: half the spec torque is under spec", h.bolts[first].torque)
	h.turn(first, 1.0)
	check(h.bolts[first].state == "stripped", "salvage: far past spec strips the bolt", h.bolts[first].torque)
	h.queue_free()
	await get_tree().process_frame

## The results screen's per-question tallies add up across players.
func test_learning_results() -> void:
	var path := "user://test_quiz_results.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	QuizScene.record(1, 3, path, [true, false, false], [true, true, true])
	var r := QuizScene.record(2, 2, path, [false, true, true], [true, false, true])
	check(int(r.runs) == 2 and int(r.before_total) == 3 and int(r.after_total) == 5, "results: totals add up", r)
	check(r.q_before == [1, 1, 1] and r.q_after == [2, 1, 2] and int(r.q_runs) == 2, "results: per-question tallies", r)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Regression (v1.4 report "can't land on Mars"): the descent button must be on screen for every world.
func test_orbit_button() -> void:
	var vs := get_viewport().get_visible_rect()
	for id: String in ["mars", "moon", "titan", "venus", "earth", "europa"]:
		Game.new_mission()
		Game.mission.target_id = id
		Game.auto_design()
		var o: Node = (load("res://scenes/orbit.tscn") as PackedScene).instantiate()
		add_child(o)
		for i in 3:
			await get_tree().process_frame
		var b: Button = o._go
		check(vs.encloses(b.get_global_rect()), "orbit: Begin descent is on screen for " + id, [b.get_global_rect(), vs.size])
		o.queue_free()
		await get_tree().process_frame
	Game.new_mission()

## v1.9: the 3D launch site and the T-minus countdown.
func test_countdown() -> void:
	var bh: Dictionary = Data.bahrain
	check(bh.has("site") and FileAccess.file_exists("res://data/regions/bahrain_spaceport/site_height.f32"), "3D site heights are bundled")
	Game.new_mission()
	Game.auto_design()
	var l: Node = (load("res://scenes/launch.tscn") as PackedScene).instantiate()
	add_child(l)
	await get_tree().process_frame
	var site: LaunchSite = l.site
	check(site.complex != null and site.complex.get_child_count() > 5, "launch complex is built")
	check(absf(site.height_at(0.1, 0.1) - site.height_at(0.0, 0.0)) < 1e-6, "ground under the complex is level")
	check(absf(float(l._rocket_y) - (l.EARTH_R + 0.05 + site.rocket_base_y())) < 1e-5 and site.rocket_base_y() > site.height_at(0.0, 0.0), "rocket stands on the mount, above the ground")
	check(l.state == "countdown" and not l.counting, "launch opens at a hold")
	l.start_count()
	check(is_equal_approx(float(l.t_minus), 30.0), "count starts at T-30")
	var n := 0
	var flame_before_zero := false
	while l.state == "countdown" and n < 60 * 40:
		l.advance_count(1.0 / 60.0)
		if float(l.t_minus) > 0.1 and l.flame.emitting:
			flame_before_zero = true
		n += 1
	check(absf(float(n) / 60.0 - 30.0) < 0.05, "liftoff exactly at T-0", float(n) / 60.0)
	check(l.state == "ascent", "the rocket lifts off when the clock reaches zero", l.state)
	check(flame_before_zero, "engines light before T-0")
	check(l.events_done.size() == l.EVENTS.size(), "every countdown step happened", l.events_done.keys())
	check(site.crew_arm_angle() >= 0.0 and site._crew_target > 0.0, "crew access arm was told to retract")
	l.queue_free()
	await get_tree().process_frame
	var quick: Node = (load("res://scenes/launch.tscn") as PackedScene).instantiate()
	add_child(quick)
	await get_tree().process_frame
	quick.start_count(10.0)
	check(quick.events_done.has(20.0) and not quick.events_done.has(10.0), "starting at T-10 completes the earlier steps at once")
	quick.queue_free()
	await get_tree().process_frame
	Sfx.stop_loops()
	Game.new_mission()

## Bahrain launch site and Al Munther, plus the player report "fuel drops with no engine on".
func test_bahrain() -> void:
	var bh: Dictionary = Data.bahrain
	check(not bh.is_empty() and bool(bh.get("concept", false)), "Bahrain site loads and is labelled concept")
	check(float(bh.pad.elev_m) > 0.5, "the concept pad is on land in the SRTM heights", bh.pad)
	check(FileAccess.file_exists("res://data/regions/bahrain_spaceport/color.jpgdata"), "Landsat scene of Bahrain is bundled")
	var ids: Array = Data.milestones.map(func(m: Dictionary) -> String: return str(m.id))
	check(ids.find("al_munther") == ids.find("iss") + 1, "Al Munther's 550 km sits between the ISS and the thermosphere", ids)
	Game.new_mission()
	Game.mission.target_id = "mars"
	Game.mission.region_id = "gale"
	Game.auto_design()
	var l: Node = (load("res://scenes/landing.tscn") as PackedScene).instantiate()
	add_child(l)
	await get_tree().process_frame
	l.auto_pilot = false
	for i in 120:
		l._physics_process(1.0 / 60.0)
	check(l.fuel == 1.0 and not l.rcs_firing, "no keys: no fuel used", l.fuel)
	Input.action_press("move_right")
	for i in 30:
		l._physics_process(1.0 / 60.0)
	check(l.fuel < 1.0 and l.rcs_firing and l._rcs.px.emitting, "steering fires a visible side thruster and uses fuel", [l.fuel, l.rcs_firing])
	Input.action_release("move_right")
	l.queue_free()
	await get_tree().process_frame
	Sfx.stop_loops()
	Game.new_mission()
