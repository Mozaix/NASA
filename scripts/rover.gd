class_name Rover
extends Node3D
## Six-wheeled rover on the height field. Gravity comes from real data and changes how it handles.

const MAX_SPEED := 24.0
const BOOST_SPEED := 40.0
## Reverse is slow, like a real rover's, and boost does not apply to it.
const REVERSE_SPEED := 8.0
const WHEELS := [Vector3(-1.4, 0, 1.7), Vector3(1.4, 0, 1.7), Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0), Vector3(-1.4, 0, -1.7), Vector3(1.4, 0, -1.7)]

const WHEEL_R := 0.55
const TRAVEL_UP := 0.7
const TRAVEL_DOWN := 0.35
## Lowest points of the chassis, in body space.
const BODY_CORNERS: Array[Vector3] = [Vector3(-1.0, 0.97, -1.8), Vector3(1.0, 0.97, -1.8), Vector3(-1.0, 0.97, 1.8), Vector3(1.0, 0.97, 1.8), Vector3(0.0, 0.97, 0.0)]

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
var _fill: OmniLight3D
const MAX_HEALTH := 100.0
## Below this closing speed a rock only stops the rover.
const SAFE_IMPACT := 6.0
const BAIL_DAMAGE := 15.0
const FLIP_RATE := 4.5
const SPIN_RATE := 5.5
var health := MAX_HEALTH
var trick_held := false
var damage_scale := 1.0
## Solid rocks nearby: x, y, z of the base and w for radius. Pebbles are left out, and the rover rolls over those.
var rocks: Array[Vector4] = []
var trick := TrickScore.new()
var last_hit := 0.0
var last_paid := 0
var bailed := false
var _flip := 0.0
var _lift := 0.0
var _air_time := 0.0
var _hit_cool := 0.0
var _smoke: CPUParticles3D
var _hop_cool := 0.0
var speed_mult := 1.0

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
	Models.cyl(_body, 0.08, 0.1, 1.6, Vector3(0.6, 2.3, 1.3), white, 16)
	Models.cube(_body, Vector3(0.55, 0.3, 0.3), Vector3(0.6, 3.15, 1.35), dark)
	Models.cyl(_body, 0.35, 0.05, 0.15, Vector3(-0.7, 2.05, -1.2), white, 24)
	var arm := Models.cube(_body, Vector3(0.1, 0.1, 1.5), Vector3(-0.7, 1.1, 2.2), dark)
	arm.rotation.x = 0.4
	var tire := Models.mat(Color(0.16, 0.16, 0.18), 0.2, 0.8)
	for w: Vector3 in WHEELS:
		var holder := Node3D.new()
		holder.position = w
		_body.add_child(holder)
		# holder moves with the suspension; axle sits at the wheel's centre and is what spins.
		var axle := Node3D.new()
		axle.position = Vector3(0, WHEEL_R, 0)
		holder.add_child(axle)
		var wheel := Models.cyl(axle, WHEEL_R, WHEEL_R, 0.45, Vector3.ZERO, tire, 28)
		wheel.rotation.z = PI / 2.0
		Models.cube(wheel, Vector3(0.14, 0.5, 1.15), Vector3.ZERO, dark)
		_wheels.append(holder)
	for sx: float in [-0.7, 0.7]:
		var s := SpotLight3D.new()
		s.position = Vector3(sx, 1.6, 1.9)
		s.rotation.y = PI
		s.rotation.x = -0.15
		s.spot_range = 170.0
		s.spot_angle = 48.0
		s.spot_attenuation = 0.55
		s.light_energy = 9.0
		s.light_color = Color(1.0, 0.96, 0.86)
		s.visible = false
		_body.add_child(s)
		_lights.append(s)
	# Soft pool of light around the rover, so the ground beside it and the rover itself show in deep shadow.
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 5.0, 1.0)
	fill.omni_range = 34.0
	fill.omni_attenuation = 0.7
	fill.light_energy = 1.6
	fill.light_color = Color(1.0, 0.96, 0.88)
	fill.visible = false
	_body.add_child(fill)
	_fill = fill
	_dust = Models.dust(self, dust_color)
	_dust.position = Vector3(0, 0.3, -1.5)
	_smoke = Models.dust(self, Color(0.12, 0.12, 0.13))
	_smoke.position = Vector3(0, 2.2, -0.6)
	_smoke.emitting = false
	place(global_position)

func place(p: Vector3) -> void:
	global_position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
	velocity = Vector3.ZERO

func body_node() -> Node3D:
	return _body

## The node at each wheel's axle.
func wheel_axles() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for h in _wheels:
		out.append(h.get_child(0) as Node3D)
	return out

func toggle_lights() -> bool:
	var on: bool = not _lights[0].visible
	for s in _lights:
		s.visible = on
	_fill.visible = on
	return on

func forward_dir() -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading))

func tick(delta: float, throttle: float, steer: float, boost: bool, hop: bool) -> void:
	var p := global_position
	var ground: float = terrain.height_at(p.x, p.z)
	var n: Vector3 = terrain.normal_at(p.x, p.z)
	grounded = p.y <= ground + 0.25
	_hop_cool = maxf(_hop_cool - delta, 0.0)
	_hit_cool = maxf(_hit_cool - delta, 0.0)
	last_hit = 0.0
	last_paid = 0
	bailed = false
	# A wrecked rover has no drive left. It only coasts to a stop.
	if health <= 0.0:
		throttle = 0.0
		steer = 0.0
		boost = false
		hop = false
	_touch_down_if_needed()
	var speed := Vector2(velocity.x, velocity.z).length()
	# Weak gravity means little wheel grip, so low-g worlds accelerate gently and drift.
	var grip := clampf(gravity / 3.7, 0.3, 1.1)
	if grounded:
		var fwd := forward_dir()
		var tangent := (fwd - n * fwd.dot(n)).normalized()
		var cap := (BOOST_SPEED if boost else MAX_SPEED) * speed_mult
		var turn_rate := lerpf(2.1, 0.9, clampf(speed / BOOST_SPEED, 0.0, 1.0))
		var along := velocity.dot(tangent)
		heading -= steer * turn_rate * delta * (1.0 if along >= -0.5 else -1.0)
		var accel := (22.0 if boost else 13.0) * grip
		if throttle > 0.0 and along < cap:
			velocity += tangent * accel * throttle * delta
		elif throttle < 0.0:
			if along > 0.5:
				# Rolling forward: S brakes first.
				velocity += tangent * accel * 1.2 * throttle * delta
			elif along > -REVERSE_SPEED * speed_mult:
				velocity += tangent * accel * 0.6 * throttle * delta
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
		_air_time += delta
		# The trick button plus a direction spins the rover in the air: W S flips about X, A D spins about Y.
		if trick_held:
			var dx := -throttle * FLIP_RATE * delta
			var dy := -steer * SPIN_RATE * delta
			_flip += dx
			heading += dy
			trick.spin(dx, dy)
		else:
			heading -= steer * 1.2 * delta
	p += velocity * delta
	var w: float = terrain.world_m
	var hit_edge := false
	if p.x < 12.0 or p.x > w - 12.0 or p.z < 12.0 or p.z > w - 12.0:
		hit_edge = true
		p.x = clampf(p.x, 12.0, w - 12.0)
		p.z = clampf(p.z, 12.0, w - 12.0)
		velocity *= 0.3
	p = _collide_rocks(p)
	var new_ground: float = terrain.height_at(p.x, p.z)
	if p.y < new_ground:
		p.y = new_ground
	elif grounded and p.y - new_ground < 0.6 and velocity.y <= 0.5:
		p.y = new_ground  # stick over small dips
	distance += Vector2(velocity.x, velocity.z).length() * delta
	global_position = p
	set_meta("hit_edge", hit_edge)
	_update_visuals(delta, n)

## Landing a jump pays the combo, unless the rover comes down on its back or its nose.
func _touch_down_if_needed() -> void:
	if not grounded or _air_time <= 0.0:
		return
	_air_time = 0.0
	if not trick.in_combo() and absf(wrapf(_flip, -PI, PI)) < 0.2:
		_flip = 0.0
		return
	if absf(wrapf(_flip, -PI, PI)) < 1.0:
		last_paid = trick.land()
	else:
		trick.bail()
		bailed = true
		velocity *= 0.25
		_take_damage(BAIL_DAMAGE)
	_flip = wrapf(_flip, -PI, PI)

func _collide_rocks(p: Vector3) -> Vector3:
	for r: Vector4 in rocks:
		var off := Vector2(p.x - r.x, p.z - r.z)
		var reach := r.w * 0.8 + 1.2
		if off.length_squared() >= reach * reach or p.y > r.y + r.w * 0.9:
			continue
		var n := off.normalized() if off.length_squared() > 0.001 else Vector2(-sin(heading), -cos(heading))
		var v := Vector2(velocity.x, velocity.z)
		var closing := -v.dot(n)
		p.x = r.x + n.x * reach
		p.z = r.z + n.y * reach
		if closing > 0.0:
			v += n * closing * 1.35
			velocity.x = v.x
			velocity.z = v.y
			if closing > SAFE_IMPACT and _hit_cool <= 0.0:
				_hit_cool = 0.5
				_take_damage((closing - SAFE_IMPACT) * damage_scale)
	return p

func _take_damage(amount: float) -> void:
	var before := health
	health = maxf(health - amount, 0.0)
	last_hit = before - health
	_smoke.emitting = health < MAX_HEALTH * 0.4

func repair(amount: float) -> void:
	health = minf(health + amount, MAX_HEALTH)
	_smoke.emitting = health < MAX_HEALTH * 0.4

func _update_visuals(delta: float, _n: Vector3) -> void:
	var fwd := forward_dir()
	var p := global_position
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	# Fit the chassis to the ground under the wheels, not to the single point at its centre.
	var f := _ground_point(p + fwd * 1.7)
	var b := _ground_point(p - fwd * 1.7)
	var r := _ground_point(p + side * 1.45)
	var l := _ground_point(p - side * 1.45)
	var fit_fwd := (f - b).normalized()
	var fit_right := (r - l).normalized()
	var up := fit_fwd.cross(fit_right).normalized()
	if up.y < 0.0:
		up = -up
	if not grounded:
		up = transform.basis.y.lerp(Vector3.UP, delta).normalized()
	var right := up.cross(fwd).normalized()
	var target := Basis(right, up, right.cross(up).normalized()).orthonormalized()
	transform.basis = transform.basis.orthonormalized().slerp(target, clampf(delta * 14.0, 0.0, 1.0))
	var along := velocity.dot(fwd)
	_spin += along * delta / WHEEL_R
	_solve_contacts(delta)
	_dust.emitting = grounded and absf(along) > 4.0

func _ground_point(q: Vector3) -> Vector3:
	return Vector3(q.x, terrain.height_at(q.x, q.z), q.z)

## How far a body-space point must rise along the chassis' up axis to clear the ground.
func _clearance_needed(local: Vector3, xf: Transform3D, up_y: float) -> float:
	var world: Vector3 = xf * local
	return (terrain.height_at(world.x, world.z) - world.y) / up_y

## Each wheel finds the ground on its own. If the travel runs out, or the chassis would touch the
## ground on a crest, the whole body rises so nothing cuts through the surface.
func _solve_contacts(delta: float) -> void:
	var xf := global_transform
	var up_y := maxf(xf.basis.y.normalized().y, 0.35)
	var needs: Array[float] = []
	var lift := 0.0
	for i in WHEELS.size():
		var need := _clearance_needed(WHEELS[i] as Vector3, xf, up_y)
		needs.append(need)
		lift = maxf(lift, need - TRAVEL_UP)
	for c: Vector3 in BODY_CORNERS:
		lift = maxf(lift, _clearance_needed(c, xf, up_y) + 0.05)
	# Rising is instant so the ground can never show through; settling back is gentle.
	_lift = maxf(lift, lerpf(_lift, 0.0, clampf(delta * 3.0, 0.0, 1.0)))
	if grounded:
		_flip = move_toward(_flip, 0.0, 12.0 * delta)
	# A flip turns about the middle of the chassis.
	var pivot := Vector3(0, 1.3, 0)
	_body.rotation.x = _flip
	_body.position = Vector3(0, _lift, 0) + pivot - Basis(Vector3.RIGHT, _flip) * pivot
	var droop := -TRAVEL_DOWN if not grounded else -0.2
	for i in _wheels.size():
		var holder := _wheels[i]
		var want := maxf(needs[i] - _lift, droop)
		# Compression is instant for the same reason; extension is smoothed so wheels do not flicker.
		holder.position.y = want if want > holder.position.y else lerpf(holder.position.y, want, clampf(delta * 16.0, 0.0, 1.0))
		(holder.get_child(0) as Node3D).rotation.x = _spin
