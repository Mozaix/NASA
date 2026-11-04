class_name TrickScore
extends RefCounted
## Skating-game scoring for spins. Half-turns build a combo; landing it pays combo points times the multiplier.
## Net rotation is what counts, so wiggling back and forth earns nothing.

const HALF_TURN_POINTS := 100
const MAX_MULT := 10

var combo_points := 0
var mult := 1
var half_turns := 0
var _x := 0.0
var _y := 0.0
var _last_axis := ""

func in_combo() -> bool:
	return half_turns > 0

func spin(dx: float, dy: float) -> void:
	_x = _count(_x + dx, "x")
	_y = _count(_y + dy, "y")

func _count(amount: float, axis: String) -> float:
	while absf(amount) >= PI:
		amount -= signf(amount) * PI
		half_turns += 1
		combo_points += HALF_TURN_POINTS
		# Switching axis mid-combo is worth more than repeating one.
		var step := 2 if _last_axis != "" and _last_axis != axis else 1
		mult = mini(mult + step, MAX_MULT) if half_turns > 1 else 1
		_last_axis = axis
	return amount

func payout() -> int:
	return combo_points * mult

## Banks the combo into the mission total and returns what it paid.
func land() -> int:
	var paid := payout()
	if paid > 0:
		Game.mission.trick_points = int(Game.mission.get("trick_points", 0)) + paid
	_reset()
	return paid

func bail() -> void:
	_reset()

func _reset() -> void:
	combo_points = 0
	mult = 1
	half_turns = 0
	_x = 0.0
	_y = 0.0
	_last_axis = ""
