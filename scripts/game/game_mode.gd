class_name GameMode extends Node

## Базовый контракт игрового режима.
## GameManager делегирует сюда ключевые события матча.

var game_manager: GameManager

func setup(manager: GameManager) -> void:
	game_manager = manager


func on_game_started() -> void:
	pass


func on_player_spawned(_id: int, _player: OnlinePlayer, _info: Dictionary) -> void:
	pass


func on_player_despawned(_id: int, _info: Dictionary) -> void:
	pass


func on_player_died(_victim_id: int, _attacker_id: int) -> void:
	pass
