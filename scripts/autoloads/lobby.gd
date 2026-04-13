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

const DEFAULT_MAP_RESOURCE := "res://resources/maps/default.tres"

# ── Состояние ─────────────────────────────────────────────────────────────

## Реестр всех подключённых игроков: peer_id → info dict
var players: Dictionary = {}

## Карта текущей сессии (хост может сменить до старта).
var selected_map: MapData

## Режим матча (см. GameModeCatalog): dm, team_elim, …
var selected_mode_id: String = GameModeCatalog.ID_DM

signal lobby_session_changed

## Информация локального игрока — меняется до подключения
var local_info: Dictionary = {"name": "Player", "op": false}

## Сервер: путь к текущей игровой сцене (для позднего входа после старта матча).
var active_game_scene_path: String = ""

# ── Инициализация ─────────────────────────────────────────────────────────

func _ready() -> void:
	_load_default_map()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _load_default_map() -> void:
	selected_map = load(DEFAULT_MAP_RESOURCE) as MapData
	if selected_map == null or selected_map.game_world_scene == null:
		push_error("Lobby: failed to load default map from " + DEFAULT_MAP_RESOURCE)
	_normalize_mode_for_map()


func _normalize_mode_for_map() -> void:
	if selected_map == null:
		return
	var allowed: PackedStringArray = selected_map.supported_mode_ids
	if allowed.is_empty():
		return
	if allowed.find(selected_mode_id) >= 0:
		return
	selected_mode_id = str(allowed[0])


## Путь к сцене мира для load_game (PackedScene.resource_path).
func get_selected_map_path() -> String:
	if selected_map == null or selected_map.game_world_scene == null:
		return ""
	return selected_map.game_world_scene.resource_path


## Старт матча с текущей selected_map (только сервер).
func start_match_from_selection() -> void:
	if not multiplayer.is_server():
		return
	var path := get_selected_map_path()
	if path.is_empty():
		push_error("Lobby: no valid map selected")
		return
	load_game(path)


func is_mode_allowed_on_selected_map(mode_id: String) -> bool:
	if selected_map == null:
		return true
	var allowed: PackedStringArray = selected_map.supported_mode_ids
	if allowed.is_empty():
		return true
	return allowed.find(mode_id) >= 0


## Только хост: сменить карту по пути к .tres MapData.
func host_set_map_by_path(map_path: String) -> void:
	if not multiplayer.is_server():
		return
	var m := load(map_path) as MapData
	if m == null or m.game_world_scene == null:
		push_error("Lobby: invalid map at " + map_path)
		return
	_apply_lobby_session(m.resource_path, selected_mode_id)
	_rpc_lobby_session.rpc(m.resource_path, selected_mode_id)


## Только хост: сменить режим (id из GameModeCatalog).
func host_set_mode_id(mode_id: String) -> void:
	if not multiplayer.is_server():
		return
	if not is_mode_allowed_on_selected_map(mode_id):
		push_warning("Lobby: mode %s not allowed on this map" % mode_id)
		return
	_apply_lobby_session(selected_map.resource_path if selected_map else "", mode_id)
	_rpc_lobby_session.rpc(selected_map.resource_path if selected_map else "", selected_mode_id)


func _apply_lobby_session(map_path: String, mode_id: String) -> void:
	if not map_path.is_empty():
		var m := load(map_path) as MapData
		if m != null and m.game_world_scene != null:
			selected_map = m
	if not mode_id.is_empty():
		selected_mode_id = mode_id
	_normalize_mode_for_map()
	lobby_session_changed.emit()


# ── Публичное API ─────────────────────────────────────────────────────────

func set_player_name(new_name: String) -> void:
	local_info["name"] = new_name


## Имя игрока для UI / логов (peer_id из реестра).
func get_player_display_name(peer_id: int) -> String:
	var info: Dictionary = players.get(peer_id, {}) as Dictionary
	return str(info.get("name", str(peer_id)))


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
	active_game_scene_path = ""
	selected_mode_id = GameModeCatalog.ID_DM
	local_info["op"] = false
	_load_default_map()


# ── Загрузка сцены ────────────────────────────────────────────────────────

## Только сервер вызывает — меняет сцену у всех.
func load_game(scene_path: String) -> void:
	if multiplayer.is_server():
		active_game_scene_path = scene_path
	_loaded_count = 0
	_loaded_peers.clear()
	_rpc_load_game.rpc(scene_path)

@rpc("authority", "call_local", "reliable")
func _rpc_load_game(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


## Клиент сообщает серверу что загрузился.
func notify_loaded() -> void:
	if multiplayer.is_server():
		_mark_peer_loaded(multiplayer.get_unique_id())
	else:
		_rpc_player_loaded.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_player_loaded() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	_mark_peer_loaded(sender_id)

var _loaded_count := 0
var _loaded_peers: Dictionary = {}
signal all_players_loaded

func _mark_peer_loaded(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	if _loaded_peers.has(peer_id):
		return
	_loaded_peers[peer_id] = true
	_loaded_count = _loaded_peers.size()
	if _loaded_count >= players.size():
		_loaded_count = 0
		_loaded_peers.clear()
		all_players_loaded.emit()


# ── Внутренние обработчики ────────────────────────────────────────────────

func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	_loaded_peers.erase(id)
	_loaded_count = _loaded_peers.size()
	var info : Dictionary = players[id].duplicate()
	players.erase(id)
	player_disconnected.emit(id, info)


func _on_connected_ok() -> void:
	players.clear()
	_rpc_client_register.rpc_id(1, local_info.duplicate(true))


func _on_connected_fail() -> void:
	disconnect_game()


func _on_server_disconnected() -> void:
	disconnect_game()
	server_disconnected.emit()


## Клиент сообщает серверу свой профиль; сервер рассылает реестр и при необходимости подгружает игру.
@rpc("any_peer", "reliable")
func _rpc_client_register(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	var sanitized := info.duplicate(true)
	sanitized["op"] = false
	_add_player(peer_id, sanitized)
	_rpc_sync_players_state.rpc_id(peer_id, _clone_players_for_net())
	_broadcast_new_player_to_remote_peers(peer_id, sanitized.duplicate(true))
	var map_p := selected_map.resource_path if selected_map else ""
	_rpc_lobby_session.rpc_id(peer_id, map_p, selected_mode_id)
	if not active_game_scene_path.is_empty():
		_rpc_load_game.rpc_id(peer_id, active_game_scene_path)


@rpc("authority", "reliable")
func _rpc_lobby_session(map_path: String, mode_id: String) -> void:
	_apply_lobby_session(map_path, mode_id)


func _clone_players_for_net() -> Dictionary:
	var d: Dictionary = {}
	for k in players.keys():
		var v: Variant = players[k]
		if v is Dictionary:
			d[k] = (v as Dictionary).duplicate(true)
		else:
			d[k] = v
	return d


@rpc("authority", "reliable")
func _rpc_sync_players_state(full: Dictionary) -> void:
	var had: Dictionary = {}
	for k in players.keys():
		had[k] = true
	players.clear()
	for k in full.keys():
		var pid: int = int(k)
		var entry: Variant = full[k]
		if entry is Dictionary:
			players[pid] = (entry as Dictionary).duplicate(true)
		else:
			players[pid] = entry
	for pid in players.keys():
		if not had.has(pid):
			player_connected.emit(pid, players[pid])


func _broadcast_new_player_to_remote_peers(peer_id: int, info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	for p in multiplayer.get_peers():
		if p != peer_id:
			_rpc_add_peer.rpc_id(p, peer_id, info.duplicate(true))


@rpc("authority", "reliable")
func _rpc_add_peer(new_id: int, info: Dictionary) -> void:
	_add_player(new_id, info)


func _add_player(id: int, info: Dictionary) -> void:
	var normalized: Dictionary = info.duplicate(true)
	if not normalized.has("op"):
		normalized["op"] = false
	if players.has(id):
		players[id] = normalized
		return
	players[id] = normalized
	player_connected.emit(id, normalized)
