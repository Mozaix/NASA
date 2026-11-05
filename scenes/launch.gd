extends Node3D
## Launch: ignite, keep aerodynamic stress out of the red or the rocket breaks up, then fire the departure burn.
## Stress values are game values with the shape of real dynamic pressure, q = 0.5 * rho * v^2.

const EARTH_R := 637.0  # 1 unit = 10 km
const ROCKET_SCALE := 0.03
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const STRESS_GAIN := 12.0
const RED_LIMIT_S := 2.5    # seconds in the red before the rocket breaks up
const RED_COOL := 0.5       # the structure recovers this many seconds' worth per second out of the red
const FLIP_RATE := 4.5
const ROLL_RATE := 6.0
const LEAN_RATE := 0.9
const COMBO_IDLE_S := 1.2   # an idle moment with the nose straight lands the combo

var rocket: Node3D
var booster: Node3D
var flame: CPUParticles3D
var flame2: CPUParticles3D
var cam: Camera3D
var sky_mat: ShaderMaterial
var state := "countdown"
var t := 3.0
var altitude := 0.0
var speed := 0.0
var throttle := 1.0
var q_time_good := 0.0
var q_time_total := 0.0
var burn_marker := 0.0
var burn_dir := 1.0
var burn_score := 0.0
var _status: Label
var _prompt: Label
var _card: HudCard
var _gauge: StressGauge
var _gauge_box: Control
var _timing: TimingBar
var _globe: Node3D
var _detached: Node3D
var _detached_v := Vector3.ZERO
var _land: MeshInstance3D
var stress := 0.0
var red_time := 0.0
var lean := 0.0
var flip := 0.0
var roll := 0.0
var auto_fly := false
var trick := TrickScore.new()
var _trick_hud: TrickHud
var _tilt := 0.0
var _gust := 0.0
var _gust_time := 0.0
var _idle := 0.0
var _base_pos := Vector3.ZERO
var _center := Vector3.ZERO
var _damage_bar: ProgressBar
var _fail_root: Control
var _ui_root: Control

## Green, amber and red bands with a needle, so the red zone is visible before the rocket gets there.
class StressGauge extends Control:
	var value := 0.0  # 1.0 is the edge of the red
	const FULL := 1.8
	func _draw() -> void:
		var h := size.y
		draw_rect(Rect2(0, 0, size.x * 0.75 / FULL, h), UI.GOOD.darkened(0.25))
		draw_rect(Rect2(size.x * 0.75 / FULL, 0, size.x * 0.25 / FULL, h), UI.AMBER.darkened(0.15))
		draw_rect(Rect2(size.x / FULL, 0, size.x * (1.0 - 1.0 / FULL), h), UI.BAD.darkened(0.15))
		var x := clampf(value / FULL, 0.0, 1.0) * size.x
		draw_rect(Rect2(x - 2.0, -3, 4, h + 6), Color.WHITE)

class TimingBar extends Control:
	var marker := 0.0
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.16, 0.95))
		draw_rect(Rect2(size.x * 0.42, 0, size.x * 0.16, size.y), UI.GOOD)
		draw_rect(Rect2(size.x * 0.28, 0, size.x * 0.14, size.y), UI.AMBER.darkened(0.2))
		draw_rect(Rect2(size.x * 0.58, 0, size.x * 0.14, size.y), UI.AMBER.darkened(0.2))
		draw_rect(Rect2(marker * size.x - 2.0, -4, 4, size.y + 8), Color.WHITE)

func _ready() -> void:
	Sfx.music("music_space")
	Game.mission.phase = "launch"
	Game.mission.launch_peak_stress = 0.0
	Game.mission.reached_orbit = false
	var sun := Vector3(0.6, 0.55, 0.6).normalized()
	var light := Space.make_sun_light(self, sun)
	light.shadow_enabled = false
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_color", Color(0.15, 0.36, 0.72))
	sky_mat.set_shader_parameter("horizon_color", Color(0.7, 0.83, 0.96))
	sky_mat.set_shader_parameter("sun_size", 0.0003)
	var stars := Data.stars_texture()
	if stars:
		sky_mat.set_shader_parameter("stars_tex", stars)
		sky_mat.set_shader_parameter("has_stars", true)
	sky_mat.set_shader_parameter("stars_amt", 0.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = Settings.glow()
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var earth := Space.make_planet(Data.body("earth"), EARTH_R, sun, 128)
	earth.rotation = Vector3.ZERO
	add_child(earth)
	_globe = earth.get_node("Globe")
	# Rotate the globe so Florida, the launch site, sits directly under the rocket at the top.
	var site := Space.latlon_to_unit(28.57, -80.65)
	var q := Quaternion(site, Vector3.UP)
	_globe.quaternion = q
	# NASA Blue Marble crop of Florida under the pad, at true scale. It is flat, so it hides as Earth curves away.
	var land := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	var region: Dictionary = Data.regions.get("earth_site", {})
	var land_size := float(region.get("width_km", 2400.0)) / 10.0
	plane.size = Vector2(land_size, land_size)
	land.mesh = plane
	var land_mat := StandardMaterial3D.new()
	land_mat.albedo_texture = Data.texture("res://data/regions/earth_site/color.jpgdata")
	land_mat.roughness = 1.0
	land.material_override = land_mat
	land.position = Vector3(0, EARTH_R + 0.05, 0)
	add_child(land)
	_land = land
	var pad_y := EARTH_R + 0.05
	Models.cyl(self, 0.05, 0.06, 0.012, Vector3(0, pad_y + 0.006, 0), Models.mat(Color(0.42, 0.42, 0.44)), 24)
	Models.cube(self, Vector3(0.005, 0.3, 0.005), Vector3(0.036, pad_y + 0.16, 0), Models.mat(Color(0.65, 0.22, 0.12), 0.3, 0.7))
	rocket = Models.rocket(str(Game.mission.launcher))
	rocket.scale = Vector3.ONE * ROCKET_SCALE
	rocket.position = Vector3(0, pad_y + 0.012, 0)
	_base_pos = rocket.position
	add_child(rocket)
	booster = rocket.get_node("Booster")
	flame = Models.flame(booster, Vector3(0, -0.2, 0), 1.3, Color(1.0, 0.62, 0.22), true, ROCKET_SCALE)
	flame2 = Models.flame(rocket.get_node("Upper"), Vector3(0, 5.95, 0), 0.7, Color(0.55, 0.72, 1.0), true, ROCKET_SCALE)
	cam = Camera3D.new()
	cam.far = 10000.0
	cam.near = 0.02
	cam.fov = 50.0
	add_child(cam)
	_build_hud()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	layer.add_child(root)
	_ui_root = root
	_card = HudCard.new("Launch", "%s to %s" % [str(Game.launcher().name), str(Game.target().name)])
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	root.add_child(_card)
	_card.add_row("height", "Height", true)
	_card.add_row("speed", "Speed")
	_gauge_box = UI.vbox(4)
	_gauge_box.visible = false
	_gauge_box.add_child(UI.label("Stress on the rocket (game value)", 15, UI.TEXT_DIM))
	_gauge = StressGauge.new()
	_gauge.custom_minimum_size = Vector2(0, 16)
	_gauge_box.add_child(_gauge)
	_gauge_box.add_child(UI.label("Rocket strength (game value)", 15, UI.TEXT_DIM))
	_damage_bar = UI.bar(0, 1, UI.GOOD, 9.0)
	_damage_bar.value = 1.0
	_gauge_box.add_child(_damage_bar)
	_gauge_box.add_child(UI.para("W S throttle   A D steer   %s + W A S D spin   %s autopilot" % [Settings.key_name("trick"), Settings.key_name("assist")], 13))
	_card.add_widget(_gauge_box)
	_trick_hud = TrickHud.new(trick, "Hold %s: W S flip, A D roll" % Settings.key_name("trick"))
	_trick_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	_trick_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_trick_hud)
	_status = UI.label("", 34, UI.TEXT, "bold")
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 40)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_status)
	_prompt = UI.label("", 22, UI.AMBER, "bold")
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 110)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_prompt)
	_timing = TimingBar.new()
	_timing.custom_minimum_size = Vector2(520, 22)
	_timing.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)
	_timing.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_timing.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_timing.visible = false
	root.add_child(_timing)

func _process(delta: float) -> void:
	match state:
		"countdown":
			_prompt.text = "Press %s to ignite" % Settings.key_name("thrust")
			_status.text = "Awaiting ignition"
			if Input.is_action_just_pressed("thrust"):
				ignite()
		"ascent":
			_ascent(delta)
		"coast":
			t -= delta
			_status.text = "Parking orbit"
			_prompt.text = "Departure burn ready"
			if t <= 0.0:
				state = "burn"
				_land_combo()
				_timing.visible = true
				_status.text = "Departure burn"
				burn_marker = 0.0
		"burn":
			_burn_timing(delta)
		"done":
			t -= delta
			if t <= 0.0:
				_next_scene()
	if state in ["ascent", "coast"]:
		_spin_controls(delta)
	elif state != "broken":
		_settle_attitude(delta)
	if state != "countdown" and state != "broken":
		_apply_attitude()
	_camera(delta)
	_card.set_row("height", "%.0f km up" % altitude, UI.TEXT, altitude / (Orbital.LEO_ALT / 1000.0))
	_card.set_row("speed", "%.1f km/s" % speed)
	_card.set_tip(_what_now())
	_card.set_details(PackedStringArray(["Throttle %.0f%%" % (throttle * 100.0), "Target orbit %.0f km" % (Orbital.LEO_ALT / 1000.0), "Earth gravity %.1f m/s\u00b2" % float(Data.body("earth").gravity)]))
	# Sky fades to black with altitude.
	var space := clampf(altitude / 90.0, 0.0, 1.0)
	sky_mat.set_shader_parameter("top_color", Color(0.15, 0.36, 0.72).lerp(Color.BLACK, space))
	sky_mat.set_shader_parameter("horizon_color", Color(0.7, 0.83, 0.96).lerp(Color.BLACK, space))
	sky_mat.set_shader_parameter("stars_amt", space)

func _what_now() -> String:
	match state:
		"countdown":
			return "Press %s to light the engines" % Settings.key_name("thrust")
		"ascent":
			if stress > 1.0:
				return "IN THE RED! Hold %s to throttle down and straighten up" % Settings.key_name("move_back")
			if absf(lean) > 0.14:
				return "Crosswind! Steer with A and D to point into the airflow"
			return "Climbing. Keep the stress needle out of the red"
		"coast":
			return "In orbit. Getting ready to leave Earth"
		"burn":
			return "Press %s when the marker is in the green" % Settings.key_name("thrust")
	if state == "broken":
		return "The rocket broke apart"
	return "On your way!"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("details"):
		_card.toggle_details()
	elif event.is_action_pressed("assist") and state == "ascent":
		auto_fly = not auto_fly
		_trick_hud.flash("Autopilot on" if auto_fly else "Autopilot off", UI.AMBER)

func ignite() -> void:
	state = "ascent"
	t = 0.0
	flame.emitting = true
	_prompt.text = ""
	_status.text = "Liftoff"
	_gauge_box.visible = true
	Sfx.play("stage")
	Sfx.loop("engine", 0.6)

func _ascent(real_delta: float) -> void:
	# The demo flies the same ascent at a faster pace.
	var delta := real_delta * (2.6 if Game.is_demo() else 1.0)
	t += delta
	var spinning := Input.is_action_pressed("trick")
	var up := 0.0 if spinning else Input.get_axis("move_back", "move_forward")
	var side := 0.0 if spinning else Input.get_axis("move_left", "move_right")
	var rho := exp(-altitude / 8.5)
	# Crosswind pushes the nose off the flight path while the air is thick.
	_gust_time -= real_delta
	if _gust_time <= 0.0:
		_gust_time = randf_range(1.2, 2.6)
		_gust = randf_range(-0.2, 0.2)
	lean += _gust * rho * real_delta
	if auto_fly:
		side = clampf(-lean * 6.0, -1.0, 1.0)
		up = clampf((0.65 - stress) * 4.0, -1.0, 1.0)
		Game.mission.assisted = Game.mission.assisted or not Game.is_demo()
	lean = clampf(lean + side * LEAN_RATE * real_delta, -0.6, 0.6)
	throttle = clampf(throttle + up * delta * 1.3, 0.35, 1.0)
	# Flying sideways points the engine away from the flight path, so less of it goes into climbing.
	var off_axis := _off_axis()
	var accel := throttle * (0.26 + t * 0.012) * lerpf(0.5, 1.0, maxf(cos(off_axis), 0.0))
	speed += accel * delta
	altitude += speed * delta * 6.2
	rho = exp(-altitude / 8.5)
	var q := 0.5 * rho * speed * speed * STRESS_GAIN
	# Air hitting the side of the rocket loads it far more than air along the nose.
	var rolling := absf(Input.get_axis("move_left", "move_right")) if spinning else 0.0
	stress = q * (1.0 + 6.0 * pow(sin(off_axis), 2.0) + 0.15 * rolling)
	var over := stress > 1.0
	var in_danger_zone := altitude > 5.0 and altitude < 60.0
	if in_danger_zone:
		q_time_total += delta
		if not over:
			q_time_good += delta
	_gauge.value = stress
	Game.mission.launch_peak_stress = maxf(float(Game.mission.launch_peak_stress), stress)
	_gauge.queue_redraw()
	# Damage counts in real seconds, so the demo's faster ascent is naturally more forgiving.
	if over:
		red_time += real_delta
		if int(red_time * 4.0) != int((red_time - real_delta) * 4.0):
			Sfx.play("alarm", -10.0)
	else:
		red_time = maxf(red_time - RED_COOL * real_delta, 0.0)
	var strength := 1.0 - red_time / RED_LIMIT_S
	_damage_bar.value = strength
	_damage_bar.add_theme_stylebox_override("fill", UI.box(UI.BAD if strength < 0.4 else (UI.AMBER if strength < 0.75 else UI.GOOD), Color.TRANSPARENT, 5, 0))
	if red_time >= RED_LIMIT_S:
		_break_up()
		return
	_tilt = clampf(altitude / 280.0, 0.0, 1.0) * 1.35
	var along := altitude * 0.55 * _tilt
	var r := EARTH_R + 0.062 + altitude / 10.0
	_land.visible = altitude < 55.0
	_base_pos = Vector3(along * 0.1, r, 0)
	if altitude > 15.0 and _status.text == "Liftoff":
		_status.text = "Max Q"
	if altitude > 80.0 and _detached == null:
		_stage_sep()
	if _detached:
		_detached_v += Vector3.DOWN * delta * 0.02
		_detached.global_position += _detached_v * delta * 60.0
	if altitude >= Orbital.LEO_ALT / 1000.0:
		Game.mission.reached_orbit = true
		stress = 0.0
		speed = sqrt(Orbital.mu_of(Data.body("earth")) / (Orbital.radius_m(Data.body("earth")) + Orbital.LEO_ALT)) / 1000.0
		state = "coast"
		t = 0.5 if Game.is_demo() else 2.2
		flame2.emitting = false
		_gauge_box.visible = false
		Sfx.loop("engine", 0.0)
		Sfx.play("chime")
		var ratio := q_time_good / maxf(q_time_total, 0.01)
		Game.mission.launch_quality = 0.75 + ratio * 0.25
		Game.add_science(0.0)

## Angle in radians between the nose and the direction of flight.
func _off_axis() -> float:
	return acos(clampf(cos(flip) * cos(lean), -1.0, 1.0))

## Trick button + W/S flips about the rocket's X axis; trick button + A/D rolls about its Y axis.
func _spin_controls(delta: float) -> void:
	var held := Input.is_action_pressed("trick") and not auto_fly
	var flip_in := Input.get_axis("move_back", "move_forward") if held else 0.0
	var roll_in := Input.get_axis("move_left", "move_right") if held else 0.0
	var dx := flip_in * FLIP_RATE * delta
	var dy := roll_in * ROLL_RATE * delta
	flip += dx
	roll += dy
	trick.spin(dx, dy)
	if absf(flip_in) < 0.1:
		# The flight computer brings the nose back round by the shortest way.
		flip = move_toward(flip, TAU * round(flip / TAU), 2.6 * delta)
	if absf(flip_in) + absf(roll_in) > 0.1 or absf(wrapf(flip, -PI, PI)) > 0.35:
		_idle = 0.0
	else:
		_idle += delta
		if _idle >= COMBO_IDLE_S:
			_land_combo()

func _settle_attitude(delta: float) -> void:
	flip = move_toward(flip, TAU * round(flip / TAU), 2.6 * delta)

func _land_combo() -> void:
	if trick.in_combo():
		var paid := trick.land()
		_trick_hud.flash("+%s" % UI.grouped(paid))
		Sfx.play("chime")

## Spins turn about the middle of the rocket, not its base.
func _apply_attitude() -> void:
	var flight := Basis(Vector3.BACK, -_tilt - lean)
	var full := flight * Basis(Vector3.RIGHT, flip) * Basis(Vector3.UP, roll)
	var pivot := Vector3(0, 7.5 if _detached else 5.0, 0) * ROCKET_SCALE
	rocket.transform = Transform3D(full.scaled(Vector3.ONE * ROCKET_SCALE), _base_pos + flight * pivot - full * pivot)
	_center = _base_pos + flight * pivot

func _break_up() -> void:
	state = "broken"
	Game.mission.breakup_km = altitude
	Game.mission.breakup_air = exp(-altitude / 8.5)
	Game.mission.breakup_sideways = pow(sin(_off_axis()), 2.0) * 6.0 > 0.5
	stress = 0.0
	trick.bail()
	_trick_hud.flash("Combo lost", UI.BAD)
	Sfx.loop("engine", 0.0)
	Sfx.play("crash")
	flame.emitting = false
	flame2.emitting = false
	var at := _center
	rocket.visible = false
	if _detached:
		_detached.visible = false
	_explode(at)
	Game.mission.rockets_lost = int(Game.mission.get("rockets_lost", 0)) + 1
	Game.mission.reached_orbit = false
	_status.text = "Vehicle lost"
	_prompt.text = ""
	_card.set_tip("The rocket broke apart", UI.BAD)
	# Let the player see the explosion before covering it.
	await get_tree().create_timer(1.6).timeout
	var v := UI.vbox(12)
	var pan := UI.panel(v, 26)
	pan.custom_minimum_size.x = 560.0
	v.add_child(UI.heading("The rocket broke apart", 32))
	v.add_child(UI.lesson_block(Game.launch_lesson(), 16))
	v.add_child(UI.para("Next time: press %s to throttle down in the thick lower air and keep the nose straight, or press %s for the autopilot." % [Settings.key_name("move_back"), Settings.key_name("assist")], 16, UI.GOOD))
	var again := UI.button("Try again with a backup rocket", func() -> void: Flow.go("launch", "Launch"), true)
	v.add_child(again)
	v.add_child(UI.button("End mission", func() -> void: Flow.go("debrief", "Mission Debrief")))
	_ui_root.add_child(pan)
	UI.center_panel(pan)
	_fail_root = pan
	again.grab_focus.call_deferred()

func _explode(at: Vector3) -> void:
	var puff: Texture2D = Models._soft_dot()
	for spec: Array in [[Color(1.0, 0.55, 0.15), 0.16, 0.42, 0.9, 90], [Color(0.3, 0.28, 0.27, 0.55), 0.2, 0.15, 2.4, 40]]:
		var p := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * float(spec[1])
		p.mesh = q
		p.amount = int(spec[4])
		p.one_shot = true
		p.explosiveness = 0.92
		p.lifetime = float(spec[3])
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = float(spec[2]) * 0.3
		p.initial_velocity_max = float(spec[2])
		p.gravity = Vector3.ZERO
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.4))
		curve.add_point(Vector2(0.3, 1.0))
		curve.add_point(Vector2(1, 0.0))
		p.scale_amount_curve = curve
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = spec[0]
		m.albedo_texture = puff
		if spec[0] == Color(1.0, 0.55, 0.15):
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.emission_enabled = true
			m.emission = spec[0]
			m.emission_energy_multiplier = 1.5
		p.material_override = m
		add_child(p)
		p.global_position = at
		p.emitting = true

func _stage_sep() -> void:
	Sfx.play("stage")
	_status.text = "Stage separation"
	flame.emitting = false
	flame2.emitting = true
	var keep := booster.global_transform
	rocket.remove_child(booster)
	add_child(booster)
	booster.global_transform = keep
	_detached = booster
	_detached_v = Vector3(0, -0.01, 0)

func _burn_timing(delta: float) -> void:
	burn_marker += burn_dir * delta * 0.55
	if burn_marker >= 1.0 or burn_marker <= 0.0:
		burn_dir = -burn_dir
		burn_marker = clampf(burn_marker, 0.0, 1.0)
	_timing.marker = burn_marker
	_timing.queue_redraw()
	_prompt.text = "Press %s in the green to fire at the right moment" % Settings.key_name("thrust")
	if Input.is_action_just_pressed("thrust"):
		fire_burn(burn_marker)

func fire_burn(at: float) -> void:
	var err := absf(at - 0.5)
	burn_score = 1.0 if err < 0.08 else (0.8 if err < 0.22 else 0.55)
	Game.mission.launch_quality = float(Game.mission.launch_quality) * (0.8 + burn_score * 0.2)
	Game.add_science(10.0 * burn_score)
	_prompt.text = "Perfect burn" if burn_score == 1.0 else ("Good burn" if burn_score > 0.6 else "Late burn: extra fuel spent")
	_status.text = "On course for %s" % str(Game.target().name)
	flame2.emitting = true
	Sfx.play("stage")
	Sfx.loop("engine", 0.5, 1.2)
	_timing.visible = false
	state = "done"
	t = 2.0

func _next_scene() -> void:
	flame2.emitting = false
	Sfx.loop("engine", 0.0)
	Game.mission.phase = "transfer"
	if Orbital.plan(Game.target()).kind == "orbit" and not Game.is_demo():
		Flow.go("orbit", str(Game.target().name))
	else:
		Flow.go("transfer", "Cruise to " + str(Game.target().name))

func _camera(delta: float) -> void:
	var near_t := clampf(altitude / 12.0, 0.0, 1.0)
	# Stay close enough that the rocket remains the subject of the shot all the way to orbit.
	var dist := lerpf(0.62, 0.95, clampf(altitude / 300.0, 0.0, 1.0))
	var off := Vector3(0.7, 0.04 + near_t * 0.5, 1.0).normalized() * dist
	var tgt: Vector3 = _center if state != "countdown" else rocket.global_transform * Vector3(0, 5.0, 0)
	var pos := tgt + off
	pos.y = maxf(pos.y, EARTH_R + 0.14)
	cam.global_position = cam.global_position.lerp(pos, clampf(delta * 9.0, 0.0, 1.0)) if cam.global_position.length() > 1.0 else pos
	cam.look_at(tgt, Vector3.UP)

func auto_advance() -> void:
	auto_fly = true
	if state == "countdown":
		ignite()
	await get_tree().create_timer(12.0 if Game.is_demo() else 30.0).timeout
	while state == "ascent":
		await get_tree().process_frame
	while state != "burn":
		await get_tree().process_frame
	fire_burn(0.5)
