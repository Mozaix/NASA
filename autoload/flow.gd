extends CanvasLayer
## Scene changes with a fade and a loading card that shows a real fact.

const SCENES := {
	"menu": "res://scenes/main_menu.tscn", "planner": "res://scenes/planner.tscn", "launch": "res://scenes/launch.tscn",
	"transfer": "res://scenes/transfer.tscn", "orbit": "res://scenes/orbit.tscn", "landing": "res://scenes/landing.tscn",
	"surface": "res://scenes/surface.tscn", "debrief": "res://scenes/debrief.tscn", "archive": "res://scenes/archive.tscn",
	"settings": "res://scenes/settings.tscn", "credits": "res://scenes/credits.tscn",
	"demo_picker": "res://scenes/demo_picker.tscn", "quiz": "res://scenes/quiz.tscn", "rocket2d": "res://scenes/rocket2d.tscn", "rocket2d_flight": "res://scenes/rocket2d_flight.tscn", "leaderboard": "res://scenes/leaderboard.tscn",
	"hatch": "res://scenes/hatch.tscn", "results": "res://scenes/results.tscn",
}

var _fade: ColorRect
var _label: Label
var _fact: Label
var busy := false
var _pause_layer: ColorRect
var _fps: Label
var _pause_end: Button
var _fps_t := 0.0
## Scenes with their own pause menu or none needed are not listed here.
const PAUSABLE: Array[String] = ["Launch", "Transfer", "Orbit", "Landing", "Hatch", "Rocket2DFlight"]

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
	_build_pause()
	_fps = Label.new()
	_fps.position = Vector2(8, 4)
	_fps.visible = false
	add_child(_fps)
	add_child(_version_stamp())

## Small version number in the corner of every screen. Labels ignore the mouse, so it can't block clicks.
func _version_stamp() -> Label:
	var stamp := UI.label(version_text(), 11, UI.TEXT_DIM)
	stamp.name = "VersionStamp"
	stamp.modulate.a = 0.6
	stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 3)
	return stamp

static func version_text() -> String:
	return "v" + str(ProjectSettings.get_setting("application/config/version", ""))

func _build_pause() -> void:
	_pause_layer = ColorRect.new()
	_pause_layer.color = Color(0, 0, 0, 0.55)
	_pause_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.visible = false
	_pause_layer.theme = UI.theme()
	add_child(_pause_layer)
	move_child(_pause_layer, 0)
	var v := UI.vbox(10)
	var pan := UI.panel(v, 24)
	pan.custom_minimum_size.x = 400.0
	_pause_layer.add_child(pan)
	pan.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	pan.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pan.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.add_child(UI.heading("Paused", 30))
	v.add_child(UI.button("Resume", _toggle_pause, true))
	_pause_end = UI.button("End mission and go to debrief", func() -> void:
		_toggle_pause()
		go("debrief", "Mission Debrief"))
	v.add_child(_pause_end)
	v.add_child(UI.button("Quit to main menu", func() -> void:
		_toggle_pause()
		go("menu")))

func _toggle_pause() -> void:
	var now := not get_tree().paused
	get_tree().paused = now
	_pause_layer.visible = now
	var cs := get_tree().current_scene
	_pause_end.visible = cs != null and str(cs.name) != "Rocket2DFlight"
	if now:
		Sfx.stop_loops()

func _unhandled_input(event: InputEvent) -> void:
	if busy or not event.is_action_pressed("pause"):
		return
	var cs := get_tree().current_scene
	if cs and (str(cs.name) in PAUSABLE or _pause_layer.visible):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_fps.visible = Settings.show_fps
	if Settings.show_fps:
		_fps_t += delta
		if _fps_t > 0.4:
			_fps_t = 0.0
			_fps.text = "%d fps" % int(Engine.get_frames_per_second())

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
