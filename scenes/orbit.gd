extends Node3D
## Orbit: survey the target for science, choose a landing site, begin descent.

const R := 10.0
var target: Dictionary
var planet: Node3D
var globe: Node3D
var cam: OrbitCamera
var scan := 0.0
var scanned := false
var _scan_bar: ProgressBar
var _status: Label
var _sites: Array = []
var _markers: Array[Node3D] = []
var _go: Button
var _sc: Node3D
var _sc_angle := 0.0
var _alt_km := 300.0
var _yaw_goal := 0.0
var _pitch_goal := 0.3
var _spin_on := true

func _ready() -> void:
	target = Game.target()
	Game.mission.phase = "orbit"
	Sfx.music("music_space")
	Space.make_space_env(self, 0.04)
	var sun := Vector3(0.8, 0.25, 0.55).normalized()
	var star_col := Data.star_color(target.get("st_teff")) if target.kind == "exoplanet" else Color(1, 0.97, 0.92)
	Space.make_sun_light(self, sun, star_col, 1.7)
	planet = Space.make_planet(target, R, sun)
	add_child(planet)
	globe = planet.get_node("Globe")
	if target.kind == "moon":
		var p: Dictionary = Data.body(target.parent)
		# Parent planet at a viewable, not true, distance.
		var ratio: float = float(p.radius_km) / maxf(float(target.radius_km), 1.0)
		var pr := minf(R * ratio * 0.35, 70.0)
		var parent := Space.make_planet(p, pr, sun, 64)
		parent.position = Vector3(-pr * 2.6, pr * 0.3, -pr * 3.4)
		add_child(parent)
	elif target.kind == "exoplanet":
		var star := Space.make_sun(self, 16.0, star_col)
		star.position = sun * 340.0
	_sc = Models.spacecraft(0.14)
	add_child(_sc)
	cam = OrbitCamera.new()
	cam.far = 5000.0
	cam.fov = 50.0
	cam.min_distance = 12.0
	cam.max_distance = 60.0
	cam.set_distance_now(28.0)
	add_child(cam)
	_alt_km = 300.0 if float(target.radius_km) > 800.0 else 60.0
	_sites = _landing_sites()
	_build_markers()
	_build_ui()

func _landing_sites() -> Array:
	if Game.is_probe_mission():
		return []
	return target.get("regions", [])

func _build_markers() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = UI.GOOD
	for s: Dictionary in _sites:
		var holder := Node3D.new()
		globe.add_child(holder)
		var n := Space.latlon_to_unit(float(s.lat), float(s.lon))
		holder.position = n * R * 1.005
		Models.ball(holder, 0.11, Vector3.ZERO, m)
		var tag := Label3D.new()
		tag.text = str(s.name)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.fixed_size = true
		tag.pixel_size = 0.0009
		tag.font = UI.font_bold()
		tag.font_size = 28
		tag.outline_size = 8
		tag.position = n * 0.5
		holder.add_child(tag)
		_markers.append(holder)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	layer.add_child(root)
	# The facts scroll; the landing-site picker and the descent button stay pinned at the bottom,
	# so a tall panel (Mars has the longest atmosphere entry) can never push them off a laptop screen.
	var outer := UI.vbox(10)
	var pan := UI.panel(outer)
	pan.custom_minimum_size.x = 420.0
	pan.anchor_left = 0.0
	pan.anchor_top = 0.0
	pan.anchor_bottom = 1.0
	pan.offset_left = 20.0
	pan.offset_top = 20.0
	pan.offset_bottom = -20.0
	pan.offset_right = 440.0
	root.add_child(pan)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var v := UI.vbox(9)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	outer.add_child(HSeparator.new())
	var bottom := UI.vbox(9)
	outer.add_child(bottom)
	v.add_child(UI.eyebrow("In orbit"))
	v.add_child(UI.heading(str(target.name), 34))
	var mu := Orbital.mu_of(target)
	var r := Orbital.radius_m(target) + _alt_km * 1000.0
	var speed := sqrt(mu / r)
	var period := TAU * r / speed / 60.0
	var orbit_g := UI.grid(2)
	UI.kv(orbit_g, "Orbit altitude", "%.0f km" % _alt_km)
	UI.kv(orbit_g, "Orbital speed", "%.2f km/s (derived)" % (speed / 1000.0))
	UI.kv(orbit_g, "Orbital period", "%.0f minutes (derived)" % period)
	v.add_child(orbit_g)
	v.add_child(HSeparator.new())
	v.add_child(UI.stats_grid(target))
	v.add_child(HSeparator.new())
	var facts: Array = target.get("facts", [])
	if not facts.is_empty():
		v.add_child(UI.fact_block(facts[randi() % facts.size()], 15))
	bottom.add_child(UI.eyebrow("Orbital survey"))
	_status = UI.para("Hold %s to scan from orbit and earn science." % Settings.key_name("interact"), 15, UI.TEXT)
	bottom.add_child(_status)
	_scan_bar = UI.bar(0, 1, UI.ACCENT, 10.0)
	bottom.add_child(_scan_bar)
	if _sites.size() > 0:
		bottom.add_child(UI.eyebrow("Landing site"))
		var opt := OptionButton.new()
		var selected := 0
		for i in _sites.size():
			opt.add_item(str(_sites[i].name))
			if _sites[i].id == Game.mission.region_id:
				selected = i
		opt.select(selected)
		opt.item_selected.connect(_select_site)
		bottom.add_child(opt)
		_select_site(selected)
	var label := "Begin descent"
	if Game.is_probe_mission():
		label = "Release the atmospheric probe"
	_go = UI.button(label, begin_descent, true)
	_go.custom_minimum_size.y = 50.0
	bottom.add_child(_go)
	_go.grab_focus.call_deferred()
	if target.get("map_credit") != null:
		v.add_child(UI.para("Map: " + str(target.map_credit), 12))
	elif target.kind == "exoplanet":
		v.add_child(UI.para("Appearance is interpreted from archive data: nobody has imaged this surface.", 12, UI.AMBER))
	var hint := UI.label("Drag to look around, scroll to zoom", 13, UI.TEXT_DIM)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(hint)

func _select_site(i: int) -> void:
	Game.mission.region_id = _sites[i].id
	_spin_on = false
	# Turn the globe so the chosen site faces the camera.
	var lon := float(_sites[i].lon)
	var u := (lon + 180.0) / 360.0
	var tw := create_tween()
	tw.tween_property(globe, "rotation:y", wrapf(-u * TAU + 0.25, -PI, PI), 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cam.yaw = 0.25 - deg_to_rad(float(target.get("obliquity_deg") if target.get("obliquity_deg") != null else 0.0)) * 0.0
	cam.pitch = clampf(deg_to_rad(float(_sites[i].lat)), -1.3, 1.3)

func _process(delta: float) -> void:
	if _spin_on:
		globe.rotation.y += Space.spin_rate(target, 400.0) * delta
	_sc_angle += delta * 0.35
	_sc.position = Vector3(cos(_sc_angle), 0.25 * sin(_sc_angle), sin(_sc_angle)) * (R * 1.2)
	_sc.look_at(_sc.position + Vector3(-sin(_sc_angle), 0, cos(_sc_angle)), Vector3.UP)
	if not scanned:
		if Input.is_action_pressed("interact"):
			scan = minf(scan + delta / 4.5, 1.0)
			_scan_bar.value = scan
			if scan >= 1.0:
				_finish_scan()

func _finish_scan() -> void:
	scanned = true
	var pts := 40.0
	if "camera" in Game.mission.instruments:
		pts += 15.0
	if "spectrometer" in Game.mission.instruments:
		pts += 15.0
	Game.mission.orbit_science = pts
	Game.add_science(pts)
	Sfx.play("collect")
	_status.text = "Survey complete: +%d science." % int(pts)
	_status.add_theme_color_override("font_color", UI.GOOD)

func begin_descent() -> void:
	Sfx.play("stage")
	if Game.is_probe_mission():
		Game.mission.landed = false
		Game.mission.phase = "surface"
		Flow.go("surface", "Entering the atmosphere of " + str(target.name))
	else:
		Game.mission.phase = "landing"
		Flow.go("landing", str(World.region_for(target).name))

func auto_advance() -> void:
	_finish_scan()
	await get_tree().create_timer(0.3).timeout
	begin_descent()
