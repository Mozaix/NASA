class_name Space
extends RefCounted
## Shared builders for the 3D space views: environment, Sun, planets, rings, orbit lines.

const PLANET_SHADER := preload("res://shaders/planet.gdshader")
const ATMO_SHADER := preload("res://shaders/atmosphere.gdshader")
const GLOW_SHADER := preload("res://shaders/sun_glow.gdshader")
const RINGS_SHADER := preload("res://shaders/rings.gdshader")

static func make_space_env(parent: Node, ambient: float = 0.035) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var stars := Data.stars_texture()
	if stars:
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = stars
		sky.sky_material = mat
	else:
		var p := ProceduralSkyMaterial.new()
		p.sky_top_color = Color.BLACK
		p.sky_horizon_color = Color.BLACK
		p.ground_bottom_color = Color.BLACK
		p.ground_horizon_color = Color.BLACK
		sky.sky_material = p
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.8)
	env.ambient_light_energy = ambient
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = Settings.glow()
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	return we

static func make_sun_light(parent: Node, dir: Vector3, color: Color = Color(1, 0.97, 0.92), energy: float = 1.5) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.light_color = color
	l.light_energy = energy
	parent.add_child(l)
	l.look_at_from_position(Vector3.ZERO, -dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT)
	return l

static func make_sun(parent: Node3D, radius: float, color: Color = Color(1.0, 0.86, 0.55)) -> Node3D:
	var n := Node3D.new()
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	s.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lerp(Color.WHITE, 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	s.material_override = m
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(s)
	var g := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 9.0
	g.mesh = q
	var gm := ShaderMaterial.new()
	gm.shader = GLOW_SHADER
	gm.set_shader_parameter("color", color)
	g.material_override = gm
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(g)
	parent.add_child(n)
	return n

## A planet node centred on the origin. Spin the child named "Globe" to rotate the surface.
static func make_planet(target: Dictionary, radius: float, sun_dir: Vector3, segments: int = -1) -> Node3D:
	var root := Node3D.new()
	var id: String = target.get("id", "")
	var art: Dictionary = Data.art(id)
	var tilt := float(target.get("obliquity_deg", 0.0) if target.get("obliquity_deg") != null else 0.0)
	root.rotation.z = deg_to_rad(clampf(tilt, -180.0, 180.0))
	var globe := MeshInstance3D.new()
	globe.name = "Globe"
	var seg: int = segments if segments > 0 else Settings.sphere_segments()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = seg
	sm.rings = seg / 2
	globe.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = PLANET_SHADER
	var tex: ImageTexture = Data.planet_texture(id)
	if tex:
		mat.set_shader_parameter("use_map", true)
		mat.set_shader_parameter("map_tex", tex)
	else:
		mat.set_shader_parameter("use_map", false)
		var has_surface: bool = target.get("has_surface", false)
		mat.set_shader_parameter("style", 1 if has_surface else 0)
		var cols: Array = art.get("ground", art.get("bands", [Color(0.5, 0.5, 0.5), Color(0.35, 0.35, 0.35), Color(0.7, 0.7, 0.7)]))
		mat.set_shader_parameter("band_a", cols[0])
		mat.set_shader_parameter("band_b", cols[1])
		mat.set_shader_parameter("band_c", cols[2])
		mat.set_shader_parameter("seed", float(hash(str(target.get("name", "x"))) % 997) * 0.01)
		mat.set_shader_parameter("lava", float(art.get("lava", 0.0)))
	globe.material_override = mat
	root.add_child(globe)
	var amt := float(art.get("atmo_amt", 0.0))
	if amt > 0.01:
		var shell := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = radius * 1.035
		ss.height = radius * 2.07
		ss.radial_segments = 48
		ss.rings = 24
		shell.mesh = ss
		var am := ShaderMaterial.new()
		am.shader = ATMO_SHADER
		am.set_shader_parameter("color", art.get("atmo", Color.WHITE))
		am.set_shader_parameter("strength", amt)
		am.set_shader_parameter("sun_dir", sun_dir.normalized())
		shell.material_override = am
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shell)
	if id == "saturn":
		root.add_child(make_rings(radius))
	return root

static func make_rings(radius: float) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var seg := 128
	var r0 := 1.2
	var r1 := 2.3
	for i in seg + 1:
		var a := float(i) / float(seg) * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		verts.append(dir * r0)
		verts.append(dir * r1)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
	for i in seg:
		var j := i * 2
		idx.append_array([j, j + 1, j + 2, j + 1, j + 3, j + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.scale = Vector3.ONE * radius
	var mat := ShaderMaterial.new()
	mat.shader = RINGS_SHADER
	mi.material_override = mat
	return mi

## Rotation about the axis in radians per second, with real sidereal periods sped up.
static func spin_rate(target: Dictionary, speedup: float = 3000.0) -> float:
	var hours: Variant = target.get("rotation_hours")
	if hours == null or absf(float(hours)) < 0.01:
		return 0.05
	return clampf(TAU / (float(hours) * 3600.0) * speedup, -0.6, 0.6)

## Point on a unit sphere for a latitude and longitude, matching SphereMesh UVs.
static func latlon_to_unit(lat: float, lon: float) -> Vector3:
	var u := (lon + 180.0) / 360.0
	var la := deg_to_rad(lat)
	return Vector3(sin(u * TAU) * cos(la), sin(la), cos(u * TAU) * cos(la))

static func line_loop(points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = false
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p in points:
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
