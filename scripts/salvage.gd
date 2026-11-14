class_name SalvageGame
extends Control
## Strip parts from a derelict lander and bolt them onto your rover.
## Remove: grab a bolt and turn it anticlockwise until it comes out.
## Install: tighten each bolt clockwise in the order on the spec sheet, and let go when the torque
## wrench reads inside the spec band. Too little is loose; far too much strips the thread.
## Grab a bolt, then circle the mouse around it (a wider circle gives finer control), or use the mouse wheel.

signal finished(result: Dictionary)

const PARTS := [
	{"id": "battery", "name": "Battery pack", "bolt": "M8", "spec": 12.0, "tol": 1.0, "order": [0, 2, 1, 3], "reward": "Repairs the rover: +40 health",
	 "holes": [Vector2(-70, -45), Vector2(70, -45), Vector2(-70, 45), Vector2(70, 45)]},
	{"id": "motor", "name": "Wheel drive motor", "bolt": "M6", "spec": 8.5, "tol": 0.7, "order": [0, 2, 1, 3], "reward": "Faster rover: +10% top speed",
	 "holes": [Vector2(0, -60), Vector2(60, 0), Vector2(0, 60), Vector2(-60, 0)]},
	{"id": "antenna", "name": "High-gain antenna", "bolt": "M5", "spec": 5.0, "tol": 0.5, "order": [0, 1, 2], "reward": "Sends more data home: +25 science",
	 "holes": [Vector2(0, -55), Vector2(50, 35), Vector2(-50, 35)]},
]
const REMOVE_TURNS := 2.0
const SNUG_TURNS := 1.0
## Newton-metres gained per turn past snug, as a multiple of the spec.
const TORQUE_PER_TURN := 1.25
const STRIP_FACTOR := 1.5
const BOLT_R := 15.0

var part_i := 0
var phase := "remove"   # remove → move → install → done
var bolts: Array[Dictionary] = []
var active := -1
var results: Array[Dictionary] = []
var wreck_name := "Derelict lander"
var _last_angle := 0.0
var _move_t := 0.0
var _msg := ""
var _msg_t := 0.0
var _t := 0.0
var _panel: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_part()

func part() -> Dictionary:
	return PARTS[part_i]

func _start_part() -> void:
	phase = "remove"
	active = -1
	bolts.clear()
	for h: Vector2 in part().holes:
		bolts.append({"hole": h, "turns": 0.0, "out": false, "torque": 0.0, "state": "loose"})
	if part_i == 0:
		_say("Unscrew the %s from the old lander: grab a bolt and turn it anticlockwise." % part().name)

func _say(text: String) -> void:
	_msg = text
	_msg_t = 4.0

# --- layout -------------------------------------------------------------------------------------

func _old_center() -> Vector2:
	return Vector2(size.x * 0.27, size.y * 0.55)

func _new_center() -> Vector2:
	return Vector2(size.x * 0.62, size.y * 0.55)

func bolt_pos(i: int) -> Vector2:
	var h: Vector2 = bolts[i].hole
	var c := _old_center() if phase == "remove" else _new_center()
	if phase == "move":
		c = _old_center().lerp(_new_center(), smoothstep(0.0, 1.0, _move_t))
	return c + h

# --- input --------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if phase != "remove" and phase != "install":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_grab(mb.position)
			else:
				_release()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			# Wheel down tightens, wheel up loosens: 1/24 of a turn per notch.
			var i := _bolt_at(mb.position)
			if i >= 0 and _can_use(i):
				active = i
				turn(i, (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) / 24.0)
				if phase == "install":
					_settle(i)
				active = -1
	elif event is InputEventMouseMotion and active >= 0:
		var mm := event as InputEventMouseMotion
		var c := bolt_pos(active)
		var a := (mm.position - c).angle()
		var d := wrapf(a - _last_angle, -PI, PI)
		_last_angle = a
		# Angles grow clockwise on screen, because y points down.
		turn(active, d / TAU)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		finished.emit(summary())

func _bolt_at(p: Vector2) -> int:
	for i in bolts.size():
		if not bolts[i].out and p.distance_to(bolt_pos(i)) < BOLT_R + 12.0:
			return i
	return -1

func _can_use(i: int) -> bool:
	if phase == "remove":
		return not bolts[i].out
	if bolts[i].state == "ok" or bolts[i].state == "over" or bolts[i].state == "stripped":
		return false
	var next := next_in_order()
	if i != next:
		_say("Follow the tightening order on the spec sheet: bolt %d is next." % (next + 1))
		Sfx.play("click", -8.0, 0.6)
		return false
	return true

func _grab(p: Vector2) -> void:
	var i := _bolt_at(p)
	if i < 0 or not _can_use(i):
		return
	active = i
	# Grabbing from the bolt's own centre gives no angle yet; nudge the reference to the right of it.
	var off := p - bolt_pos(i)
	_last_angle = off.angle() if off.length() > 2.0 else 0.0
	Sfx.play("click", -8.0, 1.4)

func _release() -> void:
	if active < 0:
		return
	if phase == "install":
		_settle(active)
	active = -1

## The bolt index that must be tightened next.
func next_in_order() -> int:
	for k: int in part().order:
		var st: String = bolts[k].state
		if st != "ok" and st != "over" and st != "stripped":
			return k
	return -1

# --- mechanics ----------------------------------------------------------------------------------

## Turn a bolt by a fraction of a revolution: positive = clockwise (tighten).
func turn(i: int, revs: float) -> void:
	var b: Dictionary = bolts[i]
	if phase == "remove":
		if revs >= 0.0:
			return
		b.turns = float(b.turns) - revs
		if int(float(b.turns) * 8.0) != int((float(b.turns) + revs) * 8.0):
			Sfx.play("click", -18.0, randf_range(0.8, 1.0))
		if float(b.turns) >= REMOVE_TURNS:
			b.out = true
			active = -1
			Sfx.play("collect", -8.0, 1.3)
			if _all_out():
				phase = "move"
				_move_t = 0.0
				for o: Dictionary in bolts:
					o.out = false
					o.turns = 0.0
				_say("Part free. Carrying it over to your rover.")
	elif phase == "install":
		b.turns = maxf(float(b.turns) + revs, 0.0)
		b.torque = torque_for(float(b.turns))
		if float(b.torque) > float(part().spec) * STRIP_FACTOR:
			b.state = "stripped"
			active = -1
			Sfx.play("crash", -8.0, 2.2)
			_say("Stripped the thread! That bolt will never hold full torque.")
			_check_part_done()

func torque_for(turns: float) -> float:
	return maxf(turns - SNUG_TURNS, 0.0) * TORQUE_PER_TURN * float(part().spec)

## Let go of the wrench: judge the bolt against the spec sheet.
func _settle(i: int) -> void:
	var b: Dictionary = bolts[i]
	if b.state == "stripped":
		return
	var spec := float(part().spec)
	var tol := float(part().tol)
	var tq := float(b.torque)
	if tq < spec - tol:
		b.state = "loose" if tq < 0.5 else "under"
		if tq >= 0.5:
			_say("%.1f N·m is under spec. Keep tightening bolt %d." % [tq, i + 1])
		return
	if tq <= spec + tol:
		b.state = "ok"
		Sfx.play("chime", -10.0, 1.4)
	else:
		b.state = "over"
		Sfx.play("click", -6.0, 0.5)
		_say("%.1f N·m is over spec. It holds, but the part is stressed." % tq)
	_check_part_done()

func _all_out() -> bool:
	for b: Dictionary in bolts:
		if not b.out:
			return false
	return true

func _check_part_done() -> void:
	if next_in_order() >= 0:
		return
	var ok := 0
	var stripped := 0
	for b: Dictionary in bolts:
		if b.state == "ok":
			ok += 1
		elif b.state == "stripped":
			stripped += 1
	results.append({"id": part().id, "name": part().name, "bolts": bolts.size(), "ok": ok, "stripped": stripped, "works": stripped == 0})
	if stripped == 0:
		_say("%s installed. %s." % [part().name, part().reward])
	else:
		_say("%s fitted, but a stripped bolt means it won't work." % part().name)
	if part_i + 1 < PARTS.size():
		_msg += "  Next: the %s." % str(PARTS[part_i + 1].name).to_lower()
	part_i += 1
	if part_i >= PARTS.size():
		phase = "done"
		_show_summary()
	else:
		_start_part()

func summary() -> Dictionary:
	var total := 0
	var ok := 0
	var stripped := 0
	var working: Array[String] = []
	for r: Dictionary in results:
		total += int(r.bolts)
		ok += int(r.ok)
		stripped += int(r.stripped)
		if r.works:
			working.append(str(r.id))
	return {"bolts": total, "in_spec": ok, "stripped": stripped, "working": working, "parts": results.size()}

func _show_summary() -> void:
	var s := summary()
	var v := UI.vbox(12)
	_panel = UI.panel(v, 26)
	_panel.custom_minimum_size.x = 520.0
	v.add_child(UI.eyebrow("Salvage complete"))
	v.add_child(UI.heading("%d of %d parts working" % [(s.working as Array).size(), int(s.parts)], 30))
	var g := UI.grid(2)
	v.add_child(g)
	UI.kv(g, "Bolts in spec", "%d of %d" % [int(s.in_spec), int(s.bolts)], UI.GOOD if int(s.in_spec) == int(s.bolts) else UI.AMBER)
	UI.kv(g, "Stripped", str(s.stripped), UI.BAD if int(s.stripped) > 0 else UI.TEXT)
	for r: Dictionary in results:
		var reward := str(PARTS.filter(func(p: Dictionary) -> bool: return p.id == r.id)[0].reward)
		UI.kv(g, str(r.name), reward if r.works else "not working", UI.GOOD if r.works else UI.BAD)
	UI.kv(g, "Science", "+%d (5 per bolt in spec)" % (int(s.in_spec) * 5), UI.GOOD)
	var go := UI.button("Back to driving", func() -> void: finished.emit(summary()), true)
	v.add_child(go)
	add_child(_panel)
	UI.center_panel(_panel)
	go.grab_focus.call_deferred()

## Tests and the autotest: do every step perfectly through the same mechanics a player uses.
func auto_complete() -> void:
	var guard := 0
	while phase != "done" and guard < 50:
		guard += 1
		if phase == "remove":
			for i in bolts.size():
				active = i
				turn(i, -REMOVE_TURNS - 0.1)
		if phase == "move":
			_move_t = 1.0
			_finish_move()
		if phase == "install":
			var i := next_in_order()
			if i < 0:
				break
			active = i
			turn(i, SNUG_TURNS + 1.0 / TORQUE_PER_TURN - float(bolts[i].turns))
			_settle(i)
			active = -1

func _finish_move() -> void:
	phase = "install"
	for b: Dictionary in bolts:
		b.turns = 0.0
		b.torque = 0.0
		b.state = "loose"
	_say("Now torque it down. Order and torque are on the spec sheet, top right.")

func _process(delta: float) -> void:
	_t += delta
	_msg_t = maxf(_msg_t - delta, 0.0)
	if phase == "move":
		_move_t += delta / 1.1
		if _move_t >= 1.0:
			_finish_move()
	queue_redraw()

# --- drawing ------------------------------------------------------------------------------------

func _draw() -> void:
	var vs := size
	var f := UI.font()
	var fb := UI.font_bold()
	var fm := UI.font_mono()
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.04, 0.06, 0.94))
	draw_string(fb, Vector2(32, 40), "SALVAGE  ·  " + wreck_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.ACCENT)
	draw_string(fb, Vector2(32, 76), "Part %d of %d: %s" % [mini(part_i + 1, PARTS.size()), PARTS.size(), part().name if part_i < PARTS.size() else "done"], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UI.TEXT)
	var how := "Grab a bolt and circle the mouse anticlockwise to unscrew it. A wider circle is finer."
	if phase == "install":
		how = "Grab the next bolt and circle clockwise. Let go when the wrench needle is in the green band."
	draw_string(f, Vector2(32, 106), how + "  Mouse wheel works too.", HORIZONTAL_ALIGNMENT_LEFT, vs.x * 0.62, 15, UI.TEXT_DIM)
	_draw_bench(_old_center(), "OLD LANDER", Color(0.42, 0.32, 0.24), true)
	_draw_bench(_new_center(), "YOUR ROVER", Color(0.22, 0.3, 0.4), false)
	if part_i < PARTS.size() and phase != "done":
		_draw_part()
		for i in bolts.size():
			_draw_bolt(i)
	# The torque wrench dial sits beside the rover's bench, clear of the bolts.
	var dial := _new_center() + Vector2(270, 40)
	if phase == "install" and active >= 0:
		_draw_wrench(dial)
	elif phase == "install":
		var nx := next_in_order()
		if nx >= 0:
			_draw_wrench(dial, nx)
	_draw_spec(fb, f, fm)
	if _msg_t > 0.0:
		var a := clampf(_msg_t, 0.0, 1.0)
		draw_string(fb, Vector2(0, vs.y - 40), _msg, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 18, Color(UI.AMBER, a))

func _draw_bench(c: Vector2, title: String, col: Color, rusty: bool) -> void:
	var r := Rect2(c - Vector2(150, 130), Vector2(300, 260))
	draw_rect(r, col.darkened(0.55))
	draw_rect(r, col, false, 2.0)
	if rusty:
		for k in 9:
			var p := r.position + Vector2(fmod(float(k) * 97.0, 280.0) + 10.0, fmod(float(k) * 53.0, 240.0) + 10.0)
			draw_circle(p, 6.0 + float(k % 3) * 4.0, Color(0.55, 0.3, 0.15, 0.35))
	draw_string(UI.font_bold(), r.position + Vector2(0, -10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TEXT_DIM)

func _draw_part() -> void:
	var c := _old_center() if phase == "remove" else (_new_center() if phase == "install" else _old_center().lerp(_new_center(), smoothstep(0.0, 1.0, _move_t)))
	var lift := -10.0 * sin(clampf(_move_t, 0.0, 1.0) * PI) if phase == "move" else 0.0
	c.y += lift
	var dusty := phase == "remove"
	match str(part().id):
		"battery":
			draw_rect(Rect2(c - Vector2(95, 65), Vector2(190, 130)), Color(0.25, 0.27, 0.3) if not dusty else Color(0.35, 0.3, 0.26))
			for k in 4:
				draw_rect(Rect2(c + Vector2(-80 + k * 42, -20), Vector2(32, 40)), Color(0.15, 0.4, 0.25))
			draw_string(UI.font_bold(), c + Vector2(-60, 5), "28 V", HORIZONTAL_ALIGNMENT_CENTER, 120, 14, UI.TEXT)
		"motor":
			draw_circle(c, 80.0, Color(0.4, 0.42, 0.45) if not dusty else Color(0.45, 0.38, 0.3))
			draw_circle(c, 34.0, Color(0.22, 0.23, 0.25))
			draw_arc(c, 50.0, 0.0, TAU, 40, Color(0.6, 0.62, 0.66), 3.0)
		_:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -82), c + Vector2(76, 58), c + Vector2(-76, 58)]), Color(0.75, 0.76, 0.78) if not dusty else Color(0.6, 0.52, 0.42))
			draw_arc(c + Vector2(0, -10), 40.0, PI * 1.15, PI * 1.85, 24, Color(0.3, 0.32, 0.36), 6.0)

func _draw_bolt(i: int) -> void:
	var b: Dictionary = bolts[i]
	if b.out:
		return
	var p := bolt_pos(i)
	var spin := float(b.turns) * TAU * (-1.0 if phase == "remove" else 1.0)
	var col := Color(0.7, 0.72, 0.75)
	if phase == "remove":
		col = Color(0.62, 0.45, 0.32)
	match str(b.state):
		"ok":
			col = UI.GOOD
		"over":
			col = UI.AMBER
		"stripped":
			col = UI.BAD
	if phase == "install" and i == next_in_order() and active < 0:
		draw_arc(p, BOLT_R + 7.0 + 2.0 * sin(_t * 5.0), 0.0, TAU, 32, UI.ACCENT, 2.0)
	if active == i:
		draw_arc(p, BOLT_R + 8.0, 0.0, TAU, 32, Color.WHITE, 2.0)
	var hexp := PackedVector2Array()
	for k in 6:
		hexp.append(p + Vector2.from_angle(spin + TAU * float(k) / 6.0) * BOLT_R)
	draw_colored_polygon(hexp, col.darkened(0.25))
	hexp.append(hexp[0])
	draw_polyline(hexp, col, 2.0)
	draw_circle(p, 4.0, col.darkened(0.5))
	if phase == "remove":
		var u := clampf(float(b.turns) / REMOVE_TURNS, 0.0, 1.0)
		if u > 0.0:
			draw_arc(p, BOLT_R + 4.0, -PI * 0.5, -PI * 0.5 - TAU * u, 32, UI.ACCENT, 3.0)
	else:
		var order: Array = part().order
		draw_string(UI.font_bold(), p + Vector2(BOLT_R + 4.0, -BOLT_R), str(order.find(i) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TEXT)

## A dial torque wrench: green band = spec ± tolerance; red past the strip point.
func _draw_wrench(c: Vector2, i: int = -1) -> void:
	var idx := active if i < 0 else i
	var spec := float(part().spec)
	var tol := float(part().tol)
	var top := spec * 1.7
	var tq := float(bolts[idx].torque)
	var r := 62.0
	var a0 := PI * 0.85
	var a1 := PI * 2.15
	var ang := func(v: float) -> float: return a0 + (a1 - a0) * clampf(v / top, 0.0, 1.0)
	draw_circle(c, r + 10.0, Color(0.06, 0.08, 0.11))
	draw_arc(c, r, a0, a1, 48, Color(0.3, 0.35, 0.42), 8.0)
	draw_arc(c, r, ang.call(spec - tol), ang.call(spec + tol), 16, UI.GOOD, 8.0)
	draw_arc(c, r, ang.call(spec * STRIP_FACTOR), a1, 16, UI.BAD, 8.0)
	var na: float = ang.call(tq)
	draw_line(c, c + Vector2.from_angle(na) * (r - 6.0), Color.WHITE, 3.0)
	draw_circle(c, 6.0, Color.WHITE)
	draw_string(UI.font_mono(), c + Vector2(-60, 34), "%.1f N·m" % tq, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, UI.TEXT)

func _draw_spec(fb: Font, f: Font, fm: Font) -> void:
	var w := 300.0
	var r := Rect2(Vector2(size.x - w - 24.0, 24.0), Vector2(w, 214.0))
	draw_rect(r, Color(0.93, 0.92, 0.86))
	draw_rect(r, Color(0.5, 0.48, 0.4), false, 1.5)
	var x := r.position.x + 16.0
	var y := r.position.y + 28.0
	var ink := Color(0.12, 0.13, 0.15)
	draw_string(fb, Vector2(x, y), "SPEC SHEET", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.15, 0.1))
	if part_i >= PARTS.size():
		return
	var p := part()
	draw_string(fb, Vector2(x, y + 26), str(p.name), HORIZONTAL_ALIGNMENT_LEFT, w - 32, 17, ink)
	draw_string(fm, Vector2(x, y + 52), "Fasteners   %d × %s" % [(p.holes as Array).size(), str(p.bolt)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	draw_string(fm, Vector2(x, y + 74), "Torque      %.1f ± %.1f N·m" % [float(p.spec), float(p.tol)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	var seq := PackedStringArray()
	for k: int in p.order:
		seq.append(str(k + 1))
	draw_string(fm, Vector2(x, y + 96), "Order       " + " → ".join(seq), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	draw_string(fm, Vector2(x, y + 118), "Strips at   %.1f N·m" % (float(p.spec) * STRIP_FACTOR), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	draw_string(f, Vector2(x, y + 146), str(p.reward), HORIZONTAL_ALIGNMENT_LEFT, w - 32, 13, Color(0.15, 0.4, 0.2))
	draw_string(f, Vector2(x, y + 170), "Game values, not a real NASA spec.", HORIZONTAL_ALIGNMENT_LEFT, w - 32, 11, Color(0.4, 0.4, 0.4))
