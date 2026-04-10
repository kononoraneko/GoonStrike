extends Control

const GAME_SCENE := "res://scenes/game/game_world.tscn"

@onready var player_list: ItemList = $VBoxContainer/PlayerList
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var settings_btn: Button = $VBoxContainer/ButtonRow/SettingsButton
@onready var leave_btn: Button = $VBoxContainer/ButtonRow/LeaveButton
@onready var start_btn: Button = $VBoxContainer/ButtonRow/StartButton

func _ready() -> void:
	Lobby.player_connected.connect(_refresh_list)
	Lobby.player_disconnected.connect(_refresh_list)
	Lobby.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	settings_btn.pressed.connect(_on_settings_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)
	start_btn.pressed.connect(_on_start_pressed)

	start_btn.visible = multiplayer.is_server()
	status_label.text = "Подключено: %d" % Lobby.players.size()
	_refresh_list()


func _refresh_list(_peer_id: int = -1, _player_info: Dictionary = {}) -> void:
	player_list.clear()
	for id in Lobby.players.keys():
		var info: Dictionary = Lobby.players[id]
		var prefix := "[HOST] " if int(id) == 1 else ""
		var op_tag := "[OP] " if bool(info.get("op", false)) else ""
		var name := str(info.get("name", "?"))
		player_list.add_item("%s%s%s" % [prefix, op_tag, name])
	status_label.text = "Подключено: %d" % Lobby.players.size()


func _on_settings_pressed() -> void:
	SettingsScreen.open(get_tree().root)


func _on_leave_pressed() -> void:
	SceneRouter.go_main_menu()


func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	Lobby.load_game(GAME_SCENE)


func _on_server_disconnected() -> void:
	SceneRouter.go_main_menu_with_error("Сервер отключился")


func _on_connection_failed() -> void:
	SceneRouter.go_main_menu_with_error("Не удалось поддерживать подключение")
