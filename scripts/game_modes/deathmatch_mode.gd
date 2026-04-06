class_name DeathmatchMode extends GameMode

signal score_changed(player_id: int, score: int)
signal match_finished(winner_id: int, score: int)

@export var respawn_delay: float = 2.5
@export var frag_limit: int = 10

var _scores: Dictionary = {}


func on_player_spawned(id: int, _player: OnlinePlayer, _info: Dictionary) -> void:
	if not _scores.has(id):
		_scores[id] = 0


func on_player_despawned(id: int, _info: Dictionary) -> void:
	if not _scores.has(id):
		_scores[id] = 0


func on_player_died(victim_id: int, attacker_id: int) -> void:
	if attacker_id > 0 and attacker_id != victim_id:
		_scores[attacker_id] = int(_scores.get(attacker_id, 0)) + 1
		score_changed.emit(attacker_id, _scores[attacker_id])
		if _scores[attacker_id] >= frag_limit:
			match_finished.emit(attacker_id, _scores[attacker_id])

	game_manager.schedule_respawn(victim_id, respawn_delay)


func get_scores() -> Dictionary:
	return _scores.duplicate(true)
