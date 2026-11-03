extends Node
## Prints a flight log of the landing autopilot, for diagnosing a specific site.
func _ready() -> void:
	for c: Array in [["venus", "venus_site"], ["enceladus", "enceladus_site"]]:
		Game.new_mission()
		Game.mission.target_id = c[0]
		Game.mission.region_id = c[1]
		Game.auto_design()
		var inst: Node = (load("res://scenes/landing.tscn") as PackedScene).instantiate()
		add_child(inst)
		await get_tree().process_frame
		inst.auto_pilot = true
		print("%s g=%.3f thrust=%.2f drag=%.3f burn=%.4f/s" % [c[0], inst.gravity, inst.thrust_acc, inst.drag, inst.fuel_burn])
		var steps := 0
		while inst.state == "fly" and steps < 60 * 300:
			inst._physics_process(1.0 / 60.0)
			steps += 1
			if steps % 300 == 0:
				var p: Vector3 = inst.craft.global_position
				print("  t=%3ds alt=%5.0f vy=%6.1f hv=%5.1f dist=%5.0f fuel=%3.0f%%" % [steps / 60, p.y - inst.terrain.height_at(p.x, p.z), inst.vel.y, Vector2(inst.vel.x, inst.vel.z).length(), Vector2(p.x - inst.pad.x, p.z - inst.pad.z).length(), inst.fuel * 100.0])
		print("  end ", inst.state, " at ", steps / 60, "s")
		inst.queue_free()
		await get_tree().process_frame
	get_tree().quit()
