class_name HealthComponent extends Node
 
signal health_changed(current_hp: int)
signal died
 
@export var max_health: int = 100
var health: int = max_health
 
var owner_player: OnlinePlayer
 
func _ready() -> void:
	owner_player = get_parent() as OnlinePlayer
	health = max_health
 
 
## Только сервер вычитает hp и рассылает обновление.
func take_damage(amount: int, _attacker: OnlinePlayer) -> void:
	if not multiplayer.is_server():
		return
	health -= amount
	if health <= 0:
		health = 0
		rpc("_sync_health", health)
		owner_player.rpc("rpc_play_hit_animation")
		die()
	else:
		rpc("_sync_health", health)
		owner_player.rpc("rpc_play_hit_animation")
 
 
func die() -> void:
	died.emit()
	print("Player %s died" % owner_player.name)
 
 
@rpc("any_peer", "reliable", "call_local")
func _sync_health(new_hp: int) -> void:
	health = new_hp
	health_changed.emit(health)
