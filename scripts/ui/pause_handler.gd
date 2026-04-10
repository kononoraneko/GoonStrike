extends Node

const PAUSE_MENU_SCRIPT := preload("res://scripts/ui/pause_menu.gd")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		PAUSE_MENU_SCRIPT.open(get_tree().root)
		get_viewport().set_input_as_handled()
