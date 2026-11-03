class_name Terrain
extends Node3D
## GPU-displaced terrain with chunk LODs. The same heights drive the rover, lander and POIs.

const CHUNK_TEXELS := 64
const SHADER := preload("res://shaders/terrain.gdshader")

var world_m := 4096.0
var n := 1024
var texel := 4.0
var y_scale := 1.0
var y_ref := 0.0
var heights := PackedFloat32Array()
var material: ShaderMaterial
var color_image: Image
var _chunks: Array[MeshInstance3D] = []
var _meshes: Array[ArrayMesh] = []
var _lod_dist: Array[float] = []
var _time := 0.0
var _morph_now := PackedFloat32Array()

static func _grid_mesh(step_t: int) -> ArrayMesh:
	# Vertices are in texel units; node scale turns them into metres. UV.x flags the skirt.
	var cells := CHUNK_TEXELS / step_t
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var side := cells + 1
	for z in side:
		for x in side:
			verts.append(Vector3(x * step_t, 0.0, z * step_t))
			uvs.append(Vector2.ZERO)
	for z in cells:
		for x in cells:
			var a := z * side + x
			idx.append_array([a, a + 1, a + side, a + 1, a + side + 1, a + side])
	# Skirt ring: each border vertex gets a twin that the shader pulls straight down.
	var border: Array[int] = []
	for x in side:
		border.append(x)
	for z in range(1, side):
		border.append(z * side + cells)
	for x in range(cells - 1, -1, -1):
		border.append(cells * side + x)
	for z in range(cells - 1, 0, -1):
		border.append(z * side)
	var first := verts.size()
	for b in border:
		verts.append(verts[b])
		uvs.append(Vector2(1.0, 0.0))
	var count := border.size()
	for i in count:
		var j := (i + 1) % count
		var top_a := border[i]
		var top_b := border[j]
		var low_a := first + i
		var low_b := first + j
		idx.append_array([top_a, low_a, top_b, top_b, low_a, low_b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func setup_region(region: Dictionary) -> void:
	var rid: String = region.id
	n = int(region.height_n)
	world_m = float(region.world_m)
	texel = world_m / float(n)
	heights = Data.height_array(rid)
	y_scale = float(region.vexag) / float(region.hscale)
	var landing: Array = region.landing_uv
	y_ref = _sample_raw(float(landing[0]) * world_m, float(landing[1]) * world_m)
	var color := Data.load_image("res://data/regions/%s/color.jpgdata" % rid)
	var normal := Data.load_image("res://data/regions/%s/normal.pngdata" % rid)
	color_image = Data.load_image("res://data/regions/%s/minimap.jpgdata" % rid, false)
	_finish(ImageTexture.create_from_image(color), ImageTexture.create_from_image(normal), 0.0)

## Procedural world, for exoplanets and Triton. Clearly labelled in the HUD.
func setup_procedural(body: Dictionary, art: Dictionary) -> void:
	n = 768
	world_m = 4096.0
	texel = world_m / float(n)
	y_scale = 1.0
	y_ref = 0.0
	var seed_v := hash(str(body.get("name", "x")))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.0028
	noise.domain_warp_enabled = false
	var ridge := FastNoiseLite.new()
	ridge.seed = seed_v + 7
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	ridge.frequency = 0.0045
	# Stronger gravity gives flatter terrain: a real tendency, used here as a rule of thumb.
	var g: float = maxf(float(body.get("gravity", 9.8)), 0.3)
	var amp: float = clampf(190.0 * pow(9.8 / g, 0.4), 70.0, 280.0)
	heights.resize(n * n)
	for z in n:
		for x in n:
			var h := noise.get_noise_2d(float(x), float(z)) * 0.8 + ridge.get_noise_2d(float(x), float(z)) * 0.35
			heights[z * n + x] = h * amp
	# Scatter a few craters directly into the height field.
	var crater_count: int = 22 if art.get("fog", 0.0) < 0.0002 else 7
	for i in crater_count:
		_carve_crater(rng.randf() * n, rng.randf() * n, 8.0 + pow(rng.randf(), 2.5) * 70.0, amp)
	y_ref = heights[n / 2 * n + n / 2]
	var ramp: Array = art.get("ground", [Color(0.3, 0.3, 0.3), Color(0.5, 0.5, 0.5), Color(0.7, 0.7, 0.7)])
	var color := Image.create(n, n, false, Image.FORMAT_RGB8)
	var normal := Image.create(n, n, false, Image.FORMAT_RGB8)
	var inv := 1.0 / (amp * 1.6)
	for z in n:
		for x in n:
			var i := z * n + x
			var hx: float = heights[z * n + mini(x + 1, n - 1)] - heights[i]
			var hz: float = heights[mini(z + 1, n - 1) * n + x] - heights[i]
			var nrm := Vector3(-hx, texel, -hz).normalized()
			normal.set_pixel(x, z, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5))
			var t := clampf(heights[i] * inv + 0.5, 0.0, 1.0)
			var c: Color = (ramp[0] as Color).lerp(ramp[1], t * 2.0) if t < 0.5 else (ramp[1] as Color).lerp(ramp[2], t * 2.0 - 1.0)
			c = c.darkened(clampf((1.0 - nrm.y) * 1.6, 0.0, 0.45))
			color.set_pixel(x, z, c)
	color_image = color.duplicate()
	color_image.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	color.generate_mipmaps()
	normal.generate_mipmaps()
	_finish(ImageTexture.create_from_image(color), ImageTexture.create_from_image(normal), float(art.get("lava", 0.0)))

func _carve_crater(cx: float, cz: float, r: float, amp: float) -> void:
	var rad := int(r * 1.5)
	var depth := amp * 0.03 + r * 0.45
	for z in range(maxi(int(cz) - rad, 0), mini(int(cz) + rad, n)):
		for x in range(maxi(int(cx) - rad, 0), mini(int(cx) + rad, n)):
			var d := Vector2(float(x) - cx, float(z) - cz).length() / r
			var bowl := (d * d - 1.0) if d < 1.0 else 0.0
			var rim := 0.25 * exp(-pow((d - 1.0) / 0.25, 2.0))
			heights[z * n + x] += (bowl + rim) * depth

func _finish(color: Texture2D, normal: Texture2D, lava: float) -> void:
	var height_img := Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("height_tex", ImageTexture.create_from_image(height_img))
	material.set_shader_parameter("color_tex", color)
	material.set_shader_parameter("normal_tex", normal)
	material.set_shader_parameter("detail_tex", detail_noise())
	material.set_shader_parameter("world_m", world_m)
	material.set_shader_parameter("n_side", float(n))
	material.set_shader_parameter("y_scale", y_scale)
	material.set_shader_parameter("y_ref", y_ref)
	material.set_shader_parameter("lava", lava)
	_build_chunks()

static var _noise_cache: NoiseTexture2D

static func detail_noise() -> NoiseTexture2D:
	if _noise_cache:
		return _noise_cache
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.seed = 11
	fn.frequency = 0.02
	fn.fractal_octaves = 5
	nt.noise = fn
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.normalize = true
	_noise_cache = nt
	return nt

func _build_chunks() -> void:
	_meshes.clear()
	for step_t: int in [1, 2, 4, 8]:
		_meshes.append(_grid_mesh(step_t))
	var size := float(CHUNK_TEXELS) * texel
	var ls := Settings.lod_scale()
	var finest := maxf(size * 1.4 * ls, size * 0.71 + 130.0)
	_lod_dist = [finest, maxf(size * 2.8 * ls, finest + size), maxf(size * 5.5 * ls, finest + size * 2.0)]
	# y range for culling boxes
	var lo := INF
	var hi := -INF
	for v in heights:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var ylo := (lo - y_ref) * y_scale - 40.0
	var yhi := (hi - y_ref) * y_scale + 10.0
	var count := n / CHUNK_TEXELS
	for cz in count:
		for cx in count:
			var mi := MeshInstance3D.new()
			mi.material_override = material
			mi.position = Vector3(cx * size, 0.0, cz * size)
			mi.scale = Vector3(texel, 1.0, texel)
			mi.custom_aabb = AABB(Vector3(0, ylo, 0), Vector3(CHUNK_TEXELS, yhi - ylo, CHUNK_TEXELS))
			mi.mesh = _meshes[3]
			mi.set_instance_shader_parameter("lod_step", 8.0)
			add_child(mi)
			_chunks.append(mi)
			_morph_now.append(0.0)
	# Coarse mirrored ring beyond the map edge, so the world does not visibly end.
	var ring_scale := 8.0
	var ring_size := size * ring_scale
	var ring_n := count / int(ring_scale)
	for cz in range(-ring_n, ring_n * 2):
		for cx in range(-ring_n, ring_n * 2):
			if cx >= 0 and cx < ring_n and cz >= 0 and cz < ring_n:
				continue
			var mi := MeshInstance3D.new()
			mi.material_override = material
			mi.mesh = _meshes[3]
			mi.position = Vector3(cx * ring_size, 0.0, cz * ring_size)
			mi.scale = Vector3(texel * ring_scale, 1.0, texel * ring_scale)
			mi.custom_aabb = AABB(Vector3(0, ylo, 0), Vector3(CHUNK_TEXELS, yhi - ylo, CHUNK_TEXELS))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)

func update_lod(cam_pos: Vector3, delta: float) -> void:
	_time += delta
	material.set_shader_parameter("time_s", _time)
	var half := float(CHUNK_TEXELS) * texel * 0.5
	for i in _chunks.size():
		var c := _chunks[i]
		var d := Vector2(c.position.x + half - cam_pos.x, c.position.z + half - cam_pos.z).length()
		var lod := 3
		if d < _lod_dist[0]:
			lod = 0
		elif d < _lod_dist[1]:
			lod = 1
		elif d < _lod_dist[2]:
			lod = 2
		var m := _meshes[lod]
		if c.mesh != m:
			c.mesh = m
			c.set_instance_shader_parameter("lod_step", float(1 << lod))
		# Blend toward the next level over the last stretch before switching, so nothing pops.
		var blend := 0.0
		if lod < 3:
			blend = smoothstep(_lod_dist[lod] * 0.78, _lod_dist[lod], d)
		if not is_equal_approx(_morph_now[i], blend):
			_morph_now[i] = blend
			c.set_instance_shader_parameter("morph", blend)

func set_pad(pos: Vector3, radius: float) -> void:
	material.set_shader_parameter("pad_pos", pos)
	material.set_shader_parameter("pad_radius", radius)

func _sample_raw(x: float, z: float) -> float:
	var fx := clampf(x / texel, 0.0, float(n - 1))
	var fz := clampf(z / texel, 0.0, float(n - 1))
	var ix := mini(int(fx), n - 2)
	var iz := mini(int(fz), n - 2)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var a := heights[iz * n + ix]
	var b := heights[iz * n + ix + 1]
	var c := heights[(iz + 1) * n + ix]
	var d := heights[(iz + 1) * n + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

## World height of one grid vertex, exactly as the terrain shader displaces it.
func vertex_height(ix: int, iz: int) -> float:
	var i := clampi(iz, 0, n - 1) * n + clampi(ix, 0, n - 1)
	return (heights[i] - y_ref) * y_scale

## Game-world height in metres at a world position. Follows the same two triangles per cell, with
## the same diagonal, as the finest mesh, so vehicles sit on exactly the surface the player sees.
func height_at(x: float, z: float) -> float:
	var fx := clampf(x / texel, 0.0, float(n - 1))
	var fz := clampf(z / texel, 0.0, float(n - 1))
	var ix := mini(int(fx), n - 2)
	var iz := mini(int(fz), n - 2)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var i := iz * n + ix
	var b := heights[i + 1]
	var c := heights[i + n]
	var h: float
	if tx + tz < 1.0:
		var a := heights[i]
		h = a + (b - a) * tx + (c - a) * tz
	else:
		var d := heights[i + n + 1]
		h = d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)
	return (h - y_ref) * y_scale

func normal_at(x: float, z: float) -> Vector3:
	var e := texel
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()

## True elevation in metres from the dataset, for readouts.
func real_elevation(x: float, z: float) -> float:
	return _sample_raw(x, z)

## Steepest slope, in degrees, under a lander-sized footprint.
func footprint_slope(x: float, z: float, r: float = 12.0) -> float:
	var worst := 0.0
	for offset: Vector2 in [Vector2(r, 0.0), Vector2(0.0, r), Vector2(r, r).normalized() * r, Vector2(r, -r).normalized() * r]:
		var rise := absf(height_at(x + offset.x, z + offset.y) - height_at(x - offset.x, z - offset.y))
		worst = maxf(worst, rad_to_deg(atan2(rise, 2.0 * r)))
	return worst

## The named site if it is safe, otherwise the nearest ground gentle enough to land on.
## Height exaggeration steepens real slopes, so a real coordinate can still be too steep in the game.
func flat_spot(u: float, v: float, max_slope: float = 11.0) -> Vector3:
	var x0 := u * world_m
	var z0 := v * world_m
	if footprint_slope(x0, z0) <= max_slope:
		return Vector3(x0, height_at(x0, z0), z0)
	var best := Vector3(x0, 0.0, z0)
	var best_slope := INF
	for ring in range(1, 41):
		var radius := float(ring) * 30.0
		for i in 24:
			var a := float(i) / 24.0 * TAU
			var x := clampf(x0 + cos(a) * radius, 60.0, world_m - 60.0)
			var z := clampf(z0 + sin(a) * radius, 60.0, world_m - 60.0)
			var s := footprint_slope(x, z)
			if s < best_slope:
				best_slope = s
				best = Vector3(x, 0.0, z)
		if best_slope <= max_slope:
			break
	best.y = height_at(best.x, best.z)
	return best

func uv_to_world(u: float, v: float) -> Vector3:
	var x := u * world_m
	var z := v * world_m
	return Vector3(x, height_at(x, z), z)
