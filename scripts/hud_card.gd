class_name HudCard
extends PanelContainer
## The top-left status card. It says what to do next, in plain words, with exact numbers one key away.

var _tip: Label
var _rows: Dictionary = {}
var _body: VBoxContainer
var _details: VBoxContainer
var _details_hint: Label

func _init(title: String, subtitle: String = "") -> void:
	custom_minimum_size.x = 350.0
	add_theme_stylebox_override("panel", UI.box(UI.PANEL_BG, UI.PANEL_LINE, 14, 16))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(8)
	add_child(v)
	v.add_child(UI.label(title, 22, UI.TEXT, "bold"))
	if subtitle != "":
		v.add_child(UI.label(subtitle, 14, UI.TEXT_DIM))
	var tip_box := PanelContainer.new()
	tip_box.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.32, 0.46, 0.75), Color.TRANSPARENT, 9, 10))
	_tip = UI.para("", 17, UI.TEXT)
	_tip.add_theme_font_override("font", UI.font_bold())
	tip_box.add_child(_tip)
	v.add_child(tip_box)
	_body = UI.vbox(7)
	v.add_child(_body)
	_details = UI.vbox(3)
	_details.visible = false
	v.add_child(_details)
	_details_hint = UI.label("", 12, UI.TEXT_DIM)
	v.add_child(_details_hint)

func set_tip(text: String, color: Color = UI.TEXT) -> void:
	if _tip.text != text:
		_tip.text = text
	_tip.add_theme_color_override("font_color", color)

## A labelled line. Pass with_bar = true for a meter under it.
func add_row(id: String, label_text: String, with_bar: bool = false, bar_color: Color = UI.ACCENT) -> void:
	var box := UI.vbox(3)
	var line := UI.hbox(8)
	var key := UI.label(label_text, 15, UI.TEXT_DIM)
	var value := UI.label("", 16, UI.TEXT, "bold")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(key)
	line.add_child(value)
	box.add_child(line)
	var row := {"value": value, "box": box}
	if with_bar:
		var bar := UI.bar(0, 1, bar_color, 9.0)
		box.add_child(bar)
		row["bar"] = bar
	_body.add_child(box)
	_rows[id] = row

func set_row(id: String, text: String, color: Color = UI.TEXT, fill: float = -1.0) -> void:
	var row: Dictionary = _rows[id]
	(row.value as Label).text = text
	(row.value as Label).add_theme_color_override("font_color", color)
	if fill >= 0.0 and row.has("bar"):
		var bar: ProgressBar = row.bar
		bar.value = clampf(fill, 0.0, 1.0)
		bar.add_theme_stylebox_override("fill", UI.box(color, Color.TRANSPARENT, 5, 0))

func show_row(id: String, on: bool) -> void:
	(_rows[id].box as Control).visible = on

func add_widget(c: Control) -> void:
	_body.add_child(c)

## The exact numbers, hidden until asked for so new players are not swamped.
func set_details(lines: PackedStringArray) -> void:
	_details_hint.text = "%s: %s exact numbers" % [Settings.key_name("details"), "hide" if _details.visible else "show"]
	if not _details.visible:
		return
	while _details.get_child_count() < lines.size():
		_details.add_child(UI.para("", 13, UI.TEXT_DIM))
	for i in _details.get_child_count():
		var l := _details.get_child(i) as Label
		l.visible = i < lines.size()
		if i < lines.size():
			l.text = lines[i]

func toggle_details() -> void:
	_details.visible = not _details.visible

## Plain-language description of gravity compared with Earth.
static func gravity_words(g: float) -> String:
	var pct := int(round(g / 9.8 * 100.0))
	if pct < 20:
		return "%d%% of Earth: almost weightless" % pct
	if pct < 60:
		return "%d%% of Earth: big, floaty hops" % pct
	if pct <= 125:
		return "%d%% of Earth: feels familiar" % pct
	return "%d%% of Earth: very heavy" % pct
