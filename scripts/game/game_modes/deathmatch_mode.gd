class_name DeathmatchMode extends GameMode

@export var respawn_delay: float = 2.5
@export var frag_limit: int = 10
@export var default_weapon: WeaponData


func on_player_spawned(id: int, player: OnlinePlayer, _info: Dictionary) -> void:
	if multiplayer.is_server() and default_weapon != null and game_manager != null:
		game_manager.rpc_equip_weapon_data.rpc(id, default_weapon.resource_path)


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


func get_scores() -> Dictionary:
	if game_manager == null:
		return {}
	return game_manager.get_kill_counts_dict_for_board()
