extends Control

const SETTINGS_SCREEN_SCRIPT := preload("res://scripts/ui/settings/settings_screen.gd")

@onready var player_list: ItemList = $VBoxContainer/PlayerList
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var session_label: Label = $VBoxContainer/SessionLabel
@onready var host_session_box: VBoxContainer = $VBoxContainer/HostSessionBox
@onready var map_option: OptionButton = $VBoxContainer/HostSessionBox/MapOption
@onready var mode_option: OptionButton = $VBoxContainer/HostSessionBox/ModeOption
@onready var settings_btn: Button = $VBoxContainer/ButtonRow/SettingsButton
@onready var leave_btn: Button = $VBoxContainer/ButtonRow/LeaveButton
@onready var start_btn: Button = $VBoxContainer/ButtonRow/StartButton

var _map_paths: Array[String] = []


func _ready() -> void:
	Lobby.player_connected.connect(_refresh_list)
	Lobby.player_disconnected.connect(_refresh_list)
	Lobby.server_disconnected.connect(_on_server_disconnected)
	Lobby.lobby_session_changed.connect(_on_lobby_session_changed)
	multiplayer.connection_failed.connect(_on_connection_failed)

	settings_btn.pressed.connect(_on_settings_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	map_option.item_selected.connect(_on_map_selected)
	mode_option.item_selected.connect(_on_mode_selected)

	start_btn.visible = multiplayer.is_server()
	host_session_box.visible = multiplayer.is_server()
	_build_map_options()
	_build_mode_options()
	_refresh_session_ui()
	status_label.text = "Подключено: %d" % Lobby.players.size()
	_refresh_list()


func _on_lobby_session_changed() -> void:
	_refresh_session_ui()
	if multiplayer.is_server():
		_sync_mode_option_with_lobby()


func _build_map_options() -> void:
	map_option.clear()
	_map_paths.clear()
	map_option.set_block_signals(true)
	var maps := MapsRegistry.load_all_maps()
	for m in maps:
		var path: String = m.resource_path
		_map_paths.append(path)
		map_option.add_item(m.display_name if not m.display_name.is_empty() else m.id)
		map_option.set_item_metadata(map_option.item_count - 1, path)
	var cur := Lobby.selected_map.resource_path if Lobby.selected_map else ""
	for i in map_option.item_count:
		if str(map_option.get_item_metadata(i)) == cur:
			map_option.select(i)
			break
	map_option.set_block_signals(false)


func _build_mode_options() -> void:
	mode_option.set_block_signals(true)
	mode_option.clear()
	var allowed := _allowed_mode_ids_for_current_map()
	var ids: PackedStringArray = allowed if not allowed.is_empty() else GameModeCatalog.all_mode_ids()
	for mid in ids:
		mode_option.add_item(GameModeCatalog.display_name(str(mid)))
		mode_option.set_item_metadata(mode_option.item_count - 1, str(mid))
	_sync_mode_option_with_lobby()
	mode_option.set_block_signals(false)


func _allowed_mode_ids_for_current_map() -> PackedStringArray:
	if Lobby.selected_map == null:
		return PackedStringArray()
	var a: PackedStringArray = Lobby.selected_map.supported_mode_ids
	return a


func _sync_mode_option_with_lobby() -> void:
	var cur := Lobby.selected_mode_id
	for i in mode_option.item_count:
		if str(mode_option.get_item_metadata(i)) == cur:
			mode_option.select(i)
			return
	if mode_option.item_count > 0:
		mode_option.select(0)


func _refresh_session_ui() -> void:
	var mn := "—"
	if Lobby.selected_map:
		mn = Lobby.selected_map.display_name if not Lobby.selected_map.display_name.is_empty() else Lobby.selected_map.id
	session_label.text = "Карта: %s  |  Режим: %s" % [mn, GameModeCatalog.display_name(Lobby.selected_mode_id)]


func _on_map_selected(index: int) -> void:
	if not multiplayer.is_server():
		return
	var path: Variant = map_option.get_item_metadata(index)
	if path is String:
		Lobby.host_set_map_by_path(path)
	_build_mode_options()


func _on_mode_selected(index: int) -> void:
	if not multiplayer.is_server():
		return
	var mid: Variant = mode_option.get_item_metadata(index)
	if mid is String:
		Lobby.host_set_mode_id(mid)


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
	SETTINGS_SCREEN_SCRIPT.open(get_tree().root)


func _on_leave_pressed() -> void:
	SceneRouter.go_main_menu()


func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	Lobby.start_match_from_selection()


func _on_server_disconnected() -> void:
	SceneRouter.go_main_menu_with_error("Сервер отключился")


func _on_connection_failed() -> void:
	SceneRouter.go_main_menu_with_error("Не удалось поддерживать подключение")
