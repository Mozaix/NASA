class_name R2DDraw
extends RefCounted
## Draws a rocket from its parts, the same in the hangar and in flight. Sizes are in metres.

const BODY := Color(0.92, 0.93, 0.96)
const SHADE := Color(0.70, 0.73, 0.80)
const DARK := Color(0.2, 0.22, 0.27)
const ACCENT := Color(0.86, 0.32, 0.16)
const BLUE := Color(0.25, 0.5, 0.85)

static func total_height(d: Dictionary) -> float:
	var R := Rocket2D
	var h := float(R.part("tank", d.tank).h) + 1.0
	if R.has_upper(d):
		h += float(R.part("utank", d.utank).h) + 0.6
	return h + float(R.part("tank", d.tank).w) * 1.3

static func _tube(c: CanvasItem, x: float, y: float, w: float, h: float, col: Color) -> void:
	# Two tones give a simple feeling of a round body.
	c.draw_rect(Rect2(x - w * 0.5, y - h, w, h), col)
	c.draw_rect(Rect2(x + w * 0.12, y - h, w * 0.38, h), col.darkened(0.14))

static func _bell(c: CanvasItem, x: float, y: float, w: float) -> void:
	c.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.22, y), Vector2(x + w * 0.22, y), Vector2(x + w * 0.4, y + 1.0), Vector2(x - w * 0.4, y + 1.0)]), DARK)

## y = 0 is the base of the main tank in the drawing's own metres; up is negative.
static func draw(c: CanvasItem, base: Vector2, px_per_m: float, angle: float, d: Dictionary, show_boosters: bool = true, show_main: bool = true) -> void:
	var R := Rocket2D
	var tank: Dictionary = R.part("tank", d.tank)
	var ut: Dictionary = R.part("utank", d.utank)
	var bo: Dictionary = R.part("boosters", d.boosters)
	var fins: Dictionary = R.part("fins", d.fins)
	var nose: Dictionary = R.part("nose", d.nose)
	c.draw_set_transform(base, angle, Vector2.ONE * px_per_m)
	var w := float(tank.w)
	var y := 0.0
	if show_main:
		if show_boosters and int(bo.n) > 0:
			var bw := float(bo.w)
			var bh := float(bo.h)
			var offsets: Array[float] = [-(w + bw) * 0.5, (w + bw) * 0.5]
			if int(bo.n) == 4:
				offsets = [-(w + bw * 3.0) * 0.5, -(w + bw) * 0.5, (w + bw) * 0.5, (w + bw * 3.0) * 0.5]
			for ox: float in offsets:
				_tube(c, ox, 0.0, bw, bh, SHADE)
				c.draw_colored_polygon(PackedVector2Array([Vector2(ox - bw * 0.5, -bh), Vector2(ox + bw * 0.5, -bh), Vector2(ox, -bh - bw * 1.1)]), ACCENT)
				_bell(c, ox, 0.0, bw * 1.2)
		_bell(c, 0.0, 0.0, w)
		_tube(c, 0.0, 0.0, w, float(tank.h), BODY)
		c.draw_rect(Rect2(-w * 0.5, -float(tank.h) * 0.62, w, float(tank.h) * 0.08), ACCENT)
		_draw_fins(c, fins.id, w)
		y = -float(tank.h)
	var nose_w := w if show_main else float(ut.w)
	if R.has_upper(d):
		var uw := float(ut.w)
		var uh := float(ut.h)
		if show_main:
			c.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, y), Vector2(w * 0.5, y), Vector2(uw * 0.5, y - 0.6), Vector2(-uw * 0.5, y - 0.6)]), DARK)
			y -= 0.6
		else:
			_bell(c, 0.0, y, uw)
		_tube(c, 0.0, y, uw, uh, BODY)
		c.draw_rect(Rect2(-uw * 0.5, y - uh * 0.55, uw, uh * 0.12), BLUE)
		y -= uh
		nose_w = uw
	_draw_nose(c, nose.id, nose_w, y)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _draw_fins(c: CanvasItem, id: String, w: float) -> void:
	var half := w * 0.5
	var pts: PackedVector2Array
	match id:
		"small":
			pts = PackedVector2Array([Vector2(half, -1.4), Vector2(half + 0.7, 0.2), Vector2(half, 0.0)])
		"large":
			pts = PackedVector2Array([Vector2(half, -2.2), Vector2(half + 1.3, 0.5), Vector2(half, 0.0)])
		"swept":
			pts = PackedVector2Array([Vector2(half, -2.0), Vector2(half + 1.2, 0.7), Vector2(half + 0.55, 0.7), Vector2(half, -0.2)])
		_:
			return
	c.draw_colored_polygon(pts, ACCENT)
	var mirror := PackedVector2Array()
	for p in pts:
		mirror.append(Vector2(-p.x, p.y))
	c.draw_colored_polygon(mirror, ACCENT)

static func _draw_nose(c: CanvasItem, id: String, w: float, y: float) -> void:
	var half := w * 0.5
	match id:
		"cap":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-half, y), Vector2(half, y), Vector2(half * 0.75, y - w * 0.3), Vector2(-half * 0.75, y - w * 0.3)]), SHADE)
		"cone":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-half, y), Vector2(half, y), Vector2(0.0, y - w * 1.1)]), ACCENT)
		"ogive":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-half, y), Vector2(half, y), Vector2(half * 0.82, y - w * 0.55), Vector2(half * 0.42, y - w * 1.05), Vector2(0.0, y - w * 1.4), Vector2(-half * 0.42, y - w * 1.05), Vector2(-half * 0.82, y - w * 0.55)]), ACCENT)
		"needle":
			c.draw_colored_polygon(PackedVector2Array([Vector2(-half, y), Vector2(half, y), Vector2(half * 0.3, y - w * 1.3), Vector2(0.0, y - w * 2.4), Vector2(-half * 0.3, y - w * 1.3)]), BLUE)
		"shuttle":
			var wing := w * 1.3
			c.draw_colored_polygon(PackedVector2Array([Vector2(half, y - 0.1), Vector2(half + wing, y + 0.1), Vector2(half, y - w * 1.0)]), DARK)
			c.draw_colored_polygon(PackedVector2Array([Vector2(-half, y - 0.1), Vector2(-half - wing, y + 0.1), Vector2(-half, y - w * 1.0)]), DARK)
			c.draw_colored_polygon(PackedVector2Array([Vector2(-half, y), Vector2(half, y), Vector2(half * 0.85, y - w * 0.9), Vector2(0.0, y - w * 1.5), Vector2(-half * 0.85, y - w * 0.9)]), BODY)
			c.draw_colored_polygon(PackedVector2Array([Vector2(-half * 0.5, y - w * 0.95), Vector2(half * 0.5, y - w * 0.95), Vector2(0.0, y - w * 1.35)]), DARK)

static func flame(c: CanvasItem, base: Vector2, px_per_m: float, angle: float, width_m: float, power: float, col: Color) -> void:
	c.draw_set_transform(base, angle, Vector2.ONE * px_per_m)
	var flick := 1.0 + 0.18 * sin(float(Time.get_ticks_msec()) * 0.05) + randf() * 0.1
	var len_m := width_m * 3.2 * power * flick
	var w := width_m * 0.4
	c.draw_colored_polygon(PackedVector2Array([Vector2(-w, 1.0), Vector2(w, 1.0), Vector2(w * 0.3, 1.0 + len_m * 0.6), Vector2(0.0, 1.0 + len_m), Vector2(-w * 0.3, 1.0 + len_m * 0.6)]), col)
	c.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.55, 1.0), Vector2(w * 0.55, 1.0), Vector2(0.0, 1.0 + len_m * 0.5)]), Color(1.0, 0.95, 0.75))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
