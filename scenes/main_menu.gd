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
	col.offset_right = 580.0
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(col)
	col.add_child(UI.eyebrow("NASA Space Apps Challenge 2026"))
	col.add_child(UI.label("Next Frontier\nExplorer", 58, UI.TEXT, "bold"))
	col.add_child(UI.para("Design a mission. Fly it. Land it. Then drive across terrain built from real NASA elevation data.", 19))
	var gap := Control.new()
	gap.custom_minimum_size.y = 10.0
	col.add_child(gap)
	var start := UI.button("New Mission", func() -> void: Flow.go("planner", "Mission Control"), true)
	start.custom_minimum_size.y = 52.0
	col.add_child(start)
	col.add_child(UI.button("Mission Archive: planets, moons, exoplanets", func() -> void: Flow.go("archive")))
	var row := UI.hbox()
	for pair: Array in [["Settings", "settings"], ["Credits & Sources", "credits"]]:
		var dest: String = pair[1]
		var b := UI.button(pair[0], func() -> void: Flow.go(dest))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	col.add_child(row)
	var quit := UI.button("Quit", func() -> void: get_tree().quit())
	col.add_child(quit)
	start.grab_focus.call_deferred()
	var foot := UI.label("Fan project using NASA data. Not endorsed by NASA.   Works fully offline.", 13, UI.TEXT_DIM)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 90.0
	foot.offset_top = -40.0
	foot.offset_bottom = -16.0
	root.add_child(foot)

func _process(delta: float) -> void:
	_globe.rotation.y += delta * 0.035

func auto_advance() -> void:
	Flow.go("planner", "Mission Control")
