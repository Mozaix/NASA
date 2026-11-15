class_name DebrisRun
extends Control
## The debris dodge: the view from on top of the spacecraft while meteoroids or debris rush at it.
## A question appears with a timer. The threat arrives exactly when the timer runs out:
## answer right and the thrusters fire to dodge; answer wrong or too late and it hits the shield.
## Built in its own SubViewport and world, so it works over any scene.

signal finished(right_count: int, asked: int)

const ANSWER_TIME := 15.0
const START_Z := -260.0
const FLYERS := 48

var questions: Array = []
var kind := "meteoroids"     # or "debris"
var right_count := 0
var state := "ask"           # ask, dodge, impact, explain, done
var _i := 0
var _t := 0.0
var _phase_t := 0.0
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _rig: Node3D
var _threat: Node3D
var _threat_r := 1.3
var _threat_spin := Vector3.ZERO
var _dodge_dir := 1.0
var _flyers: Array = []
var _rng := RandomNumberGenerator.new()
var _box: VBoxContainer
var _title: Label
var _q: Label
var _buttons: Array[Button] = []
var _answers: Array = []
var _timer_bar: ProgressBar
var _timer_label: Label
var _why: VBoxContainer
var _flash: ColorRect
var _overlay: Overlay
var _shake := 0.0
var _beeped := -1
var _puffs := {}
var _last_slot := -1

## Target brackets around the threat, and cracks on the visor after a hit.
class Overlay extends Control:
	var target := Vector2.ZERO
	var radius := 0.0
	var show_target := false
	var label := ""
	var cracks: Array = []
	func _draw() -> void:
		if show_target and radius > 0.0:
			var r := clampf(radius * 1.35, 18.0, 420.0)
			var col := Color(1.0, 0.36, 0.3)
			var k := r * 0.35
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					var c := target + Vector2(sx * r, sy * r)
					draw_line(c, c - Vector2(sx * k, 0), col, 3.0)
					draw_line(c, c - Vector2(0, sy * k), col, 3.0)
			draw_string(UI.font_bold(), target + Vector2(-r, -r - 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		for line: Array in cracks:
			draw_polyline(line, Color(0.9, 0.95, 1.0, 0.75), 2.0)

func setup(qs: Array, hazard_kind: String) -> void:
	questions = qs
	kind = hazard_kind

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UI.theme()
	_rng.randomize()
	_build_world()
	_build_ui()
	_ask()

# ---------------------------------------------------------------- 3D

func _build_world() -> void:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X if Settings.quality > 0 else Viewport.MSAA_DISABLED
	holder.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	Space.make_space_env(_world, 0.12)
	Space.make_sun_light(_world, Vector3(0.5, 0.6, 0.35), Color(1, 0.97, 0.92), 1.6)
	_rig = Node3D.new()
	_world.add_child(_rig)
	var ship := Models.satellite()
	_rig.add_child(ship)
	for t: String in ["ThrusterL", "ThrusterR"]:
		_puffs[t] = _thruster_puff(ship.get_node(t), -1.0 if t == "ThrusterL" else 1.0)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.05
	_cam.far = 2000.0
	# Just above the top deck, looking forward over the satellite with its wings out to the sides.
	_cam.position = Vector3(0, 2.1, 2.9)
	_rig.add_child(_cam)
	_cam.look_at_from_position(_cam.position, Vector3(0, 0.3, -10.0), Vector3.UP)
	for i in FLYERS:
		var f := _make_piece(_rng.randf_range(0.08, 0.45))
		_world.add_child(f)
		_flyers.append({"node": f, "v": 0.0, "spin": Vector3.ZERO})
		_respawn_flyer(_flyers[i], true)

func _make_piece(r: float) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	if kind == "debris" and _rng.randf() < 0.65:
		# Satellite fragments: bent panels and struts.
		var b := BoxMesh.new()
		b.size = Vector3(r * 2.2, r * 0.18, r * 1.4) if _rng.randf() < 0.6 else Vector3(r * 0.3, r * 2.4, r * 0.3)
		mi.mesh = b
		mi.material_override = Models.mat([Color(0.75, 0.76, 0.8), Color(0.82, 0.66, 0.3), Color(0.12, 0.16, 0.34)][_rng.randi() % 3], 0.7, 0.35)
	else:
		# Rocky meteoroid: a coarse sphere squashed out of round.
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 7
		s.rings = 4
		mi.mesh = s
		mi.material_override = Models.mat(Color(0.42, 0.38, 0.34), 0.0, 0.95)
		mi.scale = Vector3(_rng.randf_range(0.7, 1.3), _rng.randf_range(0.6, 1.1), _rng.randf_range(0.8, 1.4))
	n.add_child(mi)
	return n

## A short white burst from a side thruster, fired when the ship dodges.
func _thruster_puff(at: Node3D, side: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.1
	p.mesh = q
	p.amount = 40
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.15
	p.direction = Vector3(side, 0.1, 0)
	p.spread = 14.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3.ZERO
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.7)
	m.albedo_texture = Models._soft_dot()
	p.material_override = m
	p.emitting = false
	at.add_child(p)
	return p

## Background pieces rush past the ship, never at it.
func _respawn_flyer(f: Dictionary, anywhere: bool) -> void:
	var n: Node3D = f.node
	var ang := _rng.randf() * TAU
	var off := _rng.randf_range(3.5, 26.0)
	n.position = Vector3(cos(ang) * off, sin(ang) * off * 0.6 + 0.5, START_Z * (_rng.randf() if anywhere else _rng.randf_range(0.8, 1.0)))
	f.v = _rng.randf_range(70.0, 150.0)
	f.spin = Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3), _rng.randf_range(-3, 3))

func _new_threat() -> void:
	if _threat:
		_threat.queue_free()
	_threat_r = 2.0
	_threat = _make_piece(_threat_r)
	_world.add_child(_threat)
	_threat_spin = Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5))
	_threat.position = _threat_path(0.0)

## The threat's straight-line path from far ahead to the ship's nose, arriving at k = 1.
func _threat_path(k: float) -> Vector3:
	var start := Vector3(-6.0, 4.0, START_Z)
	var hit := Vector3(0, 0.55, -0.6)
	return start.lerp(hit, k)

func _process(delta: float) -> void:
	for f: Dictionary in _flyers:
		var n: Node3D = f.node
		n.position.z += float(f.v) * delta
		n.rotation += (f.spin as Vector3) * delta
		if n.position.z > 8.0:
			_respawn_flyer(f, false)
	if _threat and is_instance_valid(_threat):
		_threat.rotation += _threat_spin * delta
	_phase_t += delta
	match state:
		"ask":
			_t += delta
			var left := ANSWER_TIME - _t
			_timer_bar.value = left / ANSWER_TIME
			_timer_label.text = "%.1f s" % maxf(left, 0.0)
			_threat.position = _threat_path(clampf(_t / ANSWER_TIME, 0.0, 1.0))
			if left <= 3.0 and int(ceilf(left)) != _beeped:
				_beeped = int(ceilf(left))
				Sfx.play("alarm", -14.0, 1.3)
			if left <= 0.0:
				_mark(-1)
				_begin_impact()
		"dodge":
			# Thrusters push the ship sideways and the threat flies past.
			var k := clampf(_phase_t / 1.4, 0.0, 1.0)
			var ease_k := 1.0 - pow(1.0 - k, 3.0)
			_rig.position.x = _dodge_dir * 5.0 * ease_k
			_rig.rotation.z = -_dodge_dir * 0.35 * sin(k * PI)
			_threat.position += Vector3(0, 0, 160.0) * delta
			if k >= 1.0:
				_explain(true)
		"impact":
			var k := clampf(_phase_t / 0.7, 0.0, 1.0)
			var from: float = clampf(_t / ANSWER_TIME, 0.0, 1.0)
			_threat.position = _threat_path(lerpf(from, 1.0, k * k))
			if k >= 1.0:
				_impact()
	_update_overlay(delta)

func _update_overlay(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		_cam.h_offset = randf_range(-1, 1) * _shake * 0.25
		_cam.v_offset = randf_range(-1, 1) * _shake * 0.25
	else:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.8)
	_overlay.show_target = state in ["ask", "impact"] and _threat != null and not _cam.is_position_behind(_threat.global_position)
	if _overlay.show_target:
		var p := _threat.global_position
		var c := _cam.unproject_position(p)
		var edge := _cam.unproject_position(p + _cam.global_transform.basis.x * _threat_r)
		_overlay.target = c
		_overlay.radius = c.distance_to(edge)
		var left := maxf(ANSWER_TIME - _t, 0.0) if state == "ask" else 0.0
		_overlay.label = "IMPACT IN %.1f s" % left if state == "ask" else "IMPACT"
	_overlay.queue_redraw()

# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_overlay = Overlay.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_title = UI.label("", 30, UI.BAD, "bold")
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_title)
	_box = UI.vbox(10)
	var pan := UI.panel(_box, 20)
	# On the right, so the spacecraft deck and the incoming threat stay in view.
	pan.custom_minimum_size.x = 600.0
	pan.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	pan.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pan.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(pan)

func _clear_box() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_buttons.clear()

func _ask() -> void:
	if _i >= questions.size():
		_finish()
		return
	state = "ask"
	_t = 0.0
	_phase_t = 0.0
	_beeped = -1
	_rig.position = Vector3.ZERO
	_rig.rotation = Vector3.ZERO
	_overlay.cracks.clear()
	_new_threat()
	_title.text = ("Meteoroid on a collision course!" if kind == "meteoroids" else "Space debris on a collision course!")
	Sfx.play("alarm", -6.0)
	_clear_box()
	var q: Dictionary = questions[_i]
	var head := UI.hbox(10)
	head.add_child(UI.eyebrow("Answer to fire the thrusters  ·  question %d of %d" % [_i + 1, questions.size()]))
	head.add_child(UI.spacer())
	_timer_label = UI.label("", 16, UI.AMBER, "mono")
	head.add_child(_timer_label)
	_box.add_child(head)
	_timer_bar = UI.bar(1.0, 1.0, UI.AMBER, 8.0)
	_box.add_child(_timer_bar)
	_q = UI.para(str(q.q), 22, UI.TEXT)
	_box.add_child(_q)
	_answers = Questions.arrange(q, _rng, _last_slot)
	_last_slot = _answers.find(str(q.right))
	for i in _answers.size():
		var idx := i
		var b := UI.button("[%d]   %s" % [i + 1, _answers[i]], func() -> void: answer(idx))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 46.0
		b.add_theme_font_size_override("font_size", 18)
		_box.add_child(b)
		_buttons.append(b)
	_focus_later(_buttons[0])

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if state == "ask" and key >= KEY_1 and key <= KEY_3:
		answer(int(key - KEY_1))
		get_viewport().set_input_as_handled()

## Answer by index into the shuffled options. Public so tests and the autotest can answer.
func answer(idx: int) -> void:
	if state != "ask" or idx < 0 or idx >= _answers.size():
		return
	var q: Dictionary = questions[_i]
	var ok := str(_answers[idx]) == str(q.right)
	_mark(idx)
	Classroom.record_debris(q, ok)
	if ok:
		right_count += 1
		state = "dodge"
		_phase_t = 0.0
		_dodge_dir = -1.0 if _threat.position.x > 0.0 else 1.0
		# Moving right means firing the left-hand thruster, and the other way round.
		var puff: CPUParticles3D = _puffs.get("ThrusterL" if _dodge_dir > 0.0 else "ThrusterR")
		if puff:
			puff.restart()
		_title.text = "Thrusters firing!"
		_title.add_theme_color_override("font_color", UI.GOOD)
		Sfx.play("stage", -4.0)
		Game.add_science(8.0)
	else:
		_begin_impact()

func right_index() -> int:
	return _answers.find(str((questions[_i] as Dictionary).right))

func _mark(chosen: int) -> void:
	var right := right_index()
	for i in _buttons.size():
		_buttons[i].disabled = true
		if i == right:
			_buttons[i].add_theme_stylebox_override("disabled", UI.box(UI.GOOD.darkened(0.45), UI.GOOD, 8, 10))
			_buttons[i].add_theme_color_override("font_disabled_color", Color.WHITE)
		elif i == chosen:
			_buttons[i].add_theme_stylebox_override("disabled", UI.box(UI.BAD.darkened(0.5), UI.BAD, 8, 10))
			_buttons[i].add_theme_color_override("font_disabled_color", Color.WHITE)

func _begin_impact() -> void:
	state = "impact"
	_phase_t = 0.0
	if _t >= ANSWER_TIME:
		Classroom.record_debris(questions[_i], false)

func _impact() -> void:
	Sfx.play("crash", -2.0)
	_flash.color.a = 0.85
	_shake = 0.7
	_threat.visible = false
	var c := size * 0.5
	for i in 7:
		var a := float(i) / 7.0 * TAU + _rng.randf_range(-0.3, 0.3)
		var pts := PackedVector2Array([c])
		var p := c
		for s in 5:
			p += Vector2(cos(a), sin(a)).rotated(_rng.randf_range(-0.5, 0.5)) * _rng.randf_range(40, 110)
			pts.append(p)
		_overlay.cracks.append(pts)
	# A hit costs mission efficiency (a game value), never the mission itself.
	Game.mission.correction_quality = float(Game.mission.correction_quality) * 0.9
	_title.text = "Impact! The shield took the hit"
	_title.add_theme_color_override("font_color", UI.BAD)
	_explain(false)

func _explain(ok: bool) -> void:
	state = "explain"
	var q: Dictionary = questions[_i]
	_why = UI.vbox(6)
	_why.add_child(UI.label("Right: the thrusters dodged it. +8 science" if ok else "The answer: " + str(q.right), 18, UI.GOOD if ok else UI.AMBER, "bold"))
	_why.add_child(UI.para(str(q.why), 17, UI.TEXT))
	if not ok:
		_why.add_child(UI.para("Hits lower your mission efficiency score a little. The mission carries on.", 14, UI.TEXT_DIM))
	_box.add_child(_why)
	var go := UI.button("Continue" if _i + 1 < questions.size() else "Back to the cruise", next, true)
	_box.add_child(go)
	_focus_later(go)

func next() -> void:
	if state != "explain":
		return
	_i += 1
	_title.remove_theme_color_override("font_color")
	_title.add_theme_color_override("font_color", UI.BAD)
	_ask()

func _finish() -> void:
	state = "done"
	finished.emit(right_count, questions.size())
	queue_free()

## Focus a button once it is on screen; skipped if it was already replaced (a fast answer, a rebuild).
func _focus_later(b: Control) -> void:
	(func() -> void:
		if is_instance_valid(b) and b.is_inside_tree():
			b.grab_focus()).call_deferred()
