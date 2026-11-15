extends Node3D
## Cruise: real planet positions from JPL elements, true/viewable scale toggle, course corrections.

const CRUISE_SECONDS := 40.0
const DEMO_CRUISE_SECONDS := 9.0

var plan: Dictionary
var target: Dictionary
var mode := "solar"
var scale_true := false
var cam: OrbitCamera
var craft: Node3D
var sun_node: Node3D
var bodies: Array = []
var orbit_lines: Node3D
var path_line: Node3D
var progress := 0.0
var time_scale := 1.0
var _r1 := 0.0
var _r2 := 0.0
var _a := 0.0
var _e := 0.0
var _start_angle := 0.0
## Extra sweep so the path meets the target on arrival day. Zero for an ideal window; an off-window launch or
## a slower engine needs a non-Hohmann path, which is what the off-window delta-v penalty pays for.
var _arrival_fix := 0.0
var _outward := true
var _mu := Orbital.MU_SUN
var _days := 0.0
var _start_unix := 0.0
var _parent_id := ""
var _card: HudCard
var _scale_btn: Button
var _info: VBoxContainer
var _fix_active := false
var _fixes_done := 0
var debris: DebrisRun
var _asked: Array = []
var _focus_index := -1
var _star: Node3D
var _arrival := false
var _craft_tag: Label3D

func _ready() -> void:
	target = Game.target()
	plan = Game.dv_plan()
	Game.mission.phase = "transfer"
	Sfx.music("music_space")
	_days = float(plan.days)
	_start_unix = float(Game.mission.launch_unix)
	Space.make_space_env(self, 0.03)
	cam = OrbitCamera.new()
	cam.far = 200000.0
	cam.near = 0.02
	cam.fov = 55.0
	add_child(cam)
	orbit_lines = Node3D.new()
	add_child(orbit_lines)
	match str(plan.kind):
		"interstellar":
			mode = "interstellar"
		"lunar":
			mode = "lunar"
		_:
			mode = "solar"
	if mode == "interstellar":
		_setup_interstellar()
	elif mode == "lunar":
		_setup_lunar()
	else:
		_setup_solar()
	_build_hud()
	if mode != "interstellar":
		_rebuild_scale()

# ---- Scale ----

func dist_units(r_m: float) -> float:
	if mode == "lunar":
		return r_m / 384400000.0 * (60.0 if scale_true else 26.0)
	var au := r_m / Orbital.AU
	return au * 60.0 if scale_true else 15.0 * pow(au, 0.55)

func size_units(radius_km: float) -> float:
	if scale_true:
		# True scale: same units as distance. Planets become tiny, which is the lesson.
		if mode == "lunar":
			return radius_km / 384400.0 * 60.0
		return radius_km * 1000.0 / Orbital.AU * 60.0
	if mode == "lunar":
		return 0.5 + 0.2 * log(radius_km / 1000.0) / log(10.0)
	return 0.28 + 0.34 * log(radius_km / 2000.0) / log(10.0)

# ---- Setup ----

func _add_body(b: Dictionary, r_m: float, angle_fn: Callable) -> void:
	var sun_dir := Vector3.RIGHT
	var node := Space.make_planet(b, 1.0, sun_dir, 40)
	add_child(node)
	var tag := Label3D.new()
	tag.text = str(b.name)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0009
	tag.font = UI.font()
	tag.font_size = 30
	tag.outline_size = 8
	tag.modulate = Color(0.85, 0.92, 1.0, 0.95)
	add_child(tag)
	bodies.append({"data": b, "r": r_m, "angle": angle_fn, "node": node, "tag": tag, "globe": node.get_node("Globe")})

func _setup_solar() -> void:
	sun_node = Space.make_sun(self, 1.0)
	var light := OmniLight3D.new()
	light.omni_range = 200000.0
	light.omni_attenuation = 0.0
	light.light_energy = 2.2
	light.light_color = Color(1.0, 0.96, 0.9)
	add_child(light)
	for id: String in ["mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune"]:
		var b: Dictionary = Data.body(id)
		var e: Dictionary = Data.elements.planets[id]
		var pid := id
		_add_body(b, float(e.a_au) * Orbital.AU, func(u: float) -> float: return deg_to_rad(Orbital.mean_longitude(pid, u)))
	_parent_id = str(target.id) if target.kind == "planet" else str(target.parent)
	_r1 = float(Data.elements.planets.earth.a_au) * Orbital.AU
	_r2 = float(Data.elements.planets[_parent_id].a_au) * Orbital.AU
	_mu = Orbital.MU_SUN
	_start_angle = deg_to_rad(Orbital.mean_longitude("earth", _start_unix))
	var arrive := deg_to_rad(Orbital.mean_longitude(_parent_id, _start_unix + _days * 86400.0))
	_arrival_fix = wrapf(arrive - (_start_angle + PI), -PI, PI)
	_finish_transfer_setup()

func _setup_lunar() -> void:
	var earth: Dictionary = Data.body("earth")
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.3, 0.9, 0.0)
	light.light_energy = 1.6
	add_child(light)
	_add_body(earth, 0.0, func(_u: float) -> float: return 0.0)
	var moon_period := float(Data.body("moon").orbit_days) * 86400.0
	_add_body(Data.body("moon"), float(Data.body("moon").a_km) * 1000.0, func(u: float) -> float: return TAU * (u - _start_unix) / moon_period + 2.6)
	_r1 = Orbital.radius_m(earth) + Orbital.LEO_ALT
	_r2 = float(Data.body("moon").a_km) * 1000.0
	_mu = Orbital.mu_of(earth)
	_start_angle = 2.6 + TAU * (_days * 86400.0) / moon_period - PI
	_finish_transfer_setup()

func _finish_transfer_setup() -> void:
	_a = (_r1 + _r2) * 0.5
	_e = absf(_r2 - _r1) / (_r1 + _r2)
	_outward = _r2 > _r1
	craft = Models.spacecraft()
	add_child(craft)
	var glow := Models.ball(craft, 0.25, Vector3.ZERO, Models.mat(Color(0.6, 0.9, 1.0), 0.0, 1.0, 3.0))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = "Your spacecraft"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0009
	tag.font = UI.font_bold()
	tag.font_size = 30
	tag.outline_size = 8
	tag.modulate = UI.AMBER
	add_child(tag)
	_craft_tag = tag
	cam.max_distance = 6000.0
	cam.min_distance = 0.5
	cam.pitch = 0.75
	cam.yaw = 0.4

func _rebuild_scale() -> void:
	for c in orbit_lines.get_children():
		c.queue_free()
	for b: Dictionary in bodies:
		if float(b.r) > 0.0:
			var pts := PackedVector3Array()
			var rw := dist_units(float(b.r))
			for i in 129:
				var a := float(i) / 128.0 * TAU
				pts.append(Vector3(cos(a) * rw, 0.0, -sin(a) * rw))
			orbit_lines.add_child(Space.line_loop(pts, Color(0.5, 0.65, 0.85, 0.35)))
		(b.node as Node3D).scale = Vector3.ONE * maxf(size_units(float(b.data.radius_km)), 0.0001)
	# Transfer path
	var path := PackedVector3Array()
	for i in 129:
		path.append(_path_point(float(i) / 128.0))
	orbit_lines.add_child(Space.line_loop(path, Color(1.0, 0.72, 0.3, 0.9)))
	if mode == "solar":
		sun_node.scale = Vector3.ONE * (696340.0 * 1000.0 / Orbital.AU * 60.0 if scale_true else 1.1)
	var extent := dist_units(_r2) * 1.3
	cam.max_distance = maxf(extent * 3.0, 40.0)
	cam.zoom_to(extent * 1.1)
	cam.set_distance_now(extent * 1.1)
	if _scale_btn:
		_scale_btn.text = "Scale: TRUE (planets are tiny)" if scale_true else "Scale: VIEWABLE (sizes enlarged)"

## Point along the half-ellipse, at fraction f of the time of flight. Uses Kepler's equation.
func _kepler_state(f: float) -> Dictionary:
	var ecc := _e
	var mean := PI * f if _outward else PI + PI * f
	var ea := mean
	for _i in 8:
		ea -= (ea - ecc * sin(ea) - mean) / (1.0 - ecc * cos(ea))
	var r := _a * (1.0 - ecc * cos(ea))
	var nu := 2.0 * atan2(sqrt(1.0 + ecc) * sin(ea / 2.0), sqrt(1.0 - ecc) * cos(ea / 2.0))
	var base := 0.0 if _outward else -PI
	var angle := _start_angle + nu + base + _arrival_fix * f
	return {"r": r, "angle": angle}

func _path_point(f: float) -> Vector3:
	var s := _kepler_state(f)
	var rw := dist_units(float(s.r))
	return Vector3(cos(float(s.angle)) * rw, 0.0, -sin(float(s.angle)) * rw)

func _setup_interstellar() -> void:
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.2, 0.6, 0.0)
	light.light_color = Data.star_color(target.get("st_teff"))
	light.light_energy = 1.5
	add_child(light)
	_star = Space.make_sun(self, 3.0, Data.star_color(target.get("st_teff")))
	_star.position = Vector3(0, 0, -400)
	var planet := Space.make_planet(target, 1.6, Vector3(0, 0, -1))
	planet.position = Vector3(5.5, -0.5, -392)
	add_child(planet)
	bodies.append({"data": target, "r": 0.0, "node": planet, "globe": planet.get_node("Globe"), "angle": func(_u: float) -> float: return 0.0, "tag": null})
	craft = Models.spacecraft(0.5)
	add_child(craft)
	# A thin reflective sail ahead of the craft, on rigging, seen from the side so the star stays visible.
	var sail_mat := Models.mat(Color(0.95, 0.82, 0.55), 0.95, 0.12)
	sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sail := Models.cyl(craft, 4.2, 4.2, 0.02, Vector3(0, 0, -7.0), sail_mat, 32)
	sail.rotation.x = PI / 2.0
	for a: float in [0.0, 2.094, 4.189]:
		var tip := Vector3(cos(a) * 4.2, sin(a) * 4.2, -7.0)
		var cord := Models.cube(craft, Vector3(0.03, 0.03, tip.length()), tip * 0.5, Models.mat(Color(0.8, 0.8, 0.85)))
		cord.look_at_from_position(tip * 0.5, tip, Vector3.UP)
	cam.set_process(false)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	layer.add_child(root)
	_card = HudCard.new("On the way to " + str(target.name))
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	root.add_child(_card)
	_card.set_tip("Sit back. Your spacecraft is coasting there.")
	_card.add_row("trip", "Trip", true)
	_card.add_row("speed", "Speed")
	_card.add_row("where", "Distance")
	var col := UI.vbox(6)
	_card.add_widget(col)
	var speed_row := UI.hbox(6)
	speed_row.add_child(UI.button("Faster", func() -> void: time_scale = minf(time_scale * 2.0, 8.0)))
	speed_row.add_child(UI.button("Slower", func() -> void: time_scale = maxf(time_scale * 0.5, 0.25)))
	col.add_child(speed_row)
	if mode != "interstellar":
		_scale_btn = UI.button("Scale", toggle_scale)
		col.add_child(_scale_btn)
		var focus_row := UI.hbox(6)
		focus_row.add_child(UI.button("Follow craft", func() -> void: _focus_index = -1))
		focus_row.add_child(UI.button("Whole system", func() -> void: _focus_index = -2))
		col.add_child(focus_row)
		var bv := GridContainer.new()
		bv.columns = 4
		for i in bodies.size():
			var idx := i
			var b := UI.button(str(bodies[i].data.name), func() -> void: _show_body(idx))
			b.add_theme_font_size_override("font_size", 13)
			b.custom_minimum_size.y = 30.0
			bv.add_child(b)
		col.add_child(bv)
		col.add_child(UI.para("Drag to orbit the camera, scroll to zoom. %s toggles scale." % Settings.key_name("map"), 13))
	_info = UI.vbox(6)
	var ip := UI.panel(_info)
	ip.custom_minimum_size.x = 420.0
	ip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	ip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(ip)
	_show_target_info()

func _show_target_info() -> void:
	_set_info(target)

func _set_info(t: Dictionary) -> void:
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	_info.add_child(UI.heading(str(t.name), 24))
	_info.add_child(UI.stats_grid(t))
	var facts: Array = t.get("facts", [])
	if not facts.is_empty():
		_info.add_child(UI.fact_block(facts[randi() % facts.size()], 14))

func _show_body(i: int) -> void:
	_focus_index = i
	_set_info(bodies[i].data)

func toggle_scale() -> void:
	scale_true = not scale_true
	_rebuild_scale()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("details"):
		_card.toggle_details()
	if event.is_action_pressed("map") and mode != "interstellar":
		toggle_scale()

func _process(delta: float) -> void:
	if not _fix_active:
		progress += delta * time_scale / (DEMO_CRUISE_SECONDS if Game.is_demo() else CRUISE_SECONDS)
	progress = minf(progress, 1.0)
	var now := _start_unix + progress * _days * 86400.0
	if mode == "interstellar":
		_process_interstellar(delta)
	else:
		_process_system(now, delta)
	if not Game.is_demo() and not _fix_active and _fixes_done < 2 and progress > (0.32 if _fixes_done == 0 else 0.68):
		_begin_fix()
	if progress >= 1.0 and not _arrival:
		_arrival = true
		Sfx.play("chime")
		if Game.is_demo():
			# The demo goes straight to the good part.
			Game.mission.orbit_science = 40.0
			Game.add_science(40.0)
			Game.mission.phase = "landing"
			Flow.go("surface" if Game.is_probe_mission() else "landing", str(World.region_for(target).name))
		else:
			Game.mission.phase = "orbit"
			Flow.go("orbit", str(target.name))

func _process_system(now: float, delta: float) -> void:
	for b: Dictionary in bodies:
		var a: float = (b.angle as Callable).call(now)
		var rw := dist_units(float(b.r))
		var pos := Vector3(cos(a) * rw, 0.0, -sin(a) * rw)
		(b.node as Node3D).position = pos
		if b.tag:
			(b.tag as Label3D).position = pos + Vector3.UP * (maxf(size_units(float(b.data.radius_km)), 0.05) * 1.6)
		(b.globe as Node3D).rotation.y += Space.spin_rate(b.data) * delta
	var pos := _path_point(progress)
	craft.position = pos
	var next := _path_point(minf(progress + 0.005, 1.0))
	if next.distance_to(pos) > 0.0001:
		craft.look_at(next, Vector3.UP)
	var view_scale := clampf(cam.distance * 0.018, 0.02, 40.0)
	craft.scale = Vector3.ONE * view_scale
	_craft_tag.position = pos + Vector3.UP * view_scale * 1.4
	match _focus_index:
		-1:
			cam.focus = pos
		-2:
			cam.focus = Vector3.ZERO
		_:
			cam.focus = (bodies[_focus_index].node as Node3D).position
	var s := _kepler_state(progress)
	var v := sqrt(_mu * (2.0 / float(s.r) - 1.0 / _a))
	var dist_txt := "%.1f times Earth's distance from the Sun" % (float(s.r) / Orbital.AU) if mode == "solar" else "%s km from Earth" % UI.grouped(int(float(s.r) / 1000.0))
	_card.set_row("trip", "%s of %s" % [Orbital.format_time(progress * _days), Orbital.format_time(_days)], UI.TEXT, progress)
	_card.set_row("speed", "%.1f km/s" % (v / 1000.0))
	_card.set_row("where", dist_txt)
	_card.set_details(PackedStringArray(["Date %s" % Orbital.date_string(now), "Distance %.3f AU" % (float(s.r) / Orbital.AU) if mode == "solar" else "", "Transfer: Hohmann"]))

func _process_interstellar(delta: float) -> void:
	var k := pow(progress, 3.2)
	var cz := lerpf(14.0, -372.0, k)
	craft.position = Vector3(0, 0, cz - 9.0)
	cam.global_position = Vector3(16.0, 5.0, cz + 9.0)
	cam.look_at(Vector3(0.0, 0.0, lerpf(-40.0, -400.0, k)), Vector3.UP)
	var ly := float(plan.light_years)
	(bodies[0].globe as Node3D).rotation.y += delta * 0.1
	_card.set_row("trip", "%s of %s" % [Orbital.format_time(progress * _days), Orbital.format_time(_days)], UI.TEXT, progress)
	_card.set_row("speed", "20% of light speed (concept)")
	_card.set_row("where", "%.1f of %.1f light-years" % [ly * progress, ly])
	_card.set_details(PackedStringArray(["At Voyager 1's speed: %s" % Orbital.format_time(float(plan.voyager_years) * 365.25)]))

## The debris dodge: two encounters per cruise, each with a question about this mission and one about
## debris or meteoroids. Out between the planets the hazard is meteoroids; near Earth and the Moon it is
## human-made debris. See scripts/debris_run.gd.
func _begin_fix() -> void:
	_fix_active = true
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	debris = DebrisRun.new()
	debris.setup(Questions.encounter(target, plan, _asked), "debris" if mode == "lunar" else "meteoroids")
	debris.finished.connect(func(_right: int, _asked_n: int) -> void:
		layer.queue_free()
		_end_fix())
	layer.add_child(debris)

func _end_fix() -> void:
	_fix_active = false
	_fixes_done += 1
	debris = null

func auto_advance() -> void:
	time_scale = 8.0
	_auto_answer.call_deferred()
	if Game.is_demo():
		return
	if mode != "interstellar":
		_shot_true_scale()

func _shot_true_scale() -> void:
	toggle_scale()
	await get_tree().create_timer(1.0).timeout
	Autotest._shot("transfer_true_scale")
	toggle_scale()

## The autotest answers each debris question correctly after a short look.
func _auto_answer() -> void:
	while is_inside_tree():
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(debris):
			if debris.state == "ask":
				debris.answer(debris.right_index())
			elif debris.state == "explain":
				debris.next()
