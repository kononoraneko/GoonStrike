extends CanvasLayer

const SETTINGS_SCREEN_SCRIPT := preload("res://scripts/ui/settings_screen.gd")

@onready var resume_btn: Button = $ColorRect/CenterContainer/VBoxContainer/ResumeButton
@onready var settings_btn: Button = $ColorRect/CenterContainer/VBoxContainer/SettingsButton
@onready var lobby_btn: Button = $ColorRect/CenterContainer/VBoxContainer/LobbyButton
@onready var menu_btn: Button = $ColorRect/CenterContainer/VBoxContainer/MenuButton

static func open(parent: Node) -> CanvasLayer:
	for child in parent.get_children():
		if child.scene_file_path == "res://scenes/ui/pause_menu.tscn":
			return child
	var inst := preload("res://scenes/ui/pause_menu.tscn").instantiate() as CanvasLayer
	parent.add_child(inst)
	return inst


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	resume_btn.pressed.connect(_on_resume)
	settings_btn.pressed.connect(_on_settings_pressed)
	lobby_btn.pressed.connect(_on_go_lobby)
	menu_btn.pressed.connect(_on_go_menu)

	lobby_btn.visible = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func _on_resume() -> void:
	get_tree().paused = false
	queue_free()


func _on_settings_pressed() -> void:
	SETTINGS_SCREEN_SCRIPT.open(get_tree().root)


func _on_go_lobby() -> void:
	get_tree().paused = false
	Lobby.disconnect_game()
	SceneRouter.go_main_menu()


func _on_go_menu() -> void:
	get_tree().paused = false
	SceneRouter.go_main_menu()
