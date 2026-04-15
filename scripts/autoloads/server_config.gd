## ServerConfig.gd  —  Autoload
## Хранит и реплицирует серверные настройки: режим патронов, скорость, прыжок.
## Выделен из ChatNetwork — оружие и движение больше не зависят от чат-синглтона.
##
## Добавить в Project → Project Settings → Autoload как "ServerConfig".

extends Node

signal ammo_mode_changed(mode: int)

## 0 = обычный, 1 = бесконечный магазин, 2 = бесконечный резерв
var sv_ammo_mode: int = 0
var shared_speed: float = -1.0
var shared_jump: float = -1.0


## Применить текущие настройки движения к конкретному игроку.
func apply_movement_to_player(player: OnlinePlayer) -> void:
	if shared_speed > 0.0:
		player.movement.speed = shared_speed
	if shared_jump > 0.0:
		player.movement.jump_velocity = shared_jump


## Отправить текущее состояние конкретному клиенту (вызывается при его подключении).
func sync_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1:
		_apply_ammo_mode(sv_ammo_mode)
		_apply_movement(shared_speed, shared_jump)
	else:
		_rpc_sync_ammo_mode.rpc_id(peer_id, sv_ammo_mode)
		_rpc_sync_movement.rpc_id(peer_id, shared_speed, shared_jump)


## Установить и разослать режим патронов всем клиентам.
func set_and_broadcast_ammo_mode(mode: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_ammo_mode.rpc(mode)


## Установить и разослать настройки движения всем клиентам.
func set_and_broadcast_movement(speed: float, jump: float) -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_movement.rpc(speed, jump)


# ── RPC ───────────────────────────────────────────────────────────────────

@rpc("authority", "reliable", "call_local")
func _rpc_sync_ammo_mode(mode: int) -> void:
	_apply_ammo_mode(mode)


@rpc("authority", "reliable", "call_local")
func _rpc_sync_movement(speed: float, jump: float) -> void:
	_apply_movement(speed, jump)


# ── Приватное ─────────────────────────────────────────────────────────────

func _apply_ammo_mode(mode: int) -> void:
	sv_ammo_mode = mode
	ammo_mode_changed.emit(mode)


func _apply_movement(speed: float, jump: float) -> void:
	shared_speed = speed
	shared_jump  = jump
	for node in get_tree().get_nodes_in_group("online_players"):
		var player := node as OnlinePlayer
		if player:
			apply_movement_to_player(player)
