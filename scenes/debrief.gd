extends Node3D
## Scoring and the science the player actually brought home.

func _ready() -> void:
	Sfx.stop_loops()
	Sfx.music("music_space")
	Game.mission.phase = "debrief"
	var t := Game.target()
	Space.make_space_env(self)
	var sun := Vector3(0.7, 0.3, 0.6)
	Space.make_sun_light(self, sun)
	var planet := Space.make_planet(t, 7.0, sun)
	planet.position = Vector3(8.5, 0, 0)
	add_child(planet)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 25)
	cam.fov = 40.0
	add_child(cam)
	var s := Game.score()
	var best := Game.save_best(float(s.total))
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	layer.add_child(root)
	var v := UI.vbox(10)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(v)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pan := UI.panel(scroll, 24)
	pan.anchor_left = 0.0
	pan.anchor_right = 0.0
	pan.anchor_top = 0.0
	pan.anchor_bottom = 1.0
	pan.offset_left = 40.0
	pan.offset_right = 800.0
	pan.offset_top = 30.0
	pan.offset_bottom = -30.0
	root.add_child(pan)
	v.add_child(UI.eyebrow("Mission debrief"))
	v.add_child(UI.heading(str(t.name), 40))
	var outcome := "Landed and explored." if Game.mission.landed else ("Probe flown through the atmosphere." if Game.is_probe_mission() else "The mission ended before a landing.")
	v.add_child(UI.para(outcome, 18, UI.TEXT))
	v.add_child(UI.label(str(s.rank), 26, UI.AMBER, "bold"))
	var total := UI.label("%d points%s" % [int(s.total), "   new best for this target" if best else ""], 22, UI.TEXT, "mono")
	v.add_child(total)
	var g := UI.grid(2)
	v.add_child(g)
	UI.kv(g, "Mission success", "%d" % int(s.success))
	UI.kv(g, "Science", "%d" % int(s.science))
	UI.kv(g, "Budget left", "%d  ($%s M unspent)" % [int(s.budget), UI.grouped(int(maxf(Game.BUDGET_LIMIT - Game.cost(), 0.0)))])
	UI.kv(g, "Samples", str(Game.mission.samples.size()))
	UI.kv(g, "Sites visited", str(Game.mission.pois.size()))
	if float(Game.mission.distance_m) > 0.0:
		UI.kv(g, "Distance on map", "%.1f km" % (float(Game.mission.distance_m) / 1000.0))
	if int(Game.mission.crashes) > 0:
		UI.kv(g, "Landers lost", str(Game.mission.crashes), UI.BAD)
	if Game.mission.assisted:
		UI.kv(g, "Autopilot used", "yes, -60", UI.AMBER)
	var row := UI.hbox()
	v.add_child(row)
	var again := UI.button("Plan another mission", func() -> void: Flow.go("planner", "Mission Control"), true)
	row.add_child(again)
	row.add_child(UI.button("Main menu", func() -> void: Flow.go("menu")))
	again.grab_focus.call_deferred()
	var facts: Array = t.get("facts", [])
	v.add_child(HSeparator.new())
	v.add_child(UI.eyebrow("What you learned"))
	if Game.mission.facts_seen.is_empty():
		for f: Dictionary in facts.slice(0, 2):
			v.add_child(UI.fact_block(f, 15))
	else:
		for text: String in Game.mission.facts_seen:
			v.add_child(UI.para("“%s”" % text, 15, UI.TEXT))
		v.add_child(UI.para("All quotes are from NASA pages. Sources are listed in the Archive.", 12, UI.ACCENT))

func auto_advance() -> void:
	Autotest.report("score", Game.score())
