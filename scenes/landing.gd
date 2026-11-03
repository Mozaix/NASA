extends Node3D
## Powered descent onto real terrain, under real gravity. Fuel comes from the delta-v margin you designed.

var world: Dictionary
var terrain: Node
var region: Dictionary
var craft: Node3D
var flame: CPUParticles3D
var chute: Node3D
var cam: Camera3D
var pad := Vector3.ZERO
var vel := Vector3.ZERO
var gravity := 3.7
var thrust_acc := 8.0
var drag := 0.0
var fuel := 1.0
var fuel_burn := 0.03
var tilt := Vector2.ZERO
var auto_pilot := false
var state := "fly"
var _hud: Label
var _msg: Label
var _fuel_bar: ProgressBar
var _result_panel: Control
var _cam_yaw := 0.6
var _low_alarm := false
var uses_chute := false
var tolerance := 5.0
var _bounce := 0

func _ready() -> void:
	var t := Game.target()
	Game.mission.phase = "landing"
	Sfx.music("music_surface")
	region = World.region_for(t)
	world = World.build(self, t, region)
	terrain = world.terrain
	gravity = float(t.get("gravity", 3.7))
	var lander_part := Game.lander()
	tolerance = float(lander_part.tolerance)
	uses_chute = lander_part.id == "airbag"
	var uv: Array = region.landing_uv
	pad = terrain.flat_spot(float(uv[0]), float(uv[1])) if terrain is Terrain else terrain.uv_to_world(float(uv[0]), float(uv[1]))
	terrain.set_pad(pad, 34.0)
	craft = Models.lander(uses_chute or lander_part.id == "skycrane")
	add_child(craft)
	flame = craft.get_node("Flame")
	if craft.has_node("Chute"):
		chute = craft.get_node("Chute")
	# Start high and off-target. Weak-gravity worlds start with more speed so the descent stays short.
	# Weak gravity also means weak thrusters, so tiny moons start lower and closer to the pad.
	var near_factor := clampf(sqrt(gravity / 1.2), 0.4, 1.0)
	var start_h := 780.0 * near_factor
	craft.global_position = pad + Vector3(-210.0, start_h, 170.0) * Vector3(near_factor, 1.0, near_factor)
	var fall := clampf(sqrt(2.0 * gravity * start_h) * 0.45, 16.0, 62.0)
	vel = Vector3(12.0, -fall, -9.0) * Vector3(near_factor, 1.0, near_factor)
	# Thrust scales with gravity but always leaves control authority on tiny moons.
	thrust_acc = maxf(gravity * 2.6, 1.2)
	var atmo := Data.has_atmosphere(t)
	var pressure := float(t.get("pressure_bar") if t.get("pressure_bar") != null else (1.4 if t.id == "titan" else 0.0))
	drag = 0.0 if not atmo else clampf(0.012 + 0.03 * log(1.0 + pressure * 40.0), 0.01, 0.2)
	# Delta-v margin buys fuel. Sky cranes and retro landers both benefit; airbags need less.
	var margin := Game.dv_margin()
	var flight_quality := float(Game.mission.launch_quality) * float(Game.mission.correction_quality)
	var fuel_fraction := clampf(0.8 + margin / 2500.0, 0.8, 1.2) * float(lander_part.fuel) * (0.85 + 0.15 * flight_quality)
	fuel = 1.0
	fuel_burn = 1.0 / (fall / thrust_acc * 2.2 + 26.0) / fuel_fraction
	cam = Camera3D.new()
	cam.far = 30000.0
	cam.fov = 62.0
	add_child(cam)
	_build_hud()
	Sfx.loop("wind", 0.25 if atmo else 0.0)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	layer.add_child(root)
	var col := UI.vbox(6)
	var p := UI.panel(col)
	p.custom_minimum_size.x = 340.0
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	root.add_child(p)
	col.add_child(UI.eyebrow("Landing: " + str(region.name)))
	_hud = UI.label("", 16, UI.TEXT, "mono")
	col.add_child(_hud)
	col.add_child(UI.label("FUEL", 13, UI.TEXT_DIM))
	_fuel_bar = UI.bar(1, 1, UI.AMBER, 10.0)
	col.add_child(_fuel_bar)
	col.add_child(UI.para("%s thrust   WASD steer   %s autopilot (lowers score)" % [Settings.key_name("thrust"), Settings.key_name("assist")], 13))
	_msg = UI.label("", 22, UI.AMBER, "bold")
	_msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 30)
	root.add_child(_msg)
	_result_panel = Control.new()
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_result_panel)

func _physics_process(delta: float) -> void:
	if state != "fly":
		return
	var p := craft.global_position
	var ground: float = terrain.height_at(p.x, p.z)
	var alt := p.y - ground
	var steer := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	var throttle := 1.0 if Input.is_action_pressed("thrust") else 0.0
	if Input.is_action_just_pressed("assist"):
		auto_pilot = not auto_pilot
		if auto_pilot:
			Game.mission.assisted = true
	if auto_pilot:
		var c := _autopilot(p, alt)
		steer = c[0]
		throttle = c[1]
	if uses_chute:
		throttle = 0.0  # airbag landers drift under canopy and steer with small vanes
	tilt = tilt.lerp(steer * deg_to_rad(24.0), clampf(delta * 3.5, 0.0, 1.0))
	var basis := Basis.from_euler(Vector3(tilt.y, 0.0, -tilt.x))
	craft.transform.basis = basis
	var accel := Vector3.DOWN * gravity
	# Side thrusters steer without the main engine, at a small propellant cost.
	if fuel > 0.0 and not uses_chute and steer.length() > 0.05:
		accel += Vector3(steer.x, 0.0, steer.y) * minf(thrust_acc * 0.3, 2.0)
		fuel = maxf(fuel - fuel_burn * 0.12 * steer.length() * delta, 0.0)
	# Dense air gives the shell aerodynamic lift to steer with, at no propellant cost.
	if drag > 0.0 and not uses_chute:
		accel += Vector3(steer.x, 0.0, steer.y) * drag * 30.0
	if throttle > 0.0 and fuel > 0.0:
		accel += basis.y * thrust_acc * throttle
		fuel = maxf(fuel - fuel_burn * delta, 0.0)
	var firing := throttle > 0.0 and fuel > 0.0
	flame.emitting = firing
	Sfx.loop("engine", 0.45 if firing else 0.0, 0.8 + throttle * 0.2)
	if uses_chute:
		if chute and alt < 170.0:
			chute.visible = true
		# Canopy: strong drag toward a gentle terminal speed. Steering comes from vanes.
		# Falls fast under a drogue, then the main canopy slows it for the last stretch.
		var terminal := minf(tolerance * 0.65, 8.5) if alt < 170.0 else 26.0
		vel.y = lerpf(vel.y, -terminal, clampf(delta * 0.8, 0.0, 1.0))
		accel = Vector3(steer.x * 5.0, 0.0, steer.y * 5.0)
	elif drag > 0.0:
		accel -= vel * drag
	vel += accel * delta
	craft.global_position = p + vel * delta
	var w: float = terrain.world_m
	craft.global_position.x = clampf(craft.global_position.x, 10.0, w - 10.0)
	craft.global_position.z = clampf(craft.global_position.z, 10.0, w - 10.0)
	var dist := Vector2(p.x - pad.x, p.z - pad.z).length()
	_hud.text = "Altitude   %6.0f m\nDescent    %6.1f m/s\nDrift      %6.1f m/s\nTo target  %6.0f m\nGravity    %6.2f m/s²" % [alt, -vel.y, Vector2(vel.x, vel.z).length(), dist, gravity]
	_fuel_bar.value = fuel
	if fuel < 0.18 and not _low_alarm:
		_low_alarm = true
		Sfx.play("alarm")
		_msg.text = "LOW FUEL"
	var sink_limit := tolerance
	if alt < 80.0 and -vel.y > sink_limit * 1.6 and not uses_chute:
		_msg.text = "TOO FAST"
	elif fuel >= 0.18:
		_msg.text = "AUTOPILOT" if auto_pilot else ""
	if craft.global_position.y <= terrain.height_at(craft.global_position.x, craft.global_position.z):
		_touchdown(dist)

func _autopilot(p: Vector3, alt: float) -> Array:
	var to_pad := Vector2(pad.x - p.x, pad.z - p.z)
	var dist := to_pad.length()
	var hv := Vector2(vel.x, vel.z)
	# Head for the pad only as fast as the side thrusters can stop, or the craft swings past it.
	var side_accel := minf(thrust_acc * 0.3, 2.0) + drag * 30.0
	var approach := minf(sqrt(2.0 * side_accel * 0.6 * dist), 38.0)
	var want_h := to_pad.normalized() * approach if dist > 0.5 else Vector2.ZERO
	var steer := ((want_h - hv) * (0.5 / maxf(side_accel, 0.3))).limit_length(1.0)
	# Look ahead along the flight path, so rising ground is seen before the craft reaches it.
	var clearance := alt
	for look: float in [1.0, 2.0, 3.5, 5.0]:
		var ahead := p + Vector3(vel.x, 0.0, vel.z) * look
		clearance = minf(clearance, p.y - float(terrain.height_at(ahead.x, ahead.z)))
	# Fastest safe descent for this world: the speed that can still be stopped with the thrust left
	# over after gravity, using 55% of it so there is margin. v = sqrt(2 a h).
	var net := maxf(thrust_acc - gravity, 0.4)
	var want_v := -clampf(sqrt(2.0 * net * 0.55 * maxf(clearance, 0.0)) + 0.8, 1.0, 45.0)
	# Stay above the terrain until over the pad, then come straight down.
	var safe_height := 0.0 if dist < 25.0 else minf(dist * 0.18, 70.0)
	if clearance < safe_height:
		# Only climb as fast as gravity can stop: on tiny moons a hard climb would never come back down.
		var coast := sqrt(2.0 * gravity * (safe_height - clearance))
		want_v = clampf(minf((safe_height - clearance) * 0.25, coast), -2.0, 8.0)
	var v_err := want_v - vel.y
	return [steer, 1.0 if v_err > 0.0 else 0.0]

func _touchdown(dist: float) -> void:
	var p := craft.global_position
	p.y = terrain.height_at(p.x, p.z)
	craft.global_position = p
	var sink := -vel.y
	var drift := Vector2(vel.x, vel.z).length()
	var n: Vector3 = terrain.normal_at(p.x, p.z)
	var slope := rad_to_deg(n.angle_to(Vector3.UP))
	flame.emitting = false
	Sfx.loop("engine", 0.0)
	var limit := tolerance
	var ok := sink <= limit and drift <= limit * 1.3 and slope < 34.0
	if uses_chute and _bounce < 2 and ok:
		_bounce += 1
	if ok:
		state = "landed"
		Sfx.play("touchdown")
		var accuracy := 1.0 - clampf(dist / 500.0, 0.0, 1.0)
		var softness := 1.0 - clampf(sink / limit, 0.0, 1.0)
		var rating := accuracy * 0.65 + softness * 0.35
		Game.mission.landed = true
		Game.mission.landing_rating = rating
		Game.mission.landing_pos = [p.x, p.z]
		Game.mission.landing_stats = {"sink": sink, "drift": drift, "slope": slope, "dist_real_km": dist * float(region.get("hscale", 24.0)) / 1000.0, "fuel_left": fuel}
		_show_result(true, "Touchdown at %.1f m/s, %.1f km from the target." % [sink, dist * float(region.get("hscale", 24.0)) / 1000.0])
	else:
		state = "crashed"
		Sfx.play("crash")
		Game.mission.crashes = int(Game.mission.crashes) + 1
		craft.visible = false
		Game.mission.landing_stats = {"sink": sink, "drift": drift, "slope": slope, "fuel_left": fuel, "limit": limit, "dist_m": dist}
		var why := "Impact at %.1f m/s (limit %.0f)." % [sink, limit]
		if drift > limit * 1.3:
			why = "Too much sideways drift: %.1f m/s." % drift
		elif sink <= limit:
			why = "The ground was too steep: %.0f°." % slope
		_show_result(false, why)

func _show_result(ok: bool, text: String) -> void:
	var v := UI.vbox(12)
	var pan := UI.panel(v, 26)
	pan.custom_minimum_size.x = 560.0
	v.add_child(UI.heading("The rover is on the ground" if ok else "Lander lost", 32))
	v.add_child(UI.para(text, 18, UI.TEXT))
	if ok:
		var facts: Array = Game.target().get("facts", [])
		if not facts.is_empty():
			v.add_child(UI.fact_block(facts[randi() % facts.size()]))
		var go := UI.button("Deploy rover", _go_surface, true)
		v.add_child(go)
		go.grab_focus.call_deferred()
	else:
		v.add_child(UI.para("Mission control has a backup lander, at a scoring penalty. Tip: start braking earlier, and arrive slowly and nearly upright.", 16))
		var again := UI.button("Try again with the backup lander", func() -> void: Flow.go("landing", str(region.name)), true)
		v.add_child(again)
		again.grab_focus.call_deferred()
		v.add_child(UI.button("End mission", func() -> void: Flow.go("debrief", "Mission Debrief")))
	_result_panel.add_child(pan)
	_result_panel.visible = true
	_result_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	pan.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

func _go_surface() -> void:
	Flow.go("surface", str(region.name))

func _process(delta: float) -> void:
	terrain.update_lod(cam.global_position, delta)
	_cam_yaw += Input.get_axis("cam_left", "cam_right") * delta
	var p := craft.global_position
	var alt := p.y - float(terrain.height_at(p.x, p.z))
	var back := lerpf(26.0, 60.0, clampf(alt / 500.0, 0.0, 1.0))
	var target := p + Vector3(sin(_cam_yaw) * back, back * 0.42, cos(_cam_yaw) * back)
	target.y = maxf(target.y, float(terrain.height_at(target.x, target.z)) + 4.0)
	cam.global_position = cam.global_position.lerp(target, clampf(delta * 5.0, 0.0, 1.0)) if cam.global_position != Vector3.ZERO else target
	cam.look_at(p + Vector3.UP * 3.0, Vector3.UP)

func auto_advance() -> void:
	# Full autopilot, as a real player could choose. Tests use it to prove the descent can be flown.
	auto_pilot = true
	Game.mission.assisted = true

func auto_surface() -> void:
	if state == "landed":
		_go_surface()
	elif state == "crashed":
		Autotest.report("landing_crash", {"region": region.get("name", "")})
		Flow.go("surface", str(region.name))
