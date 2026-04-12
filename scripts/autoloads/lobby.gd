## Lobby.gd  —  Autoload
## Отвечает только за сетевое соединение и реестр игроков.
## Никакой игровой логики — только connect/disconnect/register.

extends Node

# ── Сигналы ───────────────────────────────────────────────────────────────

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int, player_info: Dictionary)
signal server_disconnected

# ── Константы ─────────────────────────────────────────────────────────────

const PORT            := 7000
const DEFAULT_IP      := "127.0.0.1"
const MAX_CONNECTIONS := 20

# ── Состояние ─────────────────────────────────────────────────────────────

## Реестр всех подключённых игроков: peer_id → info dict
var players: Dictionary = {}

## Информация локального игрока — меняется до подключения
var local_info: Dictionary = {"name": "Player", "op": false}

# ── Инициализация ─────────────────────────────────────────────────────────

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ── Публичное API ─────────────────────────────────────────────────────────

func set_player_name(new_name: String) -> void:
	local_info["name"] = new_name


func join_game(address: String = "") -> Error:
	if address.is_empty():
		address = DEFAULT_IP
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func create_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CONNECTIONS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	local_info["name"] = "host"
	local_info["op"] = true
	_add_player(1, local_info)
	return OK


func set_player_op(peer_id: int, is_op: bool) -> void:
	if not multiplayer.is_server():
		return
	_rpc_set_player_op.rpc(peer_id, is_op)


@rpc("authority", "reliable", "call_local")
func _rpc_set_player_op(peer_id: int, is_op: bool) -> void:
	if players.has(peer_id):
		var info: Dictionary = players[peer_id]
		info["op"] = is_op
		players[peer_id] = info
	if multiplayer.get_unique_id() == peer_id:
		local_info["op"] = is_op

func disconnect_game() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_loaded_count = 0
	_loaded_peers.clear()


# ── Загрузка сцены ────────────────────────────────────────────────────────

## Только сервер вызывает — меняет сцену у всех.
func load_game(scene_path: String) -> void:
	_loaded_count = 0
	_loaded_peers.clear()
	_rpc_load_game.rpc(scene_path)

@rpc("authority", "call_local", "reliable")
func _rpc_load_game(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


## Клиент сообщает серверу что загрузился.
func notify_loaded() -> void:
	_rpc_player_loaded.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_player_loaded() -> void:
	if not multiplayer.is_server():
		return
	# GameManager подпишется на этот сигнал
	_all_loaded_check()

var _loaded_count := 0
var _loaded_peers: Dictionary = {}
func _all_loaded_check() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0 or not players.has(sender_id):
		return
	if _loaded_peers.has(sender_id):
		return
	_loaded_peers[sender_id] = true
	_loaded_count = _loaded_peers.size()
	if _loaded_count >= players.size():
		_loaded_count = 0
		_loaded_peers.clear()
		all_players_loaded.emit()

signal all_players_loaded


# ── Внутренние обработчики ────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	# Отправляем новому пиру нашу информацию
	_rpc_register_player.rpc_id(id, local_info)


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	_loaded_peers.erase(id)
	_loaded_count = _loaded_peers.size()
	var info : Dictionary = players[id].duplicate()
	players.erase(id)
	player_disconnected.emit(id, info)


func _on_connected_ok() -> void:
	_add_player(multiplayer.get_unique_id(), local_info)


func _on_connected_fail() -> void:
	disconnect_game()


func _on_server_disconnected() -> void:
	disconnect_game()
	server_disconnected.emit()


@rpc("any_peer", "reliable")
func _rpc_register_player(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	_add_player(id, info)


func _add_player(id: int, info: Dictionary) -> void:
	var normalized: Dictionary = info.duplicate(true)
	if not normalized.has("op"):
		normalized["op"] = false
	players[id] = normalized
	player_connected.emit(id, normalized)
