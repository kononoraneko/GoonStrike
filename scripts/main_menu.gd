extends Control

@export var level:String = "res://scenes/levels/test_battle_area.tscn"
var ip = "127.0.0.1"

func _on_host_pressed():
	Lobby.create_game()
	get_tree().change_scene_to_file(level)

func _on_join_pressed():
	Lobby.join_game(ip)
	get_tree().change_scene_to_file(level)


func _on_line_edit_text_changed(new_text: String) -> void:
	Lobby.set_player_name(new_text)


func _on_ip_edit_text_changed(new_text: String) -> void:
	ip = new_text
