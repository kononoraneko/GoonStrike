class_name WeaponHolder extends Node

## Отвечает за: текущее оружие, подбор, выброс, смену.
## Оружия могут не быть вовсе — current_weapon == null.
## RPC методы репликируют состояние слота на все клиенты.

signal weapon_changed(new_weapon: Weapon)

@export var weapon_mount: Node3D
@export var weapon_mount_arms: Node3D

var is_shooting:    bool = false
var current_weapon: Weapon = null
var owner_player:   OnlinePlayer

## Максимально допустимый угол между клиентским и серверным направлением.
## cos(25°) ≈ 0.906. Защищает от явных читов, оставляя запас на сетевой лаг.
const _MAX_AIM_DOT := 0.906


func _ready() -> void:
	owner_player = get_parent() as OnlinePlayer
	assert(owner_player != null, "WeaponHolder must be child of OnlinePlayer")

	ServerConfig.ammo_mode_changed.connect(_on_ammo_mode_changed)

	if not multiplayer.is_server():
		var gm := get_tree().get_first_node_in_group("game_manager") as GameManager
		if gm:
			gm.server_weapon_sync_request.rpc_id(1, owner_player.remote_player_id)


# ── Стрельба ──────────────────────────────────────────────────────────────

func start_shooting() -> void:
	# Гарантируем одиночный цикл: повторный вызов до stop_shooting ничего не делает
	if current_weapon == null or owner_player.is_dead or is_shooting:
		return
	is_shooting = true
	_fire_loop()


func stop_shooting() -> void:
	is_shooting = false


func _fire_loop() -> void:
	if not is_shooting or current_weapon == null or owner_player.is_dead:
		is_shooting = false
		return
	try_shoot(owner_player.get_aim_ray())
	if current_weapon != null and current_weapon.data.is_automatic:
		# CONNECT_ONE_SHOT гарантирует, что старый сигнал не накапливается
		get_tree().create_timer(current_weapon.data.fire_rate) \
			.timeout.connect(_fire_loop, CONNECT_ONE_SHOT)
	else:
		is_shooting = false


func try_shoot(aim_ray: Dictionary) -> void:
	if owner_player.is_dead or current_weapon == null:
		return
	if not current_weapon.shoot(aim_ray) and current_weapon.ammo_in_mag <= 0:
		try_reload()


func try_reload() -> void:
	if owner_player.is_dead or current_weapon == null:
		return
	if not owner_player.is_multiplayer_authority():
		return
	if current_weapon.request_reload_local():
		rpc_id(1, "_server_request_reload")


# ── Экипировка / сброс ────────────────────────────────────────────────────

## Локальная установка оружия по пути к WeaponData (без RPC).
func equip_weapon_data_local(data_path: String) -> void:
	var data := load(data_path) as WeaponData
	if data == null or data.weapon_scene == null:
		push_error("WeaponHolder: invalid WeaponData at " + data_path)
		return
	_set_weapon(data)


func equip_primary_from_world(data_path: String, ammo_in_mag: int, ammo_reserve: int) -> void:
	var data := load(data_path) as WeaponData
	if data == null or data.weapon_scene == null:
		push_error("WeaponHolder: invalid world WeaponData at " + data_path)
		return
	_set_weapon(data, ammo_in_mag, ammo_reserve, true)


## Подбор оружия — вызывается сервером через RPC на всех клиентах.
@rpc("any_peer", "reliable", "call_local")
func equip_from_pickup(_pickup_path: NodePath, data_path: String) -> void:
	equip_weapon_data_local(data_path)


func drop_weapon() -> void:
	clear_current_weapon()


func clear_current_weapon() -> void:
	stop_shooting()
	if current_weapon == null:
		if owner_player and owner_player.animation:
			owner_player.animation.set_reloading(false)
		return
	current_weapon.queue_free()
	current_weapon = null
	if owner_player and owner_player.animation:
		owner_player.animation.set_reloading(false)
	weapon_changed.emit(null)


func has_primary_weapon() -> bool:
	return current_weapon != null


func create_drop_snapshot() -> Dictionary:
	if current_weapon == null or current_weapon.data == null:
		return {}
	var data_path := current_weapon.data.resource_path
	if data_path.is_empty():
		return {}
	return {
		"data_path": data_path,
		"ammo_in_mag": max(current_weapon.ammo_in_mag, 0),
		"ammo_reserve": max(current_weapon.ammo_reserve, 0),
	}


# ── Обработчики сигналов ──────────────────────────────────────────────────

func _on_shot_requested(aim_origin: Vector3, aim_direction: Vector3) -> void:
	if owner_player.is_multiplayer_authority():
		rpc_id(1, "_server_receive_shot", aim_origin, aim_direction)


## Обновляем ammo_mode у текущего оружия при изменении серверной настройки.
func _on_ammo_mode_changed(mode: int) -> void:
	if current_weapon != null:
		current_weapon.ammo_mode = mode


# ── RPC ───────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _server_receive_shot(aim_origin: Vector3, aim_direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_player.remote_player_id or owner_player.is_dead or current_weapon == null:
		return
	if not current_weapon.server_consume_shot():
		_sync_weapon_ammo(sender_id)
		return

	var server_origin    := _get_server_shot_origin()
	var server_direction := _get_server_shot_direction()
	if server_direction == Vector3.ZERO:
		return

	# Отклонение направления свыше ~25° — отбрасываем
	if aim_direction.normalized().dot(server_direction) < _MAX_AIM_DOT:
		return
	# Позиция камеры клиента расходится с серверной более чем на 3 м — отбрасываем
	if aim_origin.distance_to(server_origin) > 3.0:
		return

	var params := PhysicsRayQueryParameters3D.new()
	params.from           = server_origin
	params.to             = server_origin + server_direction * current_weapon.data.range
	params.collision_mask = 3
	params.exclude        = [owner_player]

	var result    := owner_player.get_world_3d().direct_space_state.intersect_ray(params)
	var hit_point := params.to
	var hit_player: OnlinePlayer = null

	if result:
		hit_point = result.position
		if result.collider is OnlinePlayer:
			hit_player = result.collider
			hit_player.health_component.take_damage(current_weapon.data.damage, owner_player)

	rpc("_broadcast_shot", hit_point, hit_player != null, sender_id)


func _get_server_shot_origin() -> Vector3:
	if owner_player.camera:
		return owner_player.camera.global_transform.origin
	return owner_player.global_transform.origin + Vector3.UP * 1.5


func _get_server_shot_direction() -> Vector3:
	var forward := -owner_player.global_transform.basis.z
	var right   := owner_player.global_transform.basis.x.normalized()
	# aim_angle — угол наклона камеры; множитель 1.5 компенсирует рассинхрон
	# между поворотом тела и головы в режиме 3-го лица
	var pitch := owner_player.aim_component.aim_angle * 1.5
	return forward.rotated(right, pitch).normalized()


@rpc("any_peer", "reliable")
func _server_request_reload() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_player.remote_player_id or owner_player.is_dead or current_weapon == null:
		return
	if current_weapon.server_request_reload():
		var duration := current_weapon.data.reload_time if current_weapon.data else 0.0
		rpc("_broadcast_reload_anim", sender_id, duration)


@rpc("any_peer", "reliable")
func _broadcast_reload_anim(shooter_id: int, reload_duration: float) -> void:
	# Владелец уже проигрывает анимацию локально (client prediction).
	# Сервер без графики. Значит — только для других клиентов (proxy).
	if multiplayer.get_unique_id() != shooter_id and not multiplayer.is_server():
		if owner_player.animation:
			owner_player.animation.set_reloading(true, reload_duration)


@rpc("any_peer", "reliable", "call_local")
func _broadcast_shot(hit_point: Vector3, hit_success: bool, shooter_id: int) -> void:
	if current_weapon != null:
		current_weapon.on_broadcast_shot(hit_point, hit_success, shooter_id)


@rpc("any_peer", "reliable", "call_local")
func _client_sync_ammo(in_mag: int, in_reserve: int, reloading: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1 or current_weapon == null:
		return
	current_weapon.apply_ammo_state(in_mag, in_reserve, reloading)


# ── Приватное ─────────────────────────────────────────────────────────────

func _get_weapon_parent_node() -> Node3D:
	if weapon_mount_arms and is_multiplayer_authority():
		return weapon_mount_arms
	if weapon_mount:
		return weapon_mount
	return owner_player


func _set_weapon(data: WeaponData, world_mag: int = -1, world_reserve: int = -1, from_world_pickup: bool = false) -> void:
	clear_current_weapon()
	var instance := data.weapon_scene.instantiate() as Weapon
	if instance == null:
		push_error("WeaponHolder: weapon_scene is not a Weapon node")
		return
	# Задаём зависимости до add_child, чтобы _ready() видел их сразу
	instance.data         = data
	instance.owner_player = owner_player
	instance.ammo_mode    = ServerConfig.sv_ammo_mode
	_get_weapon_parent_node().add_child(instance)
	instance.shot_requested.connect(_on_shot_requested)
	if multiplayer.is_server():
		instance.ammo_changed.connect(func(_mag, _reserve): _sync_weapon_ammo(owner_player.remote_player_id))
		instance.reload_state_changed.connect(func(_state): _sync_weapon_ammo(owner_player.remote_player_id))
	if from_world_pickup:
		instance.apply_world_pickup_ammo(world_mag, world_reserve)
	current_weapon = instance
	weapon_changed.emit(current_weapon)


func _sync_weapon_ammo(peer_id: int) -> void:
	if not multiplayer.is_server() or current_weapon == null:
		return
	rpc_id(peer_id, "_client_sync_ammo",
		current_weapon.ammo_in_mag,
		current_weapon.ammo_reserve,
		current_weapon.is_reloading)
