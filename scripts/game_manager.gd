## GameManager.gd
## Оркестратор игровой сцены. Делегирует спавн → PlayerSpawner,
## HUD → HUDManager. Сам не знает про OnlinePlayer внутри.
##
## Структура сцены:
## Game  (Node3D, GameManager.gd)
## ├── World  (Node3D — карта, навмеш и т.д.)
## ├── PlayerSpawner  (Node3D, PlayerSpawner.gd)
## └── HUDManager    (CanvasLayer, HUDManager.gd)

class_name GameManager extends Node3D

signal player_spawned(id: int, info: Dictionary)
signal player_despawned(id: int, info: Dictionary)

@onready var spawner:     PlayerSpawner = $PlayerSpawner
@onready var hud_manager: HUDManager    = $HUDManager


func _ready() -> void:
	# Подписка на Lobby
	Lobby.player_connected.connect(_on_player_connected)
	Lobby.player_disconnected.connect(_on_player_disconnected)
	Lobby.server_disconnected.connect(_on_server_disconnected)
	Lobby.all_players_loaded.connect(start_game)

	# Спавним уже подключённых (пришли раньше смены сцены)
	for id in Lobby.players:
		_spawn(id)

	# Сообщаем серверу что мы загрузились
	Lobby.notify_loaded()


# ── Спавн / деспавн ───────────────────────────────────────────────────────

func _on_player_connected(id: int, _info: Dictionary) -> void:
	_spawn(id)


func _on_player_disconnected(id: int, info: Dictionary) -> void:
	spawner.despawn(id)
	hud_manager.remove_hud(id)
	player_despawned.emit(id, info)


func _spawn(id: int) -> void:
	var player := spawner.spawn(id, Lobby.players[id])
	if player == null:
		return
	player_spawned.emit(id, Lobby.players[id])

	# HUD только для локального игрока
	if id == multiplayer.get_unique_id():
		hud_manager.create_hud(player)


# ── Старт / финиш игры ────────────────────────────────────────────────────

func start_game() -> void:
	# Здесь: снять экран загрузки, начать таймер раунда и т.д.
	print("All players loaded — game started")


func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
