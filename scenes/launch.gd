extends Node3D
## Launch: ignite, keep the rocket out of the dynamic-pressure danger zone, then fire the departure burn.

const EARTH_R := 637.0  # 1 unit = 10 km
const ROCKET_SCALE := 0.03
const SKY_SHADER := preload("res://shaders/sky.gdshader")

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
var _hud: Label
var _gauge: ProgressBar
var _gauge_box: Control
var _timing: TimingBar
var _globe: Node3D
var _detached: Node3D
var _detached_v := Vector3.ZERO
var _land: MeshInstance3D

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
	rocket = Models.rocket()
	rocket.scale = Vector3.ONE * ROCKET_SCALE
	rocket.position = Vector3(0, pad_y + 0.012, 0)
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
	var col := UI.vbox(6)
	var p := UI.panel(col)
	p.custom_minimum_size.x = 330.0
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	root.add_child(p)
	col.add_child(UI.eyebrow("%s to %s" % [str(Game.launcher().name), str(Game.target().name)]))
	_hud = UI.label("", 16, UI.TEXT, "mono")
	col.add_child(_hud)
	_gauge_box = UI.vbox(4)
	_gauge_box.visible = false
	_gauge_box.add_child(UI.label("AERODYNAMIC STRESS: keep in the green", 13, UI.TEXT_DIM))
	_gauge = UI.bar(0, 1, UI.GOOD, 14.0)
	_gauge_box.add_child(_gauge)
	_gauge_box.add_child(UI.para("%s and %s adjust throttle" % [Settings.key_name("move_forward"), Settings.key_name("move_back")], 13))
	col.add_child(_gauge_box)
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
				_timing.visible = true
				_status.text = "Departure burn"
				burn_marker = 0.0
		"burn":
			_burn_timing(delta)
		"done":
			t -= delta
			if t <= 0.0:
				_next_scene()
	_camera(delta)
	var alt_km := altitude
	var v_txt := speed
	_hud.text = "Altitude %7.0f km\nSpeed    %7.2f km/s\nThrottle %7.0f %%\nGravity  %7.2f m/s²" % [alt_km, v_txt, throttle * 100.0, float(Data.body("earth").gravity)]
	# Sky fades to black with altitude.
	var space := clampf(altitude / 90.0, 0.0, 1.0)
	sky_mat.set_shader_parameter("top_color", Color(0.15, 0.36, 0.72).lerp(Color.BLACK, space))
	sky_mat.set_shader_parameter("horizon_color", Color(0.7, 0.83, 0.96).lerp(Color.BLACK, space))
	sky_mat.set_shader_parameter("stars_amt", space)

func ignite() -> void:
	state = "ascent"
	t = 0.0
	flame.emitting = true
	_prompt.text = ""
	_status.text = "Liftoff"
	_gauge_box.visible = true
	Sfx.play("stage")
	Sfx.loop("engine", 0.6)

func _ascent(delta: float) -> void:
	t += delta
	var up := Input.get_axis("move_back", "move_forward")
	throttle = clampf(throttle + up * delta * 1.3, 0.35, 1.0)
	# Gameplay ascent: 28 seconds to orbit. Dynamic pressure follows the usual q = 0.5 * rho * v^2 shape.
	var accel := throttle * (0.26 + t * 0.012)
	speed += accel * delta
	altitude += speed * delta * 6.2
	var rho := exp(-altitude / 8.5)
	var q := 0.5 * rho * speed * speed * 45.0
	var over := q > 1.0
	var in_danger_zone := altitude > 5.0 and altitude < 60.0
	if in_danger_zone:
		q_time_total += delta
		if not over:
			q_time_good += delta
	_gauge.value = clampf(q, 0.0, 1.0)
	_gauge.add_theme_stylebox_override("fill", UI.box(UI.BAD if over else (UI.AMBER if q > 0.75 else UI.GOOD), Color.TRANSPARENT, 5, 0))
	var tilt := clampf(altitude / 280.0, 0.0, 1.0) * 1.35
	rocket.rotation.z = -tilt
	var along := altitude * 0.55 * tilt
	var r := EARTH_R + 0.062 + altitude / 10.0
	_land.visible = altitude < 55.0
	rocket.position = Vector3(along * 0.1, r, 0)
	if altitude > 15.0 and _status.text == "Liftoff":
		_status.text = "Max Q"
	if altitude > 80.0 and _detached == null:
		_stage_sep()
	if _detached:
		_detached_v += Vector3.DOWN * delta * 0.02
		_detached.global_position += _detached_v * delta * 60.0
	if altitude >= Orbital.LEO_ALT / 1000.0:
		speed = sqrt(Orbital.mu_of(Data.body("earth")) / (Orbital.radius_m(Data.body("earth")) + Orbital.LEO_ALT)) / 1000.0
		state = "coast"
		t = 2.2
		flame2.emitting = false
		_gauge_box.visible = false
		Sfx.loop("engine", 0.0)
		Sfx.play("chime")
		var ratio := q_time_good / maxf(q_time_total, 0.01)
		Game.mission.launch_quality = 0.75 + ratio * 0.25
		Game.add_science(0.0)

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
	if Orbital.plan(Game.target()).kind == "orbit":
		Flow.go("orbit", str(Game.target().name))
	else:
		Flow.go("transfer", "Cruise to " + str(Game.target().name))

func _camera(delta: float) -> void:
	var near_t := clampf(altitude / 12.0, 0.0, 1.0)
	# Stay close enough that the rocket remains the subject of the shot all the way to orbit.
	var dist := lerpf(0.62, 0.95, clampf(altitude / 300.0, 0.0, 1.0))
	var off := Vector3(0.7, 0.04 + near_t * 0.5, 1.0).normalized() * dist
	var tgt: Vector3 = rocket.global_transform * Vector3(0, 7.5 if _detached else 5.0, 0)
	var pos := tgt + off
	pos.y = maxf(pos.y, EARTH_R + 0.14)
	cam.global_position = cam.global_position.lerp(pos, clampf(delta * 9.0, 0.0, 1.0)) if cam.global_position.length() > 1.0 else pos
	cam.look_at(tgt, Vector3.UP)

func auto_advance() -> void:
	if state == "countdown":
		ignite()
	await get_tree().create_timer(30.0).timeout
	while state == "ascent":
		await get_tree().process_frame
	while state != "burn":
		await get_tree().process_frame
	fire_burn(0.5)
