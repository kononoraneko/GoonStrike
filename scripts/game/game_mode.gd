class_name GameMode extends Node

## Базовый контракт игрового режима.
## GameManager делегирует сюда ключевые события матча.
## Сигналы с префиксами ffa_/team_ разводят смысл (peer id vs team id).

signal ffa_score_changed(player_id: int, score: int)
signal ffa_match_finished(winner_peer_id: int, score: int)

signal team_score_changed(team: int, score: int)
signal team_match_finished(winning_team: int, score: int)

signal round_started(round_number: int)
signal round_ended(winning_team: int)

var game_manager: GameManager

func setup(manager: GameManager) -> void:
	game_manager = manager


## Для HUD таймера раунда: > 0 — длительность в секундах; иначе таймер не ведётся.
func get_round_timer_duration() -> float:
	return -1.0


func on_game_started() -> void:
	pass


## Для TeamElimination вернуть false — спавн только из логики раунда, не по player_connected.
func should_spawn_on_player_connected() -> bool:
	return true


func on_player_spawned(_id: int, _player: OnlinePlayer, _info: Dictionary, _reposition_existing_pawn: bool = false) -> void:
	pass


func on_player_despawned(_id: int, _info: Dictionary) -> void:
	pass


func on_player_died(_victim_id: int, _attacker_id: int) -> void:
	pass


## Для TAB: peer_id → true для живых игроков. Пустой = нет трекинга.
func get_alive_peers() -> Dictionary:
	return {}


## Можно ли сейчас покупать оружие. Переопределяется в подклассах.
func is_buy_period() -> bool:
	return false


## Разрешение покупки конкретному игроку (время, зона, DM loadout и т.д.).
func can_player_buy(_player: OnlinePlayer) -> bool:
	return is_buy_period()


## При смене оружия через меню: выбросить старое на карту или только удалить слот.
func should_drop_weapon_on_buy_replace() -> bool:
	return true


## Строка для меню закупки: правила, таймер, причина отказа (пусто = нет подсказки).
func get_buy_menu_status_hint(_player: OnlinePlayer) -> String:
	return ""
