extends Node

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const LOBBY_SCENE := "res://scenes/ui/menus/lobby.tscn"

var _current_scene_path: String = ""
var _previous_scene_path: String = ""
var _pending_error: String = ""

func _ready() -> void:
	_current_scene_path = _resolve_current_scene_path()


func go_main_menu() -> void:
	Lobby.disconnect_game()
	_cleanup_overlays()
	_go_to(MAIN_MENU_SCENE)


func go_main_menu_with_error(msg: String) -> void:
	_pending_error = msg
	go_main_menu()


func go_lobby() -> void:
	_go_to(LOBBY_SCENE)


func go_game(scene_path: String) -> void:
	_previous_scene_path = LOBBY_SCENE
	_go_to(scene_path)


func go_back() -> void:
	if _previous_scene_path.is_empty():
		return
	_go_to(_previous_scene_path)


func consume_pending_error() -> String:
	var msg := _pending_error
	_pending_error = ""
	return msg


func _go_to(scene_path: String) -> void:
	if _current_scene_path != scene_path and not _current_scene_path.is_empty():
		_previous_scene_path = _current_scene_path
	_current_scene_path = scene_path
	get_tree().change_scene_to_file(scene_path)


func _resolve_current_scene_path() -> String:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return ""
	return current_scene.scene_file_path

func _cleanup_overlays() -> void:
	var overlay_paths := {
		"res://scenes/ui/pause_menu.tscn": true,
		"res://scenes/settings/settings_screen.tscn": true,
	}
	for child in get_tree().root.get_children():
		if overlay_paths.has(child.scene_file_path):
			child.queue_free()
