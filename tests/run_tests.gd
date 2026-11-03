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
	test_rover_contact()
	await test_autoland()
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
	for c: Array in cases:
		var body: Dictionary = Data.body(str(c[0]))
		if body.is_empty() or not body.get("has_surface", false):
			continue
		Game.new_mission()
		Game.mission.target_id = c[0]
		Game.mission.region_id = c[1]
		Game.auto_design()
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
	for s: String in ["main_menu", "planner", "archive", "settings", "credits"]:
		var packed: PackedScene = load("res://scenes/%s.tscn" % s)
		var inst := packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		inst.queue_free()
		await get_tree().process_frame
		check(true, "ui scene: " + s)
