extends Node3D
## Title screen over a slowly turning real planet.

var _globe: Node3D
var _cam: Camera3D

func _ready() -> void:
	Game.new_mission()
	Sfx.stop_loops()
	Sfx.music("music_space")
	Space.make_space_env(self)
	var sun_dir := Vector3(0.7, 0.28, 0.65)
	Space.make_sun_light(self, sun_dir)
	var planet := Space.make_planet(Data.body("mars"), 10.0, sun_dir)
	planet.position = Vector3(9.5, -1.0, 0)
	add_child(planet)
	_globe = planet.get_node("Globe")
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0, 25)
	_cam.fov = 42.0
	add_child(_cam)
	_build_ui()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	layer.add_child(root)
	var col := UI.vbox(12)
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = 90.0
	col.offset_right = 640.0
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(col)
	col.add_child(UI.eyebrow("NASA Space Apps Challenge 2026"))
	col.add_child(UI.label("Next Frontier\nExplorer", 58, UI.TEXT, "bold"))
	col.add_child(UI.para("Design a mission. Fly it. Land it. Then drive across terrain built from real NASA elevation data.", 19))
	var gap := Control.new()
	gap.custom_minimum_size.y = 10.0
	col.add_child(gap)
	var start := UI.button("Play Main Game", func() -> void: Flow.go("planner", "Mission Control"), true)
	start.custom_minimum_size.y = 68.0
	start.add_theme_font_size_override("font_size", 25)
	col.add_child(start)
	var modes := UI.hbox(10)
	col.add_child(modes)
	modes.add_child(_mode_button("Play Demo", "About 4 minutes, with a short quiz", _start_demo))
	modes.add_child(_mode_button("Play 2D", "Build rockets, chase the high score", func() -> void:
		Rocket2D.new_game()
		Flow.go("rocket2d", "Rocket Builder")))
	var row := UI.hbox(8)
	col.add_child(row)
	for pair: Array in [["Leaderboard", "leaderboard"], ["Results", "results"], ["Archive", "archive"], ["Settings", "settings"], ["Credits", "credits"]]:
		var dest: String = pair[1]
		var b := UI.button(pair[0], func() -> void: Flow.go(dest))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		row.add_child(b)
	# A browser tab is closed by the player; there is nothing to quit.
	if not OS.has_feature("web"):
		col.add_child(UI.button("Quit", func() -> void: Sfx.quit_game()))
	start.grab_focus.call_deferred()
	var foot := UI.label("Fan project using NASA data. Not endorsed by NASA.   Works fully offline.", 13, UI.TEXT_DIM)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 90.0
	foot.offset_top = -40.0
	foot.offset_bottom = -16.0
	root.add_child(foot)

func _mode_button(title: String, subtitle: String, on_press: Callable) -> Button:
	var b := UI.button("", on_press)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 84.0
	var v := UI.vbox(2)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UI.label(title, 22, UI.TEXT, "bold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var st := UI.label(subtitle, 13, UI.TEXT_DIM)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	v.add_child(st)
	b.add_child(v)
	return b

func _process(delta: float) -> void:
	_globe.rotation.y += delta * 0.035

func auto_advance() -> void:
	if Autotest.two_d:
		Rocket2D.new_game()
		if Autotest._flights_override > 0:
			Rocket2D.flights_left = Autotest._flights_override
		Flow.go("rocket2d", "Rocket Builder")
		return
	if Autotest.demo:
		_start_demo()
	else:
		Flow.go("planner", "Mission Control")

func _start_demo() -> void:
	Game.quiz_stage = "before"
	Game.quiz_before = -1
	Flow.go("quiz")
