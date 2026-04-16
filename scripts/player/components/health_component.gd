class_name HealthComponent extends Node

signal health_changed(current_hp: int)
signal died(victim_id: int, attacker_id: int, assist_id: int)

@export var max_health: int = 100
var health: int = max_health

## Последний враг, нанёсший урон до текущего попадания (для ассиста при добивании).
var _last_enemy_damage_peer_id: int = 0

## Внешний фильтр урона. Сигнатура: func(attacker_id: int, victim_id: int) -> bool
## Если не задан — урон всегда проходит.
var damage_filter: Callable = Callable()

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
	if owner_player.is_dm_spawn_protected_from_damage():
		return
	if damage_filter.is_valid():
		var atk_f := attacker.remote_player_id if attacker != null else 0
		if not damage_filter.call(atk_f, owner_player.remote_player_id):
			return

	var victim_id := owner_player.remote_player_id
	var attacker_id := attacker.remote_player_id if attacker != null else 0
	var will_die := health - amount <= 0
	var assist_id := 0
	if will_die and attacker_id > 0 and attacker_id != victim_id:
		if _last_enemy_damage_peer_id != 0 and _last_enemy_damage_peer_id != attacker_id:
			assist_id = _last_enemy_damage_peer_id

	health -= amount
	if health <= 0:
		health = 0
		rpc("_sync_health", health)
		died.emit(victim_id, attacker_id, assist_id)
		owner_player.set_dead_state()
	else:
		if attacker_id != 0 and attacker_id != victim_id:
			_last_enemy_damage_peer_id = attacker_id
		rpc("_sync_health", health)
		owner_player.rpc("rpc_play_hit_animation")


func reset_health() -> void:
	health = max_health
	_last_enemy_damage_peer_id = 0
	rpc("_sync_health", health)


@rpc("any_peer", "reliable", "call_local")
func _sync_health(new_hp: int) -> void:
	health = new_hp
	health_changed.emit(health)
