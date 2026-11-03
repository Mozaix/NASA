class_name OrbitCamera
extends Camera3D
## Mouse, keyboard or gamepad orbit camera around a focus point.

var focus := Vector3.ZERO
var distance := 10.0
var min_distance := 2.0
var max_distance := 100.0
var yaw := 0.6
var pitch := 0.3
var auto_spin := 0.0
var _target_distance := 10.0
var _dragging := false

func set_distance_now(d: float) -> void:
	distance = d
	_target_distance = d

func zoom_to(d: float) -> void:
	_target_distance = clampf(d, min_distance, max_distance)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = clampf(_target_distance * 0.9, min_distance, max_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = clampf(_target_distance * 1.1, min_distance, max_distance)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.005 * Settings.mouse_sens
		var inv := -1.0 if Settings.invert_y else 1.0
		pitch = clampf(pitch + mm.relative.y * 0.005 * Settings.mouse_sens * inv, -1.45, 1.45)

func _process(delta: float) -> void:
	yaw += (Input.get_axis("cam_left", "cam_right")) * delta * 1.4 + auto_spin * delta
	pitch = clampf(pitch + Input.get_axis("cam_up", "cam_down") * delta * 1.0, -1.45, 1.45)
	distance = lerpf(distance, _target_distance, clampf(delta * 6.0, 0.0, 1.0))
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	global_position = focus + off
	look_at(focus, Vector3.UP)
