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

static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, seg: int = 20) -> MeshInstance3D:
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
	c.radial_segments = 16
	c.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

static func flame(parent: Node3D, pos: Vector3, scale_f: float = 1.0, color: Color = Color(1.0, 0.65, 0.25)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := SphereMesh.new()
	q.radius = 0.5 * scale_f
	q.height = 1.0 * scale_f
	q.radial_segments = 8
	q.rings = 4
	p.mesh = q
	p.amount = [24, 48, 80][Settings.quality]
	p.lifetime = 0.45
	p.local_coords = false
	p.direction = Vector3.DOWN
	p.spread = 7.0
	p.initial_velocity_min = 12.0 * scale_f
	p.initial_velocity_max = 20.0 * scale_f
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	p.color = color
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
static func rocket() -> Node3D:
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
	var upper := Node3D.new()
	upper.name = "Upper"
	root.add_child(upper)
	cyl(upper, 0.45, 0.5, 2.6, Vector3(0, 7.3, 0), white)
	cyl(upper, 0.46, 0.46, 0.2, Vector3(0, 7.0, 0), dark)
	cyl(upper, 0.02, 0.45, 1.5, Vector3(0, 9.35, 0), white)
	return root

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
	cyl(root, 1.6, 2.2, 1.6, Vector3(0, 2.6, 0), gold, 8)
	cyl(root, 0.9, 1.5, 1.2, Vector3(0, 3.95, 0), grey, 8)
	cyl(root, 0.5, 0.9, 0.8, Vector3(0, 1.5, 0), dark, 12)
	for a: float in [0.785, 2.356, 3.927, 5.498]:
		var leg := cyl(root, 0.08, 0.08, 3.0, Vector3(cos(a) * 2.0, 1.15, sin(a) * 2.0), grey, 6)
		leg.rotation = Vector3(sin(a) * 0.55, 0.0, -cos(a) * 0.55)
		cyl(root, 0.5, 0.5, 0.12, Vector3(cos(a) * 2.8, 0.06, sin(a) * 2.8), dark, 10)
	var f := flame(root, Vector3(0, 1.0, 0), 1.0)
	f.name = "Flame"
	if with_chute:
		var chute_mat := mat(Color(0.95, 0.5, 0.2), 0.0, 0.8)
		chute_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var chute := Node3D.new()
		chute.name = "Chute"
		chute.position = Vector3(0, 16, 0)
		root.add_child(chute)
		cyl(chute, 0.5, 9.0, 3.5, Vector3.ZERO, chute_mat, 16)
		chute.visible = false
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
