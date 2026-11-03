extends Control
## Today's heights. A finished player types a name here; their progress then resets for the next player.

var _list: VBoxContainer
var _entry_box: VBoxContainer
var _name: LineEdit
var _highlight := ""
var _clear_btn: Button
var _clear_armed := 0.0

func _ready() -> void:
	theme = UI.theme()
	Sfx.stop_loops()
	Sfx.music("music_space")
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := UI.vbox(12)
	var p := UI.panel(v, 26)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_bottom = 1.0
	p.offset_left = -480.0
	p.offset_right = 480.0
	p.offset_top = 24.0
	p.offset_bottom = -24.0
	add_child(p)
	v.add_child(UI.label("Today's Highest Rockets", 36, UI.TEXT, "bold"))
	v.add_child(UI.label(Rocket2D.today(), 15, UI.TEXT_DIM))
	_entry_box = UI.vbox(8)
	v.add_child(_entry_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = UI.vbox(5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var row := UI.hbox(10)
	v.add_child(row)
	var next := UI.button("Next player: new game", next_player, true)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(next)
	row.add_child(UI.button("Main menu", func() -> void:
		Rocket2D.new_game()
		Rocket2D.pending_submit = false
		Flow.go("menu")))
	_clear_btn = UI.button("Clear today's scores", _on_clear)
	_clear_btn.add_theme_font_size_override("font_size", 14)
	row.add_child(_clear_btn)
	if Rocket2D.pending_submit:
		_build_entry()
	else:
		next.grab_focus.call_deferred()
	_fill()

func _build_entry() -> void:
	var R := Rocket2D
	_entry_box.add_child(UI.label("You reached %s!" % R.format_height(R.best_m), 26, UI.AMBER, "bold"))
	_entry_box.add_child(UI.label("Type your name for the leaderboard", 16, UI.TEXT))
	var row := UI.hbox(8)
	_name = LineEdit.new()
	_name.max_length = R.NAME_MAX
	_name.placeholder_text = "Your name"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size.y = 50.0
	_name.add_theme_font_size_override("font_size", 24)
	_name.add_theme_stylebox_override("normal", UI.box(Color(0.08, 0.12, 0.2), UI.ACCENT, 8, 10))
	_name.add_theme_stylebox_override("focus", UI.box(Color(0.1, 0.15, 0.24), UI.AMBER, 8, 10, 2))
	_name.text_submitted.connect(func(_t: String) -> void: submit())
	row.add_child(_name)
	var save := UI.button("Save my score", submit, true)
	save.custom_minimum_size.x = 200.0
	row.add_child(save)
	_entry_box.add_child(row)
	_name.grab_focus.call_deferred()

## Saves the score, then resets the game so the next player starts from scratch.
func submit() -> void:
	var R := Rocket2D
	if not R.pending_submit:
		return
	var entry: Dictionary = R.add_score(_name.text, R.best_m, R.best_design)
	_highlight = str(entry.id)
	R.pending_submit = false
	R.new_game()
	Sfx.play("collect")
	for c in _entry_box.get_children():
		_entry_box.remove_child(c)
		c.queue_free()
	_fill()

func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var board: Array = Rocket2D.todays_board()
	if board.is_empty():
		_list.add_child(UI.para("No flights yet today. Be the first!", 18, UI.TEXT_DIM))
		return
	var rank := 0
	var shown_me := false
	for e: Dictionary in board:
		rank += 1
		var me: bool = str(e.get("id", "")) == _highlight
		if rank <= Rocket2D.BOARD_SIZE or me:
			if rank > Rocket2D.BOARD_SIZE and not shown_me:
				_list.add_child(UI.label("...", 16, UI.TEXT_DIM))
			_list.add_child(_row(rank, e, me))
		shown_me = shown_me or me

func _row(rank: int, e: Dictionary, me: bool) -> Control:
	var bg := Color(0.32, 0.22, 0.04, 0.9) if rank == 1 else (Color(0.1, 0.28, 0.42, 0.95) if me else Color(0.07, 0.1, 0.16, 0.85))
	var line := UI.hbox(14)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(bg, UI.AMBER if me else Color.TRANSPARENT, 8, 9, 2 if me else 1))
	p.add_child(line)
	var r := UI.label("%d" % rank, 24, UI.AMBER if rank == 1 else UI.TEXT, "bold")
	r.custom_minimum_size.x = 40.0
	line.add_child(r)
	var who := UI.vbox(0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(UI.label(str(e.name), 21, UI.TEXT, "bold"))
	var rocket := UI.label(str(e.get("rocket", "")), 12, UI.TEXT_DIM)
	rocket.clip_text = true
	who.add_child(rocket)
	line.add_child(who)
	line.add_child(UI.label(Rocket2D.format_height(float(e.height)), 22, UI.AMBER if rank == 1 else UI.TEXT, "bold"))
	return p

func next_player() -> void:
	Rocket2D.pending_submit = false
	Rocket2D.new_game()
	Flow.go("rocket2d", "Rocket Builder")

func _on_clear() -> void:
	if _clear_armed <= 0.0:
		_clear_armed = 4.0
		_clear_btn.text = "Press again to delete today's scores"
		return
	Rocket2D.clear_today()
	_clear_armed = 0.0
	_clear_btn.text = "Clear today's scores"
	_fill()

func _process(delta: float) -> void:
	if _clear_armed > 0.0:
		_clear_armed -= delta
		if _clear_armed <= 0.0:
			_clear_btn.text = "Clear today's scores"

func auto_advance() -> void:
	if Rocket2D.pending_submit:
		Autotest.report_shot("r2d_name_entry")
		_name.text = "Test Pilot"
		submit()
	await get_tree().create_timer(0.8).timeout
	Autotest.report_shot("r2d_leaderboard")
