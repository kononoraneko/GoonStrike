class_name Weapon extends Node3D

## Базовый класс оружия. Конкретные оружия (Rifle, Pistol) наследуют его.
## Weapon не знает про сеть — он только выполняет стрельбу и визуалы.
## Всю сетевую логику делегирует владельцу через сигналы.

signal shot_requested(aim_origin: Vector3, aim_direction: Vector3)
signal ammo_changed(current_in_mag: int, current_reserve: int)
signal reload_state_changed(is_reloading: bool)

@export var data: WeaponData

@onready var spread: SpreadComponent = $SpreadComponent
@onready var muzzle: Marker3D = $Muzzle

var can_shoot := true
var owner_player: OnlinePlayer
var ammo_in_mag: int = 0
var ammo_reserve: int = 0
var is_reloading: bool = false
var _next_server_shot_time_msec: int = 0

func _ready() -> void:
	var node := get_parent()
	while node != null:
		if node is OnlinePlayer:
			owner_player = node
			break
		node = node.get_parent()

	assert(owner_player != null, "Weapon must be placed inside an OnlinePlayer subtree")
	_init_ammo_state()


## Вызывается клиентом при нажатии кнопки стрельбы.
## Выполняет локальный визуал и отправляет сигнал для RPC.
func shoot(aim_ray: Dictionary) -> bool:
	if not _can_shoot_local():
		return false

	can_shoot = false
	get_tree().create_timer(data.fire_rate).timeout.connect(func(): can_shoot = true)
	if _should_predict_ammo():
		ammo_in_mag -= 1
		ammo_changed.emit(ammo_in_mag, ammo_reserve)
	
	var aim_origin: Vector3 = aim_ray["origin"]
	var aim_direction: Vector3 = aim_ray["direction"]
	
	var spread_node: SpreadComponent = get_node_or_null("SpreadComponent")
	if spread_node:
		var mv: MovementComponent = owner_player.movement
		aim_direction = spread_node.apply(aim_direction, mv.input_dir != Vector2.ZERO, not owner_player.is_on_floor())
		spread_node.on_shot_fired()
	
	var local_hit_point := aim_origin + aim_direction * data.range
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = aim_origin
	params.to = local_hit_point
	params.exclude = [owner_player] # Игнорируем самого себя (важно для 3-го лица!)
	params.collision_mask = 3 # Ваша маска геометрии и игроков
	
	var result := space_state.intersect_ray(params)
	if result:
		local_hit_point = result.position
	
	var muzzle_pos := get_global_muzzle_position()
	play_effects(muzzle_pos)
	show_tracer(muzzle_pos, local_hit_point)

	shot_requested.emit(aim_origin, aim_direction)
	return true


## Вызывается у всех клиентов через broadcast (из WeaponHolder / NetworkComponent).
func on_broadcast_shot(hit_point: Vector3, hit_success: bool, shooter_id: int) -> void:
	if multiplayer.get_unique_id() != shooter_id:
		var muzzle_pos := get_global_muzzle_position()
		play_effects(muzzle_pos)
		show_tracer(muzzle_pos, hit_point)
		owner_player.animation.play_shoot()
	if hit_success:
		show_hit_effect(hit_point)


func get_global_muzzle_position() -> Vector3:
	if muzzle:
		return muzzle.global_position
	return global_position


func play_effects(muzzle_pos: Vector3) -> void:
	if data == null or data.muzzle_flash_scene == null:
		return
	var flash := data.muzzle_flash_scene.instantiate()
	get_tree().root.add_child(flash)
	flash.global_position = muzzle_pos
	get_tree().create_timer(0.1).timeout.connect(flash.queue_free)


func show_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	material.emission_enabled = true
	material.emission = Color.ORANGE
	material.emission_energy_multiplier = 5.0

	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = material
	get_tree().root.add_child(line)

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	get_tree().create_timer(0.1).timeout.connect(line.queue_free)


func show_hit_effect(pos: Vector3) -> void:
	if data == null or data.hit_scene == null:
		return
	var hit_instance := data.hit_scene.instantiate()
	get_tree().root.add_child(hit_instance)
	hit_instance.global_position = pos
	get_tree().create_timer(0.1).timeout.connect(hit_instance.queue_free)


func request_reload_local() -> bool:
	if not _can_reload():
		return false
	is_reloading = true
	reload_state_changed.emit(true)
	if _should_predict_ammo():
		get_tree().create_timer(data.reload_time).timeout.connect(_finish_reload_local)
	return true


func apply_ammo_state(new_mag: int, new_reserve: int, reloading: bool) -> void:
	ammo_in_mag = max(new_mag, 0)
	ammo_reserve = max(new_reserve, 0)
	is_reloading = reloading
	ammo_changed.emit(ammo_in_mag, ammo_reserve)
	reload_state_changed.emit(is_reloading)


func server_consume_shot() -> bool:
	if data == null:
		return false
	if is_reloading:
		return false
	if ammo_in_mag <= 0:
		server_request_reload()
		return false
	var now := Time.get_ticks_msec()
	if now < _next_server_shot_time_msec:
		return false
	_next_server_shot_time_msec = now + int(data.fire_rate * 1000.0)
	ammo_in_mag -= 1
	ammo_changed.emit(ammo_in_mag, ammo_reserve)
	return true


func server_request_reload() -> bool:
	if not _can_reload():
		return false
	is_reloading = true
	reload_state_changed.emit(true)
	get_tree().create_timer(data.reload_time).timeout.connect(_finish_reload_local)
	return true


func _init_ammo_state() -> void:
	if data == null:
		return
	ammo_in_mag = max(data.magazine_size, 1)
	ammo_reserve = max(data.reserve_ammo, 0)
	ammo_changed.emit(ammo_in_mag, ammo_reserve)


func _can_shoot_local() -> bool:
	if data == null:
		return false
	if is_reloading or not can_shoot:
		return false
	return ammo_in_mag > 0


func _can_reload() -> bool:
	if data == null:
		return false
	if is_reloading:
		return false
	if ammo_in_mag >= max(data.magazine_size, 1):
		return false
	return ammo_reserve > 0


func _finish_reload_local() -> void:
	if data == null:
		is_reloading = false
		reload_state_changed.emit(false)
		return
	var max_mag : int = max(data.magazine_size, 1)
	var needed := max_mag - ammo_in_mag
	var loaded : int = min(needed, ammo_reserve)
	ammo_in_mag += loaded
	ammo_reserve -= loaded
	is_reloading = false
	ammo_changed.emit(ammo_in_mag, ammo_reserve)
	reload_state_changed.emit(false)


func _should_predict_ammo() -> bool:
	return multiplayer.is_server() or not multiplayer.has_multiplayer_peer()
