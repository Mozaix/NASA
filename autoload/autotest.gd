extends Node
## Plays the game by itself for testing, rendering screenshots and measuring frame rate.
##   godot --path . -- --nfe-auto --nfe-target=mars --nfe-region=gale --nfe-out=/some/dir
## It does nothing unless --nfe-auto is passed, so players never see it.

var active := false
var target_id := ""
var region_id := ""
var out_dir := ""
var results := {}
var _scene_name := ""
var _t := 0.0
var _stage := 0
var _fps: Dictionary = {}
var _quality := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a == "--nfe-auto":
			active = true
		elif a.begins_with("--nfe-target="):
			target_id = a.split("=")[1]
		elif a.begins_with("--nfe-region="):
			region_id = a.split("=")[1]
		elif a.begins_with("--nfe-out="):
			out_dir = a.split("=")[1]
		elif a.begins_with("--nfe-quality="):
			_quality = int(a.split("=")[1])
	if active and _quality >= 0:
		Settings.quality = _quality
		Settings.apply()

func report(key: String, value: Variant) -> void:
	results[key] = value
	print("[autotest] ", key, " = ", value)

func _shot(label: String) -> void:
	if out_dir == "" or DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_jpg("%s/%s_%s.jpg" % [out_dir, target_id, label], 0.85)

func _record(scene: String, delta: float) -> void:
	if not _fps.has(scene):
		_fps[scene] = {"frames": 0, "time": 0.0, "worst": 0.0}
	var f: Dictionary = _fps[scene]
	f.frames = int(f.frames) + 1
	f.time = float(f.time) + delta
	f.worst = maxf(float(f.worst), delta)

func _finish() -> void:
	var fps_out := {}
	for k: String in _fps:
		var f: Dictionary = _fps[k]
		fps_out[k] = {"avg_fps": snappedf(float(f.frames) / maxf(float(f.time), 0.001), 0.1), "worst_ms": snappedf(float(f.worst) * 1000.0, 0.1)}
	results["fps"] = fps_out
	results["vram_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 1.0)
	results["draw_calls_last"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	print("[autotest] RESULT ", JSON.stringify(results))
	if out_dir != "":
		var f := FileAccess.open("%s/%s_result.json" % [out_dir, target_id], FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(results, "  "))
			f.close()
	get_tree().quit(0)

func _process(delta: float) -> void:
	if not active:
		return
	var scene := get_tree().current_scene
	if scene == null or Flow.busy:
		return
	var sname: String = scene.name
	if sname != _scene_name:
		_scene_name = sname
		_t = 0.0
		_stage = 0
		print("[autotest] scene ", sname)
	_t += delta
	if _t > 1.0:  # skip the frames spent loading
		_record(sname, delta)
	match sname:
		"MainMenu", "Launch", "Transfer", "Orbit":
			if _stage == 0 and _t > 3.0:
				_stage = 1
				_shot(sname)
				scene.auto_advance()
		"Planner":
			if _stage == 0 and _t > 2.0:
				_stage = 1
				_shot("planner")
				scene.auto_advance()
		"Landing":
			if _stage == 0 and _t > 0.6:
				_stage = 1
				scene.auto_advance()
			elif _stage == 1 and _t > 10.0:
				_stage = 2
				_shot("landing_mid")
			elif _stage == 2 and scene.state != "fly":
				_stage = 3
				_t = 0.0
				report("landing", {"state": scene.state, "stats": Game.mission.get("landing_stats", {})})
				_shot("landing_end")
			elif _stage == 3 and _t > 1.2:
				_stage = 4
				scene.auto_surface()
			elif _stage == 2 and _t > 120.0:
				report("landing_timeout", true)
				_finish()
		"Surface":
			if _stage == 0 and _t > 4.0:
				_stage = 1
				_shot("surface_start")
				_drive_test(scene)
			elif _stage == 1 and _t > 10.0:
				_stage = 2
				_shot("surface_drive")
				Input.action_release("move_forward")
				scene.auto_visit_all()
			elif _stage == 2 and _t > 13.0:
				_stage = 3
				_shot("surface_poi")
				report("science", Game.mission.science)
				report("samples", Game.mission.samples.size())
				scene.auto_advance()
		"Debrief":
			if _stage == 0 and _t > 2.0:
				_stage = 1
				_shot("debrief")
				scene.auto_advance()
				_finish()

func _drive_test(scene: Node) -> void:
	# Press the real input action, so rover physics runs exactly as it does for a player.
	Input.action_press("move_forward", 1.0)
	report("rover_start", scene.vehicle.global_position)
