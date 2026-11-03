extends Node3D
## Demo mode: one simple page. Cards sit side by side, and a spinning hologram shows what is added.

const DESTINATIONS := [
	{"id": "mars", "region": "gale", "title": "Mars", "site": "Gale Crater"},
	{"id": "moon", "region": "shackleton", "title": "The Moon", "site": "Shackleton Crater"},
	{"id": "titan", "region": "titan_site", "title": "Titan", "site": "Huygens landing region"},
	{"id": "exo_trappist_1_e", "region": "", "title": "TRAPPIST-1 e", "site": "Another solar system"},
]
const KITS := [
	{"id": "scout", "title": "Scout", "desc": "A camera. Collects soil samples.", "items": ["camera"]},
	{"id": "geologist", "title": "Geologist", "desc": "Adds a spectrometer. Collects rocks too.", "items": ["camera", "spectrometer"]},
	{"id": "lab", "title": "Full lab", "desc": "Adds a drill. Collects everything.", "items": ["camera", "spectrometer", "drill"]},
]
const STEP_TITLES: Array[String] = ["Where are you going?", "Pick a rocket", "How will you land?", "What science will you bring?"]
const SPIN := 0.55

var step := 0
var _kit := "lab"
var _dest := 0
var _root: Control
var _title: Label
var _cards: HBoxContainer
var _summary: VBoxContainer
var _next: Button
var _back: Button
var _added: Label
var _added_time := 0.0
var _chips: Array[Label] = []
var _holo: Node3D
var _planet: MeshInstance3D
var _parts: Dictionary = {}
var _flashes: Array = []
var _ring: MeshInstance3D

func _ready() -> void:
	Game.new_mission()
	Game.mission.demo = true
	Sfx.music("music_space")
	var we := Space.make_space_env(self, 0.03)
	we.environment.background_energy_multiplier = 0.18
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.9, 21.0)
	cam.fov = 40.0
	add_child(cam)
	cam.look_at(Vector3(0, 1.9, 0), Vector3.UP)
	_holo = Node3D.new()
	_holo.position = Vector3(0, -0.2, 0)
	add_child(_holo)
	_build_base()
	_build_ui()
	_choose_destination(0, true)
	_show_step(0)

func _build_base() -> void:
	# Light-table the hologram stands on.
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 3.3
	t.outer_radius = 3.42
	t.rings = 64
	t.ring_segments = 8
	_ring.mesh = t
	_ring.material_override = Hologram.material()
	_ring.position = Vector3(0, -3.3, 0)
	add_child(_ring)
	for r: float in [2.2, 1.0]:
		var inner := MeshInstance3D.new()
		var ti := TorusMesh.new()
		ti.inner_radius = r
		ti.outer_radius = r + 0.05
		ti.rings = 64
		ti.ring_segments = 6
		inner.mesh = ti
		inner.material_override = Hologram.material()
		inner.position = Vector3(0, -3.3, 0)
		add_child(inner)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UI.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	_root.add_child(m)
	var col := UI.vbox(12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var top := UI.hbox(10)
	col.add_child(top)
	top.add_child(UI.button("Menu", func() -> void: Flow.go("menu")))
	_title = UI.label("", 34, UI.TEXT, "bold")
	top.add_child(_title)
	top.add_child(UI.spacer())
	for i in STEP_TITLES.size():
		var chip := UI.label("  %d  " % (i + 1), 18, UI.TEXT_DIM, "bold")
		top.add_child(chip)
		_chips.append(chip)
	var mid := UI.hbox()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mid)
	mid.add_child(UI.spacer())
	_summary = UI.vbox(7)
	var sp := UI.panel(_summary)
	sp.custom_minimum_size.x = 310.0
	sp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mid.add_child(sp)
	_added = UI.label("", 26, UI.AMBER, "bold")
	_added.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_added.modulate.a = 0.0
	col.add_child(_added)
	_cards = UI.hbox(14)
	_cards.custom_minimum_size.y = 210.0
	col.add_child(_cards)
	var bottom := UI.hbox(10)
	col.add_child(bottom)
	_back = UI.button("Back", func() -> void: _show_step(step - 1))
	_back.custom_minimum_size.x = 150.0
	bottom.add_child(_back)
	bottom.add_child(UI.spacer())
	_next = UI.button("Next", _on_next, true)
	_next.custom_minimum_size = Vector2(240, 54)
	bottom.add_child(_next)

func _on_next() -> void:
	if step < 3:
		_show_step(step + 1)
	else:
		launch()

func _show_step(i: int) -> void:
	step = i
	_title.text = STEP_TITLES[i]
	_back.visible = i > 0
	_next.text = "LAUNCH!" if i == 3 else "Next"
	for c in _chips.size():
		_chips[c].add_theme_color_override("font_color", UI.ACCENT if c == i else (UI.GOOD if c < i else UI.TEXT_DIM))
	_fill_cards()
	_update_hologram()
	_refresh_summary()
	_next.grab_focus.call_deferred()

func _clear_cards() -> void:
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()

## A big selectable card. Disabled cards say why.
func _card(title: String, lines: Array, selected: bool, on_press: Callable, reason: String = "") -> void:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 200)
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = reason != ""
	var edge := UI.AMBER if selected else UI.PANEL_LINE
	var bg := Color(0.09, 0.2, 0.3, 0.94) if selected else UI.PANEL_BG
	b.add_theme_stylebox_override("normal", UI.box(bg, edge, 14, 14, 3 if selected else 1))
	b.add_theme_stylebox_override("hover", UI.box(Color(0.12, 0.26, 0.38, 0.97), UI.ACCENT, 14, 14, 2))
	b.add_theme_stylebox_override("pressed", UI.box(bg, UI.AMBER, 14, 14, 3))
	b.add_theme_stylebox_override("disabled", UI.box(Color(0.04, 0.05, 0.08, 0.8), Color(0.3, 0.3, 0.35, 0.3), 14, 14))
	b.add_theme_stylebox_override("focus", UI.box(Color(0, 0, 0, 0), UI.ACCENT, 14, 14, 2))
	var v := UI.vbox(7)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16.0
	v.offset_top = 14.0
	v.offset_right = -16.0
	v.offset_bottom = -12.0
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.add_child(UI.label(title, 25, UI.TEXT if reason == "" else UI.TEXT_DIM, "bold"))
	for line: Variant in lines:
		var text: String = str(line)
		var l := UI.para(text, 16, UI.TEXT_DIM if reason != "" else UI.TEXT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	if reason != "":
		var r := UI.para(reason, 15, UI.BAD)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(r)
	if selected:
		var s := UI.label("Selected", 15, UI.AMBER, "bold")
		v.add_child(UI.spacer())
		v.add_child(s)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	b.pressed.connect(func() -> void: Sfx.play("click"))
	_cards.add_child(b)

func _fill_cards() -> void:
	_clear_cards()
	match step:
		0:
			for i in DESTINATIONS.size():
				var d: Dictionary = DESTINATIONS[i]
				var t := Data.body(d.id)
				var days := float(Orbital.plan(t).days)
				var idx := i
				_card(str(d.title), [str(d.site), "Gravity: %s" % HudCard.gravity_words(float(t.gravity)).split(":")[0], "Trip: %s" % Orbital.format_time(days), "Real NASA terrain" if _has_real_terrain(d) else "Imagined surface"], i == _dest, func() -> void: _choose_destination(idx))
		1:
			for l: Dictionary in Game.LAUNCHERS:
				var id: String = l.id
				var reason := "" if Game.can_design_with(id) else "Too small for this trip"
				_card(str(l.name), [str(l.desc), "Lifts %.0f tonnes" % float(l.lift_t), "Costs $%d million" % int(l.cost)], Game.mission.launcher == id, func() -> void: _choose_rocket(id), reason)
		2:
			var target := Game.target()
			for p: Dictionary in Game.LANDERS:
				if p.get("probe", false):
					continue
				var id: String = p.id
				var reason := ""
				if p.get("needs_atmo", false) and not Data.has_atmosphere(target):
					reason = "%s has too little air" % str(target.name)
				elif target.id == "venus" and id == "airbag":
					reason = "Would not survive"
				_card(str(p.name), [str(p.desc)], Game.mission.lander == id, func() -> void: _choose_lander(id), reason)
		3:
			for k: Dictionary in KITS:
				var id: String = k.id
				_card(str(k.title), [str(k.desc), "%d samples types" % (Array(k["items"]).size())], _kit == id, func() -> void: _choose_kit(id))

func _has_real_terrain(d: Dictionary) -> bool:
	var r: Variant = Data.regions.get(str(d.region))
	return r != null and r.get("real_elevation", false)

func _choose_destination(i: int, silent: bool = false) -> void:
	_dest = i
	var d: Dictionary = DESTINATIONS[i]
	Game.mission.target_id = d.id
	Game.mission.region_id = d.region
	var t := Game.target()
	Game.mission.launch_unix = maxf(Time.get_unix_time_from_system(), 1798761600.0)
	if t.kind != "exoplanet" and t.id != "moon" and t.id != "earth":
		var parent: String = t.id if t.kind == "planet" else str(t.parent)
		Game.mission.launch_unix = Orbital.best_window(parent, float(Game.mission.launch_unix), Orbital.synodic_days(parent) * 1.1)
	Game.mission.instruments = Array(_kit_items(), TYPE_STRING, "", null)
	Game.auto_design()
	Game.mission.instruments = _kit_items()
	_ensure_design()
	if not silent:
		_refresh_after_pick()
		_announce("Destination: %s" % str(d.title))

func _kit_items() -> Array:
	for k: Dictionary in KITS:
		if k.id == _kit:
			return (k["items"] as Array).duplicate()
	return []

## After any choice, make sure the mission can still fly, moving up a rocket if needed.
func _ensure_design() -> void:
	if Game.can_design_with(str(Game.mission.launcher)):
		Game.design_with(str(Game.mission.launcher))
		return
	for l: Dictionary in Game.LAUNCHERS:
		if Game.can_design_with(str(l.id)):
			Game.design_with(str(l.id))
			_announce("Upgraded to %s: this mission needs it" % str(l.name))
			return

func _choose_rocket(id: String) -> void:
	Game.design_with(id)
	_refresh_after_pick()
	_flash_part("rocket")
	_announce("Added: %s" % str(Game.launcher().name))

func _choose_lander(id: String) -> void:
	Game.mission.lander = id
	_ensure_design()
	_refresh_after_pick()
	_flash_part("lander")
	_announce("Added: %s" % str(Game.lander().name))

func _choose_kit(id: String) -> void:
	_kit = id
	Game.mission.instruments = _kit_items()
	_ensure_design()
	_refresh_after_pick()
	for item: String in Game.mission.instruments:
		_flash_part(item)
	_announce("Added: %s kit" % id.capitalize())

func _refresh_after_pick() -> void:
	_fill_cards()
	_update_hologram()
	_refresh_summary()

func _announce(text: String) -> void:
	_added.text = text
	_added.modulate.a = 1.0
	_added_time = 2.2

func _refresh_summary() -> void:
	for c in _summary.get_children():
		_summary.remove_child(c)
		c.queue_free()
	_summary.add_child(UI.eyebrow("Your mission"))
	var d: Dictionary = DESTINATIONS[_dest]
	_summary.add_child(UI.label(str(d.title), 24, UI.TEXT, "bold"))
	var g := UI.grid(2)
	UI.kv(g, "Rocket", str(Game.launcher().name) if step >= 1 else "not chosen")
	UI.kv(g, "Landing", str(Game.lander().name) if step >= 2 else "not chosen")
	UI.kv(g, "Science", _kit.capitalize() if step >= 3 else "not chosen")
	UI.kv(g, "Trip", Orbital.format_time(float(Game.dv_plan().days)))
	_summary.add_child(g)
	var left := Game.BUDGET_LIMIT - Game.cost()
	_summary.add_child(UI.para("Money left over adds to your score: $%s M" % UI.grouped(int(maxf(left, 0.0))), 14))

# ---- Hologram ----

func _flash_part(id: String) -> void:
	if _parts.has(id):
		_flashes.append({"mat": _parts[id], "t": 1.0})

func _add_part(id: String, model: Node3D, pos: Vector3, s: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ONE * s
	var mat: ShaderMaterial = Hologram.material()
	holder.add_child(model)
	Hologram.apply(model, mat)
	_holo.add_child(holder)
	_parts[id] = mat

func _update_hologram() -> void:
	for c in _holo.get_children():
		_holo.remove_child(c)
		c.queue_free()
	_parts.clear()
	var t := Game.target()
	if step == 0:
		var map: ImageTexture = Data.planet_texture(str(t.id))
		_planet = Hologram.globe(map, 3.2)
		_planet.position = Vector3(0, 0.9, 0)
		_holo.add_child(_planet)
		return
	_add_part("rocket", Models.rocket(str(Game.mission.launcher)), Vector3(0, -3.2, 0), 0.72)
	if step >= 2:
		_add_part("lander", Models.lander(false), Vector3(0, 4.55, 0), 0.32)
	if step >= 3:
		_add_part("rover", Hologram.rover_model(), Vector3(0, 6.1, 0), 0.36)
		var around := 0
		for item: String in Game.mission.instruments:
			var a := float(around) / 3.0 * TAU
			_add_part(item, Hologram.instrument_model(item), Vector3(cos(a) * 1.9, 6.0, sin(a) * 1.9), 0.75)
			around += 1
	for m: String in _parts:
		_flashes.append({"mat": _parts[m], "t": 0.7})

func _process(delta: float) -> void:
	_holo.rotation.y += delta * SPIN
	var i := _flashes.size() - 1
	while i >= 0:
		var f: Dictionary = _flashes[i]
		f.t = float(f.t) - delta * 1.1
		(f.mat as ShaderMaterial).set_shader_parameter("flash", maxf(float(f.t), 0.0))
		if float(f.t) <= 0.0:
			_flashes.remove_at(i)
		i -= 1
	if _added_time > 0.0:
		_added_time -= delta
		_added.modulate.a = clampf(_added_time, 0.0, 1.0)

func launch() -> void:
	Game.mission.phase = "launch"
	Sfx.play("stage")
	Flow.go("launch", "Launch Complex")

func auto_advance() -> void:
	for id: Dictionary in DESTINATIONS:
		if id.id == Autotest.target_id:
			_choose_destination(DESTINATIONS.find(id))
	for i in 4:
		_show_step(i)
		await get_tree().create_timer(1.3).timeout
		Autotest.report_shot("demo_step_%d" % i)
	launch()
