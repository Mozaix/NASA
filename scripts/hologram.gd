class_name Hologram
extends RefCounted
## Turns any model into a hologram. Each part keeps its own material, so one can flash when added.

const SHADER := preload("res://shaders/hologram.gdshader")

static func material(color: Color = Color(0.3, 0.85, 1.0)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("color", color)
	return m

static func apply(node: Node, mat: ShaderMaterial) -> void:
	if node is CPUParticles3D:
		node.queue_free()
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		apply(c, mat)

static func globe(map: Texture2D, radius: float) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 72
	sm.rings = 36
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	var m := material()
	if map:
		m.set_shader_parameter("map_tex", map)
		m.set_shader_parameter("use_map", true)
	mi.material_override = m
	return mi

## A rover with no moving parts, for display.
static func rover_model() -> Node3D:
	var root := Node3D.new()
	var plain := StandardMaterial3D.new()
	Models.cube(root, Vector3(2.0, 0.55, 3.6), Vector3(0, 1.25, 0), plain)
	Models.cube(root, Vector3(1.7, 0.35, 1.5), Vector3(0, 1.7, -0.8), plain)
	for w: Vector3 in Rover.WHEELS:
		var wheel := Models.cyl(root, Rover.WHEEL_R, Rover.WHEEL_R, 0.45, w + Vector3(0, Rover.WHEEL_R, 0), plain, 24)
		wheel.rotation.z = PI / 2.0
	return root

## Display models for each science instrument.
static func instrument_model(id: String) -> Node3D:
	var root := Node3D.new()
	var plain := StandardMaterial3D.new()
	match id:
		"camera":
			Models.cyl(root, 0.08, 0.1, 1.6, Vector3(0, 0.8, 0), plain, 12)
			Models.cube(root, Vector3(0.6, 0.32, 0.32), Vector3(0, 1.75, 0), plain)
		"spectrometer":
			Models.cube(root, Vector3(0.7, 0.45, 0.7), Vector3(0, 0.22, 0), plain)
			Models.cyl(root, 0.18, 0.28, 0.5, Vector3(0, 0.7, 0), plain, 16)
		"drill":
			Models.cube(root, Vector3(0.14, 1.5, 0.14), Vector3(0, 0.75, 0), plain)
			Models.cyl(root, 0.2, 0.0, 0.6, Vector3(0, -0.3, 0), plain, 16)
		_:
			Models.ball(root, 0.35, Vector3(0, 0.35, 0), plain)
	return root
