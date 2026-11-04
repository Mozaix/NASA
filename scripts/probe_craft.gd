class_name ProbeCraft
extends Node3D
## Atmospheric probe for worlds with no surface. Real gravity makes it sink; thrust holds altitude.
## It flies like a glider: turns ease in and out, and the body banks into them.

const MAX_SPEED := 42.0
const TURN_RATE := 1.05  # radians per second at full stick
const TURN_EASE := 2.6   # how quickly the turn builds and fades
const ATTITUDE_EASE := 3.2
var terrain: Node
var gravity := 10.0
var velocity := Vector3.ZERO
var heading := 0.0
var grounded := false
var distance := 0.0
var speed_mult := 1.0
var turn := 0.0
var _lift := 0.0
var _bank := 0.0
var _nose := 0.0

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
	turn = lerpf(turn, steer, 1.0 - exp(-delta * TURN_EASE))
	heading -= turn * TURN_RATE * delta
	var cap := MAX_SPEED * (1.5 if boost else 1.0) * speed_mult
	var target := forward_dir() * throttle * cap
	# Speed follows the nose gradually, so the probe sweeps round a turn rather than sliding.
	var h := Vector2(velocity.x, velocity.z).lerp(Vector2(target.x, target.z), 1.0 - exp(-delta * 1.4))
	var p := global_position
	var sink := gravity * 0.25
	var hold := clampf((62.0 - p.y) / 12.0, 0.0, 1.0)  # fades in near the floor instead of switching on
	var want_lift := sink + 12.0 if hop else sink * hold
	_lift = lerpf(_lift, want_lift, 1.0 - exp(-delta * 5.0))
	velocity = Vector3(h.x, clampf(velocity.y + (_lift - sink) * delta, -14.0, 14.0), h.y)
	p += velocity * delta
	# Ease out of the climb and the dive before reaching the limits.
	if p.y < 34.0 and velocity.y < 0.0:
		velocity.y = lerpf(velocity.y, 0.0, 1.0 - exp(-delta * 3.0))
	elif p.y > 240.0 and velocity.y > 0.0:
		velocity.y = lerpf(velocity.y, 0.0, 1.0 - exp(-delta * 3.0))
	p.y = clampf(p.y, 22.0, 260.0)
	var w: float = terrain.world_m
	p.x = clampf(p.x, 12.0, w - 12.0)
	p.z = clampf(p.z, 12.0, w - 12.0)
	distance += h.length() * delta
	global_position = p
	var ease_k := 1.0 - exp(-delta * ATTITUDE_EASE)
	_bank = lerpf(_bank, -turn * 0.55, ease_k)
	_nose = lerpf(_nose, -velocity.y * 0.018, ease_k)
	rotation = Vector3(_nose, heading, _bank)
