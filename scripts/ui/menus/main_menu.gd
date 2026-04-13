extends Control

const SETTINGS_SCREEN_SCRIPT := preload("res://scripts/ui/settings/settings_screen.gd")

@onready var name_edit: LineEdit = $VBoxContainer/NameEdit
@onready var ip_edit: LineEdit = $VBoxContainer/IpRow/IpEdit
@onready var create_btn: Button = $VBoxContainer/ButtonRow/CreateButton
@onready var join_btn: Button = $VBoxContainer/ButtonRow/JoinButton
@onready var settings_btn: Button = $VBoxContainer/ButtonRow/SettingsButton
@onready var quit_btn: Button = $VBoxContainer/ButtonRow/QuitButton
@onready var connecting_overlay: Control = $ConnectingOverlay
@onready var error_label: Label = $VBoxContainer/ErrorLabel

var _is_waiting_connection: bool = false

func _ready() -> void:
	name_edit.text_changed.connect(_on_name_text_changed)
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	Lobby.server_disconnected.connect(_on_server_disconnected)

	show_connecting_overlay(false)
	error_label.hide()

	name_edit.text = str(Lobby.local_info.get("name", "Player"))

	var pending_error := SceneRouter.consume_pending_error()
	if not pending_error.is_empty():
		show_error(pending_error)


func _on_name_text_changed(new_text: String) -> void:
	Lobby.set_player_name(new_text)


func _on_create_pressed() -> void:
	if _is_waiting_connection:
		return
	var err : Error = Lobby.create_game()
	if err != OK:
		show_error("Не удалось создать сервер: %d" % err)
		return
	SceneRouter.go_lobby()


func _on_join_pressed() -> void:
	if _is_waiting_connection:
		return
	var ip := ip_edit.text.strip_edges()
	var err : Error = Lobby.join_game(ip)
	if err != OK:
		show_error("Не удалось начать подключение: %d" % err)
		return

	_is_waiting_connection = true
	show_connecting_overlay(true)

	multiplayer.connected_to_server.connect(_on_connected_ok, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)


func _on_connected_ok() -> void:
	_is_waiting_connection = false
	show_connecting_overlay(false)
	SceneRouter.go_lobby()


func _on_connection_failed() -> void:
	_is_waiting_connection = false
	show_connecting_overlay(false)
	Lobby.disconnect_game()
	show_error("Не удалось подключиться")


func _on_settings_pressed() -> void:
	SETTINGS_SCREEN_SCRIPT.open(get_tree().root)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_server_disconnected() -> void:
	if _is_waiting_connection:
		_on_connection_failed()


func show_connecting_overlay(visible: bool) -> void:
	connecting_overlay.visible = visible
	create_btn.disabled = visible
	join_btn.disabled = visible


func show_error(msg: String) -> void:
	error_label.text = msg
	error_label.show()
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(error_label):
			error_label.hide()
	)


func _on_character_option_button_item_selected(index: int) -> void:
	Settings.selected_char = index
