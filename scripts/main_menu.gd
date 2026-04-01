extends Control

@export var level:String = "res://scenes/test_world.tscn"

func _on_host_pressed():
	Lobby.create_game()
	get_tree().change_scene_to_file(level)

func _on_join_pressed():
	Lobby.join_game()
	get_tree().change_scene_to_file(level)


func _on_line_edit_text_changed(new_text: String) -> void:
	Lobby.set_playername(new_text)
