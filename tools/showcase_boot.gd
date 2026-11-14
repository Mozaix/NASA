extends Node
## Starts the showcase driver on the scene tree's root, so it survives the game's own scene changes.
func _ready() -> void:
	get_tree().root.add_child.call_deferred(load("res://tools/showcase.gd").new())
