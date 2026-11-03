extends CanvasLayer
## Scene changes with a fade and a loading card that shows a real fact.

const SCENES := {
	"menu": "res://scenes/main_menu.tscn", "planner": "res://scenes/planner.tscn", "launch": "res://scenes/launch.tscn",
	"transfer": "res://scenes/transfer.tscn", "orbit": "res://scenes/orbit.tscn", "landing": "res://scenes/landing.tscn",
	"surface": "res://scenes/surface.tscn", "debrief": "res://scenes/debrief.tscn", "archive": "res://scenes/archive.tscn",
	"settings": "res://scenes/settings.tscn", "credits": "res://scenes/credits.tscn",
}

var _fade: ColorRect
var _label: Label
var _fact: Label
var busy := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.015, 0.02, 0.04, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.position = Vector2(-300, -80)
	_label.size = Vector2(600, 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.modulate.a = 0.0
	_fade.add_child(_label)
	_fact = Label.new()
	_fact.set_anchors_preset(Control.PRESET_CENTER)
	_fact.position = Vector2(-380, -30)
	_fact.size = Vector2(760, 120)
	_fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fact.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fact.modulate.a = 0.0
	_fade.add_child(_fact)

func go(scene: String, title: String = "") -> void:
	if busy:
		return
	busy = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.text = title
	_label.add_theme_font_override("font", UI.font_bold())
	_label.add_theme_font_size_override("font_size", 30)
	_fact.add_theme_font_override("font", UI.font())
	_fact.add_theme_font_size_override("font_size", 18)
	_fact.add_theme_color_override("font_color", UI.TEXT_DIM)
	_fact.text = _loading_fact() if title != "" else ""
	var has_card := 1.0 if title != "" else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	tw.tween_property(_label, "modulate:a", has_card, 0.3)
	tw.tween_property(_fact, "modulate:a", has_card, 0.3)
	await tw.finished
	await get_tree().process_frame
	await get_tree().process_frame
	var err := get_tree().change_scene_to_file(SCENES[scene])
	if err != OK:
		push_error("Could not open scene " + scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(_fade, "color:a", 0.0, 0.45)
	tw2.tween_property(_label, "modulate:a", 0.0, 0.25)
	tw2.tween_property(_fact, "modulate:a", 0.0, 0.25)
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false

func _loading_fact() -> String:
	var facts: Array = Game.target().get("facts", [])
	if facts.is_empty():
		return ""
	var f: Dictionary = facts[randi() % facts.size()]
	return "“%s”\nNASA" % f.text
