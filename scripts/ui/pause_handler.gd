extends Node

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		PauseMenu.open(get_tree().root)
		get_viewport().set_input_as_handled()
