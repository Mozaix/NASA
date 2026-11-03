extends Node3D
## Credits and the full source list, read from the same file the judges can check.

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
	var v := UI.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var pan := UI.panel(scroll, 24)
	pan.anchor_left = 0.5
	pan.anchor_right = 0.5
	pan.anchor_top = 0.0
	pan.anchor_bottom = 1.0
	pan.offset_left = -520.0
	pan.offset_right = 520.0
	pan.offset_top = 24.0
	pan.offset_bottom = -24.0
	root.add_child(pan)
	var back := UI.button("Back to menu", func() -> void: Flow.go("menu"))
	v.add_child(back)
	back.grab_focus.call_deferred()
	v.add_child(UI.heading("Next Frontier Explorer", 32))
	v.add_child(UI.para("Built for the NASA Space Apps Challenge 2026. Made with Godot Engine (MIT licence). Not endorsed by NASA.", 16, UI.TEXT))
	for line: String in FileAccess.get_file_as_string("res://data/SOURCES.md").split("\n"):
		var t := line.strip_edges()
		if t == "":
			continue
		if t.begins_with("|---"):
			continue
		if t.begins_with("# "):
			v.add_child(UI.heading(t.trim_prefix("# "), 26))
		elif t.begins_with("## "):
			v.add_child(UI.eyebrow(t.trim_prefix("## ")))
		elif t.begins_with("|"):
			v.add_child(UI.para(t.trim_prefix("|").trim_suffix("|").replace("|", "  ·  ").strip_edges(), 13))
		else:
			v.add_child(UI.para(t.replace("**", "").replace("`", ""), 14))
