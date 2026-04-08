class_name HealthComponent extends Node

signal health_changed(current_hp: int)
signal died(victim_id: int, attacker_id: int)

@export var max_health: int = 100
var health: int = max_health

var owner_player: OnlinePlayer


func _ready() -> void:
	owner_player = get_parent() as OnlinePlayer
	health = max_health


## Только сервер вычитает hp и рассылает обновление.
func take_damage(amount: int, attacker: OnlinePlayer) -> void:
	if not multiplayer.is_server():
		return
	if health <= 0:
		return

	health -= amount
	if health <= 0:
		health = 0
		rpc("_sync_health", health)

		var attacker_id := 0
		if attacker != null:
			attacker_id = attacker.remote_player_id

		died.emit(owner_player.remote_player_id, attacker_id)
		owner_player.set_dead_state()
	else:
		rpc("_sync_health", health)
		owner_player.rpc("rpc_play_hit_animation")


func reset_health() -> void:
	health = max_health
	rpc("_sync_health", health)


@rpc("any_peer", "reliable", "call_local")
func _sync_health(new_hp: int) -> void:
	health = new_hp
	health_changed.emit(health)
