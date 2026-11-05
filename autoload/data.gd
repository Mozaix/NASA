extends Node
## Reads bundled NASA data. Nothing here touches the network.

var bodies: Dictionary = {}
var elements: Dictionary = {}
var exo: Dictionary = {}
var regions: Dictionary = {}
var milestones: Array = []
var lessons: Dictionary = {}
var _targets: Array = []
var _by_id: Dictionary = {}
var _tex_cache: Dictionary = {}

## Visual art direction only (not data). Sky colours for each world.
const ART := {
	"mercury": {"top": Color(0.0, 0.0, 0.01), "horizon": Color(0.03, 0.03, 0.04), "atmo": Color(0.6, 0.6, 0.6), "atmo_amt": 0.0, "stars": 1.0, "fog": 0.0},
	"venus": {"top": Color(0.55, 0.36, 0.12), "horizon": Color(0.95, 0.68, 0.30), "atmo": Color(1.0, 0.8, 0.45), "atmo_amt": 1.0, "stars": 0.0, "fog": 0.0005},
	"earth": {"top": Color(0.13, 0.33, 0.72), "horizon": Color(0.68, 0.82, 0.96), "atmo": Color(0.35, 0.6, 1.0), "atmo_amt": 0.9, "stars": 0.0, "fog": 0.00022},
	"moon": {"top": Color(0.0, 0.0, 0.0), "horizon": Color(0.01, 0.01, 0.015), "atmo": Color(0.5, 0.5, 0.5), "atmo_amt": 0.0, "stars": 1.0, "fog": 0.0},
	"mars": {"top": Color(0.42, 0.28, 0.20), "horizon": Color(0.86, 0.62, 0.42), "atmo": Color(0.95, 0.6, 0.38), "atmo_amt": 0.45, "stars": 0.05, "fog": 0.00022},
	"jupiter": {"top": Color(0.20, 0.17, 0.13), "horizon": Color(0.86, 0.72, 0.52), "atmo": Color(0.95, 0.8, 0.6), "atmo_amt": 0.7, "stars": 0.1, "fog": 0.0009, "bands": [Color(0.86, 0.75, 0.6), Color(0.65, 0.45, 0.32), Color(0.93, 0.88, 0.8)]},
	"saturn": {"top": Color(0.24, 0.2, 0.13), "horizon": Color(0.88, 0.78, 0.56), "atmo": Color(0.95, 0.85, 0.62), "atmo_amt": 0.6, "stars": 0.1, "fog": 0.0009, "bands": [Color(0.89, 0.8, 0.6), Color(0.76, 0.65, 0.46), Color(0.94, 0.89, 0.74)]},
	"uranus": {"top": Color(0.14, 0.3, 0.36), "horizon": Color(0.62, 0.86, 0.88), "atmo": Color(0.6, 0.9, 0.95), "atmo_amt": 0.7, "stars": 0.1, "fog": 0.0009, "bands": [Color(0.66, 0.88, 0.9), Color(0.58, 0.82, 0.86), Color(0.72, 0.91, 0.92)]},
	"neptune": {"top": Color(0.04, 0.09, 0.3), "horizon": Color(0.26, 0.45, 0.85), "atmo": Color(0.3, 0.5, 1.0), "atmo_amt": 0.8, "stars": 0.1, "fog": 0.0009, "bands": [Color(0.2, 0.36, 0.8), Color(0.14, 0.26, 0.66), Color(0.35, 0.52, 0.9)]},
	"io": {"top": Color(0.0, 0.0, 0.01), "horizon": Color(0.05, 0.04, 0.02), "atmo": Color(0.9, 0.8, 0.4), "atmo_amt": 0.05, "stars": 1.0, "fog": 0.0},
	"europa": {"top": Color(0.0, 0.0, 0.01), "horizon": Color(0.02, 0.03, 0.05), "atmo": Color(0.7, 0.8, 1.0), "atmo_amt": 0.0, "stars": 1.0, "fog": 0.0},
	"ganymede": {"top": Color(0.0, 0.0, 0.01), "horizon": Color(0.02, 0.03, 0.04), "atmo": Color(0.7, 0.8, 1.0), "atmo_amt": 0.0, "stars": 1.0, "fog": 0.0},
	"callisto": {"top": Color(0.0, 0.0, 0.01), "horizon": Color(0.02, 0.02, 0.03), "atmo": Color(0.7, 0.7, 0.8), "atmo_amt": 0.0, "stars": 1.0, "fog": 0.0},
	"titan": {"top": Color(0.42, 0.26, 0.06), "horizon": Color(0.86, 0.58, 0.20), "atmo": Color(1.0, 0.65, 0.2), "atmo_amt": 1.0, "stars": 0.0, "fog": 0.00042},
	"enceladus": {"top": Color(0.0, 0.0, 0.01), "horizon": Color(0.03, 0.04, 0.06), "atmo": Color(0.8, 0.9, 1.0), "atmo_amt": 0.0, "stars": 1.0, "fog": 0.0},
	"triton": {"top": Color(0.0, 0.01, 0.03), "horizon": Color(0.06, 0.1, 0.17), "atmo": Color(0.6, 0.75, 1.0), "atmo_amt": 0.12, "stars": 0.9, "fog": 0.00004, "ground": [Color(0.42, 0.40, 0.42), Color(0.78, 0.72, 0.70), Color(0.92, 0.88, 0.85)]},
}

func _ready() -> void:
	bodies = _json("res://data/bodies.json")
	elements = _json("res://data/elements.json")
	exo = _json("res://data/exoplanets.json")
	regions = _json("res://data/regions.json")
	milestones = _json("res://data/milestones.json").get("milestones", [])
	lessons = _json("res://data/lessons.json").get("lessons", {})
	_build_targets()

func _json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Missing data file: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _build_targets() -> void:
	_targets.clear()
	_by_id.clear()
	var order: Array[String] = ["mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune",
		"moon", "io", "europa", "ganymede", "callisto", "titan", "enceladus", "triton"]
	for id: String in order:
		if not bodies.has(id):
			continue
		var b: Dictionary = bodies[id]
		var giant := float(b.get("radius_km", 0.0)) > 20000.0
		b["has_surface"] = not giant
		b["has_map"] = FileAccess.file_exists("res://data/textures/%s.jpgdata" % id)
		b["regions"] = regions_for(id)
		_targets.append(b)
		_by_id[id] = b
	var planets: Array = exo.get("planets", [])
	var class_facts: Dictionary = exo.get("class_facts", {})
	for raw: Dictionary in planets:
		var p: Dictionary = raw.duplicate()
		p["name"] = p.pl_name
		p["kind"] = "exoplanet"
		p["parent"] = "sun"
		p["radius_km"] = float(p.get("pl_rade", 1.0)) * 6371.0
		p["mass_kg"] = float(p.get("pl_bmasse", 1.0)) * 5.9722e24
		p["has_map"] = false
		p["regions"] = []
		var facts: Array = []
		facts.append_array(class_facts.get(p["class"], []))
		facts.append_array(class_facts.get("general", []))
		p["facts"] = facts
		_targets.append(p)
		_by_id[p.id] = p

func targets() -> Array:
	return _targets

func body(id: String) -> Dictionary:
	return _by_id.get(id, {})

func regions_for(body_id: String) -> Array:
	var out: Array = []
	for rid: String in regions:
		if regions[rid].body == body_id:
			out.append(regions[rid])
	return out

func has_atmosphere(b: Dictionary) -> bool:
	if b.get("kind") == "exoplanet":
		return not b.get("has_surface", false) or float(b.get("pl_eqt", 0.0) if b.get("pl_eqt") != null else 0.0) < 1000.0
	if b.get("id") == "titan":
		return true  # NASA fact: "the only moon in the solar system with a dense atmosphere"
	var p: Variant = b.get("pressure_bar")
	if p == null:
		return b.get("radius_km", 0.0) > 20000.0
	return float(p) >= 0.005

func art(id: String) -> Dictionary:
	if ART.has(id):
		return ART[id]
	return exo_art(_by_id.get(id, {}))

## Exoplanet colours are interpreted from archive temperature and class, and labelled as such.
func exo_art(p: Dictionary) -> Dictionary:
	var t := float(p.get("pl_eqt") if p.get("pl_eqt") != null else 250.0)
	var cls: String = p.get("class", "terrestrial")
	if cls in ["gas_giant", "neptune_like"]:
		var bands: Array
		if t > 1200.0:
			bands = [Color(0.95, 0.5, 0.2), Color(0.55, 0.16, 0.08), Color(1.0, 0.75, 0.4)]
		elif t > 500.0:
			bands = [Color(0.75, 0.6, 0.45), Color(0.55, 0.38, 0.3), Color(0.9, 0.8, 0.65)]
		elif t > 150.0:
			bands = [Color(0.85, 0.8, 0.68), Color(0.65, 0.58, 0.48), Color(0.95, 0.93, 0.85)]
		else:
			bands = [Color(0.45, 0.65, 0.9), Color(0.3, 0.48, 0.8), Color(0.65, 0.82, 0.95)]
		var hz: Color = bands[0]
		return {"top": hz.darkened(0.75), "horizon": hz, "atmo": bands[2], "atmo_amt": 0.8, "stars": 0.1, "fog": 0.0009, "bands": bands}
	var ground: Array
	var a := {"atmo_amt": 0.2, "stars": 0.6, "fog": 0.0001}
	if t > 1000.0:
		ground = [Color(0.08, 0.05, 0.05), Color(0.25, 0.14, 0.1), Color(0.5, 0.3, 0.2)]
		a = {"atmo_amt": 0.0, "stars": 1.0, "fog": 0.0, "lava": 1.0}
		a["top"] = Color(0.02, 0.0, 0.0)
		a["horizon"] = Color(0.3, 0.08, 0.02)
		a["atmo"] = Color(1.0, 0.4, 0.15)
	elif t > 400.0:
		ground = [Color(0.3, 0.2, 0.14), Color(0.55, 0.38, 0.24), Color(0.8, 0.62, 0.42)]
		a["top"] = Color(0.3, 0.16, 0.08)
		a["horizon"] = Color(0.85, 0.55, 0.3)
		a["atmo"] = Color(1.0, 0.6, 0.3)
		a["atmo_amt"] = 0.6
		a["stars"] = 0.1
		a["fog"] = 0.0004
	elif t > 180.0:
		ground = [Color(0.22, 0.26, 0.24), Color(0.42, 0.42, 0.34), Color(0.62, 0.58, 0.5)]
		a["top"] = Color(0.12, 0.2, 0.42)
		a["horizon"] = Color(0.55, 0.65, 0.78)
		a["atmo"] = Color(0.45, 0.65, 1.0)
		a["atmo_amt"] = 0.6
		a["stars"] = 0.15
		a["fog"] = 0.0002
	else:
		ground = [Color(0.5, 0.55, 0.62), Color(0.75, 0.8, 0.88), Color(0.95, 0.97, 1.0)]
		a["top"] = Color(0.0, 0.01, 0.04)
		a["horizon"] = Color(0.1, 0.15, 0.25)
		a["atmo"] = Color(0.6, 0.75, 1.0)
		a["atmo_amt"] = 0.1
		a["stars"] = 0.9
	a["ground"] = ground
	return a

## Approximate star colour from effective temperature (Tanner Helland fit). Null means no value in the archive.
func star_color(teff: Variant) -> Color:
	if teff == null:
		return Color(0.75, 0.85, 1.0)
	var t := clampf(float(teff), 1000.0, 40000.0) / 100.0
	var r := 255.0 if t <= 66.0 else 329.698727 * pow(t - 60.0, -0.1332047)
	var g := 99.4708 * log(t) - 161.1196 if t <= 66.0 else 288.122 * pow(t - 60.0, -0.0755148)
	var b := 255.0
	if t < 66.0:
		b = 0.0 if t <= 19.0 else 138.5177 * log(t - 10.0) - 305.0448
	return Color(clampf(r, 0.0, 255.0) / 255.0, clampf(g, 0.0, 255.0) / 255.0, clampf(b, 0.0, 255.0) / 255.0)

# ---- Texture loading: images ship as raw JPEG/PNG bytes and are decoded here ----

func load_image(path: String, mipmaps: bool = true) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes) if path.ends_with(".jpgdata") else img.load_png_from_buffer(bytes)
	if err != OK:
		push_error("Could not decode " + path)
		return null
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	if mipmaps:
		img.generate_mipmaps()
	return img

func texture(path: String, mipmaps: bool = true) -> ImageTexture:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var img := load_image(path, mipmaps)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[path] = tex
	# Keep the cache small: a 4K map costs about 45 MB of video memory.
	if _tex_cache.size() > 8:
		_tex_cache.erase(_tex_cache.keys()[0])
	return tex

func planet_texture(id: String) -> ImageTexture:
	var path := "res://data/textures/%s.jpgdata" % id
	return texture(path) if FileAccess.file_exists(path) else null

func stars_texture() -> ImageTexture:
	var path := "res://data/textures/stars.jpgdata"
	return texture(path, false) if FileAccess.file_exists(path) else null

func height_array(region_id: String) -> PackedFloat32Array:
	return FileAccess.get_file_as_bytes("res://data/regions/%s/height.f32" % region_id).to_float32_array()
