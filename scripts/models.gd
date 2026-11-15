class_name Models
extends RefCounted
## Spacecraft and vehicles built from primitives, so the game ships without third-party models.

static func mat(color: Color, metal: float = 0.3, rough: float = 0.55, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, seg: int = 32) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

static func cube(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var c := BoxMesh.new()
	c.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

static func ball(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var c := SphereMesh.new()
	c.radius = r
	c.height = r * 2.0
	c.radial_segments = 28
	c.rings = 14
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

static var _flame_tex: GradientTexture2D

static func _soft_dot() -> GradientTexture2D:
	if _flame_tex:
		return _flame_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_flame_tex = t
	return t

## Soft glowing exhaust. With attached = true it stays in the parent's space, which the rocket needs
## because it moves so fast that a world-space trail would be enormous. Particle billboards ignore the
## node's scale, so a scaled-down parent must pass its scale as world_scale to size the sprites.
static func flame(parent: Node3D, pos: Vector3, scale_f: float = 1.0, color: Color = Color(1.0, 0.62, 0.22), attached: bool = false, world_scale: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 1.5 * scale_f * world_scale
	p.mesh = q
	p.amount = [48, 90, 140][Settings.quality]
	p.lifetime = 0.42
	p.local_coords = attached
	p.direction = Vector3.DOWN
	p.spread = 6.0
	p.initial_velocity_min = 10.0 * scale_f
	p.initial_velocity_max = 17.0 * scale_f
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.65
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.15))
	p.scale_amount_curve = curve
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.no_depth_test = false
	m.albedo_texture = _soft_dot()
	m.albedo_color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 0.55)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	p.emitting = false
	parent.add_child(p)
	return p

static func dust(parent: Node3D, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := SphereMesh.new()
	q.radius = 0.55
	q.height = 1.1
	q.radial_segments = 6
	q.rings = 3
	p.mesh = q
	p.amount = [12, 24, 40][Settings.quality]
	p.lifetime = 1.4
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.28)
	p.material_override = m
	p.emitting = false
	parent.add_child(p)
	return p

## Launch vehicle. Lower stage node is "Booster" so the launch scene can drop it. Origin at base.
static func rocket(kind: String = "medium") -> Node3D:
	var root := Node3D.new()
	var white := mat(Color(0.92, 0.93, 0.95), 0.1, 0.5)
	var dark := mat(Color(0.14, 0.15, 0.18), 0.5, 0.5)
	var accent := mat(Color(0.86, 0.3, 0.14), 0.1, 0.55)
	var booster := Node3D.new()
	booster.name = "Booster"
	root.add_child(booster)
	cyl(booster, 0.5, 0.5, 6.0, Vector3(0, 3.0, 0), white)
	cyl(booster, 0.5, 0.62, 0.6, Vector3(0, 0.3, 0), dark)
	cyl(booster, 0.51, 0.51, 0.25, Vector3(0, 4.8, 0), accent)
	for a: float in [0.0, 1.57, 3.14, 4.71]:
		cube(booster, Vector3(0.06, 1.0, 0.7), Vector3(cos(a) * 0.65, 0.6, sin(a) * 0.65), dark).rotation.y = -a + 1.57
	# Side boosters show which launcher was chosen. They drop with the first stage.
	var side_count := {"heavy": 2, "super": 4}.get(kind, 0) as int
	for i in side_count:
		var a := float(i) / float(side_count) * TAU + (0.0 if side_count == 2 else PI / 4.0)
		var at := Vector3(cos(a) * 0.86, 0.0, sin(a) * 0.86)
		cyl(booster, 0.3, 0.3, 4.4, at + Vector3(0, 2.4, 0), white)
		cyl(booster, 0.02, 0.3, 0.8, at + Vector3(0, 5.0, 0), accent)
		cyl(booster, 0.3, 0.38, 0.4, at + Vector3(0, 0.2, 0), dark)
	var upper := Node3D.new()
	upper.name = "Upper"
	root.add_child(upper)
	cyl(upper, 0.45, 0.5, 2.6, Vector3(0, 7.3, 0), white)
	cyl(upper, 0.46, 0.46, 0.2, Vector3(0, 7.0, 0), dark)
	cyl(upper, 0.02, 0.45, 1.5, Vector3(0, 9.35, 0), white)
	return root

## A detailed satellite for close-up views (the debris dodge rides on top of it): an eight-sided bus in
## crinkled gold foil, folding solar wings with visible cells, a dish on a mast, engine bell and thrusters.
## Forward is -z. Thrusters are named ThrusterL and ThrusterR so a scene can fire puffs from them.
static func satellite() -> Node3D:
	var root := Node3D.new()
	var foil := StandardMaterial3D.new()
	foil.albedo_color = Color(0.86, 0.66, 0.27)
	foil.metallic = 0.9
	foil.roughness = 0.32
	var crinkle := NoiseTexture2D.new()
	crinkle.width = 256
	crinkle.height = 256
	crinkle.seamless = true
	crinkle.as_normal_map = true
	crinkle.bump_strength = 6.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.06
	fn.fractal_octaves = 3
	crinkle.noise = fn
	foil.normal_enabled = true
	foil.normal_texture = crinkle
	foil.normal_scale = 0.6
	foil.uv1_scale = Vector3(3, 2, 1)
	var silver := mat(Color(0.78, 0.8, 0.84), 0.85, 0.25)
	var white := mat(Color(0.92, 0.93, 0.95), 0.1, 0.45)
	var dark := mat(Color(0.1, 0.11, 0.13), 0.6, 0.5)
	var along_z := Basis(Vector3.RIGHT, PI / 2.0)
	# Turned an eighth of a side so a flat face is on top.
	var bus_basis := Basis(Vector3.BACK, PI / 8.0) * along_z
	# Bus: an eight-sided prism lying along z, with seams and end plates.
	var bus := cyl(root, 0.52, 0.52, 1.3, Vector3.ZERO, foil, 8)
	bus.basis = bus_basis
	for z: float in [-0.66, 0.66]:
		cyl(root, 0.54, 0.54, 0.04, Vector3(0, 0, z), silver, 8).basis = bus_basis
	for z: float in [-0.22, 0.22]:
		cyl(root, 0.525, 0.525, 0.015, Vector3(0, 0, z), dark, 8).basis = bus_basis
	cube(root, Vector3(0.62, 0.03, 1.0), Vector3(0, 0.49, 0), silver)
	# Engine bell at the back, thrusters on the sides.
	var bell := cyl(root, 0.12, 0.28, 0.36, Vector3(0, 0, 0.86), dark, 24)
	bell.basis = along_z
	for side: float in [-1.0, 1.0]:
		var t := Node3D.new()
		t.name = "ThrusterL" if side < 0.0 else "ThrusterR"
		t.position = Vector3(side * 0.5, 0.18, -0.45)
		root.add_child(t)
		var noz := cyl(t, 0.02, 0.055, 0.09, Vector3(side * 0.04, 0, 0), dark, 12)
		noz.basis = Basis(Vector3.FORWARD, side * PI / 2.0)
	# Dish antenna on a short mast, set back and to one side so it does not block the view ahead.
	cyl(root, 0.025, 0.025, 0.22, Vector3(0.2, 0.6, 0.5), silver, 8)
	var dish := Node3D.new()
	dish.position = Vector3(0.2, 0.74, 0.5)
	dish.rotation = Vector3(0.55, 0.3, 0)
	root.add_child(dish)
	cyl(dish, 0.24, 0.045, 0.09, Vector3.ZERO, white, 32)
	cyl(dish, 0.236, 0.236, 0.01, Vector3(0, 0.045, 0), silver, 32)
	for i in 3:
		var a := float(i) / 3.0 * TAU
		line(dish, Vector3(cos(a) * 0.21, 0.045, sin(a) * 0.21), Vector3(0, 0.22, 0), 0.006, silver)
	cyl(dish, 0.025, 0.015, 0.045, Vector3(0, 0.22, 0), dark, 12)
	# Star trackers and a whip antenna.
	cube(root, Vector3(0.12, 0.1, 0.12), Vector3(-0.26, 0.56, -0.3), dark)
	cyl(root, 0.045, 0.045, 0.08, Vector3(-0.26, 0.64, -0.3), silver, 12)
	line(root, Vector3(-0.3, 0.5, 0.45), Vector3(-0.4, 1.05, 0.55), 0.006, silver)
	# Solar wings: a yoke, then three hinged panels of cells in silver frames.
	var cells := _cell_texture()
	var cell_mat := StandardMaterial3D.new()
	cell_mat.albedo_texture = cells
	cell_mat.metallic = 0.55
	cell_mat.roughness = 0.22
	cell_mat.uv1_scale = Vector3(3, 2, 1)
	var back := mat(Color(0.82, 0.83, 0.86), 0.3, 0.6)
	for side: float in [-1.0, 1.0]:
		line(root, Vector3(side * 0.5, 0.0, 0), Vector3(side * 0.95, 0.0, 0), 0.025, silver)
		cube(root, Vector3(0.08, 0.12, 0.08), Vector3(side * 0.95, 0.0, 0), silver)
		for k in 3:
			var cx := side * (1.55 + float(k) * 1.12)
			cube(root, Vector3(1.06, 0.028, 0.74), Vector3(cx, -0.008, 0), back)
			cube(root, Vector3(1.04, 0.03, 0.72), Vector3(cx, 0.0, 0), silver)
			cube(root, Vector3(1.0, 0.032, 0.68), Vector3(cx, 0.001, 0), cell_mat)
			if k < 2:
				cube(root, Vector3(0.08, 0.04, 0.1), Vector3(cx + side * 0.56, 0.0, 0.25), silver)
				cube(root, Vector3(0.08, 0.04, 0.1), Vector3(cx + side * 0.56, 0.0, -0.25), silver)
	return root

static var _cells: ImageTexture

## Deep blue solar cells with thin bright gaps and a silver busbar, drawn once.
static func _cell_texture() -> ImageTexture:
	if _cells:
		return _cells
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.08, 0.22))
	for y in n:
		for x in n:
			var cell := 32
			var gx := x % cell
			var gy := y % cell
			var c := Color(0.06, 0.1, 0.28).lerp(Color(0.1, 0.16, 0.4), float(gy) / cell * 0.6)
			if gx < 2 or gy < 2:
				c = Color(0.55, 0.6, 0.68)
			elif gx == cell / 2:
				c = Color(0.35, 0.4, 0.5)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_cells = ImageTexture.create_from_image(img)
	return _cells

## Transfer spacecraft with solar wings.
static func spacecraft(probe_scale: float = 1.0) -> Node3D:
	var root := Node3D.new()
	var gold := mat(Color(0.86, 0.67, 0.3), 0.8, 0.35)
	var white := mat(Color(0.88, 0.89, 0.92), 0.2, 0.5)
	var panel := mat(Color(0.08, 0.13, 0.32), 0.7, 0.25)
	cube(root, Vector3(0.6, 0.6, 1.0) * probe_scale, Vector3.ZERO, gold)
	cyl(root, 0.32 * probe_scale, 0.32 * probe_scale, 0.5 * probe_scale, Vector3(0, 0, -0.7) * probe_scale, white).rotation.x = PI / 2.0
	cube(root, Vector3(3.2, 0.03, 0.7) * probe_scale, Vector3(0, 0, 0), panel)
	var dish := cyl(root, 0.4 * probe_scale, 0.05 * probe_scale, 0.15 * probe_scale, Vector3(0, 0.45, 0) * probe_scale, white)
	dish.rotation.x = 0.0
	return root

## Lander. Origin at the footpads. "Flame" particles point down.
static func lander(with_chute: bool = false) -> Node3D:
	var root := Node3D.new()
	var gold := mat(Color(0.85, 0.66, 0.3), 0.8, 0.35)
	var grey := mat(Color(0.74, 0.75, 0.78), 0.4, 0.5)
	var dark := mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
	cyl(root, 1.6, 2.2, 1.6, Vector3(0, 2.6, 0), gold, 32)
	cyl(root, 0.9, 1.5, 1.2, Vector3(0, 3.95, 0), grey, 32)
	cyl(root, 0.5, 0.9, 0.8, Vector3(0, 1.5, 0), dark, 24)
	for a: float in [0.785, 2.356, 3.927, 5.498]:
		var leg := cyl(root, 0.08, 0.08, 3.0, Vector3(cos(a) * 2.0, 1.15, sin(a) * 2.0), grey, 12)
		leg.rotation = Vector3(sin(a) * 0.55, 0.0, -cos(a) * 0.55)
		cyl(root, 0.5, 0.5, 0.12, Vector3(cos(a) * 2.8, 0.06, sin(a) * 2.8), dark, 20)
	var f := flame(root, Vector3(0, 1.0, 0), 1.0)
	f.name = "Flame"
	if with_chute:
		var chute_mat := mat(Color(0.95, 0.5, 0.2), 0.0, 0.8)
		chute_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var stripe := mat(Color(0.96, 0.95, 0.92), 0.0, 0.8)
		stripe.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cord := mat(Color(0.9, 0.88, 0.82), 0.0, 0.9)
		# Every suspension line runs from the canopy's rim down to one bridle point on top of the lander.
		var bridle := Vector3(0, 4.6, 0)
		var main := Node3D.new()
		main.name = "Chute"
		root.add_child(main)
		cyl(main, 0.5, 9.0, 3.5, Vector3(0, 16, 0), chute_mat, 32)
		cyl(main, 0.52, 3.2, 1.25, Vector3(0, 17.13, 0), stripe, 32)
		_lines(main, 12, 9.0, 14.25, bridle, cord)
		main.visible = false
		var drogue := Node3D.new()
		drogue.name = "Drogue"
		root.add_child(drogue)
		cyl(drogue, 0.3, 2.6, 1.4, Vector3(0, 12, 0), chute_mat, 20)
		_lines(drogue, 6, 2.6, 11.3, bridle, cord)
		drogue.visible = false
	return root

## Suspension lines from evenly spaced points on a canopy rim to one point below.
static func _lines(parent: Node3D, count: int, rim_r: float, rim_y: float, to: Vector3, m: Material) -> void:
	for i in count:
		var a := TAU * float(i) / float(count)
		line(parent, Vector3(cos(a) * rim_r, rim_y, sin(a) * rim_r), to, 0.035, m)

## A thin cylinder from a to b.
static func line(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := cyl(parent, r, r, a.distance_to(b), (a + b) * 0.5, m, 4)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(side, up, side.cross(up))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## A derelict from an earlier (fictional) mission: a tipped-over lander and its dead rover, dusty and dark.
static func wreck() -> Node3D:
	var root := Node3D.new()
	var old_lander := lander(false)
	old_lander.get_node("Flame").queue_free()
	old_lander.rotation = Vector3(0.22, 0.4, -0.12)
	old_lander.position = Vector3(0, -0.5, 0)
	root.add_child(old_lander)
	var dust := mat(Color(0.52, 0.42, 0.34), 0.1, 0.95)
	var dark := mat(Color(0.16, 0.16, 0.17), 0.3, 0.8)
	var panel := mat(Color(0.12, 0.14, 0.22), 0.6, 0.4)
	var rover := Node3D.new()
	rover.position = Vector3(7.5, 0.0, 3.0)
	rover.rotation = Vector3(0.05, -0.7, 0.18)
	root.add_child(rover)
	cube(rover, Vector3(3.2, 0.9, 2.0), Vector3(0, 1.1, 0), dust)
	cube(rover, Vector3(3.6, 0.06, 2.4), Vector3(0, 1.6, 0), panel)
	for x: float in [-1.2, 0.0, 1.2]:
		for z: float in [-1.15, 1.15]:
			if x == 1.2 and z == 1.15:
				continue  # one wheel lost
			var w := cyl(rover, 0.45, 0.45, 0.35, Vector3(x, 0.45, z), dark, 16)
			w.rotation = Vector3(PI * 0.5, 0, 0)
	var lost := cyl(root, 0.45, 0.45, 0.35, Vector3(11.0, 0.2, 5.5), dark, 16)
	lost.rotation = Vector3(0.2, 0.6, 1.3)
	var mast := cyl(rover, 0.07, 0.07, 1.8, Vector3(1.0, 2.1, 0.6), mat(Color(0.6, 0.6, 0.6), 0.4, 0.6), 8)
	mast.rotation = Vector3(0, 0, 0.9)
	return root

## Atmospheric probe.
static func probe() -> Node3D:
	var root := Node3D.new()
	var gold := mat(Color(0.85, 0.66, 0.3), 0.8, 0.35)
	var white := mat(Color(0.86, 0.87, 0.9), 0.2, 0.5)
	var dark := mat(Color(0.18, 0.2, 0.25), 0.5, 0.5)
	cyl(root, 1.5, 1.9, 0.7, Vector3(0, 0, 0), gold, 16)
	cyl(root, 0.5, 1.4, 0.8, Vector3(0, 0.75, 0), white, 16)
	cyl(root, 1.1, 0.3, 0.8, Vector3(0, -0.75, 0), dark, 16)
	cube(root, Vector3(5.5, 0.05, 1.0), Vector3(0, 0.1, 0), mat(Color(0.08, 0.13, 0.32), 0.7, 0.25))
	return root
