extends Node
## Persistent settings: graphics quality, audio volumes, controls, gamepad and rebinding.

const PATH := "user://settings.cfg"
const QUALITY_NAMES: Array[String] = ["Low (integrated GPU, fastest)", "Medium", "High"]

var quality := 1
var fullscreen := false
var master_vol := 0.9
var music_vol := 0.6
var sfx_vol := 0.9
var mouse_sens := 1.0
var invert_y := false
var show_fps := false
var custom_keys := {}

## action -> [label, default keycode, joypad button (-1 none), joy axis (-1 none), axis direction]
const ACTIONS := {
	"move_forward": ["Forward / throttle up", KEY_W, -1, JOY_AXIS_LEFT_Y, -1.0],
	"move_back": ["Back / throttle down", KEY_S, -1, JOY_AXIS_LEFT_Y, 1.0],
	"move_left": ["Left", KEY_A, -1, JOY_AXIS_LEFT_X, -1.0],
	"move_right": ["Right", KEY_D, -1, JOY_AXIS_LEFT_X, 1.0],
	"thrust": ["Main action (thrust, jump, burn)", KEY_SPACE, JOY_BUTTON_A, -1, 0.0],
	"interact": ["Collect sample / scan", KEY_E, JOY_BUTTON_X, -1, 0.0],
	"boost": ["Boost", KEY_SHIFT, JOY_BUTTON_RIGHT_SHOULDER, -1, 0.0],
	"lights": ["Headlights", KEY_L, JOY_BUTTON_Y, -1, 0.0],
	"map": ["Toggle map / scale", KEY_M, JOY_BUTTON_BACK, -1, 0.0],
	"assist": ["Landing autopilot", KEY_P, JOY_BUTTON_LEFT_SHOULDER, -1, 0.0],
	"pause": ["Pause menu", KEY_ESCAPE, JOY_BUTTON_START, -1, 0.0],
	"cam_left": ["Camera left", KEY_LEFT, -1, JOY_AXIS_RIGHT_X, -1.0],
	"cam_right": ["Camera right", KEY_RIGHT, -1, JOY_AXIS_RIGHT_X, 1.0],
	"cam_up": ["Camera up", KEY_UP, -1, JOY_AXIS_RIGHT_Y, -1.0],
	"cam_down": ["Camera down", KEY_DOWN, -1, JOY_AXIS_RIGHT_Y, 1.0],
}

func _ready() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	load_settings()
	rebuild_input()
	apply()

func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	quality = c.get_value("video", "quality", quality)
	fullscreen = c.get_value("video", "fullscreen", fullscreen)
	show_fps = c.get_value("video", "show_fps", show_fps)
	master_vol = c.get_value("audio", "master", master_vol)
	music_vol = c.get_value("audio", "music", music_vol)
	sfx_vol = c.get_value("audio", "sfx", sfx_vol)
	mouse_sens = c.get_value("controls", "mouse_sens", mouse_sens)
	invert_y = c.get_value("controls", "invert_y", invert_y)
	custom_keys = c.get_value("controls", "keys", {})

func save() -> void:
	var c := ConfigFile.new()
	c.set_value("video", "quality", quality)
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("video", "show_fps", show_fps)
	c.set_value("audio", "master", master_vol)
	c.set_value("audio", "music", music_vol)
	c.set_value("audio", "sfx", sfx_vol)
	c.set_value("controls", "mouse_sens", mouse_sens)
	c.set_value("controls", "invert_y", invert_y)
	c.set_value("controls", "keys", custom_keys)
	c.save(PATH)

func rebuild_input() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.25)
		var def: Array = ACTIONS[action]
		var key := InputEventKey.new()
		key.physical_keycode = int(custom_keys.get(action, def[1])) as Key
		InputMap.action_add_event(action, key)
		if int(def[2]) >= 0:
			var b := InputEventJoypadButton.new()
			b.button_index = int(def[2]) as JoyButton
			InputMap.action_add_event(action, b)
		if int(def[3]) >= 0:
			var m := InputEventJoypadMotion.new()
			m.axis = int(def[3]) as JoyAxis
			m.axis_value = float(def[4])
			InputMap.action_add_event(action, m)
	# Arrow keys also steer, because many players reach for them first.
	for pair: Array in [["move_forward", KEY_UP], ["move_back", KEY_DOWN], ["move_left", KEY_LEFT], ["move_right", KEY_RIGHT]]:
		var k := InputEventKey.new()
		k.physical_keycode = int(pair[1]) as Key
		InputMap.action_add_event(pair[0], k)

func rebind(action: String, keycode: int) -> void:
	custom_keys[action] = keycode
	rebuild_input()
	save()

func key_name(action: String) -> String:
	var code := int(custom_keys.get(action, ACTIONS[action][1]))
	return OS.get_keycode_string(code as Key)

func apply() -> void:
	_set_bus("Master", master_vol)
	_set_bus("Music", music_vol)
	_set_bus("SFX", sfx_vol)
	if not DisplayServer.get_name() == "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
		vp.scaling_3d_scale = [0.75, 1.0, 1.0][quality]

func _set_bus(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(i, linear <= 0.001)

# ---- Values that scenes read so quality presets stay in one place ----
func shadow_distance() -> float:
	return [250.0, 500.0, 900.0][quality]

func use_shadows() -> bool:
	return true

func lod_scale() -> float:
	return [0.6, 1.0, 1.5][quality]

func rock_count() -> int:
	return [500, 1200, 2500][quality]

func glow() -> bool:
	return quality > 0

func sphere_segments() -> int:
	return [64, 96, 128][quality]
