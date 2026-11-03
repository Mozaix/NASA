extends Node
## Prints how the rocket economy plays out. Developer tool for balancing.
func _ready() -> void:
	var R := Rocket2D
	var top := {"nose": "ogive", "fins": "swept", "tank": "t4", "engine": "e4", "boosters": "b3", "utank": "u3", "uengine": "ue3"}
	var cost := 0
	for slot: String in top:
		cost += int(R.part(slot, top[slot]).cost)
	print("everything best: ", R.format_height(float(R.predict(top).apogee)), " twr ", R.predict(top).twr, " reason ", R.predict(top).reason, " margin ", R.predict(top).margin, " cost $", cost)
	for t: Dictionary in R.PARTS.tank:
		for e: Dictionary in R.PARTS.engine:
			var d: Dictionary = top.duplicate()
			d.tank = t.id
			d.engine = e.id
			d.boosters = "b0"
			d.utank = "u3"
			d.uengine = "ue2"
			var p: Dictionary = R.predict(d)
			print("  ", t.id, "+", e.id, "+u3/ue2: ", R.format_height(float(p.apogee)), " ", p.reason, " twr %.2f" % float(p.twr))
	R.new_game()
	for f in R.FLIGHTS_PER_GAME:
		var bought := []
		for i in 12:
			var u: Dictionary = R.best_upgrade()
			if u.is_empty():
				break
			bought.append(u.label)
			R.apply_upgrade(u)
		var p: Dictionary = R.predict(R.design)
		print("flight ", f + 1, " bought ", bought, " -> ", R.format_height(float(p.apogee)), " ", p.reason, " money ", R.money, " design ", R.design.values())
		R.record_flight(float(p.apogee), false)
		print("   earned ", R.last_flight.earn.total, " money ", R.money)
	print("final candidates:")
	var now: float = R.predict(R.design).apogee
	for c: Dictionary in R.upgrade_candidates():
		var a: Dictionary = R.predict(c.design)
		print("   ", c.label, " $", c.cost, " ", R.format_height(float(a.apogee)), " ", a.reason, " gain ", int((float(a.apogee) - now) / 1000.0))
	get_tree().quit()
