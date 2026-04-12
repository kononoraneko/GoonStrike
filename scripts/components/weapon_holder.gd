class_name WeaponHolder extends Node

## Отвечает за: текущее оружие, подбор, выброс, смену.
## Оружия могут не быть вовсе — current_weapon == null.
## RPC методы репликируют состояние слота на все клиенты.

signal weapon_changed(new_weapon: Weapon)

@export var weapon_mount: Node3D   # точка крепления оружия (например $model/hand_R)
@export var weapon_mount_arms: Node3D   # точка крепления оружия (например $model/hand_R)

var current_weapon: Weapon = null
var owner_player: OnlinePlayer

func _ready() -> void:
	_ensure_owner_player()
	if not multiplayer.is_server():
		rpc_id(1, "_request_weapon_sync")


func _ensure_owner_player() -> void:
	if owner_player == null:
		owner_player = get_parent() as OnlinePlayer
	assert(owner_player != null, "WeaponHolder must be child of OnlinePlayer")


## Подбор оружия — вызывается сервером через RPC на всех клиентах.
@rpc("any_peer", "reliable", "call_local")
func equip_from_pickup(_pickup_path: NodePath, data_path: String) -> void:
	var data := load(data_path) as WeaponData
	if data == null or data.weapon_scene == null:
		push_error("WeaponHolder: invalid WeaponData at " + data_path)
		return
	_set_weapon(data)


## Сброс оружия (выбросить или умереть).
func drop_weapon() -> void:
	if current_weapon == null:
		return
	current_weapon.queue_free()
	current_weapon = null
	weapon_changed.emit(null)


## Стрельба — делегируется текущему оружию.
func try_shoot(aim_ray: Dictionary) -> void:
	_ensure_owner_player()
	if owner_player.is_dead:
		return
	if current_weapon == null:
		return
	#print("try shoot")
	current_weapon.shoot(aim_ray)


## Оружие сообщает о выстреле через сигнал — WeaponHolder отправляет на сервер.
func _on_shot_requested(aim_origin: Vector3, aim_direction: Vector3) -> void:
	_ensure_owner_player()
	if owner_player.is_multiplayer_authority():
		rpc_id(1, "_server_receive_shot", aim_origin, aim_direction)


@rpc("any_peer", "reliable")
func _server_receive_shot(aim_origin: Vector3, aim_direction: Vector3) -> void:
	_ensure_owner_player()
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != owner_player.remote_player_id:
		return
	if owner_player.is_dead:
		return
	if current_weapon == null:
		return

	var server_origin := _get_server_shot_origin()
	var server_direction := _get_server_shot_direction()
	if server_direction == Vector3.ZERO:
		return

	if aim_direction.normalized().dot(server_direction) < 0.35:
		return
	if aim_origin.distance_to(server_origin) > 3.0:
		return

	var world := owner_player.get_world_3d()
	var params := PhysicsRayQueryParameters3D.new()
	params.from = server_origin
	params.to = server_origin + server_direction * current_weapon.data.range
	params.collision_mask = 3
	params.exclude = [owner_player]

	var result := world.direct_space_state.intersect_ray(params)
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
	var right := owner_player.global_transform.basis.x.normalized()
	var pitch := owner_player.aim_component.aim_angle * 1.5
	return forward.rotated(right, pitch).normalized()


@rpc("any_peer", "reliable")
func _request_weapon_sync() -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if requester_id <= 0:
		return
	if current_weapon == null or current_weapon.data == null:
		return
	var data_path := current_weapon.data.resource_path
	if data_path.is_empty():
		return
	rpc_id(requester_id, "equip_from_pickup", NodePath(), data_path)


@rpc("any_peer", "reliable", "call_local")
func _broadcast_shot(hit_point: Vector3, hit_success: bool, shooter_id: int) -> void:
	if current_weapon != null:
		current_weapon.on_broadcast_shot(hit_point, hit_success, shooter_id)


# ── приватные ──────────────────────────────────────────────────────────────

func _set_weapon(data: WeaponData) -> void:
	_ensure_owner_player()
	drop_weapon()
	var instance := data.weapon_scene.instantiate() as Weapon
	if instance == null:
		push_error("WeaponHolder: weapon_scene is not a Weapon node")
		return
	instance.data = data
	(weapon_mount_arms if weapon_mount_arms and is_multiplayer_authority() else weapon_mount if weapon_mount else owner_player).add_child(instance)
	instance.shot_requested.connect(_on_shot_requested)
	current_weapon = instance
	weapon_changed.emit(current_weapon)
