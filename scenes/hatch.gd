class_name HatchScene
extends Control
## After touchdown: open the rover's hatch and move its uranium fuel rods from the transport rack
## to the power cradle at the back, one channel each, without touching the walls.
## Every wall touch shakes the core. Too many and it blows; mission control sends a fresh set of rods.
## Cutscenes before and after are drawn here too, so the scene works on every world and renderer.

const BOARD := Vector2(1000.0, 560.0)
const STAGE := Vector2(1600.0, 900.0)
const ROD_R := 9.0
const HIT_COOLDOWN := 0.7
## Each channel runs inside its own band of the board, from the rack (left) to the cradle (right).
const LANES := [
	{"name": "Rod A", "hw": 28.0, "pts": [Vector2(90, 120), Vector2(300, 120), Vector2(380, 70), Vector2(560, 160), Vector2(700, 80), Vector2(910, 120)]},
	{"name": "Rod B", "hw": 22.0, "pts": [Vector2(90, 280), Vector2(240, 280), Vector2(310, 232), Vector2(410, 328), Vector2(510, 232), Vector2(610, 328), Vector2(720, 250), Vector2(910, 280)]},
	{"name": "Rod C", "hw": 18.0, "pts": [Vector2(90, 440), Vector2(200, 440), Vector2(260, 392), Vector2(340, 392), Vector2(400, 490), Vector2(520, 490), Vector2(560, 400), Vector2(640, 400), Vector2(700, 490), Vector2(800, 460), Vector2(910, 440)]},
]
const INTRO := [
	{"dur": 3.8, "text": "Touchdown. The dust settles on %s."},
	{"dur": 3.6, "text": "Before the rover can roll, its power core has to be loaded."},
	{"dur": 3.2, "text": "Hatch release in 3... 2... 1..."},
]
const OUTRO := [
	{"dur": 3.2, "text": "Core seated. Power is flowing to the rover."},
	{"dur": 4.6, "text": "Ramp down. Wheels turning."},
	{"dur": 6.0, "text": "In real life, rovers like Curiosity and Perseverance run on an MMRTG, which turns heat from decaying plutonium-238 into electricity."},
]

var state := "intro"
var stability := 100.0
var hit_cost := 25.0
var touches := 0
var booms := 0
var held := -1
var rods: Array[Dictionary] = []
var _shot := 0
var _shot_t := 0.0
var _t := 0.0
var _play_t := 0.0
var _cooldown := 0.0
var _shake := 0.0
var _flash := 0.0
var _fade := 0.0
var _tick := 0.0
var _boom_t := 0.0
var _sparks: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _stars: Array[Vector2] = []
var _art: Dictionary
var _place := ""
var _panel: Control
var _auto := false
var _auto_s := 0.0
var _mouse := Vector2.ZERO

func _ready() -> void:
	name = "Hatch"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	Game.mission.phase = "hatch"
	Sfx.music("music_surface")
	var t := Game.target()
	_art = Data.art(str(t.get("id", "mars")))
	_place = str(World.region_for(t).get("name", t.get("name", "the surface")))
	if Game.is_demo():
		hit_cost = 20.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 140:
		_stars.append(Vector2(rng.randf(), rng.randf() * 0.62))
	_reset_rods()
	_kick_dust(60)
	Sfx.play("touchdown", -8.0)

func _reset_rods() -> void:
	rods.clear()
	for i in LANES.size():
		var pts: Array = LANES[i].pts
		rods.append({"pos": pts[0], "seated": false, "touches": 0})
	stability = 100.0
	touches = 0
	held = -1

## Channel half-width, a little wider in the demo.
func lane_hw(i: int) -> float:
	return float(LANES[i].hw) + (6.0 if Game.is_demo() else 0.0)

## Nearest point on a channel's centre line: {"point", "dist", "s"} where s is the distance along it.
static func closest_on(i: int, p: Vector2) -> Dictionary:
	var pts: Array = LANES[i].pts
	var best := {"point": pts[0], "dist": INF, "s": 0.0}
	var run := 0.0
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var c := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(c)
		if d < float(best.dist):
			best = {"point": c, "dist": d, "s": run + a.distance_to(c)}
		run += a.distance_to(b)
	return best

static func lane_length(i: int) -> float:
	var pts: Array = LANES[i].pts
	var total := 0.0
	for k in pts.size() - 1:
		total += (pts[k] as Vector2).distance_to(pts[k + 1])
	return total

static func point_at(i: int, s: float) -> Vector2:
	var pts: Array = LANES[i].pts
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var l := a.distance_to(b)
		if s <= l:
			return a.lerp(b, s / l)
		s -= l
	return pts[pts.size() - 1]

func seated_count() -> int:
	var n := 0
	for r: Dictionary in rods:
		if r.seated:
			n += 1
	return n

# --- layout -------------------------------------------------------------------------------------

func _board_xform() -> Transform2D:
	var vs := size
	var k := minf((vs.x - 120.0) / BOARD.x, (vs.y - 230.0) / BOARD.y)
	k = maxf(k, 0.3)
	var origin := Vector2((vs.x - BOARD.x * k) * 0.5, 175.0 + maxf(vs.y - 230.0 - BOARD.y * k, 0.0) * 0.5)
	return Transform2D(0.0, Vector2(k, k), 0.0, origin)

func _to_board(screen: Vector2) -> Vector2:
	return _board_xform().affine_inverse() * screen

# --- input --------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		if state in ["intro", "outro"]:
			if mb.pressed:
				_next_shot()
			return
		if state != "play":
			return
		if mb.pressed:
			var bp := _to_board(mb.position)
			for i in rods.size():
				if not rods[i].seated and bp.distance_to(rods[i].pos) < 26.0:
					held = i
					Sfx.play("click", -6.0, 1.3)
					break
		elif held >= 0:
			held = -1
			Sfx.play("click", -10.0, 0.8)

func _unhandled_input(event: InputEvent) -> void:
	if state in ["intro", "outro"] and (event.is_action_pressed("ui_accept") or (event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_SPACE)):
		_next_shot()
		get_viewport().set_input_as_handled()

# --- cutscenes ----------------------------------------------------------------------------------

func _shots() -> Array:
	return INTRO if state == "intro" else OUTRO

func _next_shot() -> void:
	_shot += 1
	_shot_t = 0.0
	if _shot == 2 and state == "intro":
		Sfx.play("stage", -6.0, 0.7)
	if _shot == 1 and state == "outro":
		Sfx.loop("rover", 0.5)
	if _shot >= _shots().size():
		if state == "intro":
			state = "to_bay"
			_t = 0.0
		else:
			_leave()

func _leave() -> void:
	if state == "leaving":
		return
	state = "leaving"
	Sfx.loop("rover", 0.0)
	Flow.go("surface", _place)

# --- game loop ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_shake = maxf(_shake - delta * 2.5, 0.0)
	_flash = maxf(_flash - delta * 1.6, 0.0)
	_update_fx(delta)
	match state:
		"intro", "outro":
			_shot_t += delta * (6.0 if _auto else 1.0)
			if _shot_t >= float(_shots()[_shot].dur):
				_next_shot()
		"to_bay":
			_fade = minf(_t / 0.5, 1.0) if _t < 0.5 else maxf(1.0 - (_t - 0.5) / 0.5, 0.0)
			if _t >= 1.0:
				state = "play"
				_fade = 0.0
				_play_t = 0.0
		"play":
			_play_t += delta
			if _auto:
				_auto_step(delta)
			elif held >= 0:
				_move_rod(held, _to_board(_mouse))
			_geiger(delta)
		"boom":
			_boom_t += delta
			if _boom_t > 2.0 and _panel == null:
				_show_boom_panel()
	queue_redraw()

## Move a held rod toward the cursor in small steps, so a fast flick cannot jump through a wall.
func _move_rod(i: int, target: Vector2) -> void:
	var r: Dictionary = rods[i]
	var from: Vector2 = r.pos
	var d := target - from
	var steps := maxi(ceili(d.length() / 5.0), 1)
	var hw := lane_hw(i)
	for k in steps:
		var p: Vector2 = from + d * float(k + 1) / float(steps)
		var c := closest_on(i, p)
		var limit := hw - ROD_R
		if float(c.dist) > limit:
			var cp: Vector2 = c.point
			var out := (p - cp).normalized()
			_touch(i, cp + out * hw)
			r.pos = cp + out * maxf(limit - 1.0, 0.0)
			return
		r.pos = p
		var end_pt: Vector2 = (LANES[i].pts as Array).back()
		if p.distance_to(end_pt) < 12.0:
			_seat(i)
			return

func _touch(i: int, at: Vector2) -> void:
	if _cooldown > 0.0 or state != "play":
		return
	_cooldown = HIT_COOLDOWN
	touches += 1
	rods[i].touches = int(rods[i].touches) + 1
	stability = maxf(stability - hit_cost, 0.0)
	_shake = 0.6
	for k in 14:
		_sparks.append({"p": at, "v": Vector2.from_angle(randf() * TAU) * randf_range(60.0, 220.0), "life": randf_range(0.3, 0.6), "c": Color(1.0, 0.8, 0.3)})
	Sfx.play("crash", -14.0, 2.4)
	if stability <= 0.0:
		_explode(rods[i].pos)

func _seat(i: int) -> void:
	var end_pt: Vector2 = (LANES[i].pts as Array).back()
	rods[i].pos = end_pt
	rods[i].seated = true
	held = -1
	Sfx.play("chime", -4.0)
	for k in 18:
		_sparks.append({"p": end_pt, "v": Vector2.from_angle(randf() * TAU) * randf_range(30.0, 120.0), "life": randf_range(0.4, 0.8), "c": Color(0.5, 1.0, 0.55)})
	if seated_count() == rods.size():
		_finish()

func _explode(at: Vector2) -> void:
	state = "boom"
	held = -1
	booms += 1
	_boom_t = 0.0
	_flash = 1.0
	_shake = 1.6
	Sfx.play("crash", 0.0, 0.8)
	Sfx.play("alarm", -6.0)
	for k in 90:
		var col := Color(1.0, randf_range(0.4, 0.9), 0.2) if k % 3 else Color(0.5, 1.0, 0.45)
		_sparks.append({"p": at, "v": Vector2.from_angle(randf() * TAU) * randf_range(80.0, 520.0), "life": randf_range(0.6, 1.6), "c": col})

## A Geiger-counter tick that speeds up as the held rod nears a wall.
func _geiger(delta: float) -> void:
	if held < 0:
		return
	var c := closest_on(held, rods[held].pos)
	var margin := lane_hw(held) - ROD_R - float(c.dist)
	var rate := lerpf(1.5, 16.0, clampf(1.0 - margin / 12.0, 0.0, 1.0))
	_tick += delta * rate
	if _tick >= 1.0:
		_tick = 0.0
		Sfx.play("click", -20.0, randf_range(1.6, 2.2))

func _update_fx(delta: float) -> void:
	for s: Dictionary in _sparks:
		s.p += s.v * delta
		s.v *= 0.92
		s.life -= delta
	_sparks = _sparks.filter(func(s: Dictionary) -> bool: return float(s.life) > 0.0)
	for d: Dictionary in _dust:
		d.p += d.v * delta
		d.v.y += 18.0 * delta
		d.life -= delta
	_dust = _dust.filter(func(d: Dictionary) -> bool: return float(d.life) > 0.0)

func _kick_dust(n: int, at: Vector2 = Vector2(800, 636), spread: float = 260.0) -> void:
	for k in n:
		_dust.append({"p": at + Vector2(randf_range(-spread, spread), randf_range(-6, 4)), "v": Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, -8.0)), "life": randf_range(1.5, 3.5), "r": randf_range(6.0, 18.0)})

# --- results ------------------------------------------------------------------------------------

func bonus() -> int:
	var b := 0
	for r: Dictionary in rods:
		b += 20 if int(r.touches) == 0 else (10 if int(r.touches) == 1 else 0)
	return b

func _finish() -> void:
	state = "result"
	var pts := bonus()
	Game.add_science(float(pts))
	Game.mission["core"] = {"touches": touches, "booms": booms, "seconds": snappedf(_play_t, 0.1), "bonus": pts}
	Autotest.report("hatch", Game.mission.core)
	var v := UI.vbox(12)
	_panel = UI.panel(v, 26)
	_panel.custom_minimum_size.x = 520.0
	v.add_child(UI.eyebrow("Power core loaded"))
	v.add_child(UI.heading("All rods are in the cradle", 30))
	var g := UI.grid(2)
	v.add_child(g)
	UI.kv(g, "Wall touches", str(touches), UI.GOOD if touches == 0 else UI.AMBER)
	UI.kv(g, "Core stability left", "%d%%" % int(stability))
	UI.kv(g, "Time", "%.1f s" % _play_t)
	if booms > 0:
		UI.kv(g, "Cores lost", str(booms), UI.BAD)
	UI.kv(g, "Science bonus", "+%d" % pts, UI.GOOD)
	var go := UI.button("Close the hatch and roll out", _start_outro, true)
	v.add_child(go)
	add_child(_panel)
	UI.center_panel(_panel)
	go.grab_focus.call_deferred()
	if _auto:
		_start_outro.call_deferred()

func _show_boom_panel() -> void:
	var v := UI.vbox(12)
	_panel = UI.panel(v, 26)
	_panel.custom_minimum_size.x = 520.0
	v.add_child(UI.heading("Core breach!", 32))
	v.add_child(UI.para("The rods knocked against the walls too many times and the core blew. Nobody was hurt: the rover vented the bay, and mission control is sending a fresh set of rods.", 17, UI.TEXT))
	v.add_child(UI.para("Tip: move slowly near the bends. The clicking speeds up as you get close to a wall.", 15))
	var again := UI.button("Try again", _retry, true)
	v.add_child(again)
	if booms >= 2:
		v.add_child(UI.button("Skip: drive out on backup batteries (no bonus)", func() -> void:
			Game.mission["core"] = {"touches": touches, "booms": booms, "skipped": true, "bonus": 0}
			_start_outro()))
	add_child(_panel)
	UI.center_panel(_panel)
	again.grab_focus.call_deferred()

func _retry() -> void:
	_close_panel()
	_reset_rods()
	_sparks.clear()
	state = "play"

func _close_panel() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null

func _start_outro() -> void:
	if state == "outro" or state == "leaving":
		return
	_close_panel()
	state = "outro"
	_shot = 0
	_shot_t = 0.0
	Sfx.play("stage", -8.0, 1.2)

## Used by tests and the autotest: skip the cutscenes and steer each rod down the middle of its channel.
func auto_advance() -> void:
	_auto = true
	if state == "intro":
		state = "to_bay"
		_t = 0.0

func _auto_step(delta: float) -> void:
	var i := -1
	for k in rods.size():
		if not rods[k].seated:
			i = k
			break
	if i < 0:
		return
	held = i
	_auto_s += delta * 420.0
	_move_rod(i, point_at(i, minf(_auto_s, lane_length(i))))
	if rods[i].seated:
		_auto_s = 0.0

# --- drawing ------------------------------------------------------------------------------------

func _draw() -> void:
	var vs := size
	match state:
		"intro":
			_draw_exterior(_intro_params())
			_draw_letterbox(INTRO, true)
		"outro", "leaving":
			_draw_exterior(_outro_params())
			_draw_letterbox(OUTRO, false)
		"to_bay":
			if _t < 0.5:
				_draw_exterior({"zoom": 2.4, "focus": Vector2(770, 478), "hatch": 1.0})
			else:
				_draw_bay()
		_:
			_draw_bay()
	if _fade > 0.0:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, _fade))
	if _flash > 0.0:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.95, 0.8, _flash * 0.85))

func _intro_params() -> Dictionary:
	var u := clampf(_shot_t / float(INTRO[_shot].dur), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, u)
	match _shot:
		0:
			return {"zoom": lerpf(0.9, 1.0, e), "focus": Vector2(800, 470), "hatch": 0.0}
		1:
			return {"zoom": lerpf(1.0, 1.9, e), "focus": Vector2(800, 470).lerp(Vector2(770, 478), e), "hatch": 0.0, "glow": u}
		_:
			return {"zoom": lerpf(1.9, 2.4, e), "focus": Vector2(770, 478), "hatch": smoothstep(0.55, 0.95, u), "glow": 1.0, "blink": u < 0.55}

func _outro_params() -> Dictionary:
	var u := clampf(_shot_t / float(OUTRO[mini(_shot, OUTRO.size() - 1)].dur), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, u)
	match _shot:
		0:
			return {"zoom": lerpf(2.2, 1.4, e), "focus": Vector2(770, 478).lerp(Vector2(820, 480), e), "hatch": 1.0 - smoothstep(0.1, 0.6, u), "glow": 1.0, "power": u}
		1:
			var ramp := smoothstep(0.0, 0.25, u)
			var drive := smoothstep(0.25, 1.0, u)
			if drive > 0.0 and randf() < 0.5:
				var rp := _rover_path(drive)
				_kick_dust(1, rp.pos, 20.0)
			return {"zoom": lerpf(1.4, 1.05, e), "focus": Vector2(820, 480).lerp(Vector2(950, 500), e), "hatch": 0.0, "ramp": ramp, "drive": drive, "power": 1.0}
		_:
			return {"zoom": 1.0, "focus": Vector2(1000, 500), "hatch": 0.0, "ramp": 1.0, "drive": 1.0 + u * 0.4, "power": 1.0}

## Where the rover sits as it drives off: along the deck, down the ramp, then out across the ground.
func _rover_path(drive: float) -> Dictionary:
	var deck := Vector2(800, 520)
	var edge := Vector2(905, 520)
	var foot := Vector2(1030, 640)
	var far := Vector2(1300, 640)
	if drive < 0.25:
		return {"pos": deck.lerp(edge, drive / 0.25), "angle": 0.0}
	if drive < 0.65:
		return {"pos": edge.lerp(foot, (drive - 0.25) / 0.4), "angle": (foot - edge).angle()}
	return {"pos": foot.lerp(far, minf((drive - 0.65) / 0.35, 1.6)), "angle": 0.0}

func _view(zoom: float, focus: Vector2) -> Transform2D:
	var k := maxf(size.x / STAGE.x, size.y / STAGE.y)
	var z := k * zoom
	var sh := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 10.0
	return Transform2D(0.0, Vector2(z, z), 0.0, size * 0.5 - focus * z + sh)

func _draw_exterior(p: Dictionary) -> void:
	var vs := size
	var top: Color = _art.get("top", Color(0.05, 0.05, 0.08))
	var hor: Color = _art.get("horizon", Color(0.3, 0.25, 0.2))
	var atmo: Color = _art.get("atmo", Color(0.6, 0.5, 0.4))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]), PackedColorArray([top, top, hor, hor]))
	var star_a := float(_art.get("stars", 0.5))
	if star_a > 0.02:
		for s: Vector2 in _stars:
			draw_circle(s * vs, 1.2, Color(1, 1, 1, star_a * (0.4 + 0.6 * absf(sin(s.x * 90.0 + _t * 0.6)))))
	var xf := _view(float(p.get("zoom", 1.0)), p.get("focus", Vector2(800, 470)))
	draw_set_transform_matrix(xf)
	# The Sun, low in the sky.
	draw_circle(Vector2(240, 230), 70.0, Color(1.0, 0.95, 0.8, 0.08))
	draw_circle(Vector2(240, 230), 26.0, Color(1.0, 0.97, 0.88, 0.9))
	var ground := atmo.darkened(0.45)
	var far_ground := ground.lerp(hor, 0.45)
	_draw_hills(560.0, 46.0, 0.004, far_ground)
	_draw_hills(640.0, 22.0, 0.009, ground, true)
	for d: Dictionary in _dust:
		draw_circle(d.p, float(d.r), Color(atmo.r, atmo.g, atmo.b, clampf(float(d.life) / 3.0, 0.0, 1.0) * 0.28))
	_draw_lander(p)
	var drive := float(p.get("drive", 0.0))
	var rp := _rover_path(drive)
	draw_set_transform_matrix(xf * Transform2D(float(rp.angle), rp.pos))
	_draw_rover(p, drive)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_hills(base: float, amp: float, freq: float, col: Color, flat_pad: bool = false) -> void:
	var pts := PackedVector2Array()
	var x := -1400.0
	while x <= 3000.0:
		var h := sin(x * freq) * amp + sin(x * freq * 2.7 + 1.3) * amp * 0.4
		if flat_pad:
			h *= smoothstep(150.0, 600.0, absf(x - 900.0))
		pts.append(Vector2(x, base - h))
		x += 40.0
	pts.append(Vector2(3000, 2400))
	pts.append(Vector2(-1400, 2400))
	draw_colored_polygon(pts, col)

func _draw_lander(p: Dictionary) -> void:
	var leg := Color(0.55, 0.57, 0.6)
	for side: float in [-1.0, 1.0]:
		draw_line(Vector2(800 + side * 70, 560), Vector2(800 + side * 125, 636), leg, 6.0)
		draw_line(Vector2(800 + side * 40, 585), Vector2(800 + side * 110, 636), leg, 4.0)
		draw_rect(Rect2(800 + side * 125 - 16, 632, 32, 6), leg)
	draw_colored_polygon(PackedVector2Array([Vector2(690, 520), Vector2(910, 520), Vector2(870, 590), Vector2(730, 590)]), Color(0.78, 0.6, 0.22))
	draw_rect(Rect2(686, 516, 228, 8), Color(0.82, 0.84, 0.88))
	for k in 6:
		draw_line(Vector2(720 + k * 30, 528), Vector2(735 + k * 24, 586), Color(0.62, 0.45, 0.16), 2.0)
	var ramp := float(p.get("ramp", 0.0))
	if ramp > 0.0:
		var hinge := Vector2(910, 520)
		var tip := hinge + Vector2.from_angle(lerpf(-PI * 0.5, (Vector2(1030, 640) - hinge).angle(), ramp)) * 170.0
		draw_line(hinge, tip, Color(0.7, 0.72, 0.76), 7.0)

## The rover in its own frame: origin at the middle of its wheel base.
func _draw_rover(p: Dictionary, drive: float) -> void:
	var body := Color(0.86, 0.87, 0.84)
	var dark := Color(0.2, 0.21, 0.24)
	var spin := drive * 40.0
	for wx: float in [-48.0, 0.0, 48.0]:
		draw_circle(Vector2(wx, -12), 12.0, dark)
		draw_circle(Vector2(wx, -12), 5.0, Color(0.5, 0.52, 0.56))
		draw_line(Vector2(wx, -12), Vector2(wx, -12) + Vector2.from_angle(spin) * 11.0, Color(0.6, 0.62, 0.66), 2.0)
	draw_line(Vector2(-48, -16), Vector2(48, -16), Color(0.5, 0.52, 0.56), 4.0)
	draw_rect(Rect2(-62, -56, 124, 36), body)
	draw_rect(Rect2(-62, -60, 124, 6), Color(0.3, 0.32, 0.36))
	# Mast and camera head.
	draw_line(Vector2(45, -60), Vector2(45, -102), Color(0.7, 0.72, 0.75), 4.0)
	draw_rect(Rect2(36, -112, 22, 12), Color(0.85, 0.86, 0.88))
	draw_circle(Vector2(54, -106), 3.0, Color(0.2, 0.5, 0.9))
	# Power bay hatch at the back. Inside, the rods glow.
	var glow := float(p.get("glow", 0.0))
	var power := float(p.get("power", 0.0))
	var bay := Rect2(-52, -52, 40, 28)
	draw_rect(bay, Color(0.08, 0.1, 0.1))
	var rod_col := Color(0.45, 1.0, 0.4, 0.35 + 0.65 * maxf(glow * float(p.get("hatch", 0.0)), power))
	for k in 3:
		draw_rect(Rect2(-48 + k * 12, -48, 6, 20), rod_col)
	if glow > 0.0 or power > 0.0:
		draw_circle(bay.get_center(), 30.0, Color(0.4, 1.0, 0.4, 0.12 * maxf(glow, power)))
	var open := float(p.get("hatch", 0.0))
	var w := 40.0 * cos(open * PI * 0.5)
	if w > 0.5:
		draw_rect(Rect2(-52, -52, w, 28), Color(0.7, 0.72, 0.7))
		draw_rect(Rect2(-52, -52, w, 28), Color(0.4, 0.42, 0.45), false, 1.5)
	if bool(p.get("blink", false)) and fmod(_t, 0.5) < 0.25:
		draw_circle(Vector2(-6, -48), 3.0, Color(1.0, 0.3, 0.2))
	if power > 0.0:
		draw_circle(Vector2(-6, -48), 3.0, Color(0.4, 1.0, 0.5, power))

func _draw_letterbox(shots: Array, intro: bool) -> void:
	var vs := size
	var bar := maxf(vs.y * 0.12, 70.0)
	draw_rect(Rect2(0, 0, vs.x, bar), Color(0, 0, 0, 0.92))
	draw_rect(Rect2(0, vs.y - bar, vs.x, bar), Color(0, 0, 0, 0.92))
	var f := UI.font()
	var fb := UI.font_bold()
	var title := ("MISSION LOG  ·  " + str(Game.target().get("name", ""))).to_upper()
	draw_string(fb, Vector2(28, bar * 0.6), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.ACCENT)
	draw_string(f, Vector2(vs.x - 28 - 260, bar * 0.6), "Click or Space: next", HORIZONTAL_ALIGNMENT_RIGHT, 260, 14, UI.TEXT_DIM)
	var i := mini(_shot, shots.size() - 1)
	var text := str(shots[i].text)
	if intro and i == 0:
		text = text % _place
	var shown := text.substr(0, int(_shot_t * 45.0))
	draw_multiline_string(f, Vector2(vs.x * 0.12, vs.y - bar + 32), shown, HORIZONTAL_ALIGNMENT_CENTER, vs.x * 0.76, 22, 2, UI.TEXT)

func _draw_bay() -> void:
	var vs := size
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.035, 0.045, 0.065))
	var sh := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 9.0
	var xf := _board_xform()
	xf.origin += sh
	draw_set_transform_matrix(xf)
	# The bay floor: a riveted plate.
	var plate := Rect2(Vector2(-30, -30), BOARD + Vector2(60, 60))
	draw_rect(plate, Color(0.11, 0.13, 0.17))
	draw_rect(plate, Color(0.3, 0.36, 0.45, 0.6), false, 3.0)
	for x in range(0, int(BOARD.x) + 1, 100):
		draw_circle(Vector2(x, -16), 3.0, Color(0.32, 0.36, 0.42))
		draw_circle(Vector2(x, BOARD.y + 16), 3.0, Color(0.32, 0.36, 0.42))
	var f := UI.font()
	var fb := UI.font_bold()
	draw_string(fb, Vector2(40, BOARD.y + 8), "TRANSPORT RACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TEXT_DIM)
	draw_string(fb, Vector2(BOARD.x - 200, BOARD.y + 8), "POWER CRADLE", HORIZONTAL_ALIGNMENT_RIGHT, 160, 13, UI.TEXT_DIM)
	for i in LANES.size():
		_draw_lane(i)
	for i in rods.size():
		_draw_rod(i)
	for s: Dictionary in _sparks:
		var c: Color = s.c
		c.a = clampf(float(s.life) * 2.0, 0.0, 1.0)
		draw_circle(s.p, 2.5, c)
	if state == "boom":
		var u := clampf(_boom_t / 1.2, 0.0, 1.0)
		draw_circle(BOARD * 0.5, 700.0 * u, Color(1.0, 0.55, 0.15, 0.35 * (1.0 - u)))
		draw_arc(BOARD * 0.5, 760.0 * u, 0.0, TAU, 64, Color(1.0, 0.85, 0.5, 1.0 - u), 6.0)
		if _boom_t > 0.6:
			draw_rect(Rect2(Vector2(-30, -30), BOARD + Vector2(60, 60)), Color(0.4, 0.42, 0.45, clampf((_boom_t - 0.6) * 0.4, 0.0, 0.35)))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_hud(f, fb)
	if _panel:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.0, 0.5))

func _draw_lane(i: int) -> void:
	var pts := PackedVector2Array(LANES[i].pts)
	var hw := lane_hw(i)
	var near := held == i and _cooldown > HIT_COOLDOWN - 0.3
	var edge := Color(1.0, 0.35, 0.3) if near else Color(0.95, 0.66, 0.25, 0.85)
	var floor_c := Color(0.05, 0.065, 0.085)
	draw_polyline(pts, edge, hw * 2.0 + 6.0)
	for p: Vector2 in pts:
		draw_circle(p, hw + 3.0, edge)
	draw_polyline(pts, floor_c, hw * 2.0)
	for p: Vector2 in pts:
		draw_circle(p, hw, floor_c)
	draw_polyline(pts, Color(0.3, 0.45, 0.6, 0.18), 1.5)
	var start: Vector2 = pts[0]
	var end_pt: Vector2 = pts[pts.size() - 1]
	draw_arc(start, ROD_R + 7.0, 0.0, TAU, 32, Color(0.5, 0.56, 0.64), 2.0)
	var seated: bool = rods[i].seated
	draw_arc(end_pt, ROD_R + 7.0, 0.0, TAU, 32, UI.GOOD if seated else UI.ACCENT.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 4.0)), 3.0)
	draw_string(UI.font_bold(), start + Vector2(-84, 5), str(LANES[i].name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TEXT_DIM)

func _draw_rod(i: int) -> void:
	var r: Dictionary = rods[i]
	var p: Vector2 = r.pos
	var c := closest_on(i, p)
	var s := float(c.s)
	var dir := (point_at(i, s + 6.0) - point_at(i, maxf(s - 6.0, 0.0))).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var pulse := 0.6 + 0.4 * sin(_t * 5.0 + float(i))
	draw_circle(p, 26.0, Color(0.4, 1.0, 0.4, 0.07 + 0.06 * pulse))
	var a := p - dir * 13.0
	var b := p + dir * 13.0
	draw_line(a, b, Color(0.25, 0.3, 0.28), ROD_R * 2.0)
	draw_circle(a, ROD_R, Color(0.25, 0.3, 0.28))
	draw_circle(b, ROD_R, Color(0.25, 0.3, 0.28))
	draw_line(a, b, Color(0.45, 1.0, 0.42, 0.75 + 0.25 * pulse), ROD_R)
	if held == i:
		draw_arc(p, ROD_R + 5.0, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 1.5)

func _draw_hud(f: Font, fb: Font) -> void:
	var vs := size
	draw_string(fb, Vector2(32, 40), "POWER BAY  ·  " + str(Game.target().get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.ACCENT)
	draw_string(fb, Vector2(32, 76), "Load the power core", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UI.TEXT)
	draw_string(f, Vector2(32, 108), "Drag each uranium rod through its channel to the cradle. Don't touch the walls.", HORIZONTAL_ALIGNMENT_LEFT, vs.x * 0.55, 16, UI.TEXT_DIM)
	var x := vs.x - 300.0
	draw_string(f, Vector2(x, 40), "Rods seated", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.TEXT_DIM)
	draw_string(fb, Vector2(x, 40), "%d / %d" % [seated_count(), rods.size()], HORIZONTAL_ALIGNMENT_RIGHT, 268, 15, UI.TEXT)
	draw_string(f, Vector2(x, 68), "Core stability", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.TEXT_DIM)
	var col := UI.GOOD if stability > 60.0 else (UI.AMBER if stability > 30.0 else UI.BAD)
	draw_string(fb, Vector2(x, 68), "%d%%" % int(stability), HORIZONTAL_ALIGNMENT_RIGHT, 268, 15, col)
	draw_rect(Rect2(x, 78, 268, 8), Color(0.1, 0.13, 0.19))
	draw_rect(Rect2(x, 78, 268 * stability / 100.0, 8), col)
	draw_string(f, Vector2(x, 110), "Wall touches", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.TEXT_DIM)
	draw_string(fb, Vector2(x, 110), str(touches), HORIZONTAL_ALIGNMENT_RIGHT, 268, 15, UI.TEXT if touches == 0 else UI.AMBER)
