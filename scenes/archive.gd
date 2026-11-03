extends Node3D
## Browse every world, every fact card and every source without flying a mission.

var _detail: VBoxContainer
var _list: VBoxContainer
var _holder: Node3D
var _globe: Node3D
var _kind := "planet"
var _sun := Vector3(0.7, 0.3, 0.6)

func _ready() -> void:
	Sfx.music("music_space")
	Space.make_space_env(self)
	Space.make_sun_light(self, _sun)
	_holder = Node3D.new()
	add_child(_holder)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 26)
	cam.fov = 38.0
	add_child(cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	layer.add_child(root)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	root.add_child(m)
	var row := UI.hbox(14)
	m.add_child(row)
	var left := UI.vbox(8)
	var lp := UI.panel(left)
	lp.custom_minimum_size.x = 300.0
	row.add_child(lp)
	var back := UI.button("Back to menu", func() -> void: Flow.go("menu"))
	left.add_child(back)
	left.add_child(UI.heading("Mission Archive"))
	var tabs := UI.hbox(4)
	left.add_child(tabs)
	for pair: Array in [["Planets", "planet"], ["Moons", "moon"], ["Exoplanets", "exoplanet"]]:
		var kind: String = pair[1]
		var b := UI.button(pair[0], func() -> void:
			_kind = kind
			_fill_list())
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = UI.vbox(5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	row.add_child(UI.spacer())
	var dp := UI.panel()
	dp.custom_minimum_size.x = 620.0
	row.add_child(dp)
	var ds := ScrollContainer.new()
	ds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dp.add_child(ds)
	_detail = UI.vbox(10)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.add_child(_detail)
	_fill_list()
	_show("mars")
	back.grab_focus.call_deferred()

func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for t: Dictionary in Data.targets():
		if t.kind != _kind:
			continue
		var id: String = t.id
		var b := UI.button(str(t.name), func() -> void: _show(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size.y = 34.0
		_list.add_child(b)

func _show(id: String) -> void:
	var t := Data.body(id)
	for c in _detail.get_children():
		c.queue_free()
	_detail.add_child(UI.eyebrow(str(t.kind)))
	_detail.add_child(UI.heading(str(t.name), 34))
	_detail.add_child(UI.stats_grid(t))
	_detail.add_child(HSeparator.new())
	_detail.add_child(UI.eyebrow("From NASA"))
	for f: Dictionary in t.get("facts", []):
		_detail.add_child(UI.fact_block(f, 15))
	var regs: Array = t.get("regions", [])
	if not regs.is_empty():
		_detail.add_child(HSeparator.new())
		_detail.add_child(UI.eyebrow("Explorable regions"))
		for r: Dictionary in regs:
			_detail.add_child(UI.label(str(r.name), 18, UI.TEXT, "bold"))
			_detail.add_child(UI.para("%s. %s." % [str(r.dem_label), str(r.color_label)], 13))
			for p: Dictionary in r.pois:
				var coords := ""
				if p.get("lat") != null:
					coords = "  (%.2f°, %.2f°)" % [float(p.lat), float(p.lon)]
				_detail.add_child(UI.label("%s%s" % [str(p.name), coords], 14, UI.ACCENT))
				_detail.add_child(UI.fact_block(p.fact, 14))
	_detail.add_child(HSeparator.new())
	if t.get("map_credit") != null:
		_detail.add_child(UI.para("Map: " + str(t.map_credit), 12))
	_detail.add_child(UI.para("Data: " + UI.short_url(str(t.get("source_url", ""))), 12, UI.ACCENT))
	for c in _holder.get_children():
		c.queue_free()
	var planet := Space.make_planet(t, 6.2, _sun)
	_holder.add_child(planet)
	_holder.position = Vector3(-3.2, 0, 0)
	_globe = planet.get_node("Globe")

func _process(delta: float) -> void:
	if is_instance_valid(_globe):
		_globe.rotation.y += delta * 0.1
