class_name World
extends RefCounted
## Builds a surface world: terrain (or cloud deck), sky, sun and atmosphere for any target.

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const CLOUD_SHADER := preload("res://shaders/cloud_deck.gdshader")

## Cloud tops for planets without a surface. Same interface the vehicles use on real terrain.
class CloudWorld extends Node3D:
	var world_m := 4096.0
	var y_scale := 1.0
	var material: ShaderMaterial
	var _plane: MeshInstance3D
	var _t := 0.0
	var color_image: Image = null
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP
	func real_elevation(_x: float, _z: float) -> float:
		return 0.0
	func uv_to_world(u: float, v: float) -> Vector3:
		return Vector3(u * world_m, 0.0, v * world_m)
	func set_pad(_p: Vector3, _r: float) -> void:
		pass
	func update_lod(cam: Vector3, delta: float) -> void:
		_t += delta
		material.set_shader_parameter("t", _t)
		_plane.global_position = Vector3(snappedf(cam.x, 40.0), -30.0, snappedf(cam.z, 40.0))
	func setup(art: Dictionary) -> void:
		var pm := PlaneMesh.new()
		pm.size = Vector2(9000, 9000)
		pm.subdivide_width = 150
		pm.subdivide_depth = 150
		_plane = MeshInstance3D.new()
		_plane.mesh = pm
		material = ShaderMaterial.new()
		material.shader = CLOUD_SHADER
		var bands: Array = art.get("bands", [Color(0.8, 0.8, 0.8), Color(0.5, 0.5, 0.5), Color(0.9, 0.9, 0.9)])
		material.set_shader_parameter("band_a", bands[0])
		material.set_shader_parameter("band_b", bands[1])
		material.set_shader_parameter("band_c", bands[2])
		material.set_shader_parameter("noise_tex", Terrain.detail_noise())
		_plane.material_override = material
		_plane.custom_aabb = AABB(Vector3(-4500, -60, -4500), Vector3(9000, 120, 9000))
		add_child(_plane)
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		img.fill(bands[0])
		color_image = img

## Region data for the chosen target. Bodies without bundled data get a labelled procedural site.
static func region_for(target: Dictionary) -> Dictionary:
	var rid: String = Game.mission.get("region_id", "")
	if Data.regions.has(rid) and Data.regions[rid].body == target.get("id", ""):
		return Data.regions[rid]
	var regs: Array = target.get("regions", [])
	if not regs.is_empty():
		return regs[0]
	return procedural_region(target)

static func procedural_region(target: Dictionary) -> Dictionary:
	var probe: bool = not target.get("has_surface", false)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(target.get("name", "x")))
	var facts: Array = target.get("facts", [])
	var types: Array = ["gas", "gas", "gas", "gas"] if probe else ["regolith", "rock", "core", "rock"]
	var pois: Array = []
	var prefix := "Sampling layer" if probe else "Survey site"
	var count := mini(maxi(facts.size(), 3), 4)
	for i in count:
		var ang := rng.randf() * 0.7 + float(i) * TAU / float(count)
		var rad := 0.16 + rng.randf() * 0.2
		var fact: Dictionary = facts[i % facts.size()] if not facts.is_empty() else {"text": "", "url": ""}
		pois.append({"name": "%s %s" % [prefix, "ABCD"[i]], "u": 0.5 + cos(ang) * rad, "v": 0.5 + sin(ang) * rad, "elev_m": null, "sample": types[i], "fact": fact})
	return {"id": "", "body": target.get("id", ""), "name": "Cloud tops" if probe else "Procedural survey zone", "real_elevation": false, "procedural": true,
		"dem_label": "Procedural surface generated from archive values" if target.get("kind") == "exoplanet" else "Procedural surface",
		"color_label": "Interpretive colours; no imagery of this surface exists in the bundled data",
		"width_km": 100.0, "hscale": 24.4, "vexag": 1.0, "landing_name": "Landing zone", "landing_uv": [0.5, 0.5], "pois": pois, "polar": false}

static func build(parent: Node3D, target: Dictionary, region: Dictionary) -> Dictionary:
	var id: String = target.get("id", "")
	var art: Dictionary = Data.art(id)
	var terrain: Node3D
	if not target.get("has_surface", false):
		var cw := CloudWorld.new()
		cw.setup(art)
		terrain = cw
	else:
		var t := Terrain.new()
		if region.get("procedural", false):
			t.setup_procedural(target, art)
		else:
			t.setup_region(region)
		terrain = t
	parent.add_child(terrain)
	# Sun: low over the lunar pole, otherwise mid-morning. Star colour comes from st_teff on exoplanets.
	var elev_deg := 5.0 if region.get("polar", false) else 38.0
	var az := deg_to_rad(40.0)
	var sun_dir := Vector3(cos(az) * cos(deg_to_rad(elev_deg)), sin(deg_to_rad(elev_deg)), sin(az) * cos(deg_to_rad(elev_deg)))
	var sun_col := Color(1.0, 0.97, 0.92)
	var sun_size := 0.0002
	if target.get("kind") == "exoplanet":
		sun_col = Data.star_color(target.get("st_teff"))
		sun_size = 0.0009
	var light := Space.make_sun_light(parent, sun_dir, sun_col, _sun_energy(target))
	light.shadow_enabled = Settings.use_shadows()
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if Settings.quality == 0 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_max_distance = Settings.shadow_distance()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_color", art.get("top", Color.BLACK))
	sky_mat.set_shader_parameter("horizon_color", art.get("horizon", Color.BLACK))
	sky_mat.set_shader_parameter("sun_color", sun_col)
	sky_mat.set_shader_parameter("sun_size", sun_size)
	sky_mat.set_shader_parameter("stars_amt", float(art.get("stars", 0.0)))
	var stars := Data.stars_texture()
	if stars:
		sky_mat.set_shader_parameter("stars_tex", stars)
		sky_mat.set_shader_parameter("has_stars", true)
	# The parent planet hangs in the sky at its real apparent size, computed from fact sheet values.
	if target.get("kind") == "moon":
		var p: Dictionary = Data.body(target.parent)
		var angular := atan(float(p.radius_km) / maxf(float(target.get("a_km", 1e6)), 1.0))
		sky_mat.set_shader_parameter("planet_size", angular)
		sky_mat.set_shader_parameter("planet_dir", Vector3(-0.5, 0.55, -0.6))
		var pc: Color = (Data.art(target.parent).get("bands", [Data.art(target.parent).get("atmo", Color.GRAY)]) as Array)[0]
		sky_mat.set_shader_parameter("planet_color", pc)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0 if float(art.get("atmo_amt", 0.0)) > 0.1 else 2.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 3.0
	env.glow_enabled = Settings.glow()
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.2
	var fog := float(art.get("fog", 0.0))
	# Thin-air worlds still get slight haze, so the far edge of the map fades out rather than cuts off.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = art.get("horizon", Color.BLACK)
	env.fog_density = maxf(fog, 0.00006)
	env.fog_sky_affect = 0.0 if fog <= 0.0 else 0.2
	env.fog_sun_scatter = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	return {"terrain": terrain, "light": light, "env": env, "sky": sky_mat, "art": art, "sun_dir": sun_dir}

static func _sun_energy(target: Dictionary) -> float:
	if target.get("kind") == "exoplanet":
		return 1.3
	var p: Dictionary = target if target.get("kind") == "planet" else Data.body(target.get("parent", "earth"))
	var au: float = float(p.get("a_km", 1.5e8)) * 1000.0 / Orbital.AU
	# Sunlight falls with distance squared. Compressed here so outer worlds stay playable.
	return clampf(1.45 * pow(1.0 / au, 0.22), 0.65, 1.8)
