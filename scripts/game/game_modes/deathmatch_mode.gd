class_name DeathmatchMode extends GameMode

@export var respawn_delay: float = 2.5
@export var frag_limit: int = 10
@export var default_weapon: WeaponData

@export_group("Buy / loadout")
## Если false — при покупке нового оружия старое удаляется без пикапа на карте.
@export var drop_weapon_on_buy_replace: bool = true
## 0 — без ограничений по времени/движению (как раньше: покупка всегда, без DM-защиты).
@export var loadout_grace_sec: float = 0.0
## Пока не сдвинулся с места — можно менять оружие в окне grace (и неуязвимость, если включена).
@export var loadout_requires_stationary: bool = true
## Неуязвимость в том же окне, что и loadout (пока действует grace и опционально стоит на месте).
@export var spawn_damage_protection: bool = true


func on_player_spawned(id: int, player: OnlinePlayer, _info: Dictionary, _reposition_existing_pawn: bool = false) -> void:
	if multiplayer.is_server() and default_weapon != null and game_manager != null:
		game_manager.rpc_equip_weapon_data.rpc(id, default_weapon.resource_path)
	if multiplayer.is_server():
		_configure_dm_spawn_state(player)


func should_drop_weapon_on_buy_replace() -> bool:
	return drop_weapon_on_buy_replace


func can_player_buy(player: OnlinePlayer) -> bool:
	if loadout_grace_sec <= 0.0:
		return true
	# Дедлайн задаёт только сервер и sync_dm_loadout_window; до прихода данных — не покупка и не UI.
	if player.dm_buy_grace_deadline_msec <= 0:
		return false
	var now := Time.get_ticks_msec()
	if now > player.dm_buy_grace_deadline_msec:
		return false
	if loadout_requires_stationary and player.dm_moved_since_spawn:
		return false
	return true


func is_spawn_damage_protected(player: OnlinePlayer) -> bool:
	if not spawn_damage_protection or loadout_grace_sec <= 0.0:
		return false
	var now := Time.get_ticks_msec()
	if now > player.dm_buy_grace_deadline_msec:
		return false
	if loadout_requires_stationary and player.dm_moved_since_spawn:
		return false
	return true


func _configure_dm_spawn_state(player: OnlinePlayer) -> void:
	player.reset_dm_loadout_tracking()
	if loadout_grace_sec <= 0.0:
		return
	player.dm_loadout_block_after_move = loadout_requires_stationary
	player.dm_buy_grace_deadline_msec = Time.get_ticks_msec() + int(loadout_grace_sec * 1000.0)
	if multiplayer.has_multiplayer_peer():
		player.sync_dm_loadout_window.rpc_id(
			player.remote_player_id,
			player.dm_buy_grace_deadline_msec,
			player.dm_loadout_block_after_move
		)


func on_player_despawned(_id: int, _info: Dictionary) -> void:
	pass


func on_player_died(victim_id: int, attacker_id: int) -> void:
	if not multiplayer.is_server():
		return
	if game_manager == null:
		return
	if attacker_id > 0 and attacker_id != victim_id:
		var k: int = game_manager.get_match_stat(attacker_id, "k")
		ffa_score_changed.emit(attacker_id, k)
		if k >= frag_limit:
			ffa_match_finished.emit(attacker_id, k)
	game_manager.schedule_respawn(victim_id, respawn_delay)


func is_buy_period() -> bool:
	return true


func get_buy_menu_status_hint(player: OnlinePlayer) -> String:
	if loadout_grace_sec <= 0.0:
		return "Режим: закупка в любой момент (ограничения по времени отключены)."
	# Меню только при can_player_buy — остаётся активное окно grace.
	var now := Time.get_ticks_msec()
	var left_sec := maxf((player.dm_buy_grace_deadline_msec - now) / 1000.0, 0.0)
	var stationary := ", стойте на месте" if loadout_requires_stationary else ""
	return "Можно менять снаряжение ещё ~%.1f с%s." % [left_sec, stationary]


func get_scores() -> Dictionary:
	if game_manager == null:
		return {}
	return game_manager.get_kill_counts_dict_for_board()
