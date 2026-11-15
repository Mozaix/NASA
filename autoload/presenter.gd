extends CanvasLayer
## Presenter mode for pitching the game. F2 cycles: notes and timer → timer only → off. F3 restarts
## the timer. The timer counts up against a 3-minute target and turns amber, then red. The notes
## follow the screen on show, each tagged with the judging criteria it covers.

const TARGET_S := 180.0
const MODES := ["off", "notes", "timer"]

## Talking points per screen (scene root name): [rubric tags, points].
const NOTES := {
	"MainMenu": ["Presentation · Influence · Local impact", [
		"The challenge: make space mission design something anyone can try, not just engineers.",
		"Our answer: plan a real mission, fly it, land it, and explore terrain built from NASA data.",
		"Who it's for: students and families in Bahrain and beyond. Free, offline, on any laptop or in a browser."]],
	"Planner": ["Validity · Use of data", [
		"Every number comes from NASA: fact sheets, JPL orbits, the Exoplanet Archive.",
		"Drag propellant down: the rocket equation says no. Auto-design fixes it.",
		"Launch windows are real: Mars on 16 November 2026, computed from JPL elements."]],
	"DemoPicker": ["Relevance · Usability", [
		"The demo is a 4-minute version for events and classrooms.",
		"It starts and ends with the same quiz, so we can measure learning."]],
	"Quiz": ["Influence · Validity", [
		"Same three questions before and after. Results show the change for each class."]],
	"Launch": ["Local impact · Use of data · Technology", [
		"We launch from a concept spaceport in Bahrain, built in 3D from NASA SRTM heights and Landsat imagery.",
		"Real launch steps in the T-minus countdown: access arm, water deluge, ignition at T-3.",
		"Stress peaks partway up, like a real rocket's Max Q. Hold it in the red and it breaks up, and the game explains why."]],
	"Transfer": ["Creativity · Validity", [
		"Real planet positions. Press M for true scale: space is mostly empty.",
		"The debris dodge: you ride on top of the spacecraft and answer to fire the thrusters.",
		"Questions use this mission's own NASA numbers, plus real debris science."]],
	"Orbit": ["Use of data", [
		"Real maps from NASA missions. Hold E to scan for science, then begin the descent."]],
	"Landing": ["Validity · Technology", [
		"The ground below is real elevation data. The autopilot (P) means the demo can't crash."]],
	"Hatch": ["Creativity", [
		"A steady-hands mini-game: load the rover's power core without touching the walls."]],
	"Surface": ["Use of data · Creativity", [
		"Drive across real terrain: the HUD shows the true elevation where you are.",
		"Each beacon is a NASA fact card about that exact place. Hold E to collect a sample."]],
	"Debrief": ["Validity · Presentation", [
		"The debrief explains this flight with its own numbers beside NASA quotes.",
		"16 solar system worlds and 50 real exoplanets use the same flow."]],
	"Results": ["Influence · Local impact · Relevance", [
		"Classroom mode: a teacher names a class; results are kept per class, with no names.",
		"Before and after quiz scores, and the hardest debris questions, ready to discuss.",
		"A printable lesson sheet and a CSV export for schools."]],
	"Rocket2DBuild": ["Influence", [
		"A quick 2D mode for younger players and busy event stands, with a daily leaderboard."]],
}

var mode := "off"
var elapsed := 0.0
var _card: PanelContainer
var _clock: Label
var _bar: ProgressBar
var _tags: Label
var _points: VBoxContainer
var _hint: Label
var _shown_scene := ""

func _ready() -> void:
	layer = 97
	process_mode = Node.PROCESS_MODE_ALWAYS
	var v := UI.vbox(6)
	_card = UI.panel(v, 14)
	_card.theme = UI.theme()
	_card.custom_minimum_size.x = 340.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 18)
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.visible = false
	add_child(_card)
	var top := UI.hbox(10)
	v.add_child(top)
	top.add_child(UI.label("PITCH", 13, UI.ACCENT, "bold"))
	_clock = UI.label("0:00 / 3:00", 22, UI.TEXT, "mono")
	top.add_child(_clock)
	_bar = UI.bar(0.0, TARGET_S, UI.GOOD, 6.0)
	v.add_child(_bar)
	_tags = UI.label("", 12, UI.AMBER, "bold")
	v.add_child(_tags)
	_points = UI.vbox(4)
	v.add_child(_points)
	_hint = UI.label("F2 notes / timer / off   F3 restart timer", 11, UI.TEXT_DIM)
	v.add_child(_hint)
	# Clicks pass straight through to the game underneath.
	_ignore_mouse(_card)

static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_F2:
		cycle()
		get_viewport().set_input_as_handled()
	elif key == KEY_F3 and mode != "off":
		elapsed = 0.0
		get_viewport().set_input_as_handled()

func cycle() -> void:
	mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
	if mode == "notes":
		elapsed = 0.0
	_shown_scene = ""
	_card.visible = mode != "off"

func notes_for(scene_name: String) -> Array:
	return NOTES.get(scene_name, ["", []])

func _process(delta: float) -> void:
	if mode == "off":
		return
	elapsed += delta
	var s := int(elapsed)
	_clock.text = "%d:%02d / %d:%02d" % [s / 60, s % 60, int(TARGET_S) / 60, int(TARGET_S) % 60]
	var col := UI.GOOD if elapsed < TARGET_S - 30.0 else (UI.AMBER if elapsed < TARGET_S else UI.BAD)
	_clock.add_theme_color_override("font_color", col)
	_bar.value = minf(elapsed, TARGET_S)
	_bar.add_theme_stylebox_override("fill", UI.box(col, Color.TRANSPARENT, 5, 0))
	var cs := get_tree().current_scene
	var nm := str(cs.name) if cs else ""
	if nm != _shown_scene:
		_shown_scene = nm
		_show_notes(nm)

func _show_notes(scene_name: String) -> void:
	for c in _points.get_children():
		c.queue_free()
	var show := mode == "notes"
	_tags.visible = show
	_points.visible = show
	if not show:
		return
	var n := notes_for(scene_name)
	_tags.text = str(n[0]).to_upper()
	for p: String in n[1]:
		var l := UI.para("•  " + p, 14, UI.TEXT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_points.add_child(l)
