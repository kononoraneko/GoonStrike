## ChatNetwork.gd  —  Autoload
## Транслирует сообщения чата между всеми клиентами.
## GameHUD подписывается на chat_received/system_received для отображения.

extends Node

signal chat_received(sender_name: String, text: String)
signal system_received(text: String)
signal console_feedback(text: String)

const MAX_LENGTH := 200

var shared_speed: float = -1.0
var shared_jump: float = -1.0

## 0 = обычный, 1 = бесконечный магазин, 2 = бесконечный резерв
var sv_ammo_mode: int = 0


## Отправить сообщение от локального игрока.
func send(text: String) -> void:
	text = text.strip_edges().left(MAX_LENGTH)
	if text.is_empty():
		return
	var sender_name: String = str(Lobby.local_info.get("name", "?"))
	if multiplayer.is_server():
		_rpc_receive(text, sender_name)
	else:
		_rpc_receive.rpc_id(1, text, sender_name)


## Отправить системное сообщение от сервера всем клиентам.
func send_system(text: String) -> void:
	if not multiplayer.is_server():
		return
	text = text.strip_edges().left(MAX_LENGTH)
	if text.is_empty():
		return
	_rpc_broadcast_system.rpc(text)


## Отправить серверную консольную команду (для op).
func send_admin_command(text: String) -> void:
	text = text.strip_edges().left(MAX_LENGTH)
	if text.is_empty():
		return
	if multiplayer.is_server():
		_rpc_admin_command(text)
	else:
		_rpc_admin_command.rpc_id(1, text)


func sync_shared_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1:
		_rpc_sync_shared_movement(shared_speed, shared_jump)
		_rpc_sync_ammo_mode(sv_ammo_mode)
	else:
		_rpc_sync_shared_movement.rpc_id(peer_id, shared_speed, shared_jump)
		_rpc_sync_ammo_mode.rpc_id(peer_id, sv_ammo_mode)

func apply_shared_movement_to_player(player: OnlinePlayer) -> void:
	if shared_speed > 0.0:
		player.movement.speed = shared_speed
	if shared_jump > 0.0:
		player.movement.jump_velocity = shared_jump


@rpc("any_peer", "reliable")
func _rpc_receive(text: String, sender_name: String) -> void:
	if not multiplayer.is_server():
		return
	text = text.strip_edges().left(MAX_LENGTH)
	if text.is_empty():
		return
	_rpc_broadcast.rpc(sender_name, text)


@rpc("authority", "reliable", "call_local")
func _rpc_broadcast(sender_name: String, text: String) -> void:
	chat_received.emit(sender_name, text)


@rpc("authority", "reliable", "call_local")
func _rpc_broadcast_system(text: String) -> void:
	system_received.emit(text)


@rpc("any_peer", "reliable")
func _rpc_admin_command(text: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if not _is_op(sender_id):
		_rpc_console_feedback.rpc_id(sender_id, "Нет прав: только op")
		return

	var parts := text.trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return

	var cmd := parts[0].to_lower()
	match cmd:
		"op":
			if parts.size() < 2:
				_rpc_console_feedback.rpc_id(sender_id, "Использование: /op <id|name>")
				return
			_handle_op_command(parts[1], sender_id)
		"speed":
			_handle_shared_move_command(cmd, parts, sender_id)
		"jump":
			_handle_shared_move_command(cmd, parts, sender_id)
		"sv_ammo":
			_handle_sv_ammo_command(parts, sender_id)
		"round_time":
			_handle_round_time_command(parts, sender_id)
		"round_limit":
			_handle_round_limit_command(parts, sender_id)
		_:
			_rpc_console_feedback.rpc_id(sender_id, "Неизвестная серверная команда")


func _is_op(peer_id: int) -> bool:
	if peer_id == 1:
		return true
	var info: Dictionary = Lobby.players.get(peer_id, {}) as Dictionary
	return bool(info.get("op", false))


func _handle_op_command(target: String, sender_id: int) -> void:
	var target_id := _find_peer_id(target)
	if target_id <= 0:
		_rpc_console_feedback.rpc_id(sender_id, "Игрок не найден")
		return

	Lobby.set_player_op(target_id, true)
	var target_name := Lobby.get_player_display_name(target_id)
	send_system("[ADMIN] %s получил OP" % target_name)
	_rpc_console_feedback.rpc_id(sender_id, "OP выдан: %s" % target_name)


func _handle_shared_move_command(cmd: String, parts: PackedStringArray, sender_id: int) -> void:
	if parts.size() < 2 or not parts[1].is_valid_float():
		_rpc_console_feedback.rpc_id(sender_id, "Использование: /%s <число>" % cmd)
		return

	var value := float(parts[1])
	if cmd == "speed":
		shared_speed = clampf(value, 1.0, 50.0)
		send_system("[ADMIN] speed = %.2f" % shared_speed)
	elif cmd == "jump":
		shared_jump = clampf(value, 5.0, 100.0)
		send_system("[ADMIN] jump = %.2f" % shared_jump)

	_rpc_sync_shared_movement.rpc(shared_speed, shared_jump)
	_rpc_console_feedback.rpc_id(sender_id, "Применено")


@rpc("authority", "reliable", "call_local")
func _rpc_sync_shared_movement(speed: float, jump: float) -> void:
	shared_speed = speed
	shared_jump = jump
	for node in get_tree().get_nodes_in_group("online_players"):
		var player := node as OnlinePlayer
		if player != null:
			apply_shared_movement_to_player(player)


@rpc("authority", "reliable", "call_local")
func _rpc_console_feedback(text: String) -> void:
	console_feedback.emit(text)


func _handle_sv_ammo_command(parts: PackedStringArray, sender_id: int) -> void:
	const MODES := ["обычный", "∞ магазин", "∞ резерв"]
	if parts.size() < 2:
		_rpc_console_feedback.rpc_id(sender_id, "sv_ammo = %d (%s)\nИспользование: /sv_ammo <0|1|2>" % [sv_ammo_mode, MODES[sv_ammo_mode]])
		return
	if not parts[1].is_valid_int():
		_rpc_console_feedback.rpc_id(sender_id, "Использование: /sv_ammo <0|1|2>")
		return
	var mode := clampi(int(parts[1]), 0, 2)
	sv_ammo_mode = mode
	_rpc_sync_ammo_mode.rpc(mode)
	send_system("[ADMIN] sv_ammo = %d (%s)" % [mode, MODES[mode]])
	_rpc_console_feedback.rpc_id(sender_id, "Применено")


func _handle_round_time_command(parts: PackedStringArray, sender_id: int) -> void:
	var gm := _get_game_manager()
	if gm == null or not (gm.game_mode is TeamEliminationMode):
		_rpc_console_feedback.rpc_id(sender_id, "Команда работает только в Team Elimination")
		return
	var mode := gm.game_mode as TeamEliminationMode
	if parts.size() < 2:
		_rpc_console_feedback.rpc_id(sender_id, "round_time = %.0f\nИспользование: /round_time <секунды>" % mode.round_duration)
		return
	if not parts[1].is_valid_float():
		_rpc_console_feedback.rpc_id(sender_id, "Использование: /round_time <секунды>")
		return
	mode.round_duration = maxf(float(parts[1]), 10.0)
	send_system("[ADMIN] round_time = %.0f сек" % mode.round_duration)
	_rpc_console_feedback.rpc_id(sender_id, "Применено")


func _handle_round_limit_command(parts: PackedStringArray, sender_id: int) -> void:
	var gm := _get_game_manager()
	if gm == null or not (gm.game_mode is TeamEliminationMode):
		_rpc_console_feedback.rpc_id(sender_id, "Команда работает только в Team Elimination")
		return
	var mode := gm.game_mode as TeamEliminationMode
	if parts.size() < 2:
		_rpc_console_feedback.rpc_id(sender_id, "round_limit = %d\nИспользование: /round_limit <число>" % mode.round_limit)
		return
	if not parts[1].is_valid_int():
		_rpc_console_feedback.rpc_id(sender_id, "Использование: /round_limit <число>")
		return
	mode.round_limit = maxi(int(parts[1]), 1)
	send_system("[ADMIN] round_limit = %d" % mode.round_limit)
	_rpc_console_feedback.rpc_id(sender_id, "Применено")


func _get_game_manager() -> GameManager:
	var nodes := get_tree().get_nodes_in_group("game_manager")
	if nodes.is_empty():
		return null
	return nodes[0] as GameManager


@rpc("authority", "reliable", "call_local")
func _rpc_sync_ammo_mode(mode: int) -> void:
	sv_ammo_mode = mode


func _find_peer_id(token: String) -> int:
	if token.is_valid_int():
		var peer_id := int(token)
		if Lobby.players.has(peer_id):
			return peer_id

	var needle := token.to_lower()
	for peer_id in Lobby.players.keys():
		var info: Dictionary = Lobby.players.get(peer_id, {}) as Dictionary
		if str(info.get("name", "")).to_lower() == needle:
			return int(peer_id)
	return -1
