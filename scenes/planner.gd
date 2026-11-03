extends Node3D
## Mission Planner: destination, spacecraft, launch window, review.

const STEPS: Array[String] = ["1  Destination", "2  Spacecraft", "3  Launch Window", "4  Review"]

var _step := 0
var _root: Control
var _content: VBoxContainer
var _side: VBoxContainer
var _tabs: Array[Button] = []
var _budget_bar: ProgressBar
var _budget_label: Label
var _mass_bar: ProgressBar
var _mass_label: Label
var _dv_bar: ProgressBar
var _dv_label: Label
var _power_label: Label
var _next: Button
var _planet_holder: Node3D
var _globe: Node3D
var _sun_dir := Vector3(0.75, 0.3, 0.6)
var _list_tab := 0
var _start_unix := 0.0

func _ready() -> void:
	Sfx.music("music_space")
	Space.make_space_env(self)
	Space.make_sun_light(self, _sun_dir)
	_planet_holder = Node3D.new()
	add_child(_planet_holder)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 26)
	cam.fov = 36.0
	cam.h_offset = -1.4
	add_child(cam)
	_start_unix = maxf(Time.get_unix_time_from_system(), 1798761600.0)  # no earlier than 2027-01-01
	_build_shell()
	_select_target(Game.mission.target_id, true)
	_show_step(0)

func _process(delta: float) -> void:
	if is_instance_valid(_globe):
		_globe.rotation.y += delta * 0.09

func _build_shell() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UI.theme()
	layer.add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_root.add_child(margin)
	var outer := UI.vbox(12)
	margin.add_child(outer)
	var top := UI.hbox(8)
	outer.add_child(top)
	var back := UI.button("Menu", func() -> void: Flow.go("menu"))
	top.add_child(back)
	var title := UI.label("  MISSION PLANNER", 20, UI.TEXT, "bold")
	top.add_child(title)
	top.add_child(UI.spacer())
	for i in STEPS.size():
		var idx := i
		var b := UI.button(STEPS[i], func() -> void: _show_step(idx))
		b.toggle_mode = true
		top.add_child(b)
		_tabs.append(b)
	var mid := UI.hbox(14)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(mid)
	var left := UI.panel()
	left.custom_minimum_size.x = 590.0
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_content = UI.vbox(10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	mid.add_child(UI.spacer())
	var right := UI.panel()
	right.custom_minimum_size.x = 430.0
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(right)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(side_scroll)
	_side = UI.vbox(10)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(_side)
	outer.add_child(_build_footer())

func _meter(row: HBoxContainer, name_text: String) -> Array:
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UI.hbox()
	head.add_child(UI.label(name_text, 13, UI.TEXT_DIM))
	head.add_child(UI.spacer())
	var val := UI.label("", 13, UI.TEXT, "mono")
	head.add_child(val)
	v.add_child(head)
	var bar := UI.bar(0, 1, UI.ACCENT, 8.0)
	v.add_child(bar)
	row.add_child(v)
	return [bar, val]

func _build_footer() -> Control:
	var p := UI.panel(null, 12)
	var row := UI.hbox(22)
	p.add_child(row)
	var m := _meter(row, "BUDGET")
	_budget_bar = m[0]
	_budget_label = m[1]
	m = _meter(row, "LAUNCH MASS")
	_mass_bar = m[0]
	_mass_label = m[1]
	m = _meter(row, "DELTA-V (HAVE / NEED)")
	_dv_bar = m[0]
	_dv_label = m[1]
	var pv := UI.vbox(4)
	pv.add_child(UI.label("POWER", 13, UI.TEXT_DIM))
	_power_label = UI.label("", 13, UI.TEXT, "mono")
	pv.add_child(_power_label)
	row.add_child(pv)
	_next = UI.button("Next", _on_next, true)
	_next.custom_minimum_size.x = 170.0
	row.add_child(_next)
	return p

func _clear(c: Control) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()

func _show_step(i: int) -> void:
	_step = i
	for t in _tabs.size():
		_tabs[t].button_pressed = t == i
	_clear(_content)
	match i:
		0: _build_destination()
		1: _build_spacecraft()
		2: _build_window()
		3: _build_review()
	_refresh()

func _refresh() -> void:
	var cost := Game.cost()
	_budget_bar.max_value = Game.BUDGET_LIMIT
	_budget_bar.value = minf(cost, Game.BUDGET_LIMIT)
	_budget_label.text = "$%s M / $%s M" % [UI.grouped(int(cost)), UI.grouped(int(Game.BUDGET_LIMIT))]
	_budget_label.add_theme_color_override("font_color", UI.BAD if cost > Game.BUDGET_LIMIT else UI.TEXT)
	var lift := float(Game.launcher().lift_t)
	_mass_bar.max_value = lift
	_mass_bar.value = minf(Game.total_mass(), lift)
	_mass_label.text = "%.1f t / %.0f t" % [Game.total_mass(), lift]
	_mass_label.add_theme_color_override("font_color", UI.BAD if Game.total_mass() > lift else UI.TEXT)
	var plan := Game.dv_plan()
	if plan.kind == "interstellar":
		_dv_label.text = "sail: no propellant"
		_dv_bar.max_value = 1.0
		_dv_bar.value = 1.0
		_dv_label.add_theme_color_override("font_color", UI.TEXT)
	else:
		var have := Game.dv_have()
		var need := float(plan.total)
		_dv_bar.max_value = maxf(need * 1.5, 1.0)
		_dv_bar.value = have
		_dv_label.text = "%.2f / %.2f km/s" % [have / 1000.0, need / 1000.0]
		_dv_label.add_theme_color_override("font_color", UI.BAD if have < need else UI.GOOD)
	var pa := Game.power_available()
	var pn := Game.power_needed()
	_power_label.text = "%.0f / %.0f W" % [pa, pn]
	_power_label.add_theme_color_override("font_color", UI.BAD if pa < pn else UI.GOOD)
	_next.text = "LAUNCH" if _step == 3 else "Next"
	_next.disabled = _step == 3 and not Game.problems().is_empty()
	_build_side()

func _on_next() -> void:
	if _step < 3:
		_show_step(_step + 1)
	else:
		launch()

func launch() -> void:
	if not Game.problems().is_empty():
		return
	Sfx.play("stage")
	Game.mission.phase = "launch"
	Flow.go("launch", "Launch Complex")

func _select_target(id: String, keep_design: bool = false) -> void:
	Game.mission.target_id = id
	var t := Game.target()
	var regs: Array = t.get("regions", [])
	var keep_region := false
	for r: Dictionary in regs:
		if r.id == Game.mission.region_id:
			keep_region = true
	if not keep_region:
		Game.mission.region_id = regs[0].id if not regs.is_empty() else ""
	if t.kind != "exoplanet" and id != "earth" and id != "moon":
		var parent: String = id if t.kind == "planet" else str(t.parent)
		Game.mission.launch_unix = Orbital.best_window(parent, _start_unix, Orbital.synodic_days(parent) * 1.1)
	else:
		Game.mission.launch_unix = _start_unix
	if not keep_design:
		Game.auto_design()
	for c in _planet_holder.get_children():
		c.queue_free()
	var radius := 6.6
	var planet := Space.make_planet(t, radius, _sun_dir)
	_planet_holder.add_child(planet)
	_globe = planet.get_node("Globe")
	_planet_holder.position = Vector3(-2.6, 0.0, 0.0)

# ---- Step 1 ----

func _build_destination() -> void:
	_content.add_child(UI.heading("Choose a destination"))
	_content.add_child(UI.para("Every number below comes from NASA data. Each target changes how hard the mission is to design."))
	var tabs := UI.hbox(6)
	_content.add_child(tabs)
	var names: Array[String] = ["Planets", "Moons", "Exoplanets"]
	for i in names.size():
		var idx := i
		var b := UI.button(names[i], func() -> void:
			_list_tab = idx
			_show_step(0))
		b.toggle_mode = true
		b.button_pressed = i == _list_tab
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	var kinds: Array[String] = ["planet", "moon", "exoplanet"]
	var g := GridContainer.new()
	g.columns = 2 if _list_tab < 2 else 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(g)
	for t: Dictionary in Data.targets():
		if t.kind != kinds[_list_tab]:
			continue
		var id: String = t.id
		var label_text: String = t.name
		if t.kind == "exoplanet":
			label_text = "%s   %.0f ly" % [t.name, float(t.sy_dist) * Orbital.PC_TO_LY]
		elif t.kind == "moon":
			label_text = "%s   (%s)" % [t.name, str(Data.body(t.parent).name)]
		var b := UI.button(label_text, func() -> void:
			_select_target(id)
			_show_step(0))
		b.toggle_mode = true
		b.button_pressed = id == Game.mission.target_id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		g.add_child(b)
	var regs: Array = Game.target().get("regions", [])
	if regs.size() > 1:
		_content.add_child(UI.eyebrow("Landing region"))
		var opt := OptionButton.new()
		for r: Dictionary in regs:
			opt.add_item(r.name)
			if r.id == Game.mission.region_id:
				opt.select(opt.item_count - 1)
		opt.item_selected.connect(func(i: int) -> void:
			Game.mission.region_id = regs[i].id
			_refresh())
		_content.add_child(opt)

# ---- Step 2 ----

func _option_row(title: String, list: Array, key: String) -> void:
	_content.add_child(UI.eyebrow(title))
	var opt := OptionButton.new()
	var valid: Array = []
	for p: Dictionary in list:
		if p.get("exo_only", false) and Game.target().kind != "exoplanet":
			continue
		valid.append(p)
		opt.add_item("%s  ($%d M)" % [p.name, int(p.cost)])
		if p.id == Game.mission[key]:
			opt.select(opt.item_count - 1)
	_content.add_child(opt)
	var desc := UI.para(str(Game.part(list, Game.mission[key]).get("desc", "")), 14)
	_content.add_child(desc)
	opt.item_selected.connect(func(i: int) -> void:
		Game.mission[key] = valid[i].id
		desc.text = str(valid[i].desc)
		_refresh())

func _build_spacecraft() -> void:
	_content.add_child(UI.heading("Design the spacecraft"))
	_content.add_child(UI.para("Costs, masses and engine numbers are game values. Delta-v is computed with the real rocket equation."))
	var auto := UI.button("Auto-design the cheapest working mission", func() -> void:
		Game.auto_design()
		_show_step(1))
	_content.add_child(auto)
	_option_row("Launch vehicle", Game.LAUNCHERS, "launcher")
	_option_row("Transfer stage", Game.STAGES, "stage")
	_content.add_child(UI.eyebrow("Propellant"))
	var row := UI.hbox()
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 125.0
	s.step = 0.5
	s.value = float(Game.mission.propellant_t)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.label("%.1f t" % float(Game.mission.propellant_t), 15, UI.TEXT, "mono")
	s.value_changed.connect(func(val: float) -> void:
		Game.mission.propellant_t = val
		v.text = "%.1f t" % val
		_refresh())
	row.add_child(s)
	row.add_child(v)
	_content.add_child(row)
	_option_row("Arrival system", Game.LANDERS, "lander")
	_option_row("Power", Game.POWERS, "power")
	_content.add_child(UI.eyebrow("Payload"))
	if not Game.is_probe_mission():
		var rv := CheckBox.new()
		rv.text = "%s  ($%d M, %.1f t)" % [Game.ROVER.name, int(Game.ROVER.cost), float(Game.ROVER.mass_t)]
		rv.button_pressed = Game.mission.rover
		rv.toggled.connect(func(on: bool) -> void:
			Game.mission.rover = on
			_refresh())
		_content.add_child(rv)
	for inst: Dictionary in Game.INSTRUMENTS:
		var id: String = inst.id
		var cb := CheckBox.new()
		cb.text = "%s  ($%d M, %.0f W). %s" % [inst.name, int(inst.cost), float(inst.watts), inst.desc]
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.button_pressed = id in Game.mission.instruments
		cb.toggled.connect(func(on: bool) -> void:
			var list: Array = Game.mission.instruments
			if on and not id in list:
				list.append(id)
			elif not on:
				list.erase(id)
			_refresh())
		_content.add_child(cb)

# ---- Step 3 ----

func _build_window() -> void:
	var t := Game.target()
	_content.add_child(UI.heading("Pick a launch window"))
	var plan := Orbital.plan(t)
	if plan.kind != "hohmann":
		match plan.kind:
			"interstellar":
				_content.add_child(UI.para("Between stars there is no transfer window: the distance dwarfs any planetary alignment. The stars are simply very far away."))
				var g := UI.grid(2)
				UI.kv(g, "Distance", "%.1f light-years" % float(plan.light_years))
				UI.kv(g, "At Voyager 1's speed (about 17 km/s)", Orbital.format_time(float(plan.voyager_years) * 365.25))
				UI.kv(g, "Concept sail at 20% of light speed", Orbital.format_time(float(plan.days)))
				_content.add_child(g)
				_content.add_child(UI.para("The 20% figure is a game assumption, taken from concept studies. No such spacecraft exists today.", 14, UI.AMBER))
			"lunar":
				_content.add_child(UI.para("Lunar windows open about every month. The Hohmann transfer from low Earth orbit takes %s." % Orbital.format_time(float(plan.days))))
			_:
				_content.add_child(UI.para("Orbiting Earth does not need a planetary window. Launch when ready."))
		return
	var parent: String = t.id if t.kind == "planet" else str(t.parent)
	_content.add_child(UI.para("A Hohmann transfer only works when %s is ahead of Earth by the right angle. Launching off-window costs extra delta-v. Planet positions come from JPL's published orbital elements." % Data.body(parent).name))
	var syn := Orbital.synodic_days(parent)
	var horizon := syn * 3.2
	var chart := WindowChart.new()
	chart.custom_minimum_size = Vector2(0, 170)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.setup(parent, _start_unix, horizon)
	_content.add_child(chart)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = horizon
	slider.step = 1.0
	slider.value = clampf((float(Game.mission.launch_unix) - _start_unix) / 86400.0, 0.0, horizon)
	_content.add_child(slider)
	var info := UI.grid(2)
	_content.add_child(info)
	var rebuild := func() -> void:
		_clear(info)
		var u := float(Game.mission.launch_unix)
		var f := Orbital.window_factor(parent, u)
		var days := float(Game.dv_plan().days)
		UI.kv(info, "Launch date", Orbital.date_string(u))
		UI.kv(info, "Arrival date", Orbital.date_string(u + days * 86400.0))
		UI.kv(info, "Travel time", Orbital.format_time(days))
		UI.kv(info, "Phase error", "%.0f°" % abs(Orbital.phase_error(parent, u)))
		UI.kv(info, "Delta-v penalty", "+%.0f%%" % ((f - 1.0) * 100.0), UI.GOOD if f < 1.03 else (UI.AMBER if f < 1.2 else UI.BAD))
		UI.kv(info, "Windows repeat every", "%.0f days (synodic period)" % syn)
		chart.marker = u
		chart.queue_redraw()
	rebuild.call()
	slider.value_changed.connect(func(v: float) -> void:
		Game.mission.launch_unix = _start_unix + v * 86400.0
		rebuild.call()
		_refresh())
	_content.add_child(UI.button("Jump to the best window", func() -> void:
		Game.mission.launch_unix = Orbital.best_window(parent, _start_unix, horizon)
		slider.value = (float(Game.mission.launch_unix) - _start_unix) / 86400.0))
	_content.add_child(UI.para("The penalty curve is a simplified model of real launch-window charts.", 13))

class WindowChart extends Control:
	var parent_id := ""
	var start := 0.0
	var horizon := 0.0
	var marker := 0.0
	var _rows: Array = []
	func setup(p: String, s: float, h: float) -> void:
		parent_id = p
		start = s
		horizon = h
		_rows = Orbital.window_table(p, s, 180, h / 180.0)
	func _draw() -> void:
		var w := size.x
		var h := size.y - 22.0
		draw_rect(Rect2(0, 0, w, h), Color(0.06, 0.09, 0.14, 0.9))
		var bw := w / float(_rows.size())
		for i in _rows.size():
			var f: float = _rows[i].factor
			var q := 1.0 - clampf((f - 1.0) / 0.9, 0.0, 1.0)
			var col := UI.BAD.lerp(UI.GOOD, pow(q, 2.0))
			var bh := h * pow(q, 1.6)
			draw_rect(Rect2(float(i) * bw, h - bh, bw + 0.5, bh), col)
		var font := UI.font_mono()
		var y0 := Time.get_datetime_dict_from_unix_time(int(start)).year as int
		var y1 := Time.get_datetime_dict_from_unix_time(int(start + horizon * 86400.0)).year as int
		for y in range(y0 + 1, y1 + 1):
			var u := Time.get_unix_time_from_datetime_string("%04d-01-01T00:00:00" % y)
			var x := (float(u) - start) / (horizon * 86400.0) * w
			draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.18))
			draw_string(font, Vector2(x + 3, h + 16), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.TEXT_DIM)
		var mx := (marker - start) / (horizon * 86400.0) * w
		draw_line(Vector2(mx, 0), Vector2(mx, h), Color.WHITE, 2.0)

# ---- Step 4 ----

func _build_review() -> void:
	var t := Game.target()
	_content.add_child(UI.heading("Mission review"))
	var g := UI.grid(2)
	_content.add_child(g)
	UI.kv(g, "Destination", str(t.name))
	if not Game.is_probe_mission():
		UI.kv(g, "Landing site", str(World.region_for(t).name))
	UI.kv(g, "Launcher", str(Game.launcher().name))
	UI.kv(g, "Transfer stage", str(Game.stage().name))
	UI.kv(g, "Arrival system", str(Game.lander().name))
	UI.kv(g, "Power", str(Game.power().name))
	var names := PackedStringArray()
	for id: String in Game.mission.instruments:
		names.append(str(Game.part(Game.INSTRUMENTS, id).name))
	UI.kv(g, "Instruments", ", ".join(names) if not names.is_empty() else "none")
	var plan := Game.dv_plan()
	UI.kv(g, "Launch date", Orbital.date_string(float(Game.mission.launch_unix)))
	UI.kv(g, "Travel time", Orbital.format_time(float(plan.days)))
	var problems := Game.problems()
	_content.add_child(UI.eyebrow("Flight readiness"))
	if problems.is_empty():
		_content.add_child(UI.label("All systems go.", 20, UI.GOOD, "bold"))
		var left := Game.BUDGET_LIMIT - Game.cost()
		_content.add_child(UI.para("$%s M unspent, which counts toward your score." % UI.grouped(int(left))))
	else:
		for p: String in problems:
			_content.add_child(UI.para("• " + p, 16, UI.BAD))
		_content.add_child(UI.button("Fix automatically with Auto-design", func() -> void:
			Game.auto_design()
			_show_step(3)))
	_content.add_child(UI.eyebrow("Samples this payload can collect"))
	var samples := PackedStringArray()
	for s: String in Game.SCI_VALUES:
		if Game.can_collect(s):
			samples.append(s)
	_content.add_child(UI.para(", ".join(samples)))

# ---- Right column: facts and delta-v ----

func _build_side() -> void:
	_clear(_side)
	var t := Game.target()
	_side.add_child(UI.eyebrow(str(t.kind)))
	_side.add_child(UI.heading(str(t.name), 30))
	_side.add_child(UI.stats_grid(t))
	var plan := Game.dv_plan()
	_side.add_child(HSeparator.new())
	_side.add_child(UI.eyebrow("Trajectory estimate"))
	var g := UI.grid(2)
	if plan.kind == "interstellar":
		UI.kv(g, "Travel (concept sail)", Orbital.format_time(float(plan.days)))
		UI.kv(g, "At Voyager 1's speed", Orbital.format_time(float(plan.voyager_years) * 365.25))
	else:
		UI.kv(g, "Departure burn", "%.2f km/s" % (float(plan.departure) / 1000.0))
		UI.kv(g, "Capture burn", "%.2f km/s" % (float(plan.capture) / 1000.0))
		UI.kv(g, "Descent", "%.2f km/s" % (float(plan.descent) / 1000.0))
		UI.kv(g, "Total", "%.2f km/s" % (float(plan.total) / 1000.0), UI.ACCENT)
		UI.kv(g, "Travel time", Orbital.format_time(float(plan.days)))
		if float(plan.get("window_factor", 1.0)) > 1.005:
			UI.kv(g, "Off-window penalty", "+%.0f%%" % ((float(plan.window_factor) - 1.0) * 100.0), UI.AMBER)
	_side.add_child(g)
	var facts: Array = t.get("facts", [])
	if not facts.is_empty():
		_side.add_child(HSeparator.new())
		_side.add_child(UI.eyebrow("From NASA"))
		_side.add_child(UI.fact_block(facts[hash(str(t.id)) % facts.size()], 15))
	if t.kind == "exoplanet":
		_side.add_child(UI.para("The surface and colours you will see are interpreted from these archive values. Nobody has seen this world up close.", 13, UI.AMBER))
	if not t.get("has_map", false) and t.kind != "exoplanet":
		_side.add_child(UI.para("No suitable global map is bundled for this world, so its globe is procedural.", 13, UI.AMBER))
	var credit := str(t.get("map_credit", ""))
	if credit != "":
		_side.add_child(UI.para("Map: " + credit, 12))
	_side.add_child(UI.para("Data: " + UI.short_url(str(t.get("source_url", ""))), 12, UI.ACCENT))

func auto_advance() -> void:
	var target_id := Autotest.target_id
	if target_id != "":
		_select_target(target_id)
		if Autotest.region_id != "":
			Game.mission.region_id = Autotest.region_id
	_show_step(3)
	await get_tree().process_frame
	if not Game.problems().is_empty():
		Autotest.report("planner_problems", Game.problems())
	launch()
