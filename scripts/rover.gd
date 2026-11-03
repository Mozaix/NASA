class_name Rover
extends Node3D
## Six-wheeled rover on the height field. Gravity comes from real data and changes how it handles.

const MAX_SPEED := 24.0
const BOOST_SPEED := 40.0
const WHEELS := [Vector3(-1.4, 0, 1.7), Vector3(1.4, 0, 1.7), Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0), Vector3(-1.4, 0, -1.7), Vector3(1.4, 0, -1.7)]

var terrain: Node
var gravity := 3.7
var velocity := Vector3.ZERO
var heading := 0.0
var grounded := true
var distance := 0.0
var _wheels: Array[Node3D] = []
var _spin := 0.0
var _body: Node3D
var _dust: CPUParticles3D
var _lights: Array[SpotLight3D] = []
var _hop_cool := 0.0
var external_input := Vector2.ZERO

func setup(t: Node, g: float, dust_color: Color) -> void:
	terrain = t
	gravity = g
	_body = Node3D.new()
	add_child(_body)
	var white := Models.mat(Color(0.86, 0.87, 0.9), 0.25, 0.5)
	var dark := Models.mat(Color(0.2, 0.21, 0.24), 0.5, 0.5)
	var gold := Models.mat(Color(0.85, 0.65, 0.3), 0.8, 0.35)
	Models.cube(_body, Vector3(2.0, 0.55, 3.6), Vector3(0, 1.25, 0), white)
	Models.cube(_body, Vector3(1.7, 0.35, 1.5), Vector3(0, 1.7, -0.8), gold)
	Models.cube(_body, Vector3(1.6, 0.06, 2.2), Vector3(0, 1.62, 0.6), Models.mat(Color(0.08, 0.13, 0.32), 0.7, 0.25))
	Models.cyl(_body, 0.08, 0.1, 1.6, Vector3(0.6, 2.3, 1.3), white, 8)
	Models.cube(_body, Vector3(0.55, 0.3, 0.3), Vector3(0.6, 3.15, 1.35), dark)
	Models.cyl(_body, 0.35, 0.05, 0.15, Vector3(-0.7, 2.05, -1.2), white, 12)
	var arm := Models.cube(_body, Vector3(0.1, 0.1, 1.5), Vector3(-0.7, 1.1, 2.2), dark)
	arm.rotation.x = 0.4
	var tire := Models.mat(Color(0.16, 0.16, 0.18), 0.2, 0.8)
	for w: Vector3 in WHEELS:
		var holder := Node3D.new()
		holder.position = w
		_body.add_child(holder)
		var wheel := Models.cyl(holder, 0.55, 0.55, 0.45, Vector3(0, 0.55, 0), tire, 14)
		wheel.rotation.z = PI / 2.0
		Models.cube(wheel, Vector3(0.14, 0.5, 1.15), Vector3.ZERO, dark)
		_wheels.append(holder)
	for sx: float in [-0.7, 0.7]:
		var s := SpotLight3D.new()
		s.position = Vector3(sx, 1.6, 1.9)
		s.rotation.y = PI
		s.rotation.x = -0.15
		s.spot_range = 90.0
		s.spot_angle = 38.0
		s.light_energy = 4.0
		s.light_color = Color(1.0, 0.96, 0.86)
		s.visible = false
		_body.add_child(s)
		_lights.append(s)
	_dust = Models.dust(self, dust_color)
	_dust.position = Vector3(0, 0.3, -1.5)
	place(global_position)

func place(p: Vector3) -> void:
	global_position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
	velocity = Vector3.ZERO

func toggle_lights() -> bool:
	var on: bool = not _lights[0].visible
	for s in _lights:
		s.visible = on
	return on

func forward_dir() -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading))

func tick(delta: float, throttle: float, steer: float, boost: bool, hop: bool) -> void:
	var p := global_position
	var ground: float = terrain.height_at(p.x, p.z)
	var n: Vector3 = terrain.normal_at(p.x, p.z)
	grounded = p.y <= ground + 0.25
	_hop_cool = maxf(_hop_cool - delta, 0.0)
	var speed := Vector2(velocity.x, velocity.z).length()
	# Weak gravity means little wheel grip, so low-g worlds accelerate gently and drift.
	var grip := clampf(gravity / 3.7, 0.3, 1.1)
	if grounded:
		var fwd := forward_dir()
		var tangent := (fwd - n * fwd.dot(n)).normalized()
		var cap := BOOST_SPEED if boost else MAX_SPEED
		var turn_rate := lerpf(2.1, 0.9, clampf(speed / BOOST_SPEED, 0.0, 1.0))
		var along := velocity.dot(tangent)
		heading -= steer * turn_rate * delta * (1.0 if along >= -0.5 else -1.0)
		var accel := (22.0 if boost else 13.0) * grip
		if throttle > 0.0 and along < cap:
			velocity += tangent * accel * throttle * delta
		elif throttle < 0.0:
			velocity += tangent * accel * 1.2 * throttle * delta
		var side := tangent.cross(n).normalized()
		velocity -= side * velocity.dot(side) * clampf(delta * 5.0 * grip, 0.0, 1.0)
		if absf(throttle) < 0.05:
			velocity -= velocity * clampf(delta * 0.9 * grip, 0.0, 1.0)
		# Slopes pull the rover downhill in proportion to real gravity.
		var pull := Vector3.DOWN * gravity
		velocity += (pull - n * pull.dot(n)) * delta * 0.9
		var into := velocity.dot(n)
		if into < 0.0:
			velocity -= n * into
		if hop and _hop_cool <= 0.0:
			velocity += n * (6.0 + 2.5 * sqrt(gravity))
			_hop_cool = 1.2
			grounded = false
	else:
		velocity.y -= gravity * delta
		heading -= steer * 1.2 * delta
	p += velocity * delta
	var w: float = terrain.world_m
	var hit_edge := false
	if p.x < 12.0 or p.x > w - 12.0 or p.z < 12.0 or p.z > w - 12.0:
		hit_edge = true
		p.x = clampf(p.x, 12.0, w - 12.0)
		p.z = clampf(p.z, 12.0, w - 12.0)
		velocity *= 0.3
	var new_ground: float = terrain.height_at(p.x, p.z)
	if p.y < new_ground:
		p.y = new_ground
	elif grounded and p.y - new_ground < 0.6 and velocity.y <= 0.5:
		p.y = new_ground  # stick over small dips
	distance += Vector2(velocity.x, velocity.z).length() * delta
	global_position = p
	set_meta("hit_edge", hit_edge)
	_update_visuals(delta, n)

func _update_visuals(delta: float, n: Vector3) -> void:
	var fwd := forward_dir()
	var up := n if grounded else transform.basis.y.lerp(Vector3.UP, delta).normalized()
	var right := up.cross(fwd).normalized()
	var f2 := right.cross(up).normalized()
	var target := Basis(right, up, f2).orthonormalized()
	transform.basis = transform.basis.orthonormalized().slerp(target, clampf(delta * 9.0, 0.0, 1.0))
	var along := velocity.dot(fwd)
	_spin += along * delta / 0.55
	for i in _wheels.size():
		var holder := _wheels[i]
		var world: Vector3 = global_transform * (WHEELS[i] as Vector3)
		var ground: float = terrain.height_at(world.x, world.z)
		var offset: float = clampf(ground - world.y, -0.5, 0.45) if grounded else -0.25
		holder.position.y = lerpf(holder.position.y, offset, clampf(delta * 16.0, 0.0, 1.0))
		(holder.get_child(0) as Node3D).rotation.x = 0.0
		holder.rotation.x = _spin
		holder.get_child(0).position = Vector3(0, 0.55, 0)
	_dust.emitting = grounded and absf(along) > 4.0
