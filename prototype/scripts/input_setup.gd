extends Node
## Rejestruje akcje wejściowe w kodzie, żeby project.godot był prosty. Lista akcji i ich klawisze są w `actions.gd`.

const Actions := preload("res://scripts/actions.gd")

func _enter_tree() -> void:
	Actions.register()
