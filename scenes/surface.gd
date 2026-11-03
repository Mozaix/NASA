extends Node3D
## Surface exploration: drive to real points of interest, read the science, collect samples.

const REACH := 22.0
const COLLECT_TIME := 1.6

var world: Dictionary
var terrain: Node
var region: Dictionary
var target: Dictionary
var vehicle: Node3D
var cam: Camera3D
var pois: Array = []
var _yaw := 0.0
var _pitch := 0.32
var _cam_dist := 15.0
var _mouse_captured := false
var _hud_stats: Label
var _nav: Label
var _objectives: VBoxContainer
var _toast: Label
var _toast_time := 0.0
var _fact_panel: PanelContainer
var _fact_box: VBoxContainer
var _fact_time := 0.0
var _progress: ProgressBar
var _progress_label: Label
var _collect := 0.0
var _map_panel: PanelContainer
var _map_tex: TextureRect
var _map_dot: Control
var _pause: Control
var _done_panel: Control
var _rocks: MultiMeshInstance3D
var _rock_center := Vector3(INF, 0, INF)
var _rng := RandomNumberGenerator.new()
var _probe := false
var _hscale := 24.0
var _lander_pos := Vector3.ZERO
var _done_shown := false

func _ready() -> void:
	target = Game.target()
	Game.mission.phase = "surface"
	Sfx.music("music_surface")
	region = World.region_for(target)
	world = World.build(self, target, region)
	terrain = world.terrain
	_probe = not target.get("has_surface", false)
	_hscale = float(region.get("hscale", 24.0))
	var uv: Array = region.landing_uv
	var start: Vector3 = terrain.uv_to_world(float(uv[0]), float(uv[1]))
	if Game.mission.has("landing_pos"):
		var lp: Array = Game.mission.landing_pos
		start = Vector3(lp[0], terrain.height_at(lp[0], lp[1]), lp[1])
	var g := float(target.get("gravity") if target.get("gravity") != null else 9.8)
	var dust := Color(0.7, 0.55, 0.42)
	if terrain.get("color_image") != null and terrain.color_image != null:
		dust = terrain.color_image.get_pixel(terrain.color_image.get_width() / 2, terrain.color_image.get_height() / 2).lightened(0.15)
	if _probe:
		vehicle = ProbeCraft.new()
	else:
		vehicle = Rover.new()
		_lander_pos = start
		var lander := Models.lander(false)
		add_child(lander)
		lander.global_position = start
		_rocks = _build_rocks()
	add_child(vehicle)
	vehicle.global_position = start + Vector3(16, 0, 10)
	vehicle.setup(terrain, g, dust)
	vehicle.place(vehicle.global_position)
	vehicle.heading = 0.6
	_yaw = PI + vehicle.heading
	cam = Camera3D.new()
	cam.far = 30000.0
	cam.fov = 68.0
	add_child(cam)
	_build_pois()
	_build_hud()
	_set_capture(true)
	_refresh_objectives()
	_show_toast("Drive to the beacons. Gravity here is %.2f m/s²." % g, 6.0)
	if float(world.art.get("atmo_amt", 0.0)) > 0.2:
		Sfx.loop("wind", 0.28)

func _build_rocks() -> MultiMeshInstance3D:
	var mesh := _rock_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = Settings.rock_count()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-5000, -3000, -5000), Vector3(14000, 6000, 14000))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	mi.material_override = m
	add_child(mi)
	return mi

func _rock_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var cache := {}
	for i in verts.size():
		var key := verts[i].snapped(Vector3.ONE * 0.01)
		if not cache.has(key):
			cache[key] = rng.randf_range(0.72, 1.25)
		verts[i] *= Vector3(cache[key], cache[key] * 0.75, cache[key])
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _update_rocks(center: Vector3) -> void:
	if _rocks == null or center.distance_to(_rock_center) < 90.0:
		return
	_rock_center = center
	var mm := _rocks.multimesh
	var img: Image = terrain.color_image
	var iw := img.get_width()
	var ih := img.get_height()
	var range_m := 280.0
	var cell := range_m * 2.0 / sqrt(float(mm.instance_count))
	var cx := int(floor(center.x / cell))
	var cz := int(floor(center.z / cell))
	var side := int(sqrt(float(mm.instance_count)))
	var i := 0
	for z in side:
		for x in side:
			var gx := cx + x - side / 2
			var gz := cz + z - side / 2
			# Hash the cell so every rock is stable as the player drives around.
			_rng.seed = hash(Vector2i(gx, gz))
			var px := (float(gx) + _rng.randf()) * cell
			var pz := (float(gz) + _rng.randf()) * cell
			var s := pow(_rng.randf(), 5.0) * 2.4 + 0.08
			var py: float = terrain.height_at(px, pz)
			var xf := Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)).scaled(Vector3.ONE * s), Vector3(px, py + s * 0.2, pz))
			mm.set_instance_transform(i, xf)
			var col := img.get_pixel(clampi(int(px / terrain.world_m * iw), 0, iw - 1), clampi(int(pz / terrain.world_m * ih), 0, ih - 1))
			mm.set_instance_color(i, col.darkened(_rng.randf_range(0.0, 0.3)))
			i += 1
	mm.visible_instance_count = i

func _build_pois() -> void:
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beacon_mat.albedo_color = Color(0.2, 1.0, 0.75, 0.22)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(0.2, 1.0, 0.75)
	beacon_mat.emission_energy_multiplier = 1.4
	for src: Dictionary in region.pois:
		var pos: Vector3 = terrain.uv_to_world(float(src.u), float(src.v))
		if _probe:
			pos.y = 60.0 + float(pois.size()) * 40.0
		var root := Node3D.new()
		add_child(root)
		root.global_position = pos
		var pillar := Models.cyl(root, 0.45, 0.45, 500.0, Vector3(0, 250, 0), beacon_mat, 8)
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tag := Label3D.new()
		tag.text = str(src.name)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.0011
		tag.font = UI.font_bold()
		tag.font_size = 36
		tag.outline_size = 10
		tag.position = Vector3(0, 12, 0)
		root.add_child(tag)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.3, 0.95, 0.7)
		pm.emission_enabled = true
		pm.emission = Color(0.3, 0.95, 0.7)
		pm.emission_energy_multiplier = 1.5
		Models.ball(root, 0.35, Vector3(0, 0.35, 0), pm)
		pois.append({"src": src, "pos": pos, "root": root, "tag": tag, "pillar": pillar, "visited": false, "sampled": false})

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	# Left column: where you are and how real the ground is.
	var col := UI.vbox(5)
	var p := UI.panel(col, 14)
	p.custom_minimum_size.x = 340.0
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 18)
	root.add_child(p)
	col.add_child(UI.eyebrow(str(target.name)))
	col.add_child(UI.label(str(region.name), 19, UI.TEXT, "bold"))
	_hud_stats = UI.label("", 14, UI.TEXT, "mono")
	col.add_child(_hud_stats)
	var src_note: String = str(region.get("dem_label", ""))
	col.add_child(UI.para(("Real elevation: " if region.get("real_elevation", false) else "") + src_note, 12, UI.GOOD if region.get("real_elevation", false) else UI.AMBER))
	# Objectives
	var ov := UI.vbox(4)
	_objectives = ov
	var op := UI.panel(ov, 14)
	op.custom_minimum_size.x = 340.0
	op.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	op.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(op)
	# Navigation strip
	_nav = UI.label("", 18, UI.GOOD, "bold")
	_nav.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	_nav.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_nav)
	_toast = UI.label("", 18, UI.AMBER, "bold")
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 62)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_toast)
	# Fact card
	_fact_box = UI.vbox(6)
	_fact_panel = UI.panel(_fact_box, 18)
	_fact_panel.custom_minimum_size.x = 620.0
	_fact_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 30)
	_fact_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fact_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fact_panel.visible = false
	root.add_child(_fact_panel)
	# Collect progress
	var pv := UI.vbox(4)
	pv.custom_minimum_size.x = 340.0
	pv.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	pv.position.y += 110.0
	_progress_label = UI.label("", 15, UI.TEXT, "bold")
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(_progress_label)
	_progress = UI.bar(0, 1, UI.GOOD, 10.0)
	_progress.visible = false
	pv.add_child(_progress)
	root.add_child(pv)
	# Bottom-left controls
	var hint := UI.para("WASD drive   Mouse look   %s %s   %s collect   %s map   %s lights   Esc pause" % [Settings.key_name("thrust"), "thrusters" if _probe else "hop", Settings.key_name("interact"), Settings.key_name("map"), Settings.key_name("lights")], 13)
	hint.custom_minimum_size.x = 560.0
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 18)
	root.add_child(hint)
	# Map
	_map_tex = TextureRect.new()
	if region.get("id", "") != "":
		_map_tex.texture = Data.texture("res://data/regions/%s/minimap.jpgdata" % str(region.id), false)
	elif terrain.color_image != null:
		_map_tex.texture = ImageTexture.create_from_image(terrain.color_image)
	_map_tex.custom_minimum_size = Vector2(230, 230)
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_panel = UI.panel(_map_tex, 6)
	_map_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	_map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_map_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_map_panel)
	_map_dot = MapOverlay.new()
	(_map_dot as MapOverlay).owner_scene = self
	_map_dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_tex.add_child(_map_dot)
	_build_pause(root)
	_done_panel = Control.new()
	root.add_child(_done_panel)

class MapOverlay extends Control:
	var owner_scene: Node3D
	func _draw() -> void:
		var s := size
		var w: float = owner_scene.terrain.world_m
		for p: Dictionary in owner_scene.pois:
			var pt := Vector2(p.pos.x / w * s.x, p.pos.z / w * s.y)
			var col := UI.GOOD if p.sampled else (UI.ACCENT if p.visited else Color(1.0, 0.9, 0.3))
			draw_circle(pt, 5.0, col)
			draw_arc(pt, 7.0, 0.0, TAU, 16, Color.BLACK, 1.0)
		var v: Vector3 = owner_scene.vehicle.global_position
		var c := Vector2(v.x / w * s.x, v.z / w * s.y)
		var f: Vector3 = owner_scene.vehicle.forward_dir()
		var d := Vector2(f.x, f.z)
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([c + d * 9.0, c - d * 5.0 + n * 5.0, c - d * 5.0 - n * 5.0]), Color.WHITE)
	func _process(_d: float) -> void:
		queue_redraw()

func _build_pause(root: Control) -> void:
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0, 0, 0, 0.55)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause.visible = false
	root.add_child(_pause)
	var v := UI.vbox(10)
	var pan := UI.panel(v, 24)
	pan.custom_minimum_size.x = 440.0
	_pause.add_child(pan)
	pan.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	v.add_child(UI.heading("Paused", 30))
	v.add_child(UI.button("Resume", _toggle_pause, true))
	var q := UI.label("Graphics quality", 14, UI.TEXT_DIM)
	v.add_child(q)
	var opt := OptionButton.new()
	for n: String in Settings.QUALITY_NAMES:
		opt.add_item(n)
	opt.select(Settings.quality)
	opt.item_selected.connect(func(i: int) -> void:
		Settings.quality = i
		Settings.apply()
		Settings.save())
	v.add_child(opt)
	v.add_child(UI.label("Master volume", 14, UI.TEXT_DIM))
	var vol := HSlider.new()
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = Settings.master_vol
	vol.value_changed.connect(func(x: float) -> void:
		Settings.master_vol = x
		Settings.apply()
		Settings.save())
	v.add_child(vol)
	v.add_child(UI.button("End mission and go to debrief", end_mission))

func _toggle_pause() -> void:
	var now := not get_tree().paused
	get_tree().paused = now
	_pause.visible = now
	_set_capture(not now)
	Sfx.loop("rover", 0.0)

func _set_capture(on: bool) -> void:
	_mouse_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("map"):
		_map_panel.visible = not _map_panel.visible
	elif event.is_action_pressed("lights"):
		var on: bool = vehicle.toggle_lights()
		_show_toast("Headlights on" if on else "Headlights off", 1.5)
	elif event is InputEventMouseMotion and _mouse_captured:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0035 * Settings.mouse_sens
		var inv := -1.0 if Settings.invert_y else 1.0
		_pitch = clampf(_pitch + mm.relative.y * 0.0035 * Settings.mouse_sens * inv, -0.2, 1.2)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b := (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist * 0.9, 7.0, 60.0)
		elif b == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist * 1.1, 7.0, 60.0)

func _physics_process(delta: float) -> void:
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer := Input.get_axis("move_left", "move_right")
	var boost := Input.is_action_pressed("boost")
	var hop := Input.is_action_pressed("thrust") if _probe else Input.is_action_just_pressed("thrust")
	vehicle.tick(delta, throttle, steer, boost, hop)
	if _probe:
		Sfx.loop("engine", 0.25 if hop else 0.0)
	else:
		var sp := Vector2(vehicle.velocity.x, vehicle.velocity.z).length()
		Sfx.loop("rover", clampf(sp / 30.0, 0.0, 0.4), 0.7 + sp / 40.0)
		if vehicle.get_meta("hit_edge", false):
			_show_toast("Edge of the mapped region.", 1.5)
	_process_pois(delta)

func _process(delta: float) -> void:
	_yaw += Input.get_axis("cam_left", "cam_right") * delta * 1.6
	_pitch = clampf(_pitch + Input.get_axis("cam_up", "cam_down") * delta, -0.2, 1.2)
	var v := vehicle.global_position
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _cam_dist
	var pos := v + Vector3.UP * 2.0 + off
	pos.y = maxf(pos.y, float(terrain.height_at(pos.x, pos.z)) + 1.5)
	cam.global_position = pos
	cam.look_at(v + Vector3.UP * 2.2, Vector3.UP)
	terrain.update_lod(cam.global_position, delta)
	_update_rocks(v)
	_update_hud()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _fact_time > 0.0:
		_fact_time -= delta
		_fact_panel.modulate.a = clampf(_fact_time, 0.0, 1.0)
		if _fact_time <= 0.0:
			_fact_panel.visible = false

func _dist_real_km(world_dist: float) -> float:
	return world_dist * _hscale / 1000.0

func _update_hud() -> void:
	var v := vehicle.global_position
	var speed: float = Vector2(vehicle.velocity.x, vehicle.velocity.z).length()
	var txt := "Gravity    %.2f m/s²\nSpeed      %.0f m/s\n" % [float(target.get("gravity") if target.get("gravity") != null else 0.0), speed]
	if region.get("real_elevation", false):
		txt += "Elevation  %s m\n" % UI.grouped(int(terrain.real_elevation(v.x, v.z)))
	if _probe:
		txt += "Height     %.0f m\n" % v.y
	else:
		txt += "Map scale  1:%d, height ×%.1f\n" % [int(_hscale), float(region.get("vexag", 1.0))]
	txt += "Driven     %.1f km" % _dist_real_km(vehicle.distance)
	_hud_stats.text = txt
	var best: Variant = null
	var best_d := INF
	for p: Dictionary in pois:
		if p.sampled:
			continue
		var d := Vector2(p.pos.x - v.x, p.pos.z - v.z).length()
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		_nav.text = "All sites complete"
		return
	var f: Vector3 = vehicle.forward_dir()
	var to := Vector2(best.pos.x - v.x, best.pos.z - v.z).normalized()
	var ang: float = rad_to_deg(Vector2(f.x, f.z).angle_to(to))
	var arrow := "▲"
	if absf(ang) > 150.0:
		arrow = "▼"
	elif ang > 20.0:
		arrow = "►"
	elif ang < -20.0:
		arrow = "◄"
	_nav.text = "%s  %s   %.1f km" % [arrow, str(best.src.name), _dist_real_km(best_d)]

func _process_pois(delta: float) -> void:
	var v := vehicle.global_position
	var near: Variant = null
	for p: Dictionary in pois:
		var d := Vector2(p.pos.x - v.x, p.pos.z - v.z).length()
		var reach := REACH if not _probe else 34.0
		if d < reach and (not _probe or absf(p.pos.y - v.y) < 45.0):
			near = p
			if not p.visited:
				_visit(p)
	_progress.visible = false
	_progress_label.text = ""
	if near == null or near.sampled:
		_collect = 0.0
		return
	var kind: String = near.src.sample
	if _probe:
		kind = "gas"
	if not Game.can_collect(kind):
		_progress_label.text = "%s sample: this mission did not bring the instrument" % kind.capitalize()
		return
	_progress_label.text = "Hold %s to collect %s sample" % [Settings.key_name("interact"), kind]
	if Input.is_action_pressed("interact"):
		_collect += delta
		_progress.visible = true
		_progress.value = _collect / COLLECT_TIME
		if _collect >= COLLECT_TIME:
			_sample(near, kind)
	else:
		_collect = 0.0

func _visit(p: Dictionary) -> void:
	p.visited = true
	Sfx.play("chime")
	var bonus := 20.0
	if "camera" in Game.mission.instruments:
		bonus += 5.0
	Game.add_science(bonus)
	Game.mission.pois[str(p.src.name)] = true
	var fact: Dictionary = p.src.fact
	if not fact.text in Game.mission.facts_seen:
		Game.mission.facts_seen.append(fact.text)
	_show_fact(p)
	_refresh_objectives()

func _show_fact(p: Dictionary) -> void:
	for c in _fact_box.get_children():
		_fact_box.remove_child(c)
		c.queue_free()
	_fact_box.add_child(UI.eyebrow("Point of interest"))
	_fact_box.add_child(UI.heading(str(p.src.name), 24))
	_fact_box.add_child(UI.fact_block(p.src.fact, 17))
	if p.src.get("elev_m") != null:
		var note := UI.para("Measured here: %s m elevation, from %s." % [UI.grouped(int(p.src.elev_m)), str(region.get("dem_label", ""))], 14, UI.GOOD)
		_fact_box.add_child(note)
	_fact_panel.visible = true
	_fact_panel.modulate.a = 1.0
	_fact_time = 14.0

func _sample(p: Dictionary, kind: String) -> void:
	p.sampled = true
	_collect = 0.0
	Sfx.play("collect")
	var value := float(Game.SCI_VALUES.get(kind, 30.0))
	Game.add_science(value)
	Game.mission.samples.append({"poi": str(p.src.name), "type": kind})
	_show_toast("%s sample stored. +%d science" % [kind.capitalize(), int(value)], 3.0)
	(p.pillar as MeshInstance3D).visible = false
	_refresh_objectives()
	_check_done()

func _refresh_objectives() -> void:
	for c in _objectives.get_children():
		_objectives.remove_child(c)
		c.queue_free()
	_objectives.add_child(UI.eyebrow("Mission objectives"))
	for p: Dictionary in pois:
		var icon := "✓" if p.sampled else ("◐" if p.visited else "○")
		var kind: String = "gas" if _probe else p.src.sample
		var col := UI.GOOD if p.sampled else UI.TEXT
		if not Game.can_collect(kind):
			col = UI.TEXT_DIM
		var l := UI.para("%s  %s  (%s)" % [icon, str(p.src.name), kind], 14, col)
		_objectives.add_child(l)
	_objectives.add_child(UI.label("Science: %d" % int(Game.mission.science), 16, UI.AMBER, "mono"))

func _check_done() -> void:
	if _done_shown:
		return
	for p: Dictionary in pois:
		var kind: String = "gas" if _probe else p.src.sample
		if not p.sampled and Game.can_collect(kind):
			return
	_done_shown = true
	Game.add_science(60.0)
	_set_capture(false)
	var v := UI.vbox(10)
	var pan := UI.panel(v, 20)
	pan.custom_minimum_size.x = 420.0
	_done_panel.get_parent().add_child(pan)
	pan.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	pan.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	v.add_child(UI.heading("All samples collected", 24))
	v.add_child(UI.para("Completion bonus: +60 science. You can keep exploring, or end the mission now.", 15))
	var end := UI.button("End mission", end_mission, true)
	v.add_child(end)
	var keep := UI.button("Keep exploring", func() -> void:
		pan.queue_free()
		_set_capture(true))
	v.add_child(keep)

func _show_toast(text: String, seconds: float) -> void:
	_toast.text = text
	_toast_time = seconds
	_toast.modulate.a = 1.0

func end_mission() -> void:
	get_tree().paused = false
	Game.mission.distance_m = vehicle.distance * _hscale
	Sfx.stop_loops()
	Flow.go("debrief", "Mission Debrief")

# ---- Test hooks: move the vehicle exactly as driving would, then collect ----
func auto_visit_all() -> void:
	for p: Dictionary in pois:
		vehicle.place(p.pos + Vector3(4, 0, 3))
		if _probe:
			vehicle.global_position.y = p.pos.y
		await get_tree().physics_frame
		await get_tree().physics_frame
		var kind: String = "gas" if _probe else p.src.sample
		if Game.can_collect(kind) and not p.sampled:
			_sample(p, kind)

func auto_advance() -> void:
	end_mission()
