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
var _card: HudCard
var _overlay: PadOverlay
var _down_blend := 0.0
var _first_frame := true
var _msg: Label
var view_down := false
var _dragging := false
var _cam_pitch := 0.4
var _cam_zoom := 1.0
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
	var start_h := 780.0 * near_factor * (0.6 if Game.is_demo() else 1.0)
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
	# The demo starts on autopilot, so anyone can watch the landing and look around.
	auto_pilot = Game.is_demo()
	cam = Camera3D.new()
	cam.far = 30000.0
	cam.near = 0.1
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
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_overlay = PadOverlay.new()
	_overlay.scene = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_card = HudCard.new("Landing", str(region.name))
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	root.add_child(_card)
	_card.add_row("height", "Height above ground", true)
	_card.add_row("falling", "Falling")
	_card.add_row("pad", "Landing pad")
	_card.add_row("fuel", "Fuel", true, UI.AMBER)
	var keys := UI.para("%s look down at the pad   %s fire engine   W A S D steer   %s autopilot" % [Settings.key_name("look_down"), Settings.key_name("thrust"), Settings.key_name("assist")], 13)
	_card.add_widget(keys)
	_msg = UI.label("", 22, UI.AMBER, "bold")
	_msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 30)
	_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_msg)
	_result_panel = Control.new()
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_result_panel)

## Marks the pad on screen wherever the player is looking, and shows the aim point when looking down.
class PadOverlay extends Control:
	var scene: Node3D
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		if scene.state != "fly":
			return
		var cam: Camera3D = scene.cam
		var font := UI.font_bold()
		if scene.view_down:
			var c := size * 0.5
			draw_arc(c, 34.0, 0.0, TAU, 40, Color(1, 1, 1, 0.7), 2.0)
			draw_line(c + Vector2(-48, 0), c + Vector2(-20, 0), Color(1, 1, 1, 0.7), 2.0)
			draw_line(c + Vector2(20, 0), c + Vector2(48, 0), Color(1, 1, 1, 0.7), 2.0)
			draw_line(c + Vector2(0, -48), c + Vector2(0, -20), Color(1, 1, 1, 0.7), 2.0)
			draw_line(c + Vector2(0, 20), c + Vector2(0, 48), Color(1, 1, 1, 0.7), 2.0)
			draw_string(font, c + Vector2(-140, 74), "You will land near here", HORIZONTAL_ALIGNMENT_CENTER, 280, 17, Color(1, 1, 1, 0.85))
		var pad_pos: Vector3 = scene.pad
		if cam.is_position_behind(pad_pos):
			return
		var pt := cam.unproject_position(pad_pos)
		var inside := pt.x > 40.0 and pt.y > 40.0 and pt.x < size.x - 40.0 and pt.y < size.y - 40.0
		if not inside:
			var dir := (pt - size * 0.5).normalized()
			var edge := size * 0.5 + dir * minf(size.x, size.y) * 0.42
			var nrm := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([edge + dir * 20.0, edge - dir * 8.0 + nrm * 14.0, edge - dir * 8.0 - nrm * 14.0]), UI.GOOD)
			draw_string(font, edge - dir * 40.0 + Vector2(-60, 6), "Pad", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, UI.GOOD)
			return
		var pulse := 18.0 + 4.0 * sin(float(Time.get_ticks_msec()) * 0.005)
		draw_arc(pt, pulse, 0.0, TAU, 32, UI.GOOD, 3.0)
		draw_string(font, pt + Vector2(-90, -pulse - 10.0), "Landing pad", HORIZONTAL_ALIGNMENT_CENTER, 180, 18, UI.GOOD)

func toggle_look_down() -> void:
	view_down = not view_down
	Sfx.play("click")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("look_down"):
		toggle_look_down()
	elif event.is_action_pressed("details"):
		_card.toggle_details()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom = clampf(_cam_zoom * 0.9, 0.45, 2.2)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom = clampf(_cam_zoom * 1.1, 0.45, 2.2)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.005 * Settings.mouse_sens
		_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.005 * Settings.mouse_sens, 0.05, 1.5)

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
		if auto_pilot and not Game.is_demo():
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
	_update_card(alt, dist)
	if craft.global_position.y <= terrain.height_at(craft.global_position.x, craft.global_position.z):
		_touchdown(dist)

func _update_card(alt: float, dist: float) -> void:
	var sink := -vel.y
	var limit := tolerance
	# "Safe" means the engine can still stop the fall from this height.
	var net := maxf(thrust_acc - gravity, 0.4)
	var stoppable := sqrt(2.0 * net * maxf(alt, 0.0)) + limit * 0.6
	var fall_word := "Rising"
	var fall_col := UI.TEXT
	if sink > 0.2:
		if uses_chute:
			fall_word = "Under parachute"
			fall_col = UI.GOOD
		elif sink > stoppable:
			fall_word = "Too fast!"
			fall_col = UI.BAD
		elif sink > stoppable * 0.75:
			fall_word = "Getting fast"
			fall_col = UI.AMBER
		else:
			fall_word = "Safe"
			fall_col = UI.GOOD
	_card.set_row("height", "%.0f m" % maxf(alt, 0.0), UI.ACCENT, alt / 800.0)
	_card.set_row("falling", fall_word, fall_col)
	var real_km := dist * float(region.get("hscale", 24.0)) / 1000.0
	var on_pad := dist < 34.0
	_card.set_row("pad", "Right below you" if on_pad else ("%.1f km away" % real_km), UI.GOOD if on_pad else UI.TEXT)
	_card.set_row("fuel", "%d%%" % int(fuel * 100.0), UI.BAD if fuel < 0.18 else UI.AMBER, fuel)
	if fuel < 0.18 and not _low_alarm:
		_low_alarm = true
		Sfx.play("alarm")
	var tip := "Steer toward the green ring with W A S D"
	if auto_pilot:
		tip = "Autopilot is flying. Press %s to look down, %s to take over" % [Settings.key_name("look_down"), Settings.key_name("assist")]
	elif uses_chute:
		tip = "The parachute does the work. Steer to the ring"
	elif fuel <= 0.0:
		tip = "Out of fuel. Brace!"
	elif fall_word == "Too fast!":
		tip = "Hold %s now to slow down" % Settings.key_name("thrust")
	elif on_pad:
		tip = "Over the pad. Tap %s to touch down gently" % Settings.key_name("thrust")
	_card.set_tip(tip, UI.BAD if fall_word == "Too fast!" else UI.TEXT)
	_card.set_details(PackedStringArray(["Descent %.1f m/s (limit %.0f)" % [sink, limit], "Drift %.1f m/s" % Vector2(vel.x, vel.z).length(), "Gravity %.2f m/s\u00b2" % gravity, "Distance on map %.0f m" % dist]))

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
	_cam_pitch = clampf(_cam_pitch + Input.get_axis("cam_up", "cam_down") * delta, 0.05, 1.5)
	var p := craft.global_position
	var alt := p.y - float(terrain.height_at(p.x, p.z))
	var k := 1.0 - exp(-delta * 6.0)
	if view_down:
		# Under the lander, straight down: the view a pilot would want for the last few metres.
		_down_blend = minf(_down_blend + delta * 2.5, 1.0)
	else:
		_down_blend = maxf(_down_blend - delta * 2.5, 0.0)
	var back := lerpf(26.0, 60.0, clampf(alt / 500.0, 0.0, 1.0)) * _cam_zoom
	var chase := p + Vector3(sin(_cam_yaw) * cos(_cam_pitch), sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch)) * back
	chase.y = maxf(chase.y, float(terrain.height_at(chase.x, chase.z)) + 4.0)
	var belly := p + Vector3(0.0, 0.9, 0.0)
	var t := smoothstep(0.0, 1.0, _down_blend)
	var target_pos := chase.lerp(belly, t)
	cam.global_position = target_pos if _first_frame else cam.global_position.lerp(target_pos, 1.0 if t > 0.98 else k)
	_first_frame = false
	var look_chase := p + Vector3.UP * 3.0
	var look_belly := Vector3(p.x, p.y - 40.0, p.z)
	var up := Vector3.UP.lerp(Vector3.FORWARD, t).normalized()
	cam.look_at(look_chase.lerp(look_belly, t), up)
	cam.fov = lerpf(62.0, 78.0, t)

func auto_advance() -> void:
	# Full autopilot, as a real player could choose. Tests use it to prove the descent can be flown.
	auto_pilot = true
	if not Game.is_demo():
		Game.mission.assisted = true

func auto_surface() -> void:
	if state == "landed":
		_go_surface()
	elif state == "crashed":
		Autotest.report("landing_crash", {"region": region.get("name", "")})
		Flow.go("surface", str(region.name))
