class_name TrickHud
extends PanelContainer
## Shows the running trick total and the live combo, in the style of a skating game.

var trick: TrickScore
var _total: Label
var _combo: Label
var _note: Label
var _note_time := 0.0

func _init(t: TrickScore, hint: String) -> void:
	trick = t
	add_theme_stylebox_override("panel", UI.box(UI.PANEL_BG, UI.PANEL_LINE, 12, 12))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 240.0
	var v := UI.vbox(2)
	add_child(v)
	v.add_child(UI.label("Trick score (game bonus)", 14, UI.TEXT_DIM))
	_total = UI.label("0", 28, UI.AMBER, "mono")
	v.add_child(_total)
	_combo = UI.label("", 20, UI.GOOD, "bold")
	v.add_child(_combo)
	_note = UI.label("", 16, UI.TEXT, "bold")
	v.add_child(_note)
	v.add_child(UI.label(hint, 12, UI.TEXT_DIM))

func flash(text: String, color: Color = UI.GOOD) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", color)
	_note_time = 2.2

func _process(delta: float) -> void:
	_total.text = UI.grouped(int(Game.mission.get("trick_points", 0)))
	_combo.text = "%d  x%d" % [trick.combo_points, trick.mult] if trick.in_combo() else ""
	if _note_time > 0.0:
		_note_time -= delta
		if _note_time <= 0.0:
			_note.text = ""
