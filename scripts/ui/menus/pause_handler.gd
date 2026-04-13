extends Node

const PAUSE_MENU_PATH := "res://scenes/ui/pause_menu.tscn"
const PAUSE_MENU_SCRIPT := preload("res://scripts/ui/menus/pause_menu.gd")

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	var root := get_tree().root
	for child in root.get_children():
		if child.scene_file_path == PAUSE_MENU_PATH:
			if child.has_method("request_close"):
				child.request_close()
			else:
				child.queue_free()
			get_viewport().set_input_as_handled()
			return

	PAUSE_MENU_SCRIPT.open(root)
	get_viewport().set_input_as_handled()
