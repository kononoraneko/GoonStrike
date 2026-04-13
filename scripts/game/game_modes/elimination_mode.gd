## team_elimination_mode.gd
## CS-подобный режим на базе TeamGameMode.
## Правила: раунды фиксированной длины, одна жизнь за раунд,
## победа раунда — уничтожить всех врагов до истечения времени.
## Матч выигрывает команда, набравшая @export round_limit раундов.

class_name TeamEliminationMode extends TeamGameMode

# ── Настройки ─────────────────────────────────────────────────────────────

@export var round_limit:      int   = 12       ## Раундов для победы в матче
@export var round_duration:   float = 120.0    ## Секунд на раунд
@export var round_end_delay:  float = 3.0      ## Пауза после раунда
@export var respawn_on_start: bool  = true     ## Заспавнить всех в начале раунда

@export var default_weapon: WeaponData

# ── Внутреннее состояние ──────────────────────────────────────────────────

## Игроки, живые в текущем раунде (peer_id → true)
var _alive_this_round: Dictionary = {}

## Живой ли раунд (принимаем ли смерти)
var _round_active: bool = false

var _round_timer: SceneTreeTimer = null


# ── Переопределения TeamGameMode ──────────────────────────────────────────

func _on_round_started_internal(round_number: int) -> void:
	if not multiplayer.is_server():
		return

	_alive_this_round.clear()
	_round_active = true

	# Заспавнить / вернуть всех игроков
	if respawn_on_start:
		for id in Lobby.players.keys():
			_alive_this_round[id] = true
			game_manager.schedule_respawn(id, 0.0)

	var msg := "[%d] Раунд %d начался" % [round_limit, round_number]
	ChatNetwork.send_system(msg)

	# Таймер раунда
	_round_timer = get_tree().create_timer(round_duration)
	_round_timer.timeout.connect(_on_round_timeout)


func _on_round_ended_internal(winning_team: int) -> void:
	if not multiplayer.is_server():
		return

	_round_active = false

	var winner_name := get_team_name(winning_team) if winning_team != Team.NONE else "Ничья"
	ChatNetwork.send_system("[Round] %s побеждает раунд" % winner_name)

	# Проверка победы в матче
	for team in [Team.ALPHA, Team.BRAVO]:
		if get_team_score(team) >= round_limit:
			match_finished.emit(team, get_team_score(team))
			var match_msg := "[Match] %s выигрывает матч (%d раундов)!" % [
				get_team_name(team), get_team_score(team)
			]
			ChatNetwork.send_system(match_msg)
			return

	# Следующий раунд через паузу
	get_tree().create_timer(round_end_delay).timeout.connect(_start_next_round)


func _on_player_spawned_team(id: int, player: OnlinePlayer, _info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if default_weapon != null:
		player.weapon_holder.rpc("equip_from_pickup", NodePath(), default_weapon.resource_path)


func _on_player_died_team(victim_id: int, attacker_id: int) -> void:
	if not multiplayer.is_server():
		return

	_alive_this_round.erase(victim_id)
	# В этом режиме не возрождаем в середине раунда
	# game_manager.schedule_respawn — НЕ вызываем

	if not _round_active:
		return

	_check_round_end()


func _on_player_despawned_team(id: int, _info: Dictionary) -> void:
	_alive_this_round.erase(id)


# ── Логика окончания раунда ───────────────────────────────────────────────

func _check_round_end() -> void:
	var alive_alpha := _count_alive(Team.ALPHA)
	var alive_bravo := _count_alive(Team.BRAVO)

	if alive_alpha == 0 and alive_bravo == 0:
		_end_round(Team.NONE)                 # ничья
	elif alive_alpha == 0:
		_end_round(Team.BRAVO)
	elif alive_bravo == 0:
		_end_round(Team.ALPHA)
	# Иначе — раунд продолжается


func _count_alive(team: int) -> int:
	var count := 0
	for pid in _alive_this_round.keys():
		if get_team(pid) == team:
			count += 1
	return count


func _on_round_timeout() -> void:
	if not _round_active:
		return
	# По истечению времени: победа команды с большим числом выживших
	var alive_alpha := _count_alive(Team.ALPHA)
	var alive_bravo := _count_alive(Team.BRAVO)

	ChatNetwork.send_system("[Round] Время вышло!")

	if alive_alpha > alive_bravo:
		_end_round(Team.ALPHA)
	elif alive_bravo > alive_alpha:
		_end_round(Team.BRAVO)
	else:
		_end_round(Team.NONE)
