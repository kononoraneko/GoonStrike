class_name Weapon extends Node3D

## Базовый класс оружия. Конкретные оружия (Rifle, Pistol) наследуют его.
## Weapon не знает про сеть — он только выполняет стрельбу и визуалы.
## Всю сетевую логику делегирует владельцу через сигналы.

signal shot_requested(aim_origin: Vector3, aim_direction: Vector3)

@export var data: WeaponData

@onready var spread: SpreadComponent = $SpreadComponent
@onready var muzzle: Marker3D = $Muzzle

var can_shoot := true
var owner_player: OnlinePlayer

func _ready() -> void:
	var node := get_parent()
	while node != null:
		if node is OnlinePlayer:
			owner_player = node
			break
		node = node.get_parent()

	assert(owner_player != null, "Weapon must be placed inside an OnlinePlayer subtree")


## Вызывается клиентом при нажатии кнопки стрельбы.
## Выполняет локальный визуал и отправляет сигнал для RPC.
func shoot(aim_ray: Dictionary) -> void:
	if not can_shoot or data == null:
		return
	can_shoot = false
	get_tree().create_timer(data.fire_rate).timeout.connect(func(): can_shoot = true)
	
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

	print("cam pos ",owner_player.camera.global_position)
	print("origin ", aim_origin)
	print("dir ", aim_direction)
	print("muzzle ", muzzle_pos)
	print("local hit ", local_hit_point)

	shot_requested.emit(aim_origin, aim_direction)


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
