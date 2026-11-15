class_name LaunchSite
extends Node3D
## The Bahrain concept spaceport in 3D: terrain from NASA SRTM heights draped with NASA/USGS Landsat colour,
## and a launch complex built from primitives (pad, flame trench, service tower with swing arms,
## lightning masts, water tower, propellant tanks, hangar, roads).
##
## Two scales meet here, as in the rest of the launch scene. The terrain is at true horizontal scale
## (1 unit = 10 km) with heights exaggerated EXAG times, because Bahrain is nearly flat. The complex is
## built in rocket-model units (the rocket is about 10 units tall) inside a node scaled like the rocket,
## so the pad always fits the rocket on it.

const EXAG := 5.0
const M_TO_UNITS := 1.0e-4      # 1 unit = 10 km
const BASE := 0.0042            # just above the flat Landsat map under the site
const FLAT_IN := 0.42           # the complex sits on ground levelled within this radius (units)...
const FLAT_OUT := 0.62          # ...blending back to the real heights by this radius
const DECK_Y := 1.0             # top of the pad's concrete hardstand, model units
const MOUNT_TOP := 1.7          # where the rocket's base rests, model units
const TOWER_X := -2.9
const ARM_SWING := 1.75         # radians the crew access arm turns when it retracts

var model_scale := 0.03
var complex: Node3D
var _heights := PackedFloat32Array()
var _n := 0
var _half := 0.8
var _pad_y := BASE
var _batches := {}
var _mats := {}
var _crew_arm: Node3D
var _umbilicals: Array[Node3D] = []
var _crew_target := 0.0
var _umb_target := 0.0
var _beacons: Array[MeshInstance3D] = []
var _blink := 0.0
var vents: Array[CPUParticles3D] = []
var deluge: Array[CPUParticles3D] = []
var smoke: Array[CPUParticles3D] = []

func _init(rocket_scale: float = 0.03) -> void:
	model_scale = rocket_scale
	name = "LaunchSite"

## Builds everything from data/bahrain.json's "site" block. Returns false if the data is missing.
func build(bh: Dictionary) -> bool:
	var site: Dictionary = bh.get("site", {})
	if site.is_empty():
		return false
	_n = int(site.n)
	_half = float(site.km) / 20.0
	_heights = FileAccess.get_file_as_bytes("res://data/regions/bahrain_spaceport/site_height.f32").to_float32_array()
	if _heights.size() != _n * _n:
		return false
	_pad_y = _raw_y(0.0, 0.0)
	add_child(_terrain())
	complex = Node3D.new()
	complex.name = "Complex"
	complex.scale = Vector3.ONE * model_scale
	complex.position = Vector3(0, _pad_y, 0)
	add_child(complex)
	_build_complex()
	return true

## Puts a node and everything under it on render layer 2, which only the pad's shadow light reaches.
static func use_site_light(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 2
	for c in n.get_children():
		use_site_light(c)

## Height of the rocket's base above the site origin, in scene units.
func rocket_base_y() -> float:
	return _pad_y + MOUNT_TOP * model_scale

## Ground height (scene units, relative to the site origin) at a point given in scene units.
func height_at(x: float, z: float) -> float:
	if _n == 0:
		return 0.0
	return _shape(x, z, _raw_y(x, z))

# ---------------------------------------------------------------- terrain

func _sample_m(x: float, z: float) -> float:
	var fx := clampf((x + _half) / (2.0 * _half) * float(_n - 1), 0.0, float(_n - 1))
	var fz := clampf((z + _half) / (2.0 * _half) * float(_n - 1), 0.0, float(_n - 1))
	var c0 := int(fx)
	var r0 := int(fz)
	var c1 := mini(c0 + 1, _n - 1)
	var r1 := mini(r0 + 1, _n - 1)
	var tx := fx - float(c0)
	var tz := fz - float(r0)
	var top := lerpf(_heights[r0 * _n + c0], _heights[r0 * _n + c1], tx)
	var bot := lerpf(_heights[r1 * _n + c0], _heights[r1 * _n + c1], tx)
	return lerpf(top, bot, tz)

## Exaggerated height before levelling. The sea (at or below 0 m) stays flat at BASE.
func _raw_y(x: float, z: float) -> float:
	var y := BASE + maxf(_sample_m(x, z), 0.0) * EXAG * M_TO_UNITS
	# The patch fades into the flat map at its edges so there is no step.
	var e := maxf(absf(x), absf(z)) / _half
	return lerpf(BASE, y, 1.0 - smoothstep(0.84, 1.0, e))

func _shape(x: float, z: float, raw: float) -> float:
	var d := sqrt(x * x + z * z)
	return lerpf(_pad_y, raw, smoothstep(FLAT_IN, FLAT_OUT, d))

func _terrain() -> MeshInstance3D:
	var step := 2 if Settings.quality == 0 else 1
	var m := (_n - 1) / step + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(m * m)
	normals.resize(m * m)
	uvs.resize(m * m)
	var cell := 2.0 * _half / float(m - 1)
	for r in m:
		var z := -_half + float(r) * cell
		for c in m:
			var x := -_half + float(c) * cell
			verts[r * m + c] = Vector3(x, height_at(x, z), z)
			uvs[r * m + c] = Vector2(float(c) / float(m - 1), float(r) / float(m - 1))
	for r in m:
		for c in m:
			var l := verts[r * m + maxi(c - 1, 0)].y
			var rr := verts[r * m + mini(c + 1, m - 1)].y
			var u := verts[maxi(r - 1, 0) * m + c].y
			var d := verts[mini(r + 1, m - 1) * m + c].y
			normals[r * m + c] = Vector3(l - rr, 2.0 * cell, u - d).normalized()
	var idx := PackedInt32Array()
	idx.resize((m - 1) * (m - 1) * 6)
	var k := 0
	for r in m - 1:
		for c in m - 1:
			var a := r * m + c
			var b := a + 1
			var cc := a + m
			var dd := cc + 1
			idx[k] = a
			idx[k + 1] = b
			idx[k + 2] = cc
			idx[k + 3] = b
			idx[k + 4] = dd
			idx[k + 5] = cc
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/site_ground.gdshader")
	sm.set_shader_parameter("color_tex", Data.texture("res://data/regions/bahrain_spaceport/site_color.jpgdata"))
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = noise
	sm.set_shader_parameter("detail_tex", nt)
	mi.material_override = sm
	return mi

# ---------------------------------------------------------------- complex

func _mat(key: String) -> Material:
	if _mats.is_empty():
		_mats = {
			"concrete": Models.mat(Color(0.7, 0.68, 0.64), 0.0, 0.92),
			"concrete_dark": Models.mat(Color(0.47, 0.46, 0.44), 0.0, 0.95),
			"gravel": Models.mat(Color(0.74, 0.68, 0.58), 0.0, 1.0),
			"asphalt": Models.mat(Color(0.2, 0.2, 0.21), 0.0, 0.95),
			"steel": Models.mat(Color(0.2, 0.21, 0.23), 0.6, 0.5),
			"tower": Models.mat(Color(0.72, 0.18, 0.1), 0.3, 0.6),
			"white": Models.mat(Color(0.9, 0.91, 0.92), 0.1, 0.45),
			"black": Models.mat(Color(0.03, 0.03, 0.035), 0.0, 1.0),
			"door": Models.mat(Color(0.28, 0.32, 0.37), 0.4, 0.5),
			"yellow": Models.mat(Color(0.92, 0.74, 0.16), 0.0, 0.7),
			"lamp": Models.mat(Color(1.0, 0.93, 0.78), 0.0, 0.5, 1.0),
		}
	return _mats[key]

## Static parts are merged into one mesh per material, so the whole complex costs a handful of draw calls.
func _add(mesh: PrimitiveMesh, xf: Transform3D, key: String) -> void:
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = st
	(_batches[key] as SurfaceTool).append_from(mesh, 0, xf)

func _box(size: Vector3, pos: Vector3, key: String, rot: Basis = Basis()) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add(b, Transform3D(rot, pos), key)

func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, key: String, seg: int = 24, rot: Basis = Basis()) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	_add(c, Transform3D(rot, pos), key)

func _ball(r: float, pos: Vector3, key: String) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	_add(s, Transform3D(Basis(), pos), key)

## A square beam from a to b.
func _beam(a: Vector3, b: Vector3, w: float, key: String) -> void:
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_box(Vector3(w, a.distance_to(b), w), (a + b) * 0.5, key, Basis(side, up, side.cross(up)))

## Ground height under a point of the complex, in model units relative to the pad.
func _ground(x: float, z: float) -> float:
	return (height_at(x * model_scale, z * model_scale) - _pad_y) / model_scale

func _commit() -> void:
	for key: String in _batches:
		var mi := MeshInstance3D.new()
		mi.name = "Static_" + key
		mi.mesh = (_batches[key] as SurfaceTool).commit()
		mi.material_override = _mat(key)
		complex.add_child(mi)
	_batches.clear()

func _build_complex() -> void:
	# Cleared gravel apron with the concrete hardstand (a raised, eight-sided mound) in the middle.
	_cyl(16.0, 16.0, 0.08, Vector3(0, 0.04, 0), "gravel", 8)
	_cyl(5.0, 7.0, DECK_Y, Vector3(0, DECK_Y * 0.5, 0), "concrete", 8)
	_cyl(5.02, 5.02, 0.03, Vector3(0, DECK_Y + 0.015, 0), "concrete_dark", 8)
	# Flame hole under the rocket, and the trench that carries the exhaust out to the east.
	_box(Vector3(1.9, 0.02, 1.9), Vector3(0, DECK_Y + 0.035, 0), "black")
	_box(Vector3(6.5, 0.04, 2.0), Vector3(7.6, 0.1, 0), "black")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(6.5, 0.9, 0.35), Vector3(7.6, 0.45, side * 1.17), "concrete")
	_box(Vector3(1.0, 1.0, 2.7), Vector3(5.2, 0.5, 0), "concrete_dark")
	# Ramp down to the road, and the road south to the hangar.
	var ramp_len := 4.6
	var slope := atan2(DECK_Y, ramp_len)
	_box(Vector3(2.6, 0.2, ramp_len / cos(slope)), Vector3(0, DECK_Y * 0.5, 5.0 + ramp_len * 0.5), "concrete", Basis(Vector3.RIGHT, slope))
	_box(Vector3(2.6, 0.06, 8.0), Vector3(0, 0.1, 13.6), "asphalt")
	_box(Vector3(0.12, 0.02, 7.6), Vector3(0, 0.14, 13.6), "yellow")
	# Painted ring and cross on the deck.
	for i in 4:
		var a := float(i) * PI / 2.0
		_box(Vector3(0.12, 0.02, 3.2), Vector3(cos(a) * 2.6, DECK_Y + 0.04, sin(a) * 2.6), "yellow", Basis(Vector3.UP, a))
	_launch_mount()
	_service_tower()
	_lightning_masts()
	_water_tower(Vector3(10.5, 0, -7.0))
	_propellant_farm()
	_hangar(Vector3(0, 0, 21.0))
	for p: Vector3 in [Vector3(-6.5, 0, -6.5), Vector3(6.5, 0, -6.5), Vector3(-5.0, 0, 9.5)]:
		_floodlight(p)
	_commit()
	_arms()
	_effects()

func _launch_mount() -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * 1.3, DECK_Y + 0.35, sz * 1.3)
			_box(Vector3(0.5, 0.7, 0.5), p, "steel")
			# Hold-down clamps reaching in to the base of the rocket.
			_beam(Vector3(sx * 1.15, MOUNT_TOP - 0.05, sz * 1.15), Vector3(sx * 0.42, MOUNT_TOP + 0.15, sz * 0.42), 0.14, "steel")
	for i in 4:
		var a := float(i) * PI / 2.0
		_box(Vector3(2.9, 0.18, 0.22), Vector3(cos(a) * 1.3, MOUNT_TOP - 0.08, sin(a) * 1.3), "steel", Basis(Vector3.UP, a + PI / 2.0))

func _service_tower() -> void:
	var w := 0.8           # half width of the tower's square footprint
	var top := 14.5
	var bay := 1.1
	var x := TOWER_X
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(0.16, top - DECK_Y, 0.16), Vector3(x + sx * w, (top + DECK_Y) * 0.5, sz * w), "tower")
	var y := DECK_Y
	while y < top - 0.01:
		var y2 := minf(y + bay, top)
		for f in 4:
			var a := float(f) * PI / 2.0
			var c1 := Vector3(cos(a) - sin(a), 0, sin(a) + cos(a)) * w
			var c2 := Vector3(cos(a + PI / 2.0) - sin(a + PI / 2.0), 0, sin(a + PI / 2.0) + cos(a + PI / 2.0)) * w
			var o := Vector3(x, 0, 0)
			_beam(o + c1 + Vector3(0, y2, 0), o + c2 + Vector3(0, y2, 0), 0.1, "tower")
			_beam(o + c1 + Vector3(0, y, 0), o + c2 + Vector3(0, y2, 0), 0.07, "tower")
		y = y2
	# Lift shaft, work floors and the roof mast with its beacon.
	_box(Vector3(0.6, top - DECK_Y, 0.6), Vector3(x, (top + DECK_Y) * 0.5, 0), "concrete_dark")
	for fy: float in [4.3, 6.8, 9.4, 12.0]:
		_box(Vector3(w * 2.2, 0.08, w * 2.2), Vector3(x, fy, 0), "steel")
	_box(Vector3(w * 2.4, 0.4, w * 2.4), Vector3(x, top + 0.2, 0), "tower")
	_cyl(0.05, 0.08, 3.0, Vector3(x, top + 1.9, 0), "steel", 8)
	_beacon(Vector3(x, top + 3.5, 0), 0.0)

func _lightning_masts() -> void:
	var tops: Array[Vector3] = []
	# Placed south-west and north-east, out of the countdown camera's path.
	for p: Vector3 in [Vector3(-8.0, 0, 6.5), Vector3(8.0, 0, -6.5)]:
		var g := _ground(p.x, p.z)
		var h := 18.0
		_cyl(0.07, 0.16, h, Vector3(p.x, g + h * 0.5, p.z), "steel", 8)
		_cyl(0.6, 0.6, 0.15, Vector3(p.x, g + 0.07, p.z), "concrete", 8)
		tops.append(Vector3(p.x, g + h, p.z))
		_beacon(Vector3(p.x, g + h + 0.25, p.z), 0.5)
	# The catenary wire between the masts passes high over the rocket, as on real pads.
	_beam(tops[0], tops[1], 0.05, "steel")
	for t: Vector3 in tops:
		for a: float in [0.6, 2.7, 4.6]:
			var anchor := Vector3(t.x + cos(a) * 6.0, 0, t.z + sin(a) * 6.0)
			anchor.y = _ground(anchor.x, anchor.z)
			_beam(t, anchor, 0.035, "steel")

func _water_tower(p: Vector3) -> void:
	var g := _ground(p.x, p.z)
	var leg_h := 7.0
	for i in 4:
		var a := float(i) * PI / 2.0 + PI / 4.0
		_beam(Vector3(p.x + cos(a) * 1.7, g, p.z + sin(a) * 1.7), Vector3(p.x + cos(a) * 1.1, g + leg_h, p.z + sin(a) * 1.1), 0.16, "steel")
	_cyl(1.6, 1.6, 2.4, Vector3(p.x, g + leg_h + 1.2, p.z), "white", 28)
	_cyl(0.15, 1.65, 0.7, Vector3(p.x, g + leg_h + 2.75, p.z), "white", 28)
	_cyl(0.25, 0.25, leg_h, Vector3(p.x, g + leg_h * 0.5, p.z), "white", 10)
	# Deluge pipe to the pad.
	var to := Vector3(1.6, DECK_Y * 0.5, -1.6)
	_beam(Vector3(p.x, g + 0.25, p.z), Vector3(to.x + 4.0, 0.25, to.z - 3.5), 0.22, "white")

func _propellant_farm() -> void:
	# Liquid oxygen in a big sphere, kerosene in horizontal tanks, piped to the pad.
	var lox := Vector3(-10.5, 0, 7.5)
	var g := _ground(lox.x, lox.z)
	for i in 4:
		var a := float(i) * PI / 2.0
		_box(Vector3(0.2, 1.3, 0.2), Vector3(lox.x + cos(a) * 1.0, g + 0.65, lox.z + sin(a) * 1.0), "steel")
	_ball(1.6, Vector3(lox.x, g + 2.6, lox.z), "white")
	for dz: float in [3.6, 5.6]:
		var fp := Vector3(-14.0, 0, dz)
		var fg := _ground(fp.x, fp.z)
		_cyl(0.75, 0.75, 4.5, Vector3(fp.x, fg + 1.0, fp.z), "white", 20, Basis(Vector3.FORWARD, PI / 2.0))
		for sx: float in [-1.4, 1.4]:
			_box(Vector3(0.3, 0.4, 1.0), Vector3(fp.x + sx, fg + 0.2, fp.z), "concrete")
	_beam(Vector3(lox.x, g + 0.3, lox.z), Vector3(-4.6, 0.3, 2.2), 0.18, "white")
	_beam(Vector3(-11.8, 0.3, 4.6), Vector3(-4.8, 0.3, 1.6), 0.18, "steel")

func _hangar(p: Vector3) -> void:
	var g := _ground(p.x, p.z)
	_box(Vector3(12.0, 0.1, 9.0), Vector3(p.x, g + 0.05, p.z), "concrete")
	_box(Vector3(8.0, 6.0, 6.0), Vector3(p.x, g + 3.0, p.z + 1.0), "white")
	_box(Vector3(8.1, 0.3, 6.1), Vector3(p.x, g + 6.1, p.z + 1.0), "concrete_dark")
	_box(Vector3(5.0, 5.0, 0.1), Vector3(p.x, g + 2.5, p.z - 2.02), "door")
	_box(Vector3(3.5, 2.6, 3.5), Vector3(p.x + 5.6, g + 1.3, p.z + 2.0), "concrete")

func _floodlight(p: Vector3) -> void:
	var g := _ground(p.x, p.z)
	_cyl(0.06, 0.1, 6.0, Vector3(p.x, g + 3.0, p.z), "steel", 8)
	var toward := Vector3(-p.x, 0, -p.z).normalized()
	_box(Vector3(1.0, 0.5, 0.15), Vector3(p.x, g + 6.0, p.z) + toward * 0.12, "lamp", Basis.looking_at(toward))

func _beacon(p: Vector3, phase: float) -> void:
	var m := Models.ball(complex, 0.22, p, Models.mat(Color(1.0, 0.15, 0.1), 0.0, 0.5, 4.0))
	m.set_meta("phase", phase)
	_beacons.append(m)

## The arms that reach from the tower to the rocket. They are separate nodes so they can swing away.
func _arms() -> void:
	var face := TOWER_X + 0.8
	var steel := _mat("steel")
	var white := _mat("white")
	_crew_arm = Node3D.new()
	_crew_arm.name = "CrewArm"
	_crew_arm.position = Vector3(face, MOUNT_TOP + 7.6, 0)
	complex.add_child(_crew_arm)
	var reach := -0.5 - face
	Models.cube(_crew_arm, Vector3(reach - 0.5, 0.45, 0.6), Vector3((reach - 0.5) * 0.5, 0, 0), steel)
	Models.cube(_crew_arm, Vector3(0.6, 0.7, 0.75), Vector3(reach - 0.25, 0.05, 0), white)
	for at: float in [3.0, 5.6]:
		var u := Node3D.new()
		u.name = "Umbilical"
		u.position = Vector3(face, MOUNT_TOP + at, 0)
		complex.add_child(u)
		Models.cube(u, Vector3(reach, 0.2, 0.3), Vector3(reach * 0.5, 0, 0), steel)
		Models.cyl(u, 0.05, 0.05, reach, Vector3(reach * 0.5, -0.15, 0), _mat("concrete_dark"), 8).rotation.z = PI / 2.0
		_umbilicals.append(u)

func _particles(pos: Vector3, amount: int, life: float, dir: Vector3, spread: float, v: Vector2, grav: Vector3, size: Vector2, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	# Billboarded particles ignore the parent's scale, so the sprite is sized in scene units here.
	q.size = Vector2.ONE * model_scale
	p.mesh = q
	p.amount = maxi(int(float(amount) * [0.5, 0.8, 1.0][Settings.quality]), 4)
	p.lifetime = life
	p.local_coords = true
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = v.x
	p.initial_velocity_max = v.y
	p.gravity = grav
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	# Puffs grow, then shrink away at the end of their life (the same recipe as the explosion smoke).
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.6, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = color
	m.albedo_texture = Models._soft_dot()
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	p.emitting = false
	complex.add_child(p)
	return p

func _effects() -> void:
	# Cold oxygen boiling off through the vents: white vapour that sinks and drifts downwind.
	for spec: Array in [[Vector3(0.5, MOUNT_TOP + 4.7, 0.1), Vector3(1, 0.1, 0.3)], [Vector3(-0.2, MOUNT_TOP + 7.1, 0.45), Vector3(0.2, 0.1, 1)]]:
		vents.append(_particles(spec[0], 36, 3.0, spec[1], 18.0, Vector2(0.5, 0.9), Vector3(0.25, -0.3, 0.15), Vector2(0.5, 1.4), Color(1, 1, 1, 0.55)))
	# Sound-suppression water spraying across the deck.
	for i in 4:
		var a := float(i) * PI / 2.0 + PI / 4.0
		var at := Vector3(cos(a) * 2.2, DECK_Y + 0.3, sin(a) * 2.2)
		deluge.append(_particles(at, 60, 1.1, Vector3(-cos(a), 1.2, -sin(a)), 25.0, Vector2(1.5, 2.6), Vector3(0, -3.0, 0), Vector2(0.15, 0.4), Color(0.85, 0.93, 1.0, 0.7)))
	# Steam and exhaust rolling out of the trench and around the pad at ignition.
	smoke.append(_particles(Vector3(10.5, 0.8, 0), 60, 4.0, Vector3(1, 0.3, 0), 20.0, Vector2(1.8, 3.2), Vector3(0, 0.35, 0), Vector2(1.2, 3.2), Color(0.93, 0.92, 0.9, 0.5)))
	smoke.append(_particles(Vector3(0, DECK_Y + 0.4, 0), 50, 3.5, Vector3(0, 0.2, 0), 90.0, Vector2(0.9, 1.8), Vector3(0, 0.25, 0), Vector2(1.0, 2.6), Color(0.88, 0.87, 0.85, 0.45)))

# ---------------------------------------------------------------- countdown actions

func retract_crew_arm() -> void:
	_crew_target = ARM_SWING

func retract_umbilicals() -> void:
	_umb_target = 1.3

func set_venting(on: bool) -> void:
	for p in vents:
		p.emitting = on

func set_deluge(on: bool) -> void:
	for p in deluge:
		p.emitting = on

func set_smoke(on: bool) -> void:
	for p in smoke:
		p.emitting = on

func crew_arm_angle() -> float:
	return _crew_arm.rotation.y if _crew_arm else 0.0

func _process(delta: float) -> void:
	if _crew_arm:
		_crew_arm.rotation.y = move_toward(_crew_arm.rotation.y, _crew_target, delta * 0.45)
	for u in _umbilicals:
		u.rotation.y = move_toward(u.rotation.y, -_umb_target, delta * 2.2)
	_blink += delta
	for b in _beacons:
		b.visible = fmod(_blink + float(b.get_meta("phase", 0.0)), 1.4) < 0.7
