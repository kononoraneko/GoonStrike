## GameManager.gd
## Оркестратор игровой сцены. Делегирует спавн → PlayerSpawner,
## HUD → HUDManager и правила матча → GameMode.

class_name GameManager extends Node3D

signal player_spawned(id: int, info: Dictionary)
signal player_despawned(id: int, info: Dictionary)
signal player_died(victim_id: int, attacker_id: int)

const DEFAULT_DEATHMATCH_MODE := preload("res://scripts/game_modes/deathmatch_mode.gd")

@export var game_mode_scene: PackedScene

@onready var spawner: PlayerSpawner = $PlayerSpawner
@onready var hud_manager: HUDManager = $HUDManager

@export var game_mode: GameMode 


func _ready() -> void:
	_setup_game_mode()

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


func _setup_game_mode() -> void:
	if game_mode_scene != null:
		game_mode = game_mode_scene.instantiate() as GameMode
	if game_mode == null:
		game_mode = DEFAULT_DEATHMATCH_MODE.new() as GameMode
	add_child(game_mode)
	game_mode.setup(self)

	if game_mode is DeathmatchMode:
		var dm := game_mode as DeathmatchMode
		dm.score_changed.connect(_on_score_changed)
		dm.match_finished.connect(_on_match_finished)


# ── Спавн / деспавн ───────────────────────────────────────────────────────

func _on_player_connected(id: int, _info: Dictionary) -> void:
	_spawn(id)


func _on_player_disconnected(id: int, info: Dictionary) -> void:
	_despawn_player(id, info)
	game_mode.on_player_despawned(id, info)


func _spawn(id: int) -> void:
	if not Lobby.players.has(id):
		return

	var player := spawner.spawn(id, Lobby.players[id])
	if player == null:
		return

	_wire_player_events(player)
	player_spawned.emit(id, Lobby.players[id])
	game_mode.on_player_spawned(id, player, Lobby.players[id])

	# HUD только для локального игрока
	if id == multiplayer.get_unique_id():
		hud_manager.create_hud(player)


func _despawn_player(id: int, info: Dictionary) -> void:
	spawner.despawn(id)
	hud_manager.remove_hud(id)
	player_despawned.emit(id, info)


func _wire_player_events(player: OnlinePlayer) -> void:
	player.health_component.died.connect(_on_player_died)


func _on_player_died(victim_id: int, attacker_id: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_on_player_died.rpc(victim_id, attacker_id)
	game_mode.on_player_died(victim_id, attacker_id)


@rpc("authority", "reliable", "call_local")
func _rpc_on_player_died(victim_id: int, attacker_id: int) -> void:
	var info: Dictionary = Lobby.players.get(victim_id, {}) as Dictionary
	_despawn_player(victim_id, info)
	player_died.emit(victim_id, attacker_id)


func schedule_respawn(peer_id: int, delay_sec: float) -> void:
	if not multiplayer.is_server():
		return

	var timer := get_tree().create_timer(max(delay_sec, 0.0))
	timer.timeout.connect(func(): _rpc_respawn_player.rpc(peer_id))


@rpc("authority", "reliable", "call_local")
func _rpc_respawn_player(peer_id: int) -> void:
	_spawn(peer_id)


# ── Старт / финиш игры ────────────────────────────────────────────────────

func start_game() -> void:
	game_mode.on_game_started()
	print("All players loaded — game started")


func _on_score_changed(player_id: int, score: int) -> void:
	var player_name: String = _resolve_player_name(player_id)
	print("[DM] %s score = %d" % [player_name, score])


func _on_match_finished(winner_id: int, score: int) -> void:
	var winner_name: String = _resolve_player_name(winner_id)
	print("[DM] Winner: %s (%d frags)" % [winner_name, score])

func _resolve_player_name(peer_id: int) -> String:
	var info: Dictionary = Lobby.players.get(peer_id, {}) as Dictionary
	if info.has("name"):
		return str(info["name"])
	return str(peer_id)

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
