class_name ProbeCraft
extends Node3D
## Atmospheric probe for worlds with no surface. Real gravity makes it sink; thrust holds altitude.

const MAX_SPEED := 42.0
var terrain: Node
var gravity := 10.0
var velocity := Vector3.ZERO
var heading := 0.0
var grounded := false
var distance := 0.0
var speed_mult := 1.0

func setup(t: Node, g: float, _dust: Color) -> void:
	terrain = t
	# Sink rate grows with gravity, capped so Jupiter stays flyable.
	gravity = minf(g, 25.0)
	add_child(Models.probe())
	global_position = Vector3(global_position.x, 70.0, global_position.z)

func place(p: Vector3) -> void:
	global_position = Vector3(p.x, 70.0, p.z)
	velocity = Vector3.ZERO

func toggle_lights() -> bool:
	return false

func forward_dir() -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading))

func tick(delta: float, throttle: float, steer: float, boost: bool, hop: bool) -> void:
	heading -= steer * 1.5 * delta
	var cap := MAX_SPEED * (1.5 if boost else 1.0) * speed_mult
	var target := forward_dir() * throttle * cap
	var h := Vector2(velocity.x, velocity.z).lerp(Vector2(target.x, target.z), clampf(delta * 1.6, 0.0, 1.0))
	var p := global_position
	var sink := gravity * 0.25
	var lift := gravity * 0.25 + 12.0 if hop else (gravity * 0.25 if p.y < 60.0 else 0.0)
	velocity = Vector3(h.x, clampf(velocity.y + (lift - sink) * delta, -14.0, 14.0), h.y)
	p += velocity * delta
	p.y = clampf(p.y, 22.0, 260.0)
	if p.y <= 22.0 or p.y >= 260.0:
		velocity.y = 0.0
	var w: float = terrain.world_m
	p.x = clampf(p.x, 12.0, w - 12.0)
	p.z = clampf(p.z, 12.0, w - 12.0)
	distance += h.length() * delta
	global_position = p
	rotation = Vector3(-velocity.y * 0.012, heading, -steer * 0.3)
