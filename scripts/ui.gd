class_name UI
extends RefCounted
## Shared look and feel: fonts, theme, panels, bars and fact cards.

const ACCENT := Color(0.36, 0.78, 1.0)
const AMBER := Color(1.0, 0.72, 0.3)
const GOOD := Color(0.42, 0.9, 0.62)
const BAD := Color(1.0, 0.42, 0.38)
const TEXT := Color(0.93, 0.95, 0.98)
const TEXT_DIM := Color(0.63, 0.69, 0.78)
const PANEL_BG := Color(0.035, 0.05, 0.085, 0.86)
const PANEL_LINE := Color(0.36, 0.5, 0.68, 0.32)

static var _theme: Theme
static var _font: Font
static var _bold: Font
static var _mono: Font

static func _variation(path: String, weight: int) -> Font:
	var base: FontFile = load(path)
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {"wght": weight}
	return v

static func font() -> Font:
	if not _font:
		_font = _variation("res://assets/fonts/SpaceGrotesk.ttf", 400)
	return _font

static func font_bold() -> Font:
	if not _bold:
		_bold = _variation("res://assets/fonts/SpaceGrotesk.ttf", 700)
	return _bold

static func font_mono() -> Font:
	if not _mono:
		_mono = _variation("res://assets/fonts/JetBrainsMono.ttf", 500)
	return _mono

static func box(bg: Color, line: Color = Color.TRANSPARENT, radius: int = 8, pad: int = 10, line_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(line_w if line.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL_BG, PANEL_LINE, 12, 16))
	t.set_stylebox("panel", "Panel", box(PANEL_BG, PANEL_LINE, 12, 16))
	var normal := box(Color(0.1, 0.15, 0.23, 0.92), Color(0.42, 0.58, 0.76, 0.4), 8, 10)
	var hover := box(Color(0.16, 0.25, 0.37, 0.96), ACCENT, 8, 10)
	var pressed := box(Color(0.08, 0.32, 0.47, 1.0), ACCENT, 8, 10)
	var disabled := box(Color(0.08, 0.1, 0.14, 0.6), Color(0.3, 0.3, 0.35, 0.3), 8, 10)
	var focus := box(Color(0, 0, 0, 0), ACCENT, 8, 10, 2)
	for type_name: String in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type_name, normal)
		t.set_stylebox("hover", type_name, hover)
		t.set_stylebox("pressed", type_name, pressed)
		t.set_stylebox("disabled", type_name, disabled)
		t.set_stylebox("focus", type_name, focus)
		t.set_color("font_color", type_name, TEXT)
		t.set_color("font_hover_color", type_name, Color.WHITE)
		t.set_color("font_pressed_color", type_name, Color.WHITE)
		t.set_color("font_disabled_color", type_name, Color(0.5, 0.52, 0.58))
	t.set_stylebox("panel", "PopupMenu", box(Color(0.05, 0.08, 0.13, 0.98), PANEL_LINE, 8, 8))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.16, 0.3, 0.45, 1.0), Color.TRANSPARENT, 5, 4))
	t.set_stylebox("background", "ProgressBar", box(Color(0.1, 0.13, 0.19, 1.0), Color.TRANSPARENT, 5, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color.TRANSPARENT, 5, 0))
	t.set_stylebox("slider", "HSlider", box(Color(0.15, 0.2, 0.28, 1.0), Color.TRANSPARENT, 4, 3))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, Color.TRANSPARENT, 4, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, Color.TRANSPARENT, 4, 3))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0.1, 0.13, 0.19, 0.6), Color.TRANSPARENT, 4, 2))
	t.set_stylebox("grabber", "VScrollBar", box(Color(0.4, 0.5, 0.65, 0.8), Color.TRANSPARENT, 4, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(ACCENT, Color.TRANSPARENT, 4, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, Color.TRANSPARENT, 4, 2))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.03, 0.05, 0.09, 0.98), PANEL_LINE, 6, 8))
	_theme = t
	return t

static func label(text: String, size: int = 17, color: Color = TEXT, style: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if style == "bold":
		l.add_theme_font_override("font", font_bold())
	elif style == "mono":
		l.add_theme_font_override("font", font_mono())
	return l

static func para(text: String, size: int = 16, color: Color = TEXT_DIM) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 80.0
	return l

static func heading(text: String, size: int = 24) -> Label:
	return label(text, size, TEXT, "bold")

static func eyebrow(text: String) -> Label:
	var l := label(text.to_upper(), 13, ACCENT, "bold")
	l.add_theme_constant_override("line_spacing", 0)
	return l

static func button(text: String, on_press: Callable = Callable(), primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 42.0
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		b.add_theme_stylebox_override("normal", box(Color(0.1, 0.44, 0.64, 1.0), ACCENT, 8, 10))
		b.add_theme_stylebox_override("hover", box(Color(0.15, 0.56, 0.78, 1.0), Color.WHITE, 8, 10))
		b.add_theme_font_override("font", font_bold())
	if on_press.is_valid():
		b.pressed.connect(on_press)
	b.pressed.connect(func() -> void: Sfx.play("click"))
	b.mouse_entered.connect(func() -> void: Sfx.play("hover"))
	return b

static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

## Centres a panel on screen, sized to its contents. Wrapped text only knows its height after a layout pass,
## so the size is worked out again once that has happened.
static func center_panel(pan: Control) -> void:
	pan.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pan.grow_vertical = Control.GROW_DIRECTION_BOTH
	pan.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var fit := func() -> void:
		if not is_instance_valid(pan) or not pan.is_inside_tree():
			return
		await pan.get_tree().process_frame
		if not is_instance_valid(pan):
			return
		pan.reset_size()
		pan.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	fit.call_deferred()

static func panel(child: Control = null, pad: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL_BG, PANEL_LINE, 12, pad))
	if child:
		p.add_child(child)
	return p

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

## Place a control against part of its parent, with a margin in pixels.
static func anchor(c: Control, preset: Control.LayoutPreset, margin: float = 20.0) -> Control:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(margin))
	return c

static func bar(value: float, max_value: float, color: Color = ACCENT, height: float = 10.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = max_value
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size.y = height
	p.add_theme_stylebox_override("fill", box(color, Color.TRANSPARENT, 5, 0))
	return p

static func grouped(v: int) -> String:
	var s := str(abs(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

static func kv(grid: GridContainer, key: String, value: String, value_color: Color = TEXT) -> void:
	var k := label(key, 15, TEXT_DIM)
	var v := label(value, 15, value_color, "mono")
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid.add_child(k)
	grid.add_child(v)

static func grid(cols: int = 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 5)
	return g

static func fmt(v: Variant, pattern: String, fallback: String = "not listed") -> String:
	return pattern % float(v) if v != null else fallback

## Scientific notation, because GDScript format strings have no %e.
static func sci(v: float) -> String:
	if v <= 0.0:
		return "0"
	var e := int(floor(log(v) / log(10.0)))
	return "%.2f \u00d7 10^%d" % [v / pow(10.0, float(e)), e]

static func short_url(url: String) -> String:
	return url.replace("https://", "").replace("www.", "").trim_suffix("/")

## A quoted NASA fact with its source.
static func fact_block(fact: Dictionary, size: int = 16) -> VBoxContainer:
	var v := vbox(3)
	v.add_child(para("“%s”" % fact.get("text", ""), size, TEXT))
	v.add_child(para("Source: " + short_url(fact.get("url", "")), 12, ACCENT))
	return v

## One entry from Game.lessons(): what happened, why, and the NASA quote behind it when there is one.
static func lesson_block(item: Dictionary, size: int = 15) -> VBoxContainer:
	var v := vbox(4)
	v.add_child(label(str(item.title), size + 2, AMBER, "bold"))
	v.add_child(para(str(item.text), size, TEXT))
	var fact: Dictionary = item.get("fact", {})
	if not fact.is_empty():
		v.add_child(fact_block(fact, size - 1))
	return v

## The numeric card for any target, every value from bundled data and labelled when computed.
static func stats_grid(t: Dictionary) -> GridContainer:
	var g := grid(2)
	if t.get("kind") == "exoplanet":
		kv(g, "Host star", str(t.get("hostname", "")))
		kv(g, "Distance", "%s light-years" % fmt(float(t.sy_dist) * Orbital.PC_TO_LY if t.get("sy_dist") != null else null, "%.1f"))
		kv(g, "Radius", fmt(t.get("pl_rade"), "%.2f Earth radii"))
		kv(g, "Mass", fmt(t.get("pl_bmasse"), "%.2f Earth masses"))
		kv(g, "Year", fmt(t.get("pl_orbper"), "%.2f days"))
		var eq := fmt(t.get("pl_eqt"), "%.0f K")
		if t.get("derived", {}).has("pl_eqt"):
			eq += " (derived)"
		kv(g, "Equilibrium temp", eq)
		kv(g, "Star temperature", fmt(t.get("st_teff"), "%.0f K"))
		kv(g, "Gravity", fmt(t.get("gravity"), "%.2f m/s² (derived)"))
		kv(g, "Discovered", "%s, %s" % [str(int(t.disc_year)) if t.get("disc_year") != null else "?", str(t.get("discoverymethod", ""))])
		kv(g, "Class", str(t.get("class", "")).replace("_", " ").capitalize())
		return g
	kv(g, "Radius", fmt(t.get("radius_km"), "%.0f km"))
	kv(g, "Mass", sci(float(t.get("mass_kg", 0.0))) + " kg")
	var grav := fmt(t.get("gravity"), "%.2f m/s²")
	if str(t.get("gravity_source", "")).begins_with("derived"):
		grav += " (derived)"
	kv(g, "Surface gravity", grav)
	kv(g, "Escape velocity", fmt(t.get("escape_kms"), "%.1f km/s"))
	if t.get("day_hours") != null:
		kv(g, "Length of day", "%.1f hours" % float(t.day_hours))
	if t.get("orbit_days") != null:
		kv(g, "Orbital period", "%s days" % grouped(int(t.orbit_days)) if float(t.orbit_days) >= 100.0 else "%.1f days" % float(t.orbit_days))
	if t.get("temp_c") != null:
		kv(g, "Mean temperature", "%.0f °C" % float(t.temp_c))
	if t.get("surface_pressure_text") != null:
		kv(g, "Surface pressure", str(t.surface_pressure_text))
	elif t.get("pressure_bar") != null:
		kv(g, "Surface pressure", "%s bar" % str(t.pressure_bar))
	if t.get("composition") != null:
		kv(g, "Atmosphere", str(t.composition))
	if t.get("n_moons") != null:
		kv(g, "Known moons", str(int(t.n_moons)))
	return g
