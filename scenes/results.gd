extends Control
## Learning results and classroom mode. A teacher can start a named class before a lesson; every result
## played on this computer then also counts for that class. Shows the demo quiz before and after, and
## which debris-dodge questions players find hardest. Totals only, no names, nothing leaves the machine.

var results_path := QuizScene.RESULTS_PATH
## Which results are on screen: "" for everyone on this computer, or a class name.
var view_class := ""
var _box: VBoxContainer
var _reset_btn: Button
var _reset_armed := 0.0
var _saved: Label
var _name_edit: LineEdit

func _ready() -> void:
	theme = UI.theme()
	Sfx.stop_loops()
	Sfx.music("music_space")
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = UI.vbox(14)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	var p := UI.panel(scroll, 28)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_bottom = 1.0
	p.offset_left = -490.0
	p.offset_right = 490.0
	p.offset_top = 24.0
	p.offset_bottom = -24.0
	add_child(p)
	view_class = Classroom.active()
	_build()

func _quiz_path() -> String:
	return results_path if view_class == "" else Classroom.quiz_path(view_class)

func _build() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_box.add_child(UI.eyebrow("Classroom and learning results on this computer"))
	_box.add_child(UI.heading("What players learned", 32))
	_classroom_bar()
	var r := QuizScene.load_results(_quiz_path())
	var runs := int(r.runs)
	var n := QuizScene.QUESTIONS.size()
	_box.add_child(UI.label("Demo quiz: before and after" + ("" if view_class == "" else "  ·  " + view_class), 20, UI.TEXT, "bold"))
	if runs == 0:
		_box.add_child(UI.para("No quiz results yet. Each player who takes the 3-question quiz before and after the demo adds to these totals.", 16, UI.TEXT_DIM))
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
	_debris_section()
	_box.add_child(UI.para("An informal check, not a scientific study. Totals only, no names, and nothing is sent anywhere.", 14, UI.TEXT_DIM))
	var row := UI.hbox(10)
	_box.add_child(row)
	var back := UI.button("Main menu", func() -> void: Flow.go("menu"), true)
	row.add_child(back)
	var save := UI.button("Save as CSV", save_csv)
	save.disabled = runs == 0 and Classroom.debris_rows(view_class).is_empty()
	row.add_child(save)
	row.add_child(UI.button("Lesson sheet for teachers", open_lesson_sheet))
	_reset_btn = UI.button("Reset for a new event" if view_class == "" else "Delete this class", _reset)
	_reset_btn.disabled = view_class == "" and runs == 0 and Classroom.debris_rows("").is_empty()
	row.add_child(_reset_btn)
	_saved = UI.label("", 14, UI.GOOD)
	_box.add_child(_saved)
	_focus_later(back)

## Start or end a class, and choose whose results to show.
func _classroom_bar() -> void:
	var v := UI.vbox(8)
	var pan := UI.panel(v, 14)
	_box.add_child(pan)
	var active := Classroom.active()
	if active == "":
		v.add_child(UI.label("Classroom mode", 18, UI.ACCENT, "bold"))
		v.add_child(UI.para("Teaching a class? Name it before the lesson. Every result played on this computer then also counts for that class, until you end it.", 15, UI.TEXT))
		var h := UI.hbox(8)
		v.add_child(h)
		_name_edit = LineEdit.new()
		_name_edit.placeholder_text = "Class name, for example Grade 6B"
		_name_edit.max_length = 40
		_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name_edit.text_submitted.connect(func(_t: String) -> void: _start_class())
		h.add_child(_name_edit)
		h.add_child(UI.button("Start class", _start_class, true))
	else:
		var h := UI.hbox(10)
		v.add_child(h)
		h.add_child(UI.label("Class running:", 18, UI.TEXT_DIM))
		h.add_child(UI.label(active, 18, UI.GOOD, "bold"))
		h.add_child(UI.spacer())
		h.add_child(UI.button("End class", func() -> void:
			Classroom.end_class()
			_build()))
	var names: Array = Classroom.classes()
	if not names.is_empty():
		var h2 := UI.hbox(8)
		v.add_child(h2)
		h2.add_child(UI.label("Show results for", 15, UI.TEXT_DIM))
		var pick := OptionButton.new()
		pick.add_item("Everyone on this computer")
		for nm: String in names:
			pick.add_item(nm)
		pick.select(names.find(view_class) + 1)
		pick.item_selected.connect(func(i: int) -> void:
			view_class = "" if i == 0 else str(names[i - 1])
			_build())
		h2.add_child(pick)

func _start_class() -> void:
	if _name_edit == null or Classroom.clean_name(_name_edit.text) == "":
		return
	view_class = Classroom.start_class(_name_edit.text)
	_build()

func _debris_section() -> void:
	var rows := Classroom.debris_rows(view_class)
	_box.add_child(UI.label("Debris dodge: hardest questions first", 20, UI.TEXT, "bold"))
	if rows.is_empty():
		_box.add_child(UI.para("No answers yet. Players answer these during the cruise in the main game.", 16, UI.TEXT_DIM))
		return
	for row: Dictionary in rows.slice(0, 6):
		var h := UI.hbox(10)
		var q := UI.label(str(row.q), 15, UI.TEXT)
		q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(q)
		var share := float(row.share)
		var bar := UI.bar(share * 100.0, 100.0, UI.GOOD if share >= 0.7 else (UI.AMBER if share >= 0.4 else UI.BAD), 12.0)
		bar.custom_minimum_size.x = 200.0
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		var pct := UI.label("%d%% of %d" % [int(round(share * 100.0)), int(row.asked)], 13, UI.TEXT, "mono")
		pct.custom_minimum_size.x = 90.0
		h.add_child(pct)
		_box.add_child(h)

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

static func _csv(s: String) -> String:
	return "\"%s\"" % s.replace("\"", "'")

## The CSV for whatever is on screen: quiz totals, per-question tallies and the debris questions.
func csv_text() -> String:
	var r := QuizScene.load_results(_quiz_path())
	var runs := int(r.runs)
	var lines := PackedStringArray(["group,%s" % _csv(view_class if view_class != "" else "everyone on this computer"),
		"players,%d" % runs, "average_before,%.2f" % (float(r.before_total) / maxi(runs, 1)), "average_after,%.2f" % (float(r.after_total) / maxi(runs, 1)),
		"", "demo_question,right_before,right_after,players"])
	var qb: Array = r.get("q_before", [])
	var qa: Array = r.get("q_after", [])
	for i in QuizScene.QUESTIONS.size():
		if i < qb.size() and i < qa.size():
			lines.append("%s,%d,%d,%d" % [_csv(str(QuizScene.QUESTIONS[i].q)), int(qb[i]), int(qa[i]), int(r.get("q_runs", 0))])
	lines.append("")
	lines.append("debris_question,answered,right,share_right")
	for row: Dictionary in Classroom.debris_rows(view_class):
		lines.append("%s,%d,%d,%.2f" % [_csv(str(row.q)), int(row.asked), int(row.right), float(row.share)])
	return "\n".join(lines) + "\n"

func save_csv() -> void:
	var file := "NextFrontier-results%s.csv" % ("" if view_class == "" else "-" + view_class.validate_filename().replace(" ", "-"))
	_saved.text = _deliver(file, csv_text(), "text/csv")

## A one-page lesson plan with the answers, as a web page the teacher can print.
func open_lesson_sheet() -> void:
	var msg := _deliver("NextFrontier-lesson-sheet.html", LessonSheet.html(view_class), "text/html", true)
	_saved.text = msg

## Saves a file to Documents (or downloads it in the browser version) and says where it went.
func _deliver(file: String, text: String, mime: String, open_after: bool = false) -> String:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file, mime)
		return "Downloaded " + file
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if dir == "":
		dir = OS.get_user_data_dir()
	var path := dir.path_join(file)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return "Could not save to " + path
	f.store_string(text)
	f.close()
	if open_after:
		OS.shell_open(path)
	return "Saved to " + path

## Two presses within 3 seconds, so a stray click can't wipe an event's or a class's results.
func _reset() -> void:
	if _reset_armed <= 0.0:
		_reset_armed = 3.0
		_reset_btn.text = "Press again to erase" + (" this class" if view_class != "" else " all results")
		return
	if view_class == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(results_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Classroom.debris_path("")))
	else:
		Classroom.delete_class(view_class)
		view_class = ""
	_reset_armed = 0.0
	_build()

func _process(delta: float) -> void:
	if _reset_armed > 0.0:
		_reset_armed -= delta
		if _reset_armed <= 0.0 and is_instance_valid(_reset_btn):
			_reset_btn.text = "Reset for a new event" if view_class == "" else "Delete this class"

## Focus a button once it is on screen; skipped if it was already replaced (a fast answer, a rebuild).
func _focus_later(b: Control) -> void:
	(func() -> void:
		if is_instance_valid(b) and b.is_inside_tree():
			b.grab_focus()).call_deferred()
