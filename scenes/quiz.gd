class_name QuizScene
extends Node3D
## Demo only: three questions before the mission and the same three after, so a player can see what changed.
## Every question is answered by something the demo shows. Totals stay on this computer and hold no names.

const RESULTS_PATH := "user://quiz_results.json"
const QUESTIONS := [
	{"q": "When is the stress from the air on a rising rocket highest?",
	 "right": "Partway up, when it is fast and the air is still thick",
	 "wrong": ["On the launch pad, before it moves", "In space, when it is going fastest"],
	 "why": "Stress depends on both speed and air density. It peaks partway up, a point called Max Q."},
	{"q": "Why do missions to Mars leave only at certain times?",
	 "right": "Earth and Mars must line up for the most efficient trip",
	 "wrong": ["Rockets can only launch in summer", "Dust storms on Mars must be over"],
	 "why": "Both planets are always moving, and NASA says the most energy-efficient alignment comes about once every 26 months."},
	{"q": "On a world with weaker gravity than Earth, what happens when a rover goes over a bump?",
	 "right": "It flies farther and comes down more slowly",
	 "wrong": ["It sticks to the ground more tightly", "Nothing changes, because gravity does not affect jumps"],
	 "why": "Weaker gravity pulls the rover back more slowly, so it stays in the air longer. The debrief shows this world's gravity."},
]

var results_path := RESULTS_PATH
var stage := "before"
var score := 0
var _i := 0
var _answered := false
var _order: Array = []
var _box: VBoxContainer
var _right: Array = []

func _ready() -> void:
	stage = Game.quiz_stage
	Sfx.music("music_space")
	Space.make_space_env(self)
	var cam := Camera3D.new()
	add_child(cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	layer.add_child(root)
	_box = UI.vbox(14)
	var pan := UI.panel(_box, 30)
	pan.custom_minimum_size.x = 720.0
	root.add_child(pan)
	UI.center_panel(pan)
	_show_question()

func _focus(b: Button) -> void:
	if is_instance_valid(b) and b.is_inside_tree():
		b.grab_focus()

func _clear() -> void:
	for c: Node in _box.get_children():
		_box.remove_child(c)
		c.queue_free()

func _show_question() -> void:
	_clear()
	_answered = false
	var q: Dictionary = QUESTIONS[_i]
	_box.add_child(UI.eyebrow("%s the mission: question %d of %d" % ["Before" if stage == "before" else "After", _i + 1, QUESTIONS.size()]))
	_box.add_child(UI.heading(str(q.q), 26))
	_order = [q.right] + q.wrong
	_order.shuffle()
	var first: Button = null
	for a: String in _order:
		var b := UI.button(a, _answer.bind(a))
		_box.add_child(b)
		if first == null:
			first = b
	if stage == "before":
		_box.add_child(UI.button("Skip the quiz", _skip))
	_focus.call_deferred(first)

func _answer(a: String) -> void:
	if _answered:
		return
	_answered = true
	var q: Dictionary = QUESTIONS[_i]
	var right := a == str(q.right)
	_right.append(right)
	if right:
		score += 1
	if stage == "before":
		# No answers yet: the mission is where they get found out.
		_next()
		return
	_clear()
	_box.add_child(UI.heading("Correct" if right else "Not quite", 28))
	_box.add_child(UI.para("Answer: %s." % str(q.right), 18, UI.GOOD))
	_box.add_child(UI.para(str(q.why), 17, UI.TEXT))
	var go := UI.button("Next", _next, true)
	_box.add_child(go)
	_focus.call_deferred(go)

func _next() -> void:
	_i += 1
	if _i < QUESTIONS.size():
		_show_question()
	elif stage == "before":
		Game.quiz_before = score
		Game.quiz_before_right = _right.duplicate()
		Flow.go("demo_picker")
	else:
		_show_results()

func _skip() -> void:
	Game.quiz_before = -1
	Flow.go("demo_picker")

func _show_results() -> void:
	_clear()
	var total := QUESTIONS.size()
	_box.add_child(UI.eyebrow("Your result"))
	if Game.quiz_before >= 0:
		_box.add_child(UI.heading("Before: %d of %d.  After: %d of %d." % [Game.quiz_before, total, score, total], 30))
		# Autotests must not fill a player's totals. A pair counts once.
		var r := load_results(results_path) if Autotest.active else record(Game.quiz_before, score, results_path, Game.quiz_before_right, _right)
		if not Autotest.active and results_path == RESULTS_PATH:
			Classroom.record_quiz(Game.quiz_before, score, Game.quiz_before_right, _right)
		if int(r.runs) > 0:
			_box.add_child(UI.para("All players on this computer (%d): average %.1f before, %.1f after." % [int(r.runs), float(r.before_total) / int(r.runs), float(r.after_total) / int(r.runs)], 17, UI.TEXT))
			_box.add_child(UI.para("This is an informal check using the same questions twice, not a scientific study.", 14, UI.TEXT_DIM))
		Game.quiz_before = -1
	else:
		_box.add_child(UI.heading("%d of %d" % [score, total], 34))
	var full := UI.button("Play the full game", func() -> void: Flow.go("planner", "Mission Control"), true)
	_box.add_child(full)
	_box.add_child(UI.button("Main menu", func() -> void: Flow.go("menu")))
	_focus.call_deferred(full)

static func load_results(path: String) -> Dictionary:
	var empty := {"runs": 0, "before_total": 0, "after_total": 0}
	if not FileAccess.file_exists(path):
		return empty
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return empty
	var d: Dictionary = json.data
	for k: String in empty:
		if not (d.get(k) is float or d.get(k) is int) or float(d[k]) < 0.0:
			return empty
	return d

static func record(before: int, after: int, path: String, before_right: Array = [], after_right: Array = []) -> Dictionary:
	var r := load_results(path)
	r.runs = int(r.runs) + 1
	r.before_total = int(r.before_total) + before
	r.after_total = int(r.after_total) + after
	# Per-question tallies: how many players got each question right, before and after.
	if before_right.size() == QUESTIONS.size() and after_right.size() == QUESTIONS.size():
		for key: String in ["q_before", "q_after"]:
			var arr: Array = r.get(key, [])
			if arr.size() != QUESTIONS.size():
				arr = []
				arr.resize(QUESTIONS.size())
				arr.fill(0)
			var src: Array = before_right if key == "q_before" else after_right
			for i in QUESTIONS.size():
				arr[i] = int(arr[i]) + (1 if src[i] else 0)
			r[key] = arr
		r.q_runs = int(r.get("q_runs", 0)) + 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(r))
	return r

## Answers every question correctly, as the automated tests do.
func auto_advance() -> void:
	for i in QUESTIONS.size():
		if not is_inside_tree():
			return
		_answer(str(QUESTIONS[_i].right))
		if stage != "before":
			_next()
