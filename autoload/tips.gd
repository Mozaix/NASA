extends CanvasLayer
## First-time help popups: the first time a player reaches a screen, a card explains what to do there.
## The game pauses while the card is open. Each card is shown once; Settings can turn them off or reset them.
## The pause menu can reopen the current screen's card at any time.

const PATH := "user://tips.cfg"

var enabled := true
var seen := {}
var _layer: ColorRect
var _box: VBoxContainer
var _open_key := ""
var _was_paused := false
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _last_scene: Node

func _ready() -> void:
	layer = 95  # above every scene, below Flow's fade (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_layer = ColorRect.new()
	_layer.color = Color(0, 0, 0, 0.5)
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.theme = UI.theme()
	_layer.visible = false
	add_child(_layer)

## Watch for new scenes. Polling the current scene avoids depending on how each scene was opened.
func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == _last_scene or cs == null:
		return
	if Flow.busy:
		return  # wait until the fade has finished so the card is not hidden behind it
	_last_scene = cs
	maybe_show(str(cs.name))

## Text for each screen, keyed by the scene's root node name. Built on demand so rebound keys show correctly.
static func tip_for(scene_name: String) -> Dictionary:
	var k := func(action: String) -> String: return "[" + Settings.key_name(action) + "]"
	match scene_name:
		"MainMenu":
			return {"title": "Welcome, explorer", "steps": [
				"Play Main Game: plan a real mission, launch it, fly to another world, land and explore.",
				"Play Demo: a guided 4-minute run with a short quiz before and after.",
				"Play 2D: build rockets from parts and chase the highest altitude.",
				"Press %s during a mission to pause. Help like this appears the first time you reach each screen." % k.call("pause")]}
		"Planner":
			return {"title": "Mission Control", "steps": [
				"Work through the four tabs at the top: Destination, Spacecraft, Launch Window, Review.",
				"Pick where to go and where to land. Every number comes from NASA data.",
				"Choose a launcher and instruments. Watch the budget bar: money left over adds to your score.",
				"Launch close to the best window. Launching off-window costs extra fuel."]}
		"DemoPicker":
			return {"title": "Pick your mission", "steps": [
				"Choose a destination and a spacecraft.",
				"Stay inside the budget. Money left over adds to your score.",
				"Then press the launch button to start."]}
		"Quiz":
			return {"title": "Quick quiz", "steps": [
				"Answer a few short questions. It is fine to guess.",
				"You take the same quiz after the demo, so you can see what you learned."]}
		"Launch":
			return {"title": "Launch", "steps": [
				"Press %s to go for launch. The T-minus clock counts down from T-30 and the pad crew works through the launch steps." % k.call("thrust"),
				"In a hurry? Press %s again to skip to T-10. The engines light at T-3, and the rocket lifts off at T-0." % k.call("thrust"),
				"%s / %s throttle up and down. %s / %s steer into crosswinds. Keep the stress needle out of the red, or the rocket breaks apart." % [k.call("move_forward"), k.call("move_back"), k.call("move_left"), k.call("move_right")],
				"In orbit, press %s when the marker is in the green to leave Earth. %s turns on the autopilot." % [k.call("thrust"), k.call("assist")]]}
		"Transfer":
			return {"title": "Cruise to your target", "steps": [
				"Your spacecraft is flying along real planet orbits. Drag to turn the camera and scroll to zoom. %s switches between true and viewable scale." % k.call("map"),
				"Twice on the way, meteoroids or space debris head straight for you. You see it from on top of your spacecraft.",
				"Answer the question before the timer runs out (click, or press 1, 2 or 3). Right fires the thrusters and you dodge. Wrong, and the shield takes a hit."]}
		"Orbit":
			return {"title": "In orbit", "steps": [
				"Hold %s to scan the planet from orbit and earn science points." % k.call("interact"),
				"Drag to look around and scroll to zoom.",
				"When you are ready, press Begin descent."]}
		"Landing":
			return {"title": "Landing", "steps": [
				"Hold %s to fire the engine (or open the parachute on worlds with air)." % k.call("thrust"),
				"Steer toward the pad with %s %s %s %s." % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right")],
				"Touch down slowly and upright. Hold %s to look down at the pad." % k.call("look_down"),
				"Stuck? %s hands control to the autopilot." % k.call("assist")]}
		"Hatch":
			return {"title": "Load the power core", "steps": [
				"Drag each fuel rod from the rack on the left to the cradle on the right.",
				"Stay inside its channel. Every wall touch shakes the core, and too many make it blow.",
				"Move slowly near the bends. The clicking speeds up as you get close to a wall."]}
		"Surface":
			return {"title": "Explore the surface", "steps": [
				"%s %s %s %s to drive and the mouse to look. %s to jump." % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("thrust")],
				"Drive to the markers and press %s to collect samples. The objectives list shows what is left." % k.call("interact"),
				"%s opens the map, %s toggles headlights, %s boosts." % [k.call("map"), k.call("lights"), k.call("boost")],
				"Found a derelict lander? Salvage it for parts to repair and upgrade your rover."]}
		"Debrief":
			return {"title": "Mission debrief", "steps": [
				"See your score and what each part of the mission earned.",
				"Read the lessons: each one explains what happened, backed by a NASA source.",
				"Try another target, or beat your best score on this one."]}
		"Rocket2DBuild":
			return {"title": "Rocket Builder", "steps": [
				"Buy parts to build a rocket: tanks, engines, fins and a nose cone.",
				"The predicted altitude updates as you add parts. A stage needs both a tank and an engine.",
				"Press Launch when you are happy. You only get a few flights, so spend wisely."]}
		"Rocket2DFlight":
			return {"title": "Flight", "steps": [
				"Press %s to launch." % k.call("thrust"),
				"Wind pushes the rocket over. Keep it straight with %s and %s." % [k.call("move_left"), k.call("move_right")],
				"The higher it goes, the more money you earn for your next build."]}
	return {}

## Shows the card for a screen if the player has not seen it yet.
func maybe_show(scene_name: String) -> void:
	if not enabled or seen.has(scene_name) or _headless():
		return
	show_tip(scene_name)

## Shows the card for a screen whether or not it was seen before. Returns false if the screen has no card.
func show_tip(scene_name: String) -> bool:
	var tip := tip_for(scene_name)
	if tip.is_empty():
		return false
	if is_open():
		close()
	_open_key = scene_name
	seen[scene_name] = true
	_save()
	_build(tip)
	_was_paused = get_tree().paused
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_layer.visible = true
	return true

func is_open() -> bool:
	return _open_key != ""

func close() -> void:
	if not is_open():
		return
	_open_key = ""
	_layer.visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_mode

func has_tip(scene_name: String) -> bool:
	return not tip_for(scene_name).is_empty()

func reset() -> void:
	seen.clear()
	_save()

func set_enabled(on: bool) -> void:
	enabled = on
	_save()

func _build(tip: Dictionary) -> void:
	for c: Node in _layer.get_children():
		c.queue_free()
	var v := UI.vbox(12)
	var pan := UI.panel(v, 26)
	pan.custom_minimum_size.x = 560.0
	_layer.add_child(pan)
	v.add_child(UI.eyebrow("How to play"))
	v.add_child(UI.heading(str(tip.title), 30))
	var i := 1
	for step: String in tip.steps:
		var row := UI.hbox(12)
		var num := UI.label(str(i), 18, UI.ACCENT, "bold")
		num.custom_minimum_size.x = 22.0
		row.add_child(num)
		row.add_child(UI.para(step, 17, UI.TEXT))
		v.add_child(row)
		i += 1
	var buttons := UI.hbox(10)
	v.add_child(buttons)
	var off := UI.button("Don't show tips", func() -> void:
		set_enabled(false)
		close())
	buttons.add_child(off)
	buttons.add_child(UI.spacer())
	var ok := UI.button("Got it", close, true)
	ok.custom_minimum_size.x = 160.0
	buttons.add_child(ok)
	UI.center_panel(pan)
	ok.grab_focus.call_deferred()

## Escape or the pause key closes the card, so it never gets stuck in front of the game.
func _unhandled_input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless" or Autotest.active

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	enabled = c.get_value("tips", "enabled", true)
	seen = c.get_value("tips", "seen", {})

func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("tips", "enabled", enabled)
	c.set_value("tips", "seen", seen)
	c.save(PATH)
