extends Node
## A scripted 60-second tour of the real game for the pitch video, with captions tagged DATA / TECH / IMPACT.
## Record it with Godot's movie writer (not part of the exported game; tools/ is excluded from builds):
##   godot --path . --write-movie pitch/showcase.avi --fixed-fps 30 --resolution 1920x1080 res://tools/showcase.tscn

const STEPS := [
	[0.0, "go_menu"],
	[0.4, "cap", "IMPACT", "Next Frontier Explorer: a free mission-design game that runs offline from a USB stick on Windows, Mac and Linux"],
	[5.5, "go_planner"],
	[6.6, "cap", "DATA", "Launch windows come from JPL planetary orbital elements: the game finds the real Mars windows of 16 Nov 2026 and 4 Jan 2029"],
	[12.5, "go_launch"],
	[13.3, "cap", "DATA", "Launching from a concept spaceport in Bahrain, built on NASA Landsat imagery and SRTM elevation of the island", "top"],
	[16.6, "cap", "TECH", "Rocket equation and Max Q: launch stress follows real dynamic pressure, using Earth's air from NASA fact sheets"],
	[19.0, "go_landing"],
	[20.0, "cap", "DATA", "Gale Crater is built from NASA MOLA laser altimetry: 16-bit heights in true metres, cross-checked against Solar System Treks"],
	[25.0, "cap", "TECH", "GPU-displaced terrain and a powered descent under real Mars gravity, 3.71 m/s², flown here by the autopilot"],
	[30.0, "go_hatch"],
	[31.0, "cap", "TECH", "Mini-games teach hands-on engineering: load the rover's power core without touching the walls"],
	[33.5, "hatch_play"],
	[39.5, "go_surface"],
	[41.0, "surface_poi"],
	[41.2, "cap", "DATA", "Every fact on screen is a verbatim NASA quote, checked against its source page when the game is built", "top"],
	[46.5, "salvage"],
	[46.7, "cap", "TECH", "Salvage a derelict lander: unscrew parts and torque them to the spec sheet with a dial wrench"],
	[51.5, "go_quiz"],
	[52.4, "cap", "IMPACT", "Built for Bahrain's classrooms: a before-and-after quiz measures learning, and the Results screen totals it for each school visit"],
	[60.0, "quit"],
]

var t := 0.0
var _i := 0
var _layer: CanvasLayer
var _tag: Label
var _text: Label
var _cap_panel: PanelContainer
var _salvage_bolt := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_caption()

func _build_caption() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	_layer.add_child(root)
	var h := UI.hbox(16)
	_cap_panel = UI.panel(h, 18)
	_cap_panel.add_theme_stylebox_override("panel", UI.box(Color(0.02, 0.03, 0.05, 0.9), Color(1, 1, 1, 0.15), 12, 18))
	_cap_panel.anchor_left = 0.5
	_cap_panel.anchor_right = 0.5
	_cap_panel.anchor_top = 1.0
	_cap_panel.anchor_bottom = 1.0
	_cap_panel.offset_left = -700.0
	_cap_panel.offset_right = 700.0
	_cap_panel.offset_top = -150.0
	_cap_panel.offset_bottom = -40.0
	_cap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_cap_panel)
	_tag = UI.label("", 22, UI.ACCENT, "bold")
	_tag.custom_minimum_size.x = 110.0
	_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_tag)
	_text = UI.para("", 26, UI.TEXT)
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_text)
	_cap_panel.visible = false

func _caption(tag: String, text: String, top: bool = false) -> void:
	# Bottom by default; at the top (narrower, between the HUD panels) when the bottom holds what the shot is about.
	_cap_panel.anchor_top = 0.0 if top else 1.0
	_cap_panel.anchor_bottom = 0.0 if top else 1.0
	_cap_panel.offset_left = -430.0 if top else -700.0
	_cap_panel.offset_right = 430.0 if top else 700.0
	_cap_panel.offset_top = 100.0 if top else -150.0
	_cap_panel.offset_bottom = 230.0 if top else -40.0
	_tag.text = tag
	_tag.add_theme_color_override("font_color", {"DATA": UI.ACCENT, "TECH": UI.AMBER, "IMPACT": UI.GOOD}[tag])
	_text.text = text
	_cap_panel.visible = true
	_cap_panel.modulate.a = 0.0
	create_tween().tween_property(_cap_panel, "modulate:a", 1.0, 0.3)

func _process(delta: float) -> void:
	t += delta
	while _i < STEPS.size() and t >= float(STEPS[_i][0]):
		var s: Array = STEPS[_i]
		_i += 1
		if s[1] == "cap":
			_caption(s[2], s[3], s.size() > 4 and s[4] == "top")
		else:
			call(s[1])
	_drive(delta)

func _scene() -> Node:
	return get_tree().current_scene

func _mars() -> void:
	Game.new_mission()
	Game.mission.target_id = "mars"
	Game.mission.region_id = "gale"
	Game.auto_design()
	Game.mission.demo = true

func go_menu() -> void:
	Flow.go("menu")

func go_planner() -> void:
	_mars()
	Flow.go("planner", "Mission Control")
	await get_tree().create_timer(1.1).timeout
	var p := _scene()
	if p and p.has_method("_show_step"):
		p._select_target("mars")
		p._show_step(2)

func go_launch() -> void:
	_mars()
	Flow.go("launch", "Launch from Bahrain")
	await get_tree().create_timer(3.2).timeout
	var s := _scene()
	if s and s.has_method("ignite"):
		s.auto_fly = true
		s.ignite()

func go_landing() -> void:
	_mars()
	Flow.go("landing", "Gale Crater")

func go_hatch() -> void:
	Flow.go("hatch", "Power Bay")

func hatch_play() -> void:
	var h := _scene()
	if h is HatchScene:
		h.auto_advance()

func go_surface() -> void:
	Flow.go("surface", "Gale Crater")

func surface_poi() -> void:
	var s := _scene()
	if s == null or not "pois" in s or s.pois.is_empty():
		return
	var p: Dictionary = s.pois[min(2, s.pois.size() - 1)]
	s.vehicle.place(p.pos + Vector3(-30, 0, -24))
	s.vehicle.heading = atan2(24.0, 30.0)
	s._yaw = PI + s.vehicle.heading

func salvage() -> void:
	Input.action_release("move_forward")
	var s := _scene()
	if s and s.has_method("open_salvage") and not s.wreck.is_empty():
		s.open_salvage()

func go_quiz() -> void:
	Input.action_release("move_forward")
	Game.quiz_stage = "after"
	Game.quiz_before = -1
	Flow.go("quiz")

func quit() -> void:
	get_tree().quit()

## Live input the way a player would give it: drive toward the beacon, then turn bolts in the salvage bench.
func _drive(delta: float) -> void:
	var s := _scene()
	if s == null:
		return
	if t > 41.0 and t < 46.4 and s.name == "Surface":
		Input.action_press("move_forward", 0.45)
	if t > 46.5 and s.name == "Surface" and s.salvage != null:
		var g: SalvageGame = s.salvage
		if g.phase == "remove" and _salvage_bolt < g.bolts.size():
			g.active = _salvage_bolt
			g.turn(_salvage_bolt, -delta * 3.0)
			if g.bolts[_salvage_bolt].out or g.phase != "remove":
				_salvage_bolt += 1
		elif g.phase == "install":
			var i := g.next_in_order()
			if i >= 0:
				g.active = i
				var target := SalvageGame.SNUG_TURNS + 1.0 / SalvageGame.TORQUE_PER_TURN
				if float(g.bolts[i].turns) < target:
					g.turn(i, minf(delta * 2.5, target - float(g.bolts[i].turns)))
				else:
					g._settle(i)
					g.active = -1
