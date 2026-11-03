extends Control
## The flight: the same Sim as the prediction, plus wind. A hand on the controls keeps it straight.

const END_ANIM := 5.0

var sim
var design: Dictionary
var state := "ready"  # ready, flying, finishing, done
var predicted := 0.0
var apogee := 0.0
var auto_steer := false
var _gust_rng := RandomNumberGenerator.new()
var _gust := 0.0
var _gust_t := 0.0
var _trail: Array = []
var _debris: Array = []
var _sparks: Array = []
var _shown_h := 0.0
var _finish_from := 0.0
var _finish_t := 0.0
var _boost_on := true
var _main_on := true
var _toast: VBoxContainer
var _toast_panel: PanelContainer
var _toast_t := 0.0
var _passed: Dictionary = {}
var _card: HudCard
var _ui: Control
var _result: Control
var _stars := PackedVector2Array()
var _clouds: Array = []
var _shake := 0.0

func _ready() -> void:
	theme = UI.theme()
	Sfx.stop_loops()
	design = Rocket2D.design.duplicate()
	sim = Rocket2D.make_sim(design)
	predicted = float(Rocket2D.predict(design).apogee)
	_gust_rng.randomize()
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 240:
		_stars.append(Vector2(r.randf(), r.randf()))
	for i in 40:
		_clouds.append({"x": r.randf_range(-900.0, 900.0), "h": r.randf_range(600.0, 11000.0), "w": r.randf_range(80.0, 260.0)})
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_card = HudCard.new("Flight %d of %d" % [Rocket2D.FLIGHTS_PER_GAME - Rocket2D.flights_left + 1, Rocket2D.FLIGHTS_PER_GAME], "Predicted: %s" % Rocket2D.format_height(predicted))
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 18)
	_ui.add_child(_card)
	_card.add_row("height", "Height")
	_card.add_row("speed", "Speed")
	_card.add_row("straight", "Pointing")
	_toast = UI.vbox(4)
	_toast_panel = UI.panel(_toast, 14)
	_toast_panel.custom_minimum_size.x = 560.0
	_toast_panel.visible = false
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_toast_panel)
	if float(Rocket2D.predict(design).twr) <= 1.0:
		_card.set_tip("Too heavy to lift off. Press %s to try anyway" % Settings.key_name("thrust"))

func launch() -> void:
	if state != "ready":
		return
	state = "flying"
	Sfx.play("stage")
	Sfx.loop("engine", 0.55)

func _physics_process(delta: float) -> void:
	advance(delta)

func _warp() -> float:
	if sim.burning():
		return 3.0
	return 5.0 + clampf(sim.h / 4000.0, 0.0, 15.0)

## One step of flight. Public so tests can run a whole flight.
func advance(delta: float) -> void:
	match state:
		"ready":
			if Input.is_action_just_pressed("thrust"):
				launch()
		"flying":
			_fly(delta)
		"finishing":
			_finish_t += delta
			var k := clampf(_finish_t / END_ANIM, 0.0, 1.0)
			# Ease out: the rocket slows as it nears its highest point.
			_shown_h = lerpf(_finish_from, apogee, 1.0 - pow(1.0 - k, 3.0))
			_check_milestones(_shown_h)
			if k >= 1.0:
				_land(false)
	_update_effects(delta)
	queue_redraw()

func _fly(delta: float) -> void:
	var steer := Input.get_axis("move_left", "move_right")
	if auto_steer:
		steer = clampf(-sim.theta * 3.0 - sim.omega * 2.0, -1.0, 1.0)
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = _gust_rng.randf_range(0.6, 2.0)
		_gust = _gust_rng.randf_range(-1.0, 1.0)
	# A rocket that cannot lift off ends quickly, rather than burning on the pad for minutes.
	if not sim.lifted and sim.t > 6.0:
		sim.step(0.01)
		if not sim.lifted:
			apogee = 0.0
			Sfx.loop("engine", 0.0)
			state = "done"
			_show_result(false)
			return
	var was_b: bool = sim.b_attached
	var was_m: bool = sim.main_attached
	var total: float = delta * _warp()
	var steps: int = maxi(ceili(total / 0.06), 1)
	var dt: float = total / float(steps)
	# Wind matters while the air is thick, and fades with height.
	var wind: float = _gust * 0.5 * clampf(sim.q / 6000.0, 0.0, 1.0)
	for i in steps:
		sim.step(dt, steer, wind)
		if sim.broken or sim.crashed or (not sim.burning() and (sim.vy <= 0.0 or sim.h >= 120000.0)):
			break
	_shown_h = sim.h
	if was_b and not sim.b_attached:
		_drop("boosters")
	if was_m and not sim.main_attached:
		_drop("main")
	_check_milestones(sim.h)
	if sim.broken:
		_break_up()
	elif sim.crashed:
		apogee = sim.h_max
		_land(false)
	elif not sim.burning():
		Sfx.loop("engine", 0.0)
		if not sim.lifted:
			apogee = 0.0
			_land(false)
		elif sim.h >= 120000.0:
			apogee = maxf(Rocket2D.apogee_from(sim), sim.h_max)
			_finish_from = sim.h
			_finish_t = 0.0
			state = "finishing"
		elif sim.vy <= 0.0:
			apogee = sim.h_max
			_land(false)
	var pct: float = absf(rad_to_deg(sim.theta))
	var straight := "Straight up"
	var col := UI.GOOD
	if pct > 25.0:
		straight = "Way off! Steer back"
		col = UI.BAD
	elif pct > 7.0:
		straight = "Leaning %s" % ("right" if sim.theta > 0.0 else "left")
		col = UI.AMBER
	_card.set_row("straight", straight, col)

func _drop(which: String) -> void:
	Sfx.play("stage")
	_debris.append({"which": which, "h": sim.h, "x": sim.x, "vy": sim.vy * 0.6, "angle": sim.theta, "t": 0.0, "spin": _gust_rng.randf_range(-1.0, 1.0)})
	_shake = 0.4

func _break_up() -> void:
	state = "done"
	apogee = maxf(sim.h_max, 0.0)
	Sfx.loop("engine", 0.0)
	Sfx.play("crash")
	_shake = 1.0
	for i in 40:
		_sparks.append({"p": Vector2.ZERO, "v": Vector2(_gust_rng.randf_range(-260.0, 260.0), _gust_rng.randf_range(-260.0, 260.0)), "t": _gust_rng.randf_range(0.5, 1.4)})
	_show_result(true)

func _land(_x: bool) -> void:
	state = "done"
	Sfx.loop("engine", 0.0)
	Sfx.play("chime")
	_show_result(false)

func _check_milestones(h: float) -> void:
	for m: Dictionary in Data.milestones:
		if not _passed.has(m.id) and h >= float(m.km) * 1000.0:
			_passed[m.id] = true
			Sfx.play("chime", -4.0)
			_show_toast(m)

func _show_toast(m: Dictionary) -> void:
	for c in _toast.get_children():
		_toast.remove_child(c)
		c.queue_free()
	_toast.add_child(UI.eyebrow("Passed %s km" % UI.grouped(int(m.km))))
	_toast.add_child(UI.heading(str(m.name), 21))
	_toast.add_child(UI.fact_block({"text": m.text, "url": m.url}, 14))
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	_toast_t = 6.0

func _update_effects(delta: float) -> void:
	var v: float = sqrt(sim.vx * sim.vx + sim.vy * sim.vy)
	if state == "flying" and sim.thrust_now > 0.0 and sim.lifted and randf() < 0.7:
		_trail.append({"h": sim.h, "x": sim.x, "t": 1.6})
	var i := _trail.size() - 1
	while i >= 0:
		_trail[i].t = float(_trail[i].t) - delta
		if float(_trail[i].t) <= 0.0:
			_trail.remove_at(i)
		i -= 1
	for d: Dictionary in _debris:
		d.t = float(d.t) + delta
	i = _sparks.size() - 1
	while i >= 0:
		_sparks[i].t = float(_sparks[i].t) - delta
		_sparks[i].p += _sparks[i].v * delta
		if float(_sparks[i].t) <= 0.0:
			_sparks.remove_at(i)
		i -= 1
	_shake = maxf(_shake - delta * 2.0, 0.0)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast_panel.modulate.a = clampf(_toast_t, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast_panel.visible = false
	if state == "done":
		return
	_card.set_row("height", Rocket2D.format_height(maxf(_shown_h, 0.0)))
	_card.set_row("speed", "%s km/h" % UI.grouped(int(v * 3.6)))
	match state:
		"ready":
			if float(Rocket2D.predict(design).twr) > 1.0:
				_card.set_tip("Press %s to launch" % Settings.key_name("thrust"))
		"flying":
			if sim.burning():
				_card.set_tip("Keep it straight with %s and %s. Wind pushes you around" % [Settings.key_name("move_left"), Settings.key_name("move_right")])
			else:
				_card.set_tip("Engines off. Coasting up...")
		"finishing":
			_card.set_tip("Coasting to your highest point...")

# ---- Drawing ----

func _sky_color(h: float) -> Array:
	var t := clampf(log(maxf(h, 1.0)) / log(100000.0), 0.0, 1.0)
	t = t * t
	var top: Color = Color(0.2, 0.42, 0.78).lerp(Color(0.0, 0.0, 0.02), t)
	var bottom: Color = Color(0.68, 0.84, 0.96).lerp(Color(0.02, 0.03, 0.08), t)
	return [top, bottom]

func _draw() -> void:
	var w := size.x
	var hgt := size.y
	var h: float = maxf(_shown_h, 0.0)
	var sky := _sky_color(h)
	var rows := 24
	for r in rows:
		var t := float(r) / float(rows)
		draw_rect(Rect2(0, t * hgt, w, hgt / float(rows) + 1.0), (sky[0] as Color).lerp(sky[1], t))
	# Stars appear as the air thins.
	var star_a := clampf((h - 20000.0) / 60000.0, 0.0, 1.0)
	if star_a > 0.0:
		for s in _stars:
			draw_rect(Rect2(s.x * w, s.y * hgt, 2, 2), Color(1, 1, 1, star_a * (0.4 + fmod(s.x * 37.0, 0.6))))
	var anchor := Vector2(w * 0.5, hgt * 0.56)
	var rocket_h := R2DDraw.total_height(design)
	var scale_px: float = clampf(240.0 / rocket_h, 8.0, 34.0)
	var shake_v := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 5.0
	var s_h: float = scale_px
	# From high up, Earth curves away below the rocket.
	var earth_r: float = float(sim.radius)
	if h > 3000.0:
		var view := clampf(h * 2.4, 12000.0, earth_r * 4.0)
		var px_per_m := hgt / view
		var center := Vector2(w * 0.5, anchor.y + 170.0 + (earth_r + h) * px_per_m - h * px_per_m + (h * px_per_m - minf(h * px_per_m, hgt * 0.42)))
		if earth_r * px_per_m > 2.0:
			_draw_earth(center, earth_r * px_per_m, h)
	# Ground and clouds up close
	var ground_y: float = anchor.y + scale_px + h * s_h * 0.16
	if ground_y < hgt + 40.0:
		draw_rect(Rect2(0, ground_y, w, hgt - ground_y + 40.0), Color(0.24, 0.38, 0.22))
		draw_rect(Rect2(w * 0.5 - 90.0, ground_y - 4.0, 180.0, 8.0), Color(0.42, 0.42, 0.45))
		if h < 40.0:
			draw_rect(Rect2(w * 0.5 + 60.0, ground_y - 180.0, 10.0, 180.0), Color(0.62, 0.22, 0.13))
	for c: Dictionary in _clouds:
		var cy: float = anchor.y + (h - float(c.h)) * 0.16
		if cy > -40.0 and cy < hgt + 40.0:
			var cx: float = w * 0.5 + float(c.x)
			draw_circle(Vector2(cx, cy), float(c.w) * 0.22, Color(1, 1, 1, 0.5))
			draw_circle(Vector2(cx + float(c.w) * 0.25, cy + 6.0), float(c.w) * 0.17, Color(1, 1, 1, 0.45))
			draw_circle(Vector2(cx - float(c.w) * 0.25, cy + 6.0), float(c.w) * 0.15, Color(1, 1, 1, 0.45))
	# Exhaust trail
	for tr: Dictionary in _trail:
		var dy: float = (h - float(tr.h)) * 0.16
		var dx: float = (float(tr.x) - float(sim.x)) * 0.16
		var a: float = clampf(float(tr.t) / 1.6, 0.0, 1.0)
		draw_circle(anchor + Vector2(dx, dy + scale_px * 1.5), 5.0 + (1.0 - a) * 24.0, Color(1, 1, 1, a * 0.3 * (1.0 - star_a * 0.7)))
	# Dropped stages falling away
	for d: Dictionary in _debris:
		var fall: float = float(d.t) * float(d.t) * 40.0 + float(d.t) * 60.0
		var p := anchor + Vector2(float(d.spin) * float(d.t) * 40.0, fall)
		if p.y < hgt + 80.0:
			var parts: Dictionary = design
			R2DDraw.draw(self, p, scale_px * 0.8, float(d.spin) * float(d.t), _debris_design(parts, str(d.which)), str(d.which) == "boosters", true)
	# The rocket
	var angle: float = sim.theta if state != "finishing" else 0.0
	var pos := anchor + shake_v
	if not sim.broken:
		_draw_flames(pos, scale_px, angle)
		R2DDraw.draw(self, pos, scale_px, angle, design, sim.b_attached, sim.main_attached)
	for sp: Dictionary in _sparks:
		var col := Color(1.0, 0.7, 0.2).lerp(Color(0.3, 0.1, 0.05), 1.0 - clampf(float(sp.t), 0.0, 1.0))
		draw_circle(anchor + (sp.p as Vector2), 3.0 + float(sp.t) * 7.0, col)
	_draw_ladder(w, hgt, h)

func _debris_design(d: Dictionary, which: String) -> Dictionary:
	var out := d.duplicate()
	out.utank = "u0"
	out.uengine = "ue0"
	if which == "boosters":
		out.fins = "nofins"
	return out

func _draw_earth(center: Vector2, r: float, h: float) -> void:
	var glow_a := clampf(1.0 - h / 8000000.0, 0.15, 0.6)
	draw_circle(center, r * 1.012, Color(0.35, 0.6, 1.0, glow_a))
	draw_circle(center, r, Color(0.08, 0.26, 0.5))
	# Simple land and cloud shapes, drawn only when the planet fits on screen.
	if r < 1600.0:
		for a: Array in [[-1.2, 0.45, 0.2], [-0.4, 0.3, 0.3], [0.6, 0.5, 0.22], [1.5, 0.28, 0.2]]:
			var c2 := center + Vector2(cos(float(a[0]) - PI * 0.5), sin(float(a[0]) - PI * 0.5)) * r * float(a[1])
			draw_circle(c2, r * float(a[2]), Color(0.24, 0.42, 0.25, 0.9))

func _draw_flames(pos: Vector2, s: float, angle: float) -> void:
	if state != "flying" or sim.thrust_now <= 0.0:
		return
	var R := Rocket2D
	var tank: Dictionary = R.part("tank", design.tank)
	var rot := Vector2.from_angle(angle)
	if sim.main_on:
		R2DDraw.flame(self, pos, s, angle, float(tank.w), 1.0, Color(1.0, 0.55, 0.15))
	if sim.b_on:
		var bo: Dictionary = R.part("boosters", design.boosters)
		var off := (float(tank.w) + float(bo.w)) * 0.5
		R2DDraw.flame(self, pos + rot * off * s, s, angle, float(bo.w) * 1.2, 1.2, Color(1.0, 0.75, 0.3))
		R2DDraw.flame(self, pos - rot * off * s, s, angle, float(bo.w) * 1.2, 1.2, Color(1.0, 0.75, 0.3))
	if sim.up_on:
		var ut: Dictionary = R.part("utank", design.utank)
		var up_base := pos + Vector2(sin(angle), -cos(angle)) * float(tank.h) * s
		R2DDraw.flame(self, up_base, s, angle, float(ut.w), 0.9, Color(0.55, 0.75, 1.0))

func _draw_ladder(w: float, hgt: float, h: float) -> void:
	var font := UI.font()
	var x := w - 300.0
	var y0 := hgt - 40.0
	var y1 := 40.0
	var yf := func(km: float) -> float:
		return lerpf(y0, y1, log(maxf(km, 1.0)) / log(400000.0))
	draw_rect(Rect2(x - 14.0, y1 - 22.0, 304.0, y0 - y1 + 44.0), Color(0.02, 0.03, 0.06, 0.45))
	draw_line(Vector2(x, y0), Vector2(x, y1), Color(1, 1, 1, 0.5), 2.0)
	for m: Dictionary in Data.milestones:
		var y: float = yf.call(float(m.km))
		var passed: bool = h >= float(m.km) * 1000.0
		var col := UI.GOOD if passed else Color(1, 1, 1, 0.65)
		draw_line(Vector2(x - 5.0, y), Vector2(x + 5.0, y), col, 2.0)
		draw_string(font, Vector2(x + 11.0, y + 4.0), "%s %s km" % [str(m.name), UI.grouped(int(m.km))], HORIZONTAL_ALIGNMENT_LEFT, 275.0, 12, col)
	if predicted > 0.0:
		var py: float = yf.call(predicted / 1000.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 20.0, py - 7.0), Vector2(x - 20.0, py + 7.0), Vector2(x - 8.0, py)]), UI.AMBER)
	var hy: float = yf.call(h / 1000.0)
	draw_circle(Vector2(x, hy), 7.0, Color.WHITE)
	draw_circle(Vector2(x, hy), 4.0, UI.ACCENT)
	var _unused := font

func _show_result(broke: bool) -> void:
	var R := Rocket2D
	Sfx.loop("engine", 0.0)
	_toast_panel.visible = false
	var f: Dictionary = R.record_flight(apogee, broke)
	var v := UI.vbox(9)
	var p := UI.panel(v, 26)
	p.custom_minimum_size.x = 600.0
	_result = p
	_ui.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.add_child(UI.eyebrow("Rocket broke up" if broke else "Flight complete"))
	v.add_child(UI.label(R.format_height(apogee), 46, UI.AMBER, "bold"))
	if bool(f.best):
		v.add_child(UI.label("New personal best!", 18, UI.GOOD, "bold"))
	var pred := float(f.predicted)
	if pred > 0.0:
		var ratio := apogee / pred
		var note := "%.0f%% of the predicted %s." % [ratio * 100.0, R.format_height(pred)]
		if broke:
			note += " It tumbled. Better fins keep a rocket pointing forward."
		elif ratio < 0.85:
			note += " Leaning loses height: keep it straight next time."
		v.add_child(UI.para(note, 16, UI.TEXT))
	var e: Dictionary = f.earn
	var g := UI.grid(2)
	UI.kv(g, "For the height", "$%s" % UI.grouped(int(e.pay)))
	if int(e.bonus) > 0:
		UI.kv(g, "Milestone bonus", "$%s" % UI.grouped(int(e.bonus)), UI.GOOD)
	UI.kv(g, "You now have", "$%s" % UI.grouped(R.money), UI.GOOD)
	v.add_child(g)
	var passed: Array = e.passed
	if not passed.is_empty():
		var top: Dictionary = passed[-1]
		v.add_child(UI.fact_block({"text": top.text, "url": top.url}, 14))
	var next_text := "Back to the hangar (%d launches left)" % R.flights_left if R.flights_left > 0 else "See my final score"
	var go := UI.button(next_text, leave, true)
	go.custom_minimum_size.y = 50.0
	v.add_child(go)
	go.grab_focus.call_deferred()

func leave() -> void:
	var R := Rocket2D
	if R.flights_left <= 0:
		R.pending_submit = true
		Flow.go("leaderboard")
	else:
		Flow.go("rocket2d")

func auto_advance() -> void:
	auto_steer = true
	launch()
