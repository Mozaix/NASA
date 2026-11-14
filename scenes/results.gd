extends Control
## Learning results for everyone who played the demo on this computer: the same three questions before
## and after the mission. Totals only, no names, nothing leaves the machine. For classes and events.

var results_path := QuizScene.RESULTS_PATH
var _box: VBoxContainer
var _reset_btn: Button
var _reset_armed := 0.0
var _saved: Label

func _ready() -> void:
	theme = UI.theme()
	Sfx.stop_loops()
	Sfx.music("music_space")
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_box = UI.vbox(14)
	var p := UI.panel(_box, 28)
	p.custom_minimum_size.x = 900.0
	add_child(p)
	UI.center_panel(p)
	_build()

func _build() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var r := QuizScene.load_results(results_path)
	var runs := int(r.runs)
	var n := QuizScene.QUESTIONS.size()
	_box.add_child(UI.eyebrow("Learning results on this computer"))
	_box.add_child(UI.heading("What players learned from the demo", 32))
	if runs == 0:
		_box.add_child(UI.para("No results yet. Each player who takes the 3-question quiz before and after the demo adds to these totals.", 17, UI.TEXT))
	else:
		var before := float(r.before_total) / runs
		var after := float(r.after_total) / runs
		var stats := UI.hbox(40)
		_box.add_child(stats)
		stats.add_child(_stat(str(runs), "players finished both quizzes", UI.TEXT))
		stats.add_child(_stat("%.1f / %d" % [before, n], "average before", UI.TEXT_DIM))
		stats.add_child(_stat("%.1f / %d" % [after, n], "average after", UI.GOOD))
		stats.add_child(_stat("%+.0f%%" % ((after - before) / float(n) * 100.0), "change in correct answers", UI.AMBER))
		var qb: Array = r.get("q_before", [])
		var qa: Array = r.get("q_after", [])
		var qruns := int(r.get("q_runs", 0))
		if qruns > 0 and qb.size() == n and qa.size() == n:
			_box.add_child(UI.label("Share of players right on each question (%d players with per-question data)" % qruns, 15, UI.TEXT_DIM))
			for i in n:
				_box.add_child(_question_row(str(QuizScene.QUESTIONS[i].q), float(qb[i]) / qruns, float(qa[i]) / qruns))
	_box.add_child(UI.para("An informal check: the same questions twice, not a scientific study. Totals only, no names, and nothing is sent anywhere.", 14, UI.TEXT_DIM))
	var row := UI.hbox(10)
	_box.add_child(row)
	var back := UI.button("Main menu", func() -> void: Flow.go("menu"), true)
	row.add_child(back)
	var save := UI.button("Save as CSV", _save_csv)
	save.disabled = runs == 0
	row.add_child(save)
	_reset_btn = UI.button("Reset for a new event", _reset)
	_reset_btn.disabled = runs == 0
	row.add_child(_reset_btn)
	_saved = UI.label("", 14, UI.GOOD)
	_box.add_child(_saved)
	back.grab_focus.call_deferred()

func _stat(big: String, small: String, col: Color) -> VBoxContainer:
	var v := UI.vbox(0)
	v.add_child(UI.label(big, 40, col, "bold"))
	v.add_child(UI.label(small, 14, UI.TEXT_DIM))
	return v

## One question: a quiet bar for before, a green bar for after, both as a share of players.
func _question_row(q: String, before: float, after: float) -> VBoxContainer:
	var v := UI.vbox(4)
	v.add_child(UI.label(q, 15, UI.TEXT))
	for pair: Array in [["Before", before, Color(0.45, 0.52, 0.62)], ["After", after, UI.GOOD]]:
		var h := UI.hbox(10)
		var l := UI.label(str(pair[0]), 13, UI.TEXT_DIM)
		l.custom_minimum_size.x = 56.0
		h.add_child(l)
		var bar := UI.bar(float(pair[1]) * 100.0, 100.0, pair[2], 12.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		var pct := UI.label("%d%%" % int(round(float(pair[1]) * 100.0)), 13, UI.TEXT, "mono")
		pct.custom_minimum_size.x = 48.0
		h.add_child(pct)
		v.add_child(h)
	return v

func _save_csv() -> void:
	var r := QuizScene.load_results(results_path)
	var runs := int(r.runs)
	var lines := PackedStringArray(["players,%d" % runs, "average_before,%.2f" % (float(r.before_total) / maxi(runs, 1)), "average_after,%.2f" % (float(r.after_total) / maxi(runs, 1)), "question,right_before,right_after,players"])
	var qb: Array = r.get("q_before", [])
	var qa: Array = r.get("q_after", [])
	for i in QuizScene.QUESTIONS.size():
		if i < qb.size() and i < qa.size():
			lines.append("\"%s\",%d,%d,%d" % [str(QuizScene.QUESTIONS[i].q).replace("\"", "'"), int(qb[i]), int(qa[i]), int(r.get("q_runs", 0))])
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if dir == "":
		dir = OS.get_user_data_dir()
	var path := dir.path_join("NextFrontier-learning-results.csv")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		_saved.text = "Saved to " + path
	else:
		_saved.text = "Could not save to " + path

## Two presses within 3 seconds, so a stray click can't wipe an event's results.
func _reset() -> void:
	if _reset_armed <= 0.0:
		_reset_armed = 3.0
		_reset_btn.text = "Press again to erase all results"
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(results_path))
	_build()

func _process(delta: float) -> void:
	if _reset_armed > 0.0:
		_reset_armed -= delta
		if _reset_armed <= 0.0 and is_instance_valid(_reset_btn):
			_reset_btn.text = "Reset for a new event"
