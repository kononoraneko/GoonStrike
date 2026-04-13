## team_elimination_mode.gd
## CS-подобный режим на базе TeamGameMode.
## Правила: раунды фиксированной длины, одна жизнь за раунд,
## победа раунда — уничтожить всех врагов до истечения времени.
## Матч выигрывает команда, набравшая @export round_limit раундов.

class_name TeamEliminationMode extends TeamGameMode

# ── Настройки ─────────────────────────────────────────────────────────────

@export var round_limit:      int   = 12
@export var round_duration:   float = 120.0
@export var round_end_delay:  float = 3.0
@export var respawn_on_start: bool  = true

@export var default_weapon: WeaponData


func get_round_timer_duration() -> float:
	return round_duration


func should_spawn_on_player_connected() -> bool:
	return true

# ── Внутреннее состояние ──────────────────────────────────────────────────

## peer_id → true (только играющие пиры, без хоста-спектатора)
var _alive_this_round: Dictionary = {}
## Клиентская копия (заполняется через RPC)
var _alive_client_cache: Dictionary = {}

var _round_active: bool = false

var _round_timer_seq: int = 0


func get_alive_peers() -> Dictionary:
	if multiplayer.is_server():
		return _alive_this_round.duplicate()
	return _alive_client_cache.duplicate()


# ── Переопределения TeamGameMode ──────────────────────────────────────────

func _on_round_started_internal(round_number: int) -> void:
	if not multiplayer.is_server():
		return

	_alive_this_round.clear()
	_round_active = true

	if respawn_on_start:
		for id in Lobby.players.keys():
			if GameManager.is_host_spectator(id):
				continue
			_alive_this_round[id] = true
			game_manager.schedule_respawn(id, 0.0)

	_push_alive_to_clients()

	var msg := "[%d] Раунд %d начался" % [round_limit, round_number]
	ChatNetwork.send_system(msg)

	_round_timer_seq += 1
	var seq := _round_timer_seq
	get_tree().create_timer(round_duration).timeout.connect(func():
		if seq != _round_timer_seq or not _round_active:
			return
		_on_round_timeout()
	)


func _on_round_ended_internal(winning_team: int) -> void:
	if not multiplayer.is_server():
		return

	_round_active = false
	_alive_this_round.clear()
	_push_alive_to_clients()

	var winner_name := get_team_name(winning_team) if winning_team != Team.NONE else "Ничья"
	ChatNetwork.send_system("[Round] %s побеждает раунд" % winner_name)

	for team_id in [Team.ALPHA, Team.BRAVO]:
		if get_team_score(team_id) >= round_limit:
			team_match_finished.emit(team_id, get_team_score(team_id))
			var match_msg := "[Match] %s выигрывает матч (%d раундов)!" % [
				get_team_name(team_id), get_team_score(team_id)
			]
			ChatNetwork.send_system(match_msg)
			return

	get_tree().create_timer(round_end_delay).timeout.connect(_start_next_round)


func _on_player_spawned_team(id: int, player: OnlinePlayer, _info: Dictionary) -> void:
	super._on_player_spawned_team(id, player, _info)
	if not multiplayer.is_server():
		return
	if _round_active and not GameManager.is_host_spectator(id):
		_alive_this_round[id] = true
		_push_alive_to_clients()
	if default_weapon != null and not GameManager.is_host_spectator(id):
		game_manager.rpc_equip_weapon_data.rpc(id, default_weapon.resource_path)


func _on_player_died_team(victim_id: int, _attacker_id: int) -> void:
	if not multiplayer.is_server():
		return

	_alive_this_round.erase(victim_id)
	_push_alive_to_clients()

	if not _round_active:
		return

	_check_round_end()


func _on_player_despawned_team(id: int, _info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_alive_this_round.erase(id)
	_push_alive_to_clients()


# ── Логика окончания раунда ───────────────────────────────────────────────

func _check_round_end() -> void:
	var alive_alpha := _count_alive(Team.ALPHA)
	var alive_bravo := _count_alive(Team.BRAVO)

	if alive_alpha == 0 and alive_bravo == 0:
		_end_round(Team.NONE)
	elif alive_alpha == 0:
		_end_round(Team.BRAVO)
	elif alive_bravo == 0:
		_end_round(Team.ALPHA)


func _count_alive(team: int) -> int:
	var count := 0
	for pid in _alive_this_round.keys():
		if get_team(pid) == team:
			count += 1
	return count


func _on_round_timeout() -> void:
	if not _round_active:
		return
	var alive_alpha := _count_alive(Team.ALPHA)
	var alive_bravo := _count_alive(Team.BRAVO)

	ChatNetwork.send_system("[Round] Время вышло!")

	if alive_alpha > alive_bravo:
		_end_round(Team.ALPHA)
	elif alive_bravo > alive_alpha:
		_end_round(Team.BRAVO)
	else:
		_end_round(Team.NONE)


# ── Alive state sync ─────────────────────────────────────────────────────

func _push_alive_to_clients() -> void:
	if not multiplayer.is_server():
		return
	var packed := _alive_this_round.duplicate(true)
	for p in multiplayer.get_peers():
		_rpc_sync_alive.rpc_id(p, packed)


@rpc("authority", "reliable")
func _rpc_sync_alive(state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_alive_client_cache = state.duplicate(true)
