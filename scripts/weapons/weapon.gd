class_name Weapon extends Node3D

## Базовый класс оружия. Конкретные оружия (Rifle, Pistol) наследуют его.
## Weapon не знает про сеть и синглтоны — он только выполняет стрельбу и визуалы.
## Всю сетевую логику делегирует владельцу через сигналы.

## base_direction — до разброса (прицел); spread_direction — после SpreadComponent (хитскан).
signal shot_requested(aim_origin: Vector3, base_direction: Vector3, spread_direction: Vector3)
signal ammo_changed(current_in_mag: int, current_reserve: int)
signal reload_state_changed(is_reloading: bool)

@export var data: WeaponData

@onready var spread: SpreadComponent = $SpreadComponent
@onready var muzzle: Marker3D        = $Muzzle

var can_shoot    := true
var owner_player: OnlinePlayer
var ammo_in_mag:  int  = 0
var ammo_reserve: int  = 0
var is_reloading: bool = false

## Режим патронов. Устанавливается из WeaponHolder при экипировке
## и обновляется через ServerConfig.ammo_mode_changed.
## 0 = обычный, 1 = бесконечный магазин, 2 = бесконечный резерв
var ammo_mode: int = 0

var _next_server_shot_time_msec: int = 0


func _ready() -> void:
	assert(owner_player != null, "Weapon: owner_player должен быть задан до add_child")
	# Инициализируем SpreadComponent данными текущего оружия
	if data and spread:
		spread.init(data.spread_pattern)
	_init_ammo_state()


func apply_skin(skin: Resource) -> void:
	if skin == null:
		return
	var override_material: Material = skin.material_override
	if override_material == null and skin.albedo_tint != Color.WHITE:
		var generated := StandardMaterial3D.new()
		generated.albedo_color = skin.albedo_tint
		override_material = generated
	if override_material == null:
		return
	_apply_material_recursive(self, override_material)


## Вызывается клиентом при нажатии кнопки стрельбы.
func shoot(aim_ray: Dictionary) -> bool:
	if not _can_shoot_local():
		return false

	can_shoot = false
	get_tree().create_timer(data.fire_rate).timeout.connect(func(): can_shoot = true)

	if _should_predict_ammo():
		ammo_in_mag -= 1
		ammo_changed.emit(ammo_in_mag, ammo_reserve)

	var aim_origin: Vector3    = aim_ray["origin"]
	var base_direction: Vector3 = aim_ray["direction"].normalized()
	var spread_direction: Vector3 = base_direction

	if spread:
		var mv: MovementComponent = owner_player.movement
		var spread_scale := 1.0
		if data and data.has_sniper_scope and owner_player.sniper_scope_stage > 0:
			var st := owner_player.sniper_scope_stage
			var tighter := 1.0 - 0.22 * float(st - 1)
			spread_scale = data.scope_spread_multiplier * maxf(tighter, 0.45)
		spread_direction = spread.apply(base_direction, mv.input_dir != Vector2.ZERO, not owner_player.is_on_floor(), spread_scale)
		# Хост (listen server): тот же узел оружия — bloom/pattern обновляет WeaponHolder._server_receive_shot,
		# иначе on_shot_fired вызовется дважды. Клиент и оффлайн — здесь.
		var host_skip := multiplayer.has_multiplayer_peer() and multiplayer.is_server() \
			and owner_player.is_multiplayer_authority()
		if not host_skip:
			spread.on_shot_fired()

	var local_hit_point := aim_origin + spread_direction * data.range
	var params           := PhysicsRayQueryParameters3D.new()
	params.from           = aim_origin
	params.to             = local_hit_point
	params.exclude        = [owner_player]
	params.collision_mask = 3

	var result := get_world_3d().direct_space_state.intersect_ray(params)
	if result:
		local_hit_point = result.position

	var muzzle_pos := get_global_muzzle_position()
	play_effects(muzzle_pos)
	show_tracer(muzzle_pos, local_hit_point)
	shot_requested.emit(aim_origin, base_direction, spread_direction)
	return true


## Вызывается у всех клиентов через broadcast (из WeaponHolder).
func on_broadcast_shot(hit_point: Vector3, hit_success: bool, shooter_id: int) -> void:
	if multiplayer.get_unique_id() != shooter_id:
		var muzzle_pos := get_global_muzzle_position()
		play_effects(muzzle_pos)
		show_tracer(muzzle_pos, hit_point)
		owner_player.animation.play_shoot()
	if hit_success:
		show_hit_effect(hit_point)


func get_global_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle else global_position


func play_effects(muzzle_pos: Vector3) -> void:
	if data == null or data.muzzle_flash_scene == null:
		return
	var flash := data.muzzle_flash_scene.instantiate()
	get_tree().root.add_child(flash)
	flash.global_position = muzzle_pos
	get_tree().create_timer(0.1).timeout.connect(flash.queue_free)


func show_tracer(from: Vector3, to: Vector3) -> void:
	TracerBeamVfx.spawn(get_tree().root, from, to, 0.09, Color(1.0, 0.52, 0.12, 1.0))


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
	ammo_in_mag  = max(new_mag, 0)
	ammo_reserve = max(new_reserve, 0)
	is_reloading = reloading
	ammo_changed.emit(ammo_in_mag, ammo_reserve)
	reload_state_changed.emit(is_reloading)


func apply_world_pickup_ammo(world_mag: int, world_reserve: int) -> void:
	apply_ammo_state(max(world_mag, 0), max(world_reserve, 0), false)


## Только для сервера. Проверяет тайминг и списывает патрон.
func server_consume_shot() -> bool:
	if data == null or is_reloading:
		return false
	if ammo_mode != 1 and ammo_in_mag <= 0:
		server_request_reload()
		return false
	var now := Time.get_ticks_msec()
	if now < _next_server_shot_time_msec:
		return false
	_next_server_shot_time_msec = now + int(data.fire_rate * 1000.0)
	if ammo_mode != 1:
		ammo_in_mag -= 1
		ammo_changed.emit(ammo_in_mag, ammo_reserve)
	return true


## Только для сервера.
func server_request_reload() -> bool:
	if not _can_reload():
		return false
	is_reloading = true
	reload_state_changed.emit(true)
	get_tree().create_timer(data.reload_time).timeout.connect(_finish_reload_local)
	return true


# ── Приватное ─────────────────────────────────────────────────────────────

func _init_ammo_state() -> void:
	if data == null:
		return
	ammo_in_mag  = max(data.magazine_size, 1)
	ammo_reserve = max(data.reserve_ammo, 0)
	ammo_changed.emit(ammo_in_mag, ammo_reserve)


func _can_shoot_local() -> bool:
	if data == null or is_reloading or not can_shoot:
		return false
	return ammo_mode == 1 or ammo_in_mag > 0


func _can_reload() -> bool:
	if data == null or is_reloading:
		return false
	if ammo_mode == 1:          # бесконечный магазин — перезарядка не нужна
		return false
	if ammo_in_mag >= max(data.magazine_size, 1):
		return false
	return ammo_mode == 2 or ammo_reserve > 0


func _finish_reload_local() -> void:
	if data == null:
		is_reloading = false
		reload_state_changed.emit(false)
		return
	var max_mag : int = max(data.magazine_size, 1)
	if ammo_mode == 2:
		ammo_in_mag = max_mag
	else:
		var needed : int = max_mag - ammo_in_mag
		var loaded : int = min(needed, ammo_reserve)
		ammo_in_mag  += loaded
		ammo_reserve -= loaded
	is_reloading = false
	ammo_changed.emit(ammo_in_mag, ammo_reserve)
	reload_state_changed.emit(false)


func _should_predict_ammo() -> bool:
	return multiplayer.is_server() or not multiplayer.has_multiplayer_peer()


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = material
	for child in node.get_children():
		_apply_material_recursive(child, material)
