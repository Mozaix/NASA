extends Control
## The hangar: buy parts, see each part's predicted effect, and launch.

var _parts_box: VBoxContainer
var _info: Label
var _money: Label
var _flights: Label
var _best: Label
var _predicted: Label
var _reasons: VBoxContainer
var _suggest: Button
var _launch: Button
var _finish: Button
var _quit: Button
var _quit_armed := 0.0
var _view: RocketView
var _ladder: Ladder
var _chips: Dictionary = {}
var _queue: Array = []
var _suggest_data: Dictionary = {}
var _suggest_pending := false

class RocketView extends Control:
	func _draw() -> void:
		var d: Dictionary = Rocket2D.design
		var h := R2DDraw.total_height(d)
		var s := minf(size.y * 0.8 / h, 34.0)
		var base := Vector2(size.x * 0.5, size.y * 0.9)
		draw_line(Vector2(size.x * 0.1, base.y + s), Vector2(size.x * 0.9, base.y + s), Color(0.4, 0.5, 0.65, 0.6), 2.0)
		R2DDraw.draw(self, base, s, 0.0, d)

## Height scale with the real milestones, and where this rocket is predicted to reach.
class Ladder extends Control:
	var predicted := 0.0
	func y_of(km: float) -> float:
		var t := log(maxf(km, 1.0)) / log(400000.0)
		return size.y - 8.0 - t * (size.y - 18.0)
	func _draw() -> void:
		var font := UI.font()
		draw_line(Vector2(10, 8), Vector2(10, size.y - 8.0), Color(0.5, 0.6, 0.75, 0.7), 2.0)
		for m: Dictionary in Data.milestones:
			var y := y_of(float(m.km))
			var got: bool = Rocket2D.reached.has(m.id)
			var col := UI.GOOD if got else UI.TEXT_DIM
			draw_line(Vector2(5, y), Vector2(16, y), col, 2.0)
			draw_string(font, Vector2(22, y + 4), "%s  %s km" % [str(m.name), UI.grouped(int(m.km))], HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 12, col)
		if predicted > 0.0:
			var y := y_of(predicted / 1000.0)
			draw_colored_polygon(PackedVector2Array([Vector2(0, y - 7), Vector2(0, y + 7), Vector2(11, y)]), UI.AMBER)
		if Rocket2D.best_m > 0.0:
			var yb := y_of(Rocket2D.best_m / 1000.0)
			draw_line(Vector2(2, yb), Vector2(18, yb), UI.ACCENT, 3.0)

func _ready() -> void:
	theme = UI.theme()
	Sfx.stop_loops()
	Sfx.music("music_space")
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	add_child(m)
	var col := UI.vbox(10)
	m.add_child(col)
	col.add_child(_build_top())
	var mid := UI.hbox(12)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mid)
	mid.add_child(_build_parts())
	_view = RocketView.new()
	_view.custom_minimum_size.x = 250.0
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(_view)
	mid.add_child(_build_panel())
	_refresh()
	_launch.grab_focus.call_deferred()

func _build_top() -> Control:
	var row := UI.hbox(14)
	_quit = UI.button("Quit game", _on_quit)
	row.add_child(_quit)
	row.add_child(UI.label("Rocket Builder", 28, UI.TEXT, "bold"))
	row.add_child(UI.spacer())
	_best = UI.label("", 18, UI.TEXT_DIM, "bold")
	row.add_child(_best)
	_flights = UI.label("", 18, UI.ACCENT, "bold")
	row.add_child(_flights)
	_money = UI.label("", 26, UI.GOOD, "bold")
	row.add_child(_money)
	return row

func _build_parts() -> Control:
	var v := UI.vbox(8)
	var p := UI.panel(v, 12)
	p.custom_minimum_size.x = 820.0
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_parts_box = UI.vbox(6)
	_parts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_parts_box)
	_info = UI.para("Each card shows the height you would gain or lose with that part. Point at a card to read about it.", 14, UI.TEXT)
	_info.custom_minimum_size.y = 40.0
	v.add_child(_info)
	return p

func _build_panel() -> Control:
	var v := UI.vbox(9)
	var p := UI.panel(v, 14)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(UI.eyebrow("Predicted height"))
	_predicted = UI.label("", 34, UI.AMBER, "bold")
	v.add_child(_predicted)
	v.add_child(UI.label("Straight up, no wind, perfect flying", 12, UI.TEXT_DIM))
	_reasons = UI.vbox(3)
	v.add_child(_reasons)
	_ladder = Ladder.new()
	_ladder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ladder.custom_minimum_size.y = 170.0
	v.add_child(_ladder)
	_suggest = UI.button("", _apply_suggestion)
	_suggest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_suggest)
	_launch = UI.button("LAUNCH", launch, true)
	_launch.custom_minimum_size.y = 58.0
	_launch.add_theme_font_size_override("font_size", 24)
	v.add_child(_launch)
	_finish = UI.button("Finish and save my score", finish)
	v.add_child(_finish)
	return p

func _on_quit() -> void:
	if _quit_armed <= 0.0 and Rocket2D.best_m > 0.0:
		_quit_armed = 3.0
		_quit.text = "Quit and lose this game?"
		return
	Rocket2D.new_game()
	Flow.go("menu")

func _clear(c: Control) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()

func _refresh() -> void:
	var R := Rocket2D
	_money.text = "$%s" % UI.grouped(R.money)
	_flights.text = "%d of %d launches left" % [R.flights_left, R.FLIGHTS_PER_GAME]
	_best.text = "Best: %s" % R.format_height(R.best_m) if R.best_m > 0.0 else ""
	_finish.disabled = R.best_m <= 0.0
	var can_lift: bool = R.predict(R.design).reason != "no_liftoff"
	_launch.disabled = R.flights_left <= 0 or not can_lift
	_launch.text = "No launches left" if R.flights_left <= 0 else ("Too heavy to launch" if not can_lift else "LAUNCH")
	_chips.clear()
	_queue.clear()
	_clear(_parts_box)
	for slot: String in R.SLOT_ORDER:
		_parts_box.add_child(UI.eyebrow(str(R.SLOT_TITLES[slot])))
		var row := UI.hbox(6)
		_parts_box.add_child(row)
		for part: Dictionary in R.PARTS[slot]:
			row.add_child(_card(slot, part))
			if part.id != R.design[slot]:
				_queue.append({"slot": slot, "id": part.id, "design": R.with_part(slot, part.id)})
	# Upgrades that only work as a pair, such as a bigger tank with a bigger engine.
	for c: Dictionary in R.upgrade_candidates():
		_queue.append({"design": c.design})
	_suggest_pending = true
	_suggest.visible = false
	_update_prediction()
	_view.queue_redraw()

func _card(slot: String, part: Dictionary) -> Button:
	var R := Rocket2D
	var id: String = part.id
	var selected: bool = R.design[slot] == id
	var owned: bool = R.is_owned(id)
	var affordable: bool = owned or int(part.cost) <= R.money
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 70)
	b.focus_mode = Control.FOCUS_ALL
	var edge := UI.AMBER if selected else UI.PANEL_LINE
	var bg := Color(0.1, 0.22, 0.32) if selected else Color(0.07, 0.1, 0.16)
	b.add_theme_stylebox_override("normal", UI.box(bg, edge, 8, 6, 2 if selected else 1))
	b.add_theme_stylebox_override("hover", UI.box(Color(0.12, 0.25, 0.36), UI.ACCENT, 8, 6))
	b.add_theme_stylebox_override("pressed", UI.box(bg, UI.AMBER, 8, 6, 2))
	b.add_theme_stylebox_override("focus", UI.box(Color(0, 0, 0, 0), UI.ACCENT, 8, 6, 2))
	var v := UI.vbox(0)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 7.0
	v.offset_top = 4.0
	v.offset_right = -5.0
	v.offset_bottom = -3.0
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var name_l := UI.label(str(part.name), 15, UI.TEXT if affordable else UI.TEXT_DIM, "bold")
	name_l.clip_text = true
	v.add_child(name_l)
	var price := "Fitted" if selected else ("Owned" if owned else "$%s" % UI.grouped(int(part.cost)))
	v.add_child(UI.label(price, 13, UI.AMBER if selected else (UI.TEXT_DIM if owned else (UI.GOOD if affordable else UI.BAD))))
	var chip := UI.label("", 13, UI.TEXT_DIM, "bold")
	chip.clip_text = true
	v.add_child(chip)
	_chips[slot + "/" + id] = chip
	b.pressed.connect(func() -> void: _pick(slot, id))
	var show_info := func() -> void:
		_info.text = "%s: %s" % [str(part.name), str(part.desc)]
	b.mouse_entered.connect(show_info)
	b.focus_entered.connect(show_info)
	return b

func _pick(slot: String, id: String) -> void:
	var R := Rocket2D
	var was: bool = R.is_owned(id)
	if R.choose(slot, id):
		Sfx.play("click" if was else "collect")
		_refresh()
	else:
		Sfx.play("alarm", -10.0)
		_info.text = "Not enough money yet. Fly higher to earn more."

func _update_prediction() -> void:
	var R := Rocket2D
	var p: Dictionary = R.predict(R.design)
	_predicted.text = R.format_height(float(p.apogee)) if p.reason != "no_liftoff" else "Stays on the pad"
	_ladder.predicted = float(p.apogee)
	_ladder.queue_redraw()
	_clear(_reasons)
	var t := float(p.twr)
	if t <= 1.0:
		_reasons.add_child(UI.para("Too heavy: the engines push with only %.1f times its weight. It needs more than 1." % t, 14, UI.BAD))
	else:
		_reasons.add_child(UI.para("Liftoff push: %.1f times its weight" % t, 14, UI.GOOD if t > 1.3 else UI.AMBER))
	if p.reason == "breakup":
		_reasons.add_child(UI.para("Will tumble and break up at about %s. Better fins will fix this." % R.format_height(float(p.breakup_h)), 14, UI.BAD))
	elif float(p.margin) >= 0.0:
		_reasons.add_child(UI.para("Flies straight", 14, UI.GOOD))
	var half: bool = (R.design.utank == "u0") != (R.design.uengine == "ue0")
	if half:
		_reasons.add_child(UI.para("A second stage needs both a tank and an engine. For now it is dead weight.", 14, UI.BAD))

func _chip_text(now: Dictionary, after: Dictionary) -> Array:
	var R := Rocket2D
	if after.reason == "no_liftoff":
		return ["Too heavy", UI.BAD]
	if after.reason == "breakup":
		return ["Would tumble", UI.BAD]
	var diff := float(after.apogee) - float(now.apogee)
	if absf(diff) < maxf(float(now.apogee) * 0.005, 5.0):
		return ["No change", UI.TEXT_DIM]
	var text: String = R.format_height(absf(diff))
	return [("+" if diff > 0.0 else "-") + text, UI.GOOD if diff > 0.0 else UI.BAD]

func _process(delta: float) -> void:
	if _quit_armed > 0.0:
		_quit_armed -= delta
		if _quit_armed <= 0.0:
			_quit.text = "Quit game"
	# Work through predictions a few per frame, so the hangar never freezes.
	var R := Rocket2D
	var started := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - started < 6000:
		var job: Dictionary = _queue.pop_front()
		var after: Dictionary = R.predict(job.design)
		if job.has("slot"):
			var chip: Label = _chips.get(str(job.slot) + "/" + str(job.id))
			if chip:
				var t: Array = _chip_text(R.predict(R.design), after)
				chip.text = t[0]
				chip.add_theme_color_override("font_color", t[1])
	if _queue.is_empty() and _suggest_pending:
		_suggest_pending = false
		_suggest_data = R.best_upgrade()
		_suggest.visible = true
		_suggest.disabled = _suggest_data.is_empty()
		if _suggest_data.is_empty():
			_suggest.text = "Nothing you can afford adds height yet. Fly to earn more."
		else:
			_suggest.text = "Best buy: %s\n$%s for +%s" % [str(_suggest_data.label), UI.grouped(int(_suggest_data.cost)), R.format_height(float(_suggest_data.gain))]

func _apply_suggestion() -> void:
	if _suggest_data.is_empty():
		return
	Rocket2D.apply_upgrade(_suggest_data)
	Sfx.play("collect")
	_refresh()

func launch() -> void:
	var R := Rocket2D
	if R.flights_left <= 0:
		return
	Sfx.play("stage")
	Flow.go("rocket2d_flight")

func finish() -> void:
	Rocket2D.pending_submit = true
	Flow.go("leaderboard")

func auto_advance() -> void:
	var R := Rocket2D
	if R.flights_left <= 0:
		Autotest.report_shot("r2d_hangar_final")
		finish()
		return
	while true:
		var u: Dictionary = R.best_upgrade()
		if u.is_empty():
			break
		R.apply_upgrade(u)
	_refresh()
	while not _queue.is_empty() or _suggest_pending:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	Autotest.report_shot("r2d_hangar_%d" % (R.FLIGHTS_PER_GAME - R.flights_left))
	launch()
