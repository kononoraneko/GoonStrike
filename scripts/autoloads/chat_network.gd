## ChatNetwork.gd  —  Autoload
## Транслирует сообщения чата и обрабатывает серверные команды.
## Настройки сервера (патроны, скорость, прыжок) делегированы в ServerConfig.

extends Node

signal chat_received(sender_name: String, text: String)
signal system_received(text: String)
signal console_feedback(text: String)

const MAX_LENGTH := 200


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


# ── RPC ───────────────────────────────────────────────────────────────────

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

	var parts := text.trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return

	var cmd := parts[0].to_lower()

	# /weapons доступна всем
	if cmd == "weapons":
		_handle_weapons_command(sender_id)
		return

	if not _is_op(sender_id):
		_rpc_console_feedback.rpc_id(sender_id, "Нет прав: только op")
		return

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
		"give":
			_handle_give_command(parts, sender_id)
		_:
			_rpc_console_feedback.rpc_id(sender_id, "Неизвестная серверная команда")


@rpc("authority", "reliable", "call_local")
func _rpc_console_feedback(text: String) -> void:
	console_feedback.emit(text)


# ── Обработчики команд ────────────────────────────────────────────────────

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
		var speed := clampf(value, 1.0, 50.0)
		ServerConfig.set_and_broadcast_movement(speed, ServerConfig.shared_jump)
		send_system("[ADMIN] speed = %.2f" % speed)
	elif cmd == "jump":
		var jump := clampf(value, 5.0, 100.0)
		ServerConfig.set_and_broadcast_movement(ServerConfig.shared_speed, jump)
		send_system("[ADMIN] jump = %.2f" % jump)
	_rpc_console_feedback.rpc_id(sender_id, "Применено")


func _handle_sv_ammo_command(parts: PackedStringArray, sender_id: int) -> void:
	const MODES := ["обычный", "∞ магазин", "∞ резерв"]
	if parts.size() < 2:
		_rpc_console_feedback.rpc_id(sender_id,
			"sv_ammo = %d (%s)\nИспользование: /sv_ammo <0|1|2>" % [
				ServerConfig.sv_ammo_mode, MODES[ServerConfig.sv_ammo_mode]])
		return
	if not parts[1].is_valid_int():
		_rpc_console_feedback.rpc_id(sender_id, "Использование: /sv_ammo <0|1|2>")
		return
	var mode := clampi(int(parts[1]), 0, 2)
	ServerConfig.set_and_broadcast_ammo_mode(mode)
	send_system("[ADMIN] sv_ammo = %d (%s)" % [mode, MODES[mode]])
	_rpc_console_feedback.rpc_id(sender_id, "Применено")


func _handle_round_time_command(parts: PackedStringArray, sender_id: int) -> void:
	var gm := _get_game_manager()
	if gm == null or not (gm.game_mode is TeamEliminationMode):
		_rpc_console_feedback.rpc_id(sender_id, "Команда работает только в Team Elimination")
		return
	var mode := gm.game_mode as TeamEliminationMode
	if parts.size() < 2:
		_rpc_console_feedback.rpc_id(sender_id,
			"round_time = %.0f\nИспользование: /round_time <секунды>" % mode.round_duration)
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
		_rpc_console_feedback.rpc_id(sender_id,
			"round_limit = %d\nИспользование: /round_limit <число>" % mode.round_limit)
		return
	if not parts[1].is_valid_int():
		_rpc_console_feedback.rpc_id(sender_id, "Использование: /round_limit <число>")
		return
	mode.round_limit = maxi(int(parts[1]), 1)
	send_system("[ADMIN] round_limit = %d" % mode.round_limit)
	_rpc_console_feedback.rpc_id(sender_id, "Применено")


func _handle_give_command(parts: PackedStringArray, sender_id: int) -> void:
	if parts.size() < 2:
		_rpc_console_feedback.rpc_id(sender_id, "Использование: /give <оружие>\nСписок: /weapons")
		return
	var weapon_key := parts[1].strip_edges().to_lower()
	if not WeaponRegistry.has_weapon(weapon_key):
		_rpc_console_feedback.rpc_id(sender_id, "Оружие не найдено: %s\nСписок: /weapons" % weapon_key)
		return
	var data_path := WeaponRegistry.get_weapon_path(weapon_key)
	var gm := _get_game_manager()
	if gm == null:
		_rpc_console_feedback.rpc_id(sender_id, "GameManager не найден")
		return
	var pl := gm.spawner.get_player(sender_id)
	if pl == null:
		_rpc_console_feedback.rpc_id(sender_id, "Игрок не заспавнен")
		return
	if pl.weapon_holder.has_primary_weapon():
		gm._server_drop_player_weapon(pl)
	gm.rpc_equip_weapon_data.rpc(sender_id, data_path)
	_rpc_console_feedback.rpc_id(sender_id, "Выдано: %s" % weapon_key)


func _handle_weapons_command(sender_id: int) -> void:
	var names := WeaponRegistry.get_all_names()
	if names.is_empty():
		_rpc_console_feedback.rpc_id(sender_id, "Оружие не зарегистрировано")
		return
	var lines: PackedStringArray = ["[b]Доступное оружие:[/b]"]
	for n in names:
		lines.append("  • %s" % n)
	lines.append("Использование: /give <название>")
	_rpc_console_feedback.rpc_id(sender_id, "\n".join(lines))


# ── Утилиты ───────────────────────────────────────────────────────────────

func _get_game_manager() -> GameManager:
	var nodes := get_tree().get_nodes_in_group("game_manager")
	return nodes[0] as GameManager if not nodes.is_empty() else null


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
