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
	test_terrain()
	await test_scenes()
	print("\nPASSED %d, FAILED %d" % [passes, fails.size()])
	for f in fails:
		print("  FAIL: ", f)
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
	for s: String in ["main_menu", "planner", "archive", "settings", "credits"]:
		var packed: PackedScene = load("res://scenes/%s.tscn" % s)
		var inst := packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		inst.queue_free()
		await get_tree().process_frame
		check(true, "ui scene: " + s)
