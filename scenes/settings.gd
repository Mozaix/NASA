extends Node3D
## Graphics, audio and controls, including key rebinding and gamepad information.

var _waiting_action := ""
var _bind_buttons := {}

func _ready() -> void:
	Space.make_space_env(self)
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	layer.add_child(root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var pan := UI.panel(scroll, 24)
	pan.anchor_left = 0.5
	pan.anchor_right = 0.5
	pan.anchor_top = 0.0
	pan.anchor_bottom = 1.0
	pan.offset_left = -420.0
	pan.offset_right = 420.0
	pan.offset_top = 24.0
	pan.offset_bottom = -24.0
	root.add_child(pan)
	var back := UI.button("Back to menu", func() -> void:
		Settings.save()
		Flow.go("menu"))
	v.add_child(back)
	back.grab_focus.call_deferred()
	v.add_child(UI.heading("Settings", 32))
	v.add_child(UI.eyebrow("Graphics"))
	var q := OptionButton.new()
	for n: String in Settings.QUALITY_NAMES:
		q.add_item(n)
	q.select(Settings.quality)
	q.item_selected.connect(func(i: int) -> void:
		Settings.quality = i
		Settings.apply()
		Settings.save())
	v.add_child(q)
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply()
		Settings.save())
	v.add_child(fs)
	var fpsc := CheckBox.new()
	fpsc.text = "Show frame rate"
	fpsc.button_pressed = Settings.show_fps
	fpsc.toggled.connect(func(on: bool) -> void:
		Settings.show_fps = on
		Settings.save())
	v.add_child(fpsc)
	v.add_child(UI.eyebrow("Audio"))
	_slider(v, "Master", Settings.master_vol, func(x: float) -> void: Settings.master_vol = x)
	_slider(v, "Music", Settings.music_vol, func(x: float) -> void: Settings.music_vol = x)
	_slider(v, "Effects", Settings.sfx_vol, func(x: float) -> void: Settings.sfx_vol = x)
	v.add_child(UI.eyebrow("Controls"))
	_slider(v, "Mouse sensitivity", Settings.mouse_sens / 2.0, func(x: float) -> void: Settings.mouse_sens = x * 2.0)
	var inv := CheckBox.new()
	inv.text = "Invert vertical look"
	inv.button_pressed = Settings.invert_y
	inv.toggled.connect(func(on: bool) -> void:
		Settings.invert_y = on
		Settings.save())
	v.add_child(inv)
	v.add_child(UI.para("Choose an action, then press the new key. Gamepads work automatically: left stick moves, right stick looks, A is the main action, X collects, Y is lights, Start pauses.", 14))
	var grid := UI.grid(2)
	v.add_child(grid)
	for action: String in Settings.ACTIONS:
		grid.add_child(UI.label(str(Settings.ACTIONS[action][0]), 15, UI.TEXT_DIM))
		var a := action
		var b := UI.button(Settings.key_name(action), func() -> void: _start_bind(a))
		b.custom_minimum_size = Vector2(170, 34)
		grid.add_child(b)
		_bind_buttons[action] = b

func _slider(v: VBoxContainer, label_text: String, value: float, on_change: Callable) -> void:
	var row := UI.hbox()
	var l := UI.label(label_text, 15, UI.TEXT_DIM)
	l.custom_minimum_size.x = 170.0
	row.add_child(l)
	var s := HSlider.new()
	s.max_value = 1.0
	s.step = 0.01
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(x: float) -> void:
		on_change.call(x)
		Settings.apply()
		Settings.save())
	row.add_child(s)
	v.add_child(row)

func _start_bind(action: String) -> void:
	_waiting_action = action
	(_bind_buttons[action] as Button).text = "Press a key..."

func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not event is InputEventKey or not event.is_pressed():
		return
	var key := event as InputEventKey
	Settings.rebind(_waiting_action, int(key.physical_keycode))
	(_bind_buttons[_waiting_action] as Button).text = Settings.key_name(_waiting_action)
	_waiting_action = ""
	get_viewport().set_input_as_handled()
