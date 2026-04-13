## team_game_mode.gd
## Командный режим — промежуточная база между GameMode и конкретными режимами.
## Берёт на себя: реестр команд, балансировку, командные очки, дружественный огонь.
## Подклассы переопределяют только то, что меняется в их логике.

class_name TeamGameMode extends GameMode

# ── Сигналы ───────────────────────────────────────────────────────────────

signal player_team_assigned(player_id: int, team: int)

# ── Команды ───────────────────────────────────────────────────────────────

enum Team {
	NONE  = 0,
	ALPHA = 1,   ## Например: CT / Красные / Союзники
	BRAVO = 2,   ## Например: T  / Синие   / Противники
}

## Человекочитаемые имена команд — можно переопределить в дочернем классе.
var team_names: Dictionary = {
	Team.ALPHA: "Alpha",
	Team.BRAVO: "Bravo",
}

# ── Экспортируемые настройки ──────────────────────────────────────────────

@export var friendly_fire: bool = false
@export var auto_balance: bool  = true   ## Автораспределение при входе

# ── Внутреннее состояние ──────────────────────────────────────────────────

## peer_id → Team
var _player_teams: Dictionary = {}

## Team → int (очки матча, не раунда)
var _team_scores: Dictionary = {
	Team.ALPHA: 0,
	Team.BRAVO: 0,
}

var _current_round: int = 0


# ── Публичное API: команды ────────────────────────────────────────────────

func get_team(player_id: int) -> int:
	return int(_player_teams.get(player_id, Team.NONE))


func get_team_name(team: int) -> String:
	return str(team_names.get(team, "Team %d" % team))


func get_team_score(team: int) -> int:
	return int(_team_scores.get(team, 0))


func get_team_members(team: int) -> Array:
	var result: Array = []
	for pid in _player_teams.keys():
		if _player_teams[pid] == team:
			result.append(pid)
	return result


## Принудительно назначить игрока в команду (только сервер).
func assign_team(player_id: int, team: int) -> void:
	if not multiplayer.is_server():
		return
	_player_teams[player_id] = team
	player_team_assigned.emit(player_id, team)
	_rpc_sync_team.rpc(player_id, team)


## Противники ли два игрока? (с учётом friendly_fire)
func are_enemies(a_id: int, b_id: int) -> bool:
	if a_id == b_id:
		return false
	var ta: int = get_team(a_id)
	var tb: int = get_team(b_id)
	if ta == Team.NONE or tb == Team.NONE:
		return true   ## Без команды — все враги
	if ta == tb:
		return friendly_fire
	return true


# ── Публичное API: раунды ─────────────────────────────────────────────────

func get_current_round() -> int:
	return _current_round


## Вызвать из подкласса, когда раунд завершён.
func _end_round(winning_team: int) -> void:
	if winning_team != Team.NONE:
		_team_scores[winning_team] = int(_team_scores.get(winning_team, 0)) + 1
		team_score_changed.emit(winning_team, _team_scores[winning_team])
		_broadcast_score()
	if multiplayer.is_server():
		_rpc_sync_scores.rpc(_team_scores[Team.ALPHA], _team_scores[Team.BRAVO])
	_on_round_ended_internal(winning_team)
	round_ended.emit(winning_team)


## Отправить текущие командные очки конкретному клиенту (для поздних входов).
func sync_scores_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_scores.rpc_id(peer_id, _team_scores[Team.ALPHA], _team_scores[Team.BRAVO])


## Вызвать из подкласса, чтобы начать следующий раунд.
func _start_next_round() -> void:
	_current_round += 1
	round_started.emit(_current_round)
	_on_round_started_internal(_current_round)


# ── Хуки для подклассов (override без обязательного super) ────────────────

## Вызывается в начале каждого раунда после инкремента счётчика.
func _on_round_started_internal(_round: int) -> void:
	pass


## Вызывается по завершении раунда (перед round_ended сигналом).
func _on_round_ended_internal(_winning_team: int) -> void:
	pass


## Подкласс может переопределить, чтобы изменить логику спавна по командам.
func get_spawn_point_for_team(_team: int) -> int:
	return -1   ## -1 = PlayerSpawner выбирает сам


# ── Переопределения GameMode ──────────────────────────────────────────────

func on_game_started() -> void:
	_current_round = 0
	_team_scores = { Team.ALPHA: 0, Team.BRAVO: 0 }
	_start_next_round()


func on_player_spawned(id: int, player: OnlinePlayer, info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if auto_balance and not _player_teams.has(id):
		var team := _pick_balanced_team()
		assign_team(id, team)
	if not GameManager.is_host_spectator(id):
		for pid in _player_teams.keys():
			_rpc_sync_team.rpc_id(id, pid, _player_teams[pid])
	_on_player_spawned_team(id, player, info)


func on_player_despawned(id: int, info: Dictionary) -> void:
	_on_player_despawned_team(id, info)


func on_player_died(victim_id: int, attacker_id: int) -> void:
	_on_player_died_team(victim_id, attacker_id)


# ── Хуки с командным контекстом (рекомендуется override вместо on_player_*) ──

func _on_player_spawned_team(_id: int, player: OnlinePlayer, _info: Dictionary) -> void:
	player.health_component.damage_filter = func(attacker_id: int, victim_id: int) -> bool:
		return are_enemies(attacker_id, victim_id)

func _on_player_despawned_team(_id: int, _info: Dictionary) -> void:
	pass

func _on_player_died_team(_victim_id: int, _attacker_id: int) -> void:
	pass


# ── Авто-балансировка ─────────────────────────────────────────────────────

func _pick_balanced_team() -> int:
	var alpha_count := get_team_members(Team.ALPHA).size()
	var bravo_count := get_team_members(Team.BRAVO).size()
	if alpha_count <= bravo_count:
		return Team.ALPHA
	return Team.BRAVO


# ── Вспомогательные методы ────────────────────────────────────────────────

func _broadcast_score() -> void:
	if not multiplayer.is_server():
		return
	var alpha : int = _team_scores[Team.ALPHA]
	var bravo : int = _team_scores[Team.BRAVO]
	var msg := "[%s] %s %d — %d %s" % [
		get_class(),
		get_team_name(Team.ALPHA), alpha,
		bravo, get_team_name(Team.BRAVO)
	]
	ChatNetwork.send_system(msg)


# ── RPC: синхронизация команд и очков ────────────────────────────────────

@rpc("authority", "reliable", "call_local")
func _rpc_sync_team(player_id: int, team: int) -> void:
	_player_teams[player_id] = team
	player_team_assigned.emit(player_id, team)


@rpc("authority", "reliable")
func _rpc_sync_scores(alpha: int, bravo: int) -> void:
	_team_scores[Team.ALPHA] = alpha
	_team_scores[Team.BRAVO] = bravo
